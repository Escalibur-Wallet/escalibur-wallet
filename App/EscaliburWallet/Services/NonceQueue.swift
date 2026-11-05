import EscaliburChains
import EscaliburEngines
import Foundation

/// Uma transacao EVM transmitida deste aparelho e ainda sem confirmacao.
struct PendingEVMTransaction: Codable, Equatable {
    let nonce: UInt64
    let hash: String
    let sentAt: Date
    /// O ativo que esta transacao tira da conta (o id do `Asset`), na troca, no envio e na ponte: a
    /// proxima transacao do mesmo ativo espera ela confirmar (auditoria de 03/11/2026). nil nas antigas.
    var sells: String? = nil
    /// Saiu pela rota privada (protecao de MEV na Ethereum): os provedores so a veem num bloco, e a poda
    /// espera mais antes de dar por perdida (terceira passada de 03/11/2026). nil nas antigas e na publica.
    var privateRoute: Bool? = nil
    /// A rede conhecia a transacao na ultima poda (no mempool de um provedor). nil ou false: ainda nao vista,
    /// e a conta nao monta outra por cima (quarta passada da auditoria de 03/11/2026).
    var seen: Bool? = nil
    /// Dois operadores ja a viram numa poda, e isso nao volta atras: a que ja foi vista so sai por um bloco, por
    /// dois sem ela depois de perguntar a todos ou depois de 3 horas (sexta passada da auditoria de 03/11/2026).
    var everSeen: Bool? = nil
    /// A ultima poda em que uma de baixo vista a segurou (`NonceQueuePruning.Result.held`, decima passada).
    var heldAt: Date? = nil
    /// A primeira poda em que, segurada antes, deixou de estar (`NonceQueuePruning.Result.released`): o prazo recomeca
    /// dali, e nao da ultima vez em que foi segurada (decima primeira passada).
    var releasedAt: Date? = nil
}

/// A fila local de nonces EVM, por carteira, rede e conta (auditoria 2, M1 dos motores).
///
/// Sem ela, o planejador exige que as duas fontes da rede concordem no nonce, e um
/// segundo envio logo depois do primeiro pode esbarrar num provedor que ainda nao viu
/// a transacao. Com ela, o planejador sabe o que este aparelho ja transmitiu. O perigo
/// e o contrario, uma entrada velha: a transacao que a rede descartou faria o proximo
/// plano usar um nonce que nunca executa. Por isso a fila e podada antes de cada plano
/// e esquecida quando o motor diz que ela esta a frente da rede.
@MainActor
enum NonceQueue {
    nonisolated static func key(wallet: UUID, chain: Chain, address: String) -> String {
        "\(wallet.uuidString)|\(chain.id)|\(address.lowercased())"
    }

    /// A fila para um pedido: nil fora da EVM ou sem transacao em transito. Os nonces
    /// vao consecutivos, terminando em `nextNonce - 1`, como o contrato pede.
    static func queue(_ session: AppSession, wallet: UUID, chain: Chain, address: String) -> PendingNonceQueue? {
        guard chain.family == .evm,
              let entries = session.metadata.pendingEVM?[key(wallet: wallet, chain: chain, address: address)], !entries.isEmpty
        else { return nil }
        return PendingNonceQueue.trailingRun(entries.map { ($0.nonce, $0.hash) })
    }

    /// Anota as transacoes EVM de um plano que acabou de ser transmitido.
    static func record(_ session: AppSession, wallet: UUID, chain: Chain, address: String, plan: SigningPlan, signed: [SignedTransaction],
                       sells: String? = nil, privately: Bool = false) {
        guard chain.family == .evm, plan.transactions.count == signed.count else { return }
        let now = Date()
        let key = key(wallet: wallet, chain: chain, address: address)
        // "Enviar de novo" dos mesmos bytes: a que a rede ja viu continua vista (setima passada de 03/11/2026).
        let old = session.metadata.pendingEVM?[key] ?? []
        let fresh = zip(plan.transactions, signed).compactMap { transaction, signature -> PendingEVMTransaction? in
            guard let evm = transaction as? EVMTransaction else { return nil }
            let wasSeen = old.contains { $0.hash == signature.id && ($0.everSeen == true || $0.seen == true) }
            return PendingEVMTransaction(nonce: evm.nonce, hash: signature.id, sentAt: now, sells: sells, privateRoute: privately ? true : nil,
                                         everSeen: wasSeen ? true : nil)
        }
        guard !fresh.isEmpty else { return }
        var all = session.metadata.pendingEVM ?? [:]
        let kept = (all[key] ?? []).filter { old in !fresh.contains { $0.nonce == old.nonce } }
        all[key] = kept + fresh
        session.metadata.pendingEVM = all
        try? session.persist()
    }

