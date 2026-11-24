import EscaliburChains
import EscaliburCore
import Foundation
import Testing
@testable import EscaliburEngines
@testable import EscaliburNetwork

/// As respostas gravadas da Polkadot Asset Hub, as mesmas dos testes do leitor
/// (EscaliburNetworkTests/Fixtures/leitores/polkadot, `gravar.mjs`), lidas do repositorio.
/// O dono e a conta 1626DFYA..., que assina com Ed25519 (a chave publica e a da
/// transferencia real dele no bloco 21.172.670).
enum PolkadotEngineRecorded {
    static let folder = URL(fileURLWithPath: caminhoNoAparelho(#filePath))
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("EscaliburNetworkTests/Fixtures/leitores/polkadot")

    static let owner = "1626DFYAYv5UGwSy6dz3yiGExMxxik68RqQbusnb4MCHEY6e"
    static let ownerKey = [UInt8](hex: "de01f487837eae7557b87b856c1750bc21effbf60042a79cd87cb54b0a11bb3e")!
    /// Conta vazia na rede (o endereco do vetor do wallet-core).
    static let destination = "13nN6BGAoJwd7Nw1XxeBCx5YcBXuYnL94Mh7i3xBprqVSsFk"
    static let free = BigUInt(10_401_141_645)
    static let fee = BigUInt(8_808_355)
    static let signedHex = "45028400de01f487837eae7557b87b856c1750bc21effbf60042a79cd87cb54b0a11bb3e002cd8da9380ba775111b8bc48fa18acb3029954441276e7160708c18e4fd0819d18f900bdfc3857f1a892ea78a8fd33f77ef11f67adf81381b8cd8fa6c667cd0d9b1791070000000a03008b67634b395e5f8220231e7a837020a2fec7b93c580b539d2f8bc07f2e1eba8b36bea35f"
    static let signedID = "0x7b0c234cbbf38694fd430566f28f43f7e73a70188da7d214ac7d454992da3aa8"

    static func data(_ name: String) throws -> Data { try Data(contentsOf: folder.appendingPathComponent(name + ".json")) }

    static func account(address: String = owner, key: [UInt8] = ownerKey) -> DerivedAccount {
        DerivedAccount(chainID: "polkadot", path: DerivationPath("m/44'/354'/0'/0'/0'")!, address: address, publicKey: key, accountXPub: nil)
    }

    static func request(amount: BigUInt = 5_000_000_000, to destination: String = destination, sendAll: Bool = false,
                        asset: Asset = .native(.polkadot), account: DerivedAccount = account(), known: [String] = []) -> SendRequest {
        SendRequest(
            walletID: UUID(), chain: .polkadot, asset: asset, account: account, destination: destination, tag: nil,
            amount: amount, sendAll: sendAll, feeLevel: .normal, utxoUsage: nil, knownAddresses: known
        )
    }

    static var signed: SignedTransaction {
        let raw = [UInt8](hex: signedHex)!
        return SignedTransaction(chainID: "polkadot", raw: raw, encoded: Hex.encode(raw, prefix: true), id: signedID)
    }

    /// JSON-RPC pelo metodo; sidecar e historico pelo host. `runtime` e `feeError` trocam a
    /// versao do runtime e fazem o no recusar a avaliacao da taxa.
    struct Transport: ReaderTransport {
        var runtime: String?
        var feeError = false
        /// O sidecar diz que a transferencia nao saiu (`success: false`), a unica fonte do resultado.
        var sidecarFails = false
        /// Os nos recusam a transmissao com o codigo 1010 e este texto (o `author_submitExtrinsic` do Substrate).
        var submitRejection: String?

        func send(_ request: ReaderRequest) async throws -> Data {
            let body = request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            switch request.url.host ?? "" {
            case "sidecar.test":
                let recorded = try data("sidecar-21172670")
                guard sidecarFails else { return recorded }
                let marker = "\"hash\":\"\(signedID)\",\"success\":"
                return Data(String(decoding: recorded, as: UTF8.self).replacingOccurrences(of: marker + "true", with: marker + "false").utf8)
            case "historico.test":
                return try data((body["query"] as? String ?? "").contains("_metadata") ? "historico-metadados" : "historico-dono")
            default: break
            }
            let params = body["params"] as? [Any] ?? []
            switch body["method"] as? String ?? "" {
            case "chain_getFinalizedHead": return try data("finalizedHead")
            case "chain_getHeader": return try data("header")
            case "chain_getBlockHash":
                switch params.first as? Int {
                case 0: return try data("blockHash-genese")
                case 21_172_670: return try data("blockHash-21172670")
                default: return try data("blockHash-referencia")
                }
            case "state_getRuntimeVersion":
                let text = String(decoding: try data("runtimeVersion"), as: UTF8.self)
                return Data((runtime.map { text.replacingOccurrences(of: "\"transactionVersion\":15", with: "\"transactionVersion\":\($0)") } ?? text).utf8)
            case "state_getStorage":
                let key = params.first as? String ?? ""
                return try data(key.hasSuffix(Hex.encode(ownerKey)) ? "storage-dono" : "storage-vazia")
            case "state_call":
                if feeError { return Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32000,\"message\":\"Client error\"}}".utf8) }
                return try data("query_info")
            case "chain_getBlock": return try data("block-21172670")
            case "author_submitExtrinsic":
                if let submitRejection {
                    return Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":1010,\"message\":\"\(submitRejection)\"}}".utf8)
                }
                return Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"\(signedID)\"}".utf8)
            default: throw HTTPClient.Failure.status(404)
            }
        }
    }

    static func engine(_ transport: Transport = Transport()) -> PolkadotSendEngine {
        PolkadotSendEngine(reader: reader(transport))
    }

    static func reader(_ transport: Transport = Transport()) -> PolkadotReader {
        PolkadotReader(
            transport: transport,
            providers: ["a", "b", "c"].map { ProviderPool.Provider(name: $0, baseURL: URL(string: "https://\($0).test")!) },
            sidecar: URL(string: "https://sidecar.test")!, history: URL(string: "https://historico.test")!, pacing: 0
        )
    }

    static func message(_ error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? "\(error)" }
}

