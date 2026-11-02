param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [string]$OutputZip = "FolderArchiveWebConsole_Package.zip"
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "FolderArchiveWebConsole\FolderArchiveWebConsole.csproj"
$publishDirectory = Join-Path $PSScriptRoot "publish-web-console"
$packagePath = Join-Path $PSScriptRoot $OutputZip

if (-not (Test-Path $project)) {
    throw "Project not found: $project"
}

dotnet publish $project -c $Configuration -r $Runtime --self-contained false -o $publishDirectory
if ($LASTEXITCODE -ne 0) {
    throw "Web console publish failed with exit code $LASTEXITCODE."
}

if (Test-Path $packagePath) {
    Remove-Item -LiteralPath $packagePath
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($publishDirectory, $packagePath)
Write-Host "Web console package created: $packagePath"
