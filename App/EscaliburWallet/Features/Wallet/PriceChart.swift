import EscaliburNetwork
import SwiftUI
import UIKit

/// O grafico de preco: linha grossa com brilho, sem preenchimento embaixo, sem grade
/// e sem eixo, so a maxima em cima do pico e a minima embaixo do vale. Lima quando o
/// periodo sobe, vermelho quando desce. Toque longo ou arrasto horizontal mostra o
/// preco de um ponto.
struct PriceChart: View {
    let points: [PricePoint]
    var loading: Bool = false
    /// Stablecoin: a escala tem piso de 2% do preco medio, senao 0,3% de oscilacao
    /// vira sismografo.
    var isStable: Bool = false
    @Binding var selection: PricePoint?
    /// A unidade escolhida em Ativos (ou a outra, ao tocar no preco).
    let unit: Fmt.DisplayUnit

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Espaco acima e abaixo da linha para os rotulos de maxima e minima.
    private static let labelRoom: CGFloat = 26

    /// No maximo 160 pontos, pela media de cada balde: o dado cru de 24h tem 288, mais
    /// do que a largura mostra, e o excesso so desenha ruido.
    private var shown: [PricePoint] {
        guard points.count > 160 else { return points }
        let size = Double(points.count) / 160
        return (0..<160).compactMap { bucket in
            let start = Int(Double(bucket) * size)
            let end = min(points.count, Int(Double(bucket + 1) * size))
            guard start < end else { return nil }
            let slice = points[start..<end]
            let average = slice.reduce(0) { $0 + $1.price } / Double(slice.count)
            return PricePoint(time: slice.last!.time, price: bucket == 159 ? points.last!.price : average)
        }
    }

    private var trend: Color {
        guard let first = points.first?.price, let last = points.last?.price else { return Palette.inkSoft }
        if last > first { return Palette.up }
        if last < first { return Palette.down }
        return Palette.inkSoft
    }

    var body: some View {
        ZStack {
            if loading && points.isEmpty {
                ChartLoading(labelRoom: Self.labelRoom)
            } else if points.count < 2 {
                Text("Sem histórico de preço neste período").typeStyle(.note).foregroundStyle(Palette.inkMuted)
            } else {
                chart
            }
        }
        // Largura toda: sem isto, o texto de "sem historico" encolhe o quadro e cola na
        // esquerda.
        .frame(maxWidth: .infinity)
        .frame(height: 248)
    }

    private var domain: ClosedRange<Double> {
        let prices = shown.map(\.price)
        var low = prices.min() ?? 0
        var high = prices.max() ?? 1
        if isStable {
            let mean = prices.reduce(0, +) / Double(max(prices.count, 1))
            low = min(low, mean * 0.99)
            high = max(high, mean * 1.01)
        }
        if high <= low { high = low + max(abs(low) * 0.01, .ulpOfOne) }
        return low...high
    }

    /// Quanto o que vem depois do ponto escolhido esta apagado: 0 sem dedo, 1 com o dedo. Anima
    /// nas duas direcoes, para o cinza entrar e sair sem corte seco (pedido do dono, 23/10/2026).
    @State private var dim: Double = 0
    /// O ultimo ponto escolhido: o corte fica nele enquanto a cor volta, depois de soltar.
    @State private var heldTime: Date?
    /// O dedo esta arrastando no grafico, e quando soltou: o toque que vem junto nao conta.
    @State private var dragging = false
    @State private var dragEndedAt: Date?

