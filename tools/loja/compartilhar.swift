// A imagem de compartilhamento do site (og:image, 1200x630), limpa: a foto da campanha da
// mao segurando o iPhone no grafico do Bitcoin a esquerda, e a direita so o icone, o nome,
// uma linha pequena e os selos da App Store e do Google Play (site/selos). A foto tem fundo
// preto puro, entao a imagem inteira e preta e a foto se funde sem emenda.
//
//   swift tools/loja/compartilhar.swift <saida.jpg> [na-loja]
//
// Sem "na-loja", o rodape diz "Em breve".
import AppKit

let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let foto = NSImage(contentsOf: raiz.appendingPathComponent("tools/loja/campanha/grafico-na-mao.png"))!
let icone = NSImage(contentsOf: raiz.appendingPathComponent("App/EscaliburWallet/Resources/Assets.xcassets/AppIcon.appiconset/wallet-1024.png"))!
let selo = NSImage(contentsOf: raiz.appendingPathComponent("site/selos/baixar-na-app-store.svg"))!
let comSelo = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "na-loja"
let L = 1200.0, A = 630.0
func cor(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: 1)
}
func texto(_ s: String, _ tamanho: Double, _ peso: NSFont.Weight, _ c: NSColor, tracking: Double = 0) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: tamanho, weight: peso), .foregroundColor: c, .kern: tamanho * tracking])
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(L), pixelsHigh: Int(A), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: L, height: A)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
NSColor.black.setFill()
NSRect(x: 0, y: 0, width: L, height: A).fill()

// A foto a esquerda: o iPhone inteiro com a mao, na altura toda.
let origem = NSRect(x: 0, y: 1672 - 1480, width: 941, height: 1330)   // y do AppKit, de baixo
let escala = A / origem.height
let w = origem.width * escala
foto.draw(in: NSRect(x: 40, y: 0, width: w, height: A), from: origem, operation: .sourceOver, fraction: 1)

// A direita, pequeno e com folga: icone, nome, uma linha, os dois selos e o endereco.
let play = NSImage(contentsOf: raiz.appendingPathComponent("site/selos/disponivel-no-google-play.png"))!
let x = 650.0
let lado = 60.0
let nome = texto("Escalibur Wallet", 46, .semibold, cor(0xF5F5F6), tracking: -0.022)
let apoio = texto("Carteira cripto self-custody. Só você tem as chaves.", 20, .regular, cor(0x8A8A92))
let seloAltura = 46.0
let appLargura = selo.size.width * seloAltura / selo.size.height
// Os dois selos na mesma altura, como as duas lojas pedem.
let playLargura = play.size.width * seloAltura / play.size.height
let rodape = texto(comSelo ? "escaliburwallet.com" : "Em breve  ·  escaliburwallet.com", 15, .medium, cor(0x5C5C63))
let alturaBloco = lado + 34 + nome.size().height + 10 + apoio.size().height + 40 + seloAltura + 22 + rodape.size().height
var y = (A + alturaBloco) / 2 - lado
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: NSRect(x: x, y: y, width: lado, height: lado), xRadius: lado * 0.2237, yRadius: lado * 0.2237).addClip()
icone.draw(in: NSRect(x: x, y: y, width: lado, height: lado))
NSGraphicsContext.restoreGraphicsState()
y -= 34 + nome.size().height
nome.draw(at: NSPoint(x: x - 2, y: y))
y -= 10 + apoio.size().height
apoio.draw(at: NSPoint(x: x, y: y))
y -= 40 + seloAltura
selo.draw(in: NSRect(x: x, y: y, width: appLargura, height: seloAltura))
play.draw(in: NSRect(x: x + appLargura + 12, y: y, width: playLargura, height: seloAltura))
y -= 22 + rodape.size().height
rodape.draw(at: NSPoint(x: x, y: y))
NSGraphicsContext.restoreGraphicsState()

let saida = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "compartilhar.jpg"
let opaco = CGContext(data: nil, width: Int(L), height: Int(A), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaco.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: L, height: A))
let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: saida) as CFURL, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(d, opaco.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
CGImageDestinationFinalize(d)
print("ok \(saida)")
