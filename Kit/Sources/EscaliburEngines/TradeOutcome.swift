import EscaliburChains
import EscaliburCore
import Foundation

/// Como a rede respondeu as transacoes de uma troca enviada, todas e nao so a ultima (quarta passada da
/// auditoria de 03/11/2026): na troca dividida em pernas, uma perna do meio que reverte nao podia sumir
/// atras de uma ultima confirmada. A mesma regra no iOS e no Android.
public enum TradeOutcome: Sendable, Equatable {
    case pending
    /// Todas confirmaram; o detalhe e o da ultima.
    case done(detail: String?)
    /// Uma falhou na rede. `partial`: outra que move valor (nao uma autorizacao) confirmou, e parte da troca saiu.
    case failed(reason: String, partial: Bool)

    /// `statuses`: o resultado final de cada transacao que ja tem um (sem entrada, ainda pendente). Uma falha so
    /// vira o resultado quando nenhuma outra esta pendente: a perna paralela ainda pode confirmar, e a tela diria
    /// que nada saiu (quinta passada da auditoria de 03/11/2026).
    public static func of(_ plan: SigningPlan?, ids: [String], statuses: [String: TransferStatus]) -> TradeOutcome {
        guard !ids.isEmpty else { return .pending }
        for id in ids {
            guard let status = statuses[id] else { return .pending }
            if case .pending = status { return .pending }
        }
        for id in ids {
            guard case .failed(let reason)? = statuses[id] else { continue }
            let moved = ids.indices.contains { index in
                guard case .confirmed? = statuses[ids[index]] else { return false }
                return !isApproval(plan, at: index)
            }
            return .failed(reason: reason, partial: moved)
        }
        var detail: String?
        for id in ids {
            guard case .confirmed(let text)? = statuses[id] else { return .pending }
            detail = text
        }
        return .done(detail: detail)
    }

    /// A transacao do plano nesta posicao e uma autorizacao de token (`approve`, sem valor): ela nao move nada.
    static func isApproval(_ plan: SigningPlan?, at index: Int) -> Bool {
        guard let plan, plan.transactions.indices.contains(index), let transaction = plan.transactions[index] as? EVMTransaction else { return false }
        return transaction.value.isZero && Array(transaction.data.prefix(4)) == [0x09, 0x5e, 0xa7, 0xb3]
    }
}
