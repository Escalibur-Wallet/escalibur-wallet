import EscaliburChains
import EscaliburCore
import Foundation

/// A cotacao que a tela mostra, ja validada pelo motor da rede. O que a tela mostra em
/// "Voce recebe" e o `minimumOut`: o minimo decodificado da transacao, ou o gravado na
/// ordem assinada, garantido na cadeia. Chega ele ou mais, nunca menos.
public struct TradeQuote: Sendable, Equatable {
    /// Como a troca executa.
    public enum Execution: Sendable, Equatable {
        /// Transacoes dos agregadores, cada uma com o minimo gravado.
        case transactions
        /// Uma ordem assinada no leilao da CoW, preenchida de uma vez ou em partes, cada
        /// parte pelo minimo ou mais. Nao gasta taxa de rede na troca; vale 30 minutos.
        case order
    }

    /// A troca grande em partes: o mesmo valor por um preco melhor que o de uma vez so,
    /// preenchido conforme chega liquidez. O preco e o que a CoW cota para uma fracao do
    /// valor, e o minimo e garantido na ordem assinada.
    public struct Parts: Sendable, Equatable {
        public let expectedOut: BigUInt
        public let minimumOut: BigUInt
        /// A fracao do valor que a cotacao usada no preco cobriu, em bps.
        public let sampleShareBps: Int
        public let validFor: TimeInterval

        public init(expectedOut: BigUInt, minimumOut: BigUInt, sampleShareBps: Int, validFor: TimeInterval) {
            self.expectedOut = expectedOut
            self.minimumOut = minimumOut
            self.sampleShareBps = sampleShareBps
            self.validFor = validFor
        }
    }

    public struct Leg: Sendable, Equatable {
        public let provider: String
        public let fraction: Double
        public let amountIn: BigUInt
        public let expectedOut: BigUInt

        public init(provider: String, fraction: Double, amountIn: BigUInt, expectedOut: BigUInt) {
            self.provider = provider
            self.fraction = fraction
            self.amountIn = amountIn
            self.expectedOut = expectedOut
        }
    }

    /// A taxa de rede estimada da troca, num ativo: o nativo da rede, ou o vendido na
    /// CoW (o leilao tira a taxa dele).
    public struct NetworkFee: Sendable, Equatable {
        public let asset: Asset
        public let amount: BigUInt

        public init(asset: Asset, amount: BigUInt) {
            self.asset = asset
            self.amount = amount
        }
    }

    public struct Alternative: Sendable, Equatable {
        public let provider: String
        public let out: BigUInt

        public init(provider: String, out: BigUInt) {
            self.provider = provider
            self.out = out
        }
    }

    public let sell: Asset
    public let buy: Asset
    public let amountIn: BigUInt
    public let expectedOut: BigUInt
    public let minimumOut: BigUInt
    public let priceImpactPercent: Double?
    /// Vazia quando o motor nao sabe estimar: a tela manda ver na revisao.
    public let networkFees: [NetworkFee]
    public let providerFeeNote: String?
    public let legs: [Leg]
    public let alternatives: [Alternative]
    public let providersCompared: Int
    public let needsApproval: Bool
    public let expiresAt: Date
    public let execution: Execution
    /// So em ordem grande, quando dividir no tempo rende um minimo melhor.
    public let parts: Parts?

    public init(
        sell: Asset, buy: Asset, amountIn: BigUInt, expectedOut: BigUInt, minimumOut: BigUInt,
        priceImpactPercent: Double?, networkFees: [NetworkFee], providerFeeNote: String?, legs: [Leg],
        alternatives: [Alternative], providersCompared: Int, needsApproval: Bool, expiresAt: Date,
        execution: Execution = .transactions, parts: Parts? = nil
    ) {
        self.sell = sell
        self.buy = buy
        self.amountIn = amountIn
        self.expectedOut = expectedOut
        self.minimumOut = minimumOut
        self.priceImpactPercent = priceImpactPercent
        self.networkFees = networkFees
        self.providerFeeNote = providerFeeNote
        self.legs = legs
        self.alternatives = alternatives
        self.providersCompared = providersCompared
        self.needsApproval = needsApproval
        self.expiresAt = expiresAt
        self.execution = execution
        self.parts = parts
    }

