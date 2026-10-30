import EscaliburCore
import EscaliburKeys
import Foundation

/// A passphrase antes de mover saldo (o `PassphraseGate` do iOS, sem a folha): a carteira com
/// passphrase e "Pedir a passphrase para enviar" pede ela antes da biometria ou do PIN. A
/// conferencia e do assinador (`Signer.sign`, NFKD e tempo constante); aqui ficam a conta das
/// tentativas, a espera depois dos erros e a folga de alguns minutos depois de acertar.
enum PortaDaPassphrase {
    private static let trava = NSLock()
    nonisolated(unsafe) private static var folgaAte: [UUID: TimeInterval] = [:]

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

    static func pede(_ wallet: WalletMeta?) -> Bool {
        guard let wallet, wallet.hasPassphrase, !wallet.isWatchOnly else { return false }
        return wallet.passphraseToSend ?? true
    }

    static func precisa(_ wallet: WalletMeta?) -> Bool {
        guard let wallet, pede(wallet) else { return false }
        return !emFolga(wallet.id)
    }

    /// A passphrase digitada confere com a do cofre? As duas em NFKD, em tempo constante: a mesma
    /// regra do assinador.
    static func confere(_ guardada: SecureBytes, _ digitada: SecureBytes) -> Bool {
        let a = BIP39.nfkd(guardada), b = BIP39.nfkd(digitada)
        defer { a.wipe(); b.wipe() }
        return a.count > 0 && Hash.constantTimeEqual(a, b)
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

    /// Cabe no cofre: 256 bytes depois do NFKD, onde uma letra com acento ocupa tres.
    static func cabe(_ segredo: SecureBytes) -> Bool {
        let normalizada = BIP39.nfkd(segredo)
        defer { normalizada.wipe() }
        return normalizada.count <= WalletVault.maxPassphraseBytes
    }

    static func emFolga(_ id: UUID) -> Bool { trava.withLock { (folgaAte[id] ?? 0) > PINPolicy.uptime } }

    /// O assinador conferiu: a folga escolhida na folha comeca agora, so na memoria.
    static func comecarFolga(_ id: UUID, minutos: Int?) {
        guard let minutos, escolhasDeFolga.contains(minutos) else { return }
        trava.withLock { folgaAte[id] = PINPolicy.uptime + TimeInterval(minutos * 60) }
    }

    /// Travar encerra toda folga: quem destrava com o PIN depois nao pula a passphrase.
    static func encerrarFolgas() { trava.withLock { folgaAte = [:] } }

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
    static func esquecer(_ metadata: inout Metadata, _ carteira: UUID) {
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
