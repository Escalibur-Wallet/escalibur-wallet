import EscaliburCore
import Foundation
import Testing
@testable import EscaliburChains

@Suite("Chave privada colada no lugar do endereco")
struct PrivateKeyGuardTests {
    private func check(_ payload: [UInt8]) -> String { Base58.bitcoin.encodeCheck(payload) }
    private func rippleCheck(_ payload: [UInt8]) -> String { Base58.ripple.encode(payload + Array(Hash.sha256d(payload).prefix(4))) }
    private func bech(_ hrp: String, _ bytes: [UInt8]) -> String {
        Bech32.encode(hrp: hrp, data: Bech32.convertBits(bytes, from: 8, to: 5, pad: true)!, variant: .bech32)
    }
    /// Um par ed25519 de verdade: a semente e a publica dela.
    private func keyPair() throws -> [UInt8] {
        let seed = [UInt8](repeating: 7, count: 32)
        let secure = SecureBytes(capacity: 32)
        seed.withUnsafeBufferPointer { secure.append(contentsOf: $0) }
        return seed + (try Ed25519.publicKey(of: secure))
    }
    /// Oito blocos do Xaman: cinco algarismos ate 65535 e o digito valor x (2 x posicao + 1) mod 9.
    private var xaman: [String] {
        [12345, 54321, 600, 65535, 4242, 31337, 7, 20000].enumerated().map { position, value in
            let digits = String(value)
            return String(repeating: "0", count: 5 - digits.count) + digits + String(value * (position * 2 + 1) % 9)
        }
    }

