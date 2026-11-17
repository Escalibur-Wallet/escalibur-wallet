import CryptoKit
import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import EscaliburNetwork
import Observation
import SwiftUI
import UserNotifications

/// Como o dono prova presenca para uma operacao que precisa da chave raiz.
enum Credential: Sendable {
    case pin(SecureBytes)
    case biometry(reason: String)
    /// O PIN e, com o Face ID ligado, o rosto tambem (A1): ver as palavras, lacrar o
    /// envelope, remover carteira, desligar o Face ID.
    case pinAndBiometry(SecureBytes, reason: String)
    /// Modo reforcado: o PIN e o rosto pela criptografia, em tudo (docs/seguranca.md §2.6).
    case hardened(SecureBytes, reason: String)
    /// Modo reforcado com o rosto ja confirmado antes do PIN (pedido do dono, 01/11/2026).
    case hardenedFace(SecureBytes, face: RootKeyVault.HardenedFacePass)

    /// O PIN e o rosto (ou o Super Security, que pede os dois em tudo): a presenca que ver as palavras, lacrar e remover pedem.
    var isFullPresence: Bool {
        switch self {
        case .pinAndBiometry, .hardened, .hardenedFace: return true
        case .pin, .biometry: return false
        }
    }

    /// Zera o PIN quando a operacao para antes de abrir a RK, que o zeraria la dentro (revisao da decima terceira passada).
    func wipe() {
        switch self {
        case .pin(let pin), .pinAndBiometry(let pin, _), .hardened(let pin, _), .hardenedFace(let pin, _): pin.wipe()
        case .biometry: break
        }
    }
}

/// O estado de alto nivel do app.
@MainActor
@Observable
final class AppSession {
    enum Phase: Equatable {
        /// Primeira abertura: boas-vindas e escolha do PIN.
        case onboarding
        case locked
        case unlocked
    }

    private(set) var phase: Phase
    var metadata = Metadata()
    /// A chave dos metadados. Existe so enquanto o app esta destrancado.
    private var indexKey: SymmetricKey?
    /// Instante da ida para o segundo plano no relogio monotonico, que conta o tempo
    /// dormindo e nao anda com o relogio de parede: atrasar o relogio nao evita o
    /// bloqueio automatico.
    private var backgroundedAt: TimeInterval?
    /// Fecha a folha de PIN aberta por cima ao travar (a do `AuthCoordinator`, que mora na raiz).
    @ObservationIgnored var onLock: (() -> Void)?

