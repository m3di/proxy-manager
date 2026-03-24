#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Load config ──────────────────────────────────────────────────────
ENV_FILE="$SCRIPT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: .env file not found. Copy .env.example to .env and fill in your values."
    exit 1
fi
source "$ENV_FILE"

REMOTE_USER="${DEPLOY_USER:?Set DEPLOY_USER in .env}"
REMOTE_HOST="${DEPLOY_HOST:?Set DEPLOY_HOST in .env}"
REMOTE_PORT="${DEPLOY_PORT:-22}"
REMOTE_DIR="${DEPLOY_DIR:?Set DEPLOY_DIR in .env}"
SSH_OPTS="-p $REMOTE_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=5"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[deploy]${NC} $*"; }
ok()   { echo -e "${GREEN}[deploy]${NC} $*"; }
fail() { echo -e "${RED}[deploy]${NC} $*"; exit 1; }

REMOTE="$REMOTE_USER@$REMOTE_HOST"

# ── Preflight ────────────────────────────────────────────────────────
log "Testing SSH connection to Windows ($REMOTE:$REMOTE_PORT)..."
ssh $SSH_OPTS "$REMOTE" "echo ok" > /dev/null 2>&1 || \
    fail "Cannot reach $REMOTE on port $REMOTE_PORT. Is Windows OpenSSH running?"

log "Checking Docker availability..."
ssh $SSH_OPTS "$REMOTE" "docker info > /dev/null 2>&1" || \
    fail "Docker not available. Is Docker Desktop running?"

# ── Sync ─────────────────────────────────────────────────────────────
log "Syncing project files..."
rsync -avz --delete \
    --exclude '.git' \
    --exclude '.DS_Store' \
    --exclude '.env' \
    --exclude 'configs/*.ovpn' \
    --exclude 'configs/*.conf' \
    --include 'configs/server.conf' \
    -e "ssh $SSH_OPTS" \
    "$SCRIPT_DIR/" \
    "$REMOTE:$REMOTE_DIR/"

# Push .env separately (contains deployment-specific config)
log "Syncing .env..."
scp $SSH_OPTS "$SCRIPT_DIR/.env" "$REMOTE:$REMOTE_DIR/.env"

ok "Files synced to $REMOTE:$REMOTE_DIR"

# ── Build & Deploy ───────────────────────────────────────────────────
log "Building and deploying containers..."
ssh $SSH_OPTS "$REMOTE" "cd $REMOTE_DIR && docker compose build && docker compose up -d"

# ── Verify ───────────────────────────────────────────────────────────
log "Verifying..."
sleep 3
ssh $SSH_OPTS "$REMOTE" "cd $REMOTE_DIR && docker compose ps"

echo ""
ok "Deploy complete."
