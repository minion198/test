
# validate-software.ps1
# This script verifies installation of software packages and components after image customization.

$logFile = "C:\Temp\InstallValidationLog.txt"
New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
Start-Transcript -Path $logFile -Force

Write-Output "=== VALIDATING MSI INSTALLED SOFTWARE ==="
$softwareNames = @(
    "AWS Command Line Interface",
    "MySQL Workbench 8.0.25",
    "PuTTY release 0.77",
    "SoapUI 5.7.2",
    "WinSCP"
)

$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($software in $softwareNames) {
    $found = $false
    foreach ($path in $uninstallPaths) {
        $match = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$software*" }
        if ($match) {
            Write-Output "Installed: $($match.DisplayName)"
            $found = $true
            break
        }
    }
    if (-not $found) {
        Write-Output "Missing: $software not found in registry"
    }
}

Write-Output "`n=== VALIDATING EXE INSTALLED SOFTWARE (BY PATH) ==="
$exeChecks = @(
    @{Name="DbVisualizer"; Path="C:\Program Files\DbVisualizer"},
    @{Name="JDK 8u371"; Path="C:\Program Files\Java\jdk1.8.0_371"},
    @{Name="NoSQL Workbench"; Path="C:\Program Files\NoSQL Workbench"},
    @{Name="pgAdmin 4"; Path="C:\Program Files\pgAdmin 4"},
    @{Name="S3 Browser"; Path="C:\Program Files (x86)\S3 Browser"},
    @{Name="SoapUI"; Path="C:\Program Files\SmartBear\SoapUI-5.7.2"},
    @{Name="WinSCP"; Path="C:\Program Files (x86)\WinSCP"}
)

foreach ($item in $exeChecks) {
    if (Test-Path $item.Path) {
        Write-Output "Installed: $($item.Name) found at $($item.Path)"
    } else {
        Write-Output "Missing: $($item.Name) not found at $($item.Path)"
    }
}

Write-Output "`n=== VALIDATING ZIP-EXTRACTED SOFTWARE FOLDERS ==="
$zipChecks = @(
    @{Name="SQL Workbench"; Path="C:\Softwares\SQLworkbench"},
    @{Name="Simba JDBC"; Path="C:\Softwares\SimbaAthenaJDBC-2.0.25.1001"},
    @{Name="Redshift JDBC"; Path="C:\Softwares\Redshift-jdbc42-2.1.0.24"}
)

foreach ($item in $zipChecks) {
    if (Test-Path $item.Path) {
        Write-Output "Installed: $($item.Name) directory exists"
    } else {
        Write-Output "Missing: $($item.Name) directory not found"
    }
}

Write-Output "`n=== VALIDATION COMPLETE ==="
Stop-Transcript
