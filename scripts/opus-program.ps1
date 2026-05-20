<#
  opus-program.ps1 - GENERADOR de programa de obra (modos DURACION y RENDIMIENTO).
  Escribe distribuciones + fechas + esfuerzo y sincroniza el encabezado. Protocolo seguro.
  Motor calibrado EXP06 (acumulacion de horas con dia parcial). Opera por RenglonDePresupuestoId.

  Input CSV (UTF-8). Columnas: Id,FechaInicio,Modo,DiasCalendario,UEjecutoras
     Modo = DUR  -> usa DiasCalendario (UEjecutoras se ignora, =1)
     Modo = REND -> usa UEjecutoras (DiasCalendario se calcula; requiere componente con DefineRendimientoActividad=1)

  Uso:
    .\opus-program.ps1 -Database "<mdf>" -InputCsv ".\programa_input.csv" -WhatIf
    .\opus-program.ps1 -Database "<mdf>" -InputCsv ".\programa_input.csv"
#>
param(
  [Parameter(Mandatory=$true)][string]$Database,
  [Parameter(Mandatory=$true)][string]$InputCsv,
  [string]$Server = "(localdb)\OpusLocal",
  [switch]$WhatIf
)
$ErrorActionPreference = "Stop"
$bf = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
function Cn($db){ $c=New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$db;Integrated Security=SSPI"; $c.Open(); $c }
function Deser($b){ if(-not $b){return $null}; $ms=New-Object System.IO.MemoryStream (,[byte[]]$b); $o=$bf.Deserialize($ms); $ms.Dispose(); $o }
function Ser($obj){ $ms=New-Object System.IO.MemoryStream; $bf.Serialize($ms,$obj); $r=$ms.ToArray(); $ms.Dispose(); ,$r }
function HorasDe($hs){ $h=0.0; if($hs){ foreach($t in $hs){ $h+=($t.Item2-$t.Item1).TotalHours } }; $h }

# ---- calendario ----
$cn = Cn $Database
$tpl=@{}; $cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT DiaDeSemana,HorariosDeTrabajo FROM UnidadDeTrabajo WHERE TipoUnidad='Dia'"
$rd=$cmd.ExecuteReader(); $t=@(); while($rd.Read()){ $t+=,@($rd.GetInt16(0),$(if($rd.IsDBNull(1)){$null}else{$rd.GetValue(1)})) }; $rd.Close()
foreach($r in $t){ $tpl[[int]$r[0]]=HorasDe (Deser $r[1]) }
$exc=@{}; $cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT CONVERT(varchar(10),FechaInicio,120),HorariosDeTrabajo FROM UnidadDeTrabajo WHERE TipoUnidad='Rango'"
$rd=$cmd.ExecuteReader(); $t=@(); while($rd.Read()){ $t+=,@($rd.GetString(0),$(if($rd.IsDBNull(1)){$null}else{$rd.GetValue(1)})) }; $rd.Close()
foreach($r in $t){ $exc[$r[0]]=HorasDe (Deser $r[1]) }
$cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT TOP 1 HoraInicioLabores FROM Calendario"; $horaIni=([datetime]$cmd.ExecuteScalar()).TimeOfDay
$cn.Close()
function HorasDia([datetime]$d){ $k=$d.ToString("yyyy-MM-dd"); if($exc.ContainsKey($k)){return [double]$exc[$k]}; return [double]$tpl[[int]$d.DayOfWeek] }

# avanza $h horas laborables desde $dt (sobre el calendario). $h=0 -> mismo $dt.
function AddWorkHours([datetime]$dt,[double]$h){
  if($h -le 1e-9){ return $dt }
  $cur=$dt; $rem=$h
  while($true){
    $dh=HorasDia $cur.Date
    $off=[math]::Max(0.0, ($cur.TimeOfDay - $horaIni).TotalHours)
    $avail=$dh-$off; if($avail -lt 0){$avail=0}
    if($avail -ge $rem -and $avail -gt 0){ return $cur.Date.Add($horaIni).AddHours($off+$rem) }
    $rem-=$avail
    $cur=$cur.Date.AddDays(1).Add($horaIni)
    if($cur -gt $dt.AddDays(3000)){ throw "AddWorkHours overflow" }
  }
}

# normaliza un inicio al siguiente instante laborable (si cae en cierre de jornada o dia no laborable)
function NormStart([datetime]$dt){
  $cur=$dt
  while($true){
    $dh=HorasDia $cur.Date; $off=($cur.TimeOfDay - $horaIni).TotalHours
    if($dh -gt 0 -and $off -lt ($dh-1e-9)){ if($off -lt 0){ return $cur.Date.Add($horaIni) } else { return $cur } }
    $cur=$cur.Date.AddDays(1).Add($horaIni)
    if($cur -gt $dt.AddDays(3000)){ return $cur }
  }
}

# ---- motor: acumula totalHoras desde el inicio (dia parcial al inicio y/o al final) ----
function Distribuir($fini,[double]$totalHoras,[decimal]$cant){
  if($totalHoras -le 0){ throw "totalHoras <= 0" }
  $porDia = New-Object 'System.Collections.Generic.Dictionary[datetime,decimal]'
  $rem=$totalHoras; $day=$fini.Date; $finDay=$day; $finEnd=0.0; $first=$true
  while($rem -gt 1e-9){
    $h=HorasDia $day
    $off= if($first){ [math]::Max(0.0, ($fini.TimeOfDay - $horaIni).TotalHours) } else { 0.0 }
    $avail=$h-$off; if($avail -lt 0){$avail=0}
    if($avail -gt 0){
      $used=[math]::Min($avail,$rem)
      $porDia[$day]=[decimal]$cant*[decimal]$used/[decimal]$totalHoras
      $finDay=$day; $finEnd=$off+$used; $rem-=$used
    } elseif ($day -ge $fini.Date) {
      $porDia[$day]=[decimal]0   # dia no laborable dentro del lapso: clave con 0
    }
    $first=$false; $day=$day.AddDays(1)
    if($day -gt $fini.Date.AddDays(3000)){ break }
  }
  $ffin=$finDay.Add($horaIni).AddHours($finEnd)
  foreach($k in @($porDia.Keys)){ if($k -gt $finDay -and $porDia[$k] -eq 0){ [void]$porDia.Remove($k) } }
  function Agr($mode){ $d=New-Object 'System.Collections.Generic.Dictionary[datetime,decimal]'
    foreach($k in $porDia.Keys){ $q=$porDia[$k]
      switch($mode){ 'sem'{$a=$k.AddDays(-[int]$k.DayOfWeek)} 'quin'{$a=New-Object datetime $k.Year,$k.Month,$(if($k.Day -le 15){1}else{16})} 'men'{$a=New-Object datetime $k.Year,$k.Month,1} }
      if($d.ContainsKey($a)){$d[$a]+=$q}else{$d[$a]=$q} }; ,$d }
  return @{ PorDia=$porDia; Sem=(Agr 'sem'); Quin=(Agr 'quin'); Men=(Agr 'men'); TotH=$totalHoras; DiasTrab=($totalHoras/8); FFin=$ffin
            DiasCal=([int]($ffin.Date - $fini.Date).TotalDays + 1) }
}

# ---- plan (resuelve predecesoras FS/SS en cascada) ----
$rows = @(Import-Csv $InputCsv)
Write-Host "Renglones a programar: $($rows.Count)`n"
$cn = Cn $Database
$info=@{}
foreach($row in $rows){
  $id=[int]$row.Id
  $cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT ClaveDeRenglon,Cantidad,PrecioUnitario,RecursoConceptoId,Total FROM RenglonDePresupuesto WHERE RenglonDePresupuestoId=$id"
  $rd=$cmd.ExecuteReader(); if(-not $rd.Read()){ $rd.Close(); throw "No existe Id=$id" }
  $info[$id]=@{ Clave=$rd.GetString(0); Cant=[decimal]$rd.GetValue(1); PU=[decimal]$rd.GetValue(2); Rcid=[int]$rd.GetValue(3); Total=[decimal]$rd.GetValue(4) }; $rd.Close()
}
$computed=@{}; $vinculos=@()
$pending=New-Object System.Collections.ArrayList; foreach($row in $rows){ [void]$pending.Add($row) }
while($pending.Count -gt 0){
  $progress=$false
  foreach($row in @($pending)){
    $id=[int]$row.Id; $ii=$info[$id]
    $predId = if($row.PSObject.Properties['PredId'] -and "$($row.PredId)".Trim()){ [int]$row.PredId } else { $null }
    if($predId -ne $null -and -not $computed.ContainsKey($predId)){ continue }
    $lagD=0.0
    if($predId -eq $null){
      $start=[datetime]::ParseExact($row.FechaInicio,'yyyy-MM-dd',$null).Date.Add($horaIni)
    } else {
      $tipo=("$($row.TipoVinc)").ToUpper(); $lagD= if("$($row.LagDias)".Trim()){[double]$row.LagDias}else{0.0}; $lagH=$lagD*8.0
      switch($tipo){
        'FS'{ $start=NormStart (AddWorkHours $computed[$predId].FFin $lagH) }
        'SS'{ $start=NormStart (AddWorkHours $computed[$predId].FIni $lagH) }
        default{ throw "$($ii.Clave): TipoVinc '$tipo' no soportado (solo FS/SS por ahora)" }
      }
    }
    $cant=$ii.Cant; $modo= if("$($row.Modo)".Trim()){("$($row.Modo)").ToUpper()}else{'DUR'}
    if($modo -eq 'DUR'){
      $dcal=[int]$row.DiasCalendario; $uejec=1; $rend=0
      $off=[math]::Max(0.0,($start.TimeOfDay-$horaIni).TotalHours)
      $tot=0.0; for($k=0;$k -lt $dcal;$k++){ $tot+=HorasDia $start.Date.AddDays($k) }
      $totH=$tot-$off; if($totH -le 0){ throw "$($ii.Clave): lapso sin horas laborables" }
    } elseif($modo -eq 'REND'){
      $uejec=[double]$row.UEjecutoras
      $c2=$cn.CreateCommand(); $c2.CommandText="SELECT MAX(Rendimiento) FROM RecursoComponente WHERE MatrizDeRecursosId=$($ii.Rcid) AND DefineRendimientoActividad=1"
      $rv=$c2.ExecuteScalar(); if($rv -eq [DBNull]::Value -or $rv -eq $null){ throw "$($ii.Clave): sin componente definidor de rendimiento" }
      $rend=[double]$rv; $totH=([double]$cant/($rend*$uejec))*8.0
    } else { throw "Modo invalido '$modo'" }
    $r=Distribuir $start $totH $cant
    $computed[$id]=[pscustomobject]@{ Id=$id; Clave=$ii.Clave; Modo=$modo; UEjec=$uejec; Rend=$rend; Cant=$cant; PU=$ii.PU;
      FIni=$start; FFin=$r.FFin; DiasCal=$r.DiasCal; DiasTrab=$r.DiasTrab; Esf=$r.TotH; Total=$(if($ii.Cant -ne 0){[decimal]$cant/$ii.Cant*$ii.Total}else{$ii.Total}); Calc=$r }
    if($predId -ne $null){ $vinculos+=@{ Suc=$id; Pred=$predId; Tipo=("$($row.TipoVinc)").ToUpper(); Lag=$lagD } }
    [void]$pending.Remove($row); $progress=$true
    $vtxt= if($predId -ne $null){ "<-$($info[$predId].Clave) $(("$($row.TipoVinc)").ToUpper())+${lagD}d" } else { "(ancla)" }
    Write-Host ("{0,-9} [{1,-4}] | {2:yyyy-MM-dd HH:mm}->{3:yyyy-MM-dd HH:mm} | dcal {4}/dtrab {5} | UEj {6} | cant {7} | `$ {8}  {9}" -f $ii.Clave,$modo,$start,$r.FFin,$r.DiasCal,[math]::Round($r.DiasTrab,3),$uejec,$cant,[math]::Round($computed[$id].Total,2),$vtxt)
  }
  if(-not $progress){ throw "Ciclo o predecesora no incluida en el CSV" }
}
$plan=@(); foreach($row in $rows){ $plan+=$computed[[int]$row.Id] }
$cn.Close()

if($WhatIf){
  $ini=($plan | Sort-Object FIni)[0].FIni; $fin=($plan | Sort-Object FFin)[-1].FFin
  $sem=[math]::Round(($fin-$ini).TotalDays/7,1)
  Write-Host ("`n[WhatIf] Inicio {0:yyyy-MM-dd} | Fin {1:yyyy-MM-dd} | {2} dias naturales | ~{3} semanas | {4} renglones" -f $ini,$fin,[int]($fin-$ini).TotalDays,$sem,$plan.Count) -ForegroundColor Cyan
  return
}

# ===== ESCRITURA =====
$m = Cn "master"; $cmd=$m.CreateCommand(); $cmd.CommandText="SELECT session_id FROM sys.dm_exec_sessions WHERE database_id=DB_ID('$Database') AND session_id<>@@SPID"
$rd=$cmd.ExecuteReader(); $sids=@(); while($rd.Read()){ $sids+=$rd.GetInt16(0) }; $rd.Close()
foreach($s in $sids){ try{ $c=$m.CreateCommand(); $c.CommandText="KILL $s"; [void]$c.ExecuteNonQuery() }catch{} }
$m.Close(); Start-Sleep -Seconds 1

$ts=Get-Date -Format "yyyyMMdd_HHmmss"
$bak=Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "backups") "SANDBOX_PRE_PROGRAMA_$ts.bak"
$mb = Cn "master"; $c=$mb.CreateCommand(); $c.CommandText="BACKUP DATABASE [$Database] TO DISK=N'$bak' WITH FORMAT,INIT,NAME='pre-programa'"; $c.CommandTimeout=120; [void]$c.ExecuteNonQuery(); $mb.Close()
Write-Host "Backup: $bak"

