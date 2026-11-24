import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation

/// O motor de envio da NEAR: so NEAR, da conta implicita do dono.
///
/// Junta o `NEARReader`, que le o bloco de referencia, as duas contas, a chave de acesso
/// do dono, o preco do gas e as regras do protocolo em dois provedores concordando, e o
/// `NEARPlanner`, que valida e monta. Nada aqui assina.
///
/// `feeLevel` nao se aplica: a NEAR nao tem gorjeta na transacao comum, e a taxa e o gas
/// fixo da transferencia ao preco do bloco.
struct NEARSendEngine: SendEngine {
    let reader: NEARReader
    /// O relogio que data o plano. Troca so nos testes.
    let now: @Sendable () -> Date

    init(reader: NEARReader = .shared, now: @escaping @Sendable () -> Date = { .now }) {
        self.reader = reader
        self.now = now
    }

    // MARK: Destino

    /// Conta com nome tem de existir, lida em dois provedores: sem isso, nada segue. Conta
    /// implicita pode ainda nao existir; o primeiro envio a cria.
    func destination(_ address: String, chain: Chain) async throws -> DestinationInfo {
        try Self.requireNEAR(chain)
        let target = try Self.parsedDestination(address)
        do {
            let state = try await reader.destination(target)
            if target.kind == .named, state == nil { throw SendEngineError.message(NEAREngineText.namedMissing) }
            let contract = state?.hasContract ?? false
            return DestinationInfo(
                exists: state != nil, requiresTag: false, isContract: contract, activationMinimum: nil,
                note: state == nil ? NEAREngineText.newImplicit : (contract ? NEAREngineText.contractDestination : nil)
            )
        } catch {
            throw NEAREngineText.userError(error)
        }
    }

    // MARK: Maximo

    func spendable(_ request: SendRequest) async throws -> Spendable {
        do {
            let order = try Order(request)
            let state = try await chainState(order)
            let cost = NEARTransferCost.transfer(to: order.destination, destinationExists: state.destination != nil, rules: state.rules)
            return Spendable(
                amount: NEARPlanner.maximumSendable(to: order.destination, state: state),
                reserveNote: NEAREngineText.reserveNote(state.sender, rules: state.rules),
                feeNote: NEAREngineText.feeNote(cost)
            )
        } catch {
            throw NEAREngineText.userError(error)
        }
    }

    // MARK: Plano

    func plan(_ request: SendRequest) async throws -> SigningPlan {
        do {
            let order = try Order(request)
            let state = try await chainState(order)
            var amount = request.amount
            if request.sendAll {
                // Nunca mais do que o dono viu; menos, se o saldo ou a taxa mudaram.
                amount = min(amount, NEARPlanner.maximumSendable(to: order.destination, state: state))
                guard !amount.isZero else { throw SendEngineError.message(NEAREngineText.insufficient) }
            }
            let plan = try NEARPlanner.planSend(
                walletID: request.walletID, owner: order.owner, to: request.destination, amount: amount, state: state, now: now()
            )
            return try Self.reviewed(plan, for: request)
        } catch {
            throw NEAREngineText.userError(error)
        }
    }

    /// O estado inteiro no mesmo bloco, em dois provedores. A conta do dono tem de existir
    /// e ter a chave dele com acesso total.
    func chainState(_ order: Order) async throws -> NEARChainState {
        let reading = try await reader.state(owner: order.sender, publicKey: order.owner.publicKey, destination: order.destination)
        guard let sender = reading.sender else { throw SendEngineError.message(NEAREngineText.accountMissing) }
        guard let accessKey = reading.accessKey else { throw SendEngineError.message(NEAREngineText.keyNotOnAccount) }
        return NEARChainState(
            checkpoint: reading.checkpoint, sender: sender, accessKey: accessKey, destination: reading.destination, rules: reading.rules
        )
    }

    // MARK: Transmissao e acompanhamento

    /// So transmite a transacao que `NEARSignedTransaction.parse` aceita, com o id igual
    /// ao hash dos bytes. O id devolvido e o calculado aqui, o mesmo que `status` procura.
    func broadcast(_ signed: [SignedTransaction], chain: Chain) async throws -> String {
        try Self.requireNEAR(chain)
        guard signed.count == 1, let transaction = signed.first, (try? NEARSignedTransaction.parse(transaction)) != nil else {
            throw SendEngineError.message(NEAREngineText.notOurTransaction)
        }
        let receipt: BroadcastReceipt
        do {
            receipt = try await reader.broadcast(transaction)
        } catch {
            throw NEAREngineText.broadcastError(error)
        }
        guard receipt.id == transaction.id else { throw SendEngineError.message(NEAREngineText.answerMismatch) }
        return transaction.id
    }

    /// O resultado em dois provedores. Enquanto nao e final, ou a leitura falha,
    /// pendente: a tela continua perguntando.
    func status(_ id: String, chain: Chain) async -> TransferStatus {
        guard chain.id == Chain.near.id, let status = try? await reader.status(of: id) else { return .pending }
        switch status {
        case .notFound, .pending: return .pending
        case .confirmed: return .confirmed(detail: NEAREngineText.confirmed)
        case .failed(let reason): return .failed(reason: NEAREngineText.failure(reason))
        }
    }

