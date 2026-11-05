import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation

/// O que o app precisa de cada rede para enviar: saber do destino, calcular o
/// maximo, montar o plano validado, transmitir e acompanhar.
///
/// Cada rede tem um motor que junta o leitor de estado (EscaliburNetwork) e o
/// planejador (EscaliburChains). O app nunca monta transacao: ele entrega a
/// intencao, e o planejador valida e monta. Nada aqui assina.
public protocol SendEngine: Sendable {
    /// O que a rede sabe do destino antes do valor: se existe, se exige tag ou memo,
    /// se e contrato.
    func destination(_ address: String, chain: Chain) async throws -> DestinationInfo

    /// Quanto do ativo pode sair agora, ja descontando reserva e taxa.
    func spendable(_ request: SendRequest) async throws -> Spendable

    /// Le o estado, valida e monta o plano. Nada e assinado aqui. O plano sai com
    /// `review.recipient` e `review.recipientTag`, que o app confere contra o digitado.
    func plan(_ request: SendRequest) async throws -> SigningPlan

    /// Transmite os mesmos bytes assinados. Devolve o id que o explorador entende,
    /// calculado localmente a partir dos bytes, nunca o que o provedor devolveu.
    func broadcast(_ signed: [SignedTransaction], chain: Chain) async throws -> String

    func status(_ id: String, chain: Chain) async -> TransferStatus

    /// O que a rede diz da transacao desta conta com este nonce (`EVMReader.Sighting`): vista por dois
    /// operadores, desconhecida de dois, ou parcial. nil sem resposta, ou onde a rede nao tem fila de nonces.
    func sighting(_ id: String, chain: Chain, from: String, nonce: UInt64) async -> EVMReader.Sighting?
}

public struct SendRequest: Sendable {
    public let walletID: UUID
    public let chain: Chain
    public let asset: Asset
    public let account: DerivedAccount
    public let destination: String
    /// Tag de destino (XRP Ledger), memo (Stellar, Tron) ou comentario (TON).
    public let tag: String?
    public let amount: BigUInt
    public let sendAll: Bool
    public let feeLevel: FeeLevel
    public let utxoUsage: UTXOUsage?
    /// Enderecos para onde esta carteira ja enviou nesta rede, para os avisos do plano.
    public let knownAddresses: [String]
    /// EVM: a fila local de transacoes desta conta ainda em transito. Sem ela, as fontes
    /// de nonce tem de concordar exatamente.
    public let nonceQueue: PendingNonceQueue?

    public init(
        walletID: UUID, chain: Chain, asset: Asset, account: DerivedAccount, destination: String, tag: String?,
        amount: BigUInt, sendAll: Bool, feeLevel: FeeLevel, utxoUsage: UTXOUsage?, knownAddresses: [String] = [],
        nonceQueue: PendingNonceQueue? = nil
    ) {
        self.walletID = walletID
        self.chain = chain
        self.asset = asset
        self.account = account
        self.destination = destination
        self.tag = tag
        self.amount = amount
        self.sendAll = sendAll
        self.feeLevel = feeLevel
        self.utxoUsage = utxoUsage
        self.knownAddresses = knownAddresses
        self.nonceQueue = nonceQueue
    }
}

/// A fila local de transacoes EVM de uma conta: o que este aparelho transmitiu e a rede
/// ainda nao confirmou (auditoria 2, M1).
///
/// O app guarda, por carteira, rede e endereco, cada transacao transmitida (nonce e id)
/// ate o `status` dela dizer confirmada ou falhou, e o proximo nonce depois da ultima. O
/// motor le a rede em duas fontes e so aceita a diferenca entre elas que estas
/// transacoes explicam; sem a fila, as fontes tem de concordar exatamente.
public struct PendingNonceQueue: Sendable, Equatable {
    /// O nonce seguinte ao da ultima transacao transmitida desta conta.
    public let nextNonce: UInt64
    /// Os ids (hash) das transacoes transmitidas e ainda nao confirmadas, em ordem de
    /// nonce. Os nonces delas sao `nextNonce - pendingHashes.count` ate `nextNonce - 1`.
    public let pendingHashes: [String]

    public init(nextNonce: UInt64, pendingHashes: [String]) {
        self.nextNonce = nextNonce
        self.pendingHashes = pendingHashes
    }
}

