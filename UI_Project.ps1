Add-Type -AssemblyName System.Windows.Forms


$FormObject = [System.Windows.Forms.Form]
# Removed unused variable $labelObject
$ButtonObject = [System.Windows.Forms.Button]

$HelloWorldForm=New-Object $FormObject
$HelloWorldForm.ClientSize='500,300'
$HelloWorldForm.Text='Hello World - Tutorial'
$helloWolrdForm.BackColor="#ffffff"

$lbltitle=New-Object $FormObject
$lbltitle.Text='Hellow World!'
$lbltitle.AutoSize=$true
$lbltitle.Font='Verdana,24,style=Bold'
$lbltitle.Location=New-Object System.Drawing.Point(120,110)

$btnHello=New-Object $ButtonObject
$btnHello.Text='Say Hello!'
$btnHello.Autosize=$true
$btnHello.font='Verdana,14'
$btnHello.Location=New-Object System.Drawing.Point(185,180,$btnHello)


$helloWolrdForm.controls.addRange(@(title))

#Logic Section & Functions

function sayHello{
    if($lbltitle.Text -eq ''){
        $lbltitle.Text="Hello World!"
    }else{
        $lbltitle.Text=''
    }
    
}

#Add the function to the form

$btnHello.Add_Click({sayHello})

#Display the form
$HelloWorldForm.ShowDialog()

#Clean Up
$HelloWorldForm.Dispose()