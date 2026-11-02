# File Archive Utility

A Windows utility for finding aging files and moving them to an archive location while preserving the source folder structure. The project includes three interactive editions: a PowerShell GUI, a Windows Forms desktop application, and a browser-based web console.

The web console is an additional edition, not a replacement for the existing applications. It runs on the Windows computer and is restricted to `localhost`; it is intended for interactive local use, not as a shared network service.

## Included Files

- `Archive-OldFiles-GUI.ps1` — PowerShell GUI application.
- `FolderArchiveTool/` — .NET 8 Windows Forms desktop application.
- `FolderArchiveWebConsole/` — .NET 8 ASP.NET Core browser console.
- `FolderArchiveWebConsole/wwwroot/RS&H_Logo.png` — RS&H logo displayed in the web console.
- `web-console-demo.html` — Standalone visual demo of the web console with sample data.
- `run_web_console.ps1` — Starts the web console from source.
- `build_web_console.ps1` — Publishes and packages the web console for Windows x64.
- `build_and_package.ps1` — Publishes and packages the Windows Forms application.
- `Installer/` — Windows Installer project for the desktop application.
- `README.md` — Installation, usage, configuration, and safety instructions.

## PowerShell GUI Features

- Select the source folder using a browse button or enter a UNC path.
- Select the archive destination using a browse button or enter a UNC path.
- Choose the age threshold in days. The default is 365 days.
- Dry Run mode is enabled by default.
- Preserve the original directory structure at the archive destination.
- Optionally remove empty source folders after archival.
- Optionally overwrite destination files when the archived copy is older.
- Display live status information and progress.
- Create detailed text and CSV logs.
- Prevent use of the same source and destination path.
- Prevent placing the archive destination inside the source folder.

## Web Console Features

- Scan a source folder recursively and review up to 5,000 eligible files.
- Filter by age, extension, minimum or maximum size, and excluded path text.
- Select individual candidates or all candidates shown in the scan.
- Preview the operation in Dry Run mode before moving files.
- Preserve the relative directory structure in the archive destination.
- Optionally remove empty source subfolders after successful moves.
- Optionally replace an existing destination file only when the source file is newer.
- View job progress and activity in the browser.
- Display the RS&H logo in the console navigation.
- Restrict the web server to the local computer; it does not accept connections from other devices.

The web console requires both the file's last access time and last modified time to be older than the selected age threshold. Reparse-point folders are skipped. Unlike the PowerShell GUI, the web console does not currently provide folder compression or persistent text/CSV reports.

### Web Console Demo

To preview the interface without starting the web server, open [web-console-demo.html](./web-console-demo.html) in a browser from the project directory. The demo displays sample paths, candidate files, and dry-run activity; it does not scan folders or move files. Keep the adjacent `FolderArchiveWebConsole` directory in place so the demo can load the RS&H logo.

## Windows Forms Desktop Features

The .NET desktop application supports scanning a folder tree, reviewing and checking candidate files and folders, file filters, Dry Run, live moves, optional removal of empty source folders, folder compression to ZIP, and interactive per-item move and overwrite prompts. Its current age threshold is 365 days.

## Requirements

- Windows 10, Windows 11, Windows Server 2016, 2019, 2022, or newer.
- Windows PowerShell 5.1 is recommended.
- PowerShell 7 can also work on Windows when Windows Forms is available.
- The web console and Windows Forms application require the .NET 8 SDK to run from source.
- A published web console package requires the .NET 8 ASP.NET Core Runtime.
- The account running the script must have appropriate file permissions.

### Required Permissions

The account running the program should have:

- Read, list, write, and delete permissions on the source location.
- Read, write, and create-folder permissions on the archive destination.
- Access to both servers when UNC paths are used.

Example UNC paths:

```text
\\FileServer01\Data
\\ArchiveServer01\Archive\Data
```

## Extracting the Package

1. Right-click the ZIP file.
2. Select **Extract All**.
3. Extract the files to a local directory, such as:

```text
C:\Scripts\FileArchiveUtility
```

Avoid running the script directly from inside the ZIP file.

## Running the Utility

### Web Console Edition

The web console is an additional version; it does not replace the existing PowerShell or Windows Forms applications. It requires the .NET 8 SDK to run from source.

