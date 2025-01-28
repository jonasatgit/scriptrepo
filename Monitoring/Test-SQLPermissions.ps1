<#
.SYNOPSIS
    Script to check SQL permissions against a predefined list of permissions.

.DESCRIPTION
    #************************************************************************************************************
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
    # 
    #************************************************************************************************************

    This script will check the SQL permissions against a predefined list of permissions. 
    The predefined list of permissions is stored in a JSON string. 
    The script will check if the current permissions match the predefined list of permissions. 
    If the current permissions do not match the predefined list of permissions, the script will output the differences.

.PARAMETER SQLServerName
    The SQL Server name to connect to. Default is the local computer name.

.PARAMETER ShowCurrentDefinitionOnly
    If this switch is used, the script will only output the current permissions in JSON format and copy the output to the clipboard.

#>
[CmdletBinding()]
param 
(
    [Parameter()]
    [String]$SQLServerName = $env:COMPUTERNAME,
    [Switch]$ShowCurrentDefinitionOnly
)

#region VARIABLES
# Use parameter ShowCurrentDefinitionOnly to only show the current permissions and copy the output to the clipboard
# Replace the $ExpectedPermissions with your own permissions
$ExpectedPermissions = @'
[
    {
        "Level":  "SERVER",
        "RoleOrDBName":  "sysadmin",
        "Login":  "sa"
    },
    {
        "Level":  "SERVER",
        "RoleOrDBName":  "sysadmin",
        "Login":  "CONTOSO\\configmgradmin"
    },
    {
        "Level":  "SERVER",
        "RoleOrDBName":  "sysadmin",
        "Login":  "NT SERVICE\\SQLWriter"
    },
    {
        "Level":  "SERVER",
        "RoleOrDBName":  "sysadmin",
        "Login":  "NT SERVICE\\Winmgmt"
    },
    {
        "Level":  "SERVER",
        "RoleOrDBName":  "sysadmin",
        "Login":  "NT SERVICE\\MSSQL$INST02"
    },
    {
        "Level":  "SERVER",
        "RoleOrDBName":  "sysadmin",
        "Login":  "NT AUTHORITY\\SYSTEM"
    },
    {
        "Level":  "SERVER",
        "RoleOrDBName":  "sysadmin",
        "Login":  "NT SERVICE\\SQLAgent$INST02"
    },
    {
        "Level":  "SERVER",
        "RoleOrDBName":  "securityadmin",
        "Login":  "NT AUTHORITY\\SYSTEM"
    },
    {
        "Level":  "DATABASE",
        "RoleOrDBName":  "master",
        "Login":  "dbo"
    },
    {
        "Level":  "DATABASE",
        "RoleOrDBName":  "tempdb",
        "Login":  "dbo"
    },
    {
        "Level":  "DATABASE",
        "RoleOrDBName":  "model",
        "Login":  "dbo"
    },
    {
        "Level":  "DATABASE",
        "RoleOrDBName":  "msdb",
        "Login":  "dbo"
    },
    {
        "Level":  "DATABASE",
        "RoleOrDBName":  "CM_P02",
        "Login":  "dbo"
    }
]
'@
#endregion


#region MAIN SCRIPT
$SqlQuery = @'
WITH ServerRoles AS (
    SELECT 
        'SERVER' AS Level,
        R.name AS RoleOrDBName,
        L.name AS Login
    FROM 
        sys.server_principals L
        JOIN sys.server_role_members RM ON L.principal_id = RM.member_principal_id
        JOIN sys.server_principals R ON R.principal_id = RM.role_principal_id
    WHERE 
        R.name IN ('sysadmin', 'securityadmin')
),
DatabaseRoles AS (
    SELECT 
        'DATABASE' AS Level,
        D.name AS RoleOrDBName,
        U.name AS Login
    FROM 
        sys.database_principals U
        JOIN sys.database_role_members RM ON U.principal_id = RM.member_principal_id
        JOIN sys.database_principals R ON R.principal_id = RM.role_principal_id
        JOIN sys.databases D ON D.owner_sid = U.sid
    WHERE 
        R.name = 'db_owner'
)
SELECT * FROM ServerRoles
UNION ALL
SELECT * FROM DatabaseRoles;
'@

$commandName = $MyInvocation.MyCommand.Name
$connectionString = "Server=$SQLServerName;Database=msdb;Integrated Security=True"
Write-Verbose "$commandName`: Connecting to SQL: `"$connectionString`""


try 
{
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $connectionString
    $SqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandText = $SqlQuery
    $SqlAdapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter
    Write-Verbose "$commandName`: Running sql query..."
    $SqlAdapter.SelectCommand = $SqlCmd
    $ds = New-Object -TypeName System.Data.DataSet
    $SqlAdapter.Fill($ds) | Out-Null
    $SqlCmd.Dispose()
}
catch 
{
    Write-Host "$commandName Connection to SQL server failed"
    Write-Host "$commandName $($Error[0].Exception)"  
    break
}

if ($SqlConnection)
{
    if($SqlConnection.state -ieq 'Open')
    {
        $SqlConnection.Close()
    }
}

if ($ds)
{
    [array]$currentPermissions = $ds.Tables.Rows 
    if($ShowCurrentDefinitionOnly)
    {
        $currentPermissions | Select-Object Level, RoleOrDBName, Login | ConvertTo-Json
        $currentPermissions | Select-Object Level, RoleOrDBName, Login | ConvertTo-Json | Clip
        Write-Host 'Current definition copied to clipboard!' -ForegroundColor Green
        break
    }

}
else 
{
    Write-Host 'No data returned'
    break
}

$OutList = [system.Collections.Generic.List[pscustomobject]]::new()
[array]$ExpectedPermissionsList = $ExpectedPermissions | ConvertFrom-Json
# Lets make sure we have each expected value in the database
foreach ($Permission in $ExpectedPermissionsList)
{
    if($currentPermissions.Where({($_.Level -ieq $Permission.Level) -and ($_.RoleOrDBName -ieq $Permission.RoleOrDBName) -and ($_.Login -ieq $Permission.Login)}))
    {
        # expected permission found in current permissions  
    }
    else 
    {
        $OutList.Add([pscustomobject][ordered]@{
            State = 'ExpectedPermissionMissingInSQL'
            Level = $Permission.Level
            RoleOrDBName = $Permission.RoleOrDBName
            Login = $Permission.Login
        })
    }
}

# Lets make sure we have each current value in our expected list
foreach ($Permission in $currentPermissions)
{
    if($ExpectedPermissionsList.Where({($_.Level -ieq $Permission.Level) -and ($_.RoleOrDBName -ieq $Permission.RoleOrDBName) -and ($_.Login -ieq $Permission.Login)}))
    {
        # current permission found in expected permissions list
    }  
    else 
    {
        $OutList.Add([pscustomobject][ordered]@{
            State = 'UnknownPermissionSetInSQL'
            Level = $Permission.Level
            RoleOrDBName = $Permission.RoleOrDBName
            Login = $Permission.Login
        })
    }  
}

if($OutList)
{
    $OutList
}
else 
{
    Write-host  'No differences detected'
}
#endregion

