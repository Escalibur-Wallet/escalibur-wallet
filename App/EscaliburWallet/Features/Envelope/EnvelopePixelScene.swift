import SwiftUI

/// "A senha da carteira entra no envelope", em pixels (pedido do dono, 16/10/2026, no lugar
/// da corrente de blocos): tres palavras ja cifradas se desfazem em pixels cinza que
/// cifram, como os do `SlideToConfirm`, e caem pela boca do envelope. O envelope inteiro e de
/// pixels que cifram ao vivo, para nao parecer papel que qualquer um abre (pedido do dono,
/// 16/10/2026): a aba fecha descendo linha por linha, sem fresta nas bordas, um cadeado de
/// pixels se monta no meio, e um anel de pixels acende em verde em volta dele, em ordem,
/// como o da checagem do aparelho. Em laco.
/// Nenhuma palavra de verdade: os glifos sao os do `EnvelopeCipherCard`. Com Reduzir
/// Movimento, o envelope trancado, parado.
struct EnvelopePixelScene: View {
    var height: CGFloat = 236
    /// Lacrando um envelope de verdade (`SealEnvelopeFlow`): sem laco, a historia anda com o
    /// lacre. Enquanto o app faz a conta da senha, as palavras viram pixels e caem no
    /// envelope; gravando, a aba fecha; lacrado, o cadeado se monta e o anel acende, e a cena
    /// para assim. Nil: o laco das telas de explicar. Em todas, o envelope e o de pixels: o
    /// de papel, que virava pixel ao fechar, foi aposentado (pedido do dono, 16/10/2026).
    var stage: Stage? = nil

    enum Stage: Equatable { case working, writing, sealed }

    /// Onde a historia estava quando a etapa mudou, e quando: a cena segue dali.
    @State private var anchor: (t: Double, at: Date) = (0, Date())
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// O desenho num quadro fixo, escalado para caber.
    private enum G {
        static let width: CGFloat = 300
        static let height: CGFloat = 236
        static let envelope = CGRect(x: 60, y: 120, width: 180, height: 104)
        static let flapHeight: CGFloat = 104 * 0.58
        static let mouth = CGPoint(x: 150, y: 166)
        static let seal = CGPoint(x: 150, y: 178)
        static let chipSize = CGSize(width: 82, height: 30)
        static let chips: [CGFloat] = [21, 109, 197]
        static let chipY: CGFloat = 16
        static let cell: CGFloat = 5
        static let pitch: CGFloat = 6.6
        static let ring = 28
        /// A grade do envelope: um pixel a cada 6 pontos.
        static let grid: CGFloat = 6
        static let gridCell: CGFloat = 4.6
        static var columns: Int { Int(envelope.width / grid) }
        static var rows: Int { Int(envelope.height / grid) }
        /// Quantas linhas a aba tem, da borda de cima ate a ponta.
        static var flapRows: Int { Int((flapHeight / grid).rounded()) }
        /// O cadeado em pixels: arco em cima, corpo embaixo, o buraco da chave no meio.
        static let lock = ["..#####..", ".##...##.", ".#.....#.", ".#.....#.", "#########",
                           "#########", "####.####", "####.####", "#########", "#########"]
    }

    /// A historia, em segundos dentro do laco.
    private enum T {
        static let period = 6.6
        static let breakFrom = 0.7
        static let breakStep = 0.32
        static let flight = 0.75
        static let flapFrom = 2.45
        static let flapTime = 0.45
        static let sealFrom = 2.95
        static let ringFrom = 3.15
        static let ringTime = 0.45
        static let fadeFrom = 6.0
    }

