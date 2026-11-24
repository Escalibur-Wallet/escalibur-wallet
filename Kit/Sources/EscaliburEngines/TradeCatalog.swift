import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation

/// A busca de qualquer moeda na escolha do que comprar (pedido do dono, 06/11/2026: como a busca de Receber), com a mesma
/// regra nos dois apps (`TradeCatalogLookup` no iPhone, "receber.redesDaTroca" no Android):
///
/// - Moeda da lista verificada (a nativa de uma rede, ou um token da lista, pelo id do CoinGecko): so as formas
///   verificadas, prontas para a troca. Os contratos de fora da lista da mesma moeda (o BNB antigo na Ethereum, o TON
///   embrulhado na BNB Chain) nao entram: seriam outra coisa com o mesmo nome.
/// - Moeda fora da lista: so com a leitura de agora (`live`), que traz o aviso do CoinGecko e o contrato atual. Ficam de
///   fora a rede achada no CoinPaprika so pelo nome (`byName`), e a rede em que a lista embarcada (`local`) tem outro
///   contrato (a moeda mudou de contrato depois desta versao). Cada contrato passa pela validacao da moeda custom; a ja
///   salva vai direto, a nova passa antes pelo Adicionar moeda, que le nome, simbolo e casas na propria rede.
///
/// (revisao de seguranca de 06/11/2026)
public enum TradeCatalog {
    public struct Option: Sendable, Hashable, Identifiable {
        public let asset: Asset
        /// Da lista verificada ou ja adicionada: vai direto para a troca. Senao, passa antes pelo Adicionar moeda.
        public let ready: Bool
        public let verified: Bool
        public var id: String { asset.id }
    }

    /// A moeda e da lista verificada (a nativa de alguma rede, ou um token da lista), em qualquer rede, com troca aqui ou
    /// nao: so as formas verificadas valem, e o contrato de fora da lista dela nunca e oferecido.
    public static func isListed(_ coinID: String) -> Bool {
        Chain.all.contains { $0.coingeckoID == coinID } || TokenRegistry.tokens.contains { $0.coingeckoID == coinID }
    }

    /// A leitura de agora vale para comprar fora da lista: veio do CoinGecko (o id dele, e nao so redes achadas no
    /// CoinPaprika pelo nome), com o aviso e o contrato atual. A moeda achada so no CoinPaprika (`paprika:`) nao tem nem um
    /// nem outro.
    public static func confirmed(coinID: String, live: CatalogCoin?) -> Bool {
        guard let live, !coinID.hasPrefix(CoinCatalog.paprikaPrefix) else { return false }
        return live.networks.isEmpty || live.networks.contains { $0.byName != true }
    }

    /// Onde a troca compra moeda fora da lista: EVM e Solana, com motor (o `TradeAccess` do iPhone, o `permite` do Android).
    public static func takesUnlisted(_ chain: Chain) -> Bool {
        (chain.family == .evm || chain.family == .solana) && TradeEngines.engine(for: chain) != nil
    }

    /// As opcoes de compra. `chains`: as redes da troca com conta nesta carteira. `custom`: as moedas custom salvas.
    /// `exclude`: o ativo do outro lado. Sem a leitura de agora confirmada (`confirmed`), so as verificadas.
    public static func options(coinID: String, local: CatalogCoin?, live: CatalogCoin?, chains: [Chain], custom: [Asset],
                               exclude: String?) -> [Option] {
        let listed = chains.filter { TradeEngines.engine(for: $0) != nil }.flatMap { chain -> [Option] in
            var found: [Asset] = chain.coingeckoID == coinID ? [.native(chain)] : []
            found += TokenRegistry.tokens.filter { $0.chainID == chain.id && $0.coingeckoID == coinID }
            return found.map { Option(asset: $0, ready: true, verified: true) }
        }
        guard !isListed(coinID) else { return unique(listed, exclude: exclude) }
        guard let live, confirmed(coinID: coinID, live: live) else { return [] }
        let open = Set(chains.filter(takesUnlisted).map(\.id))
        let priceID = coinID.hasPrefix(CoinCatalog.paprikaPrefix) ? nil : coinID
        var options: [Option] = []
        for network in live.networks where network.byName != true && open.contains(network.chainID) {
            guard let chain = network.chain else { continue }
            if let old = local?.networks.first(where: { $0.chainID == network.chainID }), !same(old.contract, network.contract, chain) { continue }
            let kind: Asset.Kind
            do {
                kind = try CustomToken.kind(chain: chain, address: network.contract)
            } catch CustomToken.Problem.alreadyListed(let asset) {
                options.append(Option(asset: asset, ready: true, verified: true))
                continue
            } catch {
                continue
            }
            let asset = Asset(chainID: chain.id, kind: kind, symbol: live.symbol, name: live.name, decimals: 0,
                              coingeckoID: priceID, isStablecoin: false, origin: .discovered)
            if let saved = saved(asset, custom: custom) {
                options.append(Option(asset: saved, ready: true, verified: false))
            } else {
                options.append(Option(asset: asset, ready: false, verified: false))
            }
        }
        return unique(options, exclude: exclude)
    }

    /// A custom salva com o mesmo contrato na mesma rede (na EVM, sem olhar a caixa).
    public static func saved(_ asset: Asset, custom: [Asset]) -> Asset? {
        guard let chain = asset.chain, let reference = CustomToken.reference(asset.kind) else { return nil }
        return custom.first { token in
            guard token.chainID == chain.id, let stored = CustomToken.reference(token.kind) else { return false }
            return same(stored, reference, chain)
        }
    }

    static func same(_ a: String, _ b: String, _ chain: Chain) -> Bool {
        chain.family == .evm ? a.lowercased() == b.lowercased() : a == b
    }

    static func unique(_ options: [Option], exclude: String?) -> [Option] {
        var seen = Set<String>()
        return options.filter { $0.id != exclude && seen.insert($0.id).inserted }
    }
}
