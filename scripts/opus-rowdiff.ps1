<#
  opus-rowdiff.ps1 - Compara TODAS las columnas de UNA fila entre dos BDs (mismo query).
  Util para ver el delta completo de un cambio: sandbox (modificado) vs 110 (pristino).
  Los varbinary se muestran como blob(len=N); las diferencias se listan columna por columna.

  Uso:
    .\opus-rowdiff.ps1 -DbBase "<110.mdf>" -DbMod "<sandbox.mdf>" `
        -Query "SELECT * FROM RenglonDePresupuesto WHERE ClaveDeRenglon='DEM'"
#>
param(
  [Parameter(Mandatory=$true)][string]$DbBase,
  [Parameter(Mandatory=$true)][string]$DbMod,
  [Parameter(Mandatory=$true)][string]$Query,
  [string]$Server = "(localdb)\OpusLocal"
)
$ErrorActionPreference = "Stop"

function Get-Row($db, $q) {
  $cn = New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$db;Integrated Security=SSPI"
  $cn.Open()
  try {
    $cmd = $cn.CreateCommand(); $cmd.CommandText = $q
    $rd = $cmd.ExecuteReader()
    $h = [ordered]@{}
    if ($rd.Read()) {
      for ($i=0; $i -lt $rd.FieldCount; $i++) {
        $name = $rd.GetName($i)
        if ($rd.IsDBNull($i)) { $h[$name] = "NULL"; continue }
        $v = $rd.GetValue($i)
        if ($v -is [byte[]]) { $h[$name] = "blob(len=$($v.Length))" }
        elseif ($v -is [datetime]) { $h[$name] = $v.ToString("yyyy-MM-dd HH:mm:ss") }
        else { $h[$name] = [string]$v }
      }
    }
    return $h
  } finally { $cn.Close() }
}

$base = Get-Row $DbBase $Query
$mod  = Get-Row $DbMod  $Query
$keys = @($base.Keys) + @($mod.Keys) | Select-Object -Unique
$diffs = 0
Write-Host ("{0,-32} | {1,-30} | {2}" -f "COLUMNA", "BASE (110)", "MOD (sandbox)")
Write-Host ("-" * 90)
foreach ($k in $keys) {
  $bv = if ($base.Contains($k)) { $base[$k] } else { "<falta>" }
  $mv = if ($mod.Contains($k))  { $mod[$k]  } else { "<falta>" }
  if ($bv -ne $mv) {
    $diffs++
    Write-Host ("{0,-32} | {1,-30} | {2}" -f $k, $bv, $mv) -ForegroundColor Yellow
  }
}
Write-Host ("-" * 90)
Write-Host "$diffs columnas distintas."