    /// O alto vazio da cena depois que as palavras caem (acima da aba aberta): quem centraliza
    /// a cena no lacre desconta a metade dele.
    static let emptyTop: CGFloat = 116

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let clock = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let scale = min(size.width / G.width, size.height / G.height)
                context.translateBy(x: (size.width - G.width * scale) / 2, y: (size.height - G.height * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                let t = reduceMotion ? T.fadeFrom - 0.3 : storyTime(at: timeline.date)
                draw(&context, t: t, clock: clock)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .onAppear {
            start = Date()
            anchor = (0, Date())
        }
        // A historia retoma de onde parou na etapa de antes: medido com o teto novo, o tempo
        // que correu esperando a conta da senha pulava o voo das palavras ate o envelope
        // (visto pelo dono, 16/10/2026).
        .onChange(of: stage) { old, _ in
            let now = Date()
            anchor = (storyTime(at: now, stage: old), now)
        }
        .accessibilityHidden(true)
    }

    /// O tempo da historia: em laco nas telas de explicar; no lacre, andando de onde parou
    /// ate o teto da etapa (no lacrado, o fim, sem esmaecer).
    private func storyTime(at now: Date) -> Double { storyTime(at: now, stage: stage) }

    private func storyTime(at now: Date, stage: Stage?) -> Double {
        guard let stage else { return now.timeIntervalSince(start).truncatingRemainder(dividingBy: T.period) }
        // As palavras voam para o envelope enquanto o app faz a conta da senha (o tempo do
        // lacre); gravando, a aba fecha; lacrado, o cadeado e o anel, um pouco mais rapido se
        // a historia ficou para tras. Antes as palavras so voavam depois da conta, e o voo
        // terminava segundos depois do "Envelope lacrado" (visto pelo dono, 16/10/2026).
        let cap: Double, rate: Double
        switch stage {
        case .working: cap = T.flapFrom - 0.05; rate = 1
        case .writing: cap = T.sealFrom - 0.05; rate = 1.4
        case .sealed: cap = T.fadeFrom - 0.05; rate = anchor.t < T.ringFrom ? 1.8 : 1
        }
        return min(cap, anchor.t + now.timeIntervalSince(anchor.at) * rate)
    }

    private func draw(_ context: inout GraphicsContext, t: Double, clock: Double) {
        // Tudo some junto no fim do laco e nasce de novo no comeco.
        context.opacity = min(Self.smooth(t / 0.35), 1 - Self.smooth((t - T.fadeFrom) / (T.period - T.fadeFrom)))
        // O envelope fica no lugar ao fechar: subir ate o centro da cena saiu (pedido do dono,
        // 17/10/2026); quem centraliza e a tela do lacre.
        let closing = reduceMotion ? 1 : Self.easeInOut((t - T.flapFrom) / T.flapTime)
        // Lacrado, sem a passada de luz: o envelope fica so cifrando (pedido do dono, 17/10/2026).
        drawEnvelope(&context, closing: closing, clock: clock, sweeping: stage != .sealed)
        drawPixels(&context, t: t, clock: clock)
        drawChips(&context, t: t, clock: clock)
        drawLock(&context, t: t)
        drawRing(&context, t: t)
    }

    /// Um pixel da grade do envelope, na coluna e na linha dadas (linha negativa: acima da
    /// borda de cima, onde fica a aba aberta).
    private func cell(_ column: Int, _ row: Int) -> CGRect {
        let inset = (G.grid - G.gridCell) / 2
        return CGRect(x: G.envelope.minX + CGFloat(column) * G.grid + inset, y: G.envelope.minY + CGFloat(row) * G.grid + inset,
                      width: G.gridCell, height: G.gridCell)
    }

    /// Distancia, em pontos, do centro de um pixel ate a reta de a ate b.
    private static func distance(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let u = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
        return hypot(point.x - (a.x + u * dx), point.y - (a.y + u * dy))
    }

    /// O envelope de pixels, cifrando ao vivo: o corpo, a borda e as dobras mais claras, e
    /// uma passada de luz que corre devagar. A aba dobra na borda de cima como papel: aberta
    /// para cima, achata na dobra e desce sobre o envelope (`closing`, de 0 a 1). Antes a aba
    /// aberta sumia linha por linha e a fechada nascia no lugar (visto pelo dono, 16/10/2026).
    private func drawEnvelope(_ context: inout GraphicsContext, closing: Double, clock: Double, sweeping: Bool) {
        let columns = G.columns, rows = G.rows, flapRows = G.flapRows
        let fold = CGPoint(x: G.envelope.midX, y: G.envelope.minY + G.envelope.height * 0.5)
        let sweep = CGFloat((clock / 2.2).truncatingRemainder(dividingBy: 1)) * (G.envelope.width + 80) + G.envelope.minX - 40
        func light(_ center: CGPoint) -> Double {
            guard sweeping else { return 0 }
            let d = Double((center.x - sweep + (center.y - G.envelope.minY) * 0.5) / 18)
            return 0.08 * exp(-d * d)
        }
        for column in 0..<columns {
            for row in 0..<rows {
                let rect = cell(column, row)
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let id = 5000 + column * rows + row
                let edge = column == 0 || column == columns - 1 || row == 0 || row == rows - 1
                let pocketFold = Self.distance(center, CGPoint(x: G.envelope.minX, y: G.envelope.minY), fold) < G.grid * 0.6
                    || Self.distance(center, CGPoint(x: G.envelope.maxX, y: G.envelope.minY), fold) < G.grid * 0.6
                let bit = Self.tone(id, clock: clock)
                // Cinza escuro, quase preto; a borda e as dobras um pouco mais claras, para o
                // desenho do envelope continuar lendo (pedido do dono, 18/10/2026).
                var tone = 0.06 + 0.07 * bit
                if edge { tone = 0.22 + 0.1 * bit } else if pocketFold { tone = 0.15 + 0.06 * bit }
                tone += light(center)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.1), with: .color(PixelFill.gray(tone)))
            }
        }
        // A aba: cada pixel na sua distancia da dobra, multiplicada pela abertura (-1 aberta
        // para cima, 0 achatada na dobra, 1 fechada), e achatado junto, como papel virando.
        let turn = CGFloat(-1 + 2 * closing)
        let squash = max(abs(turn), 0.08)
        for row in 0..<flapRows {
            let half = (1 - (CGFloat(row) + 0.5) / CGFloat(flapRows)) * G.envelope.width / 2 + G.grid * 0.5
            for column in 0..<columns {
                let home = cell(column, row)
                let offCenter = abs(home.midX - G.envelope.midX)
                guard offCenter <= half else { continue }
                let rect = CGRect(x: home.minX, y: G.envelope.minY + (home.midY - G.envelope.minY) * turn - home.height * squash / 2,
                                  width: home.width, height: home.height * squash)
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let rim = offCenter > half - G.grid * 1.2
                let bit = Self.tone(7000 + column * 40 + row, clock: clock)
                let tone = (rim ? 0.22 + 0.1 * bit : 0.09 + 0.07 * bit) + light(center)
                context.fill(Path(roundedRect: rect, cornerRadius: min(1.1, rect.height / 2)), with: .color(PixelFill.gray(tone)))
            }
        }
    }

    /// As tres palavras cifradas no alto, que somem quando viram pixels.
    private func drawChips(_ context: inout GraphicsContext, t: Double, clock: Double) {
        let tick = UInt64(max(clock * 12, 0))
        for (index, x) in G.chips.enumerated() {
            let breakAt = T.breakFrom + Double(index) * T.breakStep
            let alpha = 1 - Self.smooth((t - breakAt) / 0.22)
            guard alpha > 0.01 else { continue }
            var chip = context
            chip.opacity *= alpha
            let rect = CGRect(origin: CGPoint(x: x, y: G.chipY), size: G.chipSize)
            let shape = Path(roundedRect: rect, cornerRadius: 9, style: .continuous)
            chip.fill(shape, with: .color(Palette.void))
            chip.stroke(shape, with: .color(Palette.edgeStrong), lineWidth: 1)
            chip.draw(Text(verbatim: "\(index + 1)").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundColor(Palette.inkMuted),
                      at: CGPoint(x: rect.minX + 12, y: rect.midY), anchor: .center)
            chip.draw(Text(verbatim: EnvelopeCipherCard.glyphs(index, tick: tick)).font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Palette.inkSoft),
                      at: CGPoint(x: rect.minX + 24, y: rect.midY), anchor: .leading)
        }
    }

    /// Cada palavra vira uma grade de pixels que cifram e voam ate a boca do envelope.
    private func drawPixels(_ context: inout GraphicsContext, t: Double, clock: Double) {
        let columns = Int(G.chipSize.width / G.pitch), rows = Int(G.chipSize.height / G.pitch)
        for (index, x) in G.chips.enumerated() {
            let breakAt = T.breakFrom + Double(index) * T.breakStep
            guard t > breakAt - 0.05 else { continue }
            for column in 0..<columns {
                for row in 0..<rows {
                    let id = index * 100 + column * rows + row
                    let delay = PixelFill.noise(id, 7, 0x3C1) * 0.35
                    let p = Self.smooth((t - breakAt - delay) / T.flight)
                    guard p < 0.999 else { continue }
                    let from = CGPoint(x: x + 4 + CGFloat(column) * G.pitch, y: G.chipY + 2 + CGFloat(row) * G.pitch)
                    let spread = CGFloat(PixelFill.noise(id, 11, 0x5A) - 0.5) * 36
                    let to = CGPoint(x: G.mouth.x + spread, y: G.mouth.y)
                    // Uma curva: sobe um pouco, depois cai para dentro.
                    let control = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - 10)
                    let u = CGFloat(p)
                    let point = CGPoint(x: (1 - u) * (1 - u) * from.x + 2 * (1 - u) * u * control.x + u * u * to.x,
                                        y: (1 - u) * (1 - u) * from.y + 2 * (1 - u) * u * control.y + u * u * to.y)
                    let side = G.cell * (1 - 0.35 * u)
                    let tone = 0.22 + 0.32 * Self.tone(id, clock: clock) + 0.2 * Double(1 - u)
                    context.fill(Path(roundedRect: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side), cornerRadius: 1.2),
                                 with: .color(PixelFill.gray(tone).opacity(p < 0.02 ? 0 : 1)))
                }
            }
        }
    }

    /// O cadeado de pixels, que se monta no meio depois que a aba fecha, sobre um disco preto
    /// (pedido do dono, 17/10/2026).
    private func drawLock(_ context: inout GraphicsContext, t: Double) {
        let p = Self.easeOut((t - T.sealFrom) / 0.25)
        guard p > 0 else { return }
        var lock = context
        lock.opacity *= p
        let radius: CGFloat = 23
        lock.fill(Path(ellipseIn: CGRect(x: G.seal.x - radius, y: G.seal.y - radius, width: radius * 2, height: radius * 2)),
                  with: .color(.black))
        let pitch: CGFloat = 3.6, side: CGFloat = 3.0
        let rows = G.lock.count, columns = G.lock[0].count
        let origin = CGPoint(x: G.seal.x - CGFloat(columns) * pitch / 2, y: G.seal.y - CGFloat(rows) * pitch / 2)
        for (row, line) in G.lock.enumerated() {
            for (column, mark) in line.enumerated() where mark == "#" {
                // Cada pixel chega no seu instante: o cadeado se monta, nao aparece pronto.
                let arrive = T.sealFrom + PixelFill.noise(column, row, 0x10C) * 0.3
                guard t >= arrive || reduceMotion else { continue }
                let rect = CGRect(x: origin.x + CGFloat(column) * pitch, y: origin.y + CGFloat(row) * pitch, width: side, height: side)
                lock.fill(Path(roundedRect: rect, cornerRadius: 0.6), with: .color(Palette.ink))
            }
        }
    }

    /// O anel de pixels em volta do cadeado, acendendo em verde em ordem: trancado e conferido.
    private func drawRing(_ context: inout GraphicsContext, t: Double) {
        guard t > T.sealFrom else { return }
        for index in 0..<G.ring {
            let angle = Double(index) / Double(G.ring) * 2 * .pi - .pi / 2
            let point = CGPoint(x: G.seal.x + 34 * CGFloat(cos(angle)), y: G.seal.y + 34 * CGFloat(sin(angle)))
            let litAt = T.ringFrom + Double(index) / Double(G.ring) * T.ringTime
            let lit = t >= litAt
            let flash = lit ? exp(-max(t - litAt, 0) * 6) : 0
            let side: CGFloat = 4.6 + 1.6 * CGFloat(flash)
            let square = Path(roundedRect: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side), cornerRadius: 1.2)
            context.fill(square, with: .color(lit ? Palette.success : PixelFill.gray(0.2)))
            if flash > 0.02 { context.fill(square, with: .color(.white.opacity(0.5 * flash))) }
        }
    }

    /// O tom cifrado de um pixel agora, de 0 a 1, trocando no compasso dele.
    private static func tone(_ id: Int, clock: Double) -> Double {
        let phase = PixelFill.noise(id, 3, 0x77)
        let beat = clock * 7 * (0.6 + 0.8 * phase) + phase * 8
        let step = beat.rounded(.down)
        let blend = smooth(beat - step)
        let a = PixelFill.noise(id, 3, Int(step)), b = PixelFill.noise(id, 3, Int(step) + 1)
        return a + (b - a) * blend
    }

    private static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func easeOut(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return 1 - (1 - t) * (1 - t) * (1 - t)
    }

    private static func easeInOut(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}

