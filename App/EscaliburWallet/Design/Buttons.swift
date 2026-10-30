import SwiftUI

/// Os quatro botoes do app. Nenhum usa `.disabled()` para escurecer: o estado
/// desligado e opaco e declarado, porque transparencia sobre preto lê como erro de
/// renderizacao, e o botao desligado precisa continuar dizendo o que falta.
struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var loading: Bool = false
    /// Fundo branco no lugar do rosa (o "Copiar as palavras", pedido do dono, 18/10/2026).
    var light: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled && !loading { action() } }) {
            ZStack {
                if loading {
                    ProgressView().tint(Palette.onAccent)
                } else {
                    Text(title).typeStyle(.action)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Height.primary)
        }
        .buttonStyle(PrimaryStyle(enabled: enabled, light: light))
        // Desligado de verdade, nao so no desenho: o VoiceOver diz "esmaecido" e o
        // toque nem chega a acao.
        .disabled(!enabled)
    }
}

struct PrimaryStyle: ButtonStyle {
    var enabled: Bool = true
    var light: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Desligado continua legivel (4,8:1): o texto diz o que falta.
            .foregroundStyle(enabled ? (light ? Palette.onLive : Palette.onAccent) : Palette.inkMuted)
            .background(
                Capsule(style: .continuous)
                    .fill(enabled ? fill(configuration.isPressed) : Palette.rail)
            )
            .scaleEffect(configuration.isPressed && enabled ? 0.985 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }

    private func fill(_ pressed: Bool) -> Color {
        if light { return pressed ? Palette.livePress : Palette.live }
        return pressed ? Palette.accentPress : Palette.accent
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = Height.secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)) }
                Text(title).typeStyle(.action)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
        .buttonStyle(SecondaryStyle())
    }
}

struct SecondaryStyle: ButtonStyle {
    var surface: Palette.Surface = .void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.ink)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? Palette.rail : Palette.body)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Palette.edge, lineWidth: 1)
                    )
            )
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct TertiaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeStyle(.body)
                .frame(minHeight: Height.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(TertiaryStyle())
    }
}

struct TertiaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Palette.ink : Palette.inkSoft)
    }
}

struct DestructiveButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeStyle(.action)
                .frame(maxWidth: .infinity)
                .frame(height: Height.secondary)
        }
        .buttonStyle(DestructiveStyle())
    }
}

struct DestructiveStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.down)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? Palette.downPress : Palette.downTint)
            )
    }
}

/// Rodape fixo de acao: margens de 20, area segura mais 8, fundo solido.
struct ActionFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Space.sm) { content }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xs)
            .background(Palette.void)
    }
}

/// Estilo de linha pressionavel de borda a borda.
struct RowStyle: ButtonStyle {
    var surface: Palette.Surface = .void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Palette.pressed(on: surface) : Color.clear)
    }
}

/// Circulo de acao rapida (Enviar, Receber, Trocar, Limite).
struct QuickAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: Height.quickAction, height: Height.quickAction)
                    .background(Circle().fill(Palette.rail))
                Text(title)
                    .typeStyle(.label)
                    .foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(QuickActionStyle())
    }
}

private struct QuickActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A acao de receber quando falta saldo: lima chapado, texto escuro, em capsula. O
/// unico botao lima do app, para "o que fazer agora" nao se perder na tela.
struct AccentButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 16, weight: .bold)) }
                Text(title).typeStyle(.action)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Height.primary)
        }
        .buttonStyle(AccentStyle())
    }
}

struct AccentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.onAccent)
            .background(Capsule(style: .continuous).fill(Palette.accent.opacity(configuration.isPressed ? 0.8 : 1)))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// O botao primario de copiar. No toque, a capsula da um pulo curto, o icone de
