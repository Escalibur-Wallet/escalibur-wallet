#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// A lista de versoes autorizadas pela Escalibur, assinada por chaves de `ReleaseKeys`
/// (docs/seguranca.md, "Versao autorizada"). Publicada no site (`versoes.json`), mas a
/// confianca nao vem do site: vem das assinaturas. Quem invadir o GitHub apaga ou troca o
/// arquivo, mas nao assina outra lista; quem invadir a conta da App Store publica uma versao
/// que nao esta na lista, e o app instalado avisa.
///
/// O arquivo: `{"manifesto": "<o JSON, em texto>", "assinaturas": [{"chave", "p256"}]}`. O
/// texto do manifesto e o que foi assinado, byte a byte: nada e reformatado antes de conferir.
public struct ReleaseManifest: Sendable, Equatable {
    public struct Version: Sendable, Equatable, Codable {
        public let version: String
        public let builds: [String]
        public let published: String
        /// O dia em que o dono viu o build dele aprovado e na App Store e assinou de novo (`versoes.swift liberar`). Sem
        /// isso, a versao so passa na conferencia: a tela de atualizar nao empurra ninguem para ela. A versao entra na lista
        /// antes de o binario existir, e um build de terceiro com o mesmo numero tambem diria "confirmada" (auditoria 6,
        /// A6-01; revisao dos 3 agentes de 05/11/2026). Depois de publicada, a Apple nao aceita outro build com o numero.
        public let released: String?

        enum CodingKeys: String, CodingKey { case version = "versao", builds, published = "publicada", released = "liberada" }

        public init(version: String, builds: [String], published: String, released: String? = nil) {
            self.version = version
            self.builds = builds
            self.published = published
            self.released = released
        }

        /// O campo novo nao derruba a lista: com outro tipo, vale como nao liberada.
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(String.self, forKey: .version)
            builds = try values.decode([String].self, forKey: .builds)
            published = try values.decode(String.self, forKey: .published)
            released = (try? values.decodeIfPresent(String.self, forKey: .released))
        }
    }

    /// A atualizacao obrigatoria (pedido do dono, 05/11/2026): quem esta abaixo de `minimum`, ou numa das `versions`, perde
    /// o "Vou atualizar depois". Campo opcional do formato 1: os builds de antes nao leem e seguem conferindo a lista. Um
    /// valor de outro tipo vale como sem obrigacao, e nunca como lista mexida (o alarme de hack).
    public struct Mandatory: Sendable, Equatable, Decodable {
        public let minimum: String?
        public let versions: [String]

        enum CodingKeys: String, CodingKey { case minimum = "minima", versions = "versoes" }

        public init(minimum: String?, versions: [String]) {
            self.minimum = minimum
            self.versions = versions
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            minimum = (try? values.decodeIfPresent(String.self, forKey: .minimum))
            versions = (try? values.decodeIfPresent([String].self, forKey: .versions)) ?? []
        }

        /// A versao `installed` tem de atualizar.
        public func requires(_ installed: String) -> Bool {
            versions.contains(installed) || minimum.map { ReleaseManifest.isNewer($0, than: installed) } == true
        }
    }

    public let app: String
    public let issuedAt: String
    public let versions: [Version]
    public let mandatory: Mandatory?
    /// As chaves que assinaram de verdade.
    public let signedBy: Set<String>

    public enum Failure: Error, Equatable, Sendable {
        case malformed
        case unknownFormat
        case wrongApp
        case notEnoughSignatures
    }

    private struct Envelope: Decodable {
        let manifesto: String
        let assinaturas: [Signature]
    }

    private struct Signature: Decodable {
        let chave: String
        let p256: String
    }

    private struct Body: Decodable {
        let formato: Int
        let app: String
        let emitido: String
        let versoes: [Version]
        let obrigatoria: Mandatory?

        enum CodingKeys: String, CodingKey { case formato, app, emitido, versoes, obrigatoria }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            formato = try values.decode(Int.self, forKey: .formato)
            app = try values.decode(String.self, forKey: .app)
            emitido = try values.decode(String.self, forKey: .emitido)
            versoes = try values.decode([Version].self, forKey: .versoes)
            obrigatoria = (try? values.decodeIfPresent(Mandatory.self, forKey: .obrigatoria))
        }
    }

    /// Le e confere: pelo menos `threshold` chaves diferentes de `keys` assinaram o texto do
    /// manifesto, e ele e deste app, no formato 1. Assinatura de chave desconhecida nao conta.
    public static func verified(
        _ data: Data, app: String,
        keys: [String: P256.Signing.PublicKey] = ReleaseKeys.trusted, threshold: Int = ReleaseKeys.threshold
    ) throws -> ReleaseManifest {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw Failure.malformed }
        let signed = Data(envelope.manifesto.utf8)
        var valid = Set<String>()
        for signature in envelope.assinaturas {
            guard let key = keys[signature.chave], let raw = Data(base64Encoded: signature.p256),
                  let ecdsa = try? P256.Signing.ECDSASignature(rawRepresentation: raw),
                  key.isValidSignature(ecdsa, for: signed) else { continue }
            valid.insert(signature.chave)
        }
        guard threshold > 0, valid.count >= threshold else { throw Failure.notEnoughSignatures }
        guard let body = try? JSONDecoder().decode(Body.self, from: signed) else { throw Failure.malformed }
        guard body.formato == 1 else { throw Failure.unknownFormat }
        guard body.app == app else { throw Failure.wrongApp }
        return ReleaseManifest(app: body.app, issuedAt: body.emitido, versions: body.versoes, mandatory: body.obrigatoria, signedBy: valid)
    }

    public func authorizes(version: String) -> Bool {
        versions.contains { $0.version == version }
    }

    /// A versao esta na lista e o dono a liberou depois de a Apple publicar o build dele.
    public func released(version: String) -> Bool {
        versions.contains { $0.version == version && $0.released != nil }
    }

    /// "1.0.10" depois de "1.0.9": compara numero a numero. Texto fora do formato fica atras.
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = numbers(candidate), b = numbers(installed)
        guard !a.isEmpty, !b.isEmpty else { return false }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Um numero de versao que a comparacao le ("18.1", "1.0.2").
    public static func isVersion(_ text: String) -> Bool {
        !numbers(text).isEmpty
    }

    private static func numbers(_ text: String) -> [Int] {
        let parts = text.split(separator: ".")
        let values = parts.compactMap { Int($0) }
        return values.count == parts.count ? values : []
    }
}
