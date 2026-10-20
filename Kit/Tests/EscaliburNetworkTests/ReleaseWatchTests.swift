import CryptoKit
import Foundation
import Testing
@testable import EscaliburNetwork

/// Respostas por host, com status: a loja e o site da lista.
final class ReleaseWatchStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var answers: [String: (Int, Data)] = [:]
    private static let lock = NSLock()

    static func set(_ values: [String: (Int, Data)]) { lock.withLock { answers = values } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        let answer = Self.lock.withLock { Self.answers[url.host ?? ""] } ?? (503, Data())
        client.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: answer.0, httpVersion: "HTTP/1.1", headerFields: [:])!,
                           cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: answer.1)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// O alarme de atualizacao nao confirmada: versao nova na loja fora da lista assinada, lista
/// sumida ou mexida avisam; sem versao nova, ou sem resposta, nao.
@Suite("Versao autorizada: o alarme da atualizacao", .serialized)
struct ReleaseWatchTests {
    static let app = "app.escalibur.wallet"
    static let chave = P256.Signing.PrivateKey()
    static let client = HTTPClient(protocolClasses: [ReleaseWatchStub.self], allowedHosts: ["itunes.apple.com", "escalibur-wallet.github.io"])

    static func loja(_ versao: String?) -> (Int, Data) {
        let resultados = versao.map { #"[{"version":"\#($0)"}]"# } ?? "[]"
        return (200, Data(#"{"resultCount":\#(versao == nil ? 0 : 1),"results":\#(resultados)}"#.utf8))
    }

    static func lista(_ versoes: [String], chave: P256.Signing.PrivateKey = chave) throws -> (Int, Data) {
        let texto = ReleaseManifestFixture.manifesto(versoes)
        let assinatura = try chave.signature(for: Data(texto.utf8)).rawRepresentation.base64EncodedString()
        return (200, try JSONSerialization.data(withJSONObject: ["manifesto": texto, "assinaturas": [["chave": "a", "p256": assinatura]]]))
    }

    static func checar(_ instalada: String) async -> ReleaseWatch.Verdict {
        await ReleaseWatch.check(installed: instalada, bundleID: app, country: "BR", client: client, keys: ["a": chave.publicKey], threshold: 1)
    }

    @Test("Versao nova na lista assinada: confirmada; fora dela: nao confirmada")
    func confirmada() async throws {
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.1"), "escalibur-wallet.github.io": try Self.lista(["1.0.0", "1.0.1"])])
        #expect(await Self.checar("1.0.0") == .confirmed("1.0.1"))
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2"), "escalibur-wallet.github.io": try Self.lista(["1.0.0", "1.0.1"])])
        #expect(await Self.checar("1.0.1") == .unconfirmed("1.0.2"))
    }

    @Test("Lista sumida (404): nao confirmada; assinada por outra chave: adulterada")
    func listaMexida() async throws {
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2"), "escalibur-wallet.github.io": (404, Data())])
        #expect(await Self.checar("1.0.1") == .unconfirmed("1.0.2"))
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2"), "escalibur-wallet.github.io": try Self.lista(["1.0.2"], chave: P256.Signing.PrivateKey())])
        #expect(await Self.checar("1.0.1") == .tampered("1.0.2"))
    }

    @Test("Nada mais novo, app fora da loja, ou sem resposta: sem alarme")
    func semAlarme() async throws {
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.0"), "escalibur-wallet.github.io": (404, Data())])
        #expect(await Self.checar("1.0.0") == .upToDate)
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja(nil)])
        #expect(await Self.checar("1.0.0") == .upToDate)
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.1"), "escalibur-wallet.github.io": (503, Data())])
        #expect(await Self.checar("1.0.0") == .unknown)
        ReleaseWatchStub.set([:])
        #expect(await Self.checar("1.0.0") == .unknown)
    }
}

enum ReleaseManifestFixture {
    static func manifesto(_ versoes: [String]) -> String {
        let itens = versoes.map { #"{"builds":["7"],"publicada":"2026-10-18","versao":"\#($0)"}"# }.joined(separator: ",")
        return #"{"app":"app.escalibur.wallet","emitido":"2026-10-18T12:00:00Z","formato":1,"versoes":[\#(itens)]}"#
    }
}
