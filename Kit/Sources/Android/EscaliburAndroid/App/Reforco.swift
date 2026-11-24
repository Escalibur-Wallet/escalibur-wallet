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
        /// "Bloquear as carteiras" sem nenhuma carteira com palavras: nao ha papel a conferir.
        case semCarteiras
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
        /// O que recusa esta carteira no Super Security, ja sabido pelos metadados: a tela diz antes das palavras e do PIN.
        let aviso: String?
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
        /// Carteira nova com palavras recusa ("Bloquear as carteiras", ou o cofre que nao diz): a regra do nucleo, que falha
        /// fechada, para a tela avisar antes das palavras (revisao de seguranca de 06/11/2026).
        let bloqueado: Bool
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
                Carteira(id: $0.id.uuidString, nome: $0.name, palavras: $0.wordCount ?? 12, temPassphrase: $0.hasPassphrase, conferida: digitadas.contains($0.id),
                         aviso: PortaDaPassphrase.semConferencia($0) ? String(format: Textos.t("A passphrase de %@ não pode ser conferida por esta versão do app, e no Super Security a cópia é o único caminho de volta: com ela aqui, o Super Security recusa. As palavras com a passphrase continuam abrindo a carteira em qualquer carteira BIP-39."), $0.name)
                             : $0.hasPassphrase && $0.legacyCardanoPassphrase == true
                                 ? String(format: Textos.t("A passphrase de %@ foi gravada por uma versão anterior do app, e restaurada pelas palavras a conta da Cardano dela muda. Mova o saldo dela para outra carteira e crie a carteira com passphrase de novo."), $0.name) : nil)
            },
            bloqueado: Sessao.shared.adicionarBloqueado
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
        // A rodada antes do PBKDF2: sair do app ou travar no meio (que esquece as frases) nao deixa esta para tras.
        let rodada = trava.withLock { rodadaDasFrases }
        let segredo: WalletSecret
        do { segredo = try Importacao.segredo(frase, passphrase: passphrase) } catch {
            passphrase?.wipe()
            throw error
        }
        passphrase?.wipe()
        let guardou = trava.withLock { () -> Bool in
            guard rodadaDasFrases == rodada else { return false }
            frases[id]?.wipe()
            frases[id] = segredo
            return true
        }
        guard guardou else {
            segredo.wipe()
            throw Sessao.Falha.travada
        }
        // Travou enquanto a frase era conferida: o travar() ja zerou as frases, e esta sai tambem.
        guard Sessao.shared.fase == .unlocked else {
            esquecerFrases()
            throw Sessao.Falha.travada
        }
    }

    /// Soma um a cada esquecer: a frase que termina de ser guardada depois disso nao fica.
    nonisolated(unsafe) private static var rodadaDasFrases = 0

    static func esquecerFrases() {
        trava.withLock {
            rodadaDasFrases &+= 1
            frases.values.forEach { $0.wipe() }
            frases = [:]
        }
    }

    /// A conferencia pronta: o que roda dentro do cofre e as frases que ele le, tiradas da lista, que quem chama zera ao terminar.
    private struct Conferencia {
        let check: (SecureBytes) throws -> Void
        let digitadas: [UUID: WalletSecret]

        func zerar() { digitadas.values.forEach { $0.wipe() } }
    }

    /// A conferencia que roda sob a trava do cofre, com a RK aberta: so o `WalletVault`, nunca o
    /// `RootKeyVault`. Indo para o bloqueio, a frase de cada carteira tem de bater com a guardada
    /// (o papel passa a ser o unico caminho de volta), e a passphrase digitada, com a raiz e a conta
    /// da Cardano da criacao: o cofre nao a tem (05/11/2026). Ao ligar, em qualquer politica, e na ida para o
    /// bloqueio, a passphrase gravada fora de NFKD por uma versao anterior, ou que esta versao nao confere, recusa.
    private static func conferencia(_ politica: Politica, carteiras: [WalletMeta]) throws -> Conferencia {
        // O que recusa sem ler frase vem antes de tirar as frases da lista.
        if politica == .lock {
            guard !carteiras.isEmpty else { throw Falha.semCarteiras }
            let guardadas = trava.withLock { Set(frases.keys) }
            guard carteiras.allSatisfy({ guardadas.contains($0.id) }) else { throw Falha.faltamPalavras }
        }
        // A que esta versao nao confere nao vale como copia (`passphraseUnverified`).
        if carteiras.contains(where: PortaDaPassphrase.semConferencia) { throw PortaDaPassphrase.SemConferencia() }
        if let antiga = carteiras.first(where: { $0.hasPassphrase && $0.legacyCardanoPassphrase == true }) {
            throw Falha.passphraseAntiga(antiga.name)
        }
        // So na ida para o bloqueio, a unica que le as frases, elas saem da lista em vez de copiadas (uma so na memoria):
        // sair do app no meio nao toca no que a conferencia le, e quem chama as zera ao terminar (revisao de 05/11/2026).
        let digitadas = politica != .lock ? [:] : trava.withLock { () -> [UUID: WalletSecret] in
            let tiradas = frases
            frases = [:]
            rodadaDasFrases &+= 1
            return tiradas
        }
        // Sair do app entre a conferencia de cima e a tirada esquece as frases: confere de novo nas tiradas.
        if politica == .lock, !carteiras.allSatisfy({ digitadas[$0.id] != nil }) {
            digitadas.values.forEach { $0.wipe() }
            throw Falha.faltamPalavras
        }
        return Conferencia(check: { rk in
            // A que ainda esta no cofre fora de NFKD, com a marca que nao chegou a ser gravada, recusa tambem.
            for carteira in carteiras where carteira.hasPassphrase {
                if case .present(legacy: true, _) = try Chaves.wallets.storedPassphrase(walletID: carteira.id, rk: rk) {
                    throw Falha.passphraseAntiga(carteira.name)
                }
            }
            guard politica == .lock else { return }
            for carteira in carteiras {
                guard let digitada = digitadas[carteira.id] else { throw Falha.faltamPalavras }
                let guardada = try Chaves.wallets.open(walletID: carteira.id, rk: rk)
                defer { guardada.wipe() }
                // A entropia, nao as palavras: nenhuma frase vira String, e o idioma vem junto.
                guard guardada.language == digitada.language, Hash.constantTimeEqual(guardada.entropy, digitada.entropy) else {
                    throw Falha.naoConfere(carteira.name)
                }
                if carteira.hasPassphrase {
                    switch try PortaDaPassphrase.confere(guardada, digitada.passphrase, carteira, cardano: true) {
                    case .mismatch: throw Falha.naoConfere(carteira.name)
                    case .legacy: throw Falha.passphraseAntiga(carteira.name)
                    case .match: break
                    }
                }
            }
        }, digitadas: digitadas)
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
        let conferida = try conferencia(politica, carteiras: carteiras)
        defer { conferida.zerar() }
        do {
            try Chaves.root.enableHardened(pin: pin, reason: Textos.t("Ligar o Super Security"),
                                           confirmReason: Textos.t("Confirme a biometria para conferir o Super Security"),
                                           faceChange: politica, check: conferida.check)
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
        // So a ida para o bloqueio confere (como no iPhone): trocar entre as outras politicas, ou sair do bloqueio, nao poe nem
        // tira carteira do Super Security, e sair do bloqueio e a direcao que diminui o risco de perda.
        let conferida = politica == .lock ? try conferencia(.lock, carteiras: carteirasComFrase()) : nil
        defer { conferida?.zerar() }
        do {
            try Chaves.root.setHardenedFaceChange(politica, pin: pin, reason: Textos.t("Mudar o que acontece quando a biometria mudar"),
                                                  confirmReason: Textos.t("Confirme a biometria para conferir o Super Security"),
                                                  check: conferida?.check ?? { _ in })
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
