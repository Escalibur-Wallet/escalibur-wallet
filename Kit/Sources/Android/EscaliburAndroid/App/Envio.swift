import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import EscaliburNetwork
import Foundation

/// Um envio em andamento: o `SendModel` e o `SendStages` do iOS (Features/Send/SendFlow.swift),
/// sem a interface. Toda conferencia de seguranca do destino, do plano e da transmissao roda aqui,
/// igual ao iOS; a interface (Kotlin) so mostra o retrato (`Estado`) e devolve o que o dono digitou.
final class Envio: @unchecked Sendable {
    enum Etapa: String, Encodable { case destino, tag, valor, revisao, enviando, enviado, incerto }

    private static let trava = NSLock()
    nonisolated(unsafe) private static var corrente: Envio?

    static var atual: Envio? { trava.withLock { corrente } }

    static func comecar(ativo id: String) throws -> Envio {
        let metadata = Sessao.shared.metadata
        guard let wallet = metadata.selectedWallet, !wallet.isWatchOnly else { throw Sessao.Falha.carteiraNaoEncontrada }
        _ = Saldos.shared.mostrar()
        var achado = Saldos.shared.posicoes(carteira: wallet.id).first { $0.asset.id == id }
        #if DEBUG
        // A carteira de teste nao tem saldo: o teste do destino e dos desafios entra com zero.
        if achado == nil, id.hasPrefix("demo:"), let chain = Chain.find(String(id.dropFirst(5))) {
            achado = Holding(asset: .native(chain), amount: BigUInt())
        }
        #endif
        guard let holding = achado else { throw Nucleo.Falha(erro: "envio.semSaldo") }
        if holding.asset.isCustom, let motivo = holding.asset.chain.flatMap(CustomToken.sendUnavailableReason) {
            throw Nucleo.Falha(erro: "envio.indisponivel:" + motivo)
        }
        let envio = Envio(wallet: wallet, holding: holding)
        trava.withLock { corrente = envio }
        return envio
    }

    static func encerrar() { trava.withLock { corrente = nil } }

    /// Em revisao, transmitindo ou sem resposta: fechar a tela agora esconderia o id do envio, e o dono
    /// poderia mandar de novo (caca de bugs de 27/10/2026).
    var critico: Bool { trava.withLock { [.revisao, .enviando, .incerto].contains(etapa) } }

    /// A tela que fechou encerra o envio dela, nunca o de uma tela aberta depois.
    static func encerrar(_ id: String) { trava.withLock { if corrente?.id.uuidString == id { corrente = nil } } }

    let id = UUID()
    private let trava = NSLock()
    let wallet: WalletMeta
    private(set) var holding: Holding
    private(set) var etapa: Etapa = .destino

    private var textoDoDestino = ""
    private var destino: Address.Destination?
    private var problema: String?
    private var problemaDoLink: (texto: String, mensagem: String)?
    private var infoDoDestino: DestinationInfo?
    private var parecido: String?
    private var conferenciaDoParecido = ""
    private var trechoDoParecido: AddressPoisoning.Segment?
    private var outroID: AddressPoisoning.SameAccount?
    private var conferenciaDoOutroID = ""
    private var historico: [String] = []
    private var historicoIndisponivel = false
    /// O desafio escondido e o da opcao "Conferir o endereco em todo envio".
    private var cegoDeTodoEnvio = false
    /// Nome da NEAR: o texto cujo desafio ja nasceu, no toque do Continuar ou na entrada inteira, sem a rede. Digitando, cada comeco
    /// ja e conta valida ("bo" de "bob.near"), e o desafio nascia no segundo caractere (o nearArmedFor do iOS, revisao dos 3
    /// agentes, 09/11/2026).
    private var nomeArmado: String?
    /// Nome da NEAR valido no campo, com o desafio ainda por nascer: o Continuar o faz nascer.
    private var nomePendente = false
    /// O nome inteiro digitado nao conferiu no toque do Continuar.
    private var nomeNaoConfere = false
    /// Primeiro envio para quem nao e contato nem carteira: o desafio escondido pode nascer quando o prazo do historico vencer.
    private var cegoPossivel = false
    /// A tag, o memo ou o comentario tinha um segredo e foi apagado (o tagNotice do iOS).
    private var avisoDaTag: String?
    private var historicoLido = false
    private var trechoCego: AddressPoisoning.Segment?
    private var fonteCega = ""
    private var conferenciaCega = ""
    /// A rede do historico deste envio: a lista de quem ja recebeu so cresce dentro dela, e voltar ao destino nao le de
    /// novo (revisao de seguranca de 06/11/2026; o `historyChainID` do iOS).
    private var historicoRede: String?
    /// A leitura do historico terminou, lida ou falha. A revisao espera por ela.
    private var historicoTerminado = false
    /// A revisao esperando a leitura: a tela diz por que demora.
    private var conferindoHistorico = false
    /// Sobe a cada validacao: a tela zera os campos dos desafios junto com o nucleo.
    private var rodadaDoDesafio = 0
    /// Quando a leitura desta rede comecou: o teto da espera da revisao conta daqui, e nao de cada toque.
    private var historicoInicio: ContinuousClock.Instant?
    private var primeiroEnvio = false
    private var tag = ""
    private var tagDoLink: String?
    /// O prazo do pedido de pagamento lido (o `exp` da TON) e o endereco a que ele vale, conferido na assinatura (rodada 3 da
    /// auditoria 8), como no iOS.
    private var prazoDoLink: (endereco: String, expira: UInt64)?
    private var pulouTag = false
    private var sugestaoDeRede: Holding?
    private var redeConfirmada = false
    private var textoDoValor = ""
    private var tudo = false
    private var disponivel: Spendable?
    private var nivelDaTaxa: FeeLevel = .normal
    private var plano: SigningPlan?
    /// Sobe quando a renovacao na revisao mudou o valor ou a taxa.
    private var versaoDaRevisao = 0
    /// A ultima renovacao mudou o valor ou a taxa (some ao revisar de novo).
    private var revisaoMudou = false
    private var erro: String?
    private var idDoResultado: String?
    private var situacao: TransferStatus = .pending
    private var assinadoIncerto: [SignedTransaction]?
    private var detalheIncerto: String?

    private init(wallet: WalletMeta, holding: Holding) {
        self.wallet = wallet
        self.holding = holding
    }

    var chain: Chain? { holding.asset.chain }
    var conta: DerivedAccount? { chain.flatMap { wallet.account($0) } }
    private var motor: (any SendEngine)? { chain.flatMap { SendEngines.engine(for: $0) } }

    // MARK: O retrato

    struct Trecho: Encodable { let inicio: Int; let tamanho: Int }

    struct Estado: Encodable {
        struct Ativo: Encodable {
            let id: String, simbolo: String, nome: String, rede: String, redeNome: String, redeCoingecko: String
            let coingecko: String?, casas: Int, custom: Bool, conferido: Bool, quantidade: String, disponivel: String
        }
        /// `caixaConta`: o desafio confere maiusculas e minusculas (`AddressPoisoning.caseMatters`), e a tela avisa.
        struct Parecido: Encodable { let conhecido: String; let rotulo: String; let trechoColado: Trecho?; let trechoConhecido: Trecho?; let caixaConta: Bool }
        struct OutroID: Encodable {
            let conhecido: String; let idConhecido: String; let rotulo: String; let trechoColado: Trecho?; let trechoConhecido: Trecho?
        }
        struct Cego: Encodable {
            let fonte: String; let trecho: Trecho
            /// O desafio e o de "Conferir o endereco em todo envio" (os 6 ultimos), e nao o do historico ilegivel.
            let todoEnvio: Bool
            let caixaConta: Bool
        }
        struct Sugestao: Encodable { let ativo: String; let simbolo: String; let redeNome: String }
        struct Disponivel: Encodable { let quantidade: String; let notaDeReserva: String?; let notaDeTaxa: String? }
        struct LinhaDaPlaca: Encodable { let rotulo: String; let valor: String; let endereco: Bool }
        struct Linha: Encodable { let rotulo: String; let valor: String }
        struct Plano: Encodable {
            let titulo: String; let placa: [LinhaDaPlaca]; let linhas: [Linha]; let avisos: [String]; let saida: String
            /// Quando os dados da rede vencem (ms desde 1970): a tela renova um pouco antes.
            let venceEm: Double
            /// Sobe quando a renovacao mudou o valor ou a taxa: o aceite e o deslizar recomecam.
            let versao: Int
            /// A renovacao mudou o valor ou a taxa: a tela avisa e pede para confirmar de novo.
            let mudou: Bool
        }
        struct Resultado: Encodable {
            let id: String; let situacao: String; let detalhe: String?; let explorador: String?; let urlDoExplorador: String?
        }

        let etapa: Etapa
        let ativo: Ativo
        let familia: String
        let tipoDeTag: String
        let textoDoDestino: String
        let destino: String?
        let tagDoEndereco: String?
        let problema: String?
        let sugestao: Sugestao?
        let rotuloDoDestino: String?
        let primeiroEnvio: Bool
        let historicoLido: Bool
        let conferindoHistorico: Bool
        let rodadaDoDesafio: Int
        let parecido: Parecido?
        let outroID: OutroID?
        let cego: Cego?
        let precisaConfirmarRede: Bool
        let notaDaRede: String?
        let textoDaConfirmacaoDeRede: String?
        let muxed: Bool
        let precisaEtapaDaTag: Bool
        let exigeTag: Bool
        let tag: String
        let tagDoLink: Bool
        let problemaDaTag: String?
        let liberado: Bool
        let podeContinuar: Bool
        /// O botao Continuar: com o nome da NEAR por nascer ou o nome inteiro digitado, ele acende e confere no toque.
        /// `podeContinuar` continua a conferencia de verdade, a das etapas seguintes.
        let podeTocarContinuar: Bool
        let nomeNaoConfere: Bool
        /// O nome da NEAR que entrou inteiro e ainda nao tem o desafio calculado (o historico chegando, ou a rede errada): o campo
        /// e os blocos ficam escondidos, como com o desafio na tela (o wholeEntryHidden do iOS).
        let campoEscondido: Bool
        let avisoDaTag: String?
        let disponivel: Disponivel?
        let ativacao: String?
        let valor: String
        let tudo: Bool
        let plano: Plano?
        let erro: String?
        let resultado: Resultado?
        let detalheIncerto: String?
        let linhaDoEnvio: String
        let tempoDeConfirmacao: Int
        let contatos: [Contato]
        let minhasCarteiras: [MinhaCarteira]
        let variasCarteiras: Bool
    }

    struct Contato: Encodable { let nome: String; let endereco: String; let tag: String? }
    /// `liga`: uma e com passphrase e a outra nao; o envio fica na blockchain e liga as duas (revisao de
    /// seguranca de 24/10/2026), e a tela avisa antes de escolher.
    struct MinhaCarteira: Encodable { let id: String; let nome: String; let endereco: String; let liga: Bool }

    func estado() -> Estado {
        trava.withLock { montarEstado() }
    }

