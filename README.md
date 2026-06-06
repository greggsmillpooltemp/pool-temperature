# Pool Temperature

Simple public pool-temperature page powered by a Govee H5310 reading.

## Local Update

```powershell
powershell -ExecutionPolicy Bypass -File .\update-pool-temperature.ps1 -Email "greggsmillpooltemp@gmail.com"
```

The script writes `public/pool-temperature.json`, and `public/index.html` displays it.

## GitHub Updates

GitHub Actions keeps the public temperature file current. The scheduled workflow
runs hourly, with a backup run 30 minutes later in case GitHub skips or delays
the first schedule. Each run checks the published JSON before contacting Govee,
so the backup run exits without another Govee request when the data is already
fresh.

The updater stores the Govee session token in the GitHub Actions cache after a
successful login. Future runs try that cached token before falling back to the
password login, which reduces repeated account logins. If Govee returns a 403
rate-limit/account block, the updater records a short cooldown marker in the
cache so later scheduled runs pause instead of making the lockout worse.

The workflow runs from the schedule or from manual dispatch only. Code pushes do
not query Govee, which prevents ordinary repo updates from causing extra login
attempts.

## GitHub Secrets

Add these repository secrets before running the workflow:

- `GOVEE_EMAIL`
- `GOVEE_PASSWORD`
- `WORKFLOW_DISPATCH_TOKEN`

GitHub Pages should be configured to deploy from GitHub Actions.