/// copiar vira visto com um quique, o rotulo sobe e da lugar a `doneTitle`, e uma faixa
/// clara atravessa a capsula da esquerda para a direita. Depois de 2 segundos volta,
/// pelo caminho inverso. Com Reduzir Movimento, so troca o icone e o texto.
struct CopyButton: View {
    var title = String(localized: "Copiar endereço")
    var doneTitle = String(localized: "Endereço copiado")
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var taps = 0
    @State private var reset: Task<Void, Never>?

    var body: some View {
        let still = reduceMotion
        Button {
            action()
            taps += 1
            reset?.cancel()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { copied = true }
            reset = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { copied = false }
            }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 16, weight: .bold))
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .symbolEffect(.bounce, value: taps)
                    .frame(width: 20)
                ZStack {
                    Text(copied ? doneTitle : title)
                        .typeStyle(.action)
                        .id(copied)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
                .clipped()
            }
            .frame(maxWidth: .infinity)
            .frame(height: Height.primary)
            .background {
                if !still {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let band = width * 0.45
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.6), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            // De -1 (fora, a esquerda) a 1 (fora, a direita); parada, some.
                            .keyframeAnimator(initialValue: CGFloat(-1), trigger: taps) { view, x in
                                view.offset(x: (width + band) * (x + 1) / 2 - band).opacity(x > -1 && x < 1 ? 1 : 0)
                            } keyframes: { _ in
                                CubicKeyframe(1, duration: 0.65)
                            }
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(Capsule(style: .continuous))
            .keyframeAnimator(initialValue: 1.0, trigger: taps) { view, scale in
                view.scaleEffect(still ? 1 : scale)
            } keyframes: { _ in
                SpringKeyframe(0.96, duration: 0.08)
                SpringKeyframe(1.025, duration: 0.18)
                SpringKeyframe(1, duration: 0.28)
            }
        }
        .buttonStyle(PrimaryStyle())
        .sensoryFeedback(.success, trigger: taps)
        .accessibilityLabel(copied ? doneTitle : title)
    }
}

/// O Colar do app. Primeiro o PasteButton do sistema, que cola sem o pedido de permissao do
/// iOS. Depois de um tempo com o app aberto, o iOS as vezes encolhe esse botao a nada, e ele
/// some da tela: o Colar da frase sumiu assim num iPhone com iOS 26.3.1 (30/10/2026), e o forum
/// da Apple tem o mesmo relato desde o iOS 17. Encolhido, entra no lugar um botao do app, com o
/// mesmo rotulo e o mesmo estilo de quem chama (`tint`, `labelStyle`, `buttonBorderShape`,
/// `controlSize`), que le a area de transferencia direto; ai o iOS pergunta antes de colar.
struct AppPasteButton: View {
    let onPaste: @MainActor (String) -> Void

    @State private var width: CGFloat = 0
    @State private var collapsed = false

