#!/usr/bin/env bash
# Host checks for a DigitalOcean Plesk droplet. Exits non-zero when the
# box is too small or Docker Compose is missing.
set -euo pipefail

warn() { echo "WARN: $*" >&2; }
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

if [[ "${EUID}" -ne 0 ]]; then
  warn "run as root (or with sudo) so Docker and Plesk can be inspected"
fi

total_kb="$(awk '/MemTotal:/ { print $2 }' /proc/meminfo)"
total_gb="$((total_kb / 1024 / 1024))"
if (( total_gb < 4 )); then
  fail "detected ${total_gb}GB RAM. Twenty + Plesk need at least 8GB (16GB recommended)."
elif (( total_gb < 8 )); then
  warn "detected ${total_gb}GB RAM. Expect swap thrash. Resize the droplet to 8GB+."
else
  ok "${total_gb}GB RAM"
fi

avail_kb="$(df -Pk / | awk 'NR==2 { print $4 }')"
avail_gb="$((avail_kb / 1024 / 1024))"
if (( avail_gb < 20 )); then
  fail "only ${avail_gb}GB free on /. Need 20GB+ for images, volumes, and Plesk."
fi
ok "${avail_gb}GB free on /"

swap_kb="$(awk '/SwapTotal:/ { print $2 }' /proc/meminfo)"
if (( swap_kb < 1024 * 1024 )); then
  warn "swap is under 1GB. Add 4GB swap on 8GB droplets: fallocate -l 4G /swapfile"
else
  ok "swap $((swap_kb / 1024 / 1024))GB"
fi

command -v docker >/dev/null 2>&1 || fail "Docker is not installed. In Plesk: Extensions → Docker, then apt-get install docker-compose-plugin"
docker info >/dev/null 2>&1 || fail "Docker daemon is not running or this user cannot talk to it"
ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo present)"

docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 plugin missing (apt-get install docker-compose-plugin)"
ok "$(docker compose version --short 2>/dev/null || echo 'compose v2')"

if command -v plesk >/dev/null 2>&1 || [[ -x /usr/sbin/plesk ]]; then
  ok "Plesk CLI detected"
else
  warn "plesk CLI not on PATH. Install Plesk or confirm this is the DigitalOcean Plesk marketplace image."
fi

if ss -lnt 2>/dev/null | awk '{ print $4 }' | grep -Eq '(:|\\.)3000$'; then
  if docker ps --format '{{.Names}}' | grep -qx 'twenty-server'; then
    ok "port 3000 is already owned by twenty-server"
  else
    warn "port 3000 is in use by something other than twenty-server"
  fi
else
  ok "port 3000 is free"
fi

if ss -lnt 2>/dev/null | awk '{ print $4 }' | grep -Eq '(:|\\.)(80|443|8443)$'; then
  ok "Plesk/web ports 80/443/8443 are listening"
else
  warn "80/443/8443 are not all listening — check Plesk and the DigitalOcean Cloud Firewall"
fi

echo
echo "Preflight finished. Next: copy this pack to /opt/twenty, edit .env, run scripts/deploy.sh"
