import Foundation
import Testing
@testable import EscaliburNetwork

/// Um servidor de mentira: responde pelo caminho da URL.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        switch url.path {
        case "/pequeno":
            let body = Data("{\"ok\":true}".utf8)
            client.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(body.count)"])!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: body)
        case "/sem-tamanho":
            // Chunked: sem Content-Length, 5 MB em pedacos.
            client.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
            let chunk = Data(repeating: 0x61, count: 256 * 1024)
            for _ in 0..<20 { client.urlProtocol(self, didLoad: chunk) }
        case "/anuncia-grande":
            client.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(10 * 1024 * 1024)"])!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data(repeating: 0x61, count: 1024))
        case "/erro":
            client.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
        default:
            client.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Cliente HTTP: limites")
struct HTTPClientTests {
    let client = HTTPClient(protocolClasses: [StubProtocol.self], allowedHosts: ["stub.example"])

    @Test("Resposta pequena passa")
    func small() async throws {
        let data = try await client.get(URL(string: "https://stub.example/pequeno")!)
        #expect(data == Data("{\"ok\":true}".utf8))
    }

    @Test("Sem Content-Length, o corte acontece no meio do fluxo")
    func chunkedTooLarge() async {
        await #expect(throws: HTTPClient.Failure.tooLarge) {
            try await client.get(URL(string: "https://stub.example/sem-tamanho")!)
        }
    }

    @Test("Content-Length acima do limite e recusado antes do corpo")
    func announcedTooLarge() async {
        await #expect(throws: HTTPClient.Failure.tooLarge) {
            try await client.get(URL(string: "https://stub.example/anuncia-grande")!)
        }
    }

    @Test("Muitas leituras ao mesmo tempo num cliente novo: todas voltam, cada uma com a sua")
    func concurrentFreshClient() async throws {
        let fresh = HTTPClient(protocolClasses: [StubProtocol.self], allowedHosts: ["stub.example"])
        let answers = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<64 {
                group.addTask { try await fresh.get(URL(string: "https://stub.example/pequeno")!) }
            }
            return try await group.reduce(into: [Data]()) { $0.append($1) }
        }
        #expect(answers.count == 64)
        #expect(answers.allSatisfy { $0 == Data("{\"ok\":true}".utf8) })
    }

    @Test("Status de erro e so HTTPS")
    func statusAndScheme() async {
        await #expect(throws: HTTPClient.Failure.status(503)) {
            try await client.get(URL(string: "https://stub.example/erro")!)
        }
        await #expect(throws: HTTPClient.Failure.hostNotAllowed) {
            try await client.get(URL(string: "http://stub.example/pequeno")!)
        }
    }

    @Test("Host fora da lista nao sai do aparelho")
    func hostNotAllowed() async {
        await #expect(throws: HTTPClient.Failure.hostNotAllowed) {
            try await client.get(URL(string: "https://outro.example/pequeno")!)
        }
        #expect(AllowedHosts.all.contains("mempool.space"))
        #expect(!AllowedHosts.all.contains("stub.example"))
        // Porta fora da 443, e o GitHub fora das logos da Trust Wallet (auditoria 6).
        await #expect(throws: HTTPClient.Failure.hostNotAllowed) {
            try await client.get(URL(string: "https://stub.example:8443/pequeno")!)
        }
        let raw = HTTPClient(protocolClasses: [StubProtocol.self], allowedHosts: ["raw.githubusercontent.com"])
        await #expect(throws: HTTPClient.Failure.hostNotAllowed) {
            try await raw.get(URL(string: "https://raw.githubusercontent.com/outra-conta/outro-repo/main/x.json")!)
        }
        // A 51234 so para os servidores da Ripple, que atendem JSON-RPC nela.
        #expect(HTTPClient.permits(URL(string: "https://s1.ripple.com:51234")!, allowedHosts: AllowedHosts.all))
        #expect(!HTTPClient.permits(URL(string: "https://s1.ripple.com:8443")!, allowedHosts: AllowedHosts.all))
        #expect(!HTTPClient.permits(URL(string: "https://xrplcluster.com:51234")!, allowedHosts: AllowedHosts.all))
    }

    /// Todo endereco escrito no codigo do Kit e do app, de host da lista, passa pela regra do
    /// HTTPClient. A trava de porta da auditoria 6 recusou os dois servidores da Ripple na
    /// 51234 e nenhum teste viu: a XRP Ledger ficou com um servidor so no build 9.
    @Test("Todo endereco do codigo passa pela regra do HTTPClient")
    func everyCodedURLIsPermitted() throws {
        let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let padrao = try Regex(#""(https://[A-Za-z0-9.-]+(?::[0-9]+)?[^"\\\s]*)"#)
        var conferidos = 0
        var recusados: [String] = []
        for pasta in ["Kit/Sources", "App/EscaliburWallet"] {
            let lista = FileManager.default.enumerator(at: raiz.appendingPathComponent(pasta), includingPropertiesForKeys: nil)
            while let arquivo = lista?.nextObject() as? URL {
                guard arquivo.pathExtension == "swift", let texto = try? String(contentsOf: arquivo, encoding: .utf8) else { continue }
                for linha in texto.split(separator: "\n") where !linha.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    for achado in linha.matches(of: padrao) {
                        guard let url = URL(string: String(achado.output[1].substring ?? "")), let host = url.host,
                              AllowedHosts.all.contains(host) else { continue }
                        conferidos += 1
                        if !HTTPClient.permits(url, allowedHosts: AllowedHosts.all) { recusados.append("\(arquivo.lastPathComponent): \(url)") }
                    }
                }
            }
        }
        #expect(conferidos > 100, "achou \(conferidos) enderecos")
        #expect(recusados.isEmpty, "recusados: \(recusados)")
    }

    @Test("Com uma tela de segredo aberta, nada sai; fechada, volta")
    func quiet() async throws {
        let quiet = HTTPClient(protocolClasses: [StubProtocol.self], allowedHosts: ["stub.example"])
        quiet.beginQuiet()
        quiet.beginQuiet()
        await #expect(throws: HTTPClient.Failure.offline) {
            try await quiet.get(URL(string: "https://stub.example/pequeno")!)
        }
        quiet.endQuiet()
        // Duas telas abertas, uma fechada: continua em silencio.
        #expect(quiet.isQuiet)
        await #expect(throws: HTTPClient.Failure.offline) {
            try await quiet.get(URL(string: "https://stub.example/pequeno")!)
        }
        quiet.endQuiet()
        #expect(!quiet.isQuiet)
        let data = try await quiet.get(URL(string: "https://stub.example/pequeno")!)
        #expect(data == Data("{\"ok\":true}".utf8))
    }
}
