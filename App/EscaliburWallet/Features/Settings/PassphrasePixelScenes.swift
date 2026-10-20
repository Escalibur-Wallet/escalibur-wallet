import EscaliburChains
import SwiftUI

/// As cenas da carteira com passphrase, todas em pixels que cifram, como o envelope (pedido do
/// dono, 17/10/2026: as de antes, com cartoes e selos, tinham cara de IA). Uma metafora so: uma
/// parede de pixels com duas portas. As palavras abrem a porta de sempre; a porta da passphrase
/// fica escondida na parede e so aparece quando a chave encosta. Nada aqui e de verdade: palavras,
/// chave e codigos sao desenho.
enum PassphraseScene: Equatable {
    /// A tela da carteira com passphrase e o passo 1: palavras e chave abrem a porta escondida.
    case hiddenDoor
    /// Passo 2: so as palavras abrem a porta de sempre; a luz varre a parede e nao acha a outra.
    case wordsOnly
    /// Passo 3: cada carteira com o proprio codigo de deposito, e embaixo a moeda e o endereco
    /// de cada uma (pedido do dono, 17/10/2026, como a cena antiga das linhas de endereco).
    case ownCodes
    /// Passo 4: a chave esquecida vira ruido, e a porta volta a sumir na parede.
    case forgotten
}

struct PassphrasePixelScene: View {
    let scene: PassphraseScene
    var height: CGFloat = 236
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// O desenho num quadro fixo, escalado para caber.
    fileprivate enum G {
        static let width: CGFloat = 300
        static let height: CGFloat = 236
        static let pitch: CGFloat = 6
        static let cell: CGFloat = 4.6
        /// A parede: 40 por 22 pixels.
        static let wallOrigin = CGPoint(x: 30, y: 92)
        static let wallColumns = 40
        static let wallRows = 22
        /// As portas, em colunas e linhas da parede (a de baixo encosta no chao).
        static let usualDoor = (column: 6, row: 6, width: 8, height: 16)
        static let hiddenDoor = (column: 26, row: 6, width: 8, height: 16)
        /// As palavras: 2 fileiras de 6 pastilhas de 5 por 2 pixels, no alto, no meio da cena
        /// (de 48 a 252, como a parede; pedido do dono, 17/10/2026).
        static let tilesOrigin = CGPoint(x: 48, y: 22)
        static let period = 6.4
        /// Os dois codigos de deposito, centrados na cena.
        static let usualCode = CGPoint(x: 33, y: 30)
        static let vaultCode = CGPoint(x: 159, y: 30)
        static let codeSize: CGFloat = 108
    }

