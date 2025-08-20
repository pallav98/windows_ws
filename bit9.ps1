# Set Time Zone to Eastern Standard Time
tzutil /s "Eastern Standard Time"

# Ensure Event Log Source Exists
if (-not [System.Diagnostics.EventLog]::SourceExists("Workspace-Initialization")) {
    New-EventLog -LogName Application -Source "Workspace-Initialization"
}

# Create Install Log Folder
$LogFolder = "C:\Security-Agents-Install-Logs"
if (-Not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force
    Write-Host "Log folder created at $LogFolder"
}

# Function to Check if Software is Installed
function IsSoftwareInstalled {
    param([string]$SoftwareName)

    $InstalledSoftware = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*$SoftwareName*" }

    $InstalledSoftware += Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*$SoftwareName*" }

    return $InstalledSoftware
}

# Variables
$SoftwareName = "Carbon Black App Control Agent"
$InstallerPath = "\\gtd.gsa.gov\SYSVOL\gtd.gsa.gov\scripts\Workspaces\Security-Agents\Bit9\bit9.msi"
$LogFilePath = "$LogFolder\bit9_install.log"

# Check if already installed
$checkvar = IsSoftwareInstalled -SoftwareName $SoftwareName

if (-not $checkvar) {
    $output_msg = "Attempting to install $SoftwareName..."
    Write-Host $output_msg
    Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 100 -Message $output_msg

    if (-not (Test-Path $InstallerPath)) {
        $output_msg = "Installer not found at $InstallerPath."
        Write-Host $output_msg
        Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 404 -Message $output_msg
        exit 1
    }

    try {
        Start-Process msiexec.exe -ArgumentList "/i `"$InstallerPath`" /L*v `"$LogFilePath`" /quiet" -Wait -NoNewWindow -ErrorAction Stop
        Start-Sleep -Seconds 10

        $checkvar = IsSoftwareInstalled -SoftwareName $SoftwareName
        if ($checkvar) {
            $output_msg = "$SoftwareName installed successfully."
            Write-Host $output_msg
            Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 1 -Message $output_msg
            exit 0
        } else {
            $output_msg = "Failed to install $SoftwareName. Check the log at $LogFilePath."
            Write-Host $output_msg
            Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 500 -Message $output_msg
            exit 1
        }
    } catch {
        $output_msg = "Error during installation: $_"
        Write-Host $output_msg
        Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 580 -Message $output_msg
        exit 1
    }
} else {
    $output_msg = "$SoftwareName is already installed."
    Write-Host $output_msg
    Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 2 -Message $output_msg
    exit 0
}
