import EscaliburCore
import EscaliburKeys
import EscaliburNetwork
import Foundation

/// O Super Security (modo reforcado, docs/seguranca.md §2.6) no Android: abrir o app, assinar e
/// ver as palavras pedem o PIN e a biometria juntos, pela criptografia. O cofre e o do iOS; aqui,
/// o que a tela pede (o retrato, ligar, desligar e a politica de quando a biometria mudar) e a
/// conferencia das palavras de cada carteira na ida para "Bloquear as carteiras".
enum Reforco {
    enum Falha: Error {
        /// O que foi digitado de uma carteira nao confere com a guardada.
        case naoConfere(String)
        /// A passphrase gravada fora de NFKD por uma versao anterior: o papel nao a traz inteira.
        case passphraseAntiga(String)
        /// "Bloquear as carteiras" sem as palavras de todas digitadas antes.
        case faltamPalavras
    }

    private static let trava = NSLock()
    /// As frases digitadas para a conferencia, ate ligar ou mudar a politica (ou desistir).
    nonisolated(unsafe) private static var frases: [UUID: WalletSecret] = [:]

    typealias Politica = RootKeyVault.HardenedFaceChange

    static func politica(_ texto: String?) -> Politica? {
        switch texto {
        case "continuar": return .continue
        case "esperar": return .wait
        case "bloquear": return .lock
        default: return nil
        }
    }

    static func nome(_ politica: Politica) -> String {
        switch politica {
        case .continue: return "continuar"
        case .wait: return "esperar"
        case .lock: return "bloquear"
        }
    }

    struct Carteira: Encodable {
        let id: String
        let nome: String
        let palavras: Int
        let temPassphrase: Bool
        let conferida: Bool
    }

    struct Retrato: Encodable {
        let ligado: Bool
        /// A politica em vigor (ligado) ou nil se o cofre nao diz.
        let politica: String?
        /// O que falta da espera de "Esperar 24 horas", em segundos.
        let espera: Double
        let biometriaLigada: Bool
        let biometriaPronta: Bool
        /// A primeira carteira sem a copia conferida: ligar espera por ela.
        let faltaCopia: String?
        let faltaCopiaID: String?
        let carteiras: [Carteira]
    }

    /// As carteiras que tem frase (as de observacao ficam de fora).
    private static func carteirasComFrase() -> [WalletMeta] {
        Sessao.shared.metadata.wallets.filter { !$0.isWatchOnly }
    }

    static func retrato() -> Retrato {
        let root = Chaves.root
        let ligado = root.securityMode == .hardened
        let carteiras = carteirasComFrase()
        let falta = carteiras.first { !$0.hasBackup }
        let digitadas = trava.withLock { Set(frases.keys) }
        return Retrato(
            ligado: ligado, politica: ligado ? root.hardenedFaceChange.map(nome) : nil, espera: max(0, root.hardenedHoldRemaining),
            biometriaLigada: root.isBiometryEnabled, biometriaPronta: KeyPlatform.current.biometry() == .ready,
            faltaCopia: falta?.name, faltaCopiaID: falta?.id.uuidString,
            carteiras: carteiras.map {
                Carteira(id: $0.id.uuidString, nome: $0.name, palavras: $0.wordCount ?? 12, temPassphrase: $0.hasPassphrase, conferida: digitadas.contains($0.id))
            }
        )
    }

    /// Guarda a frase digitada de uma carteira para a conferencia dentro do cofre. A frase ja
    /// passou pela validacao da tela; aqui vira o segredo (entropia e idioma), sem String.
    static func guardarFrase(_ id: UUID, frase: SecureBytes, passphrase: SecureBytes?) throws {
        guard carteirasComFrase().contains(where: { $0.id == id }) else {
            frase.wipe()
            passphrase?.wipe()
            throw Sessao.Falha.carteiraNaoEncontrada
        }
        let segredo: WalletSecret
        do { segredo = try Importacao.segredo(frase, passphrase: passphrase) } catch {
            passphrase?.wipe()
            throw error
        }
        passphrase?.wipe()
        trava.withLock {
            frases[id]?.wipe()
            frases[id] = segredo
        }
        // Travou enquanto a frase era conferida: o travar() ja zerou as frases, e esta sai tambem.
        guard Sessao.shared.fase == .unlocked else {
            esquecerFrases()
            throw Sessao.Falha.travada
        }
    }

    static func esquecerFrases() {
        trava.withLock {
            frases.values.forEach { $0.wipe() }
            frases = [:]
        }
    }

