# Deployment for the Glove app.
#
# Production runs directly from this checkout: all state (SQLite databases,
# uploaded files, secrets) lives inside this directory. The only artifacts
# outside it are the systemd units that `make install` generates from the
# templates in deploy/.
#
# Run make as the user that will own the service (normally your login user,
# not root). Recipes use sudo where system access is required.
#
#   make install    one-time (and after Ruby upgrades): apt deps + systemd units
#   make update     make the running service reflect the current working tree
#   make status     service + backup timer status
#   make logs       follow the service journal
#
# See deploy/DEPLOYMENT.md for the full runbook, including machine migration.

APP_DIR      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SERVICE_USER := $(shell id -un)
# mise.toml pins the Ruby this app runs on.
RUBY_DIR     := $(shell cd $(APP_DIR) && mise where ruby 2>/dev/null)
SYSTEMD_DIR  := /etc/systemd/system

# Substitutes template placeholders when generating systemd units.
RENDER = sed \
	-e 's|@APP_DIR@|$(APP_DIR)|g' \
	-e 's|@RUBY_DIR@|$(RUBY_DIR)|g' \
	-e 's|@SERVICE_USER@|$(SERVICE_USER)|g'

# Loads .env before rails commands so settings like RAILS_RELATIVE_URL_ROOT
# apply to db:prepare and assets:precompile, not just the running service.
LOAD_ENV = set -a && { [ ! -f .env ] || . ./.env; } && set +a

.PHONY: install install-deps install-web install-backup update restart status logs check-ruby

install: install-deps install-web install-backup

check-ruby:
	@test -n "$(RUBY_DIR)" && test -x "$(RUBY_DIR)/bin/ruby" || { \
		echo "error: no mise-managed Ruby found (mise where ruby). Run: mise install"; \
		exit 1; \
	}

install-deps:
	sudo apt-get update -qq
	sudo apt-get install -y -qq \
		build-essential git curl rsync sqlite3 libsqlite3-dev libvips \
		libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev

install-web: check-ruby
	$(RENDER) deploy/glove-web.service.tmpl | sudo tee $(SYSTEMD_DIR)/glove-web.service >/dev/null
	sudo systemctl daemon-reload
	sudo systemctl enable glove-web.service
	@echo "Installed glove-web.service (WorkingDirectory=$(APP_DIR), User=$(SERVICE_USER))"

install-backup:
	@test -f deploy/backup.env || \
		echo "WARNING: deploy/backup.env is missing — backups will fail until it exists (see deploy/backup.env.example)"
	$(RENDER) deploy/glove-backup.service.tmpl | sudo tee $(SYSTEMD_DIR)/glove-backup.service >/dev/null
	sudo install -m 644 deploy/glove-backup.timer $(SYSTEMD_DIR)/glove-backup.timer
	sudo systemctl daemon-reload
	sudo systemctl enable --now glove-backup.timer

# No git operations here by design: production runs whatever the working
# tree contains, and git is the operator's business. db:prepare migrates but
# never drops or recreates the production databases.
update: check-ruby
	cd $(APP_DIR) && PATH="$(RUBY_DIR)/bin:$$PATH" bundle install
	cd $(APP_DIR) && $(LOAD_ENV) && PATH="$(RUBY_DIR)/bin:$$PATH" RAILS_ENV=production bin/rails db:prepare
	cd $(APP_DIR) && $(LOAD_ENV) && PATH="$(RUBY_DIR)/bin:$$PATH" RAILS_ENV=production bin/rails assets:precompile
	sudo systemctl restart glove-web.service

restart:
	sudo systemctl restart glove-web.service

status:
	@systemctl status glove-web.service --no-pager || true
	@echo
	@systemctl list-timers glove-backup.timer --no-pager || true

logs:
	journalctl -u glove-web -f
