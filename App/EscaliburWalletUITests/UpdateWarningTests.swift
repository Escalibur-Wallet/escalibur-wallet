import XCTest

/// A trava da versao nao confirmada (docs/seguranca.md, "Versao autorizada"): com uma versao
/// da App Store fora da lista assinada, o app inteiro fica atras da tela de alerta, e o
/// deslizar "Usar em emergência" entra na carteira.
final class UpdateWarningTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testUnconfirmedUpdateLocksTheApp() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-alarme-versao"]
        app.launch()
        let trava = app.descendants(matching: .any)["alarme-versao"].firstMatch
        XCTAssertTrue(trava.waitForExistence(timeout: 60), "a trava da versao nao confirmada nao apareceu")
        XCTAssertTrue(app.staticTexts["Detectamos uma tentativa de hack"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'a versão 1.0.1 apareceu na App Store'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'A equipe da Escalibur está investigando'")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Seus fundos estão seguros'")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'A versão possivelmente adulterada não chegou a rodar aqui'")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'este alerta some sozinho'")).firstMatch.exists)
        let foto = XCTAttachment(screenshot: app.screenshot())
        foto.name = "alarme-versao"
        foto.lifetime = .keepAlways
        add(foto)

        // Em emergencia, a trava sai e a carteira atende.
        let deslizar = app.descendants(matching: .any)["alarme-emergencia"].firstMatch
        let inicio = deslizar.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        inicio.press(forDuration: 0.1, thenDragTo: deslizar.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)))
        XCTAssertTrue(trava.waitForNonExistence(timeout: 5), "o deslizar nao tirou a trava")
        let carteira = app.tabBars.buttons["Carteira"]
        XCTAssertTrue(carteira.waitForExistence(timeout: 30))
        XCTAssertTrue(carteira.isHittable, "a carteira nao atende depois da emergencia")
    }

    func testSecondCover() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela-c"]
        app.launch()
        let capa = app.descendants(matching: .any)["alarme-versao"].firstMatch
        XCTAssertTrue(capa.waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1.0.1 (8)'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'tentou adulterar'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Se você já destravou'")).firstMatch.exists)
        let foto = XCTAttachment(screenshot: app.screenshot())
        foto.name = "capa-c"
        foto.lifetime = .keepAlways
        add(foto)
        // Sem deslizar: o rodape fica no lugar, e a carteira por baixo nao atende.
        XCTAssertTrue(app.descendants(matching: .any)["alarme-rodape"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["alarme-emergencia"].exists)
        let carteira = app.tabBars.buttons["Carteira"]
        XCTAssertFalse(carteira.exists && carteira.isHittable)
        // E a carteira tranca por baixo: a tela do PIN, sem as chaves na memoria.
        XCTAssertTrue(app.staticTexts["Digite o seu PIN"].waitForExistence(timeout: 15), "a carteira nao trancou")
        XCTAssertFalse(app.tabBars.buttons["Carteira"].exists)
    }
}
