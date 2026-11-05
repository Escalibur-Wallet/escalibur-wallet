#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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

    static let appStoreID = 6823379335
    static let agora = ISO8601DateFormatter().date(from: "2026-11-10T12:00:00Z")!

    static func loja(_ versao: String?, sistemaMinimo: String = "17.0", app: Int = appStoreID,
                     publicadaEm: String = "2026-11-08T07:00:00Z") -> (Int, Data) {
        let resultados = versao.map {
            #"[{"version":"\#($0)","minimumOsVersion":"\#(sistemaMinimo)","trackId":\#(app),"currentVersionReleaseDate":"\#(publicadaEm)"}]"#
        } ?? "[]"
        return (200, Data(#"{"resultCount":\#(versao == nil ? 0 : 1),"results":\#(resultados)}"#.utf8))
    }

    static func lista(_ versoes: [String], liberadas: [String]? = nil, obrigatoria: String? = nil, emitido: String = "2026-11-05T12:00:00Z",
                      chave: P256.Signing.PrivateKey = chave) throws -> (Int, Data) {
        let texto = ReleaseManifestFixture.manifesto(versoes, liberadas: liberadas ?? versoes, obrigatoria: obrigatoria, emitido: emitido)
        let assinatura = try chave.signature(for: Data(texto.utf8)).rawRepresentation.base64EncodedString()
        return (200, try JSONSerialization.data(withJSONObject: ["manifesto": texto, "assinaturas": [["chave": "a", "p256": assinatura]]]))
    }

    static func checar(_ instalada: String, sistema: String? = "18.1", piso: String? = nil) async -> ReleaseWatch.Verdict {
        await ReleaseWatch.check(installed: instalada, bundleID: app, country: "BR", systemVersion: sistema, appStoreID: appStoreID,
                                 issuedFloor: piso.flatMap { ISO8601DateFormatter().date(from: $0) }, now: agora, client: client,
                                 keys: ["a": chave.publicKey], threshold: 1).verdict
    }

    @Test("Versao nova na lista assinada: confirmada; fora dela: nao confirmada")
    func confirmada() async throws {
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.1"), "escalibur-wallet.github.io": try Self.lista(["1.0.0", "1.0.1"])])
        #expect(await Self.checar("1.0.0") == .confirmed("1.0.1"))
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2"), "escalibur-wallet.github.io": try Self.lista(["1.0.0", "1.0.1"])])
        #expect(await Self.checar("1.0.1") == .unconfirmed("1.0.2"))
    }

    @Test("Na lista e ainda nao liberada: sem tela, como antes; fora da lista: o alarme")
    func naoLiberada() async throws {
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2"),
                              "escalibur-wallet.github.io": try Self.lista(["1.0.1", "1.0.2"], liberadas: ["1.0.1"], obrigatoria: #"{"minima":"1.0.2"}"#)])
        #expect(await Self.checar("1.0.1") == .upToDate)
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.3"),
                              "escalibur-wallet.github.io": try Self.lista(["1.0.1", "1.0.2"], liberadas: ["1.0.1"])])
        #expect(await Self.checar("1.0.1") == .unconfirmed("1.0.3"))
    }

    @Test("Lista assinada mais antiga que a ja vista: velha, sem a obrigacao dela; o alarme continua")
    func listaAntiga() async throws {
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2"),
                              "escalibur-wallet.github.io": try Self.lista(["1.0.1", "1.0.2"], obrigatoria: #"{"minima":"1.0.2"}"#, emitido: "2026-11-05T12:00:00Z")])
        #expect(await Self.checar("1.0.1", piso: "2026-11-06T00:00:00Z") == .stale("1.0.2"))
        #expect(await Self.checar("1.0.1", piso: "2026-11-05T12:00:00Z") == .required("1.0.2"))
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.3"),
                              "escalibur-wallet.github.io": try Self.lista(["1.0.1", "1.0.2"], emitido: "2026-11-05T12:00:00Z")])
        #expect(await Self.checar("1.0.1", piso: "2026-11-06T00:00:00Z") == .unconfirmed("1.0.3"))
    }

    @Test("Obrigacao malformada vale como nenhuma, sem alarme de lista mexida")
    func obrigacaoMalformada() async throws {
        for regra in [#""x""#, #"{"minima":1}"#, #"{"versoes":["1.0.1",null]}"#] {
            ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2"),
                                  "escalibur-wallet.github.io": try Self.lista(["1.0.1", "1.0.2"], obrigatoria: regra)])
            #expect(await Self.checar("1.0.1") == .confirmed("1.0.2"))
        }
    }

    @Test("Lista que obriga a instalada: obrigatoria, so se a versao da loja tira da tela e instala neste aparelho")
    func obrigatoria() async throws {
        let versoes = ["1.0.0", "1.0.1", "1.0.2"]
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2"), "escalibur-wallet.github.io": try Self.lista(versoes, obrigatoria: #"{"minima":"1.0.2"}"#)])
        #expect(await Self.checar("1.0.1") == .required("1.0.2"))
        // Sistema abaixo do minimo da versao nova, ou desconhecido: a tela de deixar para depois.
        #expect(await Self.checar("1.0.1", sistema: "16.7") == .confirmed("1.0.2"))
        #expect(await Self.checar("1.0.1", sistema: nil) == .confirmed("1.0.2"))
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2", sistemaMinimo: "18.2"), "escalibur-wallet.github.io": try Self.lista(versoes, obrigatoria: #"{"minima":"1.0.2"}"#)])
        #expect(await Self.checar("1.0.1") == .confirmed("1.0.2"))
        // A propria versao da loja dentro da regra: atualizar nao tiraria da tela.
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2"), "escalibur-wallet.github.io": try Self.lista(versoes, obrigatoria: #"{"versoes":["1.0.1","1.0.2"]}"#)])
        #expect(await Self.checar("1.0.1") == .confirmed("1.0.2"))
        // Outro app na consulta, versao na loja ha menos de um dia, ou sistema ilegivel: a tela de deixar para depois.
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2", app: 1), "escalibur-wallet.github.io": try Self.lista(versoes, obrigatoria: #"{"minima":"1.0.2"}"#)])
        #expect(await Self.checar("1.0.1") == .confirmed("1.0.2"))
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2", publicadaEm: "2026-11-10T01:00:00Z"),
                              "escalibur-wallet.github.io": try Self.lista(versoes, obrigatoria: #"{"minima":"1.0.2"}"#)])
        #expect(await Self.checar("1.0.1") == .confirmed("1.0.2"))
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2", sistemaMinimo: "x"), "escalibur-wallet.github.io": try Self.lista(versoes, obrigatoria: #"{"minima":"1.0.2"}"#)])
        #expect(await Self.checar("1.0.1") == .confirmed("1.0.2"))
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2"), "escalibur-wallet.github.io": try Self.lista(versoes, obrigatoria: #"{"minima":"1.0.2"}"#)])
        #expect(await Self.checar("1.0.1", sistema: "dezoito") == .confirmed("1.0.2"))
        // A regra pega outra versao, nao a instalada.
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.2"), "escalibur-wallet.github.io": try Self.lista(versoes, obrigatoria: #"{"versoes":["1.0.0"]}"#)])
        #expect(await Self.checar("1.0.1") == .confirmed("1.0.2"))
        #expect(await Self.checar("1.0.0") == .required("1.0.2"))
        // Versao da loja fora da lista: o alarme, nunca a obrigatoria.
        ReleaseWatchStub.set(["itunes.apple.com": Self.loja("1.0.3"), "escalibur-wallet.github.io": try Self.lista(versoes, obrigatoria: #"{"minima":"1.0.2"}"#)])
        #expect(await Self.checar("1.0.1") == .unconfirmed("1.0.3"))
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
    static func manifesto(_ versoes: [String], liberadas: [String] = [], obrigatoria: String? = nil, emitido: String = "2026-10-18T12:00:00Z") -> String {
        let itens = versoes.map { versao in
            let liberada = liberadas.contains(versao) ? #","liberada":"2026-11-07""# : ""
            return #"{"builds":["7"]\#(liberada),"publicada":"2026-10-18","versao":"\#(versao)"}"#
        }.joined(separator: ",")
        let regra = obrigatoria.map { #""obrigatoria":\#($0),"# } ?? ""
        return #"{"app":"app.escalibur.wallet","emitido":"\#(emitido)","formato":1,\#(regra)"versoes":[\#(itens)]}"#
    }
}
