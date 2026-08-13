[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""
Write-Host "        ⚔                         ☠                         ⚔" -ForegroundColor White
Write-Host ""
Write-Host "          ██╗ ██████╗ ██╗     ██╗     ██╗   ██╗    ██████╗" -ForegroundColor Red
Write-Host "          ██║██╔═══██╗██║     ██║      ╚██╗ ██╔╝   ██╔══██╗" -ForegroundColor Red
Write-Host "          ██║██║   ██║██║     ██║       ╚████╔╝    ██████╔╝" -ForegroundColor Red
Write-Host "     ██   ██║██║   ██║██║     ██║        ╚██╔╝     ██╔══██╗" -ForegroundColor Red
Write-Host "     ╚█████╔╝╚██████╔╝███████╗███████╗     ██║      ██║  ██║" -ForegroundColor Red
Write-Host "      ╚════╝  ╚═════╝ ╚══════╝╚══════╝     ╚═╝      ╚═╝  ╚═╝" -ForegroundColor Red
Write-Host ""
Write-Host "               WinSxS Manifest Checker" -ForegroundColor Cyan
Write-Host "        Windows Server 2022 Component Store Validator" -ForegroundColor Yellow
Write-Host "              Jolly Roger Troubleshooting Toolkit" -ForegroundColor Green
Write-Host "             Christian Marrero Bonilla" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray


# Path to the WinSxS Manifest folder
$ManifestPath = "C:\Windows\WinSxS\Manifests"

# Manifest file patterns
$ManifestList = @(
    "amd64_microsoft-hyper-v-m*apinabout.resources_31bf3856ad364e35_10.0.20348.1_en-us_a692e4eb62ced8b3.manifest"
    "amd64_microsoft-hyper-v-m*wallrules.resources_31bf3856ad364e35_10.0.20348.1_en-us_64005ff48bb0a8e2.manifest"
    "amd64_microsoft-windows-n*ion-agent.resources_31bf3856ad364e35_10.0.20348.1_en-us_da1dd958579a40f0.manifest"
    "msil_microsoft.hyperv.po*l.objects.resources_31bf3856ad364e35_10.0.20348.1_en-us_540825df3e2b71b3.manifest"
    "msil_microsoft.hyperv.powershell.resources_31bf3856ad364e35_10.0.20348.1_en-us_87b758fae3d25ee1.manifest"
    "msil_microsoft.virtualiz*mon.types.resources_31bf3856ad364e35_10.0.20348.1_en-us_d90f2ec4219eb18e.manifest"
)

$Results = foreach ($Manifest in $ManifestList) {

    $Found = Get-ChildItem -Path $ManifestPath -Filter $Manifest -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        Manifest = $Manifest
        Status   = if ($Found) { "Present" } else { "Missing" }
    }
}

Write-Host ""
Write-Host ("{0,-105} {1}" -f "Manifest","Status") -ForegroundColor Cyan
Write-Host ("-" * 120)

foreach ($Result in $Results) {

    Write-Host ("{0,-105}" -f $Result.Manifest) -NoNewline

    if ($Result.Status -eq "Present") {
        Write-Host "Present" -ForegroundColor Green
    }
    else {
        Write-Host "Missing" -ForegroundColor Red
    }
}