    private var chart: some View {
        let data = shown
        let color = trend
        let range = domain
        return GeometryReader { geometry in
            // Margem dos lados: a linha e o brilho nao encostam na borda da tela.
            let plot = CGRect(x: Space.gutter, y: Self.labelRoom, width: geometry.size.width - Space.gutter * 2,
                              height: geometry.size.height - Self.labelRoom * 2)
            let place: (Int) -> CGPoint = { index in
                let x = data.count > 1 ? plot.minX + plot.width * CGFloat(index) / CGFloat(data.count - 1) : plot.midX
                let fraction = (data[index].price - range.lowerBound) / (range.upperBound - range.lowerBound)
                return CGPoint(x: x, y: plot.maxY - plot.height * CGFloat(fraction))
            }
            let held = (selection?.time ?? heldTime).flatMap { time in data.firstIndex(where: { $0.time == time }) }
            ZStack(alignment: .topLeading) {
                PriceLineCanvas(points: data.indices.map(place), color: color, plot: plot, cut: held, dim: dim)
                extremeLabel(data: data, top: true, place: place, width: geometry.size.width)
                extremeLabel(data: data, top: false, place: place, width: geometry.size.width)
            }
            .contentShape(Rectangle())
            // Arrastar de lado mexe o ponto na hora (pedido do dono, 27/10/2026); segurar e
            // arrastar continua valendo em qualquer direcao.
            .modifier(SlideToScrub { location in
                guard data.count > 1 else { return }
                dragging = true
                selection = data[index(at: location.x, plot: plot, count: data.count)]
            } ended: {
                dragging = false
                dragEndedAt = .now
                withAnimation(Motion.fade) { selection = nil }
            })
            .gesture(
                LongPressGesture(minimumDuration: 0.15)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        guard case .second(true, let drag?) = value, data.count > 1 else { return }
                        dragging = true
                        selection = data[index(at: drag.location.x, plot: plot, count: data.count)]
                    }
                    .onEnded { _ in
                        dragging = false
                        dragEndedAt = .now
                        withAnimation(Motion.fade) { selection = nil }
                    }
            )
            // Um toque simples tambem escolhe o ponto, e ele fica ate outro toque: no mesmo ponto,
            // o grafico volta ao presente; em outro, o ponto muda. O soltar de um arrasto tambem
            // chega aqui, e nao conta.
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                guard data.count > 1, !dragging, dragEndedAt.map({ Date.now.timeIntervalSince($0) > 0.35 }) ?? true else { return }
                let target = index(at: tap.location.x, plot: plot, count: data.count)
                if let current = selection.flatMap({ chosen in data.firstIndex(where: { $0.time == chosen.time }) }),
                   abs(place(current).x - place(target).x) < 22 {
                    withAnimation(Motion.fade) { selection = nil }
                } else {
                    selection = data[target]
                }
            })
        }
        .onChange(of: selection?.time) { _, time in
            if let time { heldTime = time }
        }
        .onChange(of: selection != nil) { _, active in
            withAnimation(reduceMotion ? nil : (active ? .easeOut(duration: 0.28) : .easeInOut(duration: 0.4))) { dim = active ? 1 : 0 }
        }
        .sensoryFeedback(.selection, trigger: selection?.time)
        .accessibilityElement()
        .accessibilityLabel("Gráfico de preço")
        .accessibilityValue(accessibilitySummary(data))
    }

    private func index(at x: CGFloat, plot: CGRect, count: Int) -> Int {
        let fraction = min(max((x - plot.minX) / max(plot.width, 1), 0), 1)
        return Int((fraction * CGFloat(count - 1)).rounded())
    }

    /// A maxima em cima do pico, a minima embaixo do vale, sem sair da tela.
    private func extremeLabel(data: [PricePoint], top: Bool, place: (Int) -> CGPoint, width: CGFloat) -> some View {
        let prices = data.map(\.price)
        let target = top ? (prices.max() ?? 0) : (prices.min() ?? 0)
        let index = data.firstIndex { $0.price == target } ?? 0
        let point = place(index)
        return Text(priceText(target, prices: prices))
            .typeStyle(.axis)
            .foregroundStyle(Palette.inkSoft)
            .fixedSize()
            .position(x: min(max(point.x, 48), width - 48), y: top ? point.y - 16 : point.y + 16)
    }

    private func priceText(_ value: Double, prices: [Double]) -> String {
        let amplitude = ((prices.max() ?? 0) - (prices.min() ?? 0)) / max(prices.max() ?? 1, .ulpOfOne)
        // Preco miudo (abaixo de 0,0001) sai com os zeros em subscrito: com 4 casas, a
        // maxima e a minima viravam as duas "R$ 0,0000".
        guard unit != .btc, value >= 0.0001 else { return Fmt.price(value, unit: unit) }
        return amplitude < 0.01 ? "\(unit.symbol)\(Fmt.nbsp)\(Fmt.grouped(value, fractionDigits: 4))" : Fmt.price(value, unit: unit)
    }

    private func accessibilitySummary(_ data: [PricePoint]) -> String {
        let prices = data.map(\.price)
        guard let low = prices.min(), let high = prices.max() else { return "" }
        return String(localized: "Mínima \(priceText(low, prices: prices)), máxima \(priceText(high, prices: prices))")
    }
}

/// A linha do grafico, com o brilho, e o ponto escolhido. Com o dedo no grafico, o que vem
/// depois do ponto fica cinza apagado: o grafico "volta no tempo" ate ali (pedido do dono,
/// 22/10/2026). `dim` anima de 0 a 1 (e volta), e a cor sai e entra aos poucos.
private struct PriceLineCanvas: View, @preconcurrency Animatable {
    let points: [CGPoint]
    let color: Color
    let plot: CGRect
    /// O indice do ponto escolhido (ou do ultimo, enquanto a cor volta).
    let cut: Int?
    var dim: Double
    @Environment(\.displayScale) private var scale

    var animatableData: Double {
        get { dim }
        set { dim = newValue }
    }

