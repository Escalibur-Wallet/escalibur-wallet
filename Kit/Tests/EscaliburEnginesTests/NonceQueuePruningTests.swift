import Foundation
import Testing
@testable import EscaliburEngines
import EscaliburNetwork

/// A poda da fila de nonces (terceira e quarta passadas da auditoria de 03/11/2026): o app nunca pula um
/// nonce nem reusa o de uma transacao viva.
@Suite("Poda da fila de nonces")
struct NonceQueuePruningTests {
    typealias E = NonceQueuePruning.Entry
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func entry(_ nonce: UInt64, ago: TimeInterval, privateRoute: Bool = false) -> E {
        E(nonce: nonce, hash: "0x\(nonce)", sentAt: now.addingTimeInterval(-ago), privateRoute: privateRoute)
    }

    /// true: dois operadores devolvem a transacao; false: dois sem ela; nil: sem resposta.
    static func prune(_ entries: [E], settled: @escaping @Sendable (E) -> Bool = { _ in false },
                      known: @escaping @Sendable (E) -> Bool?) async -> NonceQueuePruning.Result {
        await NonceQueuePruning.pruned(entries, now: now, settled: { settled($0) }, known: { entry in
            known(entry).map { $0 ? EVMReader.Sighting.seen : .unknown }
        })
    }

    @Test("Recusada ou descartada: sai depois do prazo, com tudo acima; abaixo dela fica e conta como vista")
    func lostTakesEverythingAbove() async {
        let result = await Self.prune([Self.entry(5, ago: 120), Self.entry(6, ago: 60), Self.entry(7, ago: 40)]) { $0.nonce != 6 }
        #expect(result.gone == ["0x6", "0x7"] && result.seen == ["0x5"])
    }

    @Test("Dentro do prazo ou sem resposta: fica, e nao conta como vista (o plano seguinte e recusado, nao pula)")
    func unseenStays() async {
        let young = await Self.prune([Self.entry(5, ago: 10)]) { _ in false }
        #expect(young.gone.isEmpty && young.seen.isEmpty)
        let silent = await Self.prune([Self.entry(5, ago: 120)]) { _ in nil }
        #expect(silent.gone.isEmpty && silent.seen.isEmpty)
    }

    @Test("Publica empilhada sobre uma privada ainda nao minerada: nada sai, porque a de cima nem e perguntada")
    func stackedOnPrivateIsNotLost() async {
        let asked = Asked()
        let result = await NonceQueuePruning.pruned([Self.entry(5, ago: 60, privateRoute: true), Self.entry(6, ago: 40)], now: Self.now,
                                                    settled: { _ in false }, known: { entry in await asked.add(entry.nonce); return .unknown })
        #expect(result.gone.isEmpty && result.seen.isEmpty)
        #expect(await asked.nonces == [5])
    }

    @Test("Rota privada: o prazo e de 10 minutos")
    func privateRouteHasLongerGrace() async {
        let fresh = await Self.prune([Self.entry(5, ago: 300, privateRoute: true)]) { _ in false }
        #expect(fresh.gone.isEmpty)
        let old = await Self.prune([Self.entry(5, ago: 700, privateRoute: true)]) { _ in false }
        #expect(old.gone == ["0x5"])
    }

    @Test("Mais de 30 minutos: a conhecida fica ate sair num bloco; a desconhecida sai com tudo acima")
    func staleOnlyWhenUnknown() async {
        let known = await Self.prune([Self.entry(5, ago: 40 * 60), Self.entry(6, ago: 60)]) { _ in true }
        #expect(known.gone.isEmpty && known.seen == ["0x5", "0x6"])
        let silent = await Self.prune([Self.entry(5, ago: 40 * 60), Self.entry(6, ago: 60)]) { _ in nil }
        #expect(silent.gone == ["0x5", "0x6"])
    }

    @Test("So um operador conhece: nao conta como vista (a conta fica travada) e, depois de 30 minutos, sai como a desconhecida (quinta passada de 03/11/2026)")
    func oneOperatorIsNotEnough() async {
        let young = await NonceQueuePruning.pruned([Self.entry(5, ago: 120)], now: Self.now, settled: { _ in false }, known: { _ in .partial })
        #expect(young.gone.isEmpty && young.seen.isEmpty)
        let old = await NonceQueuePruning.pruned([Self.entry(5, ago: 40 * 60), Self.entry(6, ago: 60)], now: Self.now,
                                                 settled: { _ in false }, known: { _ in .partial })
        #expect(old.gone == ["0x5", "0x6"])
    }

