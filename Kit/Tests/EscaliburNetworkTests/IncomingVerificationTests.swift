import EscaliburChains
import EscaliburCore
import Foundation
import Testing
@testable import EscaliburNetwork

/// Recebimento do historico conferido em dois RPCs (auditoria 3, M2).
@Suite("Recebimento conferido na rede")
struct IncomingVerificationTests {
    static let owner = try! EVMAddress("0xF977814e90dA44bFA03b6295A0616a897441aceC")
    static let usdt = try! EVMAddress("0xdAC17F958D2ee523a2206206994597C13D831ec7")
    static let other = try! EVMAddress("0x2652742DE21ED9a6c37e73b0E3a51b239A6D1008")
    static let hash = "0x" + String(repeating: "ab", count: 32)

    static func receipt(status: String = "0x1", contract: EVMAddress = usdt, to: EVMAddress = owner, amount: UInt64 = 5_000_000_000) -> Data {
        let topicTo = "0x" + String(repeating: "0", count: 24) + Hex.encode(to.bytes)
        let data = "0x" + String(repeating: "0", count: 64 - String(amount, radix: 16).count) + String(amount, radix: 16)
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"status":"\(status)","blockNumber":"0x10","blockHash":"0x\(String(repeating: "cd", count: 32))",
        "logs":[{"address":"\(contract.checksummed)","topics":["\(EVMReader.transferTopic)","0x000000000000000000000000\(Hex.encode(other.bytes))","\(topicTo)"],"data":"\(data)"}]}}
        """
        return Data(json.utf8)
    }

    /// `byHash`: o `eth_getTransactionByHash` de cada host (a testemunha de quem disse `null`); sem ele, falha.
    static func transport(_ receipts: [String: Data], byHash: [String: Data] = [:]) throws -> FixtureTransport {
        let chainID = try ReaderFixtures.data("evm", "eth_chainId-ethereum")
        let head = Data(#"{"jsonrpc":"2.0","id":1,"result":"0x20"}"#.utf8)
        return FixtureTransport([{ request, body in
            guard let method = FixtureTransport.method(body) else { return nil }
            switch method {
            case "eth_chainId": return chainID
            case "eth_blockNumber": return head
            case "eth_getTransactionReceipt": return receipts[request.url.host ?? ""]
            case "eth_getTransactionByHash": return byHash[request.url.host ?? ""]
            default: return nil
            }
        }])
    }

    static let none = Data(#"{"jsonrpc":"2.0","id":1,"result":null}"#.utf8)

    /// A transacao pelo hash, num bloco: o 0x10 e o hash de bloco dos recibos de `receipt`, salvo outro.
    static func mined(block: String = "0x10", blockHash: String = String(repeating: "cd", count: 32)) -> Data {
        Data(#"{"jsonrpc":"2.0","id":1,"result":{"hash":"\#(hash)","blockNumber":"\#(block)","blockHash":"0x\#(blockHash)"}}"#.utf8)
    }

    func check(_ receipts: [String: Data], byHash: [String: Data] = [:], amount: BigUInt = 5_000_000_000,
               providers: [String] = ["a", "b"]) async throws -> EVMReader.IncomingCheck {
        let reader = EVMReaderTests.reader(try Self.transport(receipts, byHash: byHash), providers: providers)
        return try await reader.verifyIncoming(chain: .ethereum, hash: Self.hash, owner: Self.owner, contract: Self.usdt, amount: amount)
    }

    @Test("Tres operadores mostram o Transfer para a conta com o valor: conferido; dois so, ainda nao (auditoria 8)")
    func confirmed() async throws {
        let result = try await check(["a.test": Self.receipt(), "b.test": Self.receipt(), "c.test": Self.receipt()], providers: ["a", "b", "c"])
        #expect(result == .confirmed(confirmations: 17))
        // O par sorteado sozinho nao confirma o que leva quem vendeu a entregar.
        await #expect(throws: ReaderError.notEnoughProviders(needed: 3, got: 2)) {
            _ = try await check(["a.test": Self.receipt(), "b.test": Self.receipt()])
        }
        // O terceiro sem recibo e sem testemunha conta contra: fica sem conferir.
        #expect(try await check(["a.test": Self.receipt(), "b.test": Self.receipt(), "c.test": Self.none], providers: ["a", "b", "c"]) == .notFound)
    }

    @Test("Valor, contrato ou destino diferente, ou transacao que falhou: nao confere")
    func mismatch() async throws {
        #expect(try await check(["a.test": Self.receipt(), "b.test": Self.receipt()], amount: 1) == .mismatch)
        #expect(try await check(["a.test": Self.receipt(contract: Self.other), "b.test": Self.receipt(contract: Self.other)]) == .mismatch)
        #expect(try await check(["a.test": Self.receipt(to: Self.other), "b.test": Self.receipt(to: Self.other)]) == .mismatch)
        #expect(try await check(["a.test": Self.receipt(status: "0x0"), "b.test": Self.receipt(status: "0x0")]) == .mismatch)
    }

    @Test("Sem recibo: ainda nao chegou na rede")
    func notFound() async throws {
        let none = Data(#"{"jsonrpc":"2.0","id":1,"result":null}"#.utf8)
        #expect(try await check(["a.test": none, "b.test": none]) == .notFound)
    }

    @Test("Um RPC diz que chegou e o outro nao: nao confere (o `null` nao vota, e um recibo so nao basta)")
    func onlyOne() async throws {
        let none = Data(#"{"jsonrpc":"2.0","id":1,"result":null}"#.utf8)
        #expect(try await check(["a.test": Self.receipt(), "b.test": none]) == .notFound)
    }

    @Test("Dois recibos diferentes, sem par: erro")
    func disagree() async throws {
        await #expect(throws: ReaderError.self) {
            _ = try await check(["a.test": Self.receipt(), "b.test": Self.receipt(amount: 1)])
        }
    }

    @Test("Recebimento de dias atras: o primeiro sem indice, mas com a transacao no bloco; os de baixo com o recibo")
    func oldReceipt() async throws {
        let three = ["a.test": Self.none, "b.test": Self.receipt(), "c.test": Self.receipt(), "d.test": Self.receipt()]
        let result = try await check(three, byHash: ["a.test": Self.mined()], providers: ["a", "b", "c", "d"])
        #expect(result == .confirmed(confirmations: 17))
        // Dois sem indice: o recibo de dois so nao basta (a testemunha ve o bloco, e nao o Transfer).
        let receipts = ["a.test": Self.none, "b.test": Self.none, "c.test": Self.receipt(), "d.test": Self.receipt()]
        await #expect(throws: ReaderError.notEnoughProviders(needed: 3, got: 2)) {
            _ = try await check(receipts, byHash: ["a.test": Self.mined(), "b.test": Self.mined()], providers: ["a", "b", "c", "d"])
        }
        // Uma testemunha falha (b sem resposta): conta contra, e fica sem conferir ate a leitura seguinte.
        #expect(try await check(receipts, byHash: ["a.test": Self.mined()], providers: ["a", "b", "c", "d"]) == .notFound)
        // A testemunha viu a transacao em outro bloco: os dois de baixo nao decidem, e fica sem conferir (nao e erro).
        let elsewhere = try await check(receipts, byHash: ["a.test": Self.mined(block: "0x11"), "b.test": Self.mined()],
                                        providers: ["a", "b", "c", "d"])
        #expect(elsewhere == .notFound)
    }

    @Test("Hash que nao existe: os honestos dizem `null` e a testemunha nao tem a transacao; os de baixo nem sao perguntados")
    func forgedIncoming() async throws {
        let receipts = ["a.test": Self.none, "b.test": Self.none, "c.test": Self.receipt(), "d.test": Self.receipt()]
        let transport = try Self.transport(receipts, byHash: ["a.test": Self.none, "b.test": Self.none])
        let reader = EVMReaderTests.reader(transport, providers: ["a", "b", "c", "d"])
        let result = try await reader.verifyIncoming(chain: .ethereum, hash: Self.hash, owner: Self.owner, contract: Self.usdt, amount: 5_000_000_000)
        #expect(result == .notFound)
        #expect(!transport.requests.contains { $0.url.host == "c.test" || $0.url.host == "d.test" })
    }

    @Test("Transacao antiga: a testemunha honesta confirma o bloco, dois forjam o Transfer e o quarto, honesto, e ouvido")
    func forgedOldIncoming() async throws {
        let receipts = ["a.test": Self.none, "b.test": Self.receipt(), "c.test": Self.receipt(), "d.test": Self.receipt(to: Self.other)]
        await #expect(throws: ReaderError.self) {
            _ = try await check(receipts, byHash: ["a.test": Self.mined()], providers: ["a", "b", "c", "d"])
        }
    }

    @Test("Ponte: o recibo com os logs segue a mesma regra (`null` nao vota, testemunha, diferentes sem decisao)")
    func receiptLogs() async throws {
        func logs(_ receipts: [String: Data], byHash: [String: Data] = [:], providers: [String]) async throws -> EVMReader.ReceiptLogs? {
            try await EVMReaderTests.reader(try Self.transport(receipts, byHash: byHash), providers: providers)
                .receiptLogs(chain: .ethereum, hash: Self.hash)
        }
        let old = try await logs(["a.test": Self.none, "b.test": Self.none, "c.test": Self.receipt(), "d.test": Self.receipt()],
                                 byHash: ["a.test": Self.mined(), "b.test": Self.mined()], providers: ["a", "b", "c", "d"])
        #expect(old?.block == 16 && old?.success == true && old?.logs.count == 1)
        #expect(try await logs(["a.test": Self.receipt(), "b.test": Self.none], providers: ["a", "b"]) == nil)
        await #expect(throws: ReaderError.self) {
            _ = try await logs(["a.test": Self.receipt(), "b.test": Self.receipt(amount: 1)], providers: ["a", "b"])
        }
    }
}
