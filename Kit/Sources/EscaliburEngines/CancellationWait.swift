import EscaliburChains
import Foundation

/// A edicao de uma ordem limite espera o cancelamento da antiga confirmar na rede antes de montar a
/// nova (segunda passada da auditoria de 03/11/2026). Montada logo depois de transmitir, a nova via a
/// antiga ainda aberta: a CoW pedia saldo e autorizacao para as duas, e o XRP Ledger repetia a Sequence
/// da oferta cancelada, e a nova nunca entrava. Igual no iOS e no Android.
public enum CancellationWait {
    public enum Outcome: Sendable, Equatable {
        case confirmed
        case failed(String)
        /// Nao confirmou no prazo: a revisao fica na tela de incerto, com o reenvio dos mesmos bytes.
        case timedOut
    }

    /// Ate 5 minutos, de 3 em 3 segundos, pelo `status` do motor de envio (que confere em dois provedores).
    public static func untilConfirmed(_ id: String, chain: Chain, attempts: Int = 100, interval: Duration = .seconds(3)) async -> Outcome {
        guard let engine = SendEngines.engine(for: chain) else { return .timedOut }
        for attempt in 0..<attempts {
            if attempt > 0 { try? await Task.sleep(for: interval) }
            if Task.isCancelled { return .timedOut }
            switch await engine.status(id, chain: chain) {
            case .confirmed: return .confirmed
            case .failed(let reason): return .failed(reason)
            case .pending: continue
            }
        }
        return .timedOut
    }
}
