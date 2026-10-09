using System.Text.RegularExpressions;
using System.Web;

namespace CUITNet.Core;

/// <summary>
/// 锐捷 SAM 5.x 门户 + CAS 单点登录（成都信息工程大学）。
///   1. 被劫持请求 302 -> /eportal/index.jsp -> /portal/portal-main?sessionId=...
///      拿不到劫持跳转时退回 GET {portal}/entry?nasip=
///   2. POST /eportal/workFlow/getCurrentNode
///   3. GET  /cas-sso/login    页面里有 AES 密钥（login-croypto）和 execution
///   4. POST /cas-sso/login    AES-128-ECB 加密后的密码
///   5. POST /eportal/network/serviceSelection + serviceLogin，authResult == "success" 才放行
/// </summary>
public sealed partial class PortalClient(Uri portal, string nasIp, PortalHttp http)
{
    public static readonly Uri DefaultPortal = new("http://10.254.241.66");

    public Uri Portal { get; private set; } = portal;

    static Uri At(Uri baseUri, string path) => new(baseUri, path);

    // 步骤 1：优先走网关的劫持跳转，只有这样门户才知道我们接在哪台接入设备上，nasIp 才是真值
    public async Task<PortalSession> OpenSessionAsync(Uri? captiveEntry, CancellationToken ct = default)
    {
        var candidates = new List<Uri>();
        if (captiveEntry != null) candidates.Add(captiveEntry);
        candidates.Add(At(Portal, string.IsNullOrEmpty(nasIp) ? "/entry" : "/entry?nasip=" + Uri.EscapeDataString(nasIp)));

        foreach (var start in candidates)
        {
            var url = start;
            for (var hop = 0; hop < 12; hop++)
            {
                var r = await http.GetAsync(url, Portal, ct: ct);
                var target = r.Location ?? url;
                var q = Query(target);
                if (q.TryGetValue("sessionId", out var sid) && sid.Length > 0)
                {
                    var origin = new Uri(target.GetLeftPart(UriPartial.Authority));
                    if (origin != Portal) Portal = origin;
                    if (r.Location != null)
                    {
                        try { await http.GetAsync(target, url, ct: ct); } catch (HttpRequestException) { }
                    }
                    return new PortalSession(Portal, sid, q, target);
                }
                if (r.Location == null) break;
                url = r.Location;
            }
        }
        throw new PortalException("门户没有返回 sessionId（可能已经在线，或当前不在校园网内）");
    }

    // 步骤 2-4
    public async Task AuthenticateAsync(PortalSession s, string username, string password, CancellationToken ct = default)
    {
        try
        {
            await http.PostJsonAsync(At(s.Portal, "/eportal/workFlow/getCurrentNode"),
                new { sessionId = s.SessionId, flowKey = s.Params.GetValueOrDefault("flowKey", "portal_auth") }, s.Url, ct);
        }
        catch (HttpRequestException) { } // 部分环境省略也能登录

        var query = HttpUtility.ParseQueryString("");
        query["flowSessionId"] = s.SessionId;
        query["customPageId"] = s.Params.GetValueOrDefault("customPageId", "");
        query["preview"] = "false";
        query["appType"] = "normal";
        query["language"] = "zh-CN";
        query["timer"] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds().ToString();
        query["nasIp"] = s.NasIp;
        query["userIp"] = s.Params.GetValueOrDefault("userIp", "");
        query["userMac"] = s.Params.GetValueOrDefault("userMac", "");
        var casUrl = At(s.Portal, "/cas-sso/login?" + query);

        var page = (await http.GetAsync(casUrl, s.Url, follow: true, ct: ct)).Text;
        var key = Pick(page, "login-croypto");
        var execution = Pick(page, "login-page-flowkey");
        if (key == null || execution == null)
            throw new PortalException("CAS 登录页里找不到密钥或令牌（页面结构可能变了）");

        var form = new Dictionary<string, string>
        {
            ["username"] = username,
            ["type"] = "UsernamePassword",
            ["_eventId"] = "submit",
            ["geolocation"] = "",
            ["execution"] = execution,
            ["captcha_code"] = "",
            ["croypto"] = key,
            ["password"] = PortalCrypto.Encrypt(key, password),
            ["captcha_payload"] = PortalCrypto.Encrypt(key, "{}"),
        };
        var r = await http.PostFormAsync(new Uri(casUrl + "&accept-language=zh-CN"), form, casUrl,
            new Dictionary<string, string> { ["Origin"] = s.Portal.GetLeftPart(UriPartial.Authority) }, ct);
        JudgeCas(r);
    }

