#if canImport(CryptoKit)
import CryptoKit
#else
import CCryptoBoringSSL
import Crypto
#endif
import Foundation

/// Ed25519 sobre o CryptoKit. Solana, Stellar e TON.
///
/// O CryptoKit aleatoriza a assinatura Ed25519 (uma assinatura diferente a cada
/// chamada, todas validas pela RFC 8032). Para as redes isso nao muda nada: o no
/// confere a assinatura, nao a compara com outra. O que muda e o teste: vetores de
/// transacao assinada sao conferidos pela verificacao, e a mensagem assinada e
/// comparada byte a byte.
public enum Ed25519 {
    public enum Failure: Error { case invalidSeed, invalidPublicKey }

    public static func publicKey(of seed: SecureBytes) throws -> [UInt8] {
        guard seed.count == 32 else { throw Failure.invalidSeed }
        let key = try seed.withUnsafeBytes { try Curve25519.Signing.PrivateKey(rawRepresentation: $0) }
        return Array(key.publicKey.rawRepresentation)
    }

    public static func sign(_ message: [UInt8], seed: SecureBytes) throws -> [UInt8] {
        guard seed.count == 32 else { throw Failure.invalidSeed }
        let key = try seed.withUnsafeBytes { try Curve25519.Signing.PrivateKey(rawRepresentation: $0) }
        return Array(try key.signature(for: message))
    }

    /// A assinatura de verdade. No iPhone, a do CryptoKit, que ja sorteia. No Android, a da BoringSSL e deterministica
    /// (RFC 8032 puro); com `hedged`, ela passa pela conta da chave estendida, a mesma do Ed25519 (kL = SHA-512 da seed
    /// com o clamp, kR o resto), com 32 bytes do gerador no nonce (auditoria das chaves de 06/11/2026). Sem os bytes do
    /// gerador, essa conta da o RFC 8032 byte a byte; a rede confere a assinatura, nunca como r nasceu.
    public static func sign(_ message: [UInt8], seed: SecureBytes, hedged: Bool) throws -> [UInt8] {
        #if canImport(CryptoKit)
        return try sign(message, seed: seed)
        #else
        guard hedged else { return try sign(message, seed: seed) }
        guard seed.count == 32 else { throw Failure.invalidSeed }
        // A chave estendida nasce direto na regiao travada, sem passar por um [UInt8] do heap (revisao final de 07/11/2026).
        let key = SecureBytes(capacity: 64)
        defer { key.wipe() }
        seed.withUnsafeBytes { raw in
            key.fill(count: 64) { destino in
                let bytes = destino.assumingMemoryBound(to: UInt8.self)
                _ = CCryptoBoringSSL_SHA512(raw.bindMemory(to: UInt8.self).baseAddress, raw.count, bytes)
                bytes[0] &= 248
                bytes[31] &= 127
                bytes[31] |= 64
            }
        }
        return try signExtended(message, extendedKey: key, hedged: true)
        #endif
    }

    public static func verify(signature: [UInt8], message: [UInt8], publicKey: [UInt8]) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signature, for: message)
    }
}
