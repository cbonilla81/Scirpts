using System;
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
}
