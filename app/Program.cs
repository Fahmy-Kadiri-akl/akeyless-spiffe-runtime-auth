// Reference workload for akeyless-spiffe-runtime-auth.
//
// Demonstrates the SPIFFE/SPIRE auth path end to end: it pulls a fresh JWT-SVID
// from the SPIRE Workload API, trades it for an Akeyless token through the
// OAuth2/JWT auth method, and reads a secret.
//
// The Akeyless side uses the Akeyless REST API directly (HttpClient). The SVID
// fetch uses the spire-agent CLI because there is no mature .NET SPIFFE
// Workload API client. No credential is stored on disk and none is held between
// runs; the SVID is fetched per invocation and expires within minutes.

using System.Diagnostics;
using System.Net.Http.Json;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;

var gateway = Require("AKEYLESS_GATEWAY").TrimEnd('/');
var authMethodAccessId = ResolveAccessId();
var secretName = Environment.GetEnvironmentVariable("AKEYLESS_SECRET") ?? "/spiffe/demo/db-password";
var audience = Environment.GetEnvironmentVariable("JWT_AUDIENCE") ?? "akeyless";
var socket = Environment.GetEnvironmentVariable("SPIFFE_WORKLOAD_SOCKET") ?? "/tmp/spire-agent/public/api.sock";

Console.WriteLine($"[1/3] Fetching JWT-SVID (audience={audience}) from {socket} ...");
var svid = await FetchJwtSvid(socket, audience);
Console.WriteLine($"      got SVID ({svid.Length} bytes), sub={DecodeClaim(svid, "sub")}, exp={DecodeClaim(svid, "exp")}");

using var http = CreateHttpClient();

Console.WriteLine($"[2/3] Authenticating to Akeyless at {gateway}/api/v2/auth ...");
var authBody = new Dictionary<string, object>
{
    ["access-type"] = "jwt",
    ["access-id"] = authMethodAccessId,
    ["jwt"] = svid,
};
var authResp = await http.PostAsJsonAsync($"{gateway}/api/v2/auth", authBody);
authResp.EnsureSuccessStatusCode();
var authJson = await authResp.Content.ReadFromJsonAsync<JsonElement>();
var token = authJson.GetProperty("token").GetString()
    ?? throw new Exception("no token in auth response");
Console.WriteLine($"      got Akeyless token ({token.Length} bytes)");

Console.WriteLine($"[3/3] Reading secret {secretName} ...");
var secretBody = new Dictionary<string, object>
{
    ["names"] = new[] { secretName },
    ["token"] = token,
};
var secretResp = await http.PostAsJsonAsync($"{gateway}/api/v2/get-secret-value", secretBody);
secretResp.EnsureSuccessStatusCode();
var secretJson = await secretResp.Content.ReadFromJsonAsync<JsonElement>();
var value = secretJson.GetProperty(secretName).GetString();
Console.WriteLine($"      secret value: {value}");

static string Require(string name) =>
    Environment.GetEnvironmentVariable(name)
        ?? throw new InvalidOperationException($"{name} environment variable is required.");

// Create an HttpClient that trusts a self-signed or internal CA when
// AKEYLESS_CA_CERT points at a PEM CA certificate file. With no CA file set,
// the default client is used, which suits a publicly trusted gateway.
static HttpClient CreateHttpClient()
{
    var caPath = Environment.GetEnvironmentVariable("AKEYLESS_CA_CERT");
    if (string.IsNullOrEmpty(caPath) || !File.Exists(caPath))
        return new HttpClient();

    var ca = new X509Certificate2(File.ReadAllBytes(caPath));
    var handler = new HttpClientHandler();
    handler.ServerCertificateCustomValidationCallback = (request, cert, chain, errors) =>
    {
        if (errors == SslPolicyErrors.None) return true;
        chain!.ChainPolicy.CustomTrustStore.Add(ca);
        chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
        return chain.Build(new X509Certificate2(cert!));
    };
    return new HttpClient(handler);
}

static string ResolveAccessId()
{
    var env = Environment.GetEnvironmentVariable("AKEYLESS_ACCESS_ID");
    if (!string.IsNullOrWhiteSpace(env)) return env;
    var file = Environment.GetEnvironmentVariable("AKEYLESS_ACCESS_ID_FILE") ?? "/run/spire-data/akeyless-access-id";
    if (File.Exists(file)) return File.ReadAllText(file).Trim();
    throw new InvalidOperationException(
        "auth-method access id not found. Set AKEYLESS_ACCESS_ID, or run " +
        "bootstrap/setup-akeyless.sh to write /run/spire-data/akeyless-access-id.");
}

static async Task<string> FetchJwtSvid(string socket, string audience)
{
    // The Workload API is gRPC; there is no mature .NET client, so we shell out
    // to the spire-agent CLI, which is the standard way to fetch an SVID.
    var (stdout, stderr, code) = await RunProcess(
        "spire-agent", ["api", "fetch", "jwt", "-audience", audience, "-socketPath", socket, "-output", "json"]);
    if (code != 0)
        throw new Exception($"spire-agent api fetch jwt failed (exit {code}): {stderr}");
    using var doc = JsonDocument.Parse(stdout);
    return doc.RootElement[0].GetProperty("svids")[0].GetProperty("svid").GetString()
        ?? throw new Exception("no SVID in Workload API response");
}

static string DecodeClaim(string jwt, string claim)
{
    try
    {
        var payload = jwt.Split('.')[1];
        payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
        var bytes = Convert.FromBase64String(payload.Replace('-', '+').Replace('_', '/'));
        using var doc = JsonDocument.Parse(bytes);
        return doc.RootElement.TryGetProperty(claim, out var v) ? v.ToString() : "?";
    }
    catch
    {
        return "?";
    }
}

static async Task<(string stdout, string stderr, int code)> RunProcess(string file, string[] args)
{
    var psi = new ProcessStartInfo
    {
        FileName = file,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false,
    };
    foreach (var a in args) psi.ArgumentList.Add(a);
    using var p = Process.Start(psi) ?? throw new Exception($"could not start {file}");
    var stdout = await p.StandardOutput.ReadToEndAsync();
    var stderr = await p.StandardError.ReadToEndAsync();
    await p.WaitForExitAsync();
    return (stdout, stderr, p.ExitCode);
}
