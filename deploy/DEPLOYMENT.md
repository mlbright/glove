# Deployment Guide

Production runs **directly from this git checkout**. There is no separate
deployed copy: the working tree at the repo root (e.g. `/home/ubuntu/glove`)
is both the development workspace and the production deployment.

## Principles

- **All production state lives inside this directory.** Copy the directory to
  a new machine, run `make install`, and production runs there. The only
  artifacts outside the repo are the systemd units, which are generated from
  templates in `deploy/` and contain no secrets.
- **The service runs as your own user** (whoever runs `make install`), so
  git, the app, mise-managed Ruby, and backups all share one owner.
- **No git in `make update`.** Production runs whatever the working tree
  contains; keeping the tree in a runnable state is the operator's job.
- **Nothing here destroys production data.** `make update` uses
  `db:prepare` (migrate, never drop); the storage pull script is additive
  and requires `--force` to overwrite.

### Production state inventory

| State                                        | Location                 |
|----------------------------------------------|--------------------------|
| SQLite databases (primary/cache/queue/cable) | `storage/*.sqlite3`      |
| Uploaded files (Active Storage)              | `storage/<2-char dirs>/` |
| Rails master key                             | `config/master.key`      |
| Runtime env (subpath, hosts, Google OAuth)   | `.env`                   |
| Backup credentials (S3/AWS, ntfy)            | `deploy/backup.env`      |

All of these are gitignored. Everything else is code and regenerable.

## Architecture

Glove is served at a **subpath** (`https://<public-host>/glove/`) behind a
Caddy reverse proxy that lives on a **separate machine** — nothing
Caddy-related is installed here.

```
               ┌─────────────────────────────┐
 Clients ────▶ │ Caddy machine (443, TLS)    │   ← separate host; see
               │   handle_path /glove/*      │     deploy/caddy-snippet.md
               └──────────┬──────────────────┘
                          │ Tailscale, plain HTTP
               ┌──────────▼──────────────────┐
               │ this machine :3004 Thruster │   ← listens on all interfaces
               │        127.0.0.1:3003 Puma  │   ← loopback only
               │        + Solid Queue        │
               └──────────┬──────────────────┘
                          │
               ┌──────────▼──────────────────┐
               │ storage/*.sqlite3           │
               │ storage/ (uploads)          │
               └─────────────────────────────┘
```

Ports 3001/3002 on this machine belong to the notes app; glove uses
3003 (Puma) and 3004 (Thruster).

The subpath works via two pieces already in the app: Caddy sends an
`X-Script-Name: /glove` header that `Rack::ScriptNameFromHeader` turns into
`SCRIPT_NAME`, and `RAILS_RELATIVE_URL_ROOT=/glove` (set in `.env`) prefixes
generated asset and URL paths. `make update` loads `.env` before
`assets:precompile` so the prefix reaches compiled assets too.

## Prerequisites