    /// A taxa de rede na moeda do dono, pelos precos que o app tem. nil sem estimativa ou
    /// sem o preco de algum ativo dela.
    public func networkFeeFiat(price: (Asset) -> Double?) -> Double? {
        guard !networkFees.isEmpty else { return nil }
        var total = 0.0
        for fee in networkFees {
            guard let unit = price(fee.asset), let amount = Double(fee.amount.decimalString) else { return nil }
            total += amount / pow(10, Double(fee.asset.decimals)) * unit
        }
        return total
    }

    /// O que o "Max" deixa de fora quando vende a moeda nativa (auditoria de 03/11/2026): a taxa
    /// estimada desta cotacao vezes tres, porque o plano reserva a taxa maxima (o gas com folga e o
    /// preco maximo do gas), e o que a rede ainda pode pedir numa troca: a conta do token na Solana
    /// (o minimo sem aluguel de uma conta de token) e a reserva da linha de confianca no XRP Ledger e
    /// na Stellar. nil fora da nativa ou sem a taxa da rede.
    public func nativeReserveForMax() -> BigUInt? {
        guard sell.kind == .native, let chain = sell.chain else { return nil }
        let native = networkFees.filter { $0.asset.id == sell.id }.reduce(BigUInt()) { $0 + $1.amount }
        guard !native.isZero else { return nil }
        let extra: BigUInt
        switch chain.family {
        case .solana: extra = 2 * 2_039_280        // lamports: a conta do token comprado e a do wSOL temporario
        case .xrpl: extra = 200_000                // drops: 0,2 XRP por objeto novo
        case .stellar: extra = 5_000_000           // stroops: 0,5 XLM por linha nova
        default: extra = 0
        }
        return max(native * 3 + extra, Self.nativeReserveBeforeQuote(chain))
    }

    /// O que o "Max" na nativa ja deixa de fora antes da primeira cotacao. Na Solana a propria cotacao
    /// confere o saldo (o rascunho da transacao), e com o saldo inteiro ela recusa antes de dizer a taxa:
    /// 0,005 SOL cobre as duas contas de token e as taxas (segunda passada da auditoria de 03/11/2026).
    /// Nas outras, a cotacao nao confere o saldo e o ajuste vem dela (`nativeReserveForMax`).
    public static func nativeReserveBeforeQuote(_ chain: Chain) -> BigUInt {
        chain.family == .solana ? 5_000_000 : 0
    }

    /// O minimo garantido da execucao escolhida.
    public func minimumOut(inParts: Bool) -> BigUInt {
        inParts ? parts?.minimumOut ?? minimumOut : minimumOut
    }

    /// A mesma rodada, executada inteira por uma das alternativas: o dono escolheu outro
    /// provedor na rota (pedido do dono, 17/10/2026). O minimo e a estimativa sao o garantido
    /// que essa alternativa cotou (a rodada so guarda o garantido dela). O plano recota esse
    /// provedor, valida, simula e prende a esse minimo, como na troca de rota por falha na
    /// simulacao; o melhor de antes vira alternativa. Nil para o que nao executa sozinho: o
    /// leilao da CoW precisa da propria ordem, e so a EVM tem alternativas.
    public func choosing(_ alternative: Alternative) -> TradeQuote? {
        guard alternatives.contains(alternative), EVMTradeQuoteMapping.provider(named: alternative.provider) != nil else { return nil }
        var others = alternatives.filter { $0 != alternative }
        if execution == .transactions, legs.count == 1, EVMTradeQuoteMapping.provider(named: legs[0].provider) != nil,
           !others.contains(where: { $0.provider == legs[0].provider }) {
            others.append(Alternative(provider: legs[0].provider, out: minimumOut))
        }
        return TradeQuote(
            sell: sell, buy: buy, amountIn: amountIn, expectedOut: alternative.out, minimumOut: alternative.out,
            priceImpactPercent: priceImpactPercent, networkFees: [], providerFeeNote: nil,
            legs: [Leg(provider: alternative.provider, fraction: 1, amountIn: amountIn, expectedOut: alternative.out)],
            alternatives: others.sorted { $0.out > $1.out }, providersCompared: providersCompared,
            // Outro provedor, outro contrato que gasta: a autorizacao pode faltar. A revisao diz.
            needsApproval: needsApproval || sell.kind != .native, expiresAt: expiresAt, execution: .transactions, parts: nil
        )
    }
}

