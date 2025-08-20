# BigFix Client installation script
# Executed via AWS SSM -> RunPowerShellScript
# Output will be captured by controller.py

$ErrorActionPreference = "Stop"
$ServiceName = "BESClient"
$InstallDir = "C:\Temp\BigFix"
$InstallerName = "BigFixClient_11.1.8.32_setup.exe"
$InstallerUrl = "https://artifactory.helix.gsa.gov/artifactory/Workspaces-Ubuntu/BigFix/$InstallerName"
$InstallerPath = Join-Path $InstallDir $InstallerName
$LogFile = "$InstallDir\install_bigfix.log"

function Write-Log {
    param([string]$Message)
    Write-Output "[BIGFIX] $Message"
}

try {
    # Check if already installed
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log "BigFix already installed. Status: $($service.Status)"
        exit 0
    }

    # Clean and recreate temp folder
    if (Test-Path $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Force -Recurse
    }
    New-Item -Path $InstallDir -ItemType Directory | Out-Null

    # Enable TLS 1.2 and TLS 1.1
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11

    # Download installer
    Write-Log "Downloading BigFix installer..."
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing

    # Run installer silently
    Write-Log "Installing BigFix Client..."
    $arguments = "/s /v`"/lv*$LogFile /qn`""
    Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -NoNewWindow

    # Wait and check service
    Start-Sleep -Seconds 15
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($service) {
        if ($service.Status -ne "Running") {
            Start-Service -Name $ServiceName
        }
        Write-Log "BigFix Client installed successfully. Status: $($service.Status)"
        exit 0
    }
    else {
        Write-Log "Installation attempted but BESClient service not found."
        exit 1
    }
}
catch {
    Write-Log "Error during installation: $($_.Exception.Message)"
    exit 1
}
