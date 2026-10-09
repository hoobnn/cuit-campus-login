using System.ComponentModel;
using System.Drawing;
using System.Windows.Forms;
using CUITNet.Core;

namespace CUITNet.App;

/// <summary>任务栏通知区域图标：显示状态，右键菜单快速登录 / 下线。</summary>
public sealed class TrayIcon : IDisposable
{
    readonly NotifyIcon _icon;
    readonly AppModel _model;
    readonly ToolStripMenuItem _status = new() { Enabled = false };
    readonly ToolStripMenuItem _login;
    readonly ToolStripMenuItem _logout;
    bool _hinted;

    public TrayIcon(AppModel model, Action show, Action quit)
    {
        _model = model;
        _login = new ToolStripMenuItem("立即登录", null, async (_, _) => await model.LoginAsync());
        _logout = new ToolStripMenuItem("下线", null, async (_, _) => await model.LogoutAsync());
        var menu = new ContextMenuStrip();
        menu.Items.AddRange([
            _status,
            new ToolStripSeparator(),
            _login,
            _logout,
            new ToolStripSeparator(),
            new ToolStripMenuItem("打开主界面", null, (_, _) => show()),
            new ToolStripMenuItem("退出", null, (_, _) => quit()),
        ]);
        _icon = new NotifyIcon
        {
            Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? SystemIcons.Application,
            ContextMenuStrip = menu,
            Visible = true,
        };
        _icon.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) show(); };
        model.PropertyChanged += OnModelChanged;
        model.Notify += (title, text, error) =>
            _icon.ShowBalloonTip(5000, title, text, error ? ToolTipIcon.Warning : ToolTipIcon.Info);
        Update();
    }

    void OnModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppModel.Status) or nameof(AppModel.Subtitle)) Update();
    }

    void Update()
    {
        var text = $"CUIT 校园网 · {_model.StatusTitle}";
        _icon.Text = text.Length > 63 ? text[..63] : text; // NotifyIcon.Text 上限 63 字符
        _status.Text = _model.StatusTitle;
        _login.Enabled = !_model.IsBusy && !_model.IsOnline;
        _logout.Enabled = !_model.IsBusy && _model.IsOnline;
    }

    public void HintOnce()
    {
        if (_hinted) return;
        _hinted = true;
        _icon.ShowBalloonTip(3000, "CUIT 校园网仍在运行", "会在后台保持在线。右键托盘图标可以退出。", ToolTipIcon.Info);
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
