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

    static func emFolga(_ id: UUID) -> Bool { trava.withLock { (folgaAte[id] ?? 0) > PINPolicy.uptime } }

    /// O assinador conferiu: a folga escolhida na folha comeca agora, so na memoria.
    static func comecarFolga(_ id: UUID, minutos: Int?) {
        guard let minutos, escolhasDeFolga.contains(minutos) else { return }
        trava.withLock { folgaAte[id] = PINPolicy.uptime + TimeInterval(minutos * 60) }
    }

    /// Travar encerra toda folga: quem destrava com o PIN depois nao pula a passphrase.
    static func encerrarFolgas() { trava.withLock { folgaAte = [:] } }

    struct Espera: Error { let ate: Date }

    /// Antes de conferir: conta a tentativa (gravada antes da conferencia). Sem gravar, nao confere.
    static func comecar() throws {
        let falta = restante()
        if falta > 0 { throw Espera(ate: Date().addingTimeInterval(falta)) }
        try Sessao.shared.alterar { metadata in
            var estado = metadata.settings.passphraseGuard ?? PassphraseGuard()
            estado.failures += 1
            metadata.settings.passphraseGuard = estado
        }
    }

    /// O dono cancelou antes de o cofre abrir: nada foi conferido, a tentativa volta.
    static func devolver() {
        try? Sessao.shared.alterar { metadata in
            guard var estado = metadata.settings.passphraseGuard, estado.failures > 0 else { return }
            estado.failures -= 1
            metadata.settings.passphraseGuard = estado
        }
    }

    static func passou() {
        guard Sessao.shared.metadata.settings.passphraseGuard != nil else { return }
        try? Sessao.shared.alterar { $0.settings.passphraseGuard = nil }
    }

    /// Errou (a tentativa ja foi contada): passado o limite, comeca a espera.
    static func errou() {
        try? Sessao.shared.alterar { metadata in
            var estado = metadata.settings.passphraseGuard ?? PassphraseGuard(failures: 1)
            guard estado.failures >= errosLivres else { return }
            let extra = Double(estado.failures - errosLivres)
            estado.startLock(seconds: min(primeiraEspera * pow(2, extra), maiorEspera))
            metadata.settings.passphraseGuard = estado
        }
    }

    /// Quanto falta da espera, no relogio monotono. De outro boot, ela recomeca cheia.
    static func restante() -> TimeInterval {
        guard var estado = Sessao.shared.metadata.settings.passphraseGuard, estado.lockUptimeDeadline != nil else { return 0 }
        let cheia = min(primeiraEspera * pow(2, Double(max(estado.failures - errosLivres, 0))), maiorEspera)
        let boot = PINPolicy.bootSession
        if boot == PINPolicy.unknownBoot {
            return max(0, (estado.lockedUntil ?? .distantPast).timeIntervalSinceNow)
        }
        if !PINPolicy.isSameBoot(estado.lockBoot.flatMap(Hex.decode) ?? [], boot) {
            estado.startLock(seconds: cheia)
            try? Sessao.shared.alterar { $0.settings.passphraseGuard = estado }
            return cheia
        }
        let falta = min(cheia, (estado.lockUptimeDeadline ?? 0) - PINPolicy.uptime)
        if falta <= 0 {
            estado.clearLock()
            try? Sessao.shared.alterar { $0.settings.passphraseGuard = estado }
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
}