    var body: some View {
        if collapsed {
            Button {
                Task {
                    // Fora da fila principal: a leitura espera a resposta do iOS ("Permitir
                    // Colar"), e a tela nao trava enquanto isso.
                    guard let text = await Task.detached(operation: { UIPasteboard.general.string }).value else { return }
                    onPaste(text)
                }
            } label: {
                Label(String(localized: "Colar"), systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
        } else {
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in onPaste(text) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { value in
                width = value
                guard value < 8 else { return }
                Task { @MainActor in
                    // Na primeira medida o tamanho pode vir zero: so conta se continuar assim.
                    try? await Task.sleep(for: .milliseconds(600))
                    if width < 8 { collapsed = true }
                }
            }
            .task {
                #if DEBUG
                // `-colar-do-app`: o botao do app desde o inicio, para o teste e para ver no simulador.
                if DebugDemo.arguments.contains("-colar-do-app") { collapsed = true }
                #endif
            }
        }
    }
}

/// Um botao que so dispara depois de segurado por `holdSeconds`: os pixels enchem o fundo
/// enquanto o dedo esta em cima, e soltar antes cancela. Para o "usar mesmo assim" de um risco
/// grande, que nao pode sair de um toque sem querer. Com 0 segundos, e um toque comum.
struct HoldButton: View {
    let title: String
    var holdSeconds: Double = 2
    /// Com uma cor, o botao enche com ela, da esquerda para a direita, no lugar dos pixels (o
    /// vermelho de apagar uma carteira, pedido do dono, 22/10/2026).
    var fill: Color? = nil
    let action: () -> Void
    /// Quando o dedo encostou; nil solto.
    @State private var pressedAt: Date?
    /// Soltou antes do fim: os pixels voltam dali, rapido.
    @State private var released: (at: Date, from: CGFloat)?
    /// `-segure <fracao>` (so no build de teste): os pixels parados nessa fracao, para ver o
    /// preenchimento sem o dedo.
    @State private var parked: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Quanto do botao os pixels cobrem agora, de 0 a 1.
    private func fraction(_ now: Date) -> CGFloat {
        if let parked { return parked }
        if let pressedAt { return CGFloat(min(max(now.timeIntervalSince(pressedAt) / holdSeconds, 0), 1)) }
        if let released { return released.from * CGFloat(max(0, 1 - now.timeIntervalSince(released.at) / 0.2)) }
        return 0
    }

    var body: some View {
        Text(title).typeStyle(.action).foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity).frame(height: Height.secondary)
            .background(
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(Palette.rail)
                    // Enquanto o dedo segura, os pixels que cifram do `SlideToConfirm` enchem o
                    // botao (pedido do dono, 17/10/2026; o verde de 18/10 voltou a ser pixels no
                    // mesmo dia).
                    GeometryReader { geometry in
                        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: pressedAt == nil && released == nil && parked == nil)) { timeline in
                            let width = geometry.size.width
                            if let fill {
                                Rectangle().fill(fill).frame(width: fraction(timeline.date) * width)
                            } else {
                                let pixels = PixelFill(edge: fraction(timeline.date) * (width + PixelFill.frontier + 32), width: width,
                                                       doneAt: nil, now: timeline.date, still: reduceMotion, tilt: 0)
                                Canvas { context, size in pixels.draw(&context, size: size) }
                            }
                        }
                    }
                }
            )
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .onTapGesture { if holdSeconds <= 0 { action() } }
            .onLongPressGesture(minimumDuration: max(holdSeconds, 0.01), maximumDistance: 40) {
                guard holdSeconds > 0 else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                action()
            } onPressingChanged: { pressing in
                guard holdSeconds > 0 else { return }
                let now = Date()
                if pressing {
                    released = nil
                    pressedAt = now
                } else {
                    let from = fraction(now)
                    pressedAt = nil
                    released = (now, from)
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        if pressedAt == nil { released = nil }
                    }
                }
            }
        #if DEBUG
            .onAppear {
                if let index = DebugDemo.arguments.firstIndex(of: "-segure"), DebugDemo.arguments.indices.contains(index + 1),
                   let value = Double(DebugDemo.arguments[index + 1]) {
                    parked = CGFloat(min(max(value, 0), 1))
                }
            }
        #endif
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(holdSeconds > 0 ? "Segure por \(Int(holdSeconds)) segundos" : "")
    }
}

