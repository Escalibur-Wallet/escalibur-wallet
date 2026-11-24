import XCTest

/// Os textos legais abrem do proprio app, a partir das boas-vindas.
final class LegalTests: XCTestCase {
    var shots: String? { ProcessInfo.processInfo.environment["ESCALIBUR_FOTOS"] }

    func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let shots { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png")) }
    }

    func testPrivacyFromWelcome() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset"]
        app.launch()
        let link = app.links["Política de privacidade"]
        XCTAssertTrue(link.waitForExistence(timeout: 15))
        link.tap()
        XCTAssertTrue(app.staticTexts["Com quem o app fala"].waitForExistence(timeout: 5))
        shot("l1-privacidade", app)
        app.buttons["Fechar"].tap()
        app.links["Termos de uso"].tap()
        XCTAssertTrue(app.staticTexts["A sua responsabilidade"].waitForExistence(timeout: 5))
        shot("l2-termos", app)
    }

    /// "Auditar o código" abre a auditoria do site dentro do app, no navegador da Apple (pedido
    /// do dono, 18/10/2026), e nao no Safari: o app continua na frente.
    func testAuditOpensInsideTheApp() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela", "ajustes"]
        app.launch()
        let about = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Taxas, código auditável'")).firstMatch
        XCTAssertTrue(about.waitForExistence(timeout: 30))
        about.tap()
        let audit = app.buttons["sobre-auditar"]
        XCTAssertTrue(audit.waitForExistence(timeout: 10))
        audit.tap()
        sleep(4)
        shot("l2-auditoria", app)
        XCTAssertEqual(app.state, .runningForeground, "o app saiu da frente: abriu no Safari")
        XCTAssertFalse(audit.isHittable, "o navegador nao cobriu a tela")
    }
}
