import Foundation
#if canImport(Security)
import Security
#endif

/// Quanto vale a senha de um envelope: quantos chutes um atacante gasta ate acerta-la,
/// contado sobre os bytes. Excecao: com um caractere fora do ASCII, a forma NFKC passa por
/// `String` (`KeyDerivation.normalized`), uma vez por medida.
///
/// **O modelo e o do zxcvbn** (Dropbox, e o zxcvbn-ts): o atacante nao testa letra por
/// letra, ele testa listas. A senha e quebrada nos pedacos mais baratos para ele, e o
/// custo e a soma dos pedacos:
///
/// - palavra ou senha comum: a posicao dela na lista de frequencia (Resources/Forca,
///   travadas em forca.lock), com maiusculas e trocas de letra por simbolo ("@" por
///   "a") somando pouco;
/// - palavra de qualquer lista BIP-39: no maximo 11 bits (2048 chutes);
/// - repeticao ("!!!!!!!!", "abandon abandon abandon"): o pedaco uma vez e a contagem;
/// - sequencia ("abcd", "4321"), ano, data e linha do teclado: quase nada;
/// - o resto, forca bruta pela classe de cada caractere.
///
/// O medidor antigo dava 11 bits a qualquer palavra BIP-39 mesmo repetida e 5 bits a
/// cada simbolo mesmo repetido: "!!!!!!!!!!!!" saia "forte" (auditoria do envelope,
/// 14/10/2026). Este erra para o lado do atacante.
///
/// A senha sorteada pelo proprio app nao passa por aqui: ela vale a entropia exata do
/// sorteio (`suggestionBits`).
public enum PasswordStrength {
    /// Acima disto, nem um Estado abre o envelope em tempo util. Abaixo, o lacre so sai
    /// com o "sim" explicito do dono (`Envelope.seal(acceptedRisk:)`).
    public static let minimumBits = 60.0
    /// O minimo absoluto de caracteres, escolha do dono (14/10/2026).
    public static let minimumLength = 4

    public enum Verdict: Equatable, Sendable {
        case strong
        /// Menos de `minimumLength` caracteres: nao lacra nem com o "sim".
        case tooShort
        /// So digitos: lacra com o "sim", mas a tela avisa para nao usar o PIN.
        case digitsOnly(bits: Double)
        case weak(bits: Double)
    }

    /// A medida inteira, com uma normalizacao so: quem precisa de mais de um numero chama esta.
    public struct Measure {
        public let scalars: Int
        public let bits: Double
        public let verdict: Verdict
        /// So digitos, de qualquer escrita: o aviso de PIN, sem medir de novo.
        public let digitsOnly: Bool
    }

    /// Mede as duas formas, a digitada e a que vai ao Argon2 (NFKC, `KeyDerivation.normalized`), e fica com a menor: quem
    /// ataca enumera qualquer uma delas. So a digitada dava "Forte" a "password12345678" em largura cheia; so a NFKC dava
    /// "Forte" a um caractere que se expande numa frase comum (U+FDFA, os quadrados do japones). Auditoria do envelope de
    /// 06/11/2026, rodadas 2 e 3.
    public static func measure(_ password: SecureBytes) -> Measure {
        let normalized = KeyDerivation.normalized(password)
        defer { if normalized !== password { normalized.wipe() } }
        let same = normalized === password
        let scalars = same ? scalarCountOf(password) : min(scalarCountOf(password), scalarCountOf(normalized))
        let rawBits = password.withUnsafeBytes { bits(bytes: $0) }
        var value = same ? rawBits : min(rawBits, normalized.withUnsafeBytes { bits(bytes: $0) })
        // Uma terceira forma: os digitos de outras escritas (arabe, persa, devanagari) em ASCII, que o NFKC nao dobra.
        // "١٢٣٤ ٥٦٧٨" e "1234 5678" para quem ataca (rodada 4 da auditoria do envelope).
        let digits = same ? nil : asciiDigits(normalized)
        defer { digits?.wipe() }
        if let digits { value = min(value, digits.withUnsafeBytes { bits(bytes: $0) }) }
        let onlyDigits = (digits ?? normalized).withUnsafeBytes { raw in raw.allSatisfy { (0x30...0x39).contains($0) } }
        let verdict: Verdict
        if scalars < minimumLength {
            verdict = .tooShort
        } else if value >= minimumBits {
            verdict = .strong
        } else {
            verdict = onlyDigits ? .digitsOnly(bits: value) : .weak(bits: value)
        }
        return Measure(scalars: scalars, bits: value, verdict: verdict, digitsOnly: onlyDigits && password.count > 0)
    }