    /// Enderecos de exemplo, so desenho: a mesma rede nas duas carteiras, um endereco em cada.
    static let samples: [(chain: Chain, usual: String, vault: String)] = [
        (.bitcoin, "bc1q8f4…3k2v", "bc1qz7m…9wd0"),
        (.ethereum, "0x4B1c…7e09", "0xA93f…12cD"),
        (.solana, "7xKp…Qm4T", "GhR2…d8Lw"),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? restingTime : timeline.date.timeIntervalSince(start).truncatingRemainder(dividingBy: G.period)
            let clock = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            // A cada volta, outra rede nos dois codigos.
            let loop = reduceMotion ? 1 : Int(timeline.date.timeIntervalSince(start) / G.period) % Self.samples.count
            Canvas { context, size in
                let scale = min(size.width / G.width, size.height / G.height)
                context.translateBy(x: (size.width - G.width * scale) / 2, y: (size.height - G.height * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                var painter = Painter(context: context, clock: clock)
                painter.context.opacity = min(Self.smooth(t / 0.35), 1 - Self.smooth((t - (G.period - 0.5)) / 0.5))
                switch scene {
                case .hiddenDoor: drawHiddenDoor(&painter, t: t)
                case .wordsOnly: drawWordsOnly(&painter, t: t)
                case .ownCodes: drawOwnCodes(&painter, t: t, loop: loop)
                case .forgotten: drawForgotten(&painter, t: t)
                }
            } symbols: {
                if scene == .ownCodes {
                    ForEach(Self.samples.indices, id: \.self) { index in
                        NetworkBadge(chain: Self.samples[index].chain, size: 18, ring: Palette.void).tag(index)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }

    /// Com Reduzir Movimento, o quadro que conta a historia, parado.
    private var restingTime: Double {
        switch scene {
        case .hiddenDoor: return 4.6
        case .wordsOnly: return 4.2
        case .ownCodes: return 3.6
        case .forgotten: return 4.4
        }
    }

    // MARK: Cenas

    private func drawHiddenDoor(_ p: inout Painter, t: Double) {
        let reveal = Self.smooth((t - 2.6) / 0.9)
        p.wall(hiddenReveal: reveal)
        p.tiles(fly: Self.smooth((t - 0.6) / 1.0), into: G.usualDoor)
        p.door(G.usualDoor, open: Self.smooth((t - 1.5) / 0.5), glow: 0)
        let keyIn = Self.smooth((t - 1.9) / 0.7)
        p.key(at: CGPoint(x: 300 - 60 * keyIn, y: 70), alpha: keyIn * (1 - Self.smooth((t - 3.5) / 0.4)))
        p.door(G.hiddenDoor, open: Self.smooth((t - 3.6) / 0.6), glow: reveal, hidden: true, reveal: reveal)
    }

    private func drawWordsOnly(_ p: inout Painter, t: Double) {
        p.wall(hiddenReveal: 0)
        p.tiles(fly: Self.smooth((t - 0.5) / 1.0), into: G.usualDoor)
        p.door(G.usualDoor, open: Self.smooth((t - 1.4) / 0.5), glow: 0)
        // A luz varre a parede da esquerda para a direita: a porta escondida nao acende.
        p.sweep(Self.smooth((t - 2.2) / 1.8))
        p.door(G.hiddenDoor, open: 0, glow: 0, hidden: true, reveal: 0)
    }

    private func drawOwnCodes(_ p: inout Painter, t: Double, loop: Int) {
        let sample = Self.samples[loop]
        p.code(origin: G.usualCode, seed: 11 + loop * 7, settle: Self.smooth((t - 0.3) / 1.0), dim: false)
        p.code(origin: G.vaultCode, seed: 29 + loop * 7, settle: Self.smooth((t - 0.9) / 1.0), dim: false)
        // Embaixo de cada codigo, a moeda e o endereco dele: o de sempre e o com passphrase.
        p.addressLabel(under: G.usualCode, badge: loop, title: String(localized: "De sempre"), address: sample.usual,
                       vault: false, appear: Self.smooth((t - 0.9) / 0.4))
        p.addressLabel(under: G.vaultCode, badge: loop, title: String(localized: "Com passphrase"), address: sample.vault,
                       vault: true, appear: Self.smooth((t - 1.5) / 0.4))
        // Uma moeda de pixels cai no codigo da direita: deposito no cofre.
        let drop = Self.smooth((t - 2.4) / 0.8)
        let middle = G.vaultCode.x + G.codeSize / 2
        p.coin(at: CGPoint(x: middle, y: 2 + 66 * drop), alpha: drop * (1 - Self.smooth((t - 3.3) / 0.4)))
        p.flash(CGRect(origin: G.vaultCode, size: CGSize(width: G.codeSize, height: G.codeSize)), Self.pulse(t - 3.25, width: 0.5))
    }

    private func drawForgotten(_ p: inout Painter, t: Double) {
        let fade = Self.smooth((t - 1.8) / 1.6)
        p.wall(hiddenReveal: 1 - fade)
        p.door(G.hiddenDoor, open: 0, glow: 1 - fade, hidden: true, reveal: 1 - fade)
        p.door(G.usualDoor, open: 0, glow: 0)
        // A chave se desfaz em ruido, de dentro para fora.
        p.key(at: CGPoint(x: 220, y: 70), alpha: 1, dissolve: Self.smooth((t - 1.0) / 1.6))
        p.tiles(fly: 0, into: G.usualDoor, alpha: 0.55)
    }

    // MARK: Apoio

    static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Um pulso de 0 a 1 e de volta, centrado em 0.
    static func pulse(_ x: Double, width: Double) -> Double {
        guard abs(x) < width else { return 0 }
        return 0.5 + 0.5 * cos(x / width * .pi)
    }
}

/// O pincel das cenas: pixels quadrados, cada um no seu tom de cinza que cifra.
private struct Painter {
    var context: GraphicsContext
    let clock: Double
    typealias G = PassphrasePixelScene.G

    func tone(_ id: Int, _ layer: Int) -> Double {
        let phase = PixelFill.noise(id, layer, 0x6A2)
        let beat = clock * 4 * (0.6 + 0.8 * phase) + phase * 8
        let step = beat.rounded(.down)
        let s = beat - step
        let blend = s * s * (3 - 2 * s)
        let a = PixelFill.noise(id, layer, Int(step)), b = PixelFill.noise(id, layer, Int(step) + 1)
        return a + (b - a) * blend
    }

    func dot(_ center: CGPoint, tone value: Double, alpha: Double = 1, side: CGFloat = G.cell, color: Color? = nil) {
        guard alpha > 0.01 else { return }
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        context.fill(Path(roundedRect: rect, cornerRadius: side * 0.24),
                     with: .color((color ?? PixelFill.gray(min(max(value, 0), 1))).opacity(alpha)))
    }

    func wallPoint(_ column: Int, _ row: Int) -> CGPoint {
        CGPoint(x: G.wallOrigin.x + CGFloat(column) * G.pitch + G.pitch / 2, y: G.wallOrigin.y + CGFloat(row) * G.pitch + G.pitch / 2)
    }

    /// A parede. A porta escondida tem o mesmo tom da parede; `hiddenReveal` acende o contorno.
    func wall(hiddenReveal: Double) {
        for column in 0..<G.wallColumns {
            for row in 0..<G.wallRows {
                let id = column * 64 + row
                let edge = row == 0 || column == 0 || column == G.wallColumns - 1
                let bit = tone(id, 1)
                dot(wallPoint(column, row), tone: edge ? 0.34 + 0.12 * bit : 0.12 + 0.12 * bit)
            }
        }
    }

    /// Uma porta: contorno mais claro e o miolo, que acende ao abrir. A escondida so mostra o
    /// contorno quando revelada, a partir da fechadura, contornando.
    func door(_ d: (column: Int, row: Int, width: Int, height: Int), open: Double, glow: Double, hidden: Bool = false, reveal: Double = 1) {
        var perimeter: [(Int, Int)] = []
        for c in d.column..<(d.column + d.width) { perimeter.append((c, d.row)) }
        for r in (d.row + 1)..<(d.row + d.height) { perimeter.append((d.column + d.width - 1, r)) }
        for r in (d.row + 1)..<(d.row + d.height) { perimeter.insert((d.column, r), at: 0) }
        for (index, cell) in perimeter.enumerated() {
            let order = Double(index) / Double(perimeter.count)
            let lit = hidden ? PassphrasePixelScene.smooth((reveal - order * 0.8) / 0.2) : 1
            let bit = tone(cell.0 * 97 + cell.1, 3)
            dot(wallPoint(cell.0, cell.1), tone: 0.12 + 0.12 * bit + lit * (0.42 + 0.12 * bit))
        }
        // O miolo: ao abrir, as duas metades se afastam do meio e a luz de dentro aparece.
        let middle = Double(d.column) + Double(d.width - 1) / 2
        for c in (d.column + 1)..<(d.column + d.width - 1) {
            for r in (d.row + 1)..<(d.row + d.height) {
                let fromMiddle = abs(Double(c) - middle) / (Double(d.width - 2) / 2)
                let gone = open > fromMiddle * 0.9 ? 1.0 : 0.0
                let bit = tone(c * 131 + r, 4)
                let panel = 0.2 + 0.14 * bit
                let light = 0.55 + 0.25 * bit
                dot(wallPoint(c, r), tone: panel * (1 - gone) + light * gone + 0.1 * glow)
            }
        }
        // A macaneta: um pixel claro do lado direito do painel, enquanto a porta esta fechada.
        if !hidden {
            dot(wallPoint(d.column + d.width - 2, d.row + d.height / 2 + 1), tone: 0.95, alpha: 1 - open)
        }
        if hidden {
            // A fechadura: dois pixels claros no meio da porta escondida, que acendem com o contorno.
            let keyhole = wallPoint(d.column + d.width / 2, d.row + d.height / 2)
            dot(keyhole, tone: 0.9, alpha: reveal * (1 - open))
            dot(CGPoint(x: keyhole.x, y: keyhole.y + G.pitch), tone: 0.9, alpha: reveal * (1 - open))
        }
    }

    /// As palavras: 12 pastilhas de pixels no alto. `fly` leva os pixels para a porta.
    func tiles(fly: Double, into d: (column: Int, row: Int, width: Int, height: Int), alpha: Double = 1) {
        let target = wallPoint(d.column + d.width / 2, d.row + d.height / 2)
        for tile in 0..<12 {
            let tileColumn = tile % 6, tileRow = tile / 6
            for px in 0..<5 {
                for py in 0..<2 {
                    let id = tile * 10 + px * 2 + py
                    let home = CGPoint(x: G.tilesOrigin.x + CGFloat(tileColumn * 6 + px) * G.pitch,
                                       y: G.tilesOrigin.y + CGFloat(tileRow * 3 + py) * G.pitch)
                    let delay = PixelFill.noise(id, 9, 0x1F) * 0.45
                    let f = PassphrasePixelScene.smooth((fly - delay) / (1 - delay + 0.0001))
                    let x = home.x + (target.x - home.x) * CGFloat(f)
                    let y = home.y + (target.y - home.y) * CGFloat(f) - CGFloat(sin(f * .pi)) * 18
                    dot(CGPoint(x: x, y: y), tone: 0.45 + 0.35 * tone(id, 5), alpha: alpha * (1 - PassphrasePixelScene.smooth((f - 0.85) / 0.15)))
                }
            }
        }
    }

    /// A chave da passphrase em pixels: argola, haste e dentes. `dissolve` espalha os pixels.
    func key(at origin: CGPoint, alpha: Double, dissolve: Double = 0) {
        let art = [".###.......", "#...#######", ".###...#.#."]
        for (row, line) in art.enumerated() {
            for (column, char) in line.enumerated() where char == "#" {
                let id = row * 20 + column
                let spread = CGFloat(dissolve) * 26
                let dx = (CGFloat(PixelFill.noise(id, 7, 1)) - 0.5) * spread * 2
                let dy = (CGFloat(PixelFill.noise(id, 7, 2)) - 0.5) * spread * 2 - CGFloat(dissolve) * 10
                let point = CGPoint(x: origin.x + CGFloat(column) * G.pitch + dx, y: origin.y + CGFloat(row) * G.pitch + dy)
                let noisy = dissolve > 0 ? 0.3 + 0.4 * tone(id, 8) : 0.92
                dot(point, tone: noisy, alpha: alpha * (1 - PassphrasePixelScene.smooth((dissolve - 0.5) / 0.5)))
            }
        }
    }

    /// Uma faixa de luz que varre a parede.
    func sweep(_ progress: Double) {
        guard progress > 0, progress < 1 else { return }
        let x = G.wallOrigin.x + CGFloat(progress) * CGFloat(G.wallColumns) * G.pitch
        for row in 0..<G.wallRows {
            for offset in -2...2 {
                let point = CGPoint(x: x + CGFloat(offset) * G.pitch, y: G.wallOrigin.y + CGFloat(row) * G.pitch + G.pitch / 2)
                dot(point, tone: 0.9, alpha: 0.28 * (1 - Double(abs(offset)) / 3))
            }
        }
    }

    /// Um codigo de deposito de pixels: 17 por 17, com os tres quadrados de canto; os pixels do
    /// meio trocam ate assentar no desenho do endereco.
    func code(origin: CGPoint, seed: Int, settle: Double, dim: Bool) {
        let size = 17
        let pitch: CGFloat = 108 / CGFloat(size)
        func finder(_ c: Int, _ r: Int) -> Bool? {
            for (fc, fr) in [(0, 0), (size - 7, 0), (0, size - 7)] where (fc..<(fc + 7)).contains(c) && (fr..<(fr + 7)).contains(r) {
                let x = c - fc, y = r - fr
                if x == 0 || x == 6 || y == 0 || y == 6 { return true }
                if (2...4).contains(x) && (2...4).contains(y) { return true }
                return false
            }
            return nil
        }
        for c in 0..<size {
            for r in 0..<size {
                let id = seed * 1000 + c * 31 + r
                let on: Bool
                if let fixed = finder(c, r) {
                    on = fixed
                } else {
                    let settled = PixelFill.noise(id, seed, 3) > 0.5
                    let flicker = tone(id, 6) > 0.5
                    on = PixelFill.noise(id, 2, 5) < settle ? settled : flicker
                }
                let point = CGPoint(x: origin.x + (CGFloat(c) + 0.5) * pitch, y: origin.y + (CGFloat(r) + 0.5) * pitch)
                dot(point, tone: on ? 0.86 : 0.14, alpha: dim ? 0.5 : 1, side: pitch * 0.82)
            }
        }
    }

    /// Embaixo de um codigo: a rede (o selo dela) e de qual carteira, e o endereco curto, que
    /// sobe um pouco ao aparecer.
    func addressLabel(under code: CGPoint, badge: Int, title: String, address: String, vault: Bool, appear: Double) {
        guard appear > 0.01 else { return }
        var label = context
        label.opacity *= appear
        let middle = code.x + G.codeSize / 2
        let rise = CGFloat(1 - appear) * 6
        let titleText = label.resolve(Text(verbatim: title).font(.system(size: 11, weight: .semibold)).foregroundColor(Palette.inkSoft))
        let titleWidth = titleText.measure(in: CGSize(width: 200, height: 20)).width
        let lock: CGFloat = vault ? 12 : 0
        let rowWidth = 18 + 6 + lock + titleWidth
        var x = middle - rowWidth / 2
        let rowY = code.y + G.codeSize + 20 + rise
        if let symbol = label.resolveSymbol(id: badge) {
            label.draw(symbol, at: CGPoint(x: x + 9, y: rowY), anchor: .center)
        }
        x += 18 + 6
        if vault {
            label.draw(Text(Image(systemName: "lock.fill")).font(.system(size: 9, weight: .bold)).foregroundColor(Palette.inkSoft),
                       at: CGPoint(x: x, y: rowY), anchor: .leading)
            x += lock
        }
        label.draw(titleText, at: CGPoint(x: x, y: rowY), anchor: .leading)
        label.draw(Text(verbatim: address).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundColor(Palette.ink),
                   at: CGPoint(x: middle, y: rowY + 22), anchor: .center)
    }

    /// Uma moeda de pixels: um disco 5 por 5 com a borda clara.
    func coin(at center: CGPoint, alpha: Double) {
        for c in -2...2 {
            for r in -2...2 where c * c + r * r <= 5 {
                let rim = c * c + r * r >= 4
                dot(CGPoint(x: center.x + CGFloat(c) * G.pitch, y: center.y + CGFloat(r) * G.pitch), tone: rim ? 0.95 : 0.7, alpha: alpha)
            }
        }
    }

    /// Um clarao sobre uma area, quando a moeda entra.
    func flash(_ rect: CGRect, _ amount: Double) {
        guard amount > 0.01 else { return }
        context.fill(Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 6), with: .color(Color.white.opacity(0.12 * amount)))
    }
}
