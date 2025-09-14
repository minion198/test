
# install-software.ps1
# Script for AIB to install software packages silently with special handling for Java and NoSQL Workbench

Set-ExecutionPolicy Bypass -Scope Process -Force

$downloadPath = "C:\Temp\Downloads"
New-Item -Path $downloadPath -ItemType Directory -Force | Out-Null
Write-Output "[$(Get-Date -Format u)] Created download directory at $downloadPath"

# Auth headers
$header = "Authorization"
$authValue = "Basic <REPLACE_WITH_BASE64_ENCODED_CREDENTIALS>"
$headers = @{}
$headers.Add($header, $authValue)

# Special install paths
$JavaFilePath = "$downloadPath\jdk-8u371-windows-x64.exe"
$NoSQLPath    = "$downloadPath\NoSQL Workbench-win-3.2.2.exe"

# Download helper
function Download-File($url, $dest) {
    Write-Output "[$(Get-Date -Format u)] Downloading $url to $dest"
    Invoke-WebRequest -Uri $url -OutFile $dest -Headers $headers -UseBasicParsing
    Write-Output "[$(Get-Date -Format u)] Downloaded: $dest"
}

# Zip extractor
function Extract-Zip($zipPath, $destPath) {
    Write-Output "[$(Get-Date -Format u)] Extracting $zipPath to $destPath"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destPath)
    Write-Output "[$(Get-Date -Format u)] Extraction completed for: $zipPath"
}

# Universal installer
function Install-IndividualFile {
    param([string]$FilePath)

    $ext = [System.IO.Path]::GetExtension($FilePath)

    if ($ext -eq ".exe") {
        if ($FilePath -ieq $JavaFilePath) {
            Write-Output "[$(Get-Date -Format u)] Starting special installation for Java"
            Start-Process -FilePath $FilePath -ArgumentList "/s" -Wait
            Write-Output "[$(Get-Date -Format u)] Finished installing Java"
        }
        elseif ($FilePath -ieq $NoSQLPath) {
            Write-Output "[$(Get-Date -Format u)] Starting installation of NoSQL Workbench"
            Start-Process -FilePath $FilePath
            Start-Sleep -Seconds 120
            taskkill /IM "NoSQL Workbench-win-3.2.2.exe" /F
            Write-Output "[$(Get-Date -Format u)] Finished NoSQL Workbench install with wait and kill"
        }
        else {
            Write-Output "[$(Get-Date -Format u)] Installing EXE: $FilePath"
            Start-Process -FilePath $FilePath -ArgumentList "/quiet /norestart" -Wait
            Write-Output "[$(Get-Date -Format u)] Installed EXE: $FilePath"
        }
    }
    elseif ($ext -eq ".msi") {
        Write-Output "[$(Get-Date -Format u)] Installing MSI: $FilePath"
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$FilePath`" /qn /norestart" -Wait
        Write-Output "[$(Get-Date -Format u)] Installed MSI: $FilePath"
    }
}

# Software list
$softwareFiles = @(
    "AWSCLIV2.msi",
    "mysql-workbench-community-8.0.25-winx64.msi",
    "putty-64bit-0.77-installer.msi",
    "dbvis_windows-x64_10_0_15_jre.exe",
    "jdk-8u371-windows-x64.exe",
    "NoSQL Workbench-win-3.2.2.exe",
    "pgadmin4-6.9-x64.exe",
    "s3browser-11-4-5.exe",
    "SoapUI-x64-5.72.exe",
    "WinSCP-5.21.7-Setup.exe"
)

foreach ($file in $softwareFiles) {
    $url = "https://<Artifactory-URL>/$file"
    $dest = Join-Path $downloadPath $file
    Download-File $url $dest
    Install-IndividualFile -FilePath $dest
}

# SQL Workbench
$sqlZip = "Workbench-Build128.zip"
$sqlDir = "C:\Softwares\SQLworkbench"
$sqlZipPath = Join-Path $downloadPath $sqlZip
Download-File "https://<Artifactory-URL>/$sqlZip" $sqlZipPath
New-Item -ItemType Directory -Path $sqlDir -Force | Out-Null
Extract-Zip $sqlZipPath $sqlDir
Download-File "https://<Artifactory-URL>/ViewSourceSta..nts.xml" (Join-Path $sqlDir "ViewSourceSta..nts.xml")

# Simba JDBC
$simbaZip = "SimbaAthenaJDBC-2.0.25.1001.zip"
$simbaDir = "C:\Softwares\SimbaAthenaJDBC-2.0.25.1001"
$simbaZipPath = Join-Path $downloadPath $simbaZip
Download-File "https://<Artifactory-URL>/$simbaZip" $simbaZipPath
New-Item -ItemType Directory -Path $simbaDir -Force | Out-Null
Extract-Zip $simbaZipPath $simbaDir

# Redshift JDBC
$redshiftZip = "Redshift-jdbc42-2.1.0.24.zip"
$redshiftDir = "C:\Softwares\Redshift-jdbc42-2.1.0.24"
$redshiftZipPath = Join-Path $downloadPath $redshiftZip
Download-File "https://<Artifactory-URL>/$redshiftZip" $redshiftZipPath
New-Item -ItemType Directory -Path $redshiftDir -Force | Out-Null
Extract-Zip $redshiftZipPath $redshiftDir

Write-Output "[$(Get-Date -Format u)] All software installation and extraction completed successfully."
