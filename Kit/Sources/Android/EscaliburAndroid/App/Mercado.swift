import EscaliburChains
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
    /// A pool de DEX de onde vem o preco, dita embaixo do grafico.
    struct Pool: Encodable { let nome: String; let dex: String; let liquidez: Double }
    /// `fonte` "nenhuma": nem o CoinGecko lista o contrato nem ha pool com liquidez.
    struct Grafico: Encodable { let pontos: [Ponto]; let atualizado: Date; let fonte: String; let velho: Bool; var pool: Pool? = nil }

    /// `reserva`: o token da lista com contrato. Se o CoinGecko e a OKX nao responderem (ou so
    /// voltar o grafico antigo), o grafico vem da pool de DEX dele, como o `dexFallback` do iOS.
    static func grafico(id: String, moeda: String, intervalo: String, reserva: String? = nil) async throws -> Grafico {
        let faixa = ChartRange(rawValue: intervalo) ?? .day
        let pelaPool = reserva.flatMap { id in TokenRegistry.tokens.first { $0.id == id } }
        func daPool(_ faixa: ChartRange) async -> ChartSnapshot? {
            guard let pelaPool, let grafico = try? await MarketService.shared.dexChart(pelaPool, currency: moeda, range: faixa),
                  grafico.snapshot.points.count >= 2 else { return nil }
            return grafico.snapshot
        }
        let retrato: ChartSnapshot
        do {
            retrato = try await MarketService.shared.chartSnapshot(id: id, currency: moeda, range: faixa)
        } catch {
            guard let pool = await daPool(faixa) else { throw error }
            return Grafico(pontos: pool.points.map { Ponto(t: $0.time, p: $0.price) }, atualizado: pool.fetchedAt, fonte: "dex", velho: false)
        }
        if retrato.isStale, let pool = await daPool(faixa) {
            return Grafico(pontos: pool.points.map { Ponto(t: $0.time, p: $0.price) }, atualizado: pool.fetchedAt, fonte: "dex", velho: false)
        }
        // "Tudo": o CoinGecko sem chave so da 365 dias; a pool de DEX tem a historia mais longa.
        if faixa == .all, let primeiro = retrato.points.first?.time, Date().timeIntervalSince(primeiro) < 380 * 86_400,
           let pool = await daPool(.all), let antes = pool.points.first?.time, antes < primeiro {
            return Grafico(pontos: pool.points.map { Ponto(t: $0.time, p: $0.price) }, atualizado: pool.fetchedAt, fonte: "dex", velho: false)
        }
        return Grafico(pontos: retrato.points.map { Ponto(t: $0.time, p: $0.price) }, atualizado: retrato.fetchedAt,
                       fonte: retrato.source.rawValue, velho: retrato.isStale)
    }

    /// O grafico de um token fora da lista ou de uma moeda custom, pelo contrato: CoinGecko ou a
    /// pool de DEX com mais liquidez. Limite ou rede fora sobe como erro: a tela tenta de novo.
    static func graficoDoContrato(id: String, moeda: String, intervalo: String) async throws -> Grafico {
        guard let ativo = Ativos.ativo(id) else { throw Nucleo.Falha(erro: "mercado.semToken") }
        if Saldos.shared.foraDaLista(id)?.isSuspicious == true { throw Nucleo.Falha(erro: "mercado.semToken") }
        do {
            let grafico = try await MarketService.shared.tokenChart(ativo, currency: moeda, range: ChartRange(rawValue: intervalo) ?? .day)
            return Grafico(
                pontos: grafico.snapshot.points.map { Ponto(t: $0.time, p: $0.price) }, atualizado: grafico.snapshot.fetchedAt,
                fonte: grafico.pool == nil ? "coingecko" : "dex", velho: grafico.snapshot.isStale,
                pool: grafico.pool.map { Pool(nome: $0.name, dex: $0.dex, liquidez: $0.reserveUSD) }
            )
        } catch HTTPClient.Failure.status(404) {
            return Grafico(pontos: [], atualizado: .now, fonte: "nenhuma", velho: false)
        }
    }

    /// O aviso que o CoinGecko poe no token deste contrato, em ingles como ele publica. `nil`: sem
    /// aviso. Erro (limite): a tela tenta de novo.
    static func avisoDoContrato(id: String) async throws -> String? {
        guard let ativo = Ativos.ativo(id) else { return nil }
        return try await MarketService.shared.contractNotice(ativo)
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
