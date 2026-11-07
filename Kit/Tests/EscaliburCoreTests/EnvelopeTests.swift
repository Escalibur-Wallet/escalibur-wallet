import Foundation
import Testing
@testable import EscaliburCore

/// O envelope precisa abrir nos dois sentidos: o que a carteira lacra abre no
/// Escalibur e no decifrador de referencia, e o que eles lacram abre aqui.
@Suite("Envelope Escalibur")
struct EnvelopeTests {
    /// Parametros minimos aceitos pelo formato, para o teste nao levar segundos.
    static let fast = KDFParameters(memoryKiB: 64 * 1024, passes: 2, lanes: 1)
    static let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

    static func secure(_ text: String) -> SecureBytes {
        let bytes = SecureBytes(capacity: max(text.utf8.count, 1))
        bytes.replaceAll(with: Array(text.utf8))
        return bytes
    }

    @Test("Ida e volta, senha errada sem mensagem distinta, tamanho constante")
    func roundTrip() throws {
        let data = try Envelope.seal(
            phrase: BIP39.canonical(Self.phrase), label: "Principal",
            password: Self.secure(Self.strong), parameters: Self.fast
        )
        #expect(data.count == 16_504)
        #expect(Envelope.looksLikeEnvelope(data))
        let opened = try Envelope.open(data, password: Self.secure(Self.strong))
        #expect(opened.phrase.withUnsafeBytes { String(decoding: $0, as: UTF8.self) } == Self.phrase)
        #expect(opened.label == "Principal")
        #expect(opened.passphrase.count == 0)
        #expect(throws: Envelope.Failure.cannotOpen) {
            try Envelope.open(data, password: Self.secure("senha errada"))
        }
    }

    @Test("Qualquer byte do cabecalho trocado, ou os compartimentos fora de lugar, nao abre")
    func tamperedHeader() throws {
        let data = try Envelope.seal(
            phrase: BIP39.canonical(Self.phrase), label: "Principal",
            password: Self.secure(Self.strong), parameters: Self.fast
        )
        // UUID, m (o byte baixo), t (o byte baixo), p, sal, vinculo, reservado, chave do vinculo, nuvem e o ultimo
        // reservado: cada um entra no AAD das duas camadas ou muda a propria chave (auditoria do envelope de 06/11/2026).
        // Recusa igual a senha errada: adulterar e errar a senha continuam indistinguiveis (rodada 3).
        for offset in [8, 28, 32, 34, 51, 52, 117, 119] {
            var forged = data
            forged[offset] ^= 0x01
            #expect(throws: Envelope.Failure.cannotOpen, "byte \(offset)") { try Envelope.open(forged, password: Self.secure(Self.strong)) }
        }
        // p = 0 nao e envelope; o vinculo ao aparelho tem recusa propria, antes de qualquer derivacao.
        var noLanes = data
        noLanes[33] ^= 0x01
        #expect(throws: Envelope.Failure.notAnEnvelope) { try Envelope.open(noLanes, password: Self.secure(Self.strong)) }
        var bound = data
        bound[50] ^= 0x01
        #expect(throws: Envelope.Failure.boundToDevice) { try Envelope.open(bound, password: Self.secure(Self.strong)) }
        // Os quatro compartimentos girados uma posicao: o que a senha abre muda de lugar, e a posicao esta no AAD.
        let header = data.prefix(VaultFormat.headerLength)
        let slots = (0..<VaultFormat.slotCount).map { index in
            data[(VaultFormat.headerLength + index * VaultFormat.slotLength)..<(VaultFormat.headerLength + (index + 1) * VaultFormat.slotLength)]
        }
        var rotated = Data(header)
        for index in 0..<VaultFormat.slotCount { rotated += slots[(index + 1) % VaultFormat.slotCount] }
        #expect(rotated.count == data.count)
        #expect(throws: Envelope.Failure.cannotOpen) { try Envelope.open(rotated, password: Self.secure(Self.strong)) }
    }

    /// Seis palavras da lista: 66 bits, acima do piso de lacre.
    static let strong = "crane violin orbit maple harbor tunnel"

    @Test("Senha abaixo do piso so lacra com o sim; abaixo de 4 caracteres, nunca")
    func weakPasswordRefused() throws {
        #expect(throws: Envelope.Failure.weakPassword) {
            try Envelope.seal(phrase: BIP39.canonical(Self.phrase), label: "x", password: Self.secure("senha longa de teste"), parameters: Self.fast)
        }
        #expect(throws: Envelope.Failure.weakPassword) {
            try Envelope.seal(phrase: BIP39.canonical(Self.phrase), label: "x", password: Self.secure("12345678"), parameters: Self.fast)
        }
        #expect(throws: Envelope.Failure.weakPassword) {
            try Envelope.seal(phrase: BIP39.canonical(Self.phrase), label: "x", password: Self.secure("123"), parameters: Self.fast,
                              acceptedRisk: true)
        }
        // Com o "sim" da tela, a senha do dono lacra e abre.
        let data = try Envelope.seal(phrase: BIP39.canonical(Self.phrase), label: "x", password: Self.secure("4821"), parameters: Self.fast,
                                     acceptedRisk: true)
        let opened = try Envelope.open(data, password: Self.secure("4821"))
        opened.wipe()
        // A sugestao do app vale a entropia do sorteio, mesmo com palavras comuns.
        _ = try Envelope.seal(phrase: BIP39.canonical(Self.phrase), label: "x", password: Self.secure("about above actor apple arena ocean"),
                              parameters: Self.fast, generatedBits: PasswordStrength.suggestionBits())
    }

    @Test("Nenhum envelope nasce abaixo de 256 MiB, mesmo pedindo menos")
    func sealFloor() throws {
        let weak = KDFParameters(memoryKiB: 64 * 1024, passes: 2, lanes: 1)
        let data = try Envelope.seal(
            phrase: BIP39.canonical(Self.phrase), label: "Principal",
            password: Self.secure(Self.strong), parameters: weak
        )
        let header = try Envelope.inspect(data)
        #expect(header.kdf.memoryKiB >= KDFCalibration.sealFloorKiB)
        #expect(KDFCalibration.calibrate().memoryKiB >= KDFCalibration.sealFloorKiB)
    }

    @Test("Regressao C7-16: o idioma em disco e um codigo fixo, o mesmo do decifrar.py; codigo desconhecido nao vira idioma")
    func languageStorageCodes() {
        // `IDIOMAS` no tools/referencia/decifrar.py, nesta ordem, de 0 a 9.
        let reference = [
            "english", "japanese", "chinese_simplified", "chinese_traditional", "french",
            "italian", "korean", "spanish", "czech", "portuguese",
        ]
        #expect(BIP39Language.allCases.count == reference.count)
        for (code, name) in reference.enumerated() {
            let language = BIP39Language(rawValue: name)
            #expect(language?.storageCode == UInt8(code), "\(name)")
            #expect(BIP39Language(storageCode: UInt8(code)) == language, "\(name)")
        }
        for code in [10, 11, 127, 255] as [UInt8] {
            #expect(BIP39Language(storageCode: code) == nil)
        }
    }

    @Test("Regressao C7-16: frase em japones grava o codigo 1 e abre em japones; codigo desconhecido recusa")
    func languageInEnvelopeBlock() throws {
        let phrase = try Mnemonic.generate(wordCount: 12, language: .japanese)
        let sealing = SealingContents(
            mnemonic: Self.secure(Mnemonic.canonicalize(phrase)), passphrase: SecureBytes(capacity: 1),
            label: "", notes: "", language: .japanese, kind: .bip39
        )
        var block = try sealing.encoded()
        #expect(block[2] == 1)
        let opened = try Envelope.decode(Self.block(block))
        #expect(opened.language == .japanese)
        opened.wipe()
        block[2] = 10
        #expect(throws: Envelope.Failure.unknownLanguage) { try Envelope.decode(Self.block(block)) }
    }

    static func block(_ bytes: [UInt8]) -> SecureBytes {
        let out = SecureBytes(capacity: bytes.count)
        out.replaceAll(with: bytes)
        return out
    }

    @Test("Regressao C7-14: a sonda da calibracao deriva de verdade e mede mais que zero")
    func calibrationProbeMeasures() throws {
        // Com 1 passe a derivacao recusava, a medida dava zero e a calibracao escolhia
        // sempre o maximo. A sonda tem de estar na faixa aceita e rodar sem erro.
        #expect(KDFCalibration.probeParameters.isWithinAcceptedRange)
        let unitCost = try KDFCalibration.probeUnitCost()
        #expect(unitCost > 0)
    }

    @Test("Envelope de referencia, conferido pelo decifrar.py do Escalibur")
    func referenceFixture() throws {
        guard let url = Bundle.module.url(forResource: "interop", withExtension: "esclbr", subdirectory: "Fixtures") else {
            Issue.record("fixture ausente")
            return
        }
        let data = try Data(contentsOf: url)
        let opened = try Envelope.open(data, password: Self.secure("cavalo correto bateria grampo"))
        #expect(opened.phrase.withUnsafeBytes { String(decoding: $0, as: UTF8.self) } == Self.phrase)
        #expect(opened.label == "Interoperabilidade")
    }

    @Test("Envelope lacrado por implementacao independente (tools/lacrar-referencia.py)")
    func independentSealer() throws {
        let url = try #require(Bundle.module.url(forResource: "referencia-python", withExtension: "esclbr", subdirectory: "Fixtures"))
        let opened = try Envelope.open(try Data(contentsOf: url), password: Self.secure("senha de referencia em python"))
        #expect(opened.phrase.withUnsafeBytes { String(decoding: $0, as: UTF8.self) } == "legal winner thank year wave sausage worth useful legal winner thank yellow")
        #expect(opened.passphrase.withUnsafeBytes { String(decoding: $0, as: UTF8.self) } == "TREZOR")
        #expect(opened.label == "Lacrado em Python")
        // A 25a palavra honrada: a seed tem de ser a do vetor oficial com "TREZOR".
        let seed = try BIP39.seed(phrase: opened.phrase, passphrase: "TREZOR")
        #expect(seed.withUnsafeBytes { Array($0) }.hex == "2e8905819b8723fe2c1d161860e5ee1830318dbf49a83bd451cfb8440c28bd6fa457fe1296106559a3c80937a1c1069be3a3a5bd381ee6260e8d9739fce1f607")
    }

    @Test("Arquivo hostil: tamanho e cabecalho recusados antes de derivar")
    func hostileFile() {
        #expect(throws: Envelope.Failure.notAnEnvelope) { try Envelope.inspect(Data(repeating: 0, count: 100)) }
        #expect(throws: Envelope.Failure.notAnEnvelope) { try Envelope.inspect(Data(repeating: 0, count: 16_504)) }
    }

    @Test("Nome vindo de arquivo alheio perde controles bidirecionais")
    func sanitize() {
        #expect(Envelope.sanitize("Carteira\u{202E}lanigiro", limit: 64) == "Carteiralanigiro")
        #expect(Envelope.sanitize(String(repeating: "a", count: 100), limit: 64).count == 64)
        #expect(Envelope.sanitize("Carteira\u{2028}\u{0007}\u{E000}\u{E0041}X", limit: 64) == "CarteiraX")
        #expect(Envelope.sanitize("  Minha\u{00A0}\u{3000} carteira  ", limit: 64) == "Minha carteira")
        #expect(Envelope.sanitize("a\u{0301}\u{0301}\u{0301}\u{0301}b", limit: 64) == "a\u{0301}\u{0301}b")
        #expect(Envelope.sanitize("Poupança", limit: 64) == "Poupança")
    }

    /// Lacra um envelope com o codigo de hoje da carteira, para o CI abrir com o
    /// decifrar.py embarcado (tools/conferir-envelope.sh). Roda so com
    /// ESCALIBUR_ENVELOPE_SAIDA apontando para onde gravar.
    @Test("Envelope da carteira para o decifrar.py", .enabled(if: ProcessInfo.processInfo.environment["ESCALIBUR_ENVELOPE_SAIDA"] != nil))
    func envelopeForReference() throws {
        let data = try Envelope.seal(
            phrase: BIP39.canonical("legal winner thank year wave sausage worth useful legal winner thank yellow"),
            passphrase: Self.secure("canção de ninar"),
            label: "Conferência do CI",
            password: Self.secure(Self.strong)
        )
        try data.write(to: URL(fileURLWithPath: ProcessInfo.processInfo.environment["ESCALIBUR_ENVELOPE_SAIDA"]!))
    }

    /// Gera a fixture. Roda so com ESCALIBUR_GERAR_FIXTURE=1, e o arquivo gerado e
    /// conferido a parte com `python3 tools/decifrar.py` antes de entrar no repo.
    @Test("Gerar fixture de interoperabilidade", .enabled(if: ProcessInfo.processInfo.environment["ESCALIBUR_GERAR_FIXTURE"] == "1"))
    func generateFixture() throws {
        // A fixture guarda a senha de antes do piso de 60 bits; o lacre vai direto ao
        // arquivo para continuar reproduzivel com a mesma senha.
        let phrase = BIP39.canonical(Self.phrase)
        guard case .valid(let language) = BIP39.validate(phrase) else { Issue.record("frase"); return }
        let sealing = SealingContents(mnemonic: phrase, passphrase: SecureBytes(capacity: 1), label: "Interoperabilidade", notes: "", language: language, kind: .bip39)
        let data = try VaultFile.create(sealing: sealing, password: Self.secure("cavalo correto bateria grampo"), parameters: Self.fast)
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ESCALIBUR_FIXTURE_SAIDA"] ?? "/tmp/interop.esclbr")
        try data.write(to: out)
    }
}

