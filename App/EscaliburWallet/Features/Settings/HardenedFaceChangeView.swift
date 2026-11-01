import EscaliburCore
import EscaliburKeys
import SwiftUI

/// "Quando o Face ID mudar" do modo reforcado (docs/seguranca.md §2.6), como a tela diz cada
/// politica. Com o Touch ID, "rosto" vira "digital".
extension RootKeyVault.HardenedFaceChange {
    var title: String {
        switch self {
        case .continue: return String(localized: "Continuar normal")
        case .wait: return String(localized: "Esperar 24 horas")
        case .lock: return String(localized: "Bloquear as carteiras")
        }
    }

    /// A frase honesta de cada opcao, na lista das tres.
    var summary: String {
        let finger = KeyServices.usesFingerprint
        switch self {
        case .continue:
            return finger ? String(localized: "Uma digital nova abre as carteiras com o PIN, na hora. Quem sabe o seu PIN e o código do iPhone tem acesso aos seus fundos.")
                : String(localized: "Um rosto novo ou a aparência alternativa abre as carteiras com o PIN, na hora. Quem sabe o seu PIN e o código do iPhone tem acesso aos seus fundos.")
        case .wait:
            return finger ? String(localized: "Uma digital nova abre o app e mostra o saldo. O resto espera 24 horas.")
                : String(localized: "Um rosto novo ou a aparência alternativa abre o app e mostra o saldo. O resto espera 24 horas.")
        case .lock:
            return finger ? String(localized: "Uma digital nova fecha as carteiras daqui de vez. Só as palavras trazem de volta.")
                : String(localized: "Um rosto novo fecha as carteiras daqui de vez. Só as palavras trazem de volta.")
        }
    }

    /// O que muda com ela, em "O que muda" do modo reforcado. So o bloqueio promete algo
    /// sobre redefinir o Face ID: a chave que sobrevive a um rosto novo pode nao sobreviver a
    /// uma redefinicao (ha relato de itens assim perdidos numa redefinicao interrompida), e o
    /// texto nao promete o que nao foi provado no aparelho.
    /// O que acontece, numa frase curta, na tela do Super Security; o risco de cada opcao fica
    /// na tela da politica (pedido do dono, 18/10/2026: o aviso estava grande demais).
    var consequence: String {
        let name = KeyServices.biometryName
        let finger = KeyServices.usesFingerprint
        switch self {
        case .continue:
            // Sem o "redefinir pode fechar" aqui: lido junto de "Continuar normal", parecia so
            // dela (pedido do dono, 18/10/2026). Vale para as tres, e a tela da politica diz.
            return finger
                ? String(localized: "Com uma digital nova no Touch ID, as carteiras continuam abrindo com o PIN.")
                : String(localized: "Com um rosto novo no \(name), as carteiras continuam abrindo com o PIN.")
        case .wait:
            return finger
                ? String(localized: "Com uma digital nova no Touch ID, por 24 horas só dá para ver o saldo.")
                : String(localized: "Com um rosto novo no \(name), por 24 horas só dá para ver o saldo.")
        case .lock:
            return String(localized: "Se o \(name) deste iPhone mudar, as carteiras daqui fecham de vez, e só as palavras de cada carteira trazem de volta.")
        }
    }

    var icon: String {
        switch self {
        case .continue: return "arrow.forward.circle"
        case .wait: return "timer"
        case .lock: return "lock"
        }
    }

    /// Para os testes de interface.
    var identifier: String {
        switch self {
        case .continue: return "continuar"
        case .wait: return "esperar"
        case .lock: return "bloquear"
        }
    }
}

/// As tres politicas, uma embaixo da outra, cada uma com a frase dela. Escolher e de quem
/// usa: a tela "Quando o Face ID mudar" e o ultimo passo de ligar.
struct HardenedFaceChangeOptions: View {
    let choice: RootKeyVault.HardenedFaceChange
    var working: RootKeyVault.HardenedFaceChange? = nil
    let onSelect: (RootKeyVault.HardenedFaceChange) -> Void

    var body: some View {
        VStack(spacing: Space.sm) {
            ForEach(RootKeyVault.HardenedFaceChange.allCases, id: \.self) { policy in
                option(policy)
            }
        }
    }

