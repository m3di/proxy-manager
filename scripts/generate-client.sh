#!/bin/bash
set -euo pipefail

# Generate a self-contained .ovpn client config with embedded certificates.
# Usage: ./generate-client.sh <client-name>
# Output: /etc/openvpn/clients/<client-name>.ovpn

EASYRSA_DIR="/etc/openvpn/easy-rsa"
PKI_DIR="$EASYRSA_DIR/pki"
OUTPUT_DIR="/etc/openvpn/clients"
REMOTE_HOST="${REMOTE_HOST:?Set REMOTE_HOST environment variable to your public IP}"
REMOTE_PORT="1194"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <client-name>"
    echo "Example: $0 mehdi-mac"
    exit 1
fi

CLIENT_NAME="$1"
OUTPUT_FILE="$OUTPUT_DIR/$CLIENT_NAME.ovpn"

echo "=== Generating client config: $CLIENT_NAME ==="

# ── Generate client certificate if it doesn't exist ──────────────────
if [ ! -f "$PKI_DIR/issued/$CLIENT_NAME.crt" ]; then
    echo "[1/2] Generating client certificate..."
    cd "$EASYRSA_DIR"
    sudo EASYRSA_BATCH=1 ./easyrsa build-client-full "$CLIENT_NAME" nopass
else
    echo "[1/2] Client certificate already exists, reusing."
fi

# ── Build the .ovpn file ────────────────────────────────────────────
echo "[2/2] Building .ovpn file..."
sudo mkdir -p "$OUTPUT_DIR"

CA_CERT=$(sudo cat "$PKI_DIR/ca.crt")
CLIENT_CERT=$(sudo openssl x509 -in "$PKI_DIR/issued/$CLIENT_NAME.crt")
CLIENT_KEY=$(sudo cat "$PKI_DIR/private/$CLIENT_NAME.key")
TA_KEY=$(sudo cat "$PKI_DIR/ta.key")

sudo tee "$OUTPUT_FILE" > /dev/null << EOF
client
dev tun
proto tcp
remote $REMOTE_HOST $REMOTE_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
key-direction 1
verb 3

<ca>
$CA_CERT
</ca>

<cert>
$CLIENT_CERT
</cert>

<key>
$CLIENT_KEY
</key>

<tls-auth>
$TA_KEY
</tls-auth>
EOF

sudo chmod 600 "$OUTPUT_FILE"

echo ""
echo "=== Client config created ==="
echo "File: $OUTPUT_FILE"
echo "Remote: $REMOTE_HOST:$REMOTE_PORT (TCP)"
echo ""
echo "Transfer this file to the client device securely."
echo "For macOS: use Tunnelblick or OpenVPN Connect"
echo "For iOS/Android: use OpenVPN Connect app"
echo "For Windows: use OpenVPN GUI"
