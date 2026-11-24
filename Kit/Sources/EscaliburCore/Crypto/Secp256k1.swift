import CSecp256k1
import Foundation

/// A curva secp256k1, sobre o libsecp256k1 do bitcoin-core.
///
/// Toda chave privada entra aqui como `SecureBytes` e nunca vira `Data` ou `[UInt8]`
/// no caminho. As assinaturas ECDSA saem em forma low-S, que e o que Bitcoin, Ethereum,
/// XRP Ledger e Tron exigem; a biblioteca garante isso por construcao, e os testes conferem.
/// O nonce e o do RFC 6979; na assinatura de verdade (`hedged`) ele leva tambem 32 bytes do
/// gerador do sistema, e os vetores fixos (testes e `SigningSelfTest`) assinam sem eles.
public enum Secp256k1 {
    public enum Failure: Error, Equatable {
        case invalidPrivateKey
        case invalidPublicKey
        case invalidTweak
        case signingFailed
    }

    /// O contexto e criado uma vez e aleatorizado com o gerador do sistema, que e a
    /// protecao da biblioteca contra canal lateral de tempo e consumo. Depois disso
    /// ele e so leitura e pode ser usado de qualquer thread.
    nonisolated(unsafe) private static let context: OpaquePointer = {
        guard let ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_NONE)) else {
            fatalError("secp256k1: contexto indisponivel")
        }
        var seed = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &seed) == errSecSuccess,
              secp256k1_context_randomize(ctx, seed) == 1
        else {
            fatalError("secp256k1: aleatorizacao do contexto falhou")
        }
        seed.resetBytes()
        return ctx
    }()

    // MARK: Chaves

    public static func isValidPrivateKey(_ key: SecureBytes) -> Bool {
        guard key.count == 32 else { return false }
        return key.withUnsafeBytes { raw in
            secp256k1_ec_seckey_verify(context, raw.bindMemory(to: UInt8.self).baseAddress!) == 1
        }
    }

    public static func publicKey(of privateKey: SecureBytes, compressed: Bool = true) throws -> [UInt8] {
        guard privateKey.count == 32 else { throw Failure.invalidPrivateKey }
        var pubkey = secp256k1_pubkey()
        let ok = privateKey.withUnsafeBytes { raw in
            secp256k1_ec_pubkey_create(context, &pubkey, raw.bindMemory(to: UInt8.self).baseAddress!)
        }
        guard ok == 1 else { throw Failure.invalidPrivateKey }
        return serialize(&pubkey, compressed: compressed)
    }

    /// Converte entre forma comprimida (33) e expandida (65), validando o ponto.
    public static func reformat(publicKey: [UInt8], compressed: Bool) throws -> [UInt8] {
        var pubkey = try parse(publicKey)
        return serialize(&pubkey, compressed: compressed)
    }

    /// `key = key + tweak (mod n)`, no lugar. E o passo da derivacao BIP-32.
    public static func tweakAdd(privateKey: SecureBytes, tweak: UnsafeRawBufferPointer) throws {
        guard privateKey.count == 32, tweak.count == 32 else { throw Failure.invalidTweak }
        var scratch = [UInt8](repeating: 0, count: 32)
        defer { scratch.resetBytes() }
        privateKey.withUnsafeBytes { raw in
            for i in 0..<32 { scratch[i] = raw[i] }
        }
        let ok = secp256k1_ec_seckey_tweak_add(context, &scratch, tweak.bindMemory(to: UInt8.self).baseAddress!)
        guard ok == 1 else { throw Failure.invalidTweak }
        privateKey.replaceAll(with: scratch)
    }

    /// `P = P + tweak * G`. Derivacao publica, para enderecos de so leitura.
    public static func tweakAdd(publicKey: [UInt8], tweak: [UInt8]) throws -> [UInt8] {
        guard tweak.count == 32 else { throw Failure.invalidTweak }
        var pubkey = try parse(publicKey)
        guard secp256k1_ec_pubkey_tweak_add(context, &pubkey, tweak) == 1 else { throw Failure.invalidTweak }
        return serialize(&pubkey, compressed: true)
    }

    // MARK: Assinatura

    /// O contexto e o `ndata` de uma assinatura. Com `hedged` (auditoria das chaves de 06/11/2026): um
    /// contexto so desta assinatura, aleatorizado com 32 bytes novos e destruido no fim (a biblioteca zera
    /// o cegamento), e 32 bytes do gerador do sistema somados ao nonce do RFC 6979. Duas assinaturas do
    /// mesmo digesto nunca usam o mesmo nonce, uma falha induzida numa delas nao se combina com outra, e quem mede o consumo do aparelho
    /// nunca ve a mesma conta duas vezes sobre o mesmo digesto. A rede nao confere como o nonce nasceu, e
    /// toda assinatura e conferida antes de sair. Sem `hedged`: o contexto comum e o RFC 6979 puro.
    private static func withSigning<T>(hedged: Bool, _ body: (OpaquePointer, UnsafeRawPointer?) throws -> T) throws -> T {
        guard hedged else { return try body(context, nil) }
        guard let own = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_NONE)) else { throw Failure.signingFailed }
        defer { secp256k1_context_destroy(own) }
        let seed = try SecureBytes.random(count: 32)
        defer { seed.wipe() }
        let extra = try SecureBytes.random(count: 32)
        defer { extra.wipe() }
        return try seed.withUnsafeBytes { seedRaw in
            guard secp256k1_context_randomize(own, seedRaw.bindMemory(to: UInt8.self).baseAddress!) == 1 else {
                throw Failure.signingFailed
            }
            return try extra.withUnsafeBytes { extraRaw in try body(own, extraRaw.baseAddress!) }
        }
    }

    /// Assinatura recuperavel: `r || s` em 64 bytes e o identificador de
    /// recuperacao (0 a 3). Ethereum, Tron e mensagens assinadas usam esta forma.
    public static func signRecoverable(digest: [UInt8], privateKey: SecureBytes) throws -> (compact: [UInt8], recoveryID: UInt8) {
        try signRecoverable(digest: digest, privateKey: privateKey, hedged: false)
    }

    public static func signRecoverable(digest: [UInt8], privateKey: SecureBytes, hedged: Bool) throws -> (compact: [UInt8], recoveryID: UInt8) {
        guard digest.count == 32 else { throw Failure.signingFailed }
        guard privateKey.count == 32 else { throw Failure.invalidPrivateKey }
        var signature = secp256k1_ecdsa_recoverable_signature()
        let ok = try withSigning(hedged: hedged) { ctx, extra in
            privateKey.withUnsafeBytes { raw in
                secp256k1_ecdsa_sign_recoverable(
                    ctx, &signature, digest, raw.bindMemory(to: UInt8.self).baseAddress!, nil, extra
                )
            }
        }
        guard ok == 1 else { throw Failure.signingFailed }
        var output = [UInt8](repeating: 0, count: 64)
        var recid: Int32 = 0
        secp256k1_ecdsa_recoverable_signature_serialize_compact(context, &output, &recid, &signature)
        return (output, UInt8(recid))
    }

    /// Assinatura ECDSA em DER, low-S. Bitcoin, Litecoin, Dogecoin e XRP Ledger.
    public static func signDER(digest: [UInt8], privateKey: SecureBytes) throws -> [UInt8] {
        try signDER(digest: digest, privateKey: privateKey, hedged: false)
    }

    public static func signDER(digest: [UInt8], privateKey: SecureBytes, hedged: Bool) throws -> [UInt8] {
        guard digest.count == 32 else { throw Failure.signingFailed }
        guard privateKey.count == 32 else { throw Failure.invalidPrivateKey }
        var signature = secp256k1_ecdsa_signature()
        let ok = try withSigning(hedged: hedged) { ctx, extra in
            privateKey.withUnsafeBytes { raw in
                secp256k1_ecdsa_sign(ctx, &signature, digest, raw.bindMemory(to: UInt8.self).baseAddress!, nil, extra)
            }
        }
        guard ok == 1 else { throw Failure.signingFailed }
        var output = [UInt8](repeating: 0, count: 72)
        var length = output.count
        secp256k1_ecdsa_signature_serialize_der(context, &output, &length, &signature)
        return Array(output.prefix(length))
    }

    /// Recupera a chave publica (expandida, 65 bytes) de uma assinatura recuperavel.
    /// Usado para conferir, antes de transmitir, que a assinatura e da conta certa.
    public static func recover(digest: [UInt8], compact: [UInt8], recoveryID: UInt8, compressed: Bool = false) throws -> [UInt8] {
        guard digest.count == 32, compact.count == 64, recoveryID < 4 else { throw Failure.invalidPublicKey }
        var signature = secp256k1_ecdsa_recoverable_signature()
        guard secp256k1_ecdsa_recoverable_signature_parse_compact(context, &signature, compact, Int32(recoveryID)) == 1 else {
            throw Failure.invalidPublicKey
        }
        var pubkey = secp256k1_pubkey()
        guard secp256k1_ecdsa_recover(context, &pubkey, &signature, digest) == 1 else { throw Failure.invalidPublicKey }
        return serialize(&pubkey, compressed: compressed)
    }

    /// Confere uma assinatura DER. So aceita a forma low-S, como os nos das redes.
    public static func verifyDER(signature der: [UInt8], digest: [UInt8], publicKey: [UInt8]) -> Bool {
        guard digest.count == 32, var pubkey = try? parse(publicKey) else { return false }
        var signature = secp256k1_ecdsa_signature()
        guard secp256k1_ecdsa_signature_parse_der(context, &signature, der, der.count) == 1 else { return false }
        return secp256k1_ecdsa_verify(context, &signature, digest, &pubkey) == 1
    }

    // MARK: Schnorr (BIP-340)

    /// Chave publica x-only (32 bytes) de uma chave privada.
    public static func xOnlyPublicKey(of privateKey: SecureBytes) throws -> [UInt8] {
        var keypair = secp256k1_keypair()
        let ok = privateKey.withUnsafeBytes { raw in
            secp256k1_keypair_create(context, &keypair, raw.bindMemory(to: UInt8.self).baseAddress!)
        }
        guard ok == 1 else { throw Failure.invalidPrivateKey }
        var xonly = secp256k1_xonly_pubkey()
        var parity: Int32 = 0
        secp256k1_keypair_xonly_pub(context, &xonly, &parity, &keypair)
        var out = [UInt8](repeating: 0, count: 32)
        secp256k1_xonly_pubkey_serialize(context, &out, &xonly)
        return out
    }

    // MARK: Interno

    private static func parse(_ bytes: [UInt8]) throws -> secp256k1_pubkey {
        var pubkey = secp256k1_pubkey()
        guard bytes.count == 33 || bytes.count == 65,
              secp256k1_ec_pubkey_parse(context, &pubkey, bytes, bytes.count) == 1
        else { throw Failure.invalidPublicKey }
        return pubkey
    }

    private static func serialize(_ pubkey: inout secp256k1_pubkey, compressed: Bool) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: compressed ? 33 : 65)
        var length = output.count
        secp256k1_ec_pubkey_serialize(
            context, &output, &length, &pubkey,
            UInt32(compressed ? SECP256K1_EC_COMPRESSED : SECP256K1_EC_UNCOMPRESSED)
        )
        return output
    }
}
