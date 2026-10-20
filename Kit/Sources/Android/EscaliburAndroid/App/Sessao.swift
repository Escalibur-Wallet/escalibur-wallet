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

/// Como o dono prova presenca para uma operacao que precisa da chave raiz (o `Credential` do iOS).
enum Credencial {
    case pin(SecureBytes)
    case biometria(motivo: String)
    /// O PIN e, com a biometria ligada, ela tambem: ver as palavras, remover carteira, desligar
    /// a biometria.
    case pinEBiometria(SecureBytes, motivo: String)
    /// Modo reforcado: o PIN e a biometria pela criptografia, em tudo.
    case reforcado(SecureBytes, motivo: String)

    func zerar() {
        switch self {
        case .pin(let pin), .pinEBiometria(let pin, _), .reforcado(let pin, _): pin.wipe()
        case .biometria: break
        }
    }
}

/// O estado de alto nivel do app Android: a mesma sessao do iOS (App/AppSession.swift), sem a
/// interface. A interface (Kotlin) pergunta o estado e chama as operacoes; nada aqui depende da
/// thread principal: o estado fica sob uma trava e o trabalho pesado (Argon2, rede) roda fora
/// dela.
final class Sessao: @unchecked Sendable {
    static let shared = Sessao()

    enum Fase: String, Codable { case onboarding, locked, unlocked }

    enum Falha: Error {
        case semPasta
        case travada
        case jaImportada(String)
        case naoEFrase
        case remocaoFalhou
        case semRascunho
        case carteiraNaoEncontrada
    }

    private let trava = NSLock()
    private var faseAtual: Fase
    private var metadados = Metadata()
    /// A chave dos metadados. So existe enquanto o app esta destrancado.
    private var chaveDeIndice: SymmetricKey?
    /// A ida para o segundo plano no relogio monotono (conta o tempo dormindo, nao anda com o
    /// relogio de parede).
    private var segundoPlanoDesde: TimeInterval?
    /// As palavras de uma carteira recem-criada, enquanto o dono anota e confere.
    private var rascunho: Rascunho?

    private init() {
        faseAtual = Chaves.root.isSetUp ? .locked : .onboarding
    }

    var fase: Fase { trava.withLock { faseAtual } }
    var metadata: Metadata { trava.withLock { metadados } }

    /// Muda os metadados e grava. Travado no meio de uma operacao: nada e gravado em silencio.
    @discardableResult
    func alterar<T>(_ corpo: (inout Metadata) throws -> T) throws -> T {
        try trava.withLock {
            guard let chaveDeIndice else { throw Falha.travada }
            var copia = metadados
            let resultado = try corpo(&copia)
            try MetadataStore.save(copia, key: chaveDeIndice)
            metadados = copia
            return resultado
        }
    }

    // MARK: Abertura

    /// Na abertura do processo: a contagem de tentativas que veio de outro boot, e a fase de novo
    /// (o cofre pode ter sido apagado por fora).
    func abrirProcesso() {
        Chaves.root.rebaseAttempts()
        trava.withLock {
            if faseAtual == .locked, !Chaves.root.isSetUp { faseAtual = .onboarding }
        }
    }

    // MARK: PIN e desbloqueio

    func cadastrarPIN(_ pin: SecureBytes) throws {
        defer { pin.wipe() }
        let rk = try Chaves.root.setUp(pin: pin)
        defer { rk.wipe() }
        let chave = IndexCipher.key(from: rk)
        try trava.withLock {
            chaveDeIndice = chave
            metadados = Metadata()
            try MetadataStore.save(metadados, key: chave)
            faseAtual = .unlocked
        }
    }

    func destrancar(pin: SecureBytes) throws {
        defer { pin.wipe() }
        let rk = Chaves.root.securityMode == .hardened
            ? try Chaves.root.unlockHardened(pin: pin, reason: Textos.destravar, use: .openApp)
            : try Chaves.root.unlock(pin: pin)
        defer { rk.wipe() }
        try abrir(com: IndexCipher.key(from: rk), novasContas: Self.contasQueFaltam(rk: rk))
    }

