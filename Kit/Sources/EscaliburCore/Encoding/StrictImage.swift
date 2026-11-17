import Foundation

/// O que passa de uma logo baixada da internet para o ImageIO, que roda no mesmo processo que assina (auditoria 8,
/// 14/11/2026). O ImageIO le o cabecalho, o EXIF, o XMP e o perfil de cor de qualquer arquivo antes de qualquer
/// conferencia nossa, e falhas nele ja foram usadas contra alvos escolhidos (o WebP de 2023, o CVE-2025-43300). Aqui o
/// arquivo e lido em Swift e montado de novo so com o que desenha a imagem:
/// - PNG: o IHDR (8 bits, sem entrelacamento, ate `maxSide`), o PLTE e o tRNS da paleta, os IDAT seguidos e o IEND, cada
///   bloco com o CRC conferido. Os blocos auxiliares (texto, EXIF, perfil de cor, gama) ficam de fora; outro bloco critico
///   recusa o arquivo. O PLTE so nos tipos de cor que o aceitam, e um tRNS so, do tamanho que o tipo de cor pede.
/// - JPEG: so o basico (SOF0 ou SOF1, 8 bits), com as tabelas (DQT, DHT, DRI), um SOS e os dados ate o EOI. Os segmentos
///   APPn (EXIF, XMP, ICC) e os comentarios ficam de fora; o progressivo e o resto recusam. Cada tabela e o cabecalho do
///   quadro e da varredura tem o tamanho exato dos campos, e a varredura so usa componentes e tabelas ja definidos.
/// Recusado, a moeda fica com as letras do simbolo. No nucleo desde a rodada 2 da auditoria 8, para ter testes no `swift test`
/// (no app, nada conferia que ele ainda recusava alguma coisa); quem decodifica continua sendo o app, pelo ImageIO. Na rodada 1 da auditoria 8, uma imagem com o SOF sem componentes, um DHT
/// de 1 byte ou dois tRNS passava para o ImageIO; agora cada campo e conferido antes.
public enum StrictImage {
    public static let maxBytes = 512 * 1024
    public static let maxSide: UInt32 = 2048

    public static func sanitize(_ data: Data) -> Data? {
        guard data.count <= maxBytes else { return nil }
        let bytes = [UInt8](data)
        if bytes.starts(with: pngSignature) { return png(bytes).map { Data($0) } }
        if bytes.starts(with: [0xFF, 0xD8]) { return jpeg(bytes).map { Data($0) } }
        return nil
    }

    // MARK: PNG

    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static func png(_ bytes: [UInt8]) -> [UInt8]? {
        var out = pngSignature
        var index = pngSignature.count
        var sawHeader = false, sawPalette = false, sawTransparency = false, inData = false, endedData = false
        var colorType: UInt8 = 0, paletteEntries = 0
        while index + 12 <= bytes.count {
            let length = Int(be32(bytes, index))
            guard length <= bytes.count, index + 12 + length <= bytes.count else { return nil }
            let type = Array(bytes[(index + 4)..<(index + 8)])
            let body = Array(bytes[(index + 8)..<(index + 8 + length)])
            let crc = be32(bytes, index + 8 + length)
            guard PNGCRC32.checksum(type + body) == crc else { return nil }
            let chunk = Array(bytes[index..<(index + 12 + length)])
            index += 12 + length
            guard let name = String(bytes: type, encoding: .ascii) else { return nil }
            if name != "IDAT", inData { inData = false; endedData = true }
            switch name {
            case "IHDR":
                guard !sawHeader, out.count == pngSignature.count, length == 13 else { return nil }
                let width = be32(body, 0), height = be32(body, 4)
                guard width > 0, height > 0, width <= maxSide, height <= maxSide else { return nil }
                // Profundidade 8; tipos de cor do PNG; compressao, filtro e entrelacamento 0.
                guard body[8] == 8, [0, 2, 3, 4, 6].contains(body[9]), body[10] == 0, body[11] == 0, body[12] == 0 else { return nil }
                colorType = body[9]
                sawHeader = true
                out += chunk
            case "PLTE":
                // So nos tipos 2, 3 e 6, antes do tRNS e dos dados, de 1 a 256 cores.
                guard sawHeader, [2, 3, 6].contains(colorType), !sawPalette, !sawTransparency, !inData, !endedData,
                      length % 3 == 0, length > 0, length <= 768 else { return nil }
                sawPalette = true
                paletteEntries = length / 3
                out += chunk
            case "tRNS":
                // Um so: 2 bytes no cinza, 6 no colorido, ate uma entrada por cor na paleta; nos tipos com alfa, nenhum.
                guard sawHeader, !sawTransparency, !inData, !endedData else { return nil }
                switch colorType {
                case 0: guard length == 2 else { return nil }
                case 2: guard length == 6 else { return nil }
                case 3: guard sawPalette, length > 0, length <= paletteEntries else { return nil }
                default: return nil
                }
                sawTransparency = true
                out += chunk
            case "IDAT":
                guard sawHeader, !endedData, colorType != 3 || sawPalette else { return nil }
                // O primeiro abre com o cabecalho do zlib: deflate, janela ate 32 KB, sem dicionario e a soma conferida
                // (rodada 3 da auditoria 8).
                if !inData {
                    guard body.count >= 2, body[0] & 0x0F == 8, body[0] >> 4 <= 7, body[1] & 0x20 == 0,
                          (UInt16(body[0]) << 8 | UInt16(body[1])) % 31 == 0 else { return nil }
                }
                inData = true
                out += chunk
            case "IEND":
                guard sawHeader, endedData || inData, length == 0 else { return nil }
                out += chunk
                return out
            default:
                // Bloco auxiliar (primeira letra minuscula): fica de fora. Critico desconhecido: recusa.
                guard let first = type.first, first >= 0x61, first <= 0x7A else { return nil }
            }
        }
        return nil
    }

