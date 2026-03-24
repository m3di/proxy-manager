#!/bin/bash
set -euo pipefail

# Generate a WireGuard client config and add the peer to the server.
# Usage: ./generate-wg-client.sh <client-name> <client-ip-last-octet>
# Example: ./generate-wg-client.sh mehdi-mac 2

WG_DIR="/etc/wireguard"
CLIENTS_DIR="$WG_DIR/clients"
SERVER_PUBKEY=$(sudo cat "$WG_DIR/server_public.key")
WG_PORT=51820
WG_SUBNET="10.9.0"
REMOTE_HOST="${REMOTE_HOST:?Set REMOTE_HOST environment variable to your public IP}"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <client-name> <client-ip-last-octet>"
    echo "Example: $0 mehdi-mac 2"
    echo ""
    echo "Allocated IPs:"
    echo "  .1 = server"
    if [ -d "$CLIENTS_DIR" ]; then
        find "$CLIENTS_DIR" -name '*.conf' -maxdepth 1 2>/dev/null | while read -r f; do
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

sudo mkdir -p "$CLIENTS_DIR"

# ── Generate client keys ─────────────────────────────────────────────
if [ -f "$CLIENTS_DIR/${CLIENT_NAME}_private.key" ]; then
    echo "[1/3] Client keys already exist, reusing."
else
    echo "[1/3] Generating client keys..."
    wg genkey | sudo tee "$CLIENTS_DIR/${CLIENT_NAME}_private.key" > /dev/null
    sudo cat "$CLIENTS_DIR/${CLIENT_NAME}_private.key" | wg pubkey | sudo tee "$CLIENTS_DIR/${CLIENT_NAME}_public.key" > /dev/null
    sudo chmod 600 "$CLIENTS_DIR/${CLIENT_NAME}_private.key"
fi

CLIENT_PRIVKEY=$(sudo cat "$CLIENTS_DIR/${CLIENT_NAME}_private.key")
CLIENT_PUBKEY=$(sudo cat "$CLIENTS_DIR/${CLIENT_NAME}_public.key")

# ── Generate preshared key ───────────────────────────────────────────
if [ ! -f "$CLIENTS_DIR/${CLIENT_NAME}_psk.key" ]; then
    wg genpsk | sudo tee "$CLIENTS_DIR/${CLIENT_NAME}_psk.key" > /dev/null
    sudo chmod 600 "$CLIENTS_DIR/${CLIENT_NAME}_psk.key"
fi
CLIENT_PSK=$(sudo cat "$CLIENTS_DIR/${CLIENT_NAME}_psk.key")

# ── Add peer to server config ────────────────────────────────────────
echo "[2/3] Adding peer to server..."
if sudo grep -q "$CLIENT_PUBKEY" "$WG_DIR/wg0.conf" 2>/dev/null; then
    echo "  Peer already in config"
else
    sudo tee -a "$WG_DIR/wg0.conf" > /dev/null << EOF

# $CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBKEY
PresharedKey = $CLIENT_PSK
AllowedIPs = ${CLIENT_IP}/32
EOF
    echo "  Added peer to wg0.conf"

    # Hot-add if wg0 is running
    if sudo wg show wg0 &>/dev/null; then
        PSK_TMP=$(mktemp)
        echo "$CLIENT_PSK" > "$PSK_TMP"
        sudo wg set wg0 peer "$CLIENT_PUBKEY" preshared-key "$PSK_TMP" allowed-ips "${CLIENT_IP}/32"
        rm -f "$PSK_TMP"
        echo "  Hot-added peer to running interface"
    fi
fi

# ── Write client config file ─────────────────────────────────────────
echo "[3/3] Writing client config..."
sudo tee "$CLIENT_CONF" > /dev/null << EOF
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

sudo chmod 600 "$CLIENT_CONF"

echo ""
echo "=== Client config created ==="
echo "File: $CLIENT_CONF"
echo "Client IP: $CLIENT_IP"
echo "Endpoint: ${REMOTE_HOST}:${WG_PORT}"
echo ""
echo "Transfer this file to the client device securely."
echo "For macOS/Windows: use WireGuard app, import tunnel"
echo "For iOS/Android: use WireGuard app, scan QR or import file"

# Show QR code if qrencode is available
if command -v qrencode &>/dev/null; then
    echo ""
    echo "=== QR Code (scan with WireGuard mobile app) ==="
    sudo cat "$CLIENT_CONF" | qrencode -t ansiutf8
fi