    func destrancarComBiometria() throws {
        let rk = try Chaves.root.unlockWithBiometry(reason: Textos.destravar)
        defer { rk.wipe() }
        try abrir(com: IndexCipher.key(from: rk), novasContas: Self.contasQueFaltam(rk: rk))
    }

    /// Redes que entraram numa versao nova ainda nao tem endereco nas carteiras antigas: com a RK
    /// aberta neste desbloqueio, os enderecos que faltam sao derivados agora.
    private static func contasQueFaltam(rk: SecureBytes) -> [UUID: [DerivedAccount]] {
        guard let metadata = try? MetadataStore.load(key: IndexCipher.key(from: rk)) else { return [:] }
        var novas: [UUID: [DerivedAccount]] = [:]
        for wallet in metadata.wallets where wallet.isWatchOnly {
            guard let evm = wallet.accounts.first(where: { Chain.find($0.chainID)?.family == .evm }) else { continue }
            let tem = Set(wallet.accounts.map(\.chainID))
            let faltam = Chain.evmChains.filter { !tem.contains($0.id) }
            guard !faltam.isEmpty else { continue }
            novas[wallet.id] = faltam.map {
                DerivedAccount(chainID: $0.id, path: evm.path, address: evm.address, publicKey: evm.publicKey, accountXPub: nil)
            }
        }
        for wallet in metadata.wallets where !wallet.isWatchOnly {
            let tem = Set(wallet.accounts.map(\.chainID))
            let faltam = Chain.all.filter { !tem.contains($0.id) }
            guard !faltam.isEmpty, let secret = try? Chaves.wallets.open(walletID: wallet.id, rk: rk) else { continue }
            defer { secret.wipe() }
            if let (contas, _) = try? AccountDeriver.derive(secret, chains: faltam), !contas.isEmpty {
                novas[wallet.id] = contas
            }
        }
        return novas
    }

    private func abrir(com chave: SymmetricKey, novasContas: [UUID: [DerivedAccount]]) throws {
        var lidos = try MetadataStore.load(key: chave)
        if !novasContas.isEmpty {
            for (id, contas) in novasContas {
                guard let indice = lidos.wallets.firstIndex(where: { $0.id == id }) else { continue }
                lidos.wallets[indice].accounts += contas
            }
            try? MetadataStore.save(lidos, key: chave)
        }
        trava.withLock {
            metadados = lidos
            chaveDeIndice = chave
            faseAtual = .unlocked
        }
    }

    func travar() {
        trava.withLock {
            rascunho?.zerar()
            rascunho = nil
            chaveDeIndice = nil
            metadados = Metadata()
            if faseAtual == .unlocked { faseAtual = .locked }
        }
        Saldos.shared.esquecer()
        PortaDaPassphrase.encerrarFolgas()
        Envio.encerrar()
    }

    /// O app foi para o segundo plano (a tela ja fica coberta pelo FLAG_SECURE).
    func foiParaSegundoPlano() {
        trava.withLock { segundoPlanoDesde = PINPolicy.uptime }
    }

    /// Voltou: trava se passou do tempo escolhido (padrao 1 minuto). Devolve se travou.
    @discardableResult
    func voltouAoPrimeiroPlano() -> Bool {
        Chaves.root.rebaseAttempts()
        let deveTravar = trava.withLock { () -> Bool in
            defer { segundoPlanoDesde = nil }
            guard faseAtual == .unlocked, let desde = segundoPlanoDesde else { return false }
            return PINPolicy.uptime - desde >= Double(max(0, metadados.settings.autoLockSeconds))
        }
        if deveTravar { travar() }
        return deveTravar
    }

    // MARK: Operacoes com a chave raiz

