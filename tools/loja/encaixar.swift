// Encaixa imagens de campanha (as geradas fora, em 9:16) no tamanho de 6,9" da App Store,
// 1320x2868: escala ate cobrir a altura e corta as laterais, sem esticar nem inventar fundo.
// Sai PNG sem canal alfa, que a App Store exige.
//
//   swift tools/loja/encaixar.swift <saida> <imagem>[@deslocamento] ...
//
// O deslocamento (de -1 a 1) move o corte para a esquerda ou a direita; 0 e o centro.
import AppKit

let largura = 1320, altura = 2868
let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { print("uso: encaixar.swift <saida> <imagem>[@deslocamento] ..."); exit(2) }
let saida = URL(fileURLWithPath: args[0])
try FileManager.default.createDirectory(at: saida, withIntermediateDirectories: true)

for (n, item) in args.dropFirst().enumerated() {
    var caminho = item, deslocamento = 0.0
    if let arroba = item.lastIndex(of: "@"), let d = Double(item[item.index(after: arroba)...]) {
        caminho = String(item[..<arroba]); deslocamento = max(-1, min(1, d))
    }
    guard let fonte = CGImageSourceCreateWithURL(URL(fileURLWithPath: caminho) as CFURL, nil),
          let imagem = CGImageSourceCreateImageAtIndex(fonte, 0, nil) else { print("nao abriu: \(caminho)"); exit(1) }
    let escala = max(Double(largura) / Double(imagem.width), Double(altura) / Double(imagem.height))
    let w = Double(imagem.width) * escala, h = Double(imagem.height) * escala
    let sobra = w - Double(largura)
    let x = -sobra / 2 - deslocamento * sobra / 2
    let ctx = CGContext(data: nil, width: largura, height: altura, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(imagem, in: CGRect(x: x, y: (Double(altura) - h) / 2, width: w, height: h))
    let nome = String(format: "%02d", n + 1) + ".png"
    let destino = CGImageDestinationCreateWithURL(saida.appendingPathComponent(nome) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destino, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(destino) else { print("nao gravou: \(nome)"); exit(1) }
    print("\(nome) <- \((caminho as NSString).lastPathComponent) (escala \(String(format: "%.2f", escala))x, corte \(Int(sobra)) px)")
}