/// Deslizar para seguir: o trilho com o cadeado que o dedo leva ate o fim. Para passos
/// que pedem atencao (digitar as palavras): um toque sem querer nao segue. Atras do
/// cadeado, pixels cinza cifrando (`PixelFill`), sem texto por cima; no fim eles selam
/// num cinza so, e a acao vem na hora. Em repouso o cadeado da uma espiada para a direita
/// de tempos em tempos. Soltou antes do fim, volta. No VoiceOver, o toque duplo confirma.
struct SlideToConfirm: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void
    @State private var offset: CGFloat = 0
    @State private var hint: CGFloat = 0
    @State private var dragging = false
    @State private var done = false
    @State private var doneAt: Date?
    /// Depois da onda final a grade nao muda mais: a linha do tempo para.
    @State private var settled = false
    /// `-deslize <fracao>` (so no build de teste): o cadeado parado nessa fracao do trilho,
    /// para ver os pixels sem o dedo.
    @State private var parked: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let height: CGFloat = 64

    private func label(_ color: Color, knob: CGFloat) -> some View {
        HStack(spacing: Space.xs) {
            Text(title).typeStyle(.action)
            Image(systemName: "chevron.forward.2").font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.leading, knob * 0.8)
    }

    var body: some View {
        GeometryReader { geo in
            let knob = height - 8
            let travel = max(geo.size.width - knob - 8, 1)
            let shift = min((parked.map { $0 * travel } ?? offset) + hint, travel)
            let showing = enabled && (shift > 0 || done)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.rail)
                TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || !showing || settled)) { timeline in
                    let pixels = PixelFill(edge: 4 + shift + knob / 2, width: geo.size.width, doneAt: done ? doneAt ?? .distantPast : nil,
                                           now: timeline.date, still: reduceMotion)
                    ZStack(alignment: .leading) {
                        Canvas { context, size in pixels.draw(&context, size: size) }
                            .clipShape(Capsule())
                            .opacity(showing ? 1 : 0)
                        // O texto so na frente do cadeado: onde os pixels ja preencheram, nada
                        // (pedido do dono, 16/10/2026).
                        label(enabled ? Palette.ink : Palette.inkMuted, knob: knob)
                            .mask(alignment: .trailing) {
                                Rectangle().frame(width: max(geo.size.width - (4 + shift + knob), 0))
                            }
                            .opacity(done ? 0 : 1)
                    }
                }
                Circle()
                    .fill(enabled ? Color.white : Palette.control)
                    .frame(width: knob, height: knob)
                    .overlay {
                        // Sem o cadeado abrindo no fim: a animacao atrasava a tela seguinte.
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(enabled ? Palette.void : Palette.inkMuted)
                    }
                    .offset(x: 4 + shift)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard enabled, !done else { return }
                                dragging = true
                                hint = 0
                                offset = min(max(value.translation.width, 0), travel)
                            }
                            .onEnded { _ in
                                dragging = false
                                guard enabled, !done else { return }
                                if offset > travel * 0.85 {
                                    doneAt = Date()
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                        offset = travel
                                        done = true
                                    }
                                    action()
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(Int(PixelFill.finale * 1000)))
                                        settled = true
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: height)
        .sensoryFeedback(.success, trigger: done) { _, new in new }
        .sensoryFeedback(.selection, trigger: offset > 0) { old, new in !old && new }
        // Quem volta para esta tela encontra o cadeado fechado no comeco de novo.
        .onAppear {
            offset = 0
            hint = 0
            done = false
            doneAt = nil
            settled = false
            #if DEBUG
            if let index = DebugDemo.arguments.firstIndex(of: "-deslize"), DebugDemo.arguments.indices.contains(index + 1),
               let fraction = Double(DebugDemo.arguments[index + 1]) {
                parked = CGFloat(min(max(fraction, 0), 1))
            }
            #endif
        }
        // A espiada: o cadeado anda um pouco e volta, para dizer que desliza.
        .task(id: enabled) {
            guard enabled, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2600))
                guard !Task.isCancelled, !dragging, !done, offset == 0 else { continue }
                withAnimation(.easeOut(duration: 0.3)) { hint = 16 }
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { hint = 0 }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if enabled { action() } }
        // Depois do elemento montado: assim o VoiceOver (e o teste) le "desabilitado".
        .disabled(!enabled)
    }
}

