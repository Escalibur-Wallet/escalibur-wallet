import EscaliburChains
import EscaliburCore
import Foundation
import Testing
@testable import EscaliburNetwork

/// SPV da Litecoin com dados reais da rede: a transacao 812eed7d... na posicao 1 do bloco
/// 3.199.905 e os seis cabecalhos a partir dele (litecoinspace.org, 22/10/2026). O trabalho e
/// o scrypt do cabecalho; o id do bloco, o SHA-256 duplo.
@Suite("Litecoin: prova de inclusao (SPV)")
struct LitecoinSPVTests {
    static let txid = "812eed7d52a8a83961582d90c797e8b3e9aed887424ee1ff1ac597db3a80591e"
    static let position: UInt32 = 1
    static let branch = [
            "1697fb16dc46e2f10bf36a35af6d317bf601bb8bb51ae0d8ccc7073dae2085fe",
            "3a64907f49ebd0b46d74ae7ab741365f32959acfca47a086af90779eb8c8699e",
            "d8b051c03e0ae627546d7116fbf19a0ffde466f4204e0f6cfdbd6bf4bf6c79fe",
            "700a3e1953e9f081a08b6510d1e419b8669b901a2215589d6eed87337437a581",
            "9c45d5a4da180698851cc9992ab96615ce062ed2894c322bc11364d2397093eb",
            "00fc5c83686fca692369a223122439ec2c3ef7a2350375cbe5cb50c5d9457d5a",
            "b23a698efb7444f17fb49042b916b954444a2c02ce494a9ec089e7e12166be41",
            "56fe9622dc14c61a9d85f1b125e97fe69832e18800ea86516097194a77179d4a",
            "aa7a0cc5f0497ca5b9386a2902d577662377c227da68e7d0fa96a3fce2cf66ea",
    ]
    /// (altura, hash, cabecalho)
    static let headers: [(UInt32, String, String)] = [
            (3199905, "7453227b985e155f8cf19f387bdabc1372db486b18bf8925a87f9678053ffc59", "14000020c713f7f11e2f7e9274e7885b590e481070a164d4ef8479d68e0a1b0da1f1f45634f3e585d2bb0fb137ca6f94f052f8468e9f66c2615a5a51cd2182c517316dba42bcda6a2fd12e1933386d6f"),
            (3199906, "872aa61dc08b72490a7fbd779462bdb8e76d5ce0fb3b8f2c645892d313d88919", "1400002059fc3f0578967fa82589bf186b48db7213bcda7b389ff18c5f155e987b22537405c4ee54f7a520c36a0800f9218bbe2e59fd8fd08ad7c999053da3f99c58ca5c5cbcda6a2fd12e190f6e67e8"),
            (3199907, "8d3f05907c17a85ab3d637245a0c64a7263da81f8ac0dd6041c857fb2ba50b3b", "000000201989d813d39258642c8f3bfbe05c6de7b8bd629477bd7f0a49728bc01da62a872182fd02e0d9303ac2addeae771dda9298608a2810c56e048c7a03a7bdeb23d440bdda6a2fd12e1970c19a60"),
            (3199908, "9c070ed951362cb95ea938248040b9d61b02f6c01594633fdaa3567d1e0280d1", "000000203b0ba52bfb57c84160ddc08a1fa83d26a7640c5a2437d6b35aa8177c90053f8d0eac2c8eb78bac2afee1a01a75428afb2b629e339f2eea0a7abf6eff606733d047bdda6a2fd12e19144e3924"),
            (3199909, "9d3de32919d4bac2cbef733fa87dc077fa7122781f57f33d7d6aa18b9468425d", "14000020d180021e7d56a3da3f639415c0f6021bd6b940802438a95eb92c3651d90e079ce1a27f14af3c0029930bc96dc121f111fd3afd2f46e9a1b403424410609b456ccfbdda6a2fd12e19d108c03a"),
            (3199910, "7ec45db0a77073df47b9e672f076356e7c2634d45a000b9db307b6b749c8ef16", "000000205d4268948ba16a7d3df3571f782271fa77c07da83f73efcbc2bad41929e33d9d63feef410b2ffb0eb9b2e133a103f9876fe8a81aa12630987d2bd4f4ef290f1d1cbeda6a2fd12e19280d3291"),
    ]

    static func header(_ index: Int) throws -> BitcoinSPV.Header {
        try BitcoinSPV.Header(raw: try #require(Hex.decode(headers[index].2)))
    }

    @Test("A raiz de Merkle bate, o scrypt de cada cabecalho cabe no alvo e eles encadeiam")
    func realProof() throws {
        let txid = try #require(UTXOTxID(hex: Self.txid))
        let branch = try Self.branch.map { try BitcoinSPV.internalHash(hex: $0) }
        let block = try Self.header(0)
        #expect(try BitcoinSPV.merkleRoot(txid: txid, branch: branch, position: Self.position) == block.merkleRoot)
        #expect(block.hash == (try BitcoinSPV.internalHash(hex: Self.headers[0].1)))
        for index in Self.headers.indices {
            let header = try Self.header(index)
            #expect(BitcoinSPV.hasWork(header, chain: .litecoin))
            if index > 0 { #expect(header.previous == (try Self.header(index - 1)).hash) }
        }
    }

    @Test("O trabalho da Litecoin e o scrypt: pelo SHA-256 duplo, ou com o piso do Bitcoin, nao passa")
    func workIsScrypt() throws {
        let block = try Self.header(0)
        // O id do bloco (SHA-256 duplo) nao cabe no alvo da Litecoin: so o scrypt cabe.
        #expect(!BitcoinSPV.hasWork(block, chain: .bitcoin))
        var raw = block.raw
        raw[76] ^= 0xff  // outro nonce: o scrypt deixa de caber no alvo
        #expect(!BitcoinSPV.hasWork(try BitcoinSPV.Header(raw: raw), chain: .litecoin))
        // Alvo facil (o do genesis da Litecoin) e recusado pelo piso.
        var easy = block.raw
        easy[72] = 0xf0; easy[73] = 0xff; easy[74] = 0x0f; easy[75] = 0x1e
        #expect(!BitcoinSPV.hasWork(try BitcoinSPV.Header(raw: easy), chain: .litecoin))
    }

    @Test("Caminho adulterado nao chega a raiz")
    func tamperedProof() throws {
        let txid = try #require(UTXOTxID(hex: Self.txid))
        var branch = try Self.branch.map { try BitcoinSPV.internalHash(hex: $0) }
        let root = try Self.header(0).merkleRoot
        branch[4][31] ^= 1
        #expect(try BitcoinSPV.merkleRoot(txid: txid, branch: branch, position: Self.position) != root)
    }

    @Test("O cache de cabecalhos separa as redes na mesma altura")
    func cacheByChain() async throws {
        let cache = BitcoinHeaderCache()
        try await cache.store(Self.header(0), .litecoin, at: 900_000)
        #expect(await cache.header(.bitcoin, at: 900_000) == nil)
        #expect(await cache.header(.litecoin, at: 900_000) == (try Self.header(0)))
    }
}
