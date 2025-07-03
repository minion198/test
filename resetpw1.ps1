param(
    [Parameter(Mandatory=$true)][string]$ResourceGroup,
    [Parameter(Mandatory=$true)][string]$KeyVaultName,
    [Parameter(Mandatory=$true)][string]$Username,
    [Parameter(Mandatory=$true)][string]$PasswordSecretName
)

# Get password from Key Vault
$password = az keyvault secret show `
    --vault-name $KeyVaultName `
    --name $PasswordSecretName `
    --query value `
    -o tsv

# Find VM(s) starting with 'pkrvm'
$vms = az vm list -g $ResourceGroup `
    --query "[?starts_with(name, 'pkrvm')].[name, timeCreated]" `
    -o json | ConvertFrom-Json

if (-not $vms -or $vms.Count -eq 0) {
    Write-Error "❌ No VM found with name starting 'pkrvm' in $ResourceGroup."
    exit 1
}

# Sort by time created
$targetVm = $vms | Sort-Object {[datetime]$_.Item(1)} | Select-Object -First 1
$vmName = $targetVm[0]

Write-Host "🔍 Selected VM: $vmName"

# Build PowerShell command as single line
# Must use backtick-escaped double quotes around password for remote VM
$escapedPassword = $password.Replace('"', '`"')
$resetCommand = "net user $Username `"$escapedPassword`""

# Run it on the VM
az vm run-command invoke `
  --resource-group $ResourceGroup `
  --name $vmName `
  --command-id RunPowerShellScript `
  --scripts "$resetCommand" `
  --query "value[0].message" `
  -o tsv

# Get private IP
$privateIp = az vm list-ip-addresses `
  --resource-group $ResourceGroup `
  --name $vmName `
  --query "[0].virtualMachine.network.privateIpAddresses[0]" `
  -o tsv

Write-Host ""
Write-Host "===================================="
Write-Host "🔐 Troubleshooting Login Info"
Write-Host "VM Name:     $vmName"
Write-Host "Private IP:  $privateIp"
Write-Host "Username:    $Username"
Write-Host "Password:    (stored in Key Vault)"
Write-Host "===================================="
