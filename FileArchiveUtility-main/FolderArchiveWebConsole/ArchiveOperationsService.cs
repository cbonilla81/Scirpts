namespace FolderArchiveWebConsole;

public class ScanRequest
{
    public string? SourcePath { get; set; }
    public string? DestinationPath { get; set; }
    public int AgeDays { get; set; } = 365;
    public string? IncludeExtensions { get; set; }
    public string? ExcludeExtensions { get; set; }
    public double? MinSizeMb { get; set; }
    public double? MaxSizeMb { get; set; }
    public string? ExcludePaths { get; set; }
}

public sealed class ArchiveRequest : ScanRequest
{
    public string[] SelectedPaths { get; set; } = [];
    public string[] SelectedFolders { get; set; } = [];
    public bool DryRun { get; set; } = true;
    public bool RemoveEmptyFolders { get; set; } = true;
    public bool ReplaceNewerDestination { get; set; }
    public bool ConfirmLiveRun { get; set; }
}

public sealed record Candidate(string Path, string Name, long SizeBytes, DateTime LastWriteTimeUtc);

public sealed record ScanResult(
    string SourcePath,
    string DestinationPath,
    int AgeDays,
    int CandidateCount,
    bool Truncated,
    Candidate[] Candidates,
    FolderCandidate[] Folders);

public sealed record FolderCandidate(string Path, string Name, int FileCount, int SubfolderCount, long SizeBytes);

public sealed class ArchiveOperationsService
{
    private const int CandidateLimit = 5000;

    public ScanResult Scan(ScanRequest request)
    {
        var options = Validate(request);
        var thresholdUtc = DateTime.UtcNow.AddDays(-options.AgeDays);
        var candidates = new List<Candidate>();
        var truncated = false;

        var enumerationOptions = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = false,
            ReturnSpecialDirectories = false,
            AttributesToSkip = FileAttributes.ReparsePoint
        };

        var folderStats = new Dictionary<string, (int FileCount, int SubfolderCount, long SizeBytes)>(StringComparer.OrdinalIgnoreCase);
        var directories = Directory.EnumerateDirectories(options.SourcePath, "*", enumerationOptions)
            .Select(Path.GetFullPath)
            .ToArray();
        foreach (var directory in directories)
            folderStats.TryAdd(directory, (0, 0, 0));

        foreach (var directory in directories)
        {
            var parent = Path.GetDirectoryName(directory);
            while (!string.IsNullOrEmpty(parent) && folderStats.TryGetValue(parent, out var stats))
            {
                folderStats[parent] = (stats.FileCount, checked(stats.SubfolderCount + 1), stats.SizeBytes);
                parent = Path.GetDirectoryName(parent);
            }
        }

        foreach (var path in Directory.EnumerateFiles(options.SourcePath, "*", enumerationOptions))
        {
            var file = new FileInfo(path);
            if (!file.Exists)
                continue;

            var parent = Path.GetDirectoryName(file.FullName);
            while (!string.IsNullOrEmpty(parent) && folderStats.TryGetValue(parent, out var stats))
            {
                folderStats[parent] = (checked(stats.FileCount + 1), stats.SubfolderCount, checked(stats.SizeBytes + file.Length));
                parent = Path.GetDirectoryName(parent);
            }

            if (!Matches(file, thresholdUtc, options))
                continue;

            if (candidates.Count == CandidateLimit)
            {
                truncated = true;
                continue;
            }

            candidates.Add(new Candidate(file.FullName, file.Name, file.Length, file.LastWriteTimeUtc));
        }