- Ubuntu 24.04+ with sudo access
- [mise](https://mise.jdx.dev/) installed for your user, with Ruby
  provisioned: `mise install` (the repo's `mise.toml` pins the version)
- Tailscale (or equivalent private network) connecting this machine and the
  Caddy machine

## First-time setup

```bash
git clone <repo-url> ~/glove
cd ~/glove

# 1. Ruby via mise
mise install

# 2. Secrets — see "Secrets reference" below
cp /path/to/master.key config/master.key && chmod 600 config/master.key
$EDITOR .env
cp deploy/backup.env.example deploy/backup.env && $EDITOR deploy/backup.env
chmod 600 deploy/backup.env

# 3. Install system packages + systemd units (uses sudo)
make install

# 4. Gems, database, assets, start
make update

# 5. Verify
make status
curl -s http://localhost:3004/up
```

Then point the Caddy machine at this one: see
[caddy-snippet.md](./caddy-snippet.md).

## Secrets reference

### `.env`

Loaded by the systemd unit (`EnvironmentFile`) and by `make update`.
Keep `chmod 600`.

```env
# Serve the app under /glove (must match the Caddy handle_path prefix).
RAILS_RELATIVE_URL_ROOT=/glove

# Comma-separated extra hosts allowed by Rails host authorization —
# the public hostname served by the Caddy machine.
RAILS_PRODUCTION_HOSTS=hippo.chameleon-gopher.ts.net

# Google OAuth2 (web sign-in).
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...

# Only needed if config/master.key is absent.
#RAILS_MASTER_KEY=...
```

### `config/master.key`

Decrypts `config/credentials.yml.enc`. `chmod 600`.

### `deploy/backup.env`

S3 bucket and AWS credentials for the backup timer; see
[backup.env.example](./backup.env.example). `chmod 600`.

## Make targets

| Target         | What it does                                                        |
|----------------|---------------------------------------------------------------------|
| `make install` | `install-deps` + `install-web` + `install-backup` (idempotent)      |
| `make install-deps`   | apt packages (build tools, sqlite3, awscli, …)               |
| `make install-web`    | Renders + installs `glove-web.service`, enables it           |
| `make install-backup` | Renders + installs backup service + timer, enables the timer |
| `make update`  | `bundle install` → `db:prepare` → `assets:precompile` → restart     |
| `make restart` | Restart the service                                                 |
| `make status`  | Service status + backup timer schedule                              |
| `make logs`    | Follow the journal                                                  |

`make install` bakes the repo path, your username, and the current mise Ruby
path into the installed units. **Re-run `make install-web install-backup`
after upgrading Ruby or moving the repo.** Never edit the files in
`/etc/systemd/system` directly — they are generated artifacts.

## Updating the app

```bash
cd ~/glove
git pull          # or merge, or edit — your call; make never touches git
make update
```

Because this is a dual-use checkout, remember: **a service restart boots
whatever is in the working tree**, including half-finished edits. Keep the
tree runnable before `make update`, reboots, or anything that restarts the
service.

## Backups

A systemd timer (`glove-backup.timer`) uploads consistent `sqlite3 .backup`
snapshots of all four databases plus any uploaded files to S3 every 6 hours
(see `deploy/backup-s3.sh`).

```bash
# Run one manually / inspect
sudo systemctl start glove-backup.service
journalctl -u glove-backup.service -e
systemctl list-timers glove-backup.timer
```

Frequency: edit `OnCalendar=` in `deploy/glove-backup.timer`, then
`make install-backup`. Retention: use an S3 lifecycle policy.

## Migrating production from the old machine (cold cutover)

Scenario: the old machine (`rattlesnake`) runs the previous layout — the
checkout at `/home/mbright/glove`, a hand-written `glove.service`, secrets in
`/home/mbright/glove/.env`. Afterwards this checkout runs production. The
public URL (host and `/glove` subpath) stays the same, so Google OAuth
redirect URIs are untouched.

On **this machine**, complete "First-time setup" above through step 3
(`make install`) — but don't create secrets or run `make update` yet; they
come from the old machine.

1. **Stop production on the old machine** (this is the start of downtime;
   a clean stop checkpoints the SQLite WAL files so plain file copies are
   consistent):

   ```bash
   ssh rattlesnake 'sudo systemctl stop glove && sudo systemctl disable glove'
   ```

2. **Copy the databases and uploads** into this checkout:

   ```bash
   script/pull-production-storage            # host defaults to rattlesnake
   ```

   The script is a guarded version of
   `rsync -av rattlesnake:/home/mbright/glove/storage/ storage/`: it aborts
   if the service is running on either machine, aborts on a non-empty remote
   WAL (the fingerprint of an unclean stop — after a clean stop the
   `-wal`/`-shm` sidecars are empty leftovers, and it excludes them from the
   copy), requires `--force` to overwrite existing local production
   databases, and never deletes local files. `--dry-run` previews the
   transfer; `--sudo` reads the remote side with `sudo rsync` if your ssh
   user cannot read the files directly.

3. **Copy the master key:**

   ```bash
   rsync -av rattlesnake:/home/mbright/glove/config/master.key ~/glove/config/master.key
   chmod 600 ~/glove/config/master.key
   ```

4. **Copy `.env`** and adjust for the new layout:

   ```bash
   rsync -av rattlesnake:/home/mbright/glove/.env ~/glove/.env
   chmod 600 ~/glove/.env
   # Ensure it contains (see "Secrets reference"):
   #   RAILS_RELATIVE_URL_ROOT=/glove
   #   RAILS_PRODUCTION_HOSTS=<public host>
   #   GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
   ```

5. **Create the backup credentials** (the old machine had no backup timer):

   ```bash
   cp deploy/backup.env.example deploy/backup.env
   $EDITOR deploy/backup.env
   chmod 600 deploy/backup.env
   ```

6. **Migrate and start** (this checkout's code may carry newer migrations
   than the old machine's data — `db:prepare` inside `make update` handles
   that):

   ```bash
   cd ~/glove
   make update
   make status
   curl -s http://localhost:3004/up        # expect 200
   ```

7. **Cut over the reverse proxy**: on the Caddy machine, change the
   `/glove/*` `reverse_proxy` target to this machine's Tailscale name and
   port 3004 (see [caddy-snippet.md](./caddy-snippet.md) — both host and
   port change), reload Caddy, and verify `https://<host>/glove/up` and a
   real sign-in end to end.

8. **Decommission the old deployment** once you've confirmed sign-in,
   transactions, CSV imports, and a manual backup run
   (`sudo systemctl start glove-backup.service`) all work from here.

## Managing the service

```bash
make status                      # service + timer overview
make logs                        # journal (Puma stdout/stderr)
sudo systemctl {start|stop|restart|reload} glove-web
tail -f log/production.log       # Rails application log
```

## Troubleshooting

| Symptom                    | Check                                                        |
|----------------------------|--------------------------------------------------------------|
| Service won't start        | `journalctl -u glove-web -e`                                 |
| 502 from Caddy             | Is Thruster up? `curl http://localhost:3004/up`; tailnet reachable from the Caddy box? |
| Blocked host error         | `RAILS_PRODUCTION_HOSTS` in `.env` must include the public host |
| Wrong asset/link paths     | `RAILS_RELATIVE_URL_ROOT=/glove` in `.env`, then `make update`; Caddy must send `X-Script-Name: /glove` |
| Assets not loading         | `make update` (re-runs `assets:precompile`)                  |
| Master key errors          | `config/master.key` present and `chmod 600`?                 |
| Write errors (DB/uploads)  | `ReadWritePaths` in the unit; re-run `make install-web` if the repo moved |
| Stale Ruby after upgrade   | Re-run `make install-web` (unit bakes in the mise Ruby path) |
| Backup failures            | `journalctl -u glove-backup -e`; `deploy/backup.env` present and valid? |
