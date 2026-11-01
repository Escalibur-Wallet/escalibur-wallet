import EscaliburCore
import Testing
@testable import EscaliburChains

/// O endereco proprio de outra rede com o mesmo formato e recusado como destino (revisao de blockchain
/// de 26/10/2026): o Aptos colado na Sui, e o hex sem 0x na conta implicita da NEAR.
@Suite("Endereco proprio de outra rede com o mesmo formato")
struct CrossNetworkSelfTests {
    let aptosHex = "00a1b2c3d4e5f60718293a4b5c6d7e8f9011223344556677889900aabbccddee"
    let suiHex = "5f2e1d0c9b8a79685746352413021f1e2d3c4b5a69788796a5b4c3d2e1f00112"

    func account(_ chainID: String, _ address: String) -> DerivedAccount {
        DerivedAccount(chainID: chainID, path: DerivationPath(components: []), address: address, publicKey: [], accountXPub: nil)
    }

    var own: [DerivedAccount] { [account("aptos", "0x" + aptosHex), account("sui", "0x" + suiHex)] }

    @Test("O Aptos do dono na Sui, e o Sui do dono na Aptos, sao recusados")
    func suiAndAptos() throws {
        let sui = try #require(Chain.find("sui")), aptos = try #require(Chain.find("aptos"))
        #expect(CrossNetworkSelf.network(of: "0x" + aptosHex, on: sui, own: own)?.id == "aptos")
        #expect(CrossNetworkSelf.network(of: "0x" + suiHex.uppercased(), on: aptos, own: own)?.id == "sui")
        // A Aptos pode escrever sem os zeros a esquerda: e o mesmo endereco.
        #expect(CrossNetworkSelf.network(of: "0x" + String(aptosHex.dropFirst(2)), on: sui, own: own)?.id == "aptos")
    }

    @Test("Na NEAR, o hex sem 0x de uma carteira Sui ou Aptos e recusado")
    func near() throws {
        let near = try #require(Chain.find("near"))
        #expect(CrossNetworkSelf.network(of: aptosHex, on: near, own: own)?.id == "aptos")
    }

    @Test("O endereco da propria rede e o de um terceiro passam; EVM fica de fora")
    func passes() throws {
        let sui = try #require(Chain.find("sui")), ethereum = try #require(Chain.find("ethereum"))
        #expect(CrossNetworkSelf.network(of: "0x" + suiHex, on: sui, own: own) == nil)
        #expect(CrossNetworkSelf.network(of: "0x" + String(repeating: "ab", count: 32), on: sui, own: own) == nil)
        #expect(CrossNetworkSelf.network(of: "0x" + aptosHex, on: ethereum, own: own) == nil)
    }

    @Test("Conta implicita da NEAR: ponto da curva passa, o que nao e ponto e recusado")
    func nearOffCurve() throws {
        // y pequeno em little-endian: procura um que seja ponto e um que nao seja, sem chutar.
        func encoded(_ y: UInt8) -> [UInt8] { [y] + [UInt8](repeating: 0, count: 31) }
        let off = try #require((2...200).map { UInt8($0) }.first { !Edwards25519.isOnCurve(encoded($0)) })
        let on = try #require((2...200).map { UInt8($0) }.first { Edwards25519.isOnCurve(encoded($0)) })
        if case .success = NEARAccountID.parse(Hex.encode(encoded(off))) {
            Issue.record("64 hex fora da curva viraram conta implicita")
        }
        if case .failure = NEARAccountID.parse(Hex.encode(encoded(on))) {
            Issue.record("um ponto da curva foi recusado")
        }
    }
}