public struct TradeRequest: Sendable {
    public let walletID: UUID
    public let chain: Chain
    public let account: DerivedAccount
    public let sell: Asset
    public let buy: Asset
    public let amountIn: BigUInt
    public let slippageBasisPoints: Int
    /// EVM: a fila local de transacoes desta conta ainda em transito (`PendingNonceQueue`).
    public let nonceQueue: PendingNonceQueue?
    /// O dono escolheu a troca em partes (`TradeQuote.parts`).
    public let inParts: Bool

    public init(
        walletID: UUID, chain: Chain, account: DerivedAccount, sell: Asset, buy: Asset, amountIn: BigUInt, slippageBasisPoints: Int,
        nonceQueue: PendingNonceQueue? = nil, inParts: Bool = false
    ) {
        self.walletID = walletID
        self.chain = chain
        self.account = account
        self.sell = sell
        self.buy = buy
        self.amountIn = amountIn
        self.slippageBasisPoints = slippageBasisPoints
        self.nonceQueue = nonceQueue
        self.inParts = inParts
    }
}

public struct LimitOrderRequest: Sendable {
    public let walletID: UUID
    public let chain: Chain
    public let account: DerivedAccount
    public let sell: Asset
    public let buy: Asset
    public let amountIn: BigUInt
    /// Quanto o dono recebe, calculado localmente a partir do preco-alvo digitado.
    public let minimumOut: BigUInt
    /// Por quanto tempo a ordem vale. nil: ate o dono cancelar. Na Stellar e no XRP Ledger
    /// a oferta vai sem prazo; na CoW, que exige um, a ordem vale o maximo pratico do
    /// protocolo (`CoWProtocol.untilCancelledValidity`) e a revisao diz isso.
    public let validFor: TimeInterval?
    /// EVM: a fila local de transacoes desta conta ainda em transito (`PendingNonceQueue`).
    public let nonceQueue: PendingNonceQueue?
    /// Editando: o UID da ordem substituida, ja cancelada na cadeia (a edicao espera o cancelamento
    /// confirmar, `CancellationWait`). A CoW ainda pode lista-la ate indexar o cancelamento, e ela sai
    /// da soma das ordens abertas (segunda passada da auditoria de 03/11/2026).
    public let replacing: String?

    public init(
        walletID: UUID, chain: Chain, account: DerivedAccount, sell: Asset, buy: Asset, amountIn: BigUInt, minimumOut: BigUInt,
        validFor: TimeInterval?, nonceQueue: PendingNonceQueue? = nil, replacing: String? = nil
    ) {
        self.replacing = replacing
        self.walletID = walletID
        self.chain = chain
        self.account = account
        self.sell = sell
        self.buy = buy
        self.amountIn = amountIn
        self.minimumOut = minimumOut
        self.validFor = validFor
        self.nonceQueue = nonceQueue
    }
}

/// A outra ponta recusou e disse por que (a CoW recusou a ordem): enviar de novo os mesmos dados nao
/// muda nada. A tela mostra o motivo, sem o "pode ja estar a caminho" de uma resposta incerta
/// (01/11/2026). Mas e a palavra da CoW (auditoria de 03/11/2026): `notes` diz o que ja entrou na
/// rede antes (a autorizacao, o embrulho do nativo), e `signedOrder` e a ordem que chegou assinada a
/// ela. Com a ordem, o app continua acompanhando ate o prazo e oferece o cancelamento na cadeia, o
/// unico que nao depende da CoW.
public struct TradeRefusedForSure: LocalizedError, Equatable, Sendable {
    public let reason: String
    public let notes: [String]
    public let signedOrder: OpenOrder?
    public init(reason: String, notes: [String] = [], signedOrder: OpenOrder? = nil) {
        self.reason = reason
        self.notes = notes
        self.signedOrder = signedOrder
    }
    public var errorDescription: String? { reason }
}

