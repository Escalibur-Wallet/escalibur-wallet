// As imagens da pagina da App Store: cada captura do simulador dentro do aparelho do site
// (o mesmo desenho de site/estilo.css, .aparelho e .tela), com o titulo e a frase de apoio
// em cima. 1320x2868, o tamanho de 6,9" que a App Store pede; a captura de 6,3" (1206x2622,
// o iPhone 17 do simulador) entra reduzida, sem ampliar.
//
//   swift tools/loja/compor.swift <legendas.json> <idioma> <pasta das capturas> <pasta de saida>
//
// legendas.json: [{"captura": "1-carteira", "pt-BR": ["titulo", "apoio"], "en-US": [...]}]
import AppKit

let args = CommandLine.arguments
guard args.count == 5 else {
    print("uso: compor.swift <legendas.json> <idioma> <capturas> <saida>")
    exit(2)
}
let idioma = args[2]
let entrada = URL(fileURLWithPath: args[3])
let saida = URL(fileURLWithPath: args[4])
try FileManager.default.createDirectory(at: saida, withIntermediateDirectories: true)
let legendas = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [[String: Any]]

// ESCALIBUR_PLATAFORMA=android: as imagens da Google Play, em 9:16 (a Play recusa mais alto que 2:1),
// com a captura do Android (1080x2400). Desenha em 1320 de largura e grava em 1080x1920.
let android = ProcessInfo.processInfo.environment["ESCALIBUR_PLATAFORMA"] == "android"
let largura = 1320.0, altura = android ? 1320.0 * 16 / 9 : 2868.0
let saidaLargura = android ? 1080 : Int(largura), saidaAltura = android ? 1920 : Int(altura)
func cor(_ hex: UInt32, _ alfa: Double = 1) -> NSColor {
    NSColor(srgbRed: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: alfa)
}
let void = cor(0x0B0B0C), ink = cor(0xF5F5F6), inkSoft = cor(0xA8A8AE)

func texto(_ s: String, tamanho: Double, peso: NSFont.Weight, cor: NSColor, tracking: Double, linha: Double) -> NSAttributedString {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    p.minimumLineHeight = tamanho * linha
    p.maximumLineHeight = tamanho * linha
    p.lineBreakStrategy = .standard
    return NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: tamanho, weight: peso),
        .foregroundColor: cor,
        .kern: tamanho * tracking,
        .paragraphStyle: p,
    ])
}

/// O aparelho do site: borda de metal fina junto da tela, faixa escura por fora, fio claro
/// na beirada e os botoes laterais. Medidas em fracao da largura, como no CSS.
func aparelho(_ captura: NSImage, x: Double, topo: Double, w: Double) {
    let borda = w * 0.034
    let telaW = w - 2 * borda
    let telaH = telaW * proporcao(captura)
    let h = telaH + 2 * borda
    let y = altura - topo - h
    let fora = NSRect(x: x, y: y, width: w, height: h)
    let corpo = NSBezierPath(roundedRect: fora, xRadius: w * 0.175, yRadius: w * 0.175)

    // A sombra embaixo (0 40px 80px -30px no site).
    NSGraphicsContext.saveGraphicsState()
    let sombra = NSShadow()
    sombra.shadowColor = NSColor.black.withAlphaComponent(0.9)
    sombra.shadowBlurRadius = w * 0.14
    sombra.shadowOffset = NSSize(width: 0, height: -w * 0.1)
    sombra.set()
    NSBezierPath(roundedRect: fora.insetBy(dx: w * 0.1, dy: w * 0.1), xRadius: w * 0.1, yRadius: w * 0.1).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Botoes: acao e volume a esquerda, ligar a direita.
    let escala = w / 280
    cor(0x2A2A2F).setFill()
    NSBezierPath(roundedRect: NSRect(x: x - 2 * escala, y: y + h * (1 - 0.22 - 0.13), width: 3 * escala, height: h * 0.13), xRadius: 2 * escala, yRadius: 2 * escala).fill()
    NSBezierPath(roundedRect: NSRect(x: x + w - escala, y: y + h * (1 - 0.27 - 0.11), width: 3 * escala, height: h * 0.11), xRadius: 2 * escala, yRadius: 2 * escala).fill()

    // Metal em 145 graus.
    let metal = NSGradient(colorsAndLocations: (cor(0x3B3B41), 0), (cor(0x1A1A1D), 0.38), (cor(0x2C2C31), 0.72), (cor(0x121214), 1))!
    metal.draw(in: corpo, angle: -55)
    NSGraphicsContext.saveGraphicsState()
    corpo.addClip()
    cor(0x0D0D0F).setStroke()
    corpo.lineWidth = borda * 0.45 * 2
    corpo.stroke()
    NSColor.white.withAlphaComponent(0.10).setStroke()
    corpo.lineWidth = 2 * escala
    corpo.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // A tela.
    let tela = NSRect(x: x + borda, y: y + borda, width: telaW, height: telaH)
    let recorte = NSBezierPath(roundedRect: tela, xRadius: w * 0.142, yRadius: w * 0.142)
    NSGraphicsContext.saveGraphicsState()
    NSColor.black.setFill()
    recorte.fill()
    recorte.addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    captura.draw(in: tela, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}

/// Altura sobre largura da captura: a do iPhone 17 (2622/1206) ou a do Android (2400/1080).
func proporcao(_ captura: NSImage) -> Double {
    guard let rep = captura.representations.first, rep.pixelsWide > 0 else { return 2622.0 / 1206 }
    return Double(rep.pixelsHigh) / Double(rep.pixelsWide)
}

/// A captura do `simctl` traz a ilha dinamica pintada de preto; a do XCUITest, nao. Para as
/// sete sairem iguais (e como no site), a area da ilha recebe a cor do fundo da barra de
/// status. So na captura do iPhone 17 (1206 de largura), onde a ilha fica em x 415-790,
/// y 42-151, e so quando o meio dela e preto puro.
func semIlha(_ imagem: NSImage) -> NSImage {
    guard let cg = imagem.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width == 1206 else { return imagem }
    let w = cg.width, h = cg.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return imagem }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    func cor(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) { let i = (y * w + x) * 4; return (px[i], px[i + 1], px[i + 2]) }
    let meio = cor(603, 96), fundo = cor(300, 60)
    // So com fundo de uma cor em volta da ilha: num fundo com imagem (a espada da abertura),
    // pintar por cima deixaria um retangulo; ali a ilha fica.
    let volta = [cor(380, 50), cor(830, 50), cor(380, 150), cor(830, 150)]
    guard meio == (0, 0, 0), fundo != (0, 0, 0), volta.allSatisfy({ $0 == fundo }) else { return imagem }
    for y in 36..<160 { for x in 405..<801 { let i = (y * w + x) * 4; px[i] = fundo.0; px[i + 1] = fundo.1; px[i + 2] = fundo.2; px[i + 3] = 255 } }
    return NSImage(cgImage: ctx.makeImage()!, size: imagem.size)
}

