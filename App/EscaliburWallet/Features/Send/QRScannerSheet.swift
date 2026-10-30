import AVFoundation
import SwiftUI
import VisionKit

/// Le um QR pela camera. Nenhuma imagem e guardada; so o texto do codigo sai daqui.
/// Sem a permissao, a tela explica e leva direto a pagina do app nos Ajustes.
struct QRScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var access: Access = .checking

    enum Access { case checking, allowed, denied, unsupported }

    var body: some View {
        Group {
            switch access {
            case .checking:
                Palette.void.ignoresSafeArea()
            case .allowed:
                ZStack(alignment: .bottom) {
                    Scanner(onScan: onScan).ignoresSafeArea()
                    SecondaryButton(title: String(localized: "Cancelar")) { dismiss() }.padding(Space.gutter)
                }
            case .denied, .unsupported:
                CameraAccessView(unsupported: access == .unsupported) { dismiss() }
            }
        }
        .task { await check() }
        // Quem volta dos Ajustes com a camera ligada ja encontra o leitor.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, access == .denied { Task { await check() } }
        }
    }

    private func check() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-camera-negada") { access = .denied; return }
        #endif
        guard DataScannerViewController.isSupported else { access = .unsupported; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: access = DataScannerViewController.isAvailable ? .allowed : .denied
        case .notDetermined: access = await AVCaptureDevice.requestAccess(for: .video) ? .allowed : .denied
        default: access = .denied
        }
    }

    private struct Scanner: UIViewControllerRepresentable {
        let onScan: (String) -> Void

        func makeUIViewController(context: Context) -> DataScannerViewController {
            let controller = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.qr])],
                qualityLevel: .balanced, recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true
            )
            controller.delegate = context.coordinator
            try? controller.startScanning()
            return controller
        }

        func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

        func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

        final class Coordinator: NSObject, DataScannerViewControllerDelegate {
            let onScan: (String) -> Void
            var done = false
            init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

            func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
                guard !done else { return }
                for item in items {
                    if case .barcode(let code) = item, let text = code.payloadStringValue, text.count <= 512 {
                        done = true
                        scanner.stopScanning()
                        onScan(text)
                        return
                    }
                }
            }
        }
    }
}

/// Sem camera: o visor que procura um QR, o que o app faz com a camera e o caminho nos
/// Ajustes, com o interruptor da Camera ligando. "Abrir Ajustes" usa o unico link
/// publico (`openSettingsURLString`): no iOS 17 ele cai na pagina do app; no iOS 26 cai
/// na raiz dos Ajustes (conferido no simulador 26.5, 15/10/2026), e por isso a tela
/// diz o caminho inteiro. Os atalhos `App-Prefs:` sao privados e a Apple recusa.
private struct CameraAccessView: View {
    let unsupported: Bool
    let onCancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var switchOn = false

    /// Do iOS 18 em diante, a pagina de cada app fica em Ajustes, Apps.
    static var path: String {
        if #available(iOS 18, *) { return String(localized: "Em Ajustes, Apps, Escalibur, ligue:") }
        return String(localized: "Nos Ajustes da Escalibur, ligue:")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.lg)
            Viewfinder(reduceMotion: reduceMotion)
                .frame(width: 180, height: 180)
                .accessibilityHidden(true)
            Text(unsupported ? "Este iPhone não lê QR pela câmera" : "Libere a câmera para ler o QR")
                .typeStyle(.title).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.top, Space.lg)
            Text(unsupported ? "Cole ou digite o endereço no campo." : "A câmera só lê o código, aqui no iPhone. Nenhuma imagem é guardada nem sai do aparelho.")
                .typeStyle(.body).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
            if !unsupported {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(Self.path).typeStyle(.note).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.sm) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: 0x8E8E93)))
                        Text("Câmera").typeStyle(.row).foregroundStyle(Palette.ink)
                        Spacer(minLength: Space.sm)
                        SettingsSwitch(on: switchOn)
                    }
                    .padding(.horizontal, Space.md)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.body))
                }
                .padding(.top, Space.lg)
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: Space.lg)
            if unsupported {
                PrimaryButton(title: String(localized: "Voltar")) { onCancel() }
            } else {
                PrimaryButton(title: String(localized: "Abrir Ajustes")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("abrir-ajustes-camera")
                TertiaryButton(title: String(localized: "Agora não")) { onCancel() }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.void.ignoresSafeArea())
        .task {
            guard !unsupported else { return }
            if reduceMotion { switchOn = true; return }
            // O interruptor liga, espera, desliga sem animacao e liga de novo.
            while !Task.isCancelled {
                switchOn = false
                try? await Task.sleep(for: .seconds(1.1))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { switchOn = true }
                try? await Task.sleep(for: .seconds(2.6))
            }
        }
    }
}

