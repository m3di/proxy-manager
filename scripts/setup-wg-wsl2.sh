#!/bin/bash
set -euo pipefail

WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/wg0.conf"
WG_PORT=51820
WG_SUBNET="10.9.0"
CLIENTS_DIR="$WG_DIR/clients"

echo "=== WireGuard Server Setup for WSL2 ==="

# ── 1. Install packages ──────────────────────────────────────────────
echo "[1/5] Installing wireguard and tools..."
sudo apt-get update -qq
sudo apt-get install -y wireguard wireguard-tools qrencode

# ── 2. Create TUN device ─────────────────────────────────────────────
echo "[2/5] Ensuring TUN device exists..."
sudo mkdir -p /dev/net
sudo mknod /dev/net/tun c 10 200 2>/dev/null || true
sudo chmod 600 /dev/net/tun

# ── 3. Generate server keys ──────────────────────────────────────────
echo "[3/5] Generating server keys..."
sudo mkdir -p "$WG_DIR"
if [ ! -f "$WG_DIR/server_private.key" ]; then
    wg genkey | sudo tee "$WG_DIR/server_private.key" > /dev/null
    sudo chmod 600 "$WG_DIR/server_private.key"
    sudo cat "$WG_DIR/server_private.key" | wg pubkey | sudo tee "$WG_DIR/server_public.key" > /dev/null
    echo "  Generated new server keypair"
else
    echo "  Server keys already exist, reusing"
fi

SERVER_PRIVKEY=$(sudo cat "$WG_DIR/server_private.key")
SERVER_PUBKEY=$(sudo cat "$WG_DIR/server_public.key")
echo "  Server public key: $SERVER_PUBKEY"

# ── 4. Write server config ───────────────────────────────────────────
echo "[4/5] Writing server config..."
IFACE=$(ip route show default | awk '{print $5; exit}')

sudo tee "$WG_CONF" > /dev/null << EOF
[Interface]
Address = ${WG_SUBNET}.1/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVKEY}

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -s ${WG_SUBNET}.0/24 -o ${IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -s ${WG_SUBNET}.0/24 -o ${IFACE} -j MASQUERADE
EOF

sudo chmod 600 "$WG_CONF"

# ── 5. Enable IP forwarding and bring up ─────────────────────────────
echo "[5/5] Enabling IP forwarding and starting WireGuard..."
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null

sudo wg-quick down wg0 2>/dev/null || true
sudo wg-quick up wg0

echo ""
echo "=== Setup Complete ==="
echo "WireGuard listening on UDP $WG_PORT"
echo "VPN subnet: ${WG_SUBNET}.0/24"
echo "Server public key: $SERVER_PUBKEY"
echo ""
echo "Next steps:"
echo "  1. Run generate-wg-client.sh to create client configs"
echo "  2. Set up Windows UDP relay (setup-windows-portforward.ps1)"
echo "  3. Forward UDP $WG_PORT on ADSL router to Windows 192.168.2.5"
