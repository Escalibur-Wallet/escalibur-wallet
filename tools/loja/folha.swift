// Junta as imagens de uma pasta numa folha de tres colunas, reduzidas, para conferir de uma vez.
//   swift tools/loja/folha.swift <pasta> <saida.png>
import AppKit

let pasta = CommandLine.arguments[1]
let nomes = try FileManager.default.contentsOfDirectory(atPath: pasta).filter { $0.first?.isNumber == true && $0.hasSuffix(".png") }.sorted()
let imagens = nomes.map { NSImage(contentsOfFile: pasta + "/" + $0)! }
let w = 440.0, h = w * 2868 / 1320, vao = 24.0
let colunas = 3.0, linhas = (Double(imagens.count) / colunas).rounded(.up)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * colunas + vao * (colunas + 1)), pixelsHigh: Int(h * linhas + vao * (linhas + 1)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(white: 0.22, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: Double(rep.pixelsWide), height: Double(rep.pixelsHigh)).fill()
NSGraphicsContext.current?.imageInterpolation = .high
for (i, imagem) in imagens.enumerated() {
    let coluna = Double(i % 3), linha = linhas - 1 - Double(i / 3)
    imagem.draw(in: NSRect(x: vao + coluna * (w + vao), y: vao + linha * (h + vao), width: w, height: h))
}
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
