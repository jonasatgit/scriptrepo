-----------------------------------------------------------------------------------------------------------------------
---- Disclaimer
----
---- This sample script is not supported under any Microsoft standard support program or service. This sample
---- script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties
---- including, without limitation, any implied warranties of merchantability or of fitness for a particular
---- purpose. The entire risk arising out of the use or performance of this sample script and documentation
---- remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation,
---- production, or delivery of this script be liable for any damages whatsoever (including, without limitation,
---- damages for loss of business profits, business interruption, loss of business information, or other
---- pecuniary loss) arising out of the use of or inability to use this sample script or documentation, even
---- if Microsoft has been advised of the possibility of such damages.
-----------------------------------------------------------------------------------------------------------------------
----
---- The script will output the results of 'Test-ConfigMgrTlsConfiguration.ps1'
---- Replace the databasename with your own ConfigMgr database: "[CM_P11]""

USE [CM_P11]
GO

DECLARE @ScriptName as nvarchar(256)
SET @ScriptName = 'Test-ConfigMgrTlsConfiguration'
 
SELECT SES.DeviceName
    ,SES.CollectionName
    ,SES.TaskID
    ,SES.ScriptVersion
    ,SES.LastUpdateTime
    ,SES.ScriptExitCode
    ,SES.State
    ,SES.TotalClients
    ,SES.UnknownClients
    ,SES.NotApplicableClients
    ,SES.FailedClients
    ,SES.CompletedClients
    ,SES.OfflineClients
    ,JSON_VALUE(SES.ScriptOutput, '$.OverallTestStatus') AS OverallTestStatus
    ,JSON_VALUE(SES.ScriptOutput, '$.OSName') AS OSName
    ,JSON_VALUE(SES.ScriptOutput, '$.OSVersion') AS OSVersion
    ,JSON_VALUE(SES.ScriptOutput, '$.OSType') AS OSType
    ,JSON_VALUE(SES.ScriptOutput, '$.IsSiteServer') AS IsSiteServer
    ,JSON_VALUE(SES.ScriptOutput, '$.IsSiteRole') AS IsSiteRole
    ,JSON_VALUE(SES.ScriptOutput, '$.IsReportingServicePoint') AS IsReportingServicePoint
    ,JSON_VALUE(SES.ScriptOutput, '$.IsSUPAndWSUS') AS IsSUPAndWSUS
    ,JSON_VALUE(SES.ScriptOutput, '$.IsSecondarySite') AS IsSecondarySite
    ,JSON_VALUE(SES.ScriptOutput, '$.TestCMGSettings') AS TestCMGSettings
    ,JSON_VALUE(SES.ScriptOutput, '$.TestSQLServerVersionOfSite') AS TestSQLServerVersionOfSite
    ,JSON_VALUE(SES.ScriptOutput, '$.TestSQLServerVersionOfWSUS') AS TestSQLServerVersionOfWSUS
    ,JSON_VALUE(SES.ScriptOutput, '$.TestSQLServerVersionOfSSRS') AS TestSQLServerVersionOfSSRS
    ,JSON_VALUE(SES.ScriptOutput, '$.TestSQLServerVersionOfSecSite') AS TestSQLServerVersionOfSecSite
    ,JSON_VALUE(SES.ScriptOutput, '$.TestSQLClientVersion') AS TestSQLClientVersion
    ,JSON_VALUE(SES.ScriptOutput, '$.TestWSUSVersion') AS TestWSUSVersion
    ,JSON_VALUE(SES.ScriptOutput, '$.TestSCHANNELSettings') AS TestSCHANNELSettings
    ,JSON_VALUE(SES.ScriptOutput, '$.TestSCHANNELKeyExchangeAlgorithms') AS TestSCHANNELKeyExchangeAlgorithms
    ,JSON_VALUE(SES.ScriptOutput, '$.TestSCHANNELHashes') AS TestSCHANNELHashes
    ,JSON_VALUE(SES.ScriptOutput, '$.TestSCHANNELCiphers') AS TestSCHANNELCiphers
    ,JSON_VALUE(SES.ScriptOutput, '$.TestCipherSuites') AS TestCipherSuites
    ,JSON_VALUE(SES.ScriptOutput, '$.TestNetFrameworkVersion') AS TestNetFrameworkVersion
    ,JSON_VALUE(SES.ScriptOutput, '$.TestNetFrameworkSettings') AS TestNetFrameworkSettings
FROM vSMS_ScriptsExecutionStatus SES
where SES.ScriptName = @ScriptName
Order by SES.TaskID, SES.LastUpdateTime desc