extension PendingNonceQueue {
    /// A fila a partir das transacoes que o app anotou: so a sequencia consecutiva que
    /// termina no maior nonce, porque o contrato le os nonces como `nextNonce - count`
    /// ate `nextNonce - 1`. Um buraco quer dizer que algo antes dele ja saiu da conta de
    /// quem esta em transito. Sem entradas, nil.
    public static func trailingRun(_ entries: [(nonce: UInt64, hash: String)]) -> PendingNonceQueue? {
        let sorted = entries.sorted { $0.nonce < $1.nonce }
        guard let last = sorted.last else { return nil }
        var run = [last]
        for entry in sorted.dropLast().reversed() {
            guard entry.nonce + 1 == run[0].nonce else { break }
            run.insert(entry, at: 0)
        }
        return PendingNonceQueue(nextNonce: last.nonce + 1, pendingHashes: run.map(\.hash))
    }
}

/// O que a poda da fila de nonces tira, e o que a rede ja viu, a mesma regra no iOS e no Android
/// (terceira e quarta passadas da auditoria de 03/11/2026). O app nunca pula um nonce nem reusa o de uma
/// transacao viva:
/// - sai a transacao confirmada ou falha num bloco;
/// - a que a rede nao conhece depois do prazo de propagacao (recusada ou descartada) sai junto com toda a
///   fila acima dela, e o proximo plano reusa o nonce (so uma das duas executaria);
/// - so se pergunta pela de cima quando todas as de baixo foram vistas: uma transacao publica empilhada
///   sobre uma privada ainda nao minerada fica parada no no, sem propagar, e pareceria perdida;
/// - os 30 minutos so tiram a que a rede nao conhece; a conhecida fica ate sair num bloco;
/// - a que a rede ainda nao viu (`seen`) trava a conta inteira: o plano seguinte e recusado em vez de
///   pular o nonce dela (`NonceQueue.unseen` no iOS, `FilaDeNonces.naoVista` no Android).
public enum NonceQueuePruning {
    public struct Entry: Sendable, Equatable {
        public let nonce: UInt64
        public let hash: String
        public let sentAt: Date
        /// Saiu pela rota privada (protecao de MEV na Ethereum): os provedores so a veem num bloco.
        public let privateRoute: Bool
        /// Dois operadores ja a viram numa poda anterior: uma resposta que falha agora nao a tira em 30 minutos.
        public let wasSeen: Bool
        /// A ultima poda em que uma de baixo vista a segurou: o prazo dela conta dali, e nao do envio (decima passada).
        public let heldAt: Date?
        /// A primeira poda em que ela, ja segurada, deixou de estar: o prazo recomeca dali (decima primeira passada).
        public let releasedAt: Date?

        public init(nonce: UInt64, hash: String, sentAt: Date, privateRoute: Bool, wasSeen: Bool = false, heldAt: Date? = nil,
                    releasedAt: Date? = nil) {
            self.nonce = nonce
            self.hash = hash
            self.sentAt = sentAt
            self.privateRoute = privateRoute
            self.wasSeen = wasSeen
            self.heldAt = heldAt
            self.releasedAt = releasedAt
        }
    }

    public struct Result: Sendable, Equatable {
        /// Os hashes que saem da fila.
        public let gone: Set<String>
        /// Os que ficam e que a rede conhece agora (no mempool de um provedor).
        public let seen: Set<String>
        /// Os que ficam segurados por uma de baixo: vista agora, ou que ficou sem ser vista e por isso a de cima nem foi
        /// perguntada (decima segunda passada). Quem chama grava a hora (`heldAt`) e apaga a `releasedAt`.
        public var held: Set<String> = []
        /// Os que estavam segurados e foram soltos nesta poda: quem chama grava a hora (`releasedAt`).
        public var released: Set<String> = []
    }

    /// Pendente ha mais que isto, e desconhecida da rede: descartada, ou o relay desistiu.
    public static let staleAfter: TimeInterval = 30 * 60

    /// A que dois operadores ja viram e que agora so um conhece (ou faltou resposta): fica ate isto. E um limite
    /// escolhido, e nao uma regra da rede (a transacao executavel parada pela taxa nao expira por tempo no geth): o
    /// bastante para os provedores que falharam voltarem, sem prender a conta para sempre por um provedor fora do
    /// ar. Antes saia em 30 minutos numa poda so, e o plano seguinte pulava ou reusava o nonce de uma transacao viva
    /// (sexta passada de 03/11/2026).
    public static let seenStaleAfter: TimeInterval = 3 * 60 * 60