    // 步骤 5：选运营商上线，返回门户里的运营商名字
    public async Task<string> SelectServiceAsync(PortalSession s, Carrier carrier, CancellationToken ct = default)
    {
        string value = carrier.Value(), name = carrier.DisplayName();
        var entries = new List<(string Name, string Value)>();
        try
        {
            var list = await http.PostJsonAsync(At(s.Portal, "/eportal/network/serviceSelection"), new { sessionId = s.SessionId }, s.Url, ct);
            if (list.Json()?["data"] is System.Text.Json.Nodes.JsonArray items)
                foreach (var item in items.OfType<System.Text.Json.Nodes.JsonObject>())
                    entries.Add((Field(item, "key", "name", "serviceName", "label"), Field(item, "value", "service", "serviceId", "id")));
        }
        catch (HttpRequestException) { }

        if (entries.Count > 0)
        {
            var hit = entries.FirstOrDefault(e => carrier.Matches(e.Value) || carrier.Matches(e.Name));
            if (hit == default)
                throw new PortalException($"门户的运营商列表里没有「{name}」，可选：{string.Join("、", entries.Select(e => e.Name))}");
            (name, value) = hit;
        }

        var r = await http.PostJsonAsync(At(s.Portal, "/eportal/network/serviceLogin"),
            new { sessionId = s.SessionId, service = value }, s.Url, ct);
        var body = r.Json() ?? throw new PortalException($"serviceLogin 返回了非 JSON（HTTP {r.Status}）");
        var data = body["data"] as System.Text.Json.Nodes.JsonObject;
        if (data?["authResult"]?.GetValue<string>() == "success") return name;
        var msg = data?["authMessage"]?.ToString() ?? body["message"]?.ToString() ?? $"HTTP {r.Status}";
        if (new[] { "密码", "不存在", "锁定", "停机", "欠费", "禁用" }.Any(msg.Contains))
            throw new AuthRejectedException(msg);
        throw new PortalException($"选择运营商「{name}」后门户未放行：{msg}");
    }

    public async Task LogoutAsync(CancellationToken ct = default)
    {
        var s = await OpenSessionAsync(null, ct);
        var r = await http.PostJsonAsync(At(s.Portal, "/eportal/network/offline"), new { sessionId = s.SessionId }, s.Url, ct);
        var body = r.Json();
        if (body?["code"]?.GetValue<int>() != 200)
            throw new PortalException("下线失败：" + (body?["message"]?.ToString() ?? $"HTTP {r.Status}"));
    }

    internal static void JudgeCas(HttpResult r)
    {
        var loc = r.Location?.ToString() ?? "";
        if (r.IsRedirect && (loc.Contains("ticket=ST-") || loc.Contains("callbackAuthorize")
                             || loc.Contains("auth-success") || !loc.Contains("/cas-sso/login")))
            return;
        foreach (var id in new[] { "login-error-msg", "loginFailMessage" })
            if (Pick(r.Text, id) is { } msg) throw new AuthRejectedException(msg);
        if (r.Status == 401 || r.Text.Contains("login-croypto")) throw new AuthRejectedException("账号或密码错误");
        throw new PortalException($"CAS 返回了无法识别的结果（HTTP {r.Status}）");
    }

    internal static string? Pick(string html, string id)
    {
        var m = Regex.Match(html, $@"id=[""']{Regex.Escape(id)}[""'][^>]*>\s*([^<]+?)\s*<");
        return m.Success ? m.Groups[1].Value : null;
    }

    static Dictionary<string, string> Query(Uri url)
    {
        var q = HttpUtility.ParseQueryString(url.Query);
        return q.AllKeys.Where(k => k != null).ToDictionary(k => k!, k => q[k] ?? "");
    }

    static string Field(System.Text.Json.Nodes.JsonObject o, params string[] keys) =>
        keys.Select(k => o[k]?.ToString()).FirstOrDefault(v => !string.IsNullOrEmpty(v)) ?? "";
}
