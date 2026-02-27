#!/usr/bin/env bash
set -euo pipefail

DEPLOY_PATH="${DEPLOY_PATH:-/var/www/amazon_hackhathon}"
APP_SERVICE_NAME="${APP_SERVICE_NAME:-app}"

cd "$DEPLOY_PATH"

echo "[deploy] syncing repository"
git fetch origin
git checkout main
git pull --ff-only origin main

if [[ ! -f docker-compose.yml ]]; then
  echo "[deploy] ERROR: docker-compose.yml not found in $DEPLOY_PATH"
  exit 1
fi

if [[ ! -f .env.production ]]; then
  echo "[deploy] ERROR: .env.production not found in $DEPLOY_PATH"
  exit 1
fi

if ! grep -Eq '^DAYTONA_API_KEY=' .env.production; then
  echo "[deploy] ERROR: DAYTONA_API_KEY is missing in .env.production"
  exit 1
fi

if ! grep -Eq '^(DAYTONA_SERVER_URL|DAYTONA_API_URL)=' .env.production; then
  echo "[deploy] ERROR: DAYTONA_SERVER_URL or DAYTONA_API_URL is missing in .env.production"
  exit 1
fi

echo "[deploy] validating compose file"
docker compose --env-file .env.production config -q

echo "[deploy] starting services"
docker compose --env-file .env.production up -d --build --remove-orphans

echo "[deploy] waiting for app container"
APP_CONTAINER_ID="$(docker compose ps -q "$APP_SERVICE_NAME" || true)"
if [[ -z "$APP_CONTAINER_ID" ]]; then
  echo "[deploy] ERROR: service '$APP_SERVICE_NAME' not found or not running"
  docker compose ps
  exit 1
fi

if ! docker exec "$APP_CONTAINER_ID" /bin/sh -lc 'env | grep -E "^(DAYTONA_SERVER_URL|DAYTONA_API_URL|DAYTONA_API_KEY)=" >/dev/null'; then
  echo "[deploy] ERROR: required Daytona env vars are not present inside app container"
  docker exec "$APP_CONTAINER_ID" /bin/sh -lc 'env | grep -E "^DAYTONA_" || true'
  exit 1
fi

echo "[deploy] app container has Daytona env vars"
docker compose ps

if command -v nginx >/dev/null 2>&1; then
  sudo nginx -t
  sudo systemctl reload nginx
fi

echo "[deploy] complete"
