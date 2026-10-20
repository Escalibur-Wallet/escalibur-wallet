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
        case "carteira.passphraseDoRascunho":
            return try json(["passphrase": Sessao.shared.passphraseDoRascunho()])
        case "carteira.terminarRevelacao":
            Sessao.shared.terminarRevelacao(try uuid(pedido["id"]))
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
        case "carteira.ordenar":
            // A ordem nova da lista de carteiras: os mesmos ids, so em outra ordem.
            let ids = (pedido["ids"]?.arrayValue ?? []).compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) }
            try Sessao.shared.alterar { metadata in
                guard Set(ids) == Set(metadata.wallets.map(\.id)), ids.count == metadata.wallets.count else { throw Falha(erro: "ordem invalida") }
                metadata.wallets = ids.compactMap { id in metadata.wallets.first { $0.id == id } }
            }
            return try json(Estado.agora())
        case "carteira.sugestoes":
            // As palavras da lista que comecam com o que foi digitado, e as letras que ainda
            // levam a alguma (o teclado proprio apaga as outras). So o pedaco digitado; os
            // idiomas, quando vem, sao os das palavras ja fechadas da frase.
            let digitado = pedido["digitado"]?.stringValue ?? ""
            let idiomas = pedido["idiomas"]?.arrayValue.map { Set($0.compactMap { $0.stringValue.flatMap(BIP39Language.init(rawValue:)) }) }
            let limite = Int(pedido["limite"]?.doubleValue ?? 4)
            return try json(Sugestoes(palavras: WordLexicon.completions(digitado, preferring: idiomas, limit: max(1, min(limite, 8))),
                                      letras: WordLexicon.nextLetters(after: digitado, languages: idiomas).map(String.init).sorted()))
        case "carteira.tron":
            // Quem controla a conta da Tron da carteira em conferencia (fora da tela das palavras).
            let endereco = pedido["endereco"]?.stringValue ?? ""
            let outra = try esperar { await Importacao.tronComOutraChave(endereco) }
            return try json(["outraChave": outra])
        case "carteira.reconhecer":
            // A rede de um endereco colado para so observar: nada e guardado.
            let texto = String((pedido["endereco"]?.stringValue ?? "").prefix(512))
            if Envio.pareceFrase(texto) { return try json(["frase": true]) }
            return try json(["reconhecida": Observacao.reconhecer(texto)])
        case "carteira.observar":
            let wallet = try Observacao.guardar(String((pedido["endereco"]?.stringValue ?? "").prefix(512)), nome: pedido["nome"]?.stringValue ?? "")
            return try json(CarteiraResumo(wallet, selecionada: true))
        case "contatos.lista":
            return try json(Contatos.lista())
        case "contatos.recentes":
            return try json(Contatos.recentes())
        case "contatos.conferir":
            return try json(Contatos.conferir(
                rede: pedido["rede"]?.stringValue ?? "", endereco: String((pedido["endereco"]?.stringValue ?? "").prefix(512)),
                tag: pedido["tag"]?.stringValue ?? "", conferencia: pedido["conferencia"]?.stringValue ?? "",
                conferenciaDoMemo: pedido["conferenciaDoMemo"]?.stringValue ?? "", comMemo: pedido["comMemo"]?.boolValue ?? false
            ))
        case "contatos.link":
            return try json(Contatos.lerLink(String((pedido["texto"]?.stringValue ?? "").prefix(4096)), rede: pedido["rede"]?.stringValue ?? ""))
        case "contatos.remover":
            try Contatos.remover(try uuid(pedido["id"]))
            return try json(Estado.agora())
        case "rede.silencio":
            // Enquanto as palavras estao na tela, o app nao fala com rede nenhuma.
            Silencio.ligar(pedido["ligar"]?.boolValue ?? false)
            return try json(["ok": true])

        case "receber.moedas":
            return try json(Receber.moedas())
        case "receber.endereco":
            return try json(try Receber.endereco(ativo: pedido["ativo"]?.stringValue ?? ""))

        case let envio where envio.hasPrefix("envio."):
            return try Envio.chamar(envio, pedido)
        case let troca where troca.hasPrefix("troca.") || troca.hasPrefix("ordens."):
            return try Troca.chamar(troca, pedido)
        case let ponte where ponte.hasPrefix("ponte."):
            return try Ponte.chamar(ponte, pedido)

        case "mercado.lista":
            let moeda = pedido["moeda"]?.stringValue ?? Sessao.shared.metadata.settings.currency
            return try json(esperar { try await Mercado.lista(moeda: moeda) })
        case "mercado.grafico":
            let id = pedido["id"]?.stringValue ?? "", moeda = pedido["moeda"]?.stringValue ?? Sessao.shared.metadata.settings.currency
            let intervalo = pedido["intervalo"]?.stringValue ?? "day"
            return try json(esperar { try await Mercado.grafico(id: id, moeda: moeda, intervalo: intervalo) })
        case "mercado.detalhes":
            let id = pedido["id"]?.stringValue ?? "", moeda = pedido["moeda"]?.stringValue ?? Sessao.shared.metadata.settings.currency
            return try json(esperar { try await Mercado.detalhes(id: id, moeda: moeda) })
        case "mercado.favorita":
            try Mercado.favoritar(pedido["id"]?.stringValue ?? "", pedido["favorita"]?.boolValue ?? false)
            return try json(["favoritas": Sessao.shared.metadata.settings.favoriteCoins ?? []])

        case "atividade.mostrar":
            return try json(Atividade.shared.mostrar())
        case "atividade.atualizar":
            let forcar = pedido["forcar"]?.boolValue ?? false
            esperarSemErro { await Atividade.shared.atualizar(forcar: forcar) }
            return try json(Atividade.shared.mostrar())
        case "atividade.conferir":
            let id = pedido["id"]?.stringValue ?? ""
            let (resultado, confirmacoes) = try esperar { await Atividade.shared.conferir(id) }
            return try json(Conferencia(resultado: resultado, confirmacoes: confirmacoes))

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
            // Encurtar vale na hora; alongar amplia a janela de quem pega o celular destravado, e
            // pede o PIN ("ajustes.autoTravar" com segredo).
            let segundos = Estado.Ajustes.prazo(Int(pedido["segundos"]?.doubleValue ?? 60))
            guard segundos <= Estado.Ajustes.prazo(Sessao.shared.metadata.settings.autoLockSeconds) else { throw Falha(erro: "ajustes.pedePIN") }
            try Sessao.shared.alterar { $0.settings.autoLockSeconds = segundos }
            return try json(Estado.agora())
        case "ajustes.rede":
            let rede = pedido["rede"]?.stringValue ?? ""
            guard Chain.find(rede) != nil else { throw Falha(erro: "rede desconhecida") }
            let ligada = pedido["ligada"]?.boolValue ?? true
            try Sessao.shared.alterar { metadata in
                if ligada { metadata.settings.disabledChainIDs.remove(rede) } else { metadata.settings.disabledChainIDs.insert(rede) }
            }
            return try json(Estado.agora())
        case "carteira.pedirPassphraseParaEnviar":
            // Ligar e na hora; desligar pede a passphrase e o PIN ("carteira.naoPedirPassphrase").
            try Sessao.shared.atualizar(try uuid(pedido["id"])) { $0.passphraseToSend = true }
            return try json(Estado.agora())
        case "carteira.removerObservacao":
            // So observar: nao ha chave a proteger, nada pede o PIN.
            let id = try uuid(pedido["id"])
            guard Sessao.shared.metadata.wallets.first(where: { $0.id == id })?.isWatchOnly == true else { throw Falha(erro: "carteira com chave") }
            try Sessao.shared.remover(id)
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
            return try json(Importacao.previa(frase, passphrase: passphrase))
        case "carteira.idiomas":
            return try json(["idiomas": Importacao.idiomas(try proxima())])
        case "carteira.importar":
            let cred = try credencial()
            let frase = try proxima()
            let passphrase = partes.isEmpty ? nil : try proxima()
            let wallet = try Importacao.importar(
                frase, passphrase: passphrase, palavras: Int(pedido["palavras"]?.doubleValue ?? 12),
                tronComOutraChave: pedido["tronOutraChave"]?.boolValue ?? false, credencial: cred
            )
            return try json(CarteiraResumo(wallet, selecionada: true))
        case "ajustes.autoTravar":
            let segundos = Estado.Ajustes.prazo(Int(pedido["segundos"]?.doubleValue ?? 60))
            try Sessao.shared.comChaveRaiz(try credencial()) { _ in }
            try Sessao.shared.alterar { $0.settings.autoLockSeconds = segundos }
            return try json(Estado.agora())
        case "contatos.salvar":
            let contato = try Contatos.salvar(
                rede: pedido["rede"]?.stringValue ?? "", endereco: String((pedido["endereco"]?.stringValue ?? "").prefix(512)),
                nome: pedido["nome"]?.stringValue ?? "", tag: pedido["tag"]?.stringValue ?? "", conferencia: pedido["conferencia"]?.stringValue ?? "",
                conferenciaDoMemo: pedido["conferenciaDoMemo"]?.stringValue, credencial: try credencial()
            )
            return try json(contato)
        case "ajustes.apagarDepois":
            // Qualquer mudanca pede o PIN: ligar e uma forma de destruir as carteiras errando de
            // proposito; desligar ou afrouxar tira a barreira contra quem tenta adivinhar.
            let limite = pedido["limite"]?.doubleValue.map { UInt32($0) }
            let cred = try credencial()
            if limite != nil, let sem = Sessao.shared.metadata.wallets.first(where: { !$0.hasBackup && !$0.isWatchOnly }) {
                cred.zerar()
                throw Falha(erro: "ajustes.semCopia:" + sem.name)
            }
            try Sessao.shared.comChaveRaiz(cred) { _ in }
            try Chaves.root.setWipeAfterErrors(limite)
            return try json(Estado.agora())
        case "carteira.naoPedirPassphrase":
            let id = try uuid(pedido["id"])
            let cred = try credencial()
            try Sessao.shared.naoPedirPassphrase(id, credencial: cred, digitada: try proxima())
            return try json(Estado.agora())
        case "envio.assinar":
            let cred = try credencial()
            let passphrase = partes.isEmpty ? nil : try proxima()
            return try Envio.assinar(cred, passphrase: passphrase, folga: pedido["folga"]?.doubleValue.map { Int($0) })
        case "ponte.assinar":
            let cred = try credencial()
            let passphrase = partes.isEmpty ? nil : try proxima()
            return try Ponte.assinar(cred, passphrase: passphrase, folga: pedido["folga"]?.doubleValue.map { Int($0) })
        case "troca.assinar":
            let cred = try credencial()
            let passphrase = partes.isEmpty ? nil : try proxima()
            return try Troca.assinar(cred, passphrase: passphrase, folga: pedido["folga"]?.doubleValue.map { Int($0) }, alvo: pedido["alvo"]?.stringValue)
        case "carteira.revelar":
            let cred = try credencial()
            let passphrase = partes.isEmpty ? nil : try proxima()
            let aberto = try Sessao.shared.revelar(try uuid(pedido["id"]), credencial: cred, passphraseDigitada: passphrase)
            return try json(Revelado(palavras: aberto.palavras, passphrase: aberto.passphrase))
        case "carteira.conferirPassphrase":
            // Com o rascunho aberto, so a passphrase vem; sem ele, o PIN primeiro.
            let cred = pedido["credencial"] == nil ? nil : try credencial()
            let resultado = try Sessao.shared.conferirPassphrase(try uuid(pedido["id"]), digitada: try proxima(), credencial: cred)
            return try json(["resultado": resultado.rawValue])
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

    struct Revelado: Encodable { let palavras: Int; let passphrase: Bool }

    struct Conferencia: Encodable { let resultado: String; let confirmacoes: UInt64? }

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
        /// Os prazos de bloquear o app que a tela oferece. Um valor de versao anterior vale como o maior.
        static let prazos = [0, 30, 60, 300, 600]
        static func prazo(_ segundos: Int) -> Int { min(max(segundos, 0), prazos.last ?? 600) }

        let moeda: String
        let unidade: String
        let ocultarSaldos: Bool
        let autoTravar: Int
        let tecladoProprio: Bool
        let protecaoMEV: Bool
        let redesDesligadas: [String]
        /// Apagar as carteiras depois de tantos PINs errados seguidos; nil, nunca.
        let apagarDepois: UInt32?
        let opcoesDeApagar: [UInt32]
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
    let contatos: Int

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
                ocultarSaldos: metadata.settings.hideBalances, autoTravar: Ajustes.prazo(metadata.settings.autoLockSeconds),
                tecladoProprio: metadata.settings.ownKeyboard ?? true, protecaoMEV: metadata.settings.mevProtection,
                redesDesligadas: metadata.settings.disabledChainIDs.sorted(), apagarDepois: root.wipeThreshold, opcoesDeApagar: PINPolicy.wipeOptions
            ),
            responsabilidade: metadata.responsibilityVersion,
            contatos: metadata.contacts.count
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
    /// Pede a passphrase para mover saldo e para ver as palavras.
    let pedePassphrase: Bool
    let selecionada: Bool
    let digital: String?
    let contas: [Conta]
    let copiaConfirmadaEm: Date?
    let passphraseConferidaEm: Date?
    let envelopeLacradoEm: Date?
    let vistaEm: Date?

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
        pedePassphrase = PortaDaPassphrase.pede(wallet)
        self.selecionada = selecionada
        digital = wallet.fingerprint?.uppercased()
        contas = wallet.accounts.map { Conta(rede: $0.chainID, endereco: $0.address) }
        copiaConfirmadaEm = wallet.backupConfirmedAt
        passphraseConferidaEm = wallet.passphraseConfirmedAt
        envelopeLacradoEm = wallet.envelopeSealedAt
        vistaEm = wallet.lastRevealedAt
    }
}

/// O silencio da rede pedido pela interface (a tela das palavras), aberto e fechado uma vez so:
/// uma chamada repetida nao empilha, e travar o app fecha.
enum Silencio {
    private static let trava = NSLock()
    nonisolated(unsafe) private static var ligado = false

    static func ligar(_ ligar: Bool) {
        trava.withLock {
            guard ligado != ligar else { return }
            ligado = ligar
            if ligar { HTTPClient.shared.beginQuiet() } else { HTTPClient.shared.endQuiet() }
        }
    }
}
