#!/bin/bash
set -euo pipefail

EASYRSA_DIR="/etc/openvpn/easy-rsa"
PKI_DIR="$EASYRSA_DIR/pki"
SERVER_DIR="/etc/openvpn/server"
OPENVPN_CONF="/etc/openvpn/server.conf"
LOG_DIR="/var/log/openvpn"

echo "=== OpenVPN Server Setup for WSL2 ==="

# ── 1. Install packages ──────────────────────────────────────────────
echo "[1/7] Installing openvpn and easy-rsa..."
sudo apt-get update -qq
sudo apt-get install -y openvpn easy-rsa iptables

# ── 2. Create TUN device ─────────────────────────────────────────────
echo "[2/7] Creating TUN device..."
sudo mkdir -p /dev/net
sudo mknod /dev/net/tun c 10 200 2>/dev/null || true
sudo chmod 600 /dev/net/tun

# ── 3. Set up Easy-RSA PKI ───────────────────────────────────────────
echo "[3/7] Setting up PKI with Easy-RSA..."
sudo mkdir -p "$EASYRSA_DIR"
sudo cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR"/

if [ -d "$PKI_DIR" ]; then
    echo "  PKI already exists at $PKI_DIR, skipping init."
    echo "  To regenerate, remove $PKI_DIR and re-run."
else
    cd "$EASYRSA_DIR"

    sudo ./easyrsa init-pki

    # Build CA non-interactively
    echo "  Building Certificate Authority..."
    sudo EASYRSA_BATCH=1 ./easyrsa build-ca nopass

    # Generate server certificate
    echo "  Generating server certificate..."
    sudo EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass

    # Generate Diffie-Hellman parameters (takes a minute)
    echo "  Generating DH parameters (this takes a while)..."
    sudo ./easyrsa gen-dh

    # Generate TLS-auth key
    echo "  Generating TLS-auth key..."
    sudo openvpn --genkey secret "$PKI_DIR/ta.key"
fi

# ── 4. Copy certs to server directory ────────────────────────────────
echo "[4/7] Copying certificates to $SERVER_DIR..."
sudo mkdir -p "$SERVER_DIR"
sudo cp "$PKI_DIR/ca.crt"                "$SERVER_DIR/ca.crt"
sudo cp "$PKI_DIR/issued/server.crt"     "$SERVER_DIR/server.crt"
sudo cp "$PKI_DIR/private/server.key"    "$SERVER_DIR/server.key"
sudo cp "$PKI_DIR/dh.pem"               "$SERVER_DIR/dh.pem"
sudo cp "$PKI_DIR/ta.key"               "$SERVER_DIR/ta.key"

sudo chmod 600 "$SERVER_DIR/server.key" "$SERVER_DIR/ta.key"

# ── 5. Install server config ────────────────────────────────────────
echo "[5/7] Installing server configuration..."
sudo tee "$OPENVPN_CONF" > /dev/null << 'SERVERCONF'
port 1194
proto tcp
dev tun

ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh /etc/openvpn/server/dh.pem
tls-auth /etc/openvpn/server/ta.key 0

server 10.8.0.0 255.255.255.0

ifconfig-pool-persist /var/log/openvpn/ipp.txt

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"

keepalive 10 120

cipher AES-256-GCM
auth SHA256

user nobody
group nogroup

persist-key
persist-tun

status /var/log/openvpn/openvpn-status.log
log-append /var/log/openvpn/openvpn.log
verb 3

max-clients 10
explicit-exit-notify 0
SERVERCONF

# ── 6. Enable IP forwarding and NAT ─────────────────────────────────
echo "[6/7] Enabling IP forwarding and NAT..."
sudo sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-openvpn.conf > /dev/null

IFACE=$(ip route show default | awk '{print $5; exit}')
echo "  Detected default interface: $IFACE"

sudo iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o "$IFACE" -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$IFACE" -j MASQUERADE

sudo iptables -C FORWARD -i tun0 -o "$IFACE" -j ACCEPT 2>/dev/null || \
    sudo iptables -A FORWARD -i tun0 -o "$IFACE" -j ACCEPT

sudo iptables -C FORWARD -i "$IFACE" -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    sudo iptables -A FORWARD -i "$IFACE" -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# ── 7. Create log directory and start OpenVPN ────────────────────────
echo "[7/7] Starting OpenVPN..."
sudo mkdir -p "$LOG_DIR"

if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
    sudo systemctl enable openvpn@server 2>/dev/null || true
    sudo systemctl restart openvpn@server
    echo "  Started via systemd (openvpn@server)"
else
    sudo pkill -f "openvpn.*server.conf" 2>/dev/null || true
    sleep 1
    sudo openvpn --config "$OPENVPN_CONF" --daemon
    echo "  Started via openvpn --daemon"
fi

echo ""
echo "=== Setup Complete ==="
echo "Server listening on TCP 1194"
echo "VPN subnet: 10.8.0.0/24"
echo ""
echo "Next steps:"
echo "  1. Run generate-client.sh to create client configs"
echo "  2. Set up Windows port forwarding (setup-windows-portforward.ps1)"
echo "  3. Forward TCP 1194 on ADSL router to Windows 192.168.2.5"
