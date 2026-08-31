#!/usr/bin/env bash
# Pull (or reuse) the published image and start Twenty behind Plesk.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PACK_DIR}/.env"

cd "${PACK_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "No .env yet. Copying .env.example — edit it before this script will start containers."
  cp "${PACK_DIR}/.env.example" "${ENV_FILE}"
fi

# Refuse to boot with the committed placeholders.
if grep -Eq 'replace_me_|crm\\.example\\.com' "${ENV_FILE}"; then
  echo "Refusing to deploy: .env still contains example placeholders." >&2
  echo "Set SERVER_URL, ENCRYPTION_KEY, and PG_DATABASE_PASSWORD, then re-run." >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

if [[ -z "${ENCRYPTION_KEY:-}" || -z "${PG_DATABASE_PASSWORD:-}" || -z "${SERVER_URL:-}" ]]; then
  echo "ENCRYPTION_KEY, PG_DATABASE_PASSWORD, and SERVER_URL are required." >&2
  exit 1
fi

if [[ "${SERVER_URL}" != https://* && "${SERVER_URL}" != http://* ]]; then
  echo "SERVER_URL must include http:// or https://" >&2
  exit 1
fi

echo "Pulling ${TWENTY_IMAGE:-twentycrm/twenty}:${TAG:-latest} ..."
docker compose --env-file "${ENV_FILE}" pull

echo "Starting Twenty ..."
docker compose --env-file "${ENV_FILE}" up -d

echo "Waiting for twenty-server healthcheck ..."
attempts=0
until [[ "$(docker inspect --format='{{.State.Health.Status}}' twenty-server 2>/dev/null || echo starting)" == "healthy" ]]; do
  attempts=$((attempts + 1))
  if (( attempts > 180 )); then
    echo "Server did not become healthy in 3 minutes. Last logs:" >&2
    docker compose --env-file "${ENV_FILE}" logs --tail=80 server
    exit 1
  fi
  sleep 1
done

echo
echo "Twenty is healthy on ${HOST_BIND:-127.0.0.1}:${HOST_PORT:-3000}"
echo "Confirm Plesk proxies this domain to that address and SERVER_URL=${SERVER_URL}"
curl -fsS "http://${HOST_BIND:-127.0.0.1}:${HOST_PORT:-3000}/healthz"
echo