    private func option(_ policy: RootKeyVault.HardenedFaceChange) -> some View {
        let selected = choice == policy
        return Button { onSelect(policy) } label: {
            HStack(alignment: .top, spacing: Space.sm) {
                // O bloqueio no vermelho forte: e a opcao sem volta (pedido do dono, 16/10/2026).
                // A espera no verde, com o cronometro branco por cima (pedido do dono, 24/10/2026).
                Image(systemName: policy.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(policy == .lock || policy == .wait ? Color.white : Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(policy == .lock ? Palette.down : (policy == .wait ? Palette.success : Palette.control)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(policy.title).typeStyle(.row).foregroundStyle(Palette.ink)
                    Text(policy.summary).typeStyle(.note).foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 1)
                Spacer(minLength: Space.xs)
                Group {
                    if working == policy {
                        ProgressView().tint(Palette.inkSoft)
                    } else {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(selected ? Palette.ink : Palette.edgeStrong)
                    }
                }
                .frame(width: 24, height: 36)
            }
            .padding(Space.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.body)
                    // Sem contorno diferente no selecionado: o visto ja diz qual e (pedido do
                    // dono, 16/10/2026).
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Palette.edge, lineWidth: 1))
            )
            .contentShape(Rectangle())
            .animation(Motion.select, value: selected)
        }
        .buttonStyle(.plain)
        .disabled(working != nil)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("reforcado-politica-\(policy.identifier)")
    }
}

/// A explicacao curta da espera, ao escolher "Esperar 24 horas".
struct HardenedWaitNote: View {
    nonisolated static var text: String {
        KeyServices.usesFingerprint
            ? String(localized: "Com uma digital nova, por 24 horas só dá para ver o saldo: enviar, trocar e ver as palavras esperam. Reiniciar o iPhone recomeça a contagem.")
            : String(localized: "Com um rosto novo, por 24 horas só dá para ver o saldo: enviar, trocar e ver as palavras esperam. Reiniciar o iPhone recomeça a contagem.")
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(Self.text).typeStyle(.note).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.rail))
        .accessibilityElement(children: .combine)
    }
}

/// "Quando o Face ID mudar": as tres opcoes. Desligado, so a escolha para ligar; ligado,
/// mudar pede o PIN e o rosto, e o rosto de novo para conferir. "Bloquear as carteiras" abre a
/// tela dele, com a animacao e o aceite.
struct HardenedFaceChangeView: View {
    @Environment(AppSession.self) private var session
    @Environment(AuthCoordinator.self) private var auth
    @Environment(ToastCenter.self) private var toasts
    @Binding var choice: RootKeyVault.HardenedFaceChange
    @Binding var lockAccepted: Bool
    let on: Bool
    let wallets: [WalletMeta]

