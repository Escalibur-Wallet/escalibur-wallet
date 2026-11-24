import Foundation
import Testing
@testable import EscaliburEngines
import EscaliburChains
import EscaliburCore
import EscaliburNetwork

/// O envio transmitido sem resposta certa da rede, fora da EVM (pentest de 17/11/2026): o registro fica ate a rede
/// dizer se saiu, e a conta nao monta outro envio por cima dele.
@Suite("Envios sem resposta")
struct UnsureSendsTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let wallet = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let other = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    static func send(_ hash: String, wallet: UUID = wallet, chain: Chain = .solana, address: String = "conta1", ago: TimeInterval = 0) -> UnsureSend {
        UnsureSend(wallet: wallet, chainID: chain.id, address: address, hash: hash, sentAt: now.addingTimeInterval(-ago),
                   asset: .native(chain), amount: BigUInt(1_000), recipient: "destino1")
    }

    static func kept(_ step: UnsureSends.Step) -> UnsureSend? {
        if case .keep(let record) = step { return record }
        return nil
    }

    static let coinA = String(repeating: "a", count: 64) + ":0"
    static let coinB = String(repeating: "b", count: 64) + ":1"
    static let coinC = String(repeating: "c", count: 64) + ":2"

    static func utxo(_ hash: String, coins: [String], address: String = "conta1", ago: TimeInterval = 0) -> UnsureSend {
        UnsureSend(wallet: wallet, chainID: Chain.bitcoin.id, address: address, hash: hash, sentAt: now.addingTimeInterval(-ago),
                   asset: .native(.bitcoin), amount: BigUInt(1_000), recipient: "destino1",
                   context: UnsureSends.coinsPrefix + coins.joined(separator: ","))
    }

    @Test("Bitcoin: o que sairia sem prova vira a marca das moedas, que nao segura a conta nem aparece, e obriga o proximo envio")
    func utxoDropBecomesMark() throws {
        let record = Self.utxo("a", coins: [Self.coinA, Self.coinB], ago: 600)
        // Duas respostas "nao conhece" com mais de 30 minutos entre elas.
        let first = try #require(Self.kept(UnsureSends.step(record, lookup: .notFound, now: Self.now)))
        let mark = try #require(Self.kept(UnsureSends.step(first, lookup: .notFound, now: Self.now.addingTimeInterval(1_801))))
        #expect(mark.coinsHeld == true)
        #expect(!UnsureSends.blocks(mark))
        #expect(!UnsureSends.shown(mark))
        #expect(UnsureSends.pending(in: [mark], wallet: Self.wallet, chainID: Chain.bitcoin.id, address: "conta1").isEmpty)
        #expect(UnsureSends.coinsToSpend(in: [mark], wallet: Self.wallet, chainID: Chain.bitcoin.id, address: "conta1") == [[Self.coinA, Self.coinB]])
        // So da mesma conta, carteira e rede.
        #expect(UnsureSends.coinsToSpend(in: [mark], wallet: Self.wallet, chainID: Chain.bitcoin.id, address: "conta2").isEmpty)
        #expect(UnsureSends.coinsToSpend(in: [mark], wallet: Self.other, chainID: Chain.bitcoin.id, address: "conta1").isEmpty)
        // O registro que ainda segura a conta nao obriga moeda: ele mesmo segura.
        #expect(UnsureSends.coinsToSpend(in: [record], wallet: Self.wallet, chainID: Chain.bitcoin.id, address: "conta1").isEmpty)
        // O teto de 14 dias, para o Bitcoin, tambem vira marca.
        let stuck = try #require(Self.kept(UnsureSends.step(Self.utxo("b", coins: [Self.coinC], ago: UnsureSends.longestKept + 60),
                                                            lookup: .seen, now: Self.now)))
        #expect(stuck.coinsHeld == true)
        // Fora do UTXO, segue saindo como antes.
        let other = Self.send("c", ago: UnsureSends.longestKept + 60)
        #expect(UnsureSends.step(other, lookup: .noAnswer, now: Self.now) == .dropped(reason: nil))
    }

    @Test("A marca fica sem perguntar nada, sai no teto dela, e sai quando um envio que gasta uma das moedas sai")
    func markLifetime() throws {
        var mark = Self.utxo("a", coins: [Self.coinA, Self.coinB], ago: 3_600)
        mark.coinsHeld = true
        #expect(UnsureSends.step(mark, lookup: .noAnswer, now: Self.now) == .keep(mark))
        #expect(UnsureSends.step(mark, lookup: .notFound, now: Self.now) == .keep(mark))
        var old = mark
        old.sentAt = Self.now.addingTimeInterval(-UnsureSends.coinsKept - 60)
        #expect(UnsureSends.step(old, lookup: .noAnswer, now: Self.now) == .dropped(reason: nil))
        // O envio novo gasta a moeda B e a transmissao responde: a marca sai junto com o registro dele.
        let next = Self.utxo("d", coins: [Self.coinB.uppercased(), Self.coinC])
        let unrelated = Self.utxo("e", coins: [Self.coinC])
        var otherMark = Self.utxo("f", coins: [String(repeating: "9", count: 64) + ":0"])
        otherMark.coinsHeld = true
        let left = UnsureSends.removing(hash: "d", wallet: Self.wallet, chainID: Chain.bitcoin.id, from: [mark, next, unrelated, otherMark])
        #expect(left.map(\.hash) == ["e", "f"])
        // Um envio que nao respondeu (o registro fica) nao solta a marca.
        #expect(UnsureSends.removing(hash: "zz", wallet: Self.wallet, chainID: Chain.bitcoin.id, from: [mark, next]).count == 2)
    }

    @Test("As moedas do registro: o que o motor UTXO grava e le de volta; texto estranho nao obriga nada")
    func coinsRoundTrip() {
        let record = Self.utxo("a", coins: [Self.coinA, Self.coinB])
        #expect(UnsureSends.coins(of: record) == [Self.coinA, Self.coinB])
        #expect(UnsureSends.coins(of: Self.send("b")).isEmpty)
        let groups = UTXOSendEngine.outpoints([[Self.coinA, "lixo", "zz:1"], ["nada"]])
        #expect(groups.count == 1)
        #expect(groups[0].map(\.description) == [Self.coinA])
    }

    @Test("Confirmado: saiu. Falhou com prova: descartado com o motivo. Nos dois, na hora e em qualquer idade")
    func settledLeaves() {
        for ago in [0, 600, 86_400, 2_592_000] as [TimeInterval] {
            let record = Self.send("a", ago: ago)
            #expect(UnsureSends.step(record, lookup: .confirmed, now: Self.now) == .sent)
            #expect(UnsureSends.step(record, lookup: .failed(reason: "venceu"), now: Self.now) == .dropped(reason: "venceu"))
        }
    }

    @Test("Sem resposta da rede: o registro nunca sai sozinho, nem horas depois do envio (o aparelho sem conexao)")
    func noAnswerNeverReleases() {
        for ago in [0, 1_860, 18_000, 259_200] as [TimeInterval] {
            let record = Self.send("a", ago: ago)
            #expect(UnsureSends.step(record, lookup: .noAnswer, now: Self.now) == .keep(record))
            #expect(UnsureSends.blocks(record))
        }
        // Mesmo com o prazo do "nao conhece" ja contado e vencido: sem resposta agora, nada sai.
        var marked = Self.send("a", ago: 5 * 3600)
        marked.unseenSince = Self.now.addingTimeInterval(-4 * 3600)
        #expect(UnsureSends.step(marked, lookup: .noAnswer, now: Self.now) == .keep(marked))
    }

    @Test("A rede nao conhece: o prazo conta da primeira resposta dessas, e nao da hora do envio")
    func notFoundStartsTheClock() {
        // Cinco horas depois do envio, a primeira resposta: so marca a hora.
        let old = Self.send("a", ago: 5 * 3600)
        let first = Self.kept(UnsureSends.step(old, lookup: .notFound, now: Self.now))
        #expect(first?.unseenSince == Self.now && first?.sentAt == old.sentAt)
        #expect(first.map(UnsureSends.blocks) == true)
        // Dentro dos 30 minutos dali, fica como esta.
        let soon = Self.now.addingTimeInterval(29 * 60)
        #expect(UnsureSends.step(first!, lookup: .notFound, now: soon) == .keep(first!))
        #expect(UnsureSends.step(first!, lookup: .notFound, now: Self.now.addingTimeInterval(30 * 60)) == .keep(first!))
        // Passou: sai, sem motivo (ninguem provou nada).
        #expect(UnsureSends.step(first!, lookup: .notFound, now: Self.now.addingTimeInterval(30 * 60 + 1)) == .dropped(reason: nil))
        #expect(UnsureSends.staleAfter == NonceQueuePruning.staleAfter)
    }

    @Test("A rede conhece: o envio saiu. Deixa de segurar a conta e segue em Pendentes, sem a nota e sem prazo de 30 minutos")
    func seenStopsBlocking() {
        var record = Self.send("a", ago: 5 * 3600)
        record.unseenSince = Self.now.addingTimeInterval(-3600)
        record.note = "nota velha"
        let seen = Self.kept(UnsureSends.step(record, lookup: .seen, now: Self.now))
        #expect(seen?.seen == true && seen?.unseenSince == nil && seen?.note == nil)
        #expect(seen.map(UnsureSends.blocks) == false)
        #expect(seen?.entry(unanswered: "Sem resposta da rede").status == .pending(nil))
        // Segue vista: nada a regravar.
        #expect(UnsureSends.step(seen!, lookup: .seen, now: Self.now.addingTimeInterval(3600)) == .keep(seen!))
        // Saiu da fila sem confirmar (trocada ou descartada): o prazo do "nao conhece" comeca, e ela segue sem segurar a conta.
        let gone = Self.kept(UnsureSends.step(seen!, lookup: .notFound, now: Self.now))
        #expect(gone?.seen == true && gone?.unseenSince == Self.now)
        #expect(UnsureSends.step(gone!, lookup: .notFound, now: Self.now.addingTimeInterval(31 * 60)) == .dropped(reason: nil))
        // Confirmou: vira envio feito.
        #expect(UnsureSends.step(seen!, lookup: .confirmed, now: Self.now) == .sent)
    }

    @Test("O teto de 14 dias vale para qualquer registro que nao confirmou nem falhou: provedor com defeito nao prende a conta para sempre")
    func longestKept() {
        let edge = Self.send("a", ago: 14 * 86_400)
        let past = Self.send("a", ago: 14 * 86_400 + 1)
        for lookup in [SendLookup.noAnswer, .notFound, .seen, .unknowable, .seenUnclear(note: "confira")] {
            #expect(UnsureSends.step(past, lookup: lookup, now: Self.now) == .dropped(reason: nil))
        }
        #expect(UnsureSends.step(edge, lookup: .seen, now: Self.now) != .dropped(reason: nil))
        #expect(UnsureSends.step(edge, lookup: .noAnswer, now: Self.now) == .keep(edge))
        #expect(UnsureSends.step(past, lookup: .confirmed, now: Self.now) == .sent)
        #expect(UnsureSends.step(past, lookup: .failed(reason: "venceu"), now: Self.now) == .dropped(reason: "venceu"))
    }

    @Test("Final sem prova (a Polkadot com o numero da conta usado, ou o resultado de uma fonte so): solta a conta, a linha manda conferir, e nunca vira falhou")
    func unclearNeverSaysFailed() {
        let record = Self.send("a", ago: 40 * 60)
        let step = UnsureSends.step(record, lookup: .seenUnclear(note: "pode ter saido, confira"), now: Self.now)
        let kept = Self.kept(step)
        #expect(kept?.seen == true && kept?.note == "pode ter saido, confira" && kept?.unseenSince == nil)
        #expect(kept.map(UnsureSends.blocks) == false)
        #expect(kept?.entry(unanswered: "Sem resposta da rede").status == .pending("pode ter saido, confira"))
        // Igual na conferencia seguinte: nada a regravar. Um dia depois do envio, a linha sai, sem rotulo.
        #expect(UnsureSends.step(kept!, lookup: .seenUnclear(note: "pode ter saido, confira"), now: Self.now) == .keep(kept!))
        let day = Self.send("a", ago: 24 * 3600 + 1)
        #expect(UnsureSends.step(day, lookup: .seenUnclear(note: "x"), now: Self.now) == .dropped(reason: nil))
        // A rede passou a conhece-la de verdade: a nota sai.
        #expect(Self.kept(UnsureSends.step(kept!, lookup: .seen, now: Self.now))?.note == nil)
    }

    @Test("Sem a quem perguntar (rede que a versao nao conhece mais, registro sem o que o motor precisa): so o tempo desde o envio decide")
    func unknowableUsesTheSendTime() {
        let young = Self.send("a", ago: 10 * 60)
        #expect(UnsureSends.step(young, lookup: .unknowable, now: Self.now) == .keep(young))
        #expect(UnsureSends.blocks(young))
        let old = Self.send("a", ago: 30 * 60 + 1)
        #expect(UnsureSends.step(old, lookup: .unknowable, now: Self.now) == .dropped(reason: nil))
    }

    @Test("Relogio do aparelho para tras: o prazo recomeca, e a conta nao fica presa pelo desvio")
    func clockMovedBack() {
        // A hora da primeira resposta ficou uma hora a frente do relogio de agora: recomeca daqui.
        var record = Self.send("a", ago: 600)
        record.unseenSince = Self.now.addingTimeInterval(3600)
        let reset = Self.kept(UnsureSends.step(record, lookup: .notFound, now: Self.now))
        #expect(reset?.unseenSince == Self.now)
        // Um minuto de folga nao recomeca nada.
        record.unseenSince = Self.now.addingTimeInterval(30)
        #expect(UnsureSends.step(record, lookup: .notFound, now: Self.now) == .keep(record))
    }

    @Test("Anotar de novo o mesmo id refaz a hora e as marcas; outro id, outra carteira ou outra rede sao outro registro")
    func recordingIsAnUpsert() {
        var first = Self.send("AbC", ago: 600)
        first.seen = true
        first.unseenSince = Self.now
        var list = UnsureSends.recording(first, in: [])
        list = UnsureSends.recording(Self.send("abc", ago: 0), in: list)
        #expect(list.count == 1 && list[0].sentAt == Self.now && list[0].seen == nil && list[0].unseenSince == nil)
        list = UnsureSends.recording(Self.send("def"), in: list)
        list = UnsureSends.recording(Self.send("abc", wallet: Self.other), in: list)
        list = UnsureSends.recording(Self.send("abc", chain: .tron), in: list)
        #expect(list.count == 4)
    }

    @Test("Tirar um registro nao leva o de outra carteira nem o de outra rede com o mesmo id")
    func removingIsScoped() {
        let list = [Self.send("abc"), Self.send("abc", wallet: Self.other), Self.send("abc", chain: .tron), Self.send("def")]
        let left = UnsureSends.removing(hash: "ABC", wallet: Self.wallet, chainID: Chain.solana.id, from: list)
        #expect(left.count == 3 && !left.contains { $0.wallet == Self.wallet && $0.chainID == Chain.solana.id && $0.hash == "abc" })
        #expect(UnsureSends.removing(hash: "nada", wallet: Self.wallet, chainID: Chain.solana.id, from: list) == list)
    }

    @Test("So os registros desta conta nesta rede seguram o envio seguinte, e so enquanto a rede nao os conhece")
    func pendingIsPerAccount() {
        var known = Self.send("visto")
        known.seen = true
        let list = [Self.send("a"), Self.send("b", address: "conta2"), Self.send("c", chain: .tron), Self.send("d", wallet: Self.other), known]
        #expect(UnsureSends.pending(in: list, wallet: Self.wallet, chainID: Chain.solana.id, address: "conta1").map(\.hash) == ["a"])
        #expect(UnsureSends.pending(in: list, wallet: Self.wallet, chainID: Chain.solana.id, address: "Conta1").isEmpty)
        #expect(UnsureSends.pending(in: [known], wallet: Self.wallet, chainID: Chain.solana.id, address: "conta1").isEmpty)
    }

    @Test("Fora da EVM: la a fila de nonces ja segura a conta")
    func notOnEVM() {
        #expect(!UnsureSends.applies(to: .ethereum))
        #expect(UnsureSends.applies(to: .solana) && UnsureSends.applies(to: .bitcoin) && UnsureSends.applies(to: .tron))
    }

    @Test("O estado dos leitores de duas fontes: nenhum conhece, na fila, final")
    func readerStatesMap() {
        #expect(SendLookup(TransactionStatus.notFound) { $0 } == .notFound)
        #expect(SendLookup(TransactionStatus.pending) { $0 } == .seen)
        #expect(SendLookup(TransactionStatus.confirmed(block: 1, confirmations: nil)) { $0 } == .confirmed)
        #expect(SendLookup(TransactionStatus.failed(reason: "expired")) { "texto de " + $0 } == .failed(reason: "texto de expired"))
        #expect(ChainTransferStatus.lookup(.notFound) == .notFound && ChainTransferStatus.lookup(.pending) == .seen)
        #expect(ChainTransferStatus.lookup(.confirmed(height: 1, confirmations: 2)) == .confirmed)
        if case .failed = ChainTransferStatus.lookup(.failed(height: 1)) {} else { Issue.record("a falha num bloco tem de sair como falha") }
    }

    @Test("O registro vai e volta dos metadados, o antigo abre sem as marcas, e vira a linha pendente com o id de um envio comum")
    func codableAndEntry() throws {
        var send = Self.send("abc", ago: 60)
        #expect(try JSONDecoder().decode(UnsureSend.self, from: JSONEncoder().encode(send)) == send)
        let entry = send.entry(unanswered: "Sem resposta da rede")
        #expect(entry.id == "enviado-\(Chain.solana.id)-abc" && entry.hash == "abc" && entry.direction == .sent)
        #expect(entry.status == .pending("Sem resposta da rede") && entry.amount == BigUInt(1_000) && entry.counterparty == "destino1")
        #expect(entry.asset == Asset.native(.solana) && entry.date == send.sentAt && !entry.suspicious)
        // Gravado sem as marcas (o registro de antes delas): as chaves nem aparecem, e a leitura da nil.
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(send)) as? [String: Any]
        #expect(plain?["seen"] == nil && plain?["unseenSince"] == nil && plain?["note"] == nil)
        send.seen = true
        send.unseenSince = Self.now
        send.note = "nota"
        #expect(try JSONDecoder().decode(UnsureSend.self, from: JSONEncoder().encode(send)) == send)
        // O que o motor guardou vai junto, e transmitir de novo o mantem.
        let withContext = UnsureSend(wallet: Self.wallet, chainID: Chain.polkadot.id, address: "conta1", hash: "0xabc", sentAt: Self.now,
                                     asset: .native(.polkadot), amount: BigUInt(5), recipient: nil, context: "7|1255")
        #expect(try JSONDecoder().decode(UnsureSend.self, from: JSONEncoder().encode(withContext)).context == "7|1255")
        #expect(plain?["context"] == nil)
    }
}
