@testable import EscaliburChains
import EscaliburCore
import Foundation
import Testing
@testable import EscaliburEngines
@testable import EscaliburNetwork

/// A ordem assinada que a CoW disse ter recusado, guardada ate vencer ou ate a cadeia dizer que
/// terminou (segunda passada da auditoria de 03/11/2026).
@Suite("Ordens assinadas guardadas")
struct SignedOrdersTests {
    typealias H = EVMTradeHarness

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Um UID da CoW: digesto, dono e validTo.
    static func uid(validTo: UInt32, seed: UInt8 = 7) -> String {
        Hex.encode([UInt8](repeating: seed, count: 32) + [UInt8](repeating: 0xab, count: 20) + withUnsafeBytes(of: validTo.bigEndian) { Array($0) },
                   prefix: true)
    }

    static func order(_ id: String, chain: Chain = .base, sell: BigUInt = 1_000, minimum: BigUInt = 400) -> OpenOrder {
        OpenOrder(id: id, chain: chain, sellAssetID: "usdc", buyAssetID: "eth", remainingSell: sell, minimumBuy: minimum,
                  expiresAt: nil, sources: 1, cancellations: [.onchain], totalSell: sell)
    }

    @Test("Guarda so a ordem da CoW, com o vencimento tirado do UID; mostra como aberta, sem fonte e so com o cancelamento na cadeia")
    func recordFromOrder() throws {
        let wallet = UUID()
        let validTo = UInt32(Self.now.timeIntervalSince1970) + 3_600
        let record = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: validTo)), walletID: wallet, now: Self.now))
        #expect(record.expiresAt == Date(timeIntervalSince1970: TimeInterval(validTo)))
        let shown = try #require(record.order)
        #expect(shown.sources == 0 && shown.cancellations == [.onchain] && shown.remainingSell == 1_000 && shown.minimumBuy == 400)
        #expect(SignedOrderRecord(Self.order("0x1234"), walletID: wallet) == nil)
        let xrpl = OpenOrder(id: "123", chain: .xrpl, sellAssetID: "a", buyAssetID: "b", remainingSell: 1, minimumBuy: 1,
                             expiresAt: nil, sources: 1, cancellations: [.onchain])
        #expect(SignedOrderRecord(xrpl, walletID: wallet) == nil)
    }

    static func chain(_ filled: BigUInt, at time: Date = now) -> SignedOrderChainState { SignedOrderChainState(filled: filled, chainTime: time) }

    @Test("Sai a vencida pelo tempo do bloco e a que a cadeia da por terminada (preenchida ou cancelada); sem resposta, fica; preenchida em parte, o resto continua")
    func refreshKeepsLiveOrders() async throws {
        let wallet = UUID()
        let future = UInt32(Self.now.timeIntervalSince1970) + 3_600
        let past = UInt32(Self.now.timeIntervalSince1970) - 120
        let live = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: future, seed: 1)), walletID: wallet))
        let partial = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: future, seed: 2)), walletID: wallet))
        let filled = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: future, seed: 3)), walletID: wallet))
        let cancelled = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: future, seed: 4)), walletID: wallet))
        let expired = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: past, seed: 5)), walletID: wallet))
        let silent = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: past, seed: 6)), walletID: wallet))
        let max = BigUInt(bigEndian: [UInt8](repeating: 0xff, count: 32))
        let answers: [String: BigUInt] = [live.id: 0, partial.id: 250, filled.id: 1_000, cancelled.id: max, expired.id: 0]
        let kept = await SignedOrders.refreshed([live, partial, filled, cancelled, expired, silent], wallet: wallet) { record in
            answers[record.id].map { Self.chain($0) }
        }
        // A vencida sem resposta da cadeia fica: o relogio do aparelho nao basta para apagar.
        #expect(kept.map(\.id) == [live.id, partial.id, silent.id])
        let rest = try #require(kept[1].order)
        #expect(rest.remainingSell == 750 && rest.minimumBuy == 300)
        // Uma leitura menor depois (uma fonte atrasada) nao devolve o que ja saiu.
        let again = await SignedOrders.refreshed(kept, wallet: wallet) { _ in Self.chain(0) }
        #expect(again.first { $0.id == partial.id }?.filled == 250)
    }

    @Test("O relogio do aparelho adiantado nao apaga: vale o tempo do bloco (terceira passada de 03/11/2026)")
    func blockTimeDecidesExpiry() async throws {
        let wallet = UUID()
        let validTo = UInt32(Self.now.timeIntervalSince1970) + 3_600
        let record = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: validTo)), walletID: wallet))
        let before = await SignedOrders.refreshed([record], wallet: wallet) { _ in Self.chain(0, at: Self.now) }
        #expect(before == [record])
        // No segundo do vencimento o contrato ainda aceita a ordem: ela fica, com a folga de um minuto.
        let atExpiry = await SignedOrders.refreshed([record], wallet: wallet) { _ in
            Self.chain(0, at: Date(timeIntervalSince1970: TimeInterval(validTo)))
        }
        #expect(atExpiry == [record])
        let after = await SignedOrders.refreshed([record], wallet: wallet) { _ in
            Self.chain(0, at: Date(timeIntervalSince1970: TimeInterval(validTo) + SignedOrders.expiryMargin + 1))
        }
        #expect(after.isEmpty)
    }

    @Test("So a carteira aberta e consultada: a de outra carteira e a de rede desligada voltam intactas, sem leitura (terceira passada de 03/11/2026)")
    func refreshOnlyTheOpenWallet() async throws {
        let wallet = UUID(), other = UUID()
        let future = UInt32(Self.now.timeIntervalSince1970) + 3_600
        let past = UInt32(Self.now.timeIntervalSince1970) - 1
        let mine = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: future, seed: 1)), walletID: wallet))
        let theirs = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: future, seed: 2)), walletID: other))
        let theirsExpired = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: past, seed: 3)), walletID: other))
        let disabled = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: future, seed: 4), chain: .ethereum), walletID: wallet))
        let asked = Asked()
        let kept = await SignedOrders.refreshed([mine, theirs, theirsExpired, disabled], wallet: wallet, skippingChains: [Chain.ethereum.id]) { record in
            await asked.add(record.id)
            return nil
        }
        #expect(await asked.ids == [mine.id])
        #expect(kept == [mine, theirs, theirsExpired, disabled])
    }

    actor Asked {
        private(set) var ids: [String] = []
        func add(_ id: String) { ids.append(id) }
    }

    @Test("A lista mostra a guardada que a CoW nao lista; a listada igual aparece uma vez, a da CoW; guardar de novo nao duplica")
    func mergedSkipsMatchingListing() throws {
        let wallet = UUID(), other = UUID()
        let future = UInt32(Date().timeIntervalSince1970) + 3_600
        let mine = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: future, seed: 1)), walletID: wallet))
        let listed = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: future, seed: 2)), walletID: wallet))
        let theirs = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: future, seed: 3)), walletID: other))
        var records = SignedOrders.adding(mine, to: nil)
        records = SignedOrders.adding(listed, to: records)
        records = SignedOrders.adding(theirs, to: records)
        records = SignedOrders.adding(mine, to: records)
        #expect(records.count == 3)
        let fromCoW = OpenOrder(id: listed.id.uppercased().replacingOccurrences(of: "0X", with: "0x"), chain: .base, sellAssetID: "usdc",
                                buyAssetID: "eth", remainingSell: 1_000, minimumBuy: 400, expiresAt: listed.expiresAt, sources: 1,
                                cancellations: [.offchain, .onchain], totalSell: 1_000)
        let shown = SignedOrders.merged([fromCoW], records: records, wallet: wallet)
        #expect(shown.map { $0.id.lowercased() } == [listed.id, mine.id] && shown.first?.sources == 1)
    }

    @Test("A CoW lista o UID da guardada com outro valor: a guardada fica no lugar, sem fonte e so com o cancelamento na cadeia")
    func mergedReplacesLyingListing() throws {
        let wallet = UUID()
        let future = UInt32(Date().timeIntervalSince1970) + 3_600
        let record = try #require(SignedOrderRecord(Self.order(Self.uid(validTo: future)), walletID: wallet))
        let lie = OpenOrder(id: record.id, chain: .base, sellAssetID: "usdc", buyAssetID: "eth", remainingSell: 1, minimumBuy: 1,
                            expiresAt: record.expiresAt, sources: 1, cancellations: [.offchain, .onchain], totalSell: 1)
        let shown = SignedOrders.merged([lie], records: [record], wallet: wallet)
        #expect(shown.count == 1 && shown[0].sources == 0 && shown[0].remainingSell == 1_000 && shown[0].cancellations == [.onchain])
    }

    @Test("A leitura na cadeia chama filledAmount(bytes) do GPv2Settlement")
    func selector() throws {
        let call = try TradeStateReader.cowFilledAmountFunction.encodeCall([.bytes([1, 2, 3])])
        #expect(Hex.encode(call.prefix(4)) == "2479fb6e")
    }

    @Test("O motor EVM le o filledAmount e o tempo do bloco na cadeia pelo UID, e recusa o que nao e UID da CoW")
    func engineReadsTheChain() async throws {
        let state = FakeTradeChain()
        let id = Self.uid(validTo: UInt32(Date().timeIntervalSince1970) + 3_600)
        await state.setFilled(id, 600)
        await state.setBlockTime(1_800_000_123)
        let engine = H.engine(state: state, sources: [], transport: try H.baseTransport())
        let read = try await engine.onChainState(Self.order(id))
        #expect(read.filled == 600 && read.chainTime == Date(timeIntervalSince1970: 1_800_000_123))
        await #expect(throws: (any Error).self) { try await engine.onChainState(Self.order("0x1234")) }
        await #expect(throws: (any Error).self) { try await engine.onChainState(Self.order(id, chain: .ethereum)) }
    }
}
