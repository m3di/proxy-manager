# Windows OpenSSH Server Setup
# Run as Administrator in PowerShell
#
# This enables the built-in OpenSSH server on Windows so you can
# SSH directly into Windows (no WSL2 dependency).

$ErrorActionPreference = "Stop"

Write-Host "=== Windows OpenSSH Server Setup ===" -ForegroundColor Cyan

# ── 1. Install OpenSSH Server ────────────────────────────────────────
Write-Host "[1/5] Installing OpenSSH Server..."
$sshServer = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

if ($sshServer.State -eq "Installed") {
    Write-Host "  Already installed." -ForegroundColor Green
} else {
    Add-WindowsCapability -Online -Name $sshServer.Name
    Write-Host "  Installed." -ForegroundColor Green
}

# ── 2. Start and enable the service ──────────────────────────────────
Write-Host "[2/5] Enabling sshd service..."
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Write-Host "  sshd is running and set to auto-start." -ForegroundColor Green

# ── 3. Firewall rule ────────────────────────────────────────────────
Write-Host "[3/5] Ensuring firewall rule exists..."
$rule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" `
        -DisplayName "OpenSSH Server (TCP 22)" `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort 22 | Out-Null
    Write-Host "  Firewall rule created." -ForegroundColor Green
} else {
    Write-Host "  Firewall rule already exists." -ForegroundColor Green
}

# ── 4. Set default shell to PowerShell ───────────────────────────────
Write-Host "[4/5] Setting default shell to PowerShell..."
$regPath = "HKLM:\SOFTWARE\OpenSSH"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
$pwshPath = (Get-Command powershell.exe).Source
New-ItemProperty -Path $regPath -Name DefaultShell -Value $pwshPath -PropertyType String -Force | Out-Null
Write-Host "  Default shell: $pwshPath" -ForegroundColor Green

# ── 5. Verify ────────────────────────────────────────────────────────
Write-Host "[5/5] Verifying..."
$svc = Get-Service sshd
Write-Host "  Service status: $($svc.Status)" -ForegroundColor Green
Write-Host "  Startup type:   $($svc.StartType)" -ForegroundColor Green

$listening = netstat -an | Select-String ":22\s.*LISTENING"
if ($listening) {
    Write-Host "  Listening on port 22: OK" -ForegroundColor Green
} else {
    Write-Host "  WARNING: Not listening on port 22" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "You can now SSH into this machine:" -ForegroundColor Yellow
Write-Host "  ssh $env:USERNAME@<this-machine-ip>" -ForegroundColor Yellow
Write-Host ""
Write-Host "To copy your SSH key from Mac (run on Mac):" -ForegroundColor Yellow
Write-Host "  ssh-copy-id $env:USERNAME@<this-machine-ip>" -ForegroundColor Yellow
Write-Host ""
Write-Host "NOTE: For admin users, the authorized_keys file is:" -ForegroundColor Yellow
Write-Host "  C:\ProgramData\ssh\administrators_authorized_keys" -ForegroundColor Yellow
Write-Host "If ssh-copy-id puts your key in ~/.ssh/authorized_keys and it" -ForegroundColor Yellow
Write-Host "doesn't work, copy it to the admin file instead:" -ForegroundColor Yellow
Write-Host '  $key = Get-Content C:\Users\' + $env:USERNAME + '\.ssh\authorized_keys' -ForegroundColor Yellow
Write-Host '  Add-Content C:\ProgramData\ssh\administrators_authorized_keys $key' -ForegroundColor Yellow
Write-Host '  icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"' -ForegroundColor Yellow
