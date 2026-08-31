#!/usr/bin/env bash
# Optional: bake this fork into a private image. Do NOT run on the Plesk
# production droplet — the frontend compile needs an 8GB Node heap.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
IMAGE="${TWENTY_IMAGE:-ghcr.io/fabiemdf/mdftwenty}"
TAG="${TAG:-local}"

total_kb="$(awk '/MemTotal:/ { print $2 }' /proc/meminfo)"
total_gb="$((total_kb / 1024 / 1024))"
if (( total_gb < 14 )); then
  echo "Refusing to build: detected ${total_gb}GB RAM. Use a 16GB+ build box or the published twentycrm/twenty image." >&2
  exit 1
fi

if [[ -x /usr/sbin/plesk ]] || command -v plesk >/dev/null 2>&1; then
  echo "Refusing to build on a Plesk host. Build elsewhere and set TWENTY_IMAGE to the pushed tag." >&2
  exit 1
fi

cd "${REPO_ROOT}"

docker build \
  --target twenty \
  -f packages/twenty-docker/twenty/Dockerfile \
  --build-arg "APP_VERSION=${TAG}" \
  -t "${IMAGE}:${TAG}" \
  .

echo "Built ${IMAGE}:${TAG}"
echo "Push with: docker push ${IMAGE}:${TAG}"
echo "Then set TWENTY_IMAGE=${IMAGE} and TAG=${TAG} in /opt/twenty/.env"