/// O interruptor do iOS, desenhado: verde ligado, cinza desligado.
private struct SettingsSwitch: View {
    let on: Bool

    var body: some View {
        Capsule()
            .fill(on ? Palette.success : Palette.control)
            .frame(width: 51, height: 31)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 27, height: 27).padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
    }
}

/// O visor em pixels, como as cenas da passphrase e do envelope (pedido do dono, 24/10/2026):
/// os quatro cantos da mira e um QR de pixels que cifram. Uma faixa clara desce e sobe pelo
/// codigo, e os pixels nao assentam: a camera nao le. Com Reduzir Movimento, parado.
private struct Viewfinder: View {
    let reduceMotion: Bool

    /// A grade do visor, em pixels: o codigo de 17 no meio e os cantos nas bordas.
    private static let grid = 25
    private static let code = 17
    private static let arm = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let clock = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let sweep = reduceMotion ? 0.5 : (sin(clock * 2 * .pi / 2.6 - .pi / 2) + 1) / 2
            Canvas { context, size in
                let side = min(size.width, size.height)
                let pitch = side / CGFloat(Self.grid)
                let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
                func dot(_ x: CGFloat, _ y: CGFloat, tone: Double, alpha: Double = 1) {
                    let cell = pitch * 0.8
                    let rect = CGRect(x: origin.x + x * pitch + (pitch - cell) / 2, y: origin.y + y * pitch + (pitch - cell) / 2,
                                      width: cell, height: cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.24), with: .color(PixelFill.gray(tone).opacity(alpha)))
                }
                // Os cantos da mira, em pixels claros.
                let last = Self.grid - 1
                for (cx, cy, dx, dy) in [(0, 0, 1, 1), (last, 0, -1, 1), (0, last, 1, -1), (last, last, -1, -1)] {
                    for k in 0..<Self.arm {
                        dot(CGFloat(cx + dx * k), CGFloat(cy), tone: 0.92)
                        if k > 0 { dot(CGFloat(cx), CGFloat(cy + dy * k), tone: 0.92) }
                    }
                }
                // O codigo: os tres olhos fixos e o resto cifrando, cada pixel no seu compasso.
                let offset = (Self.grid - Self.code) / 2
                let band = Double(offset) - 1 + sweep * Double(Self.code + 1)
                for column in 0..<Self.code {
                    for row in 0..<Self.code {
                        let glow = exp(-pow((Double(row + offset) - band) / 1.1, 2))
                        let tone: Double
                        if let eye = Self.eye(column, row) {
                            tone = eye ? 0.8 : 0.1
                        } else {
                            let bit = Self.cipher(column * 31 + row, clock: clock)
                            tone = 0.12 + 0.5 * bit * bit
                        }
                        dot(CGFloat(column + offset), CGFloat(row + offset), tone: tone + (0.95 - tone) * 0.45 * glow)
                    }
                }
                // A faixa que le: uma fileira clara, um pixel mais larga que o codigo de cada lado.
                for column in (offset - 1)...(offset + Self.code) {
                    dot(CGFloat(column), CGFloat(band), tone: 0.96, alpha: 0.85)
                }
            }
        }
    }

    /// Os olhos do QR nos tres cantos: nil fora deles.
    private static func eye(_ column: Int, _ row: Int) -> Bool? {
        for (fc, fr) in [(0, 0), (code - 7, 0), (0, code - 7)] where (fc..<(fc + 7)).contains(column) && (fr..<(fr + 7)).contains(row) {
            let x = column - fc, y = row - fr
            if x == 0 || x == 6 || y == 0 || y == 6 { return true }
            return (2...4).contains(x) && (2...4).contains(y)
        }
        return nil
    }

    /// O tom cifrado de um pixel agora, de 0 a 1, cruzando devagar de um sorteio para o outro.
    private static func cipher(_ id: Int, clock: Double) -> Double {
        let phase = PixelFill.noise(id, 3, 0x51A)
        let beat = clock * 3 * (0.6 + 0.8 * phase) + phase * 8
        let step = beat.rounded(.down)
        let s = beat - step
        let blend = s * s * (3 - 2 * s)
        let a = PixelFill.noise(id, 3, Int(step)), b = PixelFill.noise(id, 3, Int(step) + 1)
        return a + (b - a) * blend
    }
}
