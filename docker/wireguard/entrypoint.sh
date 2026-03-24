#!/bin/bash
set -euo pipefail

WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/wg0.conf"
WG_PORT=51820
WG_SUBNET="10.9.0"

mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200
chmod 600 /dev/net/tun

# ── Generate server keys (first run only) ────────────────────────────
if [ ! -f "$WG_DIR/server_private.key" ]; then
    echo "[wireguard] Generating server keys (first run)..."
    wg genkey | tee "$WG_DIR/server_private.key" | wg pubkey > "$WG_DIR/server_public.key"
    chmod 600 "$WG_DIR/server_private.key"
    echo "[wireguard] Server keys generated."
else
    echo "[wireguard] Server keys exist, reusing."
fi

SERVER_PRIVKEY=$(cat "$WG_DIR/server_private.key")
SERVER_PUBKEY=$(cat "$WG_DIR/server_public.key")
echo "[wireguard] Server public key: $SERVER_PUBKEY"

# ── Write server config (preserving peers) ───────────────────────────
IFACE=$(ip route show default | awk '{print $5; exit}')

if [ ! -f "$WG_CONF" ]; then
    echo "[wireguard] Creating initial server config..."
    cat > "$WG_CONF" << EOF
[Interface]
Address = ${WG_SUBNET}.1/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVKEY}

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -s ${WG_SUBNET}.0/24 -o ${IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -s ${WG_SUBNET}.0/24 -o ${IFACE} -j MASQUERADE
EOF
    chmod 600 "$WG_CONF"
else
    echo "[wireguard] Config exists, updating interface name..."
    # The default interface may differ between runs, update PostUp/PostDown
    sed -i "s|-o [a-z0-9]* -j MASQUERADE|-o ${IFACE} -j MASQUERADE|g" "$WG_CONF"
    sed -i "s|-o [a-z0-9]* -j ACCEPT|-o ${IFACE} -j ACCEPT|g" "$WG_CONF" 2>/dev/null || true
fi

# ── Networking ───────────────────────────────────────────────────────
echo "[wireguard] Configuring networking..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null

echo "[wireguard] Starting WireGuard on UDP $WG_PORT..."
wg-quick up wg0

# wg-quick runs in background; keep container alive and show status
sleep 1
wg show wg0

echo "[wireguard] Running. Waiting for signals..."
# Graceful shutdown
trap 'echo "[wireguard] Shutting down..."; wg-quick down wg0; exit 0' SIGTERM SIGINT

while true; do
    sleep 60 &
    wait $!
done
