#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import EscaliburCore
import Foundation

/// O segredo de uma carteira: a entropia BIP-39, o idioma e a 25a palavra.
///
/// Guarda-se a entropia (16 a 32 bytes), nao as palavras: e o menor segredo que
/// reconstroi a frase e a seed, e o registro fica do mesmo tamanho para qualquer
/// carteira. A 25a palavra nunca e guardada (pedido do dono, 05/11/2026): ela so existe
/// aqui durante uma operacao, digitada pelo dono (`PassphraseProof`).
public struct WalletSecret: Sendable {
    public let entropy: SecureBytes
    public let language: BIP39Language
    public let passphrase: SecureBytes

    public init(entropy: SecureBytes, language: BIP39Language, passphrase: SecureBytes) {
        self.entropy = entropy
        self.language = language
        self.passphrase = passphrase
    }

    /// A partir de uma frase ja canonica e validada. A 25a palavra entra numa copia propria, ja em
    /// NFKD: a seed de hoje e a de qualquer outra carteira BIP-39 sao a mesma, e derivar nunca precisa
    /// normalizar de novo. A de quem chama sai zerada: o segredo nunca divide o buffer com quem chama,
    /// e zera-lo depois nao muda a carteira (revisao de blockchain de 05/11/2026: no Android, o buffer
    /// ASCII era o mesmo, e o zerar de depois gravava a carteira de base).
    public static func from(phrase: SecureBytes, language: BIP39Language, passphrase: SecureBytes? = nil) throws -> WalletSecret {
        let entropy = try BIP39.entropy(fromPhrase: phrase, language: language)
        let stored = passphrase.map(BIP39.nfkd) ?? SecureBytes(capacity: 1)
        passphrase?.wipe()
        return WalletSecret(entropy: entropy, language: language, passphrase: stored)
    }

