<#
  opus-dashboard.ps1 - Dashboard HTML del programa de obra (identidad SOLINGEN).
  3 pesta&ntilde;as: (1) Procedimiento Constructivo Propuesto, (2) Programa de Obra (Gantt + observaciones
  editables + colapsables + vinculos con tooltip), (3) Vinculos (tabla relacional).
  La barra de herramientas solo aparece en la pesta&ntilde;a Programa de Obra.
#>
param(
  [Parameter(Mandatory=$true)][string]$Database,
  [Parameter(Mandatory=$true)][string]$Salida,
  [string]$Proyecto="Salones de Eventos - Centro Libanes",
  [string]$Revisor="Ing. Valdes",
  [string]$Server="(localdb)\OpusLocal"
)
$ErrorActionPreference="Stop"
$cult=[System.Globalization.CultureInfo]::GetCultureInfo("es-MX")
function Cn($db){ $c=New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$db;Integrated Security=SSPI"; $c.Open(); $c }
function Enc($s){ if($null -eq $s){return ""}; ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;') }
function TitleCase($s){ if(-not $s){return ""}; $cult.TextInfo.ToTitleCase($s.ToLower()) }
function JsEsc($s){ if($null -eq $s){return ""}; ($s -replace '\\','\\\\' -replace "'","\'") }
function ShortName($d){
  if(-not $d){return ""}
  $s=($d -replace '\s+',' ').Trim()
  $i=$s.IndexOfAny([char[]]@(',',';'))
  if($i -ge 18){ $s=$s.Substring(0,$i) }
  $w=$s.Split(' '); if($w.Count -gt 9){ $s=($w[0..8] -join ' ') }
  $s=$s.Trim(); if($s.Length -gt 60){ $s=$s.Substring(0,58).Trim()+[char]0x2026 }
  if($s.Length -gt 0){ $s=$s.Substring(0,1).ToUpper()+$s.Substring(1).ToLower() }
  return $s
}

$cn=Cn $Database
$q=@"
WITH tree AS (
 SELECT RenglonDePresupuestoId Id, RenglonPadreId Padre, Indice, ClaveDeRenglon Clave, Descripcion D,
        TipoRenglonPresupuesto T, Nivel, Cantidad Cant, UnidadMedida UM, Total, EstaProgramada Prog,
        FechaInicio FIni, FechaFin FFin, DiasCalendario DCal,
        CAST(RIGHT('00000'+CAST(Indice AS varchar),5) AS varchar(900)) sk, CAST('' AS varchar(900)) anc
 FROM RenglonDePresupuesto WHERE RenglonPadreId IS NULL
 UNION ALL
 SELECT r.RenglonDePresupuestoId,r.RenglonPadreId,r.Indice,r.ClaveDeRenglon,r.Descripcion,r.TipoRenglonPresupuesto,
        r.Nivel,r.Cantidad,r.UnidadMedida,r.Total,r.EstaProgramada,r.FechaInicio,r.FechaFin,r.DiasCalendario,
        CAST(t.sk+'.'+RIGHT('00000'+CAST(r.Indice AS varchar),5) AS varchar(900)),
        CAST(LTRIM(t.anc+' '+CAST(t.Id AS varchar)) AS varchar(900))
 FROM RenglonDePresupuesto r JOIN tree t ON r.RenglonPadreId=t.Id)
SELECT Id,Nivel,T,Clave,D,UM,Cant,Total,Prog,FIni,FFin,DCal,anc FROM tree WHERE Nivel>=0 ORDER BY sk;
"@
$cmd=$cn.CreateCommand(); $cmd.CommandText=$q; $rd=$cmd.ExecuteReader()
$rows=@(); $ix=0; $orderIx=@{}
while($rd.Read()){
  $o=[pscustomobject]@{
    Id=[int]$rd.GetValue(0); Nivel=[int]$rd.GetValue(1); T=[int]$rd.GetValue(2)
    Clave=$(if($rd.IsDBNull(3)){""}else{$rd.GetString(3)}); D=$(if($rd.IsDBNull(4)){""}else{$rd.GetString(4)})
    UM=$(if($rd.IsDBNull(5)){""}else{$rd.GetString(5)}); Cant=[decimal]$rd.GetValue(6); Total=[decimal]$rd.GetValue(7)
    Prog=[bool]$rd.GetValue(8); FIni=[datetime]$rd.GetValue(9); FFin=[datetime]$rd.GetValue(10); DCal=[decimal]$rd.GetValue(11)
    Anc=$(if($rd.IsDBNull(12)){""}else{$rd.GetString(12)})
  }
  $rows+=$o; $orderIx["$($o.Id)"]=$ix; $ix++
}
$rd.Close()
$cmd=$cn.CreateCommand(); $cmd.CommandText="SELECT RenglonInicioId,RenglonFinId,TipoVinculo,Aplazamiento,CadenaAplazamiento FROM Vinculo WHERE RenglonInicioId IS NOT NULL AND RenglonFinId IS NOT NULL"
$rd=$cmd.ExecuteReader(); $links=@()
while($rd.Read()){ $links+=[pscustomobject]@{ P=[int]$rd.GetValue(0);S=[int]$rd.GetValue(1);T=[int]$rd.GetValue(2);Apl=[decimal]$rd.GetValue(3);Cad=$(if($rd.IsDBNull(4)){""}else{$rd.GetString(4)}) } }
$rd.Close(); $cn.Close()

$byId=@{}; foreach($r in $rows){ $byId["$($r.Id)"]=$r }
$tipoN=@('FC (Fin->Comienzo)','FF (Fin->Fin)','CC (Comienzo->Comienzo)','CF (Comienzo->Fin)')
$short=@{}; foreach($r in $rows){ $short["$($r.Id)"]=(ShortName $r.D) }
function LagTxt($apl){ $dias=[math]::Round([double]$apl/8,1); if($dias -eq 0){"sin antelacion"}elseif($dias -gt 0){"+$dias dias hab."}else{"$dias dias hab."} }
$linksJs=($links | ForEach-Object {
  "{p:$($_.P),s:$($_.S),t:$($_.T),pc:'$(JsEsc $short["$($_.P)"])',sc:'$(JsEsc $short["$($_.S)"])',tn:'$(JsEsc $tipoN[$_.T])',lg:'$(JsEsc (LagTxt $_.Apl))'}"
}) -join ','

$pf=$rows | Where-Object{ $_.T -eq 2 -and $_.Prog }
$ini=($pf | Sort-Object FIni)[0].FIni.Date
$fin=($pf | Sort-Object FFin)[-1].FFin.Date
$totalDias=[double]($fin-$ini).TotalDays+1
$importe=($pf | Measure-Object Total -Sum).Sum
$span=@{}
foreach($r in $pf){ foreach($a in ($r.Anc -split ' ' | Where-Object{$_})){
  if(-not $span.ContainsKey($a)){ $span[$a]=@{Ini=$r.FIni;Fin=$r.FFin} } else { if($r.FIni -lt $span[$a].Ini){$span[$a].Ini=$r.FIni}; if($r.FFin -gt $span[$a].Fin){$span[$a].Fin=$r.FFin} } } }
$meses=@(); $m=New-Object datetime $ini.Year,$ini.Month,1
while($m -le $fin){ $meses+=$m; $m=$m.AddMonths(1) }
function Fmt($d){ if($d -eq 0){return ""}; ('{0:#,0.00}' -f $d) }
function Pct($d){ [math]::Round((([datetime]$d).Date-$ini).TotalDays/$totalDias*100,2) }
function Wpct($a,$b){ $w=[math]::Round(((([datetime]$b).Date-([datetime]$a).Date).TotalDays+1)/$totalDias*100,2); if($w -lt 0.6){0.6}else{$w} }
$mesHdr=""; foreach($mm in $meses){ $mesHdr+="<span class='mlab' style='left:$(Pct $mm)%'>$($mm.ToString('MMM',$cult))</span>" }

function FilaFull($r){
  $pad=[int]$r.Nivel*14
  if($r.T -eq 1){
    $sp=$span["$($r.Id)"]; $sb2="";$cf="";$cd=""
    if($sp){ $sb2="<div class='sbar' style='left:$(Pct $sp.Ini)%;width:$(Wpct $sp.Ini $sp.Fin)%'></div>"; $cf="$($sp.Ini.ToString('dd/MMM',$cult)) &rarr; $($sp.Fin.ToString('dd/MMM',$cult))"; $cd=[int]((($sp.Fin).Date-($sp.Ini).Date).TotalDays+1) }
    $tgl="<button class='tgl' data-cid='$($r.Id)' onclick='tg(`"$($r.Id)`")'>&minus;</button>"
    return "<tr class='cap$([math]::Min($r.Nivel,3))' data-anc='$($r.Anc)' data-cid='$($r.Id)'><td class='cl'>$tgl</td><td colspan='3' style='padding-left:$($pad)px'>$(Enc (TitleCase $r.D))</td><td class='dates'>$cf</td><td class='num'>$cd</td><td><div class='gantt'>$sb2</div></td><td></td></tr>`n"
  } else {
    $bar=""; if($r.Prog){ $bar="<div id='bar_$($r.Id)' class='bar' style='left:$(Pct $r.FIni)%;width:$(Wpct $r.FIni $r.FFin)%' title='$($r.FIni.ToString("dd/MMM",$cult)) - $($r.FFin.ToString("dd/MMM",$cult))'></div>" }
    $fechas=if($r.Prog){"$($r.FIni.ToString('dd/MMM',$cult)) &rarr; $($r.FFin.ToString('dd/MMM',$cult))"}else{""}
    return "<tr data-anc='$($r.Anc)'><td class='cl'>$(Enc $r.Clave)</td><td class='concepto'><div class='clamp' title='$(Enc $r.D)'>$(Enc $r.D)</div></td><td>$(Enc $r.UM)</td><td class='num'>$(Fmt $r.Cant)</td><td class='dates'>$fechas</td><td class='num'>$([int]$r.DCal)</td><td><div class='gantt'>$bar</div></td><td class='obs'><textarea data-id='$($r.Id)' placeholder='Observaciones...'></textarea></td></tr>`n"
  }
}
$tablaFull=New-Object System.Text.StringBuilder
foreach($r in $rows){ [void]$tablaFull.Append((FilaFull $r)) }
$tablaLink=New-Object System.Text.StringBuilder
$n=0
foreach($l in ($links | Sort-Object @{e={$orderIx["$($_.S)"]}})){
  $n++; $tn=@('FC','FF','CC','CF')[$l.T]
  [void]$tablaLink.Append("<tr><td class='num'>$n</td><td>$(Enc $short["$($l.P)"])</td><td class='ctr'><span class='tip2' title='$(Enc $tipoN[$l.T])'>$tn</span></td><td class='ctr'>$(Enc (LagTxt $l.Apl))</td><td>$(Enc $short["$($l.S)"])</td></tr>`n")
}

# isotipo SOLINGEN (blanco) para el header
$iso=@"
<svg class='iso' viewBox='0 0 260 427' xmlns='http://www.w3.org/2000/svg'><g fill='#fff'>
<polygon points='15,414 75,414 90,174 47,174'/><polygon points='100,414 160,414 147,34 113,34'/><polygon points='185,414 245,414 213,174 170,174'/>
<rect x='0' y='414' width='260' height='13'/><rect x='128' y='4' width='4' height='30'/><rect x='128' y='0' width='32' height='4'/><rect x='114' y='0' width='14' height='4'/><rect x='152' y='20' width='5' height='3'/></g></svg>
"@

# Procedimiento Constructivo Propuesto
$proc=@"
<span class='tag'>SOLUCIONES EN INGENIER&Iacute;A</span>
<h2>Procedimiento Constructivo Propuesto</h2><hr class='rule-celeste'>
<p>El presente programa de obra para los <b>Salones de Eventos del Centro Liban&eacute;s</b> se estructur&oacute; siguiendo la secuencia l&oacute;gica de construcci&oacute;n &mdash; del desmantelamiento a los acabados finos &mdash; con una duraci&oacute;n estimada de <b>~6.4 meses</b> ($($ini.ToString('dd/MMM/yyyy',$cult)) a $($fin.ToString('dd/MMM/yyyy',$cult))), considerando jornada con <b>s&aacute;bados a medias</b> y los <b>d&iacute;as festivos oficiales (LFT 2026)</b> como no laborables. A continuaci&oacute;n se describe el criterio constructivo y los v&iacute;nculos entre actividades.</p>
<div class='cards'>
<div class='pcard'><div class='pnum'>01</div><h3>Preliminares y demolici&oacute;n</h3><p>Arranca la obra con la <b>demolici&oacute;n de muros</b>; el <b>acarreo de material</b> se vincula con holgura negativa para iniciar antes de concluir la demolici&oacute;n y no detener el frente. En paralelo desde el d&iacute;a uno corren el <b>desmantelamiento de instalaci&oacute;n el&eacute;ctrica existente</b> y los <b>gastos generales</b> (residente, brigadista, limpieza gruesa, carga de material).</p></div>
<div class='pcard'><div class='pnum'>02</div><h3>Alba&ntilde;iler&iacute;a y estructura</h3><p>Concluida la demolici&oacute;n se ejecuta la <b>alba&ntilde;iler&iacute;a</b> en cadena: castillos, cadenas, dados de cimentaci&oacute;n, rehabilitaci&oacute;n de muro existente y muro de block. En el mismo lapso (en paralelo) se habilita el <b>acero estructural</b> &mdash; refuerzo y bastidor del muro de acceso &mdash; junto con los <b>rieles y suspensi&oacute;n met&aacute;lica</b> de los muros m&oacute;viles, que se dejan preparados desde esta etapa.</p></div>
<div class='pcard'><div class='pnum'>03</div><h3>Instalaciones</h3><p>Antes de cualquier acabado de piso se tienden las <b>instalaciones hidr&aacute;ulica, sanitaria y el&eacute;ctrica</b> (tuber&iacute;as, salidas, alimentaciones). Se consideran ~3 semanas por disciplina contemplando <b>pruebas</b> de las redes.</p></div>
<div class='pcard'><div class='pnum'>04</div><h3>Herrer&iacute;a</h3><p>Con las instalaciones listas se fabrica e instala la <b>herrer&iacute;a</b>: escaleras, escotillas, planchas, esp&aacute;rragos y la <b>estructura de p&eacute;rgola</b>, que marca el paso hacia los acabados.</p></div>
<div class='pcard'><div class='pnum'>05</div><h3>Acabados: pisos &rarr; muros &rarr; plafones</h3><p>Los acabados siguen el orden <b>pisos, muros y plafones</b>, traslapados para optimizar tiempos:</p>
<ul><li><b>Pisos:</b> primero el <b>autonivelante</b>; el <b>m&aacute;rmol</b> considera ~3 semanas de <b>suministro</b> previo a su colocaci&oacute;n (suministro y colocaci&oacute;n son conceptos distintos); la <b>alfombra</b> y el z&oacute;clo de madera se dejan al final para no exponerlos a manchas.</li>
<li><b>Muros:</b> el <b>aislamiento ac&uacute;stico</b> va antes de cerrar paneles; despu&eacute;s lambrines y placas; el <b>estuco</b> precede a la <b>pintura</b>, que se aplica al &uacute;ltimo.</li>
<li><b>Plafones:</b> panel de yeso, recubrimiento de l&aacute;mina y aislante, cerrando con la <b>pintura</b> al final.</li></ul></div>
<div class='pcard'><div class='pnum'>06</div><h3>Detalles finos y cierre</h3><p>Tras los acabados: <b>canceler&iacute;a y aluminio</b>, luego <b>carpinter&iacute;a</b> (3 semanas de fabricaci&oacute;n a puesta en obra). En paralelo, <b>muros m&oacute;viles</b> (~1 mes), <b>muebles y accesorios de ba&ntilde;o</b> (con instalaciones ya probadas) e, inicio con inicio, <b>luminarias y accesorios el&eacute;ctricos</b>. La <b>limpieza fina</b> ocupa las &uacute;ltimas 2&ndash;3 semanas.</p></div>
</div>
<div class='callout'><b>Supervisi&oacute;n y administraci&oacute;n (15%).</b> Se distribuye a lo largo de la obra de forma proporcional al <b>costo de cada mes</b>, de modo que represente el 15% del avance econ&oacute;mico mensual.</div>
<div class='callout'><b>Sobre los v&iacute;nculos.</b> Las dependencias entre actividades (FC fin&rarr;comienzo, CC comienzo&rarr;comienzo, FF, CF) y sus holguras (en d&iacute;as h&aacute;biles) pueden consultarse gr&aacute;ficamente en <i>Programa de Obra</i> (flechas, con detalle al pasar el cursor) y en la pesta&ntilde;a <i>V&iacute;nculos</i> como tabla. El programa es una propuesta sujeta a la revisi&oacute;n del ingeniero ejecutor.</div>
"@

$sb=New-Object System.Text.StringBuilder
[void]$sb.Append(@"
<!DOCTYPE html><html lang='es'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Programa de Obra - $(Enc $Proyecto)</title>
<style>
:root{--marino:#1E3A5F;--marino900:#132744;--marino700:#2a4e7c;--celeste:#53B4E7;--celeste-soft:#EAF6FD;--soft:#F2F4F7;--rule:#E5E7EB;--text:#1F2937;--text2:#6B7280}
*{box-sizing:border-box} body{font-family:'Segoe UI',Arial,Helvetica,sans-serif;margin:0;background:#fff;color:var(--text);font-size:13px}
h1,h2,h3{font-family:'Segoe UI','Arial Black',Arial,sans-serif;color:var(--marino);margin:0}
header{background:var(--marino);color:#fff;padding:12px 22px;position:sticky;top:0;z-index:30;border-bottom:3px solid var(--celeste)}
.htop{display:flex;align-items:center;gap:16px}
.brand{display:flex;align-items:center;gap:11px} .iso{height:42px;width:auto}
.wm{display:flex;flex-direction:column;line-height:1} .wm1{font-weight:900;font-size:17px;letter-spacing:2px;font-family:'Segoe UI','Arial Black',sans-serif} .wm2{font-weight:300;font-size:9.5px;letter-spacing:5px;opacity:.9}
.dtitle{margin-left:auto;text-align:right} .dtitle h1{color:#fff;font-size:17px;font-weight:700} .dtitle .sub{font-size:11.5px;opacity:.9}
.meta{font-size:11px;opacity:.9;margin-top:7px;line-height:1.5}
.tabs{display:flex;gap:4px;margin-top:10px}
.tab{background:var(--marino700);color:#cfe0ec;border:0;padding:8px 16px;border-radius:6px 6px 0 0;cursor:pointer;font-size:13px;font-weight:600}
.tab.act{background:#fff;color:var(--marino)}
#toolbar{position:sticky;top:108px;z-index:29;background:var(--soft);padding:8px 22px;border-bottom:1px solid var(--rule);display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.btn{background:var(--marino);color:#fff;border:0;padding:7px 12px;border-radius:5px;cursor:pointer;font-size:12px;font-weight:600}.btn.sec{background:var(--marino700)}.btn:hover{opacity:.92}
.note{font-size:11px;color:var(--text2)} label.chk{font-size:12px;display:flex;align-items:center;gap:4px;cursor:pointer}
#flash{color:#0a7d33;font-weight:700;font-size:12px;display:none}
.wrap{position:relative}
table{border-collapse:collapse;width:100%;background:#fff} table.t1{table-layout:fixed}
th,td{border:1px solid var(--rule);padding:5px 7px;vertical-align:top;overflow:hidden}
th{background:var(--celeste-soft);color:var(--marino);position:sticky;top:150px;z-index:10;font-weight:700;text-align:left}
tr.cap0 td{background:var(--marino900);color:#fff;font-weight:700;font-size:13.5px}
tr.cap1 td{background:var(--marino);color:#fff;font-weight:700}
tr.cap2 td{background:#cfe0ec;color:var(--marino);font-weight:700}
tr.cap3 td{background:var(--celeste-soft);color:var(--marino);font-weight:600}
.num{text-align:right;white-space:nowrap} .ctr{text-align:center}
.cl{font-family:Consolas,monospace;font-weight:600;color:var(--marino);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
td.concepto{cursor:help} .clamp{display:-webkit-box;-webkit-line-clamp:3;line-clamp:3;-webkit-box-orient:vertical;overflow:hidden;line-height:1.35;max-height:4.05em}
.tgl{width:17px;height:17px;line-height:14px;text-align:center;border:1px solid currentColor;background:transparent;color:inherit;border-radius:3px;cursor:pointer;font-weight:700;padding:0;margin-right:4px;font-size:12px}
.gantt{position:relative;height:20px;background:repeating-linear-gradient(90deg,#eef2f6 0 1px,transparent 1px 100%);border-radius:3px}
.bar{position:absolute;height:13px;top:3px;background:linear-gradient(var(--marino700),var(--marino));border-radius:3px;box-shadow:0 1px 2px rgba(0,0,0,.2)}
.sbar{position:absolute;height:7px;top:6px;background:var(--marino900);border-radius:2px}
.sbar:before,.sbar:after{content:'';position:absolute;top:0;border-top:7px solid var(--marino900);border-left:4px solid transparent;border-right:4px solid transparent}.sbar:before{left:-1px}.sbar:after{right:-1px}
.gh{position:relative;height:16px} .mlab{position:absolute;font-size:10px;color:var(--marino);opacity:.6;transform:translateX(2px)}
svg.lk{position:absolute;top:0;left:0;pointer-events:none;z-index:6;overflow:visible}
textarea{width:100%;min-height:32px;border:1px solid #c7d0d9;border-radius:4px;padding:4px;font-family:inherit;font-size:12px;resize:vertical}
textarea:focus{outline:2px solid var(--celeste);border-color:var(--celeste)} td.obs{background:#fffef5}
.dates{white-space:nowrap;font-size:11.5px}
#tip{position:fixed;display:none;z-index:100;background:var(--marino);color:#fff;padding:8px 10px;border-radius:6px;font-size:12px;line-height:1.5;box-shadow:0 3px 10px rgba(19,39,68,.3);pointer-events:none;max-width:300px;border-left:3px solid var(--celeste)}
#tab-proc{padding:26px 40px;max-width:1100px}
.tag{font-size:11px;font-weight:700;letter-spacing:.18em;color:var(--celeste)} #tab-proc h2{font-size:26px;margin:6px 0 0} .rule-celeste{height:2px;width:54px;background:var(--celeste);border:0;margin:10px 0 18px}
#tab-proc p{line-height:1.6;margin:0 0 12px;color:var(--text)} #tab-proc ul{margin:6px 0;padding-left:18px;line-height:1.55}
.cards{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:18px 0}
.pcard{background:var(--soft);border-top:3px solid var(--celeste);border-radius:0 0 6px 6px;padding:14px 16px} .pcard h3{font-size:15px;margin:2px 0 6px} .pnum{font-family:'Segoe UI','Arial Black',sans-serif;font-weight:900;font-size:30px;color:var(--celeste);line-height:1}
.callout{background:var(--celeste-soft);border-left:4px solid var(--celeste);padding:11px 14px;margin:12px 0;border-radius:0 4px 4px 0;line-height:1.55}
#tab-links{display:none;padding:18px 40px} table.t2{max-width:1100px} table.t2 td,table.t2 th{padding:7px 10px} table.t2 tr:nth-child(even) td{background:var(--soft)} .tip2{cursor:help;border-bottom:1px dotted var(--text2)}
#tab-full{display:none}
footer{background:var(--marino);color:#fff;padding:16px 22px;margin-top:24px;border-top:3px solid var(--celeste);font-size:11.5px;line-height:1.6}
footer b{color:#cfe0ec} footer .fcols{display:flex;gap:36px;flex-wrap:wrap}
@media print{#toolbar,.tabs{display:none}#tab-full,#tab-links,#tab-proc{display:block!important} textarea{border:0}}
</style></head><body>
<header>
 <div class='htop'>
  <div class='brand'>$iso<div class='wm'><span class='wm1'>SOLUCIONES</span><span class='wm2'>EN INGENIER&Iacute;A</span></div></div>
  <div class='dtitle'><h1>Programa de Obra</h1><div class='sub'>$(Enc $Proyecto)</div></div>
 </div>
 <div class='meta'>Periodo: $($ini.ToString('dd/MMM/yyyy',$cult)) &rarr; $($fin.ToString('dd/MMM/yyyy',$cult)) &nbsp;|&nbsp; Importe: `$$(Fmt $importe) &nbsp;|&nbsp; Duraciones en d&iacute;as calendario &nbsp;|&nbsp; Generado: $([datetime]::Now.ToString('dd/MMM/yyyy HH:mm',$cult))</div>
 <div class='tabs'><button class='tab act' id='tP' onclick="swTab('proc')">Procedimiento Constructivo</button><button class='tab' id='tF' onclick="swTab('full')">Programa de Obra</button><button class='tab' id='tL' onclick="swTab('links')">V&iacute;nculos</button></div>
</header>
<div id='toolbar' style='display:none'>
 <button class='btn' onclick='save()'>&#128190; Guardar comentarios</button>
 <button class='btn sec' onclick='download()'>&#11015; Descargar HTML con comentarios</button>
 <button class='btn sec' onclick='expandAll(true)'>Expandir todo</button>
 <button class='btn sec' onclick='expandAll(false)'>Colapsar partidas</button>
 <label class='chk'><input type='checkbox' id='tglv' checked onchange='toggleLk(this.checked)'> Mostrar v&iacute;nculos</label>
 <span id='flash'></span>
</div>
<div id='tab-proc'>$proc</div>
<div id='tab-full'><div class='wrap' id='wrap1'><table class='t1'>
<colgroup><col style='width:62px'><col style='width:300px'><col style='width:50px'><col style='width:74px'><col style='width:104px'><col style='width:44px'><col><col style='width:380px'></colgroup>
<thead><tr><th>Clave</th><th>Concepto</th><th>Unidad</th><th class='num'>Cantidad</th><th>Fechas</th><th class='num'>D&iacute;as</th><th>Programa<div class='gh'>$mesHdr</div></th><th>Observaciones $(Enc $Revisor)</th></tr></thead>
<tbody>
$($tablaFull.ToString())
</tbody></table><svg class='lk' id='lk1'></svg></div></div>
<div id='tab-links'>
<p class='note'><b>Precedente</b> = actividad que va antes; <b>Dependiente</b> = la que arranca seg&uacute;n la precedente. Tipo: FC fin&rarr;comienzo, CC comienzo&rarr;comienzo, FF fin&rarr;fin, CF comienzo&rarr;fin.</p>
<table class='t2'><thead><tr><th class='num'>#</th><th>Actividad precedente</th><th class='ctr'>Tipo</th><th class='ctr'>Antelaci&oacute;n</th><th>Actividad dependiente</th></tr></thead><tbody>
$($tablaLink.ToString())
</tbody></table></div>
<footer><div class='fcols'>
<div><b>Soluciones en Ingenier&iacute;a</b><br>Sur 145 No. 2317, Col. Gabriel Ramos Mill&aacute;n,<br>Iztacalco, CP 08000, Ciudad de M&eacute;xico</div>
<div><b>Ing. Luis Antonio Ram&iacute;rez Ju&aacute;rez</b><br>Tel. 55 8617 7747<br>ing.civil3333@gmail.com</div>
<div><b>Ing. Ricardo Galicia Calzada</b><br>Tel. 56 1124 2910<br>inggaliciaricardo@gmail.com</div>
</div></footer>
<div id='tip'></div>
<script>
const LINKS=[$linksJs]; const NS='http://www.w3.org/2000/svg';
const KEY='obs_centrolibanes_salones'; var collapsed=new Set(); var curTab='proc'; var showLk=true;
function flash(m){var f=document.getElementById('flash');f.textContent=m;f.style.display='inline';setTimeout(()=>f.style.display='none',2500);}
function swTab(t){curTab=t;
 document.getElementById('tab-proc').style.display=t=='proc'?'block':'none';
 document.getElementById('tab-full').style.display=t=='full'?'block':'none';
 document.getElementById('tab-links').style.display=t=='links'?'block':'none';
 document.getElementById('toolbar').style.display=t=='full'?'flex':'none';
 document.getElementById('tP').classList.toggle('act',t=='proc');document.getElementById('tF').classList.toggle('act',t=='full');document.getElementById('tL').classList.toggle('act',t=='links');
 if(t=='full')setTimeout(draw,30);}
function toggleLk(v){showLk=v;var s=document.getElementById('lk1');if(s)s.style.display=v?'block':'none';}
function tg(id){ if(collapsed.has(id))collapsed.delete(id); else collapsed.add(id); render(); }
function expandAll(open){ collapsed.clear(); if(!open){ document.querySelectorAll('tr[data-cid]').forEach(t=>{ if(t.dataset.anc.split(' ').filter(Boolean).length<=1) collapsed.add(t.dataset.cid); }); } render(); }
function render(){
  document.querySelectorAll('tr[data-anc]').forEach(function(tr){ var anc=tr.dataset.anc.split(' ').filter(Boolean); tr.style.display=anc.some(a=>collapsed.has(a))?'none':''; });
  document.querySelectorAll('button.tgl').forEach(function(b){ b.innerHTML=collapsed.has(b.dataset.cid)?'+':'&minus;'; });
  draw();
}
function draw(){ if(curTab!='full') return; var svg=document.getElementById('lk1'),wrap=document.getElementById('wrap1'); if(!svg||!wrap||wrap.offsetParent===null)return;
  svg.innerHTML='<defs><marker id="ah" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 z" fill="#53B4E7"/></marker></defs>';
  svg.setAttribute('width',wrap.scrollWidth); svg.setAttribute('height',wrap.scrollHeight); if(!showLk)return;
  var cr=wrap.getBoundingClientRect();
  LINKS.forEach(function(l){
    var a=document.getElementById('bar_'+l.p),b=document.getElementById('bar_'+l.s);
    if(!a||!b||a.offsetParent===null||b.offsetParent===null) return;
    var ra=a.getBoundingClientRect(),rb=b.getBoundingClientRect();
    var ay=ra.top-cr.top+wrap.scrollTop+ra.height/2, by=rb.top-cr.top+wrap.scrollTop+rb.height/2;
    var aR=ra.right-cr.left+wrap.scrollLeft,aL=ra.left-cr.left+wrap.scrollLeft,bR=rb.right-cr.left+wrap.scrollLeft,bL=rb.left-cr.left+wrap.scrollLeft;
    var ax,bx; if(l.t==2){ax=aL;bx=bL;}else if(l.t==1){ax=aR;bx=bR;}else if(l.t==3){ax=aL;bx=bR;}else{ax=aR;bx=bL;}
    var st=ax+6, d='M'+ax+' '+ay+' L'+st+' '+ay+' L'+st+' '+by+' L'+bx+' '+by;
    var vis=document.createElementNS(NS,'path'); vis.setAttribute('d',d);vis.setAttribute('fill','none');vis.setAttribute('stroke','#53B4E7');vis.setAttribute('stroke-width','1.3');vis.setAttribute('opacity','.85');vis.setAttribute('marker-end','url(#ah)');
    var hit=document.createElementNS(NS,'path'); hit.setAttribute('d',d);hit.setAttribute('fill','none');hit.setAttribute('stroke','rgba(0,0,0,0)');hit.setAttribute('stroke-width','11');hit.style.pointerEvents='stroke';hit.style.cursor='help';
    var info='<b>Dependiente:</b> '+l.sc+'<br><b>Precedente:</b> '+l.pc+'<br><b>Tipo:</b> '+l.tn+'<br><b>Antelaci&oacute;n:</b> '+l.lg;
    hit.addEventListener('mouseenter',function(e){tip(e,info);}); hit.addEventListener('mousemove',mtip); hit.addEventListener('mouseleave',htip);
    svg.appendChild(vis); svg.appendChild(hit);
  });
}
var TIP=null; function tip(e,html){TIP=document.getElementById('tip');TIP.innerHTML=html;TIP.style.display='block';mtip(e);} function mtip(e){if(!TIP)return;var x=e.clientX+14,y=e.clientY+14;if(x+310>innerWidth)x=e.clientX-310;TIP.style.left=x+'px';TIP.style.top=y+'px';} function htip(){if(TIP)TIP.style.display='none';}
function save(){var d={};document.querySelectorAll('textarea[data-id]').forEach(t=>{if(t.value.trim())d[t.dataset.id]=t.value;});localStorage.setItem(KEY,JSON.stringify(d));flash('Comentarios guardados ('+Object.keys(d).length+' conceptos)');}
function loadObs(){try{var d=JSON.parse(localStorage.getItem(KEY)||'{}');document.querySelectorAll('textarea[data-id]').forEach(t=>{if(d[t.dataset.id])t.value=d[t.dataset.id];});}catch(e){}}
document.addEventListener('input',e=>{if(e.target.matches('textarea[data-id]')){clearTimeout(window._t);window._t=setTimeout(save,800);}});
function download(){document.querySelectorAll('textarea[data-id]').forEach(t=>{t.textContent=t.value;});var html='<!DOCTYPE html>\n'+document.documentElement.outerHTML;var b=new Blob([html],{type:'text/html;charset=utf-8'});var a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='programa_obra_comentado.html';a.click();flash('Descargado: programa_obra_comentado.html');}
window.addEventListener('load',function(){loadObs();render();});
window.addEventListener('resize',function(){clearTimeout(window._r);window._r=setTimeout(draw,200);});
</script></body></html>
"@)
[IO.File]::WriteAllText($Salida, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
Write-Host "Dashboard generado: $Salida ($($pf.Count) conceptos, $($links.Count) vinculos)"
