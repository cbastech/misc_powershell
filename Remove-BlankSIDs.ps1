<#
.SYNOPSIS
Remediation script for "blank SID" issue (CPATR-19009) caused by Palo Alto Cortex 7.9.0, which was remediated in 7.9.1
https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR/7.9/Cortex-XDR-Agent-Release-Notes/Addressed-Issues-in-Cortex-XDR-Agent-7.9.1

.DESCRIPTION
Pulls a list of User Profile objects from the Windows registry and, if blank, removes the empty profiles. Run results are
logged to a specified log file location.

This script addressed and remediated the blank user profile objects created by a bug in Palo Alto Cortex 7.9.0 which
impacted the ability of Microsoft Configuration Manager to run deployments/actions on affected machines.

CPATR-19009: "Fixed an issue where a Windows function registry key was created falsely, which led to the creation of 
empty user profiles, resulting in a compatibility issue with SCCM deployment."

.PARAMETER LogPath
Path and filename of desired log file of results.  If not specified, defaults to C:\RemoveBlankSIDs.log

.Notes
This script has the potential to be extremely destructive!

#>

function Remove-BlankSID {
	[CmdletBinding()]
	param(
		[Parameter()]
    	[string]$LogPath = "C:\RemoveBlankSIDs.log"	
	)

	$RunDate = Get-Date -Format "MM/dd/yyyy"

	Add-Content -Path $LogPath -Value "$RunDate - Detect Blank SIDs"

	$BlankSIDs = Get-ChildItem -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\ProfileList\" | Where-Object {$_.Property.count -eq 0 }

	$BlankSIDS | Foreach-Object -Process {
		$ShortSID = $_.Name.Substring(76)
		$_.GetValue('ProfileImagePath') -match "^.*\\(?<UserName>.*?)$" | Out-Null
		Add-Content -Path $LogPath -Value "$($matches.UserName) ($ShortSID) is blank and will be removed."
		Remove-Item -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\ProfileList\$ShortSID"
		}
	
	Add-Content -Path $LogPath -Value "---- Complete ----"

}