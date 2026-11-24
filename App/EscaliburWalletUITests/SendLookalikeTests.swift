import XCTest

/// Envenenamento de endereco: um destino com as pontas do endereco da propria carteira
/// e o meio trocado pede os 6 caracteres do meio, nunca os do fim.
final class SendLookalikeTests: XCTestCase {
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

    func testMiddleSegmentChallenge() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela", "enviar-eth"]
        app.launch()
        // A carteira de teste na Ethereum e 0x9858EfFD...EcaEda94. O destino abaixo tem
        // as mesmas pontas e zeros no meio; em minusculas, sem checksum a conferir.
        XCTAssertTrue(app.staticTexts["Para"].waitForExistence(timeout: 30))
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        shot("s0-destino", app)
        field.tap()
        field.typeText("0x98580000000000000000000000000000ecaeda94")
        let check = app.textFields["conferir-trecho-endereco"]
        if !check.waitForExistence(timeout: 10) { shot("falha-parecido", app) }
        XCTAssertTrue(check.exists)
        shot("s1-parecido", app)
        let next = app.buttons["Continuar"]
        app.swipeUp()
        check.tap()
        // O fim e o que o atacante copiou: digita-lo nao pode liberar o envio.
        check.typeText("aeda94")
        next.tap()
        sleep(1)
        XCTAssertTrue(check.exists, "o fim copiado pelo atacante nao pode liberar")
        check.clearAndType("000000")
        shot("s2-conferido", app)
    }
}

/// Nome da NEAR digitado letra a letra, com "Conferir o endereco em todo envio" ligada: cada comeco ja e conta valida, e o
/// desafio nascia no segundo caractere. Ele nasce no Continuar, e o nome inteiro e conferido no toque (revisao de seguranca,
/// 09/11/2026).
final class SendNEARNameTests: XCTestCase {
    var shots: String? { ProcessInfo.processInfo.environment["ESCALIBUR_FOTOS"] }

    func shot(_ name: String, _ app: XCUIApplication) {
        guard let shots else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: shots).appendingPathComponent("near-\(name).png"))
    }

    func testNameChallengeStartsOnContinue() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela", "envio-conferir-near"]
        app.launch()
        if !app.staticTexts["Para"].waitForExistence(timeout: 60) { shot("falha-abrir", app) }
        XCTAssertTrue(app.staticTexts["Para"].exists)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        for letter in "alice-wallet.near" { field.typeText(String(letter)) }
        let check = app.textFields["conferir-meio-endereco"]
        XCTAssertFalse(check.waitForExistence(timeout: 2), "o desafio nao pode nascer na digitacao")
        shot("n0-digitado", app)
        let next = app.buttons["Continuar"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        // O historico da rede chega antes de o Continuar acender.
        let deadline = Date().addingTimeInterval(30)
        while !next.isEnabled, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        XCTAssertTrue(next.isEnabled)
        next.tap()
        XCTAssertTrue(check.waitForExistence(timeout: 10), "o Continuar faz o desafio nascer")
        shot("n1-desafio", app)
        // Um nome que e o comeco do certo acende o Continuar, mas nao passa: confere no toque.
        check.tap()
        check.typeText("alice-wallet.nea")
        next.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'O nome não confere'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(check.exists)
        shot("n2-nao-confere", app)
    }
}

extension XCUIElement {
    func clearAndType(_ text: String) {
        guard let current = value as? String else { return }
        tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeText(text)
    }
}

/// Transmissao sem resposta certa: a tela so oferece enviar os mesmos bytes de novo.
final class SendUnsureTests: XCTestCase {
    var shots: String? { ProcessInfo.processInfo.environment["ESCALIBUR_FOTOS"] }

    func testUnsureScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela", "envio-incerto"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Não deu para confirmar o envio"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Transmitir de novo"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        if let shots { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/s3-incerto.png")) }
    }
}

/// Tag opcional: quando a rede tem e o destino nao exige, o campo ja vem aberto, com o
/// nome que a exchange usa (pedido do dono de 14/10/2026).
final class SendOptionalTagTests: XCTestCase {
    var shots: String? { ProcessInfo.processInfo.environment["ESCALIBUR_FOTOS"] }

    func testOptionalTagField() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela", "enviar"]
        app.launch()
        // A folha de envio abre depois de a Carteira assentar; antes, o "XRP," da Carteira
        // e outro botao.
        XCTAssertTrue(app.staticTexts["Escolha o que enviar"].waitForExistence(timeout: 30))
        let xrp = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'XRP,'")).firstMatch
        XCTAssertTrue(xrp.waitForExistence(timeout: 40))
        xrp.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh")
        let tag = app.textFields["tag-opcional"]
        XCTAssertTrue(tag.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Tag de destino (Destination Tag)"].exists)
        XCTAssertTrue(app.staticTexts["opcional"].exists)
        // Os avisos do endereco chegam logo depois da digitacao e empurram o campo: toca
        // ate o teclado ficar nele.
        for _ in 0..<4 where (tag.value(forKey: "hasKeyboardFocus") as? Bool) != true {
            tag.tap()
            sleep(1)
        }
        tag.typeText("0123")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        if let shots { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/s4-tag-opcional.png")) }
    }
}

/// Envio EVM: o endereco nao diz a rede, e no primeiro envio o dono confirma que quem
/// recebe aceita a rede escolhida; o endereco aparece com comeco e fim marcados.
final class SendNetworkConfirmationTests: XCTestCase {
    var shots: String? { ProcessInfo.processInfo.environment["ESCALIBUR_FOTOS"] }

    func testEVMFirstSendAsksForNetwork() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela", "enviar-eth"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Para"].waitForExistence(timeout: 30))
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
        XCTAssertTrue(app.staticTexts["Envio pela rede Ethereum"].waitForExistence(timeout: 10))
        let next = app.buttons["Continuar"]
        next.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Envio pela rede Ethereum"].exists, "seguiu sem confirmar a rede")
        if let shots { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/s5-rede.png")) }
        app.switches["confirmar-rede"].firstMatch.tap()
        sleep(1)
        if let shots { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/s6-rede-confirmada.png")) }
    }

    func testTronUSDTWithEVMAddressSaysWrongNetwork() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela", "enviar"]
        app.launch()
        let usdt = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'USDT, na Tron'")).firstMatch
        XCTAssertTrue(usdt.waitForExistence(timeout: 40))
        usdt.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
        let message = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Este é um endereço EVM'")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        if let shots { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/s7-rede-errada.png")) }
    }
}