/// Abrir um envelope, redesenhado do zero (pedido do dono, 24/10/2026), na gramatica da
/// animacao do Tor: um objeto que muda de estado, sem efeito solto. O envelope e um bloco de
/// pixels que cifram, com o cadeado no meio. A senha entra ponto a ponto embaixo; com o ultimo
/// ponto o cadeado abre e se desfaz, e uma frente desce pelo bloco decifrando: os pixels
/// assentam nas 12 palavras da carteira, cada uma com o seu numero. Fica um tempo e recomeca.
/// Nenhuma palavra de verdade: as palavras sao barras. Com Reduzir Movimento, as palavras ja
/// abertas, paradas.
struct EnvelopeOpenScene: View {
    var height: CGFloat = 236
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let t = reduceMotion ? 5.0 : elapsed.truncatingRemainder(dividingBy: OpenScene.period)
            let clock = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let scale = min(size.width / OpenScene.width, size.height / OpenScene.height)
                context.translateBy(x: (size.width - OpenScene.width * scale) / 2, y: (size.height - OpenScene.height * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                OpenScene(context: context, t: t, clock: clock).draw()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }
}

/// Um quadro da abertura, num quadro fixo de 300 por 236 pontos.
private struct OpenScene {
    let context: GraphicsContext
    let t: Double
    let clock: Double

