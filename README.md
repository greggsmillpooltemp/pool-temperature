# Pool Temperature

Simple public pool-temperature page powered by a Govee H5310 reading.

## Local Update

```powershell
powershell -ExecutionPolicy Bypass -File .\update-pool-temperature.ps1 -Email "greggsmillpooltemp@gmail.com"
```

The script writes `public/pool-temperature.json`, and `public/index.html` displays it.

## GitHub Updates

GitHub Actions keeps the public temperature file current. The scheduled workflow
wakes up every 30 minutes so GitHub has multiple chances to run it, but it only
contacts Govee when the published JSON is about 2 hours old. Most scheduled
runs finish quickly after checking the public JSON and do not log into Govee.

The workflow runs from the schedule or from manual dispatch only. Code pushes do
not query Govee, which prevents ordinary repo updates from causing extra login
attempts. The updater does not store Govee auth tokens in GitHub Actions cache.

## GitHub Secrets

Add these repository secrets before running the workflow:

- `GOVEE_EMAIL`
- `GOVEE_PASSWORD`
- `GOVEE_CODE` if Govee asks for an email verification code
- `WORKFLOW_DISPATCH_TOKEN`

GitHub Pages should be configured to deploy from GitHub Actions.
