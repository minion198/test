using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace ImmutableSampleService
{
    public class Program
    {
        public static async Task Main(string[] args)
        {
            await Host.CreateDefaultBuilder(args)
                .UseWindowsService(options => options.ServiceName = "DotNetSampleService")
                .ConfigureServices(services =>
                {
                    services.AddHostedService<HttpListenerService>();
                })
                .Build()
                .RunAsync();
        }
    }

    public class HttpListenerService : BackgroundService
    {
        private readonly ILogger<HttpListenerService> _logger;
        private HttpListener? _listener;
        private volatile string _healthState;

        public HttpListenerService(ILogger<HttpListenerService> logger)
        {
            _logger = logger;
            // Start Healthy by default; override with env var HEALTH_START_STATE=Unhealthy
            var env = Environment.GetEnvironmentVariable("HEALTH_START_STATE");
            _healthState = string.Equals(env, "Unhealthy", StringComparison.OrdinalIgnoreCase) ? "Unhealthy" : "Healthy";
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _listener = new HttpListener();
            // Bind to all interfaces on port 8080
            _listener.Prefixes.Add($"http://+:8080/");
            _listener.Start();
            _logger.LogInformation("Sample App Running on port 8080...");

            try
            {
                while (!stoppingToken.IsCancellationRequested)
                {
                    var ctxTask = _listener.GetContextAsync();
                    var completed = await Task.WhenAny(ctxTask, Task.Delay(Timeout.Infinite, stoppingToken));
                    if (completed != ctxTask) break; // cancellation
                    _ = ProcessAsync(ctxTask.Result, stoppingToken);
                }
            }
            catch (HttpListenerException) { /* socket closed on stop */ }
            catch (OperationCanceledException) { /* stopping */ }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unhandled exception in listener loop");
            }
        }

        public override Task StopAsync(CancellationToken cancellationToken)
        {
            try { _listener?.Close(); } catch { /* ignore */ }
            _logger.LogInformation("Service stopping.");
            return base.StopAsync(cancellationToken);
        }

        private async Task ProcessAsync(HttpListenerContext ctx, CancellationToken token)
        {
            try
            {
                var req = ctx.Request;
                var res = ctx.Response;
                var path = (req.Url?.AbsolutePath ?? "/").Trim().ToLowerInvariant();

                if (!string.Equals(req.HttpMethod, "GET", StringComparison.OrdinalIgnoreCase))
                {
                    res.StatusCode = 405;
                    await WriteTextAsync(res, "Only GET is supported.", token);
                    return;
                }

                switch (path)
                {
                    case "/healthz":
                        // Application Health (Rich) expects JSON with ApplicationHealthState = Healthy | Unhealthy
                        res.StatusCode = 200;
                        await WriteJsonAsync(res, $"{{\"ApplicationHealthState\":\"{_healthState}\"}}", token);
                        break;

                    case "/admin/set-health":
                        if (!IsLocalCall(req))
                        {
                            res.StatusCode = 403;
                            await WriteTextAsync(res, "Forbidden: /admin/set-health is local-only.", token);
                            break;
                        }
                        var state = (req.QueryString["state"] ?? "").Trim();
                        if (!state.Equals("Healthy", StringComparison.OrdinalIgnoreCase) &&
                            !state.Equals("Unhealthy", StringComparison.OrdinalIgnoreCase))
                        {
                            res.StatusCode = 400;
                            await WriteTextAsync(res, "Bad Request: state must be Healthy or Unhealthy.", token);
                            break;
                        }
                        _healthState = char.ToUpper(state[0]) + state.Substring(1).ToLower();
                        res.StatusCode = 200;
                        await WriteJsonAsync(res, $"{{\"status\":\"ok\",\"newState\":\"{_healthState}\"}}", token);
                        break;

                    default:
                        var hostname = Dns.GetHostName();
                        var ip = GetLocalIPAddress();
                        res.StatusCode = 200;
                        await WriteTextAsync(res,
                            $"Immutable Infrastructure POC Running!\nVM Hostname: {hostname}\nVM IP: {ip}\n" +
                            $"Health endpoint: GET http://localhost:8080/healthz (currently: {_healthState})", token);
                        break;
                }
            }
            catch (Exception ex)
            {
                try
                {
                    ctx.Response.StatusCode = 500;
                    var msg = "Internal Server Error: " + ex.Message;
                    var buf = Encoding.UTF8.GetBytes(msg);
                    ctx.Response.ContentLength64 = buf.Length;
                    await ctx.Response.OutputStream.WriteAsync(buf.AsMemory(0, buf.Length), token);
                }
                catch { /* ignore */ }
            }
            finally
            {
                try { ctx.Response.OutputStream.Close(); } catch { /* ignore */ }
                try { ctx.Response.Close(); } catch { /* ignore */ }
            }
        }

        private static async Task WriteTextAsync(HttpListenerResponse res, string text, CancellationToken token)
        {
            var buffer = Encoding.UTF8.GetBytes(text);
            res.ContentType = "text/plain; charset=utf-8";
            res.ContentLength64 = buffer.Length;
            await res.OutputStream.WriteAsync(buffer.AsMemory(0, buffer.Length), token);
        }

        private static async Task WriteJsonAsync(HttpListenerResponse res, string json, CancellationToken token)
        {
            var buffer = Encoding.UTF8.GetBytes(json);
            res.ContentType = "application/json; charset=utf-8";
            res.ContentLength64 = buffer.Length;
            await res.OutputStream.WriteAsync(buffer.AsMemory(0, buffer.Length), token);
        }

        private static bool IsLocalCall(HttpListenerRequest req)
        {
            try
            {
                var ep = req.RemoteEndPoint;
                return ep != null && IPAddress.IsLoopback(ep.Address);
            }
            catch
            {
                var host = req.UserHostName ?? "";
                return host.Contains("localhost", StringComparison.OrdinalIgnoreCase) || host.StartsWith("127.0.0.1");
            }
        }

        private static string GetLocalIPAddress()
        {
            foreach (var ip in Dns.GetHostAddresses(Dns.GetHostName()))
            {
                if (ip.AddressFamily == AddressFamily.InterNetwork)
                    return ip.ToString();
            }
            return "Unknown";
        }
    }
}
