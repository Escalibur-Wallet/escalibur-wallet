import Foundation
import Testing
@testable import EscaliburCore

/// O medidor da senha do envelope, no modelo do zxcvbn: o que o atacante testa primeiro
/// (listas, repeticoes, sequencias, datas) custa pouco, e so o resto vai por forca bruta.
@Suite("Forca da senha do envelope")
struct PasswordStrengthTests {
    func secure(_ text: String) -> SecureBytes {
        let bytes = SecureBytes(capacity: max(text.utf8.count, 1))
        bytes.replaceAll(with: Array(text.utf8))
        return bytes
    }

    func bits(_ text: String) -> Double { PasswordStrength.bits(secure(text)) }

    @Test("Os buracos do medidor antigo (auditoria de 14/10/2026) agora dao fraco")
    func oldHoles() {
        // O antigo dava 66, 60, 63 e 72 bits a estas.
        #expect(bits("abandon abandon abandon abandon abandon abandon") < 20)
        #expect(bits("!!!!!!!!!!!!") < 12)
        #expect(bits("cavalo correto bateria grampo") < 50)
        #expect(bits("minha casa tem um gato") < 35)
    }

    @Test("Padroes comuns custam pouco")
    func patterns() {
        #expect(bits("123456") < 2)
        #expect(bits("qwerty123") < 12)
        #expect(bits("Bitcoin2024!") < 30)
        #expect(bits("Senha@24") < 30)
        #expect(bits("s3nh@forte") < 30)
        #expect(bits("joao1990") < 15)
        #expect(bits("01/02/1990") < 35)
        #expect(bits("correcthorsebatterystaple") < 55)
    }

    @Test("Os buracos achados na auditoria do envelope de 06/11/2026 agora dao fraco")
    func envelopeHoles() {
        // Palavra de outra lingua ou de outro alfabeto, fora das listas: o antigo contava letra a letra.
        for senha in ["Donaudampfschifffahrt", "Hochgeschwindigkeitszug", "Wszystkiego najlepszego", "otorrinolaringologista",
                      "Pneumoultramicroscopicossilicovulcanoconiotico", "一二三四五六七八九十"] {
            #expect(bits(senha) < 60, "\(senha)")
        }
        // Tres palavras comuns de uma lingua sem lista, e palavras separadas por digito (rodada 3).
        for senha in ["Schmetterling Kartoffel Regenschirm", "vlinder venster schaar", "Casa1Azul1Gato1Feliz1Mesa", "casa1azul1gato1feliz1mesa1sol"] {
            #expect(bits(senha) < 60, "\(senha)")
        }
        #expect(bits("oãçaroc") < 15)
        // Com letra trocada por digito, a palavra de fora das listas continua palavra (rodada 3).
        for senha in ["Kuehlschr4nk Gefri3rfach", "Schm3tterl1ng Kuehlschr4nk", "Eichh0ernchenW4ld", "Strassenb4hnHaltest3lle"] {
            #expect(bits(senha) < 60, "\(senha)")
        }
        // Um caractere que o NFKC expande numa frase comum: vale o menor das duas formas.
        #expect(PasswordStrength.verdict(secure("ﷺ")) == .tooShort)
        for senha in ["محمد ﷺ", "㌀ ㌁ ㌂ ㌃"] {
            if case .strong = PasswordStrength.verdict(secure(senha)) { Issue.record("\(senha) passou como forte") }
        }
        // Rodada 4: palavras curtas de outra lingua, a troca como regra e o separador de 2 a 4 caracteres repetido.
        for senha in ["tjern skjul brygg", "kutya szív kéz", "K4rt0ff3ls4l4t Schm3tt3rl1ng", "H0chg3schw1nd1gk31tszug Fl0ugh4f3n",
                      "Gato12Casa12Azul12Mesa12Sol", "gato#1casa#1azul#1mesa#1sol"] {
            if case .strong = PasswordStrength.verdict(secure(senha)) { Issue.record("\(senha) passou como forte") }
        }
        // Digitos de outras escritas, palavras de 4 e 5 letras e o separador de dois digitos (militar, rodada 4).
        for senha in ["١٢٣٤ ٥٦٧٨ ٩٠١٢ ٣٤٥٦", "१२३४ ५६७८ ९०१२ ३४५६", "١٢٣٤-٥٦٧٨-٩٠١٢-٣٤٥٦", "pferd kerze stuhl", "Stuhl-Zunge-Tisch",
                      "Mauer6Kalem6Gabel", "Pferd Kerze Kwiat", "Kuchen26Fenster26Apfelbaum", "Kuchen 26 Fenster 26 Apfelbaum",
                      "Kuchen#2Fenster#2Apfelbaum"] {
            if case .strong = PasswordStrength.verdict(secure(senha)) { Issue.record("\(senha) passou como forte") }
        }
        if case .digitsOnly = PasswordStrength.verdict(secure("١٢٣٤٥٦")) {} else { Issue.record("PIN em digitos arabes nao foi marcado") }
        #expect(PasswordStrength.isDigitsOnly(secure("١٢٣٤")))
        // O reuso pela forma da frase: palavra com acento e uma so, e a frase japonesa tambem conta.
        let espanhola = SecureBytes(capacity: 64)
        espanhola.replaceAll(with: Array("ábaco ácido".decomposedStringWithCanonicalMapping.utf8))
        #expect(!PasswordStrength.reusesPhrase(secure("a casa e a rua"), phrase: espanhola))
        let japonesa = SecureBytes(capacity: 128)
        japonesa.replaceAll(with: Array("あいこくしん あいさつ".decomposedStringWithCompatibilityMapping.utf8))
        #expect(PasswordStrength.reusesPhrase(secure("あいこくしん あいさつ ねこ"), phrase: japonesa))
        // A linha do teclado com Shift (rodada 5).
        for senha in ["!@#$%^&*()_+", "Senha!@#$%^&*()_+", "!qaz@wsx#edc$rfv%tgb^yhn", "Senha-/:;()$&@\"", "Bitcoin-/:;()$&@\"",
                      "Senha@#$_&-+()/", "@#$_&-+()/*\"':;!?", "+_)(*&^%$#@!", "1!2@3#4$5%6^7&8*9(0)", "Bitcoin1!2@3#4$5%6^",
                      "qwertyuiop[]\\asdfghjkl;'zxcvbnm,./"] {
            if case .strong = PasswordStrength.verdict(secure(senha)) { Issue.record("\(senha) passou como forte") }
        }
        // O corte em separador fora do ASCII continua (rodada 5).
        let inglesa = SecureBytes(capacity: 64)
        inglesa.replaceAll(with: Array("abandon ability able about".utf8))
        for senha in ["abandon\u{2014}ability casa", "abandon\u{00B7}ability", "Abandon\u{2013}Ability 2024", "abandon\u{1F525}ability"] {
            #expect(PasswordStrength.reusesPhrase(secure(senha), phrase: inglesa), "\(senha)")
        }
        let coreana = SecureBytes(capacity: 64)
        coreana.replaceAll(with: Array("가격 가끔".decomposedStringWithCompatibilityMapping.utf8))
        #expect(PasswordStrength.reusesPhrase(secure("가격·가끔"), phrase: coreana))
        // Palavras da frase em largura cheia continuam reuso da frase.
        let frase = SecureBytes(capacity: 64)
        frase.replaceAll(with: Array("abandon ability able about above absent".utf8))
        #expect(PasswordStrength.reusesPhrase(secure("ａｂａｎｄｏｎ ａｂｉｌｉｔｙ casa"), phrase: frase))
        // O separador repetido e a frase de tras para frente.
        for senha in ["casa-azul-gato-feliz-mesa", "Casa_Azul_Gato_Feliz_Mesa", "casa#azul#gato#feliz#mesa", "ue oma ahnim ailimaf"] {
            #expect(bits(senha) < 60, "\(senha)")
        }
        // Em largura cheia, a senha que vai ao Argon2 e "password12345678".
        if case .strong = PasswordStrength.verdict(secure("ｐａｓｓｗｏｒｄ１２３４５６７８")) { Issue.record("largura cheia passou como forte") }
        // O que era forte continua forte.
        #expect(PasswordStrength.verdict(secure("xK3!pQ9#mZ2&wR7@")) == .strong)
        #expect(PasswordStrength.verdict(secure("crane violin orbit maple harbor tunnel")) == .strong)
    }