    @Test("WIF, chave estendida, BIP-38, sementes da Stellar e da XRPL, Solana, Cardano e com o tipo escrito")
    func keys() throws {
        let key = [UInt8](repeating: 7, count: 32)
        // WIF do Bitcoin (o exemplo classico), sem e com compressao, e da Litecoin e da Dogecoin.
        #expect(PrivateKeyGuard.looksLikePrivateKey("5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"))
        #expect(PrivateKeyGuard.looksLikePrivateKey("KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617"))
        #expect(PrivateKeyGuard.looksLikePrivateKey(check([0xB0] + key + [0x01])))
        #expect(PrivateKeyGuard.looksLikePrivateKey(check([0x9E] + key + [0x01])))
        // BIP-32, vetor 1, a raiz privada; e uma versao qualquer (Yprv) pelo byte 45.
        #expect(PrivateKeyGuard.looksLikePrivateKey(
            "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi"))
        let yprv = [0x02, 0x95, 0xB0, 0x05] + [UInt8](repeating: 0, count: 41) + [0x00] + key
        #expect(PrivateKeyGuard.looksLikePrivateKey(check(yprv)))
        let xpub = [0x04, 0x88, 0xB2, 0x1E] + [UInt8](repeating: 0, count: 41) + [0x02] + key
        #expect(!PrivateKeyGuard.looksLikePrivateKey(check(xpub)))
        // BIP-38.
        #expect(PrivateKeyGuard.looksLikePrivateKey(check([0x01, 0x42, 0xC0] + [UInt8](repeating: 5, count: 36))))
        // Stellar "S"; XRPL "s" e "sEd".
        #expect(PrivateKeyGuard.looksLikePrivateKey(StellarKey.encode(version: PrivateKeyGuard.stellarSeedVersion, payload: key)))
        #expect(PrivateKeyGuard.looksLikePrivateKey(rippleCheck([0x21] + [UInt8](repeating: 9, count: 16))))
        #expect(PrivateKeyGuard.looksLikePrivateKey(rippleCheck([0x01, 0xE1, 0x4B] + [UInt8](repeating: 9, count: 16))))
        // Solana: base58 de 64 bytes, o vetor de numeros e os 128 hexadecimais.
        // O par de verdade (a semente e a publica dela); 64 bytes quaisquer nao sao chave.
        #expect(PrivateKeyGuard.looksLikePrivateKey(Base58.bitcoin.encode(try keyPair())))
        #expect(!PrivateKeyGuard.looksLikePrivateKey(Base58.bitcoin.encode([UInt8](repeating: 3, count: 64))))
        #expect(PrivateKeyGuard.looksLikePrivateKey("[" + Array(repeating: "12", count: 64).joined(separator: ",") + "]"))
        #expect(PrivateKeyGuard.looksLikePrivateKey(String(repeating: "ab", count: 64)))
        // Cardano, NEAR, Aptos e Sui.
        #expect(PrivateKeyGuard.looksLikePrivateKey(bech("ed25519e_sk", [UInt8](repeating: 4, count: 64))))
        #expect(PrivateKeyGuard.looksLikePrivateKey("ed25519:" + Base58.bitcoin.encode(try keyPair())))
        #expect(PrivateKeyGuard.looksLikePrivateKey("secp256k1:" + Base58.bitcoin.encode(key)))
        #expect(PrivateKeyGuard.looksLikePrivateKey("ed25519-priv-0x" + String(repeating: "1a", count: 32)))
        #expect(PrivateKeyGuard.looksLikePrivateKey(bech("suiprivkey", [0x00] + key)))
        // Os numeros secretos do Xaman, com o digito da conta (XLS-12).
        #expect(PrivateKeyGuard.looksLikePrivateKey(xaman.joined(separator: " ")))
    }

    @Test("A chave dentro de um texto: entre aspas, com rotulo, com esquema, partida em linhas")
    func keyInText() {
        let wif = "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"
        for text in ["\"\(wif)\"", "WIF: \(wif)", "bitcoin:\(wif)", "p2wpkh:\(wif)", "\(wif).", String(wif.prefix(26)) + "\n" + String(wif.dropFirst(26))] {
            #expect(PrivateKeyGuard.looksLikePrivateKey(text), "\(text)")
        }
    }

    @Test("Endereco nao e chave")
    func addresses() {
        for address in [
            "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2",
            "0x9858EfFD232B4033E47d90003D41EC34EcaEda94", "7cVfgArCheMR6Cs4t6vz5rfnqd56vZq4ndaBrY5xkxXy",
            "rPT1Sjq2YGrBMTttX4GZHjKu9dyfzbpAYe", "TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7", "alice.near",
            String(repeating: "a", count: 64), "0x" + String(repeating: "1", count: 62) + "ab",
            "GBRPYHIL2CI3FNQ4BXLFMNDLFJUNPU2HY3ZMFSHONUCEOASW7QC7OX2H",
            "EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N",
            "addr1q94zzrtl32tjp8j96auatnhxd2y35fnk6wuxqvqm9364vp9spdkjdsmyfhvfagjzh4uzp9zs6p5djw89jac2g0ujs2eqsuy7pu",
            "ed25519-priv-alice.near", "suiprivkey1xyz.near",
            "ed25519:" + Base58.bitcoin.encode([UInt8](repeating: 3, count: 32)),  // a chave publica da NEAR
        ] {
            #expect(!PrivateKeyGuard.looksLikePrivateKey(address), "\(address)")
        }
    }

    @Test("Texto livre: a frase, as seis palavras, a chave; a assinatura da Solana e o texto comprido passam")
    func freeText() throws {
        #expect(PrivateKeyGuard.containsSecret("minha frase: abandon ability able about above absent absorb abstract"))
        #expect(PrivateKeyGuard.containsSecret("nao consigo importar 5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"))
        #expect(!PrivateKeyGuard.containsSecret("pagamento do pedido 123"))
        // O chamado normal, de 12 palavras ou mais, sai (a regra das palavras soltas o recusava).
        #expect(!PrivateKeyGuard.containsSecret("Mandei USDT pela rede Tron para a Binance ontem e ainda não chegou na conta"))
        #expect(!PrivateKeyGuard.containsSecret("Enviei 10 USDT para a Binance pela rede Tron e até agora o valor não apareceu na minha conta."))
        // A frase em japones, separada por espaco.
        let japanese = try #require(WordLexicon.entries.first { $0.language == .japanese })
        #expect(PrivateKeyGuard.containsSecret(Array(repeating: japanese.word, count: 12).joined(separator: "\u{3000}")))
        // Assinatura: 64 bytes que nao sao a semente seguida da publica dela.
        let signature = [UInt8](repeating: 9, count: 63) + [0x05]
        #expect(!PrivateKeyGuard.containsSecret("tx " + Base58.bitcoin.encode(signature)))
        // O par de chaves com o ultimo byte da publica ate 0x10: passava pela regra da assinatura.
        var seed = [UInt8](repeating: 1, count: 32)
        var pair: [UInt8] = []
        for counter in 0...UInt8.max {
            seed[0] = counter
            let secure = SecureBytes(capacity: 32)
            seed.withUnsafeBufferPointer { secure.append(contentsOf: $0) }
            let publicKey = try Ed25519.publicKey(of: secure)
            if publicKey[31] <= 0x10 { pair = seed + publicKey; break }
        }
        try #require(pair.count == 64)
        #expect(PrivateKeyGuard.containsSecret("minha chave " + Base58.bitcoin.encode(pair)))
        #expect(PrivateKeyGuard.containsSecret("secretKey: " + Hex.encode(pair)))
    }

    @Test("Texto livre: o .env, o descritor, o vetor e os numeros no meio da frase, o WIF em duas linhas")
    func keyInFreeText() {
        let wif = "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"
        let xprv = "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi"
        let characters = Array(wif)
        let groups: [String] = stride(from: 0, to: characters.count, by: 4).map { start in
            String(characters[start..<min(start + 4, characters.count)])
        }
        let rows: [String] = zip(Array("ABCDEFGH"), xaman).map { letter, block in "\(letter) \(block)" }
        let labeledXaman: String = "numeros do Xaman: " + rows.joined(separator: ", ")
        let vector: String = "minha chave: [" + Array(repeating: "12", count: 64).joined(separator: ", ") + "] obrigado"
        let texts: [String] = [
            "PRIVATE_KEY=\(wif)", "chave=\(wif)&x=1", "wpkh([d34db33f/84h/0h/0h]\(xprv)/0/*)", vector,
            labeledXaman,
            "o papel diz\n\(wif.prefix(26))\n\(wif.dropFirst(26))\nobrigado",
            "o papel diz " + groups.joined(separator: " "),
        ]
        for text in texts {
            #expect(PrivateKeyGuard.containsSecret(text), "\(text)")
        }
        // A chave da Cardano cortada no fim.
        #expect(PrivateKeyGuard.containsSecret("ed25519e_sk1" + String(repeating: "q", count: 100)))
    }

    @Test("O que fica publico na rede: os 64 hexadecimais tambem; no suporte, nao")
    func publicText() {
        let hex = String(repeating: "4c", count: 32)
        #expect(PrivateKeyGuard.publicTextHasSecret(hex))
        #expect(PrivateKeyGuard.publicTextHasSecret("chave 0x" + hex))
        #expect(PrivateKeyGuard.publicTextHasSecret(String(repeating: "ab", count: 60)))
        #expect(!PrivateKeyGuard.containsSecret("tx " + hex))
        #expect(!PrivateKeyGuard.publicTextHasSecret("Pagamento do aluguel de novembro, apartamento 302, obrigado pela paciência de sempre"))
        #expect(!PrivateKeyGuard.publicTextHasSecret("123456789"))
    }

    @Test("O link com a chave no comentario e recusado")
    func linkTag() {
        let wif = "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"
        #expect(throws: PaymentLink.Problem.containsPrivateKey) {
            _ = try PaymentLink.read("ton://transfer/EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N?text=\(wif)")
        }
        #expect(throws: PaymentLink.Problem.containsPrivateKey) {
            _ = try PaymentLink.read("ton://transfer/EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N?text=" + String(repeating: "4c", count: 32))
        }
        #expect(PrivateKeyGuard.clipboardHasSecret("ton://transfer/EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N?text=" + String(repeating: "4c", count: 32), on: nil))
        #expect((try? PaymentLink.read("ton://transfer/EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N?text=123456"))?.tag == "123456")
    }

    @Test("Os 64 hexadecimais: chave onde nao sao endereco")
    func hexKeys() throws {
        let hex = String(repeating: "ab", count: 32)
        #expect(PrivateKeyGuard.looksLikeHexKey(hex, on: .ethereum))
        #expect(PrivateKeyGuard.looksLikeHexKey("0x" + hex, on: .ethereum))
        let sui = try #require(Chain.find("sui"))
        #expect(!PrivateKeyGuard.looksLikeHexKey("0x" + hex, on: sui))
        #expect(PrivateKeyGuard.looksLikeHexKey(hex, on: sui))
        // Sem rede, nenhum fluxo aceita 64 hex: com ou sem 0x, e chave; a TON crua passa.
        #expect(PrivateKeyGuard.looksLikeHexKey("0x" + hex, on: nil))
        #expect(!PrivateKeyGuard.looksLikeHexKey("0:" + hex, on: nil))
    }
}

