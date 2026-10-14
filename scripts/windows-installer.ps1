<#
Windows one-click installer for wechat-mini-demo
Usage:
1. Right-click the PowerShell file -> Run with PowerShell (or open PowerShell as Administrator and run: .\windows-installer.ps1)
2. The script will check for Node.js, try to install it (via Chocolatey if available), download the repo ZIP from GitHub, extract, run npm install and create a Start shortcut on Desktop.

Notes:
- Installing Node silently requires Administrator rights. If the script can't install Node automatically it will prompt you to install Node manually from https://nodejs.org and then re-run this script.
- This script uses the repository: https://github.com/Aa135246-a/wechat-mini-demo
- The script attempts to be safe and will not overwrite an existing installation unless you confirm.
#>

param(
    [string]$InstallFolder = "$env:USERPROFILE\\wechat-mini",
    [string]$RepoZipUrl = 'https://github.com/Aa135246-a/wechat-mini-demo/archive/refs/heads/main.zip'
)

function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Ensure running in PowerShell
if ($PSVersionTable -eq $null) {
    Write-Err "Please run this script inside PowerShell."; exit 1
}

Write-Info "wechat-mini Demo Installer"
Write-Info "Install folder: $InstallFolder"

# Check admin
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Warn "It is recommended to run this script as Administrator for automatic Node installation and shortcut creation."
}

# Check Node.js
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    $nodeVersion = (& node -v) -replace "\r|\n",""
    Write-Info "Node.js found: $nodeVersion"
} else {
    Write-Warn "Node.js not found. Attempting automatic installation..."

    # Try Chocolatey if available
    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if ($choco -and $IsAdmin) {
        Write-Info "Installing Node.js LTS via Chocolatey..."
        choco install nodejs-lts -y --no-progress
    } else {
        # Try direct MSI download from nodejs.org
        Write-Info "Downloading Node.js LTS MSI..."
        $tmp = Join-Path $env:TEMP "node-lts.msi"
        try {
            Invoke-WebRequest -Uri "https://nodejs.org/dist/v20.8.1/node-v20.8.1-x64.msi" -OutFile $tmp -UseBasicParsing -ErrorAction Stop
            Write-Info "Downloaded to $tmp"
            if ($IsAdmin) {
                Write-Info "Starting MSI installer (silent)..."
                Start-Process msiexec.exe -ArgumentList "/i `"$tmp`" /qn /norestart" -Wait -NoNewWindow
                Write-Info "MSI installer finished."
            } else {
                Write-Warn "Cannot run MSI installer silently without Administrator. Please run the MSI installer manually: $tmp"
                Write-Info "Or install Node.js from https://nodejs.org and re-run this script after Node is installed."
                Pause
            }
        } catch {
            Write-Err "Failed to download or run Node.js MSI: $_"
            Write-Info "Please install Node.js LTS manually from https://nodejs.org and re-run this script."
            Pause
        }
    }
}

# Re-check Node
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Err "Node.js is not installed. The installer cannot continue."
    exit 1
}

# Ensure npm exists
$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npm) { Write-Warn "npm not found even though node exists. Continuing but may fail." }

# Prepare install folder
if (Test-Path $InstallFolder) {
    Write-Warn "Install folder already exists: $InstallFolder"
    $ans = Read-Host "Do you want to overwrite it? (y/N)"
    if ($ans -ne 'y' -and $ans -ne 'Y') {
        Write-Info "Installation canceled by user."; exit 0
    }
    Remove-Item -Recurse -Force $InstallFolder
}

New-Item -Path $InstallFolder -ItemType Directory -Force | Out-Null
Push-Location $InstallFolder

# Download repo ZIP
$zipPath = Join-Path $InstallFolder "repo.zip"
Write-Info "Downloading repository..."
try {
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
    Write-Info "Downloaded repository to $zipPath"
} catch {
    Write-Err "Failed to download repository: $_"; exit 1
}

# Extract
Write-Info "Extracting..."
try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $InstallFolder -Force
    Remove-Item $zipPath -Force
    # After extraction, there's a folder like repo-main
    $dirs = Get-ChildItem -Directory | Where-Object { $_.Name -like '*wechat-mini-demo*' }
    if ($dirs.Count -ge 1) {
        $src = $dirs[0].FullName
        Write-Info "Source folder: $src"
    } else {
        Write-Err "Could not find extracted source folder."; exit 1
    }
} catch {
    Write-Err "Extraction failed: $_"; exit 1
}

# Install dependencies
Push-Location $src
Write-Info "Running npm install (this may take a few minutes)..."
$env:NPM_CONFIG_REGISTRY = 'https://registry.npmmirror.com'
try {
    npm install --no-audit --no-fund
    Write-Info "npm install finished"
} catch {
    Write-Err "npm install failed: $_"; Write-Info "You can try running 'npm install' manually in $src"; exit 1
}

# Create start script
$startBat = Join-Path $src "start.bat"
$startContent = '@echo off
cd /d %~dp0
node server.js
pause'
Set-Content -Path $startBat -Value $startContent -Encoding UTF8

# Create desktop shortcut (if running as admin)
if ($IsAdmin) {
    try {
        $WScriptShell = New-Object -ComObject WScript.Shell
        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnk = $WScriptShell.CreateShortcut((Join-Path $desktop 'Wechat-Mini Start.lnk'))
        $lnk.TargetPath = $startBat
        $lnk.WorkingDirectory = $src
        $lnk.IconLocation = 'shell32.dll,1'
        $lnk.Save()
        Write-Info "Created desktop shortcut."
    } catch {
        Write-Warn "Failed to create desktop shortcut: $_"
    }
}

Write-Info "Installation complete. The app is installed in: $src"
Write-Info "To start the app, double-click start.bat in the folder or the desktop shortcut."

# Optionally start now
$startNow = Read-Host "Start the app now? (Y/n)"
if ($startNow -eq '' -or $startNow -eq 'Y' -or $startNow -eq 'y') {
    Start-Process -FilePath $startBat -WorkingDirectory $src
}

Pop-Location
Pop-Location

Write-Info "Done."
