Add-Type -AssemblyName System.Speech
$synth = New-Object -TypeName System.Speech.Synthesis.SpeechSynthesizer
$synth.Speak("Hey $env:USERNAME, your job is finished!")

$Folder = 'C:\temp'
"Test to see if folder [$Folder]  exists"
if (Test-Path -Path $Folder) {
    "Path exists!"
} else {
    "Path doesn't exist. Creating Folder" | New-Item -Path 'C:\temp' -ItemType Directory
}