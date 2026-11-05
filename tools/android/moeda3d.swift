// A moeda 3D do tour no Android: as mesmas texturas, luz, metal e camera do
// `BitcoinCoin3D` do iOS, renderizadas pelo SceneKit do Mac em 120 quadros (uma volta,
// de 3 em 3 graus). O Android mostra o quadro do angulo da hora, e a moeda fica igual a
// do iPhone sem motor 3D no app.
//
// Uso, da raiz do repositorio (o `swift` direto quebra no SceneKit; compilado, roda):
//   swiftc -O tools/android/moeda3d.swift -o /tmp/moeda3d && /tmp/moeda3d
// Grava Android/app/src/main/assets/moeda3d/000.webp ... 119.webp (precisa do python3 com Pillow).

import AppKit
import SceneKit

let quadros = 120
let lado = 576
let raiz = FileManager.default.currentDirectoryPath
let texturas = raiz + "/App/EscaliburWallet/Resources/Moeda3D/"
let destino = raiz + "/Android/app/src/main/assets/moeda3d"

func textura(_ nome: String) -> NSImage {
    guard let imagem = NSImage(contentsOfFile: texturas + nome + ".jpg") else { fatalError("sem a textura \(nome)") }
    return imagem
}

func material(_ nome: String, repete: Int = 1) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.diffuse.contents = textura(nome)
    if repete > 1 {
        material.diffuse.wrapS = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(CGFloat(repete), 1, 1)
    }
    material.metalness.contents = 0.85
    material.roughness.contents = 0.32
    return material
}

/// O ceu claro em cima e o chao escuro embaixo, como o `environment()` do iOS.
func ambiente() -> CGImage {
    let contexto = CGContext(data: nil, width: 256, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let cores = [CGColor(gray: 1, alpha: 1), CGColor(gray: 0.45, alpha: 1), CGColor(gray: 0.06, alpha: 1)]
    let gradiente = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cores as CFArray, locations: [0, 0.5, 1])!
    // No contexto do CoreGraphics o y cresce para cima: o branco sai do topo.
    contexto.drawLinearGradient(gradiente, start: CGPoint(x: 0, y: 128), end: .zero, options: [])
    return contexto.makeImage()!
}

let cena = SCNScene()
cena.background.contents = NSColor.clear
let moeda = SCNCylinder(radius: 1, height: 0.14)
moeda.radialSegmentCount = 128
moeda.materials = [material("bitcoin-borda", repete: 6), material("bitcoin-frente"), material("bitcoin-verso")]
let corpo = SCNNode(geometry: moeda)
corpo.eulerAngles.x = .pi / 2
let giro = SCNNode()
giro.addChildNode(corpo)
cena.rootNode.addChildNode(giro)

cena.lightingEnvironment.contents = ambiente()
cena.lightingEnvironment.intensity = 1.8
let luz = SCNNode()
luz.light = SCNLight()
luz.light?.type = .directional
luz.light?.intensity = 1150
luz.eulerAngles = SCNVector3(-0.6, -0.5, 0)
cena.rootNode.addChildNode(luz)

let camera = SCNNode()
camera.camera = SCNCamera()
camera.camera?.fieldOfView = 30
camera.position = SCNVector3(0, 0, 4.6)
cena.rootNode.addChildNode(camera)

let renderizador = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
renderizador.scene = cena
renderizador.pointOfView = camera

let pasta = NSTemporaryDirectory() + "moeda3d-\(getpid())"
try FileManager.default.createDirectory(atPath: pasta, withIntermediateDirectories: true)
for indice in 0..<quadros {
    giro.eulerAngles.y = CGFloat(Double(indice) / Double(quadros) * 2 * .pi)
    // O tamanho em pontos: o snapshot devolve o dobro em pixels numa tela Retina.
    let imagem = renderizador.snapshot(atTime: 0, with: CGSize(width: lado, height: lado), antialiasingMode: .multisampling4X)
    guard let tiff = imagem.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("quadro \(indice)") }
    try png.write(to: URL(fileURLWithPath: pasta + String(format: "/%03d.png", indice)))
}

// WebP com transparencia, no tamanho do lado.
let python = Process()
python.executableURL = URL(fileURLWithPath: "/usr/bin/env")
python.arguments = ["python3", "-I", "-c", """
import os, sys
from PIL import Image
origem, destino, lado = sys.argv[1], sys.argv[2], int(sys.argv[3])
os.makedirs(destino, exist_ok=True)
for nome in sorted(os.listdir(origem)):
    imagem = Image.open(os.path.join(origem, nome)).convert("RGBA")
    if imagem.size != (lado, lado):
        imagem = imagem.resize((lado, lado), Image.LANCZOS)
    imagem.save(os.path.join(destino, nome.replace(".png", ".webp")), "WEBP", quality=86, alpha_quality=100, method=6)
""", pasta, destino, String(lado)]
try python.run()
python.waitUntilExit()
try? FileManager.default.removeItem(atPath: pasta)
guard python.terminationStatus == 0 else { fatalError("a conversao para WebP falhou") }
print("\(quadros) quadros em \(destino)")
