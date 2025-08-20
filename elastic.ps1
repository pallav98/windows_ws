# Elastic Agent installation script
# Executed via AWS SSM -> RunPowerShellScript
# Output is captured and parsed by controller.py

$ErrorActionPreference = "Stop"
$AgentExe = "C:\Program Files\Elastic\Agent\elastic-agent.exe"
$ZipFile = "C:\elastic-agent-8.8.0-windows-x86_64.zip"
$ExtractPath = "C:\elastic-agent-8.8.0-windows-x86_64"
$SourcePath = "\\gtd.gsa.gov\SYSVOL\gtd.gsa.gov\scripts\Workspaces\Security-Agents\elastic\elastic-agent-8.8.0-windows-x86_64.zip"

$EnrollUrl = "https://5b94f6e48be841b4a7bb5dcdf4c8322d.fleet.us-gov-east-1.aws.elastic-cloud.com:443"
$EnrollToken = "d1hCSjNvc8JcmVaU69QMm9HR06GN16BY1lWMkVSUzJmX21NTHLanhkQQ=="
$AgentTag = "IQ-FCS"

function Write-Log {
    param([string]$Message)
    Write-Output "[ELASTIC] $Message"
}

try {
    # Check if already installed
    if (Test-Path $AgentExe) {
        $version = & $AgentExe version 2>$null
        Write-Log "Elastic Agent already installed. Version: $version"
        exit 0
    }

    # Copy installer ZIP
    Write-Log "Copying Elastic Agent installer..."
    Copy-Item -Path $SourcePath -Destination $ZipFile -Force -ErrorAction Stop

    # Extract installer
    if (Test-Path $ExtractPath) {
        Remove-Item -LiteralPath $ExtractPath -Force -Recurse
    }
    Write-Log "Extracting installer..."
    Expand-Archive -Path $ZipFile -DestinationPath C:\ -Force -ErrorAction Stop

    # Run installation
    $InstallExe = Join-Path $ExtractPath "elastic-agent.exe"
    if (-not (Test-Path $InstallExe)) {
        Write-Log "Error: elastic-agent.exe not found after extraction"
        exit 1
    }

    Write-Log "Installing Elastic Agent..."
    & $InstallExe install `
        --url=$EnrollUrl `
        --enrollment-token=$EnrollToken `
        --non-interactive --force --tag $AgentTag

    Start-Sleep -Seconds 15

    # Verify installation
    if (Test-Path $AgentExe) {
        $version = & $AgentExe version 2>$null
        Write-Log "Elastic Agent installed successfully. Version: $version"
        exit 0
    }
    else {
        Write-Log "Installation attempted but elastic-agent.exe not found."
        exit 1
    }
}
catch {
    Write-Log "Error during Elastic Agent installation: $($_.Exception.Message)"
    exit 1
}
