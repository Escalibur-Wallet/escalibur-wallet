import EscaliburChains
import EscaliburCore
import Foundation
import Testing
@testable import EscaliburNetwork

/// A busca de Receber no CoinGecko: respostas reais gravadas de `/search?query=bonk`,
/// `/coins/bonk` e `/coins/hedera-hashgraph` (11/10/2026), e casos montados (impostor,
/// isca, id que nao cabe na URL).
@Suite("Busca de moedas")
struct CoinCatalogTests {
    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: caminhoNoAparelho(#filePath)).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).json"))
    }

    @Test("Busca real: a Bonk primeiro, com posicao no mercado e logo do host do CoinGecko")
    func search() throws {
        let results = try CoinCatalog.parseSearch(try Self.fixture("coingecko-search-bonk"))
        let first = try #require(results.first)
        #expect(first.id == "bonk" && first.symbol == "BONK" && first.name == "Bonk" && first.rank != nil)
        #expect(first.image?.host == "coin-images.coingecko.com")
        #expect(results.count > 5)
    }

    @Test("Reserva do CoinPaprika: id com prefixo, simbolo protegido fora, contratos por rede com a BNB em bnb-bnb")
    func paprikaReserve() throws {
        let search = Data("""
        {"currencies":[
          {"id":"purpe-purple-pepe","name":"Purple Pepe","symbol":"PURPE","rank":1074,"is_active":true},
          {"id":"usdt-fake","name":"Tether","symbol":"USDT","rank":0,"is_active":true},
          {"id":"dead-coin","name":"Dead","symbol":"DEAD","rank":0,"is_active":false}
        ]}
        """.utf8)
        let results = try CoinCatalog.parsePaprikaSearch(search)
        // O PEPE da lista verificada nao viria daqui: simbolo protegido so com o id da lista.
        #expect(results.map(\.id) == ["paprika:purpe-purple-pepe"])
        #expect(results.first?.rank == 1074)
        let coin = Data("""
        {"id":"purpe-purple-pepe","symbol":"PURPE","name":"Purple Pepe","contracts":[
          {"contract":"0x25d887ce7a35172c62febfd67a1856f20faebb00","platform":"bnb-bnb"},
          {"contract":"0x25d887ce7a35172c62febfd67a1856f20faebb00","platform":"arb-arbitrum"},
          {"contract":"nao-e-contrato","platform":"eth-ethereum"}
        ]}
        """.utf8)
        let parsed = try CoinCatalog.parsePaprikaCoin(coin, id: "paprika:purpe-purple-pepe")
        #expect(parsed.networks.map(\.chainID).sorted() == ["arbitrum", "bnb"])
        #expect(throws: (any Error).self) { try CoinCatalog.parsePaprikaCoin(coin, id: "paprika:outra") }
    }

