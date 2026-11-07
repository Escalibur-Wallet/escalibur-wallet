import EscaliburChains
import EscaliburCore
import EscaliburKeys
import SwiftUI

/// Carteira com passphrase: antes do Face ID ou do PIN de cada assinatura (envio, troca, ponte,
/// cancelar uma ordem), o dono digita a passphrase. A passphrase nunca fica salva no app
/// (pedido do dono, 05/11/2026): o cofre guarda so a entropia, e ela so existe durante a
/// assinatura, num buffer seguro que sai zerado logo depois. Quem viu o PIN, ou tem o rosto do
/// dono a mao, nao move o saldo da carteira com passphrase sem saber a passphrase. Na carteira
/// criada desde entao, quem tira os dados do aparelho nao a acha em lugar nenhum; a de antes, ver
/// "Versoes anteriores" em docs/seguranca.md §2.11.
///
/// A conferencia nao acontece aqui: a passphrase digitada vai para `Signer.sign`, que deriva a
/// raiz com ela e confere o fingerprint gravado na criacao, antes de nascer qualquer chave.
/// Errada, nada e assinado. Esta folha so coleta o que foi digitado.
@MainActor
final class PassphraseGate {
    static let shared = PassphraseGate()

    struct Request: Identifiable {
        let id = UUID()
        let walletID: UUID
        let walletName: String
        /// A frase de cima da folha: mover saldo, ou deixar de pedir a passphrase.
        let reason: String
        /// Mover saldo oferece a folga de alguns minutos; ver as palavras, lacrar o envelope e
        /// deixar de pedir, nao.
        let offersGrace: Bool
        let continuation: CheckedContinuation<SecureBytes?, Never>
        /// O que a folha digita, do pedido e nao da tela: fechar o pedido de fora (o app saiu, travou) o
        /// zera na hora. O `onDisappear` do SwiftUI nao roda com a cena no segundo plano.
        /// Do tamanho do campo da importacao: o limite que vale e o do NFKD (`PassphraseLimit.fits`), e
        /// um caractere de largura cheia encolhe nele (revisao de blockchain de 05/11/2026).
        let buffer = SecureBytes(capacity: PassphraseLimit.fieldCapacity)
        /// A cifra viva da folha guarda uma tag da passphrase inteira: e do pedido, e `finish` a apaga.
        let cipher: LiveCipher
    }

    private var current: Request?

    /// A carteira pede a passphrase para assinar? Toda carteira com passphrase: sem ela nao ha como
    /// assinar, porque o cofre nao a tem. O "Pedir a passphrase para enviar" de antes saiu.
    static func asks(_ wallet: WalletMeta?) -> Bool {
        guard let wallet, wallet.hasPassphrase, !wallet.isWatchOnly else { return false }
        // A que esta versao nao confere: pedir so contaria erro (`unverified`).
        return wallet.passphraseUnverified != true
    }

    /// A carteira com passphrase que esta versao nao confere (`passphraseUnverified`): assinar, ver as palavras, lacrar
    /// e conferir a copia recusam com `unverifiedMessage`, sem pedir a passphrase nem contar erro.
    static func unverified(_ wallet: WalletMeta?) -> Bool {
        guard let wallet, wallet.hasPassphrase, !wallet.isWatchOnly else { return false }
        return wallet.passphraseUnverified == true
    }

    /// A passphrase digitada, ou nil se o dono fechou a folha. O buffer e do chamador: ele
    /// zera depois de assinar.
    func ask(_ wallet: WalletMeta, reason: String? = nil) async -> SecureBytes? {
        let line = reason ?? String(localized: "\(wallet.name) pede a passphrase para mover saldo. Depois dela vem o \(KeyServices.biometryName) ou o PIN, como sempre.")
        return await ask(walletID: wallet.id, name: wallet.name, line: line, offersGrace: reason == nil)
    }

