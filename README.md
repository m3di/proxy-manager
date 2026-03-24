# Proxy Manager

A personal VPN gateway running OpenVPN (TCP) and WireGuard (UDP) in Docker containers. Clients connect via a static public IP, traffic exits through a second ISP.

## Architecture

```
Client (phone/Mac/PC)
  |
  |  TCP 1194 (OpenVPN)  or  UDP 51820 (WireGuard)
  v
Router (<public IP>)
  |
  |  port forward
  v
Windows Host (<LAN IP>)
  |
  |  Docker Desktop (WSL2 backend)
  v
┌─────────────────────────────────────────┐
│  Docker                                 │
│  ┌─────────────┐   ┌─────────────────┐  │
│  │  openvpn    │   │  wireguard      │  │
│  │  TCP 1194   │   │  UDP 51820      │  │
│  │  tun0       │   │  wg0            │  │
│  │  10.8.0.0/24│   │  10.9.0.0/24    │  │
│  └─────────────┘   └─────────────────┘  │
│         |                   |            │
│         └───────┬───────────┘            │
│                 v                        │
│          iptables MASQUERADE             │
└─────────────────────────────────────────┘
  |
  v
Internet exit (second ISP)
```

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/<your-user>/proxy-manager.git
cd proxy-manager
cp .env.example .env
# Edit .env with your public IP, SSH user, host, etc.
```

### 2. One-time Windows setup

On the Windows machine, open an **Admin PowerShell** and run:

```powershell
# Enable Windows native SSH server
.\scripts\setup-windows-ssh.ps1
```

Then install [Docker Desktop](https://www.docker.com/products/docker-desktop/) and set it to start on login.

### 3. Start the VPN servers

```bash
docker compose up -d
```

Both VPNs start, networking is configured, and they auto-restart on reboot.

### 4. Generate client configs

**OpenVPN:**

```bash
docker compose exec openvpn generate-client my-device
docker compose cp openvpn:/etc/openvpn/clients/my-device.ovpn ./configs/
```

**WireGuard:**

```bash
docker compose exec wireguard generate-client my-device 2
docker compose cp wireguard:/etc/wireguard/clients/my-device.conf ./configs/
```

### 5. Router port forwards

Forward these on your router to the Windows host LAN IP:
- TCP 1194 (OpenVPN)
- UDP 51820 (WireGuard)

## Deploy from Mac

After making changes locally, deploy to the Windows machine:

```bash
./deploy.sh
```

This SSHes directly into Windows (native OpenSSH, port 22 — no WSL2 dependency), syncs the project, rebuilds containers, and restarts services.

Set up key auth first:

```bash
ssh-copy-id <user>@<windows-ip>

# If key auth doesn't work (Windows admin user quirk), SSH in and run:
#   $key = Get-Content C:\Users\<user>\.ssh\authorized_keys
#   Add-Content C:\ProgramData\ssh\administrators_authorized_keys $key
#   icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
```

## Configuration

All deployment-specific values live in `.env` (not committed to git):

| Variable | Purpose | Example |
|----------|---------|---------|
| `VPN_PUBLIC_IP` | Public IP clients connect to | `203.0.113.1` |
| `DEPLOY_USER` | Windows SSH username | `john` |
| `DEPLOY_HOST` | Windows LAN IP | `192.168.1.100` |
| `DEPLOY_PORT` | SSH port (default 22) | `22` |
| `DEPLOY_DIR` | Project path on Windows | `C:/Users/john/proxy-manager` |

## Project Structure

```
.
├── README.md
├── REFERENCE.md                    # Infrastructure reference (fill in your values)
├── .env.example                    # Template for deployment config
├── .env                            # Your config (gitignored)
├── docker-compose.yml
├── deploy.sh                       # Deploy from Mac to Windows
├── docker/
│   ├── openvpn/
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   └── generate-client.sh
│   └── wireguard/
│       ├── Dockerfile
│       ├── entrypoint.sh
│       └── generate-client.sh
├── configs/                        # Client configs (gitignored)
│   └── server.conf                 # OpenVPN server config reference
└── scripts/
    ├── setup-windows-ssh.ps1       # One-time: enable Windows OpenSSH
    └── ...                         # Legacy WSL2 scripts
```

## Commands

```bash
docker compose up -d               # Start both VPNs
docker compose down                # Stop both VPNs
docker compose restart             # Restart both VPNs
docker compose ps                  # Status
docker compose logs openvpn        # OpenVPN logs
docker compose logs wireguard      # WireGuard logs
docker compose exec wireguard wg   # WireGuard status
docker compose build               # Rebuild images after Dockerfile changes
./deploy.sh                        # Sync + rebuild + restart from Mac
```

## Data Persistence

VPN data (keys, certs, configs) is stored in Docker named volumes:

- `openvpn-data` -> `/etc/openvpn`
- `wireguard-data` -> `/etc/wireguard`

These survive `docker compose down` and rebuilds. Only `docker volume rm` destroys them.

### Backup

```bash
docker run --rm -v openvpn-data:/data -v $(pwd)/backup:/backup alpine tar czf /backup/openvpn-backup.tar.gz -C /data .
docker run --rm -v wireguard-data:/data -v $(pwd)/backup:/backup alpine tar czf /backup/wireguard-backup.tar.gz -C /data .
```

### Restore

```bash
docker run --rm -v openvpn-data:/data -v $(pwd)/backup:/backup alpine tar xzf /backup/openvpn-backup.tar.gz -C /data
docker run --rm -v wireguard-data:/data -v $(pwd)/backup:/backup alpine tar xzf /backup/wireguard-backup.tar.gz -C /data
```

## History

Started as a Go application with xray-core. Moved to bare WSL2 services with manual startup scripts. Now runs in Docker containers with automated deployment.

See [REFERENCE.md](REFERENCE.md) for detailed infrastructure documentation.