    @Test("Busca: isca, simbolo protegido de outro id, id que nao cabe na URL e repetido ficam de fora")
    func searchSafety() throws {
        let json = #"""
        {"coins":[
          {"id":"tether","name":"Tether","symbol":"USDT","market_cap_rank":3,"thumb":"https://coin-images.coingecko.com/a.png"},
          {"id":"usdt-impostor","name":"Bridged USDT","symbol":"USDT","market_cap_rank":null,"thumb":null},
          {"id":"claim-token","name":"Claim at rewards-site.com","symbol":"RWD","market_cap_rank":null,"thumb":null},
          {"id":"../../etc","name":"Path","symbol":"PATH","market_cap_rank":null,"thumb":null},
          {"id":"toshi","name":"Toshi","symbol":"TOSHI","market_cap_rank":500,"thumb":"https://atacante.example/x.png"},
          {"id":"toshi","name":"Toshi","symbol":"TOSHI","market_cap_rank":500,"thumb":null}
        ]}
        """#
        let results = try CoinCatalog.parseSearch(Data(json.utf8))
        #expect(results.map(\.id) == ["tether", "toshi"])
        #expect(results[1].image == nil)
    }

    @Test("Moeda real (Bonk): so redes que recebem token por endereco, contrato com o formato da rede, aviso publico marcado")
    func coin() throws {
        let bonk = try CoinCatalog.parseCoin(try Self.fixture("coingecko-coin-bonk"), id: "bonk")
        let order = Chain.all.map(\.id)
        #expect(bonk.networks.map(\.chainID) == order.filter { ["ethereum", "bnb", "solana", "arbitrum", "polygon", "unichain"].contains($0) })
        #expect(bonk.networks.first { $0.chainID == "ethereum" }?.contract == "0x1151cb3d861920e07a38e03eead12c32178567f6")
        #expect(bonk.networks.first { $0.chainID == "solana" }?.contract == "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263")
        // Aptos e Neon EVM ficam de fora; o aviso do CoinGecko sobre o ataque fica marcado.
        #expect(!bonk.networks.contains { $0.chainID == "aptos" })
        #expect(bonk.hasNotice)
    }

    @Test("Moeda sem contrato aqui (Hedera): sem rede para receber; outra moeda no lugar recusa")
    func coinWithoutNetwork() throws {
        let hedera = try CoinCatalog.parseCoin(try Self.fixture("coingecko-coin-hedera"), id: "hedera-hashgraph")
        #expect(!hedera.isReceivable)
        #expect(throws: (any Error).self) { try CoinCatalog.parseCoin(try Self.fixture("coingecko-coin-bonk"), id: "hedera-hashgraph") }
    }

    @Test("Moeda da lista: so as redes de fora da lista; contrato invalido fica de fora")
    func listedCoin() throws {
        let json = #"""
        {"id":"pepe","symbol":"pepe","name":"Pepe","platforms":{
          "ethereum":"0x6982508145454ce325ddbe47a25d4ec3d2311933",
          "binance-smart-chain":"0x25d887ce7a35172c62febfd67a1856f20faebb00",
          "arbitrum-one":"not-an-address","": ""},
         "public_notice":null,"preview_listing":false}
        """#
        let pepe = try CoinCatalog.parseCoin(Data(json.utf8), id: "pepe")
        #expect(pepe.networks.map(\.chainID) == ["bnb"])
        #expect(!pepe.hasNotice)
    }

    /// A lista embarcada (`CoinList`), no formato do tools/catalogo/gerar-catalogo.py:
    /// [id, simbolo, nome, posicao, {rede: contrato}].
    static let list = Data("""
    [
    ["bnb-tiger-inu","bnbtiger","BNB Tiger Inu",null,{"bnb":"0xF8584516B7D2C156C763C874D6813E06B57E4CB5"}],
    ["bnbtiger","bnbtigerog","BNB Tiger OG",null,{"bnb":"0xac68931b666e086e9de380cfdb0fb5704a35dc2d"}],
    ["tether","usdt","Tether",3,{"ethereum":"0xdac17f958d2ee523a2206206994597c13d831ec7","bnb":"0x55d398326f99059ff775485246999027b3197955"}],
    ["usdt-copia","usdt","Tether",null,{"base":"0x1111111111111111111111111111111111111111"}],
    ["bonk","bonk","Bonk",60,{"solana":"DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263","ethereum":"0x1151cb3d861920e07a38e03eead12c32178567f6"}],
    ["formato-errado","ruim","Ruim",null,{"ethereum":"0x123","solana":"0OIl"}],
    ["so-cardano","ada2","Ada Dois",null,{}],
    ["link-na-isca","free","Visite https://x.y",null,{"ethereum":"0x2222222222222222222222222222222222222222"}]
    ]
    """.utf8)

    @Test("Lista embarcada: as redes de uma moeda sem perguntar nada, com as mesmas conferencias")
    func embeddedListCoin() throws {
        let list = try CoinList(data: Self.list)
        #expect(list.count == 8)
        let tiger = try #require(list.coin(id: "bnb-tiger-inu"))
        #expect(tiger.symbol == "BNBTIGER" && tiger.name == "BNB Tiger Inu" && !tiger.hasNotice)
        // EVM em minusculo, como a leitura na rede.
        #expect(tiger.networks.map(\.chainID) == ["bnb"] && tiger.networks.first?.contract == "0xf8584516b7d2c156c763c874d6813e06b57e4cb5")
        // Na ordem das redes do app, a de Chain.all.
        let bonk = try #require(list.coin(id: "bonk"))
        let order = Chain.all.map(\.id)
        #expect(bonk.networks.map(\.chainID) == ["ethereum", "solana"].sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! })
        // Contrato fora do formato da rede: a rede sai, a moeda fica sem endereco.
        #expect(list.coin(id: "formato-errado")?.networks.isEmpty == true)
        #expect(list.coin(id: "so-cardano")?.isReceivable == false)
        // Simbolo protegido so com o id da lista; isca no nome nunca.
        #expect(list.coin(id: "usdt-copia") == nil)
        #expect(list.coin(id: "link-na-isca") == nil)
        // O contrato da lista verificada fica de fora: aparece pela lista, com o selo.
        #expect(list.coin(id: "tether")?.networks.isEmpty == true)
        #expect(list.coin(id: "nao-esta-na-lista") == nil)
    }

    @Test("Lista embarcada: a busca acha a moeda pequena e poe a de verdade antes da copia")
    func embeddedListSearch() throws {
        let list = try CoinList(data: Self.list)
        #expect(Set(list.search("bnb tiger").map(\.id)) == ["bnb-tiger-inu", "bnbtiger"])
        #expect(list.search("BNBTIGER").first?.id == "bnb-tiger-inu")
        // A copia com o simbolo protegido nem aparece; a Tether, com posicao, sim.
        #expect(list.search("usdt").map(\.id) == ["tether"])
        #expect(list.search("tiger").count == 2)
        #expect(list.search("b").isEmpty)
        #expect(list.search("visite").isEmpty)
    }

    @Test("Juntar duas leituras: o aviso sempre, as redes so quando pedido")
    func mergeReadings() throws {
        let list = try CoinList(data: Self.list)
        let local = try #require(list.coin(id: "bonk"))
        let online = CatalogCoin(id: "bonk", symbol: "BONK", name: "Bonk", networks: [.init(chainID: "bnb", contract: "0x3333333333333333333333333333333333333333")], hasNotice: true)
        let all = local.merged(with: online, addingNetworks: true)
        #expect(all.hasNotice && all.networks.count == 3)
        let noticeOnly = local.merged(with: online, addingNetworks: false)
        #expect(noticeOnly.hasNotice && noticeOnly.networks == local.networks)
    }

    @Test("A lista do app abre e tem a BNB Tiger e a Bonk com rede")
    func appList() throws {
        let url = URL(fileURLWithPath: caminhoNoAparelho(#filePath))
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/EscaliburWallet/Resources/catalogo-moedas.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let list = try CoinList(data: try Data(contentsOf: url))
        #expect(list.count > 15_000)
        #expect(list.coin(id: "bnb-tiger-inu")?.networks.first?.chainID == "bnb")
        #expect(list.coin(id: "bonk")?.isReceivable == true)
        #expect(list.search("bnb tiger").contains { $0.id == "bnb-tiger-inu" })
    }
}

@Suite("Busca de moedas ao vivo", .enabled(if: ProcessInfo.processInfo.environment["ESCALIBUR_REDE"] == "1"))
struct CoinCatalogLiveTests {
    @Test("Buscar e abrir uma moeda: duas chamadas pequenas")
    func searchAndOpen() async throws {
        let results = try await CoinCatalog.search("bonk")
        #expect(results.first?.id == "bonk")
        let bonk = try await CoinCatalog.coin(id: "bonk")
        #expect(bonk.networks.contains { $0.chainID == "solana" })
    }
}
