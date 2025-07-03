trigger: none

pool:
  name: 'Self-Hosted'

variables:
  resourceGroup: 'aibBuildRG'

stages:

- stage: BuildImage
  jobs:
  - job: ExecuteAIB
    steps:
    - task: AzureCLI@2
      displayName: 'Execute AIB Image Build'
      inputs:
        azureSubscription: 'your-service-connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          echo "🔧 Triggering image build..."
          # Simulate AIB build step
          az resource invoke-action --ids "/subscriptions/xxx/resourceGroups/$(resourceGroup)/providers/Microsoft.VirtualMachineImages/imageTemplates/templateName" \
            --action Run

- stage: Cleanup
  dependsOn: BuildImage
  condition: succeeded()
  jobs:
  - job: CleanupResources
    steps:
    - task: AzureCLI@2
      displayName: 'Cleanup RG Resources (success only)'
      inputs:
        azureSubscription: 'your-service-connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          echo "🧹 Cleaning up resources in $(resourceGroup)..."
          ids=$(az resource list -g $(resourceGroup) --query "[].id" -o tsv)
          for id in $ids; do
            az resource delete --ids $id
          done
          echo "✅ Cleanup complete."

- stage: FailureInstructions
  dependsOn: BuildImage
  condition: failed()
  jobs:
  - job: TriggerTroubleshooting
    steps:
    - task: PowerShell@2
      displayName: 'Trigger Troubleshooting Pipeline via REST API'
      inputs:
        targetType: 'inline'
        script: |
          $org = "https://dev.azure.com/yourOrg"
          $project = "yourProject"
          $pipelineName = "Troubleshooting-Pipeline"
          $resourceGroup = "$(resourceGroup)"
          $pat = "$(adoPat)"

          $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))

          $pipelineId = (Invoke-RestMethod -Uri "$org/$project/_apis/pipelines?api-version=7.0" -Headers @{Authorization = "Basic $base64AuthInfo"}).value | `
            Where-Object { $_.name -eq $pipelineName } | Select-Object -ExpandProperty id

          if (-not $pipelineId) {
              Write-Error "❌ Pipeline '$pipelineName' not found."
              exit 1
          }

          $body = @{
              resources = @{
                  repositories = @{
                      self = @{ refName = 'refs/heads/main' }
                  }
              }
              templateParameters = @{
                  resourceGroup = "$resourceGroup"
              }
          } | ConvertTo-Json -Depth 10

          $run = Invoke-RestMethod -Uri "$org/$project/_apis/pipelines/$pipelineId/runs?api-version=7.0" `
              -Method Post -Headers @{Authorization = "Basic $base64AuthInfo"; "Content-Type" = "application/json"} `
              -Body $body

          Write-Host "✅ Troubleshooting pipeline triggered. Run ID: $($run.id)"
