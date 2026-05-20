<#
  opus-csa.ps1 - Programa el concepto CSA (Construccion/Supervision/Admin) distribuyendo su
  importe proporcional al COSTO de cada periodo del resto del programa (= 15% del costo periodico).
  Deriva la distribucion del costo diario (CantidadesPorDia x PU) de todos los renglones programados.
  Protocolo seguro (backup + transaccion).
#>
param(
  [Parameter(Mandatory=$true)][string]$Database,
  [int]$CsaId=1376257,
  [string]$Server="(localdb)\OpusLocal",
  [switch]$WhatIf
)
$ErrorActionPreference="Stop"
$bf=New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
function Cn($db){ $c=New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$db;Integrated Security=SSPI"; $c.Open(); $c }
function Deser($b){ if(-not $b){return $null}; $ms=New-Object System.IO.MemoryStream (,[byte[]]$b); $o=$bf.Deserialize($ms); $ms.Dispose(); $o }
function Ser($o){ $ms=New-Object System.IO.MemoryStream; $bf.Serialize($ms,$o); $r=$ms.ToArray(); $ms.Dispose(); ,$r }

$cn=Cn $Database
# costo por dia = sum( CantidadesPorDia[d] * PU ) sobre renglones programados (excepto CSA)
$cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT RenglonDePresupuestoId, PrecioUnitario, CantidadesPorDia FROM RenglonDePresupuesto WHERE EstaProgramada=1 AND RenglonDePresupuestoId<>$CsaId"
$rd=$cmd.ExecuteReader()
$costDay=New-Object 'System.Collections.Generic.Dictionary[datetime,decimal]'
while($rd.Read()){
  $pu=[decimal]$rd.GetValue(1); if($rd.IsDBNull(2)){continue}
  $d=Deser $rd.GetValue(2); if(-not $d){continue}
  foreach($k in $d.Keys){ $c=[decimal]$d[$k]*$pu; if($costDay.ContainsKey($k.Date)){$costDay[$k.Date]+=$c}else{$costDay[$k.Date]=$c} }
}
$rd.Close()
$total=[decimal]0; foreach($v in $costDay.Values){ $total+=$v }
if($total -le 0){ throw "Costo total 0 (no hay programados)" }

# CSA: cantidad por dia = fraccion del costo (suma=1)
$porDia=New-Object 'System.Collections.Generic.Dictionary[datetime,decimal]'
foreach($k in $costDay.Keys){ if($costDay[$k] -ne 0){ $porDia[$k]=$costDay[$k]/$total } }
function Agr($mode){ $dic=New-Object 'System.Collections.Generic.Dictionary[datetime,decimal]'
  foreach($k in $porDia.Keys){ $q=$porDia[$k]
    switch($mode){ 'sem'{$a=$k.AddDays(-[int]$k.DayOfWeek)} 'quin'{$a=New-Object datetime $k.Year,$k.Month,$(if($k.Day -le 15){1}else{16})} 'men'{$a=New-Object datetime $k.Year,$k.Month,1} }
    if($dic.ContainsKey($a)){$dic[$a]+=$q}else{$dic[$a]=$q} }; ,$dic }
$men=Agr 'men'; $sem=Agr 'sem'; $quin=Agr 'quin'

# datos CSA + span
$cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT Cantidad, PrecioUnitario FROM RenglonDePresupuesto WHERE RenglonDePresupuestoId=$CsaId"
$rd=$cmd.ExecuteReader(); $rd.Read(); $cant=[decimal]$rd.GetValue(0); $pu=[decimal]$rd.GetValue(1); $rd.Close()
$cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT MIN(FechaInicio), MAX(FechaFin) FROM RenglonDePresupuesto WHERE EstaProgramada=1 AND RenglonDePresupuestoId<>$CsaId"
$rd=$cmd.ExecuteReader(); $rd.Read(); $fini=[datetime]$rd.GetValue(0); $ffin=[datetime]$rd.GetValue(1); $rd.Close()
$diasCal=[int]($ffin.Date-$fini.Date).TotalDays+1; $diasTrab=$porDia.Count; $total_csa=$cant*$pu

Write-Host ("CSA: importe {0:N2} | span {1:yyyy-MM-dd} a {2:yyyy-MM-dd} | {3} dias con costo" -f $total_csa,$fini,$ffin,$diasTrab)
Write-Host "Distribucion mensual del CSA (= % del costo de obra de ese mes):"
foreach($k in ($men.Keys|Sort-Object)){ Write-Host ("  {0:yyyy-MM}  {1,6:P1}  -> $ {2:N0}" -f $k,$men[$k],($men[$k]*$total_csa)) }
$suma=0; foreach($v in $men.Values){$suma+=$v}; Write-Host ("  suma fracciones = {0:N4}" -f $suma)
if($WhatIf){ Write-Host "[WhatIf] no se escribio." -ForegroundColor Cyan; $cn.Close(); return }
$cn.Close()

# escritura
$m=Cn "master"; $c=$m.CreateCommand(); $c.CommandText="SELECT session_id FROM sys.dm_exec_sessions WHERE database_id=DB_ID('$Database') AND session_id<>@@SPID"
$rd=$c.ExecuteReader(); $s=@(); while($rd.Read()){$s+=$rd.GetInt16(0)}; $rd.Close()
foreach($x in $s){ try{ $cc=$m.CreateCommand(); $cc.CommandText="KILL $x"; [void]$cc.ExecuteNonQuery() }catch{} }
$ts=Get-Date -Format "yyyyMMdd_HHmmss"; $bak=Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "backups") "SANDBOX_PRE_CSA_$ts.bak"
$c=$m.CreateCommand(); $c.CommandText="BACKUP DATABASE [$Database] TO DISK=N'$bak' WITH FORMAT,INIT,NAME='pre-csa'"; $c.CommandTimeout=120; [void]$c.ExecuteNonQuery(); $m.Close()
Write-Host "Backup: $bak"