extension PrivateKeyGuardTests {
    @Test("Aspas curvas, caractere invisivel e largura cheia nao escondem a chave")
    func disguised() {
        let wif = "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"
        for text in ["minha chave é “\(wif)”", "« \(wif) »", "「\(wif)」", "\(wif)…",
                     String(wif.prefix(20)) + "\u{200B}" + String(wif.dropFirst(20)),
                     String(wif.prefix(20)) + "\u{00AD}" + String(wif.dropFirst(20))] {
            #expect(PrivateKeyGuard.containsSecret(text), "\(text)")
        }
        #expect(PrivateKeyGuard.looksLikeSecretInAddressField("abandon ability able ab\u{00AD}out above absent"))
    }

    @Test("No campo do endereco: o pedaco da frase, a frase unida por ponto, o SeedQR e o hex com rotulo")
    func addressField() {
        #expect(PrivateKeyGuard.looksLikeSecretInAddressField("abandon ability able about above absent"))
        #expect(PrivateKeyGuard.looksLikeSecretInAddressField("act.add.age.aim.air.all.arm.art.ask.bag.bar.box"))
        let seedQR = (0..<12).map { String(format: "%04d", $0 * 170) }.joined()
        #expect(PrivateKeyGuard.looksLikeSecretInAddressField(seedQR))
        #expect(PrivateKeyGuard.looksLikeSecretInAddressField("PRIVATE_KEY=" + String(repeating: "4c", count: 32)))
        #expect(PrivateKeyGuard.looksLikeLabeledHexKey("minha chave privada: " + String(repeating: "4c", count: 32)))
        // Endereco nao e segredo, nem o 64 hex sem rotulo (a conta da NEAR, a Sui).
        for address in ["alice.near", "0x" + String(repeating: "1", count: 62) + "ab", String(repeating: "a", count: 64),
                        "EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N", "GBRPYHIL2CI3FNQ4BXLFMNDLFJUNPU2HY3ZMFSHONUCEOASW7QC7OX2H",
                        "rPT1Sjq2YGrBMTttX4GZHjKu9dyfzbpAYe", "bitcoin:1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2?amount=0.1&label=Pedido",
                        "solana:7cVfgArCheMR6Cs4t6vz5rfnqd56vZq4ndaBrY5xkxXy?amount=1&reference=7cVfgArCheMR6Cs4t6vz5rfnqd56vZq4ndaBrY5xkxXy"] {
            #expect(!PrivateKeyGuard.looksLikeSecretInAddressField(address), "\(address)")
        }
    }

    @Test("A frase com dois erros, abreviada em 4 letras e numerada com letras")
    func phraseForms() {
        #expect(PrivateKeyGuard.containsSecret("abandon ability able xyzq above absent absorb abstract absurd qwrt accident account"))
        #expect(PrivateKeyGuard.containsSecret("aban abil able abou abov abse abso abst"))
        // Sem as palavras de funcao do ingles (about, above), que no texto livre sao neutras.
        #expect(PrivateKeyGuard.containsSecret("a) abandon b) ability c) able d) absent e) absorb f) abstract"))
        #expect(PrivateKeyGuard.containsSecret("1ª abandon 2ª ability 3ª able 4ª absent 5ª absorb 6ª abstract"))
        // O trecho que pesou vai no aviso.
        #expect(PrivateKeyGuard.phraseRun("zzz: abandon ability able about above absent absorb, zzz") == "abandon ability able about above absent absorb")
    }

