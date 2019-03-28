<#
	===========================================================================

	 Created on:   	2017-06-22 11:15
	 Created by:   	Arash Nabi
	 Organization:
	 Filename:     	Get-Arch.psm1
	-------------------------------------------------------------------------
	 Module Name: Get-Arch
	===========================================================================
#>

function Run-DBQuery
{
	[CmdletBinding()]
	[OutputType([int])]
	Param
	(
		[Parameter(Mandatory = $True,
				   HelpMessage = "Please specify the SQL Server instance. Ex Computer\Instance",
				   ValueFromPipeline = $False)]
		[ValidateNotNullorEmpty()]
		$Database,
		[Parameter(Mandatory = $true,
				   ValueFromPipelineByPropertyName = $true,
				   HelpMessage = "Please specify the TSQL query.",
				   Position = 0)]
		[OutputType([System.Data.DataTable])]
		$QueryString


	)

	try
	{
		try
		{
			$ConnectionString = "Data Source=$Database;Integrated Security=True;User ID=;Password="
			$command = New-Object System.Data.SqlClient.SqlCommand ($QueryString, $ConnectionString) -ErrorAction Inquire
			$adapter = New-Object System.Data.SqlClient.SqlDataAdapter ($command) -ErrorAction Inquire
		}
		catch [System.Net.WebException], [System.Exception] {
			$errorMessage = $_.Exception.Message
			Write-Warning "$errorMessage Server:$server xx"
		}



		#Load the Dataset

		$dataset = New-Object System.Data.DataSet
		if ($adapter)
		{
			[void]$adapter.Fill($dataset)
			#Return the Dataset
			return @(, $dataset.Tables[0])
		}
		{
			Write-Host "Either no access to DB or something went wrong!"
		}

	}

	catch [System.Net.WebException], [System.Exception] {
		$errorMessage = $_.Exception.Message
		Write-Warning "$errorMessage Server:$server"
	}




}

function Connect-Server
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 0)]
		$Servers
	)

	BEGIN
	{
		$serverarch_obj = @()
	}
	PROCESS
	{
		foreach ($Server in $Servers)
		{
			try
			{
				$objOption = New-CimSessionOption -Protocol Dcom -ErrorAction stop
				$objSession = New-CimSession -ComputerName $server -SessionOption $objOption -ErrorAction Stop
				$serverarch_obj += New-Object psobject -Property @{ 'Name' = $server }
			}

			catch [System.Net.WebException], [System.Exception]
			{
				Write-Warning "No CimSession connection to $server"
				$serverarch_obj += New-Object psobject -Property @{ 'Name' = $("No CimSession connection to $server") }
			}
		}
	}
	END
	{

		$serverarch_obj
	}
}

function Get-ServerArch
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		$Server
	)
	BEGIN
	{
		$serverarch_obj = @()
	}
	PROCESS
	{
		$objOption = New-CimSessionOption -Protocol Dcom -ErrorAction SilentlyContinue
		$objSession = New-CimSession -ComputerName $server -SessionOption $objOption -ErrorAction SilentlyContinue
		$WinOS = Get-CimInstance -CimSession $objSession -Namespace ROOT/cimv2 -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
		$UpTime = New-TimeSpan -Start $WinOS.LastBootUpTime -End (get-date)
		$Model = (Get-CimInstance -CimSession $objSession -Namespace ROOT/cimv2 -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).Model
		$IP = (Get-CimInstance -CimSession $objSession -Namespace ROOT/cimv2 -ClassName Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
		where { $_.ipaddress -like "1*" } | select -ExpandProperty ipaddress | select -First 1 -ErrorAction SilentlyContinue)
		$CPU = Get-CimInstance -CimSession $objSession -Namespace ROOT/cimv2 -ClassName Win32_Processor -ErrorAction SilentlyContinue


		$params = @{
			'Name' = $server
			'Arch' = $WinOS.OSArchitecture
			'OS' = $WinOS.Caption
			'Model' = $Model
			'CPU' = ($CPU.Name | Select-Object -First 1)
			'IP' = $IP
			'RAM' = ([math]::round($WinOS.TotalVisibleMemorySize/1MB)).ToString() + ' GB'
			'Cores' = ($CPU.NumberOfCores).count
			'LPU' = ($CPU.NumberOfLogicalProcessors).Count
			'LastBootUp' = $WinOS.LastBootUpTime.ToString("yyyy-MM-dd HH:mm")
			'UpTimeDays' = $UpTime.Days

		}
		$serverarch_obj += New-Object psobject -Property $params


	}
	END
	{
		$serverarch_obj
	}

}

function Get-SQLInfo
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		$Servers
	)

	BEGIN
	{
		$SQLobj = @()

	}
	PROCESS
	{
		foreach ($server in $Servers)
		{


			$InstanceName = Invoke-Command -ComputerName $server -ErrorAction Continue -ScriptBlock {
				(get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -ErrorAction SilentlyContinue).InstalledInstances
			}


			if ($InstanceName)
			{
					$params = @{
						'SQLInst' = $InstanceName
					}

					try
					{

						$SQLversionQuery = Run-DBQuery -Database "$server\$InstanceName" -QueryString "select @@version as SQLVersion" -ErrorAction Stop

						$params.add('SQLVer', $($SQLversionQuery.SQLversion))

					}

					catch [System.Net.WebException], [System.Exception]
					{

						$errorMessage = $_.Exception.Message
						$params.add('SQLVer', "Error$errorMessage")
						Write-Warning "$errorMessage xx"

					}
				$SQLobj += New-Object psobject -Property $params
			}
			else
			{
				Write-Warning "$server is not a DB server"
			}
		}

	}
	END
	{
		#$SQLobj
	}
}

function Get-DiskInfo
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		$Servers
	)

	BEGIN
	{
		$Diskobj = @()
	}
	PROCESS
	{
		foreach ($server in $Servers)
		{
			$objOption = New-CimSessionOption -Protocol Dcom -ErrorAction SilentlyContinue
			$objSession = New-CimSession -ComputerName $server -SessionOption $objOption -ErrorAction SilentlyContinue
			$allDisks = Get-CimInstance -CimSession $objSession -Namespace ROOT/cimv2 -ClassName Win32_Volume -ErrorAction SilentlyContinue |
			Where-Object { $_.Capacity -gt 1 } |
			select driveletter, capacity, freespace
			$params = @{ }
			foreach ($disk in $alldisks)
			{
				if (-not ([string]::IsNullOrEmpty($($disk.driveletter))))
				{
					$DisksizeGB = [math]::round($disk.capacity/1GB)
					$diskLetter = $disk.Driveletter.Replace(':', '')
					$DiskUsed = [math]::round(($disk.capacity - $disk.freespace) /1GB)
					$DiskFree = [math]::round(($disk.freespace /1GB))
					$percentFree = "{0:P1}" -f ($DiskFree/$DisksizeGB)
					$params.Add($($diskLetter), $("$disksizeGB GB `n($percentFree Free)"))
				}

			}
			$Diskobj += New-Object psobject -Property $params
		}
	}
	END
	{
		$Diskobj
	}
}


Export-ModuleMember Run-DBQuery,
					Connect-Server,
					Get-ServerArch,
					Get-SQLInfo,
					Get-DiskInfo