param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [string]$OutputZip = "FolderArchiveWebHosted_Package.zip"
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "FolderArchiveWebHosted\FolderArchiveWebHosted.csproj"
$publishDirectory = Join-Path $PSScriptRoot "publish-hosted-web"
$packagePath = Join-Path $PSScriptRoot $OutputZip

if (-not (Test-Path $project)) {
    throw "Hosted web project not found: $project"
}

dotnet publish $project -c $Configuration -r $Runtime --self-contained false -o $publishDirectory
if ($LASTEXITCODE -ne 0) {
    throw "Hosted web console publish failed with exit code $LASTEXITCODE."
}

if (Test-Path $packagePath) {
    Remove-Item -LiteralPath $packagePath
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($publishDirectory, $packagePath)
Write-Host "Hosted web package created: $packagePath"
