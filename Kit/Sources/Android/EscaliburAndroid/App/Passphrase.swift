import EscaliburChains
import EscaliburCore
import EscaliburKeys
import Foundation

/// A passphrase antes de cada assinatura (o `PassphraseGate` do iOS, sem a folha): a carteira com
/// passphrase pede ela antes da biometria ou do PIN, em envio, troca, ponte e cancelar ordem. Ela
/// nunca fica salva no app (pedido do dono, 05/11/2026): o cofre guarda so a entropia, e o
/// assinador (`Signer.sign`) deriva a raiz com a digitada e confere o fingerprint da criacao. Aqui
/// ficam a conta das tentativas, a espera depois dos erros e a folga de alguns minutos depois de
/// acertar, que guarda uma copia so na memoria.
enum PortaDaPassphrase {
    private static let trava = NSLock()
    nonisolated(unsafe) private static var folgaAte: [UUID: TimeInterval] = [:]
    /// A passphrase da folga, num buffer seguro (preso na RAM e fora do core dump), so da carteira
    /// em que ela conferiu. Zerada no fim do prazo, ao sair do app, ao travar, ao remover a
    /// carteira e ao apagar tudo; desligar ou reiniciar o celular apaga a RAM inteira, e nada dela
    /// vai para o disco.
    nonisolated(unsafe) private static var guardadas: [UUID: SecureBytes] = [:]
    /// A folga de agora de cada carteira: o relogio de uma folga anterior nao encerra a nova.
    nonisolated(unsafe) private static var rodadas: [UUID: UUID] = [:]
    /// Soma um a cada encerramento: a folga pedida antes de um travar, sair do app ou remover a carteira
    /// (o Argon2 do PIN leva segundos) nao nasce depois dele.
    nonisolated(unsafe) private static var geracao = 0
    /// A passphrase que a folha acabou de entregar para a proxima assinatura ("passphrase.entregar"): o
    /// Kotlin zera a dele logo depois de entregar, e esta fica num buffer seguro so ate assinar (zerada
    /// ao assinar, ao errar, ao fechar o pedido, ao travar e ao sair do app). Antes, a do Kotlin vivia
    /// ate o fim da transmissao, que esta dentro da mesma chamada.
    nonisolated(unsafe) private static var entregue: SecureBytes?
    /// A geracao em que ela chegou: a que chega depois de travar ou sair do app nao vale.
    nonisolated(unsafe) private static var entregueNaGeracao = 0

    static func entregar(_ passphrase: SecureBytes) {
        trava.withLock {
            entregue?.wipe()
            entregue = passphrase
            entregueNaGeracao = geracao
        }
    }

    static func descartarEntregue() { trava.withLock { entregue?.wipe(); entregue = nil } }