    public static func verdict(_ password: SecureBytes) -> Verdict { measure(password).verdict }

    /// So digitos, de qualquer escrita, sem a medida inteira: o aviso de PIN da tela.
    public static func isDigitsOnly(_ password: SecureBytes) -> Bool {
        guard password.count > 0 else { return false }
        // Um byte ASCII que nao e digito decide sem normalizar: o NFKC nao muda o ASCII.
        if password.withUnsafeBytes({ raw in raw.contains { $0 < 0x80 && !(0x30...0x39).contains($0) } }) { return false }
        let normalized = KeyDerivation.normalized(password)
        defer { if normalized !== password { normalized.wipe() } }
        let digits = normalized === password ? nil : asciiDigits(normalized)
        defer { digits?.wipe() }
        return (digits ?? normalized).withUnsafeBytes { raw in raw.allSatisfy { (0x30...0x39).contains($0) } }
    }

    /// Os digitos decimais fora do ASCII trocados pelos ASCII, escalar a escalar, sem `String`. Nil quando nao ha nenhum.
    static func asciiDigits(_ text: SecureBytes) -> SecureBytes? {
        let out = SecureBytes(capacity: max(text.count, 1))
        var changed = false, valid = true
        text.withUnsafeBytes { raw in
            var bytes = raw.makeIterator()
            var parser = Unicode.UTF8.ForwardParser()
            while true {
                switch parser.parseScalar(from: &bytes) {
                case .valid(let encoded):
                    let scalar = Unicode.UTF8.decode(encoded)
                    if scalar.value >= 0x80, scalar.properties.numericType == .decimal,
                       let number = scalar.properties.numericValue, (0...9).contains(number) {
                        out.append(0x30 + UInt8(number))
                        changed = true
                    } else {
                        for byte in encoded { out.append(byte) }
                    }
                case .emptyInput:
                    return
                case .error:
                    valid = false
                    return
                }
            }
        }
        if changed && valid { return out }
        out.wipe()
        return nil
    }

    /// Caracteres, contados como escalares Unicode (o primeiro byte de cada um em UTF-8), o menor das duas formas.
    public static func scalarCount(_ password: SecureBytes) -> Int {
        let normalized = KeyDerivation.normalized(password)
        defer { if normalized !== password { normalized.wipe() } }
        return normalized === password ? scalarCountOf(password) : min(scalarCountOf(password), scalarCountOf(normalized))
    }

    static func scalarCountOf(_ password: SecureBytes) -> Int {
        password.withUnsafeBytes { raw in raw.reduce(0) { $0 + ($1 & 0xC0 == 0x80 ? 0 : 1) } }
    }

    /// A entropia exata de `count` palavras sorteadas pelo app de uma lista de 2048.
    public static func suggestionBits(count: Int = 6) -> Double { Double(count) * 11 }

    /// log2 do numero de chutes.
    public static func bits(_ password: SecureBytes) -> Double { measure(password).bits }

    /// Carrega as listas antes de a primeira tecla precisar delas.
    public static func preload() { _ = Dictionaries.ranks }

    // MARK: Estimativa

    static func bits(bytes raw: UnsafeRawBufferPointer) -> Double {
        let count = min(raw.count, 256)
        guard count > 0 else { return 0 }
        var original = [UInt8](raw.prefix(count))
        var folded = foldBytes(original)
        defer {
            wipe(&original)
            wipe(&folded)
        }
        let estimator = Estimator(original: original, folded: folded)
        return estimator.segment(0, count)
    }

    /// Uma estimativa: guarda o custo de cada trecho ja medido, para cada pedaco da senha
    /// ser medido uma vez so (a repeticao mede a unidade, que tambem e um trecho).
    final class Estimator {
        let original: [UInt8]
        let folded: [UInt8]
        /// Os custos ja medidos, em arrays planos do tamanho certo (NaN: nao medido; infinito: nao e padrao), zerados ao
        /// sair. Um Dictionary deixava no heap, sem zerar, o log2 da posicao de cada palavra nas listas publicas, e as
        /// tabelas velhas a cada crescimento (rodada 4 da auditoria do envelope de 06/11/2026).
        private var segments: [Double]
        private var patterns: [Double]
        static let segmentWidth = 25
        static let patternWidth = 97