    @Test("Os numeros do Xaman: partidos, no QR, com um erro; oito numeros quaisquer passam")
    func secretNumbers() {
        let blocks = xaman
        #expect(PrivateKeyGuard.containsSecret(blocks.enumerated().map { "\($0.offset + 1) \($0.element)" }.joined(separator: " ")))
        let split: [String] = blocks.map { String($0.prefix(3)) + " " + String($0.dropFirst(3)) }
        #expect(PrivateKeyGuard.containsSecret(split.joined(separator: " ")))
        #expect(PrivateKeyGuard.containsSecret("xrplsn:" + blocks.joined()))
        var typo = blocks
        typo[3] = "999999"
        #expect(PrivateKeyGuard.containsSecret(typo.joined(separator: " ")))
        #expect(!PrivateKeyGuard.containsSecret("pedidos 123456 234567 345678 456789 567890 678901 789012 890123"))
    }

    @Test("Chave com tipo cortada no fim")
    func truncatedTyped() {
        #expect(PrivateKeyGuard.looksLikePrivateKey("suiprivkey1" + String(repeating: "q", count: 45)))
        #expect(PrivateKeyGuard.looksLikePrivateKey("ed25519-priv-0x" + String(repeating: "1a", count: 25)))
        #expect(PrivateKeyGuard.looksLikePrivateKey("ed25519:" + String(Base58.bitcoin.encode([UInt8](repeating: 3, count: 64)).prefix(60))))
        // A chave publica da NEAR passa.
        #expect(!PrivateKeyGuard.looksLikePrivateKey("ed25519:" + Base58.bitcoin.encode([UInt8](repeating: 3, count: 32))))
    }

    @Test("O chamado do suporte: o tipo do segredo, o ID pela rede, o boleto e o ingles comum passam")
    func support() throws {
        let hex = String(repeating: "4c", count: 32)
        let sui = try #require(Chain.find("sui"))
        // Com o rotulo "chave", e chave; sem rotulo, o aviso do hex.
        #expect(PrivateKeyGuard.supportSecret(details: "como importo a chave \(hex)?", transaction: "", chain: nil) == .secret)
        #expect(PrivateKeyGuard.supportSecret(details: "importei \(hex) e nao aparece", transaction: "", chain: nil) == .hex)
        // O ID: com 0x na EVM; sem 0x no Bitcoin; sem a rede, ela e pedida; na Sui, 64 hex nunca sao o codigo.
        #expect(PrivateKeyGuard.supportSecret(details: "o envio nao chegou", transaction: "0x" + hex, chain: .ethereum) == .none)
        #expect(PrivateKeyGuard.supportSecret(details: "o envio nao chegou", transaction: hex, chain: .ethereum) == .secret)
        #expect(PrivateKeyGuard.supportSecret(details: "o envio nao chegou", transaction: hex, chain: .bitcoin) == .none)
        #expect(PrivateKeyGuard.supportSecret(details: "o envio nao chegou", transaction: hex, chain: nil) == .needsNetwork)
        #expect(PrivateKeyGuard.supportSecret(details: "o envio nao chegou", transaction: "0x" + hex, chain: sui) == .secret)
        #expect(PrivateKeyGuard.supportSecret(details: "o envio nao chegou", transaction: "chave privada: 0x" + hex, chain: .ethereum) == .secret)
        // O endereco da propria rede no texto passa.
        #expect(PrivateKeyGuard.supportSecret(details: "mandei para 0x\(hex) e nao chegou", transaction: "", chain: sui, known: [hex]) == .none)
        #expect(PrivateKeyGuard.supportSecret(details: "mandei para 0x\(hex) e nao chegou", transaction: "", chain: sui) == .hex)
        #expect(PrivateKeyGuard.supportSecret(details: "chave 5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ", transaction: "", chain: nil) == .secret)
        // No texto do chamado, as palavras de funcao do ingles (about, above) nao contam: seis sem elas.
        if case .words = PrivateKeyGuard.supportSecret(details: "abandon ability able absent absorb abstract", transaction: "", chain: nil) {} else {
            Issue.record("as seis palavras")
        }
        #expect(PrivateKeyGuard.supportSecret(details: "paguei o boleto " + String(repeating: "8", count: 48), transaction: "", chain: nil) == .none)
        #expect(PrivateKeyGuard.supportSecret(details: String(repeating: "a ", count: 2100), transaction: "", chain: nil) == .secret)
        // O chamado normal em ingles, e o erro do proprio app colado nele.
        for text in ["The swap failed. Can you check this order again, please?", "Please check this transfer again today",
                     "The network fee is above the safety limit right now. Try again later."] {
            #expect(PrivateKeyGuard.supportSecret(details: text, transaction: "", chain: nil) == .none, "\(text)")
        }
        // Doze datas nao sao SeedQR.
        let dates = (1...12).map { String(format: "%02d/10/2025", $0) }.joined(separator: ", ")
        #expect(PrivateKeyGuard.supportSecret(details: "os envios de " + dates, transaction: "", chain: nil) == .none)
        // Hex em grupos e com rotulo grudado.
        #expect(PrivateKeyGuard.publicTextHasSecret(stride(from: 0, to: 64, by: 8).map { _ in "4c084c08" }.joined(separator: " ")))
        #expect(PrivateKeyGuard.publicTextHasSecret("pk-" + hex))
        #expect(!PrivateKeyGuard.publicTextHasSecret("de 0x" + String(repeating: "ab", count: 20) + " para 0x" + String(repeating: "cd", count: 20)))
    }
}

