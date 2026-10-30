import EscaliburCore
import EscaliburKeys
import SwiftUI

/// Carteira com passphrase e "Pedir a passphrase para enviar" (ligado de fabrica, pedido do
/// dono, 16/10/2026): antes do Face ID ou do PIN de um envio, troca ou ponte, o dono digita a
/// passphrase. Quem viu o PIN, ou tem o rosto do dono a mao, nao move o saldo da carteira
/// com passphrase sem saber a passphrase.
///
/// A conferencia nao acontece aqui: a passphrase digitada vai para `Signer.sign`, que a
/// compara com a do cofre (NFKD, tempo constante) antes de nascer qualquer chave. Errada,
/// nada e assinado. Esta folha so coleta o que foi digitado, num buffer que o chamador zera.
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
    }

    private var current: Request?

    /// A carteira pede a passphrase para mover saldo? E o ajuste, sem a folga.
    static func asks(_ wallet: WalletMeta?) -> Bool {
        guard let wallet, wallet.hasPassphrase, !wallet.isWatchOnly else { return false }
        return wallet.passphraseToSend ?? true
    }

    /// Para mover saldo agora: pede, a menos que a folga escolhida depois de acertar ainda valha.
    static func needed(_ wallet: WalletMeta?) -> Bool {
        guard let wallet, asks(wallet) else { return false }
        return !shared.inGrace(wallet.id)
    }

    /// A passphrase digitada, ou nil se o dono fechou a folha. O buffer e do chamador: ele
    /// zera depois de assinar.
    func ask(_ wallet: WalletMeta, reason: String? = nil) async -> SecureBytes? {
        let line = reason ?? String(localized: "\(wallet.name) pede a passphrase para mover saldo. Depois dela vem o \(KeyServices.biometryName) ou o PIN, como sempre.")
        // Um pedido em cima de outro: o de antes recebe "fechou", e nao fica pendurado.
        if let pending = current { finish(pending, with: nil) }
        pendingGrace = nil
        return await withCheckedContinuation { continuation in
            let request = Request(walletID: wallet.id, walletName: wallet.name, reason: line, offersGrace: reason == nil, continuation: continuation)
            current = request
            OverlayWindow.shared.show(PassphrasePromptSheet(request: request))
        }
    }

    /// `grace`: os minutos escolhidos na folha, que so passam a valer quando o assinador
    /// conferir a passphrase (`confirmGrace`).
    func finish(_ request: Request, with passphrase: SecureBytes?, grace minutes: Int? = nil) {
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

    /// "Nao pedir nos proximos minutos" (pedido do dono, 17/10/2026): 5, 10, 15 ou 20
    /// minutos, 5 ao ligar. Vale so para mover saldo, so na carteira em que a passphrase
    /// conferiu, e so na memoria, no relogio monotono: fechar o app ou travar zera, e o PIN
    /// ou o rosto continuam sendo pedidos a cada envio.
    static let graceChoices = [5, 10, 15, 20]
    private var pendingGrace: (wallet: UUID, minutes: Int)?
    private var graceUntil: [UUID: TimeInterval] = [:]

    func inGrace(_ walletID: UUID) -> Bool {
        (graceUntil[walletID] ?? 0) > PINPolicy.uptime
    }

    /// O assinador conferiu a passphrase desta carteira: a folga pedida na folha comeca agora.
    func confirmGrace(_ walletID: UUID) {
        defer { pendingGrace = nil }
        guard let pending = pendingGrace, pending.wallet == walletID else { return }
        graceUntil[walletID] = PINPolicy.uptime + TimeInterval(pending.minutes * 60)
    }

    /// Travar o app encerra toda folga: quem destrava com o PIN depois nao pula a passphrase.
    /// O app travou: a folha aberta responde "fechou".
    func cancel() {
        if let current { finish(current, with: nil) }
    }

    func clearGrace() {
        graceUntil = [:]
        pendingGrace = nil
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

    /// A carteira saiu deste iPhone: a conta dela sai junto.
    func forget(_ session: AppSession, wallet: UUID) {
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

    /// A passphrase digitada confere com a do cofre? As duas em NFKD, em tempo constante:
    /// a mesma regra do assinador (`Signer.sign`) e da conferencia da copia.
    nonisolated static func matches(_ stored: SecureBytes, _ typed: SecureBytes) -> Bool {
        let a = BIP39.nfkd(stored), b = BIP39.nfkd(typed)
        defer { a.wipe(); b.wipe() }
        return a.count > 0 && Hash.constantTimeEqual(a, b)
    }

    /// O texto da passphrase errada, depois do Face ID ou do PIN.
    static let mismatchMessage = String(localized: "A passphrase não confere. Nada foi assinado. Escreva igual ao que você anotou: maiúscula, acento e espaço contam.")
}

/// O tamanho maximo da passphrase: 256 bytes no cofre, contados depois do NFKD, onde uma letra
/// com acento ocupa tres (revisao de seguranca de 24/10/2026). Os campos de criar e importar
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
    @State private var buffer = SecureBytes(capacity: 256)
    @State private var length = 0
    @State private var reveal = false
    @State private var cipher = LiveCipher()
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
                        onSubmit: { confirm() }, glyphs: glyphs)
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
                     ? String(localized: "Nos próximos \(graceMinutes) minutos, \(request.walletName) não pede a passphrase para mover saldo. O \(KeyServices.biometryName) ou o PIN continuam. Travar o app encerra.")
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
