import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation

/// A ponte que a tela abre ja escolhida (pedido do dono, 27/10/2026): a stablecoin que a carteira
/// mais tem, somando as redes, saindo da rede onde ha mais dela e indo para a segunda. Com US$ 100
/// de USDT na Arbitrum e US$ 80 na BNB, abre Arbitrum para BNB, em USDT. Com a moeda numa rede so,
/// o destino fica o que a tela ja tinha, se a rota existir.
///
/// So USDC e USDT: valem um dolar, entao a quantidade ja compara redes e moedas sem cotacao.
public enum BridgeSuggestion {
    public struct Pick: Equatable, Sendable {
        public let from: Chain
        public let to: Chain
        public let asset: BridgeAsset

        public init(from: Chain, to: Chain, asset: BridgeAsset) {
            self.from = from
            self.to = to
            self.asset = asset
        }
    }

    static let stablecoins: [BridgeAsset] = [.usdt, .usdc]
    /// Menos de um dolar somando as redes e poeira: a tela fica como estava.
    static let minimum = 1.0

    /// `holdings`: os saldos da carteira em todas as redes. `nil` sem stablecoin numa rede da ponte.
    public static func pick(holdings: [Holding], currentTo: Chain) -> Pick? {
        var best: (asset: BridgeAsset, total: Double, amounts: [(chain: Chain, units: Double)])?
        for asset in stablecoins {
            let amounts: [(chain: Chain, units: Double)] = BridgeEngine.destinations.compactMap { chain in
                guard let bridgeChain = BridgeAllowlist.chain(chain), let listed = asset.asset(on: bridgeChain) else { return nil }
                let held = holdings.filter { $0.asset.id == listed.id }.reduce(BigUInt(0)) { $0 + $1.amount }
                let units = units(held, decimals: asset.decimals(on: bridgeChain))
                return units > 0 ? (chain, units) : nil
            }
            let total = amounts.reduce(0) { $0 + $1.units }
            if total >= minimum, total > (best?.total ?? 0) { best = (asset, total, amounts) }
        }
        guard let best else { return nil }
        let ranked = best.amounts.sorted { $0.units > $1.units }
        // Sai da rede com mais saldo que tenha para onde ir com esta moeda (a Tron so recebe).
        for source in ranked where BridgeEngine.chains.contains(source.chain) {
            let reachable = { (chain: Chain) in chain != source.chain && BridgeEngine.assets(from: source.chain, to: chain).contains(best.asset) }
            if let second = ranked.first(where: { reachable($0.chain) }) {
                return Pick(from: source.chain, to: second.chain, asset: best.asset)
            }
            if reachable(currentTo) { return Pick(from: source.chain, to: currentTo, asset: best.asset) }
            if let any = BridgeEngine.destinations.first(where: reachable) {
                return Pick(from: source.chain, to: any, asset: best.asset)
            }
        }
        return nil
    }

    private static func units(_ amount: BigUInt, decimals: Int) -> Double {
        guard !amount.isZero else { return 0 }
        return Double(amount.description).map { $0 / pow(10, Double(decimals)) } ?? 0
    }
}