    /// Destranca a RK com presenca nova e executa `corpo` com ela. A RK nasce, e usada e e zerada
    /// dentro desta chamada.
    func comChaveRaiz<T>(_ credencial: Credencial, _ corpo: (SecureBytes) throws -> T) throws -> T {
        do {
            let rk: SecureBytes
            switch credencial {
            case .pin(let pin):
                defer { pin.wipe() }
                rk = try Chaves.root.unlock(pin: pin)
            case .biometria(let motivo):
                rk = try Chaves.root.unlockWithBiometry(reason: motivo)
            case .pinEBiometria(let pin, let motivo):
                defer { pin.wipe() }
                rk = try Chaves.root.unlockWithPINAndBiometry(pin: pin, reason: motivo)
            case .reforcado(let pin, let motivo):
                defer { pin.wipe() }
                rk = try Chaves.root.unlockHardened(pin: pin, reason: motivo)
            }
            defer { rk.wipe() }
            return try corpo(rk)
        } catch RootKeyVault.Failure.wiped {
            // O erro que disparou o apagar apos erros veio de uma operacao: os metadados vao junto.
            apagarTudo()
            throw RootKeyVault.Failure.wiped
        }
    }

    /// Liga a biometria: o cofre confere na hora que o slot novo abre e devolve a mesma RK.
    func ligarBiometria(pin: SecureBytes, motivo: String) throws {
        do {
            defer { pin.wipe() }
            let rk = try Chaves.root.unlock(pin: pin)
            defer { rk.wipe() }
            try Chaves.root.enableBiometry(rk: rk, reason: motivo)
        } catch RootKeyVault.Failure.wiped {
            apagarTudo()
            throw RootKeyVault.Failure.wiped
        }
        try alterar { $0.settings.biometryEnabled = true }
    }

    func desligarBiometria(_ credencial: Credencial) throws {
        guard case .pinEBiometria(let pin, let motivo) = credencial else {
            credencial.zerar()
            throw RootKeyVault.Failure.biometryRequired
        }
        do {
            defer { pin.wipe() }
            try Chaves.root.disableBiometry(pin: pin, reason: motivo)
        } catch RootKeyVault.Failure.wiped {
            apagarTudo()
            throw RootKeyVault.Failure.wiped
        }
        try? alterar { $0.settings.biometryEnabled = false }
    }

    func trocarPIN(_ credencial: Credencial, novo: SecureBytes) throws {
        defer { novo.wipe() }
        try comChaveRaiz(credencial) { rk in try Chaves.root.changePIN(rk: rk, newPIN: novo) }
    }

    // MARK: Carteiras

    /// Guarda uma carteira nova ou importada. A RK so existe durante esta chamada.
    func adicionarCarteira(
        _ secret: WalletSecret, nome: String, origem: WalletMeta.Origin, palavras: Int,
        copiaConfirmada: Bool, selecionar: Bool = true, tronComOutraChave: Bool = false, credencial: Credencial
    ) throws -> WalletMeta {
        let id = UUID()
        let temPassphrase = secret.passphrase.count > 0
        let (contas, digital): ([DerivedAccount], [UInt8]) = try comChaveRaiz(credencial) { rk in
            defer { secret.wipe() }
            try Chaves.wallets.save(secret, walletID: id, rk: rk)
            return try AccountDeriver.derive(secret)
        }
        return try alterar { metadata in
            if let existente = metadata.wallets.first(where: { $0.fingerprint == digital.hex && !$0.isWatchOnly }) {
                try? Chaves.wallets.delete(id)
                throw Falha.jaImportada(existente.name)
            }
            var wallet = WalletMeta(
                id: id, name: Self.nomeUnico(nome, origem: origem, em: metadata), kind: .phrase(wordCount: palavras), origin: origem,
                createdAt: .now, accounts: contas, fingerprint: digital.hex, hasPassphrase: temPassphrase,
                backupConfirmedAt: copiaConfirmada ? .now : nil
            )
            if tronComOutraChave { wallet.tronForeignControl = true }
            metadata.wallets.append(wallet)
            if selecionar || metadata.selectedWalletID == nil { metadata.selectedWalletID = id }
            return wallet
        }
    }

    /// Nome repetido ganha a origem junto.
    private static func nomeUnico(_ nome: String, origem: WalletMeta.Origin, em metadata: Metadata) -> String {
        let usados = Set(metadata.wallets.map { esqueleto($0.name) })
        guard usados.contains(esqueleto(nome)) else { return nome }
        let marca = origem == .importedEnvelope ? Textos.envelope : Textos.importada
        var candidato = "\(nome) (\(marca))"
        var numero = 2
        while usados.contains(esqueleto(candidato)) {
            candidato = "\(nome) (\(marca) \(numero))"
            numero += 1
        }
        return String(candidato.prefix(48))
    }

