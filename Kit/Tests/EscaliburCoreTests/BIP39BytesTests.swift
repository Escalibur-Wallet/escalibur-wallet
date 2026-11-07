import Testing
@testable import EscaliburCore

@Suite("BIP-39 sobre os bytes")
struct BIP39BytesTests {
    func secure(_ text: String) -> SecureBytes {
        let bytes = SecureBytes(capacity: max(text.utf8.count, 1))
        bytes.replaceAll(with: Array(text.utf8))
        return bytes
    }

    @Test("Validar pelos bytes da o mesmo veredito do validador do Escalibur, nos dez idiomas")
    func sameVerdict() throws {
        for language in BIP39Language.allCases {
            for count in [12, 24] {
                let phrase = try Mnemonic.generate(wordCount: count, language: language)
                let canonical = Mnemonic.canonicalize(phrase)
                #expect(BIP39.validate(secure(canonical)) == Mnemonic.validate(phrase), "\(language) \(count)")
                #expect(BIP39.closingLanguage(secure(canonical), store: .shared) != nil || Mnemonic.validate(phrase) != .valid(language: language))

                // Troca a ultima palavra: checksum que nao fecha, ou palavra fora.
                var words = canonical.split(separator: " ").map(String.init)
                let list = try WordlistStore.shared.wordlist(for: language)
                words[words.count - 1] = list.words[(Int(list.position(of: words.last!) ?? 0) + 1) % 2048]
                let broken = words.joined(separator: " ")
                #expect(BIP39.validate(secure(broken)) == Mnemonic.validate(broken), "\(language) quebrada")

                // Tamanho errado e forma nao canonica.
                let short = words.dropLast().joined(separator: " ")
                #expect(BIP39.validate(secure(short)) == Mnemonic.validate(short))
                let messy = "  " + canonical.uppercased().replacingOccurrences(of: " ", with: "   ") + " "
                #expect(BIP39.validate(secure(messy)) == Mnemonic.validate(messy), "\(language) baguncada")
                // O diagnostico pelos bytes (06/11/2026): os espacos e invisiveis que o canonicalize trata, na frase boa e
                // na quebrada.
                for separator in ["\t", "\n", "\u{00A0}", "\u{3000}", "\u{2028}", " \u{200B}", "\u{00AD} ", " \u{FEFF}\u{2003}", " \u{00B4}", "\u{309B} ", "\u{02DC}"] {
                    let good = canonical.replacingOccurrences(of: " ", with: separator)
                    #expect(BIP39.validate(secure(good)) == Mnemonic.validate(good), "\(language) com \(separator.unicodeScalars.map { $0.value })")
                    let bad = broken.replacingOccurrences(of: " ", with: separator)
                    #expect(BIP39.validate(secure(bad)) == Mnemonic.validate(bad), "\(language) quebrada com \(separator.unicodeScalars.map { $0.value })")
                }
            }
        }
    }

    @Test("Entropia ida e volta pelos bytes, nos dez idiomas")
    func entropyRoundTrip() throws {
        for language in BIP39Language.allCases {
            let entropy = try SecureBytes.random(count: 32)
            let phrase = try BIP39.phrase(fromEntropy: entropy, language: language)
            let back = try BIP39.entropy(fromPhrase: phrase, language: language)
            #expect(Hash.constantTimeEqual(back, entropy), "\(language)")
        }
    }

    @Test("Frase coreana so com as palavras de 33 bytes: monta, volta e valida (auditoria 6, A6-09)")
    func longestKoreanWords() throws {
        let list = try WordlistStore.shared.wordlist(for: .korean)
        let long = list.words.indices.filter { list.words[$0].decomposedStringWithCompatibilityMapping.utf8.count == 33 }
        #expect(long.count == 7)
        for count in [12, 24] {
            // As primeiras palavras todas de 33 bytes; os bits que sobram em zero, e a ultima
            // sai do checksum.
            let entropyBits = count * 32 / 3
            var bits: [UInt8] = []
            for i in 0..<(count - 1) {
                let index = long[i % long.count]
                for b in (0..<11).reversed() { bits.append(UInt8((index >> b) & 1)) }
            }
            while bits.count < entropyBits { bits.append(0) }
            let entropy = SecureBytes(capacity: entropyBits / 8)
            for byteIndex in 0..<(entropyBits / 8) {
                var byte: UInt8 = 0
                for b in 0..<8 { byte = byte << 1 | bits[byteIndex * 8 + b] }
                entropy.append(byte)
            }
            let phrase = try BIP39.phrase(fromEntropy: entropy, language: .korean)
            let back = try BIP39.entropy(fromPhrase: phrase, language: .korean)
            #expect(Hash.constantTimeEqual(back, entropy), "\(count)")
            let text = phrase.withUnsafeBytes { String(decoding: $0, as: UTF8.self) }
            #expect(Mnemonic.validate(text) == .valid(language: .korean), "\(count)")
            #expect(text.split(separator: " ").dropLast().allSatisfy { $0.utf8.count == 33 })
        }
    }

