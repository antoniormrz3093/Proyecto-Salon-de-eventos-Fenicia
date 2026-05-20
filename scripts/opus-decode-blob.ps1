<#
  opus-decode-blob.ps1 - Deserializa columnas varbinary de OPUS (programacion) con BinaryFormatter.
  Funciona porque las distribuciones son tipos del framework .NET:
    DistribucionSemanal/Quincenal/Mensual = Dictionary<DateTime, Decimal>
  Requiere Windows PowerShell 5.1 (.NET Framework, BinaryFormatter disponible).

  Uso (lee directo de la BD, sin tocar nada):
    .\opus-decode-blob.ps1 -Database "C:\...\X.MDF" `
        -Query "SELECT TOP 1 DistribucionSemanal FROM RenglonDePresupuesto WHERE DistribucionSemanal IS NOT NULL"
#>
param(
  [Parameter(Mandatory=$true)][string]$Database,
  [Parameter(Mandatory=$true)][string]$Query,
  [string]$Server = "(localdb)\OpusLocal"
)
$ErrorActionPreference = "Stop"
$cs = "Server=$Server;Database=$Database;Integrated Security=SSPI"
$cn = New-Object System.Data.SqlClient.SqlConnection $cs
$cn.Open()
try {
  $cmd = $cn.CreateCommand(); $cmd.CommandText = $Query
  $rd  = $cmd.ExecuteReader()
  $bf  = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
  $n = 0
  while ($rd.Read()) {
    $n++
    if ($rd.IsDBNull(0)) { Write-Host "[$n] NULL"; continue }
    $bytes = $rd.GetValue(0)
    $ms = New-Object System.IO.MemoryStream (,[byte[]]$bytes)
    try {
      $obj = $bf.Deserialize($ms)
      Write-Host ("[$n] Tipo: {0}" -f $obj.GetType().FullName)
      if ($obj -is [System.Collections.IDictionary]) {
        Write-Host ("     Entradas: {0}" -f $obj.Count)
        foreach ($k in ($obj.Keys | Sort-Object)) {
          Write-Host ("       {0} => {1}" -f $k, $obj[$k])
        }
      } elseif ($obj -is [System.Collections.IEnumerable]) {
        Write-Host ("     Elementos: {0}" -f @($obj).Count)
        foreach ($e in $obj) { Write-Host ("       $e") }
      } else {
        Write-Host ("     Valor: $obj")
      }
    } catch {
      Write-Host ("[$n] ERR deserialize: {0}" -f $_.Exception.Message)
    } finally { $ms.Dispose() }
  }
} finally { $cn.Close() }
