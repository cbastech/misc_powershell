<#
.Synopsis 
Returns a list of BlueTooth devices on a computer and what version of BlueTooth they are.
#>

function Get-BluetoothDevices {
	param()
    $BTDevices = (Get-PNPDevice | Select -Property InstanceId, Class) | Where-Object {$_.Class -eq 'Bluetooth'} 
    ForEach ($Device in $BTDevices) {
		if ((Get-PNPDeviceProperty -KeyName 'DEVPKEY_Bluetooth_RadioLmpVersion' -InstanceId $Device.InstanceId).Type -ne 'Empty') {
			$BTObject = Get-PNPDeviceProperty -KeyName 'DEVPKEY_Device_Manufacturer','DEVPKEY_Name','DEVPKEY_Bluetooth_RadioLmpVersion' -InstanceId $Device.InstanceId
			$obj = New-Object PSObject
			$obj | add-member -MemberType NoteProperty -Name Manufacturer -Value "$($BTObject[0].Data)"
			$obj | add-member -MemberType NoteProperty -Name Name -Value "$($BTObject[1].Data)"
			$obj | Select-Object Manufacturer, Name, @{
				Name='BlueTooth Version'
				Expression={
					switch ($BTObject[2].Data) {
						0 {$v = '1.0b'} 
						1 {'1.1'} 
						2 {'1.2'} 
						3 {'2.0 + EDR'} 
						4 {'2.1 + EDR'} 
						5 {'3.0 + HS'} 
						6 {'4.0'} 
						7 {'4.1'} 
						8 {'4.2'} 
						9 {'5.0'} 
						10 {'5.1'} 
						11 {'5.2'} 
						12 {'5.3'} 
						13 {'5.4'} 
						14 {'6.0'}
					}
				}
			}
	    }
    }
}