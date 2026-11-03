using FolderArchiveWebConsole;

public sealed class HostedJobCoordinator(ArchiveOperationsService archive)
{
    private readonly object _lock = new();
    private readonly Dictionary<string, ArchiveJob> _jobsByUser = new(StringComparer.Ordinal);
    private string? _runningUserId;

    public Guid Start(string userId, ArchiveRequest request)
    {
        archive.Validate(request);
        if (!request.DryRun && !request.ConfirmLiveRun)
            throw new ArgumentException("Confirm the live archive operation before starting.");
        if (request.SelectedPaths is not { Length: > 0 })
            throw new ArgumentException("Select at least one candidate before starting the archive job.");

        lock (_lock)
        {
            if (_runningUserId is not null &&
                _jobsByUser[_runningUserId].Snapshot().Status == "Running")
                throw new InvalidOperationException("Another archive job is already running. Try again when it has finished.");

            var job = new ArchiveJob();
            _jobsByUser[userId] = job;
            _runningUserId = userId;
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

    public JobSnapshot? GetCurrent(string userId)
    {
        lock (_lock)
            return _jobsByUser.TryGetValue(userId, out var job) ? job.Snapshot() : null;
    }
}
