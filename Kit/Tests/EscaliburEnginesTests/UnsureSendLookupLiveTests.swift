import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation
import Testing
@testable import EscaliburEngines

/// O `lookup` dos envios sem resposta (`UnsureSend`) de cada familia fora da EVM contra a rede real, so com
/// ESCALIBUR_REDE=1. So leitura: nada e assinado nem transmitido. O motor sai de `SendEngines.engine(for:)` a cada
/// pergunta, como no app depois de reabrir: nada acompanhado na memoria.
///
/// Os dois erros que custam caro ao dono:
/// - a transacao que confirmou respondida como `.notFound`: o registro sai, a linha pendente some da Atividade e o dono
///   pode pagar de novo;
/// - a que nunca saiu respondida como vista, ou sem resposta para sempre: a conta fica presa, ou a Atividade mostra uma
///   linha pendente de algo que nunca saiu.
///
/// Dois casos por familia:
/// - `nunca-transmitido`: um id bem formado que a rede nao tem como conhecer (bytes sorteados, na grafia da rede), com
///   uma conta real como remetente. Vale `.notFound` ou `.noAnswer`.
/// - `confirmado`: uma transacao real, ja confirmada, enviada por uma conta real. Achada agora pela Atividade da propria
///   rede, para o teste nao envelhecer; onde a Atividade nao da o id que o `lookup` usa, ou nao trouxe envio confirmado,
///   uma transacao gravada nas respostas. Vale `.confirmed`, `.noAnswer` (provedor fora do ar) ou `.seen` (so um dono,
///   ou so o historico da conta, ainda guarda a transacao: ela deixa de segurar a conta e nunca e dada como nao enviada).
///   Mais velha que `UnsureSends.longestKept`, fica de fora: o registro nunca vive tanto.
/// Na Polkadot o `lookup` prova pelo numero da conta guardado no registro, e os casos sao outros (ver `polkadot`).
///
/// Cada caso imprime uma linha, `LOOKUP <rede> <caso> -> <resposta>`, para ler a rodada sem depurador.
@Suite("Envio sem resposta: lookup ao vivo", .enabled(if: ProcessInfo.processInfo.environment["ESCALIBUR_REDE"] == "1"), .serialized)
struct UnsureSendLookupLiveTests {
    typealias Confirmada = (hash: String, remetente: String, data: Date?)

    @Test("Bitcoin: transacao nunca transmitida e transacao confirmada")
    func bitcoin() async throws {
        // O primeiro endereco da frase "abandon ... about" (TestAccounts): publico e varrido por robos, entao tem envios.
        let conta = TestAccounts.bitcoin.address
        try await Self.nuncaTransmitido(.bitcoin, id: Hex.encode(Self.sorteados(32)), remetente: conta)
        let confirmada = await Self.daAtividade(.bitcoin, conta: Self.soEndereco(.bitcoin, conta))
        try await Self.confirmado(.bitcoin, confirmada)
    }

    /// Os provedores de Litecoin e Dogecoin nao sao todos Esplora: cada API tem o proprio jeito de dizer "nao conheco", e um
    /// "pendente" para o id que nunca existiu marcaria o envio que nunca saiu como visto (rodada 4 da revisao de seguranca).
    @Test("Litecoin e Dogecoin: transacao nunca transmitida")
    func outrasUTXO() async throws {
        for chain in [Chain.litecoin, Chain.dogecoin] {
            try await Self.nuncaTransmitido(chain, id: Hex.encode(Self.sorteados(32)), remetente: "")
        }
    }

    @Test("Stellar: transacao nunca transmitida e transacao confirmada")
    func stellar() async throws {
        try await Self.nuncaTransmitido(.stellar, id: Hex.encode(Self.sorteados(32)), remetente: TestAccounts.stellarAddress)
        // Sem envio confirmado na Atividade de GA5XIGA5...: a transacao gravada em Fixtures/stellar/transaction-sdf.json
        // (26/09/2026), enviada por GAIYWQKT...
        let gravada: Confirmada = (
            hash: "69178363c4d302d79d513e3bf2e9f19d0464b986514b479fb40babf608e29eb3",
            remetente: "GAIYWQKTBIVJW5LWYWTDPWIPKRYVPB76MQIQOKBP2O5ELPJSS2NYJWTA",
            data: nil
        )
        let confirmada = await Self.daAtividade(.stellar, conta: TestAccounts.stellar) ?? gravada
        try await Self.confirmado(.stellar, confirmada)
    }

