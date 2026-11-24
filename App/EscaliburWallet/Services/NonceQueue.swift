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
    /// o que a rede nao conhece depois do prazo de propagacao, com tudo acima, salvo a de nonce ja minerado, que sai
    /// sozinha (`NonceQueuePruning`, a
    /// mesma regra do Android). Leitura que falha: a entrada fica, a nao ser que esteja velha.
    static func prune(_ session: AppSession, wallet: UUID, chain: Chain, address: String) async {
        let key = key(wallet: wallet, chain: chain, address: address)
        guard chain.family == .evm, let entries = session.metadata.pendingEVM?[key], !entries.isEmpty,
              let engine = SendEngines.engine(for: chain) else { return }
        // Uma leitura por poda: o que esta abaixo do nonce minerado sai sem depender do recibo antigo (bug de 14/11/2026).
        let mined = await engine.minedNonce(chain: chain, from: address)
        let result = await NonceQueuePruning.pruned(
            entries.map {
                NonceQueuePruning.Entry(nonce: $0.nonce, hash: $0.hash, sentAt: $0.sentAt, privateRoute: $0.privateRoute == true,
                                        wasSeen: $0.everSeen == true || $0.seen == true, heldAt: $0.heldAt, releasedAt: $0.releasedAt)
            },
            minedNonce: mined,
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
}

/// Os envios fora da EVM transmitidos sem resposta certa da rede (`UnsureSend`; a regra, no Kit, e a mesma do Android,
/// onde isto e o `EnviosSemResposta`). Gravado antes de os bytes sairem, tirado quando a transmissao responde. Enquanto
/// fica: a Atividade mostra a linha em "Pendentes" e, ate a rede conhecer a transacao, a conta nao monta outro envio nesta
/// rede. Antes, travar, fechar a tela do envio sem resposta ou o sistema matar o app apagava o unico rastro, e o dono
/// podia pagar duas vezes (pentest de 17/11/2026).
@MainActor
enum UnsureSendLedger {
    /// A nota da linha na Atividade.
    static var note: String { String(localized: "Sem resposta da rede") }

    /// Grava o registro antes de os bytes sairem. false: nao gravou (o app travou no meio, a gravacao falhou, a carteira
    /// saiu) e nao ha um registro deste mesmo envio de antes; quem chama nao transmite.
    static func record(_ session: AppSession, _ send: UnsureSend) -> Bool {
        let before = session.metadata.unsureSends
        // Transmitir de novo os mesmos bytes: o registro de antes segue valendo se o novo nao gravar.
        let already = before?.contains { $0.wallet == send.wallet && $0.chainID == send.chainID && $0.hash == send.hash } == true
        // A carteira removida no meio nao volta a ter rastro.
        guard session.phase == .unlocked, session.metadata.wallets.contains(where: { $0.id == send.wallet }) else { return already }
        session.metadata.unsureSends = UnsureSends.recording(send, in: before ?? [])
        do {
            try session.persist()
        } catch {
            session.metadata.unsureSends = before
            return already
        }
        ActivityFeed.shared.syncUnsure(session, wallet: send.wallet)
        return true
    }

    /// A transmissao respondeu, ou a rede confirmou com a tela aberta: o registro sai. Travado no meio, fica para o destravar.
    static func remove(_ session: AppSession, hash: String, wallet: UUID, chainID: String) {
        session.whenUnlocked { session in
            guard let list = session.metadata.unsureSends else { return }
            let left = UnsureSends.removing(hash: hash, wallet: wallet, chainID: chainID, from: list)
            guard left.count != list.count else { return }
            session.metadata.unsureSends = left.isEmpty ? nil : left
            try? session.persist()
            ActivityFeed.shared.syncUnsure(session, wallet: wallet)
        }
    }

    /// As linhas de "Pendentes" da carteira, para a Atividade.
    static func entries(_ session: AppSession, wallet: UUID) -> [ActivityEntry] {
        (session.metadata.unsureSends ?? []).filter { $0.wallet == wallet && UnsureSends.shown($0) }.map { $0.entry(unanswered: note) }
    }

    /// O motivo para a tela quando a conta tem um envio que a rede ainda nao disse se saiu, ou nil (ler depois de `prune`).
    static func blockedReason(_ session: AppSession, wallet: UUID, chain: Chain, address: String) -> String? {
        guard !UnsureSends.pending(in: session.metadata.unsureSends ?? [], wallet: wallet, chainID: chain.id, address: address).isEmpty
        else { return nil }
        return String(localized: "Um envio anterior desta conta ficou sem resposta da rede, e ainda não dá para saber se ele saiu. Para você não pagar duas vezes, o próximo envio espera a rede dizer o que houve com ele. Se a rede responder que não conhece esse envio, o app libera 30 minutos depois. Ele aparece em Pendentes, na Atividade.")
    }

    /// Pergunta a rede por cada envio sem resposta da carteira (ou so os de uma conta) e aplica a regra
    /// (`UnsureSends.step`): o confirmado vira envio feito; o que falhou com prova sai; o que a rede conhece deixa de
    /// segurar a conta; o que ela diz nao conhecer sai 30 minutos depois da primeira resposta dessas; sem resposta, nada
    /// muda. Travado no meio, nada e gravado, e a proxima poda refaz.
    static func prune(_ session: AppSession, wallet: UUID, chain: Chain? = nil, address: String? = nil) async {
        let records = (session.metadata.unsureSends ?? []).filter { record in
            record.wallet == wallet && chain.map { $0.id == record.chainID } != false && address.map { $0 == record.address } != false
        }
        var changed = false
        for record in records {
            // Rede que esta versao nao conhece mais, ou sem motor: nao ha a quem perguntar, e so o tempo decide.
            var answer = SendLookup.unknowable
            if let known = Chain.find(record.chainID), let engine = SendEngines.engine(for: known) {
                answer = await engine.lookup(record, chain: known)
            }
            let step = UnsureSends.step(record, lookup: answer)
            if case .keep(let same) = step, same == record { continue }
            // Depois da espera: so o registro conferido aqui, com o app ainda destravado. O confirmado sai sempre; o resto, so
            // se ele segue como foi lido (um "Transmitir de novo" durante a leitura refez a hora, e esse e conferido na proxima poda).
            guard session.phase == .unlocked, var list = session.metadata.unsureSends,
                  let index = list.firstIndex(where: { $0.wallet == record.wallet && $0.chainID == record.chainID && $0.hash == record.hash })
            else { continue }
            switch step {
            case .sent:
                list.remove(at: index)
                // O que o envio feito anota (`SendStages.finish`), uma vez so: junto com a saida do registro.
                if let to = record.recipient {
                    var sentTo = session.metadata.sentTo[record.chainID] ?? []
                    if !sentTo.contains(to) { sentTo.append(to) }
                    session.metadata.sentTo[record.chainID] = sentTo
                }
                session.metadata.settings.completedSends = (session.metadata.settings.completedSends ?? 0) + 1
                // A rede desta carteira le o historico de novo: a linha de verdade entra no lugar da pendente.
                session.metadata.activityFetched?[record.wallet]?[record.chainID] = nil
                ActivityFeed.shared.settleSent(hash: record.hash, wallet: record.wallet, status: .confirmed)
            case .dropped(let reason):
                guard list[index] == record else { continue }
                list.remove(at: index)
                if let reason {
                    ActivityFeed.shared.settleSent(hash: record.hash, wallet: record.wallet, status: .failed(reason))
                } else {
                    ActivityFeed.shared.dropSent(hash: record.hash, wallet: record.wallet)
                }
            case .keep(let updated):
                guard list[index] == record else { continue }
                list[index] = updated
                // A linha que a memoria ainda mostra acompanha o registro; a marca das moedas sai da Atividade, como o envio
                // que a rede nao conhece saia antes.
                if UnsureSends.shown(updated) {
                    ActivityFeed.shared.settleSent(hash: record.hash, wallet: record.wallet, status: updated.entry(unanswered: note).status)
                } else {
                    ActivityFeed.shared.dropSent(hash: record.hash, wallet: record.wallet)
                }
            }
            session.metadata.unsureSends = list.isEmpty ? nil : list
            changed = true
        }
        guard changed else { return }
        try? session.persist()
        ActivityFeed.shared.syncUnsure(session, wallet: wallet)
    }
}