        /// O custo de cada byte tentado por forca bruta. Um simbolo ASCII que ja apareceu antes custa 0: e o separador
        /// que quem ataca fixa na mascara ("casa-azul-gato", "a_b_c"), e nao uma escolha nova a cada vez (auditoria do
        /// envelope de 06/11/2026).
        private(set) var cost: [Double]
        /// O fim de um separador entre letras (um digito so, ou de 2 a 4 caracteres que se repetem): juntar os pedacos em
        /// volta dele nao custa o bit de juncao.
        private(set) var separator: [Bool]

        init(original: [UInt8], folded: [UInt8]) {
            self.original = original
            self.folded = folded
            segments = [Double](repeating: .nan, count: max(original.count, 1) * Self.segmentWidth)
            patterns = [Double](repeating: .nan, count: max(original.count, 1) * Self.patternWidth)
            // Os simbolos ja vistos numa mascara de 128 bits, sem Set: nada da senha fica em memoria que nao se zera. Um digito
            // entre duas letras ("Casa1Azul1Gato") tambem e separador da mascara (rodada 3 da auditoria do envelope).
            var seenLow: UInt64 = 0, seenHigh: UInt64 = 0
            var separators = [Bool](repeating: false, count: original.count)
            var costs = [Double](repeating: 0, count: original.count)
            for index in original.indices {
                let byte = original[index]
                let digit = (0x30...0x39).contains(byte)
                let between = index > 0 && index + 1 < original.count
                    && PasswordStrength.isLetter(original[index - 1]) && PasswordStrength.isLetter(original[index + 1])
                let symbol = byte < 0x80 && !PasswordStrength.isLetter(byte) && byte != 0x20 && (!digit || between)
                separators[index] = digit && between
                guard symbol else {
                    costs[index] = PasswordStrength.bruteBits(byte)
                    continue
                }
                let bit: UInt64 = 1 << UInt64(byte & 63)
                let seen = byte < 64 ? seenLow & bit != 0 : seenHigh & bit != 0
                if byte < 64 { seenLow |= bit } else { seenHigh |= bit }
                costs[index] = seen ? 0 : PasswordStrength.bruteBits(byte)
            }
            // O separador de 2 a 4 caracteres entre letras que ja apareceu antes ("Gato12Casa12", "gato#1casa#1") sai de
            // graca na repeticao, como o de um caractere (rodada 4). Comparado no proprio array, sem copia.
            // Com espaco dentro tambem (" 26 ", " - "): o espaco ja e de graca, e o que ele cerca se repete igual.
            func separatorByte(_ byte: UInt8) -> Bool { byte >= 0x20 && byte < 0x7F && !PasswordStrength.isLetter(byte) }
            var index = 1
            while index < original.count {
                guard PasswordStrength.isLetter(original[index - 1]), separatorByte(original[index]) else {
                    index += 1
                    continue
                }
                var end = index
                while end < original.count, separatorByte(original[end]) { end += 1 }
                let width = end - index
                if width >= 2, width <= 4, end < original.count, PasswordStrength.isLetter(original[end]) {
                    var earlier = 1, repeated = false
                    while !repeated, earlier + width < index {
                        repeated = PasswordStrength.isLetter(original[earlier - 1]) && PasswordStrength.isLetter(original[earlier + width])
                            && original[earlier..<(earlier + width)].elementsEqual(original[index..<end])
                        earlier += 1
                    }
                    if repeated {
                        for position in index..<end { costs[position] = 0 }
                        separators[end - 1] = true
                    }
                }
                index = end
            }
            cost = costs
            separator = separators
        }

        /// A mascara de classes por posicao e os custos guardados sao pistas da senha para quem ler o heap: zerados ao sair.
        deinit {
            cost.withUnsafeMutableBytes { if let base = $0.baseAddress { memset_s(base, $0.count, 0, $0.count) } }
            separator.withUnsafeMutableBytes { if let base = $0.baseAddress { memset_s(base, $0.count, 0, $0.count) } }
            segments.withUnsafeMutableBytes { if let base = $0.baseAddress { memset_s(base, $0.count, 0, $0.count) } }
            patterns.withUnsafeMutableBytes { if let base = $0.baseAddress { memset_s(base, $0.count, 0, $0.count) } }
        }