    /// Chamar com a trava.
    private func montarEstado() -> Estado {
        let metadata = Sessao.shared.metadata
        let chain = holding.asset.chain ?? .ethereum
        let asset = holding.asset
        let saldo = saldoDaRede()
        let livre = saldo.map { $0.available(holding) } ?? holding.amount
        let ativo = Estado.Ativo(
            id: asset.id, simbolo: asset.symbol, nome: asset.name, rede: chain.id, redeNome: chain.name, redeCoingecko: chain.coingeckoID,
            coingecko: asset.coingeckoID, casas: asset.decimals, custom: asset.isCustom, conferido: asset.isVerified,
            quantidade: holding.amount.decimalString, disponivel: (disponivel?.amount ?? livre).decimalString
        )
        let parecidoDTO: Estado.Parecido? = parecido.flatMap { conhecido in
            destino.map { destino in
                Estado.Parecido(
                    conhecido: conhecido, rotulo: rotuloConhecido(conhecido, chain: chain),
                    trechoColado: trechoDoParecido.map(trecho), trechoConhecido: AddressPoisoning.differingSegment(conhecido, from: destino.address, chain: chain).map(trecho),
                    caixaConta: AddressPoisoning.caseMatters(destino.address, chain: chain)
                )
            }
        }
        let outroDTO: Estado.OutroID? = outroID.flatMap { conhecido in
            destino.map { destino in
                Estado.OutroID(
                    conhecido: conhecido.known, idConhecido: String(conhecido.knownID), rotulo: rotuloConhecido(conhecido.known, chain: chain),
                    trechoColado: AddressPoisoning.muxedIDSegment(destino.address).map(trecho), trechoConhecido: AddressPoisoning.muxedIDSegment(conhecido.known).map(trecho)
                )
            }
        }
        let cego: Estado.Cego? = (parecido == nil) ? trechoCego.map {
            Estado.Cego(fonte: fonteCega, trecho: trecho($0), todoEnvio: cegoDeTodoEnvio, caixaConta: AddressPoisoning.caseMatters(fonteCega, chain: chain))
        } : nil
        let resultado = idDoResultado.map { id -> Estado.Resultado in
            let (nome, detalhe): (String, String?)
            switch situacao {
            case .pending: (nome, detalhe) = ("pendente", nil)
            case .confirmed(let texto): (nome, detalhe) = ("confirmado", texto)
            case .failed(let motivo): (nome, detalhe) = ("falhou", motivo)
            }
            return Estado.Resultado(id: id, situacao: nome, detalhe: detalhe, explorador: chain.explorerName, urlDoExplorador: chain.explorerURL(tx: id)?.absoluteString)
        }
        return Estado(
            etapa: etapa, ativo: ativo, familia: chain.family.rawValue, tipoDeTag: chain.destinationTag.rawValue,
            textoDoDestino: textoDoDestino, destino: destino?.address, tagDoEndereco: destino?.tag.map(String.init), problema: problema,
            sugestao: sugestaoDeRede.flatMap { s in s.asset.chain.map { Estado.Sugestao(ativo: s.asset.id, simbolo: s.asset.symbol, redeNome: $0.name) } },
            rotuloDoDestino: destino.map { _ in chain.id == "xrpl" ? preencher(Textos.t("Endereço do %@"), chain.name)
                : preencher(Textos.t("Endereço da %@"), chain.name) },
            primeiroEnvio: primeiroEnvio, historicoLido: historicoLido, conferindoHistorico: conferindoHistorico,
            rodadaDoDesafio: rodadaDoDesafio, parecido: parecidoDTO, outroID: outroDTO, cego: cego,
            precisaConfirmarRede: precisaConfirmarRede, notaDaRede: precisaConfirmarRede ? notaDaConfirmacao(chain) : nil,
            textoDaConfirmacaoDeRede: precisaConfirmarRede ? (chain.family == .near ? Textos.t("Este endereço é de uma conta NEAR")
                : preencher(Textos.t("Quem vai receber aceita %@ pela %@"), asset.symbol, chain.name)) : nil,
            muxed: muxed, precisaEtapaDaTag: precisaEtapaDaTag, exigeTag: infoDoDestino?.requiresTag == true, tag: tag,
            tagDoLink: tagDoLink != nil && tagDoLink == tag, problemaDaTag: problemaDaTag, liberado: liberado,
            podeContinuar: destino != nil && historicoLido && liberado && problemaDaTag == nil && (!precisaConfirmarRede || redeConfirmada),
            podeTocarContinuar: destino != nil && historicoLido && (liberado || nomePendente || nomeInteiroDigitado) && problemaDaTag == nil
                && (!precisaConfirmarRede || redeConfirmada),
            nomeNaoConfere: nomeNaoConfere,
            campoEscondido: nomeColadoSemDesafio,
            avisoDaTag: avisoDaTag,
            disponivel: disponivel.map { Estado.Disponivel(quantidade: $0.amount.decimalString, notaDeReserva: $0.reserveNote, notaDeTaxa: $0.feeNote) },
            ativacao: infoDoDestino?.activationMinimum.map { Fmt.cripto($0, casas: asset.decimals, simbolo: asset.symbol) },
            valor: textoDoValor, tudo: tudo, plano: plano.map(planoDTO), erro: erro, resultado: resultado, detalheIncerto: detalheIncerto,
            linhaDoEnvio: linhaDoEnvio(), tempoDeConfirmacao: chain.typicalConfirmationSeconds,
            contatos: metadata.contacts.filter { $0.chainID == chain.id }.map { Contato(nome: $0.name, endereco: $0.address, tag: $0.tag) },
            minhasCarteiras: minhasCarteiras(chain, metadata).map {
                MinhaCarteira(id: $0.wallet.id.uuidString, nome: $0.wallet.name, endereco: $0.address,
                              liga: $0.wallet.hasPassphrase != (metadata.selectedWallet?.hasPassphrase ?? false))
            },
            variasCarteiras: metadata.wallets.count > 1
        )
    }

    private func trecho(_ segmento: AddressPoisoning.Segment) -> Trecho { Trecho(inicio: segmento.start, tamanho: segmento.length) }

    private func saldoDaRede() -> ChainBalance? {
        guard let chain else { return nil }
        return Saldos.shared.saldo(chain, carteira: wallet.id)
    }

    // MARK: Regras do destino (as do SendModel)

    private var muxed: Bool {
        guard chain?.family == .stellar, let address = destino?.address else { return false }
        return StellarMuxedAccount(address: address)?.isMuxed == true
    }

    private var precisaEtapaDaTag: Bool {
        guard let chain, chain.destinationTag != .none, !muxed else { return false }
        return infoDoDestino?.requiresTag == true
    }

    static func hex64(_ texto: String) -> Bool { texto.count == 64 && texto.allSatisfy(\.isHexDigit) }

    private var precisaConfirmarRede: Bool {
        guard let chain, let destino, primeiroEnvio else { return false }
        switch chain.family {
        case .evm, .sui, .aptos: return true
        case .near: return Self.hex64(destino.address)
        default: return false
        }
    }

    /// Sem endereco parecido, nada a conferir. Com ele, so segue quem digitou o trecho do meio
    /// onde o destino difere do conhecido. Com a mesma conta e outro ID, quem digitou o ID.
    private var liberado: Bool {
        if nomePendente { return false }
        if let segmento = trechoCego, parecido == nil {
            guard AddressPoisoning.answers(conferenciaCega, segment: segmento, of: fonteCega, chain: chain) else { return false }
        }
        if outroID != nil {
            guard let address = destino?.address, AddressPoisoning.muxedIDConfirmed(conferenciaDoOutroID, address: address) else { return false }
        }
        guard parecido != nil, let address = destino?.address else { return true }
        guard let segmento = trechoDoParecido else { return false }
        return AddressPoisoning.answers(conferenciaDoParecido, segment: segmento, of: address, chain: chain)
    }

    private var problemaDaTag: String? {
        guard let chain else { return nil }
        return Self.problemaDaTag(tag, rede: chain)
    }

    /// A tag ou o memo que a rede aceita. O mesmo vale ao salvar um contato: antes ele gravava uma tag que
    /// o envio depois recusava, e o Continuar ficava apagado sem explicacao (caca de bugs de 27/10/2026).
    static func problemaDaTag(_ tag: String, rede chain: Chain) -> String? {
        guard !tag.isEmpty else { return nil }
        switch chain.destinationTag {
        case .xrplTag: return UInt32(tag) == nil ? Textos.t("A tag é um número de 0 a 4.294.967.295. Confira na exchange.") : nil
        case .stellarMemo: return tag.utf8.count > 28 && UInt64(tag) == nil ? Textos.t("O memo cabe até 28 caracteres.") : nil
        default: return nil
        }
    }

    private func notaDaConfirmacao(_ chain: Chain) -> String {
        switch chain.family {
        case .sui: return Textos.t("Endereços Sui têm o mesmo formato dos endereços Aptos, então o endereço não diz a rede. Se quem vai receber espera o valor pela Aptos ou por outra rede, ele não chega.")
        case .aptos: return Textos.t("Endereços Aptos têm o mesmo formato dos endereços Sui, então o endereço não diz a rede. Se quem vai receber espera o valor pela Sui ou por outra rede, ele não chega.")
        case .near: return Textos.t("Contas NEAR sem nome têm 64 letras e números, o mesmo formato de um endereço Sui ou Aptos sem o 0x. Se este endereço é de outra rede, o valor vai para uma conta NEAR que ninguém controla e se perde.")
        default: return preencher(Textos.t("Endereços EVM são iguais em todas as redes EVM, então o endereço não diz a rede. Se quem vai receber só aceita %@ por outra rede (uma exchange que recebe só pela Ethereum, por exemplo), o valor não chega."), holding.asset.symbol)
        }
    }

    /// De onde o dono conhece um endereco: "voce ja pagou" e "salvo, nunca recebeu" pesam diferente.
    private func rotuloConhecido(_ address: String, chain: Chain) -> String {
        let metadata = Sessao.shared.metadata
        let enviados = metadata.sentTo[chain.id] ?? []
        if enviados.contains(address) || historico.contains(address) { return Textos.t("Você já pagou") }
        if let carteira = metadata.wallets.first(where: {
            !$0.isWatchOnly && $0.tronForeignControl != true && $0.foreignControl(on: chain) == nil && $0.controlChecked(on: chain) && $0.account(chain)?.address == address
        }) {
            return preencher(Textos.t("Sua carteira %@"), carteira.name)
        }
        if let contato = metadata.contacts.first(where: { $0.chainID == chain.id && $0.address == address }) {
            return preencher(Textos.t("Salvo como %@, nunca recebeu daqui"), contato.name)
        }
        return Textos.t("Você já usou")
    }

    /// Tudo que o dono pode reconhecer de vista nesta rede: para onde ja enviou, os contatos, as
    /// carteiras deste aparelho (menos as de so observar) e o historico lido.
    private func conhecidos(_ chain: Chain) -> [String] {
        let metadata = Sessao.shared.metadata
        return (metadata.sentTo[chain.id] ?? []) + metadata.contacts.filter { $0.chainID == chain.id }.map(\.address)
            + metadata.wallets.filter { !$0.isWatchOnly }.compactMap { $0.account(chain)?.address } + historico
    }

    private func contatosComTag(_ chain: Chain) -> [(address: String, tag: String)] {
        Sessao.shared.metadata.contacts.filter { $0.chainID == chain.id }.compactMap { contato in contato.tag.map { (address: contato.address, tag: $0) } }
    }

    // MARK: Destino

    /// Quanto o Continuar espera a leitura do historico da rede (06/11/2026: na Ethereum, o explorador chegava a 20 s). O
    /// `historyWait` do iOS. Passado o prazo, valem o que o app ja guardou e o trecho escondido no primeiro envio, como sem
    /// historico; a leitura segue, a revisao espera por ela, e um parecido achado nela volta a pedir a conferencia.
    static let esperaDoHistorico: Duration = .seconds(4)
    /// O teto da espera da revisao pela leitura. Passado, segue como sem historico.
    static let esperaDaRevisao: Duration = .seconds(30)

    /// Para quem esta carteira ja pagou nesta rede, do historico da propria rede. Sem ele, o
    /// primeiro envio pede o trecho escondido. Volta com a leitura ou com o prazo, o que vier antes.
    func lerHistorico() async {
        guard let chain, let conta else {
            trava.withLock {
                historicoLido = true
                historicoTerminado = true
            }
            return
        }
        // Outra rede, ou a primeira: a lista e a leitura recomecam. Na mesma rede, a leitura deste envio vale: voltar ao
        // destino nao le de novo, e a lista so cresce (revisao de seguranca de 06/11/2026).
        let comecar = trava.withLock { () -> Bool in
            guard historicoRede != chain.id else { return false }
            historicoRede = chain.id
            historico = []
            historicoIndisponivel = false
            historicoTerminado = false
            historicoLido = false
            historicoInicio = .now
            return true
        }
        if comecar {
            let uso = wallet.utxoUsage[chain.id]
            Task {
                let lido = try? await ActivitySources.source(for: chain)?.history(chain: chain, account: conta, usage: uso)
                if self.aplicarHistorico(lido, chain: chain) { self.avisar() }
            }
        }
        let inicio = ContinuousClock.now
        while !trava.withLock({ historicoLido }), ContinuousClock.now - inicio < Self.esperaDoHistorico {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        trava.withLock {
            guard self.chain?.id == chain.id, historicoRede == chain.id, !historicoLido else { return }
            // O prazo passou sem a leitura: soma o historico guardado pela Atividade, e o trecho escondido do primeiro envio.
            let guardado = (Sessao.shared.metadata.activityCache?[wallet.id] ?? []).compactMap(\.entry).filter { $0.chainID == chain.id }
            historico = Array(Set(historico + Self.pagos(guardado)))
            historicoIndisponivel = true
            historicoLido = true
            if destino != nil { validar() }
        }
    }

    /// A leitura do historico, no prazo ou depois dele. Devolve se validou de novo depois do prazo: a tela precisa saber.
    private func aplicarHistorico(_ lido: [ActivityEntry]?, chain: Chain) -> Bool {
        trava.withLock { () -> Bool in
            guard self.chain?.id == chain.id, historicoRede == chain.id else { return false }
            historicoTerminado = true
            let tarde = historicoLido
            guard let entradas = lido else {
                guard !tarde else { return false }
                historicoIndisponivel = true
                historicoLido = true
                if destino != nil { validar() }
                return false
            }
            historico = Array(Set(historico + Self.pagos(entradas)))
            guard tarde else {
                historicoIndisponivel = false
                historicoLido = true
                if destino != nil { validar() }
                return false
            }
            // Depois do prazo, o trecho escondido que ja esta na tela fica; um parecido, ou o mesmo M da Stellar com outro ID,
            // achado agora valida de novo, e a revisao e a assinatura voltam ao destino se ele nao estiver conferido.
            guard let destino, achadoTardio(destino.address, chain: chain) else { return false }
            validar()
            // Ja na tag, no valor ou na revisao: volta ao destino agora, antes de a passphrase e o PIN serem pedidos para um
            // envio que a assinatura recusaria (rodada 19 dos 3 agentes, 06/11/2026).
            if [.tag, .valor, .revisao].contains(etapa) { etapa = .destino }
            return true
        }
    }

    /// A leitura tardia achou o que o destino de agora ainda nao conferiu.
    private func achadoTardio(_ endereco: String, chain: Chain) -> Bool {
        let conhecidos = conhecidos(chain)
        if parecido == nil, AddressPoisoning.lookalike(endereco, among: conhecidos, chain: chain) != nil { return true }
        return outroID == nil
            && AddressPoisoning.sameAccountOtherID(endereco, among: conhecidos, tagged: contatosComTag(chain), chain: chain) != nil
    }

    private static func pagos(_ entradas: [ActivityEntry]) -> [String] {
        Array(Set(entradas.compactMap { entrada -> String? in
            guard entrada.direction == .sent, entrada.status == .confirmed, !entrada.suspicious else { return nil }
            return entrada.counterparty
        }))
    }

    /// O desafio na tela e o nome inteiro de uma conta NEAR: conferido no toque do Continuar, e nao ao vivo, para o botao nao
    /// acender no meio do nome verdadeiro, no tamanho de um colado que seja o comeco dele (revisao dos 3 agentes, 09/11/2026).
    /// Chamar com a trava.
    private var nomeInteiroNaTela: Bool {
        if parecido != nil, let segmento = trechoDoParecido, let endereco = destino?.address { return AddressPoisoning.coversAll(segmento, of: endereco) }
        if parecido == nil, let segmento = trechoCego { return AddressPoisoning.coversAll(segmento, of: fonteCega) }
        return false
    }

    /// O nome da NEAR armado (entrou inteiro) e o desafio ainda por calcular. Chamar com a trava.
    /// So na NEAR (com destino) ou com o texto que e nome da NEAR (sem destino): o bc1 e o addr1 tambem passam pela gramatica do
    /// nome, e na Bitcoin o campo sumia a toa enquanto o historico chegava (como no iOS).
    private var nomeColadoSemDesafio: Bool {
        let texto = textoDoDestino.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return false }
        // Sem destino: o colado inteiro que a sugestao de rede torna destino com um desafio. No envio, a rede so muda pela sugestao:
        // sem ela, esconder so tirava do dono o que ele colou (como no iOS).
        guard destino != nil, let chain else { return nomeArmado == texto && sugestaoDeRede != nil }
        guard !historicoLido else { return false }
        // Nome da NEAR digitado letra a letra fica a vista (o desafio espera o Continuar); armado, escondido.
        if chain.family == .near, AddressPoisoning.wholeNEARName(texto, chain: chain) != nil { return nomeArmado == texto }
        // Em toda rede, o desafio escondido pode nascer quando o prazo do historico vencer: a vista, os blocos destacavam o fim
        // (o wholeEntryHidden do iOS, revisao dos 3 agentes, 09/11/2026).
        return cegoPossivel
    }