    /// A passphrase de um envelope de antes: a que uma versao anterior gravou fora de NFKD (com acento
    /// composto) deu a conta da Cardano pelos bytes como estao, e a carteira importada tem de dar a mesma.
    /// Devolve o segredo com esses bytes (a raiz e as outras redes normalizam sozinhas) e se era o caso;
    /// fora dele, o `from` de sempre, em NFKD. A passphrase entra numa copia propria, e a de quem chama sai zerada.
    public static func fromEnvelope(phrase: SecureBytes, language: BIP39Language, passphrase: SecureBytes) throws -> (secret: WalletSecret, legacy: Bool) {
        let normalized = BIP39.nfkd(passphrase)
        let legacy = passphrase.count > 0 && !Hash.constantTimeEqual(normalized, passphrase)
        normalized.wipe()
        guard legacy else { return (try from(phrase: phrase, language: language, passphrase: passphrase), false) }
        let entropy = try BIP39.entropy(fromPhrase: phrase, language: language)
        // Uma copia propria, como no `from`: a de quem chama sai zerada.
        let own = SecureBytes(capacity: passphrase.count)
        passphrase.withUnsafeBytes { own.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        passphrase.wipe()
        return (WalletSecret(entropy: entropy, language: language, passphrase: own), true)
    }

    public func phrase() throws -> SecureBytes {
        try BIP39.phrase(fromEntropy: entropy, language: language)
    }

    /// A seed de 64 bytes. A 25a palavra entra aqui, sempre.
    public func seed() throws -> SecureBytes {
        let words = try phrase()
        defer { words.wipe() }
        return try BIP39.seed(phrase: words, passphrase: passphrase)
    }

    public func wipe() {
        entropy.wipe()
        passphrase.wipe()
    }
}

/// Um cofre por carteira: DEK propria, embrulhada por uma chave derivada da RK.
///
/// ```
/// RK ─HKDF(salt_w, "…/v1/dek" ‖ id)─► KEK_w ─► DEK_w ─HKDF(salt_s, "…/v1/seed")─► registro
/// ```
///
/// Com uma DEK por carteira: trocar o PIN nao toca nenhum registro, apagar uma
/// carteira destroi so a dela, e uma camada extra numa carteira (carteira-cofre) nao
/// muda as outras. Cada gravacao sorteia salts novos, entao a chave de cada cifra
/// nunca se repete e o nonce fixo em zero e seguro, como no formato do Escalibur.
public final class WalletVault: @unchecked Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case notFound
        case corrupted
    }

    static let version: UInt8 = 1
    static let recordLength = 320
    /// O tamanho maximo da passphrase digitada, depois do NFKD. Nao e mais um limite do registro
    /// (ela nao e gravada), e continua o mesmo para quem ja tem uma.
    public static let maxPassphraseBytes = 256

    let store: any SecretStore

    public init(store: any SecretStore) {
        self.store = store
    }

    static func account(_ id: UUID) -> String { "seed.\(id.uuidString.lowercased())" }

    public func exists(_ id: UUID) -> Bool { store.exists(Self.account(id)) }

    /// Existe, nao existe, ou o chaveiro nao conseguiu dizer.
    public func probe(_ id: UUID) -> ItemState { store.probe(Self.account(id)) }

    public func delete(_ id: UUID) throws { try store.delete(Self.account(id)) }

    // MARK: Gravar

    /// Grava a entropia e o idioma. A passphrase do `secret` nunca entra no registro (pedido do
    /// dono, 05/11/2026): o tamanho dela vai zero, e o lugar dela, preenchido com zeros como o resto.
    public func save(_ secret: WalletSecret, walletID: UUID, rk: SecureBytes) throws {
        let blob = try sealedBlob(secret, walletID: walletID, rk: rk)
        let account = Self.account(walletID)
        if store.exists(account) {
            try store.update(blob, account: account)
        } else {
            try store.add(blob, account: account, protection: .standard, context: nil)
        }
    }

    /// O registro cifrado, sem gravar.
    private func sealedBlob(_ secret: WalletSecret, walletID: UUID, rk: SecureBytes) throws -> Data {
        let record = SecureBytes(capacity: Self.recordLength)
        record.append(Self.version)
        record.append(secret.language.storageCode)
        record.append(UInt8(secret.entropy.count))
        secret.entropy.withUnsafeBytes { record.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        UInt16(0).bigEndianByteArray.withUnsafeBufferPointer { record.append(contentsOf: $0) }
        // Tamanho fixo: o registro nao conta quantas palavras a carteira tem.
        while record.count < Self.recordLength { record.append(0) }
        defer { record.wipe() }

        let walletSalt = try Self.randomBytes(32)
        let seedSalt = try Self.randomBytes(32)
        let dek = try SecureBytes.random(count: 32)
        defer { dek.wipe() }

        let kek = Self.kek(rk: rk, salt: walletSalt, walletID: walletID)
        let wrapped = try dek.withUnsafeData {
            try ChaChaPoly.seal($0, using: kek, nonce: Self.zeroNonce, authenticating: Self.aad(walletID, type: 0x01))
        }
        let seedKey = Self.seedKey(dek: dek, salt: seedSalt)
        let sealed = try record.withUnsafeData {
            try ChaChaPoly.seal($0, using: seedKey, nonce: Self.zeroNonce, authenticating: Self.aad(walletID, type: 0x02))
        }

        var blob = Data([Self.version])
        blob += walletSalt
        blob += wrapped.ciphertext + wrapped.tag
        blob += seedSalt
        blob += sealed.ciphertext + sealed.tag
        return blob
    }

    // MARK: Abrir

    /// Abre o registro. Chamar so dentro de uma operacao que zera tudo no fim
    /// (assinar, revelar, exportar): nada daqui fica em memoria entre operacoes.
    ///
    /// A passphrase vem sempre vazia. A que uma versao anterior gravou nao sai do registro aberto,
    /// que e zerado aqui; `purgePassphrase` a tira do cofre.
    public func open(walletID: UUID, rk: SecureBytes) throws -> WalletSecret {
        try openRecord(walletID: walletID, rk: rk, includeOld: false).secret
    }

    /// A passphrase que uma versao anterior gravou neste registro.
    public enum StoredPassphrase: Sendable, Equatable {
        case none
        /// `legacy`: gravada fora de NFKD (com acento composto), e entao a conta da Cardano dela saiu
        /// dos bytes digitados e muda se a carteira for restaurada pelas palavras. `verified`: ela, em
        /// NFKD como a digitada vai entrar, da a raiz da criacao (`fingerprint`); sem isso, a digitada
        /// tambem nao assinaria nesta versao. Sao os unicos fatos sobre ela que podem sobrar, como
        /// marcas nos metadados, antes de ela sair.
        case present(legacy: Bool, verified: Bool)
    }

    /// Ha passphrase de uma versao anterior no registro? So os fatos: ela nao sai daqui.
    public func storedPassphrase(walletID: UUID, rk: SecureBytes, fingerprint: [UInt8]? = nil) throws -> StoredPassphrase {
        let opened = try openRecord(walletID: walletID, rk: rk, includeOld: true)
        defer { opened.secret.wipe(); opened.old?.wipe() }
        guard let old = opened.old, let legacy = opened.legacy else { return .none }
        let entropy = SecureBytes(capacity: opened.secret.entropy.count)
        opened.secret.entropy.withUnsafeBytes { entropy.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        let probe = WalletSecret(entropy: entropy, language: opened.secret.language, passphrase: BIP39.nfkd(old))
        defer { probe.wipe() }
        // Duas contas: um defeito passageiro do aparelho nao vira a marca permanente de que ela nao confere, ja que a antiga
        // sai logo depois e nao ha como conferir de novo (revisao de blockchain de 05/11/2026).
        let verified = try PassphraseProof.verify(probe, fingerprint: fingerprint, cardanoPublicKey: nil) == .match
            || PassphraseProof.verify(probe, fingerprint: fingerprint, cardanoPublicKey: nil) == .match
        return .present(legacy: legacy, verified: verified)
    }

    /// A passphrase que uma versao anterior gravou sai do cofre, sempre (pedido do dono, 05/11/2026: em
    /// hipotese alguma ela fica). Nada no app a le mais: `open` a descarta, e o assinador so usa a
    /// digitada. O registro novo, com salts e DEK novos e sem ela, e aberto em memoria antes de valer, e
    /// lido de volta depois; se nao bate, o de antes volta. Devolve se havia uma. O chaveiro troca o item
    /// de uma vez (antigo ou novo, nunca metade). Vale tambem para um registro sem carteira na lista: a
    /// entropia fica (pode ser a unica copia), so a passphrase sai.
    @discardableResult
    public func purgePassphrase(walletID: UUID, rk: SecureBytes) throws -> Bool {
        let account = Self.account(walletID)
        guard let before = try store.read(account, context: nil) else { throw Failure.notFound }
        let opened = try openBlob(before, walletID: walletID, rk: rk, includeOld: true)
        defer { opened.secret.wipe(); opened.old?.wipe() }
        guard opened.old != nil else { return false }
        let after = try sealedBlob(opened.secret, walletID: walletID, rk: rk)
        let check = try openBlob(after, walletID: walletID, rk: rk, includeOld: true)
        defer { check.secret.wipe(); check.old?.wipe() }
        guard check.old == nil, check.secret.language == opened.secret.language,
              Hash.constantTimeEqual(check.secret.entropy, opened.secret.entropy) else { throw Failure.corrupted }
        try store.update(after, account: account)
        guard try store.read(account, context: nil) == after else {
            try? store.update(before, account: account)
            throw Failure.corrupted
        }
        return true
    }

    /// Os registros deste cofre (para achar os sem carteira na lista, que um gravar que parou no meio
    /// deixou numa versao anterior). So o chaveiro do iPhone sabe lista-los.
    public func storedWalletIDs() -> [UUID] {
        store.accounts(prefix: "seed.").compactMap { UUID(uuidString: String($0.dropFirst("seed.".count))) }
    }

    /// O segredo sem a passphrase; com `includeOld`, a de uma versao anterior, a parte (de quem chama,
    /// que zera), e se ela estava fora de NFKD. Sem ele, a antiga nem e copiada nem passa pelo NFKD.
    private func openRecord(walletID: UUID, rk: SecureBytes, includeOld: Bool) throws -> (secret: WalletSecret, old: SecureBytes?, legacy: Bool?) {
        guard let blob = try store.read(Self.account(walletID), context: nil) else { throw Failure.notFound }
        return try openBlob(blob, walletID: walletID, rk: rk, includeOld: includeOld)
    }

    private func openBlob(_ blob: Data, walletID: UUID, rk: SecureBytes, includeOld: Bool) throws -> (secret: WalletSecret, old: SecureBytes?, legacy: Bool?) {
        let bytes = [UInt8](blob)
        let expected = 1 + 32 + 48 + 32 + Self.recordLength + 16
        guard bytes.count == expected, bytes[0] == Self.version else { throw Failure.corrupted }
        let walletSalt = Array(bytes[1..<33])
        let wrapped = Array(bytes[33..<81])
        let seedSalt = Array(bytes[81..<113])
        let sealed = Array(bytes[113...])

        let kek = Self.kek(rk: rk, salt: walletSalt, walletID: walletID)
        guard var dekData = try? ChaChaPoly.open(
            ChaChaPoly.SealedBox(nonce: Self.zeroNonce, ciphertext: Data(wrapped.prefix(32)), tag: Data(wrapped.suffix(16))),
            using: kek, authenticating: Self.aad(walletID, type: 0x01)
        ) else { throw Failure.corrupted }
        let dek = SecureBytes.consuming(&dekData)
        defer { dek.wipe() }

        guard var plain = try? ChaChaPoly.open(
            ChaChaPoly.SealedBox(nonce: Self.zeroNonce, ciphertext: Data(sealed.prefix(Self.recordLength)), tag: Data(sealed.suffix(16))),
            using: Self.seedKey(dek: dek, salt: seedSalt), authenticating: Self.aad(walletID, type: 0x02)
        ) else { throw Failure.corrupted }
        let record = SecureBytes.consuming(&plain)
        defer { record.wipe() }

        return try record.withUnsafeBytes { raw -> (secret: WalletSecret, old: SecureBytes?, legacy: Bool?) in
            let r = raw.bindMemory(to: UInt8.self)
            guard r.count == Self.recordLength, r[0] == Self.version else { throw Failure.corrupted }
            let entropyLength = Int(r[2])
            guard let language = BIP39Language(storageCode: r[1]), [16, 20, 24, 28, 32].contains(entropyLength) else {
                throw Failure.corrupted
            }
            let entropy = SecureBytes(capacity: entropyLength)
            entropy.append(contentsOf: UnsafeBufferPointer(rebasing: r[3..<(3 + entropyLength)]))
            let at = 3 + entropyLength
            let passLength = Int(r[at]) << 8 | Int(r[at + 1])
            guard passLength <= Self.maxPassphraseBytes, at + 2 + passLength <= r.count else {
                entropy.wipe()
                throw Failure.corrupted
            }
            // A passphrase de uma versao anterior nunca entra no segredo: so vai a parte, para a purga conferir antes de
            // apagar e dizer se ela estava fora de NFKD. O registro, o `defer` zera.
            var old: SecureBytes?
            var legacy: Bool?
            if includeOld, passLength > 0 {
                let copy = SecureBytes(capacity: passLength)
                copy.append(contentsOf: UnsafeBufferPointer(rebasing: r[(at + 2)..<(at + 2 + passLength)]))
                let normalized = BIP39.nfkd(copy)
                legacy = !Hash.constantTimeEqual(normalized, copy)
                normalized.wipe()
                old = copy
            }
            return (WalletSecret(entropy: entropy, language: language, passphrase: SecureBytes(capacity: 1)), old, legacy)
        }
    }

    // MARK: Chaves

    static let zeroNonce = try! ChaChaPoly.Nonce(data: Data(repeating: 0, count: 12))  // swiftlint:disable:this force_try

    static func kek(rk: SecureBytes, salt: [UInt8], walletID: UUID) -> SymmetricKey {
        let ikm = rk.withUnsafeBytes { SymmetricKey(data: $0) }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm, salt: salt,
            info: Array("escalibur-wallet/v1/dek".utf8) + uuidBytes(walletID), outputByteCount: 32
        )
    }

    static func seedKey(dek: SecureBytes, salt: [UInt8]) -> SymmetricKey {
        let ikm = dek.withUnsafeBytes { SymmetricKey(data: $0) }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Array("escalibur-wallet/v1/seed".utf8), outputByteCount: 32)
    }

    static func aad(_ id: UUID, type: UInt8) -> Data {
        Data(uuidBytes(id) + [version, type])
    }

    static func uuidBytes(_ id: UUID) -> [UInt8] {
        withUnsafeBytes(of: id.uuid) { Array($0) }
    }

    static func randomBytes(_ count: Int) throws -> [UInt8] {
        try SecureBytes.random(count: count).withUnsafeBytes { Array($0) }
    }
}