        func segment(_ from: Int, _ to: Int) -> Double {
            let width = to - from
            guard width > 0, width < Self.segmentWidth else { return PasswordStrength.segmentBits(self, from, to) }
            let slot = from * Self.segmentWidth + width
            if !segments[slot].isNaN { return segments[slot] }
            let value = PasswordStrength.segmentBits(self, from, to)
            segments[slot] = value
            return value
        }

        func pattern(_ start: Int, _ end: Int) -> Double? {
            let width = end - start
            guard width > 0, width < Self.patternWidth else { return PasswordStrength.patternBits(self, start, end) }
            let slot = start * Self.patternWidth + width
            if !patterns[slot].isNaN { return patterns[slot].isInfinite ? nil : patterns[slot] }
            let value = PasswordStrength.patternBits(self, start, end)
            patterns[slot] = value ?? .infinity
            return value
        }
    }

    /// O menor custo de i..<j, quebrando em pedacos: cada pedaco e um padrao conhecido ou
    /// forca bruta. Programacao dinamica sobre as posicoes, como o zxcvbn.
    static func segmentBits(_ estimator: Estimator, _ from: Int, _ to: Int) -> Double {
        let original = estimator.original
        guard to > from else { return 0 }
        // Forca bruta acumulada: brute[j] - brute[i] e o custo de i..<j caractere a caractere.
        var brute = [Double](repeating: 0, count: to - from + 1)
        // A forca bruta acumulada e a mascara de classes somada: zerada ao sair, como o melhor custo (rodada 4).
        defer { brute.withUnsafeMutableBytes { if let base = $0.baseAddress { memset_s(base, $0.count, 0, $0.count) } } }
        for index in from..<to { brute[index - from + 1] = brute[index - from] + estimator.cost[index] }
        // best[j]: o menor custo para os bytes de `from` ate `from + j`.
        var best = [Double](repeating: .infinity, count: to - from + 1)
        defer { best.withUnsafeMutableBytes { if let base = $0.baseAddress { memset_s(base, $0.count, 0, $0.count) } } }
        best[0] = 0
        for end in (from + 1)...to {
            for start in from..<end {
                guard best[start - from].isFinite else { continue }
                let bruteCost = brute[end - from] - brute[start - from]
                var cost = bruteCost
                if let pattern = estimator.pattern(start, end) {
                    // Juntar pedacos de tipos diferentes custa 1 bit a mais ao atacante.
                    let joined = start > from && !isSeparator(original[start - 1]) && !estimator.separator[start - 1]
                    cost = min(bruteCost, pattern + (joined ? 1 : 0))
                }
                best[end - from] = min(best[end - from], best[start - from] + cost)
            }
        }
        return best[to - from]
    }