    @State private var locking = false
    @State private var working: RootKeyVault.HardenedFaceChange?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Quando o \(KeyServices.biometryName) mudar").typeStyle(.title).foregroundStyle(Palette.ink)
                Text(KeyServices.usesFingerprint
                     ? String(localized: "Escolha o que acontece com as carteiras daqui quando uma digital nova entra no Touch ID deste iPhone. Apagar todas as digitais pode fechar as carteiras daqui em qualquer uma das três, e aí só as palavras de cada carteira trazem de volta.")
                     : String(localized: "Escolha o que acontece com as carteiras daqui quando um rosto novo ou a aparência alternativa entra no \(KeyServices.biometryName) deste iPhone. Redefinir o \(KeyServices.biometryName) pode fechar as carteiras daqui em qualquer uma das três, e aí só as palavras de cada carteira trazem de volta."))
                    .typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.top, Space.xs)
                    .fixedSize(horizontal: false, vertical: true)
                if on, session.hardenedHold > 0 {
                    Banner(kind: .caution, title: AuthCoordinator.hardenedHoldMessage(session.hardenedHold))
                        .padding(.top, Space.md)
                }

                HardenedFaceChangeOptions(choice: choice, working: working) { policy in Task { await select(policy) } }
                    .padding(.top, Space.lg)
                if choice == .wait { HardenedWaitNote().padding(.top, Space.sm) }

                Text(KeyServices.usesFingerprint
                     ? String(localized: "Contra quem não sabe o código do iPhone, as três protegem igual: cadastrar uma digital pede o código. Com a Proteção de Aparelho Roubado ligada e o atraso de segurança em Sempre, cadastrar uma digital pede a sua digital e uma hora de espera, e as três também ficam iguais.")
                     : String(localized: "Contra quem não sabe o código do iPhone, as três protegem igual: cadastrar um rosto pede o código. Com a Proteção de Aparelho Roubado ligada e o atraso de segurança em Sempre, cadastrar um rosto pede o seu rosto e uma hora de espera, e as três também ficam iguais."))
                    .typeStyle(.note).foregroundStyle(Palette.inkMuted).padding(.top, Space.lg)
                    .fixedSize(horizontal: false, vertical: true)
                if let message { Banner(kind: .failure, title: message).padding(.top, Space.md) }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.md)
        }
        .background(Palette.void.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.refreshHardenedHold() }
        .fullScreenCover(isPresented: $locking) {
            HardenedLockFlow(on: on, wallets: wallets) { done in
                locking = false
                guard done else { return }
                choice = .lock
                if on {
                    session.refreshHardenedHold()
                    toasts.show(Self.doneMessage(.lock))
                } else {
                    lockAccepted = true
                }
            }
        }
    }

    /// O motivo embaixo de "Confirme com o PIN" ao trocar a opcao (pedido do dono, 18/10/2026:
    /// "Mudar o que acontece quando o Face ID mudar" lia mal).
    static var changeReason: String {
        String(localized: "Para trocar o que fazer se o \(KeyServices.biometryName) mudar.")
    }

    static func doneMessage(_ policy: RootKeyVault.HardenedFaceChange) -> String {
        String(localized: "Quando o \(KeyServices.biometryName) mudar: \(policy.title).")
    }

    private func select(_ policy: RootKeyVault.HardenedFaceChange) async {
        guard policy != choice, working == nil else { return }
        message = nil
        if policy == .lock {
            locking = true
            return
        }
        guard on else {
            // Sair do bloqueio ja escolhido pede o PIN (pedido do dono, 18/10/2026). Ligado, a
            // troca ja pede o PIN e o rosto, logo abaixo.
            if choice == .lock {
                do {
                    guard try await auth.perform(session, reason: Self.changeReason,
                                                 presence: .pin, { _ in true }) == true else { return }
                } catch {
                    message = AuthCoordinator.refusalMessage(error)
                    return
                }
            }
            choice = policy
            lockAccepted = false
            return
        }
        // Na espera de "Esperar 24 horas", mudar a politica espera: recusa antes do teclado.
        do {
            try KeyServices.root.checkHardenedAllowed()
        } catch {
            message = AuthCoordinator.refusalMessage(error)
            return
        }
        guard case .hardened(let pin, _)? = await auth.credential(reason: Self.changeReason) else { return }
        working = policy
        defer { working = nil }
        do {
            // So a ida para o bloqueio pede as palavras, e ela tem a tela dela.
            try await session.setHardenedFaceChange(policy, pin: pin, check: { _ in })
            choice = policy
            session.refreshHardenedHold()
            toasts.show(Self.doneMessage(policy))
        } catch {
            message = Self.failureMessage(error)
        }
    }

    /// Antes do commit, qualquer falha deixa a politica de antes valendo.
    static func failureMessage(_ error: Error) -> String? {
        switch error as? RootKeyVault.Failure {
        case .wrongPIN(let remaining)?: return AuthCoordinator.wrongPINMessage(remaining)
        case .biometryNotConfirmed(let remaining)?: return AuthCoordinator.faceNotConfirmedMessage(remaining)
        case .throttled(let seconds)?: return String(localized: "Tentativas demais. Tente de novo em \(LockView.duration(seconds)).")
        case .cancelled?: return String(localized: "O \(KeyServices.biometryName) não confirmou. Nada mudou.")
        case .biometryChanged?: return String(localized: "O \(KeyServices.biometryName) deste iPhone mudou durante a conferência. Nada mudou.")
        case .wiped?: return nil
        default:
            return AuthCoordinator.refusalMessage(error) ?? String(localized: "Não foi possível mudar agora. Nada mudou: o que valia continua valendo.")
        }
    }
}