/// As redes em volta do aparelho, no desenho do primeiro passo do tour (`NetworksScene`):
/// duas orbitas, a de dentro continua e a de fora tracejada, e as moedas nelas com um anel da
/// cor do fundo. Os logos sao os do app (Assets.xcassets/Logos); XRP e Stellar, escuros,
/// ganham o disco claro, como no app.
func redes(centro: CGPoint) {
    let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let logos = raiz.appendingPathComponent("App/EscaliburWallet/Resources/Assets.xcassets/Logos")
    let escalaDasOrbitas = android ? 0.8 : 1.0
    let dentro = 600.0 * escalaDasOrbitas, fora = 1000.0 * escalaDasOrbitas
    let orbita = NSBezierPath(ovalIn: NSRect(x: centro.x - dentro, y: centro.y - dentro, width: dentro * 2, height: dentro * 2))
    orbita.lineWidth = 3
    cor(0x3A3A40).setStroke()
    orbita.stroke()
    let externa = NSBezierPath(ovalIn: NSRect(x: centro.x - fora, y: centro.y - fora, width: fora * 2, height: fora * 2))
    externa.lineWidth = 3
    externa.setLineDash([6, 18], count: 2, phase: 0)
    cor(0x2A2A2F).setStroke()
    externa.stroke()
    // id, orbita, angulo (graus; 90 e para cima), tamanho
    let moedas: [(String, Double, Double, Double)] = [
        ("bitcoin", dentro, 15, 190), ("ethereum", dentro, 165, 190),
        ("solana", dentro, -15, 160), ("ripple", dentro, 195, 160),
        ("tron", dentro, 38, 130), ("the-open-network", dentro, 142, 130),
        ("stellar", dentro, -38, 130), ("binancecoin", dentro, 218, 130),
        ("avalanche-2", fora, 90, 150), ("cardano", fora, 70, 116), ("near", fora, 110, 116),
        ("sui", fora, 52, 108), ("dogecoin", fora, 128, 108),
    ]
    for (id, raio, angulo, tamanhoCheio) in moedas {
        let tamanho = tamanhoCheio * escalaDasOrbitas
        let pasta = logos.appendingPathComponent("logo-\(id).imageset")
        guard let nome = (try? FileManager.default.contentsOfDirectory(atPath: pasta.path))?.first(where: { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") }),
              let logo = NSImage(contentsOf: pasta.appendingPathComponent(nome)) else { print("sem logo: \(id)"); continue }
        let a = angulo * .pi / 180
        let p = CGPoint(x: centro.x + raio * cos(a), y: centro.y + raio * sin(a))
        func disco(_ d: Double) -> NSRect { NSRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d) }
        void.setFill()
        NSBezierPath(ovalIn: disco(tamanho + 28)).fill()
        let claro = ["ripple", "stellar"].contains(id)
        (claro ? cor(0xE4E4E7) : cor(0x26262B)).setFill()
        NSBezierPath(ovalIn: disco(tamanho)).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: disco(tamanho)).addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        logo.draw(in: disco(claro ? tamanho * 0.9 : tamanho), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
}

for item in legendas {
    let nome = item["captura"] as! String
    let saidaNome = item["saida"] as? String ?? nome
    let tipo = item["tipo"] as? String
    guard let linhas = item[idioma] as? [String], linhas.count == 2 else { print("sem legenda \(idioma): \(saidaNome)"); exit(1) }
    let arquivo = ["png", "webp"].map { entrada.appendingPathComponent("\(nome).\($0)") }.first { FileManager.default.fileExists(atPath: $0.path) }
    guard let arquivo, let lida = NSImage(contentsOf: arquivo) else { print("sem captura: \(nome)"); exit(1) }
    let captura = semIlha(lida)

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(largura), pixelsHigh: Int(altura), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: largura, height: altura)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    void.setFill()
    NSRect(x: 0, y: 0, width: largura, height: altura).fill()

    // Titulo e apoio, no centro (pedido do dono, 19/10/2026). O apoio pequeno com tracking
    // negativo ficava apertado: SF Pro nesse tamanho ja vem justa, entao ele fica com o
    // espacamento da fonte, linhas mais abertas e mais distancia do titulo.
    let tituloTamanho = 96.0, apoioTamanho = 46.0
    func estilo(_ altura: Double) -> NSMutableParagraphStyle {
        let e = NSMutableParagraphStyle()
        e.alignment = .center
        e.minimumLineHeight = altura
        e.maximumLineHeight = altura
        e.lineBreakStrategy = .standard
        return e
    }
    let titulo = NSAttributedString(string: linhas[0], attributes: [
        .font: NSFont.systemFont(ofSize: tituloTamanho, weight: .semibold), .foregroundColor: ink,
        .kern: tituloTamanho * -0.012, .paragraphStyle: estilo(tituloTamanho * 1.08),
    ])
    // As duas ultimas palavras presas por espaco inquebravel: a ultima linha nunca fica com
    // uma palavra so.
    var apoioTexto = linhas[1]
    if let ultimo = apoioTexto.lastIndex(of: " ") { apoioTexto.replaceSubrange(ultimo...ultimo, with: "\u{00A0}") }
    let apoio = NSAttributedString(string: apoioTexto, attributes: [
        .font: NSFont.systemFont(ofSize: apoioTamanho, weight: .regular), .foregroundColor: inkSoft,
        .kern: 0, .paragraphStyle: estilo(apoioTamanho * 1.34),
    ])
    let caixaTitulo = 1160.0, caixa = 1040.0
    let hTitulo = titulo.boundingRect(with: NSSize(width: caixaTitulo, height: 2000), options: [.usesLineFragmentOrigin]).height
    let hApoio = apoio.boundingRect(with: NSSize(width: caixa, height: 2000), options: [.usesLineFragmentOrigin]).height
    let topoTexto = 190.0
    titulo.draw(with: NSRect(x: (largura - caixaTitulo) / 2, y: altura - topoTexto - hTitulo, width: caixaTitulo, height: hTitulo), options: [.usesLineFragmentOrigin])
    let topoApoio = topoTexto + hTitulo + 30
    apoio.draw(with: NSRect(x: (largura - caixa) / 2, y: altura - topoApoio - hApoio, width: caixa, height: hApoio), options: [.usesLineFragmentOrigin])
    let hTexto = topoApoio + hApoio - topoTexto
    if hTitulo > tituloTamanho * 1.08 + 1 { print("aviso: titulo de \(saidaNome) em \(idioma) em duas linhas") }
    if hApoio > apoioTamanho * 1.34 * 2 + 1 { print("aviso: apoio de \(saidaNome) em \(idioma) passou de duas linhas") }
    let linhasUsadas = Int((hApoio / (apoioTamanho * 1.34)).rounded())

    if tipo == "redes" {
        // O aparelho menor e mais abaixo, no meio das orbitas.
        let w = android ? 620.0 : 800.0, topo = android ? 760.0 : 800.0
        let h = (w - 2 * w * 0.034) * proporcao(captura) + 2 * w * 0.034
        if topoTexto + hTexto > 640 { print("aviso: \(saidaNome) em \(idioma) com \(linhasUsadas) linhas encosta na orbita") }
        redes(centro: CGPoint(x: largura / 2, y: altura - topo - h / 2))
        aparelho(captura, x: (largura - w) / 2, topo: topo, w: w)
    } else {
        let w = android ? 820.0 : 980.0, topo = android ? 560.0 : 640.0
        if topoTexto + hTexto > topo - 70 { print("aviso: \(saidaNome) em \(idioma) com \(linhasUsadas) linhas encosta no aparelho") }
        aparelho(captura, x: (largura - w) / 2, topo: topo, w: w)
    }
    NSGraphicsContext.restoreGraphicsState()

    // A App Store recusa PNG com transparencia: sai sem o canal alfa.
    let opaco = CGContext(data: nil, width: saidaLargura, height: saidaAltura, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    opaco.interpolationQuality = .high
    opaco.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: saidaLargura, height: saidaAltura))
    let destino = CGImageDestinationCreateWithURL(saida.appendingPathComponent("\(saidaNome).png") as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destino, opaco.makeImage()!, nil)
    guard CGImageDestinationFinalize(destino) else { print("nao gravou: \(saidaNome)"); exit(1) }
    print("ok \(idioma) \(saidaNome)")
}