    /// O menor custo de i..<j como um padrao conhecido; `nil` se nao e padrao.
    static func patternBits(_ estimator: Estimator, _ start: Int, _ end: Int) -> Double? {
        let original = estimator.original
        let folded = estimator.folded
        let length = end - start
        var found: Double?
        func keep(_ value: Double) { found = min(found ?? .infinity, value) }

        // Palavra ou senha conhecida, com maiusculas e trocas de letra por simbolo.
        if length <= Dictionaries.maxLength {
            var token = Array(folded[start..<end])
            defer { wipe(&token) }
            if let rank = Dictionaries.ranks[token] {
                keep(log2(Double(max(rank, 1))) + uppercaseBits(original, start, end))
            }
            var plain = token.map { leet[$0] ?? $0 }
            defer { wipe(&plain) }
            if plain != token, let rank = Dictionaries.ranks[plain] {
                let swapped = zip(token, plain).reduce(0) { $0 + ($1.0 != $1.1 ? 1 : 0) }
                keep(log2(Double(max(rank, 1))) + uppercaseBits(original, start, end) + Double(max(swapped, 1)))
            }
            // A palavra de tras para frente: a regra de inversao e das primeiras que quem ataca roda.
            // Por escalar, e nao por byte: "oãçaroc" e "coração" de tras para frente (rodada 3).
            var reversed = [UInt8]()
            reversed.reserveCapacity(token.count)
            var cut = token.count
            for index in stride(from: token.count - 1, through: 0, by: -1) where token[index] & 0xC0 != 0x80 {
                reversed.append(contentsOf: token[index..<cut])
                cut = index
            }
            defer { wipe(&reversed) }
            if reversed != token, let rank = Dictionaries.ranks[reversed] {
                keep(log2(Double(max(rank, 1))) + uppercaseBits(original, start, end) + 1)
            }
        }
        // Uma palavra de outra lingua, um nome proprio ou um trecho em outro alfabeto, que as listas nao tem: quem ataca
        // escolhe a lingua do dono e usa a lista dela, da ordem de 10^5 palavras. Um trecho so de letras, de 6 a 64 bytes,
        // custa no maximo isso, e nao as letras uma a uma (auditoria do envelope de 06/11/2026, rodadas 2 e 3): tres
        // palavras pedem o "sim", quatro passam. Letras sorteadas tambem caem aqui: o medidor erra para o lado do "sim".
        // Com letras trocadas por digito ou simbolo ("Kuehlschr4nk"), a mesma palavra mais 1 bit por troca (rodada 3).
        // A partir de 4 bytes: com o teto da lista, 5 letras custavam mais que 6 (rodada 4).
        if length >= 4, length <= 64,
           (start..<end).allSatisfy({ original[$0] >= 0x80 || isLetter(leet[folded[$0]] ?? folded[$0]) }) {
            var swapped = 0
            var kinds: UInt64 = 0, targets: UInt32 = 0
            for index in start..<end {
                guard let letter = leet[folded[index]] else { continue }
                swapped += 1
                kinds |= 1 << UInt64(folded[index] & 63)
                targets |= 1 << UInt32(letter - 0x61)
            }
            // Troca solta: no maximo uma a cada cinco letras, 1 bit cada. Mais que isso e trecho sorteado com simbolos.
            if swapped * 5 <= length {
                keep(log2(1e5) + uppercaseBits(original, start, end) + Double(swapped))
            }
            // Troca como regra, como o hashcat aplica ("e" vira "3" na palavra inteira): 1 bit por tipo de troca, quando
            // nenhuma letra trocada ficou sem trocar no trecho, e so de 8 bytes para cima (rodada 4).
            let consistent = !(start..<end).contains { index in
                (0x61...0x7A).contains(folded[index]) && targets & (1 << UInt32(folded[index] - 0x61)) != 0
            }
            if length >= 8, swapped > 0, consistent {
                keep(log2(1e5) + uppercaseBits(original, start, end) + Double(kinds.nonzeroBitCount))
            }
        }
        // Repeticao de um pedaco (com a ultima repeticao podendo perder o separador final).
        if length >= 2, length <= 96 {
            for unit in 1...min(length / 2 + 1, 24) where unit < length {
                guard length >= 2 * unit - 1, folded[start + unit] == folded[start] else { continue }
                var same = true
                for index in start..<end where folded[index] != folded[start + (index - start) % unit] {
                    same = false
                    break
                }
                guard same else { continue }
                let times = Double((length + unit - 1) / unit)
                // A unidade pelo melhor jeito (palavra mais espaco, por exemplo), uma vez.
                keep(estimator.segment(start, start + unit) + log2(times))
            }
        }
        // Sequencia: letras ou digitos seguidos, subindo ou descendo.
        if length >= 3, let step = sequenceStep(folded, start, end) {
            let first = folded[start]
            let obvious: Set<UInt8> = [0x61, 0x7A, 0x30, 0x31, 0x39]  // a, z, 0, 1, 9
            let starts = obvious.contains(first) ? 4.0 : ((0x30...0x39).contains(first) ? 10.0 : 26.0)
            keep(log2(starts) + log2(Double(length)) + (step < 0 ? 1 : 0))
        }
        // Ano e data.
        if let year = Self.year(folded, start, end) {
            keep(log2(Double(max(abs(year - referenceYear), 20))))
        }
        if let year = Self.date(folded, start, end) {
            keep(log2(365 * Double(max(abs(year - referenceYear), 20))))
        }
        // Linha do teclado.
        if length >= 4 {
            let slice = folded[start..<end]
            let onRow = keyboardRows.contains { row in
                row.count >= length && (0...(row.count - length)).contains { row[$0..<($0 + length)].elementsEqual(slice) }
            }
            if onRow { keep(log2(Double(length) * 50)) }
        }
        return found
    }

    static let referenceYear = 2026

    static func bruteRun(_ original: [UInt8], _ start: Int, _ end: Int) -> Double {
        (start..<end).reduce(0) { $0 + bruteBits(original[$1]) }
    }