/// "Bloquear as carteiras": a animacao em quatro quadros, o que vale, e o aceite. Desligado, o
/// aceite e a escolha para ligar (as palavras vem no fluxo de ligar); ligado, depois do aceite,
/// a frase inteira de cada carteira, e o PIN e o rosto duas vezes. Com a trava, o papel e o
/// unico caminho de volta: so ir para ela pede as palavras.
struct HardenedLockFlow: View {
    @Environment(AppSession.self) private var session
    @Environment(AuthCoordinator.self) private var auth
    let on: Bool
    let wallets: [WalletMeta]
    let onClose: (Bool) -> Void

    @State private var accepted = false
    @State private var typing = false
    @State private var typed: [UUID: WalletSecret] = [:]
    @State private var index = 0
    @State private var working = false
    @State private var message: String?
    /// Muda a cada recomeco, para a tela da frase nascer limpa.
    @State private var round = 0
    /// Muda quando a ativacao para com aviso: o deslizar volta ao comeco.
    @State private var attempt = 0

    static var consentText: String {
        String(localized: "Entendo que, se o \(KeyServices.biometryName) deste iPhone mudar, as carteiras daqui fecham de vez, e só as palavras de cada carteira trazem de volta. Os nomes, endereços salvos e ajustes daqui se perdem junto.")
    }

    var body: some View {
        NavigationStack {
            Group {
                if typing, wallets.indices.contains(index) {
                    let wallet = wallets[index]
                    ImportPhraseView(onFinished: { close(false) }, verify: .init(
                        walletName: wallet.name, wordCount: HardenedEnableFlow.wordCount(wallet), hasPassphrase: wallet.hasPassphrase
                    ) { secret in
                        typed[wallet.id]?.wipe()
                        typed[wallet.id] = secret
                        message = nil
                        index += 1
                        if index >= wallets.count {
                            typing = false
                            Task { await apply() }
                        }
                    })
                    .id("\(wallet.id)-\(round)")
                } else {
                    intro
                }
            }
            .background(Palette.void.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { close(false) } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                    }
                    .accessibilityLabel("Fechar")
                }
            }
        }
        .interactiveDismissDisabled()
        .guardedAgainstCapture()
    }

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HardenedLockStory()
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.xs)
                // No meio, e dito de outro jeito (pedido do dono, 18/10/2026).
                Group {
                    Text("Trancar de vez se o \(KeyServices.biometryName) mudar").typeStyle(.title).foregroundStyle(Palette.ink)
                        .padding(.top, Space.lg)
                    Text(KeyServices.usesFingerprint
                         ? String(localized: "Qualquer mudança no Touch ID, até uma digital sua, fecha as carteiras deste iPhone. Para voltar, você importa cada carteira pelas palavras, e os nomes, os endereços salvos e os ajustes daqui se perdem.")
                         : String(localized: "Qualquer mudança no \(KeyServices.biometryName), até no seu rosto, fecha as carteiras deste iPhone. Para voltar, você importa cada carteira pelas palavras, e os nomes, os endereços salvos e os ajustes daqui se perdem."))
                        .typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.top, Space.xs)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Para ativar, você digita as palavras de cada carteira e confirma com o PIN e o \(KeyServices.biometryName).")
                        .typeStyle(.note).foregroundStyle(Palette.inkMuted).padding(.top, Space.md)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                ConsentCheckbox(checked: $accepted, text: Self.consentText)
                    .padding(.top, Space.lg)
                    .accessibilityIdentifier("reforcado-bloquear-aceite")
                if let message { Banner(kind: .failure, title: message).padding(.top, Space.md) }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.md)
        }
        .safeAreaInset(edge: .bottom) {
            ActionFooter {
                // O deslizar de pixels, que um toque sem querer nao dispara (pedido do dono,
                // 18/10/2026).
                SlideToConfirm(title: String(localized: "Ativar o bloqueio"), enabled: accepted && !working) { start() }
                    .id(attempt)
                    .accessibilityIdentifier("reforcado-bloquear-confirmar")
            }
        }
    }

    private func start() {
        message = nil
        // Desligado: so a escolha. As palavras, o PIN e o rosto vem no fluxo de ligar.
        guard on else {
            onClose(true)
            return
        }
        do {
            try KeyServices.root.checkHardenedAllowed()
        } catch {
            message = AuthCoordinator.refusalMessage(error)
            attempt += 1
            return
        }
        // As frases ja digitadas (o PIN errado na tentativa anterior) valem: so o PIN de novo.
        if HardenedPhraseCheck.collect(wallets, typed: typed).count == wallets.count {
            Task { await apply() }
            return
        }
        restart()
        typing = true
    }

    private func apply() async {
        defer { if message != nil { attempt += 1 } }
        guard case .hardened(let pin, _)? = await auth.credential(reason: String(localized: "Para ativar o bloqueio se o \(KeyServices.biometryName) mudar.")) else {
            attempt += 1
            return
        }
        working = true
        defer { working = false }
        let checks = HardenedPhraseCheck.collect(wallets, typed: typed)
        guard checks.count == wallets.count else {
            pin.wipe()
            restart()
            return
        }
        do {
            try await session.setHardenedFaceChange(.lock, pin: pin) { rk in try HardenedPhraseCheck.run(checks, rk: rk) }
            close(true)
        } catch HardenedCheckError.mismatch(let name) {
            message = String(localized: "O que você digitou de \(name) não confere com esta carteira. Confira no papel e comece de novo.")
            restart()
        } catch HardenedCheckError.legacyPassphrase(let name) {
            message = HardenedEnableFlow.legacyPassphraseMessage(name)
            restart()
        } catch RootKeyVault.Failure.wiped {
            close(false)
        } catch {
            message = HardenedFaceChangeView.failureMessage(error)
        }
    }

    private func restart() {
        typed.values.forEach { $0.wipe() }
        typed = [:]
        index = 0
        round += 1
    }

    private func close(_ done: Bool) {
        typed.values.forEach { $0.wipe() }
        typed = [:]
        onClose(done)
    }
}