1. Open PowerShell in the extracted project folder.
2. Run:

```powershell
.\run_web_console.ps1
```

The console starts a local web server at `http://localhost:5187` and attempts to open the browser. Keep the PowerShell window open while using the console; press **Ctrl+C** to stop it.

The web console supports recursive file scans, age and file filters, candidate selection, dry runs, live file moves, optional removal of empty source folders, and replacing an existing destination file only when the source is newer. Both last access and last write timestamps must be older than the age threshold. Reparse-point folders are skipped. The browser console does not currently offer folder compression or persistent text/CSV reports; job activity is shown in the console while it is running.

Dry Run is enabled by default. For a live operation, review the scan, disable Dry Run, confirm the warning, and start the job. The source and destination must be different, and the destination cannot be inside the source. The console does not accept connections from other computers; do not change its loopback binding to expose it to a network.

To publish a Windows x64 package:

```powershell
.\build_web_console.ps1
```

The script creates `FolderArchiveWebConsole_Package.zip` from the publish output. The target computer needs the .NET 8 ASP.NET Core Runtime. Extract the package and run `FolderArchiveWebConsole.exe`; the browser console remains bound to localhost.

### PowerShell GUI Edition

### Method 1: Run from PowerShell

Open Windows PowerShell and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "C:\Scripts\FileArchiveUtility\Archive-OldFiles-GUI.ps1"
```

### Method 2: Right-click the Script

You can right-click `Archive-OldFiles-GUI.ps1` and select **Run with PowerShell**.

If the GUI does not appear, use Method 1 to ensure STA mode is enabled.

### Method 3: Create a Desktop Shortcut

Create a desktop shortcut using this target:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "C:\Scripts\FileArchiveUtility\Archive-OldFiles-GUI.ps1"
```

Set **Start in** to:

```text
C:\Scripts\FileArchiveUtility
```

### Windows Forms Desktop Edition

The Windows Forms edition is a separate .NET application. With the .NET 8 SDK installed, start it from the project directory:

```powershell
dotnet run --project .\FolderArchiveTool\FolderArchiveTool.csproj
```

To publish and package the desktop application for Windows x64, run:

```powershell
.\build_and_package.ps1
```

## Using the PowerShell GUI

### 1. Select the Source Path

Choose the folder containing the files you want to evaluate.

Example:

```text
\\FileServer01\DepartmentData
```

### 2. Select the Archive Path

Choose the destination where old files should be archived.

Example:

```text
\\ArchiveServer01\Archive\DepartmentData
```

The utility recreates the source folder structure under the archive destination.

Example source file:

```text
\\FileServer01\DepartmentData\Finance\2023\Report.xlsx
```

Example archived file:

```text
\\ArchiveServer01\Archive\DepartmentData\Finance\2023\Report.xlsx
```

### 3. Set the File Age

The default value is:

```text
365 days
```

The utility uses the file's `LastWriteTime` value. A file is eligible when its last modified date is older than the selected cutoff date.

### 4. Use Dry Run Mode First

Dry Run mode is enabled by default.

When enabled, the utility:

- Scans the source location.
- Identifies eligible files.
- Shows what would be moved.
- Produces logs and a CSV report.
- Does not move files.
- Does not create archive folders.
- Does not remove source folders.

Always review the Dry Run output before running in Live mode.

### 5. Live Mode

To move files:

1. Complete and review a Dry Run.
2. Clear the **Dry Run mode** checkbox.
3. Click **Run Archive**.
4. Confirm the warning prompt.

Live mode moves eligible files to the archive destination.

## Remove Empty Source Folders (PowerShell GUI)

When selected, the utility removes source folders only when:

- The folder is older than the configured cutoff.
- The folder is empty after files are moved.
- The folder is not listed as an excluded folder.

The utility does not move entire folders based only on the folder date. It evaluates individual files to avoid archiving newer files inside an older folder.

## Overwrite Older Destination Files (PowerShell GUI)

This option is disabled by default.

When disabled:

- A source file is skipped if a file already exists at the archive destination.

When enabled:

- The destination file can be replaced when the source file is newer.
- The destination file is not replaced when it is the same age or newer.

## Logs and Reports (PowerShell GUI)

Logs are stored under:

```text
C:\ProgramData\FileArchiveUtility\Logs
```

