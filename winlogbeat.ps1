# Set Time Zone to Eastern Standard Time
tzutil /s "Eastern Standard Time"

# Create Install Log Folder
$LogFolder = "C:\Security-Agents-Install-Logs"
if (-Not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force
    Write-Host "Log folder created at $LogFolder"
} else {
    Write-Host "Log folder already exists at $LogFolder"
}

# Function to check if Winlogbeat is installed
function IsWinlogbeatInstalled {
    $Service = Get-Service -Name "winlogbeat" -ErrorAction SilentlyContinue
    return $Service
}

# Define variables
$SoftwareName = "Winlogbeat"
$ZipSourcePath = "\\gtd.gsa.gov\SYSVOL\gtd.gsa.gov\scripts\Workspaces\Security-Agents\winlogbeat\winlogbeat-7.9.2-windows-x86_64.zip"
$TempDir = "C:\Temp"
$ZipDestination = "$TempDir\winlogbeat-7.9.2-windows-x86_64.zip"
$ExtractedPath = "$TempDir\winlogbeat-7.9.2-windows-x86_64"
$LogFilePath = "$LogFolder\winlogbeat_install.log"

# If already installed, exit
if (IsWinlogbeatInstalled) {
    Write-Host "$SoftwareName is already installed and running."
    Exit 0
}

# Ensure temp directory exists
if (-Not (Test-Path $TempDir)) {
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    Write-Host "Temp directory created at $TempDir"
}

try {
    # Copy installer zip
    Copy-Item -Path $ZipSourcePath -Destination $ZipDestination -Force
    Write-Host "Copied $SoftwareName installer to $ZipDestination"

    # Extract
    Expand-Archive -Path $ZipDestination -DestinationPath $TempDir -Force
    Write-Host "Extracted $SoftwareName files to $ExtractedPath"

    # Navigate and install
    Set-Location $ExtractedPath

    if (Test-Path ".\install-service-winlogbeat.ps1") {
        Write-Host "Running $SoftwareName install script..."
        .\install-service-winlogbeat.ps1 | Out-File -FilePath $LogFilePath -Append

        # Wait briefly
        Start-Sleep -Seconds 5

        # Start service
        Start-Service -Name "winlogbeat" -ErrorAction Stop
        Write-Host "$SoftwareName service started."

        Start-Sleep -Seconds 3
        $ServiceStatus = Get-Service -Name "winlogbeat" -ErrorAction SilentlyContinue
        if ($ServiceStatus.Status -eq "Running") {
            Write-Host "$SoftwareName installed and running successfully."
        } else {
            Write-Host "Failed to start $SoftwareName. Current status: $($ServiceStatus.Status)"
        }
    } else {
        Write-Host "Error: install-service-winlogbeat.ps1 not found in $ExtractedPath"
    }
} catch {
    Write-Host "Error during $SoftwareName installation: $_"
    Write-Host "Check the log at $LogFilePath for details."
    Exit 1
}
