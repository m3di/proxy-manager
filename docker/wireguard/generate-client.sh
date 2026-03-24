#!/bin/bash
set -euo pipefail

WG_DIR="/etc/wireguard"
CLIENTS_DIR="$WG_DIR/clients"
SERVER_PUBKEY=$(cat "$WG_DIR/server_public.key")
WG_PORT=51820
WG_SUBNET="10.9.0"
REMOTE_HOST="${REMOTE_HOST:?REMOTE_HOST not set. Pass it via docker-compose environment.}"

if [ $# -lt 2 ]; then
    echo "Usage: generate-client <client-name> <client-ip-last-octet>"
    echo "Example: generate-client mehdi-mac 2"
    echo ""
    echo "Allocated IPs:"
    echo "  .1 = server"
    if [ -d "$CLIENTS_DIR" ]; then
        for f in "$CLIENTS_DIR"/*.conf; do
            [ -f "$f" ] || continue
            name=$(basename "$f" .conf)
            ip=$(grep "Address" "$f" | awk -F= '{print $2}' | tr -d ' ')
            echo "  $ip = $name"
        done
    fi
    exit 1
fi

CLIENT_NAME="$1"
CLIENT_OCTET="$2"
CLIENT_IP="${WG_SUBNET}.${CLIENT_OCTET}"
CLIENT_CONF="$CLIENTS_DIR/$CLIENT_NAME.conf"

echo "=== Generating WireGuard client: $CLIENT_NAME ($CLIENT_IP) ==="

mkdir -p "$CLIENTS_DIR"

# ── Client keys ──────────────────────────────────────────────────────
if [ -f "$CLIENTS_DIR/${CLIENT_NAME}_private.key" ]; then
    echo "[1/3] Client keys already exist, reusing."
else
    echo "[1/3] Generating client keys..."
    wg genkey | tee "$CLIENTS_DIR/${CLIENT_NAME}_private.key" | wg pubkey > "$CLIENTS_DIR/${CLIENT_NAME}_public.key"
    chmod 600 "$CLIENTS_DIR/${CLIENT_NAME}_private.key"
fi

CLIENT_PRIVKEY=$(cat "$CLIENTS_DIR/${CLIENT_NAME}_private.key")
CLIENT_PUBKEY=$(cat "$CLIENTS_DIR/${CLIENT_NAME}_public.key")

# ── Preshared key ────────────────────────────────────────────────────
if [ ! -f "$CLIENTS_DIR/${CLIENT_NAME}_psk.key" ]; then
    wg genpsk > "$CLIENTS_DIR/${CLIENT_NAME}_psk.key"
    chmod 600 "$CLIENTS_DIR/${CLIENT_NAME}_psk.key"
fi
CLIENT_PSK=$(cat "$CLIENTS_DIR/${CLIENT_NAME}_psk.key")

# ── Add peer to server ──────────────────────────────────────────────
echo "[2/3] Adding peer to server..."
if grep -q "$CLIENT_PUBKEY" "$WG_DIR/wg0.conf" 2>/dev/null; then
    echo "  Peer already in config"
else
    cat >> "$WG_DIR/wg0.conf" << EOF

# $CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBKEY
PresharedKey = $CLIENT_PSK
AllowedIPs = ${CLIENT_IP}/32
EOF
    echo "  Added peer to wg0.conf"

    if wg show wg0 &>/dev/null; then
        PSK_TMP=$(mktemp)
        echo "$CLIENT_PSK" > "$PSK_TMP"
        wg set wg0 peer "$CLIENT_PUBKEY" preshared-key "$PSK_TMP" allowed-ips "${CLIENT_IP}/32"
        rm -f "$PSK_TMP"
        echo "  Hot-added peer to running interface"
    fi
fi

# ── Client config ────────────────────────────────────────────────────
echo "[3/3] Writing client config..."
cat > "$CLIENT_CONF" << EOF
[Interface]
PrivateKey = $CLIENT_PRIVKEY
Address = ${CLIENT_IP}/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBKEY
PresharedKey = $CLIENT_PSK
Endpoint = ${REMOTE_HOST}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 "$CLIENT_CONF"

echo ""
echo "=== Client config created ==="
echo "File: $CLIENT_CONF"
echo "Client IP: $CLIENT_IP"
echo "Endpoint: ${REMOTE_HOST}:${WG_PORT}"
echo ""
echo "To copy it out:"
echo "  docker compose cp wireguard:$CLIENT_CONF ./configs/$CLIENT_NAME.conf"

if command -v qrencode &>/dev/null; then
    echo ""
    echo "=== QR Code ==="
    cat "$CLIENT_CONF" | qrencode -t ansiutf8
fi
