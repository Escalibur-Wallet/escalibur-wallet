import XCTest

/// Esqueci o PIN: a explicacao em passos e o alerta do proprio iPhone antes de apagar.
final class ForgotPINTests: XCTestCase {
    var shots: String? { ProcessInfo.processInfo.environment["ESCALIBUR_FOTOS"] }

    func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let shots { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png")) }
    }

    func testForgotPINExplainsAndAsksBeforeErasing() {
        let setup = XCUIApplication()
        setup.launchArguments = ["-reset", "-demo"]
        setup.launch()
        XCTAssertTrue(setup.staticTexts["Carteira principal"].waitForExistence(timeout: 30))
        setup.terminate()

        // Sem -demo o app abre trancado, pedindo o PIN.
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let forgot = app.buttons["Esqueci o PIN"]
        XCTAssertTrue(forgot.waitForExistence(timeout: 15))
        forgot.tap()
        XCTAssertTrue(app.staticTexts["Não existe redefinir o PIN"].waitForExistence(timeout: 5))
        shot("p1-esqueci", app)

        // Desde 27/10/2026, apagar pela tela de bloqueio so 24 horas depois do pedido: o botao de apagar nao existe na hora,
        // so o pedido, que conta o prazo e pode ser cancelado (quem pega o iPhone destravado nao apaga na hora).
        XCTAssertFalse(app.buttons["Apagar as carteiras deste iPhone"].exists, "apagar sem PIN nao pode estar disponivel na hora")
        let request = app.buttons["Pedir para apagar em 24 horas"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        request.tap()
        let cancelRequest = app.buttons["Cancelar o pedido"]
        XCTAssertTrue(cancelRequest.waitForExistence(timeout: 5), "o pedido conta o prazo e pode ser cancelado")
        XCTAssertFalse(app.buttons["Apagar as carteiras deste iPhone"].exists, "o prazo de 24 horas ainda corre")
        shot("p2-pedido", app)
        cancelRequest.tap()
        XCTAssertTrue(request.waitForExistence(timeout: 5), "cancelar volta ao pedido, sem apagar nada")
    }
}
