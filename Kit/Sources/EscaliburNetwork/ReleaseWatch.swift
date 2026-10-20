import CryptoKit
import EscaliburCore
import Foundation

/// O alarme de atualizacao nao confirmada (docs/seguranca.md, "Versao autorizada"): a versao
/// instalada pergunta a App Store qual e a mais nova e confere se ela esta na lista assinada
/// pela Escalibur. Uma versao nova fora da lista (conta da App Store invadida, build enviado
/// por terceiro) vira aviso, antes de o dono abrir a versao nova.
///
/// O limite e o do proprio aparelho: quem ja abriu a versao nova roda o codigo dela, e uma
/// troca do binario pela Apple sem mudar o numero da versao nao aparece aqui. Isso so a
/// comparacao do executavel com o build atestado mostra (docs/release.md).
public enum ReleaseWatch {
    static let manifestURL = URL(string: "https://escalibur-wallet.github.io/versoes.json")!  // swiftlint:disable:this force_unwrapping

    static func lookupURL(bundleID: String, country: String) -> URL? {
        var parts = URLComponents(string: "https://itunes.apple.com/lookup")
        parts?.queryItems = [URLQueryItem(name: "bundleId", value: bundleID), URLQueryItem(name: "country", value: country.lowercased())]
        return parts?.url
    }

    public enum Verdict: Equatable, Sendable {
        /// Nada mais novo na loja (ou o app ainda nao esta nela).
        case upToDate
        /// A versao nova esta na lista assinada.
        case confirmed(String)
        /// A versao nova nao esta na lista assinada, ou a lista sumiu do site.
        case unconfirmed(String)
        /// A lista existe, mas as assinaturas nao conferem: alguem mexeu nela.
        case tampered(String)
        /// Sem resposta agora (sem internet, loja ou site fora do ar): tenta de novo depois.
        case unknown
    }

    private struct Lookup: Decodable {
        struct Result: Decodable { let version: String }
        let resultCount: Int
        let results: [Result]
    }

    public static func check(
        installed: String, bundleID: String, country: String, client: HTTPClient = .shared,
        keys: [String: P256.Signing.PublicKey] = ReleaseKeys.trusted, threshold: Int = ReleaseKeys.threshold
    ) async -> Verdict {
        guard let url = lookupURL(bundleID: bundleID, country: country),
              let lookup = try? await client.getJSON(Lookup.self, from: url) else { return .unknown }
        guard let store = lookup.results.first?.version, ReleaseManifest.isNewer(store, than: installed) else { return .upToDate }
        let data: Data
        do {
            data = try await client.get(manifestURL)
        } catch HTTPClient.Failure.status(404) {
            // A lista some do site junto com uma versao nova: e o que quem invadiu faria.
            return .unconfirmed(store)
        } catch {
            return .unknown
        }
        guard let manifest = try? ReleaseManifest.verified(data, app: bundleID, keys: keys, threshold: threshold) else { return .tampered(store) }
        return manifest.authorizes(version: store) ? .confirmed(store) : .unconfirmed(store)
    }
}
