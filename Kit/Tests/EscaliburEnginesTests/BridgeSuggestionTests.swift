import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Testing
@testable import EscaliburEngines

/// A ponte que a tela abre ja escolhida: a stablecoin que a carteira mais tem, da rede com mais
/// para a segunda.
@Suite("Ponte: a escolha ao abrir")
struct BridgeSuggestionTests {
    func holding(_ asset: BridgeAsset, _ chain: Chain, _ dollars: Int) throws -> Holding {
        let bridgeChain = try #require(BridgeAllowlist.chain(chain))
        let listed = try #require(asset.asset(on: bridgeChain))
        return Holding(asset: listed, amount: BigUInt(dollars) * BigUInt.power(of: 10, asset.decimals(on: bridgeChain)))
    }

    @Test("US$ 100 de USDT na Arbitrum e US$ 80 na BNB: Arbitrum para BNB, em USDT")
    func ownerExample() throws {
        let pick = BridgeSuggestion.pick(holdings: [try holding(.usdt, .arbitrum, 100), try holding(.usdt, .bnb, 80), try holding(.usdc, .base, 150)],
                                         currentTo: .base)
        #expect(pick == .init(from: .arbitrum, to: .bnb, asset: .usdt))
    }

    @Test("A moeda que mais soma nas redes vence, mesmo sem ser a maior numa rede so")
    func totalAcrossChains() throws {
        let pick = BridgeSuggestion.pick(holdings: [try holding(.usdc, .base, 120), try holding(.usdt, .arbitrum, 90), try holding(.usdt, .ethereum, 60)],
                                         currentTo: .base)
        #expect(pick == .init(from: .arbitrum, to: .ethereum, asset: .usdt))
    }

    @Test("Numa rede so: o destino que a tela tinha fica, se a rota existe")
    func singleChainKeepsDestination() throws {
        let pick = BridgeSuggestion.pick(holdings: [try holding(.usdc, .base, 50)], currentTo: .arbitrum)
        #expect(pick == .init(from: .base, to: .arbitrum, asset: .usdc))
        let same = BridgeSuggestion.pick(holdings: [try holding(.usdc, .base, 50)], currentTo: .base)
        #expect(same?.from == .base && same?.to != .base && same?.asset == .usdc)
    }

    @Test("A Tron so recebe: com mais USDT la, sai da segunda rede e vai para a Tron")
    func tronOnlyReceives() throws {
        let pick = BridgeSuggestion.pick(holdings: [try holding(.usdt, .tron, 300), try holding(.usdt, .arbitrum, 40)], currentTo: .base)
        #expect(pick == .init(from: .arbitrum, to: .tron, asset: .usdt))
    }

    @Test("Sem stablecoin, ou so poeira: nada muda")
    func nothingToSuggest() throws {
        #expect(BridgeSuggestion.pick(holdings: [], currentTo: .arbitrum) == nil)
        let base = try #require(BridgeAllowlist.chain(.base))
        let dust = Holding(asset: try #require(BridgeAsset.usdc.asset(on: base)), amount: 500_000)
        #expect(BridgeSuggestion.pick(holdings: [dust], currentTo: .arbitrum) == nil)
    }
}
