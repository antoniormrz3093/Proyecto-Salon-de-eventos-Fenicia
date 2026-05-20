<#
  opus-diff.ps1 - Compara dos snapshots y muestra que cambio (lineas/filas).
  Uso: .\opus-diff.ps1 -Before antes -After despues
#>
param(
  [Parameter(Mandatory=$true)][string]$Before,
  [Parameter(Mandatory=$true)][string]$After
)
$ErrorActionPreference = "Stop"
$bDir = Join-Path $PSScriptRoot "snapshots\$Before"
$aDir = Join-Path $PSScriptRoot "snapshots\$After"
if (-not (Test-Path $bDir)) { throw "No existe snapshot '$Before' ($bDir)" }
if (-not (Test-Path $aDir)) { throw "No existe snapshot '$After' ($aDir)" }

$files = Get-ChildItem $aDir -Filter *.txt | Sort-Object Name
foreach ($f in $files) {
  $bFile = Join-Path $bDir $f.Name
  if (-not (Test-Path $bFile)) { Write-Host "== $($f.Name): (nuevo, sin baseline) =="; continue }
  $b = Get-Content $bFile
  $a = Get-Content $f.FullName
  $cmp = Compare-Object $b $a
  if ($cmp) {
    Write-Host ""
    Write-Host ("===== {0} : {1} lineas cambiadas =====" -f $f.Name, $cmp.Count) -ForegroundColor Yellow
    foreach ($c in $cmp) {
      $tag = if ($c.SideIndicator -eq '=>') { '[ANTES->]' } else { '[->DESP ]' }
      # '=>' solo en After (nuevo/modificado); '<=' solo en Before (viejo/eliminado)
      $mark = if ($c.SideIndicator -eq '=>') { 'DESPUES' } else { 'ANTES  ' }
      Write-Host ("  {0}: {1}" -f $mark, $c.InputObject)
    }
  } else {
    Write-Host ("===== {0} : sin cambios =====" -f $f.Name) -ForegroundColor DarkGray
  }
}