    /// O nome como o olho le: sem acento, em minusculas e sem espacos nas pontas. "principаl" com
    /// um "а" cirilico e "principal" dao o mesmo.
    static func esqueleto(_ nome: String) -> String {
        let latino = nome.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? nome
        return latino.trimmingCharacters(in: .whitespaces).lowercased()
    }

    func adicionarObservacao(rede: Chain, endereco: String, nome: String) throws -> WalletMeta {
        let redes = rede.family == .evm ? Chain.evmChains : [rede]
        let contas = redes.map {
            DerivedAccount(chainID: $0.id, path: DerivationPath(components: []), address: endereco, publicKey: [], accountXPub: nil)
        }
        let wallet = WalletMeta(
            id: UUID(), name: nome, kind: .watch(chainID: rede.id), origin: .watch, createdAt: .now,
            accounts: contas, fingerprint: nil, hasPassphrase: false, backupConfirmedAt: nil
        )
        try alterar { metadata in
            metadata.wallets.append(wallet)
            metadata.selectedWalletID = wallet.id
        }
        return wallet
    }

    func selecionar(_ id: UUID) throws {
        try alterar { metadata in
            guard metadata.wallets.contains(where: { $0.id == id }) else { throw Falha.carteiraNaoEncontrada }
            metadata.selectedWalletID = id
        }
    }

    func atualizar(_ id: UUID, _ corpo: (inout WalletMeta) -> Void) throws {
        try alterar { metadata in
            guard let indice = metadata.wallets.firstIndex(where: { $0.id == id }) else { throw Falha.carteiraNaoEncontrada }
            corpo(&metadata.wallets[indice])
        }
    }

    func aceitarResponsabilidade(versao: Int) throws {
        try alterar {
            $0.responsibilityAccepted = .now
            $0.responsibilityVersion = versao
        }
    }

    /// A carteira so sai da lista depois de o armazenamento confirmar que a frase saiu.
    func remover(_ id: UUID) throws {
        guard let wallet = metadata.wallets.first(where: { $0.id == id }) else { throw Falha.carteiraNaoEncontrada }
        if !wallet.isWatchOnly {
            try? Chaves.wallets.delete(id)
            guard Chaves.wallets.probe(id) == .absent else { throw Falha.remocaoFalhou }
        }
        try alterar { metadata in
            metadata.wallets.removeAll { $0.id == id }
            metadata.balanceCache[id] = nil
            if metadata.selectedWalletID == id { metadata.selectedWalletID = metadata.wallets.first?.id }
        }
    }

    /// Apaga tudo deste aparelho: as chaves do Keystore e os itens do cofre primeiro.
    func apagarTudo() {
        Chaves.root.wipeAll()
        MetadataStore.deleteFile()
        trava.withLock {
            rascunho?.zerar()
            rascunho = nil
            chaveDeIndice = nil
            metadados = Metadata()
            faseAtual = .onboarding
        }
        Saldos.shared.esquecer()
        PortaDaPassphrase.encerrarFolgas()
        Envio.encerrar()
    }

    // MARK: Carteira nova

    /// A frase nasce e a carteira e guardada **antes** de mostrar as palavras: se o dono sair no
    /// meio, ela existe marcada "palavras nao confirmadas" e nao recebe.
    func criarCarteira(palavras: Int, credencial: Credencial) throws -> WalletMeta {
        let frase = try BIP39.generate(wordCount: palavras)
        return try guardarRascunho(Rascunho(frase: frase, palavras: palavras), credencial: credencial)
    }

