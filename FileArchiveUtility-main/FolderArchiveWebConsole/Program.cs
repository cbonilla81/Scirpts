using System.ComponentModel;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using FolderArchiveWebConsole;

var appDirectory = AppContext.BaseDirectory;
var contentRoot = Directory.Exists(Path.Combine(appDirectory, "wwwroot"))
    ? appDirectory
    : Directory.GetCurrentDirectory();
var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    ContentRootPath = contentRoot
});
builder.WebHost.UseUrls("http://127.0.0.1:5187");
builder.Services.AddSingleton<ArchiveOperationsService>();
builder.Services.AddSingleton<JobCoordinator>();

var app = builder.Build();
var sessionToken = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));

app.Use(async (context, next) =>
{
    if (!string.Equals(context.Request.Host.Host, "localhost", StringComparison.OrdinalIgnoreCase))
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsync("This console only accepts requests addressed to localhost.");
        return;
    }

    context.Response.Headers["Content-Security-Policy"] =
        "default-src 'self'; connect-src 'self'; img-src 'self'; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    context.Response.Headers["Cache-Control"] = "no-store";
    await next();
});

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/session", () => Results.Ok(new { token = sessionToken }));

app.MapPost("/api/scan", (HttpContext context, ScanRequest request, ArchiveOperationsService archive) =>
{
    if (!IsAuthorized(context, sessionToken))
        return Results.Unauthorized();

    try
    {
        return Results.Ok(archive.Scan(request));
    }
    catch (ArgumentException exception)
    {
        return Results.BadRequest(new { error = exception.Message });
    }
    catch (IOException exception)
    {
        return Results.Problem(exception.Message, statusCode: StatusCodes.Status422UnprocessableEntity);
    }
    catch (UnauthorizedAccessException exception)
    {
        return Results.Problem(exception.Message, statusCode: StatusCodes.Status403Forbidden);
    }
});

app.MapPost("/api/jobs", (HttpContext context, ArchiveRequest request, JobCoordinator jobs) =>
{
    if (!IsAuthorized(context, sessionToken))
        return Results.Unauthorized();

    try
    {
        return Results.Accepted(value: new { id = jobs.Start(request) });
    }
    catch (ArgumentException exception)
    {
        return Results.BadRequest(new { error = exception.Message });
    }
    catch (InvalidOperationException exception)
    {
        return Results.Conflict(new { error = exception.Message });
    }
});

app.MapPost("/api/jobs/status", (HttpContext context, JobCoordinator jobs) =>
{
    if (!IsAuthorized(context, sessionToken))
        return Results.Unauthorized();

    return jobs.GetCurrent() is { } status
        ? Results.Ok(status)
        : Results.NoContent();
});

await app.StartAsync();
var consoleUrl = "http://localhost:5187";
Console.WriteLine($"File Archive Web Console is available at {consoleUrl}");
Console.WriteLine("This server is bound to this computer only. Press Ctrl+C to stop it.");

try
{
    Process.Start(new ProcessStartInfo(consoleUrl) { UseShellExecute = true });
}
catch (Exception exception) when (exception is InvalidOperationException or Win32Exception)
{
    Console.Error.WriteLine($"The browser could not be opened automatically: {exception.Message}");
}

await app.WaitForShutdownAsync();

static bool IsAuthorized(HttpContext context, string expectedToken)
{
    if (!context.Request.Headers.TryGetValue("X-Archive-Console-Token", out var suppliedToken))
        return false;

    var suppliedBytes = Encoding.UTF8.GetBytes(suppliedToken.ToString());
    var expectedBytes = Encoding.UTF8.GetBytes(expectedToken);
    return suppliedBytes.Length == expectedBytes.Length &&
           CryptographicOperations.FixedTimeEquals(suppliedBytes, expectedBytes);
}
