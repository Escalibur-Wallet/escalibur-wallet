@testable import EscaliburChains
import EscaliburCore
import Foundation
import Testing
@testable import EscaliburEngines
@testable import EscaliburNetwork

/// A busca de qualquer moeda na escolha do que comprar (06/11/2026): a regra que os dois apps usam.
@Suite("Troca: busca de qualquer moeda")
struct TradeCatalogTests {
    static let ethereum = Chain.find("ethereum")!
    static let bnb = Chain.find("bnb")!
    static let base = Chain.find("base")!
    static let one = "0x1111111111111111111111111111111111111111"
    static let two = "0x2222222222222222222222222222222222222222"

    static func coin(_ id: String, _ networks: [CatalogCoin.Network], notice: Bool = false) -> CatalogCoin {
        CatalogCoin(id: id, symbol: "FOO", name: "Foo", networks: networks, hasNotice: notice)
    }

    @Test("Moeda da lista verificada: so a forma verificada, nunca o contrato de fora com o mesmo nome")
    func nativeOnly() {
        // O BNB antigo na Ethereum, que o CoinGecko lista para a moeda do BNB.
        let live = Self.coin("binancecoin", [CatalogCoin.Network(chainID: "ethereum", contract: Self.one)])
        let options = TradeCatalog.options(coinID: "binancecoin", local: nil, live: live, chains: [Self.ethereum, Self.bnb], custom: [], exclude: nil)
        #expect(options.contains { $0.asset == .native(Self.bnb) })
        #expect(options.allSatisfy { $0.ready && $0.verified })
        #expect(!options.contains { $0.asset.chainID == "ethereum" })
        // A nativa do outro lado da troca nao volta.
        #expect(TradeCatalog.options(coinID: "binancecoin", local: nil, live: live, chains: [Self.bnb], custom: [],
                                     exclude: Asset.native(Self.bnb).id).isEmpty)
    }

    @Test("Fora da lista: so com a leitura de agora, sem a rede achada pelo nome e sem o contrato que mudou")
    func unlisted() throws {
        let live = Self.coin("foo-coin", [
            CatalogCoin.Network(chainID: "ethereum", contract: Self.one),
            CatalogCoin.Network(chainID: "base", contract: Self.two),
            CatalogCoin.Network(chainID: "bnb", contract: Self.two, byName: true),
        ])
        let chains = [Self.ethereum, Self.base, Self.bnb]
        let options = TradeCatalog.options(coinID: "foo-coin", local: nil, live: live, chains: chains, custom: [], exclude: nil)
        #expect(Set(options.map(\.asset.chainID)) == ["ethereum", "base"])
        #expect(options.allSatisfy { !$0.ready && !$0.verified && $0.asset.origin == .discovered })
        // A lista embarcada com outro contrato na Base: a moeda mudou de contrato, a Base sai.
        let local = Self.coin("foo-coin", [CatalogCoin.Network(chainID: "base", contract: Self.one)])
        let changed = TradeCatalog.options(coinID: "foo-coin", local: local, live: live, chains: chains, custom: [], exclude: nil)
        #expect(changed.map(\.asset.chainID) == ["ethereum"])
        // Sem a leitura de agora, nada de fora da lista.
        #expect(TradeCatalog.options(coinID: "foo-coin", local: local, live: nil, chains: chains, custom: [], exclude: nil).isEmpty)
        // Ja salva (o mesmo contrato, outra caixa): vai direto.
        let kind = try CustomToken.kind(chain: Self.ethereum, address: Self.one)
        let saved = Asset(chainID: "ethereum", kind: kind, symbol: "FOO", name: "Foo", decimals: 9, coingeckoID: "foo-coin",
                          isStablecoin: false, origin: .custom)
        let ready = TradeCatalog.options(coinID: "foo-coin", local: nil, live: live, chains: [Self.ethereum], custom: [saved], exclude: nil)
        #expect(ready.count == 1 && ready[0].ready && ready[0].asset.decimals == 9)
    }

    @Test("Moeda da lista em rede sem troca, ou sem conta: nada, nunca o contrato de fora")
    func listedElsewhere() {
        // O TON embrulhado na Ethereum e na BNB Chain, sem motor de troca na TON.
        let ton = Self.coin("the-open-network", [CatalogCoin.Network(chainID: "ethereum", contract: Self.one),
                                                 CatalogCoin.Network(chainID: "bnb", contract: Self.two)])
        #expect(TradeCatalog.options(coinID: "the-open-network", local: nil, live: ton, chains: [Self.ethereum, Self.bnb], custom: [], exclude: nil).isEmpty)
        // O BNB numa carteira sem conta na BNB Chain.
        let bnb = Self.coin("binancecoin", [CatalogCoin.Network(chainID: "ethereum", contract: Self.one)])
        #expect(TradeCatalog.options(coinID: "binancecoin", local: nil, live: bnb, chains: [Self.ethereum], custom: [], exclude: nil).isEmpty)
        #expect(TradeCatalog.isListed("the-open-network") && !TradeCatalog.isListed("foo-coin"))
    }

    @Test("Sem o CoinGecko: a moeda so do CoinPaprika, ou so com redes achadas pelo nome, nao e oferecida")
    func unconfirmed() {
        let paprika = Self.coin("paprika:foo-foo", [CatalogCoin.Network(chainID: "ethereum", contract: Self.one)])
        #expect(!TradeCatalog.confirmed(coinID: "paprika:foo-foo", live: paprika))
        #expect(TradeCatalog.options(coinID: "paprika:foo-foo", local: nil, live: paprika, chains: [Self.ethereum], custom: [], exclude: nil).isEmpty)
        let byName = Self.coin("foo-coin", [CatalogCoin.Network(chainID: "ethereum", contract: Self.one, byName: true)])
        #expect(!TradeCatalog.confirmed(coinID: "foo-coin", live: byName))
        #expect(TradeCatalog.confirmed(coinID: "foo-coin", live: Self.coin("foo-coin", [])))
        #expect(!TradeCatalog.confirmed(coinID: "foo-coin", live: nil))
    }

    @Test("A propria nativa com cara de contrato nao vira moeda custom")
    func nativeContracts() {
        #expect(throws: CustomToken.Problem.notAToken) {
            _ = try CustomToken.kind(chain: Chain.find("polygon")!, address: "0x0000000000000000000000000000000000001010")
        }
        #expect(throws: CustomToken.Problem.notAToken) {
            _ = try CustomToken.kind(chain: Chain.find("celo")!, address: "0x471EcE3750Da237f93B8E339c536989b8978a438")
        }
    }
}
