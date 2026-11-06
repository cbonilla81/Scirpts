# Proxmox API Token Test - PowerShell 7

$ProxmoxServer = "rshgisvdi0101.rsandh.com"
$TokenID = "terraform@pam!tf"

$SecureToken = Read-Host "Enter API Token Secret" -AsSecureString

$BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken)

try {
    $TokenSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
}

$Headers = @{
    Authorization = "PVEAPIToken=$TokenID=$TokenSecret"
}

try {
    $Response = Invoke-RestMethod `
        -Uri "https://${ProxmoxServer}:8006/api2/json/nodes" `
        -Headers $Headers `
        -Method Get `
        -SkipCertificateCheck `
        -SkipHeaderValidation `
        -ErrorAction Stop

    Write-Host "`nSUCCESS: Proxmox API authentication works!" -ForegroundColor Green

    $Response.data |
        Select-Object node, status |
        Format-Table -AutoSize
}
catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Remove-Variable TokenSecret, Headers -ErrorAction SilentlyContinue
}