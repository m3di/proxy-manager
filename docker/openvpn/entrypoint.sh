#!/bin/bash
set -euo pipefail

EASYRSA_DIR="/etc/openvpn/easy-rsa"
PKI_DIR="$EASYRSA_DIR/pki"
SERVER_DIR="/etc/openvpn/server"
OPENVPN_CONF="/etc/openvpn/server.conf"
LOG_DIR="/var/log/openvpn"

mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200
chmod 600 /dev/net/tun

# ── PKI setup (first run only) ──────────────────────────────────────
if [ ! -d "$PKI_DIR" ]; then
    echo "[openvpn] Initializing PKI (first run)..."
    mkdir -p "$EASYRSA_DIR"
    cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR"/
    cd "$EASYRSA_DIR"

    ./easyrsa init-pki
    EASYRSA_BATCH=1 ./easyrsa build-ca nopass
    EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass
    ./easyrsa gen-dh
    openvpn --genkey secret "$PKI_DIR/ta.key"
    echo "[openvpn] PKI initialized."
else
    echo "[openvpn] PKI already exists, reusing."
    if [ ! -d "$EASYRSA_DIR/keys" ] && [ ! -f "$EASYRSA_DIR/easyrsa" ]; then
        cp -rn /usr/share/easy-rsa/* "$EASYRSA_DIR"/ 2>/dev/null || true
    fi
fi

# ── Copy certs ───────────────────────────────────────────────────────
mkdir -p "$SERVER_DIR"
cp -u "$PKI_DIR/ca.crt"             "$SERVER_DIR/ca.crt"
cp -u "$PKI_DIR/issued/server.crt"  "$SERVER_DIR/server.crt"
cp -u "$PKI_DIR/private/server.key" "$SERVER_DIR/server.key"
cp -u "$PKI_DIR/dh.pem"            "$SERVER_DIR/dh.pem"
cp -u "$PKI_DIR/ta.key"            "$SERVER_DIR/ta.key"
chmod 600 "$SERVER_DIR/server.key" "$SERVER_DIR/ta.key"

# ── Server config ────────────────────────────────────────────────────
cat > "$OPENVPN_CONF" << 'EOF'
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
EOF

# ── Networking ───────────────────────────────────────────────────────
echo "[openvpn] Configuring NAT..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null

IFACE=$(ip route show default | awk '{print $5; exit}')
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$IFACE" -j MASQUERADE
iptables -A FORWARD -i tun0 -o "$IFACE" -j ACCEPT
iptables -A FORWARD -i "$IFACE" -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT

mkdir -p "$LOG_DIR"

echo "[openvpn] Starting OpenVPN on TCP 1194..."
exec openvpn --config "$OPENVPN_CONF"
