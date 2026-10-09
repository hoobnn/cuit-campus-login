using System.Security.Cryptography;
using System.Text;

namespace CUITNet.Core;

/// <summary>门户前端 CryptoJS 的 AES.encrypt(text, Base64.parse(key), {mode: ECB, padding: Pkcs7})。</summary>
public static class PortalCrypto
{
    public static string Encrypt(string keyBase64, string text)
    {
        byte[] key;
        try { key = Convert.FromBase64String(keyBase64); }
        catch (FormatException) { throw new PortalException("门户下发的 AES 密钥格式不对"); }
        if (key.Length != 16) throw new PortalException("门户下发的 AES 密钥长度不对");
        using var aes = Aes.Create();
        aes.Key = key;
        return Convert.ToBase64String(aes.EncryptEcb(Encoding.UTF8.GetBytes(text), PaddingMode.PKCS7));
    }
}
