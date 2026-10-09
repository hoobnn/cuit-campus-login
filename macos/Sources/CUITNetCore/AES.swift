import CommonCrypto
import Foundation

/// 门户前端 CryptoJS 的 `AES.encrypt(text, Base64.parse(key), {mode: ECB, padding: Pkcs7}).toString()`。
public enum PortalCrypto {
    public static func encrypt(keyBase64: String, text: String) throws -> String {
        guard let key = Data(base64Encoded: keyBase64), key.count == kCCKeySizeAES128 else {
            throw PortalError.unexpected("门户下发的 AES 密钥格式不对")
        }
        let input = Data(text.utf8)
        var output = Data(count: input.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inp in
                key.withUnsafeBytes { k in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                            k.baseAddress, key.count, nil,
                            inp.baseAddress, input.count,
                            out.baseAddress, outputCapacity, &written)
                }
            }
        }
        guard status == kCCSuccess else { throw PortalError.unexpected("AES 加密失败（\(status)）") }
        return output.prefix(written).base64EncodedString()
    }
}
