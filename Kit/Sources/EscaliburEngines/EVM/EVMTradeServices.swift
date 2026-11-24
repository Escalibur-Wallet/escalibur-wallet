import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation

// Os servicos de rede que o motor de troca usa, cada um atras de um protocolo com as
// mesmas assinaturas do tipo real de EscaliburNetwork. Em producao sao os tipos reais;
// nos testes, respostas gravadas. Nenhum deles ve chave, assina ou decide seguranca: o
// que eles devolvem passa pela validacao de EscaliburChains antes de virar plano.

/// O estado da cadeia que a troca e a ordem limite leem (`TradeStateReader`): nonce de
/// duas fontes, baseFee, saldos e allowance (o menor de duas), codigo e pin do router, e
/// a simulacao `eth_simulateV1` em duas fontes.
protocol EVMTradeChainReading: Sendable {
    func network(chain: Chain, owner: EVMAddress, localNextNonce: UInt64?, gasEstimate: UInt64, l1DataFee: BigUInt?,
                 destinationHasCode: Bool) async throws -> EVMNetworkState
    func l1DataFee(chain: Chain, calldataSize: Int) async throws -> BigUInt?
    func token(chain: Chain, token: EVMAddress, owner: EVMAddress, spender: EVMAddress) async throws -> EVMTokenState
    func read(for quote: ValidatedTradeQuote, localNextNonce: UInt64?) async throws -> TradeChainState
    /// As pernas da divisao simuladas em sequencia, num bloco so, em duas fontes.
    func simulateSequence(_ legs: [TradeSimulationLeg]) async throws -> [TradeSimulation]
    func readCoW(intent: CoWLimitOrderIntent, openOrdersSellTotal: BigUInt, localNextNonce: UInt64?) async throws -> CoWChainState
    func readCancellation(chain: Chain, owner: EVMAddress, uid: [UInt8], localNextNonce: UInt64?) async throws -> EVMNetworkState
    /// Quanto da ordem da CoW a cadeia ja liquidou (o maximo depois do cancelamento), o menor de duas fontes.
    func cowFilledAmount(chain: Chain, uid: [UInt8]) async throws -> BigUInt
    /// O tempo do ultimo bloco, o menor de duas fontes.
    func latestBlockTimestamp(chain: Chain) async throws -> UInt64
}

extension TradeStateReader: EVMTradeChainReading {}

/// A API da CoW (`CoWClient`): cotacao da troca imediata, registro do appData, envio da
/// ordem assinada (com o UID conferido), andamento de uma ordem, soma das ordens abertas
/// e cancelamento fora da cadeia.
protocol EVMCoWService: Sendable {
    func quote(sellToken: EVMAddress, buyToken: EVMAddress, sellAmount: BigUInt, owner: EVMAddress, chain: Chain,
               appData: CoWAppData) async throws -> CoWQuote
    func order(uid: [UInt8], chain: Chain, expected: CoWOrder?) async throws -> CoWOrderStatus
    func registerAppData(_ appData: CoWAppData, chain: Chain) async throws
    func submit(_ plan: CoWLimitOrderPlan, signature: SignedTransaction) async throws -> [UInt8]
    func openSellTotal(owner: EVMAddress, sellToken: EVMAddress, chain: Chain) async throws -> BigUInt
    func openOrders(owner: EVMAddress, chain: Chain) async throws -> [CoWOrderStatus]
    func cancel(uids: [[UInt8]], chain: Chain, owner: EVMAddress, signature: SignedTransaction) async throws
}

extension CoWClient: EVMCoWService {}

/// Precos em dolar, como texto decimal, por id do CoinGecko. Servem para comparar
/// provedores (gas convertido para o token comprado) e para a checagem de sanidade contra
/// o oraculo. Nunca entram no minimo garantido, que e decodificado da calldata. O mesmo
/// oraculo das outras redes (Support/MarketReference.swift).
typealias EVMPriceOracle = TradePriceOracle
typealias EVMMarketPriceOracle = MarketPriceOracle

/// Quanto esperar pela confirmacao da autorizacao antes de enviar a ordem limite a CoW
/// (a CoW recusa ordem sem allowance).
struct EVMConfirmationPolicy: Sendable {
    let interval: Duration
    let attempts: Int

    /// Ate cerca de cinco minutos, perguntando a cada 1,5 segundo: nas redes de bloco
    /// rapido a autorizacao confirma em poucos segundos, e a ordem nao deve esperar mais.
    static let standard = EVMConfirmationPolicy(interval: .milliseconds(1_500), attempts: 200)
}

