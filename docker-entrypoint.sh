#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/data/hermes}"

# Ensure directory structure exists
for dir in skills sessions logs memories cron; do
    mkdir -p "$HERMES_HOME/$dir"
done

# Copy default config if none exists
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    echo "First run: copying default config to $HERMES_HOME/config.yaml"
    cp /opt/hermes/app/cli-config.yaml.example "$HERMES_HOME/config.yaml"
    # Set terminal backend to local (safe default for Docker)
    sed -i 's/backend: local/backend: local/' "$HERMES_HOME/config.yaml"
fi

# Copy .env template if none exists
if [ ! -f "$HERMES_HOME/.env" ]; then
    echo "First run: copying .env template to $HERMES_HOME/.env"
    cp /opt/hermes/app/.env.example "$HERMES_HOME/.env"
fi

# Sync bundled skills
if [ -f /opt/hermes/app/tools/skills_sync.py ]; then
    python /opt/hermes/app/tools/skills_sync.py 2>/dev/null || true
fi

# Start SSH server if enabled
if [ "${ENABLE_SSH:-false}" = "true" ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    if [ -f /data/hermes/.ssh/authorized_keys ]; then
        cp /data/hermes/.ssh/authorized_keys ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
    fi
    sudo /usr/sbin/sshd
    echo "SSH server started on port 22"
fi

exec hermes "$@"