    static let width: CGFloat = 300, height: CGFloat = 236
    static let period = 6.6
    /// O bloco: 38 por 22 pixels, um a cada 6 pontos.
    static let columns = 38, rows = 22
    static let pitch: CGFloat = 6, cell: CGFloat = 4.6
    static let origin = CGPoint(x: (300 - 38 * 6) / 2, y: 14)
    /// A senha: seis pontos embaixo do bloco.
    static let dotsY: CGFloat = 14 + 22 * 6 + 34
    static let dotsFrom = 0.7, dotStep = 0.18
    /// O cadeado abre, se desfaz, e a frente desce.
    static let unlock = 1.95, dissolve = 2.35, decrypt = 2.6, decryptTime = 1.3
    static let fadeOut = 5.9
    /// O cadeado: arco em cima, corpo embaixo, a fechadura no meio (o mesmo do site).
    static let lock = ["..#####..", ".##...##.", ".#.....#.", ".#.....#.", "#########",
                       "#########", "####.####", "####.####", "#########", "#########"]
    static let lockColumn = 15, lockRow = 6

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func smooth(_ x: Double) -> Double { let c = clamp(x); return c * c * (3 - 2 * c) }
    static func easeOut(_ x: Double) -> Double { let c = 1 - clamp(x); return 1 - c * c * c }

