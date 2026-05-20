<#
  opus-blob-roundtrip.ps1 - Prueba que podemos RE-SERIALIZAR un Dictionary<DateTime,Decimal>
  a bytes equivalentes a los que guarda OPUS (linchpin del generador, NO escribe en la BD).
  Lee un blob, lo deserializa, lo vuelve a serializar y compara byte a byte.
#>
param(
  [Parameter(Mandatory=$true)][string]$Database,
  [Parameter(Mandatory=$true)][string]$Query,   # debe devolver 1 columna varbinary, 1 fila
  [string]$Server = "(localdb)\OpusLocal"
)
$ErrorActionPreference = "Stop"
$cn = New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$Database;Integrated Security=SSPI"
$cn.Open()
try {
  $cmd = $cn.CreateCommand(); $cmd.CommandText = $Query
  $orig = [byte[]]$cmd.ExecuteScalar()
} finally { $cn.Close() }
Write-Host "Original: $($orig.Length) bytes"

$bf = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
$ms = New-Object System.IO.MemoryStream (,$orig)
$obj = $bf.Deserialize($ms); $ms.Dispose()
Write-Host "Deserializado: $($obj.GetType().Name), $($obj.Count) entradas"

# Re-serializar el MISMO objeto
$ms2 = New-Object System.IO.MemoryStream
$bf.Serialize($ms2, $obj)
$re = $ms2.ToArray(); $ms2.Dispose()
Write-Host "Re-serializado (mismo objeto): $($re.Length) bytes"

# Reconstruir desde cero un Dictionary<DateTime,Decimal> con los mismos pares
$dic = New-Object 'System.Collections.Generic.Dictionary[datetime,decimal]'
foreach ($k in $obj.Keys) { $dic[$k] = $obj[$k] }
$ms3 = New-Object System.IO.MemoryStream
$bf.Serialize($ms3, $dic)
$built = $ms3.ToArray(); $ms3.Dispose()
Write-Host "Re-construido desde cero:       $($built.Length) bytes"

function Cmp($a,$b,$label){
  if ($a.Length -ne $b.Length) { Write-Host "  ${label}: DIFIERE en longitud ($($a.Length) vs $($b.Length))" -ForegroundColor Yellow; return }
  $diff = 0; for($i=0;$i -lt $a.Length;$i++){ if($a[$i] -ne $b[$i]){$diff++} }
  if ($diff -eq 0) { Write-Host "  ${label}: IDENTICO" -ForegroundColor Green }
  else { Write-Host "  ${label}: $diff bytes distintos de $($a.Length)" -ForegroundColor Yellow }
}
Cmp $orig $re    "orig vs re-serializado"
Cmp $orig $built "orig vs reconstruido"
