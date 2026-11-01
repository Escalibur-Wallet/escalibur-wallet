import EscaliburChains
import EscaliburCore
import Foundation
import Testing
@testable import EscaliburNetwork

/// A segunda opiniao do aviso de recebimento fora das redes UTXO (revisao de 23/10/2026): um RPC
/// sozinho nao inventa "Recebeu 10.000 USDT".
@Suite("Aviso de recebimento: a segunda opiniao nas redes de conta")
struct ReceiptConfirmationTests {
    static let usdt = Asset(chainID: "ethereum", kind: .token(contract: "0xdAC17F958D2ee523a2206206994597C13D831ec7"), symbol: "USDT",
                            name: "Tether", decimals: 6, coingeckoID: "tether", isStablecoin: true, origin: nil)
    static let eth = Asset.native(.ethereum)

    static func balance(_ amounts: [(Asset, BigUInt)], unread: [String]? = nil) -> ChainBalance {
        ChainBalance(chainID: "ethereum", holdings: amounts.map { Holding(asset: $0.0, amount: $0.1) }, accountExists: true, unknownTokenCount: 0,
                     fetchedAt: .now, unread: unread)
    }

    static func amount(_ balance: ChainBalance, _ asset: Asset) -> BigUInt? { balance.holdings.first { $0.asset.id == asset.id }?.amount }

    @Test("Subida inventada por um RPC: a segunda opiniao nao confirma, e fica o visto")
    func inventedRise() {
        let seen = [Self.usdt.id: BigUInt(5_000_000_000), Self.eth.id: BigUInt(1)]
        let first = Self.balance([(Self.eth, 1), (Self.usdt, 15_000_000_000)])
        let second = Self.balance([(Self.eth, 1), (Self.usdt, 5_000_000_000)])
        let result = BalanceService.confirmed(first, second: second, seen: seen)
        #expect(Self.amount(result, Self.usdt) == 5_000_000_000)
        // Sem segunda opiniao: fica o visto, fora de holdings e em unread.
        let alone = BalanceService.confirmed(first, second: nil, seen: seen)
        #expect(Self.amount(alone, Self.usdt) == nil && (alone.unread ?? []).contains(Self.usdt.id))
    }

    @Test("Subida de verdade nos dois: vale o menor")
    func realRise() {
        let seen = [Self.usdt.id: BigUInt(5_000_000_000)]
        let result = BalanceService.confirmed(Self.balance([(Self.usdt, 15_000_000_000)]), second: Self.balance([(Self.usdt, 14_000_000_000)]), seen: seen)
        #expect(Self.amount(result, Self.usdt) == 14_000_000_000)
    }

    @Test("Queda inventada nao baixa o visto; queda de verdade vale o maior")
    func falls() {
        let seen = [Self.usdt.id: BigUInt(5_000_000_000)]
        let lie = BalanceService.confirmed(Self.balance([]), second: Self.balance([(Self.usdt, 5_000_000_000)]), seen: seen)
        #expect(Self.amount(lie, Self.usdt) == nil && (lie.unread ?? []).contains(Self.usdt.id))
        let real = BalanceService.confirmed(Self.balance([(Self.usdt, 1_000_000_000)]), second: Self.balance([(Self.usdt, 2_000_000_000)]), seen: seen)
        #expect(Self.amount(real, Self.usdt) == 2_000_000_000)
        let gone = BalanceService.confirmed(Self.balance([]), second: Self.balance([]), seen: seen)
        #expect(Self.amount(gone, Self.usdt) == nil && !(gone.unread ?? []).contains(Self.usdt.id))
    }

    @Test("Saldo de partida: so com os dois iguais")
    func base() {
        let equal = BalanceService.confirmed(Self.balance([(Self.usdt, 7)]), second: Self.balance([(Self.usdt, 7)]), seen: [:])
        #expect(Self.amount(equal, Self.usdt) == 7)
        let differ = BalanceService.confirmed(Self.balance([(Self.usdt, 0)]), second: Self.balance([(Self.usdt, 7)]), seen: [:])
        #expect(Self.amount(differ, Self.usdt) == nil && (differ.unread ?? []).contains(Self.usdt.id))
    }

    @Test("Sem mudanca: nenhuma segunda leitura e necessaria")
    func unchanged() {
        let first = Self.balance([(Self.usdt, 7)])
        #expect(BalanceService.changed(first, seen: [Self.usdt.id: 7]).isEmpty)
    }
}

/// Contra os provedores reais. So com ESCALIBUR_REDE=1.
@Suite("Aviso de recebimento ao vivo", .enabled(if: ProcessInfo.processInfo.environment["ESCALIBUR_REDE"] == "1"))
struct ReceiptLiveTests {
    @Test("Saldo de partida conferido por dois donos: Ethereum (vitalik.eth) e Bitcoin (o endereco 0 da frase de teste)")
    func baseReadings() async throws {
        let eth = try await BalanceService.shared.receiptBalance(
            chain: .ethereum, addresses: ["0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"], salt: 1, seen: [:], seenAddresses: [:])
        #expect(eth.holdings.contains { $0.asset.kind == .native } || (eth.unread ?? []).contains(Asset.native(.ethereum).id))
        let address = ReaderBTest.abandonReceive0
        let btc = try await BalanceService.shared.receiptBalance(chain: .bitcoin, addresses: [address], salt: 1, seen: [:], seenAddresses: [:])
        #expect(btc.perAddress?[address] != nil)
    }
}
