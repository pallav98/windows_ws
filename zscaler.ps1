<#
.SYNOPSIS
    Installs Zscaler silently on Windows WorkSpaces

.DESCRIPTION
    This script is designed to be invoked from AWS SSM via controller.py.
    It checks if Zscaler is already installed, downloads the MSI from Artifactory,
    installs it silently, logs output, and returns proper exit codes.

.EXITCODES
    0  - Success
    1  - Already installed
    2  - Download failed
    3  - Install failed
#>

# ========================
# Setup
# ========================
$ErrorActionPreference = "Stop"
$LogFolder = "C:\Security-Agents-Install-Logs"
$LogFile   = Join-Path $LogFolder "zscaler.log"

if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logMsg = "[$timestamp] $Message"
    Write-Host $logMsg
    Add-Content -Path $LogFile -Value $logMsg
}

Write-Log "===== Starting Zscaler Installation ====="

# ========================
# Pre-check: Already Installed?
# ========================
$installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -match "Zscaler" }
if ($installed) {
    Write-Log "Zscaler is already installed. Version: $($installed.Version)"
    Exit 0
}

# ========================
# Download
# ========================
$installDir = "C:\Temp\Zscaler"
$installerPath = Join-Path $installDir "Zscaler-windows-gov-4.4.500.19-installer.msi"
$url = "https://artifactory.helix.gsa.gov/artifactory/Workspaces-Ubuntu/Zscaler"

if (Test-Path $installDir) { Remove-Item -LiteralPath $installDir -Force -Recurse }
New-Item -Path $installDir -ItemType Directory -Force | Out-Null

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    Write-Log "Downloading Zscaler installer..."
    $fullUrl = "$url/Zscaler-windows-gov-4.4.500.19-installer.msi"
    Invoke-WebRequest -Uri $fullUrl -OutFile $installerPath -ErrorAction Stop
    Write-Log "Downloaded to $installerPath"
} catch {
    Write-Log "ERROR: Failed to download Zscaler installer: $($_.Exception.Message)"
    Exit 2
}

# ========================
# Install
# ========================
try {
    Write-Log "Starting silent installation..."

    $msiArguments = @(
        "/i `"$installerPath`""
        "CLOUDNAME=zscalergov"
        "USERDOMAIN=gsa.gov"
        "ENABLEFIPS=1"
        "STRICTENFORCEMENT=1"
        "POLICYTOKEN=2235382433366&613662637663920383562642034656565200237339206862356239353363323135"
        "/qn"
        "/norestart"
        "/log `"$LogFolder\Zscaler_install.log`""
    ) -join " "

    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -eq 0) {
        Write-Log "SUCCESS: Zscaler installed successfully."
        Exit 0
    } else {
        Write-Log "ERROR: Installation failed. ExitCode=$($process.ExitCode)"
        Exit 3
    }
} catch {
    Write-Log "ERROR: Exception during installation: $($_.Exception.Message)"
    Exit 3
}
