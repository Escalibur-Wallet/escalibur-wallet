import EscaliburChains
import EscaliburCore
import Foundation
import Testing
@testable import EscaliburNetwork

/// SPV do Bitcoin com dados reais da rede: a transacao a4ae7ff9... na posicao 1 do bloco
/// 972.600 e os seis cabecalhos a partir dele (mempool.space, 22/10/2026).
@Suite("Bitcoin: prova de inclusao (SPV)")
struct BitcoinSPVTests {
    static let txid = "a4ae7ff9e6f1c5070cd1838fc00f35c068929d8877451df651b5bb20d97def6a"
    static let position: UInt32 = 1
    static let branch = [
            "8f3068750a53d4375c2a8b390b39c97f2d6e822ba1f79eb62a228fbab4a2e20d",
            "63925e4d9b54a9476a1aff3c7aacca30050ab93c0477a265a8de5bb6bee5460f",
            "e1bb2bf5a01d6844b33e83935ac631840795c69f527a34f17af8583c3010a8bb",
            "d0c1414a5b604b95b63b75396e1792551ab3bd9a2cc8a2c5a7b9311ca1eeb165",
            "d703cc371e86bc110bffe53c9b76ec76a32a1dcfead62488b58f051fb71dea5d",
            "a3054cc13675ca519c8e2c2f10886fea4aeb16833fbaa8e8a21abe3026aee317",
            "d6ad5876aae4d4e808a6b05685b4c195d4fbc331ece379be13c25194f64ea2e5",
            "d7359ffca97772fafc46a4790f001d6d4961631fff7b9fcb2e1904c920f9aade",
            "eed84b4f17b19c8ba8c06edc364f98f849247d90ca402469ad41af64db3377b1",
            "557381048433c367a723fad715720279ba02e6908e815342007b11e2a5bcafba",
            "34a39dec89b99dbbd0775c5c235802a072ef0ced1961934b87247864606a6b70",
            "4b2d5b2cd6f8b7418ee070aac7781c697880614ce90e9854a2835afb8135ad22",
    ]
    /// (altura, hash, cabecalho)
    static let headers: [(UInt32, String, String)] = [
            (972600, "000000000000000000019aafc3a7e598deaba9c79374e09d9c65ea57710d21eb", "00c0bc221c6f371bc22649111d192db28af50a2e6c4f06358f2d01000000000000000000dd3ce8f1f970f2d830eca3c10f289c80798aac3a33f0550023d8a34137ae393d2cd9d96a9300021728582d4f"),
            (972601, "0000000000000000000102e3eba1c872c56dd491a3b830bfab52b4d69f5b1466", "00200220eb210d7157ea659c9de07493c7a9abde98e5a7c3af9a0100000000000000000059c3c11c1a758a290f9e00bad79fad91a41d6c033a0bfbc585121ea71df2468118dfd96a9300021709bbd728"),
            (972602, "00000000000000000000fef7e260f59a1583d7c69609b5622f34b2a0c129758e", "0060042066145b9fd6b452abbf30b8a391d46dc572c8a1ebe302010000000000000000004c5e39ad07895d93859730977b600b2e9b884934b9a886ab5e80a4541d0b21b76cdfd96a93000217131118f5"),
            (972603, "00000000000000000000a392fa2a2c7cec8a41bcf2a108a20fe096d0d17db32f", "0020f8388e7529c1a0b2342f62b50996c6d783159af560e2f7fe000000000000000000004ebdca10b93f780f677880f3c4f55deda76ace14af066db559655dea607ea266ece1d96a930002176cefe415"),
            (972604, "00000000000000000000385443418c6287a304319f811f54e1526c93f8d06e52", "002004202fb37dd1d096e00fa208a1f2bc418aec7c2c2afa92a300000000000000000000127bd9a1cbbe7ba5152c40b1b4b70b979a464092806567283807d2e63f9a64574be4d96a93000217c1da9a57"),
            (972605, "00000000000000000000c0c197aec55ccc5581cbfde2b0b12efaf2be896d4683", "00c0982c526ed0f8936c52e1541f819f3104a387628c4143543800000000000000000000b337c7fc8f36916d0d488bf47c313c72f5f40fcf48dd6573a10f7a21b7c5ef52ece4d96a93000217f4cb1e3b"),
    ]

    static func header(_ index: Int) throws -> BitcoinSPV.Header {
        try BitcoinSPV.Header(raw: try #require(Hex.decode(headers[index].2)))
    }

    @Test("A raiz de Merkle do caminho bate com a do cabecalho, e o cabecalho tem trabalho")
    func realProof() throws {
        let txid = try #require(UTXOTxID(hex: Self.txid))
        let branch = try Self.branch.map { try BitcoinSPV.internalHash(hex: $0) }
        let block = try Self.header(0)
        #expect(try BitcoinSPV.merkleRoot(txid: txid, branch: branch, position: Self.position) == block.merkleRoot)
        #expect(block.hash == (try BitcoinSPV.internalHash(hex: Self.headers[0].1)))
        #expect(BitcoinSPV.hasWork(block))
        for index in 1..<Self.headers.count {
            let header = try Self.header(index)
            #expect(BitcoinSPV.hasWork(header))
            #expect(header.previous == (try Self.header(index - 1)).hash)
        }
    }

    @Test("Caminho adulterado, posicao trocada ou outro txid nao chegam a raiz")
    func tamperedProof() throws {
        let txid = try #require(UTXOTxID(hex: Self.txid))
        var branch = try Self.branch.map { try BitcoinSPV.internalHash(hex: $0) }
        let root = try Self.header(0).merkleRoot
        #expect(try BitcoinSPV.merkleRoot(txid: txid, branch: branch, position: Self.position + 2) != root)
        let other = try #require(UTXOTxID(hex: String(repeating: "ab", count: 32)))
        #expect(try BitcoinSPV.merkleRoot(txid: other, branch: branch, position: Self.position) != root)
        branch[3][0] ^= 1
        #expect(try BitcoinSPV.merkleRoot(txid: txid, branch: branch, position: Self.position) != root)
        // Posicao alem do tamanho do caminho e malformada, nao "outra folha".
        #expect(throws: BitcoinSPV.Failure.malformed) {
            try BitcoinSPV.merkleRoot(txid: txid, branch: Array(branch.prefix(2)), position: 9)
        }
    }

    @Test("Sem trabalho: hash acima do alvo, ou alvo mais facil que o piso")
    func weakWork() throws {
        var raw = try Self.header(0).raw
        raw[76] ^= 0xff  // outro nonce: o hash deixa de caber no alvo
        #expect(!BitcoinSPV.hasWork(try BitcoinSPV.Header(raw: raw)))
        // Alvo facil (o do bloco genesis) e recusado pelo piso, mesmo com o hash dentro dele.
        var easy = try Self.header(0).raw
        easy[72] = 0xff; easy[73] = 0xff; easy[74] = 0x00; easy[75] = 0x1d
        #expect(!BitcoinSPV.hasWork(try BitcoinSPV.Header(raw: easy)))
        #expect(BitcoinSPV.target(bits: 0x1d00_ffff) != nil)
        #expect(BitcoinSPV.target(bits: 0x0480_0000) == nil)
        #expect(throws: BitcoinSPV.Failure.malformed) { try BitcoinSPV.Header(raw: [0, 1, 2]) }
    }
}
