import EscaliburCore
import EscaliburNetwork
import Foundation

/// A tela de versao desatualizada do Android (`ReleaseWatch.checkAndroid`, pedido do dono, 07/11/2026). O Kotlin manda a
/// versao, o build e o SDK do aparelho; volta o que a tela mostra. O piso (a emissao da lista mais nova ja vista) fica aqui,
/// num arquivo da pasta sem backup: a lista que vai dentro do app tambem conta, e uma lista mais antiga servida de novo pelo
/// site nao empurra para atualizar nem traz de volta uma obrigacao que o dono tirou.
enum Atualizacao {
    struct Resposta: Encodable {
        /// "em-dia", "desatualizada", "obrigatoria", "sem-resposta" ou "antiga".
        let estado: String
        let versao: String?
    }

    static let app = "app.escalibur.wallet"

    static func conferir(versao: String, build: Int, sdk: Int?) async -> Resposta {
        let agora = Date()
        let (veredito, emitida) = await ReleaseWatch.checkAndroid(installedVersion: versao, installedBuild: build, sdk: sdk,
                                                                  issuedFloor: piso(), now: agora)
        // O piso so sobe ate um dia a frente deste relogio, como no iPhone.
        if let emitida, emitida <= agora.addingTimeInterval(86_400), piso().map({ emitida > $0 }) ?? true { guardarPiso(emitida) }
        switch veredito {
        case .confirmed(let nova): return Resposta(estado: "desatualizada", versao: nova)
        case .required(let nova): return Resposta(estado: "obrigatoria", versao: nova)
        case .upToDate: return Resposta(estado: "em-dia", versao: nil)
        case .stale: return Resposta(estado: "antiga", versao: nil)
        case .unknown, .unconfirmed, .tampered: return Resposta(estado: "sem-resposta", versao: nil)
        }
    }

    private static var arquivoDoPiso: URL? { MetadataStore.directory?.appendingPathComponent("versoes-piso.txt") }

    /// A emissao da lista mais nova ja vista: a guardada, ou a da lista que vai dentro do app.
    static func piso() -> Date? {
        let guardado = arquivoDoPiso.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { ISO8601DateFormatter().date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return [guardado, daLista].compactMap { $0 }.max()
    }

    private static let daLista: Date? = {
        guard let pasta = CoreResources.directory,
              let dados = try? Data(contentsOf: URL(fileURLWithPath: pasta).appendingPathComponent("Versoes/versoes.json")) else { return nil }
        return (try? ReleaseManifest.verified(dados, app: app)).flatMap(ReleaseWatch.issued)
    }()

    private static func guardarPiso(_ data: Date) {
        guard let arquivo = arquivoDoPiso else { return }
        try? MetadataStore.gravarDuravel(Data(ISO8601DateFormatter().string(from: data).utf8), em: arquivo)
    }
}
