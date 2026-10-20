import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import EscaliburNetwork
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Os objetos do modulo de chaves, montados uma vez: o cofre do iOS sobre o Keystore.
enum Chaves {
    static let store = KeystoreStore()
    static let wrapper = KeystoreWrapper()
    static let root = RootKeyVault(store: store, wrapper: wrapper)
    static let wallets = WalletVault(store: store)
}

/// Tudo que a carteira sabe e nao e segredo, mas e privacidade: nomes, enderecos, xpubs,
/// contatos, ajustes, cache de saldo. Os mesmos campos do iOS (App/Services/Metadata.swift),
/// cifrados com a chave de indice (derivada da RK) num arquivo da pasta sem backup do app.
struct Metadata: Codable, Equatable {
    var version = 1
    var wallets: [WalletMeta] = []
    var selectedWalletID: UUID?
    var settings = Settings()
    var contacts: [Contact] = []
    /// Enderecos para onde esta carteira ja enviou, por rede: o aviso de primeiro envio e a
    /// deteccao de endereco parecido.
    var sentTo: [String: [String]] = [:]
    var balanceCache: [UUID: [String: ChainBalance]] = [:]
    var quoteCache: [String: Quote] = [:]
    var cachedAt: Date?
    var responsibilityAccepted: Date?
    var responsibilityVersion: Int?
    var customAssets: [Asset]?
    var recognizedTokens: [String: TokenIdentity]?
    var unrecognizedChecks: [String: Date]?
    var bridges: [BridgeRecord]?
    /// As transacoes EVM transmitidas e ainda sem confirmacao, por carteira, rede e conta.
    var pendingEVM: [String: [PendingEVMTransaction]]?
    /// O ultimo historico lido de cada carteira, e quando cada rede foi lida.
    var activityCache: [UUID: [CachedActivity]]?
    var activityFetched: [UUID: [String: ActivityFetch]]?
    /// Os tokens fora da lista que ja passaram por uma troca deste aparelho.
    var tradedAssets: [Asset]?
    /// As ordens limite que o dono pediu para refazer quando vencer.
    var limitRenewals: [LimitRenewal]?

    var customTokens: [Asset] { customAssets ?? [] }

    var selectedWallet: WalletMeta? {
        wallets.first { $0.id == selectedWalletID } ?? wallets.first
    }
}

struct WalletMeta: Codable, Equatable, Hashable {
    enum Kind: Codable, Equatable, Hashable {
        case phrase(wordCount: Int)
        case watch(chainID: String)
    }

    enum Origin: String, Codable {
        case created, importedPhrase, importedEnvelope, watch
    }

    let id: UUID
    var name: String
    let kind: Kind
    let origin: Origin
    let createdAt: Date
    var accounts: [DerivedAccount]
    var fingerprint: String?
    var hasPassphrase: Bool
    var backupConfirmedAt: Date?
    var passphraseConfirmedAt: Date?
    var passphraseToSend: Bool?
    var tronForeignControl: Bool?
    var envelopeSealedAt: Date?
    var lastRevealedAt: Date?
    var hiddenAssetIDs: Set<String> = []
    var utxoUsage: [String: UTXOUsage] = [:]

    var isWatchOnly: Bool { if case .watch = kind { return true }; return false }
    var wordsConfirmed: Bool { backupConfirmedAt != nil || origin != .created }
    var passphraseConfirmed: Bool { !hasPassphrase || passphraseConfirmedAt != nil }
    var hasBackup: Bool { wordsConfirmed && passphraseConfirmed }
    var wordCount: Int? { if case .phrase(let count) = kind { return count }; return nil }

    func account(_ chain: Chain) -> DerivedAccount? { accounts.first { $0.chainID == chain.id } }
}

struct Contact: Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var chainID: String
    var address: String
    var tag: String?
}

struct Settings: Codable, Equatable {
    /// A moeda dos precos ("brl", "usd", "eur"). Quem instala comeca na da regiao do aparelho.
    var currency: String = Settings.regionCurrency
    /// A unidade escolhida em Ativos ("brl", "usd", "eur", "btc"). Nil: a moeda do app.
    var totalUnit: String?
    var favoriteCoins: [String]?
    var hideBalances = false
    var biometryEnabled = false
    var autoLockSeconds: Int = 60
    var disabledChainIDs: Set<String> = []
    var mevProtection = true
    /// As palavras no teclado proprio. No Android ele e o padrao (nil vale ligado): o teclado
    /// do sistema pode ser de terceiros e aprender o que se digita.
    var ownKeyboard: Bool?
    var completedSends: Int?
    var passphraseGuard: PassphraseGuard?

    static var regionCurrency: String {
        switch Locale.current.currency?.identifier {
        case "BRL": return "brl"
        case "EUR": return "eur"
        default: return "usd"
        }
    }

    /// Escolhe a unidade em Ativos, e com ela a moeda dos precos. Devolve se a moeda mudou.
    @discardableResult
    mutating func choose(_ unit: String) -> Bool {
        totalUnit = unit
        let fetch = unit == "btc" ? "usd" : unit
        guard currency != fetch else { return false }
        currency = fetch
        return true
    }
}

/// O arquivo de metadados, cifrado, na pasta sem backup do app (a que o Kotlin passa ao abrir).
enum MetadataStore {
    nonisolated(unsafe) static var directory: URL?

    static var file: URL? { directory?.appendingPathComponent("metadados.bin") }

    static func load(key: SymmetricKey) throws -> Metadata {
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return Metadata() }
        let sealed = try Data(contentsOf: file)
        let plain = try IndexCipher.open(sealed, key: key)
        return try JSONDecoder().decode(Metadata.self, from: plain)
    }

    static func save(_ metadata: Metadata, key: SymmetricKey) throws {
        guard let directory, let file else { throw Sessao.Falha.semPasta }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plain = try JSONEncoder().encode(metadata)
        let sealed = try IndexCipher.seal(plain, key: key)
        try sealed.write(to: file, options: .atomic)
    }

    static func deleteFile() {
        if let file { try? FileManager.default.removeItem(at: file) }
    }
}