/// A ordem assinada saiu para a CoW e a resposta nao veio com certeza (sem resposta no prazo, erro do
/// servidor, recusa sem motivo, resposta sem o UID, "ja existe" que a consulta nao confirma): ela pode
/// estar valendo (segunda passada da auditoria de 03/11/2026). A tela de incerto mostra o que ja entrou
/// na rede, acompanha a ordem e oferece o cancelamento na cadeia; o "Enviar de novo" manda a mesma ordem.
public struct TradeSubmissionUncertain: LocalizedError, Equatable, Sendable {
    public let detail: String?
    public let notes: [String]
    public let signedOrder: OpenOrder
    public init(detail: String?, notes: [String], signedOrder: OpenOrder) {
        self.detail = detail
        self.notes = notes
        self.signedOrder = signedOrder
    }
    public var errorDescription: String? { detail }
}

/// Uma ordem limite aberta da conta, lida da rede.
public struct OpenOrder: Sendable, Equatable, Identifiable {
    /// Como a ordem pode ser cancelada.
    public enum Cancellation: String, Sendable, Equatable, CaseIterable {
        /// Pedido assinado ao protocolo (CoW), sem taxa de rede. Nao e garantido: um
        /// solver que ja estiver liquidando ainda executa a ordem.
        case offchain
        /// Transacao na cadeia, com taxa de rede. Garantido depois que confirmar.
        case onchain
    }

    /// O identificador na rede: o UID da CoW (hex com `0x`), a Sequence da transacao que
    /// criou a oferta no XRP Ledger, o id da oferta na Stellar.
    public let id: String
    public let chain: Chain
    /// O `Asset.id` do que a ordem vende e do que recebe, e o `Asset` da lista quando o
    /// ativo esta nela (ordem criada fora da carteira pode ser de ativo fora da lista).
    public let sellAssetID: String
    public let buyAssetID: String
    public let sell: Asset?
    public let buy: Asset?
    /// O que ainda falta vender, na menor unidade.
    public let remainingSell: BigUInt
    /// O minimo que a ordem recebe pelo que ainda falta vender, pelo preco gravado.
    public let minimumBuy: BigUInt
    /// Quando a ordem vence sozinha. nil: nao vence, fica ate executar ou ser cancelada.
    public let expiresAt: Date?
    /// Quantas fontes independentes mostraram a ordem (1 onde o protocolo so tem uma API).
    public let sources: Int
    /// Os jeitos de cancelar esta ordem, do preferido para o outro.
    public let cancellations: [Cancellation]
    /// O valor inteiro que a ordem vende e o que ja entrou, onde o protocolo diz (CoW).
    /// Sem eles, a tela nao mostra andamento.
    public let totalSell: BigUInt?
    public let receivedBuy: BigUInt?
    /// Quando a ordem foi criada, onde o protocolo diz (CoW). nil: nao se sabe.
    public let createdAt: Date?

    public init(
        id: String, chain: Chain, sellAssetID: String, buyAssetID: String, remainingSell: BigUInt, minimumBuy: BigUInt,
        expiresAt: Date?, sources: Int, cancellations: [Cancellation], totalSell: BigUInt? = nil, receivedBuy: BigUInt? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.chain = chain
        self.sellAssetID = sellAssetID
        self.buyAssetID = buyAssetID
        self.sell = Self.listed(sellAssetID, chain: chain)
        self.buy = Self.listed(buyAssetID, chain: chain)
        self.remainingSell = remainingSell
        self.minimumBuy = minimumBuy
        self.expiresAt = expiresAt
        self.sources = sources
        self.cancellations = cancellations
        self.totalSell = totalSell
        self.receivedBuy = receivedBuy
        self.createdAt = createdAt
    }

    /// Quanto da ordem ja foi preenchido, de 0 a 1. nil onde o total nao e conhecido.
    public var filledFraction: Double? {
        guard let totalSell, !totalSell.isZero else { return nil }
        let sold = totalSell.subtractingReportingUnderflow(remainingSell) ?? 0
        return OrderProgress.fraction(sold, of: totalSell)
    }