    /// Para uma carteira que ainda nao esta na lista (a do envelope que vai ser importado). Sem folga.
    func ask(named name: String, reason: String) async -> SecureBytes? {
        await ask(walletID: UUID(), name: name, line: reason, offersGrace: false)
    }

    private func ask(walletID: UUID, name: String, line: String, offersGrace: Bool) async -> SecureBytes? {
        // Um pedido em cima de outro: o de antes recebe "fechou", e nao fica pendurado.
        if let pending = current { finish(pending, with: nil) }
        pendingGrace = nil
        let epoch = cancelEpoch
        let answer: SecureBytes? = await withCheckedContinuation { continuation in
            let request = Request(walletID: walletID, walletName: name, reason: line, offersGrace: offersGrace, continuation: continuation,
                                  cipher: LiveCipher())
            current = request
            OverlayWindow.shared.show(PassphrasePromptSheet(request: request))
        }
        // Travou ou saiu do app enquanto a folha respondia: a passphrase nao segue para o PIN, que abriria no fundo. Vale
        // para todo chamador (assinar, ver as palavras, lacrar, importar o envelope).
        guard epoch == cancelEpoch, UIApplication.shared.applicationState != .background else {
            answer?.wipe()
            pendingGrace = nil
            return nil
        }
        return answer
    }

    /// `grace`: os minutos escolhidos na folha, que so passam a valer quando o assinador
    /// conferir a passphrase (`confirmGrace`).
    func finish(_ request: Request, with passphrase: SecureBytes?, grace minutes: Int? = nil) {
        request.buffer.wipe()
        request.cipher.clearAll()
        // Uma resposta por pedido: fechar e confirmar quase juntos nao retoma duas vezes.
        guard current?.id == request.id else { passphrase?.wipe(); return }
        current = nil
        if let minutes, passphrase != nil, request.offersGrace, Self.graceChoices.contains(minutes) {
            pendingGrace = (request.walletID, minutes)
        }
        OverlayWindow.shared.hide()
        request.continuation.resume(returning: passphrase)
    }

    // MARK: Folga depois de acertar

    /// "Nao pedir nos proximos minutos" (pedido do dono, 17/10/2026, mantido em 05/11/2026): 5, 10,
    /// 15 ou 20 minutos, 5 ao ligar. Como o cofre nao tem a passphrase, a folga guarda uma copia da
    /// digitada, so na memoria, num buffer seguro (fora do core dump e, no Android, presa na RAM),
    /// so da carteira em que ela conferiu e so para assinar nela. A copia e zerada no fim do prazo
    /// (no relogio continuo, que conta o iPhone dormindo), ao sair do app, ao travar, ao remover a
    /// carteira e ao apagar tudo; desligar ou reiniciar o iPhone apaga a RAM inteira, e nada dela
    /// vai para o disco. O PIN ou o rosto continuam sendo pedidos a cada assinatura.
    static let graceChoices = [5, 10, 15, 20]
    private var pendingGrace: (wallet: UUID, minutes: Int)?
    private var graceUntil: [UUID: TimeInterval] = [:]
    private var held: [UUID: SecureBytes] = [:]
    private var expiry: [UUID: Task<Void, Never>] = [:]

    func inGrace(_ walletID: UUID) -> Bool {
        guard held[walletID] != nil else { return false }
        guard (graceUntil[walletID] ?? 0) > PINPolicy.uptime else {
            expire(walletID)
            return false
        }
        return true
    }

