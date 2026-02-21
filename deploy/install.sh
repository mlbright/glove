#!/usr/bin/env bash
#
# install.sh — Set up the Glove app on an Ubuntu/Debian VPS.
#
# Usage:
#   sudo bash deploy/install.sh
#
# Prerequisites:
#   - Ubuntu 22.04+ or Debian 12+
#   - Root or sudo access
#   - Git, curl installed
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — edit these before running
# ---------------------------------------------------------------------------
APP_USER="glove"
APP_DIR="/opt/glove"
RUBY_VERSION="3.4.7"
SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  red "This script must be run as root (or with sudo)."
  exit 1
fi

green "==> Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq \
  build-essential git curl libssl-dev libreadline-dev zlib1g-dev \
  libsqlite3-dev libyaml-dev libffi-dev

# ---------------------------------------------------------------------------
# Create application user
# ---------------------------------------------------------------------------
if ! id "$APP_USER" &>/dev/null; then
  green "==> Creating system user '$APP_USER'..."
  useradd --system --create-home --shell /usr/sbin/nologin "$APP_USER"
fi

# ---------------------------------------------------------------------------
# Install Ruby via ruby-install (if not already present)
# ---------------------------------------------------------------------------
if ! command -v ruby &>/dev/null || [[ "$(ruby -e 'puts RUBY_VERSION')" != "$RUBY_VERSION" ]]; then
  green "==> Installing ruby-install..."
  if ! command -v ruby-install &>/dev/null; then
    RUBY_INSTALL_VERSION="0.9.4"
    cd /tmp
    curl -fsSL "https://github.com/postmodern/ruby-install/releases/download/v${RUBY_INSTALL_VERSION}/ruby-install-${RUBY_INSTALL_VERSION}.tar.gz" \
      | tar -xz
    cd "ruby-install-${RUBY_INSTALL_VERSION}"
    make install
    cd /tmp && rm -rf "ruby-install-${RUBY_INSTALL_VERSION}"
  fi

  green "==> Installing Ruby ${RUBY_VERSION} (this takes a few minutes)..."
  ruby-install --system ruby "$RUBY_VERSION" -- --disable-install-doc
fi

ruby -v

# ---------------------------------------------------------------------------
# Deploy application code
# ---------------------------------------------------------------------------
green "==> Deploying application to ${APP_DIR}..."
mkdir -p "$APP_DIR"
rsync -a --delete \
  --exclude='.git' \
  --exclude='storage/development.sqlite3' \
  --exclude='storage/test.sqlite3' \
  --exclude='tmp/cache' \
  --exclude='log/*.log' \
  --exclude='node_modules' \
  "${SOURCE_DIR}/" "${APP_DIR}/"

chown -R "$APP_USER":"$APP_USER" "$APP_DIR"

# ---------------------------------------------------------------------------
# Install gems
# ---------------------------------------------------------------------------
green "==> Installing Ruby gems..."
cd "$APP_DIR"
su -s /bin/bash "$APP_USER" -c "cd $APP_DIR && bundle config set --local deployment true && bundle config set --local without 'development test' && bundle install --jobs 4 --quiet"

# ---------------------------------------------------------------------------
# Rails credentials
# ---------------------------------------------------------------------------
if [[ ! -f "$APP_DIR/config/master.key" ]]; then
  yellow "WARNING: config/master.key is missing."
  yellow "Copy your master.key to $APP_DIR/config/master.key before starting the service."
  yellow "  scp config/master.key root@server:$APP_DIR/config/master.key"
  yellow "  chown $APP_USER:$APP_USER $APP_DIR/config/master.key"
  yellow "  chmod 600 $APP_DIR/config/master.key"
fi

# ---------------------------------------------------------------------------
# Prepare database and assets
# ---------------------------------------------------------------------------
green "==> Preparing database..."
su -s /bin/bash "$APP_USER" -c "cd $APP_DIR && RAILS_ENV=production bin/rails db:prepare"

green "==> Precompiling assets..."
su -s /bin/bash "$APP_USER" -c "cd $APP_DIR && RAILS_ENV=production bin/rails assets:precompile"

# ---------------------------------------------------------------------------
# Ensure writable directories
# ---------------------------------------------------------------------------
su -s /bin/bash "$APP_USER" -c "mkdir -p $APP_DIR/tmp/pids $APP_DIR/tmp/sockets $APP_DIR/log $APP_DIR/storage"

# ---------------------------------------------------------------------------
# Install systemd service
# ---------------------------------------------------------------------------
green "==> Installing systemd service..."
cp "$APP_DIR/deploy/glove.service" /etc/systemd/system/glove.service

# Create a drop-in override for OAuth credentials (if not already present).
# Operators fill in the real values after install.
OVERRIDE_DIR="/etc/systemd/system/glove.service.d"
if [[ ! -f "$OVERRIDE_DIR/oauth.conf" ]]; then
  green "==> Creating systemd OAuth credentials override..."
  mkdir -p "$OVERRIDE_DIR"
  cat > "$OVERRIDE_DIR/oauth.conf" <<'EOF'
# Google OAuth2 credentials for the Glove app.
# Replace the placeholder values and then run:
#   sudo systemctl daemon-reload && sudo systemctl restart glove
[Service]
Environment=GOOGLE_CLIENT_ID=changeme
Environment=GOOGLE_CLIENT_SECRET=changeme
EOF
  chmod 600 "$OVERRIDE_DIR/oauth.conf"
  yellow "NOTE: Edit $OVERRIDE_DIR/oauth.conf with your Google OAuth2 credentials."
fi

systemctl daemon-reload
systemctl enable glove.service

# ---------------------------------------------------------------------------
# Start the app
# ---------------------------------------------------------------------------
green "==> Starting Glove app..."
systemctl start glove.service
systemctl status glove.service --no-pager

green ""
green "================================================================"
green "  Installation complete!"
green ""
green "  Service:  systemctl {start|stop|restart|status} glove"
green "  Logs:     journalctl -u glove -f"
green "  App logs: tail -f ${APP_DIR}/log/production.log"
green "================================================================"
