
# Proxmox API Token Test
# Replace with your Proxmox server IP or hostname
$ProxmoxServer = "rshgisvdi0101.rsandh.com"

# Enter your API token ID
$TokenID = "terraform@pam!tf"

# Securely prompt for the API token secret
$SecureToken = Read-Host "2fb7f85d-b4db-4ec0-b189-50e1fe402ce8" -AsSecureString

# Convert secret temporarily for HTTP authentication
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

$Uri = "https://${ProxmoxServer}:8006/api2/json/nodes"

try {
    $Response = Invoke-RestMethod `
        -Uri $Uri `
        -Headers $Headers `
        -Method GET `
        -ErrorAction Stop

    Write-Host "`nSUCCESS: Proxmox API authentication works!" -ForegroundColor Green

    $Response.data | Select-Object node, status, cpu, maxmem |
        Format-Table -AutoSize
}
catch {
    Write-Host "`nFAILED: Proxmox API request failed." -ForegroundColor Red
    Write-Host $_.Exception.Message
}
finally {
    Remove-Variable TokenSecret, Headers -ErrorAction SilentlyContinue
}