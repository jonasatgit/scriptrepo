# Collections\Get-ConfigMgrCollectionEvalTimes.ps1
Script to visualize the last ConfigMgr collection evaluations in a GridView by parsing the colleval.log and colleval.lo_ files

![Get-ConfigMgrCollectionEvalTimes](/Collections/Get-ConfigMgrCollectionEvalTimes.png)


# General\Get-PerfCounter.ps1
The full description can be found here: https://techcommunity.microsoft.com/t5/core-infrastructure-and-security/configmgr-performance-baseline-the-easy-way/ba-p/1583081


# General\Show-FolderSize.ps1
A script to format the output of SysinternalsSuite "du.exe" to show the folder size and find folders with the most data in it. 


# General\BITS-Monitor.ps1
A tiny script to monitor BITS downloads in Powershell directly.


# SINV Understanding ConfigMgr Software Inventory Throttling
The full description can be found here: https://techcommunity.microsoft.com/t5/core-infrastructure-and-security/understanding-configmgr-software-inventory-throttling/ba-p/1592251


# Security\Test-ConfigMgrTlsConfiguration.ps1
Script to validate the correct TLS 1.2 settings for ConfigMgr environments.


# SoftwareUpdates\New-ScheduledRebootInMaintenanceWindow.ps1
Script to create a scheduled task, which will run 10 minutes before a ConfigMgr Maintenance Window ends, to perform a scheduled reboot in case the reboot did not happen automatically. The reboot will also happen if the system is running for 40 days without a reboot. 
Main purpose is to ensure 100% patch compliance