param(
  [string]$Email,
  [string]$Password,
  [string]$Code,
  [string]$ClientId,
  [switch]$DumpRaw
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
$clientId = if ($ClientId) { $ClientId } else { New-ClientId $Email }
$userAgent = "GoveeHome/$appVersion (com.ihoment.GoVeeSensor; build:8; iOS 26.5.0) Alamofire/5.11.0"
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
  "User-Agent" = $userAgent
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

  Write-Host ""
  Write-Host "Govee requested email verification. Check your email for a code, then rerun:"
  Write-Host ".\test-govee-pool.ps1 -Email `"$Email`" -Code YOUR_CODE"
  exit 2
}

if (-not $login.client -or -not $login.client.token) {
  throw "Login did not return a token. Status: $($login.status) Message: $($login.message)"
}

$token = $login.client.token
if ($login.client.client) {
  $clientId = $login.client.client
}

$deviceHeaders = $baseHeaders.Clone()
$deviceHeaders["Authorization"] = "Bearer $token"
$deviceHeaders["clientId"] = $clientId
$deviceHeaders["timestamp"] = ([double][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000).ToString("0.000000", [System.Globalization.CultureInfo]::InvariantCulture)

$deviceLists = @()
foreach ($request in @(
  @{ method = "Get"; uri = "https://app2.govee.com/bff-app/v1/device/list"; body = $null },
  @{ method = "Get"; uri = "https://app2.govee.com/device/rest/devices/v1/list"; body = $null },
  @{ method = "Post"; uri = "https://app2.govee.com/device/rest/devices/v1/list"; body = $null },
  @{ method = "Post"; uri = "https://app2.govee.com/device/rest/devices/v1/list"; body = @{} },
  @{ method = "Post"; uri = "https://app2.govee.com/device/rest/devices/v1/list"; body = @{ client = $clientId } }
)) {
  try {
    $response = Invoke-GoveeJson $request.method $request.uri $deviceHeaders $request.body
    $deviceLists += [PSCustomObject]@{
      method = $request.method
      uri = $request.uri
      response = $response
      devices = Get-GoveeDevicesFromResponse $response
    }
  } catch {
    $deviceLists += [PSCustomObject]@{
      method = $request.method
      uri = $request.uri
      error = $_.Exception.Message
      devices = @()
    }
  }
}

$devices = @($deviceLists | ForEach-Object { $_.devices } | Where-Object { $_ })

$detailCalls = @()
foreach ($device in $devices) {
  $deviceId = $device.deviceId
  $sku = $device.sku
  $deviceAddress = $device.device
  if (-not $deviceId) {
    continue
  }

  $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $escapedDevice = [System.Uri]::EscapeDataString($deviceAddress)

  foreach ($request in @(
    @{ method = "Get"; uri = "https://app2.govee.com/bff-app/v1/device/detail?deviceId=$deviceId"; body = $null },
    @{ method = "Get"; uri = "https://app2.govee.com/bff-app/v1/device/detail?deviceId=$deviceId&sku=$sku"; body = $null },
    @{ method = "Get"; uri = "https://app2.govee.com/th/rest/devices/v1/multi-datas?currentTime=$nowMs&device=$escapedDevice&sku=$sku"; body = $null },
    @{ method = "Post"; uri = "https://app2.govee.com/bff-app/v1/device/detail"; body = @{ deviceId = $deviceId; sku = $sku } },
    @{ method = "Post"; uri = "https://app2.govee.com/device/rest/devices/v1/detail"; body = @{ deviceId = $deviceId; sku = $sku } },
    @{ method = "Post"; uri = "https://app2.govee.com/device/rest/device/v1/detail"; body = @{ deviceId = $deviceId; sku = $sku } }
  )) {
    try {
      $response = Invoke-GoveeJson $request.method $request.uri $deviceHeaders $request.body
      $detailCalls += [PSCustomObject]@{
        method = $request.method
        uri = $request.uri
        response = $response
      }
    } catch {
      $detailCalls += [PSCustomObject]@{
        method = $request.method
        uri = $request.uri
        error = $_.Exception.Message
      }
    }
  }

  try {
    foreach ($windowMinutes in @(15, 60, 360, 1440, 10080)) {
      $taskBody = @{
        fileType = "zip"
        device = $deviceAddress
        shared = 0
        sku = $sku
        timeRange = @{
          start = $nowMs - ($windowMinutes * 60 * 1000)
          end = $nowMs
        }
      }
      $taskResponse = Invoke-GoveeJson "Post" "https://app2.govee.com/th/v2/data-tasks" $deviceHeaders $taskBody
      $detailCalls += [PSCustomObject]@{
        method = "Post"
        uri = "https://app2.govee.com/th/v2/data-tasks?windowMinutes=$windowMinutes"
        response = $taskResponse
      }

      $taskIds = @($taskResponse.data.taskIds)
      if ($taskIds.Count -gt 0) {
        $taskIdsText = [string]::Join(",", $taskIds)
        for ($i = 0; $i -lt 8; $i++) {
          if ($i -gt 0) {
            Start-Sleep -Seconds 2
          }

          $linksResponse = Invoke-GoveeJson "Get" "https://app2.govee.com/th/v2/data-links?taskIds=$taskIdsText" $deviceHeaders
          $detailCalls += [PSCustomObject]@{
            method = "Get"
            uri = "https://app2.govee.com/th/v2/data-links?taskIds=$taskIdsText&windowMinutes=$windowMinutes"
            response = $linksResponse
          }

          $linksJson = $linksResponse | ConvertTo-Json -Depth 40
          if ($linksJson -match '"links"\s*:\s*\[\s*".+?"') {
            break
          }
        }
      }
    }
  } catch {
    $detailCalls += [PSCustomObject]@{
      method = "TaskFlow"
      uri = "https://app2.govee.com/th/v2/data-tasks"
      error = $_.Exception.Message
    }
  }
}

if ($devices.Count -eq 0) {
  Write-Host "Login worked, but app device list returned no devices."
  $deviceLists | ConvertTo-Json -Depth 20
  exit 1
}

if ($DumpRaw) {
  $safeLists = @($deviceLists | ForEach-Object {
    $list = $_
    $safeDevices = @($list.devices) | ForEach-Object {
      $device = $_ | Select-Object * -ExcludeProperty bindCode, secretCode
      if ($device.deviceExt -and $device.deviceExt.deviceSettings) {
        $settingsObj = ConvertFrom-GoveeJsonString $device.deviceExt.deviceSettings
        if ($settingsObj) {
          foreach ($field in @("wifiMac", "bleAddress", "address", "device", "topic", "secretCode")) {
            if ($settingsObj.PSObject.Properties.Name -contains $field) {
              $settingsObj.$field = "[redacted]"
            }
          }
          if ($settingsObj.gatewayInfo) {
            foreach ($field in @("device", "address", "topic", "secretCode")) {
              if ($settingsObj.gatewayInfo.PSObject.Properties.Name -contains $field) {
                $settingsObj.gatewayInfo.$field = "[redacted]"
              }
            }
          }
          $device.deviceExt | Add-Member -NotePropertyName "deviceSettingsParsed" -NotePropertyValue $settingsObj -Force
          $device.deviceExt.deviceSettings = "[parsed below]"
        } else {
          $device.deviceExt.deviceSettings = "[unparsed]"
        }
      }
      $device
    }
    [PSCustomObject]@{
      method = $list.method
      uri = $list.uri
      error = $list.error
      devices = $safeDevices
    }
  })

  @(
    $safeLists
    [PSCustomObject]@{
    detailCalls = $detailCalls
    }
  ) | ConvertTo-Json -Depth 60
  exit 0
}

$results = foreach ($device in $devices) {
  $lastData = $null
  if ($device.deviceExt -and $device.deviceExt.lastDeviceData) {
    $lastData = ConvertFrom-GoveeJsonString $device.deviceExt.lastDeviceData
  }

  $settingsData = $null
  if ($device.deviceExt -and $device.deviceExt.deviceSettings) {
    $settingsObj = ConvertFrom-GoveeJsonString $device.deviceExt.deviceSettings
    foreach ($propertyName in @("lastDeviceData", "deviceData", "lastData", "state", "data")) {
      $value = if ($settingsObj) { $settingsObj.$propertyName } else { $device.deviceExt.deviceSettings.$propertyName }
      if ($value) {
        $settingsData = ConvertFrom-GoveeJsonString $value
        if ($settingsData) { break }
      }
    }
  }

  if (-not $lastData -and $settingsData) {
    $lastData = $settingsData
  }

  if (-not $lastData -or $null -eq $lastData.tem) {
    $multiDataCall = $detailCalls | Where-Object {
      $_.uri -like "https://app2.govee.com/th/rest/devices/v1/multi-datas*"
    } | Select-Object -First 1

    if ($multiDataCall -and $multiDataCall.response) {
      $multiJson = $multiDataCall.response | ConvertTo-Json -Depth 50
      $tempMatch = [regex]::Match($multiJson, '"tem"\s*:\s*(-?\d+(\.\d+)?)')
      if ($tempMatch.Success) {
        $lastData = [PSCustomObject]@{
          online = $true
          tem = [double]$tempMatch.Groups[1].Value
        }
      }
    }
  }

  $tempF = $null
  $rawTem = $null
  if ($lastData -and $null -ne $lastData.tem) {
    $rawTem = [double]$lastData.tem
    $tempC = $rawTem / 100.0
    $tempF = [Math]::Round(($tempC * 9 / 5) + 32, 1)
  }

  [PSCustomObject]@{
    name = $device.deviceName
    sku = $device.sku
    deviceId = $device.deviceId
    online = if ($lastData) { $lastData.online } else { $null }
    tempF = $tempF
    rawTem = $rawTem
    lastTime = if ($lastData -and $lastData.lastTime) {
      ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$lastData.lastTime)).LocalDateTime
    } else {
      $null
    }
  }
}

$results |
  Sort-Object name, sku, deviceId, tempF, rawTem, lastTime -Unique |
  Sort-Object @{ Expression = { if ($_.tempF) { 0 } else { 1 } } }, name |
  Format-Table -AutoSize