$cn = Cn $Database; $tx = $cn.BeginTransaction()
try {
  foreach($p in $plan){
    $c=$cn.CreateCommand(); $c.Transaction=$tx
    $c.CommandText=@"
UPDATE RenglonDePresupuesto SET
 EstaProgramada=1, ProgramaSegunRendimiento=@rend, CantidadesDistribuidas=1, DistribucionesEditadas=0,
 CantidadProgramada=@cant, Remanente=0, TotalProgramado=@total, UEjecutoras=@uejec,
 DiasCalendario=@dcal, DiasTrabajables=@dtrab, Esfuerzo=@esf,
 FechaInicio=@fini, FechaInicioOriginal=@fini, FechaFin=@ffin,
 CantidadesPorDia=@cxd, DistribucionSemanal=@sem, DistribucionQuincenal=@quin, DistribucionMensual=@men
WHERE RenglonDePresupuestoId=@id
"@
    [void]$c.Parameters.Add("@rend",[Data.SqlDbType]::Bit); $c.Parameters["@rend"].Value=[bool]($p.Modo -eq 'REND')
    [void]$c.Parameters.Add("@cant",[Data.SqlDbType]::Decimal); $c.Parameters["@cant"].Precision=28; $c.Parameters["@cant"].Scale=6; $c.Parameters["@cant"].Value=[math]::Round([decimal]$p.Cant,6)
    [void]$c.Parameters.Add("@total",[Data.SqlDbType]::Decimal); $c.Parameters["@total"].Precision=28; $c.Parameters["@total"].Scale=6; $c.Parameters["@total"].Value=[math]::Round([decimal]$p.Total,6)
    [void]$c.Parameters.Add("@uejec",[Data.SqlDbType]::Decimal); $c.Parameters["@uejec"].Precision=28; $c.Parameters["@uejec"].Scale=6; $c.Parameters["@uejec"].Value=[decimal]$p.UEjec
    [void]$c.Parameters.Add("@dcal",[Data.SqlDbType]::Decimal); $c.Parameters["@dcal"].Value=[decimal]$p.DiasCal
    [void]$c.Parameters.Add("@dtrab",[Data.SqlDbType]::Decimal); $c.Parameters["@dtrab"].Precision=28; $c.Parameters["@dtrab"].Scale=6; $c.Parameters["@dtrab"].Value=[math]::Round([decimal]$p.DiasTrab,6)
    [void]$c.Parameters.Add("@esf",[Data.SqlDbType]::Float); $c.Parameters["@esf"].Value=[double]$p.Esf
    [void]$c.Parameters.Add("@fini",[Data.SqlDbType]::DateTime); $c.Parameters["@fini"].Value=$p.FIni
    [void]$c.Parameters.Add("@ffin",[Data.SqlDbType]::DateTime); $c.Parameters["@ffin"].Value=$p.FFin
    [void]$c.Parameters.Add("@cxd",[Data.SqlDbType]::VarBinary); $c.Parameters["@cxd"].Value=(Ser $p.Calc.PorDia)
    [void]$c.Parameters.Add("@sem",[Data.SqlDbType]::VarBinary); $c.Parameters["@sem"].Value=(Ser $p.Calc.Sem)
    [void]$c.Parameters.Add("@quin",[Data.SqlDbType]::VarBinary); $c.Parameters["@quin"].Value=(Ser $p.Calc.Quin)
    [void]$c.Parameters.Add("@men",[Data.SqlDbType]::VarBinary); $c.Parameters["@men"].Value=(Ser $p.Calc.Men)
    [void]$c.Parameters.Add("@id",[Data.SqlDbType]::Int); $c.Parameters["@id"].Value=$p.Id
    if($c.ExecuteNonQuery() -ne 1){ throw "UPDATE != 1 fila para Id $($p.Id)" }
  }
  $c=$cn.CreateCommand(); $c.Transaction=$tx
  $c.CommandText=@"
DECLARE @ini datetime=(SELECT MIN(FechaInicio) FROM RenglonDePresupuesto WHERE EstaProgramada=1);
DECLARE @fin datetime=(SELECT MAX(FechaFin)    FROM RenglonDePresupuesto WHERE EstaProgramada=1);
UPDATE ProyectoPropuesta SET FechaInicioProgramaDeObra=@ini,FechaFinProgramaDeObra=@fin,
 FechaInicioProyecto=@ini,FechaFinProyecto=@fin,FechaInicioFinanciamiento=@ini,FechaFinFinanciamiento=@fin,
 FechaDeInicio=@ini,FechaDeTermino=@fin,ActualizacionNecesaria=0;
"@
  [void]$c.ExecuteNonQuery()

  # vinculos (FS=0,FF=1,SS=2,SF=3 ; Aplazamiento en horas laborables = lagDias*8)
  if($vinculos.Count -gt 0){
    $c=$cn.CreateCommand(); $c.Transaction=$tx; $c.CommandText="SELECT ISNULL(MAX(Oid),0) FROM Vinculo"; $oid=[int]$c.ExecuteScalar()
    $tmap=@{'FS'=0;'FF'=1;'SS'=2;'SF'=3}
    foreach($v in $vinculos){
      $oid++
      $cad= if($v.Lag -gt 0){"+{0}l" -f $v.Lag} elseif($v.Lag -lt 0){"{0}l" -f $v.Lag} else {""}
      $c=$cn.CreateCommand(); $c.Transaction=$tx
      $c.CommandText="INSERT INTO Vinculo (Oid,RenglonInicioId,RenglonFinId,TipoVinculo,Aplazamiento,CadenaAplazamiento) VALUES (@o,@i,@f,@t,@l,@c)"
      [void]$c.Parameters.Add("@o",[Data.SqlDbType]::Int); $c.Parameters["@o"].Value=$oid
      [void]$c.Parameters.Add("@i",[Data.SqlDbType]::Int); $c.Parameters["@i"].Value=$v.Pred
      [void]$c.Parameters.Add("@f",[Data.SqlDbType]::Int); $c.Parameters["@f"].Value=$v.Suc
      [void]$c.Parameters.Add("@t",[Data.SqlDbType]::SmallInt); $c.Parameters["@t"].Value=$tmap[$v.Tipo]
      [void]$c.Parameters.Add("@l",[Data.SqlDbType]::Decimal); $c.Parameters["@l"].Precision=28; $c.Parameters["@l"].Scale=6; $c.Parameters["@l"].Value=[decimal]($v.Lag*8)
      [void]$c.Parameters.Add("@c",[Data.SqlDbType]::NVarChar); $c.Parameters["@c"].Value=$cad
      [void]$c.ExecuteNonQuery()
    }
    Write-Host "Vinculos insertados: $($vinculos.Count)"
  }

  $c=$cn.CreateCommand(); $c.Transaction=$tx; $c.CommandText="SELECT COUNT(*) FROM RenglonDePresupuesto WHERE EstaProgramada=1"
  if([int]$c.ExecuteScalar() -lt $plan.Count){ throw "Verificacion fallo" }
  $tx.Commit(); Write-Host "COMMIT OK." -ForegroundColor Green
} catch { $tx.Rollback(); Write-Host "ROLLBACK: $($_.Exception.Message)" -ForegroundColor Red; throw }
finally { $cn.Close() }
