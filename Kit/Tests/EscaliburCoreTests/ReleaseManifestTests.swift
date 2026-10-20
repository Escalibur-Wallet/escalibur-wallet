import CryptoKit
import Foundation
import Testing
@testable import EscaliburCore

/// A lista assinada de versoes: so vale com assinaturas das chaves compiladas, no limiar, do
/// app certo; texto mexido depois de assinado nao passa.
@Suite("Versao autorizada: lista assinada")
struct ReleaseManifestTests {
    static let app = "app.escalibur.wallet"

    static func manifesto(_ versoes: [String] = ["1.0.0"], app: String = app) -> String {
        let itens = versoes.map { #"{"builds":["7"],"publicada":"2026-10-18","versao":"\#($0)"}"# }.joined(separator: ",")
        return #"{"app":"\#(app)","emitido":"2026-10-18T12:00:00Z","formato":1,"versoes":[\#(itens)]}"#
    }

    static func arquivo(_ texto: String, assinantes: [(String, P256.Signing.PrivateKey)]) throws -> Data {
        let assinaturas = try assinantes.map { id, chave in
            ["chave": id, "p256": try chave.signature(for: Data(texto.utf8)).rawRepresentation.base64EncodedString()]
        }
        return try JSONSerialization.data(withJSONObject: ["manifesto": texto, "assinaturas": assinaturas])
    }

    @Test("Assinada por uma chave confiavel: le as versoes e diz quem assinou")
    func valida() throws {
        let chave = P256.Signing.PrivateKey()
        let dados = try Self.arquivo(Self.manifesto(["1.0.0", "1.0.1"]), assinantes: [("a", chave)])
        let lista = try ReleaseManifest.verified(dados, app: Self.app, keys: ["a": chave.publicKey], threshold: 1)
        #expect(lista.authorizes(version: "1.0.1") && !lista.authorizes(version: "1.0.2"))
        #expect(lista.signedBy == ["a"])
    }

    @Test("Chave desconhecida, assinatura de outro texto e limiar nao alcancado: recusa")
    func recusas() throws {
        let boa = P256.Signing.PrivateKey(), estranha = P256.Signing.PrivateKey()
        let texto = Self.manifesto()
        // Assinada por quem nao esta na lista.
        #expect(throws: ReleaseManifest.Failure.notEnoughSignatures) {
            try ReleaseManifest.verified(try Self.arquivo(texto, assinantes: [("a", estranha)]), app: Self.app, keys: ["a": boa.publicKey], threshold: 1)
        }
        // O texto mudou depois da assinatura (uma versao a mais enfiada na lista).
        var mexido = try JSONSerialization.jsonObject(with: try Self.arquivo(texto, assinantes: [("a", boa)])) as! [String: Any]
        mexido["manifesto"] = Self.manifesto(["1.0.0", "6.6.6"])
        #expect(throws: ReleaseManifest.Failure.notEnoughSignatures) {
            try ReleaseManifest.verified(try JSONSerialization.data(withJSONObject: mexido), app: Self.app, keys: ["a": boa.publicKey], threshold: 1)
        }
        // Duas de duas pedidas, uma so assinou; a mesma chave duas vezes conta uma.
        let segunda = P256.Signing.PrivateKey()
        let chaves = ["a": boa.publicKey, "b": segunda.publicKey]
        #expect(throws: ReleaseManifest.Failure.notEnoughSignatures) {
            try ReleaseManifest.verified(try Self.arquivo(texto, assinantes: [("a", boa), ("a", boa)]), app: Self.app, keys: chaves, threshold: 2)
        }
        #expect(try ReleaseManifest.verified(try Self.arquivo(texto, assinantes: [("a", boa), ("b", segunda)]), app: Self.app, keys: chaves, threshold: 2).signedBy == ["a", "b"])
        // Limiar zero nunca aceita.
        #expect(throws: ReleaseManifest.Failure.notEnoughSignatures) {
            try ReleaseManifest.verified(try Self.arquivo(texto, assinantes: []), app: Self.app, keys: chaves, threshold: 0)
        }
    }

    @Test("Lista de outro app, formato desconhecido ou arquivo ilegivel: recusa")
    func outroApp() throws {
        let chave = P256.Signing.PrivateKey()
        #expect(throws: ReleaseManifest.Failure.wrongApp) {
            try ReleaseManifest.verified(try Self.arquivo(Self.manifesto(app: "outro.app"), assinantes: [("a", chave)]), app: Self.app, keys: ["a": chave.publicKey], threshold: 1)
        }
        let formato2 = Self.manifesto().replacingOccurrences(of: #""formato":1"#, with: #""formato":2"#)
        #expect(throws: ReleaseManifest.Failure.unknownFormat) {
            try ReleaseManifest.verified(try Self.arquivo(formato2, assinantes: [("a", chave)]), app: Self.app, keys: ["a": chave.publicKey], threshold: 1)
        }
        #expect(throws: ReleaseManifest.Failure.malformed) {
            try ReleaseManifest.verified(Data("<html>404</html>".utf8), app: Self.app, keys: ["a": chave.publicKey], threshold: 1)
        }
    }

    @Test("Versao mais nova, numero a numero")
    func comparacao() {
        #expect(ReleaseManifest.isNewer("1.0.10", than: "1.0.9"))
        #expect(ReleaseManifest.isNewer("1.1", than: "1.0.9"))
        #expect(!ReleaseManifest.isNewer("1.0.0", than: "1.0.0"))
        #expect(!ReleaseManifest.isNewer("1.0", than: "1.0.0"))
        #expect(!ReleaseManifest.isNewer("1.0.0-beta", than: "0.9"))
    }

    @Test("As chaves compiladas: todas leem como P-256, e o limiar cabe nelas")
    func chavesCompiladas() {
        #expect(ReleaseKeys.trusted.count == ReleaseKeys.published.count)
        #expect(ReleaseKeys.threshold >= 1 && ReleaseKeys.threshold <= ReleaseKeys.trusted.count)
    }

    /// A lista que o site publica (`site/versoes.json`, assinada no Mac do dono) passa pelo
    /// mesmo codigo que o app usa, com as chaves compiladas, e autoriza a versao do projeto.
    @Test("A lista do site confere com as chaves do app")
    func listaDoSite() throws {
        let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let arquivo = raiz.appendingPathComponent("site/versoes.json")
        guard let data = try? Data(contentsOf: arquivo) else { return }
        let lista = try ReleaseManifest.verified(data, app: Self.app)
        #expect(lista.signedBy.count >= ReleaseKeys.threshold)
        let projeto = try String(contentsOf: raiz.appendingPathComponent("project.yml"), encoding: .utf8)
        let versao = projeto.firstMatch(of: /MARKETING_VERSION: "([0-9.]+)"/).map { String($0.1) }
        let build = projeto.firstMatch(of: /CURRENT_PROJECT_VERSION: "([0-9]+)"/).map { String($0.1) }
        #expect(versao.map(lista.authorizes(version:)) == true, "a versao do project.yml nao esta na lista")
        // O app leva esta lista: um build fora dela sairia trancado. Subir o build pede a
        // assinatura antes (docs/release.md).
        #expect(lista.versions.contains { $0.version == versao && build.map($0.builds.contains) == true },
                "o build do project.yml nao esta na lista assinada: assine antes (tools/versoes/versoes.swift autorizar)")
    }

    /// A chave do Mac do dono mudou de nome no build 11. A lista do app (a que vai no bundle)
    /// confere so com o nome novo e nao leva o antigo; a do site confere tambem para os builds
    /// 7 a 10, que so conhecem o nome antigo da mesma chave publica.
    @Test("Lista do app e do site: o nome novo para o app, o antigo ainda vale no site")
    func listasComONomeNovo() throws {
        let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let doApp = try Data(contentsOf: raiz.appendingPathComponent("App/EscaliburWallet/Resources/Versoes/versoes.json"))
        let doSite = try Data(contentsOf: raiz.appendingPathComponent("site/versoes.json"))
        #expect(try ReleaseManifest.verified(doApp, app: Self.app).signedBy == Set(ReleaseKeys.published.keys))
        #expect(!String(decoding: doApp, as: UTF8.self).contains("mac-thomaz"), "a lista do app leva o nome antigo")
        let publica = try #require(ReleaseKeys.trusted["escalibur-mac-1"])
        let antigos = try ReleaseManifest.verified(doSite, app: Self.app, keys: ["mac-thomaz-1": publica], threshold: 1)
        #expect(antigos.signedBy == ["mac-thomaz-1"])
        #expect(try ReleaseManifest.verified(doSite, app: Self.app).signedBy == ["escalibur-mac-1"])
    }
}
