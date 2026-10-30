import XCTest

/// O Safe Keyboard em todo campo (pedido do dono, 17/10/2026): ligado, a busca de token e o
/// valor da troca abrem o teclado do app, nao o do iPhone, e o que se digita chega no campo.
final class SafeKeyboardTests: XCTestCase {
    var shots: String? { ProcessInfo.processInfo.environment["ESCALIBUR_FOTOS"] }

    override func setUp() {
        continueAfterFailure = false
    }

    func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let shots { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png")) }
    }

    func testEveryFieldOpensTheSafeKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela", "trocar", "-teclado-proprio"]
        app.launch()

        // O valor: so os algarismos e a virgula, no teclado do app.
        let amount = app.textFields.firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 30))
        amount.tap()
        XCTAssertTrue(app.buttons["safe-1"].waitForExistence(timeout: 5), "o valor nao abriu o Safe Keyboard")
        XCTAssertEqual(app.keyboards.count, 0, "o valor abriu o teclado do iPhone")
        XCTAssertTrue(app.buttons["safe-decimal"].exists)
        app.buttons["safe-1"].tap()
        app.buttons["safe-decimal"].tap()
        app.buttons["safe-5"].tap()
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == '1,5' OR value == '1.5'")).firstMatch.waitForExistence(timeout: 3),
                      "o que foi digitado nao chegou no campo")
        shot("k1-valor", app)
        let done = app.buttons["Pronto"]
        if done.exists { done.tap() }

        // A busca de token: letras, no teclado do app.
        app.buttons["escolher-token-Você recebe"].tap()
        let search = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Buscar por nome'")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.buttons["safe-q"].waitForExistence(timeout: 5), "a busca nao abriu o Safe Keyboard")
        XCTAssertEqual(app.keyboards.count, 0, "a busca abriu o teclado do iPhone")
        for letter in ["u", "s", "d"] { app.buttons["safe-\(letter)"].tap() }
        XCTAssertEqual(search.value as? String, "usd")
        shot("k2-busca", app)
        // Maiuscula vale para uma letra so.
        app.buttons["safe-maiuscula"].tap()
        app.buttons["safe-c"].tap()
        app.buttons["safe-c"].tap()
        XCTAssertEqual(search.value as? String, "usdCc")
        app.buttons["safe-apagar"].tap()
        app.buttons["safe-apagar"].tap()
        XCTAssertEqual(search.value as? String, "usd")

        // O globo devolve o do iPhone naquele campo.
        app.buttons["safe-sistema"].tap()
        let until = Date().addingTimeInterval(5)
        while Date() < until, app.keyboards.count == 0 { usleep(200_000) }
        XCTAssertGreaterThan(app.keyboards.count, 0, "o globo nao trouxe o teclado do iPhone")
    }

    /// O campo de senha (a passphrase antes de mover saldo) escreve no buffer seguro pelo Safe
    /// Keyboard: o "Continuar" so acende com o que foi digitado nele.
    func testPassphraseFieldTypesThroughTheSafeKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela", "passphrase-envio", "-teclado-proprio"]
        app.launch()
        let key = app.buttons["safe-a"]
        XCTAssertTrue(key.waitForExistence(timeout: 30), "a passphrase nao abriu o Safe Keyboard")
        XCTAssertEqual(app.keyboards.count, 0, "a passphrase abriu o teclado do iPhone")
        let next = app.buttons["passphrase-envio-continuar"]
        XCTAssertFalse(next.isEnabled)
        key.tap()
        app.buttons["safe-acentos"].tap()
        app.buttons["safe-é"].tap()
        XCTAssertTrue(next.isEnabled, "o que foi digitado no Safe Keyboard nao chegou no buffer da senha")
        shot("k3-passphrase", app)
    }
}
