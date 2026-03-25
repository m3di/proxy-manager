# Windows OpenSSH Server Setup
# Run as Administrator in PowerShell
#
# Installs OpenSSH Server so you can SSH directly into Windows.
# Tries the built-in Windows capability first. If that fails (WSUS,
# disabled Windows Update, debloated installs), falls back to
# downloading the official Microsoft OpenSSH release from GitHub.

$ErrorActionPreference = "Stop"

Write-Host "=== Windows OpenSSH Server Setup ===" -ForegroundColor Cyan

# ── 0. Admin check ──────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Run this script as Administrator." -ForegroundColor Red
    exit 1
}

# ── 1. Install OpenSSH Server ───────────────────────────────────────
Write-Host "[1/5] Installing OpenSSH Server..."

$sshdService = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshdService) {
    Write-Host "  sshd service already exists, skipping install." -ForegroundColor Green
} else {
    $installed = $false

    # ── Method 1: Windows capability (works on vanilla Windows) ──
    Write-Host "  Trying Windows Optional Feature install..."
    $canInstallCapability = $true

    # Preflight: check if Windows Update service is disabled
    $wuSvc = Get-Service wuauserv -ErrorAction SilentlyContinue
    if ($wuSvc -and $wuSvc.StartType -eq "Disabled") {
        Write-Host "  Windows Update service (wuauserv) is disabled." -ForegroundColor Yellow
        $canInstallCapability = $false
    }

    # Preflight: check for WSUS policy
    $wsusKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (Test-Path $wsusKey) {
        $disableAccess = (Get-ItemProperty -Path $wsusKey -Name "DisableWindowsUpdateAccess" -ErrorAction SilentlyContinue).DisableWindowsUpdateAccess
        $useWU = (Get-ItemProperty -Path "$wsusKey\AU" -Name "UseWUServer" -ErrorAction SilentlyContinue).UseWUServer
        if ($disableAccess -eq 1 -or $useWU -eq 1) {
            Write-Host "  WSUS / Windows Update policy detected (DisableWindowsUpdateAccess=$disableAccess, UseWUServer=$useWU)." -ForegroundColor Yellow
            $canInstallCapability = $false
        }
    }

    if ($canInstallCapability) {
        try {
            $sshCap = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object Name -like 'OpenSSH.Server*'
            if ($sshCap -and $sshCap.State -ne "Installed") {
                Add-WindowsCapability -Online -Name $sshCap.Name -ErrorAction Stop | Out-Null
                Write-Host "  Installed via Windows capability." -ForegroundColor Green
                $installed = $true
            } elseif ($sshCap.State -eq "Installed") {
                Write-Host "  Already installed via Windows capability." -ForegroundColor Green
                $installed = $true
            }
        } catch {
            Write-Host "  Windows capability install failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Skipping capability install (Windows Update/WSUS restrictions)." -ForegroundColor Yellow
    }

    # ── Method 2: Download from GitHub ───────────────────────────
    if (-not $installed) {
        Write-Host ""
        Write-Host "  Falling back to GitHub release install..." -ForegroundColor Cyan

        $sshDir = "$env:ProgramFiles\OpenSSH-Win64"

        if (Test-Path "$sshDir\sshd.exe") {
            Write-Host "  OpenSSH binaries already exist at $sshDir" -ForegroundColor Green
        } else {
            Write-Host "  Downloading OpenSSH from GitHub..."
            $releasesUrl = "https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest"
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $release = Invoke-RestMethod -Uri $releasesUrl -ErrorAction Stop
                $asset = $release.assets | Where-Object { $_.name -like "OpenSSH-Win64*.zip" -and $_.name -notlike "*symbols*" } | Select-Object -First 1
                if (-not $asset) {
                    Write-Host "ERROR: Could not find OpenSSH-Win64 zip in latest release." -ForegroundColor Red
                    exit 1
                }

                $zipPath = "$env:TEMP\OpenSSH-Win64.zip"
                $extractPath = "$env:TEMP\OpenSSH-Extract"

                Write-Host "  Downloading $($asset.name)..."
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -ErrorAction Stop

                Write-Host "  Extracting..."
                if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
                Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

                $extracted = Get-ChildItem $extractPath | Where-Object { $_.PSIsContainer } | Select-Object -First 1
                if (Test-Path $sshDir) { Remove-Item $sshDir -Recurse -Force }
                Move-Item $extracted.FullName $sshDir

                Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "  Extracted to $sshDir" -ForegroundColor Green
            } catch {
                Write-Host "ERROR: Failed to download OpenSSH: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host ""
                Write-Host "Manual fallback: download OpenSSH-Win64.zip from:" -ForegroundColor Yellow
                Write-Host "  https://github.com/PowerShell/Win32-OpenSSH/releases/latest" -ForegroundColor Yellow
                Write-Host "Extract to $sshDir and re-run this script." -ForegroundColor Yellow
                exit 1
            }
        }

        # Install sshd service from the downloaded binaries
        Write-Host "  Installing sshd service..."
        & "$sshDir\install-sshd.ps1"

        # Add to PATH if not already there
        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($machinePath -notlike "*$sshDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$machinePath;$sshDir", "Machine")
            $env:Path = "$env:Path;$sshDir"
            Write-Host "  Added $sshDir to system PATH." -ForegroundColor Green
        }

        # Generate host keys if missing
        if (-not (Test-Path "$env:ProgramData\ssh\ssh_host_ed25519_key")) {
            Write-Host "  Generating host keys..."
            & "$sshDir\ssh-keygen.exe" -A
        }

        Write-Host "  Installed via GitHub release." -ForegroundColor Green
    }
}

