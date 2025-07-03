param(
    [Parameter(Mandatory=$true)][string]$ResourceGroup,
    [Parameter(Mandatory=$true)][string]$KeyVaultName,
    [Parameter(Mandatory=$true)][string]$Username,
    [Parameter(Mandatory=$true)][string]$PasswordSecretName
)

$password = az keyvault secret show --vault-name $KeyVaultName --name $PasswordSecretName --query value -o tsv

$vms = az vm list -g $ResourceGroup --query "[?starts_with(name, 'pkrvm')].[name, timeCreated]" -o json | ConvertFrom-Json

if ($vms.Count -eq 0) {
    Write-Error "❌ No VMs starting with 'pkrvm' found in RG $ResourceGroup."
    exit 1
}

$targetVm = $vms | Sort-Object {[datetime]$_.Item(1)} | Select-Object -First 1
$vmName = $targetVm[0]

Write-Host "🔍 Target VM selected: $vmName"

$resetScript = @"
net user $Username "$password"
"@

az vm run-command invoke `
  --resource-group $ResourceGroup `
  --name $vmName `
  --command-id RunPowerShellScript `
  --scripts $resetScript | Out-Null

$privateIp = az vm list-ip-addresses `
  --resource-group $ResourceGroup `
  --name $vmName `
  --query "[0].virtualMachine.network.privateIpAddresses[0]" `
  -o tsv

Write-Host "===================================="
Write-Host "🔐 Troubleshooting Login Details"
Write-Host "VM Name:     $vmName"
Write-Host "Private IP:  $privateIp"
Write-Host "Username:    $Username"
Write-Host "Password:    (stored in Key Vault)"
Write-Host "===================================="
