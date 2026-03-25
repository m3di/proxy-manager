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

## Quick Start (on Windows)

### 1. Clone and configure

```bash
git clone https://github.com/<your-user>/proxy-manager.git
cd proxy-manager
cp .env.example .env
# Edit .env — at minimum set VPN_PUBLIC_IP to your static public IP
```

### 2. Install Docker Desktop

Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) with the WSL2 backend, and set it to start on Windows login.

### 3. Start the VPN servers

```bash
docker compose up -d
```

Both VPNs start, networking is configured, and they auto-restart on reboot.

### 4. Generate client configs

```bash
docker compose exec wireguard generate-client my-device 2
docker compose cp wireguard:/etc/wireguard/clients/my-device.conf ./configs/

docker compose exec openvpn generate-client my-device
docker compose cp openvpn:/etc/openvpn/clients/my-device.ovpn ./configs/
```

### 5. Router port forwards

Forward these on your router to the Windows host LAN IP:
- TCP 1194 (OpenVPN)
- UDP 51820 (WireGuard)

That's all you need. The VPNs are running.

## Remote Management from Mac (optional)

If you want to deploy changes and generate configs from your Mac without
touching the Windows machine, enable SSH on Windows:

### One-time SSH setup

On Windows, open **Admin PowerShell** and run:

```powershell
.\scripts\setup-windows-ssh.ps1
```

This tries the built-in Windows capability first. If that fails (WSUS policies,
disabled Windows Update, debloated installs), it automatically downloads the
official OpenSSH release from GitHub as a fallback.

Then set up key auth from your Mac:

```bash
ssh-copy-id <user>@<windows-ip>

# If key auth doesn't work (Windows admin user quirk), SSH in and run:
#   $key = Get-Content $env:USERPROFILE\.ssh\authorized_keys
#   Set-Content C:\ProgramData\ssh\administrators_authorized_keys $key
#   icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
```

### Deploy from Mac

After making changes locally:

```bash
./deploy.sh
```

Syncs the project to Windows via rsync, rebuilds containers, restarts services.

### Generate clients from Mac

```bash
./generate-client.sh wg mehdi-mac 2
./generate-client.sh ovpn mehdi-mac
```

Generates inside the container and downloads the config file to `configs/`.

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
├── generate-client.sh              # Generate client configs remotely
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
./generate-client.sh wg <name> <n> # Generate WireGuard client remotely
./generate-client.sh ovpn <name>   # Generate OpenVPN client remotely
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
