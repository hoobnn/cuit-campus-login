using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CUITNet.Core;

public sealed record HttpResult(int Status, Uri Url, Uri? Location, string Text)
{
    public bool IsRedirect => Status is 301 or 302 or 303 or 307 or 308;

    public JsonObject? Json()
    {
        try { return JsonNode.Parse(Text) as JsonObject; }
        catch (System.Text.Json.JsonException) { return null; }
    }
}

/// <summary>
/// 不自动跳转、不走系统代理、自带 Cookie 的 HTTP 客户端。
/// 认证请求必须直连：开着代理时请求从代理出口发出，网关看不到本机，登录必然失败。
/// </summary>
public sealed class PortalHttp : IDisposable
{
    const string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36";

    readonly HttpClient _client;

    public PortalHttp(TimeSpan? timeout = null)
    {
        var handler = new HttpClientHandler
        {
            UseProxy = false,
            AllowAutoRedirect = false,
            UseCookies = true,
            CookieContainer = new CookieContainer(),
        };
        _client = new HttpClient(handler) { Timeout = timeout ?? TimeSpan.FromSeconds(8) };
        _client.DefaultRequestHeaders.UserAgent.ParseAdd(UserAgent);
        _client.DefaultRequestHeaders.AcceptLanguage.ParseAdd("zh-CN,zh;q=0.9");
    }

    public Task<HttpResult> GetAsync(Uri url, Uri? referer = null, bool follow = false, CancellationToken ct = default) =>
        SendAsync(() => new HttpRequestMessage(HttpMethod.Get, url), url, referer, follow, ct);

    public Task<HttpResult> PostFormAsync(Uri url, IEnumerable<KeyValuePair<string, string>> form, Uri? referer = null,
        IDictionary<string, string>? headers = null, CancellationToken ct = default) =>
        SendAsync(() => With(new HttpRequestMessage(HttpMethod.Post, url) { Content = new FormUrlEncodedContent(form) }, headers),
                  url, referer, false, ct);

    public Task<HttpResult> PostJsonAsync(Uri url, object body, Uri? referer = null, CancellationToken ct = default) =>
        // 序列化成字符串再发：JsonContent 默认分块传输、不带 Content-Length，部分老服务端读不到请求体
        SendAsync(() => new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"),
        }, url, referer, false, ct);

    static HttpRequestMessage With(HttpRequestMessage req, IDictionary<string, string>? headers)
    {
        foreach (var (k, v) in headers ?? new Dictionary<string, string>()) req.Headers.TryAddWithoutValidation(k, v);
        return req;
    }

    async Task<HttpResult> SendAsync(Func<HttpRequestMessage> make, Uri url, Uri? referer, bool follow, CancellationToken ct)
    {
        for (var hop = 0; hop < 10; hop++)
        {
            using var req = make();
            req.RequestUri = url;
            req.Headers.TryAddWithoutValidation("isPortal", "true");
            if (referer != null) req.Headers.Referrer = referer;
            using var resp = await _client.SendAsync(req, ct).ConfigureAwait(false);
            var text = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
            var loc = resp.Headers.Location is { } l ? (l.IsAbsoluteUri ? l : new Uri(url, l)) : null;
            var result = new HttpResult((int)resp.StatusCode, url, loc, text);
            if (!follow || !result.IsRedirect || loc == null) return result;
            url = loc;
            make = () => new HttpRequestMessage(HttpMethod.Get, url);
        }
        throw new PortalException("跳转次数过多");
    }

    public void Dispose() => _client.Dispose();
}
