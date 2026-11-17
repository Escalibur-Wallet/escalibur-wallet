import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import EscaliburNetwork
import Foundation

/// Os metodos que o app Android chama pela ponte. Cada um recebe e devolve JSON. O que e segredo
/// (PIN, frase, passphrase) chega separado, em bytes (`chamarComSegredo`), e nunca volta.
enum Nucleo {
    /// Quando a conferencia do endereco foi ligada nesta abertura do app, no relogio monotono: no
    /// primeiro minuto, desligar nao pede o PIN.
    static let conferenciaLigadaEm = Guarda<TimeInterval?>(nil)

    /// Sem StrongBox, so PIN de 6 digitos: a chave que confere o PIN fica no TEE, e com root um PIN de 4 cai em segundos
    /// (decisao do dono, 07/11/2026). Na duvida (o Java nao respondeu), tambem 6. O PIN recusado sai zerado.
    static func pinComTamanho(_ pin: SecureBytes) throws -> SecureBytes {
        guard pin.count == 4 else { return pin }
        let comStrongBox = ((try? Cofre.chamarInt("Cofre.temStrongBox", [])) ?? 0) == 1
        guard comStrongBox else {
            pin.wipe()
            throw Falha(erro: "sessao.pinCurto")
        }
        return pin
    }

    struct Falha: Error, Encodable {
        let erro: String
    }

