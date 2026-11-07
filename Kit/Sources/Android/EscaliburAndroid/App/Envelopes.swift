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
    /// A passphrase do envelope aberto foi digitada e conferiu (`conferirPassphrase`).
    nonisolated(unsafe) private static var passphraseConferida = false
    /// A digital da previa que o dono conferiu: so ela e gravada (revisao de blockchain de 05/11/2026).
    nonisolated(unsafe) private static var digitalDaPrevia: String?
    /// Soma um a cada esquecer e fechar a abertura: o Argon2 de abrir (e a previa) que termina depois disso nao deixa nada.
    nonisolated(unsafe) private static var rodadaDaAbertura = 0
    /// Soma um a cada encerrar o lacre (travar, fechar a tela): o lacre em curso ao sair do app fica, como no iPhone.
    nonisolated(unsafe) private static var rodadaDoLacre = 0

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

    /// Abre as palavras da carteira para o lacre. O envelope leva so as palavras: a passphrase nunca
    /// fica salva, nem no app nem num arquivo que sai dele (pedido do dono, 05/11/2026). Na carteira
    /// com passphrase, as palavras so saem depois de a passphrase digitada conferir pelo fingerprint
    /// da raiz: sem a carteira de base neste celular, quem tem o PIN e o rosto exportava as palavras
    /// e testava passphrases fora do aparelho.
    static func abrirCarteira(_ id: UUID, credencial: Credencial, passphraseDigitada: SecureBytes?) throws -> String {
        defer { passphraseDigitada?.wipe() }
        encerrar()
        guard let wallet = Sessao.shared.metadata.wallets.first(where: { $0.id == id }), !wallet.isWatchOnly else {
            credencial.zerar()
            throw Sessao.Falha.carteiraNaoEncontrada
        }
        if PortaDaPassphrase.semConferencia(wallet) {
            credencial.zerar()
            throw PortaDaPassphrase.SemConferencia()
        }
        // A digitada vem na chamada, ou entregue pela folha antes do PIN (o Kotlin zera a dele na hora).
        let conferir = PortaDaPassphrase.pede(wallet) ? (passphraseDigitada ?? PortaDaPassphrase.copiaEntregue()) : nil
        defer { conferir?.wipe() }
        if PortaDaPassphrase.pede(wallet), conferir == nil {
            credencial.zerar()
            throw Nucleo.Falha(erro: "envio.pedePassphrase")
        }
        if conferir != nil {
            do { try PortaDaPassphrase.comecar(wallet.id) } catch { credencial.zerar(); throw error }
        }
        let aberta: SecureBytes
        do {
            aberta = try Sessao.shared.comChaveRaiz(credencial) { rk in
                let segredo = try Chaves.wallets.open(walletID: id, rk: rk)
                defer { segredo.wipe() }
                if let conferir, try PortaDaPassphrase.confere(segredo, conferir, wallet) == .mismatch { throw Signer.Failure.passphraseMismatch }
                return try segredo.phrase()
            }
        } catch {
            if conferir != nil {
                if (error as? Signer.Failure) == .passphraseMismatch {
                    PortaDaPassphrase.descartarEntregue()
                    PortaDaPassphrase.errou(wallet.id)
                } else {
                    PortaDaPassphrase.devolver(wallet.id)
                }
            }
            throw error
        }
        PortaDaPassphrase.descartarEntregue()
        if conferir != nil { PortaDaPassphrase.passou(wallet.id) }
        trava.withLock {
            carteira = id
            frase = aberta
            passphrase = nil
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
            // Forte so com o piso do nucleo (60 bits), como no iPhone (rodada 3 da auditoria do envelope).
            return bits >= PasswordStrength.minimumBits ? .forte : .media
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
        // Uma medida so, com uma normalizacao (rodada 3 da auditoria do envelope); o aviso de PIN vem dela, para digitos de
        // qualquer escrita (rodadas 4 e 5).
        let medida = PasswordStrength.measure(digitada)
        let soDigitos = medida.digitsOnly
        guard medida.scalars >= PasswordStrength.minimumLength else {
            return Medida(curta: true, faixa: nil, texto: nil, soDigitos: soDigitos)
        }
        let bits = medida.bits
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
        let medida = PasswordStrength.measure(digitada)
        let bits = medida.bits
        if case .tooShort = medida.verdict {
            digitada.wipe()
            return Conferencia(resultado: "curta", titulo: nil, segurar: false, media: false)
        }
        trava.withLock {
            senha?.wipe()
            senha = digitada
            sorteada = false
            aceitouRisco = false
        }
        let custo = kdf
        let faixa = Faixa.de(bits: bits, kdf: custo)
        // Forte so com o piso do nucleo: com 512 MiB e mais passes, a faixa do tempo comeca abaixo de 60 bits, e o lacre
        // falhava sem caminho para o "sim" (auditoria do envelope de 06/11/2026). Como no iPhone, os bits antes da faixa.
        guard faixa != .forte || bits < PasswordStrength.minimumBits else {
            return Conferencia(resultado: "ok", titulo: nil, segurar: false, media: false)
        }
        let media = faixa == .media || faixa == .forte
        let titulo = media
            ? preencher(Textos.t("Um governo abriria em %@"), tempo(segundosDeGoverno(bits: bits, kdf: custo)))
            : preencher(Textos.t("Esta senha cai em %@"), tempo(segundos(bits: bits, kdf: custo)))
        return Conferencia(resultado: "risco", titulo: titulo, segurar: faixa == .muitoFraca || faixa == .fraca, media: media)
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
        // Copias, tiradas sob a trava: travar no meio zera os do lacre, e nao os que o Argon2 esta usando (revisao de seguranca
        // de 05/11/2026).
        func copia(_ b: SecureBytes) -> SecureBytes {
            let c = SecureBytes(capacity: max(b.count, 1))
            b.withUnsafeBytes { c.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
            return c
        }
        let preparo = trava.withLock { () -> (SecureBytes, SecureBytes?, SecureBytes, UUID, Bool, Bool, Int)? in
            guard let frase, let senha, let carteira else { return nil }
            return (copia(frase), passphrase.map(copia), copia(senha), carteira, sorteada, aceitouRisco, rodadaDoLacre)
        }
        guard let (frase, passphrase, senha, id, eraSorteada, aceito, rodada) = preparo else { throw Nucleo.Falha(erro: "envelope.semCarteira") }
        defer { frase.wipe(); passphrase?.wipe(); senha.wipe() }
        guard Hash.constantTimeEqual(senha, repeticao) else { throw Nucleo.Falha(erro: "envelope.naoConferem") }
        let custo = kdf
        let fraca = !eraSorteada && Faixa.de(bits: PasswordStrength.bits(senha), kdf: custo) == .muitoFraca
        let arquivo = try Envelope.seal(
            phrase: frase, passphrase: passphrase?.count == 0 ? nil : passphrase, label: String(rotulo.prefix(64)), password: senha,
            parameters: custo, generatedBits: eraSorteada ? PasswordStrength.suggestionBits() : nil, acceptedRisk: aceito
        )
        // Travou ou a tela fechou durante o Argon2: nada sai.
        guard trava.withLock({ rodadaDoLacre == rodada }) else { throw Sessao.Falha.travada }
        encerrar()
        try? Sessao.shared.atualizar(id) { $0.envelopeSealedAt = .now }
        let sorteio = try SecureBytes.random(count: 2).withUnsafeBytes { Array($0) }
        return Lacrado(arquivo: arquivo.base64EncodedString(), nome: "envelope-\(Hex.encode(sorteio).uppercased()).esclbr", fraca: fraca)
    }

    /// A tela fechou: tudo do lacre sai da memoria.
    static func encerrar() {
        trava.withLock {
            rodadaDoLacre &+= 1
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
        guard let (bytes, rodada) = trava.withLock({ dados.map { ($0, rodadaDaAbertura) } }) else { throw Envelope.Failure.notAnEnvelope }
        let conteudo = try Envelope.open(bytes, password: digitada)
        // Saiu do app ou travou durante o Argon2: o conteudo aberto nao fica (revisao de seguranca de 05/11/2026).
        let valeu = trava.withLock { () -> Bool in
            guard rodadaDaAbertura == rodada else { return false }
            aberto?.wipe()
            aberto = conteudo
            passphraseConferida = false
            digitalDaPrevia = nil
            return true
        }
        guard valeu else {
            conteudo.wipe()
            throw Sessao.Falha.travada
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
        let rodada = trava.withLock { rodadaDaAbertura }
        let (frase, passphrase, _, _) = try copias()
        defer {
            frase.wipe()
            passphrase?.wipe()
        }
        let previa = try Importacao.previa(frase, passphrase: passphrase, doEnvelope: true)
        // Saiu do app durante a previa: o conteudo aberto ja foi esquecido, e esta digital nao vale mais.
        guard trava.withLock({ () -> Bool in
            guard rodadaDaAbertura == rodada else { return false }
            digitalDaPrevia = previa.digital
            return true
        }) else { throw Sessao.Falha.travada }
        return previa
    }

    /// O envelope lacrado antes de 05/11/2026 leva a passphrase. Ela nao fica no app e nao aparece na tela
    /// (01/11/2026): sem saber a passphrase, quem importa ficaria com uma carteira que nao envia. Entao ela
    /// e digitada antes, de onde o dono a anotou, e comparada com a do envelope (as duas em NFKD, em tempo
    /// constante); confere, a carteira entra com a copia da passphrase conferida.
    static func conferirPassphrase(_ digitada: SecureBytes) throws {
        defer { digitada.wipe() }
        let (frase, passphrase, _, _) = try copias()
        frase.wipe()
        guard let passphrase else { return }
        let a = BIP39.nfkd(passphrase), b = BIP39.nfkd(digitada)
        passphrase.wipe()
        defer { a.wipe(); b.wipe() }
        guard Hash.constantTimeEqual(a, b) else { throw Signer.Failure.passphraseMismatch }
        trava.withLock { passphraseConferida = true }
    }

    /// Guarda a carteira do envelope, com a copia ja conferida (o envelope e a copia).
    static func importar(tronComOutraChave: Bool, credencial: Credencial) throws -> WalletMeta {
        let partes: (frase: SecureBytes, passphrase: SecureBytes?, palavras: Int, rotulo: String)
        do { partes = try copias() } catch { credencial.zerar(); throw error }
        let conferida = trava.withLock { passphraseConferida }
        // So a carteira da digital que o dono conferiu na previa (a conferencia e na derivacao que vai ao cofre).
        guard let esperada = trava.withLock({ digitalDaPrevia }) else {
            partes.frase.wipe()
            partes.passphrase?.wipe()
            credencial.zerar()
            throw Nucleo.Falha(erro: "importacao.mudou")
        }
        if partes.passphrase != nil, !conferida {
            partes.frase.wipe()
            partes.passphrase?.wipe()
            credencial.zerar()
            throw Nucleo.Falha(erro: "envelope.pedePassphrase")
        }
        // A de uma versao anterior, fora de NFKD: a Cardano da carteira importada sai dos mesmos bytes da original.
        let antiga = partes.passphrase.map { p in
            let n = BIP39.nfkd(p)
            defer { n.wipe() }
            return p.count > 0 && !Hash.constantTimeEqual(n, p)
        } ?? false
        let segredo: WalletSecret
        do {
            segredo = try Importacao.segredo(partes.frase, passphrase: partes.passphrase, doEnvelope: true)
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
            selecionar: quantas == 0, tronComOutraChave: tronComOutraChave,
            // A passphrase digitada conferiu com a do envelope: a copia dela entra conferida. E a Cardano que saiu dos bytes de
            // uma versao anterior entra marcada, como a da carteira de origem.
            passphraseConfirmada: conferida, cardanoAntiga: antiga, digitalEsperada: esperada, credencial: credencial
        )
        fecharAbertura()
        return wallet
    }

    /// "So ver as palavras": a frase vira o rascunho que a tela de gravar mostra de tres em tres.
    static func verPalavras() throws -> Int {
        let (frase, passphrase, palavras, _) = try copias()
        // So as palavras: a passphrase do envelope nao aparece nem fica no rascunho (05/11/2026).
        passphrase?.wipe()
        guard Sessao.shared.mostrar(Rascunho(frase: frase, palavras: palavras)) else { throw Sessao.Falha.travada }
        return palavras
    }

    /// Saiu do app: o conteudo aberto sai, e o arquivo cifrado (sem segredo nenhum) fica, para abrir de novo com a senha.
    static func esquecerAberto() {
        trava.withLock {
            rodadaDaAbertura &+= 1
            aberto?.wipe()
            aberto = nil
            passphraseConferida = false
            digitalDaPrevia = nil
        }
    }

    static func fecharAbertura() {
        trava.withLock {
            rodadaDaAbertura &+= 1
            aberto?.wipe()
            aberto = nil
            dados = nil
            passphraseConferida = false
            digitalDaPrevia = nil
        }
    }
}
