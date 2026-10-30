import Foundation

/// Sorteios fora de segredo (o sal do aviso de recebimento, a ordem e o atraso das consultas, o
/// endereco da cotacao), todos pela mesma fonte do resto do app: o SecRandomCopyBytes, via
/// `SecureBytes.random`. Sem ela, nenhum sorteio sai previsivel: a funcao falha.
public enum SecureRandom {
    /// 8 bytes sorteados.
    public static func uint64() throws -> UInt64 {
        let bytes = try SecureBytes.random(count: 8).withUnsafeBytes { Array($0) }
        return bytes.reduce(0) { $0 << 8 | UInt64($1) }
    }

    /// `count` bytes sorteados.
    public static func bytes(_ count: Int) throws -> [UInt8] {
        try SecureBytes.random(count: count).withUnsafeBytes { Array($0) }
    }

    /// Um indice de 0 ate `limit - 1`, sem vies.
    public static func index(below limit: Int) throws -> Int {
        precondition(limit > 0)
        let bound = UInt64(limit)
        let ceiling = UInt64.max - (UInt64.max % bound)
        while true {
            let value = try uint64()
            if value < ceiling { return Int(value % bound) }
        }
    }

    /// A lista em ordem sorteada (Fisher-Yates).
    public static func mixed<T>(_ items: [T]) throws -> [T] {
        var out = items
        guard out.count > 1 else { return out }
        for position in stride(from: out.count - 1, to: 0, by: -1) {
            out.swapAt(position, try index(below: position + 1))
        }
        return out
    }
}