    /// O tom cifrado de um pixel agora, de 0 a 1, cruzando de um sorteio para o outro.
    func bit(_ a: Int, _ b: Int, rate: Double = 3) -> Double {
        let phase = PixelFill.noise(a, b, 0x0E5C)
        let beat = clock * rate * (0.6 + 0.8 * phase) + phase * 8
        let step = beat.rounded(.down)
        let x = PixelFill.noise(a, b, Int(step)), y = PixelFill.noise(a, b, Int(step) + 1)
        return x + (y - x) * Self.smooth(beat - step)
    }

    func square(_ center: CGPoint, side: CGFloat, tone: Double, alpha: Double) {
        guard alpha > 0.01, side > 0.2 else { return }
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        context.fill(Path(roundedRect: rect, cornerRadius: side * 0.24), with: .color(PixelFill.gray(min(max(tone, 0), 1)).opacity(alpha)))
    }

    func point(_ column: Int, _ row: Int) -> CGPoint {
        CGPoint(x: Self.origin.x + (CGFloat(column) + 0.5) * Self.pitch, y: Self.origin.y + (CGFloat(row) + 0.5) * Self.pitch)
    }

    /// O que cada pixel vira depois de aberto: 1 nas palavras, 0,45 no numero delas, 0 no resto.
    /// Tres colunas de quatro palavras, como linhas de texto: cada uma e o numero, um respiro e
    /// a palavra, com dois pixels de altura.
    static func target(_ column: Int, _ row: Int) -> Double {
        let c = column - 2, r = row - 4
        guard c >= 0, r >= 0, c % 12 < 10, r % 4 < 2, c / 12 < 3, r / 4 < 4 else { return 0 }
        let word = (r / 4) * 3 + c / 12
        let x = c % 12
        if x == 0 { return 0.45 }
        if x == 1 { return 0 }
        let length = 4 + Int(PixelFill.noise(word, 3, 0x51D) * 5)
        return x - 2 < length ? 1 : 0
    }

