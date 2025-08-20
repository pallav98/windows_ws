# Function to check if software is installed
function CheckIfInstalled {
    param([string]$SoftwareName)
    $INSTALLED = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
        Select-Object DisplayName, DisplayVersion, UninstallString
    $INSTALLED += Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
        Select-Object DisplayName, DisplayVersion, UninstallString
    return $INSTALLED | Where-Object { $_.DisplayName -match $SoftwareName }
}

# Ensure Event Log Source Exists
if (-not [System.Diagnostics.EventLog]::SourceExists("Workspace-Initialization")) {
    New-EventLog -LogName Application -Source "Workspace-Initialization"
}

# Variables
$SoftwareName   = "UniversalForwarder"
$InstallerPath  = "\\gtd.gsa.gov\SYSVOL\gtd.gsa.gov\scripts\Workspaces\Security-Agents\Splunk\splunkforwarder-9.1.7.msi"
$LogPath        = "C:\Security-Agents-Install-Logs\SplunkInstallLog.log"
$Arguments      = "/i `"$InstallerPath`" DEPLOYMENT_SERVER=10.176.2.54:8089 LAUNCHSPLUNK=1 SPLUNKUSER=admin SPLUNKPASSWORD=Workspace123# SERVICESTARTTYPE=auto AGREETOLICENSE=yes /quiet /L*V `"$LogPath`""

# Check if already installed
$checkvar = CheckIfInstalled -SoftwareName $SoftwareName

if (-not $checkvar) {
    $output_msg = "[$SoftwareName] not found. Starting installation..."
    Write-Host $output_msg
    Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 100 -Message $output_msg

    if (-not (Test-Path $InstallerPath)) {
        $output_msg = "[$SoftwareName] installer not found at $InstallerPath"
        Write-Host $output_msg
        Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 500 -Message $output_msg
        exit 1
    }

    try {
        Start-Process msiexec.exe -Verb RunAs -ArgumentList $Arguments -Wait -ErrorAction Stop
        Write-Host "Installation completed. Validating..."

        $checkvar = CheckIfInstalled -SoftwareName $SoftwareName
        if ($checkvar) {
            $output_msg = "[$SoftwareName] installed successfully."
            Write-Host $output_msg
            Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 200 -Message $output_msg
            exit 0
        } else {
            $output_msg = "[$SoftwareName] installation failed. Check log at $LogPath."
            Write-Host $output_msg
            Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 404 -Message $output_msg
            exit 1
        }
    } catch {
        $output_msg = "[$SoftwareName] installation error: $_"
        Write-Host $output_msg
        Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 580 -Message $output_msg
        exit 1
    }
}
else {
    $output_msg = "[$SoftwareName] already installed."
    Write-Host $output_msg
    Write-EventLog -LogName Application -Source "Workspace-Initialization" -EventID 300 -Message $output_msg
    exit 0
}
