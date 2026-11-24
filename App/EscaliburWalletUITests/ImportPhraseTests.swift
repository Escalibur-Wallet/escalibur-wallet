import XCTest

/// Importar: a palavra e digitada na propria posicao, com as sugestoes da lista acima
/// do teclado, e o foco anda para a posicao seguinte sem tocar em nada.
final class ImportPhraseTests: XCTestCase {
    var shots: String? { ProcessInfo.processInfo.environment["ESCALIBUR_FOTOS"] }

    func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let shots { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png")) }
    }

    func focusedSlot(_ app: XCUIApplication, _ number: Int) -> Bool {
        let field = app.otherElements["palavra-\(number)"].textFields.firstMatch
        return field.waitForExistence(timeout: 3) && (field.value(forKey: "hasKeyboardFocus") as? Bool ?? false)
    }

    func testTypeInSlotWithSuggestions() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-tela", "adicionar"]
        app.launch()
        // A linha e um botao so, com o titulo e a descricao juntos no rotulo.
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Importar com a senha da carteira'")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 30))
        // A tela entra animada: o toque so vale depois que ela assenta.
        let settled = NSPredicate(format: "hittable == true")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: option)], timeout: 5)
        sleep(1)
        option.tap()

        // Antes de digitar, o aceite de responsabilidade. Com a carteira ainda
        // carregando atras, o primeiro toque as vezes chega antes da folha assentar.
        let accept = app.buttons["aceite-responsabilidade"]
        if !accept.waitForExistence(timeout: 8) { option.tap() }
        XCTAssertTrue(accept.waitForExistence(timeout: 10))
        accept.tap()
        app.tapWhenEnabled(app.buttons["Conferir o aparelho"])
        app.passDeviceCheck()

        let first = app.otherElements["palavra-1"]
        if !first.waitForExistence(timeout: 10) { shot("import-sem-palavra", app) }
        XCTAssertTrue(first.exists)
        first.tap()
        XCTAssertTrue(focusedSlot(app, 1), "tocar na posicao 1 nao abriu o teclado nela")
        app.typeText("aban")
        let suggestion = app.buttons["abandon"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "a sugestao nao apareceu acima do teclado")
        XCTAssertTrue(suggestion.isHittable)
        shot("i1-sugestao", app)
        suggestion.tap()
        XCTAssertTrue(focusedSlot(app, 2), "o foco nao passou para a posicao 2")

        // Espaco fecha a palavra e passa adiante, como no papel.
        for _ in 2...11 { app.typeText("abandon ") }
        XCTAssertTrue(focusedSlot(app, 12))
        app.typeText("about")
        app.typeText("\n")
        let importButton = app.buttons["Importar"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertTrue(importButton.isEnabled, "com as 12 palavras o Importar deveria liberar")
        shot("i2-preenchida", app)

        // Segurar uma posicao preenchida mostra a palavra e nao abre a edicao.
        app.otherElements["palavra-3"].press(forDuration: 0.8)
        XCTAssertFalse(focusedSlot(app, 3), "segurar nao deveria abrir a posicao para digitar")

        // Limpar, com o alerta do iPhone, esvazia as doze posicoes.
        app.buttons["limpar-palavras"].tap()
        let alert = app.alerts["Apagar as palavras digitadas?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Apagar"].tap()
        XCTAssertFalse(importButton.isEnabled, "depois de limpar, Importar volta a ficar desligado")
        XCTAssertFalse(app.buttons["limpar-palavras"].exists)
    }

    func type(pin: String, in app: XCUIApplication) {
        for digit in pin {
            let key = app.buttons.matching(identifier: "tecla-\(digit)").firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 10), "tecla \(digit)")
            key.tap()
        }
    }

    /// O caminho inteiro: digitar, conferir os enderecos, guardar com o PIN e cair na
    /// carteira nova. A carteira da demo aqui e sorteada (-vazia), para a frase publica
    /// de teste nao ser "ja importada".
    func testImportAllTheWayToSaved() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-demo", "-vazia", "-tela", "adicionar"]
        app.launch()
        // A linha e um botao so, com o titulo e a descricao juntos no rotulo.
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Importar com a senha da carteira'")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 30))
        // A tela entra animada: o toque so vale depois que ela assenta.
        let settled = NSPredicate(format: "hittable == true")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: option)], timeout: 5)
        sleep(1)
        option.tap()
        let accept = app.buttons["aceite-responsabilidade"]
        if !accept.waitForExistence(timeout: 8) { option.tap() }
        XCTAssertTrue(accept.waitForExistence(timeout: 10))
        accept.tap()
        app.tapWhenEnabled(app.buttons["Conferir o aparelho"])
        app.passDeviceCheck()
        let first = app.otherElements["palavra-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        // Na primeira carteira do app, o teclado da Escalibur ja vem (17/10/2026); com
        // carteira, o do iPhone.
        if app.buttons["teclado-a"].waitForExistence(timeout: 4) {
            for _ in 1...11 { app.typeOnOwnKeyboard("abandon") }
            app.typeOnOwnKeyboard("about")
        } else {
            for _ in 1...11 { app.typeText("abandon ") }
            app.typeText("about")
            app.typeText("\n")
        }
        app.tapWhenEnabled(app.buttons["Importar"])
        let failure = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Não foi possível importar'")).firstMatch
        let review = app.staticTexts["Confira antes de guardar"]
        XCTAssertTrue(review.waitForExistence(timeout: 15), failure.exists ? failure.label : "a conferencia nao apareceu")
        shot("i3-conferir", app)
        // Guardar so com o aceite de que quem deu as palavras controla a carteira (C7-05).
        XCTAssertFalse(app.buttons["Guardar esta carteira"].isEnabled)
        // O aceite fica no rodape, junto do Guardar. (A conta da Tron da frase publica de
        // teste tem outra chave no controle: com rede, o aviso vermelho aparece acima.)
        let consent = app.buttons["importar-aceite"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        consent.tap()
        XCTAssertTrue(consent.isSelected)
        shot("i3b-aceite", app)
        app.tapWhenEnabled(app.buttons["Guardar esta carteira"])
        type(pin: "111111", in: app)
        let saved = app.staticTexts["Carteira 2"]
        XCTAssertTrue(saved.waitForExistence(timeout: 30), failure.exists ? failure.label : "a carteira importada nao virou a carteira em uso")
        shot("i4-guardada", app)
    }

    /// Com o interruptor da passphrase, a tela das palavras nao abre campo nenhum: depois do PIN vem a tela
    /// "Digite a passphrase", e so a carteira com passphrase e guardada (pedido do dono, 08/11/2026).
    func testImportWithPassphraseAfterPIN() {
        importWithPassphrase(["-reset", "-demo", "-vazia", "-tela", "adicionar"], opens: "Carteira 2 com passphrase", prefix: "ip",
                             words: "Carteira 2", wordsStay: false)
    }

    /// As mesmas palavras de uma carteira que ja esta aqui (a da demo e a frase publica de teste): em vez
    /// de "ja esta neste app", a passphrase abre sobre a carteira que ja existe.
    func testImportKnownWordsWithPassphrase() {
        importWithPassphrase(["-reset", "-demo", "-tela", "adicionar"], opens: "Carteira principal com passphrase", prefix: "ik",
                             words: "Carteira principal", wordsStay: true)
    }

    /// A primeira carteira do aparelho, importada com passphrase: a carteira com passphrase e a unica, e "Tentar outra
    /// passphrase" ainda funciona, de volta a tela da passphrase (revisao de seguranca, 08/11/2026).
    func testFirstWalletRetryPassphrase() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["Começar"].waitForExistence(timeout: 15))
        app.buttons["Começar"].tap()
        XCTAssertTrue(app.buttons["tour-pular"].waitForExistence(timeout: 10))
        app.buttons["tour-pular"].tap()
        XCTAssertTrue(app.staticTexts["Escolha um PIN"].waitForExistence(timeout: 5))
        type(pin: "111111", in: app)
        XCTAssertTrue(app.staticTexts["Repita o PIN"].waitForExistence(timeout: 5))
        type(pin: "111111", in: app)
        if app.buttons["Agora não"].waitForExistence(timeout: 8) { app.buttons["Agora não"].tap() }
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Importar com a senha da carteira'")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 15))
        option.tap()
        let accept = app.buttons["aceite-responsabilidade"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10))
        accept.tap()
        app.tapWhenEnabled(app.buttons["Conferir o aparelho"])
        app.passDeviceCheck()
        let first = app.otherElements["palavra-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        if app.buttons["teclado-a"].waitForExistence(timeout: 4) {
            for _ in 1...11 { app.typeOnOwnKeyboard("abandon") }
            app.typeOnOwnKeyboard("about")
        } else {
            for _ in 1...11 { app.typeText("abandon ") }
            app.typeText("about")
            app.typeText("\n")
        }
        let toggle = app.switches["Esta carteira usa passphrase"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let inner = toggle.switches.firstMatch
        for _ in 0..<3 where toggle.value as? String != "1" {
            (inner.exists ? inner : toggle).tap()
            sleep(1)
        }
        app.tapWhenEnabled(app.buttons["Importar"])
        XCTAssertTrue(app.staticTexts["Confira antes de guardar"].waitForExistence(timeout: 15))
        app.buttons["importar-aceite"].tap()
        app.tapWhenEnabled(app.buttons["Continuar"])
        type(pin: "111111", in: app)
        XCTAssertTrue(app.staticTexts["Digite a passphrase"].waitForExistence(timeout: 30))
        let fields = app.secureTextFields
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText("lanterna")
        let second = fields.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        var waited = XCTWaiter.Result.timedOut
        for _ in 0..<2 where waited != .completed {
            second.tap()
            waited = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: second)], timeout: 3)
        }
        second.typeText("lanterna")
        app.buttons["Abrir carteira"].tap()
        type(pin: "111111", in: app)
        // Sem movimento (ou sem resposta), "Tentar outra passphrase" aparece; com a unica carteira, ela ainda sai.
        let retry = app.buttons["Tentar outra passphrase"]
        XCTAssertTrue(retry.waitForExistence(timeout: 60), "a busca de movimento deveria oferecer outra passphrase")
        shot("if1-busca", app)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Digite a passphrase"].waitForExistence(timeout: 15), "tentar outra deveria voltar a tela da passphrase")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Não foi possível apagar'")).firstMatch.exists)
        shot("if2-de-volta", app)
    }

    /// `words`: a carteira das palavras; `wordsStay`: ela ja estava aqui antes e fica. Com o interruptor, a importacao nunca
    /// guarda a carteira das palavras, so a com passphrase (revisao de seguranca, 08/11/2026).
    private func importWithPassphrase(_ arguments: [String], opens name: String, prefix: String, words: String, wordsStay: Bool) {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Importar com a senha da carteira'")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 30))
        let settled = NSPredicate(format: "hittable == true")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: option)], timeout: 5)
        sleep(1)
        option.tap()
        let accept = app.buttons["aceite-responsabilidade"]
        if !accept.waitForExistence(timeout: 8) { option.tap() }
        XCTAssertTrue(accept.waitForExistence(timeout: 10))
        accept.tap()
        app.tapWhenEnabled(app.buttons["Conferir o aparelho"])
        app.passDeviceCheck()
        let first = app.otherElements["palavra-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        if app.buttons["teclado-a"].waitForExistence(timeout: 4) {
            for _ in 1...11 { app.typeOnOwnKeyboard("abandon") }
            app.typeOnOwnKeyboard("about")
        } else {
            for _ in 1...11 { app.typeText("abandon ") }
            app.typeText("about")
            app.typeText("\n")
        }
        let toggle = app.switches["Esta carteira usa passphrase"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        // O toque as vezes chega enquanto o teclado ainda fecha e a tela se move: de novo, como faria a pessoa.
        let inner = toggle.switches.firstMatch
        for _ in 0..<3 where toggle.value as? String != "1" {
            (inner.exists ? inner : toggle).tap()
            sleep(1)
        }
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(app.staticTexts["Depois de conferir os endereços, você digita a passphrase numa tela só dela."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.secureTextFields.count, 0, "o interruptor nao deveria abrir campo de passphrase junto das palavras")
        shot("\(prefix)1-interruptor", app)

        app.tapWhenEnabled(app.buttons["Importar"])
        let failure = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Não foi possível' OR label BEGINSWITH 'Esta carteira já está'")).firstMatch
        XCTAssertTrue(app.staticTexts["Confira antes de guardar"].waitForExistence(timeout: 15), failure.exists ? failure.label : "a conferencia nao apareceu")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Estes são os endereços das palavras sozinhas'")).firstMatch.exists)
        shot("\(prefix)2-conferir", app)
        let consent = app.buttons["importar-aceite"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        consent.tap()
        // Nada e guardado aqui: o botao segue, e o PIN so confirma que e o dono.
        app.tapWhenEnabled(app.buttons["Continuar"])
        type(pin: "111111", in: app)

        // Depois do PIN, a tela da passphrase, com o voltar para a conferencia.
        XCTAssertTrue(app.staticTexts["Digite a passphrase"].waitForExistence(timeout: 30), failure.exists ? failure.label : "a tela da passphrase nao veio depois do PIN")
        XCTAssertTrue(app.buttons["Voltar"].exists)
        shot("\(prefix)3-digitar", app)
        // O voltar leva a conferencia com as palavras ainda na memoria, e o Continuar volta a tela da passphrase.
        app.buttons["Voltar"].tap()
        XCTAssertTrue(app.staticTexts["Confira antes de guardar"].waitForExistence(timeout: 10), "o voltar deveria levar a conferencia")
        // O aceite e marcado de novo a cada vez que a conferencia aparece.
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        if !consent.isSelected { consent.tap() }
        app.tapWhenEnabled(app.buttons["Continuar"])
        type(pin: "111111", in: app)
        XCTAssertTrue(app.staticTexts["Digite a passphrase"].waitForExistence(timeout: 30), "a tela da passphrase deveria voltar")
        let fields = app.secureTextFields
        XCTAssertTrue(fields.element(boundBy: 0).waitForExistence(timeout: 5))
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText("lanterna")
        let second = fields.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        var waited = XCTWaiter.Result.timedOut
        for _ in 0..<2 where waited != .completed {
            second.tap()
            waited = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: second)], timeout: 3)
        }
        second.typeText("lanterna")
        app.buttons["Abrir carteira"].tap()
        type(pin: "111111", in: app)
        // A busca de movimento le a rede: com resposta, "Usar esta carteira"; ainda procurando, "Abrir sem esperar".
        let searching = app.staticTexts["Procurando movimento"]
        XCTAssertTrue(searching.waitForExistence(timeout: 30) || app.buttons["Usar esta carteira"].exists, "a busca de movimento nao veio depois do PIN")
        shot("\(prefix)4-busca", app)
        let useIt = app.buttons["Usar esta carteira"]
        let skip = app.buttons["Abrir sem esperar"]
        if useIt.waitForExistence(timeout: 20) { useIt.tap() } else if skip.exists { skip.tap() }
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: searching),
                                            XCTNSPredicateExpectation(predicate: gone, object: useIt)], timeout: 10), .completed,
                       "a busca de movimento deveria fechar")
        // Na demo, "-tela adicionar" abre a tela de adicionar por dois caminhos, e o segundo aparece
        // quando o primeiro fecha (acontece tambem sem passphrase): fechado ele, a Carteira.
        sleep(3)
        if app.staticTexts["Adicionar carteira"].exists { app.buttons["Fechar"].firstMatch.tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: app.staticTexts["Adicionar carteira"])], timeout: 10), .completed)
        XCTAssertFalse(searching.exists)
        let receive = app.buttons["acao-receber"]
        XCTAssertTrue(receive.waitForExistence(timeout: 15), "deveria cair na Carteira")
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15), failure.exists ? failure.label : "a carteira com passphrase nao virou a carteira em uso")
        shot("\(prefix)5-aberta", app)
        // Na lista de carteiras: a das palavras so fica se ja estava aqui.
        app.buttons["carteira-nome"].tap()
        let wordsRow = app.staticTexts[words]
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertEqual(wordsRow.exists, wordsStay, wordsStay ? "a carteira das palavras que ja estava aqui deveria ficar" : "a carteira das palavras desta importacao deveria sair")
        shot("\(prefix)6-lista", app)
    }
}