$cn=Cn $Database; $tx=$cn.BeginTransaction()
try{
  $c=$cn.CreateCommand(); $c.Transaction=$tx
  $c.CommandText=@"
UPDATE RenglonDePresupuesto SET
 EstaProgramada=1, ProgramaSegunRendimiento=0, CantidadesDistribuidas=1, DistribucionesEditadas=1,
 CantidadProgramada=@cant, Remanente=0, TotalProgramado=@total, UEjecutoras=1,
 DiasCalendario=@dcal, DiasTrabajables=@dtrab, Esfuerzo=@esf,
 FechaInicio=@fini, FechaInicioOriginal=@fini, FechaFin=@ffin,
 CantidadesPorDia=@cxd, DistribucionSemanal=@sem, DistribucionQuincenal=@quin, DistribucionMensual=@men
WHERE RenglonDePresupuestoId=@id
"@
  [void]$c.Parameters.Add("@cant",[Data.SqlDbType]::Decimal); $c.Parameters["@cant"].Precision=28; $c.Parameters["@cant"].Scale=6; $c.Parameters["@cant"].Value=$cant
  [void]$c.Parameters.Add("@total",[Data.SqlDbType]::Decimal); $c.Parameters["@total"].Precision=28; $c.Parameters["@total"].Scale=6; $c.Parameters["@total"].Value=[math]::Round($total_csa,6)
  [void]$c.Parameters.Add("@dcal",[Data.SqlDbType]::Decimal); $c.Parameters["@dcal"].Value=[decimal]$diasCal
  [void]$c.Parameters.Add("@dtrab",[Data.SqlDbType]::Decimal); $c.Parameters["@dtrab"].Value=[decimal]$diasTrab
  [void]$c.Parameters.Add("@esf",[Data.SqlDbType]::Float); $c.Parameters["@esf"].Value=[double]($diasTrab*8)
  [void]$c.Parameters.Add("@fini",[Data.SqlDbType]::DateTime); $c.Parameters["@fini"].Value=$fini
  [void]$c.Parameters.Add("@ffin",[Data.SqlDbType]::DateTime); $c.Parameters["@ffin"].Value=$ffin
  [void]$c.Parameters.Add("@cxd",[Data.SqlDbType]::VarBinary); $c.Parameters["@cxd"].Value=(Ser $porDia)
  [void]$c.Parameters.Add("@sem",[Data.SqlDbType]::VarBinary); $c.Parameters["@sem"].Value=(Ser $sem)
  [void]$c.Parameters.Add("@quin",[Data.SqlDbType]::VarBinary); $c.Parameters["@quin"].Value=(Ser $quin)
  [void]$c.Parameters.Add("@men",[Data.SqlDbType]::VarBinary); $c.Parameters["@men"].Value=(Ser $men)
  [void]$c.Parameters.Add("@id",[Data.SqlDbType]::Int); $c.Parameters["@id"].Value=$CsaId
  if($c.ExecuteNonQuery() -ne 1){ throw "UPDATE CSA != 1" }
  $tx.Commit(); Write-Host "COMMIT OK (CSA programado)." -ForegroundColor Green
}catch{ $tx.Rollback(); Write-Host "ROLLBACK: $($_.Exception.Message)" -ForegroundColor Red; throw }
finally{ $cn.Close() }
