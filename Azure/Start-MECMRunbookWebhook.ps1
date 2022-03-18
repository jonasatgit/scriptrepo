# URL of the webhook
$webhookURL = 'https://5abf541d-717f-4ef9-8df6-5e985d6d0ddf.webhook.ne.azure-automation.net/webhooks?token=[tokenvalue]'

# A header
$header = @{message='We need a new machine'}

# The body contains the neccesary parameter values
$body = @{
        SystemName='TestSystem005'
        SystemMacAdress='00:11:22:33:44:AA'
        CollectionName = 'All Systems' 
        StartString = '64fe693f-150e-4593-a1e1-6cb0f3f11114'
    } | ConvertTo-Json # we need to convert the body to JSON

# A simple POST invokes the runbook
Invoke-RestMethod -Method Post -Uri $webhookURL -Headers $header -Body $body


