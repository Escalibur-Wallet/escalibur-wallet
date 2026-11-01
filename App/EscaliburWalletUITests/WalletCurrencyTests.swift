import XCTest

/// A unidade do saldo (pedido do dono, 18/10/2026): o dolar primeiro, o real depois, e trocar
/// a moeda converte o que esta na tela, sem ler a carteira de novo.
final class WalletCurrencyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDollarFirstAndSwitchWithoutReloading() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo"]
        app.launch()
        let dollar = app.buttons["Dólar"]
        let real = app.buttons["Real"]
        XCTAssertTrue(dollar.waitForExistence(timeout: 60), "a unidade do saldo nao apareceu")
        XCTAssertTrue(real.exists)
        XCTAssertLessThan(dollar.frame.minX, real.frame.minX, "o dolar deveria vir antes do real")

        // A primeira leitura da carteira termina.
        let loading = app.descendants(matching: .any)["ativos-carregando"]
        let until = Date().addingTimeInterval(90)
        while Date() < until, loading.exists { usleep(500_000) }
        XCTAssertFalse(loading.exists, "a carteira nao terminou de ler")

        dollar.tap()
        // O total ja em dolar, e a carteira nao volta a carregar.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'US$'")).firstMatch.waitForExistence(timeout: 3),
                      "o total nao mudou para dolar na hora")
        let watch = Date().addingTimeInterval(4)
        while Date() < watch {
            XCTAssertFalse(loading.exists, "trocar a moeda leu a carteira inteira de novo")
            usleep(250_000)
        }
        real.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'R$'")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(loading.exists)
    }
}
