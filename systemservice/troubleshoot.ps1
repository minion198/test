# ===== CONFIG =====
$ServiceName   = 'ImmutableDemo'            # your service name
$PublishPath   = 'C:\Apps\DotNetSample'     # folder produced by: dotnet publish -o ...
$Port          = 8080
$RunAs         = 'LocalSystem'              # or 'NT AUTHORITY\NetworkService' etc.
$RunAsPassword = $null                      # required only for domain/local users

$ErrorActionPreference = 'Stop'

Write-Host "== Diagnose & Repair for service '$ServiceName' =="

# 0) Show last known status and config if service exists
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
  Write-Host "Current status: $($svc.Status)"
  Write-Host "Current config (sc qc):"
  sc.exe qc $ServiceName
}

# 1) Determine binPath (EXE preferred; otherwise dotnet + DLL)
Write-Host "`n== Resolving executable in $PublishPath =="
if (-not (Test-Path $PublishPath)) { throw "PublishPath not found: $PublishPath" }

$exe = Get-ChildItem -Path $PublishPath -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($exe) {
  $binPath = $exe.FullName
  Write-Host "Found EXE: $binPath"
} else {
  $dll = Get-ChildItem -Path $PublishPath -Filter *.dll -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $dll) { throw "No .exe or .dll found in $PublishPath" }

  $dotnet = "${env:ProgramFiles}\dotnet\dotnet.exe"
  if (-not (Test-Path $dotnet)) { throw "dotnet runtime not found at $dotnet (install .NET runtime or publish self-contained)." }

  # sc.exe needs the entire command in binPath=
  $binPath = "$dotnet `"$($dll.FullName)`""
  Write-Host "Using framework-dependent launch: $binPath"
}

# 2) Optional: test-run the binary once (it should not crash immediately)
Write-Host "`n== Smoke test (5s) =="
try {
  $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$binPath`"" -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 2
  if ($p.HasExited) {
    Write-Warning "Process exited immediately with code $($p.ExitCode). Check Application event log for details."
  } else {
    Write-Host "App appears to start; terminating smoke test..."
    Stop-Process -Id $p.Id -Force
  }
} catch {
  Write-Warning "Smoke test failed to start: $($_.Exception.Message)"
}

# 3) Ensure URL ACL for chosen identity
Write-Host "`n== Ensuring URL ACL for http://+:$Port/ =="
$svcUserForAcl = switch -Regex ($RunAs) {
  '^(LocalSystem|NT AUTHORITY\\SYSTEM)$' { 'NT AUTHORITY\SYSTEM' ; break }
  '^(NT AUTHORITY\\NetworkService)$'     { 'NT AUTHORITY\NETWORK SERVICE' ; break }
  '^(NT AUTHORITY\\LocalService)$'       { 'NT AUTHORITY\LOCAL SERVICE' ; break }
  default                                { $RunAs }
}
# Remove conflicting stale ACLs (optional safety)
$acls = (netsh http show urlacl) 2>$null
if ($acls -and ($acls -match "http://\+:$Port/")) {
  Write-Host "Existing ACLs for port $Port detected."
}
try { netsh http add urlacl url="http://+:$Port/" user="$svcUserForAcl" | Out-Null } catch { Write-Host "URL ACL may already exist. Continuing..." }

# 4) Firewall rule
Write-Host "== Ensuring firewall rule for TCP $Port =="
if (-not (Get-NetFirewallRule -DisplayName "DotNet_$ServiceName_$Port" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName "DotNet_$ServiceName_$Port" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
}

# 5) Check if port is already bound
Write-Host "== Checking if port $Port is already in use =="
$inUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($inUse) {
  Write-Warning "Port $Port is already in use by PID $($inUse.OwningProcess). The service will fail to bind."
}

# 6) Recreate the service with correct quoting
Write-Host "`n== (Re)creating Windows Service =="
if ($svc) {
  sc.exe stop $ServiceName | Out-Null
  Start-Sleep -Seconds 2
  sc.exe delete $ServiceName | Out-Null
  Start-Sleep -Seconds 2
}

# IMPORTANT: sc.exe syntax requires a space after the equals sign
sc.exe create $ServiceName binPath= "$binPath" start= auto | Out-Null
sc.exe description $ServiceName "Immutable Demo (.NET) on $Port" | Out-Null

if ($RunAs -notmatch 'LocalSystem|NT AUTHORITY\\SYSTEM') {
  if (-not $RunAsPassword) { throw "RunAs specified but no password provided." }
  sc.exe config $ServiceName obj= "$RunAs" password= "$RunAsPassword" | Out-Null
}

# Per-service env var for initial health (optional)
$svcKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
New-Item -Path $svcKey -Force | Out-Null
New-ItemProperty -Path $svcKey -Name "Environment" -PropertyType MultiString -Value @("HEALTH_START_STATE=Healthy") -Force | Out-Null

# Recovery: restart on failure
sc.exe failure $ServiceName reset= 86400 actions= restart/5000 | Out-Null

# 7) Start service and show status / logs
Write-Host "`n== Starting service =="
try {
  Start-Service -Name $ServiceName
  Start-Sleep -Seconds 3
  $curr = Get-Service -Name $ServiceName
  Write-Host "Service state: $($curr.Status)"
} catch {
  Write-Warning "Start-Service failed: $($_.Exception.Message)"
}

Write-Host "`n== sc query =="
sc.exe query $ServiceName

Write-Host "`n== Recent Application log events (last 50) related to .NET / your service =="
$providers = @('DotNetSampleService','ImmutableDemo','Application Error','.NET Runtime','Windows Error Reporting','Microsoft-Windows-WAS')
Get-WinEvent -LogName Application -MaxEvents 200 |
  Where-Object { $providers -contains $_.ProviderName -or $_.Message -match $ServiceName } |
  Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
  Select-Object -First 50 | Format-List