    private var nomeInteiroDigitado: Bool { nomeInteiroNaTela && !(parecido != nil ? conferenciaDoParecido : conferenciaCega).isEmpty }

    func mudarDestino(_ texto: String) {
        trava.withLock {
            // O endereco que entra inteiro (colar pelo menu ou pelo teclado), medido pelo que entrou: o desafio do nome nasce na
            // hora. So a digitacao, letra a letra, espera o Continuar.
            if AddressPoisoning.enteredWhole(from: textoDoDestino, to: texto) { armarNome(texto) }
            textoDoDestino = texto
            validar()
        }
    }

    /// O que veio do QR ou do colar: o link de outra rede nem entra no campo, e a tag do link vai
    /// para o campo, dita na tela.
    func aplicarLink(_ texto: String) {
        trava.withLock {
            var problema: String?
            var leitura: PaymentLink.Reading?
            do {
                leitura = try PaymentLink.read(texto)
            } catch PaymentLink.Problem.tooLong {
                problema = Textos.t("Este código é longo demais para ser um endereço.")
            } catch PaymentLink.Problem.containsPhrase {
                problema = Textos.t("Este código traz as palavras de uma senha de carteira, não um endereço. Quem tem essas palavras tem o saldo: não mostre a ninguém.")
            } catch PaymentLink.Problem.containsPrivateKey {
                problema = Textos.t("Isto parece uma chave privada, não um endereço. Quem tem essa chave tem o saldo: não mostre a ninguém.")
            } catch PaymentLink.Problem.unknownScheme {
                problema = Textos.t("O app não reconhece este tipo de link. Cole só o endereço.")
            } catch PaymentLink.Problem.unsupportedNetwork {
                problema = Textos.t("Este pedido de pagamento é de uma rede que a Escalibur não envia. Confira com quem pediu.")
            } catch PaymentLink.Problem.unsupportedMemo {
                problema = Textos.t("Este pedido traz um memo que o app não envia como está. Cole só o endereço e digite o memo, conferindo com quem pediu.")
            } catch PaymentLink.Problem.expiredRequest {
                problema = Textos.t("Este pedido de pagamento venceu. Peça um novo a quem cobrou.")
            } catch {
                problema = Textos.t("Este pedido de pagamento não pôde ser lido com segurança. Peça só o endereço.")
            }
            if problema == nil, let leitura, let chain {
                if !PaymentLink.matches(leitura.asset, asset: holding.asset) {
                    // O link que pede outra moeda que a da tela: recusado, como no iOS (rodada 1 da auditoria 8).
                    problema = preencher(Textos.t("Este pedido é de outra moeda, e o envio é de %@. Confira com quem pediu antes de enviar."), holding.asset.symbol)
                } else if let pedida = leitura.chainID, pedida != chain.id {
                    let nome = Chain.find(pedida)?.name ?? Textos.t("outra rede")
                    problema = preencher(Textos.t("Este pedido é da rede %@, e o envio é pela %@. Confira com quem pediu antes de enviar."), nome, chain.name)
                } else if let familia = leitura.family, familia != chain.family {
                    problema = preencher(Textos.t("Este pedido é de outra rede, e o envio é pela %@. Confira com quem pediu antes de enviar."), chain.name)
                }
            }
            let endereco = problema == nil ? (leitura?.address ?? "") : ""
            problemaDoLink = problema.map { (texto: endereco, mensagem: $0) }
            armarNome(endereco)
            textoDoDestino = endereco
            tag = ""
            tagDoLink = nil
            prazoDoLink = problema == nil ? leitura?.expiresAt.map { (endereco: endereco, expira: $0) } : nil
            validar()
            if problema == nil, let tagLida = leitura?.tag, !tagLida.isEmpty, let chain, chain.destinationTag != .none, destino != nil, !muxed {
                guardarTag(tagLida)
                tagDoLink = tag.isEmpty ? nil : tagLida
            }
        }
    }

    /// Chamar com a trava. A mesma validacao do iOS (SendStages.validate).
    private func validar() {
        guard let chain else { return }
        destino = nil
        problema = nil
        parecido = nil
        trechoDoParecido = nil
        conferenciaDoParecido = ""
        outroID = nil
        conferenciaDoOutroID = ""
        trechoCego = nil
        // A resposta do trecho escondido e do desafio de antes: cada validacao pede de novo.
        conferenciaCega = ""
        rodadaDoDesafio &+= 1
        // A consulta do destino (tag, ativacao) era do destino de antes: o Continuar consulta de novo (como no iOS).
        infoDoDestino = nil
        // Pular a tag foi escolha para o destino de antes.
        pulouTag = false
        cegoDeTodoEnvio = false
        nomePendente = false
        nomeNaoConfere = false
        cegoPossivel = false
        sugestaoDeRede = nil
        redeConfirmada = false
        if let link = problemaDoLink {
            if link.texto == textoDoDestino {
                problema = link.mensagem
                return
            }
            problemaDoLink = nil
        }
        let texto = textoDoDestino.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        // A frase (ou a chave, ou os 64 hexadecimais que nesta rede nao sao endereco) digitada ou colada sai do campo na hora.
        if Self.pareceFrase(texto) || PrivateKeyGuard.looksLikeHexKey(texto, on: chain) {
            // A frase tambem nao fica na marca do nome da NEAR (revisao dos 3 agentes, 09/11/2026).
            nomeArmado = nil
            textoDoDestino = ""
            let mensagem = Self.avisoDoSegredo(texto, rede: chain)
            problemaDoLink = (texto: "", mensagem: mensagem)
            problema = mensagem
            return
        }
        switch Address.validate(texto, for: chain) {
        case .success(let destination):
            if wallet.accounts.contains(where: { $0.address == destination.address }) {
                problema = Textos.t("Este endereço é desta mesma carteira.")
                return
            }
            // O endereco de uma carteira deste celular em outra rede de mesmo formato (Sui, Aptos, conta
            // implicita da NEAR): parece seu, mas aqui nenhuma chave sua o controla.
            let proprias = Sessao.shared.metadata.wallets.filter { !$0.isWatchOnly }.flatMap(\.accounts)
            if let outra = CrossNetworkSelf.network(of: destination.address, on: chain, own: proprias) {
                problema = preencher(Textos.t("Este endereço é da sua carteira na rede %@. Nesta rede ele não é seu: o que for enviado se perde."), outra.name)
                return
            }
            // Uma conta deste celular com outra chave no controle nesta rede: o envio para ela e um deposito que quem controla a
            // outra chave leva (pedido do dono, 15/11/2026, a forma mais segura, como o Receber e o iOS).
            if let dona = Sessao.shared.metadata.wallets.donaMarcada(de: destination.address, on: chain) {
                problema = preencher(Textos.t("Este endereço é da carteira %@, e lá a rede mostrou outra chave no controle. O que for enviado para ele, quem controla essa chave leva."), dona.name)
                return
            }
            destino = destination
            if let tagDoEndereco = destination.tag { tag = String(tagDoEndereco) }
            if chain.destinationTag == .none || muxed { tag = ""; tagDoLink = nil }
            let metadata = Sessao.shared.metadata
            let enviados = metadata.sentTo[chain.id] ?? []
            primeiroEnvio = !enviados.contains(destination.address)
            let contatos = metadata.contacts.filter { $0.chainID == chain.id }.map(\.address)
            // So as de "Minhas carteiras": a sem copia conferida e a com a Tron em outra chave (em
            // qualquer rede) nao contam como suas, e pedem a conferencia (auditoria de 30/10/2026,
            // revisao de 01/11/2026).
            let carteiras = metadata.wallets.filter {
                !$0.isWatchOnly && $0.hasBackup && $0.tronForeignControl != true && $0.foreignControl(on: chain) == nil && $0.controlChecked(on: chain)
            }.compactMap { $0.account(chain)?.address }
            let conhecidos = conhecidos(chain)
            cegoPossivel = primeiroEnvio && !contatos.contains(destination.address) && !carteiras.contains(destination.address)
            // Nome da NEAR: o desafio nasce no toque do Continuar, com o nome inteiro no campo (`continuar`).
            if AddressPoisoning.wholeNEARName(texto, chain: chain) != nil, nomeArmado != texto {
                nomePendente = true
                return
            }
            parecido = AddressPoisoning.lookalike(destination.address, among: conhecidos, chain: chain)
            trechoDoParecido = parecido.flatMap { AddressPoisoning.differingSegment(destination.address, from: $0, chain: chain) }
            outroID = AddressPoisoning.sameAccountOtherID(destination.address, among: conhecidos, tagged: contatosComTag(chain), chain: chain)
            if parecido == nil, outroID == nil, primeiroEnvio, historicoIndisponivel,
               !contatos.contains(destination.address), !carteiras.contains(destination.address) {
                fonteCega = texto
                // Os 6 ultimos, faceis de achar onde o endereco foi copiado (pedido do dono, 08/11/2026; antes era o meio, e o
                // dono escolheu o fim sabendo que quem troca o endereco copiado imita as pontas). O contato salvo segue no meio.
                trechoCego = AddressPoisoning.tailSegment(texto, chain: chain)
            }
            // "Conferir o endereco em todo envio" (Ajustes, Seguranca), sempre ligada no Super
            // Security: sem outro desafio na tela, todo envio pede os 6 ultimos caracteres,
            // escondidos, lidos na fonte. O mesmo desafio do historico ilegivel (pedido do dono, 23/10/2026).
            // Para uma carteira deste celular, nao pede: o endereco vem da propria carteira (pedido
            // do dono, 30/10/2026).
            if metadata.settings.confirmEveryAddress == true || Chaves.root.securityMode == .hardened,
               parecido == nil, outroID == nil, trechoCego == nil, !carteiras.contains(destination.address),
               let ultimos = AddressPoisoning.tailSegment(texto, chain: chain) {
                fonteCega = texto
                trechoCego = ultimos
                cegoDeTodoEnvio = true
            }
        case .failure(let falha):
            problema = Self.mensagem(falha, chain: chain)
            // A sugestao so quando o colado vale na rede sugerida: a Cardano reconhece tipos que ela mesma recusa como destino.
            if case .otherNetwork(let outra) = falha, case .success = Address.validate(texto, for: outra) { sugestaoDeRede = sugestao(para: outra) }
            // Um nome (com ponto) noutra rede: o aviso diz que e um nome, e nao manda copiar de novo (como no iOS).
            if case .malformed = falha, AddressPoisoning.nameNotAddress(texto, on: chain) {
                problema = preencher(Textos.t("Este é um nome, não um endereço. Cole o endereço da rede %@."), chain.name)
            }
        }
    }

    /// A chave privada colada (WIF, xprv, a semente da Stellar ou da XRPL, a chave da Solana) tem o mesmo destino da frase
    /// (`PrivateKeyGuard`, como o PhraseGuard do iOS, revisao dos 3 agentes, 09/11/2026).
    /// Tambem o pedaco da frase, o SeedQR e os 64 hexadecimais com rotulo de chave (como no iOS, revisao dos 3 agentes, 09/11/2026).
    static func pareceFrase(_ texto: String) -> Bool {
        PrivateKeyGuard.looksLikeSecretInAddressField(texto)
    }

    /// O aviso do segredo colado: o da chave, o dos 64 hexadecimais (chave ou codigo de transacao) ou o da frase.
    static func avisoDoSegredo(_ texto: String, rede: Chain? = nil) -> String {
        if PrivateKeyGuard.looksLikePrivateKey(texto) || PrivateKeyGuard.looksLikeLabeledHexKey(texto) {
            return Textos.t("Isto parece uma chave privada, não um endereço. Quem tem essa chave tem o saldo: não mostre a ninguém.")
        }
        if PrivateKeyGuard.looksLikeHexKey(texto, on: rede) {
            return Textos.t("Isto parece uma chave privada ou o código de uma transação, não um endereço. Se for uma chave, não mostre a ninguém.")
        }
        return Textos.t("Este código traz as palavras de uma senha de carteira, não um endereço. Quem tem essas palavras tem o saldo: não mostre a ninguém.")
    }

    /// O que e segredo num campo de endereco desta rede (o reconhecer do observar e o Colar usam sem rede).
    static func ehSegredo(_ texto: String, rede: Chain?) -> Bool {
        pareceFrase(texto) || PrivateKeyGuard.looksLikeHexKey(texto, on: rede)
    }