    /// O dono escolheu as primeiras palavras; o app sorteia a ultima, que fecha a conta.
    func criarComPalavras(_ primeiras: SecureBytes, palavras: Int, credencial: Credencial) throws -> WalletMeta {
        defer { primeiras.wipe() }
        let frase: SecureBytes
        do {
            frase = try BIP39.completing(primeiras)
        } catch {
            credencial.zerar()
            throw error
        }
        return try guardarRascunho(Rascunho(frase: frase, palavras: palavras), credencial: credencial)
    }

    private func guardarRascunho(_ novo: Rascunho, credencial: Credencial) throws -> WalletMeta {
        do {
            let copia = SecureBytes(capacity: novo.frase.capacity)
            novo.frase.withUnsafeBytes { copia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
            let secret = try WalletSecret.from(phrase: copia, language: .english)
            copia.wipe()
            let quantas = metadata.wallets.count
            let nome = quantas == 0 ? Textos.carteiraPrincipal : Textos.carteira(quantas + 1)
            let wallet = try adicionarCarteira(secret, nome: nome, origem: .created, palavras: novo.palavras, copiaConfirmada: false, credencial: credencial)
            trava.withLock {
                rascunho?.zerar()
                rascunho = novo
            }
            return wallet
        } catch {
            novo.zerar()
            throw error
        }
    }

    func comRascunho<T>(_ corpo: (Rascunho) throws -> T) throws -> T {
        try trava.withLock {
            guard let rascunho else { throw Falha.semRascunho }
            return try corpo(rascunho)
        }
    }

    /// As palavras conferidas: a carteira ganha a copia e o rascunho e zerado.
    func confirmarCopia(_ id: UUID) throws {
        try atualizar(id) { $0.backupConfirmedAt = .now }
        descartarRascunho()
    }

    func descartarRascunho() {
        trava.withLock {
            rascunho?.zerar()
            rascunho = nil
        }
    }
}

/// A frase de uma carteira recem-criada, enquanto o dono anota e confere. As palavras so viram
/// `String` no grupo que esta na tela.
final class Rascunho: @unchecked Sendable {
    let frase: SecureBytes
    let palavras: Int

    init(frase: SecureBytes, palavras: Int) {
        self.frase = frase
        self.palavras = palavras
    }

    func palavras(_ faixa: Range<Int>) -> [String] {
        frase.withUnsafeBytes { raw in
            let trechos = Self.trechos(raw)
            return faixa.compactMap { trechos.indices.contains($0) ? String(decoding: raw[trechos[$0]], as: UTF8.self) : nil }
        }
    }

    /// A palavra digitada confere com a da posicao? Em tempo constante sobre os bytes canonicos.
    func confere(_ digitada: String, em indice: Int) -> Bool {
        var candidata = Array(Mnemonic.canonicalize(digitada).utf8)
        defer { candidata.resetBytes() }
        return frase.withUnsafeBytes { raw in
            let trechos = Self.trechos(raw)
            guard trechos.indices.contains(indice) else { return false }
            var palavra = Array(raw[trechos[indice]])
            defer { palavra.resetBytes() }
            return Hash.constantTimeEqual(palavra, candidata)
        }
    }

    private static func trechos(_ raw: UnsafeRawBufferPointer) -> [Range<Int>] {
        var saida: [Range<Int>] = []
        var inicio = 0
        for indice in 0...raw.count where indice == raw.count || raw[indice] == 0x20 {
            if indice > inicio { saida.append(inicio..<indice) }
            inicio = indice + 1
        }
        return saida
    }

    func zerar() { frase.wipe() }
}

/// Os textos que o nucleo grava ou mostra no sistema (nome de carteira, motivo da biometria). O
/// app instala a traducao ao abrir (`Textos.instalar`).
enum Textos {
    nonisolated(unsafe) private static var tabela: [String: String] = [:]

    static func instalar(_ nova: [String: String]) { tabela = nova }

    static func t(_ chave: String) -> String { tabela[chave] ?? chave }

    static var destravar: String { t("Destravar a Escalibur") }
    static var carteiraPrincipal: String { t("Carteira principal") }
    static func carteira(_ numero: Int) -> String { t("Carteira %lld").replacingOccurrences(of: "%lld", with: "\(numero)") }
    static var envelope: String { t("envelope") }
    static var importada: String { t("importada") }
}