    /// Tira da fila o que a rede ja confirmou ou recusou num bloco, o que esta pendente ha tempo demais e
    /// o que a rede nao conhece depois do prazo de propagacao, com tudo acima (`NonceQueuePruning`, a
    /// mesma regra do Android). Leitura que falha: a entrada fica, a nao ser que esteja velha.
    static func prune(_ session: AppSession, wallet: UUID, chain: Chain, address: String) async {
        let key = key(wallet: wallet, chain: chain, address: address)
        guard chain.family == .evm, let entries = session.metadata.pendingEVM?[key], !entries.isEmpty,
              let engine = SendEngines.engine(for: chain) else { return }
        let result = await NonceQueuePruning.pruned(
            entries.map {
                NonceQueuePruning.Entry(nonce: $0.nonce, hash: $0.hash, sentAt: $0.sentAt, privateRoute: $0.privateRoute == true,
                                        wasSeen: $0.everSeen == true || $0.seen == true, heldAt: $0.heldAt, releasedAt: $0.releasedAt)
            },
            settled: { entry in
                if case .pending = await engine.status(entry.hash, chain: chain) { return false }
                return true
            },
            known: { await engine.sighting($0.hash, chain: chain, from: address, nonce: $0.nonce) })
        // So muda o que foi conferido aqui, pelo hash e pela hora do envio: um envio anotado durante as
        // leituras fica, e um "Enviar de novo" dos mesmos bytes tambem (antes a poda o apagava pelo hash).
        // Travado no meio, nada e gravado; a proxima poda refaz (caca de bugs de 25/10/2026).
        let checked = Set(entries.map { "\($0.hash)|\($0.sentAt.timeIntervalSince1970)" })
        let agoraDaPoda = Date()
        guard session.phase == .unlocked, var current = session.metadata.pendingEVM?[key] else { return }
        let before = current
        current.removeAll { result.gone.contains($0.hash) && checked.contains("\($0.hash)|\($0.sentAt.timeIntervalSince1970)") }
        for index in current.indices where checked.contains("\(current[index].hash)|\(current[index].sentAt.timeIntervalSince1970)") {
            // A vista de antes desta versao (so `seen`) tambem fica marcada, antes de `seen` mudar (setima passada).
            let vista = result.seen.contains(current[index].hash)
            if vista || current[index].seen == true { current[index].everSeen = true }
            current[index].seen = vista
            if result.held.contains(current[index].hash) {
                current[index].heldAt = agoraDaPoda
                current[index].releasedAt = nil
            }
            if result.released.contains(current[index].hash) { current[index].releasedAt = agoraDaPoda }
        }
        guard current != before else { return }
        session.metadata.pendingEVM?[key] = current.isEmpty ? nil : current
        try? session.persist()
    }

    /// Uma transacao deste aparelho nesta conta que a rede ainda nao viu (ler depois de `prune`): a proxima
    /// nao monta, de nenhum ativo, em vez de pular o nonce dela ou reusar o de uma transacao viva. Vale para a
    /// rota privada ate ela sair num bloco (quarta passada da auditoria de 03/11/2026).
    static func unseen(_ session: AppSession, wallet: UUID, chain: Chain, address: String) -> Bool {
        guard chain.family == .evm else { return false }
        return session.metadata.pendingEVM?[key(wallet: wallet, chain: chain, address: address)]?.contains { $0.seen != true } == true
    }

    /// O motivo para a tela quando a conta nao pode montar outra transacao agora, ou nil.
    /// `usesNonce`: o plano tem transacao na cadeia. O que so assina (cancelar fora da cadeia, a ordem da CoW sem
    /// autorizacao) nao usa nonce e nao espera a transacao nao vista (quinta passada de 03/11/2026).
    static func blockedReason(_ session: AppSession, wallet: UUID, chain: Chain, address: String, asset: Asset?, usesNonce: Bool = true) -> String? {
        if usesNonce, unseen(session, wallet: wallet, chain: chain, address: address) {
            return String(localized: "Uma transação anterior desta conta ainda não apareceu na rede, e a próxima não pode passar na frente dela. Tente de novo quando ela aparecer ou confirmar. Se ela tiver sido descartada, o app libera em até 30 minutos, ou em até 3 horas se a rede já tinha visto a transação. Se uma transação anterior a ela seguir esperando na rede, só libera quando essa confirmar.")
        }
        if let asset, sellsInFlight(session, wallet: wallet, chain: chain, address: address, asset: asset.id) {
            return String(localized: "Uma transação anterior com \(asset.symbol) ainda não confirmou na rede. Tente de novo quando ela confirmar. Se ela tiver sido descartada, o app libera em até 30 minutos, ou em até 3 horas se a rede já tinha visto a transação. Se ela seguir esperando na rede, só libera quando ela confirmar.")
        }
        return nil
    }

    /// Uma transacao deste aparelho que tira `asset` desta conta ainda nao confirmou (ler depois de
    /// `prune`). O saldo e a autorizacao que o plano le ainda contam o que ela vai tirar: a nova do mesmo
    /// ativo reverteria na rede, cobrando a taxa (auditoria de 03/11/2026). Na moeda da rede, qualquer
    /// uma conta: toda transacao paga o gas nela (terceira passada de 03/11/2026).
    static func sellsInFlight(_ session: AppSession, wallet: UUID, chain: Chain, address: String, asset: String) -> Bool {
        guard chain.family == .evm, let entries = session.metadata.pendingEVM?[key(wallet: wallet, chain: chain, address: address)] else { return false }
        return asset == Asset.native(chain).id ? !entries.isEmpty : entries.contains { $0.sells == asset }
    }

    static func clear(_ session: AppSession, wallet: UUID, chain: Chain, address: String) {
        session.metadata.pendingEVM?[key(wallet: wallet, chain: chain, address: address)] = nil
        try? session.persist()
    }
}
