
Add-Type -AssemblyName System.Windows.Forms

$form = New-Object System.Windows.Forms.Form
$form.Text = "TextBox and Label Example"
$form.Width = 400
$form.Height = 200

$label = New-Object System.Windows.Forms.Label
$label.Text = "Enter text:"
$label.Top = 20
$label.Left = 20
$form.Controls.Add($label)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Top = 50
$textBox.Left = 20
$form.Controls.Add($textBox)

$button = New-Object System.Windows.Forms.Button
$button.Text = "Update Label"
$button.Top = 80
$button.Left = 20
$button.Add_Click({
    $label.Text = $textBox.Text
})
$form.Controls.Add($button)

$form.ShowDialog()