    @Test("Cardano: transacao nunca transmitida e transacao confirmada")
    func cardano() async throws {
        let conta = CardanoEngineRecorded.owner
        try await Self.nuncaTransmitido(.cardano, id: Hex.encode(Self.sorteados(32)), remetente: conta)
        // Sem envio confirmado na Atividade: uma das transacoes do dono, com a chave dele de testemunha
        // (EscaliburNetworkTests/Fixtures/leitores/cardano/koios-address_txs-dono.json).
        let gravada: Confirmada = (hash: "0dcb37399a16220a9a38e857e0e825a1a48ebaad704ed8486a34ab066eed8a74", remetente: conta, data: nil)
        let confirmada = await Self.daAtividade(.cardano, conta: CardanoEngineRecorded.account()) ?? gravada
        try await Self.confirmado(.cardano, confirmada)
    }

    @Test("TON: mensagem nunca transmitida e mensagem confirmada")
    func ton() async throws {
        let conta = TONRecorded.wallet.address.friendly(bounceable: false)
        try await Self.nuncaTransmitido(.ton, id: Hex.encode(Self.sorteados(32)), remetente: conta)
        // Na TON o id do envio e o hash da mensagem externa, e a Atividade (eventos da tonapi) so traz o da transacao. Vai a
        // mensagem externa conhecida das gravacoes (Fixtures/ton/tonapi-message-transaction.json, a mesma do
        // TONReaderLiveTests.knownMessage). O lookup da TON pergunta so pela mensagem; a conta nao entra na pergunta.
        let gravada: Confirmada = (hash: "732af3f9e362d8b32896464d6589f770a458a52a56eb45454a5f7cff92da407f", remetente: conta, data: nil)
        try await Self.confirmado(.ton, gravada)
    }

    @Test("Sui: transacao nunca transmitida e transacao confirmada")
    func sui() async throws {
        try await Self.nuncaTransmitido(.sui, id: Base58.bitcoin.encode(Self.sorteados(32)), remetente: SuiRecorded.owner)
        let confirmada = await Self.daAtividade(.sui, conta: SuiRecorded.account())
        try await Self.confirmado(.sui, confirmada)
    }

    @Test("Aptos: transacao nunca transmitida e transacao confirmada")
    func aptos() async throws {
        let conta = AptosRecorded.recording.dono
        try await Self.nuncaTransmitido(.aptos, id: Hex.encode(Self.sorteados(32), prefix: true), remetente: conta)
        let confirmada = await Self.aptosDaAtividade()
        try await Self.confirmado(.aptos, confirmada)
    }

    @Test("Tron: transacao nunca transmitida e transacao confirmada")
    func tron() async throws {
        try await Self.nuncaTransmitido(.tron, id: Hex.encode(Self.sorteados(32)), remetente: TronRecorded.owner)
        let confirmada = await Self.daAtividade(.tron, conta: TronRecorded.account())
        try await Self.confirmado(.tron, confirmada)
    }

    @Test("XRP Ledger: transacao nunca transmitida e transacao confirmada")
    func xrpl() async throws {
        let conta = TestAccounts.xrpl.address
        try await Self.nuncaTransmitido(.xrpl, id: Hex.encode(Self.sorteados(32)).uppercased(), remetente: conta)
        // Sem envio confirmado na Atividade de rEb8TK3g...: o pagamento dela gravado em Fixtures/xrpl/tx-validado.json.
        let gravada: Confirmada = (hash: "692B5317FE8FB841C8F3F1EBA99E9F525191055F4F107F01876F8C62ECE83D0E", remetente: conta, data: nil)
        let confirmada = await Self.daAtividade(.xrpl, conta: TestAccounts.xrpl) ?? gravada
        try await Self.confirmado(.xrpl, confirmada)
    }

