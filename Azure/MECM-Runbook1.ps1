﻿#************************************************************************************************************
# Disclaimer
#
# This sample script is not supported under any Microsoft standard support program or service. This sample
# script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties
# including, without limitation, any implied warranties of merchantability or of fitness for a particular
# purpose. The entire risk arising out of the use or performance of this sample script and documentation
# remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation,
# production, or delivery of this script be liable for any damages whatsoever (including, without limitation,
# damages for loss of business profits, business interruption, loss of business information, or other
# pecuniary loss) arising out of the use of or inability to use this sample script or documentation, even
# if Microsoft has been advised of the possibility of such damages.
#************************************************************************************************************

<#
.Synopsis
    Simple Runbook Example
    
.DESCRIPTION
    Simple Runbook Example
    Source: https://github.com/jonasatgit/scriptrepo

.PARAMETER WebhookData
    

.EXAMPLE
    MECM-Runbook1.ps1

.INPUTS
   Azure Automation Webhook in the form of a JSON string

.OUTPUTS
   None
    
#>
param
(
	# No parametersets possible in runbooks
    [Parameter(Mandatory=$false)]
    [object]$WebhookData,
	[Parameter(Mandatory=$false)]
	[string]$StartString,
	[Parameter(Mandatory=$false)]
	[string]$SystemName,
	[Parameter(Mandatory=$false)]
    [string]$SystemMacAdress,
	[Parameter(Mandatory=$false)]
	[string]$CollectionName,
	[Parameter(Mandatory=$false)]
    [string]$ProviderMachineName,
	[Parameter(Mandatory=$false)]
	[string]$SiteCode
)

#region STEP 1 - webhook
# This section is used to read data from a webhook object
# If no webhook was used the other parameters will be used
if ($WebhookData)
{
	$WebhookName    =   $WebhookData.WebhookName
	$WebhookHeaders =   $WebhookData.RequestHeader
	$WebhookBody    =   $WebhookData.RequestBody

	# no body means no data passed via webhook
	if ($WebhookBody) 
	{ 
		# we need to convert the JSON input to an object we can work with in PowerShell
		$inputData = (ConvertFrom-Json -InputObject $WebhookBody)

		# we extract the information passed via JSON
		$StartString = $inputData.StartString
		$SystemName = $inputData.SystemName
    	$SystemMacAdress = $inputData.SystemMacAdress
    	$CollectionName = $inputData.CollectionName

	}
	else
	{
		# this will stop the runbook and shows an error message in the Azure portal
		throw "No webhook body found!"	
	}
}
#endregion

#region STEP 2 - secure strings
# We use two "secure" strings to make sure we can block a runbook from running if we want to
# With two string we can always re-new one string while the other can still work
# First, lets see if we are running within Azure Automation or as a standalone script
# That step is helpful to be able to run the script locally (in VisualStudio Code for example) without a startstring
if (Get-Command -Name Get-AutomationVariable)
{
	$runbookRunString01 = Get-AutomationVariable -Name "Var-RunString1"
	$runbookRunString02 = Get-AutomationVariable -Name "Var-RunString2"
	
	# Either startstring one or two needs to be correct in order for the runbook to proceed
	if (-NOT ($runbookRunString01 -eq $StartString -or $runbookRunString02 -eq $StartString))
	{
		throw "Wrong start-string was used. String: `"$($StartString)`""
	}
}
else 
{
	# Startstring check disabled. Nothing to do.
}
#endregion

#region STEP 3 - Get MECM site information
# In this section we read two varibles to be able to connect to the correct MECM site
$SiteCode = Get-AutomationVariable -Name "Var-SiteCode"
$ProviderMachineName = Get-AutomationVariable -Name "Var-ProviderName"
#endregion

#region STEP 4 - Data validation
# Since it is always a good idea to validate the input data lets just do that
# validate system name first
if (-NOT ([regex]::Matches($SystemName,'^(?![0-9]{1,15}$)[a-zA-Z0-9-]{1,15}$')))
{
    throw "No valid system name found!"
}

# validate mac addres
$SystemMacAdress = $SystemMacAdress.Replace('-',':') # just to remove "-" and only use ":"" intead
if (-NOT ([regex]::Matches($SystemMacAdress,'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$')))
{
    throw "No valid mac address found!"
}

# validate collection name lengh
if ($CollectionName.Length -gt 255)
{
    throw "Collection name too long!"
}
#endregion

#region STEP 5 - Actual machine import step
# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "E:\Program Files\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

Import-CMComputerInformation -CollectionName $CollectionName -ComputerName $SystemName -MacAddress $SystemMacAdress
#endregion