param(
  [Parameter(Mandatory=$true)][string]$ServiceName,
  [Parameter(Mandatory=$true)][string]$DisplayName,
  [Parameter(Mandatory=$true)][string]$PublishPath,     # folder where you published
  [int]$Port = 8080,
  [ValidateSet('LocalSystem','NT AUTHORITY\SYSTEM','NT AUTHORITY\NetworkService','NT AUTHORITY\LocalService')]
  [string]$RunAs = 'LocalSystem',
  [string]$RunAsPassword,
  [ValidateSet('Healthy','Unhealthy')]
  [string]$InitialHealth = 'Healthy'
)

$ErrorActionPreference = 'Stop'

Write-Host "== Resolve binary in $PublishPath =="
$exe = Get-ChildItem -Path $PublishPath -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($exe) {
  $binPath = $exe.FullName
} else {
  $dll = Get-ChildItem -Path $PublishPath -Filter *.dll -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $dll) { throw "No .exe or .dll found in $PublishPath" }
  $binPath = "C:\Program Files\dotnet\dotnet.exe `"$($dll.FullName)`""
}

Write-Host "== URL ACL (http://+:$Port/) for $RunAs =="
$svcUserForAcl = switch -Regex ($RunAs) {
  '^(LocalSystem|NT AUTHORITY\\SYSTEM)$' { 'NT AUTHORITY\SYSTEM' ; break }
  '^(NT AUTHORITY\\NetworkService)$'     { 'NT AUTHORITY\NETWORK SERVICE' ; break }
  '^(NT AUTHORITY\\LocalService)$'       { 'NT AUTHORITY\LOCAL SERVICE' ; break }
  default                                { $RunAs }
}
try { netsh http add urlacl url="http://+:$Port/" user="$svcUserForAcl" | Out-Null } catch { Write-Host "URL ACL may already exist." }

Write-Host "== Firewall rule for TCP $Port =="
if (-not (Get-NetFirewallRule -DisplayName "DotNet_$ServiceName_$Port" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName "DotNet_$ServiceName_$Port" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
}

Write-Host "== (Re)Create Windows service =="
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
  sc.exe stop $ServiceName | Out-Null
  Start-Sleep -Seconds 2
  sc.exe delete $ServiceName | Out-Null
  Start-Sleep -Seconds 2
}
sc.exe create $ServiceName binPath= "$binPath" start= auto | Out-Null
sc.exe description $ServiceName "$DisplayName" | Out-Null

if ($RunAs -notmatch 'LocalSystem|NT AUTHORITY\\SYSTEM') {
  if (-not $RunAsPassword) { throw "RunAs specified but no password provided." }
  sc.exe config $ServiceName obj= "$RunAs" password= "$RunAsPassword" | Out-Null
}

Write-Host "== Set per-service environment (HEALTH_START_STATE=$InitialHealth) =="
# For Windows services, you can set the "Environment" REG_MULTI_SZ under the service key
$svcKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
New-Item -Path $svcKey -Force | Out-Null
$envList = @("HEALTH_START_STATE=$InitialHealth")
New-ItemProperty -Path $svcKey -Name "Environment" -PropertyType MultiString -Value $envList -Force | Out-Null

Write-Host "== Configure recovery (restart on failure) =="
sc.exe failure $ServiceName reset= 86400 actions= restart/5000 | Out-Null

Write-Host "== Start service =="
Start-Service -Name $ServiceName
Start-Sleep -Seconds 3
(Get-Service -Name $ServiceName).Status | Out-Null
Write-Host "Service '$ServiceName' installed and running on port $Port."
