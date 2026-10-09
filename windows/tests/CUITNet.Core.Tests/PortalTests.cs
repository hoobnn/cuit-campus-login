using System.Diagnostics;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using CUITNet.Core;
using Xunit;

namespace CUITNet.Core.Tests;

public class UnitTests
{
    [Fact]
    public void AesMatchesCapturedPortalCiphertext() =>
        // 浏览器在真实门户上加密 zzprobe0001 得到的密文
        Assert.Equal("Uz/UJgU3BdOiWO9Bfrykrg==", PortalCrypto.Encrypt("Qvy2L55c2aTCHUc6uX/Llw==", "zzprobe0001"));

    [Fact]
    public void CarrierAliases()
    {
        Assert.True(Carrier.Cmcc.Matches("中国移动"));
        Assert.True(Carrier.Ctcc.Matches("CTCC"));
        Assert.False(Carrier.Unicom.Matches("移动"));
    }
}

/// <summary>启动 testing/fake_portal.py 作为假门户，端到端跑完整链路。</summary>
public sealed class FakePortal : IDisposable
{
    readonly Process _process;
    public Uri Base { get; }
    public IReadOnlyList<Probe> Probes => [new(new Uri(Base, "/generate_204"), 204)];

    public FakePortal()
    {
        var dir = AppContext.BaseDirectory;
        while (!Directory.Exists(Path.Combine(dir, "testing"))) dir = Path.GetDirectoryName(dir)!;
        var port = Random.Shared.Next(20000, 40000);
        _process = Process.Start(new ProcessStartInfo(OperatingSystem.IsWindows() ? "python" : "python3",
            [Path.Combine(dir, "testing", "fake_portal.py"), port.ToString()])
        { RedirectStandardOutput = true })!;
        Base = new Uri(_process.StandardOutput.ReadLine()!.Trim());
    }

    public async Task<JsonObject> StateAsync()
    {
        using var c = new HttpClient();
        var r = await c.PostAsJsonAsync(new Uri(Base, "/__state"), new { });
        return (JsonNode.Parse(await r.Content.ReadAsStringAsync()) as JsonObject)!;
    }

    public void Dispose() => _process.Kill();
}

public class EndToEndTests : IDisposable
{
    readonly FakePortal _portal = new();

    public void Dispose() => _portal.Dispose();

    [Fact]
    public async Task DetectsCaptivePortal()
    {
        var s = await Connectivity.CheckAsync(_portal.Probes);
        Assert.Equal(NetKind.Captive, s.Kind);
        Assert.Equal("/eportal/index.jsp", s.PortalEntry?.AbsolutePath);
    }

    [Fact]
    public async Task LoginAndLogout()
    {
        var out_ = await Login.RunAsync(new Credentials("2023000001", "right-pass", Carrier.Cmcc), _portal.Base, probes: _portal.Probes);
        Assert.Equal("登录成功（移动）", out_.Message);
        Assert.Equal("10.254.0.1", out_.LearnedNas);
        var st = await _portal.StateAsync();
        Assert.True(st["online"]!.GetValue<bool>());
        Assert.Equal("cmcc", st["chosen"]!.GetValue<string>());
        Assert.Equal(NetKind.Online, (await Connectivity.CheckAsync(_portal.Probes)).Kind);

        await Login.LogoutAsync(_portal.Base);
        Assert.False((await _portal.StateAsync())["online"]!.GetValue<bool>());
    }

    [Fact]
    public async Task WrongPasswordIsRejected()
    {
        var e = await Assert.ThrowsAsync<AuthRejectedException>(() =>
            Login.RunAsync(new Credentials("2023000001", "wrong", Carrier.Cmcc), _portal.Base, probes: _portal.Probes));
        Assert.Contains("密码错误", e.Message);
    }
}
