using System;
using System.Collections.Generic;
using System.IO;
using Xunit;
using FolderArchiveTool;

public class ArchiveScannerTests
{
    [Fact]
    public void IsFileCandidate_BothTimestampsOld_ReturnsTrue()
    {
        var tmp = Path.Combine(Path.GetTempPath(), "fat_test_dir");
        if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
        Directory.CreateDirectory(tmp);
        var f = Path.Combine(tmp, "old.txt");
        File.WriteAllText(f, "old");
        var oldDate = DateTime.UtcNow.AddYears(-2);
        File.SetLastAccessTimeUtc(f, oldDate);
        File.SetLastWriteTimeUtc(f, oldDate);

        var filters = new FilterSettings();
        var threshold = DateTime.UtcNow.AddDays(-365);
        try
        {
            Assert.True(ArchiveScanner.IsFileCandidate(f, threshold, filters));
        }
        finally
        {
            File.Delete(f);
            Directory.Delete(tmp);
        }
    }

    [Fact]
    public void IsFileCandidate_ExcludeExtension_ReturnsFalse()
    {
        var tmp = Path.Combine(Path.GetTempPath(), "fat_test_dir2");
        if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
        Directory.CreateDirectory(tmp);
        var f = Path.Combine(tmp, "old.log");
        File.WriteAllText(f, "old");
        var oldDate = DateTime.UtcNow.AddYears(-2);
        File.SetLastAccessTimeUtc(f, oldDate);
        File.SetLastWriteTimeUtc(f, oldDate);

        var filters = new FilterSettings();
        filters.ExcludeExtensions.Add(".log");
        var threshold = DateTime.UtcNow.AddDays(-365);
        try
        {
            Assert.False(ArchiveScanner.IsFileCandidate(f, threshold, filters));
        }
        finally
        {
            File.Delete(f);
            Directory.Delete(tmp);
        }
    }

    [Fact]
    public void Scan_ReportsFileAndFolderCountsAndProgress()
    {
        var tmp = Path.Combine(Path.GetTempPath(), $"fat_scan_{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path.Combine(tmp, "child"));
        File.WriteAllText(Path.Combine(tmp, "child", "sample.txt"), "sample");
        var progress = new InlineProgress<ArchiveScanProgress>();

        try
        {
            var result = ArchiveScanner.Scan(tmp, DateTime.UtcNow.AddYears(-1), new FilterSettings(), progress);

            Assert.Equal(1L, result.FilesScanned);
            Assert.Equal(2L, result.FoldersScanned);
            Assert.Equal(tmp, progress.LastReported!.CurrentPath);
            Assert.Equal(1L, progress.LastReported.FilesScanned);
            Assert.Equal(2L, progress.LastReported.FoldersScanned);
        }
        finally
        {
            Directory.Delete(tmp, recursive: true);
        }
    }

    [Fact]
    public void Scan_ReportsErrorsForPathsItCannotRead()
    {
        var missingPath = Path.Combine(Path.GetTempPath(), $"fat_missing_{Guid.NewGuid():N}");
        var errors = new List<string>();

        var result = ArchiveScanner.Scan(
            missingPath,
            DateTime.UtcNow,
            new FilterSettings(),
            errorCallback: (path, exception) => errors.Add($"{path}: {exception.Message}"));

        Assert.Equal(1, result.ErrorCount);
        Assert.Single(errors);
        Assert.Contains(missingPath, errors[0]);
    }

    private sealed class InlineProgress<T> : IProgress<T>
    {
        public T? LastReported { get; private set; }

        public void Report(T value) => LastReported = value;
    }
}
