namespace CUITNet.Core;

/// <summary>门户流程出错，可以稍后重试。</summary>
public class PortalException(string message) : Exception(message);

/// <summary>账号或密码被拒。不能自动重试，否则可能把账号试锁。</summary>
public sealed class AuthRejectedException(string message) : PortalException("认证被拒：" + message);

public enum Carrier { Cmcc, Ctcc, Unicom }

public static class CarrierExtensions
{
    public static string Value(this Carrier c) => c switch
    {
        Carrier.Cmcc => "cmcc",
        Carrier.Ctcc => "ctcc",
        _ => "unicom",
    };

    public static string DisplayName(this Carrier c) => c switch
    {
        Carrier.Cmcc => "移动",
        Carrier.Ctcc => "电信",
        _ => "联通",
    };

    static string[] Aliases(this Carrier c) => c switch
    {
        Carrier.Cmcc => ["cmcc", "移动", "中国移动", "mobile"],
        Carrier.Ctcc => ["ctcc", "电信", "中国电信", "telecom", "chinanet"],
        _ => ["unicom", "联通", "中国联通", "cucc"],
    };

    public static bool Matches(this Carrier c, string text) =>
        c.Aliases().Contains(text.Trim().ToLowerInvariant());
}

public enum NetKind { Online, Captive, NoNetwork }

public sealed record NetState(NetKind Kind, Uri? PortalEntry = null);

public sealed record Credentials(string Username, string Password, Carrier Carrier);

/// <param name="LearnedNas">新学到的真实接入设备地址，调用方应保存。</param>
public sealed record LoginOutcome(string Message, string? Carrier, Uri Portal, string? LearnedNas);

public sealed record PortalSession(Uri Portal, string SessionId, IReadOnlyDictionary<string, string> Params, Uri Url)
{
    public string NasIp => Params.GetValueOrDefault("nasIp", "");
    public bool HasRealNas => NasIp is not ("" or "1.1.1.1");
}