/// A chave de indice: protege os metadados (nomes, enderecos, xpubs, catalogo,
/// historico de ordens), que sao dado de privacidade, nao segredo. Vive em memoria
/// enquanto o app esta destrancado.
public enum IndexCipher {
    public static func key(from rk: SecureBytes) -> SymmetricKey {
        let ikm = rk.withUnsafeBytes { SymmetricKey(data: $0) }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: [UInt8](), info: Array("escalibur-wallet/v1/index".utf8), outputByteCount: 32)
    }

    /// Cifra com subchave por gravacao: `salt(32) ‖ ciphertext ‖ tag`.
    public static func seal(_ plain: Data, key: SymmetricKey) throws -> Data {
        let salt = try WalletVault.randomBytes(32)
        let subkey = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: salt, info: Array("escalibur-wallet/v1/metadados".utf8), outputByteCount: 32)
        let sealed = try ChaChaPoly.seal(plain, using: subkey, nonce: WalletVault.zeroNonce)
        return Data(salt) + sealed.ciphertext + sealed.tag
    }

    public static func open(_ blob: Data, key: SymmetricKey) throws -> Data {
        guard blob.count >= 48 else { throw WalletVault.Failure.corrupted }
        let salt = [UInt8](blob.prefix(32))
        let subkey = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: salt, info: Array("escalibur-wallet/v1/metadados".utf8), outputByteCount: 32)
        let body = blob.dropFirst(32)
        return try ChaChaPoly.open(
            ChaChaPoly.SealedBox(nonce: WalletVault.zeroNonce, ciphertext: body.dropLast(16), tag: body.suffix(16)),
            using: subkey
        )
    }
}

extension SecureBytes {
    /// Move o conteudo de um `Data` que saiu de uma API para o buffer seguro, e zera
    /// a origem.
    public static func consuming(_ data: inout Data) -> SecureBytes {
        let out = SecureBytes(capacity: max(data.count, 1))
        data.withUnsafeMutableBytes { raw in
            out.append(contentsOf: raw.bindMemory(to: UInt8.self).withMemoryRebound(to: UInt8.self) { UnsafeBufferPointer($0) })
            if let base = raw.baseAddress { memset_s(base, raw.count, 0, raw.count) }
        }
        return out
    }
}
