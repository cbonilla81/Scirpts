# File Archive Utility

A Windows utility for finding aging files and moving them to an archive location while preserving the source folder structure. The project includes a PowerShell GUI, a Windows Forms desktop application, a localhost browser console, and a separately deployable hosted web console.

The localhost web console remains restricted to `localhost` for personal use. The separate hosted console is designed for Windows Server/IIS and uses Microsoft Entra ID sign-in for shared access.

## Included Files

- `Archive-OldFiles-GUI.ps1` — PowerShell GUI application.
- `FolderArchiveTool/` — .NET 8 Windows Forms desktop application.
- `FolderArchiveWebConsole/` — .NET 8 ASP.NET Core browser console.
- `FolderArchiveWebHosted/` — Separate .NET 8 hosted console with Entra ID authentication.
- `FolderArchiveWebConsole/wwwroot/RS&H_Logo.png` — RS&H logo displayed in the web console.
- `web-console-demo.html` — Standalone visual demo of the web console with sample data.
- `hosted-web-console-demo.html` — Standalone sign-in-to-console walkthrough for the hosted edition.
- `run_web_console.ps1` — Starts the web console from source.
- `build_web_console.ps1` — Publishes and packages the web console for Windows x64.
- `build_hosted_web.ps1` — Publishes and packages the hosted console for Windows x64.
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

- Scan a source tree recursively and review subfolders with recursive file counts, nested-folder counts, and total sizes.
- Select folders only, or use the header checkbox to select all folders in the source tree.
- Selecting a parent folder includes all nested subfolders; overlapping selections are prevented.
- Export every folder in the latest scan to CSV, including contents, size, and selection state.
- Export the completed job summary and activity log to CSV from the Job Activity panel.
- Archive all files in selected folders, regardless of age or file type.
- Files directly under the source root are not included; select one or more subfolders to archive.
- Preview the operation in Dry Run mode before moving files.
- Preserve the relative directory structure in the archive destination.
- Optionally remove empty source subfolders after successful moves.
- Optionally replace an existing destination file only when the source file is newer.
- View job progress and activity in the browser.
- Display the RS&H logo in the console navigation.
- The localhost edition is restricted to the local computer; it does not accept connections from other devices.

### Hosted Web Console

The hosted console is a separate application for shared use on Windows Server with IIS. It uses Microsoft Entra ID for sign-in and does not store user passwords. Console pages and APIs require an authenticated session, and state-changing requests require an anti-forgery token. Each user can see their own current job status; only one archive job can run at a time across a server instance.

The hosted console shares the folder-selection interface and file-processing service with the localhost web console. It lists subfolders recursively with recursive file counts, nested-folder counts, and total sizes. It supports selecting a subfolder under the configured source to archive all of its contents, regardless of age or file type. Selecting a parent folder includes all nested subfolders; overlapping selections are prevented. Files directly under the source root are not included, and the source root itself cannot be selected. Reparse-point folders are skipped, and existing destination files follow the configured skip/replace behavior. Review a Dry Run before starting a live archive. File operations run as the IIS application-pool identity.

#### Before you begin

You will need:

- A Windows Server supported by your organization, IIS, and permission to install the .NET 8 Hosting Bundle.
- A DNS name for the site, a valid HTTPS certificate, and network access to the site from intended users.
- A Microsoft Entra tenant administrator (or delegated application administrator) who can register an application and assign users/groups.
- A build machine with the .NET 8 SDK and a copy of this project.
- A dedicated Windows service identity for the IIS application pool, plus approved source and archive locations.

**File access and trust boundary:** Scans and moves run on the server as the IIS application-pool identity—not as the signed-in user. Users enter source and destination paths themselves, so they can request operations on any paths that identity can access. Restrict access to the application to trusted users, and use NTFS and file-server share permissions to limit the application identity to approved locations. Do not grant the identity broad access to server data. For network shares, use an appropriately managed domain service account or gMSA and grant both share and NTFS permissions. A local IIS virtual account generally will not have the credentials needed for remote shares.