    /// A conferencia que roda sob a trava do cofre, com a RK aberta: so o `WalletVault`, nunca o
    /// `RootKeyVault`. Indo para o bloqueio, a frase de cada carteira tem de bater com a guardada
    /// (o papel passa a ser o unico caminho de volta); nas outras politicas, so a passphrase
    /// gravada fora de NFKD por uma versao anterior recusa.
    private static func conferencia(_ politica: Politica, carteiras: [WalletMeta]) throws -> (SecureBytes) throws -> Void {
        let digitadas = trava.withLock { frases }
        if politica == .lock {
            guard carteiras.allSatisfy({ digitadas[$0.id] != nil }) else { throw Falha.faltamPalavras }
        }
        return { rk in
            for carteira in carteiras {
                let guardada = try Chaves.wallets.open(walletID: carteira.id, rk: rk)
                defer { guardada.wipe() }
                let salva = BIP39.nfkd(guardada.passphrase)
                defer { salva.wipe() }
                if politica == .lock, let digitada = digitadas[carteira.id] {
                    // A entropia, nao as palavras: nenhuma frase vira String, e o idioma vem junto.
                    guard guardada.language == digitada.language, Hash.constantTimeEqual(guardada.entropy, digitada.entropy) else {
                        throw Falha.naoConfere(carteira.name)
                    }
                    if carteira.hasPassphrase {
                        guard Hash.constantTimeEqual(salva, digitada.passphrase) else { throw Falha.naoConfere(carteira.name) }
                    }
                }
                if carteira.hasPassphrase {
                    guard Hash.constantTimeEqual(salva, guardada.passphrase) else { throw Falha.passphraseAntiga(carteira.name) }
                }
            }
        }
    }

    /// Ligar: o cofre pede o PIN e a biometria do slot de hoje, roda a conferencia, grava o
    /// registro novo, abre de novo com o PIN e a biometria e so entao apaga o slot so-PIN.
    static func ligar(_ politica: Politica, pin: SecureBytes) throws {
        defer {
            pin.wipe()
            esquecerFrases()
        }
        let carteiras = carteirasComFrase()
        guard !carteiras.isEmpty, carteiras.allSatisfy(\.hasBackup) else { throw Sessao.Falha.copiaPendente }
        let check = try conferencia(politica, carteiras: carteiras)
        do {
            try Chaves.root.enableHardened(pin: pin, reason: Textos.t("Ligar o Super Security"),
                                           confirmReason: Textos.t("Confirme a biometria para conferir o Super Security"),
                                           faceChange: politica, check: check)
        } catch RootKeyVault.Failure.wiped {
            Sessao.shared.apagarTudo()
            throw RootKeyVault.Failure.wiped
        }
        try? Sessao.shared.alterar { $0.settings.biometryEnabled = false }
    }

    /// Desligar: o slot do PIN e a biometria voltam, conferidos. Devolve se a biometria voltou.
    static func desligar(pin: SecureBytes) throws -> Bool {
        defer { pin.wipe() }
        let voltou: Bool
        do {
            voltou = try Chaves.root.disableHardened(pin: pin, reason: Textos.t("Desligar o Super Security"),
                                                     biometryReason: Textos.t("Confirme a biometria para religar"))
        } catch RootKeyVault.Failure.wiped {
            Sessao.shared.apagarTudo()
            throw RootKeyVault.Failure.wiped
        }
        try? Sessao.shared.alterar { $0.settings.biometryEnabled = voltou }
        return voltou
    }

    /// Mudar o que acontece quando a biometria muda: o PIN e a biometria, as palavras de cada
    /// carteira so na ida para o bloqueio, e a biometria de novo para conferir o registro novo.
    static func mudarPolitica(_ politica: Politica, pin: SecureBytes) throws {
        defer {
            pin.wipe()
            esquecerFrases()
        }
        let check = try conferencia(politica, carteiras: carteirasComFrase())
        do {
            try Chaves.root.setHardenedFaceChange(politica, pin: pin, reason: Textos.t("Mudar o que acontece quando a biometria mudar"),
                                                  confirmReason: Textos.t("Confirme a biometria para conferir o Super Security"), check: check)
        } catch RootKeyVault.Failure.wiped {
            Sessao.shared.apagarTudo()
            throw RootKeyVault.Failure.wiped
        }
    }

    static func chamar(_ metodo: String, _ pedido: JSONValue, segredo: () throws -> SecureBytes, segundo: () throws -> SecureBytes?) throws -> Data {
        switch metodo {
        case "reforco.estado":
            return try Nucleo.json(retrato())
        case "reforco.esquecer":
            esquecerFrases()
            return try Nucleo.json(retrato())
        case "reforco.guardarFrase":
            let id = try Nucleo.uuid(pedido["id"])
            let frase = try segredo()
            try guardarFrase(id, frase: frase, passphrase: try segundo())
            return try Nucleo.json(retrato())
        case "reforco.ligar":
            guard let alvo = politica(pedido["politica"]?.stringValue) else { throw Nucleo.Falha(erro: "reforco.politica") }
            try ligar(alvo, pin: try segredo())
            return try Nucleo.json(retrato())
        case "reforco.desligar":
            let voltou = try desligar(pin: try segredo())
            return try Nucleo.json(["biometria": voltou])
        case "reforco.politica":
            guard let alvo = politica(pedido["politica"]?.stringValue) else { throw Nucleo.Falha(erro: "reforco.politica") }
            try mudarPolitica(alvo, pin: try segredo())
            return try Nucleo.json(retrato())
        default:
            throw Nucleo.Falha(erro: "metodoDesconhecido")
        }
    }
}
