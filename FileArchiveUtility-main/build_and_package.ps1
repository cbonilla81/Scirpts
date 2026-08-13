param(
    [string]$OutputZip = "FolderArchiveTool_Package.zip",
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)

$proj = Join-Path -Path $PSScriptRoot -ChildPath "FolderArchiveTool\FolderArchiveTool.csproj"
if (-not (Test-Path $proj)) { Write-Error "Project not found: $proj"; exit 1 }

Write-Host "Publishing project..."
dotnet publish $proj -c $Configuration -r $Runtime --self-contained false -o "$PSScriptRoot\publish" --no-restore

if ($LASTEXITCODE -ne 0) { Write-Error "Publish failed"; exit $LASTEXITCODE }

if (Test-Path "$PSScriptRoot\$OutputZip") { Remove-Item "$PSScriptRoot\$OutputZip" }

Write-Host "Creating zip $OutputZip from publish folder"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory("$PSScriptRoot\publish", "$PSScriptRoot\$OutputZip")
Write-Host "Package created: $OutputZip"