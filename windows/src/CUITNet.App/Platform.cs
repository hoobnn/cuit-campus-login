using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using CUITNet.Core;
using Microsoft.Win32;

namespace CUITNet.App;

public sealed class Settings
{
    public string Username { get; set; } = "";
    public Carrier Carrier { get; set; } = Carrier.Cmcc;
    public string Portal { get; set; } = PortalClient.DefaultPortal.ToString();
    public string NasIp { get; set; } = "";
    public bool KeepOnline { get; set; } = true;

    public static string Dir
    {
        get
        {
            var d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CUITNet");
            Directory.CreateDirectory(d);
            return d;
        }
    }

    static string FilePath => Path.Combine(Dir, "settings.json");

    public static Settings Load()
    {
        try { return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new(); }
        catch (Exception e) when (e is IOException or JsonException) { return new(); }
    }

    public void Save()
    {
        var tmp = FilePath + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(tmp, FilePath, overwrite: true);
    }
}

/// <summary>密码存进 Windows 凭据管理器（普通凭据，目标名 CUITNet:学号）。</summary>
public static class CredentialStore
{
    static string Target(string user) => "CUITNet:" + user;

    public static void Save(string user, string password)
    {
        var blob = Encoding.Unicode.GetBytes(password);
        var ptr = Marshal.AllocHGlobal(blob.Length);
        try
        {
            Marshal.Copy(blob, 0, ptr, blob.Length);
            var cred = new CREDENTIAL
            {
                Type = 1, // CRED_TYPE_GENERIC
                TargetName = Target(user),
                UserName = user,
                CredentialBlob = ptr,
                CredentialBlobSize = (uint)blob.Length,
                Persist = 2, // CRED_PERSIST_LOCAL_MACHINE
            };
            if (!CredWrite(ref cred, 0)) throw new IOException("写入凭据管理器失败：" + Marshal.GetLastWin32Error());
        }
        finally { Marshal.FreeHGlobal(ptr); }
    }

    public static string? Load(string user)
    {
        if (string.IsNullOrEmpty(user) || !CredRead(Target(user), 1, 0, out var p)) return null;
        try
        {
            var c = Marshal.PtrToStructure<CREDENTIAL>(p);
            return c.CredentialBlobSize == 0 ? "" : Marshal.PtrToStringUni(c.CredentialBlob, (int)c.CredentialBlobSize / 2);
        }
        finally { CredFree(p); }
    }

    public static void Delete(string user)
    {
        if (!string.IsNullOrEmpty(user)) CredDelete(Target(user), 1, 0);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct CREDENTIAL
    {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredWrite(ref CREDENTIAL credential, uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredDelete(string target, uint type, uint flags);

    [DllImport("advapi32.dll")]
    static extern void CredFree(IntPtr buffer);
}

/// <summary>开机自启：HKCU Run 键，无需管理员权限。</summary>
public static class AutoStart
{
    const string Key = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string Name = "CUITNet";

    static string Command => $"\"{Environment.ProcessPath}\" --background";

    public static bool IsEnabled
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(Key);
            return k?.GetValue(Name) is string v && v == Command;
        }
    }

    public static void Set(bool on)
    {
        using var k = Registry.CurrentUser.CreateSubKey(Key);
        if (on) k.SetValue(Name, Command);
        else k.DeleteValue(Name, throwOnMissingValue: false);
    }
}