The application creates two files for each execution:

```text
Archive_YYYYMMDD_HHMMSS.log
Archive_YYYYMMDD_HHMMSS.csv
```

The CSV report includes:

- Timestamp
- Item type
- Source path
- Destination path
- File size in bytes
- File size in megabytes
- Status
- Details

Possible status values include:

- `Archived`
- `WhatIf`
- `Skipped`
- `Failed`
- `Removed`

## Default Exclusions

The script excludes these file extensions:

```text
.tmp
.lock
```

The script excludes folders with these names:

```text
ActiveProjects
LegalHold
DoNotArchive
```

To change the exclusions, edit these sections near the top of the script:

```powershell
$script:ExcludedExtensions = @(".tmp", ".lock")
$script:ExcludedFolderNames = @("ActiveProjects", "LegalHold", "DoNotArchive")
```

Example:

```powershell
$script:ExcludedExtensions = @(
    ".tmp",
    ".lock",
    ".bak"
)

$script:ExcludedFolderNames = @(
    "ActiveProjects",
    "LegalHold",
    "DoNotArchive",
    "Executive",
    "CurrentContracts"
)
```

## PowerShell Execution Policy

If Windows blocks the script, use:

```powershell
Unblock-File -Path "C:\Scripts\FileArchiveUtility\Archive-OldFiles-GUI.ps1"
```

You can also launch it with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "C:\Scripts\FileArchiveUtility\Archive-OldFiles-GUI.ps1"
```

The `Bypass` option applies only to that PowerShell process and does not permanently change the computer's execution policy.

## Recommended Testing Procedure

Before using the utility on production data:

1. Create a small test source folder.
2. Add a few files with different modified dates.
3. Select a test archive destination.
4. Run with Dry Run enabled.
5. Review the status window and CSV report.
6. Run Live mode using the test data.
7. Confirm that the folder structure was preserved.
8. Confirm that newer files remained in the source location.
9. Confirm that only empty folders were removed.
10. Run a Dry Run against production data before enabling Live mode.

## Changing File Dates for Testing

You can create a test file and set its last modified date using PowerShell:

```powershell
New-Item -Path "C:\ArchiveTest\OldFile.txt" -ItemType File -Force
(Get-Item "C:\ArchiveTest\OldFile.txt").LastWriteTime = (Get-Date).AddDays(-400)
```

Create a newer file:

```powershell
New-Item -Path "C:\ArchiveTest\NewFile.txt" -ItemType File -Force
(Get-Item "C:\ArchiveTest\NewFile.txt").LastWriteTime = (Get-Date).AddDays(-30)
```

Set the GUI threshold to 365 days. Only `OldFile.txt` should be eligible.

## Important Safety Notes

- Always run in Dry Run mode first.
- Review the CSV report before enabling Live mode.
- Ensure the archive destination has sufficient free storage.
- Confirm backup and retention policies before moving production files.
- Do not archive folders subject to legal hold, active investigations, or compliance restrictions.
- Test access using the same account that will run the application.
- Avoid using mapped drive letters for scheduled or service accounts. UNC paths are more reliable.
- The script moves files. A successful move removes the file from the source location.

## Troubleshooting

### The GUI Does Not Open

Run the script using STA mode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\Archive-OldFiles-GUI.ps1"
```

### Access Is Denied

Verify that the account has permissions on both the source and destination shares.

Test access:

```powershell
Test-Path "\\FileServer01\Data"
Test-Path "\\ArchiveServer01\Archive\Data"
```

### The Source Path Is Not Found

Confirm:

- The server is online.
- DNS resolves the server name.
- The share name is correct.
- The account has permission to list the share.

### Files Are Being Skipped

Check whether:

- The destination file already exists.
- The file is newer than the cutoff date.
- The file extension is excluded.
- The file is located in an excluded folder.
- The account cannot access the file.

### Logs Cannot Be Created

The default log directory is:

```text
C:\ProgramData\FileArchiveUtility\Logs
```

Run PowerShell with sufficient local permissions or change the log path in the script.

## Scheduling Consideration

This version is designed as an interactive GUI application. For unattended scheduled execution, use a separate non-GUI version or modify the script to accept command-line parameters.

A Windows Scheduled Task should normally use a service account with permissions to both UNC paths.
