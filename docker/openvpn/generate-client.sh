#!/bin/bash
set -euo pipefail

EASYRSA_DIR="/etc/openvpn/easy-rsa"
PKI_DIR="$EASYRSA_DIR/pki"
OUTPUT_DIR="/etc/openvpn/clients"
REMOTE_HOST="${REMOTE_HOST:?REMOTE_HOST not set. Pass it via docker-compose environment.}"
REMOTE_PORT="1194"

if [ $# -lt 1 ]; then
    echo "Usage: generate-client <client-name>"
    echo "Example: generate-client mehdi-mac"
    if [ -d "$OUTPUT_DIR" ]; then
        echo ""
        echo "Existing clients:"
        ls "$OUTPUT_DIR"/*.ovpn 2>/dev/null | xargs -I{} basename {} .ovpn | sed 's/^/  /'
    fi
    exit 1
fi

CLIENT_NAME="$1"
OUTPUT_FILE="$OUTPUT_DIR/$CLIENT_NAME.ovpn"

echo "=== Generating OpenVPN client: $CLIENT_NAME ==="

if [ ! -f "$PKI_DIR/issued/$CLIENT_NAME.crt" ]; then
    echo "[1/2] Generating client certificate..."
    cd "$EASYRSA_DIR"
    EASYRSA_BATCH=1 ./easyrsa build-client-full "$CLIENT_NAME" nopass
else
    echo "[1/2] Client certificate already exists, reusing."
fi

echo "[2/2] Building .ovpn file..."
mkdir -p "$OUTPUT_DIR"

CA_CERT=$(cat "$PKI_DIR/ca.crt")
CLIENT_CERT=$(openssl x509 -in "$PKI_DIR/issued/$CLIENT_NAME.crt")
CLIENT_KEY=$(cat "$PKI_DIR/private/$CLIENT_NAME.key")
TA_KEY=$(cat "$PKI_DIR/ta.key")

cat > "$OUTPUT_FILE" << EOF
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

chmod 600 "$OUTPUT_FILE"

echo ""
echo "=== Client config created ==="
echo "File: $OUTPUT_FILE"
echo "Remote: $REMOTE_HOST:$REMOTE_PORT (TCP)"
echo ""
echo "To copy it out:"
echo "  docker compose cp openvpn:$OUTPUT_FILE ./configs/$CLIENT_NAME.ovpn"
