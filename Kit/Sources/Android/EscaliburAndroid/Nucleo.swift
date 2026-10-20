import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import EscaliburNetwork
import Foundation

/// Os metodos que o app Android chama pela ponte. Cada um recebe e devolve JSON. O que e segredo
/// (PIN, frase, passphrase) chega separado, em bytes (`chamarComSegredo`), e nunca volta.
enum Nucleo {
    struct Falha: Error, Encodable {
        let erro: String
    }

    static func chamar(_ metodo: String, _ entrada: Data) throws -> Data {
        let pedido = (try? JSONDecoder().decode(JSONValue.self, from: entrada)) ?? .object([:])
        switch metodo {
        case "iniciar":
            if let pasta = pedido["pasta"]?.stringValue { MetadataStore.directory = URL(fileURLWithPath: pasta) }
            if let recursos = pedido["recursos"]?.stringValue { CoreResources.directory = recursos }
            if case .object(let tabela)? = pedido["textos"] {
                // A tabela do idioma do aparelho: os textos do nucleo (kitText) e os do app.
                let textos = tabela.compactMapValues(\.stringValue)
                Textos.instalar(textos)
                KitText.install(textos)
            }
            if let numeros = pedido["numeros"], let decimal = numeros["decimal"]?.stringValue, let grupo = numeros["grupo"]?.stringValue {
                NumberStyle.adopt(NumberStyle(
                    decimal: decimal, groupSeparator: grupo,
                    primaryGroup: Int(numeros["grupoPrimario"]?.doubleValue ?? 3), secondaryGroup: Int(numeros["grupoSecundario"]?.doubleValue ?? 3),
                    dateFormat: numeros["data"]?.stringValue ?? "dd/MM/yyyy HH:mm"
                ))
            }
            Sessao.shared.abrirProcesso()
            return try json(Estado.agora())
        case "estado":
            return try json(Estado.agora())
        case "versao":
            return try json(Versao(nucleo: "1.0.0", redes: Chain.all.count))
        case "redes":
            return try json(Chain.all.map(RedeResumo.init))

        case "sessao.travar":
            Sessao.shared.travar()
            return try json(Estado.agora())
        case "sessao.segundoPlano":
            Sessao.shared.foiParaSegundoPlano()
            return try json(["ok": true])
        case "sessao.primeiroPlano":
            Sessao.shared.voltouAoPrimeiroPlano()
            return try json(Estado.agora())
        case "sessao.apagarTudo":
            // So da tela de "Esqueci o PIN", depois da confirmacao: apaga cofre e metadados.
            Sessao.shared.apagarTudo()
            return try json(Estado.agora())
        case "sessao.destrancarBiometria":
            try Sessao.shared.destrancarComBiometria()
            return try json(Estado.agora())
        case "sessao.aceitarResponsabilidade":
            try Sessao.shared.aceitarResponsabilidade(versao: Int(pedido["versao"]?.doubleValue ?? 1))
            return try json(Estado.agora())

        case "carteira.palavras":
            let de = Int(pedido["de"]?.doubleValue ?? 0), ate = Int(pedido["ate"]?.doubleValue ?? 0)
            return try json(Sessao.shared.comRascunho { $0.palavras(max(0, de)..<max(de, ate)) })
        case "carteira.conferir":
            let indice = Int(pedido["indice"]?.doubleValue ?? -1)
            let palavra = pedido["palavra"]?.stringValue ?? ""
            return try json(["confere": Sessao.shared.comRascunho { $0.confere(palavra, em: indice) }])
        case "carteira.confirmarCopia":
            try Sessao.shared.confirmarCopia(try uuid(pedido["id"]))
            return try json(Estado.agora())
        case "carteira.descartarRascunho":
            Sessao.shared.descartarRascunho()
            return try json(["ok": true])
        case "carteira.selecionar":
            try Sessao.shared.selecionar(try uuid(pedido["id"]))
            return try json(Estado.agora())
        case "carteira.renomear":
            let nome = String((pedido["nome"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
            guard !nome.isEmpty else { throw Falha(erro: "nome vazio") }
            try Sessao.shared.atualizar(try uuid(pedido["id"])) { $0.name = nome }
            return try json(Estado.agora())
        case "carteira.sugestoes":
            // As palavras da lista que comecam com o que foi digitado, e as letras que ainda
            // levam a alguma (o teclado proprio apaga as outras). So o pedaco digitado.
            let digitado = pedido["digitado"]?.stringValue ?? ""
            return try json(Sugestoes(palavras: WordLexicon.completions(digitado), letras: WordLexicon.nextLetters(after: digitado).map(String.init).sorted()))

        case "receber.moedas":
            return try json(Receber.moedas())
        case "receber.endereco":
            return try json(try Receber.endereco(ativo: pedido["ativo"]?.stringValue ?? ""))

        case let envio where envio.hasPrefix("envio."):
            return try Envio.chamar(envio, pedido)

        case "saldos.mostrar":
            return try json(Saldos.shared.mostrar())
        case "saldos.atualizar":
            let forcar = pedido["forcar"]?.boolValue ?? false
            esperarSemErro { await Saldos.shared.atualizar(forcar: forcar) }
            return try json(Saldos.shared.retratoAtual())

        case "ajustes.unidade":
            let unidade = pedido["unidade"]?.stringValue ?? "usd"
            guard ["brl", "usd", "eur", "btc"].contains(unidade) else { throw Falha(erro: "unidade desconhecida") }
            try Sessao.shared.alterar { metadata in
                if metadata.settings.choose(unidade) { metadata.quoteCache = [:] }
            }
            return try json(Estado.agora())
        case "ajustes.ocultarSaldos":
            let ocultar = pedido["ocultar"]?.boolValue ?? false
            try Sessao.shared.alterar { $0.settings.hideBalances = ocultar }
            return try json(Estado.agora())
        case "ajustes.autoTravar":
            let segundos = Int(pedido["segundos"]?.doubleValue ?? 60)
            try Sessao.shared.alterar { $0.settings.autoLockSeconds = max(0, min(segundos, 3600)) }
            return try json(Estado.agora())

        #if DEBUG
        case "saldo":
            let rede = pedido["rede"]?.stringValue ?? ""
            let enderecos = pedido["enderecos"]?.arrayValue?.compactMap(\.stringValue) ?? []
            guard let chain = Chain.all.first(where: { $0.id == rede }) else { throw Falha(erro: "rede desconhecida: \(rede)") }
            return try json(esperar { try await BalanceService.shared.balance(chain: chain, addresses: enderecos) })
        case "tls.teste":
            return try json(esperar { await TesteTLS.rodar() })
        case "cofre.teste":
            return try json(TesteCofre.rodar(biometria: pedido["biometria"]?.boolValue ?? false, etapa: pedido["etapa"]?.stringValue ?? "completo"))
        #endif
        default:
            throw Falha(erro: "metodo desconhecido: \(metodo)")
        }
    }

    /// As operacoes com segredo. O segredo vem dividido por quebra de linha: o PIN da credencial
    /// primeiro, quando ela e por PIN, e depois o que a operacao pede. Cada parte e zerada no fim,
    /// usada ou nao.
    static func chamarComSegredo(_ metodo: String, _ entrada: Data, _ segredo: SecureBytes) throws -> Data {
        let pedido = (try? JSONDecoder().decode(JSONValue.self, from: entrada)) ?? .object([:])
        var partes = dividir(segredo)
        segredo.wipe()
        defer { partes.forEach { $0.wipe() } }
        func proxima() throws -> SecureBytes {
            guard !partes.isEmpty else { throw Falha(erro: "segredo incompleto") }
            return partes.removeFirst()
        }
        func credencial() throws -> Credencial {
            let motivo = pedido["credencial"]?["motivo"]?.stringValue ?? ""
            switch pedido["credencial"]?["tipo"]?.stringValue {
            case "pin": return .pin(try proxima())
            case "biometria": return .biometria(motivo: motivo)
            case "pinEBiometria": return .pinEBiometria(try proxima(), motivo: motivo)
            case "reforcado": return .reforcado(try proxima(), motivo: motivo)
            default: throw Falha(erro: "credencial desconhecida")
            }
        }

        switch metodo {
        case "sessao.cadastrarPIN":
            try Sessao.shared.cadastrarPIN(try proxima())
            return try json(Estado.agora())
        case "sessao.destrancar":
            try Sessao.shared.destrancar(pin: try proxima())
            return try json(Estado.agora())
        case "sessao.ligarBiometria":
            try Sessao.shared.ligarBiometria(pin: try proxima(), motivo: pedido["motivo"]?.stringValue ?? "")
            return try json(Estado.agora())
        case "sessao.desligarBiometria":
            try Sessao.shared.desligarBiometria(try credencial())
            return try json(Estado.agora())
        case "sessao.trocarPIN":
            let atual = try credencial()
            try Sessao.shared.trocarPIN(atual, novo: try proxima())
            return try json(Estado.agora())

        case "carteira.criar":
            let palavras = Int(pedido["palavras"]?.doubleValue ?? 12)
            guard palavras == 12 || palavras == 24 else { throw Falha(erro: "12 ou 24 palavras") }
            let wallet = try Sessao.shared.criarCarteira(palavras: palavras, credencial: try credencial())
            return try json(CarteiraResumo(wallet, selecionada: true))
        case "carteira.criarComPalavras":
            let palavras = Int(pedido["palavras"]?.doubleValue ?? 12)
            guard palavras == 12 || palavras == 24 else { throw Falha(erro: "12 ou 24 palavras") }
            let cred = try credencial()
            let wallet = try Sessao.shared.criarComPalavras(try proxima(), palavras: palavras, credencial: cred)
            return try json(CarteiraResumo(wallet, selecionada: true))
        case "carteira.validarFrase":
            return try json(Importacao.validar(try proxima()))
        case "carteira.previa":
            let frase = try proxima()
            let passphrase = partes.isEmpty ? nil : try proxima()
            return try json(esperar { try await Importacao.previa(frase, passphrase: passphrase) })
        case "carteira.importar":
            let cred = try credencial()
            let frase = try proxima()
            let passphrase = partes.isEmpty ? nil : try proxima()
            let wallet = try Importacao.importar(
                frase, passphrase: passphrase, palavras: Int(pedido["palavras"]?.doubleValue ?? 12),
                tronComOutraChave: pedido["tronOutraChave"]?.boolValue ?? false, credencial: cred
            )
            return try json(CarteiraResumo(wallet, selecionada: true))
        case "envio.assinar":
            let cred = try credencial()
            let passphrase = partes.isEmpty ? nil : try proxima()
            return try Envio.assinar(cred, passphrase: passphrase, folga: pedido["folga"]?.doubleValue.map { Int($0) })
        case "carteira.remover":
            let id = try uuid(pedido["id"])
            // Remover pede a mesma presenca que ver as palavras: o cofre confere antes.
            try Sessao.shared.comChaveRaiz(try credencial()) { _ in }
            try Sessao.shared.remover(id)
            return try json(Estado.agora())
        default:
            throw Falha(erro: "metodo desconhecido: \(metodo)")
        }
    }

    /// O segredo em partes, separadas por quebra de linha. PIN, palavras e passphrase nunca tem
    /// quebra de linha (a interface nao deixa digitar).
    static func dividir(_ segredo: SecureBytes) -> [SecureBytes] {
        segredo.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var partes: [SecureBytes] = []
            var inicio = 0
            for indice in 0...bytes.count where indice == bytes.count || bytes[indice] == 0x0A {
                let parte = SecureBytes(capacity: max(indice - inicio, 1))
                if indice > inicio { parte.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[inicio..<indice])) }
                partes.append(parte)
                inicio = indice + 1
            }
            return partes
        }
    }