    /// Bits de um caractere tentado por forca bruta, pela classe dele.
    static func bruteBits(_ byte: UInt8) -> Double {
        switch byte {
        case 0x61...0x7A, 0x41...0x5A: return 4.7      // 26 letras
        case 0x30...0x39: return 3.32                  // 10 digitos
        case 0x20: return 0                            // o separador obvio de uma frase
        case 0x80...0xBF: return 0                     // continuacao de um caractere UTF-8
        case 0xC0...0xFF: return 6.64                  // um caractere fora do ASCII
        default: return 5.04                           // 33 simbolos
        }
    }

    static func isSeparator(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x2D || byte == 0x5F || byte == 0x2E }

    /// Minusculas, no ASCII e nas letras latinas com acento (UTF-8 C3 80 a C3 9E).
    static func fold(_ byte: UInt8) -> UInt8 {
        (0x41...0x5A).contains(byte) ? byte + 0x20 : byte
    }

    /// As letras com acento em maiuscula viram minuscula no segundo byte.
    static func foldBytes(_ bytes: [UInt8]) -> [UInt8] {
        var out = bytes.map(fold)
        var index = 0
        while index + 1 < out.count {
            if out[index] == 0xC3, (0x80...0x9E).contains(out[index + 1]), out[index + 1] != 0x97 { out[index + 1] += 0x20 }
            index += 1
        }
        return out
    }

    /// Maiusculas numa palavra: nenhuma, a primeira ou todas custam 1 bit; misturadas,
    /// o numero de jeitos de escolher quais.
    static func uppercaseBits(_ original: [UInt8], _ start: Int, _ end: Int) -> Double {
        var upper = 0
        var lower = 0
        for index in start..<end {
            if (0x41...0x5A).contains(original[index]) { upper += 1 } else if (0x61...0x7A).contains(original[index]) { lower += 1 }
        }
        guard upper > 0 else { return 0 }
        let firstOnly = upper == 1 && (0x41...0x5A).contains(original[start])
        if firstOnly || lower == 0 { return 1 }
        var ways = 0.0
        for chosen in 1...min(upper, lower) { ways += combinations(upper + lower, chosen) }
        return log2(max(ways, 2))
    }

    static func combinations(_ n: Int, _ k: Int) -> Double {
        guard k >= 0, k <= n else { return 0 }
        var result = 1.0
        for index in 0..<k { result = result * Double(n - index) / Double(index + 1) }
        return result
    }

    /// Trocas comuns de letra por digito ou simbolo, desfeitas.
    static let leet: [UInt8: UInt8] = [
        0x34: 0x61, 0x40: 0x61, 0x33: 0x65, 0x31: 0x69, 0x21: 0x69, 0x30: 0x6F,
        0x24: 0x73, 0x35: 0x73, 0x37: 0x74, 0x38: 0x62, 0x39: 0x67,
    ]

    static func sequenceStep(_ folded: [UInt8], _ start: Int, _ end: Int) -> Int? {
        let step = Int(folded[start + 1]) - Int(folded[start])
        guard abs(step) == 1 else { return nil }
        let letters = (0x61...0x7A), digits = (0x30...0x39)
        let inLetters = letters.contains(Int(folded[start])), inDigits = digits.contains(Int(folded[start]))
        guard inLetters || inDigits else { return nil }
        for index in (start + 1)..<end {
            guard Int(folded[index]) - Int(folded[index - 1]) == step,
                  inLetters ? letters.contains(Int(folded[index])) : digits.contains(Int(folded[index]))
            else { return nil }
        }
        return step
    }

    static func number(_ bytes: [UInt8], _ start: Int, _ end: Int) -> Int? {
        guard end > start, (start..<end).allSatisfy({ (0x30...0x39).contains(bytes[$0]) }) else { return nil }
        return (start..<end).reduce(0) { $0 * 10 + Int(bytes[$1] - 0x30) }
    }

    static func year(_ bytes: [UInt8], _ start: Int, _ end: Int) -> Int? {
        guard end - start == 4, let value = number(bytes, start, end), (1900...2099).contains(value) else { return nil }
        return value
    }

    /// ddmmaaaa, aaaammdd e ddmmaa: devolve o ano.
    static func date(_ bytes: [UInt8], _ start: Int, _ end: Int) -> Int? {
        let length = end - start
        guard length == 6 || length == 8, number(bytes, start, end) != nil else { return nil }
        func valid(day: Int, month: Int) -> Bool { (1...31).contains(day) && (1...12).contains(month) }
        if length == 8 {
            if let day = number(bytes, start, start + 2), let month = number(bytes, start + 2, start + 4),
               let year = year(bytes, start + 4, end), valid(day: day, month: month) { return year }
            if let year = year(bytes, start, start + 4), let month = number(bytes, start + 4, start + 6),
               let day = number(bytes, start + 6, end), valid(day: day, month: month) { return year }
            return nil
        }
        guard let day = number(bytes, start, start + 2), let month = number(bytes, start + 2, start + 4),
              let short = number(bytes, start + 4, end), valid(day: day, month: month) else { return nil }
        return short < 50 ? 2000 + short : 1900 + short
    }