    static func listed(_ id: String, chain: Chain) -> Asset? {
        TokenRegistry.assets(on: chain).first { $0.id == id }
    }
}

extension OpenOrder {
    /// A mais recente primeiro (pedido do dono, 31/10/2026). A CoW diz quando a ordem nasceu;
    /// na Stellar e no XRP Ledger o numero da oferta so cresce, entao o maior e o mais novo.
    /// A ordem sem data vem depois das datadas, rede por rede.
    public static func newestFirst(_ orders: [OpenOrder]) -> [OpenOrder] {
        let position = Dictionary(Chain.all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return orders.sorted { a, b in
            switch (a.createdAt, b.createdAt) {
            case let (x?, y?): return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil):
                if a.chain.id != b.chain.id { return (position[a.chain.id] ?? .max) < (position[b.chain.id] ?? .max) }
                return (UInt64(a.id) ?? 0) > (UInt64(b.id) ?? 0)
            }
        }
    }
}

/// O andamento de uma ordem: quanto ja foi vendido e recebido, lido da rede.
public struct OrderProgress: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// Aberta: esperando o preco ou sendo preenchida.
        case open
        /// Preenchida por inteiro.
        case filled
        /// O prazo passou; o que nao foi preenchido continua na carteira.
        case expired
        /// Cancelada; o que nao foi preenchido continua na carteira.
        case cancelled
    }

    public let id: String
    public let state: State
    public let totalSell: BigUInt
    public let soldSell: BigUInt
    public let receivedBuy: BigUInt
    /// O minimo que a ordem inteira garante.
    public let minimumBuy: BigUInt
    public let expiresAt: Date?

    public init(id: String, state: State, totalSell: BigUInt, soldSell: BigUInt, receivedBuy: BigUInt, minimumBuy: BigUInt, expiresAt: Date?) {
        self.id = id
        self.state = state
        self.totalSell = totalSell
        self.soldSell = soldSell
        self.receivedBuy = receivedBuy
        self.minimumBuy = minimumBuy
        self.expiresAt = expiresAt
    }

    /// De 0 a 1, pelo que ja foi vendido.
    public var fraction: Double {
        state == .filled ? 1 : Self.fraction(soldSell, of: totalSell)
    }

    /// `part / total` em ponto flutuante, sem estourar com valores de 18 casas.
    static func fraction(_ part: BigUInt, of total: BigUInt) -> Double {
        guard !total.isZero else { return 0 }
        let scaled = (min(part, total) * BigUInt(1_000_000) / total).uint64 ?? 0
        return Double(scaled) / 1_000_000
    }

    /// Terminou, por qualquer motivo: nao muda mais.
    public var isFinal: Bool { state != .open }
}

/// O motor de troca de uma rede: cotar entre provedores, montar o plano validado,
/// transmitir. Ordens limite quando a rede tem protocolo nao custodial para elas.
public protocol TradeEngine: Sendable {
    func quote(_ request: TradeRequest) async throws -> TradeQuote
    func plan(_ request: TradeRequest, quote: TradeQuote) async throws -> SigningPlan
    func planLimitOrder(_ request: LimitOrderRequest) async throws -> SigningPlan
    /// Transmite qualquer plano deste motor: troca, ordem limite e cancelamento.
    func submit(_ signed: [SignedTransaction], plan: SigningPlan) async throws -> [String]
    var supportsLimitOrders: Bool { get }
    /// Onde fica o dinheiro enquanto a ordem espera, dito como fato.
    var limitCustodyNote: String { get }

