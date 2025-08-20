# CrowdStrike Falcon Sensor installation script
# Executed via AWS SSM -> RunPowerShellScript
# Output is captured and parsed by controller.py

$ErrorActionPreference = "Stop"

# Config
$TempDir = "C:\Temp"
$InstallerUrl = "https://artifactory.helix.gsa.gov/artifactory/Workspaces-Ubuntu/WindowsSensor.GovLaggar.exe"
$InstallerPath = Join-Path $TempDir "WindowsSensor.GovLaggar.exe"
$CID = "37690B110B014A5FACBC08C84A1F9D4-55"
$GroupingTags = "IQ-FCS-Workspaces"

function Write-Log {
    param([string]$Message)
    Write-Output "[CROWDSTRIKE] $Message"
}

try {
    # Check if CrowdStrike is already installed
    $Installed = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* 2>$null | Where-Object {
        $_.DisplayName -match "CrowdStrike"
    }

    if ($Installed) {
        Write-Log "CrowdStrike Falcon Sensor already installed: $($Installed.DisplayName)"
        exit 0
    }

    # Ensure Temp directory exists
    if (-not (Test-Path $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
        Write-Log "Temp directory created at $TempDir"
    }

    # Download installer
    Write-Log "Downloading CrowdStrike installer..."
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop
    Write-Log "Installer downloaded successfully: $InstallerPath"

    # Run installer
    Write-Log "Installing CrowdStrike Falcon Sensor..."
    Start-Process -FilePath $InstallerPath -ArgumentList "/quiet /install /norestart CID=$CID GROUPING_TAGS=$GroupingTags" -Wait -ErrorAction Stop

    Start-Sleep -Seconds 10

    # Verify installation
    $Installed = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* 2>$null | Where-Object {
        $_.DisplayName -match "CrowdStrike"
    }

    if ($Installed) {
        Write-Log "CrowdStrike installed successfully: $($Installed.DisplayName)"
        exit 0
    }
    else {
        Write-Log "Installation attempted but CrowdStrike not found in registry."
        exit 1
    }
}
catch {
    Write-Log "Error during CrowdStrike installation: $($_.Exception.Message)"
    exit 1
}
