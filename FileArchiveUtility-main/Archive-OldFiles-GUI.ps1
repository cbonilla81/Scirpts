<#
.SYNOPSIS
    GUI-based file archival utility.

.DESCRIPTION
    Finds files older than a selected number of days and moves them from a
    source location to an archive location while preserving the folder structure.

    Dry Run mode previews the operation without moving or deleting anything.

.REQUIREMENTS
    Windows PowerShell 5.1 or PowerShell 7 on Windows
    Must run in STA mode for Windows Forms
#>

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-STA"
            "-File", "`"$PSCommandPath`""
        )
        exit
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:IsRunning = $false
$script:Results = [System.Collections.Generic.List[object]]::new()
$script:TextLogPath = $null
$script:CsvLogPath = $null

$script:ExcludedExtensions = @(".tmp", ".lock")
$script:ExcludedFolderNames = @("ActiveProjects", "LegalHold", "DoNotArchive")

$form = New-Object System.Windows.Forms.Form
$form.Text = "File Archive Utility"
$form.Size = New-Object System.Drawing.Size(900, 700)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(800, 600)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.AutoScaleMode = "Dpi"

$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = "Top"
$headerPanel.Height = 75
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(35, 55, 75)
$form.Controls.Add($headerPanel)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "File Archive Utility"
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(20, 10)
$headerPanel.Controls.Add($titleLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = "Move files older than a selected age to an archive server"
$subtitleLabel.ForeColor = [System.Drawing.Color]::Gainsboro
$subtitleLabel.AutoSize = $true
$subtitleLabel.Location = New-Object System.Drawing.Point(23, 45)
$headerPanel.Controls.Add($subtitleLabel)

$configGroup = New-Object System.Windows.Forms.GroupBox
$configGroup.Text = "Archive Configuration"
$configGroup.Location = New-Object System.Drawing.Point(15, 90)
$configGroup.Size = New-Object System.Drawing.Size(850, 215)
$configGroup.Anchor = "Top, Left, Right"
$form.Controls.Add($configGroup)

$sourceLabel = New-Object System.Windows.Forms.Label
$sourceLabel.Text = "Source path:"
$sourceLabel.AutoSize = $true
$sourceLabel.Location = New-Object System.Drawing.Point(20, 35)
$configGroup.Controls.Add($sourceLabel)

$sourceTextBox = New-Object System.Windows.Forms.TextBox
$sourceTextBox.Location = New-Object System.Drawing.Point(130, 31)
$sourceTextBox.Size = New-Object System.Drawing.Size(600, 25)
$sourceTextBox.Anchor = "Top, Left, Right"
$configGroup.Controls.Add($sourceTextBox)

$sourceBrowseButton = New-Object System.Windows.Forms.Button
$sourceBrowseButton.Text = "Browse..."
$sourceBrowseButton.Location = New-Object System.Drawing.Point(740, 29)
$sourceBrowseButton.Size = New-Object System.Drawing.Size(85, 29)
$sourceBrowseButton.Anchor = "Top, Right"
$configGroup.Controls.Add($sourceBrowseButton)

$destinationLabel = New-Object System.Windows.Forms.Label
$destinationLabel.Text = "Archive path:"
$destinationLabel.AutoSize = $true
$destinationLabel.Location = New-Object System.Drawing.Point(20, 75)
$configGroup.Controls.Add($destinationLabel)

$destinationTextBox = New-Object System.Windows.Forms.TextBox
$destinationTextBox.Location = New-Object System.Drawing.Point(130, 71)
$destinationTextBox.Size = New-Object System.Drawing.Size(600, 25)
$destinationTextBox.Anchor = "Top, Left, Right"
$configGroup.Controls.Add($destinationTextBox)

$destinationBrowseButton = New-Object System.Windows.Forms.Button
$destinationBrowseButton.Text = "Browse..."
$destinationBrowseButton.Location = New-Object System.Drawing.Point(740, 69)
$destinationBrowseButton.Size = New-Object System.Drawing.Size(85, 29)
$destinationBrowseButton.Anchor = "Top, Right"
$configGroup.Controls.Add($destinationBrowseButton)

$ageLabel = New-Object System.Windows.Forms.Label
$ageLabel.Text = "Archive files older than:"
$ageLabel.AutoSize = $true
$ageLabel.Location = New-Object System.Drawing.Point(20, 118)
$configGroup.Controls.Add($ageLabel)

$ageNumeric = New-Object System.Windows.Forms.NumericUpDown
$ageNumeric.Location = New-Object System.Drawing.Point(180, 114)
$ageNumeric.Size = New-Object System.Drawing.Size(90, 25)
$ageNumeric.Minimum = 1
$ageNumeric.Maximum = 36500
$ageNumeric.Value = 365
$configGroup.Controls.Add($ageNumeric)

$daysLabel = New-Object System.Windows.Forms.Label
$daysLabel.Text = "days"
$daysLabel.AutoSize = $true
$daysLabel.Location = New-Object System.Drawing.Point(280, 118)
$configGroup.Controls.Add($daysLabel)

$dryRunCheckBox = New-Object System.Windows.Forms.CheckBox
$dryRunCheckBox.Text = "Dry Run mode - preview only; do not move files"
$dryRunCheckBox.Checked = $true
$dryRunCheckBox.AutoSize = $true
$dryRunCheckBox.Location = New-Object System.Drawing.Point(370, 116)
$configGroup.Controls.Add($dryRunCheckBox)

$removeEmptyCheckBox = New-Object System.Windows.Forms.CheckBox
$removeEmptyCheckBox.Text = "Remove empty source folders after archival"
$removeEmptyCheckBox.Checked = $true
$removeEmptyCheckBox.AutoSize = $true
$removeEmptyCheckBox.Location = New-Object System.Drawing.Point(20, 158)
$configGroup.Controls.Add($removeEmptyCheckBox)

$overwriteCheckBox = New-Object System.Windows.Forms.CheckBox
$overwriteCheckBox.Text = "Overwrite older destination files"
$overwriteCheckBox.Checked = $false
$overwriteCheckBox.AutoSize = $true
$overwriteCheckBox.Location = New-Object System.Drawing.Point(370, 158)
$configGroup.Controls.Add($overwriteCheckBox)

$statusGroup = New-Object System.Windows.Forms.GroupBox
$statusGroup.Text = "Status"
$statusGroup.Location = New-Object System.Drawing.Point(15, 315)
$statusGroup.Size = New-Object System.Drawing.Size(850, 275)
$statusGroup.Anchor = "Top, Bottom, Left, Right"
$form.Controls.Add($statusGroup)

$statusTextBox = New-Object System.Windows.Forms.RichTextBox
$statusTextBox.Location = New-Object System.Drawing.Point(15, 25)
$statusTextBox.Size = New-Object System.Drawing.Size(820, 200)
$statusTextBox.Anchor = "Top, Bottom, Left, Right"
$statusTextBox.ReadOnly = $true
$statusTextBox.BackColor = [System.Drawing.Color]::White
$statusTextBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$statusTextBox.WordWrap = $false
$statusGroup.Controls.Add($statusTextBox)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(15, 235)
$progressBar.Size = New-Object System.Drawing.Size(820, 22)
$progressBar.Anchor = "Bottom, Left, Right"
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$statusGroup.Controls.Add($progressBar)

$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = "Run Dry Test"
$runButton.Location = New-Object System.Drawing.Point(15, 605)
$runButton.Size = New-Object System.Drawing.Size(130, 38)
$runButton.Anchor = "Bottom, Left"
$runButton.BackColor = [System.Drawing.Color]::FromArgb(40, 120, 180)
$runButton.ForeColor = [System.Drawing.Color]::White
$runButton.FlatStyle = "Flat"
$form.Controls.Add($runButton)

$openLogsButton = New-Object System.Windows.Forms.Button
$openLogsButton.Text = "Open Logs"
$openLogsButton.Location = New-Object System.Drawing.Point(155, 605)
$openLogsButton.Size = New-Object System.Drawing.Size(110, 38)
$openLogsButton.Anchor = "Bottom, Left"
$form.Controls.Add($openLogsButton)

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = "Clear Status"
$clearButton.Location = New-Object System.Drawing.Point(275, 605)
$clearButton.Size = New-Object System.Drawing.Size(110, 38)
$clearButton.Anchor = "Bottom, Left"
$form.Controls.Add($clearButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "Close"
$closeButton.Location = New-Object System.Drawing.Point(755, 605)
$closeButton.Size = New-Object System.Drawing.Size(110, 38)
$closeButton.Anchor = "Bottom, Right"
$form.Controls.Add($closeButton)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Text = "Mode: DRY RUN"
$modeLabel.AutoSize = $true
$modeLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$modeLabel.ForeColor = [System.Drawing.Color]::DarkOrange
$modeLabel.Location = New-Object System.Drawing.Point(620, 615)
$modeLabel.Anchor = "Bottom, Right"
$form.Controls.Add($modeLabel)

function Write-GuiLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "WHATIF")][string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp [$Level] $Message"
    $color = switch ($Level) {
        "SUCCESS" { [System.Drawing.Color]::DarkGreen }
        "WARNING" { [System.Drawing.Color]::DarkOrange }
        "ERROR"   { [System.Drawing.Color]::DarkRed }
        "WHATIF"  { [System.Drawing.Color]::DarkCyan }
        default   { [System.Drawing.Color]::Black }
    }

    $statusTextBox.SelectionStart = $statusTextBox.TextLength
    $statusTextBox.SelectionColor = $color
    $statusTextBox.AppendText($entry + [Environment]::NewLine)
    $statusTextBox.SelectionColor = $statusTextBox.ForeColor
    $statusTextBox.ScrollToCaret()

    if ($script:TextLogPath) {
        try { Add-Content -LiteralPath $script:TextLogPath -Value $entry } catch {}
    }

    [System.Windows.Forms.Application]::DoEvents()
}

function Add-ArchiveResult {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$ItemType,
        [string]$Status,
        [string]$Details,
        [long]$SizeBytes = 0
    )

    $script:Results.Add([PSCustomObject]@{
        Timestamp   = Get-Date
        ItemType    = $ItemType
        Source      = $Source
        Destination = $Destination
        SizeBytes   = $SizeBytes
        SizeMB      = [math]::Round($SizeBytes / 1MB, 2)
        Status      = $Status
        Details     = $Details
    })
}

function Test-IsExcludedPath {
    param([Parameter(Mandatory)][string]$FullPath)
    $pathParts = $FullPath -split "[\\/]"
    foreach ($excludedFolder in $script:ExcludedFolderNames) {
        if ($pathParts -contains $excludedFolder) { return $true }
    }
    return $false
}

function Test-IsDestinationInsideSource {
    param([string]$Source, [string]$Destination)
    try {
        $normalizedSource = [System.IO.Path]::GetFullPath($Source.TrimEnd("\"))
        $normalizedDestination = [System.IO.Path]::GetFullPath($Destination.TrimEnd("\"))
        return $normalizedDestination.StartsWith(
            $normalizedSource + "\",
            [System.StringComparison]::OrdinalIgnoreCase
        )
    }
    catch { return $false }
}

function Set-ControlsEnabled {
    param([bool]$Enabled)
    $sourceTextBox.Enabled = $Enabled
    $destinationTextBox.Enabled = $Enabled
    $sourceBrowseButton.Enabled = $Enabled
    $destinationBrowseButton.Enabled = $Enabled
    $ageNumeric.Enabled = $Enabled
    $dryRunCheckBox.Enabled = $Enabled
    $removeEmptyCheckBox.Enabled = $Enabled
    $overwriteCheckBox.Enabled = $Enabled
    $runButton.Enabled = $Enabled
}

function Select-Folder {
    param([string]$Description, [string]$InitialPath)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($InitialPath -and (Test-Path -LiteralPath $InitialPath)) {
        $dialog.SelectedPath = $InitialPath
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Export-ArchiveResults {
    if ($script:Results.Count -eq 0 -or -not $script:CsvLogPath) { return }
    try {
        $script:Results | Export-Csv -LiteralPath $script:CsvLogPath -NoTypeInformation -Encoding UTF8
        Write-GuiLog "CSV report created: $script:CsvLogPath" "SUCCESS"
    }
    catch {
        Write-GuiLog "Could not export CSV report: $($_.Exception.Message)" "ERROR"
    }
}

function Start-ArchiveOperation {
    $sourcePath = $sourceTextBox.Text.Trim()
    $archivePath = $destinationTextBox.Text.Trim()
    $ageInDays = [int]$ageNumeric.Value
    $dryRun = $dryRunCheckBox.Checked
    $removeEmptyFolders = $removeEmptyCheckBox.Checked
    $overwriteExisting = $overwriteCheckBox.Checked

    if ([string]::IsNullOrWhiteSpace($sourcePath)) {
        [System.Windows.Forms.MessageBox]::Show("Enter or select a source path.", "Source Path Required", "OK", "Warning")
        return
    }
    if ([string]::IsNullOrWhiteSpace($archivePath)) {
        [System.Windows.Forms.MessageBox]::Show("Enter or select an archive destination.", "Archive Path Required", "OK", "Warning")
        return
    }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show("The source path could not be found or accessed.`n`n$sourcePath", "Invalid Source Path", "OK", "Error")
        return
    }
    if ($sourcePath.TrimEnd("\") -eq $archivePath.TrimEnd("\")) {
        [System.Windows.Forms.MessageBox]::Show("The source and archive paths cannot be the same.", "Invalid Configuration", "OK", "Error")
        return
    }
    if (Test-IsDestinationInsideSource -Source $sourcePath -Destination $archivePath) {
        [System.Windows.Forms.MessageBox]::Show("The archive destination cannot be inside the source folder.", "Invalid Configuration", "OK", "Error")
        return
    }

    if (-not $dryRun) {
        $confirmation = [System.Windows.Forms.MessageBox]::Show(
            "Dry Run mode is disabled.`n`nEligible files will be moved to:`n$archivePath`n`nContinue?",
            "Confirm Archive Operation",
            "YesNo",
            "Warning"
        )
        if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    $script:IsRunning = $true
    $script:Results.Clear()
    $progressBar.Value = 0
    Set-ControlsEnabled -Enabled $false

    try {
        $logDirectory = Join-Path $env:ProgramData "FileArchiveUtility\Logs"
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $script:TextLogPath = Join-Path $logDirectory "Archive_$timestamp.log"
        $script:CsvLogPath = Join-Path $logDirectory "Archive_$timestamp.csv"
        New-Item -Path $script:TextLogPath -ItemType File -Force | Out-Null

        $cutoffDate = (Get-Date).AddDays(-$ageInDays)
        $normalizedSource = $sourcePath.TrimEnd("\")

        Write-GuiLog "Archive operation started."
        Write-GuiLog "Source: $sourcePath"
        Write-GuiLog "Destination: $archivePath"
        Write-GuiLog "Age threshold: $ageInDays days"
        Write-GuiLog "Cutoff date: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))"
        if ($dryRun) {
            Write-GuiLog "DRY RUN is enabled. No files will be moved." "WARNING"
        } else {
            Write-GuiLog "LIVE MODE is enabled. Eligible files will be moved." "WARNING"
        }

        if (-not (Test-Path -LiteralPath $archivePath)) {
            if ($dryRun) {
                Write-GuiLog "Destination folder would be created: $archivePath" "WHATIF"
            } else {
                New-Item -Path $archivePath -ItemType Directory -Force | Out-Null
                Write-GuiLog "Created destination folder: $archivePath" "SUCCESS"
            }
        }

        Write-GuiLog "Scanning source folder for eligible files."
        $eligibleFiles = @(
            Get-ChildItem -LiteralPath $sourcePath -File -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.LastWriteTime -lt $cutoffDate -and
                    $_.Extension -notin $script:ExcludedExtensions -and
                    -not (Test-IsExcludedPath -FullPath $_.FullName)
                }
        )

        $totalFiles = $eligibleFiles.Count
        $totalBytes = ($eligibleFiles | Measure-Object Length -Sum).Sum
        if ($null -eq $totalBytes) { $totalBytes = 0 }

        Write-GuiLog "Eligible files found: $totalFiles"
        Write-GuiLog ("Total eligible size: {0:N2} GB" -f ($totalBytes / 1GB))

        if ($totalFiles -eq 0) {
            Write-GuiLog "No eligible files were found." "WARNING"
            $progressBar.Value = 100
            return
        }

        $processedFiles = 0
        foreach ($file in $eligibleFiles) {
            $processedFiles++
            $progressBar.Value = [math]::Min([math]::Floor(($processedFiles / $totalFiles) * 100), 100)

            try {
                $relativePath = $file.FullName.Substring($normalizedSource.Length).TrimStart("\")
                $destinationFile = Join-Path $archivePath $relativePath
                $destinationDirectory = Split-Path -Path $destinationFile -Parent

                if (Test-Path -LiteralPath $destinationFile) {
                    $existingFile = Get-Item -LiteralPath $destinationFile -ErrorAction Stop
                    if (-not $overwriteExisting) {
                        $message = "Destination file already exists."
                        Write-GuiLog "Skipped: $relativePath - $message" "WARNING"
                        Add-ArchiveResult -Source $file.FullName -Destination $destinationFile -ItemType "File" -Status "Skipped" -Details $message -SizeBytes $file.Length
                        continue
                    }
                    if ($existingFile.LastWriteTime -ge $file.LastWriteTime) {
                        $message = "Archive copy is the same age or newer."
                        Write-GuiLog "Skipped: $relativePath - $message" "WARNING"
                        Add-ArchiveResult -Source $file.FullName -Destination $destinationFile -ItemType "File" -Status "Skipped" -Details $message -SizeBytes $file.Length
                        continue
                    }
                }

                if ($dryRun) {
                    Write-GuiLog "Would move: $relativePath" "WHATIF"
                    Add-ArchiveResult -Source $file.FullName -Destination $destinationFile -ItemType "File" -Status "WhatIf" -Details "File would be moved." -SizeBytes $file.Length
                    continue
                }

                if (-not (Test-Path -LiteralPath $destinationDirectory)) {
                    New-Item -Path $destinationDirectory -ItemType Directory -Force | Out-Null
                }

                Move-Item -LiteralPath $file.FullName -Destination $destinationFile -Force:$overwriteExisting -ErrorAction Stop
                if (-not (Test-Path -LiteralPath $destinationFile)) { throw "Destination verification failed." }

                Write-GuiLog "Archived: $relativePath" "SUCCESS"
                Add-ArchiveResult -Source $file.FullName -Destination $destinationFile -ItemType "File" -Status "Archived" -Details "File successfully moved." -SizeBytes $file.Length
            }
            catch {
                $message = $_.Exception.Message
                Write-GuiLog "Failed: $($file.FullName) - $message" "ERROR"
                Add-ArchiveResult -Source $file.FullName -Destination $destinationFile -ItemType "File" -Status "Failed" -Details $message -SizeBytes $file.Length
            }
        }

        if ($removeEmptyFolders) {
            Write-GuiLog "Checking for empty source folders."
            $directories = @(
                Get-ChildItem -LiteralPath $sourcePath -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.LastWriteTime -lt $cutoffDate -and
                        -not (Test-IsExcludedPath -FullPath $_.FullName)
                    } |
                    Sort-Object { $_.FullName.Split("\").Count } -Descending
            )

            foreach ($directory in $directories) {
                try {
                    $remainingItem = Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction Stop | Select-Object -First 1
                    if ($null -ne $remainingItem) { continue }

                    if ($dryRun) {
                        Write-GuiLog "Would remove empty folder: $($directory.FullName)" "WHATIF"
                        Add-ArchiveResult -Source $directory.FullName -Destination "" -ItemType "Folder" -Status "WhatIf" -Details "Empty folder would be removed."
                        continue
                    }

                    Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction Stop
                    Write-GuiLog "Removed empty folder: $($directory.FullName)" "SUCCESS"
                    Add-ArchiveResult -Source $directory.FullName -Destination "" -ItemType "Folder" -Status "Removed" -Details "Empty source folder removed."
                }
                catch {
                    Write-GuiLog "Could not remove folder $($directory.FullName): $($_.Exception.Message)" "WARNING"
                }
            }
        }

        $progressBar.Value = 100
        Export-ArchiveResults

        $archivedCount = @($script:Results | Where-Object Status -eq "Archived").Count
        $whatIfCount = @($script:Results | Where-Object Status -eq "WhatIf").Count
        $skippedCount = @($script:Results | Where-Object Status -eq "Skipped").Count
        $failedCount = @($script:Results | Where-Object Status -eq "Failed").Count

        Write-GuiLog "Archive process completed."
        Write-GuiLog "Archived: $archivedCount"
        Write-GuiLog "Dry Run actions: $whatIfCount"
        Write-GuiLog "Skipped: $skippedCount"
        Write-GuiLog "Failed: $failedCount"

        [System.Windows.Forms.MessageBox]::Show(
            "Archive operation completed.`n`nArchived: $archivedCount`nDry Run actions: $whatIfCount`nSkipped: $skippedCount`nFailed: $failedCount`n`nLogs:`n$logDirectory",
            "Archive Complete",
            "OK",
            "Information"
        )
    }
    catch {
        Write-GuiLog "Fatal error: $($_.Exception.Message)" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("The operation encountered an error:`n`n$($_.Exception.Message)", "Archive Error", "OK", "Error")
    }
    finally {
        Export-ArchiveResults
        $script:IsRunning = $false
        Set-ControlsEnabled -Enabled $true
    }
}

$sourceBrowseButton.Add_Click({
    $selectedPath = Select-Folder -Description "Select the source folder" -InitialPath $sourceTextBox.Text
    if ($selectedPath) { $sourceTextBox.Text = $selectedPath }
})

$destinationBrowseButton.Add_Click({
    $selectedPath = Select-Folder -Description "Select the archive destination" -InitialPath $destinationTextBox.Text
    if ($selectedPath) { $destinationTextBox.Text = $selectedPath }
})

$dryRunCheckBox.Add_CheckedChanged({
    if ($dryRunCheckBox.Checked) {
        $modeLabel.Text = "Mode: DRY RUN"
        $modeLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        $runButton.Text = "Run Dry Test"
    } else {
        $modeLabel.Text = "Mode: LIVE"
        $modeLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $runButton.Text = "Run Archive"
    }
})

$runButton.Add_Click({ Start-ArchiveOperation })

$openLogsButton.Add_Click({
    $logDirectory = Join-Path $env:ProgramData "FileArchiveUtility\Logs"
    if (-not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }
    Start-Process explorer.exe -ArgumentList "`"$logDirectory`""
})

$clearButton.Add_Click({
    $statusTextBox.Clear()
    $progressBar.Value = 0
})

$closeButton.Add_Click({
    if ($script:IsRunning) {
        [System.Windows.Forms.MessageBox]::Show("An archive operation is currently running.", "Operation in Progress", "OK", "Warning")
        return
    }
    $form.Close()
})

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:IsRunning) {
        $eventArgs.Cancel = $true
        [System.Windows.Forms.MessageBox]::Show("The program cannot be closed while an archive operation is running.", "Operation in Progress", "OK", "Warning")
    }
})

[void]$form.ShowDialog()
