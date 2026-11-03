using System.Security.Claims;
using System.Text.Encodings.Web;
using FolderArchiveWebConsole;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authorization;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;

var builder = WebApplication.CreateBuilder(args);
var tenantId = builder.Configuration["Authentication:Microsoft:TenantId"];
var clientId = builder.Configuration["Authentication:Microsoft:ClientId"];
var clientSecret = builder.Configuration["Authentication:Microsoft:ClientSecret"];

if (!Guid.TryParse(tenantId, out _) ||
    !Guid.TryParse(clientId, out _) ||
    string.IsNullOrWhiteSpace(clientSecret))
{
    throw new InvalidOperationException(
        "Configure Authentication__Microsoft__TenantId, Authentication__Microsoft__ClientId, and Authentication__Microsoft__ClientSecret before starting the hosted console.");
}

builder.Services
    .AddAuthentication(options =>
    {
        options.DefaultScheme = CookieAuthenticationDefaults.AuthenticationScheme;
    })
    .AddCookie(options =>
    {
        options.Cookie.Name = "__Host-ArchiveAuth";
        options.Cookie.HttpOnly = true;
        options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.Cookie.Path = "/";
        options.ExpireTimeSpan = TimeSpan.FromHours(8);
        options.SlidingExpiration = true;
        options.LoginPath = "/account/login";
        options.AccessDeniedPath = "/account/denied";
        options.Events.OnRedirectToLogin = context =>
        {
            if (context.Request.Path.StartsWithSegments("/api"))
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            else
                context.Response.Redirect(context.RedirectUri);
            return Task.CompletedTask;
        };
        options.Events.OnRedirectToAccessDenied = context =>
        {
            if (context.Request.Path.StartsWithSegments("/api"))
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
            else
                context.Response.Redirect(context.RedirectUri);
            return Task.CompletedTask;
        };
    })
    .AddOpenIdConnect(options =>
    {
        options.Authority = $"https://login.microsoftonline.com/{tenantId}/v2.0";
        options.ClientId = clientId;
        options.ClientSecret = clientSecret;
        options.ResponseType = OpenIdConnectResponseType.Code;
        options.SignedOutCallbackPath = "/signout-callback-oidc";
        options.MapInboundClaims = false;
        options.SaveTokens = false;
        options.RequireHttpsMetadata = true;
        options.Scope.Clear();
        options.Scope.Add("openid");
        options.Scope.Add("profile");
        options.TokenValidationParameters.NameClaimType = "name";
        options.Events.OnRemoteFailure = context =>
        {
            context.HandleResponse();
            context.Response.Redirect("/account/login?error=1");
            return Task.CompletedTask;
        };
    });

builder.Services.AddAuthorization();
builder.Services.AddAntiforgery(options =>
{
    options.HeaderName = "X-CSRF-TOKEN";
    options.Cookie.Name = "__Host-ArchiveCsrf";
    options.Cookie.HttpOnly = true;
    options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
    options.Cookie.SameSite = SameSiteMode.Strict;
    options.Cookie.Path = "/";
});
builder.Services.AddSingleton<ArchiveOperationsService>();
builder.Services.AddSingleton<HostedJobCoordinator>();

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

app.UseHttpsRedirection();
app.Use(async (context, next) =>
{
    context.Response.Headers["Content-Security-Policy"] =
        "default-src 'self'; connect-src 'self'; img-src 'self'; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["X-Frame-Options"] = "DENY";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    context.Response.Headers["Cache-Control"] = "no-store";
    await next();
});

app.UseStaticFiles();
app.UseAuthentication();
app.UseAuthorization();

var loginPage = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "Login.html"));
app.MapGet("/account/login", (HttpContext context) =>
{
    if (context.User.Identity?.IsAuthenticated == true)
        return (IResult)Results.Redirect("/");

    return Results.Content(loginPage, "text/html; charset=utf-8");
}).AllowAnonymous();

app.MapGet("/account/signin", () =>
    Results.Challenge(
        new Microsoft.AspNetCore.Authentication.AuthenticationProperties { RedirectUri = "/" },
        [OpenIdConnectDefaults.AuthenticationScheme]))
    .AllowAnonymous();

