import EscaliburChains
import EscaliburCore
import Foundation

/// O nonce das assinaturas deterministicas, conferido no proprio aparelho antes de qualquer assinatura (revisao da decima
/// terceira passada da auditoria de 03/11/2026). E a unica falha de assinatura que entrega a chave: um HMAC mal compilado
/// que ignorasse a mensagem repetiria o nonce em duas transacoes, e a verificacao depois de assinar nao percebe. A chave e o
/// digest errados a assinatura ja recusa (`Signer.sign`), sem este teste.
///
/// Cada esquema tem o seu teste, e um defeito num nao trava os outros:
/// - secp256k1 com o RFC 6979 da libsecp256k1, na forma recuperavel e em DER: d = 1 (bitcoinjs-lib,
///   test/fixtures/ecdsa.json, valid.ecdsa[0]).
/// - Ed25519 da BoringSSL fora da Apple (RFC 8032, 7.1, TEST 2). No iPhone, o CryptoKit sorteia a assinatura, e um valor
///   fixo nao se compara.
/// - A Ed25519 da Cardano (chave estendida, o nonce e o SHA-512 da metade direita com a mensagem), nas duas plataformas: o
///   mesmo TEST 2, pela chave estendida que a RFC tira da semente.
public enum SigningSelfTest {
    public struct Failure: LocalizedError, Sendable {
        public init() {}

        public var errorDescription: String? {
            kitText("Este aparelho calculou uma assinatura de teste diferente da esperada. Por segurança, nada é assinado aqui.")
        }
    }

    enum Scheme: CaseIterable {
        case secp256k1, ed25519, cardano
    }

    static func scheme(_ scheme: SignatureScheme) -> Scheme? {
        switch scheme {
        case .ecdsaDER, .ecdsaRecoverable: return .secp256k1
        case .ed25519: return .ed25519
        case .ed25519Cardano: return .cardano
        // O Signer recusa antes de assinar.
        case .schnorrBIP340: return nil
        }
    }

    /// Os esquemas que o plano assina passam (conferido antes de pedir o PIN e de novo antes de abrir o cofre).
    public static func passed(for plan: SigningPlan) -> Bool {
        Set(plan.transactions.flatMap(\.signingRequests).compactMap { scheme($0.scheme) }).allSatisfy(passed)
    }

    /// Todos os esquemas.
    public static var passed: Bool { Scheme.allCases.allSatisfy(passed) }

    static func passed(_ scheme: Scheme) -> Bool {
        caches[scheme]!.passed {
            do { return try check(scheme) } catch { return nil }
        }
    }

    private static let caches = Dictionary(uniqueKeysWithValues: Scheme.allCases.map { ($0, DerivationSelfTest.Cache()) })

    static let message = "Everything should be made as simple as possible, but not simpler."
    static let compact = "33a69cd2065432a30f3d1ce4eb0d59b8ab58c74f27c41a7fdb5696ad4e6108c96f807982866f785d3f6418d24163ddae117b7db4d5fdf0071de069fa54342262"
    static let der = "3044022033a69cd2065432a30f3d1ce4eb0d59b8ab58c74f27c41a7fdb5696ad4e6108c902206f807982866f785d3f6418d24163ddae117b7db4d5fdf0071de069fa54342262"
    static let ed25519Seed = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
    static let ed25519Signature = "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"

    static func key(_ bytes: [UInt8]) -> SecureBytes {
        let key = SecureBytes(capacity: bytes.count)
        key.replaceAll(with: bytes)
        return key
    }

    static func check(_ scheme: Scheme) throws -> Bool {
        switch scheme {
        case .secp256k1:
            let one = key([UInt8](repeating: 0, count: 31) + [1])
            defer { one.wipe() }
            let digest = Hash.sha256(Array(message.utf8))
            guard Hex.encode(try Secp256k1.signRecoverable(digest: digest, privateKey: one).compact) == compact else { return false }
            return Hex.encode(try Secp256k1.signDER(digest: digest, privateKey: one)) == der
        case .ed25519:
            #if canImport(CryptoKit)
            return true
            #else
            guard let seedBytes = Hex.decode(ed25519Seed) else { return false }
            let seed = key(seedBytes)
            defer { seed.wipe() }
            return Hex.encode(try Ed25519.sign([0x72], seed: seed)) == ed25519Signature
            #endif
        case .cardano:
            // A chave estendida kL || kR como a RFC 8032 tira da semente.
            guard let seedBytes = Hex.decode(ed25519Seed) else { return false }
            var digest = Hash.sha512(seedBytes)
            digest[0] &= 248
            digest[31] &= 127
            digest[31] |= 64
            let extended = key(digest)
            digest.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
            defer { extended.wipe() }
            return Hex.encode(try Ed25519.signExtended([0x72], extendedKey: extended)) == ed25519Signature
        }
    }
}
