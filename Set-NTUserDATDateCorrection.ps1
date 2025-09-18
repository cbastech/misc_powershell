<#
.SYNOPSIS
Attempts to 'correct' the NTUSER.DAT LastWriteTime based on actual user activity rather than relying on Windows'
built-in functionality.

.DESCRIPTION
Used to set the NTUSER.DAT LastWriteTime to that of the last modified date within the user profile folder,
based on commonly used locations of actual activity. This is needed because Windows Cumulative Updates 
(or something) are altering the NTUSER.DAT LastWriteTime, which then defeats the ability for GPO to delete
aged profiles based on date.

This script skips local user profiles and built-in accounts, and queries Active Directory to determine
whether Domain accounts are Terminated or Suspended bas

.OUTPUTS
Logfile is created at C:\DATCorrection.log and a CSV of evaluated profiles at C:\DATResults.csv

.NOTES
This script assumes that Terminated/Suspended accounts have Useraccesscontrol value 514 (Enabled = false)
and the Description starting either with "Term*" or "Suspend*", respectively.  If this is not the case
in your environment, adjust accordingly.

#>

### REPORTING FUNCTION
function Write-Log {
    [CmdletBinding()]
    Param(
          [parameter(Mandatory=$true)]
          [String]$Path,

          [parameter(Mandatory=$true)]
          [String]$Message,

          [parameter(Mandatory=$true)]
          [String]$Component,

          [Parameter(Mandatory=$true)]
          [ValidateSet("Info", "Warning", "Error")]
          [String]$Type
    )
    try {
        # Create a log entry
        $Content = "<![LOG[$Message]LOG]!>" +`
            "<time=`"$(Get-Date -Format "HH:mm:ss.ffffff")`" " +`
            "date=`"$(Get-Date -Format "M-d-yyyy")`" " +`
            "component=`"$Component`" " +`
            "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
            "type=`"$Type`" " +`
            "thread=`"$([Threading.Thread]::CurrentThread.ManagedThreadId)`" " +`
            "file=`"`">"

        # Write the line to the log file
        Add-Content -Path $Path -Value $Content
    }
    catch {
        throw "Failure to write information to the custom log file."
    }
}  #END REPORTING FUNCTION


### GET AD USER INFO
function Get-pcADUserProperties {
	[CmdletBinding()]
    Param(
          [parameter(Mandatory=$true)]
          [String]$LDAPPath,

          [parameter(Mandatory=$true)]
          [String]$Target
    )
	$root = ([adsi]"LDAP://$($LDAPPath)",'objectCategory=user')
	$searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
	if ($Target -match "\\") { $searcher.filter = "(&(ObjectClass=User)(objectSID=$($Target)))"}
	else { $searcher.filter = "(&(ObjectClass=User)(samAccountName=$($Target)))" }
	$searcher.PageSize = 10
	$searcher.PropertiesToLoad.Add("Name") | out-null
	$searcher.PropertiesToLoad.Add("userAccountControl") | out-null
	$searcher.PropertiesToLoad.Add("objectSID") | out-null
	$searcher.PropertiesToLoad.Add("description") | out-null
	$searcher.PropertiesToLoad.Add("sn") | out-null
	$UserObject = $searcher.findall()
	return $UserObject.properties
}

$script:LocalLog = "C:\DATCorrection.log"
$script:LocalCSV = "C:\DATResults.csv"

# LOCATIONS WE'RE CHECKING
# We scan each of these and pull the latest modify date of child items
# in order to try to determine the actual most recent time that the
# user was on the machine.

$UserActivityLocations = @(
    'Desktop'
    'Downloads'
    'Favorites'
    'Documents'
    'Pictures'
    'Videos'
    'AppData\Local\Google\Chrome\User Data'
	'AppData\Local\Microsoft'
	'AppData\Local\Temp'
	)

$results = @()
$excluded = @('Public','Administrator','Guest','TEMP') # Technically not 'local' accounts, so need to specifically exclude them.

$Path = "C:\Users"

Write-Log -Path $LocalLog -Component File_System -Type Info -Message "Retrieving user profile list..." 

$UserFolders = $Path | Get-ChildItem -Directory

if ($UserFolders) { Write-Log -Path $LocalLog -Component File_System -Type Info -Message "User profile list retrieved." }
else { Write-Log -Path $LocalLog -Component File_System -Type Error -Message "Unable to retrieve user profile list" }


ForEach ($UserFolder in $UserFolders) {
	
	$LWT_Array = @()
	$userprofiletype, $testpath_error, $getitem_error, $dat_error, $Dat, $User, $MostRecent = $null # Blank out what we need

	$UserName = $UserFolder.Name

	Write-Log -Path $LocalLog -Component User_Profile -Type Info -Message "Processing user $UserName" 

	if (Get-LocalUser -Name $UserName) { 
		$userprofiletype = "Local" 
		Write-Log -Path $LocalLog -Component User_Profile -Type Warning -Message "$UserName is a local account. Skipping."
		continue;
	}
	
	if ($UserName -in $excluded) { 
		$userprofiletype = "Excluded" 
		Write-Log -Path $LocalLog -Component User_Profile -Type Warning -Message "$UserName is an excluded account. Skipping." 
		continue;
	}
	
# That covers non-domains.  Now for domain accounts
# 1. Do They Exist?  If not, they've been terminated.  We should delete their stuff!
# 2. Is the account disabled?  (This means they are NOT terminated; maybe FLMA - skip them)

	$User = Get-pcADUserProperties $UserName
	
	if (-not $User) {  # Doesn't exist in AD.  Is it someone who changed their name? Let's check.
	
		$UserWMI = Get-WMIObject win32_userprofile | Select-Object SID, LocalPath | Where-Object {$_.LocalPath -match $UserName}
				# Get their SID. We have to turn it to binary for the AD query.  This is a stupidly complex process.
				$sid = New-Object System.Security.Principal.SecurityIdentifier($UserWMI.SID)
				$binsid = New-Object 'byte[]' $sid.BinaryLength  # This creates a holding variable
				$sid.GetBinaryForm($binsid, 0) # And this puts the value IN the holding variable
				$hexsid = [System.BitConverter]::ToString($binsid).replace('-','\') # Because ADSI stores binary as hexadecimal for some ungodly reason.
				$hexsid = '\' + $hexsid #Prefix the first octet
				$SIDUser = Get-pcADUserProperties $hexsid	
				if ($SIDUser) { 
					$userprofiletype = "AD" # We found a match; someone changed their name
				}
				else { 
					$userprofiletype = $null # No match.  Either VERY new, or very terminated. 
				}
	} # End 'If Not User'
	else { $userprofiletype = "AD" }

	if (($User) -and ($User.useraccountcontrol -eq 514) -and ($User.description -like "Term*")) {
		$userprofiletype = "Terminated" 
		Write-Log -Path $LocalLog -Component User_Profile -Type Warning -Message "$UserName has been terminated in Active Directory." 
		#continue;
	}

	if (($User) -and ($User.useraccountcontrol -eq 514) -and ($User.description -like "Suspend*")) {
		$userprofiletype = "Suspended" 
		Write-Log -Path $LocalLog -Component User_Profile -Type Warning -Message "$UserName is suspended in Active Directory and may be on leave. Skipping." 
		#continue;
	}

# Sanity catch for unexpected cases
	if (-Not $userprofiletype) { 		
		$userprofiletype = "Unknown" 
		Write-Log -Path $LocalLog -Component User_Profile -Type Error -Message "$UserName does not exist in Active Directory." 
		#continue;
	}


# Pull child items and catalog the last modified dates.
# We only run this is the $userprofile is an AD account

	if (($userprofiletype -eq "AD") -or ($userprofiletype -eq "Terminated") -or ($userprofiletype -eq "Unknown")) {
		if (($userprofiletype -eq "AD") -or ($userprofiletype -eq "Terminated")) { Write-Log -Path $LocalLog -Component User_Profile -Type Info -Message "$UserName is valid for processing."}
		if ($userprofiletype -eq "Unknown") { Write-Log -Path $LocalLog -Component User_Profile -Type Info -Message "Assuming terminated account; processing as normal."}

# Sanity check - does an NTUSER.DAT even exist?
	if (Test-Path "$Path\$UserName\NTUSER.DAT" -ErrorAction SilentlyContinue) { 	

# Now we need to cycle through all our locations (for each user) and find the most recent file out of all the files/locations

	foreach ($Location in $UserActivityLocations) {
	
	if (-Not (Test-Path "$Path\$UserName\$Location" -ErrorVariable testpath_error)) {
		Write-Log -Path $LocalLog -Component FindLastWrite -Type Error -Message "Test-Path on $Path\$UserName\$Location failed with error:`n $testpath_error"
	} #End failed test-path
	else {
		Write-Log -Path $LocalLog -Component FindLastWrite -Type Info -Message "Test-Path succeeded; scanning for most recent items..."		
		
		#If it's an Appdata Location, get children that are directories.
		#If it's not an Appdata Location, get children that are files
		
		if ($Location -Like "AppData\Local\") {	$MostRecent = Get-ChildItem -Path "$Path\$UserName\$Location" -Directory -Force -Depth 1 | Sort-Object LastWriteTime | Select-Object -last 1 }
		else { $MostRecent = Get-ChildItem -Path "$Path\$UserName\$Location" -File -Force -Depth 1 | Sort-Object LastWriteTime | Select-Object -last 1}
        if (-not ($null -eq $MostRecent)) { # Error catch. Avoids adding empty directories to the array.
		    $LWT_Array += $MostRecent #Add THIS location's most-recent to the array
        }
	} # Successful test-path
	} # End foreach location
	
	# See which is the most recent of all our 'most recent'

	$MostRecent = $LWT_Array | Sort-Object LastWriteTime | Select-Object -last 1  # This returns an object

	Write-Log -Path $LocalLog -Component FindLastWrite -Type Info -Message "Most recent item modified: $($MostRecent.FullName)"
	Write-Log -Path $LocalLog -Component FindLastWrite -Type Info -Message "Last modified at $($MostRecent.LastWriteTime)"
	
	# Compare it to the user's NTUSER.DAT.
	# We still need to modify this if we're going to use Group Policy to cleanly remove old/stale profiles
	
	Write-Log -Path $LocalLog -Component DAT_Modification -Type Info -Message "Using this to set NTUSER.DAT LastWriteTime..."

	$Dat = Get-Item "$Path\$UserName\NTUSER.DAT" -force -ErrorVariable getitem_error
	if ($getitem_error) { Write-Log -Path $LocalLog -Component DAT_Modification -Type Error -Message "Get-Item failed with error:`n $getitem_error" }
	elseif ($Dat) {
		Write-Log -Path $LocalLog -Component DAT_Modification -Type Info -Message "Get-Item successful.  Retrieving last modified date."		
		Write-Log -Path $LocalLog -Component DAT_Modification -Type Info -Message "NTUSER previous modified time: $($Dat.LastWriteTime)"
		$DatTimePrevious = $Dat.LastWriteTime
		try { $Dat.LastWriteTime = $MostRecent.LastWriteTime } catch { $dat_error = $PSItem.Exception.Message } 
		if ($dat_error) { Write-Log -Path $LocalLog -Component DAT_Modification -Type Error -Message "Could not write new modified date. Error:`n $dat_error" }
		else { Write-Log -Path $LocalLog -Component DAT_Modification -Type Info -Message "NTUSER new modified time: $($Dat.LastWriteTime)" }
		$DatTimeNow = $Dat.LastWriteTime
	} # End Got Dat
	} # End 'NTUSER.DAT' Exists check
	else { 
		Write-Log -Path $LocalLog -Component User_Profile -Type Info -Message "No NTUSER.DAT found. User profile may be empty. Skipping."
		$userprofiletype = "Empty"
	}
	} # End 'Valid User' processing
	
	$results += [pscustomobject]@{
		Username = $UserName
		ProfileType = if ($userprofiletype) { $userprofiletype } else { "AD" }
		PreviousDatTime = if (($userprofiletype -ne "AD") -and ($userprofiletype -ne "Unknown") -and ($userprofiletype -ne "Terminated")) { "Skipped"} elseif ($DatTimePrevious) { $DatTimePrevious } else { "Error(s): $testpath_error $getitem_error" }
		NewDatTime = if (($userprofiletype -ne "AD") -and ($userprofiletype -ne "Unknown") -and ($userprofiletype -ne "Terminated")) { "Skipped"} elseif ($DatTimeNow) { $DatTimeNow } else { "Error(s): $dat_error" }
		RunDate = Get-Date -Format MM/dd/yyyy
	}	
	
} # End 'ForEach User' loop.

$results | Sort-Object -Property Username | Export-Csv -Path $LocalCSV -Append