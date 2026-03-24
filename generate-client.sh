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
REMOTE="$REMOTE_USER@$REMOTE_HOST"

usage() {
    echo "Generate VPN client configs remotely and download them."
    echo ""
    echo "Usage:"
    echo "  $0 wg <client-name> <ip-octet>     Generate WireGuard client"
    echo "  $0 ovpn <client-name>               Generate OpenVPN client"
    echo ""
    echo "Examples:"
    echo "  $0 wg mehdi-mac 2"
    echo "  $0 ovpn mehdi-mac"
    echo "  $0 wg sina 4"
    exit 1
}

[ $# -lt 2 ] && usage

TYPE="$1"
CLIENT_NAME="$2"

case "$TYPE" in
    wg)
        [ $# -lt 3 ] && { echo "ERROR: WireGuard requires <client-name> <ip-octet>"; usage; }
        OCTET="$3"
        echo "=== Generating WireGuard client: $CLIENT_NAME (10.9.0.$OCTET) ==="
        ssh $SSH_OPTS "$REMOTE" "cd $REMOTE_DIR && docker compose exec -T wireguard generate-client $CLIENT_NAME $OCTET"
        echo ""
        echo "Downloading config..."
        mkdir -p "$SCRIPT_DIR/configs"
        scp $SSH_OPTS "$REMOTE:$REMOTE_DIR/configs/$CLIENT_NAME.conf" "$SCRIPT_DIR/configs/$CLIENT_NAME.conf" 2>/dev/null || \
            ssh $SSH_OPTS "$REMOTE" "cd $REMOTE_DIR && docker compose cp wireguard:/etc/wireguard/clients/$CLIENT_NAME.conf configs/" && \
            scp $SSH_OPTS "$REMOTE:$REMOTE_DIR/configs/$CLIENT_NAME.conf" "$SCRIPT_DIR/configs/$CLIENT_NAME.conf"
        echo "Saved to configs/$CLIENT_NAME.conf"
        ;;
    ovpn)
        echo "=== Generating OpenVPN client: $CLIENT_NAME ==="
        ssh $SSH_OPTS "$REMOTE" "cd $REMOTE_DIR && docker compose exec -T openvpn generate-client $CLIENT_NAME"
        echo ""
        echo "Downloading config..."
        mkdir -p "$SCRIPT_DIR/configs"
        scp $SSH_OPTS "$REMOTE:$REMOTE_DIR/configs/$CLIENT_NAME.ovpn" "$SCRIPT_DIR/configs/$CLIENT_NAME.ovpn" 2>/dev/null || \
            ssh $SSH_OPTS "$REMOTE" "cd $REMOTE_DIR && docker compose cp openvpn:/etc/openvpn/clients/$CLIENT_NAME.ovpn configs/" && \
            scp $SSH_OPTS "$REMOTE:$REMOTE_DIR/configs/$CLIENT_NAME.ovpn" "$SCRIPT_DIR/configs/$CLIENT_NAME.ovpn"
        echo "Saved to configs/$CLIENT_NAME.ovpn"
        ;;
    *)
        echo "ERROR: Unknown type '$TYPE'. Use 'wg' or 'ovpn'."
        usage
        ;;
esac

echo ""
echo "Done."