    var body: some View {
        Canvas { context, size in
            var line = Path()
            for (index, point) in points.enumerated() {
                index == 0 ? line.move(to: point) : line.addLine(to: point)
            }
            let style = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            // So a linha e o brilho: a area em pontinhos embaixo dela saiu (pedido do dono,
            // 14/10/2026). O brilho: a linha larga e desfocada por baixo da linha nitida, 38% mais
            // fraco desde 15/10/2026 (pedido do dono).
            func draw(_ layer: inout GraphicsContext) {
                layer.drawLayer { glow in
                    glow.addFilter(.blur(radius: 14))
                    glow.stroke(line, with: .color(color.opacity(0.34)), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                }
                layer.stroke(line, with: .color(color), style: style)
            }
            guard let cut, points.indices.contains(cut), dim > 0.001 else {
                context.drawLayer { draw(&$0) }
                return
            }
            let point = points[cut]
            // O corte no pixel: as duas metades se encontram sem fresta.
            let x = (point.x * scale).rounded() / scale
            context.drawLayer { past in
                past.clip(to: Path(CGRect(x: 0, y: 0, width: x, height: size.height)))
                draw(&past)
            }
            context.drawLayer { future in
                future.clip(to: Path(CGRect(x: x, y: 0, width: max(size.width - x, 0), height: size.height)))
                future.stroke(line, with: .color(Palette.edgeStrong), style: style)
                future.opacity = 1 - dim
                draw(&future)
            }
            // A regua e o ponto entram e saem junto com o cinza.
            context.opacity = dim
            var rule = Path()
            rule.move(to: CGPoint(x: x, y: plot.minY))
            rule.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(rule, with: .color(Palette.inkMuted), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)), with: .color(Palette.void))
            context.fill(Path(ellipseIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)), with: .color(color))
        }
    }
}

/// Os periodos, por extenso: "1M" e ambiguo entre minuto e mes.
struct PeriodPicker: View {
    @Binding var range: ChartRange
    @Namespace private var namespace

    private func title(_ range: ChartRange) -> String {
        switch range {
        case .day: return "24h"
        case .week: return String(localized: "7 dias")
        case .month: return String(localized: "30 dias")
        case .year: return String(localized: "1 ano")
        case .all: return String(localized: "Tudo")
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ChartRange.allCases) { option in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { range = option }
                } label: {
                    Text(title(option))
                        .typeStyle(.label)
                        .fontWeight(range == option ? .semibold : .regular)
                        .foregroundStyle(range == option ? Palette.ink : Palette.inkMuted)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                        .background {
                            if range == option {
                                Color.clear
                                    .modifier(SelectionGlass(active: true))
                                    .matchedGeometryEffect(id: "period", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(range == option ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: range)
    }
}

/// O grafico carregando (pedido do dono, 14/10/2026): uma linha fantasma cinza, que ondula
/// devagar, com um brilho que corre da esquerda para a direita. Cinza e sem rotulos, para
/// nunca passar por dado. Com Reduzir Movimento, fica parada. O Mercado sem fonte usa a
/// mesma linha.
struct ChartLoading: View {
    let labelRoom: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let sweepPeriod = 1.8

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let plot = CGRect(x: Space.gutter, y: labelRoom, width: size.width - Space.gutter * 2, height: size.height - labelRoom * 2)
                var line = Path()
                let steps = 90
                for step in 0...steps {
                    let x = Double(step) / Double(steps)
                    let wave = 0.5 + 0.16 * sin(x * 2 * .pi * 1.2 + time * 0.9) + 0.08 * sin(x * 2 * .pi * 2.9 - time * 1.3)
                    let point = CGPoint(x: plot.minX + plot.width * x, y: plot.maxY - plot.height * wave)
                    step == 0 ? line.move(to: point) : line.addLine(to: point)
                }
                let style = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                canvas.stroke(line, with: .color(Palette.edgeStrong), style: style)
                guard !reduceMotion else { return }
                // O brilho: uma janela que atravessa a linha, mais clara no meio.
                let phase = time.truncatingRemainder(dividingBy: Self.sweepPeriod) / Self.sweepPeriod
                let width = plot.width * 0.28
                let center = plot.minX - width / 2 + (plot.width + width) * phase
                canvas.drawLayer { glow in
                    glow.clip(to: Path(CGRect(x: center - width / 2, y: 0, width: width, height: size.height)))
                    glow.stroke(line, with: .linearGradient(
                        Gradient(stops: [.init(color: Palette.inkSoft.opacity(0), location: 0), .init(color: Palette.inkSoft, location: 0.5),
                                         .init(color: Palette.inkSoft.opacity(0), location: 1)]),
                        startPoint: CGPoint(x: center - width / 2, y: 0), endPoint: CGPoint(x: center + width / 2, y: 0)
                    ), style: style)
                }
            }
        }
        .accessibilityLabel("Carregando o gráfico")
    }
}

/// O arrasto de lado no grafico, como nos apps de corretora: o ponto anda com o dedo desde o
/// comeco, sem segurar antes. Ele decide no primeiro movimento: de lado, e dele, e a rolagem da
/// tela espera ele desistir; na vertical, desiste e a tela rola. No iOS 17 fica o segurar e arrastar.
private struct SlideToScrub: ViewModifier {
    let changed: (CGPoint) -> Void
    let ended: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(HorizontalPan(changed: changed, ended: ended))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let changed: (CGPoint) -> Void
    let ended: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: changed(context.converter.localLocation)
        case .ended, .cancelled, .failed: ended()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        /// A rolagem da tela so comeca se o arrasto de lado desistir.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }

        /// O voltar pela borda da tela vem antes.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            other is UIScreenEdgePanGestureRecognizer
        }
    }
}
