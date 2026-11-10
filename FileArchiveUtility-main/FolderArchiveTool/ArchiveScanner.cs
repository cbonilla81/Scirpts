using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace FolderArchiveTool
{
    public sealed class ArchiveScanNode
    {
        public string Name { get; init; } = string.Empty;
        public string Path { get; init; } = string.Empty;
        public bool IsDirectory { get; init; }
        public bool Qualifies { get; set; }
        public List<ArchiveScanNode> Children { get; } = new();
    }

    public sealed class ArchiveScanProgress
    {
        public long FilesScanned { get; init; }
        public long FoldersScanned { get; init; }
        public string CurrentPath { get; init; } = string.Empty;
    }

    public sealed class ArchiveScanResult
    {
        public ArchiveScanNode Root { get; init; } = new();
        public long FilesScanned { get; init; }
        public long FoldersScanned { get; init; }
        public int ErrorCount { get; init; }
        public int SkippedReparsePointCount { get; init; }
    }

    public static class ArchiveScanner
    {
        static readonly TimeSpan ProgressInterval = TimeSpan.FromMilliseconds(250);

        public static bool IsFileCandidate(string filePath, DateTime thresholdUtc, FilterSettings filters)
        {
            try
            {
                var fi = new FileInfo(filePath);
                if (!fi.Exists) return false;
                var fa = fi.LastAccessTimeUtc;
                var fw = fi.LastWriteTimeUtc;
                if (!(fa < thresholdUtc && fw < thresholdUtc)) return false;
                return filters == null || filters.Matches(fi);
            }
            catch
            {
                return false;
            }
        }

        public static bool IsDirectoryCandidate(string dirPath, DateTime thresholdUtc, FilterSettings filters)
        {
            try
            {
                var di = new DirectoryInfo(dirPath);
                if (!di.Exists) return false;
                var da = di.LastAccessTimeUtc;
                var dw = di.LastWriteTimeUtc;
                if (!(da < thresholdUtc && dw < thresholdUtc)) return false;

                foreach (var file in Directory.EnumerateFiles(dirPath, "*", SearchOption.AllDirectories))
                {
                    if (!IsFileCandidate(file, thresholdUtc, filters)) return false;
                }
                return true;
            }
            catch
            {
                return false;
            }
        }

        public static ArchiveScanResult Scan(
            string rootPath,
            DateTime thresholdUtc,
            FilterSettings filters,
            IProgress<ArchiveScanProgress>? progress = null,
            Action<string, Exception>? errorCallback = null,
            Action<string>? skippedReparsePointCallback = null)
        {
            long filesScanned = 0;
            long foldersScanned = 0;
            var errorCount = 0;
            var skippedReparsePointCount = 0;
            var lastProgressTime = Stopwatch.StartNew();

            void ReportProgress(string path, bool force = false)
            {
                if (force || lastProgressTime.Elapsed >= ProgressInterval)
                {
                    progress?.Report(new ArchiveScanProgress
                    {
                        FilesScanned = filesScanned,
                        FoldersScanned = foldersScanned,
                        CurrentPath = path
                    });
                    lastProgressTime.Restart();
                }
            }

            void ReportError(string path, Exception exception)
            {
                errorCount++;
                errorCallback?.Invoke(path, exception);
            }

            ArchiveScanNode ScanPath(string path)
            {
                FileAttributes attributes;
                try
                {
                    attributes = File.GetAttributes(path);
                }
                catch (Exception ex)
                {
                    ReportError(path, ex);
                    ReportProgress(path);
                    return new ArchiveScanNode { Name = Path.GetFileName(path), Path = path };
                }

                bool isDirectory = (attributes & FileAttributes.Directory) != 0;
                var node = new ArchiveScanNode
                {
                    Name = Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)),
                    Path = path,
                    IsDirectory = isDirectory
                };

                if (!isDirectory)
                {
                    filesScanned++;
                    try
                    {
                        var file = new FileInfo(path);
                        node.Qualifies =
                            file.LastAccessTimeUtc < thresholdUtc &&
                            file.LastWriteTimeUtc < thresholdUtc &&
                            (filters == null || filters.Matches(file));
                    }
                    catch (Exception ex)
                    {
                        ReportError(path, ex);
                    }

                    ReportProgress(path);
                    return node;
                }

                foldersScanned++;
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                {
                    skippedReparsePointCount++;
                    skippedReparsePointCallback?.Invoke(path);
                    ReportProgress(path);
                    return node;
                }

                bool timestampsQualify = false;
                try
                {
                    var directory = new DirectoryInfo(path);
                    timestampsQualify =
                        directory.LastAccessTimeUtc < thresholdUtc &&
                        directory.LastWriteTimeUtc < thresholdUtc;
                }
                catch (Exception ex)
                {
                    ReportError(path, ex);
                }

                bool allChildrenQualify = true;
                bool enumerationCompleted = true;
                try
                {
                    foreach (var childPath in Directory.EnumerateFileSystemEntries(path))
                    {
                        var child = ScanPath(childPath);
                        node.Children.Add(child);
                        if (!child.Qualifies) allChildrenQualify = false;
                    }
                }
                catch (Exception ex)
                {
                    ReportError(path, ex);
                    enumerationCompleted = false;
                }

                node.Qualifies = timestampsQualify && allChildrenQualify && enumerationCompleted;
                ReportProgress(path);
                return node;
            }

            ReportProgress(rootPath, force: true);
            var root = ScanPath(rootPath);
            ReportProgress(rootPath, force: true);
            return new ArchiveScanResult
            {
                Root = root,
                FilesScanned = filesScanned,
                FoldersScanned = foldersScanned,
                ErrorCount = errorCount,
                SkippedReparsePointCount = skippedReparsePointCount
            };
        }

        public static bool BuildNodeRecursive(string path, TreeNode node, DateTime thresholdUtc, FilterSettings filters)
        {
            var result = Scan(path, thresholdUtc, filters);
            CopyToTreeNode(result.Root, node);
            return result.Root.Qualifies;
        }

        public static void CopyToTreeNode(ArchiveScanNode source, TreeNode target)
        {
            target.Text = source.Name;
            target.Tag = source.Path;
            target.Checked = source.Qualifies;
            target.Nodes.Clear();
            foreach (var child in source.Children)
            {
                var childNode = new TreeNode();
                CopyToTreeNode(child, childNode);
                target.Nodes.Add(childNode);
            }
        }
    }
}
