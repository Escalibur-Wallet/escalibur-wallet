import CryptoKit
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

        enum CodingKeys: String, CodingKey { case version = "versao", builds, published = "publicada" }
    }

    public let app: String
    public let issuedAt: String
    public let versions: [Version]
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
        return ReleaseManifest(app: body.app, issuedAt: body.emitido, versions: body.versoes, signedBy: valid)
    }

    public func authorizes(version: String) -> Bool {
        versions.contains { $0.version == version }
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

    private static func numbers(_ text: String) -> [Int] {
        let parts = text.split(separator: ".")
        let values = parts.compactMap { Int($0) }
        return values.count == parts.count ? values : []
    }
}
