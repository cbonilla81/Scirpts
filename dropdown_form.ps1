
Add-Type -AssemblyName System.Windows.Forms

$form = New-Object System.Windows.Forms.Form
$form.Text = "ComboBox Example"
$form.Width = 300
$form.Height = 200

$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.Top = 20
$comboBox.Left = 20
$comboBox.Items.AddRange(@("Option 1", "Option 2", "Option 3"))
$form.Controls.Add($comboBox)

$button = New-Object System.Windows.Forms.Button
$button.Text = "Show Selected"
$button.Top = 60
$button.Left = 20
$button.Add_Click({
    [System.Windows.Forms.MessageBox]::Show("Selected: " + $comboBox.SelectedItem)
})
$form.Controls.Add($button)

$form.ShowDialog()