@Suite("Polkadot: motor de envio e Atividade")
struct PolkadotSendEngineTests {
    @Test("Maximo: o livre menos o deposito existencial e a taxa com folga")
    func spendable() async throws {
        let spendable = try await PolkadotEngineRecorded.engine().spendable(PolkadotEngineRecorded.request())
        #expect(spendable.amount == PolkadotEngineRecorded.free - PolkadotRuntime.existentialDeposit - BigUInt(10_570_026))
        #expect(spendable.reserveNote == "0,01 DOT fica na conta: é o mínimo que a rede exige para ela existir.")
        #expect(spendable.feeNote?.contains("0,0008808355 DOT") == true)
    }

    @Test("Plano de 0,5 DOT para conta vazia: revisao, avisos e intencao conferidos")
    func plan() async throws {
        let request = PolkadotEngineRecorded.request()
        let plan = try await PolkadotEngineRecorded.engine().plan(request)
        #expect(plan.chain == .polkadot && plan.walletID == request.walletID)
        #expect(plan.review.recipient == PolkadotEngineRecorded.destination)
        #expect(plan.review.warnings.contains(.firstSendToAddress))
        #expect(plan.review.warnings.contains(.activatesAccount(minimum: "0,01 DOT")))
        try PlanIntentCheck.send(plan.review, asset: .native(.polkadot), amount: request.amount, ceiling: PolkadotEngineRecorded.free, chain: .polkadot)
        let transfer = try #require(plan.transactions.first as? PolkadotTransfer)
        #expect(transfer.fields.nonce == 485 && transfer.fields.blockNumber == 21_173_079 && transfer.fields.era.period == 256)
    }

