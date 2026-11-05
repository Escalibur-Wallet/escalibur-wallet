import EscaliburKeys
import SwiftUI

/// A4: o app trancado. O Face ID dispara sozinho quando o app esta na frente.
struct LockView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    /// O Face ID automatico ja foi tentado nesta vinda para a frente.
    @State private var triedBiometry = false
    @State private var entry = PINEntry()
    @State private var working = false
    @State private var forgotPIN = false
    @State private var confirmErase = false
    /// O pedido de "Esqueci o PIN": nil sem pedido, 0 pronto para apagar, mais que 0 o que falta.
    @State private var eraseRemaining: TimeInterval?
    @State private var eraseError: String?
    /// Modo reforcado com o cadastro de rostos trocado: o cofre nao abre mais aqui.
    @State private var vaultLost = false
    @State private var throttleTask: Task<Void, Never>?
    /// Super Security: o rosto ja confirmado, a espera do PIN (pedido do dono, 01/11/2026). Vale um PIN.
    @State private var facePass: RootKeyVault.HardenedFacePass?

    /// Depois de reiniciar (ou de a bateria acabar), o Face ID so vale depois do PIN.
    private var restartNeedsPIN: Bool { session.biometryEnabled && !KeyServices.root.pinEnteredThisBoot }

    /// Modo reforcado: a espera de "Esperar 24 horas", se correndo; senao, o aviso do rosto
    /// depois do PIN. Abrir o app vale na espera: o saldo aparece, o resto espera.
    private var hardenedSubtitle: String {
        let hold = KeyServices.root.hardenedHoldRemaining
        if hold > 0 { return AuthCoordinator.hardenedHoldMessage(hold) }
        if facePass != nil { return String(localized: "O \(KeyServices.biometryName) confirmou. Agora o PIN.") }
        return String(localized: "Super Security: primeiro o \(KeyServices.biometryName), depois o PIN.")
    }

    var body: some View {
        PINScreen(
            title: String(localized: "Digite o seu PIN"),
            subtitle: session.hardenedModeOn
                ? hardenedSubtitle
                : (restartNeedsPIN
                    ? String(localized: "O iPhone reiniciou. Depois de reiniciar ou de a bateria acabar, o PIN é necessário uma vez antes do \(KeyServices.biometryName) voltar a valer.")
                    : nil),
            entry: entry,
            showsBadge: true,
            biometryIcon: session.hardenedModeOn
                ? (facePass == nil ? KeyServices.biometryIcon : nil)
                : (session.biometryEnabled && !restartNeedsPIN ? KeyServices.biometryIcon : nil),
            onBiometry: { Task { session.hardenedModeOn ? await tryHardenedFace() : await tryBiometry() } },
            working: working,
            onComplete: { Task { await submit() } }
        ) {
            TertiaryButton(title: String(localized: "Esqueci o PIN")) { forgotPIN = true }
        }
        // O alerta de preco abre o app em segundo plano, as vezes com o iPhone
        // bloqueado: ai nao ha rosto para ler e o chaveiro nao responde. O Face ID
        // automatico espera o app vir para a frente, uma vez a cada vinda.
        .task(id: scenePhase) {
            // Aberta em segundo plano, com o chaveiro mudo, a tela nao sabia o tamanho do PIN.
            if scenePhase == .active { entry.refreshStoredLength() }
            guard scenePhase == .active, !triedBiometry else { return }
            triedBiometry = true
            showThrottleIfNeeded()
            // Com a trava de alerta ou a atualizacao obrigatoria na tela, o Face ID automatico nao abre por cima delas.
            guard !UpdateAlarmWindow.covering, !UpdateRequiredWindow.shared.covering else { return }
            if session.hardenedModeOn {
                await tryHardenedFace()
            } else if session.biometryEnabled, !restartNeedsPIN {
                await tryBiometry()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                triedBiometry = false
                // O rosto confirmado nao fica para a volta: na proxima vinda, o rosto de novo.
                if facePass != nil { KeyServices.root.discardHardenedFace(); facePass = nil }
            }
        }
        .sheet(isPresented: $forgotPIN) { forgotSheet }
        #if DEBUG
        // `-tela esqueci`: a folha de Esqueci o PIN aberta, para conferir o desenho no simulador.
        .onAppear { if DebugDemo.screen == "esqueci" { forgotPIN = true } }
        #endif
    }

    private func submit() async {
        working = true
        defer { working = false }
        let pin = entry.take()
        // O rosto confirmado vale este PIN so, certo ou errado. Sem ele (o rosto foi cancelado), o
        // cofre pede o rosto depois do PIN, como antes.
        let pass = facePass
        facePass = nil
        do {
            if let pass {
                try await session.unlock(pin: pin, face: pass)
            } else {
                try await session.unlock(pin: pin)
            }
        } catch let failure as RootKeyVault.Failure {
            handle(failure)
            if pass != nil, session.hardenedModeOn, !vaultLost { await tryHardenedFace() }
        } catch {
            entry.fail(String(localized: "Não foi possível destravar. Tente de novo."))
        }
    }

    /// Super Security: o rosto primeiro (pedido do dono, 01/11/2026). Cancelado ou nao reconhecido,
    /// o teclado continua, e o PIN pede o rosto depois.
    private func tryHardenedFace() async {
        guard session.hardenedModeOn, facePass == nil, KeyServices.root.throttleRemaining() <= 0 else { return }
        do {
            facePass = try await session.hardenedFace(reason: String(localized: "Destravar a Escalibur"))
        } catch RootKeyVault.Failure.biometryNotConfirmed {
            // Cancelado ou nao reconhecido: nada mudou, o teclado continua ali.
        } catch let failure as RootKeyVault.Failure {
            handle(failure)
        } catch {
            // O teclado continua ali.
        }
    }

    private func tryBiometry() async {
        guard session.biometryEnabled, KeyServices.root.throttleRemaining() <= 0 else { return }
        do {
            try await session.unlockWithBiometry()
        } catch RootKeyVault.Failure.pinRequiredAfterRestart {
            entry.fail(String(localized: "O iPhone reiniciou. Digite o PIN uma vez para o \(KeyServices.biometryName) voltar a valer."))
        } catch RootKeyVault.Failure.biometryChanged {
            entry.fail(String(localized: "O \(KeyServices.biometryName) deste iPhone mudou desde que foi ligado aqui. Entre com o PIN; depois você pode religar."))
        } catch {
            // Cancelado: o teclado continua ali.
        }
    }

    private func handle(_ failure: RootKeyVault.Failure) {
        switch failure {
        case .wrongPIN(let remaining):
            entry.fail(AuthCoordinator.wrongPINMessage(remaining))
            showThrottleIfNeeded()
        case .throttled(let seconds):
            entry.fail(String(localized: "Tentativas demais. Tente de novo em \(Self.duration(seconds))."))
            showThrottleIfNeeded()
        case .wiped:
            session.eraseEverything()
        case .biometryNotConfirmed(let remaining):
            entry.fail(AuthCoordinator.faceNotConfirmedMessage(remaining))
            showThrottleIfNeeded()
        case .hardenedSlotLost:
            vaultLost = true
            forgotPIN = true
        case .biometryLockedOut, .biometryUnavailable, .biometryNotEnrolled, .hardenedFaceKeyFailed:
            entry.fail(AuthCoordinator.refusalMessage(failure) ?? String(localized: "Não foi possível destravar. Tente de novo."))
        default:
            entry.fail(String(localized: "Não foi possível destravar. Tente de novo."))
        }
    }

    private func showThrottleIfNeeded() {
        guard KeyServices.root.throttleRemaining() > 0 else { return }
        throttleTask?.cancel()
        throttleTask = Task { @MainActor in
            while !Task.isCancelled {
                let left = KeyServices.root.throttleRemaining()
                if left <= 0 {
                    entry.error = nil
                    return
                }
                entry.error = String(localized: "Tentativas demais. Tente de novo em \(Self.duration(left)).")
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        if s < 60 { return s == 1 ? String(localized: "1 segundo") : String(localized: "\(s) segundos") }
        let m = Int((Double(s) / 60).rounded(.up))
        if m < 60 { return m == 1 ? String(localized: "1 minuto") : String(localized: "\(m) minutos") }
        let h = Int((Double(m) / 60).rounded(.up))
        if h < 48 { return h == 1 ? String(localized: "1 hora") : String(localized: "\(h) horas") }
        // A escada vai ate 7 dias por tentativa (auditoria 4, C7-04).
        let d = Int((Double(h) / 24).rounded(.up))
        return String(localized: "\(d) dias")
    }

    private var forgotSheet: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "") { forgotPIN = false }
            ScrollView {
                // Redesenho do dono (01/11/2026): sem o icone num circulo nem o cartao de passos
                // numerados, que tinham cara de template. Uma cena de pixels conta a saida: o PIN se
                // desfaz, as palavras anotadas aparecem e viram um PIN novo. Texto alinhado a esquerda.
                VStack(alignment: .leading, spacing: 0) {
                    ForgotPINScene()
                        .padding(.top, -Space.xs)
                    Text(vaultLost ? String(localized: "O \(KeyServices.biometryName) mudou") : String(localized: "Não existe redefinir o PIN"))
                        .typeStyle(.title).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.md)
                    Text(vaultLost
                         ? (KeyServices.root.hardenedFaceChange == .lock
                            ? String(localized: "No Super Security, as carteiras deste iPhone só abrem com o PIN e o mesmo \(KeyServices.biometryName) de quando ele foi ligado. O cadastro mudou, e ninguém consegue abrir, nem a Escalibur. Para voltar a usar o app, comece de novo:")
                            // Fora da trava, so a chave que sumiu (uma redefinicao do Face ID, por exemplo).
                            : String(localized: "No Super Security, as carteiras deste iPhone só abrem com o PIN e a chave do \(KeyServices.biometryName) que nasceu com ele. A chave não existe mais, e ninguém consegue abrir, nem a Escalibur. Para voltar a usar o app, comece de novo:"))
                         : String(localized: "O PIN mora só neste iPhone, e ninguém tem cópia dele, nem a Escalibur. Para voltar a usar o app, comece de novo:"))
                        .typeStyle(.body).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.xs)
                    VStack(alignment: .leading, spacing: Space.base) {
                        ForgotStep(number: 1, text: String(localized: "Tenha em mãos a senha de cada carteira (as 12 ou 24 palavras) ou o envelope Escalibur, e a passphrase de cada carteira que usa passphrase."))
                        ForgotStep(number: 2, text: String(localized: "Apague as carteiras deste iPhone."))
                        ForgotStep(number: 3, text: String(localized: "Crie um PIN novo e importe cada carteira de novo."))
                    }
                    .padding(.top, Space.lg)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.xs)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: Space.sm) {
                // Cofre reforcado que nao abriu: tentar de novo vem primeiro. Apagar e para
                // sempre, e o motivo pode ter sido passageiro.
                if vaultLost {
                    PrimaryButton(title: String(localized: "Tentar de novo")) { forgotPIN = false; vaultLost = false }
                    DestructiveButton(title: String(localized: "Apagar as carteiras deste iPhone")) { confirmErase = true }
                } else {
                    // Apagar pela tela de bloqueio so 24 horas depois do pedido: quem pega o iPhone
                    // destravado nao apaga as carteiras do dono na hora (revisao de seguranca de 27/10/2026).
                    if let eraseError {
                        Text(eraseError).typeStyle(.note).foregroundStyle(Palette.down).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    switch eraseRemaining {
                    case nil:
                        DestructiveButton(title: String(localized: "Pedir para apagar em 24 horas")) {
                            do {
                                try KeyServices.root.requestForgotPINErase()
                                eraseError = nil
                            } catch {
                                eraseError = String(localized: "Não foi possível fazer o pedido agora. Tente de novo.")
                            }
                            eraseRemaining = KeyServices.root.forgotPINEraseRemaining
                        }
                    case let left? where left > 0:
                        // A contagem anda com a folha aberta.
                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text("Apagar fica disponível em \(Self.duration(KeyServices.root.forgotPINEraseRemaining ?? left)). Reiniciar o aparelho recomeça a contagem. Se lembrar o PIN, é só destravar: o pedido some.")
                                .typeStyle(.note).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        TertiaryButton(title: String(localized: "Cancelar o pedido")) {
                            KeyServices.root.cancelForgotPINErase()
                            eraseRemaining = nil
                        }
                    default:
                        DestructiveButton(title: String(localized: "Apagar as carteiras deste iPhone")) { confirmErase = true }
                    }
                    SecondaryButton(title: String(localized: "Voltar e tentar o PIN")) { forgotPIN = false }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xs)
        }
        .presentationDetents([.large])
        .onAppear { eraseRemaining = KeyServices.root.forgotPINEraseRemaining }
        .presentationBackground(Palette.body)
        .presentationCornerRadius(Radius.sheet)
        // O alerta do proprio iPhone, no centro da tela: apagar e para sempre.
        .whiteAlert("Apagar as carteiras deste iPhone?", isPresented: $confirmErase) {
            Button("Apagar permanentemente", role: .destructive) {
                forgotPIN = false
                // Confere de novo no cofre: so com a espera cumprida, ou com o cofre perdido.
                if vaultLost || KeyServices.root.forgotPINEraseRemaining == 0 {
                    session.eraseEverything()
                } else {
                    eraseRemaining = KeyServices.root.forgotPINEraseRemaining
                    eraseError = String(localized: "Não foi possível fazer o pedido agora. Tente de novo.")
                    forgotPIN = true
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Sem a senha de cada carteira ou um envelope, e a passphrase das que usam passphrase, o saldo delas fica inacessível para sempre.")
        }
    }
}

/// Um passo de como voltar a usar o app sem o PIN: o numero no mesmo tipo do texto, mais apagado,
/// sem circulo nem cartao.
private struct ForgotStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text("\(number)")
                .typeStyle(.row).foregroundStyle(Palette.inkMuted)
                .monospacedDigit()
                .frame(width: 16, alignment: .leading)
            Text(text).typeStyle(.body).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A saida de quem esqueceu o PIN, em pixels que cifram, como as cenas da passphrase: os seis
/// pontos do PIN se desfazem em ruido, as palavras anotadas aparecem uma a uma e sobem para
/// virar um PIN novo, em lima. Nada aqui e de verdade: pontos e palavras sao desenho.
struct ForgotPINScene: View {
    var height: CGFloat = 176
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private enum G {
        static let width: CGFloat = 300
        static let height: CGFloat = 176
        static let pitch: CGFloat = 6
        static let cell: CGFloat = 4.6
        static let period = 7.2
        /// Os seis pontos do PIN: 3 por 3 pixels cada, com 4 pixels entre eles.
        static let dotsY: CGFloat = 40
        static let dotSize = 3
        static let dotGap = 4
        /// As palavras: 2 fileiras de 6 pastilhas de 5 por 2 pixels.
        static let tilesY: CGFloat = 104
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let t = reduceMotion ? 5.6 : elapsed.truncatingRemainder(dividingBy: G.period)
            let clock = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let scale = min(size.width / G.width, size.height / G.height)
                context.translateBy(x: (size.width - G.width * scale) / 2, y: (size.height - G.height * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                context.opacity = reduceMotion ? 1 : min(Self.smooth(t / 0.3), 1 - Self.smooth((t - (G.period - 0.45)) / 0.45))
                draw(context, t: t, clock: clock)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }

    private func draw(_ context: GraphicsContext, t: Double, clock: Double) {
        func tone(_ id: Int, _ layer: Int) -> Double {
            let phase = PixelFill.noise(id, layer, 0x5F1)
            let beat = clock * 4 * (0.6 + 0.8 * phase) + phase * 8
            let step = beat.rounded(.down)
            let s = beat - step
            let a = PixelFill.noise(id, layer, Int(step)), b = PixelFill.noise(id, layer, Int(step) + 1)
            return a + (b - a) * s * s * (3 - 2 * s)
        }
        func dot(_ center: CGPoint, _ color: Color, _ alpha: Double) {
            guard alpha > 0.01 else { return }
            let rect = CGRect(x: center.x - G.cell / 2, y: center.y - G.cell / 2, width: G.cell, height: G.cell)
            context.fill(Path(roundedRect: rect, cornerRadius: G.cell * 0.24), with: .color(color.opacity(alpha)))
        }
        // Onde fica cada pixel dos seis pontos do PIN.
        let dotsWidth = CGFloat(6 * G.dotSize + 5 * G.dotGap) * G.pitch
        let dotsX = (G.width - dotsWidth) / 2
        func pinPixel(_ index: Int) -> CGPoint {
            let dot = index / (G.dotSize * G.dotSize), inner = index % (G.dotSize * G.dotSize)
            let column = dot * (G.dotSize + G.dotGap) + inner % G.dotSize
            return CGPoint(x: dotsX + (CGFloat(column) + 0.5) * G.pitch, y: G.dotsY + (CGFloat(inner / G.dotSize) + 0.5) * G.pitch)
        }
        let pinPixels = 6 * G.dotSize * G.dotSize

        // 1. O PIN de antes: aceso, e depois se desfaz em ruido, de cada pixel para um lado.
        let dissolve = Self.smooth((t - 0.9) / 1.5)
        for index in 0..<pinPixels {
            let home = pinPixel(index)
            let spread = CGFloat(dissolve) * 30
            let dx = (CGFloat(PixelFill.noise(index, 3, 1)) - 0.5) * spread * 2
            let dy = (CGFloat(PixelFill.noise(index, 3, 2)) - 0.5) * spread * 2 - CGFloat(dissolve) * 8
            let value = dissolve > 0 ? 0.3 + 0.45 * tone(index, 2) : 0.9
            dot(CGPoint(x: home.x + dx, y: home.y + dy), PixelFill.gray(value), 1 - Self.smooth((dissolve - 0.45) / 0.55))
        }

        // 2. As palavras anotadas aparecem, uma pastilha de cada vez.
        let tilesWidth = CGFloat(6 * 5 + 5) * G.pitch
        let tilesX = (G.width - tilesWidth) / 2
        var tilePixels: [(home: CGPoint, id: Int, appear: Double)] = []
        for tile in 0..<12 {
            let appear = Self.smooth((t - 2.3 - Double(tile) * 0.09) / 0.35)
            for px in 0..<5 {
                for py in 0..<2 {
                    let home = CGPoint(x: tilesX + (CGFloat((tile % 6) * 6 + px) + 0.5) * G.pitch,
                                       y: G.tilesY + (CGFloat((tile / 6) * 3 + py) + 0.5) * G.pitch)
                    tilePixels.append((home, tile * 10 + px * 2 + py, appear))
                }
            }
        }
        // 3. As palavras sobem e viram o PIN novo, em lima: so quem tem as palavras volta.
        let rise = Self.smooth((t - 4.0) / 1.3)
        for (index, pixel) in tilePixels.enumerated() {
            let delay = PixelFill.noise(pixel.id, 9, 0x2C) * 0.4
            let f = Self.smooth((rise - delay) / (1 - delay + 0.0001))
            let target = pinPixel(index % pinPixels)
            let x = pixel.home.x + (target.x - pixel.home.x) * CGFloat(f)
            let y = pixel.home.y + (target.y - pixel.home.y) * CGFloat(f) - CGFloat(sin(f * .pi)) * 14
            let resting = PixelFill.gray(0.42 + 0.36 * tone(pixel.id, 5))
            // Os que chegam somem dentro do ponto novo; o ponto e desenhado inteiro abaixo.
            dot(CGPoint(x: x, y: y), resting, pixel.appear * (1 - Self.smooth((f - 0.8) / 0.2)))
        }
        let settled = Self.smooth((t - 5.0) / 0.5)
        for index in 0..<pinPixels {
            dot(pinPixel(index), Palette.lime, settled)
        }
        // As palavras ficam, apagadas, depois de virar o PIN: elas continuam sendo a saida.
        for pixel in tilePixels {
            dot(pixel.home, PixelFill.gray(0.2 + 0.12 * tone(pixel.id, 6)), settled * 0.9)
        }
    }

    static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
