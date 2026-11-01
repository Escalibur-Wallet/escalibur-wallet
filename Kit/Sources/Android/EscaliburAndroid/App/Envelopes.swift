import EscaliburChains
import EscaliburCore
import EscaliburKeys
import Foundation

/// O envelope Escalibur (`.esclbr` v1): lacrar a senha de uma carteira num arquivo cifrado e
/// abrir um (o `SealEnvelopeFlow` e o `OpenEnvelopeFlow` do iOS, sem a interface). As palavras, a
/// passphrase e a senha do envelope ficam aqui, em buffers que o nucleo zera; a interface recebe
/// as seis palavras sorteadas (para mostrar, como no iOS), os textos e, no fim, os bytes do arquivo.
enum Envelopes {
    private static let trava = NSLock()

    // MARK: Lacrar

    nonisolated(unsafe) private static var carteira: UUID?
    nonisolated(unsafe) private static var frase: SecureBytes?
    nonisolated(unsafe) private static var passphrase: SecureBytes?
    /// As posicoes das palavras sorteadas: a senha e montada direto no buffer seguro.
    nonisolated(unsafe) private static var indices: [Int] = []
    /// A senha do envelope, depois de conferida e antes da repeticao.
    nonisolated(unsafe) private static var senha: SecureBytes?
    /// A senha e a sorteada pelo app (vale a entropia do sorteio, 66 bits).
    nonisolated(unsafe) private static var sorteada = false
    /// O "sim" explicito do dono para uma senha abaixo de forte.
    nonisolated(unsafe) private static var aceitouRisco = false
    /// O custo do Argon2 deste aparelho, medido uma vez por abertura do app.
    nonisolated(unsafe) private static var custo: KDFParameters?

    // MARK: Abrir

    nonisolated(unsafe) private static var dados: Data?
    nonisolated(unsafe) private static var aberto: Envelope.Contents?

    /// O custo deste aparelho: o piso de lacre ate a medida chegar.
    private static var kdf: KDFParameters {
        trava.withLock { custo } ?? KDFParameters(memoryKiB: KDFCalibration.sealFloorKiB, passes: 3, lanes: KDFCalibration.lanes)
    }

    struct Calibracao: Encodable { let segundos: Double; let podeLacrar: Bool }

    /// Mede o Argon2 deste aparelho (alguns segundos): o custo e o tempo do lacre.
    static func calibrar() -> Calibracao {
        let medido = trava.withLock { custo } ?? KDFCalibration.calibrate()
        trava.withLock { custo = medido }
        return Calibracao(segundos: KDFCalibration.estimatedSeconds(for: medido), podeLacrar: KDFCalibration.canSeal())
    }

