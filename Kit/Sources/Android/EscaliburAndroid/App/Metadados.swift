import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import EscaliburNetwork
import Foundation
#if canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif
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
    /// As ordens limite da CoW assinadas aqui que a CoW disse ter recusado, ou sem resposta certa
    /// (`SignedOrderRecord`, como no iOS): ate vencer ou a cadeia dizer que terminaram.
    var signedOrders: [SignedOrderRecord]?
    /// As transacoes EVM transmitidas e ainda sem confirmacao, por carteira, rede e conta.
    var pendingEVM: [String: [PendingEVMTransaction]]?
    /// Os envios fora da EVM transmitidos sem resposta certa da rede (`UnsureSend`, a mesma regra do iOS): ate a rede
    /// dizer se sairam, ou o prazo vencer.
    var unsureSends: [UnsureSend]?
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
    /// O "Pedir a passphrase para enviar" de antes. Nao vale mais: desde 05/11/2026 a passphrase nao
    /// fica no cofre, e toda assinatura da carteira com passphrase a pede. Fica so para os metadados
    /// antigos abrirem.
    var passphraseToSend: Bool?
    /// A passphrase que uma versao anterior gravou estava fora de NFKD, e a conta da Cardano dela saiu
    /// dos bytes digitados: restaurada pelas palavras, ela muda. O unico fato sobre a passphrase que
    /// sobra, marcado ao tira-la do cofre (05/11/2026), para o Super Security continuar recusando.
    var legacyCardanoPassphrase: Bool?
    /// A passphrase que uma versao anterior gravou nao dava a raiz da criacao, e saiu do cofre assim mesmo
    /// (05/11/2026): a digitada tambem nao assina nesta versao, e a tela diz isso em vez de contar erro.
    var passphraseUnverified: Bool?
    var tronForeignControl: Bool?
    /// Outra chave, conta ou contrato no controle das contas da carteira, por rede (`ForeignControl`; auditoria 8,
    /// 14/11/2026), fora a Tron, que tem a marca propria: o `foreignControl` do iOS. O Receber da rede mostra o aviso, a conta
    /// sai de Minhas carteiras e a revisao avisa. Opcional para os metadados antigos.
    var foreignControl: [String: ForeignControl]?
    /// A ultima conferencia de todas as redes (`ForeignControlCheck`): a do destravar espera um dia.
    var foreignControlCheckedAt: Date?
    /// As redes em que a outra chave no controle ja foi lida de verdade, como no iOS (rodada 6 da auditoria 8).
    var foreignControlRead: Set<String>?
    /// Criada aqui com as palavras escolhidas pelo dono: conferida como a importada (rodada 6 da auditoria 8), como no iOS.
    var chosenWords: Bool?
    /// A versao da carteira TON ja conferida (`TONDiscovery`), como no iOS: uma vez por carteira.
    var tonVersionChecked: Bool?
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
    /// Outra chave, conta ou contrato no controle da conta desta rede (fora a Tron, que tem a marca propria). Numa rede EVM,
    /// tambem a marca de outra rede EVM: o endereco e a chave sao os mesmos em todas (rodada 2 da auditoria 8), como no iOS.
    func foreignControl(on chain: Chain) -> ForeignControl? {
        if let own = foreignControl?[chain.id] { return own }
        guard chain.family == .evm, let marks = foreignControl else { return nil }
        return marks.keys.sorted().lazy.filter { Chain.find($0)?.family == .evm }.first.flatMap { marks[$0] }
    }
    /// Ja conferida para outra chave no controle, ou criada aqui; a importada nunca conferida nao conta como sua no envio
    /// (rodada 5 da auditoria 8), como no iOS.
    /// Por rede: a sem outra chave para ler conta direto, e a com leitura so depois de lida (rodada 6), como no iOS.
    func controlChecked(on chain: Chain) -> Bool {
        (origin == .created && chosenWords != true) || !ForeignControlCheck.reads(chain) || foreignControlRead?.contains(chain.id) == true
    }
    /// A rede onde a marca de `foreignControl(on:)` foi vista: a propria, ou, numa EVM, a outra EVM marcada (rodada 3).
    func foreignControlOrigin(on chain: Chain) -> Chain? {
        if foreignControl?[chain.id] != nil { return chain }
        guard chain.family == .evm, let marks = foreignControl else { return nil }
        return marks.keys.sorted().lazy.compactMap { Chain.find($0) }.first { $0.family == .evm }
    }
    /// A carteira recebe nesta rede (o `receives(on:)` do iOS): nem a conta da Tron com outra chave, nem, desde a auditoria 8
    /// (14/11/2026, pela regra do dono de sempre a forma mais segura), a de qualquer rede com outra chave ou contrato no controle.
    func recebe(on chain: Chain) -> Bool {
        !(chain.family == .tron && tronForeignControl == true) && foreignControl(on: chain) == nil
    }
}

