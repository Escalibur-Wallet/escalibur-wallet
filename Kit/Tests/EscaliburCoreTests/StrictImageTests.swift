import Foundation
import Testing
@testable import EscaliburCore

/// A barreira antes do ImageIO no processo que assina (auditoria 8 e rodadas 1 e 2): o PNG e o JPEG remontados so com o que
/// desenha a imagem, cada campo conferido. Os arquivos sao montados aqui byte a byte, sem ImageIO, para rodar tambem no
/// Android.
@Suite("Imagem estrita (StrictImage)")
struct StrictImageTests {
    // MARK: PNG

    static func chunk(_ name: String, _ body: [UInt8]) -> [UInt8] {
        let type = Array(name.utf8)
        let length = UInt32(body.count)
        let crc = PNGCRC32.checksum(type + body)
        return [UInt8(length >> 24), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)] + type + body
            + [UInt8(crc >> 24), UInt8(crc >> 16 & 0xFF), UInt8(crc >> 8 & 0xFF), UInt8(crc & 0xFF)]
    }

    static func header(width: UInt32 = 4, height: UInt32 = 4, depth: UInt8 = 8, color: UInt8, interlace: UInt8 = 0) -> [UInt8] {
        func be(_ value: UInt32) -> [UInt8] { [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
        return chunk("IHDR", be(width) + be(height) + [depth, color, 0, 0, interlace])
    }

    static let data = chunk("IDAT", [0x78, 0x9C, 0x63, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])
    static let end = chunk("IEND", [])
    static let palette = chunk("PLTE", [255, 0, 0, 0, 255, 0, 0, 0, 255])

    static func png(_ chunks: [[UInt8]]) -> Data { Data(StrictImage.pngSignature + chunks.flatMap { $0 }) }

    @Test("PNG comum passa sem os blocos auxiliares; paleta com tRNS do tamanho certo passa")
    func pngAccepted() throws {
        let text = Self.chunk("tEXt", Array("Comment\u{0}x".utf8))
        let rgb = try #require(StrictImage.sanitize(Self.png([Self.header(color: 2), text, Self.data, Self.end])))
        #expect(rgb == Self.png([Self.header(color: 2), Self.data, Self.end]))
        #expect(StrictImage.sanitize(Self.png([Self.header(color: 3), Self.palette, Self.chunk("tRNS", [0, 128]), Self.data, Self.end])) != nil)
        #expect(StrictImage.sanitize(Self.png([Self.header(color: 0), Self.chunk("tRNS", [0, 1]), Self.data, Self.end])) != nil)
        #expect(StrictImage.sanitize(Self.png([Self.header(color: 6), Self.data, Self.data, Self.end])) != nil)
    }

    @Test("PNG malformado recusa: paleta onde nao cabe, dois tRNS, tRNS no tipo com alfa ou maior que a paleta, CRC, ordem")
    func pngRefused() {
        let cases: [(String, Data)] = [
            ("PLTE no cinza", Self.png([Self.header(color: 0), Self.palette, Self.data, Self.end])),
            ("PLTE no cinza com alfa", Self.png([Self.header(color: 4), Self.palette, Self.data, Self.end])),
            ("dois tRNS", Self.png([Self.header(color: 0), Self.chunk("tRNS", [0, 1]), Self.chunk("tRNS", [0, 1]), Self.data, Self.end])),
            ("tRNS de 4000 bytes", Self.png([Self.header(color: 0), Self.chunk("tRNS", [UInt8](repeating: 0, count: 4000)), Self.data, Self.end])),
            ("tRNS no RGBA", Self.png([Self.header(color: 6), Self.chunk("tRNS", [0, 1, 0, 1, 0, 1]), Self.data, Self.end])),
            ("tRNS maior que a paleta", Self.png([Self.header(color: 3), Self.palette, Self.chunk("tRNS", [1, 2, 3, 4]), Self.data, Self.end])),
            ("paleta depois do tRNS", Self.png([Self.header(color: 2), Self.chunk("tRNS", [0, 1, 0, 1, 0, 1]), Self.palette, Self.data, Self.end])),
            ("paleta sem PLTE", Self.png([Self.header(color: 3), Self.data, Self.end])),
            ("IDAT partido por um auxiliar", Self.png([Self.header(color: 2), Self.data, Self.chunk("tEXt", [0x61]), Self.data, Self.end])),
            ("bloco critico desconhecido (CgBI)", Self.png([Self.chunk("CgBI", [0, 0, 0, 0]), Self.header(color: 2), Self.data, Self.end])),
            ("16 bits", Self.png([Self.header(depth: 16, color: 2), Self.data, Self.end])),
            ("entrelacado", Self.png([Self.header(color: 2, interlace: 1), Self.data, Self.end])),
            ("lado maior que o limite", Self.png([Self.header(width: 4096, color: 2), Self.data, Self.end])),
            ("sem IEND", Self.png([Self.header(color: 2), Self.data])),
            ("IDAT que nao e zlib", Self.png([Self.header(color: 2), Self.chunk("IDAT", [0x00, 0x00, 0x01]), Self.end])),
            ("zlib com dicionario", Self.png([Self.header(color: 2), Self.chunk("IDAT", [0x78, 0xBB, 0x00]), Self.end])),
        ]
        for (name, file) in cases { #expect(StrictImage.sanitize(file) == nil, "\(name)") }
        var badCRC = [UInt8](Self.png([Self.header(color: 2), Self.data, Self.end]))
        badCRC[badCRC.count - 13] ^= 0xFF
        #expect(StrictImage.sanitize(Data(badCRC)) == nil)
    }

    // MARK: JPEG

    static func segment(_ marker: UInt8, _ body: [UInt8]) -> [UInt8] {
        let length = body.count + 2
        return [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + body
    }

    static let quant = segment(0xDB, [0x00] + [UInt8](repeating: 1, count: 64))
    static let frame = segment(0xC0, [8, 0, 16, 0, 16, 1, 1, 0x11, 0])
    static func huffman(_ spec: UInt8) -> [UInt8] { segment(0xC4, [spec, 1] + [UInt8](repeating: 0, count: 15) + [0]) }
    static let scan = segment(0xDA, [1, 1, 0x00, 0, 63, 0])
    static let pixels: [UInt8] = [0x12, 0x34, 0xFF, 0x00, 0x56, 0x78]

    static func jpeg(_ parts: [[UInt8]]) -> Data { Data([0xFF, 0xD8] + parts.flatMap { $0 } + Self.pixels + [0xFF, 0xD9]) }

    @Test("JPEG basico passa sem o APPn; tabelas e varredura com o tamanho exato")
    func jpegAccepted() throws {
        let exif = Self.segment(0xE1, Array("Exif\u{0}\u{0}x".utf8))
        let clean = try #require(StrictImage.sanitize(Self.jpeg([exif, Self.quant, Self.frame, Self.huffman(0x00), Self.huffman(0x10), Self.scan])))
        #expect(clean == Self.jpeg([Self.quant, Self.frame, Self.huffman(0x00), Self.huffman(0x10), Self.scan]))
        #expect(StrictImage.sanitize(Self.jpeg([Self.quant, Self.frame, Self.huffman(0x00), Self.huffman(0x10), Self.segment(0xDD, [0, 4]), Self.scan])) != nil)
        // Rodada 4: os marcadores de reinicio com o DRI e na ordem passam.
        let restarts = [UInt8]([0xFF, 0xD8]) + [Self.quant, Self.frame, Self.huffman(0x00), Self.huffman(0x10), Self.segment(0xDD, [0, 4]), Self.scan].flatMap { $0 }
            + [0x12, 0xFF, 0xD0, 0x34, 0xFF, 0xD1, 0x56, 0xFF, 0xD9]
        #expect(StrictImage.sanitize(Data(restarts)) != nil)
        // O 4:2:0 de tres componentes (6 blocos por MCU) passa.
        let yuv = Self.segment(0xC0, [8, 0, 16, 0, 16, 3, 1, 0x22, 0, 2, 0x11, 0, 3, 0x11, 0])
        #expect(StrictImage.sanitize(Self.jpeg([Self.quant, yuv, Self.huffman(0x00), Self.huffman(0x10), Self.segment(0xDA, [3, 1, 0x00, 2, 0x00, 3, 0x00, 0, 63, 0])])) != nil)
        // Rodada 6: o 4:2:2 (luma 2x1) e o 4:4:0 (luma 1x2), de camera e do libjpeg, tambem passam.
        // O ffmpeg grava o 4:4:4 com 1x2 nos tres e o 4:2:2 com a luma 2x2 e os cromas 1x2: vale a proporcao.
        let threeScan = Self.segment(0xDA, [3, 1, 0x00, 2, 0x00, 3, 0x00, 0, 63, 0])
        for (luma, chroma): (UInt8, UInt8) in [(0x21, 0x11), (0x12, 0x11), (0x12, 0x12), (0x22, 0x12), (0x21, 0x21), (0x22, 0x21)] {
            let sampled = Self.segment(0xC0, [8, 0, 16, 0, 16, 3, 1, luma, 0, 2, chroma, 0, 3, chroma, 0])
            #expect(StrictImage.sanitize(Self.jpeg([Self.quant, sampled, Self.huffman(0x00), Self.huffman(0x10), threeScan])) != nil, "luma \(luma), croma \(chroma)")
        }
        // Continuam recusados o croma maior que a luma numa direcao, os cromas diferentes e a luma que nao e multiplo deles.
        for sampling: [UInt8] in [[0x11, 0x12, 0x12], [0x21, 0x12, 0x12], [0x22, 0x12, 0x11], [0x12, 0x21, 0x21]] {
            let sampled = Self.segment(0xC0, [8, 0, 16, 0, 16, 3, 1, sampling[0], 0, 2, sampling[1], 0, 3, sampling[2], 0])
            #expect(StrictImage.sanitize(Self.jpeg([Self.quant, sampled, Self.huffman(0x00), Self.huffman(0x10), threeScan])) == nil, "\(sampling)")
        }
        // A tabela padrao de luminancia do JPEG (a do Anexo K) passa na desigualdade de Kraft.
        let standardDC = Self.segment(0xC4, [0x00, 0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0] + Array(0...11))
        #expect(StrictImage.sanitize(Self.jpeg([Self.quant, Self.frame, standardDC, Self.huffman(0x10), Self.scan])) != nil)
    }

    @Test("JPEG malformado recusa: quadro sem componentes, DHT de 1 byte, varredura vazia, tabela que nao existe, progressivo")
    func jpegRefused() {
        let tables = [Self.quant, Self.huffman(0x00), Self.huffman(0x10)]
        let cases: [(String, Data)] = [
            ("quadro sem componentes", Self.jpeg([Self.quant, Self.segment(0xC0, [8, 0, 16, 0, 16, 0]), Self.huffman(0x00), Self.huffman(0x10), Self.scan])),
            ("DHT de 1 byte", Self.jpeg([Self.quant, Self.frame, Self.segment(0xC4, [0x00]), Self.scan])),
            ("varredura sem componentes", Self.jpeg(tables + [Self.frame, Self.segment(0xDA, [0, 0, 63, 0])])),
            ("varredura com tabela de Huffman que nao existe", Self.jpeg([Self.quant, Self.frame, Self.huffman(0x00), Self.scan])),
            ("quantizacao que nao existe", Self.jpeg([Self.frame, Self.huffman(0x00), Self.huffman(0x10), Self.scan])),
            ("DQT de 16 bits", Self.jpeg([Self.segment(0xDB, [0x10] + [UInt8](repeating: 1, count: 128)), Self.frame, Self.huffman(0x00), Self.huffman(0x10), Self.scan])),
            ("DRI de outro tamanho", Self.jpeg(tables + [Self.frame, Self.segment(0xDD, [0, 4, 0]), Self.scan])),
            ("progressivo", Self.jpeg(tables + [Self.segment(0xC2, [8, 0, 16, 0, 16, 1, 1, 0x11, 0]), Self.scan])),
            ("varredura progressiva num quadro basico", Self.jpeg(tables + [Self.frame, Self.segment(0xDA, [1, 1, 0x00, 1, 5, 0])])),
            ("dois quadros", Self.jpeg(tables + [Self.frame, Self.frame, Self.scan])),
            // Rodada 3: a tabela impossivel, o simbolo fora da faixa, o repetido e a varredura que nao cobre o quadro.
            ("DHT impossivel", Self.jpeg([Self.quant, Self.frame, Self.segment(0xC4, [0x00, 16] + [UInt8](repeating: 0, count: 15) + Array(0..<16)), Self.huffman(0x10), Self.scan])),
            ("DC com simbolo 200", Self.jpeg([Self.quant, Self.frame, Self.segment(0xC4, [0x00, 1] + [UInt8](repeating: 0, count: 15) + [200]), Self.huffman(0x10), Self.scan])),
            ("AC com tamanho 15", Self.jpeg([Self.quant, Self.frame, Self.huffman(0x00), Self.segment(0xC4, [0x10, 1] + [UInt8](repeating: 0, count: 15) + [0x0F]), Self.scan])),
            ("simbolo repetido", Self.jpeg([Self.quant, Self.frame, Self.segment(0xC4, [0x00, 0, 2] + [UInt8](repeating: 0, count: 14) + [1, 1]), Self.huffman(0x10), Self.scan])),
            ("tres componentes e varredura de um", Self.jpeg(tables + [Self.segment(0xC0, [8, 0, 16, 0, 16, 3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0]), Self.scan])),
            // Rodada 4: o MCU de 12 blocos (tres componentes 2x2) e a quantizacao com zero.
            ("MCU de 12 blocos", Self.jpeg(tables + [Self.segment(0xC0, [8, 0, 16, 0, 16, 3, 1, 0x22, 0, 2, 0x22, 0, 3, 0x22, 0]),
                                                     Self.segment(0xDA, [3, 1, 0x00, 2, 0x00, 3, 0x00, 0, 63, 0])])),
            ("croma maior que a luma", Self.jpeg(tables + [Self.segment(0xC0, [8, 0, 16, 0, 16, 3, 1, 0x11, 0, 2, 0x22, 0, 3, 0x11, 0]),
                                                           Self.segment(0xDA, [3, 1, 0x00, 2, 0x00, 3, 0x00, 0, 63, 0])])),
            ("DQT com zero", Self.jpeg([Self.segment(0xDB, [0x00, 0] + [UInt8](repeating: 1, count: 63)), Self.frame, Self.huffman(0x00), Self.huffman(0x10), Self.scan])),
        ]
        for (name, file) in cases { #expect(StrictImage.sanitize(file) == nil, "\(name)") }
        // Rodada 4: reinicio sem o DRI ou fora da ordem, varredura sem dado e componentes fora da ordem do quadro.
        let head = [UInt8]([0xFF, 0xD8]) + (tables + [Self.frame]).flatMap { $0 }
        #expect(StrictImage.sanitize(Data(head + Self.scan + [0x12, 0xFF, 0xD0, 0x34, 0xFF, 0xD9])) == nil)
        let withDRI = [UInt8]([0xFF, 0xD8]) + (tables + [Self.frame, Self.segment(0xDD, [0, 4])]).flatMap { $0 }
        #expect(StrictImage.sanitize(Data(withDRI + Self.scan + [0x12, 0xFF, 0xD3, 0x34, 0xFF, 0xD9])) == nil)
        #expect(StrictImage.sanitize(Data(head + Self.scan + [0xFF, 0xD9])) == nil)
        let threeFrame = Self.segment(0xC0, [8, 0, 16, 0, 16, 3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0])
        #expect(StrictImage.sanitize(Self.jpeg(tables + [threeFrame, Self.segment(0xDA, [3, 2, 0x00, 1, 0x00, 3, 0x00, 0, 63, 0])])) == nil)
        // Rodada 5: o RGB da Adobe (APP14 com a transformacao 0) e tres componentes recusa; com a 1 (YCbCr), passa.
        let adobeRGB = Self.segment(0xEE, Array("Adobe".utf8) + [0, 100, 0, 0, 0, 0, 0])
        let adobeYCC = Self.segment(0xEE, Array("Adobe".utf8) + [0, 100, 0, 0, 0, 0, 1])
        #expect(StrictImage.sanitize(Self.jpeg([adobeRGB] + tables + [threeFrame, Self.segment(0xDA, [3, 1, 0x00, 2, 0x00, 3, 0x00, 0, 63, 0])])) == nil)
        #expect(StrictImage.sanitize(Self.jpeg([adobeYCC] + tables + [threeFrame, Self.segment(0xDA, [3, 1, 0x00, 2, 0x00, 3, 0x00, 0, 63, 0])])) != nil)
        // O AC com tamanho zero que nao e o fim de bloco nem a corrida de 16.
        #expect(StrictImage.sanitize(Self.jpeg([Self.quant, Self.frame, Self.huffman(0x00), Self.segment(0xC4, [0x10, 1] + [UInt8](repeating: 0, count: 15) + [0x50]), Self.scan])) == nil)
        // Sem o EOI, ou com um marcador no meio dos dados, recusa.
        #expect(StrictImage.sanitize(Data([0xFF, 0xD8] + tables.flatMap { $0 } + Self.frame + Self.scan + Self.pixels)) == nil)
        #expect(StrictImage.sanitize(Data([0xFF, 0xD8] + tables.flatMap { $0 } + Self.frame + Self.scan + [0x12, 0xFF, 0xC4, 0xFF, 0xD9])) == nil)
    }

    @Test("Outro formato e arquivo grande demais recusam")
    func otherFormats() {
        #expect(StrictImage.sanitize(Data("GIF89a".utf8)) == nil)
        #expect(StrictImage.sanitize(Data([0x52, 0x49, 0x46, 0x46])) == nil)
        #expect(StrictImage.sanitize(Data(StrictImage.pngSignature + [UInt8](repeating: 0, count: StrictImage.maxBytes))) == nil)
    }
}
