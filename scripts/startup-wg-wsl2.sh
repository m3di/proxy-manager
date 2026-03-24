#!/bin/bash
set -euo pipefail

echo "=== WireGuard WSL2 Startup ==="

# ── TUN device ───────────────────────────────────────────────────────
echo "[1/3] Ensuring TUN device exists..."
sudo mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    sudo mknod /dev/net/tun c 10 200
    echo "  Created /dev/net/tun"
else
    echo "  /dev/net/tun already exists"
fi
sudo chmod 600 /dev/net/tun

# ── IP forwarding ────────────────────────────────────────────────────
echo "[2/3] Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null

# ── Start WireGuard ──────────────────────────────────────────────────
echo "[3/3] Starting WireGuard..."
sudo wg-quick down wg0 2>/dev/null || true
sudo wg-quick up wg0

sleep 1

# ── Verify ───────────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
if sudo wg show wg0 &>/dev/null; then
    echo "  WireGuard wg0 interface: UP"
    sudo wg show wg0 | head -5
else
    echo "  WARNING: WireGuard wg0 NOT running"
fi

echo "  IP forwarding: $(cat /proc/sys/net/ipv4/ip_forward)"
echo ""

# Check if listening on UDP port
WG_PORT=$(sudo wg show wg0 listen-port 2>/dev/null || echo "unknown")
if ss -ulnp 2>/dev/null | grep -q ":${WG_PORT}"; then
    echo "  Listening on UDP ${WG_PORT}: OK"
else
    echo "  WARNING: Not listening on UDP ${WG_PORT}"
fi

echo ""
echo "Done. Remember to run the Windows port-forward script too."