    /// Ate quando a rede pode ainda nao conhecer a transacao: a publica aparece nos provedores em segundos;
    /// a da rota privada so aparece num bloco, e os relays desistem depois de uns 25 blocos.
    public static func grace(privateRoute: Bool) -> TimeInterval { privateRoute ? 10 * 60 : 30 }

    /// `settled`: a rede ja confirmou ou recusou num bloco. `known`: o que a rede diz da transacao. Vista so com
    /// dois operadores (`seen`); a que so um conhece, ou sem resposta, fica sem contar como vista e, depois dos
    /// 30 minutos, segue a regra da desconhecida (quinta passada da auditoria de 03/11/2026).
    public static func pruned(_ entries: [Entry], now: Date = Date(), settled: @Sendable (Entry) async -> Bool,
                              known: @Sendable (Entry) async -> EVMReader.Sighting?) async -> Result {
        var gone = Set<String>()
        var seen = Set<String>()
        var held = Set<String>()
        var released = Set<String>()
        var lowerSeen = true
        var lostFrom: UInt64?
        // O prazo mais tarde das de baixo que ficam, como instante (o "Enviar de novo" refaz a hora do envio da de
        // baixo): a de cima nao perguntada nunca sai por tempo antes delas. Saindo antes, a fila dava o nonce dela como
        // o proximo quando a de baixo voltasse, com ela viva (oitava e nona passadas de 03/11/2026).
        var lowerDeadline = Date.distantPast
        for entry in entries.sorted(by: { $0.nonce < $1.nonce }) {
            if await settled(entry) {
                gone.insert(entry.hash)
                continue
            }
            guard lostFrom == nil else { continue }
            let age = now.timeIntervalSince(entry.sentAt)
            let answer = lowerSeen ? await known(entry) : nil
            if answer == .seen {
                seen.insert(entry.hash)
                // Vista agora: fica ate sair num bloco, e a de cima nao sai por tempo enquanto ela estiver na rede
                // (nona passada da auditoria de 03/11/2026).
                lowerDeadline = .distantFuture
                continue
            }
            // O prazo conta do envio, da ultima poda em que uma de baixo vista a segurou, ou da poda em que foi solta:
            // confirmada a de baixo, a de cima nao sai na mesma poda por um prazo que ja tinha passado enquanto esperava
            // (decima passada), nem quando a poda que a solta vem horas depois, com o app fechado (decima primeira).
            let soltaAgora = entry.heldAt != nil && entry.releasedAt == nil && lowerDeadline != .distantFuture
            let base = soltaAgora ? now : max(entry.sentAt, entry.heldAt ?? entry.sentAt, entry.releasedAt ?? entry.sentAt)
            let deadline = max(base.addingTimeInterval(entry.wasSeen ? seenStaleAfter : staleAfter), lowerDeadline)
            if lowerSeen, answer == .unknown, age > grace(privateRoute: entry.privateRoute) {
                lostFrom = entry.nonce
            } else if now > deadline {
                lostFrom = entry.nonce
            } else if lowerDeadline == .distantFuture || !lowerSeen {
                // Segurada por uma de baixo vista agora, ou nao perguntada porque uma de baixo ficou: o prazo dela recomeca
                // quando for solta. Antes, a nao perguntada corria o prazo proprio enquanto esperava, e saia na mesma poda
                // em que a de baixo confirmava (decima segunda passada da auditoria de 03/11/2026).
                held.insert(entry.hash)
            } else if soltaAgora {
                released.insert(entry.hash)
            }
            lowerDeadline = deadline
            lowerSeen = false
        }
        if let lostFrom { gone.formUnion(entries.filter { $0.nonce >= lostFrom }.map(\.hash)) }
        var result = Result(gone: gone, seen: seen.subtracting(gone))
        result.held = held.subtracting(gone)
        result.released = released.subtracting(gone)
        return result
    }
}

extension EVMNetworkState {
    /// O estado lido da rede com a fila local do app e, numa troca em varias pernas, as
    /// transacoes das pernas anteriores deste mesmo plano (`plannedAhead`, que ainda nem
    /// foram transmitidas e que `plannedNext` segue).
    func applying(_ queue: PendingNonceQueue?, plannedNext: UInt64? = nil, plannedAhead: UInt64 = 0) -> EVMNetworkState {
        let next = plannedNext ?? queue?.nextNonce
        let pending = UInt64(queue?.pendingHashes.count ?? 0) + plannedAhead
        return withLocalQueue(nextNonce: next, pendingCount: pending)
    }
}