    func draw() {
        let alpha = Self.smooth(t / 0.4) * (1 - Self.smooth((t - Self.fadeOut) / 0.6))
        guard alpha > 0.01 else { return }
        // A frente que decifra, em linhas do bloco: acima dela, ja aberto.
        let front = Self.smooth((t - Self.decrypt) / Self.decryptTime) * Double(Self.rows + 4) - 2
        // O cadeado: o arco sobe ao abrir, e os pixels encolhem e somem.
        let lift = Self.easeOut((t - Self.unlock) / 0.3) * Double(Self.pitch) * 1.2
        let lockGone = Self.clamp((t - Self.dissolve) / 0.4)
        // Em volta do cadeado, o bloco escurece para ele aparecer; volta quando ele some.
        let halo = 1 - Self.smooth((t - Self.dissolve - 0.1) / 0.4)

        for column in 0..<Self.columns {
            for row in 0..<Self.rows {
                let edge = row == 0 || column == 0 || row == Self.rows - 1 || column == Self.columns - 1
                let cipher = (edge ? 0.26 : 0.13) + 0.22 * bit(column, row)
                let goal = edge ? 0.2 : (Self.target(column, row) > 0 ? 0.12 + 0.8 * Self.target(column, row) : 0.075)
                let settle = Self.smooth((front - Double(row)) / 2.2)
                let heat = 4 * settle * (1 - settle)
                var tone = cipher + (goal - cipher) * settle + 0.3 * heat * bit(column, row, rate: 7)
                let lx = column - Self.lockColumn, ly = row - Self.lockRow
                if (-1...9).contains(lx), (-1...10).contains(ly) { tone = tone + (0.05 - tone) * 0.85 * halo }
                square(point(column, row), side: Self.cell, tone: tone, alpha: alpha)
            }
        }

        for (y, line) in Self.lock.enumerated() {
            for (x, mark) in line.enumerated() where mark == "#" {
                let n = PixelFill.noise(x, y, 0x10C)
                let gone = Self.clamp((lockGone - 0.5 * n) / 0.5)
                guard gone < 1 else { continue }
                var p = point(Self.lockColumn + x, Self.lockRow + y)
                if y < 4 { p.y -= lift }
                p.y -= CGFloat(gone) * 8
                square(p, side: Self.cell * CGFloat(1 - 0.7 * gone), tone: 0.95, alpha: alpha * (1 - gone))
            }
        }

        // A senha: cada ponto acende quando a tecla entra, com um tranco pequeno.
        for k in 0..<6 {
            let typed = Self.clamp((t - Self.dotsFrom - Double(k) * Self.dotStep) / 0.15)
            let pop = 1 + 0.35 * sin(typed * .pi)
            let center = CGPoint(x: Self.width / 2 + (CGFloat(k) - 2.5) * 18, y: Self.dotsY)
            square(center, side: 9 * CGFloat(pop), tone: 0.22 + 0.73 * typed, alpha: alpha)
        }
    }
}
