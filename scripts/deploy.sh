#!/usr/bin/env bash
# Runs ON the EC2 instance (invoked through SSM). Usage: deploy.sh <commit-sha>
set -euo pipefail

SHA="${1:?usage: deploy.sh <commit-sha>}"
NAME=app
IMAGE="aws-auto-deploy:${SHA}"

echo "==> Building ${IMAGE}"
docker build --build-arg APP_VERSION="${SHA}" -t "${IMAGE}" .

echo "==> Replacing container"
docker rm -f "${NAME}" >/dev/null 2>&1 || true
docker run -d --name "${NAME}" --restart unless-stopped -p 80:8000 "${IMAGE}"

echo "==> Waiting for /health"
for _ in $(seq 1 15); do
  if curl -fsS http://localhost/health >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "==> Verifying deployed version"
if curl -fsS http://localhost/version | grep -q "\"${SHA}\""; then
  echo "OK: ${SHA} is live and healthy"
else
  echo "FAIL: deployed version does not match ${SHA}" >&2
  docker ps -a --filter "name=${NAME}" >&2
  docker logs --tail 50 "${NAME}" >&2 || true
  exit 1
fi

# Keep disk usage in check on a small instance
docker image prune -f >/dev/null