extension Array where Element == WalletMeta {
    /// Outra carteira deste aparelho com o mesmo endereco nesta rede, e nele a marca de outra chave no controle: a so de
    /// observacao desse endereco (ou outra carteira com ele) tambem nao recebe por ele (pedido do dono, 15/11/2026, a forma mais
    /// segura), como o `markedElsewhere` do iOS.
    func marcadaEmOutra(_ carteira: WalletMeta, on chain: Chain) -> WalletMeta? {
        guard let endereco = carteira.account(chain)?.address else { return nil }
        return donaMarcada(de: endereco, on: chain, exceto: carteira.id)
    }

    /// Como o endereco esta gravado em cada carteira deste aparelho com a mesma conta (`Address.canonicalRecipient`; numa EVM, em
    /// qualquer EVM), mais ele mesmo: a copia da TON so de observacao em EQ ou crua sai junto com a marca (revisao dos tres
    /// agentes de 15/11/2026), como o `addressForms` do iOS.
    func formas(de endereco: String, on chain: Chain) -> Set<String> {
        guard let alvo = Address.canonicalRecipient(endereco, chain: chain) else { return [endereco] }
        var saida: Set<String> = [endereco]
        for conta in flatMap(\.accounts) {
            guard let outra = Chain.find(conta.chainID) else { continue }
            let mesma = chain.family == .evm
                ? outra.family == .evm && conta.address.lowercased() == alvo
                : outra.id == chain.id && Address.canonicalRecipient(conta.address, chain: chain) == alvo
            if mesma { saida.insert(conta.address) }
        }
        return saida
    }

    /// A carteira deste aparelho dona de `endereco` nesta rede, com a marca de outra chave no controle nela (`recebe`): receber
    /// nesse endereco, ou enviar para ele de outra carteira, e depositar numa conta que quem controla a outra chave leva
    /// (15/11/2026), como o `markedOwner` do iOS. Pela identidade canonica (`Address.canonicalRecipient`): a TON so de observacao
    /// fica gravada como foi digitada. Numa EVM, o endereco de qualquer EVM, como a marca.
    func donaMarcada(de endereco: String, on chain: Chain, exceto: UUID? = nil) -> WalletMeta? {
        guard let alvo = Address.canonicalRecipient(endereco, chain: chain) else { return nil }
        let evm = chain.family == .evm
        return first { outra in
            guard outra.id != exceto, !outra.recebe(on: chain) else { return false }
            if evm {
                return outra.accounts.contains { Chain.find($0.chainID)?.family == .evm && $0.address.lowercased() == alvo }
            }
            return outra.account(chain).flatMap { Address.canonicalRecipient($0.address, chain: chain) } == alvo
        }
    }
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
    /// Conferir o endereco em todo envio: os 6 ultimos caracteres do destino, lidos na fonte.
    /// Nil: desligado, o padrao; no Super Security vale ligado. Desligar pede o PIN.
    var confirmEveryAddress: Bool?
    var completedSends: Int?
    var passphraseGuard: PassphraseGuard?
    /// A conta de passphrases erradas de cada carteira, pelo id (revisao de seguranca de 24/10/2026):
    /// acertar a passphrase de uma carteira zera so a dela. A conta unica de antes passa para cada
    /// carteira na primeira vez que a conta e tocada.
    var passphraseGuards: [String: PassphraseGuard]?

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
        try gravarDuravel(sealed, em: file)
    }

    /// Grava e troca de uma vez, e so volta depois de a troca estar no disco: fsync do arquivo novo,
    /// rename e fsync da pasta, como o `gravarAtomico` do Cofre.kt. O `.atomic` do Foundation faz o
    /// rename sem o fsync da pasta, e no f2fs um reinicio forcado logo depois voltava o arquivo antigo:
    /// quem tem o PIN devolvia a conta das passphrases erradas reiniciando o celular (revisao de
    /// seguranca do Android de 26/10/2026).
    static func gravarDuravel(_ dados: Data, em arquivo: URL) throws {
        let temporario = arquivo.path + ".novo"
        let fd = open(temporario, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        var ok = dados.withUnsafeBytes { bruto -> Bool in
            var feito = 0
            while feito < bruto.count {
                let n = write(fd, bruto.baseAddress! + feito, bruto.count - feito)
                if n <= 0 { return false }
                feito += n
            }
            return true
        }
        ok = ok && fsync(fd) == 0
        close(fd)
        guard ok, rename(temporario, arquivo.path) == 0 else {
            unlink(temporario)
            throw CocoaError(.fileWriteUnknown)
        }
        // O arquivo ja foi trocado: daqui em diante, falhar deixaria a memoria diferente do disco. O
        // fsync da pasta e o melhor esforco.
        let pasta = open(arquivo.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC)
        if pasta >= 0 {
            _ = fsync(pasta)
            close(pasta)
        }
    }

    static func deleteFile() {
        if let file { try? FileManager.default.removeItem(at: file) }
    }
}