/// As ordens limite planejadas e ainda nao enviadas, pelo id do `SigningPlan`.
///
/// O contrato do motor devolve so o `SigningPlan`, e o envio a CoW precisa da ordem, do
/// UID e do appData que o planejador calculou junto. Guarda so dado publico, na memoria,
/// e cada entrada sai quando a CoW responde com certeza, ou vence: em 10 minutos se a ordem
/// ainda nao foi a CoW, no validTo dela se ja foi (terceira passada da auditoria de 03/11/2026).
actor EVMPendingLimitOrders {
    static let shared = EVMPendingLimitOrders()
    static let lifetime: TimeInterval = 10 * 60

    struct Entry {
        let plan: CoWLimitOrderPlan
        let storedAt: Date
        /// A autorizacao e o embrulho ja foram transmitidos uma vez: o reenvio confere o recibo antes.
        var prerequisitesSent = false
        /// A autorizacao e o embrulho ja confirmaram: o reenvio nao os manda de novo.
        var prerequisitesDone = false
        /// O appData ja esta registrado: o reenvio nao o registra de novo.
        var appDataDone = false
        /// A ordem assinada ja saiu para a CoW (ou pode ter saido): toda saida dali em diante leva a ordem,
        /// para o dono cancelar na cadeia.
        var orderSent = false

        func alive(_ now: Date) -> Bool {
            if orderSent, let validTo = CoWProtocol.validTo(ofUID: plan.uid) { return now.timeIntervalSince1970 < TimeInterval(validTo) }
            return now.timeIntervalSince(storedAt) < EVMPendingLimitOrders.lifetime
        }
    }

    private var plans: [UUID: Entry] = [:]

    func store(_ plan: CoWLimitOrderPlan, now: Date = .now) {
        plans = plans.filter { $0.value.alive(now) }
        plans[plan.signingPlan.id] = Entry(plan: plan, storedAt: now)
    }

    /// A ordem do plano, que fica no registro ate a CoW responder com certeza: o "Enviar de novo" de um
    /// envio incerto manda a mesma ordem assinada outra vez, e a CoW reconhece o UID (segunda passada da
    /// auditoria de 03/11/2026; antes ela saia no primeiro envio, e o reenvio dizia que a ordem venceu).
    /// `prerequisitesDone`: a autorizacao e o embrulho ja confirmaram, e o reenvio nao os manda de novo.
    func entry(_ id: UUID, now: Date = .now) -> Entry? {
        guard let entry = plans[id], entry.alive(now) else { return nil }
        return entry
    }

    func markPrerequisitesDone(_ id: UUID) {
        plans[id]?.prerequisitesDone = true
    }

    func markPrerequisitesSent(_ id: UUID) {
        plans[id]?.prerequisitesSent = true
    }

    func markAppDataDone(_ id: UUID) {
        plans[id]?.appDataDone = true
    }

    func markOrderSent(_ id: UUID) {
        plans[id]?.orderSent = true
    }

    /// A CoW respondeu com certeza (criou ou recusou): a ordem sai do registro.
    func finish(_ id: UUID) {
        plans[id] = nil
    }
}

/// Tudo o que o motor de troca usa da rede, junto. `live` e compartilhado pelo app
/// inteiro: o agregador guarda o circuit breaker e o cache de 10 s, e os leitores guardam
/// o `eth_chainId` ja conferido de cada provedor.
struct EVMTradeServices: Sendable {
    let aggregator: TradeAggregator
    let chainState: any EVMTradeChainReading
    let reader: EVMReader
    let cow: any EVMCoWService
    let prices: any EVMPriceOracle
    let pendingOrders: EVMPendingLimitOrders
    let confirmation: EVMConfirmationPolicy
    /// O endereco que vai aos agregadores na cotacao, a partir do dono: sorteado a cada rodada
    /// (`EVMTradeContext.quoteIntent`). Os testes com respostas gravadas usam o proprio dono.
    var quoteAddress: @Sendable (EVMAddress) -> EVMAddress = { _ in EVMTradeContext.randomAddress() }
    /// As ordens abertas do dono na CoW, guardadas para a cotacao.
    var openOrders = CoWOpenOrdersCache()

    static let live = EVMTradeServices(
        aggregator: TradeAggregator(), chainState: TradeStateReader(), reader: .shared, cow: CoWClient(),
        prices: EVMMarketPriceOracle(service: .shared), pendingOrders: .shared, confirmation: .standard
    )
}