# ── 2. Start and enable the service ─────────────────────────────────
Write-Host "[2/5] Enabling sshd service..."
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue
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

# ── 4. Set default shell to PowerShell ──────────────────────────────
Write-Host "[4/5] Setting default shell to PowerShell..."
$regPath = "HKLM:\SOFTWARE\OpenSSH"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
$pwshPath = (Get-Command powershell.exe).Source
New-ItemProperty -Path $regPath -Name DefaultShell -Value $pwshPath -PropertyType String -Force | Out-Null
Write-Host "  Default shell: $pwshPath" -ForegroundColor Green

# ── 5. Verify ───────────────────────────────────────────────────────
Write-Host "[5/5] Verifying..."
$svc = Get-Service sshd -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "  Service status: $($svc.Status)" -ForegroundColor Green
    Write-Host "  Startup type:   $($svc.StartType)" -ForegroundColor Green
} else {
    Write-Host "  ERROR: sshd service not found after install." -ForegroundColor Red
    exit 1
}

$listening = netstat -an | Select-String ":22\s.*LISTENING"
if ($listening) {
    Write-Host "  Listening on port 22: OK" -ForegroundColor Green
} else {
    Write-Host "  WARNING: Not listening on port 22. Try: Restart-Service sshd" -ForegroundColor Yellow
}

# ── Done ────────────────────────────────────────────────────────────
$lanIPs = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" }).IPAddress -join ", "

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "This machine's LAN IP(s): $lanIPs" -ForegroundColor Green
Write-Host ""
Write-Host "From your Mac, test with:" -ForegroundColor Yellow
Write-Host "  ssh $env:USERNAME@<LAN_IP>" -ForegroundColor Yellow
Write-Host ""
Write-Host "Set up key auth (run on Mac):" -ForegroundColor Yellow
Write-Host "  ssh-copy-id $env:USERNAME@<LAN_IP>" -ForegroundColor Yellow
Write-Host ""
Write-Host "If key auth doesn't work (admin user), SSH in and run:" -ForegroundColor Yellow
Write-Host '  $key = Get-Content $env:USERPROFILE\.ssh\authorized_keys' -ForegroundColor Yellow
Write-Host '  Set-Content C:\ProgramData\ssh\administrators_authorized_keys $key' -ForegroundColor Yellow
Write-Host '  icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"' -ForegroundColor Yellow
