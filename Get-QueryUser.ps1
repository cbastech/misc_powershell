<#
.SYNOPSIS
Retrieve user sessions from remote computer and optionally disconnect them.

.DESCRIPTION
Queries a remote computer for user sessions using 'query user' and returns them
as a Powershell object. Optionally logs off the returned user session(s). If used 
with 'Logoff', no object is returned.

.PARAMETER Logoff
Switch. Attempts to log off a user session if the user 'State' is 'Disc' (Disconnected)

.PARAMETER Force
Switch. Used with '-LOGOFF'; attempts to log off a user session regardless of 'State'.
'-Force' has no effect without '-Logoff'

.OUTPUTS
PSCustomObject

.EXAMPLE
PS> Get-QueryUser localhost

USERNAME    : administrator
SESSIONNAME : console
ID          : 1
STATE       : Active
IDLE TIME   : none
LOGON TIME  : 9/5/2025 6:13 PM

#>

function Get-QueryUser {
	Param(
			[CmdletBinding()] 
			[parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$True)]
			[String]$ComputerName,
			[parameter(Mandatory=$false)]
			[Switch]$Logoff,
			[parameter(Mandatory=$false)]
			[Switch]$Force
	)

	if ($Force -and (-not $Logoff)) { return "Parameter -Force has no effect without Parameter -Logoff" }

		if (Test-Connection $ComputerName -quiet -count 2) { 
			$userdata = query user /server:$ComputerName
			if ($userdata) {
				$usercsv = $userdata | ForEach-Object -Process { $_ -replace '\s{2,}',',' }
				$userdata = $usercsv | ConvertFrom-Csv -Delim ','
				# Cleanup for null session names - shift things down one
				foreach ($obj in $userdata) {
				if ($obj.username -and (-not $obj."Logon Time")) {
					$obj."Logon Time" = $obj."Idle Time"
					$obj."Idle Time" = $obj.State
					$obj.State = $obj.ID
					$obj.ID = $obj.SessionName
					$obj.SessionName = ""
					}
				if ($Logoff -and ($obj.State -eq "Disc")) { 
					Write-Host "Logging off $($obj.username) from $ComputerName ($($obj.State))"
					logoff $obj.ID /server:$ComputerName }
				if ($Logoff -and $Force) { 
					Write-Host "Logging off $($obj.username) from $ComputerName ($($obj.State))"
					logoff $obj.ID /server:$ComputerName}
				}
				if (-not $Logoff) { return $userdata } else { return }
			}
		} else { 
			Write-Host "$ComputerName is unreachable."
			return $false
		}
}