    @Test("NEAR: transacao nunca transmitida e transacao confirmada")
    func near() async throws {
        // Na NEAR o lookup pergunta com a conta que assinou: o envio da Atividade e assinado pelo dono.
        try await Self.nuncaTransmitido(.near, id: Base58.bitcoin.encode(Self.sorteados(32)), remetente: NEAREngineRecorded.owner)
        let confirmada = await Self.daAtividade(.near, conta: NEAREngineRecorded.account())
        try await Self.confirmado(.near, confirmada)
    }

    @Test("Solana: assinatura nunca transmitida e transacao confirmada")
    func solana() async throws {
        // A carteira quente de exchange dos testes da Solana: envia o tempo todo.
        let conta = "5tzFkiKscXHK5ZXCGbXZxdw7gTjjD1mBwuoFbhUvuAi9"
        try await Self.nuncaTransmitido(.solana, id: Base58.bitcoin.encode(Self.sorteados(64)), remetente: conta)
        // Sem envio confirmado na Atividade: a transferencia de SOL gravada em Fixtures/solana/tx-sol-transfer.json
        // (26/09/2026), assinada pela mesma conta.
        let gravada: Confirmada = (
            hash: "AePrTTwYp8nGRJ2mvAQuozWWG6Y3SJgQBM3w8dL7MCw14cDKSDgwwcu9dVmRAVntnMDxwmSQSRLstBjLxm8Bij5", remetente: conta, data: nil
        )
        let confirmada = await Self.daAtividade(.solana, conta: Self.soEndereco(.solana, conta)) ?? gravada
        try await Self.confirmado(.solana, confirmada)
    }

    /// Na Polkadot o leitor so acha a transacao varrendo os blocos da era, e a varredura vive na memoria: depois de o app
    /// reabrir, o `lookup` decide pelo `context` do registro ("<nonce>|<ultimo bloco da era>") e pelo numero da conta
    /// num bloco final igual em dois provedores. A conta 1626DFYA... ja enviou (numero 485 na gravacao).
    @Test("Polkadot: o registro decidido pelo numero da conta e pela era guardados")
    func polkadot() async throws {
        let conta = PolkadotEngineRecorded.owner
        let id = Hex.encode(Self.sorteados(32), prefix: true)
        let livre: UInt32 = 4_000_000_000
        let longe: UInt64 = 1_000_000_000_000
        let casos: [(caso: String, contexto: String?, aceitas: Set<String>)] = [
            // Registro sem o que o motor precisa: so o tempo decide.
            ("sem-contexto", nil, ["unknowable"]),
            // O numero ainda livre e a era aberta: nada se conclui.
            ("nonce-livre-era-aberta", "\(livre)|\(longe)", ["noAnswer"]),
            // O numero livre e a era acabada: venceu, nada saiu.
            ("nonce-livre-era-vencida", "\(livre)|1", ["failed", "noAnswer"]),
            // O numero ja usado: o envio pode ter saido, mas o numero usado nao prova qual transacao o usou.
            ("nonce-usado-era-aberta", "0|\(longe)", ["seenUnclear", "noAnswer"]),
        ]
        for item in casos {
            try await Self.conferir(.polkadot, item.caso, Self.envio(.polkadot, remetente: conta, hash: id, contexto: item.contexto),
                                    aceitas: item.aceitas)
        }
    }

