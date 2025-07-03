# Set Execution Policy
Set-ExecutionPolicy Bypass -Scope Process -Force

# Define download directory
$downloadPath = "C:\Temp\Downloads"
New-Item -Path $downloadPath -ItemType Directory -Force | Out-Null
Write-Output "[$(Get-Date -Format u)] Created download directory at $downloadPath"

# Define headers for authenticated downloads
$header = "Authorization"
$authValue = "Basic <REPLACE_WITH_BASE64_ENCODED_CREDENTIALS>"
$headers = @{}
$headers.Add($header, $authValue)

# Helper function to download files with headers
function Download-File($url, $dest) {
    Write-Output "[$(Get-Date -Format u)] Downloading $url to $dest"
    Invoke-WebRequest -Uri $url -OutFile $dest -Headers $headers -UseBasicParsing
    Write-Output "[$(Get-Date -Format u)] Downloaded: $dest"
}

# Helper function to unzip
function Extract-Zip($zipPath, $destPath) {
    Write-Output "[$(Get-Date -Format u)] Extracting $zipPath to $destPath"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destPath)
    Write-Output "[$(Get-Date -Format u)] Extraction completed for: $zipPath"
}

# Install MSI
function Install-MSI($path) {
    Write-Output "[$(Get-Date -Format u)] Installing MSI: $path"
    Start-Process "msiexec.exe" -ArgumentList "/i `"$path`" /qn /norestart" -Wait
    Write-Output "[$(Get-Date -Format u)] Installed MSI: $path"
}

# Install EXE
function Install-EXE($path, $silentArgs = "/quiet /norestart") {
    Write-Output "[$(Get-Date -Format u)] Installing EXE: $path"
    Start-Process $path -ArgumentList $silentArgs -Wait
    Write-Output "[$(Get-Date -Format u)] Installed EXE: $path"
}

# --- DOWNLOAD AND INSTALL SOFTWARE ---

$softwareList = @{
    "AWSCLIV2.msi"                             = "msi"
    "mysql-workbench-community-8.0.25-winx64.msi" = "msi"
    "putty-64bit-0.77-installer.msi"           = "msi"
    "dbvis_windows-x64_10_0_15_jre.exe"        = "exe"
    "jdk-8u371-windows-x64.exe"               = "exe"
    "NoSQL Workbench-win-3.2.2.exe"           = "exe"
    "pgadmin4-6.9-x64.exe"                    = "exe"
    "s3browser-11-4-5.exe"                    = "exe"
    "SoapUI-x64-5.72.exe"                     = "exe"
    "WinSCP-5.21.7-Setup.exe"                 = "exe"
}

foreach ($file in $softwareList.Keys) {
    $url = "https://<Artifactory-URL>/$file"
    $localPath = Join-Path $downloadPath $file
    Download-File $url $localPath

    if ($softwareList[$file] -eq "msi") {
        Install-MSI $localPath
    } elseif ($softwareList[$file] -eq "exe") {
        Install-EXE $localPath
    }
}

# --- HANDLE SPECIAL ZIP INSTALLATIONS ---

# SQL Workbench
$sqlZip = "Workbench-Build128.zip"
$sqlUrl = "https://<Artifactory-URL>/$sqlZip"
$sqlDir = "C:\Softwares\SQLworkbench"
New-Item -ItemType Directory -Path $sqlDir -Force | Out-Null
$sqlZipPath = Join-Path $downloadPath $sqlZip
Download-File $sqlUrl $sqlZipPath
Extract-Zip $sqlZipPath $sqlDir

# Add config file
$configFile = "ViewSourceSta..nts.xml"
$configPath = Join-Path $sqlDir $configFile
Download-File "https://<Artifactory-URL>/$configFile" $configPath

# Simba Athena JDBC
$simbaZip = "SimbaAthenaJDBC-2.0.25.1001.zip"
$simbaDir = "C:\Softwares\SimbaAthenaJDBC-2.0.25.1001"
New-Item -ItemType Directory -Path $simbaDir -Force | Out-Null
$simbaZipPath = Join-Path $downloadPath $simbaZip
Download-File "https://<Artifactory-URL>/$simbaZip" $simbaZipPath
Extract-Zip $simbaZipPath $simbaDir

# Redshift JDBC
$redshiftZip = "Redshift-jdbc42-2.1.0.24.zip"
$redshiftDir = "C:\Softwares\Redshift-jdbc42-2.1.0.24"
New-Item -ItemType Directory -Path $redshiftDir -Force | Out-Null
$redshiftZipPath = Join-Path $downloadPath $redshiftZip
Download-File "https://<Artifactory-URL>/$redshiftZip" $redshiftZipPath
Extract-Zip $redshiftZipPath $redshiftDir

Write-Output "[$(Get-Date -Format u)] All downloads, installations, and extractions completed successfully."
