# ================================================
# Verify Required Files Exist in a Folder
# ================================================

# Folder to check
$FolderPath = "C:\Windows\WinSxS\Manifests"

# List of required files
$RequiredFiles = @(
    "amd64_microsoft-windows-n..ion-agent.resources_31bf3856ad364e35_10.0.20348.1_en-us_da1dd958579a40f0.manifest",
    "msil_microsoft.hyperv.powershell.resources_31bf3856ad364e35_10.0.20348.1_en-us_87b758fae3d25ee1.manifest",
    "msil_microsoft.hyperv.po..l.objects.resources_31bf3856ad364e35_10.0.20348.1_en-us_540825df3e2b71b3.manifest",
    "amd64_microsoft-hyper-v-m..apinabout.resources_31bf3856ad364e35_10.0.20348.1_en-us_a692e4eb62ced8b3.manifest",
    "amd64_microsoft-hyper-v-m..wallrules.resources_31bf3856ad364e35_10.0.20348.1_en-us_64005ff48bb0a8e2.manifest",
    "msil_microsoft.virtualiz..mon.types.resources_31bf3856ad364e35_10.0.20348.1_en-us_d90f2ec4219eb18e.manifest"
)

Write-Host "Checking folder: $FolderPath" -ForegroundColor Cyan
Write-Host "----------------------------------------"

# Verify folder exists
if (!(Test-Path $FolderPath)) {
    Write-Host "ERROR: Folder does not exist: $FolderPath" -ForegroundColor Red
    exit 1
}

$MissingFiles = @()

foreach ($File in $RequiredFiles) {

    $FullPath = Join-Path $FolderPath $File

    if (Test-Path $FullPath) {
        Write-Host "[FOUND]   $File" -ForegroundColor Green
    }
    else {
        Write-Host "[MISSING] $File" -ForegroundColor Yellow
        $MissingFiles += $File
    }
}

Write-Host ""
Write-Host "========================================"

if ($MissingFiles.Count -eq 0) {
    Write-Host "SUCCESS: All required files are present." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "WARNING: The following files are missing:" -ForegroundColor Red
    $MissingFiles | ForEach-Object {
        Write-Host " - $_"
    }

    exit 1
}