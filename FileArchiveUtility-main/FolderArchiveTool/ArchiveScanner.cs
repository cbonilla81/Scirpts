using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace FolderArchiveTool
{
    public static class ArchiveScanner
    {
        // Returns true if the file meets the age & filter criteria
        public static bool IsFileCandidate(string filePath, DateTime thresholdUtc, FilterSettings filters)
        {
            try
            {
                var fi = new FileInfo(filePath);
                if (!fi.Exists) return false;
                var fa = fi.LastAccessTimeUtc;
                var fw = fi.LastWriteTimeUtc;
                if (!(fa < thresholdUtc && fw < thresholdUtc)) return false;
                if (filters != null && !filters.Matches(fi)) return false;
                return true;
            }
            catch
            {
                return false;
            }
        }

        // For folders: require folder timestamps AND all children to meet criteria
        public static bool IsDirectoryCandidate(string dirPath, DateTime thresholdUtc, FilterSettings filters)
        {
            try
            {
                var di = new DirectoryInfo(dirPath);
                if (!di.Exists) return false;
                var da = di.LastAccessTimeUtc;
                var dw = di.LastWriteTimeUtc;
                if (!(da < thresholdUtc && dw < thresholdUtc)) return false;

                // Walk children; each file must match file candidate check; directories checked recursively
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

        // Build tree nodes using scanner rules
        public static bool BuildNodeRecursive(string path, TreeNode node, DateTime thresholdUtc, FilterSettings filters)
        {
            try
            {
                if (File.Exists(path))
                {
                    bool qualifies = IsFileCandidate(path, thresholdUtc, filters);
                    node.Text = Path.GetFileName(path);
                    node.Tag = path;
                    node.Checked = qualifies;
                    return qualifies;
                }
                else if (Directory.Exists(path))
                {
                    var children = Directory.EnumerateFileSystemEntries(path);
                    bool allChildrenQualify = true;
                    List<TreeNode> childNodes = new List<TreeNode>();
                    foreach (var c in children)
                    {
                        var cn = new TreeNode(Path.GetFileName(c)) { Tag = c };
                        bool childQual = BuildNodeRecursive(c, cn, thresholdUtc, filters);
                        childNodes.Add(cn);
                        if (!childQual) allChildrenQualify = false;
                    }
                    var di = new DirectoryInfo(path);
                    var da = di.LastAccessTimeUtc;
                    var dw = di.LastWriteTimeUtc;
                    bool folderTimestampQualifies = da < thresholdUtc && dw < thresholdUtc;
                    bool folderQualifies = folderTimestampQualifies && allChildrenQualify;

                    node.Nodes.Clear();
                    node.Nodes.AddRange(childNodes.ToArray());
                    node.Tag = path;
                    node.Checked = folderQualifies;
                    node.Text = Path.GetFileName(path);

                    return folderQualifies;
                }
            }
            catch (UnauthorizedAccessException)
            {
                // skip
            }
            catch (Exception)
            {
                // skip
            }
            return false;
        }
    }
}
