# Twenty on Plesk (DigitalOcean)

Community pack for running this fork behind Plesk on a DigitalOcean
droplet. Twenty's core team supports Docker Compose; this folder only
adds Plesk reverse-proxy, firewall, and sizing guidance.

## Review

| Topic | Finding |
| --- | --- |
| What to run | Official `twentycrm/twenty` image (server + worker + Postgres 16 + Redis). Do not use Plesk Node.js / Passenger. |
| What not to do | Do **not** compile this monorepo on the Plesk droplet. `twenty-front` needs an 8GB Node heap; Plesk plus Docker plus that compile will OOM on typical marketplace sizes. |
| Droplet size | **8GB RAM / 4 vCPU / 80GB disk minimum. 16GB recommended.** A 4GB Plesk marketplace droplet is too small (Plesk itself uses 1–2GB). |
| Image | Plesk Web Admin SE marketplace image is fine, or Ubuntu 24.04 + Plesk. Open 22, 80, 443, 8443 only. |
| TLS | Plesk Let's Encrypt on the CRM domain. `SERVER_URL` must be that `https://` URL. |
| Storage | Local volume works on one droplet. Use DigitalOcean Spaces (`STORAGE_TYPE=S_3`) if you snapshot/rebuild droplets. |

## 1. Prepare the droplet

1. Create an 8GB+ DigitalOcean droplet (Plesk marketplace or Ubuntu).
2. Point the CRM hostname (A record) at the droplet public IPv4.
3. In DigitalOcean Cloud Firewall allow TCP 22, 80, 443, 8443. Leave 3000, 5432, and 6379 closed.
4. In Plesk: **Extensions → Docker**. Then install Compose v2 if it is missing:

   ```bash
   apt-get update
   apt-get install -y docker-compose-plugin
   ```

5. Add 4GB swap on 8GB droplets:

   ```bash
   fallocate -l 4G /swapfile
   chmod 600 /swapfile
   mkswap /swapfile
   swapon /swapfile
   echo '/swapfile none swap sw 0 0' >> /etc/fstab
   ```

6. Run the host check:

   ```bash
   bash packages/twenty-docker/plesk/scripts/preflight.sh
   ```

## 2. Install the compose pack

Copy only this folder to the droplet — not the rest of the monorepo:

```bash
mkdir -p /opt/twenty
# from a machine that has the repo:
scp -r packages/twenty-docker/plesk/. root@YOUR_DROPLET:/opt/twenty/
```

Or, on the droplet:

```bash
mkdir -p /opt/twenty && cd /opt/twenty
curl -fsSO https://raw.githubusercontent.com/fabiemdf/MDFtwenty/main/packages/twenty-docker/plesk/docker-compose.yml
curl -fsSO https://raw.githubusercontent.com/fabiemdf/MDFtwenty/main/packages/twenty-docker/plesk/.env.example
mkdir -p scripts
curl -fsS -o scripts/deploy.sh https://raw.githubusercontent.com/fabiemdf/MDFtwenty/main/packages/twenty-docker/plesk/scripts/deploy.sh
curl -fsS -o scripts/backup.sh https://raw.githubusercontent.com/fabiemdf/MDFtwenty/main/packages/twenty-docker/plesk/scripts/backup.sh
chmod +x scripts/*.sh
```

```bash
cd /opt/twenty
cp .env.example .env
```

Set at least:

```ini
SERVER_URL=https://crm.your-domain.com
ENCRYPTION_KEY=<openssl rand -base64 32>
PG_DATABASE_PASSWORD=<openssl rand -hex 32>
```

```bash
bash /opt/twenty/scripts/deploy.sh
```

The script refuses to start if `.env` still has the example placeholders.
Containers bind `127.0.0.1:3000` only.

## 3. Attach the domain in Plesk

1. **Websites & Domains → Add Domain** for the hostname in `SERVER_URL`.
2. Hosting: no PHP required. Document root can stay the default; nginx will
   proxy everything.
3. **SSL/TLS Certificates → Let's Encrypt** for that domain (include www if
   you use it).
4. **Apache & nginx Settings**:
   - Uncheck **Proxy mode**.
   - Click **Apply** (required — otherwise Plesk errors on a duplicate `location /`).
   - Paste `nginx-additional-directives.conf` into **Additional nginx directives**.
   - Apply again.
5. Confirm from the droplet:

   ```bash
   curl -fsS http://127.0.0.1:3000/healthz
   curl -fsSI https://crm.your-domain.com/healthz
   ```

Do not use Plesk **Docker Proxy Rules** as the only proxy. They skip the
streaming headers Twenty needs for AI chat and GraphQL.

## 4. First login

Open `SERVER_URL`. The first user becomes the workspace admin
(`canAccessFullAdminPanel`). Further signups are disabled in single-workspace
mode (the default).

Configure SMTP, OAuth, and the rest under **Settings → Admin Panel →
Configuration Variables**.

## 5. DigitalOcean Spaces (optional)

```ini
STORAGE_TYPE=S_3
STORAGE_S3_REGION=nyc3
STORAGE_S3_NAME=your-space-name
STORAGE_S3_ENDPOINT=https://nyc3.digitaloceanspaces.com
STORAGE_S3_ACCESS_KEY_ID=...
STORAGE_S3_SECRET_ACCESS_KEY=...
```

Then `docker compose up -d` again. Add the Twenty origin to the Space CORS
policy if the browser downloads files directly from Spaces.

## 6. Backup and upgrade

Daily dump (root crontab):

```bash
0 2 * * * BACKUP_DIR=/opt/twenty/backups /opt/twenty/scripts/backup.sh
```

Copy `/opt/twenty/backups` off the droplet (Spaces, another region, or
`rclone`). Test a restore before you need one.

Upgrade a published tag:

```bash
cd /opt/twenty
# set TAG=v1.x.x in .env (pin a release in production; avoid latest)
bash scripts/deploy.sh
```

## 7. Custom image (only if this fork diverges)

Build on a **separate 16GB+ box**, never on Plesk:

```bash
TAG=v1.0.0 TWENTY_IMAGE=ghcr.io/fabiemdf/mdftwenty \
  bash packages/twenty-docker/plesk/scripts/build-image.sh
docker push ghcr.io/fabiemdf/mdftwenty:v1.0.0
```

Point `/opt/twenty/.env` at that image and redeploy.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Login / cookie loops | `SERVER_URL` must be the exact public `https://` URL. Restart after changing it. |
| AI chat waits until refresh | Stream location is missing or proxy mode is still on. Re-apply the nginx snippet. |
| `password authentication failed` on a fresh install | Password is baked into the Postgres volume. `docker compose down --volumes` wipes data. |
| 502 from Plesk | `curl http://127.0.0.1:3000/healthz` and `docker compose logs server`. |
| OOM / containers restart | Droplet is undersized. Resize to 8GB+ and add swap. |
| Duplicate `location /` in Plesk | Disable proxy mode and Apply **before** pasting the snippet. |

Logs:

```bash
docker compose -f /opt/twenty/docker-compose.yml logs -f server worker
```