    // MARK: JPEG

    static func jpeg(_ bytes: [UInt8]) -> [UInt8]? {
        var out: [UInt8] = [0xFF, 0xD8]
        var index = 2
        var sawFrame = false
        // O intervalo de reinicio do DRI: sem ele, nenhum marcador de reinicio nos dados (rodada 4 da auditoria 8).
        var restartInterval = 0
        // A transformacao de cor do APP14 da Adobe: 0 com tres componentes e RGB sem YCbCr, e sem o APP14, que fica de fora, o
        // ImageIO leria as cores trocadas (rodada 5 da auditoria 8).
        var adobeTransform: UInt8?
        // Os componentes do quadro (id e tabela de quantizacao) e as tabelas ja definidas, para conferir a varredura.
        var components: [(id: UInt8, quant: UInt8)] = []
        var quantTables = Set<UInt8>(), huffmanTables = Set<UInt8>()
        while index + 4 <= bytes.count {
            guard bytes[index] == 0xFF else { return nil }
            let marker = bytes[index + 1]
            if marker == 0xFF { index += 1; continue }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2, index + 2 + length <= bytes.count else { return nil }
            let segment = Array(bytes[index..<(index + 2 + length)])
            switch marker {
            case 0xC0, 0xC1:
                // Basico ou estendido, 8 bits, ate `maxSide`, cinza ou 3 componentes, com o tamanho exato dos componentes.
                guard !sawFrame, length >= 8, segment[4] == 8 else { return nil }
                let height = UInt32(segment[5]) << 8 | UInt32(segment[6]), width = UInt32(segment[7]) << 8 | UInt32(segment[8])
                guard width > 0, height > 0, width <= maxSide, height <= maxSide else { return nil }
                let count = Int(segment[9])
                guard count == 1 || count == 3, length == 8 + 3 * count else { return nil }
                var blocks = 0
                var samplings: [UInt8] = []
                for offset in stride(from: 10, to: 10 + 3 * count, by: 3) {
                    let id = segment[offset], sampling = segment[offset + 1], quant = segment[offset + 2]
                    guard (1...2).contains(sampling >> 4), (1...2).contains(sampling & 0x0F), quant <= 3,
                          !components.contains(where: { $0.id == id }) else { return nil }
                    blocks += Int(sampling >> 4) * Int(sampling & 0x0F)
                    samplings.append(sampling)
                    components.append((id, quant))
                }
                // Com tres componentes, a amostragem que os codificadores geram: a luma em 4:4:4, 4:2:2, 4:4:0 ou 4:2:0 (rodada 5
                // da auditoria 8). Vale a proporcao, e nao o numero: o ffmpeg grava o 4:4:4 com 1x2 nos tres e o 4:2:2 com a luma
                // 2x2 e os cromas 1x2. Os dois cromas iguais, e a luma um multiplo deles em cada direcao (os fatores ja sao 1 ou 2,
                // e o MCU fica em ate 10 blocos) (rodada 6).
                if count == 3 {
                    let luma = samplings[0], chroma = samplings[1]
                    guard samplings[2] == chroma, (luma >> 4) % (chroma >> 4) == 0, (luma & 0x0F) % (chroma & 0x0F) == 0 else { return nil }
                }
                // Ate 10 blocos por MCU na varredura com mais de um componente (T.81, B.2.3; o libjpeg recusa mais) (rodada 4).
                guard count == 1 || blocks <= 10 else { return nil }
                sawFrame = true
                out += segment
            case 0xDB:
                // Tabelas de quantizacao de 8 bits (Pq 0), de 65 bytes cada, ids de 0 a 3.
                let tables = segment[4...]
                guard !tables.isEmpty, tables.count % 65 == 0 else { return nil }
                for start in stride(from: tables.startIndex, to: tables.endIndex, by: 65) {
                    let spec = tables[start]
                    // Os 64 valores de 1 a 255: zero nao e quantizacao (T.81, B.2.4.1; rodada 4).
                    guard spec >> 4 == 0, spec & 0x0F <= 3, !tables[(start + 1)..<(start + 65)].contains(0) else { return nil }
                    quantTables.insert(spec & 0x0F)
                }
                out += segment
            case 0xC4:
                // Tabelas de Huffman: classe 0 ou 1, id 0 ou 1, ate 256 simbolos, e o segmento acaba junto com a ultima.
                var at = 4
                guard at < segment.count else { return nil }
                while at < segment.count {
                    guard at + 17 <= segment.count else { return nil }
                    let spec = segment[at]
                    guard spec >> 4 <= 1, spec & 0x0F <= 1 else { return nil }
                    let counts = segment[(at + 1)..<(at + 17)].map(Int.init)
                    let symbols = counts.reduce(0, +)
                    guard symbols > 0, symbols <= 256, at + 17 + symbols <= segment.count else { return nil }
                    // Uma tabela possivel (a desigualdade de Kraft, como o jpeg_make_d_derived_tbl do libjpeg: sobra sempre o
                    // codigo de uns), simbolos sem repetir, o DC ate 11 e o AC com o tamanho ate 10 (rodada 3 da auditoria 8).
                    var code = 0
                    for (index, count) in counts.enumerated() {
                        code += count
                        guard code < 1 << (index + 1) else { return nil }
                        code <<= 1
                    }
                    let values = segment[(at + 17)..<(at + 17 + symbols)]
                    guard Set(values).count == values.count,
                          values.allSatisfy({ spec >> 4 == 0 ? $0 <= 11 : $0 & 0x0F <= 10 && ($0 & 0x0F != 0 || $0 == 0x00 || $0 == 0xF0) })
                    else { return nil }
                    huffmanTables.insert(spec)
                    at += 17 + symbols
                }
                out += segment
            case 0xDD:
                guard length == 4 else { return nil }
                restartInterval = Int(segment[4]) << 8 | Int(segment[5])
                out += segment
            case 0xE0...0xEF, 0xFE:
                if marker == 0xEE, length >= 14, Array(segment[4..<9]) == Array("Adobe".utf8) { adobeTransform = segment[15] }
            case 0xDA:
                // Uma varredura sequencial: componentes do quadro, sem repetir, com as tabelas ja definidas.
                guard sawFrame, length >= 6 else { return nil }
                let count = Int(segment[4])
                // Uma varredura so, entao com todos os componentes do quadro (rodada 3 da auditoria 8).
                guard count == components.count, length == 6 + 2 * count else { return nil }
                guard !(components.count == 3 && adobeTransform == 0) else { return nil }
                var used = Set<UInt8>()
                for offset in stride(from: 5, to: 5 + 2 * count, by: 2) {
                    let id = segment[offset], tables = segment[offset + 1]
                    // Na ordem do quadro (T.81, B.2.3; rodada 4).
                    guard id == components[(offset - 5) / 2].id,
                          let component = components.first(where: { $0.id == id }), used.insert(id).inserted,
                          quantTables.contains(component.quant),
                          huffmanTables.contains(tables >> 4), huffmanTables.contains(0x10 | (tables & 0x0F)) else { return nil }
                }
                let tail = 5 + 2 * count
                guard segment[tail] == 0, segment[tail + 1] == 63, segment[tail + 2] == 0 else { return nil }
                // Os dados comprimidos vao ate o EOI: so o 0xFF00 de escape e os marcadores de reinicio no meio, estes so com o DRI
                // e na ordem, de 0 a 7 e de novo; e pelo menos um byte de dado (rodada 4 da auditoria 8).
                let start = index + 2 + length
                var end = start
                var restart: UInt8 = 0
                while end + 1 < bytes.count {
                    if bytes[end] == 0xFF {
                        let next = bytes[end + 1]
                        if next == 0xD9 {
                            guard end > start else { return nil }
                            return out + Array(bytes[index..<(end + 2)])
                        }
                        if (0xD0...0xD7).contains(next) {
                            guard restartInterval > 0, next == 0xD0 + restart else { return nil }
                            restart = (restart + 1) % 8
                        } else {
                            guard next == 0x00 else { return nil }
                        }
                    }
                    end += 1
                }
                return nil
            default:
                // Progressivo, aritmetico, hierarquico e o resto: recusa.
                return nil
            }
            index += 2 + length
        }
        return nil
    }

    static func be32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16 | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
    }
}

/// O CRC-32 do PNG (o do zlib, polinomio 0xEDB88320).
enum PNGCRC32 {
    static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 != 0 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
        return crc
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}
