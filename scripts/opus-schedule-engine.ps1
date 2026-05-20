<#
  opus-schedule-engine.ps1 - Motor de programacion OPUS (read-only / validacion).
  Modelo calibrado (EXP06): jornada inicia a HoraInicioLabores (08:00); dia completo = N horas
  contiguas (8 entre semana, 4 sabado a medias, 0 no laborable); el ultimo dia puede ser parcial.
  Reparte la cantidad proporcional a las horas trabajadas por dia.

  Uso:  .\opus-schedule-engine.ps1 -Database "<mdf>" -ValidarClaves K-1,D-01,RES-01,DEM
#>
param(
  [Parameter(Mandatory=$true)][string]$Database,
  [string[]]$ValidarClaves,
  [string]$Server = "(localdb)\OpusLocal"
)
$ErrorActionPreference = "Stop"
$bf = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
function New-Cn { $c = New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$Database;Integrated Security=SSPI"; $c.Open(); $c }
function Deser($bytes){ if(-not $bytes){return $null}; $ms=New-Object System.IO.MemoryStream (,[byte[]]$bytes); $o=$bf.Deserialize($ms); $ms.Dispose(); $o }
function Get-Blob($cn,$q){ $cmd=$cn.CreateCommand(); $cmd.CommandText=$q; $v=$cmd.ExecuteScalar(); if($v -is [byte[]]){$v}else{$null} }
function HorasDe($hs){ $h=0.0; if($hs){ foreach($t in $hs){ $h += ($t.Item2 - $t.Item1).TotalHours } }; $h }

$cn = New-Cn
# --- Calendario ---
$tpl=@{}; $cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT DiaDeSemana,HorariosDeTrabajo FROM UnidadDeTrabajo WHERE TipoUnidad='Dia'"
$rd=$cmd.ExecuteReader(); $rs=@(); while($rd.Read()){ $rs+=,@($rd.GetInt16(0),$(if($rd.IsDBNull(1)){$null}else{$rd.GetValue(1)})) }; $rd.Close()
foreach($r in $rs){ $tpl[[int]$r[0]]=HorasDe (Deser $r[1]) }
$exc=@{}; $cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT CONVERT(varchar(10),FechaInicio,120),HorariosDeTrabajo FROM UnidadDeTrabajo WHERE TipoUnidad='Rango'"
$rd=$cmd.ExecuteReader(); $rs=@(); while($rd.Read()){ $rs+=,@($rd.GetString(0),$(if($rd.IsDBNull(1)){$null}else{$rd.GetValue(1)})) }; $rd.Close()
foreach($r in $rs){ $exc[$r[0]]=HorasDe (Deser $r[1]) }
$horaIni = ([datetime]($cn.CreateCommand() | ForEach-Object { $_.CommandText="SELECT TOP 1 HoraInicioLabores FROM Calendario"; $_.ExecuteScalar() })).TimeOfDay
function HorasDia([datetime]$d){ $k=$d.ToString("yyyy-MM-dd"); if($exc.ContainsKey($k)){return [double]$exc[$k]}; return [double]$tpl[[int]$d.DayOfWeek] }

# --- Motor: acumula totalHoras desde startDT, dia a dia, con dia parcial ---
function Distribuir([datetime]$startDT,[double]$totalHoras,[double]$cant){
  $daily=@{}; $rem=$totalHoras; $day=$startDT.Date
  $offset=($startDT.TimeOfDay - $horaIni).TotalHours; if($offset -lt 0){$offset=0}
  $fin=$startDT; $first=$true
  while($rem -gt 1e-9){
    $cap=HorasDia $day
    $disp=$cap; if($first){ $disp=$cap-$offset; if($disp -lt 0){$disp=0} }
    if($disp -gt 0){
      $used=[math]::Min($disp,$rem)
      $daily[$day]=[math]::Round($cant*$used/$totalHoras,2)
      $startThis = if($first){$offset}else{0}
      $fin = $day.Add($horaIni).AddHours($startThis+$used)
      $rem-=$used
    }
    $first=$false; $day=$day.AddDays(1)
    if($day -gt $startDT.Date.AddDays(400)){break}
  }
  return @{ Daily=$daily; Fin=$fin }
}

foreach($clave in $ValidarClaves){
  $cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT TOP 1 CONVERT(varchar(19),FechaInicio,120),Esfuerzo,CantidadProgramada,CONVERT(varchar(19),FechaFin,120) FROM RenglonDePresupuesto WHERE ClaveDeRenglon='$clave' AND EstaProgramada=1"
  $rd=$cmd.ExecuteReader(); if(-not $rd.Read()){ $rd.Close(); Write-Host "(${clave}: no programado)"; continue }
  $fini=[datetime]::Parse($rd.GetString(0)); $esf=[double]$rd.GetValue(1); $cant=[double]$rd.GetValue(2); $ffinDB=[datetime]::Parse($rd.GetString(3)); $rd.Close()
  $res=Distribuir $fini $esf $cant
  $opus=Deser (Get-Blob $cn "SELECT CantidadesPorDia FROM RenglonDePresupuesto WHERE ClaveDeRenglon='$clave' AND EstaProgramada=1")
  $okFin = ([math]::Abs(($res.Fin - $ffinDB).TotalMinutes) -lt 1)
  Write-Host ""; Write-Host ("=== {0}: inicio {1:yyyy-MM-dd HH:mm}, Esfuerzo {2}h, cant {3} ===" -f $clave,$fini,$esf,$cant)
  Write-Host ("  FechaFin  calc={0:yyyy-MM-dd HH:mm:ss}  OPUS={1:yyyy-MM-dd HH:mm:ss}  {2}" -f $res.Fin,$ffinDB,$(if($okFin){'OK'}else{'X'}))
  $okAll=$okFin
  foreach($d in ($res.Daily.Keys | Sort-Object)){
    $o=$null; foreach($k in $opus.Keys){ if($k.Date -eq $d.Date){$o=[math]::Round([double]$opus[$k],2);break} }
    $c=$res.Daily[$d]; $m=([math]::Abs($c-$o) -lt 0.011); if(-not $m){$okAll=$false}
    Write-Host ("    {0:yyyy-MM-dd} calc={1,8} opus={2,8} {3}" -f $d,$c,$o,$(if($m){'OK'}else{'X'}))
  }
  Write-Host ("  => {0}" -f $(if($okAll){'EXACTO'}else{'DIFERENCIAS'})) -ForegroundColor $(if($okAll){'Green'}else{'Yellow'})
}
$cn.Close()