#### 1. Register the application in Microsoft Entra ID

In the [Microsoft Entra admin center](https://entra.microsoft.com/):

1. Open **Identity > Applications > App registrations** and select **New registration**.
2. Give the app a recognizable name, such as **File Archive Hosted Console**.
3. Under supported account types, choose **Accounts in this organizational directory only** (single tenant), then register it.
4. On the app's **Overview** page, record the **Directory (tenant) ID** and **Application (client) ID**. These become the `TenantId` and `ClientId` settings below.
5. Open **Authentication > Add a platform > Web**. Add both HTTPS redirect URIs, replacing the example host with the final public DNS name:

   ```text
   https://archive.example.com/signin-oidc
   https://archive.example.com/signout-callback-oidc
   ```

   The host, scheme, port (if non-standard), and path must exactly match the deployed site. Do not use an HTTP redirect URI for production.
6. Under **Certificates & secrets > Client secrets**, create a secret with an expiry that meets your organization's policy. Copy the **secret value** immediately; it is shown only once. The secret ID is not the secret value.
7. Open **Enterprise applications > All applications**, select the new app, then open **Properties**. Set **Assignment required?** to **Yes** and save.
8. Under **Users and groups**, assign only the approved users and/or groups. Group assignment may require an appropriate Entra ID license. Users not assigned should not be able to sign in to the application.
9. Have your administrator review the app registration, secret expiry/rotation owner, and access assignments before production use.

No Microsoft Graph API permission or delegated file-storage permission is needed by this application. The app uses Entra ID only to authenticate users; file access is controlled by the Windows application-pool identity.

#### 2. Build the hosted package

On the build machine, open PowerShell in the project directory and run:

```powershell
.\build_hosted_web.ps1
```

The script publishes the separate `FolderArchiveWebHosted` project for Windows x64 and creates `FolderArchiveWebHosted_Package.zip` in the project directory. This is a framework-dependent deployment: the server must have the .NET 8 Hosting Bundle installed. Transfer the ZIP to the server using your organization's approved deployment method. Do not put Entra secrets in the ZIP or source files.

#### 3. Prepare the Windows Server and IIS

1. Install the current supported .NET 8 Hosting Bundle from Microsoft on the Windows Server. The bundle installs the ASP.NET Core Module used by IIS. Restart IIS services (or the server) after installation if the installer requests it.
2. Install/enable the IIS **Web Server** role. Allow inbound HTTPS (normally TCP 443) only from the networks that should reach the app. The server also needs outbound HTTPS access to Microsoft Entra sign-in endpoints.
3. Configure DNS for the chosen hostname and install/bind a valid TLS certificate to the IIS HTTPS site. Keep HTTP-to-HTTPS redirection enabled; the hosted app's authentication and anti-forgery cookies are Secure and require HTTPS.
4. Create a dedicated, non-administrator app-pool identity. For SMB shares, use an approved domain service account or gMSA. Grant it only:
   - Read/list/traverse permissions for approved source folders.
   - Read/list plus create/write/delete permissions required for the approved archive destination and move operation.
   - Read/execute permissions on the published application files.
   - Write access only to any explicitly configured log or persistent key directory.

   Test the identity's access to the exact local and UNC folders that operators will use. Do not rely on an administrator's interactive mapped drives; IIS services should use UNC paths.
5. Create a protected directory for the app, for example `C:\inetpub\FileArchiveHosted`, and extract the contents of `FolderArchiveWebHosted_Package.zip` there. Confirm that the published `web.config`, application executable, and `wwwroot` folder are present. Give the app-pool identity read/execute access to the deployment directory; limit who can read deployment/configuration files.
6. In IIS Manager, add an application pool for this app. Set **.NET CLR version** to **No Managed Code** and configure its identity as the dedicated service identity.
7. Add an IIS site (or application under an existing site) with the extracted directory as its physical path. Assign the dedicated application pool and bind the HTTPS hostname/certificate. For the simplest deployment, host it at the site root so the callback paths remain `/signin-oidc` and `/signout-callback-oidc`.
8. Configure the three Entra settings as environment variables available to the IIS worker process. For a site-specific setup, edit the published `web.config` and add an `<environmentVariables>` element inside its existing `<aspNetCore>` element, preserving the other published attributes and elements:

   ```text
   Authentication__Microsoft__TenantId=<Directory (tenant) ID GUID>
   Authentication__Microsoft__ClientId=<Application (client) ID GUID>
   Authentication__Microsoft__ClientSecret=<client secret VALUE>
   ```

   The names and values go into XML attributes like this (replace the placeholders; do not copy this example secret):

   ```xml
   <aspNetCore processPath="dotnet" arguments=".\FolderArchiveWebHosted.dll" stdoutLogEnabled="false" stdoutLogFile=".\logs\stdout">
     <environmentVariables>
       <environmentVariable name="Authentication__Microsoft__TenantId" value="YOUR-TENANT-GUID" />
       <environmentVariable name="Authentication__Microsoft__ClientId" value="YOUR-CLIENT-GUID" />
       <environmentVariable name="Authentication__Microsoft__ClientSecret" value="YOUR-SECRET-VALUE" />
     </environmentVariables>
   </aspNetCore>
   ```

   Keep the package's actual `processPath`, `arguments`, hosting model, and other generated settings; add only the `<environmentVariables>` child if they differ from the example. XML-escape special characters in values (for example, represent `&` as `&amp;`). Use your organization's approved secret-management process. Because the client secret is stored as plain text in `web.config`, restrict the file's NTFS permissions to server administrators and the IIS app-pool identity, do not check it into source control, and do not include it in support logs or deployment artifacts. Alternatively, configure machine-level environment variables in a controlled administrative session. Restart the application pool after changing environment variables. The application exits during startup if a setting is missing or either ID is not a GUID.
9. Start the site and review **Event Viewer > Windows Logs > Application** and IIS logs if the worker fails to start. Verify that HTTPS reaches the site and HTTP redirects to HTTPS.

#### 4. Test Entra sign-in and archive behavior

1. From an allowed user account on a client computer, browse to `https://archive.example.com/`. The app should send the browser to the organization's Microsoft sign-in page.
2. Sign in with an assigned account. The browser should return to the hosted console and show the signed-in account. Use **Sign out** to test logout.
3. Test an unassigned account. Access should be denied by Entra or the application; if it is allowed, stop deployment and correct the Enterprise Application assignment settings.
4. Enter a small, approved test source folder and a separate test destination available to the app-pool identity. Scan the source and verify the recursive folder list, file counts, subfolder counts, and sizes.
5. Leave **Dry run** enabled, run it, and confirm the activity log only reports the expected preview. Then test a live move only with disposable test files and explicit operational approval.
6. Confirm the app cannot read or write paths outside the locations granted to its service identity. Review the IIS service account's actual local and share permissions rather than relying solely on UI behavior.
7. Confirm another assigned user cannot see the first user's job status. The server permits only one active job at a time.

#### Operations and troubleshooting

- **Redirect URI mismatch / sign-in loop:** Check the Entra Web redirect URI exactly matches the deployed HTTPS hostname and `/signin-oidc`; also register `/signout-callback-oidc`. Ensure IIS forwards the original HTTPS scheme correctly when TLS terminates at a reverse proxy.
- **Startup fails with missing configuration:** Verify the three environment variable names and values, then recycle the app pool. IDs must be GUIDs; use the client secret **value**, not its ID.
- **HTTP 500.30 / process won't start:** Confirm the .NET 8 Hosting Bundle is installed, app-pool read/execute permissions are correct, environment variables are present, and inspect the Windows Application event log. Disable detailed errors in production; do not publish secrets or tokens in logs.
- **Sign-in succeeds but folder access fails:** File permissions belong to the IIS app-pool identity. For a UNC path, verify both SMB share and NTFS permissions and confirm the service identity can reach the share.
- **Secret rotation:** Create a replacement secret in Entra, update the protected server configuration, recycle the app pool, test sign-in, and remove the old secret after validation. Track expiry to avoid an outage.
- The current coordinator keeps job status in process memory, and only one job runs per server process. An app restart/recycle loses status; avoid deployments or routine recycles during active archive jobs. Job history is not persisted.
- For multiple IIS instances, configure a shared ASP.NET Core Data Protection key ring and the same application name on every instance; otherwise authentication cookies may not be readable on another node. Coordinate jobs across nodes separately—the current in-memory single-job guard is per process, not distributed.
- Keep Windows, IIS, the .NET Hosting Bundle, and the Entra client secret maintained under your organization's patching and rotation policies.

The hosted web console lists folders recursively and archives every file within selected folders, regardless of age or file type. Files directly under the source root are not included. Reparse-point folders are skipped. Folder lists and job activity can be downloaded as CSV, but those exports are not retained as persistent reports. Unlike the PowerShell GUI, it does not currently provide folder compression.

The localhost web console lists folders recursively and archives every file within selected folders, regardless of age or file type. Files directly under the source root are not included. Reparse-point folders are skipped. Folder lists and job activity can be downloaded as CSV, but those exports are not retained as persistent reports. Unlike the PowerShell GUI, the web console does not currently provide folder compression.

### Web Console Demo

To preview the interface without starting the web server, open [web-console-demo.html](./web-console-demo.html) in a browser from the project directory. The demo displays sample folders, contents, and dry-run activity; it does not scan folders or move files. Keep the adjacent `FolderArchiveWebConsole` directory in place so the demo can load the RS&H logo.

To preview the hosted sign-in page and then the hosted console layout, open [hosted-web-console-demo.html](./hosted-web-console-demo.html). Select **Continue to hosted console demo** to view the sample console, or **Back to sign-in** to return to the login screen. This walkthrough is static: sign-in is simulated and no files are scanned or moved. Keep `web-console-demo.html` and the `FolderArchiveWebConsole` directory beside the hosted demo so its embedded console and logo load correctly.

## Windows Forms Desktop Features

The .NET desktop application supports scanning a folder tree, reviewing and checking candidate files and folders, file filters, Dry Run, live moves, optional removal of empty source folders, folder compression to ZIP, and interactive per-item move and overwrite prompts. Its current age threshold is 365 days.

## Requirements

- Windows 10, Windows 11, Windows Server 2016, 2019, 2022, or newer.
- Windows PowerShell 5.1 is recommended.
- PowerShell 7 can also work on Windows when Windows Forms is available.
- The web console and Windows Forms application require the .NET 8 SDK to run from source.
- A published web console package requires the .NET 8 ASP.NET Core Runtime.
- The hosted web console requires the .NET 8 Hosting Bundle and IIS on Windows Server.
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

The web console scans the source tree recursively and lists each subfolder with the number of files and descendant folders and its total size. Select folders only; selecting a parent includes its nested subfolders. The header checkbox selects all top-level folders, which covers all subfolders. **Export folder list** downloads every listed subfolder with its path, recursive contents, total size, and selection state. Folder archiving includes all files regardless of age or file type. Files directly under the source root are not included, and the source root itself cannot be selected. After a job completes, **Export job output** in the Job Activity panel downloads a CSV with the final status, processed/moved/skipped/failed counts, and each activity entry. These downloads are not retained as persistent reports. Dry runs, live moves, optional removal of empty source folders, and replacing an existing destination file only when the source is newer are supported. Existing destination files that are not replaced are skipped. Reparse-point folders are skipped. The browser console does not currently offer folder compression; live job activity is shown in the console while it is running.

Use the separate [hosted web console](#hosted-web-console) for shared, authenticated access; the localhost edition remains limited to the computer running it.

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

The PowerShell GUI does not move entire folders based only on the folder date. It evaluates individual files to avoid archiving newer files inside an older folder. Both web console editions allow explicitly selecting a subfolder to archive all of its contents.

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