    @Test("25a palavra: bytes ASCII e caminho NFKD dao a mesma seed do vetor")
    func passphraseSeed() throws {
        let phrase = BIP39.canonical("legal winner thank year wave sausage worth useful legal winner thank yellow")
        let viaBytes = try BIP39.seed(phrase: phrase, passphrase: secure("TREZOR"))
        let viaString = try BIP39.seed(phrase: phrase, passphrase: "TREZOR")
        #expect(Hash.constantTimeEqual(viaBytes, viaString))
        #expect(viaBytes.withUnsafeBytes { Array($0) }.hex.hasPrefix("2e8905819b8723fe"))
        // Fora do ASCII: NFC e NFKD da mesma senha dao a mesma seed.
        let nfc = try BIP39.seed(phrase: phrase, passphrase: secure("canção"))
        let nfkd = try BIP39.seed(phrase: phrase, passphrase: secure("canção".decomposedStringWithCompatibilityMapping))
        #expect(Hash.constantTimeEqual(nfc, nfkd))
        // E contra um valor publicado, e nao so contra a propria Foundation: o vetor 0 do bip32JP (test_JP_BIP39.json), em
        // que o espaco ideografico, o ㍍ e as kana com dakuten so dao esta seed com o NFKD (revisao da decima terceira passada).
        let japanese = BIP39.canonical(Array(repeating: "\u{3042}\u{3044}\u{3053}\u{304F}\u{3057}\u{3093}", count: 11).joined(separator: "\u{3000}")
            + "\u{3000}\u{3042}\u{304A}\u{305E}\u{3089}")
        let jp = try BIP39.seed(phrase: japanese, passphrase: secure("\u{334D}\u{30AC}\u{30D0}\u{30F4}\u{30A1}\u{3071}\u{3070}\u{3050}\u{309E}\u{3061}\u{3062}\u{5341}\u{4EBA}\u{5341}\u{8272}"))
        #expect(jp.withUnsafeBytes { Array($0) }.hex == "a262d6fb6122ecf45be09c50492b31f92e9beb7d9a845987a02cefda57a15f9c467a17872029a9e92299b5cbdf306e3a0ee620245cbd508959b6cb7ca637bd55")
    }

    /// O NFKD de antes, pela `String` inteira: a referencia do de hoje, que decompoe letra por letra.
    func wholeString(_ bytes: [UInt8]) -> [UInt8] {
        Array(String(decoding: bytes, as: UTF8.self).decomposedStringWithCompatibilityMapping.utf8)
    }

    /// O caminho de reserva (trecho por trecho entre os ASCII), que vale onde as tabelas divergem.
    func segmentedFallback(_ bytes: [UInt8]) -> [UInt8] {
        let buffer = SecureBytes(capacity: max(bytes.count, 1))
        buffer.replaceAll(with: bytes)
        return BIP39.wholeStringNFKD(buffer).withUnsafeBytes { Array($0) }
    }

    func letterByLetter(_ bytes: [UInt8]) -> [UInt8] {
        let buffer = SecureBytes(capacity: max(bytes.count, 1))
        buffer.replaceAll(with: bytes)
        return BIP39.nfkd(buffer).withUnsafeBytes { Array($0) }
    }

