import EscaliburChains
import EscaliburCore
import Foundation

/// Uma moeda achada na busca de Receber, ainda sem as redes: so o que a lista mostra.
public struct CoinSearchResult: Sendable, Hashable, Identifiable {
    /// O id do CoinGecko.
    public let id: String
    public let symbol: String
    public let name: String
    /// A posicao no mercado, quando a moeda tem.
    public let rank: Int?
    /// A logo pequena, so no host de imagens do CoinGecko.
    public let image: URL?
}

/// Uma moeda com as redes em que a carteira recebe ela, lida quando o dono toca nela.
public struct CatalogCoin: Codable, Sendable, Hashable, Identifiable {
    /// Uma rede em que a carteira recebe esta moeda, com o contrato fora da lista
    /// conferida.
    public struct Network: Codable, Sendable, Hashable {
        public let chainID: String
        /// O contrato como o CoinGecko escreve (minusculo na EVM), com o formato da rede
        /// conferido. A validacao completa (checksum, chave da rede) e a da moeda custom,
        /// `CustomToken.kind`, na hora de mostrar o endereco.
        public let contract: String

        public var chain: Chain? { Chain.find(chainID) }
    }

    public let id: String
    public let symbol: String
    public let name: String
    /// Onde a carteira recebe: EVM, Solana, Tron e TON, contrato com o formato da rede e
    /// fora da lista.
    public let networks: [Network]
    /// O CoinGecko publicou um aviso sobre a moeda (ataque, migracao, golpe) ou ela esta
    /// em pre-listagem. O texto do aviso nao e mostrado: e de quem escreveu, com link.
    public let hasNotice: Bool

    public var isReceivable: Bool { !networks.isEmpty }

    /// A mesma moeda com o que a outra leitura sabe a mais: o aviso, e as redes que faltam
    /// quando `addingNetworks`. Nome, simbolo e id ficam os desta.
    public func merged(with other: CatalogCoin, addingNetworks: Bool) -> CatalogCoin {
        var joined = networks
        if addingNetworks {
            for network in other.networks where !joined.contains(where: { $0.chainID == network.chainID }) {
                joined.append(network)
            }
            let order = Dictionary(Chain.all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            joined.sort { (order[$0.chainID] ?? .max) < (order[$1.chainID] ?? .max) }
        }
        return CatalogCoin(id: id, symbol: symbol, name: name, networks: joined, hasNotice: hasNotice || other.hasNotice)
    }
}

/// A lista de moedas com as redes, embarcada no app do iPhone (`tools/catalogo/gerar-catalogo.py`,
/// da lista do CoinGecko com os contratos). As redes de uma moeda saem dela sem perguntar
/// nada na hora, e a busca cai nela quando o CoinGecko e o CoinPaprika nao respondem (pedido
/// do dono, 30/10/2026: a pausa do CoinGecko nunca deve aparecer). Tudo passa pelas mesmas
/// conferencias da leitura na rede: nome e simbolo limpos, simbolo protegido so com o id da
/// lista, contrato no formato da rede e fora da lista verificada. A lista nao traz o aviso
/// do CoinGecko (ataque, migracao, golpe): ele vem da leitura na rede, quando ela responde.
public struct CoinList: Sendable {
    struct Entry: Decodable, Sendable {
        let id: String
        let symbol: String
        let name: String
        let rank: Int?
        let contracts: [String: String]
        /// Simbolo e nome sem acento e sem caixa, para a busca.
        let foldedSymbol: String
        let foldedName: String

        init(from decoder: Decoder) throws {
            var item = try decoder.unkeyedContainer()
            id = try item.decode(String.self)
            symbol = try item.decode(String.self)
            name = try item.decode(String.self)
            rank = try item.decodeIfPresent(Int.self)
            contracts = try item.decode([String: String].self)
            foldedSymbol = CoinList.fold(symbol)
            foldedName = CoinList.fold(name)
        }
    }

    let entries: [Entry]
    let byID: [String: Int]

