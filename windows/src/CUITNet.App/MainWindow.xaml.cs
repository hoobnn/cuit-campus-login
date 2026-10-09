using System.IO;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Windows;
using System.Windows.Media.Imaging;
using CUITNet.Core;

namespace CUITNet.App;

public partial class MainWindow : Window
{
    public static readonly DependencyProperty HasActivityProperty =
        DependencyProperty.Register(nameof(HasActivity), typeof(bool), typeof(MainWindow));

    readonly AppModel _model;

    public bool HasActivity
    {
        get => (bool)GetValue(HasActivityProperty);
        set => SetValue(HasActivityProperty, value);
    }

    public MainWindow(AppModel model)
    {
        InitializeComponent();
        _model = model;
        DataContext = model;
        try { Logo.Source = new BitmapImage(new Uri("pack://application:,,,/app.png")); }
        catch (IOException) { Logo.Visibility = Visibility.Collapsed; }

        UsernameBox.Text = model.Username;
        PasswordBox.Password = model.Password;
        PortalBox.Text = model.Portal;
        (model.Carrier switch { Carrier.Ctcc => CtccRadio, Carrier.Unicom => UnicomRadio, _ => CmccRadio }).IsChecked = true;

        HasActivity = model.Activity.Count > 0;
        model.Activity.CollectionChanged += (_, _) => HasActivity = model.Activity.Count > 0;
    }

    Carrier SelectedCarrier =>
        CtccRadio.IsChecked == true ? Carrier.Ctcc : UnicomRadio.IsChecked == true ? Carrier.Unicom : Carrier.Cmcc;

    async void Save_Click(object sender, RoutedEventArgs e)
    {
        ErrorText.Text = "";
        if (string.IsNullOrWhiteSpace(UsernameBox.Text) || (PasswordBox.Password.Length == 0 && !_model.HasAccount))
        {
            ErrorText.Text = "请填写学号和密码";
            return;
        }
        try { _model.SaveAccount(UsernameBox.Text, PasswordBox.Password, SelectedCarrier, PortalBox.Text); }
        catch (Exception ex) when (ex is ArgumentException or IOException)
        {
            ErrorText.Text = ex.Message;
            return;
        }
        await _model.LoginAsync();
    }

    async void Logout_Click(object sender, RoutedEventArgs e) => await _model.LogoutAsync();

    async void Refresh_Click(object sender, RoutedEventArgs e) => await _model.RefreshAsync();

    void OpenLog_Click(object sender, RoutedEventArgs e) => _model.OpenLog();

    void SelfService_Click(object sender, RoutedEventArgs e) => _model.OpenSelfService();

    protected override void OnClosing(CancelEventArgs e)
    {
        // 关窗只是隐藏，程序留在托盘里继续保持在线
        e.Cancel = true;
        Hide();
        ((App)Application.Current).HiddenToTray();
        base.OnClosing(e);
    }
}