    /// Abre as palavras da carteira para o lacre. O envelope leva a passphrase junto: na carteira
    /// que pede a passphrase, ela so sai depois de digitada e conferida no cofre. Sem isso, quem
    /// tem o PIN e o rosto exportava as duas.
    static func abrirCarteira(_ id: UUID, credencial: Credencial, passphraseDigitada: SecureBytes?) throws -> String {
        defer { passphraseDigitada?.wipe() }
        encerrar()
        guard let wallet = Sessao.shared.metadata.wallets.first(where: { $0.id == id }), !wallet.isWatchOnly else {
            credencial.zerar()
            throw Sessao.Falha.carteiraNaoEncontrada
        }
        let conferir = PortaDaPassphrase.pede(wallet) ? passphraseDigitada : nil
        if PortaDaPassphrase.pede(wallet), conferir == nil {
            credencial.zerar()
            throw Nucleo.Falha(erro: "envio.pedePassphrase")
        }
        if conferir != nil {
            do { try PortaDaPassphrase.comecar(wallet.id) } catch { credencial.zerar(); throw error }
        }
        let aberta: (SecureBytes, SecureBytes)
        do {
            aberta = try Sessao.shared.comChaveRaiz(credencial) { rk in
                let segredo = try Chaves.wallets.open(walletID: id, rk: rk)
                defer { segredo.wipe() }
                if let conferir, !PortaDaPassphrase.confere(segredo.passphrase, conferir) { throw Signer.Failure.passphraseMismatch }
                let palavras = try segredo.phrase()
                let copia = SecureBytes(capacity: max(segredo.passphrase.count, 1))
                segredo.passphrase.withUnsafeBytes { copia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
                return (palavras, copia)
            }
        } catch {
            if conferir != nil {
                if (error as? Signer.Failure) == .passphraseMismatch { PortaDaPassphrase.errou(wallet.id) } else { PortaDaPassphrase.devolver(wallet.id) }
            }
            throw error
        }
        if conferir != nil { PortaDaPassphrase.passou(wallet.id) }
        trava.withLock {
            carteira = id
            frase = aberta.0
            passphrase = aberta.1
        }
        // Travou enquanto o cofre abria: o travar() ja zerou o lacre, e o que acabou de chegar sai
        // tambem.
        guard Sessao.shared.fase == .unlocked else {
            encerrar()
            throw Sessao.Falha.travada
        }
        return wallet.name
    }

    /// Seis palavras sorteadas neste aparelho, que nao repetem as da carteira.
    static func sugerir() throws -> [String] {
        let novos = try PasswordStrength.suggestionIndices(avoiding: trava.withLock { frase })
        let lista = try WordlistStore.shared.wordlist(for: .english)
        trava.withLock { indices = novos }
        return novos.map { lista.words[$0] }
    }

    /// "Anotei, continuar": a senha sai direto das posicoes sorteadas.
    static func usarSorteada() throws {
        try trava.withLock {
            guard !indices.isEmpty else { throw Nucleo.Falha(erro: "envelope.semSorteio") }
            let buffer = SecureBytes(capacity: 256)
            try PasswordStrength.write(indices, into: buffer)
            senha?.wipe()
            senha = buffer
            sorteada = true
            aceitouRisco = false
        }
    }

    // MARK: A forca da senha propria

    /// As faixas, pelo tempo real com o custo deste aparelho (o `PasswordCost` do iOS).
    enum Faixa: String, Encodable {
        case muitoFraca, fraca, media, forte

        static func de(bits: Double, kdf: KDFParameters) -> Faixa {
            let ano = 31_557_600.0
            let crime = segundos(bits: bits, kdf: kdf)
            if crime < 86_400 { return .muitoFraca }
            if crime < 10 * ano { return .fraca }
            if segundosDeGoverno(bits: bits, kdf: kdf) < 1_000 * ano { return .media }
            return .forte
        }
    }

    /// Segundos para o crime organizado achar a senha, em media: 1,2 x 10^5 chutes por segundo
    /// com os parametros de referencia, e proporcionalmente mais com parametros mais leves.
    static func segundos(bits: Double, kdf: KDFParameters) -> Double {
        let taxa = 1.2e5 * 4096.0 / max(kdf.memoryTrafficMiB, 1)
        return pow(2, bits) / 2 / taxa
    }

    /// Um Estado testa 100 vezes mais rapido que o crime organizado.
    static func segundosDeGoverno(bits: Double, kdf: KDFParameters) -> Double { segundos(bits: bits, kdf: kdf) / 100 }

    /// "4 segundos", "6 dias", "485 anos", "3,7 milhões de anos".
    static func tempo(_ segundos: Double) -> String {
        let minuto = 60.0, hora = 3600.0, dia = 86_400.0, ano = 31_557_600.0
        func contar(_ valor: Double) -> (um: Bool, texto: String) {
            let arredondado = max(Int(valor.rounded()), 1)
            return (arredondado == 1, Fmt.agrupado(Double(arredondado), casas: 0))
        }
        switch segundos {
        case ..<1: return Textos.t("menos de 1 segundo")
        case ..<minuto:
            let n = contar(segundos)
            return n.um ? Textos.t("1 segundo") : preencher(Textos.t("%@ segundos"), n.texto)
        case ..<hora:
            let n = contar(segundos / minuto)
            return n.um ? Textos.t("1 minuto") : preencher(Textos.t("%@ minutos"), n.texto)
        case ..<dia:
            let n = contar(segundos / hora)
            return n.um ? Textos.t("1 hora") : preencher(Textos.t("%@ horas"), n.texto)
        case ..<ano:
            let n = contar(segundos / dia)
            return n.um ? Textos.t("1 dia") : preencher(Textos.t("%@ dias"), n.texto)
        case ..<(1e6 * ano):
            let n = contar(segundos / ano)
            return n.um ? Textos.t("1 ano") : preencher(Textos.t("%@ anos"), n.texto)
        case ..<(1e9 * ano): return preencher(Textos.t("%@ milhões de anos"), Fmt.agrupado(segundos / ano / 1e6, casas: 1, aparar: true))
        default: return Textos.t("mais de 1 bilhão de anos")
        }
    }

    static func textoDaFaixa(bits: Double, kdf: KDFParameters) -> String {
        switch Faixa.de(bits: bits, kdf: kdf) {
        case .muitoFraca: return preencher(Textos.t("Muito fraca. Quem pegar o arquivo abre em %@."), tempo(segundos(bits: bits, kdf: kdf)))
        case .fraca: return preencher(Textos.t("Fraca. Um grupo com placas de vídeo abre em %@."), tempo(segundos(bits: bits, kdf: kdf)))
        case .media: return preencher(Textos.t("Média. Um grupo com placas de vídeo levaria %@, e um governo, %@."),
                                      tempo(segundos(bits: bits, kdf: kdf)), tempo(segundosDeGoverno(bits: bits, kdf: kdf)))
        case .forte: return Textos.t("Forte. Nem um governo abre em tempo útil.")
        }
    }

    struct Medida: Encodable { let curta: Bool; let faixa: Faixa?; let texto: String?; let soDigitos: Bool }

    /// Ao vivo, enquanto o dono digita: em quanto tempo a senha cai, com o custo deste aparelho.
    static func medir(_ digitada: SecureBytes) -> Medida {
        defer { digitada.wipe() }
        let soDigitos = digitada.count > 0 && digitada.withUnsafeBytes { $0.allSatisfy { (0x30...0x39).contains($0) } }
        guard PasswordStrength.scalarCount(digitada) >= PasswordStrength.minimumLength else {
            return Medida(curta: true, faixa: nil, texto: nil, soDigitos: soDigitos)
        }
        let bits = PasswordStrength.bits(digitada)
        let custo = kdf
        return Medida(curta: false, faixa: Faixa.de(bits: bits, kdf: custo), texto: textoDaFaixa(bits: bits, kdf: custo), soDigitos: soDigitos)
    }

    struct Conferencia: Encodable {
        /// "ok", "curta", "usaFrase" ou "risco".
        let resultado: String
        let titulo: String?
        /// Muito fraca e fraca: o "usar mesmo assim" exige segurar o botao.
        let segurar: Bool
        let media: Bool
    }

    /// A senha propria, antes da repeticao. Palavras da propria frase anulam o backup (o papel da
    /// frase abriria o envelope): isso nao e questao de forca, e continua recusado. Abaixo de
    /// forte, com o custo deste aparelho, pede o "sim".
    static func conferir(_ digitada: SecureBytes) -> Conferencia {
        let frase = trava.withLock { Self.frase }
        if let frase, PasswordStrength.reusesPhrase(digitada, phrase: frase) {
            digitada.wipe()
            return Conferencia(resultado: "usaFrase", titulo: nil, segurar: false, media: false)
        }
        let bits: Double
        switch PasswordStrength.verdict(digitada) {
        case .tooShort:
            digitada.wipe()
            return Conferencia(resultado: "curta", titulo: nil, segurar: false, media: false)
        case .strong: bits = PasswordStrength.bits(digitada)
        case .digitsOnly(let medidos), .weak(let medidos): bits = medidos
        }
        trava.withLock {
            senha?.wipe()
            senha = digitada
            sorteada = false
            aceitouRisco = false
        }
        let custo = kdf
        let faixa = Faixa.de(bits: bits, kdf: custo)
        guard faixa != .forte else { return Conferencia(resultado: "ok", titulo: nil, segurar: false, media: false) }
        let titulo = faixa == .media
            ? preencher(Textos.t("Um governo abriria em %@"), tempo(segundosDeGoverno(bits: bits, kdf: custo)))
            : preencher(Textos.t("Esta senha cai em %@"), tempo(segundos(bits: bits, kdf: custo)))
        return Conferencia(resultado: "risco", titulo: titulo, segurar: faixa == .muitoFraca || faixa == .fraca, media: faixa == .media)
    }

    static func aceitarRisco() { trava.withLock { aceitouRisco = true } }

    /// Da repeticao de volta para a senha: a senha sai da memoria. Com as palavras sorteadas,
    /// voltam as mesmas (o dono ja anotou).
    static func voltar() -> [String] {
        let (eraSorteada, posicoes) = trava.withLock { () -> (Bool, [Int]) in
            senha?.wipe()
            senha = nil
            aceitouRisco = false
            let era = sorteada
            sorteada = false
            return (era, indices)
        }
        guard eraSorteada, let lista = try? WordlistStore.shared.wordlist(for: .english) else { return [] }
        return posicoes.map { lista.words[$0] }
    }

    struct Lacrado: Encodable { let arquivo: String; let nome: String; let fraca: Bool }

    /// Confere a repeticao (em tempo constante) e lacra. A frase, a passphrase e a senha saem da
    /// memoria aqui, de qualquer jeito.
    static func lacrar(repeticao: SecureBytes, rotulo: String) throws -> Lacrado {
        defer { repeticao.wipe() }
        guard Sessao.shared.fase == .unlocked else { throw Sessao.Falha.travada }
        let preparo = trava.withLock { () -> (SecureBytes, SecureBytes?, SecureBytes, UUID, Bool, Bool)? in
            guard let frase, let senha, let carteira else { return nil }
            return (frase, passphrase, senha, carteira, sorteada, aceitouRisco)
        }
        guard let (frase, passphrase, senha, id, eraSorteada, aceito) = preparo else { throw Nucleo.Falha(erro: "envelope.semCarteira") }
        guard Hash.constantTimeEqual(senha, repeticao) else { throw Nucleo.Falha(erro: "envelope.naoConferem") }
        let custo = kdf
        let fraca = !eraSorteada && Faixa.de(bits: PasswordStrength.bits(senha), kdf: custo) == .muitoFraca
        let arquivo = try Envelope.seal(
            phrase: frase, passphrase: passphrase?.count == 0 ? nil : passphrase, label: String(rotulo.prefix(64)), password: senha,
            parameters: custo, generatedBits: eraSorteada ? PasswordStrength.suggestionBits() : nil, acceptedRisk: aceito
        )
        encerrar()
        try? Sessao.shared.atualizar(id) { $0.envelopeSealedAt = .now }
        let sorteio = try SecureBytes.random(count: 2).withUnsafeBytes { Array($0) }
        return Lacrado(arquivo: arquivo.base64EncodedString(), nome: "envelope-\(Hex.encode(sorteio).uppercased()).esclbr", fraca: fraca)
    }

    /// A tela fechou: tudo do lacre sai da memoria.
    static func encerrar() {
        trava.withLock {
            frase?.wipe()
            passphrase?.wipe()
            senha?.wipe()
            frase = nil
            passphrase = nil
            senha = nil
            indices = []
            sorteada = false
            aceitouRisco = false
            carteira = nil
        }
    }

    // MARK: Abrir um envelope

    struct Inspecao: Encodable { let segundos: Double }

    /// O arquivo escolhido: um envelope Escalibur do tamanho certo, que este aparelho abre.
    static func inspecionar(_ base64: String) throws -> Inspecao {
        fecharAbertura()
        guard let bytes = Data(base64Encoded: base64), bytes.count == Envelope.fileLength else { throw Envelope.Failure.notAnEnvelope }
        let inspecao = try Envelope.inspect(bytes)
        trava.withLock { dados = bytes }
        return Inspecao(segundos: inspecao.estimatedSeconds)
    }

    struct Aberto: Encodable { let rotulo: String; let palavras: Int; let idioma: String; let comPassphrase: Bool }

    static func abrir(senha digitada: SecureBytes) throws -> Aberto {
        defer { digitada.wipe() }
        guard let bytes = trava.withLock({ dados }) else { throw Envelope.Failure.notAnEnvelope }
        let conteudo = try Envelope.open(bytes, password: digitada)
        trava.withLock {
            aberto?.wipe()
            aberto = conteudo
        }
        let palavras = conteudo.phrase.withUnsafeBytes { raw in raw.filter { $0 == 0x20 }.count + 1 }
        return Aberto(rotulo: conteudo.label, palavras: palavras, idioma: conteudo.language.rawValue, comPassphrase: conteudo.passphrase.count > 0)
    }

    /// As copias da frase e da passphrase abertas, para quem as consome (e zera).
    private static func copias() throws -> (frase: SecureBytes, passphrase: SecureBytes?, palavras: Int, rotulo: String) {
        try trava.withLock {
            guard let aberto else { throw Envelope.Failure.notAnEnvelope }
            let frase = SecureBytes(capacity: aberto.phrase.capacity)
            aberto.phrase.withUnsafeBytes { frase.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
            var passphrase: SecureBytes?
            if aberto.passphrase.count > 0 {
                let copia = SecureBytes(capacity: aberto.passphrase.count)
                aberto.passphrase.withUnsafeBytes { copia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
                passphrase = copia
            }
            let palavras = aberto.phrase.withUnsafeBytes { raw in raw.filter { $0 == 0x20 }.count + 1 }
            return (frase, passphrase, palavras, aberto.label)
        }
    }

    /// A previa da importacao: a digital e os enderecos, como na importacao pelas palavras.
    static func previa() throws -> Importacao.Previa {
        let (frase, passphrase, _, _) = try copias()
        defer {
            frase.wipe()
            passphrase?.wipe()
        }
        return try Importacao.previa(frase, passphrase: passphrase)
    }

    /// Guarda a carteira do envelope, com a copia ja conferida (o envelope e a copia).
    static func importar(tronComOutraChave: Bool, credencial: Credencial) throws -> WalletMeta {
        let partes: (frase: SecureBytes, passphrase: SecureBytes?, palavras: Int, rotulo: String)
        do { partes = try copias() } catch { credencial.zerar(); throw error }
        let segredo: WalletSecret
        do {
            segredo = try Importacao.segredo(partes.frase, passphrase: partes.passphrase)
        } catch {
            partes.frase.wipe()
            partes.passphrase?.wipe()
            credencial.zerar()
            throw error
        }
        partes.frase.wipe()
        partes.passphrase?.wipe()
        let quantas = Sessao.shared.metadata.wallets.count
        let nome = partes.rotulo.isEmpty ? Textos.carteira(quantas + 1) : String(partes.rotulo.prefix(40))
        let wallet = try Sessao.shared.adicionarCarteira(
            segredo, nome: nome, origem: .importedEnvelope, palavras: partes.palavras, copiaConfirmada: true,
            selecionar: quantas == 0, tronComOutraChave: tronComOutraChave, credencial: credencial
        )
        fecharAbertura()
        return wallet
    }

    /// "So ver as palavras": a frase vira o rascunho que a tela de gravar mostra de tres em tres.
    static func verPalavras() throws -> Int {
        let (frase, passphrase, palavras, _) = try copias()
        guard Sessao.shared.mostrar(Rascunho(frase: frase, palavras: palavras, passphrase: passphrase)) else { throw Sessao.Falha.travada }
        return palavras
    }

    static func fecharAbertura() {
        trava.withLock {
            aberto?.wipe()
            aberto = nil
            dados = nil
        }
    }
}