    static func chamar(_ metodo: String, _ entrada: Data) throws -> Data {
        let pedido = (try? JSONDecoder().decode(JSONValue.self, from: entrada)) ?? .object([:])
        switch metodo {
        case "iniciar":
            if let pasta = pedido["pasta"]?.stringValue { MetadataStore.directory = URL(fileURLWithPath: pasta) }
            if let vigias = pedido["vigias"]?.stringValue { Vigias.pasta = URL(fileURLWithPath: vigias) }
            if let recursos = pedido["recursos"]?.stringValue { CoreResources.directory = recursos }
            if let pacote = pedido["pacote"] {
                Pacote.abrir(nome: pacote["nome"]?.stringValue ?? "", versao: pacote["versao"]?.stringValue ?? "0",
                             build: pacote["build"]?.stringValue ?? "0", idioma: pedido["idioma"]?.stringValue ?? "pt")
            }
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
        case "atualizacao.conferir":
            // Sem o build do Android, nenhuma conclusao: um 0 faria qualquer build liberado mais novo, e a obrigatoria valeria.
            guard let versao = pedido["versao"]?.stringValue, let build = Int(pedido["build"]?.stringValue ?? ""), build >= 1000 else {
                return try json(Atualizacao.Resposta(estado: "sem-resposta", versao: nil))
            }
            let sdk = pedido["sdk"]?.doubleValue.flatMap { Int(exactly: $0) }
            return try json(esperar { await Atualizacao.conferir(versao: versao, build: build, sdk: sdk) })
        case "redes":
            return try json(Chain.all.map(RedeResumo.init))

        case "sessao.travar":
            Sessao.shared.travar()
            return try json(Estado.agora())
        // Super Security: a biometria antes do PIN (pedido do dono, 01/11/2026). `abrir` e o abrir do
        // app, o unico uso que a espera de "Esperar 24 horas" deixa passar.
        case "sessao.confirmarRosto":
            try Sessao.shared.confirmarRosto(motivo: pedido["motivo"]?.stringValue ?? Textos.destravar,
                                             abrir: pedido["abrir"]?.boolValue == true)
            return try json(["ok": true])
        case "sessao.descartarRosto":
            Sessao.shared.descartarRosto()
            return try json(["ok": true])
        case "sessao.segundoPlano":
            Sessao.shared.foiParaSegundoPlano()
            return try json(["ok": true])
        case "passphrase.descartar":
            PortaDaPassphrase.descartarEntregue()
            return try json(["ok": true])
        case "passphrase.encerrarFolgas":
            // Ida ao seletor de arquivos do app: nao trava, mas a copia da passphrase da folga nao fica (05/11/2026).
            PortaDaPassphrase.encerrarFolgas()
            return try json(["ok": true])
        case "sessao.primeiroPlano":
            Sessao.shared.voltouAoPrimeiroPlano()
            return try json(Estado.agora())
        case "sessao.apagarTudo":
            // Da tela de "Esqueci o PIN", depois da confirmacao: apaga cofre e metadados. So com o cofre
            // ja apagado (apagar depois de N erros) ou com a espera de 24 horas do pedido cumprida
            // (revisao de seguranca de 27/10/2026).
            guard !Chaves.root.isSetUp || Chaves.root.forgotPINEraseRemaining == 0 || Chaves.root.hardenedVaultLost else {
                throw Falha(erro: "sessao.esperaParaApagar")
            }
            Sessao.shared.apagarTudo()
            return try json(Estado.agora())
        case "operacao.critica":
            // Um envio, troca ou ponte em revisao, transmitindo ou sem resposta: a notificacao tocada nao
            // fecha a tela (caca de bugs de 27/10/2026).
            let critica = (Envio.atual?.critico ?? false) || Troca.algumaCritica || Ponte.shared.critica
            return try json(["critica": critica])
        case "sessao.esqueciPIN":
            return try json(EsqueciPIN(restante: Chaves.root.forgotPINEraseRemaining))
        case "sessao.pedirApagar":
            try Chaves.root.requestForgotPINErase()
            return try json(EsqueciPIN(restante: Chaves.root.forgotPINEraseRemaining))
        case "sessao.cancelarApagar":
            Chaves.root.cancelForgotPINErase()
            return try json(EsqueciPIN(restante: nil))
        case "sessao.destrancarBiometria":
            try Sessao.shared.destrancarComBiometria()
            return try json(Estado.agora())
        case "sessao.podeComecar":
            // Antes do teclado do PIN, como o `retrying` do iOS: a espera depois de a biometria
            // mudar, e a biometria perdida e nao religada, recusam aqui. Digitar o PIN para ouvir
            // "espere" nao ajuda ninguem. No reforcado vale a espera de "Esperar 24 horas" em
            // toda operacao. O cofre confere de novo na operacao.
            if Chaves.root.securityMode == .hardened {
                try Chaves.root.checkHardenedAllowed()
            } else if pedido["ambos"]?.boolValue == true {
                try Chaves.root.checkPINAndBiometryAllowed()
            }
            return try json(["ok": true])
        case "sessao.aceitarResponsabilidade":
            try Sessao.shared.aceitarResponsabilidade(versao: Int(pedido["versao"]?.doubleValue ?? 1))
            return try json(Estado.agora())

        case "carteira.confirmarCopia":
            try Sessao.shared.confirmarCopia(try uuid(pedido["id"]))
            return try json(Estado.agora())
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
            // O mesmo saneamento do iOS: sem controle, sem caractere invisivel ou de direcao (revisao, 08/11/2026).
            let nome = Envelope.sanitize(pedido["nome"]?.stringValue ?? "", limit: 40)
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
            // Quem controla a conta da Tron da carteira em conferencia (fora da tela das palavras). A rodada do dia da escolhida
            // para antes, como no `carteira.evm` (rodada 4 da auditoria 8). Com passphrase, nada e poupado (rodada 5).
            Sessao.shared.abrirPrevia(oculta: pedido["oculta"]?.boolValue ?? true)
            let endereco = pedido["endereco"]?.stringValue ?? ""
            // A Tron desligada nos Ajustes nao e consultada por nada (rodada 5 da auditoria 8).
            guard !Sessao.shared.metadata.settings.disabledChainIDs.contains(Chain.tron.id) else { return try json(["outraChave": false]) }
            let outra = try esperar { await Importacao.tronComOutraChave(endereco) }
            return try json(["outraChave": outra])
        case "conferencias.agendar":
            // A tela das palavras fechou: a rodada do dia que desistiu no silencio volta, se for a hora (rodada 9), como no iOS.
            Sessao.shared.agendarConferencias()
            return try json(["ok": true])
        case "conferencias.segurar":
            // A previa da importacao com a passphrase depois: a rodada do dia fica segura ate o fluxo fechar (rodada 8), como no iOS.
            Sessao.shared.abrirPrevia(oculta: true)
            return try json(["ok": true])
        case "conferencias.retomar":
            // A previa da importacao fechou: a rodada do dia da escolhida volta (rodada 5 da auditoria 8), como no iOS.
            Sessao.shared.fecharPrevia()
            return try json(["ok": true])
        case "carteira.evm":
            // A conta EVM da carteira em conferencia com contrato instalado por delegacao (EIP-7702) numa das redes da previa,
            // como o `checkEVM` do iOS (auditoria 8, 14/11/2026). O aviso, e a marca ao gravar (rodada 4).
            let endereco = pedido["endereco"]?.stringValue ?? ""
            // A rodada do dia da escolhida para antes: a previa consulta a importada, e as duas nao saem juntas (rodada 4). Com
            // passphrase, nada e poupado (rodada 5).
            Sessao.shared.abrirPrevia(oculta: pedido["oculta"]?.boolValue ?? true)
            let epoca = Sessao.shared.epocaAtual
            // As redes desligadas nos Ajustes nao sao consultadas por nada (rodada 5 da auditoria 8).
            let desligadas = Sessao.shared.metadata.settings.disabledChainIDs
            let achado = try esperar { await ForeignControlCheck.previewDelegation(address: endereco, skipping: desligadas) }
            // Guardado no nucleo, pelo endereco: ao gravar esta carteira, vira marca (rodada 4 da auditoria 8). So destravado, na
            // mesma epoca de antes da leitura: travado no meio, o achado ficava na memoria com o app travado (rodada 5).
            Sessao.shared.seDestravada(desde: epoca) { Importacao.guardarPreviaEVM(endereco, achado) }
            return try json(["rede": achado?.chain.name, "aviso": achado?.control.message])
        // Sem segredo nenhum: chegam pelo `Api.objeto` do Kotlin, que vem para ca. Dentro do `chamarComSegredo`, caiam em
        // "metodo desconhecido", e a busca de movimento da carteira com passphrase nunca respondia (segunda revisao de
        // blockchain, 08/11/2026).
        case "carteira.usoDaPassphrase":
            // A busca de movimento na carteira recem-aberta (o UsageCheck, igual ao iOS).
            let id = try uuid(pedido["id"])
            // A rodada do dia para: a carteira com passphrase e a de base nao sao consultadas juntas (rodada 1 da auditoria 8). A
            // pausa mantem as desta, que acabaram de sair (rodada 4).
            Sessao.shared.pararConferencias(mantendo: id)
            guard let contas = Sessao.shared.metadata.wallets.first(where: { $0.id == id })?.accounts else { throw Sessao.Falha.carteiraNaoEncontrada }
            // A Tron dela junto da busca: com outra chave no controle, a carteira nao abre sozinha (revisao, 08/11/2026).
            let tron = Sessao.shared.conferirTron(id)
            Sessao.shared.conferirControle(id)
            Sessao.shared.conferirVersaoTON(id)
            let uso = try esperar({ await UsageCheck.run(contas) })
            // No maximo 5 s depois da busca: um provedor lento nao prende a tela, e a conferencia continua sozinha.
            let outraChave = try esperar({ await Nucleo.respostaDaTron(tron, segundos: 5) })
            switch uso {
            case .used: return try json(UsoDaPassphrase(resultado: "usada", falharam: nil, tronOutraChave: outraChave))
            case .never: return try json(UsoDaPassphrase(resultado: "nunca", falharam: nil, tronOutraChave: outraChave))
            case .incomplete(let falharam):
                let nomes = falharam.compactMap { Chain.find($0)?.name }.joined(separator: ", ")
                return try json(UsoDaPassphrase(resultado: "incompleta", falharam: nomes, tronOutraChave: outraChave))
            }
        case "carteira.esperarTron":
            // A conferencia da Tron de uma carteira que acabou de abrir, esperada fora da tela: a resposta recarrega o estado
            // do Kotlin, e os atalhos de copiar deixam de mostrar a Tron marcada (revisao de blockchain, 08/11/2026).
            let id = try uuid(pedido["id"])
            let tarefa = Sessao.shared.conferirTron(id)
            return try json(["outraChave": try esperar { await tarefa.value ?? false }])
        case "carteira.descartarPassphrase":
            try Sessao.shared.descartarCarteiraComPassphrase(try uuid(pedido["id"]), anterior: pedido["anterior"]?.stringValue.flatMap(UUID.init(uuidString:)))
            return try json(Estado.agora())
        case "suporte.pareceFrase":
            // A mesma conferencia do SupportView do iOS (`PrivateKeyGuard.supportSecret`): a chave, a frase ou um pedaco dela, e
            // no texto os hexadecimais longos, que no ID da transacao passam. O tipo escolhe o aviso; nas palavras, o trecho vai
            // junto, para quem so conversava saber o que trocar (revisao dos 3 agentes, 09/11/2026). Um caractere a mais que o
            // campo aceita, para o texto comprido demais tambem ficar.
            let detalhes = String((pedido["detalhes"]?.stringValue ?? "").prefix(4097))
            let transacao = String((pedido["transacao"]?.stringValue ?? "").prefix(4097))
            struct Resposta: Encodable { let frase: Bool; let tipo: String; let palavras: String }
            // Com a rede do chamado: os 64 hexadecimais no ID passam so no formato do codigo de transacao dela.
            let rede = pedido["rede"]?.stringValue.flatMap(Chain.find)
            // So os enderecos que o app ja conhece na rede passam no texto (as contas, os contatos, os destinos), como no iOS.
            let conhecidos: Set<String> = rede.map { chain in
                let metadata = Sessao.shared.metadata
                let contas = metadata.wallets.flatMap(\.accounts).filter { $0.chainID == chain.id }.map(\.address)
                let contatos = metadata.contacts.filter { $0.chainID == chain.id }.map(\.address)
                // Tambem os contratos publicos: o USDC e o USDt oficiais e as moedas custom da carteira.
                return Set((contas + contatos + (metadata.sentTo[chain.id] ?? [])).map(PrivateKeyGuard.hexKey))
                    .union(PrivateKeyGuard.publicContracts(on: chain, assetIDs: metadata.customTokens.map(\.id)))
            } ?? []
            switch PrivateKeyGuard.supportSecret(details: detalhes, transaction: transacao, chain: rede, known: conhecidos) {
            case .none: return try json(Resposta(frase: false, tipo: "", palavras: ""))
            case .secret: return try json(Resposta(frase: true, tipo: "chave", palavras: ""))
            case .words(let trecho): return try json(Resposta(frase: true, tipo: "palavras", palavras: trecho))
            case .hex: return try json(Resposta(frase: true, tipo: "hex", palavras: ""))
            case .needsNetwork: return try json(Resposta(frase: true, tipo: "rede", palavras: ""))
            }
        case "texto.segredo":
            // O Colar do app pergunta antes: com uma frase ou uma chave, a area de transferencia esvazia (como no iOS).
            // Com a rede da tela, como no iOS: sem ela, a chave com 0x na EVM saia do campo e ficava na area de transferencia.
            // Um caractere a mais que a conferencia alcanca: o texto comprido demais tambem esvazia (como no iOS).
            let texto = String((pedido["texto"]?.stringValue ?? "").prefix(4097))
            let rede = pedido["rede"]?.stringValue.flatMap(Chain.find)
            return try json(["segredo": PrivateKeyGuard.clipboardHasSecret(texto, on: rede)])
        case "texto.campo":
            // O campo da moeda custom (o contrato, o codigo, o emissor): a frase ou a chave sai dele com o aviso, como no observar.
            let texto = String((pedido["texto"]?.stringValue ?? "").prefix(4097)).trimmingCharacters(in: .whitespacesAndNewlines)
            let rede = pedido["rede"]?.stringValue.flatMap(Chain.find)
            struct Campo: Encodable { let segredo: Bool; let aviso: String }
            let segredo = Envio.ehSegredo(texto, rede: rede)
            return try json(Campo(segredo: segredo, aviso: segredo ? Envio.avisoDoSegredo(texto, rede: rede) : ""))
        case "carteira.reconhecer":
            // A rede de um endereco colado para so observar: nada e guardado.
            let texto = String((pedido["endereco"]?.stringValue ?? "").prefix(512))
            if Envio.ehSegredo(texto, rede: nil) {
                struct Segredo: Encodable { let frase: Bool; let aviso: String }
                return try json(Segredo(frase: true, aviso: Envio.avisoDoSegredo(texto)))
            }
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
                conferenciaDoMemo: pedido["conferenciaDoMemo"]?.stringValue ?? "", comMemo: pedido["comMemo"]?.boolValue ?? false,
                armado: pedido["armado"]?.boolValue ?? true
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

        case "envelope.calibrar":
            return try json(Envelopes.calibrar())
        case "envelope.sugerir":
            try Envelopes.sugerir()
            return try json(["ok": true])
        case "envelope.usarSorteada":
            try Envelopes.usarSorteada()
            return try json(["ok": true])
        case "envelope.aceitarRisco":
            Envelopes.aceitarRisco()
            return try json(["ok": true])
        case "envelope.voltar":
            return try json(["sorteada": Envelopes.voltar()])
        case "envelope.entregue":
            Envelopes.entregue()
            return try json(["ok": true])
        case "envelope.encerrar":
            Envelopes.esquecerLacrado()
            Envelopes.encerrar()
            Envelopes.fecharAbertura()
            return try json(["ok": true])
        case "envelope.inspecionar":
            return try json(try Envelopes.inspecionar(pedido["dados"]?.stringValue ?? ""))
        case "envelope.previa":
            return try json(try Envelopes.previa())
        case "envelope.verPalavras":
            return try json(["palavras": try Envelopes.verPalavras()])

        case "receber.moedas":
            return try json(Receber.moedas())
        case "receber.endereco":
            return try json(try Receber.endereco(ativo: pedido["ativo"]?.stringValue ?? "", rede: pedido["rede"]?.stringValue))
        case "carteira.enderecoParaCopiar":
            // O Copiar endereco e os Enderecos dos Ajustes conferem aqui, na hora do toque e na carteira gravada: a tela pode estar um
            // passo atras da marca de outra chave (rodada 8 da auditoria 8). Sem a marca em nenhuma das redes e com o mesmo endereco
            // em todas, volta o endereco; senao, nada.
            let pedidas = pedido["redes"]?.arrayValue ?? []
            let redes = pedidas.compactMap { $0.stringValue.flatMap(Chain.find) }
            guard Sessao.shared.fase == .unlocked, let id = UUID(uuidString: pedido["id"]?.stringValue ?? ""), !redes.isEmpty,
                  redes.count == pedidas.count, let carteira = Sessao.shared.metadata.wallets.first(where: { $0.id == id }),
                  // Com a copia conferida, como as telas: o nucleo e o portao inteiro (rodada 9).
                  carteira.hasBackup || carteira.isWatchOnly,
                  let endereco = carteira.account(redes[0])?.address,
                  // Desde 15/11/2026 (pedido do dono, a forma mais segura), so a rede ja lida para outra chave no controle, e nunca
                  // o endereco que outra carteira deste aparelho tem marcado, como no iOS.
                  redes.allSatisfy({ carteira.recebe(on: $0) && (carteira.isWatchOnly || carteira.controlChecked(on: $0))
                                     && Sessao.shared.metadata.wallets.marcadaEmOutra(carteira, on: $0) == nil
                                     && carteira.account($0)?.address == endereco }) else {
                return try json(["endereco": String?.none])
            }
            return try json(["endereco": endereco])
        case "receber.conferirControle":
            // A hora do deposito: a rede desta conta conferida de novo ao abrir o Receber, sem esperar a do destravar, como o
            // iOS (auditoria 8, 14/11/2026). Volta o aviso que vale agora; a tela recarrega o endereco com ele.
            guard let rede = Chain.find(pedido["rede"]?.stringValue ?? ""), let carteira = Sessao.shared.metadata.selectedWallet,
                  !carteira.isWatchOnly else { return try json(["aviso": String?.none]) }
            if rede.family == .tron {
                // Cancelada, nil: a tela espera os 3 s, como nas outras redes (rodada 4 da auditoria 8).
                guard try esperar({ await Sessao.shared.conferirTron(carteira.id).value }) != nil else {
                    throw Falha(erro: "receber.naoConferida")
                }
            } else {
                // Numa EVM, tambem as outras EVM marcadas: a marca de uma fecha todas (rodada 3 da auditoria 8), como no iOS.
                let marcadas = rede.family == .evm
                    ? Set((carteira.foreignControl ?? [:]).keys.filter { Chain.find($0)?.family == .evm }) : []
                // A que nao foi ate o fim (a pausa) volta como erro: a tela espera os 3 s em vez de liberar na hora (rodada 4).
                guard try esperar({ await Sessao.shared.conferirControle(carteira.id, redes: marcadas.union([rede.id])).value }) else {
                    throw Falha(erro: "receber.naoConferida")
                }
            }
            let atual = Sessao.shared.metadata.wallets.first { $0.id == carteira.id }
            return try json(["aviso": atual?.foreignControl(on: rede)?.message, "tronOutraChave": atual?.tronForeignControl == true ? "sim" : nil])
        case "receber.buscar":
            let texto = pedido["texto"]?.stringValue ?? ""
            return try json(esperar { await Receber.buscar(texto) })
        case "receber.redes":
            let id = pedido["id"]?.stringValue ?? ""
            let simbolo = pedido["simbolo"]?.stringValue, nome = pedido["nome"]?.stringValue
            return try json(esperar { try await Receber.redes(id: id, simbolo: simbolo, nome: nome) })
        case "receber.redesDaTroca":
            let id = pedido["id"]?.stringValue ?? ""
            let simbolo = pedido["simbolo"]?.stringValue, nome = pedido["nome"]?.stringValue
            return try json(esperar { await Receber.redesDaTroca(id: id, simbolo: simbolo, nome: nome, excluir: pedido["excluir"]?.stringValue) })

        case let envio where envio.hasPrefix("envio."):
            return try Envio.chamar(envio, pedido)
        case let troca where troca.hasPrefix("troca.") || troca.hasPrefix("ordens."):
            return try Troca.chamar(troca, pedido)
        case let ponte where ponte.hasPrefix("ponte."):
            return try Ponte.chamar(ponte, pedido)
        case let vigia where vigia.hasPrefix("vigias.") || vigia.hasPrefix("alertas.") || vigia.hasPrefix("recebimentos."):
            return try Vigias.chamar(vigia, pedido)
        case "reforco.estado", "reforco.esquecer":
            return try Reforco.chamar(metodo, pedido, segredo: { throw Falha(erro: "segredo incompleto") }, segundo: { nil })

        case "mercado.lista":
            let moeda = pedido["moeda"]?.stringValue ?? Sessao.shared.metadata.settings.currency
            return try json(esperar { try await Mercado.lista(moeda: moeda) })
        case "mercado.grafico":
            let id = pedido["id"]?.stringValue ?? "", moeda = pedido["moeda"]?.stringValue ?? Sessao.shared.metadata.settings.currency
            let intervalo = pedido["intervalo"]?.stringValue ?? "day", reserva = pedido["reserva"]?.stringValue
            return try json(esperar { try await Mercado.grafico(id: id, moeda: moeda, intervalo: intervalo, reserva: reserva) })
        case "mercado.graficoDoContrato":
            let id = pedido["id"]?.stringValue ?? "", moeda = pedido["moeda"]?.stringValue ?? Sessao.shared.metadata.settings.currency
            let intervalo = pedido["intervalo"]?.stringValue ?? "day"
            return try json(esperar { try await Mercado.graficoDoContrato(id: id, moeda: moeda, intervalo: intervalo) })
        case "mercado.avisoDoContrato":
            let id = pedido["id"]?.stringValue ?? ""
            return try json(["aviso": try esperar { try await Mercado.avisoDoContrato(id: id) }])
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
        case let ativos where ativos.hasPrefix("ativos.") || ativos.hasPrefix("tokens."):
            return try Ativos.chamar(ativos, pedido)
        case "saldos.atualizar":
            let forcar = pedido["forcar"]?.boolValue ?? false
            esperarSemErro { await Saldos.shared.atualizar(forcar: forcar) }
            return try json(Saldos.shared.retratoAtual())
        case "saldos.precos":
            esperarSemErro { await Saldos.shared.atualizarCotacoes() }
            return try json(Saldos.shared.retratoAtual())

        case "ajustes.unidade":
            let unidade = pedido["unidade"]?.stringValue ?? "usd"
            guard ["brl", "usd", "eur", "btc"].contains(unidade) else { throw Falha(erro: "unidade desconhecida") }
            let antiga = Sessao.shared.metadata.settings.currency
            var mudou = false
            try Sessao.shared.alterar { metadata in
                mudou = metadata.settings.choose(unidade)
                if mudou { metadata.quoteCache = [:] }
            }
            // Os precos na tela viram a moeda nova na hora; o Kotlin pede so os precos depois ("saldos.precos").
            if mudou { Saldos.shared.moedaMudou(de: antiga) }
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
        case "ajustes.tecladoProprio":
            // O Safe Keyboard: no Super Security ele fica sempre ligado (como no iOS). Desligar
            // entrega o que se digita ao teclado do celular, que pode ser de terceiros: pede o PIN
            // ("ajustes.tecladoProprio" com segredo).
            let ligado = pedido["ligado"]?.boolValue ?? true
            guard ligado || Chaves.root.securityMode != .hardened else { throw Falha(erro: "ajustes.tecladoNoReforco") }
            guard ligado else { throw Falha(erro: "ajustes.pedePIN") }
            try Sessao.shared.alterar { $0.settings.ownKeyboard = true }
            return try json(Estado.agora())
        case "ajustes.conferirEndereco":
            // Conferir o endereco em todo envio: ligar e na hora; desligar tira uma barreira e pede o
            // PIN ("ajustes.conferirEndereco" com segredo), como o Safe Keyboard. No primeiro minuto
            // depois de ligar, desligar nao pede (pedido do dono, 24/10/2026): quem ligou sem querer
            // volta atras, e a barreira desfeita e a que acabou de nascer. Na memoria, no relogio monotono.
            guard pedido["ligada"]?.boolValue ?? true else {
                guard Chaves.root.securityMode != .hardened else { throw Falha(erro: "ajustes.conferenciaNoReforco") }
                guard let desde = Nucleo.conferenciaLigadaEm.withLock({ $0 }), PINPolicy.uptime - desde < 60 else { throw Falha(erro: "ajustes.pedePIN") }
                try Sessao.shared.alterar { $0.settings.confirmEveryAddress = false }
                Nucleo.conferenciaLigadaEm.withLock { $0 = nil }
                return try json(Estado.agora())
            }
            try Sessao.shared.alterar { $0.settings.confirmEveryAddress = true }
            Nucleo.conferenciaLigadaEm.withLock { $0 = PINPolicy.uptime }
            return try json(Estado.agora())
        case "carteira.removerObservacao":
            // So observar: nao ha chave a proteger, nada pede o PIN.
            let id = try uuid(pedido["id"])
            guard Sessao.shared.metadata.wallets.first(where: { $0.id == id })?.isWatchOnly == true else { throw Falha(erro: "carteira com chave") }
            try Sessao.shared.remover(id, credencial: nil)
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
        case "cofre.rsaTeste":
            // So de depuracao: o RSA-OAEP do nucleo com uma chave publica do Keystore, para o Kotlin abrir e comparar.
            let publica = Data(base64Encoded: pedido["publica"]?.stringValue ?? "") ?? Data()
            let claro = try SecureBytes.random(count: 32)
            defer { claro.wipe() }
            let cifrado = try RSAOAEP.encrypt(claro, publicKeyDER: [UInt8](publica))
            return try json(["cifrado": Data(cifrado).base64EncodedString(), "claro": claro.withUnsafeBytes { Data($0) }.base64EncodedString()])
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
        // A passphrase que chega vazia (um campo zerado no caminho) nunca vira "sem passphrase": isso gravaria, mostraria ou
        // assinaria a carteira de base no lugar da com passphrase (revisao de seguranca de 05/11/2026). Nenhum chamador
        // legitimo manda parte vazia: a folha e a importacao exigem o campo preenchido.
        func passphraseOpcional(_ cred: Credencial?) throws -> SecureBytes? {
            guard !partes.isEmpty else { return nil }
            return try passphraseCheia(cred)
        }
        func passphraseCheia(_ cred: Credencial?) throws -> SecureBytes {
            let parte = try proxima()
            guard parte.count > 0 else {
                parte.wipe()
                cred?.zerar()
                throw Falha(erro: "passphrase.vazia")
            }
            return parte
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
        // Ver as palavras, lacra-las num envelope e remover a carteira pedem a presenca inteira: o PIN e, com a biometria
        // ligada, ela tambem (ou o Super Security). As telas ja pedem assim; o nucleo confere, para nenhuma tela nova pedir
        // menos (auditoria 8, 14/11/2026), como o `desligarBiometria` ja fazia.
        func credencialForte() throws -> Credencial {
            let cred = try credencial()
            switch cred {
            case .pinEBiometria, .reforcado: return cred
            case .pin, .biometria:
                cred.zerar()
                throw RootKeyVault.Failure.biometryRequired
            }
        }

        switch metodo {
        case let reforco where reforco.hasPrefix("reforco."):
            return try Reforco.chamar(reforco, pedido, segredo: proxima, segundo: { partes.isEmpty ? nil : try passphraseCheia(nil) })
        case "sessao.cadastrarPIN":
            try Sessao.shared.cadastrarPIN(try Self.pinComTamanho(try proxima()))
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
        case "sessao.conferirPIN":
            // So o PIN, sem mudar nada: desfazer uma escolha feita com aceite, antes de ligar (sair de "Bloquear as carteiras"
            // com o Super Security desligado, pedido do dono de 18/10/2026, como no iPhone). Errar conta como em toda conferencia.
            try Sessao.shared.comChaveRaiz(try credencial()) { _ in }
            return try json(Estado.agora())
        case "sessao.trocarPIN":
            let atual = try credencial()
            try Sessao.shared.trocarPIN(atual, novo: try Self.pinComTamanho(try proxima()))
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
        case "carteira.conferir":
            // A palavra digitada na conferencia, contra a da posicao no rascunho: chega como segredo, e nao no JSON.
            let digitada = try proxima()
            defer { digitada.wipe() }
            let indice = Int(pedido["indice"]?.doubleValue ?? -1)
            return try json(["confere": Sessao.shared.comRascunho { $0.confere(digitada, em: indice) }])
        case "carteira.conferirEscolhidas":
            // As palavras escolhidas, antes do PIN: cada uma da lista em ingles e nenhuma das
            // combinacoes que robo testa primeiro. A frase completada sai da memoria aqui mesmo.
            let primeiras = try proxima()
            defer { primeiras.wipe() }
            if let fora = Importacao.foraDoIngles(primeiras) { return try json(["fora": fora]) }
            let completa = try BIP39.completing(primeiras)
            completa.wipe()
            return try json(["ok": true])
        case "carteira.validarFrase":
            return try json(Importacao.validar(try proxima()))
        case "carteira.previa":
            let frase = try proxima()
            let passphrase = try passphraseOpcional(nil)
            return try json(Importacao.previa(frase, passphrase: passphrase))
        case "carteira.idiomas":
            return try json(["idiomas": Importacao.idiomas(try proxima())])
        case "carteira.importar":
            let cred = try credencial()
            let frase = try proxima()
            let passphrase = try passphraseOpcional(cred)
            let wallet = try Importacao.importar(
                frase, passphrase: passphrase, palavras: Int(pedido["palavras"]?.doubleValue ?? 12),
                tronComOutraChave: pedido["tronOutraChave"]?.boolValue ?? false, digital: pedido["digital"]?.stringValue, credencial: cred
            )
            return try json(CarteiraResumo(wallet, selecionada: true))
        case "carteira.importarComPassphrase":
            // O interruptor da passphrase na importacao: so a carteira com passphrase vai ao cofre (revisao dos 3 agentes, 08/11/2026).
            // A rodada do dia da carteira de base para antes, como ao abrir pelos Ajustes (rodada 2 da auditoria 8). Sem abrir (o
            // PIN recusado, um erro), ela volta (rodada 6), como no iOS.
            Sessao.shared.pararConferencias()
            var aberta = false
            defer { if !aberta { Sessao.shared.agendarConferencias() } }
            let cred = try credencial()
            let frase = try proxima()
            let nome = nomeComPassphrase(pedido["nome"]?.stringValue)
            let anterior = Sessao.shared.metadata.selectedWalletID
            let (wallet, jaAberta) = try Importacao.importarComPassphrase(
                frase, passphrase: try passphraseCheia(cred), palavras: Int(pedido["palavras"]?.doubleValue ?? 12),
                digitalDaFrase: pedido["digital"]?.stringValue, nome: nome, credencial: cred
            )
            aberta = true
            _ = Sessao.shared.conferirTron(wallet.id)
            Sessao.shared.conferirControle(wallet.id)
            Sessao.shared.conferirVersaoTON(wallet.id)
            return try json(AbertaComPassphrase(carteira: CarteiraResumo(wallet, selecionada: true), jaAberta: jaAberta, anterior: anterior?.uuidString))
        case "sessao.confirmar":
            // O PIN ou a digital, sem abrir nada: importar com o interruptor da passphrase pede a confirmacao antes da tela da
            // passphrase (pedido do dono, 08/11/2026).
            try Sessao.shared.comChaveRaiz(try credencial()) { _ in }
            return try json(["ok": true])
        case "ajustes.tecladoProprio":
            guard Chaves.root.securityMode != .hardened else { throw Falha(erro: "ajustes.tecladoNoReforco") }
            try Sessao.shared.comChaveRaiz(try credencial()) { _ in }
            try Sessao.shared.alterar { $0.settings.ownKeyboard = false }
            return try json(Estado.agora())
        case "ajustes.conferirEndereco":
            guard Chaves.root.securityMode != .hardened else { throw Falha(erro: "ajustes.conferenciaNoReforco") }
            try Sessao.shared.comChaveRaiz(try credencial()) { _ in }
            try Sessao.shared.alterar { $0.settings.confirmEveryAddress = false }
            Nucleo.conferenciaLigadaEm.withLock { $0 = nil }
            return try json(Estado.agora())
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
        case "passphrase.escrevivel":
            // Antes do PIN, sem credencial: a passphrase da importacao tem o que o papel nao mostra? O app pergunta antes de
            // abrir (revisao de seguranca, 08/11/2026). O Kotlin zera a dele na volta.
            let passphrase = try passphraseCheia(nil)
            defer { passphrase.wipe() }
            return try json(["escrevivel": PortaDaPassphrase.escrevivel(passphrase)])
        case "passphrase.entregar":
            // A passphrase digitada para a proxima assinatura, sem credencial: o Kotlin zera a dele na volta.
            PortaDaPassphrase.entregar(try passphraseCheia(nil))
            return try json(["ok": true])
        case "envio.assinar":
            let cred = try credencial()
            let passphrase = try passphraseOpcional(cred)
            return try Envio.assinar(cred, passphrase: passphrase, folga: pedido["folga"]?.doubleValue.map { Int($0) },
                                     versao: pedido["versao"]?.doubleValue.map { Int($0) })
        case "ponte.assinar":
            let cred = try credencial()
            let passphrase = try passphraseOpcional(cred)
            return try Ponte.assinar(cred, passphrase: passphrase, folga: pedido["folga"]?.doubleValue.map { Int($0) })
        case "troca.assinar":
            let cred = try credencial()
            let passphrase = try passphraseOpcional(cred)
            return try Troca.assinar(cred, passphrase: passphrase, folga: pedido["folga"]?.doubleValue.map { Int($0) }, alvo: pedido["alvo"]?.stringValue)
        case "envelope.abrirCarteira":
            let id = try uuid(pedido["id"])
            let cred = try credencialForte()
            let passphrase = try passphraseOpcional(cred)
            return try json(["nome": try Envelopes.abrirCarteira(id, credencial: cred, passphraseDigitada: passphrase)])
        case "envelope.medir":
            return try json(Envelopes.medir(try proxima()))
        case "envelope.conferir":
            return try json(Envelopes.conferir(try proxima()))
        case "envelope.lacrar":
            return try json(try Envelopes.lacrar(repeticao: try proxima(), rotulo: pedido["nome"]?.stringValue ?? ""))
        case "envelope.abrir":
            return try json(try Envelopes.abrir(senha: try proxima()))
        case "envelope.conferirPassphrase":
            try Envelopes.conferirPassphrase(try passphraseCheia(nil))
            return try json(["ok": true])
        case "envelope.importar":
            let wallet = try Envelopes.importar(tronComOutraChave: pedido["tronOutraChave"]?.boolValue ?? false, credencial: try credencial())
            return try json(CarteiraResumo(wallet, selecionada: Sessao.shared.metadata.selectedWalletID == wallet.id))
        case "carteira.abrirComPassphrase":
            let base = try uuid(pedido["base"])
            let cred = try credencial()
            let nome = nomeComPassphrase(pedido["nome"]?.stringValue)
            let anterior = Sessao.shared.metadata.selectedWalletID
            Sessao.shared.pararConferencias()
            // Sem abrir (o PIN recusado, um erro), a rodada do dia da base volta (rodada 6 da auditoria 8), como no iOS.
            var aberta = false
            defer { if !aberta { Sessao.shared.agendarConferencias() } }
            let (wallet, jaAberta) = try Sessao.shared.abrirComPassphrase(base: base, passphrase: try passphraseCheia(cred), nome: nome, credencial: cred)
            aberta = true
            // A Tron dela conferida ja, nova ou reaberta, mesmo que o dono abra sem esperar a busca de movimento (o golpe da
            // "frase com saldo", revisao de 08/11/2026).
            _ = Sessao.shared.conferirTron(wallet.id)
            Sessao.shared.conferirControle(wallet.id)
            Sessao.shared.conferirVersaoTON(wallet.id)
            return try json(AbertaComPassphrase(carteira: CarteiraResumo(wallet, selecionada: true), jaAberta: jaAberta, anterior: anterior?.uuidString))
        case "carteira.revelar":
            let cred = try credencialForte()
            let passphrase = try passphraseOpcional(cred)
            let aberto = try Sessao.shared.revelar(try uuid(pedido["id"]), credencial: cred, passphraseDigitada: passphrase)
            return try json(Revelado(palavras: aberto.palavras, passphrase: aberto.passphrase))
        case "carteira.conferirPassphrase":
            // Com o rascunho aberto, so a passphrase vem; sem ele, o PIN primeiro.
            let cred = pedido["credencial"] == nil ? nil : try credencial()
            let resultado = try Sessao.shared.conferirPassphrase(try uuid(pedido["id"]), digitada: try passphraseCheia(cred), credencial: cred)
            return try json(["resultado": resultado.rawValue])
        case "carteira.remover":
            let id = try uuid(pedido["id"])
            // Remover pede a mesma presenca que ver as palavras: a remocao confere e o cofre abre antes (rodada 3).
            try Sessao.shared.remover(id, credencial: try credencialForte())
            return try json(Estado.agora())
        default:
            throw Falha(erro: "metodo desconhecido: \(metodo)")
        }
    }

    /// O pedido de "Esqueci o PIN": sem `restante`, nada pedido; 0, pode apagar.
    struct EsqueciPIN: Encodable {
        let restante: Double?
    }

    /// O nome da carteira com passphrase, saneado como no iOS. So com caractere de controle ou invisivel, o saneamento deixava
    /// vazio, e a carteira ficava sem nome na lista (revisao dos 3 agentes, 08/11/2026).
    static func nomeComPassphrase(_ pedido: String?) -> String {
        let nome = Envelope.sanitize(pedido ?? "", limit: 40)
        return nome.isEmpty ? Textos.t("Carteira com passphrase") : nome
    }

    /// A resposta da Tron, esperada no maximo `segundos` (o tronAnswer do iOS): sem resposta no prazo, "nao", e a conferencia
    /// segue sozinha e marca a carteira quando chegar.
    static func respostaDaTron(_ tarefa: Task<Bool?, Never>, segundos: Double) async -> Bool {
        final class Uma: @unchecked Sendable {
            private let trava = NSLock()
            private var feita = false
            func vez() -> Bool { trava.withLock { defer { feita = true }; return !feita } }
        }
        let uma = Uma()
        return await withCheckedContinuation { continuacao in
            Task {
                let valor = await tarefa.value ?? false
                if uma.vez() { continuacao.resume(returning: valor) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
                if uma.vez() { continuacao.resume(returning: false) }
            }
        }
    }

    struct UsoDaPassphrase: Encodable {
        let resultado: String
        let falharam: String?
        let tronOutraChave: Bool
    }

    struct AbertaComPassphrase: Encodable {
        let carteira: CarteiraResumo
        let jaAberta: Bool
        /// A carteira escolhida antes: volta a ser, se a nova for descartada.
        let anterior: String?
    }

    /// O segredo em partes, cada uma com o tamanho na frente (4 bytes, big-endian). Por tamanho e
    /// nao por separador: uma passphrase com quebra de linha chegava cortada, sem aviso. Parte que
    /// passa do fim encerra a leitura (o que falta vira "segredo incompleto").
    static func dividir(_ segredo: SecureBytes) -> [SecureBytes] {
        segredo.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var partes: [SecureBytes] = []
            var inicio = 0
            while inicio + 4 <= bytes.count {
                let tamanho = Int(bytes[inicio]) << 24 | Int(bytes[inicio + 1]) << 16 | Int(bytes[inicio + 2]) << 8 | Int(bytes[inicio + 3])
                let fim = inicio + 4 + tamanho
                guard tamanho >= 0, fim <= bytes.count else { break }
                let parte = SecureBytes(capacity: max(tamanho, 1))
                if tamanho > 0 { parte.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[(inicio + 4)..<fim])) }
                partes.append(parte)
                inicio = fim
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
        case let falha as Reforco.Falha:
            switch falha {
            case .naoConfere(let nome):
                saida["erro"] = .string("reforco.naoConfere")
                saida["nome"] = .string(nome)
            case .passphraseAntiga(let nome):
                saida["erro"] = .string("reforco.passphraseAntiga")
                saida["nome"] = .string(nome)
            case .faltamPalavras:
                saida["erro"] = .string("reforco.faltamPalavras")
            case .semCarteiras:
                saida["erro"] = .string("reforco.semCarteiras")
            }
        case is PortaDaPassphrase.SemConferencia:
            saida["erro"] = .string("passphrase.semConferencia")
            saida["mensagem"] = .string(Textos.t("Esta versão do app não consegue conferir a passphrase desta carteira, e ela não assina aqui. As palavras com a passphrase continuam abrindo a carteira em qualquer carteira BIP-39."))
        case is PortaDaPassphrase.CardanoAntiga:
            saida["erro"] = .string("passphrase.semConferencia")
            saida["mensagem"] = .string(Textos.t("A conta da Cardano desta carteira saiu da passphrase exatamente como foi digitada na criação. Digite igual: o mesmo teclado, a mesma forma dos acentos e da largura dos caracteres."))
        case let espera as PortaDaPassphrase.Espera:
            saida["erro"] = .string("passphrase.espera")
            saida["ate"] = .number(espera.ate.timeIntervalSince1970 * 1000)
        case let falha as Signer.Failure where falha == .passphraseMismatch:
            saida["erro"] = .string("passphrase.errada")
        case let falha as Envelope.Failure:
            if case .tooExpensiveForThisDevice(let mib) = falha {
                saida["erro"] = .string("envelope.caro")
                saida["mib"] = .number(Double(mib))
            } else {
                saida["erro"] = .string("envelope." + String(describing: falha))
            }
        case let falha as SendEngineError:
            saida["erro"] = .string("envio.motor")
            if let mensagem = falha.errorDescription { saida["mensagem"] = .string(mensagem) }
        case let fraca as BIP39.WeakChoice:
            saida["erro"] = .string("frase.fraca." + String(describing: fraca))
        case let falha as HTTPClient.Failure:
            saida["erro"] = .string("rede." + String(describing: falha))
        // O aparelho que calcula diferente dos vetores publicos, com o texto proprio (revisao da decima terceira passada).
        case let falha as DerivationSelfTest.Failure:
            saida["erro"] = .string("autoteste.derivacao")
            if let mensagem = falha.errorDescription { saida["mensagem"] = .string(mensagem) }
        case let falha as SigningSelfTest.Failure:
            saida["erro"] = .string("autoteste.assinatura")
            if let mensagem = falha.errorDescription { saida["mensagem"] = .string(mensagem) }
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
        /// Todo envio pede os 6 ultimos caracteres do destino (sempre ligado no Super Security).
        let conferirEndereco: Bool
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
    /// O que falta da espera de "Esperar 24 horas" (Super Security), em segundos: a faixa da Carteira, de Seguranca e do bloqueio.
    let espera: Double
    let carteiras: [CarteiraResumo]
    let selecionada: String?
    let ajustes: Ajustes
    let responsabilidade: Int?
    let contatos: Int
    let aviso: Pacote.Aviso?

    static func agora() -> Estado {
        let aviso = Pacote.aviso()
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
            espera: root.securityMode == .hardened ? max(0, root.hardenedHoldRemaining) : 0,
            carteiras: metadata.wallets.map { CarteiraResumo($0, selecionada: $0.id == selecionada, todas: metadata.wallets) },
            selecionada: selecionada?.uuidString,
            ajustes: Ajustes(
                moeda: metadata.settings.currency, unidade: metadata.settings.totalUnit ?? metadata.settings.currency,
                ocultarSaldos: metadata.settings.hideBalances, autoTravar: Ajustes.prazo(metadata.settings.autoLockSeconds),
                tecladoProprio: (metadata.settings.ownKeyboard ?? true) || root.securityMode == .hardened,
                conferirEndereco: metadata.settings.confirmEveryAddress == true || root.securityMode == .hardened, protecaoMEV: metadata.settings.mevProtection,
                redesDesligadas: metadata.settings.disabledChainIDs.sorted(), apagarDepois: root.wipeThreshold, opcoesDeApagar: PINPolicy.wipeOptions
            ),
            responsabilidade: metadata.responsibilityVersion,
            contatos: metadata.contacts.count,
            aviso: aviso
        )
    }
}

struct CarteiraResumo: Encodable {
    /// `curto`: o comeco e o fim do endereco como o iOS mostra (o prefixo que a rede impoe
    /// inteiro, e 6 mais 4 do corpo).
    struct Conta: Encodable { let rede: String; let endereco: String; let curto: String }

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
    /// As redes com outra chave ou contrato no controle (auditoria 8): o endereco nao aparece nem copia.
    let outroControle: [String]
    /// As redes ainda nao lidas para outra chave no controle (`controlChecked`): o endereco espera a conferencia para aparecer e
    /// copiar (pedido do dono, 15/11/2026, a forma mais segura). Vazio na so de observacao, que nao e conferida.
    let naoLidas: [String]
    /// As redes cujo endereco outra carteira deste aparelho tem marcado (`marcadaEmOutra`): nao aparece nem copia (15/11/2026).
    let marcadaEmOutra: [String]
    /// Pede a passphrase para assinar e para ver as palavras: toda carteira com passphrase (05/11/2026).
    let pedePassphrase: Bool
    /// A carteira com passphrase que esta versao nao confere: ver, lacrar e conferir recusam antes da passphrase e do PIN.
    let semConferencia: Bool
    let selecionada: Bool
    let digital: String?
    let contas: [Conta]
    let copiaConfirmadaEm: Date?
    let passphraseConferidaEm: Date?
    let envelopeLacradoEm: Date?
    let vistaEm: Date?

    init(_ wallet: WalletMeta, selecionada: Bool, todas: [WalletMeta]? = nil) {
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
        // Toda rede com a marca, e numa EVM tambem a marca de outra EVM (o mesmo endereco e a mesma chave; rodada 2 da auditoria 8).
        outroControle = Set((wallet.foreignControl ?? [:]).keys).union(wallet.accounts.compactMap { conta in
            Chain.find(conta.chainID).flatMap { wallet.foreignControl(on: $0) != nil ? conta.chainID : nil }
        }).sorted()
        naoLidas = wallet.isWatchOnly ? [] : wallet.accounts.compactMap { conta in
            Chain.find(conta.chainID).flatMap { wallet.controlChecked(on: $0) ? nil : conta.chainID }
        }.sorted()
        let todas = todas ?? Sessao.shared.metadata.wallets
        marcadaEmOutra = wallet.accounts.compactMap { conta in
            Chain.find(conta.chainID).flatMap { todas.marcadaEmOutra(wallet, on: $0) != nil ? conta.chainID : nil }
        }.sorted()
        pedePassphrase = PortaDaPassphrase.pede(wallet)
        semConferencia = PortaDaPassphrase.semConferencia(wallet)
        self.selecionada = selecionada
        digital = wallet.fingerprint?.uppercased()
        contas = wallet.accounts.map { Conta(rede: $0.chainID, endereco: $0.address, curto: Fmt.endereco($0.address, chain: Chain.find($0.chainID))) }
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

/// Um valor com trava, para o que o nucleo guarda so na memoria entre um pedido e outro.
final class Guarda<Valor>: @unchecked Sendable {
    private let trava = NSLock()
    private var valor: Valor

    init(_ valor: Valor) { self.valor = valor }

    func withLock<Resultado>(_ corpo: (inout Valor) -> Resultado) -> Resultado {
        trava.lock()
        defer { trava.unlock() }
        return corpo(&valor)
    }
}
