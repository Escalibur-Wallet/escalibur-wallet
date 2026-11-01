import Foundation
import Testing
@testable import EscaliburCore

/// O lexico do teclado proprio (revisao do teclado proprio, M2): toda palavra das seis
/// listas latinas entra digitada sem acento, com o Seguinte, e a frase digitada sem acento
/// volta a ser a do idioma em que ela fecha.
@Suite("Lexico das palavras")
struct WordLexiconTests {
    func secure(_ word: String) -> SecureBytes {
        let bytes = Array(Mnemonic.canonicalize(word).utf8)
        let out = SecureBytes(capacity: max(bytes.count, 1))
        out.replaceAll(with: bytes)
        return out
    }

    @Test("Sem acento, a forma de cada palavra e unica dentro de cada lista latina")
    func foldedIsUnique() throws {
        for language in WordLexicon.latin {
            let words = try WordlistStore.shared.wordlist(for: language).words
            #expect(Set(words.map(WordLexicon.fold)).count == words.count, "\(language)")
        }
    }

    @Test("Toda palavra latina, digitada sem acento no idioma da frase, e a primeira sugestao")
    func everyLatinWordIsFirst() throws {
        for language in WordLexicon.latin {
            for (position, word) in try WordlistStore.shared.wordlist(for: language).words.enumerated() {
                let typed = WordLexicon.fold(word)
                #expect(WordLexicon.completions(typed, preferring: [language]).first == word, "\(language) \(word)")
                // E as letras dela acendem no teclado, uma depois da outra (uma amostra: a
                // conta inteira leva minutos em depuracao).
                guard position % 16 == 0 else { continue }
                var prefix = ""
                for letter in typed {
                    #expect(WordLexicon.nextLetters(after: prefix, languages: [language]).contains(letter), "\(language) \(word) \(prefix)")
                    prefix.append(letter)
                }
            }
        }
    }

    @Test("A palavra exata vem antes das que so comecam assim, em qualquer idioma")
    func exactFirst() {
        #expect(WordLexicon.completions("act").first == "act")
        #expect(WordLexicon.completions("abaco").first == "abaco")
        #expect(WordLexicon.completions("abaco", preferring: [.spanish]).first == "ábaco")
        #expect(WordLexicon.completions("año").first == "año")
        #expect(WordLexicon.completions("ano", preferring: [.spanish]).first == "año")
    }

    @Test("O idioma das palavras ja fechadas vem primeiro, sem travar os outros")
    func languageOrder() {
        #expect(WordLexicon.languages(containing: []) == nil)
        let spanish = WordLexicon.languages(containing: [secure("abaco"), secure("abdomen")]) ?? []
        #expect(spanish.contains(.spanish))
        #expect(!spanish.contains(.english))
        // Uma primeira palavra no idioma errado nao some com as palavras dos outros: "zorro"
        // (espanhol) continua sugerido com o portugues preferido (segunda revisao, N1).
        #expect(WordLexicon.completions("zorro", preferring: [.portuguese]).contains("zorro"))
        #expect(WordLexicon.nextLetters(after: "zo").contains("r"))
    }

    @Test("A frase digitada sem acento volta a ser a do idioma em que fecha")
    func resolveFolded() throws {
        for language in [BIP39Language.spanish, .french, .czech, .portuguese, .italian] {
            for count in [12, 24] {
                let phrase = try Mnemonic.generate(wordCount: count, language: language)
                let typed = Mnemonic.words(in: phrase).map { secure(WordLexicon.fold($0)) }
                let resolved = try #require(WordLexicon.resolve(typed), "\(language) \(count)")
                defer { resolved.phrase.wipe() }
                #expect(resolved.language == language)
                let text = resolved.phrase.withUnsafeBytes { String(decoding: $0, as: UTF8.self) }
                #expect(text == Mnemonic.canonicalize(phrase))
            }
        }
        // Uma frase que nao fecha em idioma nenhum nao vira nada.
        #expect(WordLexicon.resolve(Array(repeating: secure("abaco"), count: 12)) == nil)
    }

    @Test("Frase colada: numeracao, virgula, marcador e quebra de linha separam; as palavras saem iguais em todo idioma")
    func pastedWords() throws {
        let twelve = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let expected = Mnemonic.words(in: twelve)
        let numbered = expected.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        #expect(Mnemonic.pastedWords(numbered) == expected)
        #expect(Mnemonic.pastedWords(expected.enumerated().map { "\($0.offset + 1)) \($0.element)" }.joined(separator: " ")) == expected)
        #expect(Mnemonic.pastedWords(expected.joined(separator: ", ")) == expected)
        #expect(Mnemonic.pastedWords(expected.map { "• \($0)" }.joined(separator: "\n")) == expected)
        #expect(Mnemonic.pastedWords("  " + expected.joined(separator: "\t").uppercased() + ".\n") == expected)
        for language in BIP39Language.allCases {
            let phrase = try Mnemonic.generate(wordCount: 24, language: language)
            let numberedPhrase = Mnemonic.words(in: phrase).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            #expect(Mnemonic.pastedWords(numberedPhrase) == Mnemonic.words(in: phrase), "\(language)")
        }
    }
}
