# amazon_hackhathon

Deployment bootstrap for AWS + Cloudflare with CI/CD and Daytona sandbox env wiring.

## Current repository status

This repository is currently a minimal scaffold and does not yet include runnable application code.

## Included deployment assets

- `.github/workflows/deploy.yml`: deploys on push to `main`, writes `.env.production` from GitHub secrets, and runs `scripts/deploy.sh`.
- `scripts/deploy.sh`: validates Daytona env vars, validates Compose config, deploys services, and fails fast if app container is missing Daytona env values.
- `docs/aws-cloudflare-deploy.md`: manual AWS + Cloudflare setup flow and troubleshooting.

## Required GitHub secrets

- `EC2_HOST`
- `EC2_USER`
- `EC2_SSH_KEY`
- `EC2_PORT`
- `DEPLOY_PATH`
- `DAYTONA_API_KEY`
- `DAYTONA_SERVER_URL`
- `DAYTONA_TARGET` (optional, if your app uses it)
- `APP_SERVICE_NAME` (optional, defaults to `app`)
