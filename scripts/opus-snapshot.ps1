<#
  opus-snapshot.ps1 - Fotografia el estado de programacion de una BD OPUS Modulo 1.
  Corre cada template de scripts\sql\*.sql contra la BD y guarda el resultado en
  scripts\snapshots\<Label>\<nombre>.txt (texto plano, BLOBs en hex).

  Uso:
    .\opus-snapshot.ps1 -Label antes  -Database "C:\...\SANDBOX.MDF"
    (haces UNA accion en OPUS, guardas y cierras)
    .\opus-snapshot.ps1 -Label despues -Database "C:\...\SANDBOX.MDF"
    .\opus-diff.ps1 -Before antes -After despues
#>
param(
  [Parameter(Mandatory=$true)][string]$Label,
  [Parameter(Mandatory=$true)][string]$Database,
  [string]$Server = "(localdb)\OpusLocal"
)
$ErrorActionPreference = "Stop"
$sqlDir   = Join-Path $PSScriptRoot "sql"
$outDir   = Join-Path $PSScriptRoot "snapshots\$Label"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$templates = Get-ChildItem $sqlDir -Filter *.sql | Sort-Object Name
foreach ($tpl in $templates) {
  $name    = [IO.Path]::GetFileNameWithoutExtension($tpl.Name)
  $tmpSql  = Join-Path $env:TEMP "opus_$name.sql"
  $body    = "USE [$Database];`r`n" + (Get-Content $tpl.FullName -Raw)
  Set-Content -Path $tmpSql -Value $body -Encoding UTF8
  $out     = Join-Path $outDir "$name.txt"
  # -y0 -Y0: no truncar hex largos (excluyente con -W) | -s '|': separador | -E: trusted
  & sqlcmd -S $Server -E -i $tmpSql -o $out -s "|" -y 0 -Y 0
  Remove-Item $tmpSql -ErrorAction SilentlyContinue
  Write-Host ("  [ok] {0,-14} -> {1}" -f $name, (Split-Path $out -Leaf))
}
Write-Host "Snapshot '$Label' guardado en: $outDir"
