<#
.SYNOPSIS
    MDT Post-Task Sequence Script for PDQ Deploy Integration

.DESCRIPTION
    This script is designed to run as a final step in an MDT task sequence.
    It copies PsExec locally, configures network settings, and triggers a
    PDQ Deploy package to run on the newly imaged machine.

    The script waits for PDQ deployment completion before exiting.

.PARAMETER MDTScriptsPath
    UNC path to the MDT Deployment Share Scripts folder containing PsExec.exe
    Default: \\PATH-TO-Deploymentshare\Scripts

.PARAMETER PDQHost
    FQDN of the PDQ Deploy server
    Default: pdq.host.fqdn

.PARAMETER PackageName
    Name of the PDQ Deploy package to run
    Default: "New PC Setup"

.PARAMETER DisableFirewall
    Switch to disable Windows Firewall. If not specified, firewall rules are added instead.

.PARAMETER TimeoutMinutes
    Maximum time to wait for PDQ deployment (in minutes)
    Default: 60

.EXAMPLE
    .\mdt-pdq-psexec.ps1
    Runs with default parameters

.EXAMPLE
    .\mdt-pdq-psexec.ps1 -MDTScriptsPath "\\mdt01\DeploymentShare$\Scripts" -PDQHost "pdq01.corp.local" -PackageName "Standard Desktop"
    Runs with custom server paths and package name

.EXAMPLE
    .\mdt-pdq-psexec.ps1 -TimeoutMinutes 120
    Waits up to 2 hours for deployment completion

.NOTES
    Version:        2.0
    Author:         IT Admin
    Creation Date:  2026-02-12
    Purpose/Change: Improved error handling, parameters, and logging
    
    Requirements:
    - Must run as Administrator
    - PDQ Deploy must be configured to allow remote deployments
    - PsExec.exe must exist in the MDT Scripts folder
    
    Exit Codes:
    0   - Success
    1   - Not running as administrator
    2   - MDT scripts path not accessible
    3   - PsExec copy failed
    4   - PDQ deployment timed out
    5   - PDQ deployment failed to start
#>

#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(HelpMessage="UNC path to MDT Deployment Share Scripts folder")]
    [string]$MDTScriptsPath = '\\PATH-TO-Deploymentshare\Scripts',
    
    [Parameter(HelpMessage="FQDN of the PDQ Deploy server")]
    [string]$PDQHost = 'pdq.host.fqdn',
    
    [Parameter(HelpMessage="Name of the PDQ Deploy package to run")]
    [string]$PackageName = 'New PC Setup',
    
    [Parameter(HelpMessage="Disable Windows Firewall entirely (not recommended)")]
    [switch]$DisableFirewall,
    
    [Parameter(HelpMessage="Maximum wait time for deployment in minutes")]
    [ValidateRange(1,240)]
    [int]$TimeoutMinutes = 60
)

#region Initialization
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

$startTime = Get-Date
$logFile = "${env:TEMP}\MDT-PDQ-Deploy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [ValidateSet('Info','Warning','Error')][string]$Level = 'Info')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry
    switch ($Level) {
        'Info'    { Write-Verbose $Message }
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Error $Message }
    }
}

Write-Log "Starting MDT-PDQ integration script"
Write-Log "Parameters: MDTScriptsPath=$MDTScriptsPath, PDQHost=$PDQHost, PackageName=$PackageName"
#endregion

#region PsExec Setup
try {
    $psExecSource = Join-Path $MDTScriptsPath "PsExec.exe"
    $psExecDest = Join-Path $env:windir "PsExec.exe"
    
    Write-Log "Checking PsExec source: $psExecSource"
    if (-not (Test-Path $psExecSource)) {
        throw "PsExec.exe not found at: $psExecSource"
    }
    
    if ($PSCmdlet.ShouldProcess($psExecDest, "Copy PsExec.exe")) {
        Write-Log "Copying PsExec.exe to Windows directory..."
        Copy-Item -Path $psExecSource -Destination $psExecDest -Force
        Write-Log "PsExec.exe copied successfully"
    }
}
catch {
    Write-Log "Failed to copy PsExec: $($_.Exception.Message)" -Level Error
    exit 3
}
#endregion

