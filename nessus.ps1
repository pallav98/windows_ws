<#
.SYNOPSIS
  Ensure Nessus Agent is installed, running, and properly linked.
.DESCRIPTION
  - Installs Nessus Agent if missing or outdated
  - Ensures service is running
  - Ensures agent is linked to expected server
  - Produces structured JSON result for controller.py
#>

param(
  [string]$NessusServerHost = "nm02.sec.helix.gsa.gov",
  [int]$NessusServerPort = 50505,
  [string]$NessusKey = "a345a31710c596e59b1b6e3e1034e3f9a1b914b64034272cbf75cad9de526",
  [string]$ExpectedDisplayName = "Nessus Agent (x64)",
  [string]$ExpectedVersionText = "10.8.5.20039",
  [string]$MsiSharePath = "\\gtd.gsa.gov\SYSVOL\gtd.gsa.gov\scripts\Workspaces\Security-Agents\Nessus\installer\NessusAgent-10.8.5-x64.msi"
)

$Result = @{
    software    = "Nessus Agent"
    expected    = $ExpectedVersionText
    status      = "Unknown"
    details     = @()
    exit_code   = 1
}

function Add-Detail {
    param($msg)
    $Result.details += $msg
    Write-Output $msg
}

function Get-InstalledProduct {
  param([string]$NamePattern)
  $paths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  foreach ($p in $paths) {
    Get-ItemProperty $p -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -and $_.DisplayName -match $NamePattern } |
      Select-Object DisplayName, DisplayVersion, UninstallString
  }
}

function Get-NessusCliPath {
  $paths = @(
    "$env:ProgramFiles\Tenable\Nessus Agent\nessuscli.exe",
    "${env:ProgramFiles(x86)}\Tenable\Nessus Agent\nessuscli.exe"
  )
  foreach ($p in $paths) { if (Test-Path $p) { return $p } }
  return $null
}

# --- MAIN ---
Try {
    # 1) Check installed version
    $installed = Get-InstalledProduct -NamePattern "Nessus Agent" | Select-Object -First 1
    if ($installed) {
        Add-Detail "Detected installed Nessus Agent: $($installed.DisplayVersion)"
    } else {
        Add-Detail "Nessus Agent not detected."
    }

    $needsInstall = $true
    if ($installed -and $installed.DisplayVersion -eq $ExpectedVersionText) {
        $needsInstall = $false
        Add-Detail "Installed version matches expected ($ExpectedVersionText)."
    }

    # 2) Install if needed
    if ($needsInstall) {
        if (-not (Test-Path $MsiSharePath)) {
            throw "MSI not found at $MsiSharePath"
        }
        $msiArgs = "NESSUS_SERVER=$($NessusServerHost):$NessusServerPort NESSUS_KEY=$NessusKey"
        $args = "/i `"$MsiSharePath`" $msiArgs /qn"
        Add-Detail "Running msiexec $args"
        $code = (Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru).ExitCode
        if ($code -ne 0) { throw "Installer failed with exit code $code" }
        Add-Detail "Nessus Agent installation successful."
    }

    # 3) Ensure service running
    $svc = Get-Service -Name "Tenable Nessus Agent" -ErrorAction Stop
    if ($svc.Status -ne "Running") {
        Start-Service -Name "Tenable Nessus Agent"
        $svc.WaitForStatus("Running","00:00:20")
        Add-Detail "Nessus Agent service started."
    } else {
        Add-Detail "Nessus Agent service already running."
    }

    # 4) Verify link status
    $cli = Get-NessusCliPath
    if (-not $cli) { throw "nessuscli.exe not found" }

    $stat = & $cli agent status 2>&1 | Out-String
    if ($stat -match "Linked to: $NessusServerHost") {
        Add-Detail "Agent already linked to $NessusServerHost:$NessusServerPort."
    } else {
        Add-Detail "Agent not linked correctly. Attempting re-link..."
        & $cli agent unlink | Out-Null
        Start-Sleep -Seconds 2
        & $cli agent link --key $NessusKey --host $NessusServerHost --port $NessusServerPort | Out-Null
        Add-Detail "Agent linked to $NessusServerHost:$NessusServerPort."
    }

    # Final check
    $final = & $cli agent status 2>&1 | Out-String
    if ($final -match "Linked to: $NessusServerHost") {
        $Result.status = "Installed & Linked"
        $Result.exit_code = 0
    } else {
        $Result.status = "Link Failed"
        $Result.exit_code = 2
    }
}
Catch {
    $Result.status = "Error"
    Add-Detail "Error: $_"
    $Result.exit_code = 3
}

# --- Print structured JSON result ---
$Result | ConvertTo-Json -Depth 3
exit $Result.exit_code
