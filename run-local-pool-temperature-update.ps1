param(
  [string]$Email = $env:GOVEE_EMAIL,
  [string]$Password = $env:GOVEE_PASSWORD,
  [string]$Code = $env:GOVEE_CODE
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repoRoot

if (-not $Email -or -not $Password) {
  throw "Set GOVEE_EMAIL and GOVEE_PASSWORD as user environment variables before running this scheduled updater."
}

.\update-pool-temperature.ps1 -Email $Email -Password $Password -Code $Code -OutputPath ".\public\pool-temperature.json"

$status = git status --short -- public/pool-temperature.json
if (-not $status) {
  Write-Host "Pool temperature JSON did not change."
  exit 0
}

git add public/pool-temperature.json
git commit -m "Update pool temperature data"
git push origin main
