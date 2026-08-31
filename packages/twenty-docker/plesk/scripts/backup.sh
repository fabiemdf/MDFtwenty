#!/usr/bin/env bash
# Dump Postgres and copy the server local-storage volume to BACKUP_DIR.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PACK_DIR}/.env"
BACKUP_DIR="${BACKUP_DIR:-/opt/twenty/backups}"
STAMP="$(date +%Y%m%dT%H%M%SZ)"

cd "${PACK_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

mkdir -p "${BACKUP_DIR}"

dump_path="${BACKUP_DIR}/twenty-${STAMP}.sql"
echo "Dumping database to ${dump_path}"
docker exec twenty-postgres pg_dump \
  -U "${PG_DATABASE_USER:-postgres}" \
  "${PG_DATABASE_NAME:-default}" > "${dump_path}"

storage_path="${BACKUP_DIR}/local-storage-${STAMP}.tgz"
echo "Archiving local storage to ${storage_path}"
docker run --rm \
  -v twenty_server-local-data:/data:ro \
  -v "${BACKUP_DIR}:/backup" \
  alpine \
  tar -C /data -czf "/backup/local-storage-${STAMP}.tgz" .

echo "Backup complete:"
ls -lh "${dump_path}" "${storage_path}"