    /// Uma copia da passphrase da folga, de quem chama (que zera depois de assinar), ou nil sem folga.
    private func heldCopy(_ walletID: UUID) -> SecureBytes? {
        guard inGrace(walletID), let passphrase = held[walletID] else { return nil }
        let copy = SecureBytes(capacity: max(passphrase.count, 1))
        passphrase.withUnsafeBytes { copy.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        return copy
    }

    /// O assinador conferiu a passphrase desta carteira: a folga pedida na folha comeca agora, com
    /// uma copia dela. Sem folga pedida, nada fica.
    private func confirmGrace(_ walletID: UUID, passphrase: SecureBytes) {
        defer { pendingGrace = nil }
        guard let pending = pendingGrace, pending.wallet == walletID else { return }
        expire(walletID)
        let copy = SecureBytes(capacity: max(passphrase.count, 1))
        passphrase.withUnsafeBytes { copy.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        let seconds = TimeInterval(pending.minutes * 60)
        held[walletID] = copy
        graceUntil[walletID] = PINPolicy.uptime + seconds
        // Zerada no fim do prazo mesmo sem ninguem perguntar por ela.
        expiry[walletID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.expire(walletID)
        }
    }

    /// A folga desta carteira acaba, e a copia da passphrase sai zerada.
    func expire(_ walletID: UUID) {
        held.removeValue(forKey: walletID)?.wipe()
        graceUntil[walletID] = nil
        expiry.removeValue(forKey: walletID)?.cancel()
    }

    /// Travar o app encerra toda folga: quem destrava com o PIN depois nao pula a passphrase.
    /// Soma um a cada `cancel` e `clearGrace` (travou, saiu do app, apagou tudo): a passphrase
    /// digitada antes disso nao segue para o PIN, nem com a folha ja fechada (a saida entre a folha da
    /// passphrase e a do PIN, revisao de seguranca de 05/11/2026).
    private var cancelEpoch = 0

    /// O app travou ou saiu: a folha aberta responde "fechou", e o que estava digitado sai zerado.
    func cancel() {
        cancelEpoch &+= 1
        if let current { finish(current, with: nil) }
    }

    /// Travar, sair do app ou apagar tudo: toda copia da passphrase sai zerada.
    func clearGrace() {
        cancelEpoch &+= 1
        for id in Array(held.keys) + Array(graceUntil.keys) { expire(id) }
        pendingGrace = nil
    }

    // MARK: Assinar

    enum Signing {
        case signed([SignedTransaction])
        /// O dono fechou a folha da passphrase, do rosto ou do PIN: nada foi assinado.
        case cancelled
        /// Por que nao assina agora, sem contar tentativa: a espera depois de muitas passphrases erradas, ou a
        /// passphrase que esta versao nao consegue conferir.
        case waiting(String)
        case failed(any Error)
    }

    /// Assina o plano com a RK de agora. Na carteira com passphrase, a passphrase vem antes do Face
    /// ID ou do PIN (a copia da folga, se ainda vale), e o assinador a confere pelo fingerprint da
    /// raiz; a tentativa conta antes, a folga escolhida comeca depois de conferir, e as redes que uma
    /// versao nova trouxe nascem nessa mesma abertura do cofre (sem a passphrase, nao ha outro jeito).
    /// No fim a passphrase sai zerada: so a copia da folga, se o dono a pediu, continua na memoria.
    func sign(_ plan: SigningPlan, session: AppSession, auth: AuthCoordinator, reason: String,
              prompt: ((WalletMeta) -> String)? = nil) async -> Signing {
        let wallet = session.metadata.wallets.first { $0.id == plan.walletID }
        if Self.unverified(wallet) { return .waiting(Self.unverifiedMessage) }
        let epoch = cancelEpoch
        var typed: SecureBytes?
        var fresh = false
        if Self.asks(wallet), let wallet {
            if let copy = heldCopy(wallet.id) {
                typed = copy
            } else {
                guard let given = await ask(wallet, reason: prompt?(wallet)) else { return .cancelled }
                typed = given
                fresh = true
            }
        }
        let check = typed
        defer { check?.wipe() }
        // Travou ou saiu do app enquanto a folha respondia: a passphrase nao segue para o PIN, que abriria no fundo.
        guard epoch == cancelEpoch, UIApplication.shared.applicationState != .background else {
            pendingGrace = nil
            return .cancelled
        }
        // A tentativa conta antes de o assinador conferir; com muitas erradas, espera.
        if fresh, let wait = begin(session, wallet: plan.walletID) {
            pendingGrace = nil
            return .waiting(wait)
        }
        let fingerprint = wallet?.fingerprint.flatMap(Hex.decode)
        let have = Set(wallet?.accounts.map(\.chainID) ?? [])
        let missing = check == nil ? [] : Chain.all.filter { !have.contains($0.id) }
        do {
            guard let (signed, added) = try await auth.perform(session, reason: reason, { rk -> ([SignedTransaction], [DerivedAccount]) in
                // Assina antes (o plano vencido recusa antes de a passphrase ser usada), e so depois as redes que faltam,
                // com uma copia da RK, que o assinador zera. Ao contrario, a passphrase era testada antes do vencimento, e o
                // plano vencido devolvia a tentativa (revisao de seguranca de 05/11/2026).
                // A copia so nasce quando ha rede para derivar: no caso comum, a RK morre no assinador, como antes.
                var again: SecureBytes?
                if check != nil, !missing.isEmpty {
                    let copy = SecureBytes(capacity: max(rk.count, 1))
                    rk.withUnsafeBytes { copy.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
                    again = copy
                }
                defer { again?.wipe() }
                let signed = try Signer.sign(plan, rootKey: rk, vault: KeyServices.wallets, passphrase: check, fingerprint: fingerprint)
                // Uma rede que nao nasce (aparelho com defeito) nao segura a assinatura: so fica para a proxima.
                let added = again.flatMap { key in
                    check.flatMap { typed in
                        try? PassphraseProof.missingAccounts(walletID: plan.walletID, rootKey: key, vault: KeyServices.wallets,
                                                             typed: typed, fingerprint: fingerprint, chains: missing)
                    }
                } ?? []
                return (signed, added)
            }) else {
                if fresh { refund(session, wallet: plan.walletID) }
                pendingGrace = nil
                return .cancelled
            }
            if let check {
                if fresh {
                    passed(session, wallet: plan.walletID)
                    confirmGrace(plan.walletID, passphrase: check)
                }
                if !added.isEmpty { session.addAccounts(added, to: plan.walletID) }
            }
            return .signed(signed)
        } catch {
            let mismatch = (error as? Signer.Failure) == .passphraseMismatch
            if fresh {
                // Parou antes da passphrase (PIN errado, cofre): nada foi conferido, a tentativa volta.
                if mismatch { failed(session, wallet: plan.walletID) } else { refund(session, wallet: plan.walletID) }
            } else if mismatch {
                expire(plan.walletID)
            }
            pendingGrace = nil
            // A raiz conferiu, mas a Cardano de uma carteira antiga saiu dos bytes da criacao, que a digitada nao repetiu.
            if (error as? Signer.Failure) == .unexpectedKey, wallet?.legacyCardanoPassphrase == true, plan.chain.family == .cardano {
                return .waiting(Self.legacyCardanoMessage)
            }
            return .failed(error)
        }
    }

    // MARK: Espera depois de erros

    /// Erros livres antes da primeira espera; a espera comeca em 1 minuto e dobra a cada
    /// erro, ate 24 horas. Acertar zera.
    static let freeFailures = 5
    static let firstWait: TimeInterval = 60
    static let longestWait: TimeInterval = 24 * 3600

    /// A porta de abrir ou criar com passphrase: dez tentativas livres antes da primeira espera
    /// (pedido do dono, 27/10/2026). Daí em diante depende do que ha neste iPhone:
    /// - sem carteira com passphrase aqui, e por ela que o dono que esqueceu a passphrase tenta
    ///   lembrar: espera de no maximo 15 minutos, e um dia sem tentar zera a conta (25/10/2026);
    /// - com uma carteira com passphrase aqui, a porta diria "esta carteira ja esta aberta" para o
    ///   chute certo, e seria o jeito facil de descobrir a passphrase dela e depois enviar: a espera
    ///   cresce ate 24 horas e nao zera sozinha, como a de enviar (revisao de seguranca de 26/10/2026).
    static let creationFreeFailures = 10
    static let creationLongestWait: TimeInterval = 15 * 60
    static let creationForgetAfter: TimeInterval = 24 * 3600

    private static func limits(creation: Bool, strict: Bool) -> (free: Int, longest: TimeInterval) {
        guard creation else { return (freeFailures, longestWait) }
        return (creationFreeFailures, strict ? longestWait : creationLongestWait)
    }

    /// Ha carteira com passphrase neste iPhone: a porta de criar segue a escada inteira.
    private static func strict(_ session: AppSession) -> Bool {
        session.metadata.wallets.contains { $0.hasPassphrase && !$0.isWatchOnly }
    }

    /// A conta e de cada carteira (revisao de seguranca de 24/10/2026): com uma conta so,
    /// acertar a passphrase de uma carteira propria zerava a espera, e quem sabe o PIN seguia
    /// chutando a passphrase da carteira do dono. A criacao conta na carteira de base, numa
    /// conta a parte: uma base que tem passphrase segue a escada inteira nas portas dela.
    private static func slot(_ wallet: UUID, _ creation: Bool) -> String {
        creation ? "creation-" + wallet.uuidString : wallet.uuidString
    }

    private func guardState(_ session: AppSession, _ wallet: UUID, creation: Bool = false) -> PassphraseGuard? {
        migrateLegacy(session)
        return session.metadata.settings.passphraseGuards?[Self.slot(wallet, creation)]
    }

    private func store(_ session: AppSession, _ wallet: UUID, _ value: PassphraseGuard?, creation: Bool = false) {
        migrateLegacy(session)
        var all = session.metadata.settings.passphraseGuards ?? [:]
        all[Self.slot(wallet, creation)] = value
        session.metadata.settings.passphraseGuards = all.isEmpty ? nil : all
    }

    /// A conta unica de antes vale para todas as carteiras daqui: ninguem sai da espera que
    /// ja corria.
    private func migrateLegacy(_ session: AppSession) {
        guard let legacy = session.metadata.settings.passphraseGuard else { return }
        var all = session.metadata.settings.passphraseGuards ?? [:]
        for wallet in session.metadata.wallets where all[wallet.id.uuidString] == nil {
            all[wallet.id.uuidString] = legacy
        }
        session.metadata.settings.passphraseGuards = all.isEmpty ? nil : all
        session.metadata.settings.passphraseGuard = nil
    }

    /// Antes de conferir uma passphrase desta carteira: conta a tentativa (gravada antes da
    /// conferencia) e devolve nil para seguir, ou o texto da espera. Sem gravar, nao confere.
    func begin(_ session: AppSession, wallet: UUID, creation: Bool = false) -> String? {
        if creation, !Self.strict(session), guardState(session, wallet, creation: true)?.idle(for: Self.creationForgetAfter) == true {
            store(session, wallet, nil, creation: true)
        }
        let left = lockRemaining(session, wallet, creation: creation)
        if left > 0 {
            let until = Date.now.addingTimeInterval(left).formatted(date: .omitted, time: .shortened)
            // Na porta de criar nada esta errado: toda passphrase abre uma carteira.
            return creation ? String(localized: "Muitas tentativas seguidas. Tente de novo às \(until).")
                : String(localized: "Muitas passphrases erradas. Tente de novo às \(until).")
        }
        var state = guardState(session, wallet, creation: creation) ?? PassphraseGuard()
        state.failures += 1
        if creation { state.markAttempt() }
        // A espera nasce junto com a contagem, antes da conferencia: o desfecho que nao chega a
        // `failed` (o app morto no meio) nao deixa o contador sem espera. Acertar zera tudo, e a
        // tentativa devolvida leva a espera junto (revisao de seguranca do iPhone de 27/10/2026).
        let limits = Self.limits(creation: creation, strict: Self.strict(session))
        if state.failures >= limits.free {
            state.startLock(seconds: min(Self.firstWait * pow(2, Double(state.failures - limits.free)), limits.longest))
        }
        store(session, wallet, state, creation: creation)
        do { try session.persist() } catch { return String(localized: "Não foi possível conferir a passphrase agora.") }
        return nil
    }

    /// Nada foi conferido (o dono cancelou o PIN ou o rosto, ou o assinador parou antes da
    /// passphrase): a tentativa contada em `begin` volta.
    func refund(_ session: AppSession, wallet: UUID, creation: Bool = false) {
        pendingGrace = nil
        guard session.phase == .unlocked else { return later(wallet, creation, .refund) }
        guard var state = guardState(session, wallet, creation: creation), state.failures > 0 else { return }
        state.failures -= 1
        // A espera desta tentativa sai com ela: a de antes ja tinha vencido, ou `begin` nao deixaria.
        state.clearLock()
        store(session, wallet, state, creation: creation)
        try? session.persist()
    }

    /// Acertou: a conta desta carteira zera, e so ela.
    func passed(_ session: AppSession, wallet: UUID) {
        guard session.phase == .unlocked else { return later(wallet, false, .passed) }
        guard guardState(session, wallet) != nil else { return }
        store(session, wallet, nil)
        try? session.persist()
    }

    /// Errou (a tentativa ja foi contada em `begin`): passado o limite, comeca a espera.
    /// O aviso por cima de tudo: o erro de cada tela ficava no fim dela, fora da vista, e a
    /// passphrase errada parecia nao dar aviso (pedido do dono, 18/10/2026).
    weak var toasts: ToastCenter?

    /// `warn` falso: a criacao de uma carteira com passphrase, que conta como tentativa sem
    /// ter errado nada.
    func failed(_ session: AppSession, wallet: UUID, warn: Bool = true, creation: Bool = false) {
        if warn { toasts?.show(Self.mismatchMessage, kind: .failure) }
        pendingGrace = nil
        guard session.phase == .unlocked else { return later(wallet, creation, .failed) }
        var state = guardState(session, wallet, creation: creation) ?? PassphraseGuard(failures: 1)
        let limits = Self.limits(creation: creation, strict: Self.strict(session))
        guard state.failures >= limits.free else { return }
        let extra = Double(state.failures - limits.free)
        state.startLock(seconds: min(Self.firstWait * pow(2, extra), limits.longest))
        store(session, wallet, state, creation: creation)
        try? session.persist()
    }

    /// Travou entre contar e saber o resultado: os metadados sairam da memoria, e devolver, zerar
    /// ou comecar a espera ali nao gravava nada. Sem a espera gravada, travar no meio de cada
    /// conferencia deixava chutar sem esperar (caca de bugs de 25/10/2026, B2). O resultado fica
    /// aqui e vale no proximo destravar; se o app fechar antes, a tentativa segue contada.
    private enum Outcome { case refund, passed, failed }
    private var pending: [(wallet: UUID, creation: Bool, outcome: Outcome)] = []

    private func later(_ wallet: UUID, _ creation: Bool, _ outcome: Outcome) {
        pending.append((wallet, creation, outcome))
    }

    /// Destravou: vale o que ficou esperando.
    func applyPending(_ session: AppSession) {
        let list = pending
        pending = []
        for item in list where session.metadata.wallets.contains(where: { $0.id == item.wallet }) {
            switch item.outcome {
            case .refund: refund(session, wallet: item.wallet, creation: item.creation)
            case .passed: passed(session, wallet: item.wallet)
            case .failed: failed(session, wallet: item.wallet, warn: false, creation: item.creation)
            }
        }
    }

    /// A carteira saiu deste iPhone: a conta dela sai junto, e a copia da folga, zerada.
    func forget(_ session: AppSession, wallet: UUID) {
        expire(wallet)
        let slots = [Self.slot(wallet, false), Self.slot(wallet, true)]
        guard slots.contains(where: { session.metadata.settings.passphraseGuards?[$0] != nil }) else { return }
        for slot in slots { session.metadata.settings.passphraseGuards?[slot] = nil }
        if session.metadata.settings.passphraseGuards?.isEmpty == true { session.metadata.settings.passphraseGuards = nil }
    }

    /// Quanto falta da espera desta carteira, no relogio monotono. De outro boot, ela
    /// recomeca cheia (falha para o lado de esperar mais), como a da voz.
    private func lockRemaining(_ session: AppSession, _ wallet: UUID, creation: Bool) -> TimeInterval {
        guard var state = guardState(session, wallet, creation: creation), state.lockUptimeDeadline != nil else { return 0 }
        let limits = Self.limits(creation: creation, strict: Self.strict(session))
        let full = min(Self.firstWait * pow(2, Double(max(state.failures - limits.free, 0))), limits.longest)
        let boot = PINPolicy.bootSession
        if boot == PINPolicy.unknownBoot {
            return max(0, (state.lockedUntil ?? .distantPast).timeIntervalSinceNow)
        }
        if !PINPolicy.isSameBoot(state.lockBoot.flatMap(Hex.decode) ?? [], boot) {
            state.startLock(seconds: full)
            store(session, wallet, state, creation: creation)
            try? session.persist()
            return full
        }
        let left = min(full, (state.lockUptimeDeadline ?? 0) - PINPolicy.uptime)
        if left <= 0 {
            state.clearLock()
            store(session, wallet, state, creation: creation)
            try? session.persist()
            return 0
        }
        return left
    }

    /// A passphrase que uma versao anterior gravou e que esta nao conseguiu conferir pela raiz: ela saiu do
    /// cofre, e a digitada passaria pelo mesmo caminho. A carteira continua inteira nas palavras com a passphrase.
    static let unverifiedMessage = String(localized: "Esta versão do app não consegue conferir a passphrase desta carteira, e ela não assina aqui. As palavras com a passphrase continuam abrindo a carteira em qualquer carteira BIP-39.")

    /// A Cardano da carteira cuja passphrase uma versao anterior gravou fora de NFKD: so a digitada byte a byte igual a
    /// da criacao a assina (`legacyCardanoPassphrase`).
    static let legacyCardanoMessage = String(localized: "A conta da Cardano desta carteira saiu da passphrase exatamente como foi digitada na criação. Digite igual: o mesmo teclado, a mesma forma dos acentos e da largura dos caracteres.")

    /// O texto da passphrase errada, depois do Face ID ou do PIN.
    static let mismatchMessage = String(localized: "A passphrase não confere. Nada foi assinado. Escreva igual ao que você anotou: maiúscula, acento e espaço contam.")
}

/// O tamanho maximo da passphrase: 256 bytes, contados depois do NFKD, onde uma letra com acento
/// ocupa tres (revisao de seguranca de 24/10/2026). Era o limite do cofre, que nao a guarda mais, e
/// continua o mesmo para quem ja tem uma. Os campos de criar e importar
/// guardam ate o dobro, para quem passa do limite ver o aviso em vez de ter a passphrase cortada
/// sem saber, e a conta exata vem antes de gravar.
enum PassphraseLimit {
    static var maxBytes: Int { WalletVault.maxPassphraseBytes }
    static let fieldCapacity = 512

    /// Passou do limite so pelo que foi digitado (sem acento, cada caractere e um byte).
    static func overflows(_ typedBytes: Int) -> Bool { typedBytes > maxBytes }

    /// Cabe no cofre, contado depois do NFKD.
    static func fits(_ typed: SecureBytes) -> Bool {
        let normalized = BIP39.nfkd(typed)
        defer { normalized.wipe() }
        return normalized.count <= maxBytes
    }

    static var message: String {
        String(localized: "A passphrase passou do tamanho máximo: até 256 caracteres sem acento, menos com acento. Encurte para seguir.")
    }
}

/// A folha da passphrase antes de assinar.
struct PassphrasePromptSheet: View {
    let request: PassphraseGate.Request
    private var buffer: SecureBytes { request.buffer }
    @State private var length = 0
    @State private var reveal = false
    private var cipher: LiveCipher { request.cipher }
    @State private var answered = false
    /// A folga: desligada a cada folha; ligar comeca em 5 minutos.
    @State private var graceOn = false
    @State private var graceMinutes = PassphraseGate.graceChoices[0]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: String(localized: "Digite a passphrase")) { close() }
            // O selo das telas onde se digita um segredo (pedido do dono, 18/10/2026).
            // Menor que nas telas cheias: a folha divide a altura com o teclado.
            CipherEmblem(size: 60).frame(maxWidth: .infinity)
            Text(request.reason)
                .typeStyle(.body).foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.gutter).padding(.top, Space.sm)
            PasswordBox(buffer: buffer, length: $length, placeholder: String(localized: "Passphrase"), focusOnAppear: true, reveal: $reveal,
                        onSubmit: { confirm() }, glyphs: glyphs, wipesOnLeave: true)
                .padding(.horizontal, Space.gutter).padding(.top, Space.lg)
                .accessibilityIdentifier("passphrase-envio")
            Text("Segure o dedo no campo para conferir o que digitou.")
                .typeStyle(.note).foregroundStyle(Palette.inkMuted)
                .padding(.horizontal, Space.gutter).padding(.top, Space.xs)
            if request.offersGrace {
                grace
                    .padding(.horizontal, Space.gutter).padding(.top, Space.lg)
            }
            Spacer(minLength: Space.md)
            PrimaryButton(title: String(localized: "Continuar"), enabled: length > 0) { confirm() }
                .padding(.horizontal, Space.gutter).padding(.bottom, Space.xs)
                .accessibilityIdentifier("passphrase-envio-continuar")
        }
        .padding(.top, Space.sm)
        .background(Palette.void.ignoresSafeArea())
        .guardedAgainstCapture()
        .onChange(of: length) { _, _ in cipher.seal(0, buffer: buffer) }
        .onDisappear {
            cipher.clearAll()
            if !answered { buffer.wipe() }
        }
    }

    private var glyphs: ((UInt64) -> String)? {
        guard length > 0 else { return nil }
        let cipher = self.cipher, count = length
        return { tick in cipher.glyphs(0, count: count, tick: tick) }
    }

    /// "Nao pedir de novo por alguns minutos", com a escolha dos minutos ao ligar. O interruptor
    /// fica preso na linha do titulo: o texto de baixo muda de tamanho ao ligar, e o
    /// interruptor centralizado nele pulava de lugar. Sem o cartao em volta (pedido do dono,
    /// 17/10/2026).
    private var grace: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: $graceOn.animation(Motion.fade)) {
                    Text("Não pedir de novo por um tempo").typeStyle(.body).foregroundStyle(Palette.ink)
                }
                .tint(Palette.success)
                .accessibilityIdentifier("passphrase-folga")
                Text(graceOn
                     ? String(localized: "Nos próximos \(graceMinutes) minutos, \(request.walletName) não pede a passphrase. Até lá ela fica só na memória do app, e sai apagada no fim do tempo, ao sair do app ou ao travar. O \(KeyServices.biometryName) ou o PIN continuam.")
                     : String(localized: "Depois de a passphrase conferir, os próximos envios, trocas e ordens pulam esta etapa por alguns minutos."))
                    .typeStyle(.note).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 64)
            }
            if graceOn {
                Segmented(options: PassphraseGate.graceChoices.map { ($0, String(localized: "\($0) min")) }, selection: $graceMinutes)
                    .accessibilityIdentifier("passphrase-folga-minutos")
                    .transition(.opacity)
            }
        }
    }

    private func confirm() {
        guard length > 0, !answered else { return }
        answered = true
        // O chamador fica com uma copia; o campo zera o dele.
        let copy = SecureBytes(capacity: buffer.count)
        buffer.withUnsafeBytes { copy.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        buffer.wipe()
        PassphraseGate.shared.finish(request, with: copy, grace: graceOn ? graceMinutes : nil)
    }

    private func close() {
        answered = true
        buffer.wipe()
        PassphraseGate.shared.finish(request, with: nil)
    }
}