#region Network Configuration
try {
    if ($DisableFirewall) {
        Write-Log "WARNING: Disabling Windows Firewall on all profiles" -Level Warning
        if ($PSCmdlet.ShouldProcess("Windows Firewall", "Disable all profiles")) {
            netsh advfirewall set allprofiles state off | Out-Null
            Write-Log "Firewall disabled"
        }
    }
    else {
        Write-Log "Adding firewall rules for PDQ Deploy..."
        if ($PSCmdlet.ShouldProcess("Windows Firewall", "Add PDQ Deploy rules")) {
            # Enable firewall but ensure PDQ ports are open
            New-NetFirewallRule -DisplayName "PDQ Deploy (TCP)" -Direction Inbound -Protocol TCP -LocalPort 6336,6337 -Action Allow -ErrorAction SilentlyContinue | Out-Null
            New-NetFirewallRule -DisplayName "PDQ Deploy (UDP)" -Direction Inbound -Protocol UDP -LocalPort 6336,6337 -Action Allow -ErrorAction SilentlyContinue | Out-Null
            Write-Log "PDQ firewall rules added"
        }
    }
    
    Write-Log "Registering DNS..."
    ipconfig /registerdns | Out-Null
    Write-Log "DNS registration complete"
}
catch {
    Write-Log "Network configuration error: $($_.Exception.Message)" -Level Error
}
#endregion

#region PDQ Deployment
try {
    Write-Log "Flushing DNS on PDQ host: $PDQHost"
    $flushResult = & "$env:windir\PsExec.exe" "\\$PDQHost" -h -accepteula ipconfig /flushdns 2>&1
    Write-Log "DNS flush result: $flushResult"
    
    Write-Log "Starting PDQ deployment: Package='$PackageName' Target='$env:COMPUTERNAME'"
    if ($PSCmdlet.ShouldProcess("$PackageName on $env:COMPUTERNAME", "Deploy via PDQ")) {
        $deployResult = & "$env:windir\PsExec.exe" "\\$PDQHost" -h -accepteula pdqdeploy.exe Deploy -Package "$PackageName" -Targets $env:COMPUTERNAME 2>&1
        Write-Log "PDQ deploy initiated: $deployResult"
        
        # Check if deployment started successfully
        Start-Sleep -Seconds 5
        $lockFile = "C:\Windows\AdminArsenal\PDQDeployRunner\service-1.lock"
        
        if (-not (Test-Path $lockFile)) {
            Write-Log "Warning: PDQ lock file not detected after 5 seconds, but deployment may still be starting..." -Level Warning
        }
    }
}
catch {
    Write-Log "PDQ deployment failed to start: $($_.Exception.Message)" -Level Error
    exit 5
}
#endregion

#region Wait for Completion
Write-Log "Waiting for PDQ deployment to complete (timeout: $TimeoutMinutes minutes)..."
$lockFile = "C:\Windows\AdminArsenal\PDQDeployRunner\service-1.lock"
$elapsed = 0
$checkInterval = 10

while (Test-Path $lockFile -ErrorAction SilentlyContinue) {
    Start-Sleep -Seconds $checkInterval
    $elapsed += $checkInterval
    
    $minutes = [math]::Floor($elapsed / 60)
    $seconds = $elapsed % 60
    Write-Progress -Activity "PDQ Deployment in Progress" -Status "Waiting... ($minutes`:$seconds elapsed)" -PercentComplete (($elapsed / ($TimeoutMinutes * 60)) * 100)
    
    if ($elapsed -ge ($TimeoutMinutes * 60)) {
        Write-Log "PDQ deployment timed out after $TimeoutMinutes minutes" -Level Error
        exit 4
    }
}

Write-Progress -Activity "PDQ Deployment" -Completed
Write-Log "PDQ deployment completed successfully"
#endregion

#region Cleanup
$endTime = Get-Date
$duration = $endTime - $startTime
Write-Log "Total execution time: $($duration.ToString('hh\:mm\:ss'))"
Write-Log "Script completed. Log saved to: $logFile"

# Cleanup PsExec if desired (uncomment to enable)
# Remove-Item -Path $psExecDest -Force -ErrorAction SilentlyContinue
#endregion

# Wait for keypress only if running interactively
if ($Host.Name -eq 'ConsoleHost') {
    Write-Host -NoNewLine "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
