# Pool Temperature

Simple public pool-temperature page powered by a Govee H5310 reading.

## Local Update

```powershell
powershell -ExecutionPolicy Bypass -File .\update-pool-temperature.ps1 -Email "greggsmillpooltemp@gmail.com"
```

The script writes `public/pool-temperature.json`, and `public/index.html` displays it.

## GitHub Updates

GitHub Actions keeps the public temperature file current. The scheduled workflow
creates staggered update jobs at 0, 5, 10, 15, 20, and 25 minutes, and each job
reads Govee and deploys GitHub Pages directly.

For continuous GitHub-hosted updates, add one more repository secret:

- `WORKFLOW_DISPATCH_TOKEN`

This must be a GitHub token that can run workflows for this repository. The
workflow uses it to start the next updater run after each half-hour batch.

## GitHub Secrets

Add these repository secrets before running the workflow:

- `GOVEE_EMAIL`
- `GOVEE_PASSWORD`
- `WORKFLOW_DISPATCH_TOKEN`

GitHub Pages should be configured to deploy from GitHub Actions.