app.MapGet("/account/denied", () =>
    Results.Content("Your organization has not granted you access to this application.", "text/plain"))
    .AllowAnonymous();

var indexPage = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "HostedIndex.html"));
app.MapGet("/", (HttpContext context, IAntiforgery antiforgery) =>
{
    var tokens = antiforgery.GetAndStoreTokens(context);
    var csrfToken = HtmlEncoder.Default.Encode(tokens.RequestToken ?? string.Empty);
    var accountName = context.User.FindFirstValue("preferred_username")
        ?? context.User.FindFirstValue("name")
        ?? "Signed-in user";
    var safeAccountName = HtmlEncoder.Default.Encode(accountName);
    var logoutForm =
        $"<div class=\"account-actions\"><span>{safeAccountName}</span><form method=\"post\" action=\"/account/logout\"><input type=\"hidden\" name=\"__RequestVerificationToken\" value=\"{csrfToken}\"><button type=\"submit\">Sign out</button></form></div>";
    var hostedPage = indexPage
        .Replace("Private local session", "Entra ID authenticated", StringComparison.Ordinal)
        .Replace("Only this computer can connect", "Access is controlled by your organization", StringComparison.Ordinal)
        .Replace("LOCALHOST ONLY", "SECURE SERVER", StringComparison.Ordinal)
        .Replace("Local browser console", "Secure hosted console", StringComparison.Ordinal)
        .Replace("<div class=\"local-badge\"><span></span> SECURE SERVER</div>", logoutForm, StringComparison.Ordinal)
        .Replace("</head>", $"<meta name=\"csrf-token\" content=\"{csrfToken}\"><link rel=\"stylesheet\" href=\"/hosted.css\"></head>", StringComparison.Ordinal);
    return Results.Content(hostedPage, "text/html; charset=utf-8");
}).RequireAuthorization();

app.MapPost("/account/logout", (HttpContext context) =>
{
    return Results.SignOut(
        new AuthenticationProperties { RedirectUri = "/account/login" },
        [CookieAuthenticationDefaults.AuthenticationScheme, OpenIdConnectDefaults.AuthenticationScheme]);
}).RequireAuthorization().AddEndpointFilter(ValidateAntiforgery);

app.MapPost("/api/scan", (ScanRequest request, ArchiveOperationsService archive) =>
{
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
}).RequireAuthorization().AddEndpointFilter(ValidateAntiforgery);

app.MapPost("/api/jobs", (HttpContext context, ArchiveRequest request, HostedJobCoordinator jobs) =>
{
    try
    {
        return Results.Accepted(value: new { id = jobs.Start(GetUserId(context), request) });
    }
    catch (ArgumentException exception)
    {
        return Results.BadRequest(new { error = exception.Message });
    }
    catch (InvalidOperationException exception)
    {
        return Results.Conflict(new { error = exception.Message });
    }
}).RequireAuthorization().AddEndpointFilter(ValidateAntiforgery);

app.MapPost("/api/jobs/status", (HttpContext context, HostedJobCoordinator jobs) =>
{
    return jobs.GetCurrent(GetUserId(context)) is { } status
        ? Results.Ok(status)
        : Results.NoContent();
}).RequireAuthorization().AddEndpointFilter(ValidateAntiforgery);

await app.RunAsync();

static string GetUserId(HttpContext context) =>
    context.User.FindFirstValue("sub")
    ?? throw new InvalidOperationException("The authenticated account does not contain a stable user identifier.");

static async ValueTask<object?> ValidateAntiforgery(
    EndpointFilterInvocationContext context,
    EndpointFilterDelegate next)
{
    var antiforgery = context.HttpContext.RequestServices.GetRequiredService<IAntiforgery>();
    try
    {
        await antiforgery.ValidateRequestAsync(context.HttpContext);
    }
    catch (AntiforgeryValidationException)
    {
        return Results.BadRequest(new { error = "The request verification token is missing or invalid. Reload the page and try again." });
    }

    return await next(context);
}
