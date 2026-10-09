using System.Net.Http;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Net.NetworkInformation;
using System.Runtime.CompilerServices;
using System.Windows;
using CUITNet.Core;
using Microsoft.Win32;

namespace CUITNet.App;

public enum StatusKind { Checking, Online, Captive, NoNetwork, Working, Rejected, Failed }

public sealed record ActivityEntry(DateTime Time, string Text, bool IsError)
{
    public string TimeText => Time.ToString("HH:mm");
}

/// <summary>界面状态与守护循环。所有属性只在 UI 线程上修改。</summary>
public sealed class AppModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    /// <summary>需要弹系统通知时触发（标题，正文，是否错误）。</summary>
    public event Action<string, string, bool>? Notify;

    readonly Settings _settings = Settings.Load();
    readonly string _logPath = Path.Combine(Settings.Dir, "logs", "cuitnet.log");
    CancellationTokenSource? _monitor;
    CancellationTokenSource _nap = new();
    string? _rejectedFingerprint;

    public ObservableCollection<ActivityEntry> Activity { get; } = [];

    public AppModel()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_logPath)!);
        // 换网络、插拔网线、从睡眠恢复时立刻重新检查，不用等下一个周期
        NetworkChange.NetworkAddressChanged += (_, _) => Ui(Poke);
        SystemEvents.PowerModeChanged += (_, e) => { if (e.Mode == PowerModes.Resume) Ui(Poke); };
        if (KeepOnline) StartMonitor(); else _ = RefreshAsync();
    }

    // ---------------------------------------------------------------- 状态

    StatusKind _status = StatusKind.Checking;
    string _detail = "";

    public StatusKind Status
    {
        get => _status;
        private set { _status = value; Changed(); Changed(nameof(StatusTitle)); Changed(nameof(IsBusy)); Changed(nameof(IsOnline)); Changed(nameof(Subtitle)); }
    }

    public string StatusTitle => Status switch
    {
        StatusKind.Checking => "正在检测…",
        StatusKind.Online => "已联网",
        StatusKind.Captive => "未认证",
        StatusKind.NoNetwork => "没有网络",
        StatusKind.Working => _detail,
        StatusKind.Rejected => "账号被拒",
        _ => "登录失败",
    };

    public string Subtitle => Status is StatusKind.Rejected or StatusKind.Failed
        ? _detail
        : string.IsNullOrEmpty(Username) ? "尚未设置账号" : $"{Username} · {Carrier.DisplayName()}";

    public bool IsBusy => Status is StatusKind.Checking or StatusKind.Working;
    public bool IsOnline => Status == StatusKind.Online;

    void SetStatus(StatusKind kind, string detail = "")
    {
        _detail = detail;
        Status = kind;
    }

    // ---------------------------------------------------------------- 设置

    public string Username => _settings.Username;
    public Carrier Carrier => _settings.Carrier;
    public string Portal => _settings.Portal;
    public string NasIp => string.IsNullOrEmpty(_settings.NasIp) ? "首次登录后自动识别" : _settings.NasIp;
    public bool HasAccount => !string.IsNullOrEmpty(Username) && CredentialStore.Load(Username) != null;
    public string Password => CredentialStore.Load(Username) ?? "";

    public bool KeepOnline
    {
        get => _settings.KeepOnline;
        set
        {
            if (_settings.KeepOnline == value) return;
            _settings.KeepOnline = value;
            _settings.Save();
            Changed();
            if (value) StartMonitor(); else StopMonitor();
        }
    }

    public bool LaunchAtLogin
    {
        get => AutoStart.IsEnabled;
        set
        {
            try { AutoStart.Set(value); }
            catch (Exception e) { Record("设置开机启动失败：" + e.Message, true); }
            Changed();
        }
    }

    public void SaveAccount(string username, string password, Carrier carrier, string portal)
    {
        username = username.Trim();
        if (!Uri.TryCreate(portal.Trim(), UriKind.Absolute, out _)) throw new ArgumentException("认证服务器地址不正确");
        if (!string.IsNullOrEmpty(_settings.Username) && _settings.Username != username) CredentialStore.Delete(_settings.Username);
        if (password.Length > 0) CredentialStore.Save(username, password);
        _settings.Username = username;
        _settings.Carrier = carrier;
        _settings.Portal = portal.Trim();
        _settings.Save();
        Changed(nameof(Username)); Changed(nameof(Carrier)); Changed(nameof(Portal)); Changed(nameof(Subtitle)); Changed(nameof(HasAccount));
        Record($"已保存账号 {username}（{carrier.DisplayName()}）");
    }

    // ---------------------------------------------------------------- 动作

    public async Task RefreshAsync()
    {
        SetStatus(StatusKind.Checking);
        var s = await Connectivity.CheckAsync();
        SetStatus(s.Kind switch
        {
            NetKind.Online => StatusKind.Online,
            NetKind.Captive => StatusKind.Captive,
            _ => StatusKind.NoNetwork,
        });
    }

    public async Task LoginAsync()
    {
        _rejectedFingerprint = null;
        await AttemptLoginAsync();
    }

    public async Task LogoutAsync()
    {
        SetStatus(StatusKind.Working, "正在下线…");
        KeepOnline = false; // 否则马上又被自动登录
        try
        {
            await Login.LogoutAsync(PortalUri, _settings.NasIp);
            Record("已下线，已暂停自动保持在线");
        }
        catch (Exception e) when (e is PortalException or HttpRequestException or TaskCanceledException)
        {
            Record($"下线失败：{e.Message}。可在自助服务中心手动下线", true);
        }
        await RefreshAsync();
    }

    public void OpenLog()
    {
        if (!File.Exists(_logPath)) File.WriteAllText(_logPath, "");
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(_logPath) { UseShellExecute = true });
    }

    public void OpenSelfService() =>
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(Portal.TrimEnd('/') + "/self/index") { UseShellExecute = true });

    // ---------------------------------------------------------------- 守护

    /// <summary>打断当前等待，立刻检查一轮。</summary>
    public void Poke()
    {
        if (_monitor != null) _nap.Cancel(); else _ = RefreshAsync();
    }

    void StartMonitor()
    {
        if (_monitor != null) return;
        _monitor = new CancellationTokenSource();
        var token = _monitor.Token;
        _ = Task.Run(async () =>
        {
            var backoff = 0.0;
            while (!token.IsCancellationRequested)
            {
                var (delay, next) = await UiAsync(() => TickAsync(backoff));
                backoff = next;
                _nap = CancellationTokenSource.CreateLinkedTokenSource(token);
                try { await Task.Delay(TimeSpan.FromSeconds(delay), _nap.Token); }
                catch (TaskCanceledException) { }
            }
        }, token);
    }

    void StopMonitor()
    {
        _monitor?.Cancel();
        _monitor = null;
        _ = RefreshAsync();
    }

    /// <summary>一轮检查，返回（距离下一轮的秒数，新的退避值）。</summary>
    async Task<(double, double)> TickAsync(double backoff)
    {
        if (_rejectedFingerprint != null)
        {
            if (_rejectedFingerprint == Fingerprint()) return (30, backoff); // 账号没改就不重试，防止锁号
            _rejectedFingerprint = null;
        }
        await RefreshAsync();
        if (Status == StatusKind.Online) return (60, 0);
        if (!HasAccount) return (30, backoff);
        if (await AttemptLoginAsync()) return (60, 0);
        if (Status == StatusKind.Rejected) { _rejectedFingerprint = Fingerprint(); return (30, backoff); }
        var next = Math.Min(Math.Max(backoff * 2, 10), 300);
        return (next, next);
    }

    async Task<bool> AttemptLoginAsync()
    {
        if (!HasAccount)
        {
            SetStatus(StatusKind.Failed, "请先填写学号和密码");
            return false;
        }
        SetStatus(StatusKind.Working, "正在登录…");
        try
        {
            var outcome = await Login.RunAsync(new Credentials(Username, Password, Carrier), PortalUri, _settings.NasIp);
            if (outcome.LearnedNas != null || outcome.Portal != PortalUri)
            {
                _settings.NasIp = outcome.LearnedNas ?? _settings.NasIp;
                _settings.Portal = outcome.Portal.ToString();
                _settings.Save();
                Changed(nameof(NasIp)); Changed(nameof(Portal));
            }
            Record(outcome.Message);
            if (outcome.Carrier != null) Notify?.Invoke("校园网已连接", outcome.Message, false);
            await RefreshAsync();
            return Status == StatusKind.Online || outcome.Carrier != null;
        }
        catch (AuthRejectedException e)
        {
            SetStatus(StatusKind.Rejected, e.Message);
            Record(e.Message + "。已停止自动重试，请检查密码或运营商", true);
            Notify?.Invoke("校园网登录被拒", e.Message, true);
            return false;
        }
        catch (Exception e) when (e is PortalException or HttpRequestException or TaskCanceledException)
        {
            SetStatus(StatusKind.Failed, e.Message);
            Record(e.Message, true);
            return false;
        }
    }

    Uri PortalUri => Uri.TryCreate(Portal, UriKind.Absolute, out var u) ? u : PortalClient.DefaultPortal;

    string Fingerprint() => $"{Username}|{Carrier}|{Password.GetHashCode()}";

    // ---------------------------------------------------------------- 工具

    void Record(string text, bool isError = false)
    {
        Activity.Insert(0, new ActivityEntry(DateTime.Now, text, isError));
        while (Activity.Count > 50) Activity.RemoveAt(Activity.Count - 1);
        try { File.AppendAllText(_logPath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {(isError ? "ERROR" : "INFO ")} {text}{Environment.NewLine}"); }
        catch (IOException) { }
    }

    void Changed([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    static void Ui(Action a) => Application.Current?.Dispatcher.BeginInvoke(a);

    static Task<T> UiAsync<T>(Func<Task<T>> f) => Application.Current.Dispatcher.InvokeAsync(f).Task.Unwrap();
}
