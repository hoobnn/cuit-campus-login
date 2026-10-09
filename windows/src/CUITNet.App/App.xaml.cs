using System.Threading;
using System.Windows;

namespace CUITNet.App;

public partial class App : Application
{
    const string InstanceName = "com.ikuyu.cuitnet.SingleInstance";
    Mutex? _mutex;
    EventWaitHandle? _showSignal;
    TrayIcon? _tray;
    MainWindow? _window;

    public AppModel Model { get; private set; } = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // 单实例：再次启动时只把已有实例的窗口叫出来
        _mutex = new Mutex(true, InstanceName, out var first);
        _showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, InstanceName + ".Show");
        if (!first)
        {
            _showSignal.Set();
            Shutdown();
            return;
        }
        new Thread(() =>
        {
            while (_showSignal.WaitOne()) Dispatcher.BeginInvoke(ShowMainWindow);
        }) { IsBackground = true }.Start();

        Model = new AppModel();
        _tray = new TrayIcon(Model, ShowMainWindow, Quit);

        var background = e.Args.Contains("--background");
        if (!background || !Model.HasAccount) ShowMainWindow();
    }

    public void ShowMainWindow()
    {
        _window ??= new MainWindow(Model);
        _window.Show();
        if (_window.WindowState == WindowState.Minimized) _window.WindowState = WindowState.Normal;
        _window.Activate();
    }

    /// <summary>关闭窗口只是隐藏到托盘，第一次时提示一下。</summary>
    public void HiddenToTray() => _tray?.HintOnce();

    public void Quit()
    {
        _tray?.Dispose();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        _mutex?.Dispose();
        base.OnExit(e);
    }
}