/// A animacao de "Bloquear as carteiras", em quatro quadros com os discos do emblema: o PIN e
/// o rosto abrem as carteiras; outro rosto entra no lugar; o cadeado fecha sobre as carteiras
/// apagadas; o papel das palavras traz de volta. Os glifos ficam fora do VoiceOver, e as
/// legendas sao lidas. Com Reduzir Movimento (ou o VoiceOver ligado), os quatro quadros ficam
/// parados, um embaixo do outro, cada um com a legenda dele.
struct HardenedLockStory: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var frame = 0

    static var captions: [String] {
        let name = KeyServices.biometryName
        if KeyServices.usesFingerprint {
            return [
                String(localized: "A sua digital e o PIN abrem as carteiras."),
                String(localized: "Alguém cadastra outra digital, ou apaga uma das suas."),
                String(localized: "As carteiras daqui fecham de vez. Ninguém abre, nem a Escalibur."),
                String(localized: "Só as palavras de cada carteira trazem de volta."),
            ]
        }
        return [
            String(localized: "O seu rosto e o PIN abrem as carteiras."),
            String(localized: "Alguém cadastra outro rosto, ou o \(name) é redefinido."),
            String(localized: "As carteiras daqui fecham de vez. Ninguém abre, nem a Escalibur."),
            String(localized: "Só as palavras de cada carteira trazem de volta."),
        ]
    }

    var body: some View {
        if reduceMotion || voiceOver || Self.stillForTests { still } else { animated }
    }

    /// `-quadros` (so no build de teste): os quatro quadros parados, um embaixo do outro.
    private static var stillForTests: Bool {
        #if DEBUG
        return DebugDemo.arguments.contains("-quadros")
        #else
        return false
        #endif
    }

    private var animated: some View {
        let captions = Self.captions
        return VStack(spacing: Space.md) {
            HardenedLockStage(frame: frame)
                .frame(width: HardenedLockStage.size.width, height: HardenedLockStage.size.height)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index == frame ? Palette.ink : Palette.edgeStrong)
                        .frame(width: index == frame ? 16 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            // As quatro legendas no mesmo lugar, so a do quadro visivel: a altura e a da maior, e
            // o texto embaixo nao pula.
            ZStack {
                ForEach(captions.indices, id: \.self) { index in
                    Text(captions[index])
                        .typeStyle(.body).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(index == frame ? 1 : 0)
                        .accessibilityHidden(index != frame)
                }
            }
            .frame(maxWidth: 300)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2800))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { frame = (frame + 1) % 4 }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: frame) { _, new in new == 2 }
    }

    private var still: some View {
        let captions = Self.captions
        return VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(captions.indices, id: \.self) { index in
                HStack(spacing: Space.md) {
                    HardenedLockStage(frame: index)
                        .frame(width: HardenedLockStage.size.width, height: HardenedLockStage.size.height)
                        .scaleEffect(0.5)
                        .frame(width: HardenedLockStage.size.width / 2, height: HardenedLockStage.size.height / 2)
                        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.body))
                        .accessibilityHidden(true)
                    Text(captions[index])
                        .typeStyle(.body).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Um quadro da animacao. As pecas sao as mesmas nos quatro; o quadro decide onde cada uma
/// esta e com que forca aparece, e a mola entre eles faz o movimento. Sem as tres carteiras
/// embaixo (pedido do dono, 18/10/2026): cada quadro tem uma peca so, no meio.
struct HardenedLockStage: View {
    static let size = CGSize(width: 240, height: 124)
    let frame: Int

    var body: some View {
        ZStack {
            // O PIN, so no primeiro quadro.
            HardenedDisc(icon: "circle.grid.3x3.fill", size: 62)
                .offset(x: -34)
                .opacity(frame == 0 ? 1 : 0)
            // O rosto do dono sobe e some no segundo quadro.
            HardenedDisc(icon: KeyServices.biometryIcon, size: 62)
                .offset(x: 34, y: frame == 0 ? 0 : -62)
                .opacity(frame == 0 ? 1 : 0)
            // O cadeado aberto entre os dois, quando o PIN e o rosto abrem.
            badge("lock.open.fill")
                .opacity(frame == 0 ? 1 : 0)
                .scaleEffect(frame == 0 ? 1 : 0.5)
            // Quadro 2: outro rosto sendo cadastrado no Face ID (pedido do dono, 18/10/2026).
            if frame == 1 {
                HardenedFaceScan()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            // Quadro 3: o selo de pixels fecha, com o cadeado vermelho.
            if frame == 2 {
                CipherEmblem(size: 104, symbol: "lock.fill", tint: Palette.down)
                    .transition(.scale(scale: 1.3).combined(with: .opacity))
            }
            // Quadro 4: a folha das palavras sendo anotada, a mesma de criar a carteira.
            if frame == 3 {
                PaperScribble(words: 8, size: CGSize(width: 150, height: 98))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    private func badge(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Palette.ink)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Palette.edgeStrong))
            .overlay(Circle().stroke(Palette.void, lineWidth: 3))
    }
}

/// Outro rosto sendo cadastrado no Face ID, no estilo de pixels do app: o glifo do Face ID no
/// meio e, em volta, um anel de pixels que acende em amarelo, como o cadastro de um rosto no
/// iPhone; cheio, entra o "+" de rosto novo, e o anel recomeca. Com Reduzir Movimento, o anel
/// fica cheio e parado.
private struct HardenedFaceScan: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let count = 44
    private static let cell: CGFloat = 5
    private static let period = 2.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.99 : (timeline.date.timeIntervalSinceReferenceDate / Self.period).truncatingRemainder(dividingBy: 1)
            // Tres quartos do ciclo enchendo, o resto cheio, com o "+".
            let fill = min(t / 0.72, 1)
            let full = fill >= 1
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) / 2 - Self.cell
                    for index in 0..<Self.count {
                        let share = Double(index) / Double(Self.count)
                        let angle = share * 2 * .pi - .pi / 2
                        let lit = share < fill
                        // A ponta que acende agora, mais clara.
                        let head = lit && share > fill - 1.5 / Double(Self.count) && !full
                        let point = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
                        let square = CGRect(x: point.x - Self.cell / 2, y: point.y - Self.cell / 2, width: Self.cell, height: Self.cell)
                        let color = head ? Color.white : (lit ? Palette.caution : PixelFill.gray(0.2 + 0.1 * PixelFill.noise(index, 3, 0x7A)))
                        context.fill(Path(roundedRect: square, cornerRadius: 1.3), with: .color(color))
                    }
                }
                Circle().fill(Palette.control).frame(width: 62, height: 62)
                Image(systemName: KeyServices.usesFingerprint ? "touchid" : "faceid")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(full ? Palette.caution : Palette.ink)
            }
            .frame(width: 100, height: 100)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.void)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Palette.caution))
                    .overlay(Circle().stroke(Palette.void, lineWidth: 3))
                    .scaleEffect(full ? 1 : 0.4)
                    .opacity(full ? 1 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: full)
                    .offset(x: -4, y: -4)
            }
        }
    }
}