    /// As linhas e diagonais do teclado do computador, com e sem Shift, e a pagina de numeros e simbolos do celular, onde esta
    /// senha e digitada (iPhone e Gboard), nos dois sentidos: "!@#$%^&*()_+", "-/:;()$&@" e "+_)(*&^%$#@!" sao caminhadas de
    /// lista de vazamento (rodada 5 da auditoria do envelope).
    static let keyboardRows: [[UInt8]] = {
        let rows = [
            "`1234567890-=", "~!@#$%^&*()_+", "1!2@3#4$5%6^7&8*9(0)-_=+",
            "qwertyuiop[]\\", "qwertyuiop{}|", "asdfghjkl;'", "asdfghjkl:\"", "zxcvbnm,./", "zxcvbnm<>?", "qazwsxedc",
            "1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik,9ol.0p;/", "!qaz@wsx#edc$rfv%tgb^yhn&ujm*ik<(ol>)p:?",
            "-/:;()$&@\"", ".,?!'", "[]{}#%^*+=", "_\\|~<>", "@#$_&-+()/", "*\"':;!?",
        ]
        return rows.flatMap { [Array($0.utf8), Array($0.utf8.reversed())] }
    }()

    /// As listas: a menor posicao de cada palavra entre todas, e as palavras BIP-39 de
    /// todos os idiomas com no maximo 2048.
    enum Dictionaries {
        static let maxLength = 32
        static let files = ["senhas-comuns", "pt-palavras", "pt-nomes", "pt-sobrenomes", "pt-wikipedia", "en-palavras", "en-nomes", "en-wikipedia"]

