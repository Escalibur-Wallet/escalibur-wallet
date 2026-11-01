import SafariServices
import SwiftUI

/// O navegador da Apple dentro do app, so para as paginas do site da Escalibur (pedido do dono,
/// 18/10/2026: "Auditar o código" sem sair do app). O `SFSafariViewController` roda em outro
/// processo: o app nao le a pagina, nao injeta script e nao ve os cookies dele, e nada passa
/// pelo `HTTPClient`. Endereco fora do site nao abre aqui. O `verificar.sh` confere que este e
/// o unico arquivo com navegador, e que os outros tipos de navegador continuam fora do app.
struct SiteBrowser: UIViewControllerRepresentable {
    static let host = "escalibur-wallet.github.io"
    let url: URL
    let onDone: () -> Void

    /// So https e so o site da Escalibur, na org da Escalibur no GitHub (desde 19/10/2026): o
    /// host inteiro e dela. Antes, o site ficava numa conta pessoal que servia outros
    /// repositorios no mesmo host, e so o caminho da carteira abria (auditoria 6).
    static func allows(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == host && url.port == nil
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        let safe = Self.allows(url) ? url : URL(string: "https://\(Self.host)/")!  // swiftlint:disable:this force_unwrapping
        let browser = SFSafariViewController(url: safe, configuration: configuration)
        browser.preferredBarTintColor = UIColor(Palette.void)
        browser.preferredControlTintColor = UIColor(Palette.ink)
        browser.dismissButtonStyle = .close
        browser.delegate = context.coordinator
        return browser
    }

    func updateUIViewController(_ browser: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDone() }
    }
}