extension PrivateKeyGuardTests {
    @Test("A parte SLIP-39 do Trezor e a frase chinesa sem espaco")
    func slipAndHan() throws {
        let slip = try WordlistStore.shared.slip39().words
        let share = (0..<20).map { slip[($0 * 37) % 1024] }.joined(separator: " ")
        #expect(PrivateKeyGuard.containsSecret("tenho um Trezor com 20 palavras e o app nao aceita: " + share))
        let entropy = SecureBytes(capacity: 16)
        [UInt8](repeating: 0x5A, count: 16).withUnsafeBufferPointer { entropy.append(contentsOf: $0) }
        let phrase = try BIP39.phrase(fromEntropy: entropy, language: .chineseSimplified)
        let han = phrase.withUnsafeData { String(decoding: $0, as: UTF8.self) }.filter { !$0.isWhitespace }
        #expect(PrivateKeyGuard.containsSecret("minha frase: " + han + "。"))
        #expect(PrivateKeyGuard.looksLikeSecretInAddressField(han))
    }

    @Test("Os 64 hex enfeitados no campo do endereco, e os 66 da XRPL")
    func decoratedHex() throws {
        let hex = String(repeating: "4c", count: 32)
        let near = try #require(Chain.find("near"))
        let ton = try #require(Chain.find("ton"))
        for text in ["\"0x\(hex)\"", "\(hex).", "“\(hex)”", "PK=\(hex)", String(hex.prefix(32)) + "\n" + String(hex.dropFirst(32))] {
            #expect(PrivateKeyGuard.looksLikeHexKey(text, on: .ethereum), "\(text)")
        }
        #expect(PrivateKeyGuard.looksLikeHexKey("key: \(hex)", on: near))
        #expect(PrivateKeyGuard.looksLikeHexKey("ED" + hex, on: .ethereum))
        #expect(!PrivateKeyGuard.looksLikeHexKey("0:" + hex, on: ton))
        #expect(!PrivateKeyGuard.looksLikeHexKey("ton://transfer/0:" + hex, on: ton))
    }

    @Test("Erros de digitacao: Xaman com dois blocos, SeedQR com um grupo, assinatura da NEAR e Solana cortada")
    func typos() throws {
        var blocks = xaman
        blocks[2] = "999999"
        blocks[5] = "999998"
        #expect(PrivateKeyGuard.containsSecret(blocks.joined(separator: " ")))
        let seedQR = (0..<12).map { String(format: "%04d", $0 * 170) }
        var wrong = seedQR
        wrong[4] = "9999"
        #expect(PrivateKeyGuard.looksLikeSeedNumbers(wrong.joined()))
        #expect(PrivateKeyGuard.looksLikeSeedNumbers(wrong.joined(separator: " ")))
        // A assinatura da NEAR (64 bytes que nao sao o par) passa; a chave de verdade, nao.
        #expect(!PrivateKeyGuard.containsSecret("ed25519:" + Base58.bitcoin.encode([UInt8](repeating: 3, count: 64))))
        #expect(PrivateKeyGuard.containsSecret("ed25519:" + Base58.bitcoin.encode(try keyPair())))
        #expect(PrivateKeyGuard.containsSecret("minha chave " + String(Base58.bitcoin.encode(try keyPair()).prefix(70))))
        // O hex partido fora do meio, e com hifen.
        let hex = String(repeating: "4c", count: 32)
        #expect(PrivateKeyGuard.publicTextHasSecret(String(hex.prefix(40)) + " " + String(hex.dropFirst(40))))
        #expect(PrivateKeyGuard.containsSecret("5Hue-CGU8-rMjx-EXxi-PuD5-BDku-4MkF-qeZy-d4dZ-1jvh-TVqv-bTLv-yTJ"))
    }
}

