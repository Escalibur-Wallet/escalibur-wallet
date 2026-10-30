import Testing
@testable import EscaliburEngines

/// A regra da busca de movimento na EVM (revisao de blockchain de 26/10/2026): "vazia" so com o que
/// foi lido; o indexador que recusa ou a rede sem historico nunca viram "nunca usada".
@Suite("Busca de movimento: a regra da EVM")
struct UsageCheckTests {
    @Test("Movimento no historico ou no rastro da conta decide")
    func movementWins() async {
        #expect(await UsageCheck.combine(history: .used, footprint: .failed, tokens: { .failed }) == .used)
        #expect(await UsageCheck.combine(history: .failed, footprint: .used, tokens: { .failed }) == .used)
        #expect(await UsageCheck.combine(history: .empty, footprint: .used, tokens: { .empty }) == .used)
    }

    @Test("Sem historico, vazio so com o rastro e os tokens lidos e zerados")
    func withoutHistory() async {
        #expect(await UsageCheck.combine(history: .failed, footprint: .empty, tokens: { .empty }) == .empty)
        #expect(await UsageCheck.combine(history: .failed, footprint: .empty, tokens: { .used }) == .used)
        #expect(await UsageCheck.combine(history: .failed, footprint: .empty, tokens: { .failed }) == .failed)
        #expect(await UsageCheck.combine(history: .failed, footprint: .failed, tokens: { .empty }) == .failed)
    }

    @Test("Historico lido e vazio continua vazio com o rastro zerado ou sem responder")
    func emptyHistory() async {
        #expect(await UsageCheck.combine(history: .empty, footprint: .empty, tokens: { .used }) == .empty)
        #expect(await UsageCheck.combine(history: .empty, footprint: .failed, tokens: { .used }) == .empty)
    }
}
