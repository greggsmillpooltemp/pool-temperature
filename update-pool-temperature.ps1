param(
  [string]$Email,
  [string]$Password,
  [string]$Code,
  [string]$AuthToken,
  [string]$ClientId,
  [switch]$ExportAuthEnvironment,
  [string]$AuthCachePath,
  [string]$OutputPath = ".\public\pool-temperature.json"
)

$ErrorActionPreference = "Stop"

function New-ClientId([string]$email) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($email.Trim().ToLowerInvariant())
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $hash = $sha.ComputeHash($bytes)
  return "cdx" + ([BitConverter]::ToString($hash).Replace("-", "").ToLowerInvariant().Substring(0, 29))
}

function Save-GoveeAuthCache([string]$Path, [string]$Email, [string]$ClientId, [string]$AuthToken, [string]$BlockedUntil = $null) {
  if (-not $Path) {
    return
  }

  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  [PSCustomObject]@{
    email = $Email
    clientId = $ClientId
    authToken = $AuthToken
    blockedUntil = $BlockedUntil
    savedAt = [DateTimeOffset]::UtcNow.ToString("o")
  } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-GoveeAuthCache([string]$Path, [string]$Email) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  try {
    $cache = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($cache.email -and $Email -and $cache.email -ne $Email) {
      return $null
    }
    return $cache
  } catch {
    Write-Warning "Could not read Govee auth cache: $($_.Exception.Message)"
    return $null
  }
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
  try {
    return Invoke-RestMethod @params
  } catch {
    $statusCode = $null
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
      $statusCode = [int]$_.Exception.Response.StatusCode
    }

    if ($statusCode -eq 403) {
      $blockedUntil = [DateTimeOffset]::UtcNow.AddHours(4).ToString("o")
      Save-GoveeAuthCache $AuthCachePath $Email $ClientId $AuthToken $blockedUntil
      throw "Govee returned 403 Forbidden. This usually means the account or endpoint is temporarily rate-limited/blocked. Wait for the Govee cooldown before retrying; repeated manual re-runs can extend the block."
    }

    throw
  }
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

function Get-GoveeReadingFromLastData($Device, $LastData, $Source) {
  if (-not $LastData -or $null -eq $LastData.tem) {
    return $null
  }

  $rawTem = [double]$LastData.tem
  $tempC = $rawTem / 100.0
  [PSCustomObject]@{
    deviceName = $Device.deviceName
    sku = $Device.sku
    tempF = [Math]::Round(($tempC * 9 / 5) + 32, 1)
    tempC = [Math]::Round($tempC, 1)
    rawTem = $rawTem
    online = $LastData.online
    battery = $LastData.battery
    source = $Source
    lastReadingAt = if ($LastData.lastTime) {
      [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$LastData.lastTime).ToLocalTime().ToString("o")
    } else {
      $null
    }
    updatedAt = [DateTimeOffset]::Now.ToString("o")
  }
}

function Get-GoveeMultiDataReading($Device, $Headers) {
  if (-not $Device.device -or -not $Device.sku) {
    return $null
  }

  try {
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $escapedDevice = [System.Uri]::EscapeDataString($Device.device)
    $uri = "https://app2.govee.com/th/rest/devices/v1/multi-datas?currentTime=$nowMs&device=$escapedDevice&sku=$($Device.sku)"
    $response = Invoke-GoveeJson "Get" $uri $Headers
    $json = $response | ConvertTo-Json -Depth 60 -Compress

    $tempMatch = [regex]::Match($json, '"tem"\s*:\s*(-?\d+(\.\d+)?)')
    if (-not $tempMatch.Success) {
      return $null
    }

    $lastTime = $null
    $timeMatch = [regex]::Match($json, '"lastTime"\s*:\s*(\d+)')
    if ($timeMatch.Success) {
      $lastTime = [int64]$timeMatch.Groups[1].Value
    }

    $online = $true
    $onlineMatch = [regex]::Match($json, '"online"\s*:\s*(true|false)')
    if ($onlineMatch.Success) {
      $online = [bool]::Parse($onlineMatch.Groups[1].Value)
    }

    $lastData = [PSCustomObject]@{
      tem = [double]$tempMatch.Groups[1].Value
      online = $online
      lastTime = $lastTime
    }

    $reading = Get-GoveeReadingFromLastData $Device $lastData "multi-datas"
    if (-not $reading.lastReadingAt) {
      $reading.lastReadingAt = $reading.updatedAt
    }
    return $reading
  } catch {
    Write-Warning "Could not read multi-datas for $($Device.deviceName): $($_.Exception.Message)"
    return $null
  }
}