@Suite("NFKC da senha por trechos")
struct ChunkedNFKCTests {
    /// SplitMix64: a mesma sequencia em toda rodada.
    struct Sorteio {
        var state: UInt64
        mutating func next(_ limit: Int) -> Int {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Int((z ^ (z >> 31)) % UInt64(limit))
        }
    }

    @Test("Por trechos da o mesmo NFKC da String inteira: marcas soltas depois de ASCII, Hangul, compatibilidade e UTF-8 quebrado")
    func sameAsWholeString() {
        let pecas: [[UInt8]] = [
            "a", "e", "o", "Z", "1", " ", "-", "!", "é", "ñ", "Å", "ǟ", "\u{0301}", "\u{0308}", "\u{0304}", "\u{0345}", "\u{0334}",
            "\u{0327}", "\u{3099}", "\u{309A}", "ｶ", "\u{FF9E}", "か", "ﬁ", "Ａ", "①", "㌀", "ﷺ", "\u{0344}", "ά", "\u{1100}",
            "\u{1161}", "\u{11A8}", "가", "각", "ي", "\u{064B}", "😀", "ệ", "Ω", "\u{212B}", "ẛ", "\u{0323}", "ﬃ", "²", "ß",
        ].map { Array($0.utf8) } + [[0x80], [0xC3], [0xE2, 0x82], [0xFF], [0xED, 0xA0, 0x80]]
        var sorteio = Sorteio(state: 0x5EED)
        for _ in 0..<20_000 {
            var bytes: [UInt8] = []
            for _ in 0..<(1 + sorteio.next(12)) { bytes += pecas[sorteio.next(pecas.count)] }
            let senha = SecureBytes(capacity: bytes.count)
            senha.replaceAll(with: bytes)
            let porTrechos = KeyDerivation.normalized(senha).withUnsafeBytes { Array($0) }
            let inteira = Array(String(decoding: bytes, as: UTF8.self).precomposedStringWithCompatibilityMapping.utf8)
            #expect(porTrechos == inteira, "\(bytes)")
            if porTrechos != inteira { return }
        }
    }
}