public enum FeeLevel: String, Sendable, CaseIterable { case slow, normal, fast }

public struct DestinationInfo: Sendable {
    public var exists: Bool
    /// A propria rede exige tag/memo (RequireDest, SEP-29).
    public var requiresTag: Bool
    public var isContract: Bool
    /// Minimo para ativar a conta de destino, quando ela ainda nao existe.
    public var activationMinimum: BigUInt?
    public var note: String?

    public init(exists: Bool = true, requiresTag: Bool = false, isContract: Bool = false, activationMinimum: BigUInt? = nil, note: String? = nil) {
        self.exists = exists
        self.requiresTag = requiresTag
        self.isContract = isContract
        self.activationMinimum = activationMinimum
        self.note = note
    }
}

public struct Spendable: Sendable {
    public let amount: BigUInt
    /// "1 XRP fica reservado pela rede enquanto a conta existir."
    public let reserveNote: String?
    public let feeNote: String?

    public init(amount: BigUInt, reserveNote: String? = nil, feeNote: String? = nil) {
        self.amount = amount
        self.reserveNote = reserveNote
        self.feeNote = feeNote
    }
}

public enum TransferStatus: Sendable, Equatable {
    case pending
    case confirmed(detail: String?)
    case failed(reason: String)
}

/// O erro que a tela mostra. `message` ja vem em portugues, sem travessao e sem
/// dado que o provedor devolveu.
public enum SendEngineError: LocalizedError, Equatable {
    case unsupported(Chain)
    case message(String)
    /// O recurso nao existe nesta versao para esta rede (sem indexador publico, sem
    /// protocolo avaliado). Tentar de novo nao muda nada: a tela diz o motivo e nao
    /// oferece "tentar de novo".
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let chain): return "Enviar pela rede \(chain.name) chega numa atualização em breve. Receber já funciona."
        case .message(let text), .unavailable(let text): return text
        }
    }
}

/// Enderecos UTXO ja usados, por rede: indices de recebimento e troco.
public struct UTXOUsage: Codable, Equatable, Hashable, Sendable {
    public var receiveUsed: Int
    public var changeUsed: Int

    public init(receiveUsed: Int = 0, changeUsed: Int = 0) {
        self.receiveUsed = receiveUsed
        self.changeUsed = changeUsed
    }

    /// Os indices de recebimento que o aviso de recebimento confere: os dois ultimos usados e o
    /// proximo. Troco e moeda do proprio dono, nao recebimento; e conferir todos os usados juntos,
    /// do mesmo IP, de tempos em tempos, entregava ao provedor a ligacao entre eles (auditoria de
    /// privacidade, 22/10/2026).
    public var receiptIndices: ClosedRange<Int> { max(0, receiveUsed - 2)...max(0, receiveUsed) }
}

/// Os motores disponiveis nesta versao. Cada familia registra os seus no proprio
/// arquivo (Families/), para os motores de redes diferentes nunca disputarem linha.
public enum SendEngines {
    public static func engine(for chain: Chain) -> (any SendEngine)? {
        switch chain.family {
        case .utxo: return EngineRegistry.utxoSend(chain)
        case .evm: return EngineRegistry.evmSend(chain)
        case .solana: return EngineRegistry.solanaSend(chain)
        case .xrpl: return EngineRegistry.xrplSend(chain)
        case .stellar: return EngineRegistry.stellarSend(chain)
        case .tron: return EngineRegistry.tronSend(chain)
        case .ton: return EngineRegistry.tonSend(chain)
        case .sui: return EngineRegistry.suiSend(chain)
        case .cardano: return EngineRegistry.cardanoSend(chain)
        case .polkadot: return EngineRegistry.polkadotSend(chain)
        case .near: return EngineRegistry.nearSend(chain)
        case .aptos: return EngineRegistry.aptosSend(chain)
        }
    }
}

extension SendEngine {
    /// Depois de um envio, o novo uso de enderecos UTXO (indice de troco que
    /// avancou). Nil quando a rede nao tem isso ou nada mudou.
    public func usage(after plan: SigningPlan, current: UTXOUsage?) -> UTXOUsage? { nil }

    public func sighting(_ id: String, chain: Chain, from: String, nonce: UInt64) async -> EVMReader.Sighting? { nil }
}
