<#
  opus-calendario.ps1 - Extiende el calendario de trabajo (UnidadDeTrabajo, tipo Rango):
  sabados a medias (08-12h) y festivos LFT como no laborables, en un horizonte.
  Reusa los blobs HorariosDeTrabajo ya creados por OPUS (medio sabado / vacio). Protocolo seguro.

  Uso:
    .\opus-calendario.ps1 -Database "<mdf>" -Desde 2026-05-25 -Hasta 2026-12-31 -WhatIf
    .\opus-calendario.ps1 -Database "<mdf>" -Desde 2026-05-25 -Hasta 2026-12-31
#>
param(
  [Parameter(Mandatory=$true)][string]$Database,
  [string]$Desde="2026-05-25",
  [string]$Hasta="2026-12-31",
  [string[]]$Festivos=@("2026-09-16","2026-11-16","2026-12-25"),
  [int]$IdMedioSabado=2195456,   # Rango con 08-12h (en PlantillaDb)
  [int]$IdVacio=2195461,         # Rango vacio / no laborable (en PlantillaDb)
  [string]$PlantillaDb="",        # BD de donde leer los blobs plantilla (default = Database)
  [string]$Server="(localdb)\OpusLocal",
  [switch]$WhatIf
)
$ErrorActionPreference="Stop"
function Cn($db){ $c=New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$db;Integrated Security=SSPI"; $c.Open(); $c }

$cn=Cn $Database
function Scalar($q){ $c=$cn.CreateCommand(); $c.CommandText=$q; $c.ExecuteScalar() }
# blobs plantilla: leer de PlantillaDb si se indica (p.ej. replicar calendario de la copia a la 110)
if($PlantillaDb -and $PlantillaDb -ne $Database){
  $cpl=Cn $PlantillaDb; $cm=$cpl.CreateCommand()
  $cm.CommandText="SELECT HorariosDeTrabajo FROM UnidadDeTrabajo WHERE UnidadDeTrabajoId=$IdMedioSabado"; $blobHalf=[byte[]]$cm.ExecuteScalar()
  $cm.CommandText="SELECT HorariosDeTrabajo FROM UnidadDeTrabajo WHERE UnidadDeTrabajoId=$IdVacio"; $blobEmpty=[byte[]]$cm.ExecuteScalar()
  $cpl.Close()
} else {
  $blobHalf=[byte[]](Scalar "SELECT HorariosDeTrabajo FROM UnidadDeTrabajo WHERE UnidadDeTrabajoId=$IdMedioSabado")
  $blobEmpty=[byte[]](Scalar "SELECT HorariosDeTrabajo FROM UnidadDeTrabajo WHERE UnidadDeTrabajoId=$IdVacio")
}
$calId=[int](Scalar "SELECT TOP 1 CalendarioId FROM Calendario")
# fechas Rango ya existentes
$existing=@{}; $c=$cn.CreateCommand(); $c.CommandText="SELECT CONVERT(varchar(10),FechaInicio,120) FROM UnidadDeTrabajo WHERE TipoUnidad='Rango' AND FechaInicio IS NOT NULL"
$rd=$c.ExecuteReader(); while($rd.Read()){ $existing[$rd.GetString(0)]=$true }; $rd.Close()

$d0=[datetime]::Parse($Desde); $d1=[datetime]::Parse($Hasta)
$targets=@()  # @{Date; Blob; Tipo}
for($d=$d0; $d -le $d1; $d=$d.AddDays(1)){
  $k=$d.ToString("yyyy-MM-dd")
  if($existing.ContainsKey($k)){ continue }
  if($Festivos -contains $k){ $targets+=@{Date=$d;Blob=$blobEmpty;Tipo="FESTIVO"} }
  elseif($d.DayOfWeek -eq [DayOfWeek]::Saturday){ $targets+=@{Date=$d;Blob=$blobHalf;Tipo="SAB-1/2"} }
}
Write-Host "Calendario: $($targets.Count) excepciones a insertar ($Desde a $Hasta)"
$targets | ForEach-Object { Write-Host ("  {0:yyyy-MM-dd ddd}  {1}" -f $_.Date,$_.Tipo) }
if($WhatIf){ Write-Host "[WhatIf] no se escribio." -ForegroundColor Cyan; $cn.Close(); return }
if($targets.Count -eq 0){ Write-Host "Nada que insertar."; $cn.Close(); return }
$cn.Close()

# kill sesiones + backup
$m=Cn "master"; $c=$m.CreateCommand(); $c.CommandText="SELECT session_id FROM sys.dm_exec_sessions WHERE database_id=DB_ID('$Database') AND session_id<>@@SPID"
$rd=$c.ExecuteReader(); $s=@(); while($rd.Read()){$s+=$rd.GetInt16(0)}; $rd.Close()
foreach($x in $s){ try{ $cc=$m.CreateCommand(); $cc.CommandText="KILL $x"; [void]$cc.ExecuteNonQuery() }catch{} }
$ts=Get-Date -Format "yyyyMMdd_HHmmss"
$bak=Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "backups") "SANDBOX_PRE_CALENDARIO_$ts.bak"
$c=$m.CreateCommand(); $c.CommandText="BACKUP DATABASE [$Database] TO DISK=N'$bak' WITH FORMAT,INIT,NAME='pre-cal'"; $c.CommandTimeout=120; [void]$c.ExecuteNonQuery(); $m.Close()
Write-Host "Backup: $bak"

$cn=Cn $Database; $tx=$cn.BeginTransaction()
try{
  $c=$cn.CreateCommand(); $c.Transaction=$tx; $c.CommandText="SELECT ISNULL(MAX(UnidadDeTrabajoId),0) FROM UnidadDeTrabajo"; $id=[int]$c.ExecuteScalar()
  foreach($t in $targets){
    $id++
    $c=$cn.CreateCommand(); $c.Transaction=$tx
    $c.CommandText="INSERT INTO UnidadDeTrabajo (UnidadDeTrabajoId,TipoUnidad,CalendarioId,HorariosDeTrabajo,FechaInicio,FechaFin,DiaDeSemana) VALUES (@id,'Rango',@cal,@b,@f,@f,NULL)"
    [void]$c.Parameters.Add("@id",[Data.SqlDbType]::Int); $c.Parameters["@id"].Value=$id
    [void]$c.Parameters.Add("@cal",[Data.SqlDbType]::Int); $c.Parameters["@cal"].Value=$calId
    [void]$c.Parameters.Add("@b",[Data.SqlDbType]::VarBinary); $c.Parameters["@b"].Value=$t.Blob
    [void]$c.Parameters.Add("@f",[Data.SqlDbType]::DateTime); $c.Parameters["@f"].Value=$t.Date
    if($c.ExecuteNonQuery() -ne 1){ throw "INSERT != 1" }
  }
  $tx.Commit(); Write-Host "COMMIT OK. Insertadas: $($targets.Count)" -ForegroundColor Green
}catch{ $tx.Rollback(); Write-Host "ROLLBACK: $($_.Exception.Message)" -ForegroundColor Red; throw }
finally{ $cn.Close() }
