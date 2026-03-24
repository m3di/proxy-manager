#!/bin/bash
set -euo pipefail

echo "=== OpenVPN WSL2 Startup ==="

# ── TUN device ───────────────────────────────────────────────────────
echo "[1/4] Ensuring TUN device exists..."
sudo mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    sudo mknod /dev/net/tun c 10 200
    echo "  Created /dev/net/tun"
else
    echo "  /dev/net/tun already exists"
fi
sudo chmod 600 /dev/net/tun

# ── IP forwarding ────────────────────────────────────────────────────
echo "[2/4] Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null

# ── iptables NAT ─────────────────────────────────────────────────────
echo "[3/4] Setting up iptables NAT..."
IFACE=$(ip route show default | awk '{print $5; exit}')
echo "  Default interface: $IFACE"

sudo iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o "$IFACE" -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$IFACE" -j MASQUERADE

sudo iptables -C FORWARD -i tun0 -o "$IFACE" -j ACCEPT 2>/dev/null || \
    sudo iptables -A FORWARD -i tun0 -o "$IFACE" -j ACCEPT

sudo iptables -C FORWARD -i "$IFACE" -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    sudo iptables -A FORWARD -i "$IFACE" -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# ── Start OpenVPN ────────────────────────────────────────────────────
echo "[4/4] Starting OpenVPN..."
if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
    sudo systemctl restart openvpn@server
    echo "  Started via systemd"
else
    sudo pkill -f "openvpn.*server.conf" 2>/dev/null || true
    sleep 1
    sudo openvpn --config /etc/openvpn/server.conf --daemon
    echo "  Started via openvpn --daemon"
fi

sleep 2

# ── Verify ───────────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
if ss -tlnp 2>/dev/null | grep -q ":1194"; then
    echo "  OpenVPN listening on TCP 1194: OK"
else
    echo "  WARNING: OpenVPN NOT listening on TCP 1194"
    echo "  Check logs: sudo tail -50 /var/log/openvpn/openvpn.log"
fi

echo "  IP forwarding: $(cat /proc/sys/net/ipv4/ip_forward)"
echo "  NAT rules:"
sudo iptables -t nat -L POSTROUTING -n --line-numbers 2>/dev/null | grep -E "10\.8\.0" || echo "    (none found)"
echo ""
echo "Done. Remember to run the Windows port-forward script too."
