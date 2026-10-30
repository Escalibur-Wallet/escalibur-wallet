import XCTest

/// O apagar no seletor de carteiras (pedido do dono, 30/10/2026): arrastar a linha para a
/// esquerda deixa o apagar aberto sem escolher a carteira, e o toque no apagar abre a tela de
/// remover.
final class WalletSwitcherSwipeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSwipeOpensDeleteWithoutSelectingAndDeleteIsTappable() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela", "carteiras"]
        app.launch()
        XCTAssertTrue(app.buttons["Adicionar carteira"].waitForExistence(timeout: 60), "o seletor de carteiras nao abriu")
        // A linha da folha, e nao o nome no alto da Carteira: so ela diz as palavras.
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'palavras'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "a carteira nao aparece no seletor")
        attach(app, "1-seletor")

        row.swipeLeft()
        let delete = app.buttons["Apagar"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "o apagar nao apareceu")
        // A folha continua aberta: o arrasto nao escolheu a carteira.
        XCTAssertTrue(row.exists, "o arrasto escolheu a carteira e fechou o seletor")
        attach(app, "2-apagar-aberto")

        delete.tap()
        XCTAssertTrue(app.descendants(matching: .any)["deslizar-para-remover"].waitForExistence(timeout: 5),
                      "o toque no apagar nao abriu a tela de remover")
        attach(app, "3-remover")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