    /// A tag, o memo ou o comentario: com uma frase ou uma chave, sai na hora. O comentario da TON vai a rede ja na estimativa da
    /// taxa e, enviado, fica publico para sempre (o guardTag do iOS, revisao dos 3 agentes, 09/11/2026). Chamar com a trava.
    private func guardarTag(_ texto: String) {
        // A regra das 12 palavras soltas fica so no campo do endereco: aqui ela apagava qualquer comentario comprido.
        if PrivateKeyGuard.publicTextHasSecret(texto) {
            tag = ""
            avisoDaTag = Textos.t("Este campo tinha uma frase ou uma chave de carteira, e foi apagado. O que vai aqui fica público na rede.")
        } else {
            tag = String(texto.prefix(120))
            if !texto.isEmpty { avisoDaTag = nil }
        }
    }

    static func mensagem(_ falha: Address.Problem, chain: Chain) -> String {
        switch falha {
        case .empty: return ""
        case .otherNetwork(let outra):
            let nome = outra.family == .evm ? Textos.t("EVM (Ethereum, Base e outras)") : outra.name
            return chain.id == "xrpl"
                ? preencher(Textos.t("Este é um endereço %@. Para enviar pela rede %@, use um endereço do %@."), nome, chain.name, chain.name)
                : preencher(Textos.t("Este é um endereço %@. Para enviar pela rede %@, use um endereço da %@."), nome, chain.name, chain.name)
        case .badChecksum: return Textos.t("Uma letra deste endereço não confere. Ele pode ter sido copiado pela metade ou alterado. Copie de novo, inteiro.")
        case .unsupportedType: return Textos.t("Este tipo de endereço ainda não recebe envios desta carteira.")
        case .malformed:
            return chain.id == "xrpl"
                ? preencher(Textos.t("Este endereço não é do %@. Confira se copiou inteiro."), chain.name)
                : preencher(Textos.t("Este endereço não é da %@. Confira se copiou inteiro."), chain.name)
        }
    }

    /// A mesma moeda na rede do endereco colado, se a carteira tem saldo dela la. Moeda custom
    /// nunca troca de rede pelo simbolo.
    private func sugestao(para outra: Chain) -> Holding? {
        guard holding.asset.isVerified else { return nil }
        let candidatos = Saldos.shared.posicoes(carteira: wallet.id).filter { item in
            guard item.asset.isVerified, let rede = item.asset.chain else { return false }
            let mesmaRede = outra.family == .evm ? rede.family == .evm : rede.id == outra.id
            let mesmaMoeda = holding.asset.coingeckoID.map { $0 == item.asset.coingeckoID } ?? (item.asset.symbol == holding.asset.symbol)
            return mesmaRede && mesmaMoeda
        }
        return candidatos.first { $0.asset.chainID == outra.id } ?? candidatos.first
    }

    /// As outras carteiras deste app com conta nesta rede: o endereco vem da propria carteira. A
    /// que so observa fica de fora (nao e chave do dono), e a sem copia conferida tambem.
    private func minhasCarteiras(_ chain: Chain, _ metadata: Metadata) -> [(wallet: WalletMeta, address: String)] {
        metadata.wallets.compactMap { carteira in
            guard carteira.id != wallet.id, !carteira.isWatchOnly, carteira.hasBackup, let address = carteira.account(chain)?.address, !address.isEmpty,
                  // A carteira com a Tron em outra chave nao e sua em rede nenhuma: quem trocou a
                  // chave tem as palavras (revisao de seguranca de 01/11/2026).
                  carteira.tronForeignControl != true,
                  // Nem a conta com outra chave ou contrato no controle nesta rede: o que entrar nela pode sair sem a
                  // assinatura do dono, e aqui ele nao ve o aviso do Receber (auditoria 8, 14/11/2026).
                  carteira.foreignControl(on: chain) == nil,
                  // Nem a importada que nunca foi conferida (rodada 5 da auditoria 8), como no iOS.
                  carteira.controlChecked(on: chain) else { return nil }
            return (carteira, address)
        }
    }

    /// Um contato salvo (com a tag dele) ou outra carteira do dono (sem tag).
    func escolher(endereco: String, tag: String?) {
        trava.withLock {
            armarNome(endereco)
            textoDoDestino = endereco
            guardarTag(tag ?? "")
            validar()
        }
    }

    func trocarRede(ativo id: String) {
        trava.withLock {
            guard let novo = sugestaoDeRede, novo.asset.id == id else { return }
            holding = novo
            sugestaoDeRede = nil
            textoDoValor = ""
            tudo = false
            disponivel = nil
            historico = []
            historicoLido = false
            // O "historico ilegivel" era da rede de antes: o desafio dela nao nasce na nova antes da leitura (como no iOS).
            historicoIndisponivel = false
            historicoTerminado = false
            historicoRede = nil
            validar()
        }
    }

    func conferir(parecido: String?, outroID: String?, cego: String?, redeConfirmada: Bool?, tag: String?) {
        trava.withLock {
            if let parecido { conferenciaDoParecido = parecido }
            if let outroID { conferenciaDoOutroID = outroID }
            if let cego { conferenciaCega = cego }
            if parecido != nil || cego != nil { nomeNaoConfere = false }
            if let redeConfirmada { self.redeConfirmada = redeConfirmada }
            if let tag { guardarTag(tag) }
        }
    }

    func editarDestino() {
        trava.withLock {
            textoDoDestino = ""
            destino = nil
            problemaDoLink = nil
            parecido = nil
            trechoDoParecido = nil
            conferenciaDoParecido = ""
            outroID = nil
            conferenciaDoOutroID = ""
            trechoCego = nil
            cegoDeTodoEnvio = false
            conferenciaCega = ""
            nomeArmado = nil
            nomePendente = false
            nomeNaoConfere = false
            cegoPossivel = false
            infoDoDestino = nil
            pulouTag = false
            tag = ""
            tagDoLink = nil
            prazoDoLink = nil
            // O erro e a sugestao de rede do texto de antes saem com ele (o iOS revalida pelo onChange).
            validar()
        }
    }

