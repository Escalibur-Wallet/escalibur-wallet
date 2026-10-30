// O icone de 512 e a imagem de destaque (1024x500) da Google Play, do icone do iOS.
//
//   swift tools/loja/destaque-android.swift     grava em build/loja-android/grafico
import AppKit
let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
let saida = raiz + "/build/loja-android/grafico"
try? FileManager.default.createDirectory(atPath: saida, withIntermediateDirectories: true)
let icone = NSImage(contentsOfFile: raiz + "/App/EscaliburWallet/Resources/Assets.xcassets/AppIcon.appiconset/wallet-1024.png")!
func cor(_ hex: UInt32) -> NSColor { NSColor(srgbRed: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: 1) }
func gravar(_ rep: NSBitmapImageRep, _ nome: String, _ w: Int, _ h: Int) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: w, height: h))
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: saida + "/" + nome) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)
}
func tela(_ w: Int, _ h: Int, _ desenho: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    desenho(); NSGraphicsContext.restoreGraphicsState(); return rep
}
// O icone da Play: 512 quadrado, sem canto (a Play arredonda).
gravar(tela(512, 512) { icone.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512)) }, "icone-512.png", 512, 512)
// A imagem de destaque: 1024x500, a marca e a frase.
for (idioma, frase) in [("pt-BR", "Carteira cripto self-custody. Só você tem as chaves."), ("en-US", "Self-custody crypto wallet. Only you hold the keys.")] {
    gravar(tela(1024, 500) {
        cor(0x0B0B0C).setFill(); NSRect(x: 0, y: 0, width: 1024, height: 500).fill()
        let lado = 132.0, x = (1024 - lado) / 2, y = 500 - 96 - lado
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: lado, height: lado), xRadius: lado * 0.225, yRadius: lado * 0.225).addClip()
        icone.draw(in: NSRect(x: x, y: y, width: lado, height: lado))
        NSGraphicsContext.restoreGraphicsState()
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let nome = NSAttributedString(string: "Escalibur Wallet", attributes: [.font: NSFont.systemFont(ofSize: 64, weight: .bold), .foregroundColor: cor(0xF5F5F6), .kern: -1.2, .paragraphStyle: p])
        nome.draw(in: NSRect(x: 0, y: 150, width: 1024, height: 80))
        let apoio = NSAttributedString(string: frase, attributes: [.font: NSFont.systemFont(ofSize: 30, weight: .regular), .foregroundColor: cor(0xA8A8AE), .paragraphStyle: p])
        apoio.draw(in: NSRect(x: 0, y: 96, width: 1024, height: 44))
    }, "destaque-\(idioma).png", 1024, 500)
}
print("ok")