    static func uuid(_ valor: JSONValue?) throws -> UUID {
        guard let texto = valor?.stringValue, let id = UUID(uuidString: texto) else { throw Falha(erro: "id invalido") }
        return id
    }

    /// O erro como a interface le: um codigo estavel e, quando ha, o numero que a mensagem usa.
    static func erro(_ error: Error) -> Data {
        var saida: [String: JSONValue] = [:]
        switch error {
        case let falha as Falha:
            saida["erro"] = .string(falha.erro)
        case let falha as RootKeyVault.Failure:
            switch falha {
            case .wrongPIN(let restantes):
                saida["erro"] = .string("cofre.pinErrado")
                if let restantes { saida["restantes"] = .number(Double(restantes)) }
                let erros = Chaves.root.failureCount()
                saida["erros"] = .number(Double(erros))
                saida["proximaEspera"] = .number(PINPolicy.delay(afterFailures: erros + 1))
            case .throttled(let segundos):
                saida["erro"] = .string("cofre.espera")
                saida["segundos"] = .number(segundos)
            case .biometryHold(let segundos):
                saida["erro"] = .string("cofre.esperaDaBiometria")
                saida["segundos"] = .number(segundos)
            case .biometryNotConfirmed(let restantes):
                saida["erro"] = .string("cofre.biometriaNaoConfirmou")
                if let restantes { saida["restantes"] = .number(Double(restantes)) }
            case .hardenedBlocked(let motivo):
                saida["erro"] = .string("cofre.reforcadoBloqueado")
                saida["motivo"] = .string(String(describing: motivo))
            default:
                saida["erro"] = .string("cofre." + String(describing: falha))
            }
        case let falha as Sessao.Falha:
            switch falha {
            case .jaImportada(let nome):
                saida["erro"] = .string("sessao.jaImportada")
                saida["nome"] = .string(nome)
            default:
                saida["erro"] = .string("sessao." + String(describing: falha))
            }
        case let espera as PortaDaPassphrase.Espera:
            saida["erro"] = .string("passphrase.espera")
            saida["ate"] = .number(espera.ate.timeIntervalSince1970 * 1000)
        case let falha as Signer.Failure where falha == .passphraseMismatch:
            saida["erro"] = .string("passphrase.errada")
        case let falha as SendEngineError:
            saida["erro"] = .string("envio.motor")
            if let mensagem = falha.errorDescription { saida["mensagem"] = .string(mensagem) }
        case let fraca as BIP39.WeakChoice:
            saida["erro"] = .string("frase.fraca." + String(describing: fraca))
        case let falha as HTTPClient.Failure:
            saida["erro"] = .string("rede." + String(describing: falha))
        default:
            saida["erro"] = .string("falha")
        }
        #if DEBUG
        saida["detalhe"] = .string(String(String(describing: error).prefix(200)))
        #endif
        return (try? json(saida)) ?? Data(#"{"erro":"falha"}"#.utf8)
    }

    static func json<T: Encodable>(_ valor: T) throws -> Data {
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.sortedKeys]
        codificador.dateEncodingStrategy = .millisecondsSince1970
        return try codificador.encode(valor)
    }

