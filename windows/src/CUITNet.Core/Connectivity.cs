using System.Net;
using System.Text.RegularExpressions;

namespace CUITNet.Core;

public sealed record Probe(Uri Url, int? Status, string? Contains = null)
{
    /// <summary>223.5.5.5 是纯 IP：断网时 DNS 不通也能被网关劫持，从而拿到门户地址。</summary>
    public static readonly IReadOnlyList<Probe> Standard =
    [
        new(new Uri("http://connect.rom.miui.com/generate_204"), 204),
        new(new Uri("http://www.msftconnecttest.com/connecttest.txt"), 200, "Microsoft Connect Test"),
        new(new Uri("http://captive.apple.com/hotspot-detect.html"), 200, "Success"),
        new(new Uri("http://223.5.5.5/"), null),
    ];
}

public static class Connectivity
{
    public static async Task<NetState> CheckAsync(IReadOnlyList<Probe>? probes = null, CancellationToken ct = default)
    {
        using var http = new PortalHttp(TimeSpan.FromSeconds(4));
        var reachable = false;
        foreach (var p in probes ?? Probe.Standard)
        {
            HttpResult r;
            try { r = await http.GetAsync(p.Url, ct: ct); }
            catch (Exception e) when (e is HttpRequestException or TaskCanceledException) { continue; }
            reachable = true;
            if (PortalEntry(r) is { } entry) return new NetState(NetKind.Captive, entry);
            if (p.Status is { } want)
            {
                if (r.Status == want && (p.Contains == null || r.Text.Contains(p.Contains))) return new NetState(NetKind.Online);
            }
            else if (!r.IsRedirect) return new NetState(NetKind.Online);
        }
        return new NetState(reachable ? NetKind.Captive : NetKind.NoNetwork);
    }

    static Uri? PortalEntry(HttpResult r)
    {
        if (r.IsRedirect && r.Location != null && IsPrivate(r.Location)) return r.Location;
        if (r.Status != 200) return null;
        var body = r.Text.Length > 8000 ? r.Text[..8000] : r.Text;
        foreach (var pattern in new[] { @"<meta[^>]+http-equiv=[""']?refresh[""']?[^>]+url=([^""'>\s]+)",
                                        @"location\.(?:replace|href)\s*[=(]\s*[""']([^""']+)[""']" })
        {
            var m = Regex.Match(body, pattern, RegexOptions.IgnoreCase);
            if (m.Success && Uri.TryCreate(r.Url, m.Groups[1].Value, out var u) && IsPrivate(u)) return u;
        }
        return null;
    }

    static bool IsPrivate(Uri u)
    {
        if (!IPAddress.TryParse(u.Host, out var ip)) return false;
        var b = ip.GetAddressBytes();
        return b.Length == 4 && (b[0] == 10 || b[0] == 127 || (b[0] == 192 && b[1] == 168) || (b[0] == 172 && b[1] is >= 16 and <= 31));
    }
}

public static class Login
{
    /// <summary>一次完整的登录。已在线时直接返回（force 除外）。</summary>
    public static async Task<LoginOutcome> RunAsync(Credentials creds, Uri? portal = null, string nasIp = "",
        bool force = false, IReadOnlyList<Probe>? probes = null, CancellationToken ct = default)
    {
        portal ??= PortalClient.DefaultPortal;
        var state = await Connectivity.CheckAsync(probes, ct);
        if (state.Kind == NetKind.Online && !force) return new LoginOutcome("已经在线", null, portal, null);

        using var http = new PortalHttp();
        var client = new PortalClient(portal, nasIp, http);
        PortalSession session;
        try { session = await client.OpenSessionAsync(state.Kind == NetKind.Captive ? state.PortalEntry : null, ct); }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            throw new PortalException("连不上认证服务器（不在校园网内？）：" + e.Message);
        }
        await client.AuthenticateAsync(session, creds.Username, creds.Password, ct);
        var name = await client.SelectServiceAsync(session, creds.Carrier, ct);
        var nas = session.HasRealNas && session.NasIp != nasIp ? session.NasIp : null;
        return new LoginOutcome($"登录成功（{name}）", name, client.Portal, nas);
    }

    public static async Task LogoutAsync(Uri? portal = null, string nasIp = "", CancellationToken ct = default)
    {
        using var http = new PortalHttp();
        await new PortalClient(portal ?? PortalClient.DefaultPortal, nasIp, http).LogoutAsync(ct);
    }
}