    /// Uma copia da entregue (de quem chama, que zera), se ela chegou na geracao de agora.
    static func copiaEntregue() -> SecureBytes? {
        trava.withLock {
            guard let entregue, entregue.count > 0, entregueNaGeracao == geracao else { return nil }
            let copia = SecureBytes(capacity: entregue.count)
            entregue.withUnsafeBytes { copia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
            return copia
        }
    }

    static let escolhasDeFolga = [5, 10, 15, 20]
    /// Erros livres antes da primeira espera; a espera comeca em 1 minuto e dobra a cada erro,
    /// ate 24 horas. Acertar zera.
    static let errosLivres = 5
    static let primeiraEspera: TimeInterval = 60
    static let maiorEspera: TimeInterval = 24 * 3600

    /// A porta de abrir ou criar com passphrase: dez tentativas livres antes da primeira espera
    /// (pedido do dono, 27/10/2026). Dai em diante depende do que ha neste celular:
    /// - sem carteira com passphrase aqui, e por ela que o dono que esqueceu a passphrase tenta
    ///   lembrar: espera de no maximo 15 minutos, e um dia sem tentar zera a conta (25/10/2026);
    /// - com uma carteira com passphrase aqui, a porta diria "esta carteira ja esta aberta" para o
    ///   chute certo, e seria o jeito facil de descobrir a passphrase dela e depois enviar: a espera
    ///   cresce ate 24 horas e nao zera sozinha, como a de enviar (revisao de seguranca de 26/10/2026).
    static let errosLivresDaCriacao = 10
    static let maiorEsperaDaCriacao: TimeInterval = 15 * 60
    static let esquecerCriacaoDepois: TimeInterval = 24 * 3600

    private static func limites(criacao: Bool, _ metadata: Metadata) -> (livres: Int, maior: TimeInterval) {
        guard criacao else { return (errosLivres, maiorEspera) }
        return (errosLivresDaCriacao, rigida(metadata) ? maiorEspera : maiorEsperaDaCriacao)
    }

    /// Ha carteira com passphrase neste celular: a porta de criar segue a escada inteira.
    private static func rigida(_ metadata: Metadata) -> Bool {
        metadata.wallets.contains { $0.hasPassphrase && !$0.isWatchOnly }
    }

    /// Toda carteira com passphrase pede: sem ela nao ha como assinar, porque o cofre nao a tem. O
    /// "Pedir a passphrase para enviar" de antes saiu.
    static func pede(_ wallet: WalletMeta?) -> Bool {
        guard let wallet, wallet.hasPassphrase, !wallet.isWatchOnly else { return false }
        // A que esta versao nao confere: pedir so contaria erro (`semConferencia`).
        return wallet.passphraseUnverified != true
    }

    /// A carteira com passphrase que esta versao nao confere (`passphraseUnverified`): assinar, ver as palavras, lacrar e
    /// conferir a copia recusam com o texto proprio, sem pedir a passphrase nem contar erro.
    static func semConferencia(_ wallet: WalletMeta?) -> Bool {
        guard let wallet, wallet.hasPassphrase, !wallet.isWatchOnly else { return false }
        return wallet.passphraseUnverified == true
    }

    static func precisa(_ wallet: WalletMeta?) -> Bool {
        guard let wallet, pede(wallet) else { return false }
        return !emFolga(wallet.id)
    }

    /// A passphrase digitada da a carteira? Pelo fingerprint da raiz e, com a conta Cardano, se ela foi
    /// gravada fora de NFKD por uma versao anterior. Com o registro ja aberto.
    static func confere(_ guardada: WalletSecret, _ digitada: SecureBytes, _ carteira: WalletMeta?, cardano: Bool = false) throws -> PassphraseProof.Result {
        try PassphraseProof.check(guardada, typed: digitada, fingerprint: carteira?.fingerprint.flatMap(Hex.decode),
                                  cardanoPublicKey: cardano ? carteira?.accounts.first { $0.chainID == Chain.cardano.id }?.publicKey : nil)
    }

    /// A passphrase cabe no papel? Caractere de controle, de formato (largura zero, bidirecional),
    /// separador de linha, uso privado ou um espaco que nao e o comum nao aparecem, ou aparecem
    /// iguais a outros, e quem anota perde a carteira (revisao da auditoria 4, C7-02).
    static func escrevivel(_ segredo: SecureBytes) -> Bool {
        segredo.withUnsafeBytes { raw in
            var iterador = raw.makeIterator()
            var decodificador = Unicode.UTF8()
            while true {
                switch decodificador.decode(&iterador) {
                case .scalarValue(let escalar):
                    switch escalar.properties.generalCategory {
                    case .format, .control, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
                        return false
                    case .spaceSeparator where escalar != " ":
                        return false
                    default:
                        continue
                    }
                case .emptyInput: return true
                case .error: return false
                }
            }
        }
    }

    /// Cabe no limite: 256 bytes depois do NFKD, onde uma letra com acento ocupa tres. Era o do cofre, que
    /// nao a guarda mais, e continua o mesmo para quem ja tem uma.
    static func cabe(_ segredo: SecureBytes) -> Bool {
        let normalizada = BIP39.nfkd(segredo)
        defer { normalizada.wipe() }
        return normalizada.count <= WalletVault.maxPassphraseBytes
    }

    static func emFolga(_ id: UUID) -> Bool {
        trava.withLock {
            guard guardadas[id] != nil else { return false }
            guard (folgaAte[id] ?? 0) > PINPolicy.uptime else {
                encerrarSemTrava(id)
                return false
            }
            return true
        }
    }

    /// Uma copia da passphrase da folga, de quem chama (que zera depois de assinar), ou nil sem folga.
    /// A folga vencida sai zerada aqui mesmo.
    private static func copiaDaFolga(_ id: UUID) -> SecureBytes? {
        trava.withLock {
            guard let guardada = guardadas[id] else { return nil }
            guard (folgaAte[id] ?? 0) > PINPolicy.uptime else {
                encerrarSemTrava(id)
                return nil
            }
            let copia = SecureBytes(capacity: max(guardada.count, 1))
            guardada.withUnsafeBytes { copia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
            return copia
        }
    }

    /// O assinador conferiu: a folga escolhida na folha comeca agora, com uma copia da passphrase,
    /// so na memoria. Sem folga escolhida, nada fica, e nada fica se a folga foi encerrada depois de
    /// `antes` (travou, saiu do app ou a carteira saiu enquanto o cofre abria).
    private static func comecarFolga(_ id: UUID, minutos: Int?, passphrase: SecureBytes, antes: Int) {
        guard let minutos, escolhasDeFolga.contains(minutos) else { return }
        let copia = SecureBytes(capacity: max(passphrase.count, 1))
        passphrase.withUnsafeBytes { copia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        let segundos = TimeInterval(minutos * 60)
        let rodada = UUID()
        let comecou = trava.withLock { () -> Bool in
            // So a geracao: travar() passa por `encerrarFolgas`. Perguntar a Sessao aqui inverteria a ordem das travas
            // (a Sessao chama esta trava por dentro da dela, ao remover a carteira).
            guard geracao == antes else { return false }
            encerrarSemTrava(id)
            guardadas[id] = copia
            folgaAte[id] = PINPolicy.uptime + segundos
            rodadas[id] = rodada
            return true
        }
        guard comecou else {
            copia.wipe()
            return
        }
        // Zerada no fim do prazo mesmo sem ninguem perguntar por ela. Pelo relogio de parede, que anda com o
        // celular dormindo; quem decide e o monotono, a cada uso.
        DispatchQueue.global().asyncAfter(wallDeadline: .now() + segundos) {
            trava.withLock { if rodadas[id] == rodada { encerrarSemTrava(id) } }
        }
    }

    /// A folga desta carteira acaba, e a copia da passphrase sai zerada.
    static func encerrarFolga(_ id: UUID) {
        trava.withLock {
            geracao &+= 1
            encerrarSemTrava(id)
        }
    }

    private static func encerrarSemTrava(_ id: UUID) {
        guardadas.removeValue(forKey: id)?.wipe()
        folgaAte[id] = nil
        rodadas[id] = nil
    }

    /// Travar, sair do app ou apagar tudo: toda copia da passphrase sai zerada, e quem destrava com o PIN
    /// depois nao pula a passphrase.
    static func encerrarFolgas() {
        trava.withLock {
            geracao &+= 1
            for id in Array(guardadas.keys) + Array(folgaAte.keys) { encerrarSemTrava(id) }
            entregue?.wipe()
            entregue = nil
        }
    }

    /// Assina o plano na carteira dele. Com passphrase: a digitada agora (que conta como tentativa) ou a
    /// copia da folga; o assinador a confere pelo fingerprint da raiz; a folga escolhida comeca depois de
    /// conferir; e as redes que uma versao nova trouxe nascem nessa mesma abertura do cofre (sem a
    /// passphrase, nao ha outro jeito). A digitada e a copia saem zeradas logo depois de assinar, antes de
    /// transmitir: so a copia da folga, se o dono a pediu, continua na memoria.
    /// A passphrase que uma versao anterior gravou nao dava a raiz da criacao (`passphraseUnverified`): a digitada
    /// tambem nao assina nesta versao, e a tela diz isso em vez de contar erro.
    struct SemConferencia: Error {}

    /// A raiz conferiu, mas a Cardano de uma carteira antiga saiu dos bytes da criacao, que a digitada nao repetiu
    /// (`legacyCardanoPassphrase`).
    struct CardanoAntiga: Error {}

    static func assinar(_ plano: SigningPlan, carteira: WalletMeta?, digitada: SecureBytes?, folga: Int?, credencial: Credencial) throws -> [SignedTransaction] {
        defer { digitada?.wipe() }
        // A geracao antes de qualquer copia: travar ou sair do app daqui em diante nao deixa a folga nascer.
        let antes = trava.withLock { geracao }
        if semConferencia(carteira) {
            credencial.zerar()
            throw SemConferencia()
        }
        var conferir: SecureBytes?
        var nova = false
        if pede(carteira), let carteira {
            if let digitada {
                conferir = digitada
                nova = true
            } else if let copia = copiaEntregue() {
                conferir = copia
                nova = true
            } else if let copia = copiaDaFolga(carteira.id) {
                conferir = copia
            } else {
                credencial.zerar()
                throw Nucleo.Falha(erro: "envio.pedePassphrase")
            }
        }
        defer { conferir?.wipe() }
        if nova {
            do { try comecar(plano.walletID) } catch { credencial.zerar(); throw error }
        }
        let digital = carteira?.fingerprint.flatMap(Hex.decode)
        let tem = Set(carteira?.accounts.map(\.chainID) ?? [])
        let faltam = conferir == nil ? [] : Chain.all.filter { !tem.contains($0.id) }
        let resultado: ([SignedTransaction], [DerivedAccount])
        do {
            resultado = try Sessao.shared.comChaveRaiz(credencial) { rk in
                // Assina antes (o plano vencido recusa antes de a passphrase ser usada), e so depois as redes que faltam,
                // com uma copia da RK, que o assinador zera. Ao contrario, a passphrase era testada antes do vencimento, e o
                // plano vencido devolvia a tentativa (revisao de seguranca de 05/11/2026).
                // A copia so nasce quando ha rede para derivar: no caso comum, a RK morre no assinador, como antes.
                var outra: SecureBytes?
                if conferir != nil, !faltam.isEmpty {
                    let copia = SecureBytes(capacity: max(rk.count, 1))
                    rk.withUnsafeBytes { copia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
                    outra = copia
                }
                defer { outra?.wipe() }
                let assinado = try Signer.sign(plano, rootKey: rk, vault: Chaves.wallets, passphrase: conferir, fingerprint: digital)
                // Uma rede que nao nasce (aparelho com defeito) nao segura a assinatura: so fica para a proxima.
                let novas = outra.flatMap { chave in
                    conferir.flatMap { passphrase in
                        try? PassphraseProof.missingAccounts(walletID: plano.walletID, rootKey: chave, vault: Chaves.wallets,
                                                             typed: passphrase, fingerprint: digital, chains: faltam)
                    }
                } ?? []
                return (assinado, novas)
            }
        } catch {
            let errada = (error as? Signer.Failure) == .passphraseMismatch
            // A errada nao serve para a proxima tentativa; o PIN errado, sim (a folha do PIN volta).
            if errada { descartarEntregue() }
            if nova {
                if errada { errou(plano.walletID) } else { devolver(plano.walletID) }
            } else if errada {
                encerrarFolga(plano.walletID)
            }
            if (error as? Signer.Failure) == .unexpectedKey, carteira?.legacyCardanoPassphrase == true, plano.chain.family == .cardano {
                throw CardanoAntiga()
            }
            throw error
        }
        // Assinou: a entregue sai ja, antes de transmitir.
        descartarEntregue()
        if let conferir {
            if nova {
                passou(plano.walletID)
                comecarFolga(plano.walletID, minutos: folga, passphrase: conferir, antes: antes)
            }
            if !resultado.1.isEmpty { Sessao.shared.acrescentarContas(resultado.1, em: plano.walletID) }
        }
        return resultado.0
    }

    struct Espera: Error { let ate: Date }

    /// A conta e de cada carteira (revisao de seguranca de 24/10/2026): com uma conta so, acertar a
    /// passphrase de uma carteira propria zerava a espera, e quem sabe o PIN seguia chutando a
    /// passphrase da carteira do dono. A criacao conta na carteira de base, numa conta a parte: uma
    /// base que tem passphrase segue a escada inteira nas portas dela.
    private static func chave(_ carteira: UUID, _ criacao: Bool) -> String {
        criacao ? "creation-" + carteira.uuidString : carteira.uuidString
    }

    private static func conta(_ metadata: Metadata, _ carteira: UUID, criacao: Bool = false) -> PassphraseGuard? {
        if criacao { return metadata.settings.passphraseGuards?[chave(carteira, true)] }
        return metadata.settings.passphraseGuards?[carteira.uuidString] ?? metadata.settings.passphraseGuard
    }

    /// Grava a conta desta carteira, e passa a conta unica de antes para todas as carteiras daqui:
    /// ninguem sai da espera que ja corria.
    private static func gravar(_ metadata: inout Metadata, _ carteira: UUID, _ valor: PassphraseGuard?, criacao: Bool = false) {
        var todas = metadata.settings.passphraseGuards ?? [:]
        if let antiga = metadata.settings.passphraseGuard {
            for wallet in metadata.wallets where todas[wallet.id.uuidString] == nil { todas[wallet.id.uuidString] = antiga }
            metadata.settings.passphraseGuard = nil
        }
        todas[chave(carteira, criacao)] = valor
        metadata.settings.passphraseGuards = todas.isEmpty ? nil : todas
    }

    /// Antes de conferir a passphrase desta carteira: conta a tentativa (gravada antes da
    /// conferencia). Sem gravar, nao confere.
    static func comecar(_ carteira: UUID, criacao: Bool = false) throws {
        if criacao, !rigida(Sessao.shared.metadata), conta(Sessao.shared.metadata, carteira, criacao: true)?.idle(for: esquecerCriacaoDepois) == true {
            try? Sessao.shared.alterar { gravar(&$0, carteira, nil, criacao: true) }
        }
        let falta = restante(carteira, criacao: criacao)
        if falta > 0 { throw Espera(ate: Date().addingTimeInterval(falta)) }
        try Sessao.shared.alterar { metadata in
            var estado = conta(metadata, carteira, criacao: criacao) ?? PassphraseGuard()
            estado.failures += 1
            if criacao { estado.markAttempt() }
            // A espera nasce junto com a contagem, antes da conferencia: o desfecho que nao chega a
            // `errou` (o processo morto no meio) nao deixa o contador sem espera. Acertar zera tudo, e
            // a tentativa devolvida leva a espera junto (revisao de seguranca de 27/10/2026).
            let limite = limites(criacao: criacao, metadata)
            if estado.failures >= limite.livres {
                estado.startLock(seconds: min(primeiraEspera * pow(2, Double(estado.failures - limite.livres)), limite.maior))
            }
            gravar(&metadata, carteira, estado, criacao: criacao)
        }
    }

    /// Nada foi conferido (o dono cancelou, ou o cofre parou antes): a tentativa volta.
    static func devolver(_ carteira: UUID, criacao: Bool = false) {
        do {
            try Sessao.shared.alterar { metadata in
                guard var estado = conta(metadata, carteira, criacao: criacao), estado.failures > 0 else { return }
                estado.failures -= 1
                // A espera desta tentativa sai com ela: a de antes ja tinha vencido, ou `comecar` nao deixaria.
                estado.clearLock()
                gravar(&metadata, carteira, estado, criacao: criacao)
            }
        } catch Sessao.Falha.travada {
            depois(carteira, criacao, .devolver)
        } catch {}
    }

    /// Acertou: a conta desta carteira zera, e so ela.
    static func passou(_ carteira: UUID) {
        guard Sessao.shared.fase == .unlocked else { return depois(carteira, false, .passou) }
        guard conta(Sessao.shared.metadata, carteira) != nil else { return }
        do {
            try Sessao.shared.alterar { gravar(&$0, carteira, nil) }
        } catch Sessao.Falha.travada {
            depois(carteira, false, .passou)
        } catch {}
    }

    /// Errou (a tentativa ja foi contada): passado o limite, comeca a espera.
    static func errou(_ carteira: UUID, criacao: Bool = false) {
        do {
            try Sessao.shared.alterar { metadata in
                var estado = conta(metadata, carteira, criacao: criacao) ?? PassphraseGuard(failures: 1)
                let limite = limites(criacao: criacao, metadata)
                guard estado.failures >= limite.livres else { return }
                let extra = Double(estado.failures - limite.livres)
                estado.startLock(seconds: min(primeiraEspera * pow(2, extra), limite.maior))
                gravar(&metadata, carteira, estado, criacao: criacao)
            }
        } catch Sessao.Falha.travada {
            depois(carteira, criacao, .errou)
        } catch {}
    }

    /// Travou entre contar e saber o resultado: os metadados sairam da memoria, e devolver, zerar
    /// ou comecar a espera ali nao gravava nada. Sem a espera gravada, travar no meio de cada
    /// conferencia deixava chutar sem esperar (caca de bugs de 25/10/2026, B2). O resultado fica
    /// aqui e vale no proximo destravar; se o processo morrer antes, a tentativa segue contada.
    private enum Resultado { case devolver, passou, errou }
    nonisolated(unsafe) private static var pendentes: [(carteira: UUID, criacao: Bool, resultado: Resultado)] = []

    private static func depois(_ carteira: UUID, _ criacao: Bool, _ resultado: Resultado) {
        trava.withLock { pendentes.append((carteira, criacao, resultado)) }
    }

    /// Destravou: vale o que ficou esperando.
    static func aplicarPendentes() {
        let lista = trava.withLock { () -> [(carteira: UUID, criacao: Bool, resultado: Resultado)] in
            defer { pendentes = [] }
            return pendentes
        }
        let carteiras = Set(Sessao.shared.metadata.wallets.map(\.id))
        for item in lista where carteiras.contains(item.carteira) {
            switch item.resultado {
            case .devolver: devolver(item.carteira, criacao: item.criacao)
            case .passou: passou(item.carteira)
            case .errou: errou(item.carteira, criacao: item.criacao)
            }
        }
    }

    /// A carteira saiu deste celular: a conta dela sai junto.
    /// A carteira saiu deste celular: a conta dela sai junto, e a copia da folga, zerada.
    static func esquecer(_ metadata: inout Metadata, _ carteira: UUID) {
        encerrarFolga(carteira)
        metadata.settings.passphraseGuards?[chave(carteira, false)] = nil
        metadata.settings.passphraseGuards?[chave(carteira, true)] = nil
        if metadata.settings.passphraseGuards?.isEmpty == true { metadata.settings.passphraseGuards = nil }
    }

    /// Quanto falta da espera desta carteira, no relogio monotono. De outro boot, ela recomeca cheia.
    static func restante(_ carteira: UUID, criacao: Bool = false) -> TimeInterval {
        guard var estado = conta(Sessao.shared.metadata, carteira, criacao: criacao), estado.lockUptimeDeadline != nil else { return 0 }
        let limite = limites(criacao: criacao, Sessao.shared.metadata)
        let cheia = min(primeiraEspera * pow(2, Double(max(estado.failures - limite.livres, 0))), limite.maior)
        let boot = PINPolicy.bootSession
        if boot == PINPolicy.unknownBoot {
            return max(0, (estado.lockedUntil ?? .distantPast).timeIntervalSinceNow)
        }
        if !PINPolicy.isSameBoot(estado.lockBoot.flatMap(Hex.decode) ?? [], boot) {
            estado.startLock(seconds: cheia)
            try? Sessao.shared.alterar { gravar(&$0, carteira, estado, criacao: criacao) }
            return cheia
        }
        let falta = min(cheia, (estado.lockUptimeDeadline ?? 0) - PINPolicy.uptime)
        if falta <= 0 {
            estado.clearLock()
            try? Sessao.shared.alterar { gravar(&$0, carteira, estado, criacao: criacao) }
            return 0
        }
        return falta
    }
}

struct PassphraseGuard: Codable, Equatable {
    var failures = 0
    /// So para mostrar a hora; quem decide e o prazo monotono.
    var lockedUntil: Date?
    var lockUptimeDeadline: TimeInterval?
    var lockBoot: String?
    /// A ultima tentativa na porta de abrir ou criar com passphrase, que zera depois de um dia
    /// sem tentar (caca de bugs de 25/10/2026, B1). No relogio monotono, com o boot: adiantar a
    /// hora do aparelho nao zera a conta. Opcionais para os metadados gravados antes.
    var lastAttemptAt: Date?
    var lastAttemptUptime: TimeInterval?
    var lastAttemptBoot: String?

    mutating func startLock(seconds: TimeInterval) {
        lockedUntil = Date().addingTimeInterval(seconds)
        lockUptimeDeadline = PINPolicy.uptime + seconds
        lockBoot = Hex.encode(PINPolicy.bootSession)
    }

    mutating func clearLock() {
        lockedUntil = nil
        lockUptimeDeadline = nil
        lockBoot = nil
    }

    mutating func markAttempt() {
        lastAttemptAt = Date()
        lastAttemptUptime = PINPolicy.uptime
        lastAttemptBoot = Hex.encode(PINPolicy.bootSession)
    }

    /// Passou `interval` sem tentar? Medido neste boot; de outro boot nao da para medir, e a conta
    /// segue ate a proxima tentativa recomecar o relogio (falha para o lado de esperar mais). Sem a
    /// identidade do boot, vale o relogio de parede, como na espera.
    func idle(for interval: TimeInterval) -> Bool {
        let boot = PINPolicy.bootSession
        if boot == PINPolicy.unknownBoot { return Date().timeIntervalSince(lastAttemptAt ?? Date()) >= interval }
        guard let uptime = lastAttemptUptime, PINPolicy.isSameBoot(lastAttemptBoot.flatMap(Hex.decode) ?? [], boot) else { return false }
        return PINPolicy.uptime - uptime >= interval
    }
}
