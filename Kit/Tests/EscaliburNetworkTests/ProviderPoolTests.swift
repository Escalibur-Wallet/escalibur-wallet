import Foundation
import Testing
@testable import EscaliburNetwork

@Suite("Pool de provedores: consenso")
struct ProviderPoolTests {
    static func providers(_ names: [String]) -> [ProviderPool.Provider] {
        names.map { ProviderPool.Provider(name: $0, baseURL: URL(string: "https://\($0).example")!) }
    }

    @Test("Um provedor so nunca e consenso")
    func single() async {
        let pool = ProviderPool(Self.providers(["a"]))
        await #expect(throws: ConsensusFailure.self) { try await pool.agreeing { _ in 7 } }
    }

    @Test("Dois que concordam; divergencia chama o terceiro")
    func agreement() async throws {
        let pool = ProviderPool(Self.providers(["a", "b", "c"]))
        #expect(try await pool.agreeing { _ in 7 } == 7)
        let answers = ["a": 1, "b": 2, "c": 2]
        #expect(try await pool.agreeing { answers[$0.name] ?? 0 } == 2)
        let split = ["a": 1, "b": 2, "c": 3]
        await #expect(throws: ConsensusFailure.self) { try await pool.agreeing { split[$0.name] ?? 0 } }
    }

    @Test("Com os outros no banco, o consenso ainda pergunta a eles")
    func benched() async throws {
        let pool = ProviderPool(Self.providers(["a", "b"]))
        let b = Self.providers(["b"])[0]
        for _ in 0..<3 { await pool.reportFailure(b) }
        #expect(await pool.available().map(\.name) == ["a"])
        #expect(try await pool.agreeing { _ in 42 } == 42)
        struct Down: Error {}
        await #expect(throws: ConsensusFailure.self) {
            try await pool.agreeing { provider -> Int in
                if provider.name == "b" { throw Down() }
                return 42
            }
        }
    }
}

/// O banco pelo motivo da recusa (contingencia de Litecoin e Dogecoin, 04/10/2026).
@Suite("Banco pelo motivo")
struct ProviderPoolReasonTests {
    @Test("429 tira por 5 min, 430 e 403 por 15, timeout por 2; outro erro segue a regra das tres")
    func benchByReason() async {
        let names = ["a", "b", "c", "d", "e"]
        let providers = names.map { ProviderPool.Provider(name: $0, baseURL: URL(string: "https://\($0).test")!) }
        let pool = ProviderPool(providers)
        let now = Date(timeIntervalSince1970: 1_000_000)
        await pool.reportFailure(providers[0], error: HTTPClient.Failure.status(429), now: now)
        await pool.reportFailure(providers[1], error: HTTPClient.Failure.status(430), now: now)
        await pool.reportFailure(providers[2], error: HTTPClient.Failure.timeout, now: now)
        await pool.reportFailure(providers[3], error: HTTPClient.Failure.status(403), now: now)
        await pool.reportFailure(providers[4], error: HTTPClient.Failure.status(500), now: now)
        #expect(await pool.benched(providers[0]) == now.addingTimeInterval(300))
        #expect(await pool.benched(providers[1]) == now.addingTimeInterval(900))
        #expect(await pool.benched(providers[2]) == now.addingTimeInterval(120))
        #expect(await pool.benched(providers[3]) == now.addingTimeInterval(900))
        #expect(await pool.benched(providers[4]) == nil)
        #expect(await pool.available(now: now.addingTimeInterval(1)).map(\.name) == ["e"])
        #expect(await pool.available(now: now.addingTimeInterval(301)).map(\.name) == ["a", "c", "e"])
        // Uma recusa curta nao encurta um banco mais longo ja marcado.
        await pool.reportFailure(providers[1], error: HTTPClient.Failure.status(429), now: now)
        #expect(await pool.benched(providers[1]) == now.addingTimeInterval(900))
    }

    static func owned(_ pairs: [(String, String)]) -> [ProviderPool.Provider] {
        pairs.map { ProviderPool.Provider(name: $0.0, baseURL: URL(string: "https://\($0.0).example")!, operatorName: $0.1) }
    }

    @Test("Donos diferentes na frente: os dois primeiros de um consenso sao de duas empresas")
    func spreadsOperators() async {
        let pool = ProviderPool(Self.owned([("cluster", "xrpl"), ("s2", "ripple"), ("s1", "ripple"), ("outro", "outro")]))
        #expect(await pool.available().map(\.name) == ["cluster", "s2", "outro", "s1"])
        // Com o primeiro no banco, os dois da Ripple nao ficam juntos na frente.
        for _ in 0..<3 { await pool.reportFailure(pool.providers[0]) }
        #expect(await pool.available().map(\.name) == ["s2", "outro", "s1"])
    }

    @Test("Dois enderecos do mesmo dono nao fazem consenso")
    func sameOperatorIsOneAnswer() async throws {
        let pool = ProviderPool(Self.owned([("s2", "ripple"), ("s1", "ripple"), ("cluster", "xrpl")]))
        let answers = ["s2": 7, "s1": 7, "cluster": 8]
        await #expect(throws: ConsensusFailure.self) { try await pool.agreeing { answers[$0.name] ?? 0 } }
        let honest = ["s2": 7, "s1": 7, "cluster": 7]
        #expect(try await pool.agreeing { honest[$0.name] ?? 0 } == 7)
        let alone = ProviderPool(Self.owned([("s2", "ripple"), ("s1", "ripple")]))
        await #expect(throws: ConsensusFailure.self) { try await alone.agreeing { _ in 7 } }
    }

    @Test("Quorum: a concordancia de um dono so nao vale, nem como duas respostas")
    func quorumNeedsTwoOperators() async throws {
        let providers = Self.owned([("s2", "ripple"), ("s1", "ripple")])
        let pool = ProviderPool(providers)
        await #expect(throws: ReaderError.self) {
            _ = try await Quorum.agree(providers, pool: pool, field: "x") { _ in 5 }
        }
        await #expect(throws: ReaderError.self) {
            _ = try await Quorum.collect(providers, pool: pool, count: 2) { _ in 5 }
        }
        let mixed = Self.owned([("s2", "ripple"), ("s1", "ripple"), ("cluster", "xrpl")])
        let both = try await Quorum.collect(mixed, pool: ProviderPool(mixed), count: 2) { _ in 5 }
        #expect(Set(both.map(\.provider.operatorName)) == ["ripple", "xrpl"])
    }
}
