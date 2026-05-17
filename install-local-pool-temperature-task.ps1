param(
  [string]$TaskName = "Greggs Mill Pool Temperature Update",
  [int]$IntervalMinutes = 5
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $repoRoot "run-local-pool-temperature-update.ps1"

if (-not (Test-Path -LiteralPath $runner)) {
  throw "Could not find $runner"
}

if (-not [Environment]::GetEnvironmentVariable("GOVEE_EMAIL", "User") -or
    -not [Environment]::GetEnvironmentVariable("GOVEE_PASSWORD", "User")) {
  throw @"
Set GOVEE_EMAIL and GOVEE_PASSWORD first, then rerun this installer.

Example:
[Environment]::SetEnvironmentVariable("GOVEE_EMAIL", "your@email.com", "User")
[Environment]::SetEnvironmentVariable("GOVEE_PASSWORD", "your-password", "User")
"@
}

$action = New-ScheduledTaskAction `
  -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runner`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
  -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
  -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -MultipleInstances IgnoreNew

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -Description "Updates the Gregg's Mill pool temperature JSON and deploys it through GitHub Pages." `
  -Force | Out-Null

Write-Host "Installed scheduled task: $TaskName"
Write-Host "It will run every $IntervalMinutes minutes while this Windows user profile is available."
