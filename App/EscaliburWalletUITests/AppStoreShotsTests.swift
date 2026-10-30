import XCTest

/// As capturas da pagina da App Store. So roda com `ESCALIBUR_LOJA=1`: abre cada tela da
/// carteira de demonstracao, espera os dados e fotografa. `ESCALIBUR_LOJA_IDIOMA` escolhe
/// `en-US` (o padrao, o idioma principal da loja) ou `pt-BR`. Os nomes batem com
/// `tools/loja/legendas.json`, que poe cada captura no aparelho com o titulo.
final class AppStoreShotsTests: XCTestCase {
    var shots: String? { ProcessInfo.processInfo.environment["ESCALIBUR_FOTOS"] }
    var language: [String] {
        ProcessInfo.processInfo.environment["ESCALIBUR_LOJA_IDIOMA"] == "pt-BR"
            ? ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
            : ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ESCALIBUR_LOJA"] == "1", "so para as capturas da loja")
    }

    func open(_ screen: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo"] + language + (screen.map { ["-tela", $0] } ?? [])
        app.launch()
        return app
    }

    func save(_ name: String, _ app: XCUIApplication) {
        let image = app.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let shots { try? image.pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png")) }
    }

    func testStoreScreenshots() {
        var app = open(nil)
        XCTAssertTrue(app.buttons["acao-receber"].waitForExistence(timeout: 40))
        sleep(14)
        save("1-carteira", app)
        app.terminate()

        for (name, screen, wait) in [
            // A revisao com a placa de enderecos e contratos, e a troca de XRP que a carteira
            // de teste consegue fazer (as contas dela na Tron e na Solana foram mexidas por quem
            // conhece a frase, e o app recusa montar).
            ("2-revisao", "revisao", 10),
            ("3-trocar", "trocar-xrp", 18),
            ("4-receber", "receber-btc", 16),
            ("5-mercado", "mercado", 16),
            ("6-moeda", "moeda", 16),
            ("7-envelope", "lacrar-parado", 12),
        ] as [(String, String, UInt32)] {
            app = open(screen)
            // A placa aberta: os enderecos e contratos que o app confere antes de assinar.
            if screen == "revisao", app.buttons["revisao-enderecos"].waitForExistence(timeout: 30) {
                app.buttons["revisao-enderecos"].tap()
            }
            sleep(wait)
            save(name, app)
            app.terminate()
        }
    }
}
