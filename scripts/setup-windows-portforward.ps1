# VPN Windows Port Forwarding Setup
# Run as Administrator in PowerShell
#
# This script:
#   1. Detects WSL2's current internal IP
#   2. Sets up netsh portproxy for TCP services (OpenVPN, SSH)
#   3. Starts a UDP relay job for WireGuard (netsh can't forward UDP)
#   4. Creates firewall rules
#
# Re-run after every WSL restart (WSL2 IP changes on reboot).

$ErrorActionPreference = "Stop"

Write-Host "=== VPN Windows Port Forwarding ===" -ForegroundColor Cyan

# ── Detect WSL2 IP ───────────────────────────────────────────────────
Write-Host "[1/5] Detecting WSL2 IP..."
$wslIp = (wsl hostname -I).Trim().Split(" ")[0]
if (-not $wslIp) {
    Write-Host "ERROR: Could not detect WSL2 IP. Is WSL running?" -ForegroundColor Red
    exit 1
}
Write-Host "  WSL2 IP: $wslIp" -ForegroundColor Green

# ── TCP port proxy (OpenVPN + SSH) ───────────────────────────────────
Write-Host "[2/5] Setting up TCP port proxies..."

netsh interface portproxy delete v4tov4 listenport=1194 listenaddress=0.0.0.0 2>$null
netsh interface portproxy add v4tov4 listenport=1194 listenaddress=0.0.0.0 connectport=1194 connectaddress=$wslIp
Write-Host "  OpenVPN:  0.0.0.0:1194 -> ${wslIp}:1194 (TCP)" -ForegroundColor Green

netsh interface portproxy delete v4tov4 listenport=2222 listenaddress=0.0.0.0 2>$null
netsh interface portproxy add v4tov4 listenport=2222 listenaddress=0.0.0.0 connectport=22 connectaddress=$wslIp
Write-Host "  SSH:      0.0.0.0:2222 -> ${wslIp}:22   (TCP)" -ForegroundColor Green

# ── UDP relay for WireGuard ──────────────────────────────────────────
Write-Host "[3/5] Starting UDP relay for WireGuard (port 51820)..."

# Kill any existing relay
Get-Process -Name "powershell","pwsh" -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -eq "WG-UDP-Relay" } |
    Stop-Process -Force -ErrorAction SilentlyContinue 2>$null

# Start UDP relay as a background job
$relayScript = @"
`$title = 'WG-UDP-Relay'
`$host.UI.RawUI.WindowTitle = `$title

`$listenPort = 51820
`$targetIp = '$wslIp'
`$targetPort = 51820

`$udpClient = New-Object System.Net.Sockets.UdpClient(`$listenPort)
`$udpClient.Client.ReceiveTimeout = 5000
Write-Host "UDP relay: 0.0.0.0:`$listenPort -> `${targetIp}:`$targetPort"

`$clients = @{}

while (`$true) {
    try {
        `$remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        `$data = `$udpClient.Receive([ref]`$remoteEP)

        `$remoteKey = "`$(`$remoteEP.Address):`$(`$remoteEP.Port)"

        if (-not `$clients.ContainsKey(`$remoteKey)) {
            `$forwardClient = New-Object System.Net.Sockets.UdpClient
            `$forwardClient.Connect(`$targetIp, `$targetPort)
            `$clients[`$remoteKey] = @{ Client = `$forwardClient; EP = `$remoteEP; LastSeen = [DateTime]::Now }

            # Start background receive from WG server back to this client
            `$null = [System.Threading.Tasks.Task]::Run({
                param(`$fc, `$uc, `$ep)
                `$serverEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                while (`$true) {
                    try {
                        `$reply = `$fc.Receive([ref]`$serverEP)
                        `$null = `$uc.Send(`$reply, `$reply.Length, `$ep)
                    } catch { break }
                }
            }.GetNewClosure())
        }

        `$clients[`$remoteKey].LastSeen = [DateTime]::Now
        `$null = `$clients[`$remoteKey].Client.Send(`$data, `$data.Length)

    } catch [System.Net.Sockets.SocketException] {
        # Timeout, clean up old clients
        `$now = [DateTime]::Now
        `$stale = `$clients.Keys | Where-Object { (`$now - `$clients[`$_].LastSeen).TotalSeconds -gt 120 }
        foreach (`$k in `$stale) {
            `$clients[`$k].Client.Close()
            `$clients.Remove(`$k)
        }
    }
}
"@

$relayFile = "$env:TEMP\wg-udp-relay.ps1"
$relayScript | Out-File -FilePath $relayFile -Encoding UTF8 -Force

Start-Process powershell -ArgumentList "-WindowStyle Hidden -File `"$relayFile`"" -WindowStyle Hidden
Write-Host "  WireGuard: 0.0.0.0:51820 -> ${wslIp}:51820 (UDP relay)" -ForegroundColor Green

# ── Firewall rules ───────────────────────────────────────────────────
Write-Host "[4/5] Ensuring firewall rules exist..."

$rules = @(
    @{ Name = "OpenVPN TCP 1194"; Protocol = "TCP"; Port = 1194 },
    @{ Name = "WireGuard UDP 51820"; Protocol = "UDP"; Port = 51820 }
)

foreach ($r in $rules) {
    $existing = Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow -Protocol $r.Protocol -LocalPort $r.Port | Out-Null
        Write-Host "  Created: $($r.Name)" -ForegroundColor Green
    } else {
        Write-Host "  Exists:  $($r.Name)" -ForegroundColor Green
    }
}

# ── Summary ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Current TCP Port Proxy Rules ===" -ForegroundColor Cyan
netsh interface portproxy show all

Write-Host ""
Write-Host "[5/5] Summary" -ForegroundColor Cyan
Write-Host "  SSH:       TCP 2222  -> WSL2:22"
Write-Host "  OpenVPN:   TCP 1194  -> WSL2:1194"
Write-Host "  WireGuard: UDP 51820 -> WSL2:51820 (background relay)"
Write-Host ""
Write-Host "ADSL router port forwards needed:"
Write-Host "  TCP 1194  -> 192.168.2.5 (OpenVPN)"
Write-Host "  UDP 51820 -> 192.168.2.5 (WireGuard)"
