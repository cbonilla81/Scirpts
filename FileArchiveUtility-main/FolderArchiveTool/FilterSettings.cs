using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace FolderArchiveTool
{
    public class FilterSettings
    {
        public HashSet<string> IncludeExtensions { get; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> ExcludeExtensions { get; } = new(StringComparer.OrdinalIgnoreCase);
        public long? MinSizeBytes { get; set; }
        public long? MaxSizeBytes { get; set; }
        public List<string> ExcludePaths { get; } = new();

        public static FilterSettings ParseFromInputs(string includeExtCsv, string excludeExtCsv, string minSizeMbText, string maxSizeMbText, string excludePathsCsv)
        {
            var fs = new FilterSettings();
            if (!string.IsNullOrWhiteSpace(includeExtCsv))
            {
                foreach (var s in includeExtCsv.Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    var t = s.Trim(); if (!t.StartsWith(".")) t = "." + t; fs.IncludeExtensions.Add(t);
                }
            }
            if (!string.IsNullOrWhiteSpace(excludeExtCsv))
            {
                foreach (var s in excludeExtCsv.Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    var t = s.Trim(); if (!t.StartsWith(".")) t = "." + t; fs.ExcludeExtensions.Add(t);
                }
            }
            if (double.TryParse(minSizeMbText, out var minMb)) fs.MinSizeBytes = (long)(minMb * 1024 * 1024);
            if (double.TryParse(maxSizeMbText, out var maxMb)) fs.MaxSizeBytes = (long)(maxMb * 1024 * 1024);
            if (!string.IsNullOrWhiteSpace(excludePathsCsv))
            {
                foreach (var s in excludePathsCsv.Split(new[] { '\n', ';', ',' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    var t = s.Trim(); if (!string.IsNullOrEmpty(t)) fs.ExcludePaths.Add(t);
                }
            }
            return fs;
        }

        public bool Matches(FileInfo fi)
        {
            if (IncludeExtensions.Count > 0 && !IncludeExtensions.Contains(fi.Extension)) return false;
            if (ExcludeExtensions.Count > 0 && ExcludeExtensions.Contains(fi.Extension)) return false;
            if (MinSizeBytes.HasValue && fi.Length < MinSizeBytes.Value) return false;
            if (MaxSizeBytes.HasValue && fi.Length > MaxSizeBytes.Value) return false;
            if (ExcludePaths.Count > 0)
            {
                foreach (var p in ExcludePaths)
                {
                    if (fi.FullName.IndexOf(p, StringComparison.OrdinalIgnoreCase) >= 0) return false;
                }
            }
            return true;
        }
    }
}
