$ErrorActionPreference = "Stop"

$project = Join-Path $PSScriptRoot "FolderArchiveWebConsole\FolderArchiveWebConsole.csproj"
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw ".NET 8 SDK is required. Install it from https://dotnet.microsoft.com/download/dotnet/8.0."
}

Push-Location $PSScriptRoot
try {
    dotnet run --project $project
    if ($LASTEXITCODE -ne 0) {
        throw "The web console exited with code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
