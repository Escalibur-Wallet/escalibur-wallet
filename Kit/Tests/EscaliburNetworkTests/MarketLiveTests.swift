import Foundation
import Testing
import EscaliburChains
@testable import EscaliburNetwork

/// Testes contra os provedores reais. So rodam com ESCALIBUR_REDE=1, para o CI
/// nao depender da internet nem gastar limite de API.
///
/// Um de cada vez: em paralelo, os nove testes mandavam uma rajada de pedidos ao CoinGecko
/// sem chave no mesmo segundo, e o do contrato levava 429 (23/10/2026).
@Suite("Mercado ao vivo", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ESCALIBUR_REDE"] == "1"))
struct MarketLiveTests {
    @Test("Precos em BRL das moedas nativas")
    func quotes() async throws {
        let quotes = try await MarketService().quotes(ids: ["bitcoin", "ethereum", "solana", "ripple", "stellar", "tron", "the-open-network"], currency: "brl")
        #expect(quotes.count >= 6)
        #expect((quotes["bitcoin"]?.price ?? 0) > 10_000)
    }

    @Test("Lista de mercado com minigrafico")
    func markets() async throws {
        let coins = try await MarketService().markets(currency: "brl", perPage: 20)
        #expect(coins.count >= 10)
        #expect(coins.first?.sparkline.isEmpty == false)
    }

    @Test("Tudo: a historia inteira, da fonte que comeca mais cedo (BTC antes de 2014, USDT e USDC com anos de historia)")
    func fullHistory() async throws {
        let market = MarketService()
        let bitcoin = try await market.chartSnapshot(id: "bitcoin", currency: "usd", range: .all)
        #expect(bitcoin.source == .kraken)
        #expect((bitcoin.points.first?.time ?? .now) < Date(timeIntervalSince1970: 1_388_534_400), "BTC antes de 2014")
        for (id, before) in [("tether", 1_514_764_800.0), ("usd-coin", 1_609_459_200.0)] {
            let stable = try await market.chartSnapshot(id: id, currency: "usd", range: .all)
            #expect((stable.points.first?.time ?? .now) < Date(timeIntervalSince1970: before), "\(id)")
            // Uma stablecoin fica perto de um dolar a historia inteira (o USDT foi a 0,92 em 2017).
            #expect(stable.points.allSatisfy { $0.price > 0.85 && $0.price < 1.15 }, "\(id)")
        }
        // A BNB vem da OKX, que tem mais anos dela que a Kraken.
        let bnb = try await market.chartSnapshot(id: "binancecoin", currency: "usd", range: .all)
        #expect(bnb.source == .okx)
    }

    @Test("Historico de 7 dias e contingencia da OKX")
    func chart() async throws {
        let points = try await MarketService().chart(id: "bitcoin", currency: "brl", range: .week)
        #expect(points.count > 50)
    }

    @Test("Grafico pelo contrato de token com aviso do CoinGecko (BNB Frog Inu e o SHIB da BNB Chain)")
    func contractChart() async throws {
        let market = MarketService()
        let frog = Asset(chainID: "bnb", kind: .token(contract: "0x64da67a12a46f1ddf337393e2da12ed0a507ad3d"), symbol: "BNBFROG",
                         name: "BNB Frog Inu", decimals: 9, coingeckoID: nil, isStablecoin: false, origin: .discovered)
        let shib = Asset(chainID: "bnb", kind: .token(contract: "0x2859e4544c4bb03966803b044a93563bd2d0dd4d"), symbol: "SHIB",
                         name: "SHIBA INU", decimals: 18, coingeckoID: nil, isStablecoin: false, origin: .discovered)
        for asset in [frog, shib] {
            // O caminho do app: CoinGecko pelo contrato e GeckoTerminal ao mesmo tempo, vale o
            // primeiro que responder. Com o CoinGecko em 429, o grafico vem da pool.
            let chart = try await market.tokenChart(asset, currency: "brl", range: .day)
            let snapshot = chart.snapshot
            if chart.pool == nil {
                #expect(snapshot.source == .coingecko && snapshot.points.count > 50, "\(asset.symbol)")
            } else {
                #expect(snapshot.source == .geckoTerminal && snapshot.points.count >= 2, "\(asset.symbol)")
            }
            #expect(snapshot.points.allSatisfy { $0.price > 0 })
        }
    }

    @Test("Token com aviso do CoinGecko continua sem reconhecimento (BNB Frog Inu e o SHIB da BNB Chain)")
    func contractNoticeRefusal() async throws {
        let market = MarketService()
        let frog = Asset(chainID: "bnb", kind: .token(contract: "0x64da67a12a46f1ddf337393e2da12ed0a507ad3d"), symbol: "BNBFROG",
                         name: "BNB Frog Inu", decimals: 9, coingeckoID: nil, isStablecoin: false, origin: .discovered)
        let shib = Asset(chainID: "bnb", kind: .token(contract: "0x2859e4544c4bb03966803b044a93563bd2d0dd4d"), symbol: "SHIB",
                         name: "SHIBA INU", decimals: 18, coingeckoID: nil, isStablecoin: false, origin: .discovered)
        for asset in [frog, shib] {
            // O reconhecimento continua recusado: o aviso mantem o token fora da confianca.
            #expect(try await market.tokenIdentity(asset) == nil, "\(asset.symbol)")
            let notice = try await market.contractNotice(asset)
            #expect(notice?.contains("GoPlus") == true, "\(asset.symbol): \(notice ?? "sem aviso")")
            #expect(notice?.contains("<") == false)
        }
    }

    @Test("Grafico de DEX pelo GeckoTerminal: pool com mais liquidez, so acima do minimo")
    func dexChart() async throws {
        let market = MarketService()
        let frog = Asset(chainID: "bnb", kind: .token(contract: "0x64da67a12a46f1ddf337393e2da12ed0a507ad3d"), symbol: "BNBFROG",
                         name: "BNB Frog Inu", decimals: 9, coingeckoID: nil, isStablecoin: false, origin: .discovered)
        let chart = try await market.dexChart(frog, currency: "usd", range: .week)
        let pool = try #require(chart.pool)
        #expect(pool.reserveUSD >= MarketService.dexMinimumReserveUSD)
        #expect(pool.dex.hasPrefix("PancakeSwap"))
        #expect(chart.snapshot.source == .geckoTerminal)
        #expect(chart.snapshot.points.count > 10)
        #expect(chart.snapshot.points.allSatisfy { $0.price > 0 && $0.time >= Date().addingTimeInterval(-7 * 86_400 - 60) })
        // Em ordem, do mais antigo ao mais novo (a API manda ao contrario).
        #expect(zip(chart.snapshot.points, chart.snapshot.points.dropFirst()).allSatisfy { $0.time < $1.time })
    }

    @Test("Logo passa pelas regras de tamanho e formato")
    func logo() async throws {
        let coins = try await MarketService().markets(currency: "usd", perPage: 5)
        let url = try #require(coins.first?.imageURL)
        let data = await ImageLoader().data(for: url)
        #expect(data != nil)
    }

    /// O CoinGecko cortado (como no IP que estourou a cota): tudo vem da reserva.
    struct GeckoBlocked: ReaderTransport {
        func send(_ request: ReaderRequest) async throws -> Data {
            if request.url.host == "api.coingecko.com" { throw HTTPClient.Failure.status(429) }
            return try await HTTPClient.shared.send(request)
        }
    }

    @Test("Sem CoinGecko: lista, cotacao, grafico e detalhe pela reserva")
    func reserve() async throws {
        let service = MarketService(transport: GeckoBlocked())
        let list = try await service.marketSnapshot(currency: "brl")
        #expect(list.source == .coinpaprika && list.coins.count >= 50)
        #expect(list.coins.first?.id == "bitcoin")
        let quotes = try await service.quotes(ids: ["bitcoin", "dogecoin", "litecoin"], currency: "brl")
        #expect(quotes.count == 3)
        // A TON pela tabela a mao (o id antigo, "ton-toncoin", deu 404 em outubro de 2026).
        let ton = try await service.quotes(ids: ["the-open-network"], currency: "brl")
        #expect((ton["the-open-network"]?.price ?? 0) > 0)
        let chart = try await service.chartSnapshot(id: "dogecoin", currency: "brl", range: .day)
        #expect(chart.source == .okx && chart.points.count > 50)
        let details = try await service.coinDetails(id: "dogecoin", currency: "brl")
        #expect(details.source == .coinpaprika && details.high24h != nil && details.about != nil)
    }

    @Test("Toda id da tabela a mao do CoinPaprika existe la (uma chamada so, a lista inteira)")
    func paprikaTable() async throws {
        struct Ticker: Decodable { let id: String }
        let data = try await HTTPClient.shared.send(ReaderRequest(method: .get, url: URL(string: "https://api.coinpaprika.com/v1/tickers")!, timeout: 20))
        let listed = Set(try JSONDecoder().decode([Ticker].self, from: data).map(\.id))
        for (gecko, paprika) in MarketService.paprikaIDs {
            #expect(listed.contains(paprika), "\(gecko): \(paprika) nao existe no CoinPaprika")
        }
    }

    @Test("Detalhe pelo CoinGecko")
    func details() async throws {
        let details = try await MarketService().coinDetails(id: "bitcoin", currency: "brl")
        #expect(details.maxSupply == 21_000_000 && details.allTimeHigh != nil && details.about != nil)
    }
}