    @Test("Seis palavras sorteadas e caracteres aleatorios longos passam; cinco palavras nao")
    func verdicts() {
        #expect(PasswordStrength.verdict(secure("crane violin orbit maple harbor tunnel")) == .strong)
        #expect(bits("Crane Violin Orbit Maple Harbor Tunnel") > bits("crane violin orbit maple harbor tunnel"))
        #expect(PasswordStrength.verdict(secure("k7#Qp!2vZr@9mW")) == .strong)
        if case .weak = PasswordStrength.verdict(secure("crane violin orbit maple harbor")) {} else { Issue.record("5 palavras passaram") }
        #expect(PasswordStrength.verdict(secure("abc")) == .tooShort)
        #expect(PasswordStrength.verdict(secure("")) == .tooShort)
        if case .digitsOnly = PasswordStrength.verdict(secure("4821")) {} else { Issue.record("PIN nao foi marcado") }
        #expect(PasswordStrength.suggestionBits() == 66)
    }

    @Test("Caracteres contados como escalares, nao bytes")
    func length() {
        #expect(PasswordStrength.scalarCount(secure("ação")) == 4)
        #expect(PasswordStrength.scalarCount(secure("abcd")) == 4)
        #expect(PasswordStrength.verdict(secure("açã")) == .tooShort)
    }

    /// A tela mede fora da thread principal e depois da ultima tecla; isto e so a guarda
    /// contra o medidor ficar ordens de grandeza mais lento.
    @Test("Rapido o bastante para a tela")
    func speed() {
        PasswordStrength.preload()
        let long = secure("Correct-Horse-Battery-Staple 1987! minha frase bem comprida e boba 42")
        let start = Date()
        for _ in 0..<5 { _ = PasswordStrength.bits(long) }
        #expect(Date().timeIntervalSince(start) / 5 < 1.0)
    }

    @Test("Sugestao: seis palavras distintas, nenhuma da frase da carteira, escritas direto no buffer")
    func suggestion() throws {
        let phrase = secure("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        let list = try WordlistStore.shared.wordlist(for: .english)
        for _ in 0..<50 {
            let indices = try PasswordStrength.suggestionIndices(avoiding: phrase)
            #expect(indices.count == 6 && Set(indices).count == 6)
            let words = indices.map { list.words[$0] }
            #expect(!words.contains("abandon") && !words.contains("about"))
            let buffer = SecureBytes(capacity: 128)
            try PasswordStrength.write(indices, into: buffer)
            #expect(buffer.withUnsafeBytes { String(decoding: $0, as: UTF8.self) } == words.joined(separator: " "))
        }
    }

    @Test("Reusar duas palavras da frase e recusado")
    func reuse() {
        let phrase = secure("legal winner thank year wave sausage worth useful legal winner thank yellow")
        #expect(PasswordStrength.reusesPhrase(secure("Legal-Winner 2024 casa"), phrase: phrase))
        #expect(!PasswordStrength.reusesPhrase(secure("legal crane violin"), phrase: phrase))
    }
}
