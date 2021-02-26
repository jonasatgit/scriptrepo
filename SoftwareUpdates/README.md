# New-ScheduledRebootInMaintenanceWindow.ps1

Script to create a scheduled task, which will run 10 minutes before a ConfigMgr Maintenance Window ends, to perform a scheduled reboot in case the reboot did not happen automatically. The reboot will also happen if the system is running for 40 days without a reboot. 
Main purpose is to ensure 100% patch compliance


# Create-PatchDeployments.ps1
Script to create update deployments based on Automatic Deployment Rules using a json config file. 