    @Test("Ja vista por dois operadores e agora so por um: fica ate 3 horas; dois sem ela a tiram com as de cima (sexta passada de 03/11/2026)")
    func seenBeforeStays() async {
        let seen = E(nonce: 5, hash: "0x5", sentAt: Self.now.addingTimeInterval(-40 * 60), privateRoute: false, wasSeen: true)
        let partial = await NonceQueuePruning.pruned([seen, Self.entry(6, ago: 60)], now: Self.now, settled: { _ in false }, known: { _ in .partial })
        #expect(partial.gone.isEmpty && partial.seen.isEmpty)
        let unknown = await NonceQueuePruning.pruned([seen, Self.entry(6, ago: 60)], now: Self.now, settled: { _ in false }, known: { _ in .unknown })
        #expect(unknown.gone == ["0x5", "0x6"])
        let old = E(nonce: 5, hash: "0x5", sentAt: Self.now.addingTimeInterval(-4 * 60 * 60), privateRoute: false, wasSeen: true)
        let stale = await NonceQueuePruning.pruned([old], now: Self.now, settled: { _ in false }, known: { _ in .partial })
        #expect(stale.gone == ["0x5"])
    }

    @Test("A de cima nao sai por tempo antes da de baixo ja vista, que fica ate 3 horas (oitava passada de 03/11/2026)")
    func upperWaitsForLower() async {
        let lower = E(nonce: 5, hash: "0x5", sentAt: Self.now.addingTimeInterval(-50 * 60), privateRoute: false, wasSeen: true)
        let result = await NonceQueuePruning.pruned([lower, Self.entry(6, ago: 40 * 60)], now: Self.now, settled: { _ in false },
                                                    known: { _ in .partial })
        #expect(result.gone.isEmpty && result.seen.isEmpty)
    }

    @Test("A de baixo reenviada depois da de cima: a de cima espera o prazo dela pela hora, e nao pela duracao (nona passada)")
    func upperWaitsForResentLower() async {
        let lower = E(nonce: 5, hash: "0x5", sentAt: Self.now.addingTimeInterval(-160 * 60), privateRoute: false, wasSeen: true)
        let upper = E(nonce: 6, hash: "0x6", sentAt: Self.now.addingTimeInterval(-185 * 60), privateRoute: false)
        let result = await NonceQueuePruning.pruned([lower, upper], now: Self.now, settled: { _ in false }, known: { _ in .partial })
        #expect(result.gone.isEmpty)
    }

    @Test("A de baixo vista agora: a de cima, so de um operador, nao sai por tempo (nona passada)")
    func upperWaitsForSeenLower() async {
        let result = await NonceQueuePruning.pruned([Self.entry(5, ago: 50 * 60), Self.entry(6, ago: 40 * 60)], now: Self.now,
                                                    settled: { _ in false }, known: { $0.nonce == 5 ? .seen : .partial })
        #expect(result.gone.isEmpty && result.seen == ["0x5"])
        let unknown = await NonceQueuePruning.pruned([Self.entry(5, ago: 50 * 60), Self.entry(6, ago: 40 * 60)], now: Self.now,
                                                     settled: { _ in false }, known: { $0.nonce == 5 ? .seen : .unknown })
        #expect(unknown.gone == ["0x6"])
    }

    @Test("Segurada pela de baixo vista: fica marcada, e o prazo conta dali quando a de baixo confirma (decima passada)")
    func heldRestartsTheClock() async {
        let held = await NonceQueuePruning.pruned([Self.entry(5, ago: 50 * 60), Self.entry(6, ago: 40 * 60)], now: Self.now,
                                                  settled: { _ in false }, known: { $0.nonce == 5 ? .seen : .partial })
        #expect(held.held == ["0x6"])
        let upper = E(nonce: 6, hash: "0x6", sentAt: Self.now.addingTimeInterval(-40 * 60), privateRoute: false, heldAt: Self.now.addingTimeInterval(-60))
        let after = await NonceQueuePruning.pruned([Self.entry(5, ago: 50 * 60), upper], now: Self.now,
                                                   settled: { $0.nonce == 5 }, known: { _ in .partial })
        #expect(after.gone == ["0x5"])
    }