extension PrivateKeyGuardTests {
    @Test("Quinta rodada: rotulo no chamado, \"Wallet 1:\", ordinais, chines com \"助记词是\", Taproot e AIP-80 em linhas")
    func roundFive() throws {
        let hex = String(repeating: "4c", count: 32)
        let aptos = try #require(Chain.find("aptos"))
        let ton = try #require(Chain.find("ton"))
        let near = try #require(Chain.find("near"))
        // A chave com rotulo no texto do chamado da Aptos; o endereco sem rotulo passa.
        #expect(PrivateKeyGuard.supportSecret(details: "Minha chave privada da Petra: 0x\(hex)", transaction: "", chain: aptos) == .secret)
        #expect(PrivateKeyGuard.supportSecret(details: "mandei para 0x\(hex) e nao chegou", transaction: "", chain: aptos, known: [hex]) == .none)
        // O endereco cru da TON no chamado da TON passa.
        #expect(PrivateKeyGuard.supportSecret(details: "mandei para 0:\(hex) ontem", transaction: "", chain: ton) == .none)
        // Um rotulo que termina em 0 ou 1 nao e o endereco cru da TON.
        for text in ["Wallet 1:\n\(hex)", "1: \(hex)", "Conta 0: 0x\(hex)"] {
            #expect(PrivateKeyGuard.looksLikeHexKey(text, on: .ethereum), "\(text)")
        }
        #expect(PrivateKeyGuard.looksLikeHexKey("Wallet 1:\n\(hex)", on: near))
        #expect(!PrivateKeyGuard.looksLikeHexKey("ton://transfer/0:\(hex)", on: ton))
        // A chave publica com rotulo nao e chave.
        #expect(!PrivateKeyGuard.looksLikeLabeledHexKey("public key: \(hex)"))
        // Os ordinais e o numero da linha nao quebram a frase.
        #expect(PrivateKeyGuard.containsSecret("1st abandon 2nd ability 3rd able 4th absent 5th absorb 6th abstract"))
        #expect(PrivateKeyGuard.containsSecret("No.1 abandon No.2 ability No.3 able No.4 absent No.5 absorb No.6 abstract"))
        // As palavras de funcao do ingles sao neutras: a frase com elas no meio continua pega.
        #expect(PrivateKeyGuard.containsSecret("abandon ability able about above absent absorb abstract absurd"))
        #expect(!PrivateKeyGuard.publicTextHasSecret("Please confirm when you receive this payment, thank you very much"))
        // A frase chinesa logo depois de "助记词是".
        let entropy = SecureBytes(capacity: 16)
        [UInt8](repeating: 0x5A, count: 16).withUnsafeBufferPointer { entropy.append(contentsOf: $0) }
        let phrase = try BIP39.phrase(fromEntropy: entropy, language: .chineseSimplified)
        let han = phrase.withUnsafeData { String(decoding: $0, as: UTF8.self) }.filter { !$0.isWhitespace }
        #expect(PrivateKeyGuard.containsSecret("我的助记词是" + han + "请帮我恢复"))
        // O Taproot de 62 caracteres nao e chave da Solana cortada.
        #expect(PrivateKeyGuard.supportSecret(details: "mandei para bc1p" + String(repeating: "q", count: 58), transaction: "", chain: .bitcoin) == .none)
        // A AIP-80 em duas linhas.
        #expect(PrivateKeyGuard.looksLikePrivateKey("ed25519-priv-0x" + String(hex.prefix(32)) + "\n" + String(hex.dropFirst(32))))
        // No ID: o hex partido, o xrpl.js e os 128.
        #expect(PrivateKeyGuard.supportSecret(details: "o envio nao chegou", transaction: "0x" + String(hex.prefix(32)) + " " + String(hex.dropFirst(32)), chain: .bitcoin) == .secret)
        #expect(PrivateKeyGuard.supportSecret(details: "o envio nao chegou", transaction: "ED" + hex, chain: .xrpl) == .secret)
        #expect(PrivateKeyGuard.supportSecret(details: "o envio nao chegou", transaction: hex + hex, chain: .bitcoin) == .secret)
    }
}

extension PrivateKeyGuardTests {
    @Test("Sexta rodada: numeracao em CJK, rotulo longe, palavra vizinha do hex, link da NEAR, chines com 单词, dois codigos no ID")
    func roundSix() throws {
        let hex = String(repeating: "4c", count: 32)
        let aptos = try #require(Chain.find("aptos"))
        let near = try #require(Chain.find("near"))
        // A frase coreana e a chinesa numeradas, grudadas no algarismo.
        for language in [BIP39Language.korean, .chineseSimplified] {
            let words = WordLexicon.entries.filter { $0.language == language }.prefix(12).map(\.word)
            let numbered = words.enumerated().map { "\($0.offset + 1)\($0.element)" }.joined(separator: " ")
            #expect(PrivateKeyGuard.containsSecret(numbered), "\(language)")
        }
        // O rotulo longe do hex, e "publish" antes dele.
        #expect(PrivateKeyGuard.supportSecret(details: "Segue a chave privada da minha conta na Petra para vocês conferirem: 0x\(hex)", transaction: "", chain: aptos) == .secret)
        #expect(PrivateKeyGuard.looksLikeLabeledHexKey("Tried to publish the tx, private key: 0x\(hex)"))
        #expect(PrivateKeyGuard.looksLikeLabeledHexKey("const deployerKey = \"0x\(hex)\""))
        #expect(!PrivateKeyGuard.looksLikeLabeledHexKey("chave pública: \(hex)"))
        // A palavra vizinha do hex, separada por espaco, no campo do endereco.
        for text in ["MetaMask \(hex)", "\(hex) metamask", "ETH 0x\(hex)", "Conta 1 - \(hex)"] {
            #expect(PrivateKeyGuard.looksLikeHexKey(text, on: .ethereum), "\(text)")
        }
        #expect(PrivateKeyGuard.looksLikeHexKey("MetaMask \(hex)", on: nil))
        // O link da NEAR para a conta implicita (na curva) passa.
        let implicit = Hex.encode(Array(try keyPair()[32..<64]))
        #expect(!PrivateKeyGuard.looksLikeHexKey("near:\(implicit)", on: near))
        // A TON crua colada na rede errada nao vira chave (a validacao sugere a TON).
        #expect(!PrivateKeyGuard.looksLikeHexKey("0:\(hex)", on: .ethereum))
        // O chines com o termo do proprio app.
        let entropy = SecureBytes(capacity: 16)
        [UInt8](repeating: 0x5A, count: 16).withUnsafeBufferPointer { entropy.append(contentsOf: $0) }
        let phrase = try BIP39.phrase(fromEntropy: entropy, language: .chineseSimplified)
        let han = phrase.withUnsafeData { String(decoding: $0, as: UTF8.self) }.filter { !$0.isWhitespace }
        #expect(PrivateKeyGuard.containsSecret("我的12个单词是" + han + "请帮我看看"))
        // Dois codigos de transacao do Bitcoin no ID passam.
        let other = String(repeating: "5d", count: 32)
        #expect(PrivateKeyGuard.supportSecret(details: "dois envios nao chegaram", transaction: hex + " " + other, chain: .bitcoin) == .none)
    }
}