/// O preenchimento do `SlideToConfirm`: pixels cinza que cifram (pedido do dono,
/// 16/10/2026, no lugar do verde de 15/10). Atras do cadeado, cada pixel troca de tom o
/// tempo todo, como bits de um texto cifrado, e cada um no seu compasso, cruzando de um tom
/// para o outro sem piscar. Na frente que avanca, os pixels nascem pequenos e com mais
/// contraste, e encaixam; de tempos em tempos uma passada clara corre a parte cifrada. No
/// fim, a varredura corre o resto do trilho, os tons param num cinza so e as juntas fecham:
/// o selo. Sem sorteio: o mesmo gesto, no mesmo instante, da sempre o mesmo desenho.
struct PixelFill {
    /// Ate onde os pixels chegam: o centro do cadeado.
    let edge: CGFloat
    let width: CGFloat
    /// Quando o dedo levou o cadeado ate o fim; nil enquanto nao chegou.
    let doneAt: Date?
    let now: Date
    /// Reduzir Movimento: nada de cifra correndo, e o fim vem sem a varredura.
    let still: Bool
    /// O atraso das linhas de baixo (`slant`, a diagonal do deslizar). Zero, a frente anda
    /// reta, como no "Segure para usar mesmo assim" (pedido do dono, 18/10/2026).
    var tilt: CGFloat = PixelFill.slant

    static let cell: CGFloat = 6
    static let gap: CGFloat = 1.5
    /// A largura da frente onde os pixels ainda estao encaixando.
    static let frontier: CGFloat = 48
    /// Quanto a linha de baixo atrasa em relacao a de cima: a varredura sai na diagonal.
    static let slant: CGFloat = 0.55
    /// Quantas trocas de tom por segundo, por pixel.
    static let rate = 7.0
    /// A passada clara, em segundos por volta.
    static let pass = 1.8
    /// A varredura do fim e o selar, em segundos.
    static let wave = 0.34
    static let finale = 0.8
    /// O cinza do selo, e o fundo das juntas.
    static let sealTone = 0.66

    private var elapsed: Double? { doneAt.map { now.timeIntervalSince($0) } }

    /// A borda dos pixels, ja com a varredura do fim.
    var reach: CGFloat {
        guard let elapsed else { return edge }
        if still { return width * 2 + Self.frontier }
        let end = width + Self.frontier + 64
        return edge + (end - edge) * CGFloat(Self.easeOut(elapsed / Self.wave))
    }

    /// Ate onde os pixels ja encaixaram em todas as linhas.
    var solid: CGFloat { reach - Self.frontier - 32 }

    /// O selo: 0 com a cifra correndo, 1 com o cinza inteiro e parado.
    var merge: Double {
        guard let elapsed else { return 0 }
        if still { return 1 }
        return Self.smooth((elapsed - Self.wave * 0.8) / (Self.finale - Self.wave))
    }

