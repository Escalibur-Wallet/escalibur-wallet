#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
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
        /// A versao nova esta na lista assinada, e a lista obriga a instalada a atualizar: sem o "Vou atualizar depois".
        case required(String)
        /// A versao nova nao esta na lista assinada, ou a lista sumiu do site.
        case unconfirmed(String)
        /// A lista existe, mas as assinaturas nao conferem: alguem mexeu nela.
        case tampered(String)
        /// Sem resposta agora (sem internet, loja ou site fora do ar): tenta de novo depois.
        case unknown
        /// A loja e o site responderam, mas a lista e mais antiga que a ja vista (ou sem data legivel): so vale para o alarme,
        /// que ja foi conferido antes (a versao da loja esta nela). Fica o que se sabia, e a proxima conferencia espera o
        /// intervalo normal.
        case stale(String)
    }

    private struct Lookup: Decodable {
        struct Result: Decodable {
            let version: String
            let minimumOsVersion: String?
            let trackId: Int?
            let currentVersionReleaseDate: String?
        }
        let resultCount: Int
        let results: [Result]
    }

    /// A versao fica um dia na loja antes de a tela obrigatoria valer: a consulta da Apple mostra a versao nova antes de a
    /// App Store do aparelho oferecer a atualizacao (o Siren espera o mesmo dia).
    static let requiredDelay: TimeInterval = 24 * 3600

    /// A emissao da lista, no formato que `versoes.swift` grava. Aqui, e nao no nucleo: o nucleo nao ganha simbolo de fora.
    public static func issued(_ manifest: ReleaseManifest) -> Date? {
        ISO8601DateFormatter().date(from: manifest.issuedAt)
    }

    /// `issuedFloor`: a emissao da lista mais nova ja vista (a que vai dentro do app, ou uma conferencia anterior). Uma
    /// lista assinada mais antiga, servida de novo pelo site, so vale para o alarme (`.stale`): nao empurra para atualizar,
    /// nao traz de volta uma obrigacao que o dono tirou e nao tira o que a tela ja mostra. Volta tambem a emissao da lista
    /// conferida, para subir o piso.
    public static func check(
        installed: String, bundleID: String, country: String, systemVersion: String? = nil, appStoreID: Int? = nil,
        issuedFloor: Date? = nil, now: Date = Date(), client: HTTPClient = .shared,
        keys: [String: P256.Signing.PublicKey] = ReleaseKeys.trusted, threshold: Int = ReleaseKeys.threshold
    ) async -> (verdict: Verdict, issued: Date?) {
        guard let url = lookupURL(bundleID: bundleID, country: country),
              let lookup = try? await client.getJSON(Lookup.self, from: url) else { return (.unknown, nil) }
        guard let release = lookup.results.first, ReleaseManifest.isNewer(release.version, than: installed) else { return (.upToDate, nil) }
        let store = release.version
        let data: Data
        do {
            data = try await client.get(manifestURL)
        } catch HTTPClient.Failure.status(404) {
            // A lista some do site junto com uma versao nova: e o que quem invadiu faria.
            return (.unconfirmed(store), nil)
        } catch {
            return (.unknown, nil)
        }
        guard let manifest = try? ReleaseManifest.verified(data, app: bundleID, keys: keys, threshold: threshold) else { return (.tampered(store), nil) }
        guard manifest.authorizes(version: store) else { return (.unconfirmed(store), issued(manifest)) }
        guard let issued = issued(manifest), issuedFloor.map({ issued >= $0 }) ?? true else { return (.stale(store), nil) }
        // Na lista, mas ainda nao liberada: so passa na conferencia, sem tela, como antes das telas de atualizar.
        guard manifest.released(version: store) else { return (.upToDate, issued) }
        // Obrigatoria so quando a versao da loja tira a pessoa da tela: ela mesma fora da regra, instalavel neste aparelho
        // (sistema e minimo dele legiveis, e o sistema nao mais antigo), na loja ha um dia, e o app da consulta e o que o
        // "Atualizar agora" abre. Faltando qualquer um, fica a tela de deixar para depois.
        guard let mandatory = manifest.mandatory, mandatory.requires(installed), !mandatory.requires(store),
              let system = systemVersion, let minimum = release.minimumOsVersion,
              ReleaseManifest.isVersion(system), ReleaseManifest.isVersion(minimum), !ReleaseManifest.isNewer(minimum, than: system),
              let appStoreID, release.trackId == appStoreID,
              let date = release.currentVersionReleaseDate.flatMap({ ISO8601DateFormatter().date(from: $0) }),
              now.timeIntervalSince(date) >= requiredDelay else { return (.confirmed(store), issued) }
        return (.required(store), issued)
    }
}
