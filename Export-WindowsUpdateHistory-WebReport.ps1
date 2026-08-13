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
Write-Host "               Patch Installed Checker" -ForegroundColor Cyan
Write-Host "        Windows Server 2022 Component Store Validator" -ForegroundColor Yellow
Write-Host "              Jolly Roger Troubleshooting Toolkit" -ForegroundColor Green
Write-Host "             Christian Marrero Bonilla" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray


# Export-WindowsUpdateHistory-WebReport.ps1
# Windows Server 2022 Update History Report with Web UI
Add-Type -AssemblyName System.Web
$ReportFolder = "C:\Temp\WindowsUpdateReport"
$CsvPath = "$ReportFolder\WindowsUpdateHistory.csv"
$HtmlPath = "$ReportFolder\WindowsUpdateHistoryReport.html"

if (!(Test-Path $ReportFolder)) {
    New-Item -Path $ReportFolder -ItemType Directory -Force | Out-Null
}

$ComputerName = $env:COMPUTERNAME
$GeneratedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$OSInfo = Get-CimInstance Win32_OperatingSystem

$Session = New-Object -ComObject Microsoft.Update.Session
$Searcher = $Session.CreateUpdateSearcher()
$HistoryCount = $Searcher.GetTotalHistoryCount()
$Updates = $Searcher.QueryHistory(0, $HistoryCount)

$Results = $Updates | Select-Object `
    @{Name="Date";Expression={$_.Date}},
    @{Name="Title";Expression={$_.Title}},
    @{Name="Description";Expression={$_.Description}},
    @{Name="ResultCode";Expression={
        switch ($_.ResultCode) {
            0 {"NotStarted"}
            1 {"InProgress"}
            2 {"Succeeded"}
            3 {"SucceededWithErrors"}
            4 {"Failed"}
            5 {"Aborted"}
            default {"Unknown"}
        }
    }},
    @{Name="Operation";Expression={
        switch ($_.Operation) {
            1 {"Installation"}
            2 {"Uninstallation"}
            default {"Other"}
        }
    }},
    @{Name="SupportUrl";Expression={$_.SupportUrl}},
    @{Name="ClientApplicationID";Expression={$_.ClientApplicationID}},
    @{Name="HResult";Expression={$_.HResult}}

$Results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

$TotalUpdates = $Results.Count
$Succeeded = ($Results | Where-Object {$_.ResultCode -eq "Succeeded"}).Count
$Failed = ($Results | Where-Object {$_.ResultCode -eq "Failed"}).Count
$Warnings = ($Results | Where-Object {$_.ResultCode -eq "SucceededWithErrors"}).Count
$Aborted = ($Results | Where-Object {$_.ResultCode -eq "Aborted"}).Count

$Rows = foreach ($Item in $Results) {

    $StatusClass = switch ($Item.ResultCode) {
        "Succeeded" {"success"}
        "Failed" {"failed"}
        "SucceededWithErrors" {"warning"}
        "Aborted" {"aborted"}
        default {"neutral"}
    }

    $SafeTitle = [System.Web.HttpUtility]::HtmlEncode($Item.Title)
    $SafeDescription = [System.Web.HttpUtility]::HtmlEncode($Item.Description)

    @"
<tr>
    <td>$($Item.Date)</td>
    <td>$SafeTitle</td>
    <td>$($Item.Operation)</td>
    <td><span class='badge $StatusClass'>$($Item.ResultCode)</span></td>
    <td>$($Item.ClientApplicationID)</td>
    <td>$($Item.HResult)</td>
    <td><a href='$($Item.SupportUrl)' target='_blank'>Support</a></td>
</tr>
"@
}

$Html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Windows Update History Report</title>
<style>
body {
    margin: 0;
    font-family: Segoe UI, Arial, sans-serif;
    background: #f4f7fb;
    color: #1f2937;
}

.header {
    background: linear-gradient(135deg, #0f172a, #1d4ed8);
    color: white;
    padding: 35px;
}

.header h1 {
    margin: 0;
    font-size: 34px;
}

.header p {
    margin: 8px 0 0;
    opacity: .9;
}

.container {
    padding: 30px;
}

.cards {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 18px;
    margin-bottom: 30px;
}

.card {
    background: white;
    border-radius: 14px;
    padding: 22px;
    box-shadow: 0 6px 18px rgba(0,0,0,.08);
}

.card h2 {
    margin: 0;
    font-size: 28px;
}

.card p {
    margin: 6px 0 0;
    color: #64748b;
}

.success-card { border-left: 6px solid #16a34a; }
.failed-card { border-left: 6px solid #dc2626; }
.warning-card { border-left: 6px solid #f59e0b; }
.aborted-card { border-left: 6px solid #7c3aed; }
.total-card { border-left: 6px solid #2563eb; }

.report-box {
    background: white;
    border-radius: 14px;
    padding: 25px;
    box-shadow: 0 6px 18px rgba(0,0,0,.08);
}

table {
    width: 100%;
    border-collapse: collapse;
    font-size: 14px;
}

th {
    background: #0f172a;
    color: white;
    padding: 12px;
    text-align: left;
}

td {
    padding: 12px;
    border-bottom: 1px solid #e5e7eb;
    vertical-align: top;
}

tr:hover {
    background: #f1f5f9;
}

.badge {
    padding: 6px 10px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: bold;
    color: white;
}

.success { background: #16a34a; }
.failed { background: #dc2626; }
.warning { background: #f59e0b; }
.aborted { background: #7c3aed; }
.neutral { background: #64748b; }

.footer {
    text-align: center;
    padding: 25px;
    color: #64748b;
    font-size: 13px;
}

a {
    color: #2563eb;
    text-decoration: none;
}

@media print {
    .header {
        background: #0f172a !important;
    }
}
</style>
</head>

<body>

<div class="header">
    <h1>Windows Update History Report</h1>
    <p>Server: $ComputerName</p>
    <p>Operating System: $($OSInfo.Caption) - Build $($OSInfo.BuildNumber)</p>
    <p>Generated: $GeneratedDate</p>
</div>

<div class="container">

    <div class="cards">
        <div class="card total-card">
            <h2>$TotalUpdates</h2>
            <p>Total Updates</p>
        </div>

        <div class="card success-card">
            <h2>$Succeeded</h2>
            <p>Succeeded</p>
        </div>

        <div class="card failed-card">
            <h2>$Failed</h2>
            <p>Failed</p>
        </div>

        <div class="card warning-card">
            <h2>$Warnings</h2>
            <p>Succeeded With Errors</p>
        </div>

        <div class="card aborted-card">
            <h2>$Aborted</h2>
            <p>Aborted</p>
        </div>
    </div>

    <div class="report-box">
        <h2>Update History Details</h2>

        <table>
            <thead>
                <tr>
                    <th>Date</th>
                    <th>Update Title</th>
                    <th>Operation</th>
                    <th>Status</th>
                    <th>Client</th>
                    <th>HResult</th>
                    <th>Support URL</th>
                </tr>
            </thead>
            <tbody>
                $Rows
            </tbody>
        </table>
    </div>

</div>

<div class="footer">
    Generated by PowerShell Windows Update History Report
</div>

</body>
</html>
"@

$Html | Out-File -FilePath $HtmlPath -Encoding UTF8

Write-Host "CSV report created: $CsvPath" -ForegroundColor Green
Write-Host "HTML report created: $HtmlPath" -ForegroundColor Green

Start-Process $HtmlPath