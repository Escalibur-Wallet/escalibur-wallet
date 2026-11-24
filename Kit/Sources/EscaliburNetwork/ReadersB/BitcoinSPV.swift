import EscaliburChains
import EscaliburCore
import Foundation

/// A prova de que uma transacao Bitcoin ou Litecoin esta num bloco minerado de verdade (SPV), sem
/// acreditar no provedor (docs/seguranca.md §5.5).
///
/// O provedor diz em que bloco a transacao entrou e da o caminho de Merkle ate a raiz. O
/// app confere: a raiz calculada bate com a do cabecalho; o cabecalho tem o trabalho que o
/// proprio alvo exige, e o alvo nunca e mais facil que `easiestBits`; os cabecalhos
/// seguintes, ate `depth`, encadeiam e tambem tem trabalho. Inventar uma moeda
/// "confirmada" passa a custar mineracao de verdade. Quando um provedor de outro dono
/// responde, o bloco daquela altura tem de ser o mesmo nos dois.
public enum BitcoinSPV {
    /// O alvo mais facil aceito. Bitcoin: 16 vezes o do bloco 972.695 (22/10/2026,
    /// dificuldade 1,4 x 10^14). Litecoin: 16 vezes o do bloco 3.199.922 (22/10/2026). A
    /// dificuldade das duas nunca caiu perto disso, e um cabecalho falso com esse alvo ainda
    /// custa horas de um pool grande, cada um.
    static func easiestBits(for chain: Chain) -> UInt32 {
        chain == .litecoin ? 0x1A02_ED12 : 0x1720_0930
    }
    /// Quantos cabecalhos, contando o do bloco da transacao, o app confere.
    static let depth: UInt32 = 6

    public enum Failure: Error, Equatable, Sendable {
        /// Nenhum provedor entregou a prova agora (fora do ar, limite). Nao e prova falsa.
        case unavailable
        /// Resposta que nao tem o formato de uma prova.
        case malformed
        /// A raiz de Merkle nao bate: a transacao nao esta no bloco dito.
        case notInBlock
        /// Cabecalho sem o trabalho que o alvo exige, ou com alvo facil demais.
        case weakWork
        /// Os cabecalhos seguintes nao encadeiam.
        case brokenChain
        /// Dois donos dizem blocos diferentes na mesma altura.
        case providersDisagree
    }

    /// Um cabecalho de 80 bytes.
    struct Header: Equatable, Sendable {
        let raw: [UInt8]

        init(raw: [UInt8]) throws {
            guard raw.count == 80 else { throw Failure.malformed }
            self.raw = raw
        }

        /// Na ordem interna, a do campo "anterior" do cabecalho seguinte.
        var hash: [UInt8] { Hash.sha256d(raw) }
        var previous: [UInt8] { Array(raw[4..<36]) }
        var merkleRoot: [UInt8] { Array(raw[36..<68]) }
        var bits: UInt32 { UInt32(raw[72]) | UInt32(raw[73]) << 8 | UInt32(raw[74]) << 16 | UInt32(raw[75]) << 24 }
    }

    /// O alvo compacto em 32 bytes big-endian. Nil para negativo, zero ou expoente fora
    /// do que o Bitcoin usa.
    static func target(bits: UInt32) -> [UInt8]? {
        let exponent = Int(bits >> 24), mantissa = bits & 0x00ff_ffff
        guard mantissa != 0, mantissa & 0x0080_0000 == 0, (3...32).contains(exponent) else { return nil }
        var out = [UInt8](repeating: 0, count: 32)
        let start = 32 - exponent
        out[start] = UInt8(mantissa >> 16)
        out[start + 1] = UInt8((mantissa >> 8) & 0xff)
        out[start + 2] = UInt8(mantissa & 0xff)
        return out
    }

    /// O hash de trabalho do cabecalho cabe no alvo dele, e o alvo dele nao e mais facil que
    /// o piso da rede. No Litecoin o trabalho e medido pelo scrypt; o id do bloco continua o
    /// SHA-256 duplo.
    static func hasWork(_ header: Header, chain: Chain = .bitcoin) -> Bool {
        guard let own = target(bits: header.bits), let floor = target(bits: easiestBits(for: chain)) else { return false }
        let work = chain == .litecoin ? LitecoinScrypt.hash(header.raw) : header.hash
        return atMost(own, floor) && atMost(Array(work.reversed()), own)
    }

    private static func atMost(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool { !rhs.lexicographicallyPrecedes(lhs) }

    /// A raiz de Merkle a partir do txid e do caminho (cada irmao na ordem interna).
    static func merkleRoot(txid: UTXOTxID, branch: [[UInt8]], position: UInt32) throws -> [UInt8] {
        guard branch.count <= 32, branch.allSatisfy({ $0.count == 32 }),
              branch.count == 32 || UInt64(position) >> UInt64(branch.count) == 0
        else { throw Failure.malformed }
        var node = txid.bytes
        var index = position
        for sibling in branch {
            node = index & 1 == 0 ? Hash.sha256d(node + sibling) : Hash.sha256d(sibling + node)
            index >>= 1
        }
        return node
    }

    /// Hash de bloco no hex de explorador (invertido) para a ordem interna.
    static func internalHash(hex: String) throws -> [UInt8] {
        guard hex.count == 64, let bytes = Hex.decode(hex), bytes.count == 32 else { throw Failure.malformed }
        return bytes.reversed()
    }
}

/// Os cabecalhos ja conferidos nesta sessao, por rede e altura: moedas do mesmo trecho da
/// cadeia nao pedem de novo o que ja foi provado.
actor BitcoinHeaderCache {
    static let shared = BitcoinHeaderCache()
    private struct Key: Hashable { let chain: Chain; let height: UInt32 }
    private var headers: [Key: BitcoinSPV.Header] = [:]

    func header(_ chain: Chain, at height: UInt32) -> BitcoinSPV.Header? { headers[Key(chain: chain, height: height)] }

    func store(_ header: BitcoinSPV.Header, _ chain: Chain, at height: UInt32) {
        if headers.count > 4_000 { headers.removeAll() }
        headers[Key(chain: chain, height: height)] = header
    }
}
