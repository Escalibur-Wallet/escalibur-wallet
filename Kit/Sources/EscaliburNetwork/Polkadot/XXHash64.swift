import Foundation

/// O xxHash64 (semente 0), que o Substrate usa nas chaves dos mapas `Twox64Concat`: o `twox64` e o hash em little-endian.
/// So para montar a chave de leitura do armazenamento, nunca para conferir nada (o xxHash nao e criptografico).
/// Conferido com o prefixo de `System.Account` (`twox128`) e com os valores de referencia do algoritmo nos testes.
enum XXHash64 {
    private static let p1: UInt64 = 11_400_714_785_074_694_791
    private static let p2: UInt64 = 14_029_467_366_897_019_727
    private static let p3: UInt64 = 1_609_587_929_392_839_161
    private static let p4: UInt64 = 9_650_029_242_287_828_579
    private static let p5: UInt64 = 2_870_177_450_012_600_261

    static func twox64(_ data: [UInt8]) -> [UInt8] {
        littleEndian(hash(data, seed: 0))
    }

    static func twox128(_ data: [UInt8]) -> [UInt8] {
        littleEndian(hash(data, seed: 0)) + littleEndian(hash(data, seed: 1))
    }

    static func hash(_ data: [UInt8], seed: UInt64) -> UInt64 {
        var index = 0
        var h: UInt64
        if data.count >= 32 {
            var v1 = seed &+ p1 &+ p2, v2 = seed &+ p2, v3 = seed, v4 = seed &- p1
            while index + 32 <= data.count {
                v1 = round(v1, word(data, index)); v2 = round(v2, word(data, index + 8))
                v3 = round(v3, word(data, index + 16)); v4 = round(v4, word(data, index + 24))
                index += 32
            }
            h = rotate(v1, 1) &+ rotate(v2, 7) &+ rotate(v3, 12) &+ rotate(v4, 18)
            h = merge(h, v1); h = merge(h, v2); h = merge(h, v3); h = merge(h, v4)
        } else {
            h = seed &+ p5
        }
        h = h &+ UInt64(data.count)
        while index + 8 <= data.count {
            h ^= round(0, word(data, index))
            h = rotate(h, 27) &* p1 &+ p4
            index += 8
        }
        if index + 4 <= data.count {
            var half: UInt64 = 0
            for offset in 0..<4 { half |= UInt64(data[index + offset]) << (8 * UInt64(offset)) }
            h ^= half &* p1
            h = rotate(h, 23) &* p2 &+ p3
            index += 4
        }
        while index < data.count {
            h ^= UInt64(data[index]) &* p5
            h = rotate(h, 11) &* p1
            index += 1
        }
        h ^= h >> 33; h = h &* p2; h ^= h >> 29; h = h &* p3; h ^= h >> 32
        return h
    }

    private static func round(_ acc: UInt64, _ input: UInt64) -> UInt64 { rotate(acc &+ input &* p2, 31) &* p1 }
    private static func merge(_ acc: UInt64, _ value: UInt64) -> UInt64 { (acc ^ round(0, value)) &* p1 &+ p4 }
    private static func rotate(_ x: UInt64, _ r: UInt64) -> UInt64 { (x << r) | (x >> (64 - r)) }

    private static func word(_ data: [UInt8], _ index: Int) -> UInt64 {
        var value: UInt64 = 0
        for offset in 0..<8 { value |= UInt64(data[index + offset]) << (8 * UInt64(offset)) }
        return value
    }

    private static func littleEndian(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) } }
}