    /// Para operacoes que nao lancam.
    static func esperarSemErro(_ operacao: @escaping @Sendable () async -> Void) {
        _ = try? esperar { await operacao() }
    }

    struct Versao: Encodable { let nucleo: String; let redes: Int }

    struct Sugestoes: Encodable { let palavras: [String]; let letras: [String] }

    struct RedeResumo: Encodable {
        let id: String, nome: String, familia: String, simbolo: String, coingecko: String, casas: Int
        init(_ chain: Chain) {
            id = chain.id
            nome = chain.name
            familia = chain.family.rawValue
            simbolo = chain.nativeSymbol
            coingecko = chain.coingeckoID
            casas = chain.nativeDecimals
        }
    }
}

/// O que a interface precisa saber para decidir a tela: fase, PIN, biometria, carteiras e ajustes.
struct Estado: Encodable {
    struct Biometria: Encodable {
        let ligada: Bool
        /// "pronta", "semCadastro", "indisponivel", "bloqueada".
        let sistema: String
        /// Ligada, mas o aparelho reiniciou e o PIN ainda nao foi digitado neste boot.
        let pedePINDepoisDeReiniciar: Bool
    }

    struct Ajustes: Encodable {
        let moeda: String
        let unidade: String
        let ocultarSaldos: Bool
        let autoTravar: Int
        let tecladoProprio: Bool
        let protecaoMEV: Bool
    }