        return new ScanResult(
            options.SourcePath,
            options.DestinationPath,
            options.AgeDays,
            candidates.Count,
            truncated,
            candidates.ToArray(),
            folderStats
                .Select(pair => new FolderCandidate(
                    pair.Key,
                    Path.GetFileName(pair.Key),
                    pair.Value.FileCount,
                    pair.Value.SubfolderCount,
                    pair.Value.SizeBytes))
                .OrderBy(folder => Path.GetRelativePath(options.SourcePath, folder.Path), StringComparer.OrdinalIgnoreCase)
                .ToArray());
    }

    public ValidatedOptions Validate(ScanRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);

        var source = NormalizeExistingDirectory(request.SourcePath, "source");
        var destination = NormalizeDirectory(request.DestinationPath, "destination");
        if (PathsEqual(source, destination))
            throw new ArgumentException("The source and destination folders must be different.");
        if (IsWithinDirectory(destination, source))
            throw new ArgumentException("The destination cannot be inside the source folder.");
        if (request.AgeDays is < 1 or > 36500)
            throw new ArgumentException("Age must be between 1 and 36,500 days.");

        if (request.MinSizeMb is < 0 || request.MaxSizeMb is < 0)
            throw new ArgumentException("Minimum and maximum sizes cannot be negative.");
        if ((request.MinSizeMb.HasValue &&
             (!double.IsFinite(request.MinSizeMb.Value) || request.MinSizeMb.Value > long.MaxValue / (1024d * 1024d))) ||
            (request.MaxSizeMb.HasValue &&
             (!double.IsFinite(request.MaxSizeMb.Value) || request.MaxSizeMb.Value > long.MaxValue / (1024d * 1024d))))
            throw new ArgumentException("Minimum and maximum sizes are outside the supported range.");
        if (request.MinSizeMb.HasValue && request.MaxSizeMb.HasValue &&
            request.MinSizeMb.Value > request.MaxSizeMb.Value)
            throw new ArgumentException("Minimum size cannot be greater than maximum size.");

        long? minSizeBytes = request.MinSizeMb.HasValue
            ? checked((long)(request.MinSizeMb.Value * 1024 * 1024))
            : null;
        long? maxSizeBytes = request.MaxSizeMb.HasValue
            ? checked((long)(request.MaxSizeMb.Value * 1024 * 1024))
            : null;

        return new ValidatedOptions(
            source,
            destination,
            request.AgeDays,
            ParseExtensions(request.IncludeExtensions),
            ParseExtensions(request.ExcludeExtensions),
            minSizeBytes,
            maxSizeBytes,
            (request.ExcludePaths ?? string.Empty)
                .Split(['\r', '\n', ';', ','], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
    }

    public void Execute(ArchiveRequest request, ArchiveJob job)
    {
        var options = Validate(request);
        var thresholdUtc = DateTime.UtcNow.AddDays(-options.AgeDays);
        var selectedPaths = request.SelectedPaths ?? [];
        var selectedFolders = request.SelectedFolders ?? [];
        var uniquePaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var selectedFilePaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var foldersToArchive = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var folderDirectories = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var folderFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        if (selectedPaths.Length == 0 && selectedFolders.Length == 0)
            throw new ArgumentException("Select at least one file or folder before starting the archive job.");
        if (!request.DryRun && !request.ConfirmLiveRun)
            throw new ArgumentException("Confirm the live archive operation before starting.");

        foreach (var selectedFolder in selectedFolders)
        {
            var fullPath = NormalizeDirectory(selectedFolder, "selected folder");
            if (!IsWithinDirectory(fullPath, options.SourcePath))
                throw new ArgumentException("A selected folder must be a subfolder of the configured source folder.");
            if (!Directory.Exists(fullPath))
                throw new ArgumentException($"The selected folder does not exist: {fullPath}");
            if ((File.GetAttributes(fullPath) & FileAttributes.ReparsePoint) != 0)
                throw new ArgumentException("A selected folder cannot be a reparse point.");
            if (!foldersToArchive.Add(fullPath))
                throw new ArgumentException("The selection contains a duplicate folder.");
        }

        foreach (var selectedFolder in foldersToArchive)
        {
            if (foldersToArchive.Any(otherFolder =>
                    !PathsEqual(otherFolder, selectedFolder) &&
                    IsWithinDirectory(selectedFolder, otherFolder)))
                throw new ArgumentException("Selected folders cannot contain one another.");

            var enumerationOptions = new EnumerationOptions
            {
                RecurseSubdirectories = true,
                IgnoreInaccessible = false,
                ReturnSpecialDirectories = false,
                AttributesToSkip = FileAttributes.ReparsePoint
            };

            folderDirectories.Add(selectedFolder);
            foreach (var directory in Directory.EnumerateDirectories(selectedFolder, "*", enumerationOptions))
                folderDirectories.Add(directory);
            foreach (var path in Directory.EnumerateFiles(selectedFolder, "*", enumerationOptions))
                folderFiles.Add(Path.GetFullPath(path));
        }

        foreach (var selectedPath in selectedPaths)
        {
            var fullPath = Path.GetFullPath(selectedPath);
            if (!IsWithinDirectory(fullPath, options.SourcePath))
                throw new ArgumentException("A selected file is outside the configured source folder.");
            if (!selectedFilePaths.Add(fullPath))
                throw new ArgumentException("The selection contains a duplicate file path.");
            uniquePaths.Add(fullPath);
        }

        uniquePaths.UnionWith(folderFiles);
        job.SetTotal(uniquePaths.Count);

        foreach (var directory in folderDirectories)
        {
            var relativePath = Path.GetRelativePath(options.SourcePath, directory);
            var destinationPath = Path.GetFullPath(Path.Combine(options.DestinationPath, relativePath));
            if (!IsWithinDirectory(destinationPath, options.DestinationPath))
                throw new IOException("The calculated destination folder is outside the configured destination folder.");

            if (request.DryRun)
                job.Log("Dry run", $"Would preserve folder: {directory} -> {destinationPath}");
            else
                Directory.CreateDirectory(destinationPath);
        }

        foreach (var selectedFolder in foldersToArchive)
        {
            var relativePath = Path.GetRelativePath(options.SourcePath, selectedFolder);
            var destinationPath = Path.GetFullPath(Path.Combine(options.DestinationPath, relativePath));
            job.Log(
                request.DryRun ? "Dry run" : "Archiving",
                $"{(request.DryRun ? "Would archive" : "Archiving")} entire folder: {selectedFolder} -> {destinationPath}");
        }

        foreach (var sourcePath in uniquePaths)
        {
            try
            {
                var file = new FileInfo(sourcePath);
                if (!file.Exists || (!folderFiles.Contains(sourcePath) && !Matches(file, thresholdUtc, options)))
                {
                    job.Record("Skipped", $"No longer eligible: {sourcePath}");
                    continue;
                }

                var relativePath = Path.GetRelativePath(options.SourcePath, sourcePath);
                var destinationPath = Path.GetFullPath(Path.Combine(options.DestinationPath, relativePath));
                if (!IsWithinDirectory(destinationPath, options.DestinationPath))
                    throw new IOException("The calculated destination path is outside the configured destination folder.");

                var destinationExists = File.Exists(destinationPath);
                var replaceDestination = destinationExists &&
                    request.ReplaceNewerDestination &&
                    file.LastWriteTimeUtc > File.GetLastWriteTimeUtc(destinationPath);

                if (destinationExists && !replaceDestination)
                {
                    job.Record("Skipped", $"Destination already exists: {destinationPath}");
                    continue;
                }

                if (request.DryRun)
                {
                    job.Record("Dry run", $"{(replaceDestination ? "Would replace" : "Would move")}: {sourcePath} -> {destinationPath}");
                    continue;
                }

                var destinationDirectory = Path.GetDirectoryName(destinationPath)
                    ?? throw new IOException("Could not determine the destination folder.");
                Directory.CreateDirectory(destinationDirectory);
                File.Move(sourcePath, destinationPath, overwrite: replaceDestination);
                job.Record("Archived", $"Moved: {sourcePath} -> {destinationPath}");

                if (request.RemoveEmptyFolders)
                    RemoveEmptyParents(Path.GetDirectoryName(sourcePath), options.SourcePath, job);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
            {
                job.Record("Failed", $"{sourcePath}: {exception.Message}");
            }
        }

        if (request.RemoveEmptyFolders)
        {
            foreach (var directory in folderDirectories.OrderByDescending(path => path.Length))
                RemoveEmptyParents(directory, options.SourcePath, job);
        }
    }

    private static bool Matches(FileInfo file, DateTime thresholdUtc, ValidatedOptions options)
    {
        if (file.LastAccessTimeUtc >= thresholdUtc || file.LastWriteTimeUtc >= thresholdUtc)
            return false;
        if (options.IncludeExtensions.Count > 0 && !options.IncludeExtensions.Contains(file.Extension))
            return false;
        if (options.ExcludeExtensions.Contains(file.Extension))
            return false;
        if (options.MinSizeBytes.HasValue && file.Length < options.MinSizeBytes.Value)
            return false;
        if (options.MaxSizeBytes.HasValue && file.Length > options.MaxSizeBytes.Value)
            return false;

        return !options.ExcludePaths.Any(excludedPath =>
            file.FullName.Contains(excludedPath, StringComparison.OrdinalIgnoreCase));
    }

    private static HashSet<string> ParseExtensions(string? value) =>
        (value ?? string.Empty)
            .Split([',', ';'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(extension => extension.StartsWith('.') ? extension : $".{extension}")
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

    private static string NormalizeExistingDirectory(string? path, string kind)
    {
        var normalized = NormalizeDirectory(path, kind);
        if (!Directory.Exists(normalized))
            throw new ArgumentException($"The {kind} folder does not exist or cannot be accessed.");
        return normalized;
    }

    private static string NormalizeDirectory(string? path, string kind)
    {
        if (string.IsNullOrWhiteSpace(path))
            throw new ArgumentException($"Enter a {kind} folder path.");

        try
        {
            return Path.TrimEndingDirectorySeparator(Path.GetFullPath(path.Trim()));
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or NotSupportedException)
        {
            throw new ArgumentException($"The {kind} folder path is invalid: {exception.Message}");
        }
    }

    private static bool PathsEqual(string first, string second) =>
        string.Equals(first, second, StringComparison.OrdinalIgnoreCase);

    private static bool IsWithinDirectory(string path, string directory)
    {
        var directoryPrefix = Path.EndsInDirectorySeparator(directory)
            ? directory
            : directory + Path.DirectorySeparatorChar;
        return path.StartsWith(directoryPrefix, StringComparison.OrdinalIgnoreCase);
    }

    private static void RemoveEmptyParents(string? current, string sourceRoot, ArchiveJob job)
    {
        var rootPrefix = Path.EndsInDirectorySeparator(sourceRoot)
            ? sourceRoot
            : sourceRoot + Path.DirectorySeparatorChar;

        while (!string.IsNullOrEmpty(current) &&
               current.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase) &&
               Directory.Exists(current))
        {
            try
            {
                if (Directory.EnumerateFileSystemEntries(current).Any())
                    break;

                Directory.Delete(current);
                job.Log("Removed", $"Removed empty folder: {current}");
                current = Path.GetDirectoryName(current);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                job.Log("Failed", $"Could not remove empty folder {current}: {exception.Message}");
                break;
            }
        }
    }
}

public sealed record ValidatedOptions(
    string SourcePath,
    string DestinationPath,
    int AgeDays,
    HashSet<string> IncludeExtensions,
    HashSet<string> ExcludeExtensions,
    long? MinSizeBytes,
    long? MaxSizeBytes,
    string[] ExcludePaths);

public sealed record JobSnapshot(
    Guid Id,
    string Status,
    int Total,
    int Processed,
    int Archived,
    int Skipped,
    int Failed,
    string[] Logs);

public sealed class ArchiveJob
{
    private readonly object _lock = new();
    private readonly List<string> _logs = [];
    private int _total;
    private int _processed;
    private int _archived;
    private int _skipped;
    private int _failed;
    private string _status = "Running";

    public Guid Id { get; } = Guid.NewGuid();

    public void SetTotal(int total)
    {
        lock (_lock)
            _total = total;
    }

    public void Record(string outcome, string message)
    {
        lock (_lock)
        {
            _processed++;
            if (outcome == "Archived")
                _archived++;
            else if (outcome == "Skipped")
                _skipped++;
            else if (outcome == "Failed")
                _failed++;

            _logs.Add($"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss zzz}] {outcome}: {message}");
        }
    }

    public void Log(string outcome, string message)
    {
        lock (_lock)
        {
            if (outcome == "Failed")
                _failed++;
            _logs.Add($"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss zzz}] {outcome}: {message}");
        }
    }

    public void Complete(string status)
    {
        lock (_lock)
            _status = status;
    }

    public JobSnapshot Snapshot()
    {
        lock (_lock)
            return new JobSnapshot(Id, _status, _total, _processed, _archived, _skipped, _failed, _logs.ToArray());
    }
}

public sealed class JobCoordinator(ArchiveOperationsService archive)
{
    private readonly object _lock = new();
    private ArchiveJob? _currentJob;

    public Guid Start(ArchiveRequest request)
    {
        archive.Validate(request);
        if (!request.DryRun && !request.ConfirmLiveRun)
            throw new ArgumentException("Confirm the live archive operation before starting.");
        if (request.SelectedPaths is not { Length: > 0 } &&
            request.SelectedFolders is not { Length: > 0 })
            throw new ArgumentException("Select at least one file or folder before starting the archive job.");

        lock (_lock)
        {
            if (_currentJob?.Snapshot().Status == "Running")
                throw new InvalidOperationException("An archive job is already running.");

            var job = new ArchiveJob();
            _currentJob = job;
            _ = Task.Run(() =>
            {
                try
                {
                    archive.Execute(request, job);
                    job.Complete("Completed");
                }
                catch (Exception exception)
                {
                    job.Record("Failed", exception.Message);
                    job.Complete("Failed");
                }
            });
            return job.Id;
        }
    }

    public JobSnapshot? GetCurrent()
    {
        lock (_lock)
            return _currentJob?.Snapshot();
    }
}
