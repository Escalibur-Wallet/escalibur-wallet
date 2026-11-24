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

    /// Quantas transacoes desta conta ja entraram num bloco (`EVMReader.minedNonce`), igual em dois operadores. nil sem
    /// resposta, ou onde a rede nao tem fila de nonces.
    func minedNonce(chain: Chain, from: String) async -> UInt64?

    /// O que a rede diz de um envio sem resposta deste aparelho (`UnsureSends`). Mais fino que o `status`, onde "pendente"
    /// junta tres coisas que aqui decidem: ninguem respondeu, a rede respondeu que nao conhece, e a rede conhece mas ainda
    /// nao e final. Vai o registro inteiro: a conta que enviou (a NEAR so pergunta com ela) e o que o motor guardou
    /// (`unsureContext`). "A rede nao conhece" nunca sai de uma fonte so.
    func lookup(_ send: UnsureSend, chain: Chain) async -> SendLookup

    /// O que o motor precisa ter gravado junto do registro para perguntar pela transacao depois de o app reabrir, quando o
    /// que ele guarda na memoria nao existe mais. nil onde o id basta.
    func unsureContext(for plan: SigningPlan) -> String?
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
    /// Redes UTXO: as moedas de cada envio desta conta que a rede disse nao conhecer (`UnsureSends.coinsToSpend`). O envio
    /// gasta pelo menos uma de cada grupo que ainda esteja na conta, e so um dos dois pode confirmar.
    public let unsureCoins: [[String]]

    public init(
        walletID: UUID, chain: Chain, asset: Asset, account: DerivedAccount, destination: String, tag: String?,
        amount: BigUInt, sendAll: Bool, feeLevel: FeeLevel, utxoUsage: UTXOUsage?, knownAddresses: [String] = [],
        nonceQueue: PendingNonceQueue? = nil, unsureCoins: [[String]] = []
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
        self.unsureCoins = unsureCoins
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
///   fila acima dela, e o proximo plano reusa o nonce (so uma das duas executaria), salvo a de nonce ja
///   minerado, que sai sozinha (bug de 14/11/2026);
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
    /// 30 minutos, segue a regra da desconhecida (quinta passada da auditoria de 03/11/2026). `minedNonce`: quantas
    /// transacoes da conta ja entraram num bloco (`EVMReader.minedNonce`); a entrada abaixo dele sai sem perguntar mais.
    public static func pruned(_ entries: [Entry], now: Date = Date(), minedNonce: UInt64? = nil, settled: @Sendable (Entry) async -> Bool,
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
            // Nonce ja gasto num bloco, por ela ou por outra com o mesmo nonce (a mesma frase em outro aparelho): nenhuma
            // transacao com ele entra de novo. O recibo da antiga pode nao existir mais nos provedores (a publicnode o
            // apaga depois de uns 2 dias), e ela ficava vista e presa para sempre (bug de 14/11/2026). So depois de 30
            // minutos: o recibo nunca some antes disso, e o prazo cobre a reorganizacao e o par que infla o nonce contra
            // um honesto (revisao dos tres agentes de 14/11/2026).
            if let minedNonce, entry.nonce < minedNonce, now.timeIntervalSince(entry.sentAt) > staleAfter {
                gone.insert(entry.hash)
                continue
            }
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
            // Sumiu da rede, mas com o nonce ja gasto num bloco por outra transacao (a mesma frase em outro aparelho): sai
            // sozinha. As de cima seguem validas, porque o nonce de baixo delas ja foi usado; levar todas fazia o plano
            // seguinte reusar o nonce de uma viva (revisao dos tres agentes de 14/11/2026). A vencida abaixo dele ja saiu
            // pela regra do nonce minerado, porque o prazo e de pelo menos 30 minutos.
            if lowerSeen, answer == .unknown, age > grace(privateRoute: entry.privateRoute), let minedNonce, entry.nonce < minedNonce {
                gone.insert(entry.hash)
                continue
            }
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

/// O que a rede diz de uma transacao deste aparelho (`SendEngine.lookup`).
public enum SendLookup: Sendable, Equatable {
    /// Ninguem respondeu (rede fora do ar, provedor que falha, aparelho sem conexao), ou ainda nao da para concluir.
    case noAnswer
    /// As fontes responderam, e nenhuma conhece a transacao.
    case notFound
    /// A rede conhece a transacao, ainda sem resultado final: na fila, ou vista por uma fonte so.
    case seen
    /// Final, com sucesso.
    case confirmed
    /// Final, e nada saiu: entrou e falhou, ou venceu sem entrar, com a prova que cada motor exige (duas fontes ou todas).
    case failed(reason: String)
    /// Final na rede, mas sem prova de que o envio saiu ou nao (o numero da conta foi usado; o resultado veio de uma fonte
    /// so): deixa de segurar a conta, e a linha fica pendente com o texto do motor, que manda conferir. Nunca "falhou".
    case seenUnclear(note: String)
    /// Nao ha a quem perguntar (rede que esta versao nao conhece mais, registro antigo sem o que o motor precisa): so o
    /// tempo desde o envio decide.
    case unknowable

    /// O estado de um leitor de duas fontes. `failure` da o texto da tela para o codigo da rede.
    init(_ status: TransactionStatus, failure: (String) -> String) {
        switch status {
        case .notFound: self = .notFound
        case .pending: self = .seen
        case .confirmed: self = .confirmed
        case .failed(let reason): self = .failed(reason: failure(reason))
        }
    }

    /// O que todos os donos dizem depois de os dois sorteados nao conhecerem a transacao (`TransactionPresence`): um que
    /// conheca basta para "vista"; "nao encontrada" so com todos respondendo sem conhecer; a leitura que falhou (nil) e o
    /// resto ficam sem resposta, que nunca solta a conta.
    init(_ presence: TransactionPresence?) {
        switch presence {
        case .known: self = .seen
        case .unknown: self = .notFound
        case .unclear, nil: self = .noAnswer
        }
    }
}

/// Um envio deste aparelho, fora da EVM, transmitido sem resposta certa da rede (pentest de 17/11/2026, achado antigo).
/// Fica nos metadados cifrados, gravado antes de os bytes sairem e tirado quando a transmissao responde: o envio que
/// ficou sem resposta nao some com a tela (o travar, a carteira fechada, o app morto pelo sistema), a Atividade segue
/// mostrando a linha, e a conta nao monta outro envio por cima dele antes de a rede dizer se saiu. Antes, fechar a
/// tela apagava o unico rastro, e o dono podia pagar duas vezes. Na EVM a fila de nonces ja faz esse papel.
/// Sem os bytes assinados: so o que a rede mostra publicamente, como o cache do historico.
public struct UnsureSend: Codable, Equatable, Sendable {
    public let wallet: UUID
    public let chainID: String
    /// A conta que enviou.
    public let address: String
    /// O id calculado dos bytes assinados, o mesmo que o explorador entende.
    public let hash: String
    /// Quando os bytes sairam pela ultima vez: transmitir de novo os mesmos bytes refaz a hora e as marcas.
    public var sentAt: Date
    public let asset: Asset
    public let amount: BigUInt
    public let recipient: String?
    /// A rede ja conheceu a transacao (`SendLookup.seen`): o envio saiu, deixa de segurar a conta e espera um bloco.
    public var seen: Bool?
    /// A primeira vez que a rede respondeu que nao conhece a transacao: o prazo conta daqui, nunca da hora do envio.
    public var unseenSince: Date?
    /// O que o motor disse quando a resposta nao prova se o envio saiu (`SendLookup.seenUnclear`), para a linha da Atividade.
    public var note: String?
    /// O que o motor da rede guardou para perguntar pela transacao depois de o app reabrir (`SendEngine.unsureContext`): na
    /// Polkadot, o numero da transacao na conta e a era. So ele le.
    public let context: String?
    /// Redes UTXO: a rede disse que nao conhece o envio, ou ele passou do teto na fila, sem prova de que nao sai. Quem recebeu
    /// os bytes pode transmiti-los depois, e no Bitcoin a transacao nao vence: o registro deixa de segurar a conta e de
    /// aparecer na Atividade, e vira a marca que obriga o proximo envio da conta a gastar uma das mesmas moedas
    /// (rodada dos 3 agentes de 19/11/2026).
    public var coinsHeld: Bool?

    public init(wallet: UUID, chainID: String, address: String, hash: String, sentAt: Date, asset: Asset, amount: BigUInt, recipient: String?,
                seen: Bool? = nil, unseenSince: Date? = nil, note: String? = nil, context: String? = nil, coinsHeld: Bool? = nil) {
        self.wallet = wallet
        self.chainID = chainID
        self.address = address
        self.hash = hash
        self.sentAt = sentAt
        self.asset = asset
        self.amount = amount
        self.recipient = recipient
        self.seen = seen
        self.unseenSince = unseenSince
        self.note = note
        self.context = context
        self.coinsHeld = coinsHeld
    }

    /// A linha de "Pendentes" da Atividade, com o mesmo id da linha de um envio que saiu. `unanswered`: a nota enquanto a
    /// rede nao diz nada. A que a rede ja conhece vai sem nota, como qualquer envio esperando confirmacao.
    public func entry(unanswered: String?) -> ActivityEntry {
        ActivityEntry(id: "enviado-\(chainID)-\(hash)", chainID: chainID, direction: .sent, asset: asset, amount: amount, counterparty: recipient,
                      date: sentAt, status: .pending(note ?? (seen == true ? nil : unanswered)), fee: nil, hash: hash, suspicious: false)
    }
}

/// A regra dos envios sem resposta, a mesma no iOS e no Android.
public enum UnsureSends {
    /// Depois de a rede responder que nao conhece a transacao, por quanto tempo o registro ainda fica: o mesmo prazo da
    /// transacao EVM que a rede nao conhece (`NonceQueuePruning.staleAfter`). A validade da transacao e de 1 a 15 minutos em
    /// quase todas as redes daqui, e o motor responde "venceu" com prova. Na NEAR (86.400 blocos) e na Sui (a epoca) ela vale
    /// por horas, e no Bitcoin nao vence: ali o que impede os dois envios de sair e o nonce da conta, o objeto de gas e, no
    /// Bitcoin, a fila que as duas fontes veem.
    public static let staleAfter: TimeInterval = NonceQueuePruning.staleAfter

    /// A linha do envio que a rede fechou sem prova (`SendLookup.seenUnclear`): fica um dia, como a linha de qualquer envio
    /// feito aqui que a leitura da rede ainda nao trouxe.
    public static let unclearKept: TimeInterval = 24 * 3600

    /// O teto de qualquer registro. E o prazo em que um no do Bitcoin tira da fila a transacao parada (336 horas, o padrao
    /// do Bitcoin Core): passou disso, "na fila" ou "sem resposta" e defeito de um provedor ou do motor, e a conta nao fica
    /// presa para sempre por ele.
    public static let longestKept: TimeInterval = 14 * 24 * 3600

    /// O prefixo do `context` das redes UTXO: as moedas que o envio gasta, "utxo:txid:vout,txid:vout".
    public static let coinsPrefix = "utxo:"

    /// Por quanto tempo a marca das moedas fica, contado do envio. A transacao do Bitcoin nao vence, e quem guardou os bytes
    /// pode transmiti-los a qualquer hora enquanto as moedas nao forem gastas; a marca so obriga o proximo envio a gastar uma
    /// delas e some quando um envio que gasta uma delas sai. O teto so evita lista sem fim numa conta que nunca mais envia.
    public static let coinsKept: TimeInterval = 180 * 24 * 3600

    public enum Step: Sendable, Equatable {
        /// Fica, talvez com marcas novas (vista, a hora da primeira resposta "nao conhece", a nota do motor).
        case keep(UnsureSend)
        /// Confirmado: vira envio feito.
        case sent
        /// Sai sem ter saido, ou sem a rede provar que saiu. `reason`: o que o motor disse, quando disse.
        case dropped(reason: String?)
    }

    /// O que fazer com um registro, dada a resposta da rede.
    /// - Sem resposta: nada muda. O aparelho sem conexao, ou o provedor fora do ar, nunca libera a conta sozinho (revisao dos
    ///   3 agentes, 17/11/2026: antes o prazo contava da hora do envio, e 30 minutos sem rede soltavam a conta sem ninguem ter
    ///   perguntado nada).
    /// - A rede nao conhece: o prazo comeca na primeira resposta dessas, e o registro so sai numa resposta igual depois dele.
    /// - A rede conhece: o envio saiu. Deixa de segurar a conta e segue em "Pendentes" ate confirmar (uma transacao de
    ///   Bitcoin espera horas na fila, e sumir dali levava a enviar de novo).
    /// - Redes UTXO: o que sairia sem prova (a rede nao conhece, ou o teto) vira a marca das moedas (`coinsHeld`), que nao
    ///   segura a conta nem aparece na Atividade, e obriga o proximo envio a gastar uma das mesmas moedas: se quem recebeu os
    ///   bytes os transmitir depois, so um dos dois envios confirma (rodada dos 3 agentes de 19/11/2026).
    public static func step(_ record: UnsureSend, lookup: SendLookup, now: Date = Date()) -> Step {
        if record.coinsHeld == true {
            if case .confirmed = lookup { return .sent }
            return abs(now.timeIntervalSince(record.sentAt)) > coinsKept ? .dropped(reason: nil) : .keep(record)
        }
        let next = plainStep(record, lookup: lookup, now: now)
        guard case .dropped(reason: nil) = next, !coins(of: record).isEmpty else { return next }
        var mark = record
        mark.coinsHeld = true
        mark.seen = nil
        mark.unseenSince = nil
        mark.note = nil
        return .keep(mark)
    }

    private static func plainStep(_ record: UnsureSend, lookup: SendLookup, now: Date) -> Step {
        switch lookup {
        case .confirmed: return .sent
        case .failed(let reason): return .dropped(reason: reason)
        default: break
        }
        // A distancia ate a hora do envio nos dois sentidos: o relogio do aparelho pode ter andado para tras.
        let age = abs(now.timeIntervalSince(record.sentAt))
        guard age <= longestKept else { return .dropped(reason: nil) }
        var next = record
        switch lookup {
        case .confirmed, .failed, .noAnswer:
            return .keep(record)
        case .seen:
            next.seen = true
            next.unseenSince = nil
            next.note = nil
            return .keep(next)
        case .notFound:
            // A primeira resposta "nao conhece", ou a hora dela ficou a frente do relogio (ele andou para tras): conta daqui.
            guard let since = record.unseenSince, since <= now.addingTimeInterval(60) else {
                next.unseenSince = now
                return .keep(next)
            }
            return now.timeIntervalSince(since) > staleAfter ? .dropped(reason: nil) : .keep(record)
        case .seenUnclear(let note):
            guard age <= unclearKept else { return .dropped(reason: nil) }
            next.seen = true
            next.unseenSince = nil
            next.note = note
            return .keep(next)
        case .unknowable:
            return age > staleAfter ? .dropped(reason: nil) : .keep(record)
        }
    }

    /// O registro segura o envio seguinte da conta enquanto a rede nao disse se o envio saiu.
    public static func blocks(_ record: UnsureSend) -> Bool { record.seen != true && record.coinsHeld != true }

    /// O registro aparece em "Pendentes": a marca das moedas, nao.
    public static func shown(_ record: UnsureSend) -> Bool { record.coinsHeld != true }

    /// As moedas que o envio gasta ("txid:vout"), do `context` das redes UTXO; vazio nas outras.
    public static func coins(of record: UnsureSend) -> [String] {
        guard let context = record.context, context.hasPrefix(coinsPrefix) else { return [] }
        return context.dropFirst(coinsPrefix.count).split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    /// Os grupos de moedas que o proximo envio desta conta tem de reaproveitar: um por marca (`SendRequest.unsureCoins`).
    public static func coinsToSpend(in list: [UnsureSend], wallet: UUID, chainID: String, address: String) -> [[String]] {
        list.filter { $0.wallet == wallet && $0.chainID == chainID && $0.address == address && $0.coinsHeld == true }
            .map(coins(of:)).filter { !$0.isEmpty }
    }

    static func same(_ a: String, _ b: String) -> Bool { a.lowercased() == b.lowercased() }

    /// A lista com este envio anotado. O mesmo id de novo (transmitir de novo os mesmos bytes) refaz a hora e as marcas.
    public static func recording(_ send: UnsureSend, in list: [UnsureSend]) -> [UnsureSend] {
        list.filter { !($0.wallet == send.wallet && $0.chainID == send.chainID && same($0.hash, send.hash)) } + [send]
    }

    /// A lista sem o envio com este id nesta carteira e nesta rede (a transmissao respondeu, ou a rede confirmou). As marcas
    /// cujas moedas este envio gasta saem junto: o envio que saiu disputa a moeda com o antigo, e so um dos dois confirma.
    public static func removing(hash: String, wallet: UUID, chainID: String, from list: [UnsureSend]) -> [UnsureSend] {
        let spent = Set(list.filter { $0.wallet == wallet && $0.chainID == chainID && same($0.hash, hash) && $0.coinsHeld != true }
            .flatMap(coins(of:)).map { $0.lowercased() })
        return list.filter { record in
            guard record.wallet == wallet, record.chainID == chainID else { return true }
            if same(record.hash, hash) { return false }
            return !(record.coinsHeld == true && coins(of: record).contains { spent.contains($0.lowercased()) })
        }
    }

    /// Os envios desta conta nesta rede que ainda seguram o seguinte.
    public static func pending(in list: [UnsureSend], wallet: UUID, chainID: String, address: String) -> [UnsureSend] {
        list.filter { $0.wallet == wallet && $0.chainID == chainID && $0.address == address && blocks($0) }
    }

    /// O registro so existe fora da EVM: la a fila de nonces segura a conta, com a regra dela.
    public static func applies(to chain: Chain) -> Bool { chain.family != .evm }
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

    public func minedNonce(chain: Chain, from: String) async -> UInt64? { nil }

    /// Sem leitura propria (a EVM, que nao usa o registro): o `status`, e pendente conta como "sem resposta", que nunca
    /// tira nada do registro.
    public func lookup(_ send: UnsureSend, chain: Chain) async -> SendLookup {
        switch await status(send.hash, chain: chain) {
        case .confirmed: return .confirmed
        case .failed(let reason): return .failed(reason: reason)
        case .pending: return .noAnswer
        }
    }

    public func unsureContext(for plan: SigningPlan) -> String? { nil }
}