extension PrivateKeyGuardTests {
    @Test("Setima rodada: sem rede, chines pela frequencia, rotulos dobrados, hifen, tipo da Move, ID com tamanho estranho")
    func roundSeven() throws {
        let hex = String(repeating: "4c", count: 32)
        let sui = try #require(Chain.find("sui"))
        let aptos = try #require(Chain.find("aptos"))
        let ton = try #require(Chain.find("ton"))
        // Sem rede: a chave na curva tambem.
        let onCurve = Hex.encode(Array(try keyPair()[32..<64]))
        #expect(PrivateKeyGuard.looksLikeHexKey(onCurve, on: nil))
        // A frase chinesa a mais de 2 caracteres da palavra-chave, e sem palavra-chave nenhuma.
        let entropy = SecureBytes(capacity: 16)
        [UInt8](repeating: 0x5A, count: 16).withUnsafeBufferPointer { entropy.append(contentsOf: $0) }
        let phrase = try BIP39.phrase(fromEntropy: entropy, language: .chineseSimplified)
        let han = phrase.withUnsafeData { String(decoding: $0, as: UTF8.self) }.filter { !$0.isWhitespace }
        for text in ["我的助记词是这个" + han + "请帮我看看", han + "是我的助记词", "助记词分别是" + han, "我的钱包是" + han] {
            #expect(PrivateKeyGuard.containsSecret(text), "\(text)")
        }
        // O chamado comum em chines passa.
        #expect(PrivateKeyGuard.supportSecret(details: "我的助记词导入成功了但是看不到之前的资产", transaction: "", chain: nil) == .none)
        // A chave publica em russo nao e chave; a variavel de ambiente e.
        #expect(!PrivateKeyGuard.looksLikeLabeledHexKey("открытый ключ: \(hex)"))
        #expect(PrivateKeyGuard.looksLikeLabeledHexKey("WALLETKEY=\(hex)"))
        #expect(!PrivateKeyGuard.looksLikeLabeledHexKey("public key: \(hex)"))
        #expect(PrivateKeyGuard.looksLikeLabeledHexKey("pk-\(hex)"))
        #expect(!PrivateKeyGuard.looksLikeLabeledHexKey("reimbursement \(hex)"))
        // O hex em grupos com hifen na NEAR, e o enfeitado na Sui; o link da Sui passa.
        let dashed = stride(from: 0, to: 64, by: 4).map { _ in "4c4c" }.joined(separator: "-")
        #expect(PrivateKeyGuard.looksLikeHexKey(dashed, on: try #require(Chain.find("near"))))
        #expect(PrivateKeyGuard.looksLikeHexKey("(0) 0x\(hex)", on: sui))
        #expect(!PrivateKeyGuard.looksLikeHexKey("sui:0x\(hex)", on: sui))
        // O tipo da Move inteiro passa no chamado; "0x<chave>::" sozinho, nao.
        #expect(PrivateKeyGuard.supportSecret(details: "a moeda 0x\(hex)::usdc::USDC sumiu", transaction: "", chain: sui) == .none)
        #expect(PrivateKeyGuard.publicTextHasSecret("0x\(hex)::"))
        // O USDC oficial da Aptos no chamado passa como contrato conhecido.
        let usdc = "0xbae207659db88bea0cbead6da0ed00aac12edcdda169e591cd41c94180b46f3b"
        let known = PrivateKeyGuard.publicContracts(on: aptos, assetIDs: [])
        #expect(PrivateKeyGuard.supportSecret(details: "o USDC \(usdc) nao aparece", transaction: "", chain: aptos, known: known) == .none)
        // A TON crua com rotulo por perto, no chamado da TON, e endereco.
        #expect(PrivateKeyGuard.supportSecret(details: "importei a seed e o endereco ficou 0:\(hex)", transaction: "", chain: ton) == .none)
        // O ID com o cborHex da Cardano (68) nao sai.
        #expect(PrivateKeyGuard.supportSecret(details: "o envio nao chegou", transaction: "5820" + hex, chain: .cardano) == .secret)
    }
}