    @Test("NFKD letra por letra da o mesmo que o da String inteira: cada escalar, marcas fora de ordem, Hangul e UTF-8 quebrado")
    func nfkdLetterByLetter() {
        // Cada escalar do Unicode fora do ASCII, sozinho e entre letras.
        for value in UInt32(0x80)...UInt32(0x10FFFF) {
            guard let scalar = Unicode.Scalar(value), value <= 0x2FFFF || (0xE0000...0xE01EF).contains(value) else { continue }
            let alone = Array(String(Character(scalar)).utf8)
            #expect(letterByLetter(alone) == wholeString(alone), "U+\(String(value, radix: 16))")
        }
        // Marcas de classes diferentes, em todas as ordens, coladas em letras que ja trazem marca.
        let marks: [UInt32] = [0x0301, 0x0323, 0x0308, 0x031B, 0x0327, 0x05B0, 0x0E38, 0x3099, 0x1D165, 0x0345]
        let bases = ["a", "\u{1EC7}", "\u{01D5}", "\u{1E69}", "\u{FB2C}", "\u{AC00}", "\u{304B}", "\u{2460}", "\u{FDFA}", "\u{0390}"]
        for base in bases {
            for i in marks.indices {
                for j in marks.indices where j != i {
                    for k in marks.indices where k != i && k != j && (i + j + k) % 3 == 0 {
                        let text = base + String(String.UnicodeScalarView([marks[i], marks[j], marks[k]].compactMap(Unicode.Scalar.init))) + "x" + base
                        #expect(letterByLetter(Array(text.utf8)) == wholeString(Array(text.utf8)), "\(text.unicodeScalars.map { String($0.value, radix: 16) })")
                    }
                }
            }
        }
        // A tabela de classes do Swift e a do Foundation concordam neste build (senao vale o NFKD de antes), e cada marca
        // depois de U+0345 (classe 240), tambem por aqui; e o texto que comeca por marca.
        // No iPhone as duas tabelas concordam. No Android (o Foundation do Swift 6.4.1 sobre o ICU do sistema) discordam em
        // alguma marca, e vale o caminho de reserva, que da o mesmo NFKD de antes: o que este teste confere e o resultado
        // igual, nao o caminho (07/11/2026, os vetores de derivacao no emulador).
        #if canImport(Darwin)
        #expect(BIP39.letterByLetterAgrees)
        #endif
        for value in UInt32(0x300)...UInt32(0x10FFFF) {
            guard let mark = Unicode.Scalar(value), mark.properties.canonicalCombiningClass.rawValue != 0 else { continue }
            for probe in ["a\u{0345}" + String(Character(mark)), "a" + String(Character(mark)) + "\u{0334}"] {
                let text = Array(probe.utf8)
                #expect(letterByLetter(text) == wholeString(text), "\(probe.unicodeScalars.map { String($0.value, radix: 16) })")
            }
        }
        // Frases inteiras, com espaco ideografico, kana com dakuten separado e compatibilidade.
        for text in ["canção de ninar", "\u{334D}\u{30AC}\u{30D0}\u{30F4}\u{30A1}\u{3071}\u{3070}\u{3050}\u{309E}\u{3061}\u{3062}\u{5341}\u{4EBA}\u{5341}\u{8272}",
                     "\u{304B}\u{3099}\u{3000}\u{FB01}\u{2075}\u{00BD}", "한국어 비밀번호", "Ǆemal ŉ ﷺ ẛ̣", "e\u{0301}\u{0323}e\u{0323}\u{0301}", "\u{0301}\u{0323}", "\u{0345}\u{0301}a", "a\u{0345}\u{0378}", "a\u{0301}\u{0378}\u{0323}"] {
            #expect(letterByLetter(Array(text.utf8)) == wholeString(Array(text.utf8)), "\(text)")
        }
        // O caminho de reserva tambem da o mesmo, nas frases, nas marcas fora de ordem e no UTF-8 quebrado.
        for text in ["canção de ninar", "e\u{0301}\u{0323}e\u{0323}\u{0301}x", "\u{0301}\u{0323}", "a\u{0345}\u{0378}", "한국어 비밀번호", "\u{304B}\u{3099}\u{3000}\u{FB01}"] {
            #expect(segmentedFallback(Array(text.utf8)) == wholeString(Array(text.utf8)), "\(text)")
        }
        for broken: [UInt8] in [[0xC3], [0x61, 0xC3, 0x28], [0xE2, 0x82], [0xFF, 0xC3, 0xA7, 0x80], [0xC0, 0xAF, 0xE0, 0x80, 0xAF]] {
            #expect(segmentedFallback(broken) == wholeString(broken), "\(broken)")
        }
        // UTF-8 quebrado vira U+FFFD, como no `String(decoding:)`.
        for broken: [UInt8] in [[0xC3], [0x61, 0xC3, 0x28], [0xE2, 0x82], [0xF0, 0x9F, 0x98], [0xED, 0xA0, 0x80], [0xFF, 0xC3, 0xA7, 0x80], [0xC0, 0xAF, 0xE0, 0x80, 0xAF]] {
            #expect(letterByLetter(broken) == wholeString(broken), "\(broken)")
        }
    }
}