        static let ranks: [[UInt8]: Int32] = {
            var out: [[UInt8]: Int32] = [:]
            out.reserveCapacity(260_000)
            let bundle = CoreResources.bundle
            for name in files {
                guard let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: "Forca")
                        ?? bundle.url(forResource: name, withExtension: "txt"),
                      let data = try? Data(contentsOf: url) else { continue }
                var rank: Int32 = 0
                var start = data.startIndex
                for index in data.indices where data[index] == 0x0A {
                    defer { start = index + 1 }
                    guard index > start, index - start <= maxLength else { continue }
                    rank += 1
                    let word = foldBytes(Array(data[start..<index]))
                    if let known = out[word], known <= rank { continue }
                    out[word] = rank
                }
            }
            for language in BIP39Language.allCases {
                guard let list = try? WordlistStore.shared.wordlist(for: language) else { continue }
                for word in list.words {
                    let key = foldBytes(Array(word.utf8))
                    if let known = out[key], known <= 2048 { continue }
                    out[key] = 2048
                }
            }
            return out
        }()
    }

    // MARK: Sugestao e reuso da frase

    static func isLetter(_ byte: UInt8) -> Bool {
        (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }

    static func wipe(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { if let base = $0.baseAddress { memset_s(base, $0.count, 0, $0.count) } }
    }

    /// Seis palavras BIP-39 sorteadas: 66 bits. Nenhuma pode estar na frase da
    /// propria carteira, para o papel da frase nunca abrir o envelope. Devolve as
    /// posicoes na lista inglesa: quem mostra monta o texto, quem lacra monta os bytes.
    public static func suggestionIndices(avoiding phrase: SecureBytes?, count: Int = 6) throws -> [Int] {
        let list = try WordlistStore.shared.wordlist(for: .english)
        var avoid = Set<Int>()
        if let phrase {
            phrase.withUnsafeBytes { raw in
                var token = [UInt8]()
                defer { wipe(&token) }
                func close() {
                    if !token.isEmpty, let position = list.position(of: String(decoding: token, as: UTF8.self)) { avoid.insert(Int(position)) }
                    wipe(&token)
                    token.removeAll(keepingCapacity: true)
                }
                // Sem copiar a frase inteira para fechar a ultima palavra (auditoria, A3).
                for byte in raw {
                    if byte == 0x20 { close() } else { token.append(byte) }
                }
                close()
            }
        }
        var chosen: [Int] = []
        while chosen.count < count {
            var bytes = [UInt8](repeating: 0, count: 2)
            guard SecRandomCopyBytes(kSecRandomDefault, 2, &bytes) == errSecSuccess else { throw CryptoError.randomnessUnavailable }
            // 2048 divide 65536: pegar 11 bits de 16 nao tem vies.
            let index = (Int(bytes[0]) << 8 | Int(bytes[1])) & 0x7FF
            if !avoid.contains(index), !chosen.contains(index) { chosen.append(index) }
        }
        return chosen
    }

    /// As palavras sorteadas como texto, para a tela.
    public static func suggestion(avoiding phrase: SecureBytes?, count: Int = 6) throws -> [String] {
        let list = try WordlistStore.shared.wordlist(for: .english)
        return try suggestionIndices(avoiding: phrase, count: count).map { list.words[$0] }
    }

    /// As palavras sorteadas direto num buffer seguro, separadas por espaco.
    public static func write(_ indices: [Int], into buffer: SecureBytes) throws {
        let list = try WordlistStore.shared.wordlist(for: .english)
        buffer.reset()
        for (position, index) in indices.enumerated() {
            if position > 0 { buffer.append(0x20) }
            var bytes = Array(list.words[index].utf8)
            bytes.withUnsafeBufferPointer { buffer.append(contentsOf: $0) }
            wipe(&bytes)
        }
    }

    /// A senha usa duas ou mais palavras da propria frase? Quem achar o papel da
    /// frase teria meio caminho andado.
    public static func reusesPhrase(_ password: SecureBytes, phrase: SecureBytes) -> Bool {
        // As duas na forma da frase (NFKD canonica): em largura cheia, "ａｂａｎｄｏｎ" e "abandon"; uma palavra com acento ou
        // de outro alfabeto continua uma palavra so. A frase se corta so no espaco, a forma canonica; a senha, em qualquer
        // byte ASCII que nao e letra (rodada 4 da auditoria do envelope). Cada palavra num array do tamanho certo, que
        // nunca realoca, e nada de Set: ele seguraria copias que o wipe nao alcanca.
        func tokens(_ secret: SecureBytes, onlySpace: Bool) -> [[UInt8]] {
            secret.withUnsafeBytes { raw in
                var out: [[UInt8]] = []
                out.reserveCapacity(raw.count / 2 + 1)
                var start = 0, index = 0
                func close(_ end: Int) {
                    guard end > start else { return }
                    var token = [UInt8]()
                    token.reserveCapacity(end - start)
                    for byte in raw[start..<end] { token.append((0x41...0x5A).contains(byte) ? byte + 0x20 : byte) }
                    out.append(token)
                }
                // Escalar a escalar: fora do ASCII, corta no que nao e letra nem marca (travessao, ponto do meio, emoji,
                // a virgula ideografica), como cortava antes (rodada 5 da auditoria do envelope).
                while index < raw.count {
                    let lead = raw[index]
                    let next = min(index + (lead < 0x80 ? 1 : lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : 2), raw.count)
                    let cut: Bool
                    if onlySpace {
                        cut = lead == 0x20
                    } else if lead < 0x80 {
                        cut = !isLetter(lead)
                    } else {
                        var bytes = UnsafeRawBufferPointer(rebasing: raw[index..<next]).makeIterator()
                        var parser = Unicode.UTF8.ForwardParser()
                        if case .valid(let encoded) = parser.parseScalar(from: &bytes) {
                            let properties = Unicode.UTF8.decode(encoded).properties
                            switch properties.generalCategory {
                            case .nonspacingMark, .spacingMark, .enclosingMark: cut = false
                            default: cut = !properties.isAlphabetic
                            }
                        } else {
                            cut = true
                        }
                    }
                    if cut {
                        close(index)
                        start = next
                    }
                    index = next
                }
                close(raw.count)
                return out
            }
        }
        let typedForm = BIP39.nfkd(password)
        defer { typedForm.wipe() }
        var typed = tokens(typedForm, onlySpace: false)
        var words = tokens(phrase, onlySpace: true)
        defer {
            for index in typed.indices { wipe(&typed[index]) }
            for index in words.indices { wipe(&words[index]) }
        }
        var reused = 0
        for token in typed where words.contains(where: { $0 == token }) { reused += 1 }
        return reused >= 2
    }
}