    func draw(_ context: inout GraphicsContext, size: CGSize) {
        let pitch = Self.cell + Self.gap
        let columns = Int((size.width / pitch).rounded(.up))
        let rows = Int(((size.height + Self.gap) / pitch).rounded(.up))
        let top = (size.height - (CGFloat(rows) * pitch - Self.gap)) / 2
        let reach = self.reach
        let merge = self.merge
        let clock = still ? 0 : now.timeIntervalSinceReferenceDate
        // A passada clara anda da esquerda ate a frente, e some no selo.
        let sweep = CGFloat((clock / Self.pass).truncatingRemainder(dividingBy: 1)) * max(reach + 40, 1) - 20

        // Por baixo, as juntas: escuras com a cifra correndo, do cinza do selo no fim.
        if solid > 0 {
            context.fill(Path(CGRect(x: 0, y: 0, width: min(solid, size.width), height: size.height)),
                         with: .color(Self.gray(0.14 + (Self.sealTone - 0.14) * merge)))
        }
        let middle = CGFloat(rows - 1) / 2
        for column in 0..<columns {
            let x = CGFloat(column) * pitch
            if x - reach > Self.frontier { break }
            for row in 0..<rows {
                // A linha do meio acompanha o cadeado; as de baixo vem um pouco atras.
                let lag = (CGFloat(row) - middle) * pitch * tilt
                let progress = Self.smooth(Double((reach - lag - (x + Self.cell / 2)) / Self.frontier))
                guard progress > 0.02 else { continue }
                // O tom cifrado deste pixel agora: dois tons sorteados pelo hash do lugar e
                // do compasso, cruzados devagar, cada pixel com a sua fase.
                let phase = Self.noise(column, row, 0x9E37)
                let beat = clock * Self.rate * (0.6 + 0.8 * phase) + phase * 8
                let step = beat.rounded(.down)
                let blend = Self.smooth(beat - step)
                let a = Self.noise(column, row, Int(step)), b = Self.noise(column, row, Int(step) + 1)
                let bit = a + (b - a) * blend
                // Na frente, mais contraste: os bits mais claros acendem antes de encaixar.
                let edgeHeat = 1 - progress
                var tone = 0.17 + 0.26 * bit + 0.46 * edgeHeat * bit * bit * bit
                // A passada clara.
                let distance = Double((x + Self.cell / 2 - sweep) / 22)
                tone += 0.16 * exp(-distance * distance) * (1 - merge)
                // O selo: todos no mesmo cinza.
                tone = tone + (Self.sealTone - tone) * merge
                // Nasce menor e encaixa no tamanho cheio; no selo, as juntas fecham.
                let inset = Self.cell * 0.32 * CGFloat(1 - progress) - Self.gap / 2 * CGFloat(merge)
                let square = CGRect(x: x + inset, y: top + CGFloat(row) * pitch + inset,
                                    width: Self.cell - 2 * inset, height: Self.cell - 2 * inset)
                context.fill(Path(roundedRect: square, cornerRadius: 1.4 * CGFloat(1 - merge)),
                             with: .color(Self.gray(tone).opacity(0.35 + 0.65 * progress)))
            }
        }
    }

    /// Um cinza do app: o mesmo tom levemente frio do trilho e dos textos.
    static func gray(_ tone: Double) -> Color {
        let t = min(max(tone, 0), 1)
        return Color(red: t * 0.97, green: t * 0.97, blue: t)
    }

    /// Um numero de 0 a 1 que so depende do lugar e do compasso.
    static func noise(_ column: Int, _ row: Int, _ step: Int) -> Double {
        var h = UInt64(bitPattern: Int64(column &* 73_856_093 ^ row &* 19_349_663 ^ step &* 83_492_791))
        h ^= h >> 33
        h &*= 0xFF51_AFD7_ED55_8CCD
        h ^= h >> 33
        h &*= 0xC4CE_B9FE_1A85_EC53
        h ^= h >> 33
        return Double(h >> 11) / Double(1 << 53)
    }

    private static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func easeOut(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return 1 - (1 - t) * (1 - t) * (1 - t)
    }
}

/// O veu de pixels, no material do `PixelFill`: cinzas que cifram, cada pixel no seu compasso.
/// Cobrindo (o saldo ao ocultar), uma frente corre da esquerda para a direita, os pixels nascem
/// pequenos e claros e encaixam, o que estava embaixo some atras deles, e no fim os pixels se
/// apagam. Descobrindo (o saldo ao mostrar, um campo que aparece), o contrario na ordem: os
/// pixels acendem cobrindo o lugar e a frente corre de novo da esquerda para a direita, levando
/// os pixels e descobrindo o que esta embaixo.
struct PixelVeil: ViewModifier, @preconcurrency Animatable {
    /// 0, o numero limpo; 1, o numero escondido e os pixels apagados.
    var progress: Double
    /// Mostrando: a frente descobre em vez de cobrir.
    let reveal: Bool
    /// A faixa da altura que os pixels cobrem: no saldo, so a dos algarismos.
    var band: ClosedRange<CGFloat> = 0.2...0.9
    /// O recorte dos pixels, para cobrir um campo com o raio dele.
    var cornerRadius: CGFloat = 0

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    static let duration = 0.7
    /// A parte do tempo em que a frente corre (cobrindo); o resto apaga os pixels.
    static let coverShare = 0.66
    static let pitch: CGFloat = 7
    static let cell: CGFloat = 5.5
    static let front: CGFloat = 40