    /// Na NEAR e na Aptos, fora do que os provedores ainda guardam, decide o numero guardado no registro (`unsureContext`):
    /// o da chave de acesso (NEAR) e o de sequencia da conta (Aptos). Ja usado: pode ter saido, e nunca "nao conhece". Ainda
    /// livre: "nao conhece", porque o proximo envio sai com o mesmo numero. As duas contas gravadas ja enviaram.
    @Test("NEAR e Aptos: o registro decidido pelo numero guardado")
    func numeroGuardado() async throws {
        let near = NEAREngineRecorded.owner
        let chave = Base58.bitcoin.encode(try #require(Hex.decode(near)))
        let idNear = Base58.bitcoin.encode(Self.sorteados(32))
        try await Self.conferir(.near, "nonce-livre", Self.envio(.near, remetente: near, hash: idNear, contexto: "\(UInt64.max / 2)|\(chave)"),
                                aceitas: ["notFound", "noAnswer"])
        try await Self.conferir(.near, "nonce-usado", Self.envio(.near, remetente: near, hash: idNear, contexto: "1|\(chave)"),
                                aceitas: ["seenUnclear", "noAnswer"])
        let aptos = AptosRecorded.recording.dono
        let idAptos = Hex.encode(Self.sorteados(32), prefix: true)
        try await Self.conferir(.aptos, "sequencia-livre", Self.envio(.aptos, remetente: aptos, hash: idAptos, contexto: "\(UInt64.max / 2)"),
                                aceitas: ["notFound", "noAnswer"])
        try await Self.conferir(.aptos, "sequencia-usada", Self.envio(.aptos, remetente: aptos, hash: idAptos, contexto: "0"),
                                aceitas: ["seenUnclear", "noAnswer"])
    }

    /// A escada de idades: transacoes reais e confirmadas, de uma hora a treze dias, achadas por fora num no de arquivo
    /// (um JSON com `rede`, `idade`, `hash` e `remetente`, no caminho de ESCALIBUR_LOOKUP_CASOS). Os nos publicos esquecem
    /// transacoes antigas, cada um no seu prazo, e o registro de um envio sem resposta vive ate 14 dias: aqui se ve o que
    /// o motor responde em cada idade. So imprime; reprova apenas `.notFound` e `.failed`, que fariam o dono pagar de novo.
    @Test("Transacoes confirmadas de varias idades: nenhuma e respondida como desconhecida ou como falha",
          .enabled(if: ProcessInfo.processInfo.environment["ESCALIBUR_LOOKUP_CASOS"] != nil))
    func escadaDeIdades() async throws {
        struct Caso: Decodable { let rede: String; let idade: String; let hash: String; let remetente: String }
        let caminho = try #require(ProcessInfo.processInfo.environment["ESCALIBUR_LOOKUP_CASOS"])
        let casos = try JSONDecoder().decode([Caso].self, from: Data(contentsOf: URL(fileURLWithPath: caminho)))
        for caso in casos {
            let chain = try #require(Chain.find(caso.rede))
            try await Self.conferir(chain, "idade-\(caso.idade)", Self.envio(chain, remetente: caso.remetente, hash: caso.hash),
                                    aceitas: ["confirmed", "noAnswer", "seen", "seenUnclear", "unknowable"])
        }
    }

    // MARK: Apoio

    /// O registro como o app grava antes de os bytes sairem, com a hora de agora.
    static func envio(_ chain: Chain, remetente: String, hash: String, contexto: String? = nil) -> UnsureSend {
        UnsureSend(wallet: UUID(), chainID: chain.id, address: remetente, hash: hash, sentAt: Date(), asset: .native(chain),
                   amount: BigUInt(1_000), recipient: nil, context: contexto)
    }

    /// Pergunta a um motor recem-criado, imprime a linha do caso e confere a resposta.
    static func conferir(_ chain: Chain, _ caso: String, _ envio: UnsureSend, aceitas: Set<String>) async throws {
        guard let motor = SendEngines.engine(for: chain) else { throw EngineFixture.Missing(name: "motor de envio \(chain.id)") }
        let resposta = await motor.lookup(envio, chain: chain)
        print("LOOKUP \(chain.id) \(caso) -> \(resposta)")
        #expect(aceitas.contains(tipo(resposta)), "\(chain.id) \(caso): respondeu \(resposta), so vale \(aceitas.sorted())")
    }

    static func nuncaTransmitido(_ chain: Chain, id: String, remetente: String) async throws {
        try await conferir(chain, "nunca-transmitido", envio(chain, remetente: remetente, hash: id), aceitas: ["notFound", "noAnswer"])
    }

    static func confirmado(_ chain: Chain, _ transacao: Confirmada?) async throws {
        guard let transacao else {
            print("LOOKUP \(chain.id) confirmado -> sem-transacao")
            Issue.record("\(chain.id): nenhuma transacao confirmada para perguntar (a Atividade falhou ou nao trouxe envio confirmado)")
            return
        }
        if let data = transacao.data, Date().timeIntervalSince(data) > UnsureSends.longestKept {
            print("LOOKUP \(chain.id) confirmado -> fora-do-prazo (\(data))")
            return
        }
        try await conferir(chain, "confirmado", envio(chain, remetente: transacao.remetente, hash: transacao.hash),
                           aceitas: ["confirmed", "noAnswer", "seen"])
    }

    /// O nome do caso da resposta, sem o texto que vem junto.
    static func tipo(_ resposta: SendLookup) -> String {
        switch resposta {
        case .noAnswer: return "noAnswer"
        case .notFound: return "notFound"
        case .seen: return "seen"
        case .confirmed: return "confirmed"
        case .failed: return "failed"
        case .seenUnclear: return "seenUnclear"
        case .unknowable: return "unknowable"
        }
    }

    static func sorteados(_ count: Int) -> [UInt8] { (0..<count).map { _ in UInt8.random(in: .min ... .max) } }

    /// A conta so com o endereco, como a da carteira de observacao: basta para ler a Atividade.
    static func soEndereco(_ chain: Chain, _ address: String) -> DerivedAccount {
        DerivedAccount(chainID: chain.id, path: DerivationPath(components: []), address: address, publicKey: [], accountXPub: nil)
    }

    /// A mais nova com mais de dez minutos, para os provedores ja terem o bloco; sem nenhuma assim, a mais velha da pagina.
    static func maisNovaComFolga(_ entradas: [ActivityEntry]) -> ActivityEntry? {
        let ordenadas = entradas.sorted { $0.date > $1.date }
        let limite = Date().addingTimeInterval(-600)
        return ordenadas.first { $0.date < limite } ?? ordenadas.last
    }

    /// O envio confirmado da conta, pela fonte de Atividade que o app usa nesta rede. nil quando a leitura falha ou a pagina
    /// nao tem envio confirmado.
    static func daAtividade(_ chain: Chain, conta: DerivedAccount) async -> Confirmada? {
        guard let fonte = ActivitySources.source(for: chain),
              let entradas = try? await fonte.history(chain: chain, account: conta, usage: nil),
              let escolhida = maisNovaComFolga(entradas.filter { $0.direction == .sent && $0.status == .confirmed })
        else { return nil }
        print("LOOKUP \(chain.id) escolhida \(escolhida.hash) de \(escolhida.date) remetente \(conta.address)")
        return (hash: escolhida.hash, remetente: conta.address, data: escolhida.date)
    }

    /// Na Aptos a Atividade da a versao da transacao, nao o hash que o `lookup` usa. O hash e quem assinou saem da propria
    /// transacao, lida pela versao na API REST da Aptos Labs (um provedor so: aqui so serve para achar o que perguntar).
    static func aptosDaAtividade() async -> Confirmada? {
        guard let entradas = try? await AptosActivitySource().history(chain: .aptos, account: AptosRecorded.account(), usage: nil)
        else { return nil }
        // Saida de APT (`.sent`) ou outra transacao assinada pelo dono (`.other`): o remetente vem da transacao lida.
        let assinadas = entradas.filter { ($0.direction == .sent || $0.direction == .other) && $0.status == .confirmed }
        guard let escolhida = maisNovaComFolga(assinadas),
              let versao = UInt64(escolhida.hash),
              let url = URL(string: "https://api.mainnet.aptoslabs.com/v1/transactions/by_version/\(versao)"),
              let data = try? await HTTPClient.shared.get(url, timeout: 30),
              let transacao = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (transacao["success"] as? Bool) == true,
              let hash = transacao["hash"] as? String,
              let remetente = transacao["sender"] as? String
        else { return nil }
        return (hash: hash, remetente: remetente, data: escolhida.date)
    }
}