    /// O endereco entrou inteiro (colar, QR, contato, Minhas carteiras): o desafio do nome da NEAR nasce na hora. Adiar ate o
    /// Continuar deixava o nome trocado a vista no campo (o armNEAR do iOS, revisao dos 3 agentes, 09/11/2026). Chamar com a trava.
    private func armarNome(_ texto: String) {
        // So o texto, sem a rede: colado noutra rede e trocado para a NEAR pela sugestao, o nome voltava a vista.
        nomeArmado = texto.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// De volta ao destino por um guard (a revisao, a assinatura): os passos dele recomecam, iguais na tela e no nucleo,
    /// como no `voltar` (rodada 19 dos 3 agentes). Chamar com a trava.
    private func voltarAoDestino() {
        etapa = .destino
        validar()
    }

    /// Continuar do destino: a rede diz se o destino existe e se exige tag.
    func continuar() async {
        // Nome da NEAR: o desafio nasce aqui, e o nome inteiro e conferido aqui (revisao dos 3 agentes, 09/11/2026). Sem desafio,
        // segue direto.
        let parar = trava.withLock { () -> Bool in
            if nomePendente {
                armarNome(textoDoDestino)
                validar()
                return parecido != nil || outroID != nil || trechoCego != nil
            }
            if nomeInteiroNaTela, !liberado {
                // Sem nada digitado (dois toques rapidos), nada a dizer: alarme falso ensina a ignorar o verdadeiro.
                nomeNaoConfere = nomeInteiroDigitado
                return true
            }
            return false
        }
        if parar { return }
        let (destino, chain, motor, pode) = trava.withLock { (self.destino, self.chain, self.motor, montarEstado().podeContinuar) }
        guard pode, let destino, let chain else { return }
        guard let motor else {
            trava.withLock { problema = SendEngineError.unsupported(chain).errorDescription }
            return
        }
        do {
            let info = try await motor.destination(destino.address, chain: chain)
            trava.withLock {
                // A consulta vale so para o destino consultado, inteiro (o X-address da XRPL e o classico da mesma conta tem o
                // mesmo endereco e tags diferentes), e so com os passos do destino ainda feitos: o campo, os contatos, a rede e
                // uma leitura tardia do historico continuam ativos durante ela (rodada 19 dos 3 agentes, 06/11/2026).
                guard etapa == .destino, self.destino == destino, self.chain?.id == chain.id, montarEstado().podeContinuar else { return }
                problema = nil
                infoDoDestino = info
                etapa = precisaEtapaDaTag && destino.tag == nil ? .tag : .valor
            }
        } catch {
            trava.withLock {
                // O erro e da consulta deste destino: com outro na tela, nao aparece debaixo dele.
                guard etapa == .destino, self.destino == destino, self.chain?.id == chain.id else { return }
                problema = (error as? LocalizedError)?.errorDescription ?? Textos.t("Não foi possível consultar o destino agora.")
            }
        }
    }

    func definirTag(_ texto: String, pular: Bool) {
        trava.withLock {
            if pular {
                pulouTag = true
                tag = ""
                etapa = .valor
            } else if !texto.isEmpty {
                guardarTag(texto)
                if !tag.isEmpty, problemaDaTag == nil {
                    pulouTag = false
                    etapa = .valor
                }
            }
        }
    }

    /// So para tras, e nunca no meio da transmissao: avancar e com `continuar`, `definirTag` e
    /// `revisar`, que conferem cada passo (revisao de seguranca do Android de 26/10/2026).
    func voltar(para etapa: Etapa) {
        trava.withLock {
            let ordem: [Etapa] = [.destino, .tag, .valor, .revisao]
            guard self.etapa != .enviando, let alvo = ordem.firstIndex(of: etapa), alvo < 3 else { return }
            if let atual = ordem.firstIndex(of: self.etapa), alvo >= atual { return }
            self.etapa = etapa
            erro = nil
            // De volta ao destino, os passos dele recomecam (a rede do primeiro envio, os desafios, a consulta): a tela, que
            // monta de novo vazia, e o nucleo ficam iguais, e o Continuar confere tudo de novo.
            if etapa == .destino { validar() }
        }
    }

    // MARK: Valor e revisao

    func mudarValor(_ texto: String, tudo: Bool) {
        trava.withLock {
            textoDoValor = String(texto.prefix(48))
            self.tudo = tudo
        }
    }

    private var quantidade: BigUInt? {
        if tudo { return disponivel?.amount ?? saldoDaRede().map { $0.available(holding) } ?? holding.amount }
        return Fmt.lerQuantidade(textoDoValor, casas: holding.asset.decimals)
    }

    private func pedido(quantidade: BigUInt, tudo: Bool) -> SendRequest? {
        guard let chain, let conta, let destino else { return nil }
        let metadata = Sessao.shared.metadata
        return SendRequest(
            walletID: wallet.id, chain: chain, asset: holding.asset, account: conta, destination: destino.address,
            tag: tag.isEmpty ? nil : tag, amount: quantidade, sendAll: tudo, feeLevel: nivelDaTaxa,
            utxoUsage: wallet.utxoUsage[chain.id], knownAddresses: metadata.sentTo[chain.id] ?? [],
            nonceQueue: FilaDeNonces.fila(metadata, carteira: wallet.id, rede: chain, endereco: conta.address),
            // Redes UTXO: as moedas de um envio que a rede disse nao conhecer entram de novo (rodada dos 3 agentes de 19/11/2026).
            unsureCoins: UnsureSends.coinsToSpend(in: metadata.unsureSends ?? [], wallet: wallet.id, chainID: chain.id, address: conta.address)
        )
    }

    func carregarDisponivel() async {
        let (motor, sonda) = trava.withLock { (motor, pedido(quantidade: holding.amount, tudo: true)) }
        guard let motor, let sonda else { return }
        let lido = try? await motor.spendable(sonda)
        trava.withLock { disponivel = lido }
    }

    func revisar() async {
        // A leitura do historico ainda corre: a revisao espera por ela (o Continuar so esperou o prazo), para um parecido
        // achado tarde aparecer antes da assinatura, e nao depois (revisao de seguranca de 06/11/2026). Quase sempre ela ja
        // terminou enquanto o valor era digitado.
        if !trava.withLock({ historicoTerminado }) {
            let limite = (trava.withLock { historicoInicio } ?? .now) + Self.esperaDaRevisao
            trava.withLock { conferindoHistorico = true }
            avisar()
            while !trava.withLock({ historicoTerminado }), ContinuousClock.now < limite {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            trava.withLock { conferindoHistorico = false }
        }
        // A leitura tardia achou um parecido: de volta ao destino, com o desafio na tela.
        let voltou = trava.withLock { () -> Bool in
            guard etapa == .valor || etapa == .revisao,
                  !(historicoLido && liberado && infoDoDestino != nil && (!precisaConfirmarRede || redeConfirmada)) else { return false }
            voltarAoDestino()
            return true
        }
        if voltou {
            avisar()
            return
        }
        let preparo = trava.withLock { () -> (any SendEngine, Chain, DerivedAccount, BigUInt)? in
            erro = nil
            // O nucleo confere os passos, e nao so a tela: destino consultado (tag e ativacao), rede
            // confirmada no primeiro envio, endereco parecido conferido (revisao de seguranca do Android
            // de 26/10/2026).
            guard etapa == .valor || etapa == .revisao, infoDoDestino != nil, montarEstado().podeContinuar else { return nil }
            guard let motor, let chain, let conta, let quantidade, !quantidade.isZero else { return nil }
            return (motor, chain, conta, quantidade)
        }
        guard let (motor, chain, conta, _) = preparo else { return }
        await FilaDeNonces.podar(carteira: wallet.id, rede: chain, endereco: conta.address)
        await EnviosSemResposta.podar(carteira: wallet.id, rede: chain, endereco: conta.address)
        guard !emTransito(rede: chain, endereco: conta.address) else { return }
        // O pedido e o destino, o valor e o "tudo" de agora: o plano e comparado com eles, e nao com o que a tela tiver depois.
        guard let (pedido, destinoDoPedido, quantidadeDoPedido, tudoDoPedido) = trava.withLock({
            quantidade.flatMap { q in pedido(quantidade: q, tudo: tudo).map { ($0, destino, q, tudo) } }
        }) else { return }
        do {
            let novo = try await motor.plan(pedido)
            trava.withLock {
                // O plano demora: se a tela saiu do valor no meio (o voltar), ou o destino, a rede ou o valor mudaram, a revisao
                // e do pedido de antes, e para sem alarme (mexer na tela nao e adulteracao).
                guard etapa == .valor || etapa == .revisao, self.destino == destinoDoPedido, self.chain?.id == chain.id,
                      self.tudo == tudoDoPedido, tudoDoPedido || self.quantidade == quantidadeDoPedido else { return }
                guard confere(novo) else {
                    plano = nil
                    erro = Textos.t("O envio montado não confere com o destino digitado. Nada foi assinado.")
                    return
                }
                plano = novo
                revisaoMudou = false
                etapa = .revisao
            }
        } catch {
            // A fila a frente da rede nao e apagada aqui: a poda de antes do plano ja tira, no prazo dela, a transacao que a rede
            // descartou. Apagar tudo numa leitura so (dois nos atrasados logo depois de uma confirmacao) fazia o plano seguinte reusar
            // o nonce de uma transacao viva, como a troca pela rota privada (auditoria 8, 14/11/2026).
            trava.withLock { erro = (error as? LocalizedError)?.errorDescription ?? Textos.t("Não foi possível preparar o envio.") }
        }
    }

    /// Uma transacao anterior desta conta com o mesmo ativo (troca, envio, ponte) ainda nao confirmou:
    /// o plano leria o saldo de antes dela, e o segundo envio reverteria cobrando a taxa (auditoria de
    /// 03/11/2026, o `sellsInFlight` do iOS). Ler depois de `podar`. Mostra o motivo e devolve true.
    private func emTransito(rede: Chain, endereco: String) -> Bool {
        let ativo = trava.withLock { holding.asset }
        // Fora da EVM, o envio desta conta que ficou sem resposta da rede (`EnviosSemResposta`): outro por cima dele poderia
        // pagar duas vezes (pentest de 17/11/2026).
        guard let motivo = FilaDeNonces.motivoDoBloqueio(carteira: wallet.id, rede: rede, endereco: endereco, ativo: ativo)
            ?? EnviosSemResposta.motivoDoBloqueio(carteira: wallet.id, rede: rede, endereco: endereco) else { return false }
        trava.withLock { erro = motivo }
        return true
    }

    /// O plano confere com o que o dono digitou: mesma carteira, mesma rede, mesmo destino e mesma
    /// tag, e o ativo e o valor que saem. Chamar com a trava.
    private func confere(_ plano: SigningPlan) -> Bool {
        guard let chain, let destino else { return false }
        guard plano.review.kind == .send, plano.chain.id == chain.id, plano.walletID == wallet.id else { return false }
        guard Address.sameRecipient(plano.review.recipient, destino.address, chain: chain) else { return false }
        guard PlanIntentCheck.sameTag(plano.review.recipientTag, tag, chain: chain) else { return false }
        guard let pedido = quantidade else { return false }
        return (try? PlanIntentCheck.send(plano.review, asset: holding.asset, amount: tudo ? nil : pedido, ceiling: holding.amount, chain: chain)) != nil
    }

    private var memoComOutroID: AddressPoisoning.SameAccount? {
        guard let chain, chain.family == .stellar, let destino, !muxed, !tag.isEmpty else { return nil }
        return AddressPoisoning.sameAccountOtherID(destino.address, tag: tag, among: conhecidos(chain), tagged: contatosComTag(chain), chain: chain)
    }

    private func planoDTO(_ plano: SigningPlan) -> Estado.Plano {
        let placa = plano.review.lines.filter { $0.verbatim && $0.role != .assetReference }.map {
            Estado.LinhaDaPlaca(rotulo: $0.label, valor: $0.value, endereco: $0.value.count >= 26 && !$0.value.contains(" "))
        }
        let linhas = plano.review.lines.filter { !$0.verbatim }.map { Estado.Linha(rotulo: $0.label, valor: $0.value) }
            + [Estado.Linha(rotulo: Textos.t("De"), valor: wallet.name)]
        return Estado.Plano(titulo: plano.review.title, placa: placa, linhas: linhas, avisos: avisos(plano),
                            saida: (plano.review.outgoing?.amount ?? quantidade ?? BigUInt()).decimalString,
                            venceEm: (plano.createdAt.timeIntervalSince1970 + SigningPlan.lifetime) * 1000,
                            versao: versaoDaRevisao, mudou: revisaoMudou)
    }

    /// Monta o plano de novo com o mesmo pedido, sem sair da revisao (pedido do dono, 23/10/2026:
    /// enviar com os dados da rede vencidos voltava para a tela do valor). O mesmo conteudo troca so
    /// os dados da rede; outro valor ou outra taxa sobem a versao da revisao, e a tela pede o aceite e
    /// o deslizar de novo. Falhou: o erro fica na revisao, e nada se assina com o plano velho.
    @discardableResult
    func renovar() async -> SigningPlan? {
        let preparo = trava.withLock { () -> (any SendEngine, Chain, DerivedAccount, SigningPlan)? in
            guard etapa == .revisao, let motor, let chain, let conta, let plano else { return nil }
            return (motor, chain, conta, plano)
        }
        guard let (motor, chain, conta, antigo) = preparo else { return nil }
        await FilaDeNonces.podar(carteira: wallet.id, rede: chain, endereco: conta.address)
        guard let pedido = trava.withLock({ quantidade.flatMap { pedido(quantidade: $0, tudo: tudo) } }) else { return nil }
        do {
            let novo = try await motor.plan(pedido)
            return trava.withLock { () -> SigningPlan? in
                guard etapa == .revisao, plano?.id == antigo.id else { return nil }
                guard confere(novo) else {
                    erro = Textos.t("O envio montado não confere com o destino digitado. Nada foi assinado.")
                    return nil
                }
                if novo.review != antigo.review {
                    versaoDaRevisao += 1
                    revisaoMudou = true
                }
                plano = novo
                erro = nil
                return novo
            }
        } catch {
            // A fila a frente da rede nao e apagada aqui: a poda de antes do plano ja tira, no prazo dela, a transacao que a rede
            // descartou. Apagar tudo numa leitura so (dois nos atrasados logo depois de uma confirmacao) fazia o plano seguinte reusar
            // o nonce de uma transacao viva, como a troca pela rota privada (auditoria 8, 14/11/2026).
            trava.withLock { erro = (error as? LocalizedError)?.errorDescription ?? Textos.t("Não foi possível renovar os dados da rede. Tente de novo.") }
            return nil
        }
    }

    enum TipoDeTag { case tag, memo, comentario }

    private var tipoDeTag: TipoDeTag {
        switch chain?.destinationTag {
        case .stellarMemo?: return .memo
        case .tonComment?: return .comentario
        default: return .tag
        }
    }

    private func avisos(_ plano: SigningPlan) -> [String] {
        var saida: [String] = []
        // Outra chave ou contrato no controle desta conta (auditoria 8, 14/11/2026): o envio segue, porque tirar o saldo
        // dali e o que o dono precisa fazer, mas ele fica sabendo. Como no iOS.
        if let chain, let marca = Sessao.shared.metadata.wallets.first(where: { $0.id == wallet.id })?.foreignControl(on: chain) {
            saida.append(marca.message)
        }
        if let parecido { saida.append(preencher(Textos.t("Endereço parecido com %@. Confira o endereço inteiro."), Fmt.endereco(parecido, chain: chain))) }
        if outroID != nil || memoComOutroID != nil {
            saida.append(Textos.t("Mesma conta de um endereço que você já usou, com outro ID. Confira o ID com quem vai receber."))
        }
        if pulouTag {
            switch tipoDeTag {
            case .tag: saida.append(Textos.t("Envio sem tag de destino, por sua escolha."))
            case .memo: saida.append(Textos.t("Envio sem memo, por sua escolha."))
            case .comentario: saida.append(Textos.t("Envio sem comentário, por sua escolha."))
            }
        } else if let chain, chain.destinationTag != .none, tag.isEmpty, primeiroEnvio, !muxed {
            saida.append(textoDoAviso(.noDestinationTag))
        }
        for aviso in plano.review.warnings {
            if aviso == .firstSendToAddress, primeiroEnvio { continue }
            if case .unverifiedToken = aviso { continue }
            saida.append(textoDoAviso(aviso))
        }
        return saida
    }

    private func textoDoAviso(_ aviso: PlanReview.Warning) -> String { Self.textoDoAviso(aviso, chain: chain, tipo: tipoDeTag) }

    /// O texto de cada aviso do plano, igual em todas as telas que assinam (PlanWarningText do iOS).
    static func textoDoAviso(_ aviso: PlanReview.Warning, chain: Chain?, tipo tipoDeTag: TipoDeTag) -> String {
        switch aviso {
        case .firstSendToAddress: return Textos.t("Primeira vez que você envia para este endereço.")
        case .lookalikeAddress(let conhecido):
            // Nome da NEAR: o aviso e o do nome (revisao dos 3 agentes, 09/11/2026).
            if let chain, AddressPoisoning.wholeNEARName(conhecido, chain: chain) != nil { return preencher(Textos.t("Nome parecido com %@."), conhecido) }
            return preencher(Textos.t("Endereço parecido com %@."), Fmt.endereco(conhecido, chain: chain))
        case .noDestinationTag:
            switch tipoDeTag {
            case .tag: return Textos.t("Sem tag de destino. Se o destino for uma exchange, confira na tela de depósito se ela pede: sem isso o valor não chega na sua conta de lá.")
            case .memo: return Textos.t("Sem memo. Se o destino for uma exchange, confira na tela de depósito se ela pede: sem isso o valor não chega na sua conta de lá.")
            case .comentario: return Textos.t("Sem comentário. Se o destino for uma exchange, confira na tela de depósito se ela pede: sem isso o valor não chega na sua conta de lá.")
            }
        case .destinationIsContract: return Textos.t("O destino é um contrato, não uma carteira comum.")
        case .highFee(let percentual): return preencher(Textos.t("A taxa é %@%% do valor."), Fmt.agrupado(percentual, casas: 1))
        case .activatesAccount(let minimo): return preencher(Textos.t("Este envio ativa a conta de destino (mínimo %@)."), minimo)
        case .unverifiedToken(let simbolo): return preencher(Textos.t("%@ não está na lista de tokens verificados."), simbolo)
        case .unlimitedApproval: return Textos.t("Autorização sem limite.")
        case .highPriceImpact(let percentual): return preencher(Textos.t("Impacto no preço de %@%%."), Fmt.agrupado(percentual, casas: 1))
        case .binancePeg(let simbolo):
            let original = simbolo == "USDC" ? Textos.t("USDC da Circle") : simbolo == "USDT" ? Textos.t("USDT da Tether") : Textos.t("ETH da rede Ethereum")
            return preencher(Textos.t("Na BNB, o %@ é o da Binance (Binance-Peg). Ele vale enquanto a Binance mantiver o lastro e o resgate: não é o %@."), simbolo, original)
        case .publicMempool:
            return Textos.t("Nesta rede a troca passa pela fila pública, sem proteção contra robôs: eles podem comprar antes e vender depois. O mínimo garantido continua valendo, mas o que ficar entre a estimativa e ele pode não chegar.")
        case .uncomparedPrice:
            return Textos.t("Não há preço de referência do mercado: o preço desta troca não foi comparado com o mercado.")
        }
    }

    // MARK: Assinar e transmitir

    /// A conferencia do destino vale ate a assinatura: se a validacao rodou de novo, o desafio volta
    /// para a tela do destino e nada e assinado. O plano confere de novo, e plano vencido volta.
    /// Carteira com passphrase: ela chega antes da biometria ou do PIN e o assinador confere.
    /// `versao` e a da revisao que o dono aceitou ao deslizar. A renovacao automatica pode trocar a taxa
    /// ou o valor enquanto a tela pede a passphrase ou o PIN: com outra versao, nada e assinado e a
    /// revisao mostra o plano novo (revisao de seguranca do Android 1008, 28/10/2026).
    func assinar(_ credencial: Credencial, passphrase: SecureBytes?, folga: Int?, versao: Int?) async throws {
        defer { passphrase?.wipe() }
        let preparo = trava.withLock { () -> (SigningPlan, any SendEngine, Chain)? in
            erro = nil
            guard let plano, let motor, let chain, etapa == .revisao else { return nil }
            guard historicoLido, liberado, infoDoDestino != nil, !precisaConfirmarRede || redeConfirmada else {
                voltarAoDestino()
                return nil
            }
            guard confere(plano) else {
                erro = Textos.t("O envio montado não confere com o destino digitado. Nada foi assinado.")
                return nil
            }
            // A marca que chegou depois do destino: nada e assinado para a conta que outra chave controla (15/11/2026), como no iOS.
            if let destino, let dona = Sessao.shared.metadata.wallets.donaMarcada(de: destino.address, on: chain) {
                erro = preencher(Textos.t("Este endereço é da carteira %@, e lá a rede mostrou outra chave no controle. O que for enviado para ele, quem controla essa chave leva."), dona.name)
                return nil
            }
            if let prazo = prazoDoLink, prazo.endereco == textoDoDestino, PaymentLink.expired(prazo.expira) {
                // O pedido que venceu entre a leitura e a assinatura (rodada 3 da auditoria 8).
                erro = Textos.t("Este pedido de pagamento venceu. Peça um novo a quem cobrou.")
                return nil
            }
            guard versao == versaoDaRevisao else {
                // Com a renovacao que mudou, a revisao ja mostra essa faixa e pede o aceite de novo.
                if !revisaoMudou { erro = Textos.t("Os dados da rede foram renovados e o valor ou a taxa mudaram. Confira e confirme de novo.") }
                return nil
            }
            return (plano, motor, chain)
        }
        guard var (plano, motor, chain) = preparo else {
            credencial.zerar()
            return
        }
        // Dado vencido nao se assina: renova aqui mesmo, na revisao. Igual ao que o dono viu, segue
        // com o plano novo; diferente (valor ou taxa), a tela mostra e pede para confirmar de novo.
        if plano.isExpired() {
            guard let novo = await renovar(), novo.review == plano.review else {
                credencial.zerar()
                return
            }
            plano = novo
        }
        // Ate a assinatura: uma troca ou outro envio deste ativo pode ter saido depois da revisao.
        if let endereco = trava.withLock({ conta?.address }), emTransito(rede: chain, endereco: endereco) {
            credencial.zerar()
            return
        }
        let carteira = Sessao.shared.metadata.wallets.first { $0.id == plano.walletID }
        // O autoteste da assinatura antes da porta da passphrase e da RK: com um defeito do aparelho, nada conta nem abre
        // (o Signer confere de novo antes de abrir o cofre; revisao da decima terceira passada).
        guard SigningSelfTest.passed(for: plano) else { credencial.zerar(); throw SigningSelfTest.Failure() }
        // Carteira com passphrase: ela nunca fica salva, e sai zerada logo depois de assinar (pedido do dono,
        // 05/11/2026; ver `PortaDaPassphrase.assinar`).
        let assinado = try PortaDaPassphrase.assinar(plano, carteira: carteira, digitada: passphrase, folga: folga, credencial: credencial)
        // Travou entre assinar e transmitir: nada sai. Travado, o que o envio anota (nonce, troco)
        // nao gravaria, e o proximo envio repetiria o nonce (caca de bugs de 25/10/2026). Destravado,
        // o dono envia de novo.
        guard Sessao.shared.fase == .unlocked else { throw Sessao.Falha.travada }
        // De novo depois do PIN e da renovacao: uma leitura do historico chegada nesse meio tempo pode ter achado um parecido.
        // Os bytes assinados ficam aqui, sem sair (revisao de seguranca de 06/11/2026).
        let segue = trava.withLock { () -> Bool in
            guard etapa == .revisao else { return false }
            guard historicoLido, liberado, infoDoDestino != nil, !precisaConfirmarRede || redeConfirmada, confere(plano) else {
                voltarAoDestino()
                return false
            }
            etapa = .enviando
            return true
        }
        avisar()
        guard segue else { return }
        await transmitir(assinado, plano: plano, motor: motor, chain: chain)
    }

    /// Transmite os bytes assinados. Erro aqui nao quer dizer que nada saiu: a tela diz isso,
    /// acompanha o id que ja se conhece e so oferece transmitir de novo os mesmos bytes.
    private func transmitir(_ assinado: [SignedTransaction], plano: SigningPlan, motor: any SendEngine, chain: Chain) async {
        // Fora da EVM, o envio fica anotado antes de os bytes sairem (`UnsureSend`): se a resposta nao vier, ou o app morrer
        // no meio, a Atividade segue mostrando a linha e a conta nao monta outro envio por cima dele. Antes, travar ou fechar
        // a tela do envio sem resposta apagava o unico rastro, e o dono podia pagar duas vezes (pentest de 17/11/2026).
        // Antes de qualquer outra anotacao, e sem o registro gravado nada sai (o app travou no meio, ou a gravacao falhou):
        // os bytes assinados ficam aqui, como no travar entre assinar e transmitir.
        let semResposta = trava.withLock { () -> UnsureSend? in
            guard UnsureSends.applies(to: chain), let endereco = conta?.address, let hash = assinado.last?.id else { return nil }
            return UnsureSend(wallet: wallet.id, chainID: chain.id, address: endereco, hash: hash, sentAt: Date(), asset: holding.asset,
                              amount: plano.review.outgoing?.amount ?? quantidade ?? BigUInt(), recipient: destino?.address,
                              context: motor.unsureContext(for: plano))
        }
        if let semResposta, !EnviosSemResposta.anotar(semResposta) {
            trava.withLock {
                erro = Textos.t("Não foi possível preparar o envio.")
                etapa = assinadoIncerto == nil ? .revisao : .incerto
            }
            return
        }
        if let endereco = conta?.address {
            FilaDeNonces.anotar(carteira: wallet.id, rede: chain, endereco: endereco, plano: plano, assinado: assinado,
                                 vende: trava.withLock { holding.asset.id })
        }
        let usoAtual = Sessao.shared.metadata.wallets.first { $0.id == wallet.id }?.utxoUsage[chain.id]
        if let uso = motor.usage(after: plano, current: usoAtual) {
            let id = wallet.id
            Sessao.shared.alterarOuDepois { metadata in
                guard let indice = metadata.wallets.firstIndex(where: { $0.id == id }) else { return }
                metadata.wallets[indice].utxoUsage[chain.id] = uso
            }
        }
        do {
            let id = try await motor.broadcast(assinado, chain: chain)
            trava.withLock {
                assinadoIncerto = nil
                detalheIncerto = nil
            }
            if let semResposta { EnviosSemResposta.tirar(hash: semResposta.hash, carteira: wallet.id, rede: chain.id) }
            await concluir(id: id, motor: motor, chain: chain)
        } catch {
            trava.withLock {
                idDoResultado = assinado.last?.id
                assinadoIncerto = assinado
                detalheIncerto = (error as? LocalizedError)?.errorDescription
                etapa = .incerto
            }
            // A linha ja aparece em "Pendentes": a tela do envio sem resposta oferece "Fechar e acompanhar na Atividade".
            if let semResposta { Atividade.shared.anotarEnviado(semResposta.entry(unanswered: EnviosSemResposta.nota), carteira: wallet.id) }
        }
    }

    private func concluir(id: String, motor: any SendEngine, chain: Chain) async {
        let (endereco, valor, ativo) = trava.withLock { () -> (String?, BigUInt, Asset) in
            idDoResultado = id
            etapa = .enviado
            return (destino?.address, plano?.review.outgoing?.amount ?? quantidade ?? BigUInt(), holding.asset)
        }
        // Saiu: o registro de envio sem resposta, se havia (o que confirmou depois, com a tela aberta), sai.
        EnviosSemResposta.tirar(hash: id, carteira: wallet.id, rede: chain.id)
        // O envio aparece ja em "Pendentes" na Atividade: a leitura da rede pode levar minutos (pedido do dono, 08/11/2026).
        Atividade.shared.anotarEnviado(ActivityEntry(id: "enviado-\(chain.id)-\(id)", chainID: chain.id, direction: .sent, asset: ativo,
                                                     amount: valor, counterparty: endereco, date: Date(), status: .pending(nil), fee: nil,
                                                     hash: id, suspicious: false), carteira: wallet.id)
        // Saiu: o registro vale mesmo que o app tenha travado durante a transmissao.
        Sessao.shared.alterarOuDepois { metadata in
            if let endereco {
                var enviados = metadata.sentTo[chain.id] ?? []
                if !enviados.contains(endereco) { enviados.append(endereco) }
                metadata.sentTo[chain.id] = enviados
            }
            metadata.settings.completedSends = (metadata.settings.completedSends ?? 0) + 1
        }
    }

    func retransmitir() async {
        let preparo = trava.withLock { () -> ([SignedTransaction], SigningPlan, any SendEngine, Chain)? in
            guard let assinadoIncerto, let plano, let motor, let chain else { return nil }
            etapa = .enviando
            return (assinadoIncerto, plano, motor, chain)
        }
        guard let (assinado, plano, motor, chain) = preparo else { return }
        guard Sessao.shared.fase == .unlocked else {
            trava.withLock { etapa = .incerto }
            return
        }
        avisar()
        await transmitir(assinado, plano: plano, motor: motor, chain: chain)
    }

    /// Pergunta a rede pelo id ja conhecido: no envio incerto, se a rede conhece a transacao, o
    /// envio saiu; no enviado, a confirmacao.
    func acompanhar() async {
        let (id, motor, chain, etapaAtual) = trava.withLock { (idDoResultado, motor, chain, etapa) }
        guard let id, let motor, let chain else { return }
        let agora = await motor.status(id, chain: chain)
        if etapaAtual == .incerto {
            if case .confirmed = agora {
                trava.withLock { assinadoIncerto = nil }
                await concluir(id: id, motor: motor, chain: chain)
                trava.withLock { situacao = agora }
                // Saiu de "incerto" ja confirmado: a linha da Atividade e o saldo tambem (revisao, 08/11/2026).
                Task { await self.assentar(agora, id: id, chain: chain) }
            }
        } else {
            let antes = trava.withLock { () -> TransferStatus in
                defer { situacao = agora }
                return situacao
            }
            // Sem segurar a resposta: o "Confirmado" chega a tela na hora, e a releitura segue por fora.
            if case .pending = antes, agora != .pending { Task { await self.assentar(agora, id: id, chain: chain) } }
        }
    }

    /// A rede respondeu sobre o envio: a linha da Atividade muda de situacao, e o saldo e o historico desta rede leem de novo,
    /// sem esperar o prazo de cada um (o settled do iOS, pedido do dono de 08/11/2026).
    private func assentar(_ agora: TransferStatus, id: String, chain: Chain) async {
        if case .failed(let motivo) = agora {
            Atividade.shared.assentarEnviado(hash: id, carteira: wallet.id, situacao: .failed(motivo))
        } else {
            Atividade.shared.assentarEnviado(hash: id, carteira: wallet.id, situacao: .confirmed)
        }
        let carteira = wallet.id
        Sessao.shared.alterarOuDepois { metadata in metadata.activityFetched?[carteira]?[chain.id] = nil }
        // As leituras sao da carteira escolhida: travado, ou com outra carteira na tela, nada a reler (o iOS faz igual).
        func aindaNela() -> Bool { Sessao.shared.fase == .unlocked && Sessao.shared.metadata.selectedWalletID == carteira }
        guard aindaNela() else { return }
        await Saldos.shared.atualizarRede(chain)
        guard aindaNela() else { return }
        await Atividade.shared.atualizar(forcar: false)
    }

    /// "0,5 ETH para 0x12ab…34cd": o valor que a transacao move, do plano. Chamar com a trava.
    private func linhaDoEnvio() -> String {
        let valor = plano?.review.outgoing?.amount ?? quantidade ?? BigUInt()
        let texto = Fmt.cripto(valor, casas: holding.asset.decimals, simbolo: holding.asset.symbol, cheio: true)
        guard let endereco = destino?.address else { return texto }
        return preencher(Textos.t("%@ para %@"), texto, Fmt.endereco(endereco, chain: chain))
    }
}

/// O preenchimento dos textos montados aqui, como o do iOS: "%@" na ordem, "%1$@" na posicao
/// (as traducoes podem trocar a ordem) e "%%" vira "%".
func preencher(_ modelo: String, _ valores: String...) -> String {
    var saida = ""
    var proximo = 0
    var resto = Substring(modelo)
    while let marca = resto.firstIndex(of: "%") {
        saida += resto[..<marca]
        var depois = resto[resto.index(after: marca)...]
        if depois.first == "%" {
            saida += "%"
            resto = depois.dropFirst()
            continue
        }
        let digitos = depois.prefix { $0.isNumber }
        var posicao: Int?
        if !digitos.isEmpty, depois.dropFirst(digitos.count).first == "$" {
            posicao = Int(digitos).map { $0 - 1 }
            depois = depois.dropFirst(digitos.count + 1)
        }
        // "%@" e, para os numeros que o catalogo do iOS guarda como "%lld", tambem "%lld".
        let marcador = depois.hasPrefix("lld") ? 3 : depois.first == "@" ? 1 : 0
        guard marcador > 0 else {
            saida += "%"
            resto = resto[resto.index(after: marca)...]
            continue
        }
        let indice = posicao ?? proximo
        if posicao == nil { proximo += 1 }
        saida += indice >= 0 && indice < valores.count ? valores[indice] : ""
        resto = depois.dropFirst(marcador)
    }
    return saida + resto
}

/// A formatacao que o nucleo do Android usa nos textos que ele mesmo monta: os separadores da
/// regiao (NumberStyle), a mesma regra do `Fmt` do iOS.
enum Fmt {
    /// `aparar`: sem os zeros do fim ("1,5" em vez de "1,500000").
    static func agrupado(_ valor: Double, casas: Int, aparar: Bool = false) -> String {
        let estilo = NumberStyle.current
        // Pelo texto, nunca por Int: um token com quatrilhoes de unidades (o BNB Frog Inu) passava
        // do Int e fechava o app na cotacao.
        guard valor.isFinite else { return "0" }
        let texto = String(format: "%.\(max(casas, 0))f", abs(valor))
        let partes = texto.split(separator: ".", omittingEmptySubsequences: false)
        var fracao = partes.count > 1 ? String(partes[1]) : ""
        if aparar { while fracao.hasSuffix("0") { fracao.removeLast() } }
        return estilo.decimal(estilo.group(String(partes[0])), fracao)
    }

    /// O inteiro da rede como o dono digitaria: sem separador de milhar, com todas as casas que
    /// contam ("1234,5").
    static func decimalSimples(_ valor: BigUInt, casas: Int) -> String {
        let digitos = valor.decimalString
        guard casas > 0 else { return digitos }
        let cheio = digitos.count <= casas ? String(repeating: "0", count: casas - digitos.count + 1) + digitos : digitos
        let inteiro = String(cheio.dropLast(casas))
        var fracao = String(cheio.suffix(casas))
        while fracao.hasSuffix("0") { fracao.removeLast() }
        return fracao.isEmpty ? inteiro : inteiro + NumberStyle.current.decimal + fracao
    }

    /// Valor de token a partir do inteiro da rede, truncado para baixo, com ate 8 casas (`cheio`)
    /// ou 6 algarismos significativos.
    static func cripto(_ valor: BigUInt, casas: Int, simbolo: String, cheio: Bool = false) -> String {
        let digitos = valor.decimalString
        let (inteiro, fracao): (String, String)
        if casas <= 0 {
            (inteiro, fracao) = (digitos, "")
        } else if digitos.count <= casas {
            (inteiro, fracao) = ("0", String(repeating: "0", count: casas - digitos.count) + digitos)
        } else {
            (inteiro, fracao) = (String(digitos.dropLast(casas)), String(digitos.suffix(casas)))
        }
        let mostradas: Int
        if cheio {
            mostradas = min(casas, 8)
        } else if inteiro != "0" {
            mostradas = inteiro.count >= 6 ? 0 : min(6 - inteiro.count, 8)
        } else {
            mostradas = min(fracao.prefix { $0 == "0" }.count + 6, 8)
        }
        var parte = String(fracao.prefix(mostradas))
        while parte.hasSuffix("0") { parte.removeLast() }
        let estilo = NumberStyle.current
        return estilo.decimal(estilo.group(inteiro), parte) + " " + simbolo
    }

    /// Le o valor digitado ("1,5" ou "1.5") para o inteiro da rede, sem ponto flutuante. Casas
    /// demais sao recusadas, nao arredondadas.
    static func lerQuantidade(_ texto: String, casas: Int) -> BigUInt? {
        let cru = texto.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
        if NumberStyle.current.decimal == ".", cru.contains(",") { return nil }
        let partes = cru.replacingOccurrences(of: ".", with: ",").split(separator: ",", omittingEmptySubsequences: false)
        guard !cru.isEmpty, partes.count <= 2 else { return nil }
        let inteiro = partes[0].isEmpty ? "0" : String(partes[0])
        let fracao = partes.count == 2 ? String(partes[1]) : ""
        guard fracao.count <= casas, inteiro.allSatisfy(\.isNumber), fracao.allSatisfy(\.isNumber) else { return nil }
        let digitos = (inteiro + fracao + String(repeating: "0", count: casas - fracao.count)).drop { $0 == "0" }
        return BigUInt(decimal: digitos.isEmpty ? "0" : String(digitos))
    }

    /// "0x71C7A3…976F": o prefixo que a rede impoe inteiro, e 6 mais 4 do corpo.
    static func endereco(_ texto: String, chain: Chain?, inicio: Int = 6, fim: Int = 4) -> String {
        guard let chain else {
            guard texto.count > inicio + fim + 1 else { return texto }
            return "\(texto.prefix(inicio))…\(texto.suffix(fim))"
        }
        let mostrado = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let corpo = AddressPoisoning.bodySegment(mostrado, chain: chain)
        guard corpo.length > inicio + fim + 1, mostrado.count - corpo.start >= AddressPoisoning.minimumLength else { return mostrado }
        let caracteres = Array(mostrado)
        let final = corpo.start + corpo.length
        return String(caracteres[..<(corpo.start + inicio)]) + "…" + String(caracteres[(final - fim)...])
    }
}

/// Uma transacao EVM transmitida deste aparelho e ainda sem confirmacao.
struct PendingEVMTransaction: Codable, Equatable {
    let nonce: UInt64
    let hash: String
    let sentAt: Date
    /// O ativo que esta transacao tira da conta (o id do `Asset`), na troca, no envio e na ponte: a
    /// proxima transacao do mesmo ativo espera ela confirmar, como no iOS (auditoria de 03/11/2026). nil nas antigas.
    var sells: String? = nil
    /// Saiu pela rota privada (protecao de MEV na Ethereum): os provedores so a veem num bloco, e a poda
    /// espera mais antes de dar por perdida (terceira passada de 03/11/2026). nil nas antigas e na publica.
    var privateRoute: Bool? = nil
    /// A rede conhecia a transacao na ultima poda. nil ou false: ainda nao vista, e a conta nao monta outra
    /// por cima, como no iOS (quarta passada da auditoria de 03/11/2026).
    var seen: Bool? = nil
    /// Dois operadores ja a viram numa poda, e isso nao volta atras: a que ja foi vista so sai por um bloco, por
    /// dois sem ela depois de perguntar a todos ou depois de 3 horas (sexta passada da auditoria de 03/11/2026).
    var everSeen: Bool? = nil
    /// A ultima poda em que uma de baixo vista a segurou (`NonceQueuePruning.Result.held`, decima passada).
    var heldAt: Date? = nil
    /// A primeira poda em que, segurada antes, deixou de estar (`NonceQueuePruning.Result.released`): o prazo recomeca
    /// dali, e nao da ultima vez em que foi segurada (decima primeira passada).
    var releasedAt: Date? = nil
}

/// A fila local de nonces EVM, por carteira, rede e conta (o `NonceQueue` do iOS).
enum FilaDeNonces {
    static func chave(carteira: UUID, rede: Chain, endereco: String) -> String {
        "\(carteira.uuidString)|\(rede.id)|\(endereco.lowercased())"
    }

    static func fila(_ metadata: Metadata, carteira: UUID, rede: Chain, endereco: String) -> PendingNonceQueue? {
        guard rede.family == .evm, let entradas = metadata.pendingEVM?[chave(carteira: carteira, rede: rede, endereco: endereco)], !entradas.isEmpty
        else { return nil }
        return PendingNonceQueue.trailingRun(entradas.map { ($0.nonce, $0.hash) })
    }

    static func anotar(carteira: UUID, rede: Chain, endereco: String, plano: SigningPlan, assinado: [SignedTransaction], vende: String? = nil,
                       privada: Bool = false) {
        guard rede.family == .evm, plano.transactions.count == assinado.count else { return }
        let agora = Date()
        let novas = zip(plano.transactions, assinado).compactMap { transacao, assinatura -> PendingEVMTransaction? in
            guard let evm = transacao as? EVMTransaction else { return nil }
            return PendingEVMTransaction(nonce: evm.nonce, hash: assinatura.id, sentAt: agora, sells: vende, privateRoute: privada ? true : nil)
        }
        guard !novas.isEmpty else { return }
        let chave = chave(carteira: carteira, rede: rede, endereco: endereco)
        Sessao.shared.alterarOuDepois { metadata in
            var todas = metadata.pendingEVM ?? [:]
            let velhas = todas[chave] ?? []
            // "Enviar de novo" dos mesmos bytes: a que a rede ja viu continua vista, como no iOS (setima passada).
            let herdadas = novas.map { nova -> PendingEVMTransaction in
                var nova = nova
                if velhas.contains(where: { $0.hash == nova.hash && ($0.everSeen == true || $0.seen == true) }) { nova.everSeen = true }
                return nova
            }
            let mantidas = velhas.filter { velha in !herdadas.contains { $0.nonce == velha.nonce } }
            todas[chave] = mantidas + herdadas
            metadata.pendingEVM = todas
        }
    }

    static func podar(carteira: UUID, rede: Chain, endereco: String) async {
        let chave = chave(carteira: carteira, rede: rede, endereco: endereco)
        guard rede.family == .evm, let entradas = Sessao.shared.metadata.pendingEVM?[chave], !entradas.isEmpty,
              let motor = SendEngines.engine(for: rede) else { return }
        // A mesma regra do iOS (`NonceQueuePruning`): sai a confirmada ou falha, a que a rede nao conhece depois
        // do prazo de propagacao, com tudo acima (salvo a de nonce ja minerado, que sai sozinha), e fica marcada a que
        // a rede ja viu (terceira e quarta passadas
        // de 03/11/2026). Uma leitura por poda do nonce minerado: o que esta abaixo dele sai sem depender do recibo
        // antigo (bug de 14/11/2026).
        let minerado = await motor.minedNonce(chain: rede, from: endereco)
        let resultado = await NonceQueuePruning.pruned(
            entradas.map {
                NonceQueuePruning.Entry(nonce: $0.nonce, hash: $0.hash, sentAt: $0.sentAt, privateRoute: $0.privateRoute == true,
                                        wasSeen: $0.everSeen == true || $0.seen == true, heldAt: $0.heldAt, releasedAt: $0.releasedAt)
            },
            minedNonce: minerado,
            settled: { entrada in
                if case .pending = await motor.status(entrada.hash, chain: rede) { return false }
                return true
            },
            known: { await motor.sighting($0.hash, chain: rede, from: endereco, nonce: $0.nonce) })
        // So muda o que foi conferido aqui, pelo hash e pela hora do envio: um envio anotado durante as leituras
        // fica, e um "Enviar de novo" dos mesmos bytes tambem. Travado, nada e gravado; a proxima poda refaz
        // (caca de bugs de 25/10/2026).
        let conferidas = Set(entradas.map { "\($0.hash)|\($0.sentAt.timeIntervalSince1970)" })
        let agoraDaPoda = Date()
        try? Sessao.shared.alterar { metadata in
            guard var atuais = metadata.pendingEVM?[chave] else { return }
            atuais.removeAll { resultado.gone.contains($0.hash) && conferidas.contains("\($0.hash)|\($0.sentAt.timeIntervalSince1970)") }
            for indice in atuais.indices where conferidas.contains("\(atuais[indice].hash)|\(atuais[indice].sentAt.timeIntervalSince1970)") {
                // A vista de antes desta versao (so `seen`) tambem fica marcada, antes de `seen` mudar (setima passada).
                let vista = resultado.seen.contains(atuais[indice].hash)
                if vista || atuais[indice].seen == true { atuais[indice].everSeen = true }
                atuais[indice].seen = vista
                if resultado.held.contains(atuais[indice].hash) {
                    atuais[indice].heldAt = agoraDaPoda
                    atuais[indice].releasedAt = nil
                }
                if resultado.released.contains(atuais[indice].hash) { atuais[indice].releasedAt = agoraDaPoda }
            }
            metadata.pendingEVM?[chave] = atuais.isEmpty ? nil : atuais
        }
    }

    /// Uma transacao deste aparelho nesta conta que a rede ainda nao viu (ler depois de `podar`): a proxima
    /// nao monta, de nenhum ativo, em vez de pular o nonce dela ou reusar o de uma transacao viva (o `unseen`
    /// do iOS, quarta passada da auditoria de 03/11/2026).
    static func naoVista(carteira: UUID, rede: Chain, endereco: String) -> Bool {
        guard rede.family == .evm else { return false }
        return Sessao.shared.metadata.pendingEVM?[chave(carteira: carteira, rede: rede, endereco: endereco)]?.contains { $0.seen != true } == true
    }

    /// O motivo para a tela quando a conta nao pode montar outra transacao agora, ou nil (o `blockedReason` do iOS).
    /// `usaNonce`: o plano tem transacao na cadeia; o que so assina nao espera a transacao nao vista (como no iOS).
    static func motivoDoBloqueio(carteira: UUID, rede: Chain, endereco: String, ativo: Asset?, usaNonce: Bool = true) -> String? {
        if usaNonce, naoVista(carteira: carteira, rede: rede, endereco: endereco) {
            return Textos.t("Uma transação anterior desta conta ainda não apareceu na rede, e a próxima não pode passar na frente dela. Tente de novo quando ela aparecer ou confirmar. Se ela tiver sido descartada, o app libera em até 30 minutos, ou em até 3 horas se a rede já tinha visto a transação. Se uma transação anterior a ela seguir esperando na rede, só libera quando essa confirmar.")
        }
        if let ativo, vendeEmTransito(carteira: carteira, rede: rede, endereco: endereco, ativo: ativo.id) {
            return preencher(Textos.t("Uma transação anterior com %@ ainda não confirmou na rede. Tente de novo quando ela confirmar. Se ela tiver sido descartada, o app libera em até 30 minutos, ou em até 3 horas se a rede já tinha visto a transação. Se ela seguir esperando na rede, só libera quando ela confirmar."), ativo.symbol)
        }
        return nil
    }

    /// Uma transacao deste aparelho que tira `ativo` desta conta ainda nao confirmou (ler depois de
    /// `podar`): a nova do mesmo ativo reverteria na rede, cobrando a taxa (o `sellsInFlight` do iOS). Na
    /// moeda da rede, qualquer uma conta: toda transacao paga o gas nela (terceira passada de 03/11/2026).
    static func vendeEmTransito(carteira: UUID, rede: Chain, endereco: String, ativo: String) -> Bool {
        guard rede.family == .evm, let entradas = Sessao.shared.metadata.pendingEVM?[chave(carteira: carteira, rede: rede, endereco: endereco)]
        else { return false }
        return ativo == Asset.native(rede).id ? !entradas.isEmpty : entradas.contains { $0.sells == ativo }
    }
}

/// Os envios fora da EVM transmitidos sem resposta certa da rede (`UnsureSend`; a regra, no Kit, e a mesma do iOS, onde
/// isto e o `UnsureSendLedger`). Gravado antes de os bytes sairem, tirado quando a transmissao responde. Enquanto fica: a
/// Atividade mostra a linha em "Pendentes" e, ate a rede conhecer a transacao, a conta nao monta outro envio nesta rede.
enum EnviosSemResposta {
    /// A nota da linha na Atividade.
    static var nota: String { Textos.t("Sem resposta da rede") }

    private struct NadaATirar: Error {}

    /// Grava o registro antes de os bytes sairem. false: nao gravou (o app travou no meio, a gravacao falhou, a carteira
    /// saiu) e nao ha um registro deste mesmo envio de antes; quem chama nao transmite.
    static func anotar(_ envio: UnsureSend) -> Bool {
        let gravou = (try? Sessao.shared.alterar { metadata -> Bool in
            // A carteira removida no meio nao volta a ter rastro.
            guard metadata.wallets.contains(where: { $0.id == envio.wallet }) else { return false }
            metadata.unsureSends = UnsureSends.recording(envio, in: metadata.unsureSends ?? [])
            return true
        }) ?? false
        if gravou { return true }
        // Transmitir de novo os mesmos bytes: o registro de antes segue valendo.
        return Sessao.shared.metadata.unsureSends?.contains { $0.wallet == envio.wallet && $0.chainID == envio.chainID && $0.hash == envio.hash } == true
    }

    /// A transmissao respondeu, ou a rede confirmou com a tela aberta: o registro sai.
    static func tirar(hash: String, carteira: UUID, rede: String) {
        let saida: (inout Metadata) -> Bool = { metadata in
            guard let lista = metadata.unsureSends else { return false }
            let nova = UnsureSends.removing(hash: hash, wallet: carteira, chainID: rede, from: lista)
            guard nova.count != lista.count else { return false }
            metadata.unsureSends = nova.isEmpty ? nil : nova
            return true
        }
        do {
            // Destravado e sem registro (todo envio que respondeu certo, e todo envio da EVM, passa por aqui): nada a gravar. A
            // conferencia e a gravacao na mesma trava da sessao.
            try Sessao.shared.alterar { metadata in if !saida(&metadata) { throw NadaATirar() } }
        } catch is NadaATirar {
        } catch {
            // Travado no meio (os metadados nao estao na memoria para saber) ou a gravacao falhou: fica para o destravar.
            Sessao.shared.alterarOuDepois { metadata in _ = saida(&metadata) }
        }
    }

    /// As linhas de "Pendentes" da carteira, para a Atividade.
    static func linhas(_ metadata: Metadata, carteira: UUID) -> [ActivityEntry] {
        (metadata.unsureSends ?? []).filter { $0.wallet == carteira && UnsureSends.shown($0) }.map { $0.entry(unanswered: nota) }
    }

    /// O motivo para a tela quando a conta tem um envio que a rede ainda nao disse se saiu, ou nil (ler depois de `podar`).
    static func motivoDoBloqueio(carteira: UUID, rede: Chain, endereco: String) -> String? {
        guard !UnsureSends.pending(in: Sessao.shared.metadata.unsureSends ?? [], wallet: carteira, chainID: rede.id, address: endereco).isEmpty
        else { return nil }
        return Textos.t("Um envio anterior desta conta ficou sem resposta da rede, e ainda não dá para saber se ele saiu. Para você não pagar duas vezes, o próximo envio espera a rede dizer o que houve com ele. Se a rede responder que não conhece esse envio, o app libera 30 minutos depois. Ele aparece em Pendentes, na Atividade.")
    }

    /// Pergunta a rede por cada envio sem resposta da carteira (ou so os de uma conta) e aplica a regra
    /// (`UnsureSends.step`): o confirmado vira envio feito; o que falhou com prova sai; o que a rede conhece deixa de
    /// segurar a conta; o que ela diz nao conhecer sai 30 minutos depois da primeira resposta dessas; sem resposta, nada
    /// muda. Travado no meio, nada e gravado, e a proxima poda refaz.
    static func podar(carteira: UUID, rede: Chain? = nil, endereco: String? = nil) async {
        let registros = (Sessao.shared.metadata.unsureSends ?? []).filter { registro in
            registro.wallet == carteira && rede.map { $0.id == registro.chainID } != false && endereco.map { $0 == registro.address } != false
        }
        for registro in registros {
            // Rede que esta versao nao conhece mais, ou sem motor: nao ha a quem perguntar, e so o tempo decide.
            var resposta = SendLookup.unknowable
            if let chain = Chain.find(registro.chainID), let motor = SendEngines.engine(for: chain) {
                resposta = await motor.lookup(registro, chain: chain)
            }
            let passo = UnsureSends.step(registro, lookup: resposta)
            if case .keep(let igual) = passo, igual == registro { continue }
            let gravou = (try? Sessao.shared.alterar { metadata -> Bool in
                guard var lista = metadata.unsureSends,
                      let indice = lista.firstIndex(where: { $0.wallet == registro.wallet && $0.chainID == registro.chainID && $0.hash == registro.hash })
                else { throw NadaATirar() }
                // So o registro conferido aqui. O confirmado sai sempre; o resto, so se ele segue como foi lido (um
                // "Transmitir de novo" durante a leitura refez a hora, e esse e conferido na proxima poda).
                switch passo {
                case .sent:
                    lista.remove(at: indice)
                    // O que o envio feito anota (`Envio.concluir`), uma vez so: junto com a saida do registro.
                    if let para = registro.recipient {
                        var enviados = metadata.sentTo[registro.chainID] ?? []
                        if !enviados.contains(para) { enviados.append(para) }
                        metadata.sentTo[registro.chainID] = enviados
                    }
                    metadata.settings.completedSends = (metadata.settings.completedSends ?? 0) + 1
                    // A rede desta carteira le o historico de novo: a linha de verdade entra no lugar da pendente.
                    metadata.activityFetched?[registro.wallet]?[registro.chainID] = nil
                case .dropped:
                    guard lista[indice] == registro else { throw NadaATirar() }
                    lista.remove(at: indice)
                case .keep(let novo):
                    guard lista[indice] == registro else { throw NadaATirar() }
                    lista[indice] = novo
                }
                metadata.unsureSends = lista.isEmpty ? nil : lista
                return true
            }) ?? false
            guard gravou else { continue }
            // A linha que a memoria ainda mostra acompanha o registro.
            switch passo {
            case .sent: Atividade.shared.assentarEnviado(hash: registro.hash, carteira: registro.wallet, situacao: .confirmed)
            case .dropped(let motivo?): Atividade.shared.assentarEnviado(hash: registro.hash, carteira: registro.wallet, situacao: .failed(motivo))
            case .dropped: Atividade.shared.retirarEnviado(hash: registro.hash, carteira: registro.wallet)
            case .keep(let novo) where !UnsureSends.shown(novo):
                // A marca das moedas sai da Atividade, como o envio que a rede nao conhece saia antes.
                Atividade.shared.retirarEnviado(hash: registro.hash, carteira: registro.wallet)
            case .keep(let novo):
                guard case .pending(let nota) = novo.entry(unanswered: Self.nota).status else { break }
                Atividade.shared.assentarEnviado(hash: registro.hash, carteira: registro.wallet, situacao: .pending(nota))
            }
        }
    }
}

// MARK: A ponte

/// Leva para a tarefa o que nao e Sendable (a credencial com o PIN, a passphrase). So uma tarefa
/// usa, e quem chamou espera ela terminar.
struct Embrulho<T>: @unchecked Sendable { let valor: T; init(_ valor: T) { self.valor = valor } }

extension Envio {
    /// Os metodos "envio.*". As chamadas que vao a rede bloqueiam ate a resposta: o Kotlin chama
    /// de uma corrotina fora da thread principal e recebe o retrato novo.
    struct AtivoParaEnviar: Encodable {
        let id: String, simbolo: String, nome: String, rede: String, redeNome: String, redeCoingecko: String, coingecko: String?
        let casas: Int, custom: Bool, conferido: Bool, quantidade: String, disponivel: String, valor: Double?, indisponivel: String?
    }

    /// Uma linha por ativo por rede, porque todo envio acontece numa rede.
    static func ativos() throws -> [AtivoParaEnviar] {
        let metadata = Sessao.shared.metadata
        guard let wallet = metadata.selectedWallet, !wallet.isWatchOnly else { return [] }
        _ = Saldos.shared.mostrar()
        return Saldos.shared.posicoes(carteira: wallet.id).compactMap { item in
            guard let chain = item.asset.chain else { return nil }
            let livre = Saldos.shared.saldo(chain, carteira: wallet.id).map { $0.available(item) } ?? item.amount
            let valor = Saldos.shared.preco(item.asset).map { Saldos.decimal(item.amount, casas: item.asset.decimals) * $0 }
            return AtivoParaEnviar(
                id: item.asset.id, simbolo: item.asset.symbol, nome: item.asset.name, rede: chain.id, redeNome: chain.name,
                redeCoingecko: chain.coingeckoID, coingecko: item.asset.coingeckoID, casas: item.asset.decimals, custom: item.asset.isCustom,
                conferido: item.asset.isVerified, quantidade: item.amount.decimalString, disponivel: livre.decimalString, valor: valor,
                indisponivel: item.asset.isCustom ? CustomToken.sendUnavailableReason(chain) : nil
            )
        }
    }

    static func chamar(_ metodo: String, _ pedido: JSONValue) throws -> Data {
        if metodo == "envio.ativos" { return try Nucleo.json(ativos()) }
        if metodo == "envio.iniciar" {
            let envio = try comecar(ativo: pedido["ativo"]?.stringValue ?? "")
            return try retrato(envio)
        }
        if metodo == "envio.encerrar" {
            encerrar(pedido["id"]?.stringValue ?? "")
            return try Nucleo.json(["ok": true])
        }
        guard let envio = atual else { throw Nucleo.Falha(erro: "envio.semEnvio") }
        switch metodo {
        case "envio.estado": break
        case "envio.historico": Nucleo.esperarSemErro { await envio.lerHistorico() }
        case "envio.destino": envio.mudarDestino(String((pedido["texto"]?.stringValue ?? "").prefix(4096)))
        case "envio.link": envio.aplicarLink(String((pedido["texto"]?.stringValue ?? "").prefix(4096)))
        case "envio.trocarRede": envio.trocarRede(ativo: pedido["ativo"]?.stringValue ?? "")
        case "envio.conferir":
            envio.conferir(
                parecido: pedido["parecido"]?.stringValue, outroID: pedido["outroID"]?.stringValue, cego: pedido["cego"]?.stringValue,
                redeConfirmada: pedido["rede"]?.boolValue, tag: pedido["tag"]?.stringValue
            )
        case "envio.editarDestino": envio.editarDestino()
        case "envio.escolher": envio.escolher(endereco: String((pedido["endereco"]?.stringValue ?? "").prefix(512)), tag: pedido["tag"]?.stringValue)
        case "envio.continuar": Nucleo.esperarSemErro { await envio.continuar() }
        case "envio.tag": envio.definirTag(pedido["texto"]?.stringValue ?? "", pular: pedido["pular"]?.boolValue ?? false)
        case "envio.voltar":
            guard let etapa = pedido["etapa"]?.stringValue.flatMap(Etapa.init(rawValue:)), [.destino, .tag, .valor].contains(etapa) else {
                throw Nucleo.Falha(erro: "etapa invalida")
            }
            envio.voltar(para: etapa)
        case "envio.valor": envio.mudarValor(pedido["texto"]?.stringValue ?? "", tudo: pedido["tudo"]?.boolValue ?? false)
        case "envio.disponivel": Nucleo.esperarSemErro { await envio.carregarDisponivel() }
        case "envio.ordens":
            let ativo = envio.holding.asset
            Nucleo.esperarSemErro { await Ordens.shared.lerDoEnvio(ativo) }
        case "envio.revisar": Nucleo.esperarSemErro { await envio.revisar() }
        case "envio.renovar": Nucleo.esperarSemErro { _ = await envio.renovar() }
        case "envio.retransmitir": Nucleo.esperarSemErro { await envio.retransmitir() }
        case "envio.acompanhar": Nucleo.esperarSemErro { await envio.acompanhar() }
        default: throw Nucleo.Falha(erro: "metodo desconhecido: \(metodo)")
        }
        return try retrato(envio)
    }

    /// "envio.assinar": a credencial e, na carteira com passphrase, a passphrase depois dela.
    static func assinar(_ credencial: Credencial, passphrase: SecureBytes?, folga: Int?, versao: Int?) throws -> Data {
        guard let envio = atual else {
            credencial.zerar()
            passphrase?.wipe()
            throw Nucleo.Falha(erro: "envio.semEnvio")
        }
        let pedido = Embrulho((credencial, passphrase))
        try esperar { try await envio.assinar(pedido.valor.0, passphrase: pedido.valor.1, folga: folga, versao: versao) }
        return try retrato(envio)
    }

    private static func retrato(_ envio: Envio) throws -> Data {
        let numero = contagem.withLock { () -> Int in
            ultimoNumero += 1
            return ultimoNumero
        }
        let estado = envio.estado()
        let preco = Saldos.shared.preco(envio.holding.asset)
        return try Nucleo.json(Retrato(numero: numero, id: envio.id.uuidString, envio: estado, preco: preco, moeda: Sessao.shared.metadata.settings.currency,
                                       pedePassphrase: PortaDaPassphrase.precisa(envio.wallet), nomeDaCarteira: envio.wallet.name,
                                       semConferencia: PortaDaPassphrase.semConferencia(envio.wallet),
                                       ordens: Ordens.shared.retratoDoEnvio(envio.holding.asset)))
    }

    private static let contagem = NSLock()
    nonisolated(unsafe) private static var ultimoNumero = 0

    /// A etapa mudou no meio de uma chamada longa (assinou e esta transmitindo): a interface
    /// fica sabendo sem esperar a resposta.
    func avisar() {
        guard let json = try? Self.retrato(self) else { return }
        Eventos.emitir("envio", json)
    }

    /// Cada retrato leva um numero crescente: a interface descarta o que chegar fora de ordem.
    struct Retrato: Encodable {
        let numero: Int
        let id: String
        let envio: Estado
        let preco: Double?
        let moeda: String
        let pedePassphrase: Bool
        let nomeDaCarteira: String
        /// A carteira com passphrase que esta versao nao confere: a tela recusa antes de pedir a passphrase e o PIN.
        let semConferencia: Bool
        /// As ordens de venda abertas deste ativo, se houver (lidas com "envio.ordens").
        let ordens: Ordens.DoEnvio?
    }
}