    init() {
        #if DEBUG
        // Testes de interface comecam do zero, como uma instalacao nova.
        if ProcessInfo.processInfo.arguments.contains("-reset") {
            KeyServices.root.wipeAll()
            MetadataStore.deleteFile()
            PriceAlertStore.erase()
        }
        #if targetEnvironment(simulator)
        // `-rosto-novo`: o simulador nao troca o cadastro de rostos de verdade. A vigia do modo
        // reforcado some como no aparelho, quando um rosto e cadastrado (a chave que segue o
        // cadastro morre; a que nao segue continua).
        if ProcessInfo.processInfo.arguments.contains("-rosto-novo") { KeyServices.wrapper.deleteKey(.hardenedBiometry) }
        #endif
        #endif
        // Os alertas de preco abrem o app em segundo plano, as vezes com o iPhone
        // bloqueado: ai o chaveiro nao responde. `isSetUp` le "nao sei" como configurado,
        // e o app abre travado, nunca na criacao do PIN.
        phase = KeyServices.root.isSetUp ? .locked : .onboarding
        launchChecks()
        // Este init roda antes de o iOS terminar de abrir o app, e ai
        // `isProtectedDataAvailable` ainda diz "nao" com o iPhone desbloqueado (visto em
        // 16/10/2026): a limpeza da instalacao nova nunca rodava, e quem reinstalava o app
        // achava o PIN e o cofre da instalacao anterior no chaveiro. As conferencias de
        // abertura rodam de novo quando o app termina de abrir e quando os dados
        // protegidos ficam disponiveis (o app aberto em segundo plano antes do primeiro
        // desbloqueio), uma vez so.
        guard !launchChecked else { return }
        launchObservers = [UIApplication.didFinishLaunchingNotification, UIApplication.protectedDataDidBecomeAvailableNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.launchChecks() }
            }
        }
    }

    /// As conferencias de abertura, que precisam do chaveiro e dos arquivos protegidos:
    /// a limpeza da instalacao nova, o relogio das tentativas e, sem cofre, os arquivos
    /// do segundo plano. So rodam com os dados protegidos disponiveis, e uma vez so.
    @ObservationIgnored private var launchChecked = false
    @ObservationIgnored private var launchObservers: [any NSObjectProtocol] = []

    private func launchChecks() {
        guard !launchChecked, UIApplication.shared.isProtectedDataAvailable else { return }
        launchChecked = true
        launchObservers.forEach(NotificationCenter.default.removeObserver)
        launchObservers = []
        // A limpeza apagou o cofre de uma instalacao anterior: o app abre na criacao do
        // PIN, nunca no PIN que sobrou no chaveiro, e nada da sessao fica de pe, qualquer
        // que seja a fase.
        if KeyServices.firstLaunchCleanup() {
            indexKey = nil
            metadata = Metadata()
            phase = .onboarding
        }
        // A contagem de tentativas que veio de outro boot; com o chaveiro mudo, fica para
        // a volta ao primeiro plano (`scenePhaseChanged`).
        KeyServices.root.rebaseAttempts()
        if phase == .locked, !KeyServices.root.isSetUp { phase = .onboarding }
        // Sem chaves (o codigo do iPhone foi tirado e o chaveiro apagou o cofre, ou uma
        // instalacao nova): o que o segundo plano guardava fora do cofre nao tem mais dono
        // (pentest de 14/10/2026, B6).
        if phase == .onboarding {
            Self.eraseBackgroundFiles()
            Preferences.receiptWatchChosen = false
            Preferences.receiptOfferSeen = false
            Preferences.priceAlertsChosen = false
        }
    }

    /// O que o segundo plano guarda fora do cofre (enderecos e ultimo saldo do aviso de
    /// recebimento, UIDs das ordens, alertas de preco), apagado na hora, com a agenda e os
    /// avisos pendentes junto. Nada disso espera um `Task`: o app pode fechar antes.
    static func eraseBackgroundFiles() {
        ReceiptWatchStore.erase()
        LimitOrderWatchStore.erase()
        PriceAlertStore.erase()
        NoticeKey.erase()
        WidgetFeed.erase()
        ImageLoader.eraseStored()
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        BackgroundCheck.reschedule()
    }

    /// Os enderecos EVM da carteira, em hex minusculo sem `0x`: o dono que o UID da CoW traz.
    nonisolated static func evmOwners(_ meta: WalletMeta) -> Set<String> {
        Set(Chain.all.filter { $0.family == .evm }.compactMap { chain in
            meta.account(chain).map { $0.address.lowercased().replacingOccurrences(of: "0x", with: "") }
        })
    }

    var selectedWallet: WalletMeta? { metadata.selectedWallet }
    var currency: Fmt.Currency { Fmt.Currency(rawValue: metadata.settings.currency.uppercased()) ?? .brl }

    // MARK: PIN e desbloqueio

    /// Cadastra o PIN. O Argon2 do PIN roda fora do MainActor.
    func setUpPIN(_ pin: SecureBytes) async throws {
        let key: SymmetricKey = try await Offload.run {
            defer { pin.wipe() }
            let rk = try KeyServices.root.setUp(pin: pin)
            defer { rk.wipe() }
            return IndexCipher.key(from: rk)
        }
        indexKey = key
        metadata = Metadata()
        // Nada de uma instalacao anterior espera o destravar desta (um envio que terminou depois de apagar tudo; revisao, 08/11/2026).
        afterUnlock = []
        try persist()
        phase = .unlocked
    }

    func unlock(pin: SecureBytes) async throws {
        let epoch = lockEpoch
        let reason = String(localized: "Destravar a Escalibur")
        let (key, updates) = try await Offload.run {
            defer { pin.wipe() }
            // No modo reforcado, abrir o app tambem pede o rosto depois do PIN. E o unico uso que
            // a espera de "Esperar 24 horas" deixa passar: o saldo aparece, o resto espera.
            let rk = KeyServices.root.securityMode == .hardened
                ? try KeyServices.root.unlockHardened(pin: pin, reason: reason, use: .openApp)
                : try KeyServices.root.unlock(pin: pin)
            defer { rk.wipe() }
            return (IndexCipher.key(from: rk), Self.unlockUpdates(rk: rk))
        }
        try open(with: key, adding: updates, epoch: epoch)
    }

    /// Super Security: o rosto antes do PIN, para abrir o app (pedido do dono, 01/11/2026). O cofre
    /// guarda o rosto confirmado para um PIN so, por 2 minutos.
    func hardenedFace(reason: String) async throws -> RootKeyVault.HardenedFacePass {
        try await Offload.run { try KeyServices.root.hardenedFace(reason: reason, use: .openApp) }
    }

    /// Abre o app com o PIN e o rosto ja confirmado em `hardenedFace`.
    func unlock(pin: SecureBytes, face: RootKeyVault.HardenedFacePass) async throws {
        let epoch = lockEpoch
        let (key, updates) = try await Offload.run {
            defer { pin.wipe() }
            let rk = try KeyServices.root.unlockHardened(pin: pin, face: face, use: .openApp)
            defer { rk.wipe() }
            return (IndexCipher.key(from: rk), Self.unlockUpdates(rk: rk))
        }
        try open(with: key, adding: updates, epoch: epoch)
    }

    func unlockWithBiometry() async throws {
        let epoch = lockEpoch
        let (key, updates) = try await Offload.run {
            let rk = try KeyServices.root.unlockWithBiometry(reason: String(localized: "Destravar a Escalibur"))
            defer { rk.wipe() }
            return (IndexCipher.key(from: rk), Self.unlockUpdates(rk: rk))
        }
        try open(with: key, adding: updates, epoch: epoch)
    }

    /// O que o destravar acerta nas carteiras, com a RK aberta.
    struct UnlockUpdates: Sendable {
        var accounts: [UUID: [DerivedAccount]] = [:]
    }

    /// Redes que entraram numa versao nova ainda nao tem endereco nas carteiras
    /// antigas. Como a RK ja esta aberta neste desbloqueio, os enderecos que faltam
    /// sao derivados agora, sem pedir o Face ID de novo. Cada registro e zerado ao
    /// fim da derivacao. A carteira com passphrase fica para a proxima assinatura,
    /// quando a passphrase e digitada (`PassphraseGate.sign`): o cofre nao a tem.
    ///
    /// E a passphrase que uma versao anterior gravou sai do cofre, no primeiro destravar
    /// depois de atualizar (pedido do dono, 05/11/2026). A que estava fora de NFKD deixa so a
    /// marca `legacyCardanoPassphrase`, gravada antes de ela sair: sem a marca gravada, ela
    /// espera o proximo destravar. Se o chaveiro recusar, tambem; o registro aberto ja nao a
    /// devolve a ninguem.
    nonisolated private static func unlockUpdates(rk: SecureBytes) -> UnlockUpdates {
        let key = IndexCipher.key(from: rk)
        guard var metadata = try? MetadataStore.load(key: key) else { return UnlockUpdates() }
        // Os fatos sobre a antiga (fora de NFKD; nao da a raiz da criacao) viram marcas, gravadas antes de ela sair: sem as
        // marcas gravadas, ela espera o proximo destravar.
        var found: [(id: UUID, legacy: Bool, verified: Bool)] = []
        for wallet in metadata.wallets where wallet.hasPassphrase && !wallet.isWatchOnly {
            let fingerprint = wallet.fingerprint.flatMap(Hex.decode)
            if case .present(let legacy, let verified) = try? KeyServices.wallets.storedPassphrase(walletID: wallet.id, rk: rk, fingerprint: fingerprint) {
                found.append((wallet.id, legacy, verified))
            }
        }
        let marks = found.filter { $0.legacy || !$0.verified }
        var marked = true
        if !marks.isEmpty {
            for index in metadata.wallets.indices {
                guard let mark = marks.first(where: { $0.id == metadata.wallets[index].id }) else { continue }
                if mark.legacy { metadata.wallets[index].legacyCardanoPassphrase = true }
                if !mark.verified { metadata.wallets[index].passphraseUnverified = true }
            }
            marked = (try? MetadataStore.save(metadata, key: key)) != nil
        }
        for item in found where marked || !(item.legacy || !item.verified) {
            _ = try? KeyServices.wallets.purgePassphrase(walletID: item.id, rk: rk)
        }
        // E a de um registro sem carteira na lista, que uma versao anterior deixou ao parar no meio de gravar.
        let listed = Set(metadata.wallets.map(\.id))
        for id in KeyServices.wallets.storedWalletIDs() where !listed.contains(id) {
            _ = try? KeyServices.wallets.purgePassphrase(walletID: id, rk: rk)
        }
        var result = UnlockUpdates()
        var updates: [UUID: [DerivedAccount]] = [:]
        // Carteira so de observacao de endereco EVM: o mesmo endereco vale nas redes EVM
        // novas, como em `addWatchWallet`. Nada e derivado; so se repete o endereco.
        for wallet in metadata.wallets where wallet.isWatchOnly {
            guard let evm = wallet.accounts.first(where: { Chain.find($0.chainID)?.family == .evm }) else { continue }
            let have = Set(wallet.accounts.map(\.chainID))
            let missing = Chain.evmChains.filter { !have.contains($0.id) }
            guard !missing.isEmpty else { continue }
            updates[wallet.id] = missing.map {
                DerivedAccount(chainID: $0.id, path: evm.path, address: evm.address, publicKey: evm.publicKey, accountXPub: nil)
            }
        }
        for wallet in metadata.wallets where !wallet.isWatchOnly && !wallet.hasPassphrase {
            let have = Set(wallet.accounts.map(\.chainID))
            let missing = Chain.all.filter { !have.contains($0.id) }
            guard !missing.isEmpty, let secret = try? KeyServices.wallets.open(walletID: wallet.id, rk: rk) else { continue }
            defer { secret.wipe() }
            if let (accounts, _) = try? AccountDeriver.derive(secret, chains: missing), !accounts.isEmpty {
                updates[wallet.id] = accounts
            }
        }
        result.accounts = updates
        return result
    }

    /// As redes que nasceram numa assinatura da carteira com passphrase. So as que ainda faltam.
    func addAccounts(_ accounts: [DerivedAccount], to walletID: UUID) {
        guard phase == .unlocked, let index = metadata.wallets.firstIndex(where: { $0.id == walletID }) else { return }
        let have = Set(metadata.wallets[index].accounts.map(\.chainID))
        let fresh = accounts.filter { !have.contains($0.chainID) }
        guard !fresh.isEmpty else { return }
        metadata.wallets[index].accounts += fresh
        try? persist()
    }

    /// Cada `lock()` soma um. O destravar que comecou antes de um travar (o iPhone bloqueado durante o
    /// Argon2) nao termina abrindo o app: o `open` posterior desfazia o `lock()` do
    /// `protectedDataWillBecomeUnavailable` (revisao de seguranca do iPhone de 27/10/2026).
    private(set) var lockEpoch = 0

    private func open(with key: SymmetricKey, adding unlocked: UnlockUpdates = UnlockUpdates(), epoch: Int) throws {
        guard epoch == lockEpoch else { throw WalletError.locked }
        metadata = try MetadataStore.load(key: key)
        indexKey = key
        // A moeda dos precos segue a unidade de Ativos. Metadados de antes de 12/10/2026
        // podiam ter as duas diferentes (Ajustes em real, Ativos em dolar).
        if metadata.settings.choose(metadata.settings.displayUnit) {
            metadata.quoteCache = [:]
            try? persist()
        }
        if !unlocked.accounts.isEmpty {
            for (id, accounts) in unlocked.accounts {
                guard let index = metadata.wallets.firstIndex(where: { $0.id == id }) else { continue }
                metadata.wallets[index].accounts += accounts
            }
            try? persist()
        }
        refreshHardenedHold()
        withAnimation(Motion.fade) { phase = .unlocked }
        PassphraseGate.shared.applyPending(self)
        let queued = afterUnlock
        afterUnlock = []
        for change in queued { change(self) }
        NoticeMigration.runOnce(self)
        scheduleControlChecks()
        // O cache de saldo e o historico de carteira que nao existe mais saem: uma leitura que terminou depois da remocao
        // os regravava (decima terceira passada da auditoria de 03/11/2026 e a revisao dela).
        let carteiras = Set(metadata.wallets.map(\.id))
        let prefixes = carteiras.map { $0.uuidString + "|" }
        if metadata.balanceCache.keys.contains(where: { !carteiras.contains($0) })
            || (metadata.activityCache ?? [:]).keys.contains(where: { !carteiras.contains($0) })
            || (metadata.activityFetched ?? [:]).keys.contains(where: { !carteiras.contains($0) })
            || (metadata.pendingEVM ?? [:]).keys.contains(where: { key in !prefixes.contains { key.hasPrefix($0) } }) {
            metadata.balanceCache = metadata.balanceCache.filter { carteiras.contains($0.key) }
            metadata.activityCache = metadata.activityCache?.filter { carteiras.contains($0.key) }
            metadata.activityFetched = metadata.activityFetched?.filter { carteiras.contains($0.key) }
            metadata.pendingEVM = metadata.pendingEVM?.filter { item in prefixes.contains { item.key.hasPrefix($0) } }
            try? persist()
        }
        // E os mapas por ativo com o que nenhuma carteira tem mais (o resto de uma leitura que terminou depois de remover).
        var pruned = metadata
        Self.pruneAssetMaps(&pruned)
        if pruned.quoteCache != metadata.quoteCache || pruned.recognizedTokens != metadata.recognizedTokens
            || pruned.unrecognizedChecks != metadata.unrecognizedChecks || pruned.tokenLogos != metadata.tokenLogos {
            metadata = pruned
            try? persist()
        }
    }

    /// O que a tela guarda na memoria de uma carteira (o Portfolio, que e do App, e o historico e as ordens vencidas):
    /// sai ao travar e ao apagar tudo, e ao remover a carteira que esta na tela, e uma leitura em curso dela nao grava
    /// mais nada (revisao da decima terceira passada; o Android ja esquecia ao travar).
    var onForget: ((UUID?) -> Void)?

    private func forgetMemory(_ wallet: UUID? = nil) {
        onForget?(wallet)
        ActivityFeed.shared.forget(wallet)
        LimitRenewalCenter.shared.forget(wallet)
    }

    /// Os mapas por ativo (a cotacao por contrato, o reconhecimento de token e as logos) so com o que as carteiras que
    /// ficam tem no cache de saldo: os tokens que so a removida tinha saem com ela (revisao da decima terceira passada).
    /// `keeping`: o que a leitura em curso tem na memoria e o cache de saldo ainda nao tem.
    static func pruneAssetMaps(_ metadata: inout Metadata, keeping extra: Set<String> = []) {
        let held = Set(metadata.balanceCache.values.flatMap(\.values).flatMap { balance in
            balance.holdings.map(\.asset.id) + (balance.unlisted ?? []).map(\.asset.id)
        }).union(extra)
        metadata.recognizedTokens = metadata.recognizedTokens?.filter { held.contains($0.key) }
        metadata.unrecognizedChecks = metadata.unrecognizedChecks?.filter { held.contains($0.key) }
        metadata.tokenLogos = metadata.tokenLogos?.filter { held.contains($0.key) }
        let prefix = Portfolio.contractQuotePrefix
        metadata.quoteCache = metadata.quoteCache.filter { key, _ in !key.hasPrefix(prefix) || held.contains(String(key.dropFirst(prefix.count))) }
    }

    /// O que terminou depois de o app travar e precisa ir para os metadados: a ponte ou a ordem
    /// que saiu enquanto o app travava (caca de bugs de 25/10/2026). Travado, os metadados nao estao
    /// na memoria e gravar ali nao fazia nada; a mudanca espera o proximo destravar e vale por cima
    /// dos metadados de verdade. Se o app fechar antes, ela se perde, como antes.
    private var afterUnlock: [(AppSession) -> Void] = []

    func whenUnlocked(_ change: @escaping (AppSession) -> Void) {
        guard phase == .unlocked, indexKey != nil else {
            afterUnlock.append(change)
            return
        }
        change(self)
    }

    /// O app travou ou foi apagado: o que so pode existir destravado sai na hora (as palavras de uma importacao em curso). Ao
    /// contrario do `SecureInputField.wipeAll`, nao sai ao ir para o fundo: a previa manda comparar os enderecos noutro app.
    static let didLock = Notification.Name("escalibur.session.didLock")

    func lock() {
        // A folha de PIN, de passphrase ou de voz aberta por cima recebe "fechou": nada digitado
        // nela leva uma operacao adiante com o app travado (auditoria 6, A6-05).
        lockEpoch &+= 1
        onLock?()
        PassphraseGate.shared.cancel()
        VoiceGate.shared.cancel()
        PassphraseGate.shared.clearGrace()
        NotificationCenter.default.post(name: SecureInputField.wipeAll, object: nil)
        // Na hora do aviso, e nao quando a tela sair: suspenso, o SwiftUI so tira a tela na volta (revisao dos 3 agentes, 08/11/2026).
        NotificationCenter.default.post(name: Self.didLock, object: nil)
        // Um rosto do Super Security confirmado e ainda sem PIN nao vale depois de travar.
        KeyServices.root.discardHardenedFace()
        // As conferencias das carteiras com passphrase param: a tarefa guardava as contas dela na memoria com o app travado
        // (rodada 3 da auditoria 8). A que nao terminou a primeira e conferida de novo quando escolhida (rodada 4).
        for wallet in metadata.wallets where wallet.hasPassphrase { cancelControlChecks(of: wallet.id) }
        // Travado, a tela da previa sai: a marca dela nao segura a rodada do dia depois de destravar (rodada 6).
        previewOpen = false
        tronReadAt = [:]
        indexKey = nil
        metadata = Metadata()
        forgetMemory()
        withAnimation(Motion.fade) { phase = .locked }
    }

    /// Trava ao voltar do segundo plano depois do tempo escolhido (padrao 1 minuto).
    /// Sair do app ja cobre a tela na hora; isto decide se pede o PIN de novo.
    func scenePhaseChanged(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .background:
            backgroundedAt = PINPolicy.uptime
            // A copia da passphrase da folga nao fica para a volta: sair do app a zera (pedido do dono, 05/11/2026). E a
            // folha da passphrase e a do PIN abertas fecham, com o que estava digitado zerado: suspenso, o app nao recebe o
            // aviso de o iPhone bloquear, e a digitada ficaria na memoria ate a volta.
            PassphraseGate.shared.cancel()
            onLock?()
            PassphraseGate.shared.clearGrace()
            NotificationCenter.default.post(name: SecureInputField.wipeAll, object: nil)
            // Um rosto do Super Security confirmado e ainda sem PIN nao fica para a volta.
            KeyServices.root.discardHardenedFace()
        case .active:
            DeviceIntegrity.recheck()
            // Fora da thread principal: com um PIN sendo cadastrado ou conferido (dois
            // Argon2, segundos), o cofre fica trancado, e esperar por ele aqui congelava
            // a tela inteira (amostra de 15/10/2026: a espada da abertura parada no
            // mutex). O `unlock` refaz esta conta por conta propria, dentro do cofre.
            Task {
                await Offload.compute { KeyServices.root.rebaseAttempts() }
                if phase == .unlocked { refreshHardenedHold() }
            }
            if phase == .unlocked, let since = backgroundedAt,
               PINPolicy.uptime - since >= Double(AutoLockView.clamped(metadata.settings.autoLockSeconds)) {
                lock()
            }
            backgroundedAt = nil
        default:
            break
        }
    }

    /// O iPhone foi bloqueado: os dados protegidos vao sumir. Trava na hora.
    func deviceWillLock() {
        if phase == .unlocked { lock() }
    }

    // MARK: Operacoes com a chave raiz

    /// Destranca a RK com presenca nova e executa `body` com ela, de forma
    /// sincrona, fora do MainActor. A RK nao atravessa nenhum `await`: nasce, e usada
    /// e zerada dentro da mesma funcao sincrona (docs/seguranca.md §2.9).
    func withRootKey<T: Sendable>(_ credential: Credential, _ body: @escaping @Sendable (SecureBytes) throws -> T) async throws -> T {
        DeviceIntegrity.recheck()
        do {
            return try await rootKeyTask(credential, body)
        } catch RootKeyVault.Failure.wiped {
            // O decimo erro veio de uma folha de PIN no meio de uma operacao: o cofre
            // ja apagou as chaves, e os metadados vao junto.
            eraseEverything()
            throw RootKeyVault.Failure.wiped
        }
    }

    private func rootKeyTask<T: Sendable>(_ credential: Credential, _ body: @escaping @Sendable (SecureBytes) throws -> T) async throws -> T {
        try await Offload.run {
            let rk: SecureBytes
            switch credential {
            case .pin(let pin):
                defer { pin.wipe() }
                rk = try KeyServices.root.unlock(pin: pin)
            case .biometry(let reason):
                rk = try KeyServices.root.unlockWithBiometry(reason: reason)
            case .pinAndBiometry(let pin, let reason):
                defer { pin.wipe() }
                rk = try KeyServices.root.unlockWithPINAndBiometry(pin: pin, reason: reason)
            case .hardened(let pin, let reason):
                defer { pin.wipe() }
                rk = try KeyServices.root.unlockHardened(pin: pin, reason: reason)
            case .hardenedFace(let pin, let face):
                defer { pin.wipe() }
                rk = try KeyServices.root.unlockHardened(pin: pin, face: face, use: .operation)
            }
            defer { rk.wipe() }
            return try body(rk)
        }
    }

    var biometryEnabled: Bool { KeyServices.root.isBiometryEnabled }

    /// Liga o Face ID. O cofre confere na hora que o slot novo abre com o rosto e devolve a
    /// mesma RK, e decide se a espera do A1 comeca (religar depois de uma queda).
    func enableBiometry(pin: SecureBytes) async throws {
        let reason = String(localized: "Confirme o \(KeyServices.biometryName) para ligar")
        do {
            try await Offload.run {
                defer { pin.wipe() }
                let rk = try KeyServices.root.unlock(pin: pin)
                defer { rk.wipe() }
                try KeyServices.root.enableBiometry(rk: rk, reason: reason)
            }
        } catch RootKeyVault.Failure.wiped {
            // O PIN errado desta folha foi o que disparou o apagar apos erros: o cofre ja
            // apagou as chaves, e a sessao vai junto (auditoria 4, C7-10).
            eraseEverything()
            throw RootKeyVault.Failure.wiped
        }
        metadata.settings.biometryEnabled = true
        try persist()
    }

    /// Desliga o Face ID com o PIN e o rosto (A1): com ele desligado, ver as palavras passa
    /// a pedir so o PIN. A credencial vem de `AuthCoordinator.retrying(presence:
    /// .pinAndBiometry)`.
    func disableBiometry(_ credential: Credential) async throws {
        guard case .pinAndBiometry(let pin, let reason) = credential else { throw RootKeyVault.Failure.biometryRequired }
        do {
            try await Offload.run {
                defer { pin.wipe() }
                try KeyServices.root.disableBiometry(pin: pin, reason: reason)
            }
        } catch RootKeyVault.Failure.wiped {
            eraseEverything()
            throw RootKeyVault.Failure.wiped
        }
        metadata.settings.biometryEnabled = false
        try? persist()
    }

    // MARK: Modo reforcado

    var hardenedModeOn: Bool { KeyServices.root.securityMode == .hardened }
    /// Super Security em "Bloquear as carteiras": nenhuma carteira com palavras entra (pedido do dono, 06/11/2026). As palavras
    /// inteiras de cada carteira sao conferidas ao escolher "Bloquear"; uma adicionada depois ficaria presa a um papel nunca
    /// conferido inteiro. Troca a politica, adiciona, e volta: o app pede as palavras de todas. So observar continua.
    var addingWordsBlocked: Bool { Self.wordsBlocked(KeyServices.root) }

    /// Na duvida, recusa: o chaveiro mudo, ou o cabecalho do Super Security ilegivel, contam como "Bloquear" (revisao de
    /// seguranca de 06/11/2026). Sem trava propria do cofre: vale tambem com a RK aberta, logo antes de gravar.
    nonisolated static func wordsBlocked(_ root: RootKeyVault) -> Bool {
        switch root.securityMode {
        case .normal: return false
        case .unknown: return true
        case .hardened: return root.hardenedFaceChange.map { $0 == .lock } ?? true
        }
    }
    /// As palavras no teclado proprio: escolhido em Seguranca, ou sempre no modo reforcado.
    var ownKeyboardOn: Bool {
        #if DEBUG
        // `-teclado-proprio`: ligado, para ver o teclado sem passar pelos Ajustes.
        if DebugDemo.arguments.contains("-teclado-proprio") { return true }
        #endif
        return metadata.settings.ownKeyboard == true || hardenedModeOn
    }

    /// Todo envio pede os 6 ultimos caracteres do destino: a opcao de Seguranca, ou o Super
    /// Security, que a deixa sempre ligada.
    var confirmEveryAddressOn: Bool {
        metadata.settings.confirmEveryAddress == true || hardenedModeOn
    }

    /// O que o modo reforcado faz quando o Face ID muda. Nil fora dele.
    var hardenedFaceChange: RootKeyVault.HardenedFaceChange? { KeyServices.root.hardenedFaceChange }

    /// O que falta da espera de "Esperar 24 horas", para a faixa da Carteira e de Seguranca.
    /// Relido ao abrir o app, ao voltar para ele e depois de cada mudanca do modo: o cofre nao
    /// e observavel.
    private(set) var hardenedHold: TimeInterval = 0

    func refreshHardenedHold() {
        hardenedHold = KeyServices.root.hardenedHoldRemaining
    }

    /// Liga o modo reforcado. O cofre pede o PIN e o rosto pelo slot de hoje, roda a
    /// conferencia das palavras com a RK aberta (`check`), grava o rk.and com as chaves de
    /// `faceChange`, abre de novo com PIN e rosto, e so entao apaga o slot so-PIN.
    func enableHardened(pin: SecureBytes, faceChange: RootKeyVault.HardenedFaceChange,
                        check: @escaping @Sendable (SecureBytes) throws -> Void) async throws {
        let reason = String(localized: "Ligar o Super Security")
        let confirm = String(localized: "Confirme o \(KeyServices.biometryName) para conferir o Super Security")
        do {
            try await Offload.run {
                defer { pin.wipe() }
                try KeyServices.root.enableHardened(pin: pin, reason: reason, confirmReason: confirm, faceChange: faceChange, check: check)
            }
        } catch RootKeyVault.Failure.wiped {
            eraseEverything()
            throw RootKeyVault.Failure.wiped
        }
        metadata.settings.biometryEnabled = false
        try? persist()
    }

    /// Desliga o modo reforcado: o slot do PIN e o Face ID voltam, conferidos. Devolve se o
    /// Face ID voltou (o segundo rosto pode ser recusado; ai fica desligado).
    func disableHardened(pin: SecureBytes) async throws -> Bool {
        let reason = String(localized: "Desligar o Super Security")
        let biometry = String(localized: "Confirme o \(KeyServices.biometryName) para religar")
        let restored: Bool
        do {
            restored = try await Offload.run {
                defer { pin.wipe() }
                return try KeyServices.root.disableHardened(pin: pin, reason: reason, biometryReason: biometry)
            }
        } catch RootKeyVault.Failure.wiped {
            eraseEverything()
            throw RootKeyVault.Failure.wiped
        }
        metadata.settings.biometryEnabled = restored
        try? persist()
        return restored
    }

    /// Muda o que acontece quando o Face ID muda: PIN e rosto, as palavras de cada carteira
    /// so na ida para "Bloquear as carteiras" (`check`, que o cofre so roda nela), e o rosto de
    /// novo para conferir o registro novo antes de valer.
    func setHardenedFaceChange(_ target: RootKeyVault.HardenedFaceChange, pin: SecureBytes,
                               check: @escaping @Sendable (SecureBytes) throws -> Void) async throws {
        let reason = String(localized: "Mudar o que acontece quando o \(KeyServices.biometryName) mudar")
        let confirm = String(localized: "Confirme o \(KeyServices.biometryName) para conferir o Super Security")
        do {
            try await Offload.run {
                defer { pin.wipe() }
                try KeyServices.root.setHardenedFaceChange(target, pin: pin, reason: reason, confirmReason: confirm, check: check)
            }
        } catch RootKeyVault.Failure.wiped {
            eraseEverything()
            throw RootKeyVault.Failure.wiped
        }
    }

    // MARK: Carteiras

    /// Guarda uma carteira nova ou importada. A RK so existe durante esta chamada.
    /// `select` falso guarda sem trocar a carteira em uso (envelope, que pode ter vindo de
    /// outra pessoa). Nome repetido ganha a origem junto: o envelope de terceiro chamado
    /// "Carteira principal" nunca se confunde com a do dono.
    func addWallet(
        secret: WalletSecret, name: String, origin: WalletMeta.Origin, wordCount: Int,
        backupConfirmed: Bool, select: Bool = true, tronForeignControl: Bool = false, foreignControl: [String: ForeignControl]? = nil,
        chosenWords: Bool = false,
        passphraseConfirmed: Bool = false, legacyCardano: Bool = false, expectedFingerprint: String? = nil, credential: Credential
    ) async throws -> WalletMeta {
        guard !addingWordsBlocked else {
            secret.wipe()
            credential.wipe()
            throw WalletError.lockPolicy
        }
        let id = UUID()
        let hasPassphrase = secret.passphrase.count > 0
        // O autoteste antes de abrir a RK, e a derivacao antes de gravar: se ela falha, nada fica no cofre (a frase ficava
        // guardada sem carteira, longe do "Remover"; revisao da decima terceira passada).
        // Fora da thread principal: a primeira conferencia leva dezenas de milissegundos.
        do { try await Offload.run { try DerivationSelfTest.require() } } catch { secret.wipe(); credential.wipe(); throw error }
        // A carteira que ja esta aqui nao e gravada de novo: gravar e depois apagar deixava um registro se o apagar
        // falhasse (revisao da decima terceira passada).
        let known = Set(metadata.wallets.filter { !$0.isWatchOnly }.map(\.fingerprint))
        let (accounts, fingerprint, saved): ([DerivedAccount], [UInt8], Bool) = try await withRootKey(credential) { rk in
            defer { secret.wipe() }
            let derived = try AccountDeriver.derive(secret)
            // A importacao so grava a carteira da digital que o dono conferiu na previa, na mesma derivacao que vai ao cofre
            // (revisao de blockchain de 05/11/2026).
            if let expectedFingerprint, derived.fingerprint.hex.uppercased() != expectedFingerprint.uppercased() {
                throw WalletError.importChanged
            }
            guard !known.contains(derived.fingerprint.hex) else { return (derived.accounts, derived.fingerprint, false) }
            // De novo com o cofre aberto, logo antes de gravar: a politica pode ter mudado no meio.
            guard !Self.wordsBlocked(KeyServices.root) else { throw WalletError.lockPolicy }
            try KeyServices.wallets.save(secret, walletID: id, rk: rk)
            return (derived.accounts, derived.fingerprint, true)
        }
        // Travou enquanto o cofre abria: a frase ja foi guardada, mas a lista nao vai gravar. Ela sai
        // agora, ou ficaria no chaveiro sem carteira nenhuma, longe do "Remover" (caca de bugs de 27/10/2026).
        guard phase == .unlocked, indexKey != nil else {
            if saved { try? KeyServices.wallets.delete(id) }
            throw WalletError.locked
        }
        if let existing = metadata.wallets.first(where: { $0.fingerprint == fingerprint.hex && !$0.isWatchOnly }) {
            if saved { try? KeyServices.wallets.delete(id) }
            // A delegacao que a previa viu vale para a carteira que ja estava, e ela e conferida (rodada 5 da auditoria 8). So se
            // for a mesma conta EVM: a digital tem 4 bytes, e uma frase moida com a digital da vitima marcava a carteira dela.
            let sameEVM = Set(accounts.filter { Chain.find($0.chainID)?.family == .evm }.map { $0.address.lowercased() })
                .isSubset(of: Set(existing.accounts.map { $0.address.lowercased() }))
            // A Tron que a previa viu tambem: a conferencia dela, e a marca so com dois de acordo (rodada 6).
            if sameEVM, tronForeignControl || foreignControl?.isEmpty == false,
               let index = metadata.wallets.firstIndex(where: { $0.id == existing.id }) {
                if let foreignControl, !foreignControl.isEmpty {
                    metadata.wallets[index].foreignControl = ForeignControlCheck.apply(foreignControl.mapValues { .foreign($0) },
                                                                                       to: metadata.wallets[index].foreignControl, startingFrom: nil)
                    try? persist()
                    withdrawBlockedCopy(existing.id)
                }
                _ = checkTronControl(existing.id)
                checkForeignControl(existing.id)
            }
            throw WalletError.alreadyImported(existing.name)
        }
        // Estava aqui quando o cofre abriu e saiu no meio: nada foi gravado, e nada e criado.
        guard saved else { throw WalletError.changedDuringSave }
        var wallet = WalletMeta(
            id: id, name: uniqueName(name, origin: origin), kind: .phrase(wordCount: wordCount), origin: origin, createdAt: .now,
            accounts: accounts, fingerprint: fingerprint.hex, hasPassphrase: hasPassphrase,
            backupConfirmedAt: backupConfirmed ? .now : nil
        )
        if tronForeignControl { wallet.tronForeignControl = true }
        // A delegacao EVM que a previa viu, com dois operadores de acordo, nasce como marca, como a da Tron (rodada 4 da
        // auditoria 8): o envelope que nao fica escolhido so seria conferido quando escolhido.
        if let foreignControl, !foreignControl.isEmpty { wallet.foreignControl = foreignControl }
        if chosenWords { wallet.chosenWords = true }
        // As marcas do envelope de antes nascem com a carteira, e nao numa gravacao depois (revisao de blockchain de 05/11/2026).
        if wallet.hasPassphrase, passphraseConfirmed { wallet.passphraseConfirmedAt = .now }
        if wallet.hasPassphrase, legacyCardano { wallet.legacyCardanoPassphrase = true }
        metadata.wallets.append(wallet)
        // A mesma conta de volta (removida e importada de novo nesta sessao) volta a ter os avisos de ordem.
        let returning = Self.evmOwners(wallet)
        Task { await LimitOrderWatch.shared.remember(owners: returning) }
        if select || metadata.selectedWalletID == nil { metadata.selectedWalletID = id }
        do { try persist() } catch {
            metadata.wallets.removeAll { $0.id == id }
            try? KeyServices.wallets.delete(id)
            throw error
        }
        // A frase importada ou o envelope aberto, conferidos logo depois de gravar, como no Android: sem isso, o Copiar
        // endereco, os Ajustes e as Minhas carteiras ficavam abertos ate o proximo destravar numa conta com varredor, e a W5
        // da TON nao era procurada (rodada 3 da auditoria 8). A carteira criada aqui nao tem o que ler, e a consulta so
        // entregaria os enderecos novos aos operadores; so a escolhida, como na rodada do dia.
        // O envelope tambem quando nao fica escolhido: a previa ja consultou a EVM e a Tron dele, deste IP, segundos antes, e sem
        // isso ele so seria conferido quando escolhido, aberto no Minhas carteiras de quem paga a taxa (rodada 4).
        // A que passa a ser escolhida: o que ainda consultava a de antes para (rodada 4 da auditoria 8). O envelope que nao fica
        // escolhido tambem: conferido agora, ele nao sai junto com a rodada da escolhida.
        if metadata.selectedWalletID == id || origin == .importedEnvelope { pauseControlChecks(keeping: id) }
        if origin != .created || chosenWords, metadata.selectedWalletID == id || origin == .importedEnvelope {
            // So a sem passphrase entra na excecao da pausa: a com passphrase nunca sai junto com outra (rodada 5).
            if !wallet.hasPassphrase { firstChecks.insert(id) }
            _ = checkTronControl(id)
            checkForeignControl(id)
            _ = checkTONVersion(id)
        }
        return wallet
    }

    private func uniqueName(_ name: String, origin: WalletMeta.Origin) -> String {
        let taken = Set(metadata.wallets.map { Self.nameSkeleton($0.name) })
        guard taken.contains(Self.nameSkeleton(name)) else { return name }
        let tag = origin == .importedEnvelope ? String(localized: "envelope") : String(localized: "importada")
        var candidate = "\(name) (\(tag))"
        var number = 2
        while taken.contains(Self.nameSkeleton(candidate)) {
            candidate = "\(name) (\(tag) \(number))"
            number += 1
        }
        return String(candidate.prefix(48))
    }

    /// O nome como o olho le: transliterado para o alfabeto latino, sem acento, em
    /// minusculas e sem espacos nas pontas. "Carteira principаl" com um "а" cirilico e
    /// "Carteira principal" dao o mesmo (revisao da auditoria 4, C7-05).
    static func nameSkeleton(_ name: String) -> String {
        let latin = name.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? name
        return latin.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// A carteira da 25ª palavra: a frase de `base` com uma palavra a mais, escolhida pelo
    /// dono, abre outra carteira, com outros enderecos (a carteira oculta da Ledger e da
    /// Trezor). A frase nunca sai do cofre: abre, deriva e e gravada dentro da mesma
    /// funcao sincrona, com uma confirmacao so.
    func addPassphraseWallet(base: WalletMeta, passphrase: SecureBytes, name: String, credential: Credential) async throws -> WalletMeta {
        guard case .phrase(let wordCount) = base.kind else { throw WalletError.notPhraseWallet }
        // A base e sempre a carteira sem passphrase: com uma por frase (a importacao recusa a repetida),
        // a conta de tentativas da porta de criar e por frase, e trocar de base nao a zera (revisao de
        // seguranca de 26/10/2026).
        guard !base.hasPassphrase else { throw WalletError.passphraseBase }
        // Passphrase vazia seria a carteira de sempre marcada como "com passphrase": o assinador recusa
        // passphrase vazia, e ela nao enviaria nem deixaria de pedir (revisao de blockchain de 26/10/2026).
        guard passphrase.count > 0 else { throw WalletError.emptyPassphrase }
        guard !addingWordsBlocked else {
            credential.wipe()
            throw WalletError.lockPolicy
        }
        let baseID = base.id
        let id = UUID()
        // Como em `addWallet`: o autoteste antes da RK, a derivacao antes de gravar, e a carteira que ja esta aqui nao e
        // gravada de novo.
        do { try await Offload.run { try DerivationSelfTest.require() } } catch { credential.wipe(); throw error }
        let known = Set(metadata.wallets.filter { !$0.isWatchOnly }.map(\.fingerprint))
        let (accounts, fingerprint, saved): ([DerivedAccount], [UInt8], Bool) = try await withRootKey(credential) { rk in
            let original = try KeyServices.wallets.open(walletID: baseID, rk: rk)
            defer { original.wipe() }
            let entropy = SecureBytes(capacity: original.entropy.count)
            original.entropy.withUnsafeBytes { entropy.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
            // A 25a palavra em NFKD, como a importacao grava. A seed BIP-39 normaliza sozinha,
            // mas a chave da Cardano (Icarus) usa os bytes como estao: com os bytes do teclado
            // (NFC), "ação" aqui dava outra conta da Cardano que a da importacao das mesmas
            // palavras (revisao do modo reforcado, N1).
            // Uma copia propria sempre (o NFKD copia ate no ASCII): o segredo nunca divide o buffer de quem chama.
            let normalized = BIP39.nfkd(passphrase)
            let secret = WalletSecret(entropy: entropy, language: original.language, passphrase: normalized)
            defer { secret.wipe() }
            let derived = try AccountDeriver.derive(secret)
            guard !known.contains(derived.fingerprint.hex) else { return (derived.accounts, derived.fingerprint, false) }
            // De novo com o cofre aberto, logo antes de gravar: a politica pode ter mudado no meio.
            guard !Self.wordsBlocked(KeyServices.root) else { throw WalletError.lockPolicy }
            try KeyServices.wallets.save(secret, walletID: id, rk: rk)
            return (derived.accounts, derived.fingerprint, true)
        }
        // Travou enquanto o cofre abria: a carteira guardada sai, como em `addWallet`.
        guard phase == .unlocked, indexKey != nil else {
            if saved { try? KeyServices.wallets.delete(id) }
            throw WalletError.locked
        }
        // A mesma frase com a mesma passphrase abre a mesma carteira: se ela ja esta aqui,
        // abrir e so passar a usa-la. A digital tem 4 bytes: o endereco da Bitcoin confirma que e a mesma, e uma
        // carteira de outra frase com a mesma digital nunca e escolhida no lugar (revisao dos 3 agentes, 08/11/2026).
        if let existing = metadata.wallets.first(where: { $0.fingerprint == fingerprint.hex && !$0.isWatchOnly }) {
            if saved { try? KeyServices.wallets.delete(id) }
            guard existing.account(.bitcoin)?.address == accounts.first(where: { $0.chainID == Chain.bitcoin.id })?.address else {
                throw WalletError.alreadyImported(existing.name)
            }
            metadata.selectedWalletID = existing.id
            try persist()
            // Reaberta, a mesma conferencia da que nasce agora, como no Android (rodada 1 da auditoria 8).
            _ = checkTronControl(existing.id)
            checkForeignControl(existing.id)
            _ = checkTONVersion(existing.id)
            return existing
        }
        guard saved else { throw WalletError.changedDuringSave }
        var wallet = WalletMeta(
            id: id, name: name, kind: .phrase(wordCount: wordCount), origin: base.origin, createdAt: .now,
            accounts: accounts, fingerprint: fingerprint.hex, hasPassphrase: true,
            backupConfirmedAt: base.backupConfirmedAt
        )
        // As palavras escolhidas da base valem para a com passphrase: sem isso, a `.created` contava como conferida em toda
        // rede (rodada 6 da auditoria 8).
        wallet.chosenWords = base.chosenWords
        metadata.wallets.append(wallet)
        // A mesma conta de volta (removida e importada de novo nesta sessao) volta a ter os avisos de ordem.
        let returning = Self.evmOwners(wallet)
        Task { await LimitOrderWatch.shared.remember(owners: returning) }
        metadata.selectedWalletID = id
        do { try persist() } catch {
            metadata.wallets.removeAll { $0.id == id }
            try? KeyServices.wallets.delete(id)
            throw error
        }
        freshPassphraseWallets[id] = PINPolicy.uptime
        // A Tron dela ja, logo depois de gravar: travar entre aqui e a tela nao a deixa sem conferencia. E as outras redes.
        _ = checkTronControl(id)
        checkForeignControl(id)
        _ = checkTONVersion(id)
        return wallet
    }

    /// As carteiras com passphrase abertas por este processo, com o instante no relogio monotono:
    /// so elas podem sair sem PIN pela busca de movimento. O id que a tela manda e o `createdAt`
    /// (relogio de parede, que se atrasa a mao) nao bastam (revisao de seguranca de 26/10/2026).
    private var freshPassphraseWallets: [UUID: TimeInterval] = [:]

    func addWatchWallet(chain: Chain, address: String, name: String) throws -> WalletMeta {
        // Endereco EVM vale em todas as redes EVM: observa todas.
        let chains = chain.family == .evm ? Chain.evmChains : [chain]
        let accounts = chains.map {
            DerivedAccount(chainID: $0.id, path: DerivationPath(components: []), address: address, publicKey: [], accountXPub: nil)
        }
        let wallet = WalletMeta(
            id: UUID(), name: name, kind: .watch(chainID: chain.id), origin: .watch, createdAt: .now,
            accounts: accounts, fingerprint: nil, hasPassphrase: false, backupConfirmedAt: nil
        )
        metadata.wallets.append(wallet)
        // A mesma conta de volta (removida e importada de novo nesta sessao) volta a ter os avisos de ordem.
        let returning = Self.evmOwners(wallet)
        Task { await LimitOrderWatch.shared.remember(owners: returning) }
        metadata.selectedWalletID = wallet.id
        try persist()
        return wallet
    }

    func select(_ wallet: WalletMeta) {
        // A rodada de outra carteira para: a que passa a ser escolhida nao e consultada junto com ela (rodada 2 da auditoria 8).
        if metadata.selectedWalletID != wallet.id { pauseControlChecks(keeping: wallet.id) }
        metadata.selectedWalletID = wallet.id
        try? persist()
        // A conferencia do dia e so da carteira em uso: a que passa a ser escolhida e conferida agora, se ja for a hora dela.
        scheduleControlChecks()
    }

    /// So o nome, sobre a carteira como ela esta agora: gravar a copia da tela apagava a marca da Tron que chegou
    /// depois de a tela abrir (revisao de seguranca de 08/11/2026).
    func rename(_ id: UUID, to name: String) {
        // Todo caminho de renomear passa pelo mesmo saneamento: sem controle, sem caractere invisivel ou de direcao, ate 40.
        let clean = Envelope.sanitize(name, limit: 40)
        guard !clean.isEmpty, let index = metadata.wallets.firstIndex(where: { $0.id == id }) else { return }
        metadata.wallets[index].name = clean
        try? persist()
    }

    /// Muda a carteira gravada, lida na hora, e devolve como ficou. A tela que gravava a copia inteira (guardada minutos
    /// antes) apagava o que a conferencia de outra chave gravou no meio: a marca, as redes lidas, a troca da TON para a W5
    /// (rodada 7 da auditoria 8). Como o `atualizar` do Android.
    @discardableResult
    func update(_ id: UUID, _ change: (inout WalletMeta) -> Void) -> WalletMeta? {
        guard let index = metadata.wallets.firstIndex(where: { $0.id == id }) else { return nil }
        change(&metadata.wallets[index])
        try? persist()
        return metadata.wallets[index]
    }

    /// Grava o aceite de responsabilidade: a data e a versao do texto aceito.
    func acceptResponsibility(version: Int) {
        metadata.responsibilityAccepted = .now
        metadata.responsibilityVersion = version
        try? persist()
    }

    /// As palavras de uma carteira, para ver ou lacrar num envelope. A presenca inteira e conferida aqui, na operacao, e nao
    /// na tela que pede: uma tela nova que pedisse so o rosto e lesse as palavras passava (rodada 1 da auditoria 8,
    /// 14/11/2026). Como o `credencialForte` do nucleo do Android. Com passphrase, `check` confere a digitada antes.
    func walletPhrase(_ credential: Credential, walletID: UUID, check: SecureBytes?, fingerprint: [UInt8]?) async throws -> SecureBytes {
        guard credential.isFullPresence else {
            credential.wipe()
            throw RootKeyVault.Failure.biometryRequired
        }
        return try await withRootKey(credential) { rk in
            let secret = try KeyServices.wallets.open(walletID: walletID, rk: rk)
            defer { secret.wipe() }
            if let check, try PassphraseProof.check(secret, typed: check, fingerprint: fingerprint, cardanoPublicKey: nil) == .mismatch {
                throw Signer.Failure.passphraseMismatch
            }
            return try secret.phrase()
        }
    }

    /// Remove uma carteira com as palavras: so com a presenca inteira, e a credencial abrindo a chave raiz antes (rodada 1 da
    /// auditoria 8). A carteira so de olhar sai sem credencial. Quem decide se e so de olhar e a lista, e nao quem chama.
    func remove(_ wallet: WalletMeta, credential: Credential?) async throws {
        guard let stored = metadata.wallets.first(where: { $0.id == wallet.id }) else {
            credential?.wipe()
            throw WalletError.removeFailed
        }
        if !stored.isWatchOnly {
            guard let credential else { throw WalletError.removeFailed }
            guard credential.isFullPresence else {
                credential.wipe()
                throw RootKeyVault.Failure.biometryRequired
            }
            _ = try await withRootKey(credential) { _ in true }
        } else {
            credential?.wipe()
        }
        try removeNow(stored)
    }

    /// A carteira so sai da lista depois de o chaveiro confirmar que a frase saiu. Antes,
    /// uma falha do chaveiro tirava a carteira da lista e deixava a frase la, sem caminho
    /// para apagar (auditoria 4, C7-20).
    private func removeNow(_ wallet: WalletMeta) throws {
        // Quem chama esperou a autorizacao (await): o app pode ter travado nesse meio tempo, e o
        // lock() troca os metadados por vazios. Sem a sessao aberta e a carteira na lista, nada sai.
        // Antes, a lista vazia fazia a remocao de UMA carteira apagar o app inteiro (caca de bugs de
        // 25/10/2026, A1).
        guard phase == .unlocked, indexKey != nil else { throw WalletError.locked }
        guard metadata.wallets.contains(where: { $0.id == wallet.id }) else { throw WalletError.removeFailed }
        if !wallet.isWatchOnly {
            try? KeyServices.wallets.delete(wallet.id)
            guard KeyServices.wallets.probe(wallet.id) == .absent else { throw WalletError.removeFailed }
        }
        // A copia de um endereco da carteira que sai do aparelho sai tambem (rodada 12), ja aqui: com a chave fora, uma gravacao
        // que falhe depois nao a deixa para tras (rodada 13).
        Pasteboard.withdrawReceive(ifAmong: Set(wallet.accounts.map(\.address)))
        metadata.wallets.removeAll { $0.id == wallet.id }
        // Tudo o que leva enderecos ou o rastro desta carteira sai junto (revisao de seguranca de
        // 24/10/2026): o historico, as transacoes em transito, as ordens a refazer e a conta de
        // passphrases erradas dela.
        metadata.balanceCache[wallet.id] = nil
        metadata.activityCache?[wallet.id] = nil
        metadata.activityFetched?[wallet.id] = nil
        let prefix = wallet.id.uuidString + "|"
        metadata.pendingEVM = metadata.pendingEVM?.filter { !$0.key.hasPrefix(prefix) }
        // Os avisos de refazer quando vencer dela saem da agenda do sistema (quinta passada de 03/11/2026).
        LimitRenewalCenter.forgetNotices((metadata.limitRenewals ?? []).filter { $0.walletID == wallet.id }.map(\.orderID))
        // As notificacoes ja mostradas saem da Central: a de ordem e a de recebimento podem ser desta carteira, e o id
        // de uma versao anterior levava o UID da ordem, com o endereco (sexta passada da auditoria de 03/11/2026).
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        metadata.limitRenewals?.removeAll { $0.walletID == wallet.id }
        // As ordens assinadas guardadas e os avisos de ordem limite dela: o UID traz o endereco, e o arquivo dos
        // avisos abre com o iPhone bloqueado (quarta passada da auditoria de 03/11/2026).
        // So os enderecos que nenhuma carteira que fica usa (uma carteira so para ver o mesmo endereco segue com os
        // avisos dela).
        let owners = Self.evmOwners(wallet).subtracting(metadata.wallets.filter { $0.id != wallet.id }.flatMap(Self.evmOwners))
        let stored = Set((metadata.signedOrders ?? []).filter { $0.walletID == wallet.id }.map(\.id))
        metadata.signedOrders?.removeAll { $0.walletID == wallet.id }
        Self.pruneAssetMaps(&metadata)
        Task { await LimitOrderWatch.shared.forget(owners: owners, ids: stored) }
        PassphraseGate.shared.forget(self, wallet: wallet.id)
        ImageLoader.eraseStored()
        // As consultas da removida param, e a rodada do dia, se for dela: os lotes seguintes saiam com os enderecos dela (rodada 4
        // da auditoria 8).
        cancelControlChecks(of: wallet.id)
        if sweptWallet == wallet.id {
            controlSweep?.cancel()
            controlSweep = nil
            sweptWallet = nil
        }
        if metadata.selectedWalletID == wallet.id { metadata.selectedWalletID = metadata.wallets.first?.id }
        // O que ainda consultava outra carteira para, mantendo a escolhida, em toda remocao, como no Android (rodadas 4 e 5).
        pauseControlChecks(keeping: metadata.selectedWalletID)
        // A ultima carteira saiu: o app volta a ser como recem-instalado, PIN e ajustes inclusive
        // (pedido do dono, 24/10/2026). Nada da carteira de antes fica para a proxima. So depois de
        // a lista sem ela estar gravada: com a gravacao recusada, nada mais e apagado.
        let lastOne = metadata.wallets.isEmpty
        try persist()
        forgetMemory(wallet.id)
        if lastOne { eraseEverything() }
    }

    /// A carteira com passphrase recem-aberta em que a busca nao achou movimento nenhum, quando o
    /// dono prefere tentar outra passphrase (pedido do dono, 25/10/2026): sai sem pedir o PIN de
    /// novo, e a carteira de antes volta a ser a escolhida. Nao ha o que perder: nunca recebeu nada, e
    /// a mesma frase com a mesma passphrase a abre de novo, igual. So vale para uma carteira com
    /// passphrase criada agora, e nunca para a ultima.
    func discardFreshPassphraseWallet(_ id: UUID, restoring previous: UUID?) throws {
        guard phase == .unlocked, indexKey != nil else { throw WalletError.locked }
        // Vinda da importacao, ela pode ser a unica: a primeira carteira do aparelho, com as palavras ainda na tela de importar,
        // que segue aberta (revisao dos 3 agentes, 08/11/2026). Nada mais e apagado.
        guard let openedAt = freshPassphraseWallets[id], PINPolicy.uptime - openedAt < 3600,
              let wallet = metadata.wallets.first(where: { $0.id == id }), wallet.hasPassphrase, !wallet.isWatchOnly,
              metadata.wallets.count > 1 || importedPassphraseWallets.contains(id)
        else { throw WalletError.removeFailed }
        try? KeyServices.wallets.delete(id)
        guard KeyServices.wallets.probe(id) == .absent else { throw WalletError.removeFailed }
        // A copia de um endereco da descartada sai ja, com a chave fora, como no `removeNow` (rodadas 13 e 14).
        Pasteboard.withdrawReceive(ifAmong: Set(wallet.accounts.map(\.address)))
        metadata.wallets.removeAll { $0.id == id }
        metadata.balanceCache[id] = nil
        metadata.activityCache?[id] = nil
        metadata.activityFetched?[id] = nil
        // O que leva o endereco dela: as transacoes em transito e as ordens guardadas (quarta passada de 03/11/2026).
        metadata.pendingEVM = metadata.pendingEVM?.filter { !$0.key.hasPrefix(id.uuidString + "|") }
        metadata.signedOrders?.removeAll { $0.walletID == id }
        Self.pruneAssetMaps(&metadata)
        PassphraseGate.shared.forget(self, wallet: id)
        let back = previous.flatMap { previous in metadata.wallets.contains { $0.id == previous } ? previous : nil }
        metadata.selectedWalletID = back ?? metadata.wallets.first?.id
        // As da descartada param antes, ja fora da lista (rodada 5 da auditoria 8).
        cancelControlChecks(of: id)
        // O que ainda consultava a carteira descartada para, antes de a de volta ser consultada (rodada 3 da auditoria 8), e a
        // rodada do dia da de volta e agendada de novo (rodada 4).
        pauseControlChecks(keeping: metadata.selectedWalletID)
        try persist()
        scheduleControlChecks()
        freshPassphraseWallets[id] = nil
        importedPassphraseWallets.remove(id)
        forgetMemory(id)
    }

    /// As carteiras com passphrase gravadas pela importacao neste processo.
    private var importedPassphraseWallets: Set<UUID> = []

    /// O PIN ou o rosto, sem abrir nada: importar com o interruptor da passphrase pede a confirmacao antes da tela da
    /// passphrase (pedido do dono, 08/11/2026), e so a carteira com passphrase e gravada depois, com outra.
    func confirmPresence(_ credential: Credential) async throws {
        _ = try await withRootKey(credential) { _ in true }
    }

    /// Importar com o interruptor da passphrase (08/11/2026): as palavras ficaram so na memoria da tela, e uma gravacao
    /// so guarda a carteira com passphrase, como a importacao fazia antes. Nenhuma carteira sem passphrase destas palavras e
    /// criada: com uma aqui, quem tem o PIN e o rosto veria as palavras sem a passphrase e testaria passphrases fora do
    /// aparelho, e travar no meio deixava as duas (revisao dos 3 agentes, 08/11/2026). Ver as palavras da carteira com
    /// passphrase pede a passphrase. As palavras continuam com a tela, para
    /// tentar outra passphrase; a mesma frase com a mesma passphrase ja aqui so passa a ser a escolhida.
    func addImportedPassphraseWallet(words: WalletSecret, passphrase: SecureBytes, name: String, wordCount: Int,
                                     expectedWordsFingerprint: String, credential: Credential) async throws -> WalletMeta {
        // Passphrase vazia seria a carteira das palavras marcada como "com passphrase" (revisao de blockchain de 26/10/2026).
        guard passphrase.count > 0 else { credential.wipe(); throw WalletError.emptyPassphrase }
        // As palavras zeradas (a tela saiu): nada a gravar.
        guard words.entropy.count > 0 else { credential.wipe(); throw WalletError.importChanged }
        guard !addingWordsBlocked else { credential.wipe(); throw WalletError.lockPolicy }
        func copy(_ bytes: SecureBytes) -> SecureBytes {
            let copy = SecureBytes(capacity: max(bytes.count, 1))
            bytes.withUnsafeBytes { copy.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
            return copy
        }
        // A 25a palavra em NFKD, como `addPassphraseWallet` e a importacao de antes gravavam (revisao do modo reforcado, N1).
        let alone = WalletSecret(entropy: copy(words.entropy), language: words.language, passphrase: SecureBytes(capacity: 1))
        let secret = WalletSecret(entropy: copy(words.entropy), language: words.language, passphrase: BIP39.nfkd(passphrase))
        let fingerprints: (alone: String, hidden: String, bitcoin: String?)
        do {
            fingerprints = try await Offload.run {
                defer { alone.wipe() }
                let hidden = try AccountDeriver.derive(secret, chains: [.bitcoin])
                return (try AccountDeriver.derive(alone, chains: [.bitcoin]).fingerprint.hex.uppercased(),
                        hidden.fingerprint.hex.uppercased(), hidden.accounts.first?.address)
            }
        } catch {
            secret.wipe()
            credential.wipe()
            throw error
        }
        // As palavras na memoria sao as da previa que o dono conferiu.
        guard fingerprints.alone == expectedWordsFingerprint.uppercased() else {
            secret.wipe()
            credential.wipe()
            throw WalletError.importChanged
        }
        // A digital tem 4 bytes: o endereco da Bitcoin confirma que e a mesma carteira. Uma de outra frase com a mesma
        // digital nunca e escolhida no lugar; o `addWallet` abaixo a recusa como ja importada (revisao, 08/11/2026).
        if let existing = metadata.wallets.first(where: {
            $0.fingerprint?.uppercased() == fingerprints.hidden && !$0.isWatchOnly && fingerprints.bitcoin != nil
                && $0.account(.bitcoin)?.address == fingerprints.bitcoin
        }) {
            secret.wipe()
            _ = try await withRootKey(credential) { _ in true }
            metadata.selectedWalletID = existing.id
            try persist()
            _ = checkTronControl(existing.id)
            checkForeignControl(existing.id)
            _ = checkTONVersion(existing.id)
            return existing
        }
        let wallet = try await addWallet(secret: secret, name: name, origin: .importedPhrase, wordCount: wordCount, backupConfirmed: true,
                                         expectedFingerprint: fingerprints.hidden, credential: credential)
        // A busca de movimento pode tira-la sem PIN, como a aberta pelos Ajustes, mesmo sendo a unica.
        freshPassphraseWallets[wallet.id] = PINPolicy.uptime
        importedPassphraseWallets.insert(wallet.id)
        _ = checkTronControl(wallet.id)
        checkForeignControl(wallet.id)
        _ = checkTONVersion(wallet.id)
        return wallet
    }

    private var tronChecks: [UUID: Task<Bool?, Never>] = [:]

    /// Quem controla a conta da Tron de uma carteira que acabou de abrir por aqui (o golpe da "frase com saldo",
    /// como a previa da importacao faz): outra chave no controle marca a carteira, e o Receber da Tron fecha. Uma
    /// conferencia por carteira, que segue mesmo se a tela fechar; sem rede, nada a dizer, e o envio confere de novo.
    /// O que volta (o aviso na hora) basta um operador ver; a marca guardada so entra com os dois de acordo, e sai com todos
    /// os operadores que respondem vendo a conta limpa, e pelo menos tres: um operador sozinho fechava o Receber da Tron para
    /// sempre (auditoria 8, 14/11/2026, e rodadas 1 e 2).
    /// Devolve o aviso na hora (outra chave vista), ou nil quando a conferencia foi cancelada: o Receber e a ponte nao a
    /// tomam por feita (rodada 4 da auditoria 8).
    func checkTronControl(_ id: UUID) -> Task<Bool?, Never> {
        if let running = tronChecks[id] { return running }
        // Sem a carteira (o app travou e a lista esta vazia), nada fica guardado: a proxima chamada confere. A Tron desligada
        // nos Ajustes nao e perguntada (rodada 1 da auditoria 8).
        guard !metadata.settings.disabledChainIDs.contains(Chain.tron.id),
              let address = metadata.wallets.first(where: { $0.id == id })?.account(.tron).flatMap({ TronAddress($0.address) }) else {
            return Task { false }
        }
        // Ja marcada, "limpa" so com todos os operadores de acordo (rodada 1 da auditoria 8).
        let marked = metadata.wallets.first(where: { $0.id == id })?.tronForeignControl == true
        let tronText = metadata.wallets.first(where: { $0.id == id })?.account(.tron)?.address ?? ""
        let check = Task { @MainActor [weak self] () -> Bool? in
            // A tela das palavras deixa a rede em silencio: a conferencia espera ela fechar (rodada 7 da auditoria 8).
            await HTTPClient.shared.whenAudible()
            guard !Task.isCancelled else { return nil }
            let reading = try? await TronReader.shared.ownerControlCheck(owner: address, everyone: marked)
            guard let self, !Task.isCancelled else { return nil }
            // Terminada, a proxima chamada pergunta de novo (a do destravar, um dia depois).
            self.tronChecks[id] = nil
            self.checkEnded(id)
            // Sem resposta, nada fica guardado (revisao, 08/11/2026).
            guard let reading else { return false }
            // "Limpa" so tira a marca que ja estava quando a conferencia comecou, e foi lida com todos (rodada 2 da auditoria 8).
            if let agreed = reading.agreed {
                // A copia do endereco da Tron com outra chave sai ja, mesmo travado (rodada 12).
                if agreed.isCompromised { Pasteboard.withdrawReceive(ifAmong: [tronText]) }
                // Lida com dois de acordo: a data do dia da conferencia das outras redes pode contar com ela (rodada 7).
                self.tronReadAt[id] = .now
                // Travado no meio, a marca espera o proximo destravar em vez de se perder.
                self.whenUnlocked { session in
                    guard let index = session.metadata.wallets.firstIndex(where: { $0.id == id }) else { return }
                    var changed = false
                    if agreed.isCompromised || marked {
                        let mark: Bool? = agreed.isCompromised ? true : nil
                        if session.metadata.wallets[index].tronForeignControl != mark {
                            session.metadata.wallets[index].tronForeignControl = mark
                            changed = true
                        }
                    }
                    // Lida de verdade, com dois de acordo: a Tron conta como lida (rodada 6 da auditoria 8).
                    if session.metadata.wallets[index].foreignControlRead?.contains(Chain.tron.id) != true {
                        session.metadata.wallets[index].foreignControlRead = (session.metadata.wallets[index].foreignControlRead ?? []).union([Chain.tron.id])
                        changed = true
                    }
                    if changed { try? session.persist() }
                    session.withdrawBlockedCopy(id)
                }
            }
            return reading.shown.isCompromised
        }
        tronChecks[id] = check
        return check
    }

    private var foreignChecks: [UUID: Task<Bool, Never>] = [:]
    private var controlSweep: Task<Void, Never>?
    /// Quando a Tron de cada carteira foi lida com dois de acordo, so na memoria (rodada 7 da auditoria 8).
    private var tronReadAt: [UUID: Date] = [:]

    /// O endereco que pode ser copiado agora, na carteira gravada: com a copia conferida, sem a marca em nenhuma das redes e o
    /// mesmo em todas (rodada 9 da auditoria 8), como o `carteira.enderecoParaCopiar` do Android. O Copiar endereco e os
    /// Enderecos dos Ajustes conferem aqui, na hora do toque.
    /// Desde 15/11/2026 (pedido do dono, a forma mais segura), so a rede ja lida para outra chave no controle (`controlChecked`),
    /// e nunca o endereco que outra carteira deste aparelho tem marcado (`markedElsewhere`).
    func copyableAddress(_ walletID: UUID, chains: [Chain]) -> String? {
        guard phase == .unlocked, let wallet = metadata.wallets.first(where: { $0.id == walletID }), wallet.hasBackup || wallet.isWatchOnly,
              let first = chains.first, let address = wallet.account(first)?.address,
              chains.allSatisfy({ wallet.receives(on: $0) && (wallet.isWatchOnly || wallet.controlChecked(on: $0))
                                  && markedElsewhere(wallet, on: $0) == nil && wallet.account($0)?.address == address }) else { return nil }
        return address
    }

    /// A rede da conta conferida de novo antes de receber nela pela troca (pedido do dono, 15/11/2026), como o Receber a cada
    /// abertura: a delegacao posta depois da conferencia do dia receberia o que foi comprado (revisao dos tres agentes). Numa EVM,
    /// tambem as outras EVM marcadas, como o Receber e a ponte. Devolve se a conferencia foi ate o fim.
    @discardableResult
    func checkBeforeReceiving(_ id: UUID, on chain: Chain) async -> Bool {
        guard let wallet = metadata.wallets.first(where: { $0.id == id }), !wallet.isWatchOnly else { return true }
        if chain.family == .tron { return await checkTronControl(id).value != nil }
        let marked = chain.family == .evm ? Set((wallet.foreignControl ?? [:]).keys.filter { Chain.find($0)?.family == .evm }) : []
        return await checkForeignControl(id, chains: marked.union([chain.id])).value
    }

    /// Outra carteira deste aparelho com o mesmo endereco nesta rede, e nele a marca de outra chave no controle: a so de
    /// observacao desse endereco (ou outra carteira com ele) tambem nao recebe por ele (pedido do dono, 15/11/2026, a forma mais
    /// segura).
    func markedElsewhere(_ wallet: WalletMeta, on chain: Chain) -> WalletMeta? {
        guard let address = wallet.account(chain)?.address else { return nil }
        return markedOwner(of: address, on: chain, excluding: wallet.id)
    }

    /// A carteira deste aparelho dona de `address` nesta rede, com a marca de outra chave no controle nela (`receives`): receber
    /// nesse endereco, ou enviar para ele de outra carteira, e depositar numa conta que quem controla a outra chave leva
    /// (15/11/2026). Pela identidade canonica (`Address.canonicalRecipient`): a TON so de observacao fica gravada como foi
    /// digitada (EQ ou crua) e a derivada como UQ. Numa EVM, o endereco de qualquer EVM, como a marca.
    func markedOwner(of address: String, on chain: Chain, excluding: UUID? = nil) -> WalletMeta? {
        guard let target = Address.canonicalRecipient(address, chain: chain) else { return nil }
        let evm = chain.family == .evm
        return metadata.wallets.first { other in
            guard other.id != excluding, !other.receives(on: chain) else { return false }
            if evm {
                return other.accounts.contains { Chain.find($0.chainID)?.family == .evm && $0.address.lowercased() == target }
            }
            return other.account(chain).flatMap { Address.canonicalRecipient($0.address, chain: chain) } == target
        }
    }

    /// A copia de um endereco que deixou de receber (a marca de outra chave, a troca da TON) sai da area de transferencia antes do
    /// prazo (rodada 10 da auditoria 8).
    /// Tambem a mesma conta escrita de outra forma em outra carteira deste aparelho (a TON so de observacao em EQ ou crua; revisao
    /// dos tres agentes de 15/11/2026): a copia dela sai junto.
    fileprivate func withdrawBlockedCopy(_ walletID: UUID, also extra: Set<String> = []) {
        guard let wallet = metadata.wallets.first(where: { $0.id == walletID }) else { return }
        let blocked = wallet.accounts.reduce(into: Set<String>()) { out, account in
            guard let chain = Chain.find(account.chainID), !wallet.receives(on: chain) else { return }
            out.formUnion(addressForms(account.address, on: chain))
        }
        Pasteboard.withdrawReceive(ifAmong: blocked.union(extra))
    }

    /// Como o endereco esta gravado em cada carteira deste aparelho com a mesma conta (`Address.canonicalRecipient`; numa EVM, em
    /// qualquer EVM), mais ele mesmo.
    func addressForms(_ address: String, on chain: Chain) -> Set<String> {
        guard let target = Address.canonicalRecipient(address, chain: chain) else { return [address] }
        var out: Set<String> = [address]
        for account in metadata.wallets.flatMap(\.accounts) {
            guard let other = Chain.find(account.chainID) else { continue }
            let same = chain.family == .evm
                ? other.family == .evm && account.address.lowercased() == target
                : other.id == chain.id && Address.canonicalRecipient(account.address, chain: chain) == target
            if same { out.insert(account.address) }
        }
        return out
    }

    /// Terminada uma conferencia de outra carteira (a primeira do envelope, a Tron, a TON, a releitura de uma rede), a rodada do
    /// dia da escolhida volta: ela desiste com outra conferencia no ar, e nada mais a armava (rodada 7 da auditoria 8).
    private func checkEnded(_ id: UUID) {
        if metadata.selectedWalletID != id { scheduleControlChecks() }
    }

    /// Outra chave, conta ou contrato no controle das outras contas de uma carteira (`ForeignControlCheck`; auditoria 8,
    /// 14/11/2026): rede por rede, a marca entra com dois operadores de acordo e so sai com todos os que respondem vendo a conta
    /// limpa, e pelo menos tres. A Tron fica com `checkTronControl`. `chains`: so estas redes, como o Receber confere a dele.
    @discardableResult
    /// Devolve se a conferencia foi ate o fim (a cancelada pela pausa nao conta: o Receber e a ponte nao a tomam por feita,
    /// rodada 4 da auditoria 8).
    func checkForeignControl(_ id: UUID, chains: Set<String>? = nil) -> Task<Bool, Never> {
        if chains == nil, let running = foreignChecks[id] { return running }
        guard let wallet = metadata.wallets.first(where: { $0.id == id }), !wallet.isWatchOnly else {
            firstChecks.remove(id)
            return Task { true }
        }
        // So as redes ligadas nos Ajustes: as desligadas nao sao consultadas por nada (rodada 1 da auditoria 8).
        let disabled = metadata.settings.disabledChainIDs
        let accounts = wallet.accounts.filter {
            $0.chainID != Chain.tron.id && !disabled.contains($0.chainID) && (chains?.contains($0.chainID) ?? true)
        }
        // A de algumas redes (o Receber, a ponte) tambem uma por vez: abrir de novo enquanto a primeira nao volta nao pergunta
        // de novo a todos os operadores (rodada 3 da auditoria 8). Com o endereco na chave: a releitura da W5 nao reaproveita a
        // do Receber da TON aberto com a V4R2 (rodada 8).
        let chainKey = chains.map { _ in "\(id.uuidString)|" + accounts.map { "\($0.chainID):\($0.address)" }.sorted().joined(separator: ",") }
        if let chainKey, let running = chainChecks[chainKey] { return running }
        // Sem conta para ler, a completa segue mesmo assim: a data do dia entra com a Tron lida (a carteira so com a Tron, que
        // antes era relida a cada destravar; rodada 8).
        guard !accounts.isEmpty || chains == nil else { return Task { true } }
        let start = wallet.foreignControl
        let marked = Set((start ?? [:]).keys)
        let check = Task { @MainActor [weak self] in
            // A tela das palavras deixa a rede em silencio: a conferencia espera ela fechar (rodada 7 da auditoria 8).
            await HTTPClient.shared.whenAudible()
            guard !Task.isCancelled else { return false }
            let verdicts = await ForeignControlCheck.check(accounts, marked: marked)
            guard let self, !Task.isCancelled else { return false }
            // A copia de um endereco com outra chave sai ja, sem esperar o destravar: o app pode estar travado na frente (rodada
            // 12). Numa EVM o endereco e o mesmo em todas.
            Pasteboard.withdrawReceive(ifAmong: Set(accounts.compactMap { account -> String? in
                if case .foreign = verdicts[account.chainID] { return account.address }
                return nil
            }))
            // A marca e as redes lidas entram ja; so a data do dia espera a Tron, embaixo (rodada 8: a marca achada esperava a
            // Tron lenta, e o Copiar endereco seguia mostrando a rede marcada).
            self.whenUnlocked { session in
                guard let index = session.metadata.wallets.firstIndex(where: { $0.id == id }) else { return }
                let marks = ForeignControlCheck.apply(verdicts, to: session.metadata.wallets[index].foreignControl, startingFrom: start)
                var changed = marks != session.metadata.wallets[index].foreignControl
                session.metadata.wallets[index].foreignControl = marks
                // As redes que responderam de verdade contam como lidas, uma por uma (rodada 6 da auditoria 8), e so pelo endereco
                // que a carteira ainda tem: a TON trocada para a W5 no meio nao conta pela leitura da V4R2 (rodada 7).
                let current = session.metadata.wallets[index]
                let read = Set(verdicts.compactMap { chainID, verdict -> String? in
                    guard verdict != .unknown,
                          accounts.first(where: { $0.chainID == chainID })?.address == current.accounts.first(where: { $0.chainID == chainID })?.address
                    else { return nil }
                    return chainID
                })
                if !read.isSubset(of: session.metadata.wallets[index].foreignControlRead ?? []) {
                    session.metadata.wallets[index].foreignControlRead = (session.metadata.wallets[index].foreignControlRead ?? []).union(read)
                    changed = true
                }
                if changed { try? session.persist() }
                session.withdrawBlockedCopy(id)
            }
            // A data do dia tambem espera a Tron, quando ela tem o que ler: lida com dois de acordo nesta rodada. Sem isso, a
            // carteira so com Bitcoin e Tron ganhava a data com a Tron sem resposta, e ficava 24 h sem reler (rodada 7). A Tron
            // que corre junto (a do `addWallet`) e esperada, com esta ainda na lista: travar, pausar e apagar tudo a cancelam
            // tambem na espera, e as contas da com passphrase nao ficam para depois do destravar (rodada 8).
            if chains == nil, let tron = self.tronChecks[id] { _ = await tron.value }
            guard !Task.isCancelled else { return false }
            if chains == nil {
                self.foreignChecks[id] = nil
                self.firstChecks.remove(id)
            }
            if let chainKey { self.chainChecks[chainKey] = nil }
            // Terminada a primeira (a do envelope, que pausou a escolhida), a rodada do dia da escolhida volta (rodada 5), e
            // tambem depois de qualquer outra de outra carteira (rodada 7).
            self.checkEnded(id)
            let tronOwed = !disabled.contains(Chain.tron.id) && wallet.account(.tron) != nil
            let tronRead = self.tronReadAt[id].map { Date.now.timeIntervalSince($0) < 600 } ?? false
            // Sem resposta nenhuma (sem rede), a conferencia do dia fica para o proximo destravar. Sem conta com leitura (so o
            // Bitcoin, a Sui ou a Cardano ligadas), conta como feita, e a rodada nao volta a cada destravar (rodada 6).
            let answered = (verdicts.values.contains { $0 != .unknown }
                || !accounts.contains { Chain.find($0.chainID).map(ForeignControlCheck.reads) ?? false })
                && (!tronOwed || tronRead)
            if chains == nil, answered {
                // So com as mesmas contas lidas: a TON trocada para a W5 no meio (a da importacao, que corre junto) tirou a data, e
                // esta conferencia leu a V4R2; gravar a data por cima deixava a W5 24 h sem leitura (rodada 9 da auditoria 8).
                let read = Set(accounts.map { "\($0.chainID):\($0.address)" })
                self.whenUnlocked { session in
                    guard let index = session.metadata.wallets.firstIndex(where: { $0.id == id }) else { return }
                    let now = Set(session.metadata.wallets[index].accounts
                        .filter { $0.chainID != Chain.tron.id && !disabled.contains($0.chainID) }
                        .map { "\($0.chainID):\($0.address)" })
                    guard now == read else { return }
                    session.metadata.wallets[index].foreignControlCheckedAt = .now
                    try? session.persist()
                }
            }
            return true
        }
        if chains == nil { foreignChecks[id] = check }
        if let chainKey { chainChecks[chainKey] = check }
        return check
    }

    private var chainChecks: [String: Task<Bool, Never>] = [:]

    /// A carteira TON na W5 (`TONDiscovery`; auditoria 8, 14/11/2026): uma vez por carteira, depois de gravar ou abrir, e no
    /// destravar para a que ja estava aqui. A conta da V4R2 sem movimento troca pela W5 da mesma chave que teve; o saldo
    /// guardado da TON sai, e a leitura seguinte traz o da W5. Sem resposta, a proxima vez pergunta de novo.
    func checkTONVersion(_ id: UUID) -> Task<Void, Never> {
        // Uma por carteira: abrir, gravar e o destravar chamavam juntas, e a TON era perguntada duas ou tres vezes (rodada 2).
        if let running = tonChecks[id] { return running }
        guard let wallet = metadata.wallets.first(where: { $0.id == id }), !wallet.isWatchOnly, wallet.tonVersionChecked != true,
              !metadata.settings.disabledChainIDs.contains(Chain.ton.id), let ton = wallet.account(.ton) else { return Task {} }
        let check = Task { @MainActor [weak self] in
            // A tela das palavras deixa a rede em silencio: a conferencia espera ela fechar (rodada 7 da auditoria 8).
            await HTTPClient.shared.whenAudible()
            guard !Task.isCancelled else { return }
            let answer = await TONDiscovery.check(ton)
            guard let self, !Task.isCancelled else { return }
            self.tonChecks[id] = nil
            self.checkEnded(id)
            guard answer != .unknown else { return }
            // A conta TON que muda de endereco e conferida de novo: a marca era a do endereco da V4R2 (rodada 1 da auditoria 8).
            defer { if case .switchTo = answer { self.checkForeignControl(id, chains: [Chain.ton.id]) } }
            // A copia da V4R2 sai ja, mesmo travado (rodada 12).
            if case .switchTo = answer { Pasteboard.withdrawReceive(ifAmong: [ton.address]) }
            self.whenUnlocked { session in
                guard let index = session.metadata.wallets.firstIndex(where: { $0.id == id }) else { return }
                if case .switchTo(let better) = answer,
                   let account = session.metadata.wallets[index].accounts.firstIndex(where: { $0.chainID == Chain.ton.id && $0.address == ton.address }) {
                    session.metadata.wallets[index].accounts[account] = better
                    session.metadata.balanceCache[id]?[Chain.ton.id] = nil
                    // A W5 ainda nao foi lida: a TON volta a contar so depois da releitura dela (rodada 7 da auditoria 8). E a data
                    // do dia sai: se a releitura nao ler (travada, ou sem resposta), a proxima rodada le tudo (rodada 8).
                    session.metadata.wallets[index].foreignControlRead?.remove(Chain.ton.id)
                    session.metadata.wallets[index].foreignControlCheckedAt = nil
                }
                session.metadata.wallets[index].tonVersionChecked = true
                try? session.persist()
                if case .switchTo = answer { session.withdrawBlockedCopy(id, also: [ton.address]) }
            }
        }
        tonChecks[id] = check
        return check
    }

    private var tonChecks: [UUID: Task<Void, Never>] = [:]

    /// A carteira com passphrase vai abrir: a rodada do dia para, para as duas nao serem consultadas juntas, do mesmo IP (rodada 1
    /// da auditoria 8).
    /// `hidden`: quem abre e uma carteira com passphrase (ou a previa de uma), e entao nada e poupado. Sem dizer, vale a de
    /// `keeping`; sem `keeping`, nada e poupado (rodada 5 da auditoria 8).
    func pauseControlChecks(keeping: UUID? = nil, hidden: Bool? = nil) {
        let hiding = hidden ?? keeping.flatMap { id in metadata.wallets.first { $0.id == id }?.hasPassphrase } ?? true
        controlSweep?.cancel()
        controlSweep = nil
        sweptWallet = nil
        // E toda consulta de outra carteira no ar, e nao so a da rodada: a importacao, o Receber e a ponte disparam as suas, e
        // seguiam junto com a da carteira que abriu, do mesmo IP (rodadas 2 e 3 da auditoria 8).
        let running = Set(tronChecks.keys).union(foreignChecks.keys).union(tonChecks.keys)
            .union(chainChecks.keys.compactMap { UUID(uuidString: String($0.prefix { $0 != "|" })) })
        for id in running where id != keeping {
            // A primeira conferencia da recem-importada (a disparada ao gravar) segue, salvo quando quem abre tem passphrase:
            // a de base nao sai junto com ela (rodadas 4 e 5 da auditoria 8).
            if !hiding, firstChecks.contains(id), metadata.wallets.first(where: { $0.id == id })?.hasPassphrase == false { continue }
            cancelControlChecks(of: id)
        }
    }

    /// As carteiras cuja primeira conferencia, disparada ao gravar, ainda esta no ar (so na memoria).
    private var firstChecks: Set<UUID> = []

    /// As consultas de outra chave e da TON de uma carteira, canceladas e fora das listas.
    private func cancelControlChecks(of id: UUID) {
        firstChecks.remove(id)
        tronChecks.removeValue(forKey: id)?.cancel()
        foreignChecks.removeValue(forKey: id)?.cancel()
        tonChecks.removeValue(forKey: id)?.cancel()
        for key in chainChecks.keys where key.hasPrefix(id.uuidString + "|") { chainChecks.removeValue(forKey: key)?.cancel() }
    }

    /// A carteira da rodada do dia em andamento, e a vez dela: so a rodada que ainda e a atual se apaga no fim.
    private var sweptWallet: UUID?
    private var sweepGeneration = 0

    /// Uma vez por dia, ao destravar ou ao escolher a carteira: so a carteira em uso, e so as redes ligadas, como o saldo e a
    /// atividade (docs/seguranca.md: so a carteira aberta e consultada). Antes, todas as carteiras, uma atras da outra, do mesmo
    /// IP: o operador ligava uma a outra numa rodada so (rodada 1 da auditoria 8). Comeca depois de um tempo sorteado, de 30 s a
    /// 5 min, para nao cair junto do destravar. A carteira com passphrase so e conferida quando abre.
    /// A rodada do dia de volta, depois de uma pausa que nao trocou a escolhida (a previa da importacao fechou; rodada 5).
    func resumeControlChecks() {
        previewOpen = false
        scheduleControlChecks()
    }

    /// A rodada do dia de volta depois de uma pausa da tela da passphrase (o PIN cancelado, a recusa), sem soltar a previa: na
    /// importacao com a passphrase depois, quem solta e a tela de importar ao sumir (rodada 9 da auditoria 8).
    func rescheduleControlChecks() {
        scheduleControlChecks()
    }

    /// A previa da importacao abriu: a rodada do dia da escolhida para e nao volta enquanto ela estiver aberta (rodada 6 da
    /// auditoria 8). `hidden`: a previa e de uma carteira com passphrase.
    func beginPreview(hidden: Bool) {
        previewOpen = true
        pauseControlChecks(hidden: hidden)
    }

    /// Uma previa da importacao aberta, consultando a importada: a rodada do dia nao sai junto.
    private var previewOpen = false

    private func scheduleControlChecks() {
        // A com passphrase so quando ainda nao terminou a primeira (travou no meio dela; rodada 4 da auditoria 8).
        guard controlSweep == nil, !previewOpen, let id = metadata.selectedWalletID,
              let wallet = metadata.wallets.first(where: { $0.id == id }), !wallet.isWatchOnly,
              !wallet.hasPassphrase || wallet.foreignControlCheckedAt == nil,
              wallet.foreignControlCheckedAt.map({ Date.now.timeIntervalSince($0) > ForeignControlCheck.interval }) ?? true
        else { return }
        let delay = ForeignControlCheck.checkDelay()
        sweepGeneration &+= 1
        let generation = sweepGeneration
        sweptWallet = id
        controlSweep = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            // A rodada cancelada nao apaga a nova (rodada 2 da auditoria 8).
            defer {
                if self.sweepGeneration == generation {
                    self.controlSweep = nil
                    self.sweptWallet = nil
                }
            }
            // Antes de cada passo: pausada, travada ou com outra carteira escolhida, para. Na saida, tambem com a conferencia de
            // outra carteira no ar (a primeira do envelope, a da previa), e so se ainda for a hora: a conferencia logo depois de
            // gravar ja leu a escolhida (rodada 6 da auditoria 8).
            // Com a rede em silencio (a tela das palavras aberta), a rodada desiste em vez de esperar: a espera saia junto da
            // carteira com passphrase que abre logo depois (rodada 8).
            let current = { !Task.isCancelled && self.phase == .unlocked && self.metadata.selectedWalletID == id && !HTTPClient.shared.isQuiet }
            let due = { self.metadata.wallets.first { $0.id == id }?.foreignControlCheckedAt.map { Date.now.timeIntervalSince($0) > ForeignControlCheck.interval } ?? true }
            guard current(), due(), !self.previewOpen, !self.othersChecking(id) else { return }
            _ = await self.checkTronControl(id).value
            guard current() else { return }
            _ = await self.checkForeignControl(id).value
            guard current() else { return }
            await self.checkTONVersion(id).value
        }
    }

    /// Alguma conferencia de outra carteira no ar.
    private func othersChecking(_ id: UUID) -> Bool {
        let prefix = id.uuidString + "|"
        return tronChecks.keys.contains { $0 != id } || foreignChecks.keys.contains { $0 != id }
            || tonChecks.keys.contains { $0 != id } || chainChecks.keys.contains { !$0.hasPrefix(prefix) }
    }

    /// Apaga tudo deste aparelho: chaves do SE e itens do chaveiro primeiro.
    func eraseEverything() {
        lockEpoch &+= 1
        // Nada da carteira de antes fica, nem o endereco copiado (rodada 12 da auditoria 8).
        Pasteboard.withdrawReceive(ifAmong: nil)
        PassphraseGate.shared.cancel()
        PassphraseGate.shared.clearGrace()
        NotificationCenter.default.post(name: Self.didLock, object: nil)
        afterUnlock = []
        // A conferencia da Tron em voo para, e nada dela grava depois (revisao, 08/11/2026); a das outras redes tambem.
        tronChecks.values.forEach { $0.cancel() }
        tronChecks = [:]
        foreignChecks.values.forEach { $0.cancel() }
        foreignChecks = [:]
        tonChecks.values.forEach { $0.cancel() }
        tonChecks = [:]
        chainChecks.values.forEach { $0.cancel() }
        chainChecks = [:]
        controlSweep?.cancel()
        controlSweep = nil
        sweptWallet = nil
        firstChecks = []
        previewOpen = false
        tronReadAt = [:]
        importedPassphraseWallets = []
        KeyServices.root.wipeAll()
        MetadataStore.deleteFile()
        Self.eraseBackgroundFiles()
        Preferences.receiptWatchChosen = false
        Preferences.receiptOfferSeen = false
        Preferences.priceAlertsChosen = false
        // Os atores zeram o que tinham em memoria; os arquivos ja sairam acima.
        Task {
            await ReceiptWatchCenter.shared.disable()
            await LimitOrderWatch.shared.erase()
            await PriceAlertCenter.shared.erase()
        }
        indexKey = nil
        metadata = Metadata()
        forgetMemory()
        phase = .onboarding
    }

    func persist() throws {
        // Travado no meio de uma operacao: gravar nada em silencio fazia ela parecer feita
        // (auditoria 6, A6-05).
        guard let indexKey else { throw WalletError.locked }
        try MetadataStore.save(metadata, key: indexKey)
    }
}

enum WalletError: LocalizedError {
    case alreadyImported(String)
    case notPhraseWallet
    case removeFailed
    case locked
    case emptyPassphrase
    case passphraseBase
    /// A carteira que ja estava aqui quando o cofre abriu saiu no meio: nada foi gravado.
    case changedDuringSave
    /// A carteira que ia ser gravada nao e a da previa que o dono conferiu: nada foi gravado.
    case importChanged
    /// Super Security em "Bloquear as carteiras": nenhuma carteira com palavras entra.
    case lockPolicy

    static var lockPolicyMessage: String {
        String(localized: "Com Bloquear as carteiras ligado, carteira nova não entra. Troque essa opção do Super Security, adicione a carteira e volte para Bloquear as carteiras digitando as palavras de todas, inclusive a nova.")
    }

    var errorDescription: String? {
        switch self {
        case .alreadyImported(let name): return String(localized: "Esta carteira já está aqui, como \(name).")
        case .notPhraseWallet: return String(localized: "Esta carteira só acompanha um endereço. A passphrase precisa da senha de 12 ou 24 palavras.")
        case .removeFailed: return String(localized: "Não foi possível apagar a carteira deste iPhone agora. Ela continua aqui; tente de novo.")
        case .locked: return String(localized: "O app travou antes de terminar. Destrave e tente de novo.")
        case .emptyPassphrase: return String(localized: "Digite a passphrase")
        case .passphraseBase: return String(localized: "Abra a carteira com passphrase a partir da carteira de sempre, a que não tem passphrase.")
        case .changedDuringSave: return String(localized: "As carteiras mudaram enquanto o cofre abria. Nada foi guardado; tente de novo.")
        case .importChanged: return String(localized: "A carteira mudou desde a conferência dos endereços. Nada foi guardado: comece de novo.")
        case .lockPolicy: return Self.lockPolicyMessage
        }
    }
}
