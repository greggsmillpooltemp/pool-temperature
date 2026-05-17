# Pool Temperature

Simple public pool-temperature page powered by a Govee H5310 reading.

## Local Update

```powershell
powershell -ExecutionPolicy Bypass -File .\update-pool-temperature.ps1 -Email "greggsmillpooltemp@gmail.com"
```

The script writes `public/pool-temperature.json`, and `public/index.html` displays it.

## GitHub Updates

GitHub Actions keeps the public temperature file current. The scheduled workflow
runs every six hours, reads Govee once, and deploys GitHub Pages directly. This
keeps the widget current enough for the community while avoiding repeated Govee
logins that can trigger account safety restrictions.

## GitHub Secrets

Add these repository secrets before running the workflow:

- `GOVEE_EMAIL`
- `GOVEE_PASSWORD`

GitHub Pages should be configured to deploy from GitHub Actions.