if (-not $Email) {
  $Email = Read-Host "Govee account email"
}

if (-not $AuthToken -and -not $Password) {
  $securePassword = Read-Host "Govee account password" -AsSecureString
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
  try {
    $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

$appVersion = "7.4.40"
if (-not $ClientId) {
  $ClientId = New-ClientId $Email
}
$script:GoveeSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$baseHeaders = @{
  "appVersion" = $appVersion
  "clientId" = $ClientId
  "clientType" = "1"
  "iotVersion" = "0"
  "timestamp" = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()).ToString()
  "envId" = "0"
  "sysVersion" = "26.5.0"
  "timezone" = if ($env:TZ) { $env:TZ } else { [System.TimeZoneInfo]::Local.Id }
  "country" = "US"
  "User-Agent" = "GoveeHome/$appVersion (com.ihoment.GoVeeSensor; build:8; iOS 26.5.0) Alamofire/5.11.0"
  "Accept" = "*/*"
  "Accept-Language" = "en"
}

$authCache = Read-GoveeAuthCache $AuthCachePath $Email
if ($authCache -and $authCache.blockedUntil) {
  $blockedUntil = [DateTimeOffset]::Parse([string]$authCache.blockedUntil)
  if ($blockedUntil -gt [DateTimeOffset]::UtcNow) {
    throw "Govee refresh is in cooldown until $($blockedUntil.ToString("u")) after a recent 403 response."
  }
}

if (-not $AuthToken -and $authCache -and $authCache.authToken) {
  $AuthToken = [string]$authCache.authToken
  if ($authCache.clientId) {
    $ClientId = [string]$authCache.clientId
  }
  Write-Host "Using cached Govee auth token."
  Write-Host "::add-mask::$AuthToken"
  Write-Host "::add-mask::$ClientId"
}

if (-not $AuthToken) {
  $loginBody = @{
    email = $Email
    password = $Password
    client = $ClientId
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

  $AuthToken = $login.client.token
  if ($login.client.client) {
    $ClientId = $login.client.client
  }

  Save-GoveeAuthCache $AuthCachePath $Email $ClientId $AuthToken

  if ($ExportAuthEnvironment -and $env:GITHUB_ENV) {
    "GOVEE_AUTH_TOKEN=$AuthToken" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    "GOVEE_CLIENT_ID=$ClientId" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    Write-Host "::add-mask::$AuthToken"
    Write-Host "::add-mask::$ClientId"
  }
}

$deviceHeaders = $baseHeaders.Clone()
$deviceHeaders["Authorization"] = "Bearer $AuthToken"
$deviceHeaders["clientId"] = $ClientId
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
    $listReading = Get-GoveeReadingFromLastData $device $lastData "device-list"
    if ($listReading) {
      $listReading
    }

    $multiReading = Get-GoveeMultiDataReading $device $deviceHeaders
    if ($multiReading) {
      $multiReading
    }
  }
}

$reading = $readings |
  Sort-Object deviceName, sku, source, tempF, rawTem, lastReadingAt -Unique |
  Sort-Object @{ Expression = { if ($_.source -eq "multi-datas") { 0 } else { 1 } } }, @{ Expression = { if ($_.lastReadingAt) { 0 } else { 1 } } }, lastReadingAt -Descending |
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