    /// O que o `lookup` precisa depois de o app reabrir: o numero da transacao na chave de acesso (`nonce`) e a chave.
    func unsureContext(for plan: SigningPlan) -> String? {
        guard plan.transactions.count == 1, let transfer = plan.transactions.first as? NEARTransfer else { return nil }
        return "\(transfer.fields.nonce)|\(Base58.bitcoin.encode(transfer.fields.publicKey))"
    }

    /// Para o registro dos envios sem resposta. O leitor so pergunta pela transacao com a conta que assinou, que ele guarda
    /// na memoria: depois de o app reabrir, ela vem do registro.
    /// Nenhum dos dois conhecer nao basta: os nos RPC da NEAR esquecem a transacao em menos de um dia (conferido ao vivo em
    /// 18/11/2026). No historico da conta (`NEARReader.historyContains`), ela entrou. Fora dele (uma conta com muitas
    /// transacoes depois, ou o indexador fora do ar), decide o numero da chave guardado no registro (`unsureContext`), num
    /// bloco final igual em dois provedores: ja usado, ela (ou outra da mesma chave) entrou, e a linha manda conferir, sem
    /// nunca dizer que nao saiu; ainda livre, ela nao entrou, e o proximo envio sai com o mesmo numero, entao so um dos dois
    /// pode entrar e o dono nao paga duas vezes.
    func lookup(_ send: UnsureSend, chain: Chain) async -> SendLookup {
        guard chain.id == Chain.near.id, let status = try? await reader.status(of: send.hash, signer: send.address) else { return .noAnswer }
        guard case .notFound = status else { return SendLookup(status) { NEAREngineText.failure($0) } }
        let inHistory = try? await reader.historyContains(send.hash, owner: send.address)
        if inHistory == true { return .seen }
        // Registro sem o numero (o planejador sempre monta uma transacao so, entao nao acontece): o historico, uma fonte so,
        // nao diz sozinho que a rede nao conhece (rodada 4 da revisao de seguranca).
        guard let key = Self.unsureKey(send.context), case .success(let owner) = NEARAccountID.parse(send.address) else { return .noAnswer }
        let current: UInt64?
        do {
            current = try await reader.accessKeyNonce(owner: owner, publicKey: key.publicKey)
        } catch {
            return .noAnswer
        }
        // A chave saiu da conta: a transacao nao entra mais, e pode ter entrado antes.
        guard let current else { return .seenUnclear(note: NEAREngineText.nonceUsed) }
        return current >= key.nonce ? .seenUnclear(note: NEAREngineText.nonceUsed) : .notFound
    }

    /// O numero e a chave guardados pelo `unsureContext`.
    static func unsureKey(_ context: String?) -> (nonce: UInt64, publicKey: [UInt8])? {
        let parts = (context ?? "").split(separator: "|")
        guard parts.count == 2, let nonce = UInt64(parts[0]), let key = Base58.bitcoin.decode(String(parts[1])), key.count == 32 else {
            return nil
        }
        return (nonce, key)
    }

    // MARK: O pedido conferido

    /// O pedido conferido antes de qualquer leitura: rede, ativo, a chave contra a conta
    /// guardada e o destino.
    struct Order {
        let owner: NEAROwner
        let sender: NEARAccountID
        let destination: NEARAccountID

        init(_ request: SendRequest) throws {
            try NEARSendEngine.requireNEAR(request.chain)
            guard request.asset.chainID == Chain.near.id, request.asset.kind == .native else {
                throw SendEngineError.message(NEAREngineText.unsupportedAsset)
            }
            guard request.account.chainID == Chain.near.id, let sender = NEARAccountID(implicitPublicKey: request.account.publicKey),
                  sender.text == request.account.address
            else { throw SendEngineError.message(NEAREngineText.keyMismatch) }
            owner = NEAROwner(path: request.account.path, publicKey: request.account.publicKey)
            self.sender = sender
            destination = try NEARSendEngine.parsedDestination(request.destination)
        }
    }

    static func requireNEAR(_ chain: Chain) throws {
        guard chain.id == Chain.near.id else { throw SendEngineError.unsupported(chain) }
    }

    static func parsedDestination(_ text: String) throws -> NEARAccountID {
        switch Address.validate(text, for: .near) {
        case .failure(let problem):
            throw SendEngineError.message(NEAREngineText.address(problem))
        case .success(let destination):
            guard case .success(let account) = NEARAccountID.parse(destination.address) else {
                throw SendEngineError.message(NEAREngineText.address(.malformed))
            }
            return account
        }
    }

    // MARK: Revisao

    /// O plano so sai se o destino dele for o pedido, sem tag. Acrescenta os avisos que
    /// dependem de onde o dono ja enviou: primeiro envio e conta parecida com uma
    /// conhecida (docs/seguranca.md §4.10).
    static func reviewed(_ plan: SigningPlan, for request: SendRequest) throws -> SigningPlan {
        let review = plan.review
        guard review.kind == .send, plan.chain.id == Chain.near.id, plan.walletID == request.walletID,
              Address.sameRecipient(review.recipient, request.destination, chain: .near), review.recipientTag == nil
        else { throw SendEngineError.message(NEAREngineText.planMismatch) }

        var warnings = review.warnings
        let known = request.knownAddresses
        if let lookalike = AddressPoisoning.lookalike(request.destination, among: known + [request.account.address], chain: .near) {
            warnings.append(.lookalikeAddress(known: lookalike))
        }
        if !known.contains(where: { Address.sameRecipient($0, request.destination, chain: .near) }) {
            warnings.append(.firstSendToAddress)
        }
        return plan.addingWarnings(warnings)
    }
}