    func body(content: Content) -> some View {
        // O tempo da troca, sempre para a frente, de 0 a 1.
        let time = reveal ? 1 - progress : progress
        content
            .mask {
                GeometryReader { geometry in
                    let w = geometry.size.width
                    let f = frontier(time, width: w)
                    // O numero fica onde a frente ainda nao passou (ocultando) ou ja passou (mostrando).
                    let start = reveal ? 0 : min(max(f - Self.front * 0.5, 0), w)
                    let end = reveal ? min(max(f - Self.front * 0.5, 0), w) : w
                    Rectangle().frame(width: max(end - start, 0)).offset(x: start)
                }
            }
            .overlay {
                Canvas { context, size in draw(&context, size: size, time: time) }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
    }

    /// Onde a frente esta: antes do numero no comeco, depois dele no fim.
    private func frontier(_ time: Double, width: CGFloat) -> CGFloat {
        let run = reveal ? Self.smooth((time - (1 - Self.coverShare)) / Self.coverShare) : Self.smooth(time / Self.coverShare)
        return -Self.front + CGFloat(run) * (width + 2 * Self.front)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        let f = frontier(time, width: size.width)
        // Ocultando, os pixels se apagam depois da frente; mostrando, acendem antes dela.
        let presence = reveal ? Self.smooth(time / (1 - Self.coverShare)) : 1 - Self.smooth((time - Self.coverShare) / (1 - Self.coverShare))
        guard presence > 0.01 else { return }
        let top = size.height * band.lowerBound, bottom = size.height * band.upperBound
        let rows = max(Int(((bottom - top) / Self.pitch).rounded()), 1)
        let y0 = top + ((bottom - top) - CGFloat(rows) * Self.pitch) / 2
        let columns = Int((size.width / Self.pitch).rounded(.up))
        let beat = time * 16
        let step = beat.rounded(.down)
        let blend = Self.smooth(beat - step)
        for column in 0..<columns {
            let x = CGFloat(column) * Self.pitch + Self.pitch / 2
            // Quanto deste pixel ja esta no lugar: 1 atras da frente ao cobrir, 1 adiante dela ao descobrir.
            let placed = reveal ? Self.smooth(Double((x - (f - Self.front)) / Self.front)) : Self.smooth(Double((f - x) / Self.front))
            guard placed > 0.02 else { continue }
            for row in 0..<rows {
                let a = PixelFill.noise(column, row, Int(step)), b = PixelFill.noise(column, row, Int(step) + 1)
                let bit = a + (b - a) * blend
                // Na frente, mais claro: os pixels acendem antes de encaixar.
                let heat = 4 * placed * (1 - placed)
                let tone = 0.2 + 0.36 * bit + 0.34 * heat * bit
                let side = Self.cell * CGFloat(0.4 + 0.6 * placed) * CGFloat(0.6 + 0.4 * presence)
                let rect = CGRect(x: x - side / 2, y: y0 + CGFloat(row) * Self.pitch + (Self.pitch - side) / 2, width: side, height: side)
                context.fill(Path(roundedRect: rect, cornerRadius: side * 0.24),
                             with: .color(PixelFill.gray(tone).opacity(placed * presence)))
            }
        }
    }

    private static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Um campo que nasce dos pixels (pedido do dono, 24/10/2026: "como se ele tivesse nascendo dos
/// pixels", "mais blend in", das pontas para o meio, e os pixels sumindo no fim em vez de um
/// esmaecer). Das duas pontas para o meio, cada pixel surge no tom do fundo da tela, pequeno, e
/// clareia ate um cinza que cifra de leve; as juntas fecham no tom do campo e o campo de verdade
/// fica pronto por baixo; entao cada pixel some no seu instante, encolhendo, e o campo aparece
/// pelos buracos que eles deixam.
struct PixelBirth: ViewModifier, @preconcurrency Animatable {
    /// 0, o campo inteiro; 1, nada ainda.
    var progress: Double
    var cornerRadius: CGFloat = Radius.card

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    static let duration = 1.0
    static let cell: CGFloat = 4.6
    static let pitch: CGFloat = 6
    /// Em fracao do tempo: ate onde os pixels nascem, quando as juntas fecham e o campo fica por
    /// baixo, e quanto leva cada pixel para sumir.
    static let bornUntil = 0.4, closedAt = 0.52, vanish = 0.12

    func body(content: Content) -> some View {
        // O tempo da entrada, de 0 a 1.
        let time = 1 - progress
        content
            .opacity(time >= Self.closedAt ? 1 : 0)
            .overlay {
                Canvas { context, size in draw(&context, size: size, time: time) }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
            }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        guard time < 1 else { return }
        let merge = Self.smooth((time - Self.bornUntil) / (Self.closedAt - Self.bornUntil))
        let columns = Int((size.width / Self.pitch).rounded(.up))
        let rows = Int((size.height / Self.pitch).rounded(.up))
        let x0 = (size.width - CGFloat(columns) * Self.pitch) / 2, y0 = (size.height - CGFloat(rows) * Self.pitch) / 2
        // O fundo da tela, de onde os pixels saem, e o do campo, onde eles assentam.
        let ground = 0.045, floor = 0.083
        let beat = time * 18
        let step = beat.rounded(.down)
        let blend = Self.smooth(beat - step)
        for column in 0..<columns {
            let along = Double(column) / Double(max(columns - 1, 1))
            for row in 0..<rows {
                // Nasce das duas pontas para o meio; some cada um no seu instante, sem ordem.
                let bornAt = 0.26 * (1 - abs(along - 0.5) * 2) + 0.1 * PixelFill.noise(column, row, 0xB1E)
                let goneAt = Self.closedAt + (1 - Self.closedAt - Self.vanish) * PixelFill.noise(column, row, 0x50D)
                let grow = Self.smooth((time - bornAt) / 0.14)
                let gone = Self.smooth((time - goneAt) / Self.vanish)
                guard grow > 0.01, gone < 0.99 else { continue }
                let a = PixelFill.noise(column, row, Int(step)), b = PixelFill.noise(column, row, Int(step) + 1)
                let bit = a + (b - a) * blend
                // Sai do tom do fundo e clareia ate cifrar de leve; fechado, o tom do campo.
                var tone = ground + (0.075 + 0.11 * bit - ground) * grow
                tone += (floor - tone) * merge
                // Nasce pequeno e encaixa; fecha as juntas; e encolhe ate sumir.
                let full = Self.cell * CGFloat(0.35 + 0.65 * grow) + (Self.pitch - Self.cell + 0.6) * CGFloat(merge)
                let side = full * CGFloat(1 - gone)
                let cx = x0 + (CGFloat(column) + 0.5) * Self.pitch, cy = y0 + (CGFloat(row) + 0.5) * Self.pitch
                let rect = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
                let round = side * 0.24 * CGFloat(max(1 - merge, gone))
                context.fill(Path(roundedRect: rect, cornerRadius: round), with: .color(PixelFill.gray(tone)))
            }
        }
    }

    private static func smooth(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
}

/// Desliga o "voltar arrastando pelo meio da tela" do iOS 26 enquanto a tela esta na
/// frente: arrastar o cadeado do `SlideToConfirm` para a direita voltava a tela anterior.
/// O botao voltar e o gesto pela borda continuam.
struct ContentSwipeBackDisabled: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setContentPop(false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setContentPop(true)
        }

        private func setContentPop(_ enabled: Bool) {
            if #available(iOS 26, *) { navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = enabled }
        }
    }
}
