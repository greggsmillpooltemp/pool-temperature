param(
  [string]$Email,
  [string]$Password,
  [string]$Code,
  [string]$OutputPath = ".\public\pool-temperature.json"
)

$ErrorActionPreference = "Stop"

function New-ClientId([string]$email) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($email.Trim().ToLowerInvariant())
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $hash = $sha.ComputeHash($bytes)
  return "cdx" + ([BitConverter]::ToString($hash).Replace("-", "").ToLowerInvariant().Substring(0, 29))
}

function Invoke-GoveeJson($Method, $Uri, $Headers, $Body = $null) {
  $params = @{
    Method = $Method
    Uri = $Uri
    Headers = $Headers
    TimeoutSec = 30
    WebSession = $script:GoveeSession
  }
  if ($null -ne $Body) {
    $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
    $params.ContentType = "application/json"
  } elseif ($Method -eq "Post") {
    $params.ContentType = "application/json"
  }
  return Invoke-RestMethod @params
}

function ConvertFrom-GoveeJsonString($Value) {
  if (-not $Value -or $Value -isnot [string]) {
    return $null
  }

  foreach ($candidate in @($Value, ($Value -replace '\\"', '"'))) {
    try {
      return $candidate | ConvertFrom-Json
    } catch {
      continue
    }
  }

  return $null
}

function Get-GoveeDevicesFromResponse($Response) {
  if (-not $Response) {
    return @()
  }

  if ($Response.PSObject.Properties.Name -contains "devices") {
    return @($Response.devices)
  }

  if ($Response.data -and ($Response.data.PSObject.Properties.Name -contains "devices")) {
    return @($Response.data.devices)
  }

  return @()
}

if (-not $Email) {
  $Email = Read-Host "Govee account email"
}

if (-not $Password) {
  $securePassword = Read-Host "Govee account password" -AsSecureString
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
  try {
    $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

$appVersion = "7.4.40"
$clientId = New-ClientId $Email
$script:GoveeSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$baseHeaders = @{
  "appVersion" = $appVersion
  "clientId" = $clientId
  "clientType" = "1"
  "iotVersion" = "0"
  "timestamp" = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()).ToString()
  "envId" = "0"
  "sysVersion" = "26.5.0"
  "timezone" = [System.TimeZoneInfo]::Local.Id
  "country" = "US"
  "User-Agent" = "GoveeHome/$appVersion (com.ihoment.GoVeeSensor; build:8; iOS 26.5.0) Alamofire/5.11.0"
  "Accept" = "*/*"
  "Accept-Language" = "en"
}

$loginBody = @{
  email = $Email
  password = $Password
  client = $clientId
}
if ($Code) {
  $loginBody.code = $Code
}

$login = Invoke-GoveeJson "Post" "https://app2.govee.com/account/rest/account/v2/login" $baseHeaders $loginBody
if ($login.status -eq 454) {
  Invoke-GoveeJson "Post" "https://app2.govee.com/account/rest/account/v1/verification" $baseHeaders @{
    type = 8
    email = $Email
  } | Out-Null
  throw "Govee requested email verification. Rerun with -Code using the code sent to $Email."
}

if (-not $login.client -or -not $login.client.token) {
  throw "Login did not return a token. Status: $($login.status) Message: $($login.message)"
}

if ($login.client.client) {
  $clientId = $login.client.client
}

$deviceHeaders = $baseHeaders.Clone()
$deviceHeaders["Authorization"] = "Bearer $($login.client.token)"
$deviceHeaders["clientId"] = $clientId
$deviceHeaders["timestamp"] = ([double][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000).ToString("0.000000", [System.Globalization.CultureInfo]::InvariantCulture)

$responses = @(
  Invoke-GoveeJson "Get" "https://app2.govee.com/bff-app/v1/device/list" $deviceHeaders
  Invoke-GoveeJson "Post" "https://app2.govee.com/device/rest/devices/v1/list" $deviceHeaders
)

$readings = foreach ($response in $responses) {
  foreach ($device in (Get-GoveeDevicesFromResponse $response)) {
    if ($device.sku -ne "H5310") {
      continue
    }

    $lastData = ConvertFrom-GoveeJsonString $device.deviceExt.lastDeviceData
    if ($lastData -and $null -ne $lastData.tem) {
      $rawTem = [double]$lastData.tem
      $tempC = $rawTem / 100.0
      [PSCustomObject]@{
        deviceName = $device.deviceName
        sku = $device.sku
        tempF = [Math]::Round(($tempC * 9 / 5) + 32, 1)
        tempC = [Math]::Round($tempC, 1)
        rawTem = $rawTem
        online = $lastData.online
        battery = $lastData.battery
        lastReadingAt = if ($lastData.lastTime) {
          [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$lastData.lastTime).ToLocalTime().ToString("o")
        } else {
          $null
        }
        updatedAt = [DateTimeOffset]::Now.ToString("o")
      }
    }
  }
}

$reading = $readings |
  Sort-Object deviceName, sku, tempF, rawTem, lastReadingAt -Unique |
  Sort-Object @{ Expression = { if ($_.lastReadingAt) { 0 } else { 1 } } }, lastReadingAt -Descending |
  Select-Object -First 1

if (-not $reading) {
  throw "No H5310 temperature reading found."
}

$outputFile = Resolve-Path -LiteralPath (Split-Path -Parent $OutputPath) -ErrorAction SilentlyContinue
if (-not $outputFile) {
  New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) | Out-Null
}

$reading | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$reading | Format-Table -AutoSize