    let fase: Sessao.Fase
    let pinDigitos: [Int]
    let biometria: Biometria
    let atraso: Double
    let erros: Int
    let reforcado: Bool
    let carteiras: [CarteiraResumo]
    let selecionada: String?
    let ajustes: Ajustes
    let responsabilidade: Int?

    static func agora() -> Estado {
        let root = Chaves.root
        let metadata = Sessao.shared.metadata
        let sistema: String
        switch KeyPlatform.current.biometry() {
        case .ready: sistema = "pronta"
        case .notEnrolled: sistema = "semCadastro"
        case .unavailable: sistema = "indisponivel"
        case .lockedOut: sistema = "bloqueada"
        }
        let selecionada = metadata.selectedWallet?.id
        return Estado(
            fase: Sessao.shared.fase,
            pinDigitos: root.pinLengths.sorted(),
            biometria: Biometria(ligada: root.isBiometryEnabled, sistema: sistema,
                                 pedePINDepoisDeReiniciar: root.isBiometryEnabled && !root.pinEnteredThisBoot),
            atraso: root.throttleRemaining(),
            erros: Int(root.failureCount()),
            reforcado: root.securityMode == .hardened,
            carteiras: metadata.wallets.map { CarteiraResumo($0, selecionada: $0.id == selecionada) },
            selecionada: selecionada?.uuidString,
            ajustes: Ajustes(
                moeda: metadata.settings.currency, unidade: metadata.settings.totalUnit ?? metadata.settings.currency,
                ocultarSaldos: metadata.settings.hideBalances, autoTravar: metadata.settings.autoLockSeconds,
                tecladoProprio: metadata.settings.ownKeyboard ?? true, protecaoMEV: metadata.settings.mevProtection
            ),
            responsabilidade: metadata.responsibilityVersion
        )
    }
}

struct CarteiraResumo: Encodable {
    struct Conta: Encodable { let rede: String; let endereco: String }

    let id: String
    let nome: String
    let observacao: Bool
    let palavras: Int?
    let origem: String
    let criada: Date
    let palavrasConfirmadas: Bool
    let temCopia: Bool
    let temPassphrase: Bool
    let passphraseConfirmada: Bool
    let tronOutraChave: Bool
    let selecionada: Bool
    let digital: String?
    let contas: [Conta]

    init(_ wallet: WalletMeta, selecionada: Bool) {
        id = wallet.id.uuidString
        nome = wallet.name
        observacao = wallet.isWatchOnly
        palavras = wallet.wordCount
        origem = wallet.origin.rawValue
        criada = wallet.createdAt
        palavrasConfirmadas = wallet.wordsConfirmed
        temCopia = wallet.hasBackup
        temPassphrase = wallet.hasPassphrase
        passphraseConfirmada = wallet.passphraseConfirmed
        tronOutraChave = wallet.tronForeignControl ?? false
        self.selecionada = selecionada
        digital = wallet.fingerprint?.uppercased()
        contas = wallet.accounts.map { Conta(rede: $0.chainID, endereco: $0.address) }
    }
}
