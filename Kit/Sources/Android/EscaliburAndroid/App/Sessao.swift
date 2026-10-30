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
        /// Alguma carteira ainda sem a copia conferida (o Super Security espera por ela).
        case copiaPendente
        /// A passphrase tem um caractere que nao da para anotar no papel.
        case passphraseInvisivel
        /// Passou dos 256 bytes do cofre, contados depois do NFKD (revisao de seguranca de 24/10/2026).
        case passphraseLonga
        /// Passphrase vazia ao abrir uma carteira com passphrase.
        case passphraseVazia
        /// Abrir com passphrase a partir de uma carteira que ja tem passphrase.
        case baseComPassphrase
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

    /// O que terminou depois de o app travar e precisa ir para os metadados (o `whenUnlocked` do
    /// iOS): a ponte ou a ordem que saiu enquanto o app travava (caca de bugs de 25/10/2026). Espera
    /// o proximo destravar e vale por cima dos metadados de verdade. Se o processo morrer antes, se
    /// perde, como antes.
    private var depoisDeDestravar: [(inout Metadata) -> Void] = []

    func alterarOuDepois(_ corpo: @escaping (inout Metadata) -> Void) {
        trava.withLock {
            guard let chaveDeIndice else {
                depoisDeDestravar.append(corpo)
                return
            }
            var copia = metadados
            corpo(&copia)
            guard (try? MetadataStore.save(copia, key: chaveDeIndice)) != nil else { return }
            metadados = copia
        }
    }

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
        // Sem cofre, nenhuma carteira: nenhum arquivo de aviso fica.
        if !Chaves.root.isSetUp { Vigias.apagarTudo() }
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
        let epoca = trava.withLock { epocaDeTravar }
        let rk = Chaves.root.securityMode == .hardened
            ? try Chaves.root.unlockHardened(pin: pin, reason: Textos.destravar, use: .openApp)
            : try Chaves.root.unlock(pin: pin)
        defer { rk.wipe() }
        try abrir(com: IndexCipher.key(from: rk), novasContas: Self.contasQueFaltam(rk: rk), epoca: epoca)
    }

    func destrancarComBiometria() throws {
        let epoca = trava.withLock { epocaDeTravar }
        let rk = try Chaves.root.unlockWithBiometry(reason: Textos.destravar)
        defer { rk.wipe() }
        try abrir(com: IndexCipher.key(from: rk), novasContas: Self.contasQueFaltam(rk: rk), epoca: epoca)
    }

    /// Cada travar() soma um. O destravar que comecou antes de um travar (o dono apertou o botao de
    /// energia durante o Argon2) nao termina abrindo o app com a tela apagada (revisao de seguranca do
    /// Android de 26/10/2026).
    private var epocaDeTravar = 0

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

    private func abrir(com chave: SymmetricKey, novasContas: [UUID: [DerivedAccount]], epoca: Int) throws {
        var lidos = try MetadataStore.load(key: chave)
        if !novasContas.isEmpty {
            for (id, contas) in novasContas {
                guard let indice = lidos.wallets.firstIndex(where: { $0.id == id }) else { continue }
                lidos.wallets[indice].accounts += contas
            }
            try? MetadataStore.save(lidos, key: chave)
        }
        let abriu = trava.withLock { () -> Bool in
            guard epocaDeTravar == epoca else { return false }
            metadados = lidos
            chaveDeIndice = chave
            faseAtual = .unlocked
            return true
        }
        guard abriu else { throw Falha.travada }
        PortaDaPassphrase.aplicarPendentes()
        let pendentes = trava.withLock { () -> [(inout Metadata) -> Void] in
            defer { depoisDeDestravar = [] }
            return depoisDeDestravar
        }
        if !pendentes.isEmpty { try? alterar { metadata in for corpo in pendentes { corpo(&metadata) } } }
    }

    func travar() {
        trava.withLock {
            epocaDeTravar &+= 1
            rascunho?.zerar()
            rascunho = nil
            chaveDeIndice = nil
            metadados = Metadata()
            if faseAtual == .unlocked { faseAtual = .locked }
        }
        Saldos.shared.esquecer()
        Atividade.shared.esquecer()
        PortaDaPassphrase.encerrarFolgas()
        Envio.encerrar()
        Silencio.ligar(false)
        esquecerSegredosDasTelas()
    }

    /// Os segredos que as telas guardam entre um passo e outro (lacre e abertura de envelope, frases do
    /// Super Security) saem ao travar e ao apagar tudo: antes so a tela, ao fechar, os zerava, e com o
    /// app no fundo isso esperava a volta (revisao de seguranca do Android de 26/10/2026).
    private func esquecerSegredosDasTelas() {
        Envelopes.encerrar()
        Envelopes.fecharAbertura()
        Reforco.esquecerFrases()
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
        // No Super Security o PIN troca dentro do registro do modo, com a biometria de novo para
        // conferir antes de valer.
        if case .reforcado(let pin, let motivo) = credencial {
            defer { pin.wipe() }
            do {
                try Chaves.root.changeHardenedPIN(currentPIN: pin, newPIN: novo, reason: motivo,
                                                  confirmReason: Textos.t("Confirme a biometria para conferir o Super Security"))
            } catch RootKeyVault.Failure.wiped {
                apagarTudo()
                throw RootKeyVault.Failure.wiped
            }
            return
        }
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
        // A frase ja foi guardada: se a lista nao grava (o app travou no meio), ela sai, ou ficaria no
        // cofre sem carteira nenhuma, longe do "Remover" (caca de bugs de 27/10/2026).
        do { return try alterar { metadata in
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
        } } catch {
            try? Chaves.wallets.delete(id)
            throw error
        }
    }

    /// A carteira da 25a palavra a partir de outra (o `addPassphraseWallet` do iOS): o cofre abre a
    /// frase da base, junta a passphrase e guarda a carteira nova, sem a frase aparecer. A mesma frase
    /// com a mesma passphrase e a mesma carteira: se ela ja esta aqui, so passa a ser a escolhida.
    /// Criar e uma porta de chute (a passphrase certa reabre a que existe): toda tentativa conta, numa
    /// espera mais curta que zera depois de um dia sem tentar. E por aqui que o dono que esqueceu a
    /// passphrase tenta lembrar (pedido do dono, 25/10/2026).
    func abrirComPassphrase(base id: UUID, passphrase: SecureBytes, nome: String, credencial: Credencial) throws -> (WalletMeta, jaAberta: Bool) {
        defer { passphrase.wipe() }
        guard let base = metadata.wallets.first(where: { $0.id == id }), case .phrase(let palavras) = base.kind else {
            credencial.zerar()
            throw Falha.carteiraNaoEncontrada
        }
        // A base e sempre a carteira sem passphrase: a conta de tentativas da porta de criar fica por
        // frase, e trocar de base nao a zera (revisao de seguranca do Android de 26/10/2026).
        guard !base.hasPassphrase else {
            credencial.zerar()
            throw Falha.baseComPassphrase
        }
        // Passphrase vazia seria a carteira de sempre marcada como "com passphrase": o assinador recusa
        // passphrase vazia (revisao de blockchain de 26/10/2026).
        guard passphrase.count > 0 else {
            credencial.zerar()
            throw Falha.passphraseVazia
        }
        guard PortaDaPassphrase.escrevivel(passphrase) else {
            credencial.zerar()
            throw Falha.passphraseInvisivel
        }
        guard PortaDaPassphrase.cabe(passphrase) else {
            credencial.zerar()
            throw Falha.passphraseLonga
        }
        do { try PortaDaPassphrase.comecar(id, criacao: true) } catch { credencial.zerar(); throw error }
        let novo = UUID()
        let contas: [DerivedAccount]
        let digital: [UInt8]
        do {
            (contas, digital) = try comChaveRaiz(credencial) { rk in
                let original = try Chaves.wallets.open(walletID: id, rk: rk)
                defer { original.wipe() }
                let entropia = SecureBytes(capacity: original.entropy.count)
                original.entropy.withUnsafeBytes { entropia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
                // A 25a palavra em NFKD, como a importacao grava: a chave da Cardano (Icarus) usa os
                // bytes como estao, e "ação" do teclado (NFC) daria outra conta.
                let normalizada: SecureBytes
                if passphrase.withUnsafeBytes({ raw in raw.contains { $0 >= 0x80 } }) {
                    normalizada = BIP39.nfkd(passphrase)
                } else {
                    normalizada = SecureBytes(capacity: passphrase.count)
                    passphrase.withUnsafeBytes { normalizada.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
                }
                let secret = WalletSecret(entropy: entropia, language: original.language, passphrase: normalizada)
                defer { secret.wipe() }
                try Chaves.wallets.save(secret, walletID: novo, rk: rk)
                return try AccountDeriver.derive(secret)
            }
        } catch {
            PortaDaPassphrase.devolver(id, criacao: true)
            throw error
        }
        // Conta na espera, sem o aviso de passphrase errada: aqui nada errou.
        PortaDaPassphrase.errou(id, criacao: true)
        let resultado: (WalletMeta, jaAberta: Bool)
        do { resultado = try alterar { metadata -> (WalletMeta, jaAberta: Bool) in
            if let existente = metadata.wallets.first(where: { $0.fingerprint == digital.hex && !$0.isWatchOnly }) {
                try? Chaves.wallets.delete(novo)
                metadata.selectedWalletID = existente.id
                return (existente, true)
            }
            let wallet = WalletMeta(
                id: novo, name: Self.nomeUnico(nome, origem: base.origin, em: metadata), kind: .phrase(wordCount: palavras), origin: base.origin,
                createdAt: .now, accounts: contas, fingerprint: digital.hex, hasPassphrase: true, backupConfirmedAt: base.backupConfirmedAt
            )
            metadata.wallets.append(wallet)
            metadata.selectedWalletID = novo
            return (wallet, false)
        } } catch {
            // A carteira guardada sai se a lista nao gravou, como em `adicionarCarteira`.
            try? Chaves.wallets.delete(novo)
            throw error
        }
        if !resultado.jaAberta { trava.withLock { recemAbertas[resultado.0.id] = PINPolicy.uptime } }
        return resultado
    }

    /// As carteiras com passphrase abertas por este processo, com o instante no relogio monotono:
    /// so elas podem sair sem PIN pela busca de movimento. O id que o Kotlin manda e o `createdAt`
    /// (relogio de parede, que se atrasa a mao) nao bastam (revisao de seguranca do Android de 26/10/2026).
    private var recemAbertas: [UUID: TimeInterval] = [:]

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
        var ficouSemCarteira = false
        try alterar { metadata in
            guard metadata.wallets.contains(where: { $0.id == id }) else { throw Falha.carteiraNaoEncontrada }
            metadata.wallets.removeAll { $0.id == id }
            ficouSemCarteira = metadata.wallets.isEmpty
            // Tudo o que leva enderecos ou o rastro desta carteira sai junto (revisao de seguranca de
            // 24/10/2026): o historico, as transacoes em transito, as ordens a refazer e a conta de
            // passphrases erradas dela.
            metadata.balanceCache[id] = nil
            metadata.activityCache?[id] = nil
            metadata.activityFetched?[id] = nil
            let prefixo = id.uuidString + "|"
            metadata.pendingEVM = metadata.pendingEVM?.filter { !$0.key.hasPrefix(prefixo) }
            metadata.limitRenewals?.removeAll { $0.walletID == id }
            PortaDaPassphrase.esquecer(&metadata, id)
            if metadata.selectedWalletID == id { metadata.selectedWalletID = metadata.wallets.first?.id }
        }
        // A ultima carteira saiu: o app volta a ser como recem-instalado, PIN e ajustes inclusive
        // (pedido do dono, 24/10/2026). Nada da carteira de antes fica para a proxima. A decisao vem
        // de dentro da gravacao: relida depois, a lista podia ser a vazia de um travar() no meio
        // (caca de bugs de 25/10/2026, B5).
        if ficouSemCarteira { apagarTudo() }
    }

    /// A carteira com passphrase recem-aberta em que a busca nao achou movimento nenhum, quando o dono
    /// prefere tentar outra passphrase (o discardFreshPassphraseWallet do iOS, pedido do dono,
    /// 25/10/2026): sai sem pedir o PIN de novo, e a carteira de antes volta a ser a escolhida. Nao ha o
    /// que perder: nunca recebeu nada, e a mesma frase com a mesma passphrase a abre de novo, igual. So
    /// vale para uma carteira com passphrase criada agora, e nunca para a ultima.
    func descartarCarteiraComPassphrase(_ id: UUID, anterior: UUID?) throws {
        guard fase == .unlocked else { throw Falha.travada }
        guard let aberta = trava.withLock({ recemAbertas[id] }), PINPolicy.uptime - aberta < 3600,
              let wallet = metadata.wallets.first(where: { $0.id == id }), wallet.hasPassphrase, !wallet.isWatchOnly,
              metadata.wallets.count > 1
        else { throw Falha.carteiraNaoEncontrada }
        try? Chaves.wallets.delete(id)
        guard Chaves.wallets.probe(id) == .absent else { throw Falha.remocaoFalhou }
        try alterar { metadata in
            metadata.wallets.removeAll { $0.id == id }
            metadata.balanceCache[id] = nil
            metadata.activityCache?[id] = nil
            metadata.activityFetched?[id] = nil
            PortaDaPassphrase.esquecer(&metadata, id)
            let volta = anterior.flatMap { anterior in metadata.wallets.contains { $0.id == anterior } ? anterior : nil }
            metadata.selectedWalletID = volta ?? metadata.wallets.first?.id
        }
        trava.withLock { recemAbertas[id] = nil }
    }

    /// Apaga tudo deste aparelho: as chaves do Keystore e os itens do cofre primeiro.
    func apagarTudo() {
        Chaves.root.wipeAll()
        MetadataStore.deleteFile()
        Vigias.apagarTudo()
        trava.withLock {
            rascunho?.zerar()
            rascunho = nil
            chaveDeIndice = nil
            metadados = Metadata()
            depoisDeDestravar = []
            faseAtual = .onboarding
        }
        Saldos.shared.esquecer()
        Atividade.shared.esquecer()
        PortaDaPassphrase.encerrarFolgas()
        Envio.encerrar()
        Silencio.ligar(false)
        esquecerSegredosDasTelas()
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

    /// As palavras conferidas: a carteira ganha a copia e o rascunho e zerado. Revelado de uma
    /// carteira com passphrase, ele fica para a conferencia dela, logo depois.
    func confirmarCopia(_ id: UUID) throws {
        try atualizar(id) { $0.backupConfirmedAt = .now }
        let ficaParaAPassphrase = trava.withLock { rascunho?.carteira == id && rascunho?.passphrase != nil }
        if !ficaParaAPassphrase { descartarRascunho() }
    }

    /// Deixar de pedir a passphrase para mover saldo: pede a passphrase e o PIN (nunca so o rosto),
    /// conferida com a do cofre: quem viu o PIN nao tira a protecao.
    func naoPedirPassphrase(_ id: UUID, credencial: Credencial, digitada: SecureBytes) throws {
        defer { digitada.wipe() }
        do { try PortaDaPassphrase.comecar(id) } catch { credencial.zerar(); throw error }
        let confere: Bool
        do {
            confere = try comChaveRaiz(credencial) { rk in
                let secret = try Chaves.wallets.open(walletID: id, rk: rk)
                defer { secret.wipe() }
                return PortaDaPassphrase.confere(secret.passphrase, digitada)
            }
        } catch {
            PortaDaPassphrase.devolver(id)
            throw error
        }
        guard confere else {
            PortaDaPassphrase.errou(id)
            throw Signer.Failure.passphraseMismatch
        }
        PortaDaPassphrase.passou(id)
        try atualizar(id) { $0.passphraseToSend = false }
    }

    // MARK: Ver as palavras de uma carteira guardada

    /// Abre a frase de uma carteira guardada, para ver ou para a copia que faltou (o RevealFlow
    /// do iOS). Com a passphrase ligada para mover saldo, ela vem digitada e o cofre confere antes
    /// de qualquer palavra sair: quem tem o PIN e o rosto nao le a passphrase sem saber ela.
    func revelar(_ id: UUID, credencial: Credencial, passphraseDigitada: SecureBytes?) throws -> (palavras: Int, passphrase: Bool) {
        defer { passphraseDigitada?.wipe() }
        guard let wallet = metadata.wallets.first(where: { $0.id == id }), !wallet.isWatchOnly else {
            credencial.zerar()
            throw Falha.carteiraNaoEncontrada
        }
        let conferir = PortaDaPassphrase.pede(wallet) ? passphraseDigitada : nil
        if PortaDaPassphrase.pede(wallet), conferir == nil {
            credencial.zerar()
            throw Nucleo.Falha(erro: "envio.pedePassphrase")
        }
        if conferir != nil {
            do { try PortaDaPassphrase.comecar(id) } catch { credencial.zerar(); throw error }
        }
        let aberto: (SecureBytes, SecureBytes?)
        do {
            aberto = try comChaveRaiz(credencial) { rk in
                let secret = try Chaves.wallets.open(walletID: id, rk: rk)
                defer { secret.wipe() }
                if let conferir, !PortaDaPassphrase.confere(secret.passphrase, conferir) { throw Signer.Failure.passphraseMismatch }
                var pass: SecureBytes?
                if secret.passphrase.count > 0 {
                    let copia = SecureBytes(capacity: secret.passphrase.count)
                    secret.passphrase.withUnsafeBytes { copia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
                    pass = copia
                }
                return (try secret.phrase(), pass)
            }
        } catch {
            if conferir != nil {
                if (error as? Signer.Failure) == .passphraseMismatch { PortaDaPassphrase.errou(id) } else { PortaDaPassphrase.devolver(id) }
            }
            throw error
        }
        if conferir != nil { PortaDaPassphrase.passou(id) }
        let (frase, pass) = aberto
        let palavras = frase.withUnsafeBytes { raw in raw.filter { $0 == 0x20 }.count + 1 }
        // So guarda com a sessao aberta, sob a mesma trava do travar(): o app que travou durante a
        // abertura do cofre nao fica com as palavras na memoria (revisao de seguranca do Android de
        // 26/10/2026).
        guard mostrar(Rascunho(frase: frase, palavras: palavras, passphrase: pass, carteira: id)) else { throw Falha.travada }
        return (palavras, pass != nil)
    }

    /// A passphrase do rascunho aberto, so para mostrar junto das palavras.
    func passphraseDoRascunho() -> String? {
        trava.withLock { rascunho?.passphrase?.withUnsafeBytes { String(decoding: $0, as: UTF8.self) } }
    }

    /// Fechou a tela das palavras: a carteira anota quando elas foram vistas e o rascunho sai.
    func terminarRevelacao(_ id: UUID) {
        let eraDela = trava.withLock { rascunho?.carteira == id }
        if eraDela { try? atualizar(id) { $0.lastRevealedAt = .now } }
        descartarRascunho()
    }

    enum ConferenciaDaPassphrase: String, Encodable { case confere, naoConfere, antiga }

    /// A passphrase digitada de onde o dono anotou. Logo depois das palavras, compara com a do
    /// rascunho; sozinha (palavras ja conferidas), pelo cofre com o PIN, contando a tentativa.
    func conferirPassphrase(_ id: UUID, digitada: SecureBytes, credencial: Credencial?) throws -> ConferenciaDaPassphrase {
        defer { digitada.wipe() }
        func comparar(_ guardada: SecureBytes) -> ConferenciaDaPassphrase {
            let a = BIP39.nfkd(guardada), b = BIP39.nfkd(digitada)
            defer { a.wipe(); b.wipe() }
            guard a.count > 0, Hash.constantTimeEqual(a, b) else { return .naoConfere }
            // Gravada fora de NFKD por uma versao anterior.
            return Hash.constantTimeEqual(a, guardada) ? .confere : .antiga
        }
        let doRascunho = trava.withLock { () -> ConferenciaDaPassphrase? in
            guard let rascunho, rascunho.carteira == id, let guardada = rascunho.passphrase else { return nil }
            return comparar(guardada)
        }
        let resultado: ConferenciaDaPassphrase
        if let doRascunho {
            resultado = doRascunho
        } else {
            guard let credencial else { throw Nucleo.Falha(erro: "credencial desconhecida") }
            do { try PortaDaPassphrase.comecar(id) } catch { credencial.zerar(); throw error }
            do {
                resultado = try comChaveRaiz(credencial) { rk in
                    let secret = try Chaves.wallets.open(walletID: id, rk: rk)
                    defer { secret.wipe() }
                    return comparar(secret.passphrase)
                }
            } catch {
                PortaDaPassphrase.devolver(id)
                throw error
            }
            if resultado == .naoConfere { PortaDaPassphrase.errou(id) } else { PortaDaPassphrase.passou(id) }
        }
        if resultado == .confere {
            try atualizar(id) { $0.passphraseConfirmedAt = .now }
            descartarRascunho()
        }
        return resultado
    }

    func descartarRascunho() {
        trava.withLock {
            rascunho?.zerar()
            rascunho = nil
        }
    }

    /// As palavras de um envelope aberto, so para ver: o rascunho que a tela de gravar mostra de
    /// tres em tres, sem carteira guardada.
    /// Guarda o rascunho so com a sessao aberta, sob a trava do travar(); travada, zera o novo.
    @discardableResult
    func mostrar(_ novo: Rascunho) -> Bool {
        let guardou = trava.withLock { () -> Bool in
            guard chaveDeIndice != nil else { return false }
            rascunho?.zerar()
            rascunho = novo
            return true
        }
        if !guardou { novo.zerar() }
        return guardou
    }
}

/// A frase de uma carteira recem-criada, enquanto o dono anota e confere. As palavras so viram
/// `String` no grupo que esta na tela.
final class Rascunho: @unchecked Sendable {
    let frase: SecureBytes
    let palavras: Int
    /// Revelado de uma carteira guardada: a passphrase dela, quando tem, e de qual carteira e.
    let passphrase: SecureBytes?
    let carteira: UUID?

    init(frase: SecureBytes, palavras: Int, passphrase: SecureBytes? = nil, carteira: UUID? = nil) {
        self.frase = frase
        self.palavras = palavras
        self.passphrase = passphrase
        self.carteira = carteira
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

    func zerar() {
        frase.wipe()
        passphrase?.wipe()
    }
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
