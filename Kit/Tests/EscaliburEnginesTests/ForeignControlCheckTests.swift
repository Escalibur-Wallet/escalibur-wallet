import EscaliburChains
import EscaliburCore
import Foundation
import Testing
@testable import EscaliburEngines

/// As marcas de outra chave no controle, por rede (auditoria 8, 14/11/2026).
@Suite("Outra chave no controle: as marcas")
struct ForeignControlCheckTests {
    static let delegation = ForeignControl(kind: .delegation, detail: "0x63c0c19a282a1B52b07dD5a65b58948A07DAE32B")
    static let otherKey = ForeignControl(kind: .otherKey)

    @Test("A de fora entra, a limpa sai, a sem resposta fica; a Tron nunca entra nas marcas gerais")
    func apply() {
        let start: [String: ForeignControl] = ["base": Self.delegation, "xrpl": Self.otherKey]
        let verdicts: [String: ForeignControlCheck.Verdict] = [
            "base": .clean, "xrpl": .unknown, "stellar": .foreign(Self.otherKey), "tron": .foreign(Self.otherKey),
        ]
        let marks = ForeignControlCheck.apply(verdicts, to: start, startingFrom: start)
        #expect(marks == ["xrpl": Self.otherKey, "stellar": Self.otherKey])
        // Tudo limpo: nenhuma marca, e o campo some.
        #expect(ForeignControlCheck.apply(["xrpl": .clean], to: ["xrpl": Self.otherKey], startingFrom: ["xrpl": Self.otherKey]) == nil)
        // A delegacao trocada de contrato troca a marca.
        let other = ForeignControl(kind: .delegation, detail: "0x000000009B1D0aF20D8C6d0A44e162d11F9b8f00")
        #expect(ForeignControlCheck.apply(["base": .foreign(other)], to: start, startingFrom: nil)?["base"] == other)
        // Rodada 2: a conferencia que comecou sem a marca (lida com dois) nao apaga a que outra pos no meio.
        #expect(ForeignControlCheck.apply(["base": .clean], to: ["base": Self.delegation], startingFrom: nil) == ["base": Self.delegation])
        // Rodada 3: a que comecou com a marca e terminou por ultimo nao apaga a nova, posta no meio por outra.
        let other2 = ForeignControl(kind: .delegation, detail: "0x000000009B1D0aF20D8C6d0A44e162d11F9b8f00")
        #expect(ForeignControlCheck.apply(["base": .clean], to: ["base": other2], startingFrom: ["base": Self.delegation]) == ["base": other2])
    }

    @Test("A marca da Tron: entra com outra chave, sai limpa, fica sem resposta")
    func tronMark() {
        #expect(ForeignControlCheck.tronMark(["tron": .foreign(Self.otherKey)], previous: nil) == true)
        #expect(ForeignControlCheck.tronMark(["tron": .clean], previous: true) == nil)
        #expect(ForeignControlCheck.tronMark(["tron": .unknown], previous: true) == true)
        #expect(ForeignControlCheck.tronMark([:], previous: nil) == nil)
    }

    @Test("Metadados: a marca le e grava; um tipo de uma versao mais nova le como outra chave")
    func codable() throws {
        let data = try JSONEncoder().encode(["base": Self.delegation])
        #expect(try JSONDecoder().decode([String: ForeignControl].self, from: data) == ["base": Self.delegation])
        let newer = Data(#"{"kind":"somethingNew","detail":"x"}"#.utf8)
        #expect(try JSONDecoder().decode(ForeignControl.self, from: newer) == ForeignControl(kind: .otherKey, detail: "x"))
    }

    @Test("O aviso: o contrato da delegacao encurtado; codigo sem delegacao e outra chave, sem nome de rede")
    func message() {
        #expect(Self.delegation.message.contains("0x63c0…E32B"))
        #expect(ForeignControl(kind: .delegation).message.contains("código de contrato"))
        #expect(Self.otherKey.message.contains("Outra chave ou conta"))
    }

    @Test("A conta so de endereco (observacao) nao e conferida, sem perguntar a rede")
    func accounts() async {
        let watch = DerivedAccount(chainID: Chain.base.id, path: DerivationPath(components: []), address: "0x2652742DE21ED9a6c37e73b0E3a51b239A6D1008",
                                   publicKey: [], accountXPub: nil)
        #expect(await ForeignControlCheck.check(watch) == .unknown)
    }

    @Test("A espera sorteada da conferencia do destravar fica entre 30 s e 5 min")
    func delay() {
        for _ in 0..<200 { #expect((30...300).contains(ForeignControlCheck.checkDelay())) }
    }

    @Test("TON: a conta ja na W5, ou de outra rede, fica como esta, sem perguntar a rede")
    func tonKeep() async throws {
        let key = [UInt8](repeating: 9, count: 32)
        let w5 = try TONWallet(publicKey: key, version: .v5r1).address.friendly(bounceable: false)
        let account = DerivedAccount(chainID: Chain.ton.id, path: DefaultPaths.path(for: .ton), address: w5, publicKey: key, accountXPub: nil)
        #expect(await TONDiscovery.check(account) == .keep)
        let other = DerivedAccount(chainID: Chain.solana.id, path: DefaultPaths.path(for: .solana), address: "x", publicKey: key, accountXPub: nil)
        #expect(await TONDiscovery.check(other) == .keep)
    }
}
