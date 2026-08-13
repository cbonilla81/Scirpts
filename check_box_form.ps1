
Add-Type -AssemblyName System.Windows.Forms

$form = New-Object System.Windows.Forms.Form
$form.Text = "CheckBox Example"
$form.Width = 300
$form.Height = 200

$checkBox = New-Object System.Windows.Forms.CheckBox
$checkBox.Text = "Check me"
$checkBox.Top = 20
$checkBox.Left = 20
$form.Controls.Add($checkBox)

$button = New-Object System.Windows.Forms.Button
$button.Text = "Check Status"
$button.Top = 60
$button.Left = 20
$button.Add_Click({
    $status = if ($checkBox.Checked) { "Checked" } else { "Unchecked" }
    [System.Windows.Forms.MessageBox]::Show("Status: " + $status)
})
$form.Controls.Add($button)

$form.ShowDialog()