    /// As ordens limite abertas da conta, lidas da rede (das duas fontes quando o leitor
    /// tem duas). Onde nao ha ordem limite, `SendEngineError.unavailable`.
    func openOrders(account: DerivedAccount) async throws -> [OpenOrder]
    /// O plano que cancela a ordem, por um dos jeitos que `order.cancellations` oferece.
    /// O plano sai com `kind == .cancelOrder` e vai para `submit` como os outros.
    /// `nonceQueue`: no EVM, a fila local da conta (o cancelamento na cadeia usa nonce).
    func planCancel(
        _ order: OpenOrder, walletID: UUID, account: DerivedAccount, via: OpenOrder.Cancellation, nonceQueue: PendingNonceQueue?
    ) async throws -> SigningPlan
    /// O andamento de uma ordem desta conta (o id que `submit` devolveu). Onde a rede nao
    /// tem ordem com andamento, `SendEngineError.unavailable`.
    func orderProgress(id: String, account: DerivedAccount) async throws -> OrderProgress

    /// Quanto da ordem a cadeia ja liquidou, lido no contrato e nao na API, e o tempo do ultimo bloco (a
    /// ordem assinada que a CoW disse ter recusado, `SignedOrders`).
    func onChainState(_ order: OpenOrder) async throws -> SignedOrderChainState
}

extension TradeEngine {
    public func openOrders(account: DerivedAccount) async throws -> [OpenOrder] {
        throw SendEngineError.unavailable(kitText("Ordens limite ainda não estão disponíveis nesta rede."))
    }

    public func planCancel(
        _ order: OpenOrder, walletID: UUID, account: DerivedAccount, via: OpenOrder.Cancellation, nonceQueue: PendingNonceQueue?
    ) async throws -> SigningPlan {
        throw SendEngineError.unavailable(kitText("Ordens limite ainda não estão disponíveis nesta rede."))
    }

    public func onChainState(_ order: OpenOrder) async throws -> SignedOrderChainState {
        throw SendEngineError.unavailable(kitText("O andamento da ordem não está disponível nesta rede."))
    }

    public func orderProgress(id: String, account: DerivedAccount) async throws -> OrderProgress {
        throw SendEngineError.unavailable(kitText("O andamento da ordem não está disponível nesta rede."))
    }

    /// Cancela pelo jeito escolhido, sem fila local.
    public func planCancel(_ order: OpenOrder, walletID: UUID, account: DerivedAccount, via: OpenOrder.Cancellation) async throws -> SigningPlan {
        try await planCancel(order, walletID: walletID, account: account, via: via, nonceQueue: nil)
    }

    /// Cancela pelo jeito preferido da ordem.
    public func planCancel(_ order: OpenOrder, walletID: UUID, account: DerivedAccount) async throws -> SigningPlan {
        guard let via = order.cancellations.first else { throw SendEngineError.unavailable(kitText("Esta ordem não pode ser cancelada pela carteira.")) }
        return try await planCancel(order, walletID: walletID, account: account, via: via, nonceQueue: nil)
    }
}

public enum TradeEngines {
    /// As redes com troca nesta versao, na ordem da interface.
    public static var chains: [Chain] { Chain.all.filter { engine(for: $0) != nil } }

    public static func engine(for chain: Chain) -> (any TradeEngine)? {
        switch chain.family {
        case .utxo: return EngineRegistry.utxoTrade(chain)
        case .evm: return EngineRegistry.evmTrade(chain)
        case .solana: return EngineRegistry.solanaTrade(chain)
        case .xrpl: return EngineRegistry.xrplTrade(chain)
        case .stellar: return EngineRegistry.stellarTrade(chain)
        case .tron: return EngineRegistry.tronTrade(chain)
        case .ton: return EngineRegistry.tonTrade(chain)
        case .sui: return EngineRegistry.suiTrade(chain)
        case .cardano: return EngineRegistry.cardanoTrade(chain)
        case .polkadot: return EngineRegistry.polkadotTrade(chain)
        case .near: return EngineRegistry.nearTrade(chain)
        case .aptos: return EngineRegistry.aptosTrade(chain)
        }
    }
}

/// Os degraus de impacto no preco (docs/design/produto-ux.md T1).
public enum PriceImpact: Sendable {
    case normal, visible, confirm, blocked

    public static func level(_ percent: Double?) -> PriceImpact {
        guard let percent else { return .normal }
        switch percent {
        case ..<1: return .normal
        case ..<5: return .visible
        case ..<15: return .confirm
        default: return .blocked
        }
    }
}
