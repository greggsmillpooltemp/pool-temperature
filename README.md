# Pool Temperature

Simple public pool-temperature page powered by a Govee H5310 reading.

## Local Update

```powershell
powershell -ExecutionPolicy Bypass -File .\update-pool-temperature.ps1 -Email "greggsmillpooltemp@gmail.com"
```

The script writes `public/pool-temperature.json`, and `public/index.html` displays it.

## GitHub Updates

GitHub Actions keeps the public temperature file current. The scheduled workflow
runs every three hours, logs into Govee once, and reuses that session for hourly
temperature refreshes during the run. This keeps the widget current for the
community while avoiding repeated password logins that can trigger account
safety restrictions.

The workflow runs from the schedule or from manual dispatch only. Code pushes do
not query Govee, which prevents ordinary repo updates from causing extra login
attempts.

After each hourly refresh batch finishes, the workflow uses
`WORKFLOW_DISPATCH_TOKEN` to start the next batch. The schedule remains as a
backup starter if GitHub misses or delays the handoff.

## GitHub Secrets

Add these repository secrets before running the workflow:

- `GOVEE_EMAIL`
- `GOVEE_PASSWORD`
- `WORKFLOW_DISPATCH_TOKEN`

GitHub Pages should be configured to deploy from GitHub Actions.