    @Test("Enviar tudo nunca passa do maximo; abaixo do deposito existencial, recusa com o minimo")
    func sendAllAndExistentialDeposit() async throws {
        let engine = PolkadotEngineRecorded.engine()
        let all = try await engine.plan(PolkadotEngineRecorded.request(amount: PolkadotEngineRecorded.free, sendAll: true))
        #expect(all.review.outgoing?.amount == PolkadotEngineRecorded.free - PolkadotRuntime.existentialDeposit - BigUInt(10_570_026))
        await #expect(throws: SendEngineError.message(PolkadotEngineText.insufficient)) {
            _ = try await engine.plan(PolkadotEngineRecorded.request(amount: PolkadotEngineRecorded.free))
        }
        do {
            _ = try await engine.plan(PolkadotEngineRecorded.request(amount: 50_000_000))
            Issue.record("envio abaixo do deposito existencial foi montado")
        } catch {
            #expect(PolkadotEngineRecorded.message(error) == "A conta de destino está vazia na rede Polkadot, e a rede só a cria com pelo menos 0,01 DOT. Envie esse valor ou mais.")
        }
    }

    @Test("Destino da Kusama, ativo que nao e DOT e conta que nao confere sao recusados antes de ler a rede")
    func refusals() async throws {
        let engine = PolkadotEngineRecorded.engine()
        do {
            _ = try await engine.plan(PolkadotEngineRecorded.request(to: "HNZata7iMYWmk5RvZRTiAsSDhV8366zq2YGb3tLH5Upf74F"))
            Issue.record("endereco da Kusama foi aceito")
        } catch {
            #expect(PolkadotEngineRecorded.message(error) == "Este endereço é da Kusama, não da Polkadot. Peça o endereço no formato Polkadot, que começa com 1.")
        }
        let usdt = try #require(TokenRegistry.tokens.first { $0.symbol == "USDT" })
        await #expect(throws: SendEngineError.message(PolkadotEngineText.unsupportedAsset)) {
            _ = try await engine.plan(PolkadotEngineRecorded.request(asset: usdt))
        }
        let other = PolkadotEngineRecorded.account(address: PolkadotEngineRecorded.destination)
        await #expect(throws: SendEngineError.message(PolkadotEngineText.keyMismatch)) {
            _ = try await engine.plan(PolkadotEngineRecorded.request(account: other))
        }
    }

    @Test("Runtime com outra versao de transacao, e no que nao avalia a transacao: nada e montado")
    func runtimeChanges() async throws {
        await #expect(throws: SendEngineError.message(PolkadotEngineText.runtimeChanged)) {
            _ = try await PolkadotEngineRecorded.engine(.init(runtime: "16")).plan(PolkadotEngineRecorded.request())
        }
        await #expect(throws: SendEngineError.message(PolkadotEngineText.notDecoded)) {
            _ = try await PolkadotEngineRecorded.engine(.init(feeError: true)).plan(PolkadotEngineRecorded.request())
        }
    }

    @Test("Destino vazio: a tela sabe o minimo antes do valor")
    func destination() async throws {
        let info = try await PolkadotEngineRecorded.engine().destination(PolkadotEngineRecorded.destination, chain: .polkadot)
        #expect(!info.exists && info.activationMinimum == PolkadotRuntime.existentialDeposit && info.note == PolkadotEngineText.emptyDestination)
        await #expect(throws: SendEngineError.self) { _ = try await PolkadotEngineRecorded.engine().destination("x", chain: .polkadot) }
    }

    @Test("Transmissao: so a extrinsic no formato da carteira, com o id calculado aqui")
    func broadcast() async throws {
        let engine = PolkadotEngineRecorded.engine()
        #expect(try await engine.broadcast([PolkadotEngineRecorded.signed], chain: .polkadot) == PolkadotEngineRecorded.signedID)
        var raw = PolkadotEngineRecorded.signed.raw
        raw[raw.count - 1] ^= 1
        // Outro valor, id recalculado: bem formada, mas o no devolve o hash da gravada.
        let tampered = SignedTransaction(chainID: "polkadot", raw: raw, encoded: Hex.encode(raw, prefix: true), id: PolkadotSignedExtrinsic.id(of: raw))
        await #expect(throws: SendEngineError.message(PolkadotEngineText.answerMismatch)) {
            _ = try await engine.broadcast([tampered], chain: .polkadot)
        }
        // Id que nao e o hash dos bytes: nem sai.
        let original = PolkadotEngineRecorded.signed
        let wrongID = SignedTransaction(chainID: "polkadot", raw: original.raw, encoded: original.encoded, id: PolkadotSignedExtrinsic.id(of: raw))
        await #expect(throws: SendEngineError.message(PolkadotEngineText.notOurTransaction)) {
            _ = try await engine.broadcast([wrongID], chain: .polkadot)
        }
        await #expect(throws: SendEngineError.unsupported(.sui)) { _ = try await engine.broadcast([PolkadotEngineRecorded.signed], chain: .sui) }
        #expect(await engine.status("0x" + String(repeating: "ab", count: 32), chain: .polkadot) == .pending)
    }

    @Test("Atividade: enviados e recebidos, nenhum sosia no historico gravado")
    func activity() async throws {
        let entries = try await PolkadotActivitySource(reader: PolkadotEngineRecorded.reader())
            .history(chain: .polkadot, account: PolkadotEngineRecorded.account(), usage: nil)
        #expect(entries.count == 30)
        #expect(entries.first?.direction == .sent && entries.first?.hash == PolkadotEngineRecorded.signedID)
        #expect(entries.contains { $0.direction == .received })
        #expect(!entries.contains { $0.suspicious })
        // Recebimento de um endereco que imita o destino pago: escondido.
        let paid = "149nNNvTDsJdvCBnEh83EG9j89GAk97a3ucoivz4RyqZGJJ3"
        let items = [
            ActivityItem(id: "1", chainID: "polkadot", direction: .sent, asset: .native(.polkadot), amount: 10, counterparty: paid,
                         date: .now, status: .confirmed, fee: 1, hash: "0x01", explorerURL: nil),
            ActivityItem(id: "2", chainID: "polkadot", direction: .received, asset: .native(.polkadot), amount: 10,
                         counterparty: "149nNNZaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaZGJJ3", date: .now, status: .confirmed, fee: nil, hash: "0x02", explorerURL: nil),
        ]
        #expect(PolkadotActivitySource.entries(items, owner: PolkadotEngineRecorded.owner).last?.suspicious == true)
    }

    @Test("So o sidecar diz que a transferencia nao saiu: pendente na tela, e o envio sem resposta fica com a nota de conferir")
    func sidecarFailureIsNotFinal() async throws {
        #expect(String(decoding: try PolkadotEngineRecorded.data("sidecar-21172670"), as: UTF8.self)
            .contains("\"hash\":\"\(PolkadotEngineRecorded.signedID)\",\"success\":true"))
        let engine = PolkadotEngineRecorded.engine(PolkadotEngineRecorded.Transport(sidecarFails: true))
        #expect(try await engine.broadcast([PolkadotEngineRecorded.signed], chain: .polkadot) == PolkadotEngineRecorded.signedID)
        // Duas leituras: a varredura acha a transacao num bloco final, e o resultado vem do sidecar. Nunca "falhou".
        for _ in 0..<2 {
            #expect(await engine.status(PolkadotEngineRecorded.signedID, chain: .polkadot) == .pending)
        }
        #expect(await engine.reader.unproven(PolkadotEngineRecorded.signedID))
        let record = UnsureSend(wallet: UUID(), chainID: Chain.polkadot.id, address: PolkadotEngineRecorded.owner, hash: PolkadotEngineRecorded.signedID,
                                sentAt: Date(), asset: .native(.polkadot), amount: 5_000_000_000, recipient: PolkadotEngineRecorded.destination)
        // A mesma nota do numero usado lido depois de reabrir o app: manda conferir, sem dizer que a transferencia nao saiu.
        #expect(await engine.lookup(record, chain: .polkadot) == .seenUnclear(note: PolkadotEngineText.failure("nonceUsed")))

        // O mesmo envio com o sidecar dizendo sucesso: confirmado, sem a marca.
        let fine = PolkadotEngineRecorded.engine()
        _ = try await fine.broadcast([PolkadotEngineRecorded.signed], chain: .polkadot)
        var last = TransferStatus.pending
        for _ in 0..<2 where last == .pending { last = await fine.status(PolkadotEngineRecorded.signedID, chain: .polkadot) }
        #expect(last == .confirmed(detail: PolkadotEngineText.confirmed))
        #expect(await !fine.reader.unproven(PolkadotEngineRecorded.signedID))
    }

    @Test("Numero antigo na transmissao (o \"Transmitir de novo\" da transacao que ja entrou): nunca \"nada saiu\"")
    func outdatedRejectionIsNotNothingLeft() async throws {
        let old = "Outra transação desta conta entrou antes. Nada saiu por esta. Confira a Atividade e envie de novo."
        #expect(PolkadotEngineText.rejected(.nonceTooLow) == PolkadotEngineText.failure("nonceUsed"))
        #expect(PolkadotEngineText.rejected(.nonceTooLow) != old)
        #expect(PolkadotEngineText.rejected(.nonceTooHigh) == old)
        #expect(PolkadotEngineText.broadcastError(ReaderError.broadcastRejected(.nonceTooLow, code: "1014"))
            == .message(PolkadotEngineText.failure("nonceUsed")))
        #expect(PolkadotEngineText.broadcastError(ReaderError.broadcastRejected(.nonceTooHigh, code: "1010")) == .message(old))
        // Pelo motor, como a tela recebe: os dois nos recusam com 1010 "Transaction is outdated".
        let engine = PolkadotEngineRecorded.engine(PolkadotEngineRecorded.Transport(submitRejection: "Invalid Transaction: Transaction is outdated"))
        await #expect(throws: SendEngineError.message(PolkadotEngineText.failure("nonceUsed"))) {
            _ = try await engine.broadcast([PolkadotEngineRecorded.signed], chain: .polkadot)
        }
        let future = PolkadotEngineRecorded.engine(PolkadotEngineRecorded.Transport(submitRejection: "Invalid Transaction: Transaction will be valid in the future"))
        await #expect(throws: SendEngineError.message(old)) {
            _ = try await future.broadcast([PolkadotEngineRecorded.signed], chain: .polkadot)
        }
    }

    @Test("Acompanhamento: numero usado fica pendente, so \"venceu\" vira falha")
    func statusFailsOnlyWhenExpired() async throws {
        let owner = try PolkadotAddress.parse(PolkadotEngineRecorded.owner).get()
        // O nonce gravado em storage-dono.json e 485; a era acabou 40 blocos antes do finalizado gravado (21.173.079).
        let finalized: UInt64 = 21_173_079
        let missing = "0x" + String(repeating: "cd", count: 32)
        let used = PolkadotEngineRecorded.engine()
        await used.reader.track(missing, birth: finalized - 70, death: finalized - 40, sender: owner, nonce: 484)
        #expect(try await used.reader.status(of: missing) == .failed(reason: "nonceUsed"))
        #expect(await used.status(missing, chain: .polkadot) == .pending)
        let expired = PolkadotEngineRecorded.engine()
        await expired.reader.track(missing, birth: finalized - 70, death: finalized - 40, sender: owner, nonce: 485)
        #expect(await expired.status(missing, chain: .polkadot) == .failed(reason: PolkadotEngineText.failure("expired")))
    }

    @Test("Registro: envio e historico existem, troca nao")
    func registry() {
        #expect(SendEngines.engine(for: .polkadot) is PolkadotSendEngine)
        #expect(ActivitySources.source(for: .polkadot) is PolkadotActivitySource)
        #expect(TradeEngines.engine(for: .polkadot) == nil)
    }
}