    public init(data: Data) throws {
        do { entries = try JSONDecoder().decode([Entry].self, from: data) } catch { throw HTTPClient.Failure.decoding("lista de moedas") }
        byID = Dictionary(entries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public var count: Int { entries.count }

    /// A moeda com as redes em que a carteira recebe ela, ou nil se nao esta na lista (moeda
    /// listada depois do build) ou nao passa nas conferencias.
    public func coin(id: String) -> CatalogCoin? {
        guard let index = byID[id], CoinCatalog.isValidID(id) else { return nil }
        let entry = entries[index]
        guard let (symbol, name) = CoinCatalog.acceptable(id: id, symbol: entry.symbol, name: entry.name) else { return nil }
        var networks: [CatalogCoin.Network] = []
        for (chainID, contract) in entry.contracts.sorted(by: { $0.key < $1.key }) {
            guard let chain = Chain.find(chainID), CustomToken.supports(chain), !CustomToken.usesIssuer(chain),
                  let shaped = CoinCatalog.shape(contract, chain: chain),
                  !CoinCatalog.listedContracts.contains("\(chain.id):\(shaped)"), !networks.contains(where: { $0.chainID == chain.id })
            else { continue }
            networks.append(.init(chainID: chain.id, contract: shaped))
        }
        let order = Dictionary(Chain.all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        networks.sort { (order[$0.chainID] ?? .max) < (order[$1.chainID] ?? .max) }
        return CatalogCoin(id: id, symbol: symbol, name: name, networks: networks, hasNotice: false)
    }

    /// A busca sem rede: simbolo igual primeiro, depois simbolo ou nome que comeca com o
    /// texto, depois nome com uma palavra que comeca com ele. Em cada grupo, a maior no
    /// mercado primeiro (a copia com o mesmo simbolo quase nunca tem posicao).
    public func search(_ query: String, limit: Int = 30) -> [CoinSearchResult] {
        let text = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard text.count >= 2, text.count <= 60 else { return [] }
        var found: [(score: Int, entry: Entry)] = []
        for entry in entries {
            let score: Int
            if entry.foldedSymbol == text || entry.foldedName == text {
                score = 0
            } else if entry.foldedSymbol.hasPrefix(text) || entry.foldedName.hasPrefix(text) {
                score = 1
            } else if entry.foldedName.split(separator: " ").contains(where: { $0.hasPrefix(text) }) {
                score = 2
            } else {
                continue
            }
            found.append((score, entry))
        }
        found.sort { a, b in
            if a.score != b.score { return a.score < b.score }
            if (a.entry.rank ?? .max) != (b.entry.rank ?? .max) { return (a.entry.rank ?? .max) < (b.entry.rank ?? .max) }
            return a.entry.name.count < b.entry.name.count
        }
        var results: [CoinSearchResult] = []
        for (_, entry) in found where results.count < limit {
            guard CoinCatalog.isValidID(entry.id), let (symbol, name) = CoinCatalog.acceptable(id: entry.id, symbol: entry.symbol, name: entry.name) else { continue }
            results.append(CoinSearchResult(id: entry.id, symbol: symbol, name: name, rank: entry.rank, image: nil))
        }
        return results
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// A busca de Receber no CoinGecko, sem chave: so o que o dono digitou, e as redes de uma
/// moeda so quando ele toca nela.
///
/// - `GET /search?query=` devolve as moedas que casam com o texto (cerca de 8 KB). O
///   CoinGecko ve o que foi buscado; a politica de privacidade diz isso.
/// - `GET /coins/{id}` (sem mercado, tickers nem comunidade) devolve as plataformas com o
///   contrato de cada uma.
/// - So entra rede em que a carteira recebe token por endereco e mostra o saldo (EVM,
///   Solana, Tron e TON, as redes de moeda custom por contrato). XRP Ledger e Stellar
///   pedem linha de confianca; Sui, Cardano, Polkadot, NEAR e Aptos ainda nao mostram
///   token fora da lista. Moeda so dessas redes, ou de redes que a carteira nao tem, fica
///   sem endereco.
/// - O contrato precisa ter o formato da rede, e o que ja esta na lista conferida fica de
///   fora: aparece pela lista, com o selo. Antes de virar endereco na tela, passa pela
///   validacao completa da moeda custom (`CustomToken.kind`).
/// - Nome e simbolo sao de quem listou: limpos, e fora quem tem link, isca ou caractere
///   escondido. Simbolo de stablecoin, de nativa ou da lista so com o id da lista: um
///   "USDT" de outro id nao aparece.
public enum CoinCatalog {
    static let base = URL(string: "https://api.coingecko.com/api/v3")!

    /// A reserva: o CoinPaprika, quando o CoinGecko sem chave pede pausa ou nao responde
    /// (pedido do dono, 17/10/2026). O id do resultado leva o prefixo `paprika:`, para a
    /// leitura das redes ir ao mesmo lugar; nada do CoinPaprika vira id de preco.
    static let paprika = URL(string: "https://api.coinpaprika.com/v1")!
    public static let paprikaPrefix = "paprika:"

    public static func search(_ query: String, client: HTTPClient = .shared) async throws -> [CoinSearchResult] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text.count <= 60 else { return [] }
        var components = URLComponents(url: base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "query", value: text)]
        guard let url = components.url else { return [] }
        do {
            return try parseSearch(try await client.get(url, timeout: 10))
        } catch {
            try Task.checkCancellation()
            // O caminho termina em barra: sem ela, o CoinPaprika responde com redirecionamento.
            var reserve = URLComponents(url: paprika.appendingPathComponent("search/"), resolvingAgainstBaseURL: false)!
            reserve.queryItems = [URLQueryItem(name: "q", value: text), URLQueryItem(name: "c", value: "currencies"), URLQueryItem(name: "limit", value: "30")]
            guard let reserveURL = reserve.url else { throw error }
            return try parsePaprikaSearch(try await client.get(reserveURL, timeout: 10))
        }
    }

    public static func coin(id: String, client: HTTPClient = .shared) async throws -> CatalogCoin {
        if id.hasPrefix(paprikaPrefix) {
            let reserveID = String(id.dropFirst(paprikaPrefix.count))
            guard isValidID(reserveID) else { throw HTTPClient.Failure.decoding("moeda") }
            return try parsePaprikaCoin(try await client.get(paprika.appendingPathComponent("coins/\(reserveID)"), timeout: 10), id: id)
        }
        guard isValidID(id) else { throw HTTPClient.Failure.decoding("moeda") }
        var components = URLComponents(url: base.appendingPathComponent("coins/\(id)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            "localization", "tickers", "market_data", "community_data", "developer_data", "sparkline",
        ].map { URLQueryItem(name: $0, value: "false") }
        guard let url = components.url else { throw HTTPClient.Failure.decoding("moeda") }
        return try parseCoin(try await client.get(url, timeout: 10), id: id)
    }

    /// As redes da moeda pelas duas fontes juntas (pedido do dono, 17/10/2026): o CoinGecko e o
    /// CoinPaprika, achado pelo mesmo simbolo e nome. O CoinGecko lista o SHIB so na Ethereum;
    /// o CoinPaprika tambem na BNB Chain. Uma fonte basta: com o CoinGecko em pausa, vale o
    /// CoinPaprika sozinho. O id continua o do CoinGecko, e a moeda e aceita por ele.
    public static func coinAllNetworks(id: String, symbol: String?, name: String?, client: HTTPClient = .shared) async throws -> CatalogCoin {
        guard !id.hasPrefix(paprikaPrefix), let symbol, let name else { return try await coin(id: id, client: client) }
        async let geckoCoin = try? coin(id: id, client: client)
        var reserve: CatalogCoin?
        if let match = try? await paprikaMatch(symbol: symbol, name: name, client: client) {
            reserve = try? parsePaprikaCoin(try await client.get(paprika.appendingPathComponent("coins/\(match)"), timeout: 10),
                                            id: paprikaPrefix + match, acceptAs: id)
        }
        let base = await geckoCoin
        guard let first = base ?? reserve else { throw HTTPClient.Failure.offline }
        let joined = reserve.map { first.merged(with: $0, addingNetworks: true) } ?? first
        return CatalogCoin(id: id, symbol: joined.symbol, name: joined.name, networks: joined.networks, hasNotice: base?.hasNotice ?? false)
    }

    /// O id do CoinPaprika da moeda de mesmo simbolo e mesmo nome (sem acento e sem caixa).
    static func paprikaMatch(symbol: String, name: String, client: HTTPClient) async throws -> String? {
        var reserve = URLComponents(url: paprika.appendingPathComponent("search/"), resolvingAgainstBaseURL: false)!
        reserve.queryItems = [URLQueryItem(name: "q", value: symbol), URLQueryItem(name: "c", value: "currencies"), URLQueryItem(name: "limit", value: "20")]
        guard let url = reserve.url else { return nil }
        struct Response: Decodable {
            struct Coin: Decodable { let id: String; let name: String; let symbol: String; let is_active: Bool? }
            let currencies: [Coin]?
        }
        let response = try JSONDecoder().decode(Response.self, from: try await client.get(url, timeout: 10))
        func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        return response.currencies?.first { coin in
            coin.is_active != false && isValidID(coin.id) && fold(coin.symbol) == fold(symbol) && fold(coin.name) == fold(name)
        }?.id
    }

    /// O id vai no caminho da URL: so letras minusculas, digitos e hifen.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 120
            && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    // MARK: Leitura

    static func parseSearch(_ data: Data) throws -> [CoinSearchResult] {
        struct Response: Decodable {
            struct Coin: Decodable {
                let id: String
                let name: String
                let symbol: String
                let market_cap_rank: Int?
                let thumb: String?
            }
            let coins: [Coin]
        }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch { throw HTTPClient.Failure.decoding("busca") }
        var seen = Set<String>()
        return response.coins.prefix(60).compactMap { coin -> CoinSearchResult? in
            guard isValidID(coin.id), seen.insert(coin.id).inserted,
                  let (symbol, name) = acceptable(id: coin.id, symbol: coin.symbol, name: coin.name)
            else { return nil }
            let image = coin.thumb.flatMap(URL.init(string:)).flatMap { ImageLoader.isAllowed($0) ? $0 : nil }
            return CoinSearchResult(id: coin.id, symbol: symbol, name: name, rank: coin.market_cap_rank, image: image)
        }
    }

    static func parseCoin(_ data: Data, id: String) throws -> CatalogCoin {
        struct Response: Decodable {
            let id: String
            let symbol: String
            let name: String
            let platforms: [String: String?]?
            let public_notice: String?
            let preview_listing: Bool?
        }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch { throw HTTPClient.Failure.decoding("moeda") }
        guard response.id == id, let (symbol, name) = acceptable(id: id, symbol: response.symbol, name: response.name) else {
            throw HTTPClient.Failure.decoding("moeda")
        }
        let order = Dictionary(Chain.all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var networks: [CatalogCoin.Network] = []
        for (platform, contract) in (response.platforms ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let contract, let chain = chains[platform], let shaped = shape(contract, chain: chain),
                  !listedContracts.contains("\(chain.id):\(shaped)"), !networks.contains(where: { $0.chainID == chain.id })
            else { continue }
            networks.append(.init(chainID: chain.id, contract: shaped))
        }
        networks.sort { (order[$0.chainID] ?? .max) < (order[$1.chainID] ?? .max) }
        let notice = !(response.public_notice ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || response.preview_listing == true
        return CatalogCoin(id: id, symbol: symbol, name: name, networks: networks, hasNotice: notice)
    }

    static func parsePaprikaSearch(_ data: Data) throws -> [CoinSearchResult] {
        struct Response: Decodable {
            struct Coin: Decodable {
                let id: String
                let name: String
                let symbol: String
                let rank: Int?
                let is_active: Bool?
            }
            let currencies: [Coin]?
        }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch { throw HTTPClient.Failure.decoding("busca") }
        var seen = Set<String>()
        return (response.currencies ?? []).prefix(60).compactMap { coin -> CoinSearchResult? in
            let id = paprikaPrefix + coin.id
            guard coin.is_active != false, isValidID(coin.id), seen.insert(id).inserted,
                  let (symbol, name) = acceptable(id: id, symbol: coin.symbol, name: coin.name)
            else { return nil }
            return CoinSearchResult(id: id, symbol: symbol, name: name, rank: coin.rank.flatMap { $0 > 0 ? $0 : nil }, image: nil)
        }
    }

    /// `acceptAs`: o id do CoinGecko da moeda, quando ela ja e conhecida por ele (o simbolo
    /// protegido vale com o id da lista).
    static func parsePaprikaCoin(_ data: Data, id: String, acceptAs: String? = nil) throws -> CatalogCoin {
        struct Response: Decodable {
            struct Contract: Decodable {
                let contract: String
                let platform: String
            }
            let id: String
            let symbol: String
            let name: String
            let contracts: [Contract]?
        }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch { throw HTTPClient.Failure.decoding("moeda") }
        guard paprikaPrefix + response.id == id, let (symbol, name) = acceptable(id: acceptAs ?? id, symbol: response.symbol, name: response.name) else {
            throw HTTPClient.Failure.decoding("moeda")
        }
        let order = Dictionary(Chain.all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var networks: [CatalogCoin.Network] = []
        for item in response.contracts ?? [] {
            guard let chain = paprikaChains[item.platform], let shaped = shape(item.contract, chain: chain),
                  !listedContracts.contains("\(chain.id):\(shaped)"), !networks.contains(where: { $0.chainID == chain.id })
            else { continue }
            networks.append(.init(chainID: chain.id, contract: shaped))
        }
        networks.sort { (order[$0.chainID] ?? .max) < (order[$1.chainID] ?? .max) }
        return CatalogCoin(id: id, symbol: symbol, name: name, networks: networks, hasNotice: false)
    }

    /// A plataforma do CoinPaprika de cada rede, como os contratos da moeda dizem. A da BNB
    /// aparece como "bnb-bnb" nos contratos e "bnb-binance-coin" na lista de contratos: as
    /// duas valem.
    static let paprikaChains: [String: Chain] = {
        var out: [String: Chain] = [:]
        for (chainID, platform) in MarketService.tokenPlatforms {
            guard let reserve = platform.paprika, let chain = Chain.find(chainID), CustomToken.supports(chain), !CustomToken.usesIssuer(chain) else { continue }
            out[reserve] = chain
        }
        if let bnb = Chain.find("bnb") { out["bnb-bnb"] = bnb }
        return out
    }()

    /// Simbolo e nome limpos, ou nil: texto com link, isca ou caractere escondido, ou
    /// simbolo protegido com id fora da lista.
    static func acceptable(id: String, symbol rawSymbol: String, name rawName: String) -> (String, String)? {
        let symbol = TokenSafety.clean(rawSymbol.uppercased(), limit: TokenSafety.symbolLimit)
        let name = TokenSafety.clean(rawName, limit: TokenSafety.nameLimit)
        guard !symbol.isEmpty, !name.isEmpty, TokenSafety.textReasons(symbol: rawSymbol, name: rawName).isEmpty else { return nil }
        guard listedIDs.contains(id) || !TokenSafety.isProtectedAnywhere(symbol) else { return nil }
        return (symbol, name)
    }

    static let listedIDs = Set(TokenRegistry.tokens.compactMap(\.coingeckoID) + Chain.all.map(\.coingeckoID))

    /// A plataforma do CoinGecko de cada rede que recebe token por endereco.
    static let chains: [String: Chain] = {
        var out: [String: Chain] = [:]
        for (chainID, platform) in MarketService.tokenPlatforms {
            guard let chain = Chain.find(chainID), CustomToken.supports(chain), !CustomToken.usesIssuer(chain) else { continue }
            out[platform.gecko] = chain
        }
        return out
    }()

    /// Os contratos da lista conferida, como "rede:contrato" (minusculo na EVM).
    static let listedContracts: Set<String> = Set(TokenRegistry.tokens.compactMap { token -> String? in
        guard case .token(let contract) = token.kind, let chain = Chain.find(token.chainID) else { return nil }
        return "\(token.chainID):\(chain.family == .evm ? contract.lowercased() : contract)"
    })

    static let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    static let base64url = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    static let hex = Set("0123456789abcdef")

    /// O formato do contrato na rede, sem checksum.
    static func shape(_ raw: String, chain: Chain) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        switch chain.family {
        case .evm:
            let lower = text.lowercased()
            guard lower.count == 42, lower.hasPrefix("0x") else { return nil }
            let body = lower.dropFirst(2)
            guard body.allSatisfy(hex.contains), body.contains(where: { $0 != "0" }) else { return nil }
            return lower
        case .solana:
            return (32...44).contains(text.count) && text.allSatisfy(base58.contains) ? text : nil
        case .tron:
            return text.count == 34 && text.hasPrefix("T") && text.allSatisfy(base58.contains) ? text : nil
        case .ton:
            if text.count == 48, text.allSatisfy(base64url.contains) { return text }
            if text.count == 66, text.hasPrefix("0:"), text.dropFirst(2).lowercased().allSatisfy(hex.contains) { return text }
            return nil
        default:
            return nil
        }
    }
}
