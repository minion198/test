using System;
using System.Net;
using System.Text;
using System.Net.Sockets;

class Program
{
    // Start Healthy by default; override with env var HEALTH_START_STATE=Unhealthy
    private static string _healthState = Environment.GetEnvironmentVariable("HEALTH_START_STATE")?.Equals("Unhealthy", StringComparison.OrdinalIgnoreCase) == true
        ? "Unhealthy" : "Healthy";

    static void Main()
    {
        var listener = new HttpListener();

        // Bind to all interfaces on port 8080
        listener.Prefixes.Add("http://*:8080/");
        listener.Start();
        Console.WriteLine("Sample App Running on port 8080...");

        while (true)
        {
            HttpListenerContext context = null;
            try
            {
                context = listener.GetContext();
                HandleRequest(context);
            }
            catch (Exception ex)
            {
                try
                {
                    if (context != null)
                    {
                        context.Response.StatusCode = 500;
                        var msg = Encoding.UTF8.GetBytes("Internal Server Error: " + ex.Message);
                        context.Response.ContentLength64 = msg.Length;
                        context.Response.OutputStream.Write(msg, 0, msg.Length);
                        context.Response.OutputStream.Close();
                    }
                }
                catch { /* swallow */ }
                Console.Error.WriteLine($"[ERROR] {ex}");
            }
        }
    }

    private static void HandleRequest(HttpListenerContext ctx)
    {
        var req = ctx.Request;
        var res = ctx.Response;

        var path = (req.Url?.AbsolutePath ?? "/").Trim().ToLowerInvariant();

        if (req.HttpMethod != "GET")
        {
            res.StatusCode = 405; // Method Not Allowed
            WriteText(res, "Only GET is supported.");
            return;
        }

        switch (path)
        {
            case "/healthz":
                // Application Health (Rich) expects JSON with ApplicationHealthState = Healthy | Unhealthy
                res.StatusCode = 200;
                var json = $"{{\"ApplicationHealthState\":\"{_healthState}\"}}";
                WriteJson(res, json);
                break;

            case "/admin/set-health":
                // Allow only local callers to toggle health for demos
                if (!IsLocalCall(req))
                {
                    res.StatusCode = 403;
                    WriteText(res, "Forbidden: /admin/set-health is local-only.");
                    break;
                }

                var state = (req.QueryString["state"] ?? "").Trim();
                if (!state.Equals("Healthy", StringComparison.OrdinalIgnoreCase) &&
                    !state.Equals("Unhealthy", StringComparison.OrdinalIgnoreCase))
                {
                    res.StatusCode = 400;
                    WriteText(res, "Bad Request: state must be Healthy or Unhealthy.");
                    break;
                }

                _healthState = char.ToUpper(state[0]) + state.Substring(1).ToLower();
                res.StatusCode = 200;
                WriteJson(res, $"{{\"status\":\"ok\",\"newState\":\"{_healthState}\"}}");
                break;

            default:
                // Original landing response
                var hostname = Dns.GetHostName();
                var ipAddress = GetLocalIPAddress();
                res.StatusCode = 200;
                WriteText(res,
                    $"Immutable Infrastructure POC Running!\nVM Hostname: {hostname}\nVM IP: {ipAddress}\n" +
                    $"Health endpoint: GET http://localhost:8080/healthz (currently: {_healthState})");
                break;
        }
    }

    private static void WriteText(HttpListenerResponse res, string text)
    {
        var buffer = Encoding.UTF8.GetBytes(text);
        res.ContentType = "text/plain; charset=utf-8";
        res.ContentLength64 = buffer.Length;
        res.OutputStream.Write(buffer, 0, buffer.Length);
        res.OutputStream.Close();
    }

    private static void WriteJson(HttpListenerResponse res, string json)
    {
        var buffer = Encoding.UTF8.GetBytes(json);
        res.ContentType = "application/json; charset=utf-8";
        res.ContentLength64 = buffer.Length;
        res.OutputStream.Write(buffer, 0, buffer.Length);
        res.OutputStream.Close();
    }

    private static bool IsLocalCall(HttpListenerRequest req)
    {
        // Treat loopback as local. Fallback to header if RemoteEndPoint is null.
        try
        {
            var ep = req.RemoteEndPoint;
            return ep != null && IPAddress.IsLoopback(ep.Address);
        }
        catch
        {
            // As a conservative fallback, only allow if Host header is localhost/127.0.0.1
            var host = req.UserHostName ?? "";
            return host.Contains("localhost", StringComparison.OrdinalIgnoreCase) || host.StartsWith("127.0.0.1");
        }
    }

    // Get the local IPv4 address of the VM
    private static string GetLocalIPAddress()
    {
        foreach (var ip in Dns.GetHostAddresses(Dns.GetHostName()))
        {
            if (ip.AddressFamily == AddressFamily.InterNetwork)
            {
                return ip.ToString();
            }
        }
        return "Unknown";
    }
}
