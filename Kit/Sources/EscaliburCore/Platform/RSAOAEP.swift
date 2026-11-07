// So no build Android: o embrulho do slot de biometria, feito no nucleo sobre a BoringSSL.
#if !canImport(Darwin)
import CCryptoBoringSSL
import Foundation

/// RSA-OAEP com SHA-256, MGF1 com SHA-1 e sem rotulo, sobre uma chave publica X.509: o par que o Keystore
/// aceita em todo Android 11+ (Cofre.kt, `oaep`). E como o nucleo embrulha a chave AES do slot de biometria
/// sem que ela passe pelo Java (auditoria das chaves de 06/11/2026). Abrir fica com o Keystore, depois da
/// biometria. A BoringSSL zera os buffers de padding no `OPENSSL_free`.
public enum RSAOAEP {
    public enum Failure: Error, Equatable {
        case invalidPublicKey
        case encryptionFailed
    }

    public static func encrypt(_ secret: SecureBytes, publicKeyDER: [UInt8]) throws -> [UInt8] {
        let key: OpaquePointer = try publicKeyDER.withUnsafeBufferPointer { der in
            var cbs = CBS()
            CCryptoBoringSSL_CBS_init(&cbs, der.baseAddress, der.count)
            guard let key = CCryptoBoringSSL_EVP_parse_public_key(&cbs) else { throw Failure.invalidPublicKey }
            guard CCryptoBoringSSL_CBS_len(&cbs) == 0, CCryptoBoringSSL_EVP_PKEY_id(key) == EVP_PKEY_RSA,
                  CCryptoBoringSSL_EVP_PKEY_bits(key) >= 2048
            else {
                CCryptoBoringSSL_EVP_PKEY_free(key)
                throw Failure.invalidPublicKey
            }
            return key
        }
        defer { CCryptoBoringSSL_EVP_PKEY_free(key) }
        guard let context = CCryptoBoringSSL_EVP_PKEY_CTX_new(key, nil) else { throw Failure.encryptionFailed }
        defer { CCryptoBoringSSL_EVP_PKEY_CTX_free(context) }
        guard CCryptoBoringSSL_EVP_PKEY_encrypt_init(context) == 1,
              CCryptoBoringSSL_EVP_PKEY_CTX_set_rsa_padding(context, RSA_PKCS1_OAEP_PADDING) == 1,
              CCryptoBoringSSL_EVP_PKEY_CTX_set_rsa_oaep_md(context, CCryptoBoringSSL_EVP_sha256()) == 1,
              CCryptoBoringSSL_EVP_PKEY_CTX_set_rsa_mgf1_md(context, CCryptoBoringSSL_EVP_sha1()) == 1
        else { throw Failure.encryptionFailed }
        return try secret.withUnsafeBytes { plain in
            let input = plain.bindMemory(to: UInt8.self).baseAddress
            var length = 0
            guard CCryptoBoringSSL_EVP_PKEY_encrypt(context, nil, &length, input, plain.count) == 1, length > 0 else {
                throw Failure.encryptionFailed
            }
            var output = [UInt8](repeating: 0, count: length)
            guard CCryptoBoringSSL_EVP_PKEY_encrypt(context, &output, &length, input, plain.count) == 1 else {
                throw Failure.encryptionFailed
            }
            return Array(output.prefix(length))
        }
    }
}
#endif
