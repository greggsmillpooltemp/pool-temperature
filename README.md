# Pool Temperature

Simple public pool-temperature page powered by a Govee H5310 reading.

## Local Update

```powershell
powershell -ExecutionPolicy Bypass -File .\update-pool-temperature.ps1 -Email "greggsmillpooltemp@gmail.com"
```

The script writes `public/pool-temperature.json`, and `public/index.html` displays it.

## GitHub Updates

GitHub Actions keeps the public temperature file current. The scheduled workflow
runs every six hours, logs into Govee once, and reuses that session for hourly
temperature refreshes during the run. This keeps the widget current for the
community while avoiding repeated password logins that can trigger account
safety restrictions.

The workflow runs from the schedule or from manual dispatch only. Code pushes do
not query Govee, which prevents ordinary repo updates from causing extra login
attempts.

## GitHub Secrets

Add these repository secrets before running the workflow:

- `GOVEE_EMAIL`
- `GOVEE_PASSWORD`

GitHub Pages should be configured to deploy from GitHub Actions.