    @Test("Solta horas depois, com o app fechado: o prazo recomeca na poda que a solta, e nao da ultima vez segurada")
    func releasedRestartsTheClock() async {
        // Segurada ha 5 horas; a de baixo confirmou enquanto o app estava fechado, e a de cima so um operador conhece.
        let upper = E(nonce: 6, hash: "0x6", sentAt: Self.now.addingTimeInterval(-6 * 60 * 60), privateRoute: false,
                      heldAt: Self.now.addingTimeInterval(-5 * 60 * 60))
        let first = await NonceQueuePruning.pruned([Self.entry(5, ago: 7 * 60 * 60), upper], now: Self.now,
                                                   settled: { $0.nonce == 5 }, known: { _ in .partial })
        #expect(first.gone == ["0x5"] && first.released == ["0x6"])
        // Na proxima poda, o prazo conta da soltura: 20 minutos depois fica, 40 minutos depois sai.
        let released = E(nonce: 6, hash: "0x6", sentAt: upper.sentAt, privateRoute: false, heldAt: upper.heldAt, releasedAt: Self.now)
        let soon = await NonceQueuePruning.pruned([released], now: Self.now.addingTimeInterval(20 * 60),
                                                  settled: { _ in false }, known: { _ in .partial })
        #expect(soon.gone.isEmpty && soon.released.isEmpty)
        let late = await NonceQueuePruning.pruned([released], now: Self.now.addingTimeInterval(40 * 60),
                                                  settled: { _ in false }, known: { _ in .partial })
        #expect(late.gone == ["0x6"])
        // Desconhecida de todos os operadores, sai na hora, solta ou nao.
        let gone = await NonceQueuePruning.pruned([Self.entry(5, ago: 7 * 60 * 60), upper], now: Self.now,
                                                  settled: { $0.nonce == 5 }, known: { _ in .unknown })
        #expect(gone.gone == ["0x5", "0x6"])
    }

    @Test("Nao perguntada por causa de uma de baixo que ficou: fica segurada, e o prazo recomeca quando a de baixo confirma")
    func unaskedUpperIsHeld() async {
        // A de baixo ja foi vista e agora so um operador a conhece; a de cima, publica, esta ha 2h50 sem ser perguntada.
        let lower = E(nonce: 5, hash: "0x5", sentAt: Self.now.addingTimeInterval(-175 * 60), privateRoute: false, wasSeen: true)
        let upper = Self.entry(6, ago: 170 * 60)
        let first = await NonceQueuePruning.pruned([lower, upper], now: Self.now, settled: { _ in false }, known: { _ in .partial })
        #expect(first.gone.isEmpty && first.held == ["0x6"])
        // A de baixo confirma um minuto depois, e a de cima, perguntada pela primeira vez, ainda propaga: fica.
        let held = E(nonce: 6, hash: "0x6", sentAt: upper.sentAt, privateRoute: false, heldAt: Self.now)
        let later = Self.now.addingTimeInterval(60)
        let second = await NonceQueuePruning.pruned([lower, held], now: later, settled: { $0.nonce == 5 }, known: { _ in .partial })
        #expect(second.gone == ["0x5"] && second.released == ["0x6"])
    }

    @Test("Confirmada ou falha num bloco: sai sozinha, sem levar as de cima")
    func settledLeavesAlone() async {
        let result = await Self.prune([Self.entry(5, ago: 60), Self.entry(6, ago: 50)], settled: { $0.nonce == 5 }) { _ in true }
        #expect(result.gone == ["0x5"] && result.seen == ["0x6"])
    }

    actor Asked {
        private(set) var nonces: [UInt64] = []
        func add(_ nonce: UInt64) { nonces.append(nonce) }
    }
}

/// O resultado de uma troca enviada com varias transacoes (quarta passada de 03/11/2026).
@Suite("Resultado da troca enviada")
struct TradeOutcomeTests {
    @Test("Concluida so com todas confirmadas; uma falha aparece mesmo com a ultima confirmada")
    func allTransactionsCount() {
        let ids = ["0xa", "0xb"]
        #expect(TradeOutcome.of(nil, ids: ids, statuses: ["0xa": .pending, "0xb": .confirmed(detail: "ok")]) == .pending)
        #expect(TradeOutcome.of(nil, ids: ids, statuses: ["0xa": .confirmed(detail: nil), "0xb": .confirmed(detail: "ok")]) == .done(detail: "ok"))
        #expect(TradeOutcome.of(nil, ids: ids, statuses: ["0xa": .failed(reason: "r"), "0xb": .confirmed(detail: nil)])
                == .failed(reason: "r", partial: true))
        #expect(TradeOutcome.of(nil, ids: ids, statuses: ["0xa": .failed(reason: "r"), "0xb": .failed(reason: "s")])
                == .failed(reason: "r", partial: false))
        #expect(TradeOutcome.of(nil, ids: [], statuses: [:]) == .pending)
        // Uma perna falhou e a outra ainda nao respondeu: espera, porque ela ainda pode sair.
        #expect(TradeOutcome.of(nil, ids: ids, statuses: ["0xa": .failed(reason: "r")]) == .pending)
    }
}
