# Bigfoot API — Production Deployment

End-to-end guide for the DigitalOcean droplet + Managed Postgres + GitHub
Actions CI/CD setup. Run once for first-time bootstrap; thereafter every push
to `main` auto-deploys.

---

## Architecture

```
GitHub push → Actions (test → build → push image to GHCR)
                                          ↓
              SSH deploy → pulls image → restarts compose
                                          ↓
   Internet → Caddy (80/443 auto-TLS) → API (3000, internal)
                                       ↘ Redis (internal)
                                       ↘ Managed PostgreSQL (VPC private)
                                       ↘ DO Spaces (HTTPS)
```

---

## Prerequisites

- DigitalOcean Droplet (Ubuntu 24.04, 2 vCPU / 4 GB minimum)
- DigitalOcean Managed PostgreSQL in the same VPC
- DigitalOcean Spaces bucket (private) in `nyc3`
- A domain with an A record pointing at the droplet's public IP
- A GitHub repository for the codebase

---

## One-time droplet bootstrap

Run as `root` over SSH:

```bash
# 1. Patch + essentials
apt update && apt upgrade -y
apt install -y unattended-upgrades ufw fail2ban git
dpkg-reconfigure --priority=low unattended-upgrades

# 2. Non-root deploy user
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
mkdir -p /home/deploy/.ssh
cp ~/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

# 3. Harden SSH — disable root login + passwords
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers deploy
EOF
systemctl restart ssh

# 4. Host firewall (defense in depth on top of DO Cloud Firewall)
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# 5. fail2ban for SSH brute-force
cat > /etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
maxretry = 3
findtime = 10m
bantime = 24h
EOF
systemctl enable --now fail2ban

# 6. Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker deploy

# 7. App directory
mkdir -p /opt/bigfoot/bigfoot-api
chown -R deploy:deploy /opt/bigfoot
```

### Also do at DO control panel level
- **Networking → Firewalls**: create a firewall with SSH (port 22) restricted
  to your office/home IP only; ports 80 + 443 open to all. Attach to droplet.
- **Managed Database → Settings → Trusted sources**: add the droplet so the
  database refuses every other IP.
- **Managed Database → Connection details → Download CA certificate**:
  download it and `scp` it to `/opt/bigfoot/do-pg-ca.crt` on the droplet
  (chmod 644, owner `deploy`). The compose file mounts it read-only into the
  api container at `/etc/ssl/do-pg-ca.crt`; Prisma reads it for strict
  chain + hostname validation. No "accept invalid certs" shortcuts.
- **DNS**: A record `api.bigfoottrailers.com` → droplet's public IP. Wait for
  it to propagate (`dig api.bigfoottrailers.com +short`).

---

## Configure secrets on the droplet (as `deploy`)

```bash
sudo -u deploy -i
cd /opt/bigfoot

# Copy the template from the repo (rsync it up or grab it from GitHub raw)
curl -fsSL https://raw.githubusercontent.com/<your-org>/<repo>/main/bigfoot-api/.env.production.example \
  -o .env.production
chmod 600 .env.production
nano .env.production    # fill in every value — see notes below
```

Critical values to set:
- `DOMAIN` — your real domain (Caddy uses this for TLS issuance)
- `DATABASE_URL` — Managed Postgres PRIVATE VPC connection string with `?sslmode=require`
- `JWT_SECRET` — generate with `openssl rand -base64 48`
- `CORS_ORIGINS` — your real frontend/mobile origins (no localhost in prod)
- All `DO_SPACES_*`, `TWILIO_*`, `FIREBASE_*` from those services' dashboards

The API refuses to start if `NODE_ENV=production` and any required value is
missing or `JWT_SECRET` is left as the placeholder.

---

## Set up GitHub secrets + variables

In the GitHub repo → **Settings → Secrets and variables → Actions**:

### Secrets (encrypted)
| Name | Value |
|---|---|
| `DEPLOY_HOST` | Droplet public IP (e.g. `159.203.78.95`) |
| `DEPLOY_USER` | `deploy` |
| `DEPLOY_SSH_KEY` | A **dedicated CI SSH private key** (generate fresh, see below) |

### Variables (not secret)
| Name | Value |
|---|---|
| `DEPLOY_DOMAIN` | `api.bigfoottrailers.com` |

### Generate a dedicated CI deploy key
On your laptop:
```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/bigfoot-ci -N ""
# Add the PUBLIC key to the droplet's deploy user:
ssh-copy-id -i ~/.ssh/bigfoot-ci.pub deploy@<droplet-ip>
# Paste the contents of the PRIVATE key (~/.ssh/bigfoot-ci) into DEPLOY_SSH_KEY
```
The CI key has no passphrase (Actions can't type one) and only authorizes
`deploy@droplet`. Keep your personal key for human SSH access.

### Optional but recommended: require approval before deploy
**Settings → Environments → New environment** named `production` → check
**Required reviewers** and add yourself. Every deploy will then pause for a
manual click before pushing to prod.

---

## First deploy

The Docker image must exist in GHCR before the first compose `up`. Push any
commit to `main` (or click **Run workflow** in the Actions tab) to trigger
the pipeline — it will:

1. Run `npm run lint` and `npm test` (394 tests)
2. Build the image and push to `ghcr.io/<owner>/<repo>/bigfoot-api`
3. SCP `docker-compose.prod.yml` + `Caddyfile` to the droplet
4. SSH in, pull the new image, `docker compose up -d --remove-orphans`
5. Curl `https://<domain>/health` 30× until green

When you see the green check, browse `https://api.bigfoottrailers.com/health`
in a browser — should return `{"status":"ok"}` with a valid TLS cert.

---

## Day-to-day

**Deploy**: merge to `main` → automatic.

**Roll back**: SSH to droplet, set the previous SHA, re-up:
```bash
ssh deploy@<droplet-ip>
cd /opt/bigfoot/bigfoot-api
export IMAGE_TAG=sha-<previous-40-char-sha>
docker compose --env-file /opt/bigfoot/.env.production \
  -f docker-compose.prod.yml up -d
```
The previously-deployed SHA is recorded in `/opt/bigfoot/.deployed-sha`.

**Update environment variables**: edit `/opt/bigfoot/.env.production` then
`docker compose ... up -d` to restart the api container.

**View logs**: `docker compose -f docker-compose.prod.yml logs -f api caddy`.

**Update compose / Caddyfile**: edit in the repo, push to `main`. The deploy
pipeline scp's the new files to the droplet on every run.

---

## Security checklist (verify post-deploy)

```bash
# From your laptop:
curl -I https://api.bigfoottrailers.com/health
# expect: 200, with `Strict-Transport-Security` header

curl http://api.bigfoottrailers.com/health
# expect: 308 redirect to https

nmap -Pn <droplet-ip>
# expect: only 22, 80, 443 open

curl -I https://api.bigfoottrailers.com/docs
# expect: 404 (Swagger disabled in production)

# Try the JWT-protected route without a token
curl -i https://api.bigfoottrailers.com/v1/trailers
# expect: 401 UNAUTHORIZED
```

The DO Cloud Firewall, host UFW, fail2ban, SSH key-only access, Managed DB
trusted sources, NODE_ENV=production validation, Caddy HSTS+CSP, and image
non-root user (`appuser` UID 1001) together make this a hard target.

---

## What runs on each container start

`docker-entrypoint.sh` (inside the API image):
1. `npx prisma db push --accept-data-loss` — syncs schema to the database
2. Applies any new `prisma/sql-patches/*.sql` (idempotent)
3. Starts the API (`node dist/src/main`)

⚠️ The `--accept-data-loss` flag lets Prisma drop columns. For additive
schema changes (the normal case) this is safe. For column removals,
test in a staging environment first.
