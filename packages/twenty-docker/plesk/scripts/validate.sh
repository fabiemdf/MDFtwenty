#!/usr/bin/env bash
# Static checks for the Plesk pack. Safe to run without Docker or a droplet.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "OK: $*"
}

test -f "${PACK_DIR}/docker-compose.yml" || fail "docker-compose.yml missing"
test -f "${PACK_DIR}/.env.example" || fail ".env.example missing"
test -f "${PACK_DIR}/nginx-additional-directives.conf" || fail "nginx snippet missing"
test -f "${PACK_DIR}/README.md" || fail "README.md missing"

COMPOSE="$(cat "${PACK_DIR}/docker-compose.yml")"
ENV_EXAMPLE="$(cat "${PACK_DIR}/.env.example")"
NGINX="$(cat "${PACK_DIR}/nginx-additional-directives.conf")"

echo "${COMPOSE}" | grep -q 'container_name: twenty-server' || fail "server container_name missing"
echo "${COMPOSE}" | grep -q 'container_name: twenty-worker' || fail "worker container_name missing"
echo "${COMPOSE}" | grep -q 'container_name: twenty-postgres' || fail "postgres container_name missing"
echo "${COMPOSE}" | grep -q 'container_name: twenty-redis' || fail "redis container_name missing"
echo "${COMPOSE}" | grep -q 'HOST_BIND:-127.0.0.1' || fail "compose must bind loopback by default"
echo "${COMPOSE}" | grep -q 'healthz' || fail "server healthcheck missing"
echo "${COMPOSE}" | grep -q 'yarn", "worker:prod' || fail "worker command missing"
echo "${COMPOSE}" | grep -q 'DISABLE_DB_MIGRATIONS: "true"' || fail "worker must not re-run migrations"
echo "${COMPOSE}" | grep -q 'maxmemory-policy' || fail "redis eviction policy missing"
echo "${COMPOSE}" | grep -qE '[0-9.]+:5432:5432|"5432:5432"' && fail "postgres must not publish 5432"
echo "${COMPOSE}" | grep -q 'image: postgres:16' || fail "postgres 16 image missing"
pass "compose services and loopback bind"

for key in \
  TWENTY_IMAGE \
  TAG \
  HOST_BIND \
  HOST_PORT \
  SERVER_URL \
  ENCRYPTION_KEY \
  PG_DATABASE_PASSWORD \
  STORAGE_TYPE
do
  echo "${ENV_EXAMPLE}" | grep -q "^${key}=" || fail ".env.example missing ${key}"
done
pass ".env.example required keys"

echo "${NGINX}" | grep -q 'proxy_pass http://127.0.0.1:3000' || fail "nginx must proxy to loopback:3000"
echo "${NGINX}" | grep -q 'proxy_set_header Upgrade' || fail "nginx Upgrade header missing"
echo "${NGINX}" | grep -q 'X-Forwarded-Proto' || fail "nginx X-Forwarded-Proto missing"
echo "${NGINX}" | grep -q 'proxy_buffering off' || fail "nginx stream buffering-off missing"
echo "${NGINX}" | grep -q 'graphql/stream' || fail "nginx GraphQL stream location missing"
echo "${NGINX}" | grep -q 'client_max_body_size' || fail "nginx upload limit missing"
echo "${NGINX}" | grep -q 'server {' && fail "nginx snippet must not open a server block"
echo "${NGINX}" | grep -qE '^map ' && fail "nginx snippet must not use map (http-level)"
pass "nginx Plesk snippet"

# Placeholder values must stay in the example so deploy.sh can refuse a
# copied-but-unedited .env on the droplet.
echo "${ENV_EXAMPLE}" | grep -q 'replace_me_with_openssl_rand_base64_32' || fail "ENCRYPTION_KEY placeholder missing"
echo "${ENV_EXAMPLE}" | grep -q 'crm.example.com' || fail "example SERVER_URL missing"
pass "unsafe placeholder markers present for deploy guard"

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  python3 - "${PACK_DIR}/docker-compose.yml" <<'PY'
import sys
import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    compose = yaml.safe_load(handle)

required_services = ("server", "worker", "db", "redis")
services = compose.get("services") or {}
missing = [name for name in required_services if name not in services]
if missing:
    raise SystemExit(f"compose missing services: {', '.join(missing)}")

for name in ("db", "redis"):
    if "ports" in services[name]:
        raise SystemExit(f"{name} must not publish host ports")

server_ports = services["server"].get("ports") or []
if not any("127.0.0.1" in str(port) for port in server_ports):
    raise SystemExit("server must bind loopback")

if services["worker"].get("command") != ["yarn", "worker:prod"]:
    raise SystemExit("worker command must be yarn worker:prod")
PY
  pass "compose YAML structure"
else
  echo "SKIP: PyYAML not available — skipped structural compose parse"
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose -f "${PACK_DIR}/docker-compose.yml" --env-file "${PACK_DIR}/.env.example" config >/tmp/twenty-plesk-compose.yml
  grep -q '127.0.0.1' /tmp/twenty-plesk-compose.yml || fail "rendered compose lost loopback bind"
  grep -q 'twenty-server' /tmp/twenty-plesk-compose.yml || fail "rendered compose missing server"
  grep -q 'twenty-worker' /tmp/twenty-plesk-compose.yml || fail "rendered compose missing worker"
  pass "docker compose config renders"
else
  echo "SKIP: docker compose not available — interpolation not rendered"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
cp "${PACK_DIR}/docker-compose.yml" "${PACK_DIR}/.env.example" "${TMP_DIR}/"
mkdir -p "${TMP_DIR}/scripts"
cp "${PACK_DIR}/scripts/deploy.sh" "${TMP_DIR}/scripts/"
chmod +x "${TMP_DIR}/scripts/deploy.sh"
set +e
DEPLOY_OUTPUT="$(bash "${TMP_DIR}/scripts/deploy.sh" 2>&1)"
DEPLOY_STATUS=$?
set -e
[[ "${DEPLOY_STATUS}" -ne 0 ]] || fail "deploy.sh must refuse an unedited .env"
echo "${DEPLOY_OUTPUT}" | grep -q 'placeholders' || fail "deploy.sh must mention placeholders"
pass "deploy.sh refuses example .env"

echo
echo "Plesk pack validation passed."
