import EscaliburCore
import EscaliburNetwork
import Foundation

/// O Mercado (o MarketView do iOS): so dado publico de mercado, igual para todo mundo, que nao
/// revela nada da carteira do dono.
enum Mercado {
    struct Moeda: Encodable {
        let id: String, simbolo: String, nome: String, preco: Double, variacao24h: Double?
        let capitalizacao: Double?, volume: Double?, posicao: Int?, linha: [Double]
    }

    struct Lista: Encodable { let moedas: [Moeda]; let atualizado: Date; let fonte: String; let velho: Bool; let favoritas: [String] }

    static func lista(moeda: String) async throws -> Lista {
        let retrato = try await MarketService.shared.marketSnapshot(currency: moeda)
        return Lista(
            moedas: retrato.coins.map {
                Moeda(id: $0.id, simbolo: $0.symbol, nome: $0.name, preco: $0.price, variacao24h: $0.change24h, capitalizacao: $0.marketCap,
                      volume: $0.volume24h, posicao: $0.rank, linha: $0.sparkline)
            },
            atualizado: retrato.fetchedAt, fonte: retrato.source.rawValue, velho: retrato.isStale,
            favoritas: Sessao.shared.metadata.settings.favoriteCoins ?? []
        )
    }

    struct Ponto: Encodable { let t: Date; let p: Double }
    struct Grafico: Encodable { let pontos: [Ponto]; let atualizado: Date; let fonte: String; let velho: Bool }

    static func grafico(id: String, moeda: String, intervalo: String) async throws -> Grafico {
        let faixa = ChartRange(rawValue: intervalo) ?? .day
        let retrato = try await MarketService.shared.chartSnapshot(id: id, currency: moeda, range: faixa)
        return Grafico(pontos: retrato.points.map { Ponto(t: $0.time, p: $0.price) }, atualizado: retrato.fetchedAt,
                       fonte: retrato.source.rawValue, velho: retrato.isStale)
    }

    static func detalhes(id: String, moeda: String) async throws -> MarketCoinDetails {
        try await MarketService.shared.coinDetails(id: id, currency: moeda)
    }

    static func favoritar(_ id: String, _ favorita: Bool) throws {
        try Sessao.shared.alterar { metadata in
            var lista = metadata.settings.favoriteCoins ?? []
            lista.removeAll { $0 == id }
            if favorita { lista.append(id) }
            metadata.settings.favoriteCoins = lista
        }
    }
}
