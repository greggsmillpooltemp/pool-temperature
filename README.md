# Pool Temperature

Simple public pool-temperature page powered by a Govee H5310 reading.

## Local Update

```powershell
powershell -ExecutionPolicy Bypass -File .\update-pool-temperature.ps1 -Email "greggsmillpooltemp@gmail.com"
```

The script writes `public/pool-temperature.json`, and `public/index.html` displays it.

## Reliable 5-Minute Updates

GitHub Actions scheduled runs can be delayed or skipped. For steady updates,
run the updater from Windows Task Scheduler on an always-on computer:

```powershell
[Environment]::SetEnvironmentVariable("GOVEE_EMAIL", "your@email.com", "User")
[Environment]::SetEnvironmentVariable("GOVEE_PASSWORD", "your-password", "User")
powershell -ExecutionPolicy Bypass -File .\install-local-pool-temperature-task.ps1
```

The scheduled task runs `run-local-pool-temperature-update.ps1`, commits only
`public/pool-temperature.json`, and pushes it to GitHub. The GitHub workflow
then deploys that exact JSON to GitHub Pages.

## GitHub Secrets

Add these repository secrets before running the workflow:

- `GOVEE_EMAIL`
- `GOVEE_PASSWORD`

GitHub Pages should be configured to deploy from GitHub Actions.
