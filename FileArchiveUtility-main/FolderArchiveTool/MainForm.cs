using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace FolderArchiveTool
{
    public class MainForm : Form
    {
        TextBox txtSource = null!, txtDestination = null!;
        Button btnBrowseSource = null!, btnBrowseDest = null!, btnScan = null!, btnExecute = null!;
        TreeView treeCandidates = null!;
        TextBox txtPreview = null!, txtLog = null!;
        ProgressBar progressBar = null!;
        CheckBox chkDryRun = null!, chkRemoveEmpty = null!, chkApplyChoiceToAll = null!;

        // New UI for compression and filters
        CheckBox chkCompressFolders = null!;
        TextBox txtIncludeExt = null!, txtExcludeExt = null!, txtMinSizeMb = null!, txtMaxSizeMb = null!, txtExcludePaths = null!;

        DateTime thresholdDateUtc;
        string sourceRoot = string.Empty;

        // Move prompt state
        bool lastChoiceMove = false;
        bool applyChoiceToAll = false;

        // Overwrite prompt state
        bool lastOverwriteChoice = false;
        bool applyOverwriteToAll = false;

        FilterSettings currentFilters = new FilterSettings();

        public MainForm()
        {
            Text = "Folder Archive Tool";
            Width = 1000;
            Height = 700;
            InitializeComponents();
        }

        void InitializeComponents()
        {
            Label lblSource = new Label() { Text = "Source:", Left = 10, Top = 15, Width = 50 };
            txtSource = new TextBox() { Left = 70, Top = 10, Width = 720 };
            btnBrowseSource = new Button() { Text = "Browse...", Left = 800, Top = 8, Width = 80 };
            btnBrowseSource.Click += (s, e) => { using var dlg = new FolderBrowserDialog(); if (dlg.ShowDialog() == DialogResult.OK) txtSource.Text = dlg.SelectedPath; };

            Label lblDest = new Label() { Text = "Destination:", Left = 10, Top = 50, Width = 70 };
            txtDestination = new TextBox() { Left = 90, Top = 45, Width = 700 };
            btnBrowseDest = new Button() { Text = "Browse...", Left = 800, Top = 43, Width = 80 };
            btnBrowseDest.Click += (s, e) => { using var dlg = new FolderBrowserDialog(); if (dlg.ShowDialog() == DialogResult.OK) txtDestination.Text = dlg.SelectedPath; };

            btnScan = new Button() { Text = "Scan for candidates", Left = 10, Top = 85, Width = 160 };
            btnScan.Click += async (s, e) => await ScanAsync();
            chkDryRun = new CheckBox() { Text = "Dry run (don't move files)", Left = 190, Top = 90, Width = 200, Checked = true };
            chkRemoveEmpty = new CheckBox() { Text = "Remove empty source folders after move", Left = 400, Top = 90, Width = 260, Checked = true };

            // Compression option
            chkCompressFolders = new CheckBox() { Text = "Compress folder candidates to .zip", Left = 690, Top = 90, Width = 250, Checked = false };

            // Filter inputs
            var lblInclude = new Label() { Text = "Include extensions (comma):", Left = 10, Top = 115, Width = 180 };
            txtIncludeExt = new TextBox() { Left = 200, Top = 112, Width = 260, Text = "" };

            var lblExclude = new Label() { Text = "Exclude extensions (comma):", Left = 470, Top = 115, Width = 180 };
            txtExcludeExt = new TextBox() { Left = 650, Top = 112, Width = 220, Text = "" };

            var lblMinSize = new Label() { Text = "Min size (MB, optional):", Left = 10, Top = 145, Width = 180 };
            txtMinSizeMb = new TextBox() { Left = 200, Top = 142, Width = 100, Text = "" };

            var lblMaxSize = new Label() { Text = "Max size (MB, optional):", Left = 320, Top = 145, Width = 180 };
            txtMaxSizeMb = new TextBox() { Left = 500, Top = 142, Width = 100, Text = "" };

            var lblExcludePaths = new Label() { Text = "Exclude paths (newline or comma separated):", Left = 620, Top = 145, Width = 300 };
            txtExcludePaths = new TextBox() { Left = 620, Top = 165, Width = 340, Height = 40, Multiline = true, ScrollBars = ScrollBars.Vertical };

            treeCandidates = new TreeView() { Left = 10, Top = 220, Width = 450, Height = 350, CheckBoxes = true };
            treeCandidates.AfterSelect += (s, e) => UpdatePreviewForSelectedNode();

            txtPreview = new TextBox() { Left = 470, Top = 220, Width = 490, Height = 250, Multiline = true, ScrollBars = ScrollBars.Vertical, ReadOnly = true };

            progressBar = new ProgressBar() { Left = 470, Top = 480, Width = 490, Height = 20 };

            btnExecute = new Button() { Text = "Execute Move/Archive", Left = 470, Top = 510, Width = 160 };
            btnExecute.Click += async (s, e) => await ExecuteMoveAsync();

            chkApplyChoiceToAll = new CheckBox() { Text = "Apply my move choice to all remaining prompts", Left = 650, Top = 514, Width = 320 };

            txtLog = new TextBox() { Left = 10, Top = 580, Width = 950, Height = 70, Multiline = true, ScrollBars = ScrollBars.Vertical, ReadOnly = true };

            Controls.AddRange(new Control[] { lblSource, txtSource, btnBrowseSource, lblDest, txtDestination, btnBrowseDest, btnScan, chkDryRun, chkRemoveEmpty, chkCompressFolders, lblInclude, txtIncludeExt, lblExclude, txtExcludeExt, lblMinSize, txtMinSizeMb, lblMaxSize, txtMaxSizeMb, lblExcludePaths, txtExcludePaths, treeCandidates, txtPreview, progressBar, btnExecute, chkApplyChoiceToAll, txtLog });
        }

        async Task ScanAsync()
        {
            txtLog.Clear();
            treeCandidates.Nodes.Clear();
            sourceRoot = txtSource.Text?.Trim() ?? string.Empty;
            if (string.IsNullOrEmpty(sourceRoot) || !Directory.Exists(sourceRoot))
            {
                MessageBox.Show("Please specify a valid source folder.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            thresholdDateUtc = DateTime.UtcNow.AddDays(-365); // 1 year

            // Parse filters from UI
            currentFilters = FilterSettings.ParseFromInputs(txtIncludeExt.Text, txtExcludeExt.Text, txtMinSizeMb.Text, txtMaxSizeMb.Text, txtExcludePaths.Text);

            AppendLog($"Scanning {sourceRoot} for items where both last write AND last access are older than {thresholdDateUtc:u} (UTC)");
            btnScan.Enabled = false;
            try
            {
                var rootNode = new TreeNode(Path.GetFileName(sourceRoot)) { Tag = sourceRoot };
                progressBar.Style = ProgressBarStyle.Marquee;

                await Task.Run(() =>
                {
                    bool rootQualifies = ArchiveScanner.BuildNodeRecursive(sourceRoot, rootNode, thresholdDateUtc, currentFilters);
                });

                treeCandidates.Nodes.Add(rootNode);
                rootNode.Expand();
                AppendLog("Scan complete.");
            }
            finally
            {
                progressBar.Style = ProgressBarStyle.Blocks;
                btnScan.Enabled = true;
            }
        }

        bool BuildNodeRecursive(string path, TreeNode node)
        {
            // Delegate to ArchiveScanner but keep same signature for compatibility
            try
            {
                return ArchiveScanner.BuildNodeRecursive(path, node, thresholdDateUtc, currentFilters);
            }
            catch (Exception ex)
            {
                AppendLog($"Error scanning {path}: {ex.Message}");
                return false;
            }
        }

        void UpdatePreviewForSelectedNode()
        {
            if (treeCandidates.SelectedNode == null) return;
            var path = treeCandidates.SelectedNode.Tag as string;
            if (path == null) return;
            try
            {
                if (File.Exists(path))
                {
                    var fi = new FileInfo(path);
                    txtPreview.Text = $"File: {fi.FullName}{Environment.NewLine}Size: {fi.Length} bytes{Environment.NewLine}Last Write (UTC): {fi.LastWriteTimeUtc:u}{Environment.NewLine}Last Access (UTC): {fi.LastAccessTimeUtc:u}";
                }
                else if (Directory.Exists(path))
                {
                    var dirInfo = new DirectoryInfo(path);
                    var files = Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories).ToArray();
                    long totalSize = files.Select(f => new FileInfo(f).Length).Sum();
                    txtPreview.Text = $"Folder: {dirInfo.FullName}{Environment.NewLine}Files (rec): {files.Length}{Environment.NewLine}Total size: {totalSize} bytes";
                }
                else
                {
                    txtPreview.Text = "Item not found.";
                }
            }
            catch (Exception ex)
            {
                txtPreview.Text = "Error reading item: " + ex.Message;
            }
        }

        async Task ExecuteMoveAsync()
        {
            if (string.IsNullOrWhiteSpace(sourceRoot) || !Directory.Exists(sourceRoot))
            {
                MessageBox.Show("Please scan a valid source first.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            var destRoot = txtDestination.Text?.Trim() ?? string.Empty;
            if (string.IsNullOrEmpty(destRoot) || !Directory.Exists(destRoot))
            {
                MessageBox.Show("Please specify a valid destination folder.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            chkApplyChoiceToAll.Enabled = false;
            applyChoiceToAll = false;
            lastChoiceMove = false;
            applyOverwriteToAll = false;
            lastOverwriteChoice = false;

            var nodesToProcess = new List<string>(); // paths
            CollectCheckedPaths(treeCandidates.Nodes, nodesToProcess);

            if (nodesToProcess.Count == 0)
            {
                MessageBox.Show("No checked candidates to move.", "Info", MessageBoxButtons.OK, MessageBoxIcon.Information);
                chkApplyChoiceToAll.Enabled = true;
                return;
            }

            progressBar.Minimum = 0;
            progressBar.Maximum = nodesToProcess.Count;
            progressBar.Value = 0;

            bool dryRun = chkDryRun.Checked;
            bool removeEmpty = chkRemoveEmpty.Checked;
            bool compress = chkCompressFolders.Checked;

            AppendLog($"Preparing to process {nodesToProcess.Count} items. Dry-run: {dryRun}");

            await Task.Run(() =>
            {
                int processed = 0;
                foreach (var path in nodesToProcess)
                {
                    processed++;
                    Invoke(() => progressBar.Value = processed);

                    try
                    {
                        string relative = Path.GetRelativePath(sourceRoot, path);
                        string destPath = Path.Combine(destRoot, relative);

                        if (File.Exists(path))
                        {
                            // Ensure destination folder exists
                            var destDir = Path.GetDirectoryName(destPath);
                            if (!Directory.Exists(destDir)) Directory.CreateDirectory(destDir);

                            bool doMove = PromptForAction(path);
                            if (!doMove)
                            {
                                AppendLog($"Skipped: {path}");
                                continue;
                            }

                            if (dryRun)
                            {
                                AppendLog($"[DRY] Move file: {path} -> {destPath}");
                            }
                            else
                            {
                                if (File.Exists(destPath))
                                {
                                    var overwrite = PromptOverwrite(destPath);
                                    if (!overwrite)
                                    {
                                        AppendLog($"Skipped existing destination: {destPath}");
                                        continue;
                                    }
                                }
                                File.Move(path, destPath);
                                AppendLog($"Moved: {path} -> {destPath}");
                            }
                        }
                        else if (Directory.Exists(path))
                        {
                            // Ensure destination parent exists
                            string destFull = Path.Combine(destRoot, relative);
                            var destParent = Path.GetDirectoryName(destFull);
                            if (!Directory.Exists(destParent)) Directory.CreateDirectory(destParent);

                            bool doMove = PromptForAction(path);
                            if (!doMove)
                            {
                                AppendLog($"Skipped: {path}");
                                continue;
                            }

                            if (compress)
                            {
                                // Create zip at destination: destFull + ".zip"
                                string destZip = destFull.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + ".zip";
                                if (dryRun)
                                {
                                    AppendLog($"[DRY] Compress folder: {path} -> {destZip}");
                                }
                                else
                                {
                                    if (File.Exists(destZip))
                                    {
                                        var overwrite = PromptOverwrite(destZip);
                                        if (!overwrite)
                                        {
                                            AppendLog($"Skipped existing destination archive: {destZip}");
                                            continue;
                                        }
                                        File.Delete(destZip);
                                    }
                                    ZipFile.CreateFromDirectory(path, destZip, CompressionLevel.Optimal, includeBaseDirectory: true);
                                    // After successful zip, remove original folder
                                    Directory.Delete(path, recursive: true);
                                    AppendLog($"Compressed folder: {path} -> {destZip}");
                                }
                            }
                            else
                            {
                                if (dryRun)
                                {
                                    AppendLog($"[DRY] Move folder: {path} -> {destFull}");
                                }
                                else
                                {
                                    if (Directory.Exists(destFull))
                                    {
                                        var overwrite = PromptOverwrite(destFull);
                                        if (!overwrite)
                                        {
                                            AppendLog($"Skipped existing destination folder: {destFull}");
                                            continue;
                                        }
                                        Directory.Delete(destFull, recursive: true);
                                    }
                                    Directory.Move(path, destFull);
                                    AppendLog($"Moved folder: {path} -> {destFull}");
                                }
                            }
                        }

                        if (removeEmpty && !dryRun)
                        {
                            TryRemoveEmptyParentFolders(Path.GetDirectoryName(path));
                        }
                    }
                    catch (Exception ex)
                    {
                        AppendLog($"Error processing {path}: {ex.Message}");
                    }
                }
            });

            AppendLog("Operation complete.");
            chkApplyChoiceToAll.Enabled = true;
        }

        void CollectCheckedPaths(TreeNodeCollection nodes, List<string> outPaths)
        {
            foreach (TreeNode node in nodes)
            {
                var path = node.Tag as string;
                if (node.Checked && path != null)
                {
                    outPaths.Add(path);
                }
                if (node.Nodes.Count > 0)
                {
                    CollectCheckedPaths(node.Nodes, outPaths);
                }
            }
        }

        bool PromptForAction(string path)
        {
            if (applyChoiceToAll)
            {
                return lastChoiceMove;
            }

            DialogResult res = DialogResult.No;
            // Show on UI thread
            Invoke(new Action(() =>
            {
                res = MessageBox.Show($"Move '{path}'?\n(Yes = move, No = skip)", "Confirm move", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (chkApplyChoiceToAll.Checked)
                {
                    applyChoiceToAll = true;
                    lastChoiceMove = (res == DialogResult.Yes);
                }
            }));

            return res == DialogResult.Yes;
        }

        bool PromptOverwrite(string destPath)
        {
            // Use ConflictPromptForm to get choices: Yes/YesToAll/No/NoToAll
            if (applyOverwriteToAll)
            {
                return lastOverwriteChoice;
            }

            ConflictDecision decision = ConflictDecision.No;
            // Show dialog on UI thread
            Invoke(new Action(() =>
            {
                decision = ConflictPromptForm.ShowDialogChoice(this, $"Destination exists: '{destPath}'\nChoose action:");
            }));

            switch (decision)
            {
                case ConflictDecision.Yes:
                    return true;
                case ConflictDecision.YesToAll:
                    applyOverwriteToAll = true;
                    lastOverwriteChoice = true;
                    return true;
                case ConflictDecision.No:
                    return false;
                case ConflictDecision.NoToAll:
                    applyOverwriteToAll = true;
                    lastOverwriteChoice = false;
                    return false;
                default:
                    return false;
            }
        }

        void TryRemoveEmptyParentFolders(string? startDir)
        {
            try
            {
                var dir = startDir;
                while (!string.IsNullOrEmpty(dir) && Directory.Exists(dir) && dir.StartsWith(sourceRoot, StringComparison.OrdinalIgnoreCase))
                {
                    if (!Directory.EnumerateFileSystemEntries(dir).Any())
                    {
                        Directory.Delete(dir);
                        AppendLog($"Removed empty folder: {dir}");
                        dir = Path.GetDirectoryName(dir);
                    }
                    else break;
                }
            }
            catch (Exception ex)
            {
                AppendLog($"Error removing empty folders: {ex.Message}");
            }
        }

        void AppendLog(string message)
        {
            Invoke(() =>
            {
                txtLog.AppendText($"[{DateTime.Now:u}] {message}{Environment.NewLine}");
            });
        }
    }
}