@Suite("Comentario da TON com segredo")
struct TONCommentSecretTests {
    @Test("A frase ou a chave no comentario e recusada antes da rede")
    func comment() {
        #expect(throws: TONPlanError.commentHasSecret) {
            _ = try TONPlanner.checkedComment("5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ")
        }
        #expect((try? TONPlanner.checkedComment("pedido 123")) == "pedido 123")
        let long = "Pagamento do aluguel de novembro, apartamento 302, obrigado pela paciência de sempre"
        #expect((try? TONPlanner.checkedComment(long)) == long)
        #expect(throws: TONPlanError.commentHasSecret) {
            _ = try TONPlanner.checkedComment("0x" + String(repeating: "4c", count: 32))
        }
    }

    @Test("Auditoria 8: a frase colada, em CamelCase, com letra modificadora ou letras cirilicas; a chave em pares e com ponto")
    func transformed() throws {
        let words = "abandon ability able about above absent absorb abstract absurd abuse access accident".split(separator: " ").map(String.init)
        // Colada sem espaco e em CamelCase.
        #expect(PrivateKeyGuard.publicTextHasSecret(words.joined()))
        #expect(PrivateKeyGuard.publicTextHasSecret(words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()))
        // A letra modificadora (U+02BC, U+02C8) no lugar do espaco.
        #expect(PrivateKeyGuard.publicTextHasSecret(words.joined(separator: "\u{02BC}")))
        #expect(PrivateKeyGuard.publicTextHasSecret(words.joined(separator: "\u{02C8}")))
        // Letras cirilicas e gregas identicas as latinas.
        let cyrillic = words.joined(separator: " ").replacingOccurrences(of: "a", with: "\u{0430}").replacingOccurrences(of: "e", with: "\u{0435}")
            .replacingOccurrences(of: "o", with: "\u{03BF}")
        #expect(PrivateKeyGuard.publicTextHasSecret(cyrillic))
        // A chave de 64 hexadecimais em pares, com ponto a cada 8, e como lista de bytes.
        let hex = "4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
        let pairs = stride(from: 0, to: 64, by: 2).map { i -> String in let a = hex.index(hex.startIndex, offsetBy: i); return String(hex[a..<hex.index(a, offsetBy: 2)]) }
        #expect(PrivateKeyGuard.publicTextHasSecret(pairs.joined(separator: " ")))
        #expect(PrivateKeyGuard.publicTextHasSecret(stride(from: 0, to: 64, by: 8).map { i -> String in
            let a = hex.index(hex.startIndex, offsetBy: i); return String(hex[a..<hex.index(a, offsetBy: 8)]) }.joined(separator: ".")))
        #expect(PrivateKeyGuard.publicTextHasSecret(pairs.map { "0x" + $0 }.joined(separator: ", ")))
        #expect(PrivateKeyGuard.publicTextHasSecret(pairs.joined(separator: "/")))
    }

    @Test("Auditoria 8: texto comum colado, dois enderecos, data e hora, e o memo de deposito passam")
    func transformedCommonText() {
        for text in ["pleasesendthepaymenttomynewaccount", "olaamigocomovocevaihojeestabem", "thankyouverymuchforyourhelptoday",
                     "PaymentForServicesRenderedInNovember", "deposito 2025-11-14 14:30:00 pedido 4512",
                     "0x2652742DE21ED9a6c37e73b0E3a51b239A6D1008, 0xF977814e90dA44bFA03b6295A0616a897441aceC",
                     "ref ab12 cd34 pedido 77", "MEMO 1234567890"] {
            #expect(!PrivateKeyGuard.publicTextHasSecret(text), "\(text)")
        }
        // A frase de verdade com palavras de fora da lista no meio continua pela regra de antes, e um trecho curto colado nao
        // vira frase.
        #expect(!PrivateKeyGuard.publicTextHasSecret("abandonability"))
        #expect(PrivateKeyGuard.wordsCovering(Array("abandonabilityable")) == 3)
        #expect(PrivateKeyGuard.wordsCovering(Array("abandonabilityablex")) == 0)
    }

    @Test("Rodada 1: a frase com algarismos no lugar de letras e com as letras soltas; a chave em grupos do tamanho de chave")
    func roundOneTransforms() {
        #expect(PrivateKeyGuard.containsSecret("4b4nd0n 4b1l1ty 4bl3 4b0ut 4b0v3 4bs3nt 4bs0rb 4bstr4ct 4bsurd 4bus3 4cc3ss 4cc1d3nt"))
        #expect(PrivateKeyGuard.undigited("ab4nd0n 100 USDT").contains("abandon 100 USDT"))
        #expect(PrivateKeyGuard.joiningSpacedLetters("a b a n d o n ok").hasPrefix("abandon"))
        #expect(PrivateKeyGuard.publicTextHasSecret("a b a n d o n a b i l i t y a b l e a b o u t a b o v e a b s e n t"))
        #expect(PrivateKeyGuard.publicTextHasSecret("a1b2 c3d4 e5f6 a7b8 c9d0 e1f2 a3b4 c5d6 e7f8 a9b0 c1d2 e3f4"))
        // Os grupos sem a forma de chave partida passam: dois UUIDs, a data, a lista de codigos.
        for text in ["pedido 123e4567-e89b-12d3-a456-426614174000 e 9f8e7d6c-5b4a-3c2d-1e0f-a1b2c3d4e5f6",
                     "vence 01/10/2025", "codigos 123456 234567 345678 456789 567890 678901 789012 890123"] {
            #expect(!PrivateKeyGuard.publicTextHasSecret(text), "\(text)")
        }
    }

    @Test("Rodada 1: o UID de uma ordem da CoW passa no ID do chamado so com o dono sendo conta da carteira")
    func cowOrderUID() {
        let owner = "2652742de21ed9a6c37e73b0e3a51b239a6d1008"
        let uid = String(repeating: "ab", count: 32) + owner + "6a1b2c3d"
        #expect(uid.count == 112)
        #expect(PrivateKeyGuard.supportSecret(details: "a ordem nao saiu", transaction: "0x" + uid, chain: .ethereum, known: [owner]) == .none)
        #expect(PrivateKeyGuard.supportSecret(details: "a ordem nao saiu", transaction: "0x" + uid, chain: .ethereum) == .secret)
    }
}
