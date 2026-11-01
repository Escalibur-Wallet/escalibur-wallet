import EscaliburCore

/// O scrypt com os parametros da prova de trabalho do Litecoin (N = 1024, r = 1, p = 1, 32
/// bytes, o cabecalho como senha e como sal), para conferir o trabalho de um cabecalho na
/// prova de inclusao (`BitcoinSPV`). O id do bloco continua sendo o SHA-256 duplo; so o
/// trabalho e medido por este hash.
enum LitecoinScrypt {
    static func hash(_ header: [UInt8]) -> [UInt8] {
        let n = 1024
        var x = words(pbkdf2(header, salt: header, length: 128))
        var v = [UInt32](repeating: 0, count: 32 * n)
        for i in 0..<n {
            for k in 0..<32 { v[i * 32 + k] = x[k] }
            blockMix(&x)
        }
        for _ in 0..<n {
            let j = Int(x[16] & UInt32(n - 1))
            for k in 0..<32 { x[k] ^= v[j * 32 + k] }
            blockMix(&x)
        }
        return pbkdf2(header, salt: bytes(x), length: 32)
    }

    /// PBKDF2-HMAC-SHA256 com uma iteracao, o que o scrypt pede nas duas pontas.
    private static func pbkdf2(_ password: [UInt8], salt: [UInt8], length: Int) -> [UInt8] {
        var out: [UInt8] = []
        var block: UInt32 = 1
        while out.count < length {
            let index = [UInt8(block >> 24), UInt8((block >> 16) & 0xff), UInt8((block >> 8) & 0xff), UInt8(block & 0xff)]
            out += Hash.hmacSHA256(key: password, data: salt + index)
            block += 1
        }
        return Array(out.prefix(length))
    }

    /// BlockMix com r = 1: dois blocos de 64 bytes passando pelo Salsa20/8.
    private static func blockMix(_ b: inout [UInt32]) {
        var x = Array(b[16..<32])
        for i in 0..<16 { x[i] ^= b[i] }
        salsa8(&x)
        let first = x
        for i in 0..<16 { x[i] ^= b[16 + i] }
        salsa8(&x)
        b = first + x
    }

    private static func salsa8(_ b: inout [UInt32]) {
        var x = b
        @inline(__always) func r(_ value: UInt32, _ shift: UInt32) -> UInt32 { (value << shift) | (value >> (32 - shift)) }
        for _ in 0..<4 {
            x[4] ^= r(x[0] &+ x[12], 7); x[8] ^= r(x[4] &+ x[0], 9); x[12] ^= r(x[8] &+ x[4], 13); x[0] ^= r(x[12] &+ x[8], 18)
            x[9] ^= r(x[5] &+ x[1], 7); x[13] ^= r(x[9] &+ x[5], 9); x[1] ^= r(x[13] &+ x[9], 13); x[5] ^= r(x[1] &+ x[13], 18)
            x[14] ^= r(x[10] &+ x[6], 7); x[2] ^= r(x[14] &+ x[10], 9); x[6] ^= r(x[2] &+ x[14], 13); x[10] ^= r(x[6] &+ x[2], 18)
            x[3] ^= r(x[15] &+ x[11], 7); x[7] ^= r(x[3] &+ x[15], 9); x[11] ^= r(x[7] &+ x[3], 13); x[15] ^= r(x[11] &+ x[7], 18)
            x[1] ^= r(x[0] &+ x[3], 7); x[2] ^= r(x[1] &+ x[0], 9); x[3] ^= r(x[2] &+ x[1], 13); x[0] ^= r(x[3] &+ x[2], 18)
            x[6] ^= r(x[5] &+ x[4], 7); x[7] ^= r(x[6] &+ x[5], 9); x[4] ^= r(x[7] &+ x[6], 13); x[5] ^= r(x[4] &+ x[7], 18)
            x[11] ^= r(x[10] &+ x[9], 7); x[8] ^= r(x[11] &+ x[10], 9); x[9] ^= r(x[8] &+ x[11], 13); x[10] ^= r(x[9] &+ x[8], 18)
            x[12] ^= r(x[15] &+ x[14], 7); x[13] ^= r(x[12] &+ x[15], 9); x[14] ^= r(x[13] &+ x[12], 13); x[15] ^= r(x[14] &+ x[13], 18)
        }
        for i in 0..<16 { b[i] = b[i] &+ x[i] }
    }

    private static func words(_ bytes: [UInt8]) -> [UInt32] {
        stride(from: 0, to: bytes.count, by: 4).map { (i: Int) -> UInt32 in
            let low = UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8
            let high = UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
            return low | high
        }
    }

    private static func bytes(_ words: [UInt32]) -> [UInt8] {
        words.flatMap { [UInt8($0 & 0xff), UInt8(($0 >> 8) & 0xff), UInt8(($0 >> 16) & 0xff), UInt8($0 >> 24)] }
    }
}
