# PDQ Deploy Integration Scripts

PowerShell scripts for integrating PDQ Deploy with MDT (Microsoft Deployment Toolkit) task sequences.

## Scripts

### `mdt-pdq-psexec.ps1`

Integrates PDQ Deploy into MDT task sequences for post-imaging software deployment.

#### What It Does

1. **Copies PsExec locally** - From MDT deployment share to Windows directory
2. **Configures networking** - Registers DNS and optionally configures firewall
3. **Triggers PDQ deployment** - Executes a PDQ Deploy package on the local machine
4. **Waits for completion** - Monitors PDQ deployment and exits when done

#### Why Use This?

- Extend MDT task sequences with PDQ Deploy's superior package management
- Deploy software that requires user context or complex sequencing
- Bridge the gap between OS deployment (MDT) and software deployment (PDQ)

## Quick Start

1. Place `PsExec.exe` in your MDT Deployment Share `\Scripts` folder
2. Configure PDQ Deploy with a package (e.g., "New PC Setup")
3. Add this script as the final step in your MDT task sequence

## Usage

### Basic
```powershell
.\mdt-pdq-psexec.ps1
```

### Custom Parameters
```powershell
.\mdt-pdq-psexec.ps1 `
    -MDTScriptsPath "\\mdt01\DeploymentShare$\Scripts" `
    -PDQHost "pdq01.corp.local" `
    -PackageName "Standard Desktop" `
    -TimeoutMinutes 90
```

### What-If Mode (Test without executing)
```powershell
.\mdt-pdq-psexec.ps1 -WhatIf
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `MDTScriptsPath` | String | `\\PATH-TO-Deploymentshare\Scripts` | UNC path to MDT Scripts folder containing PsExec.exe |
| `PDQHost` | String | `pdq.host.fqdn` | FQDN of the PDQ Deploy server |
| `PackageName` | String | `New PC Setup` | Name of the PDQ Deploy package to run |
| `DisableFirewall` | Switch | `$false` | **Not recommended** - Disables firewall entirely instead of adding rules |
| `TimeoutMinutes` | Int | 60 | Maximum wait time for PDQ deployment (1-240 minutes) |

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Administrator privileges (enforced via `#Requires`)
- PsExec.exe in specified MDT Scripts path
- PDQ Deploy server configured for remote deployments
- Network connectivity between target and PDQ server

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Not running as administrator |
| 2 | MDT scripts path not accessible |
| 3 | PsExec copy failed |
| 4 | PDQ deployment timed out |
| 5 | PDQ deployment failed to start |

## Logging

Script creates detailed logs in `%TEMP%\MDT-PDQ-Deploy_YYYYMMDD_HHMMSS.log`

## Firewall Configuration

By default, the script adds specific firewall rules for PDQ Deploy rather than disabling the firewall:

- TCP ports 6336, 6337
- UDP ports 6336, 6337

Use `-DisableFirewall` only if you understand the security implications.

## Troubleshooting

### "PsExec.exe not found"
- Verify the `MDTScriptsPath` parameter points to your MDT Scripts folder
- Ensure PsExec.exe exists in that folder

### "PDQ deployment timed out"
- Increase `-TimeoutMinutes` if your package takes longer
- Check PDQ Deploy console for deployment status
- Verify the PDQ server can communicate with the target

### "Access denied"
- Ensure running as Administrator
- Check that the PDQ Deploy service account has rights to the target

### Deployment doesn't start
- Verify the package name matches exactly in PDQ Deploy
- Check PDQ Deploy logs on the server
- Ensure the target computer is in PDQ Inventory

## Security Notes

- PsExec is copied to `C:\Windows` temporarily
- Firewall rules are added for PDQ communication
- Script requires Administrator privileges
- Consider removing PsExec after deployment (uncomment cleanup section)

## Version History

### 2.0 (2026-02-12)
- Added comprehensive logging
- Added parameter support
- Added timeout protection
- Added `-WhatIf` support
- Improved error handling
- Added firewall rule option vs. disable
- Added exit codes
- Added progress indication

### 1.0
- Initial release

## License

MIT License - Use at your own risk.

## See Also

- [PDQ Deploy Documentation](https://www.pdq.com/pdq-deploy/)
- [MDT Documentation](https://docs.microsoft.com/en-us/mem/mdt/)
