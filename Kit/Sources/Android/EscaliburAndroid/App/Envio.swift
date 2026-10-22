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
    private var historicoLido = false
    private var trechoCego: AddressPoisoning.Segment?
    private var fonteCega = ""
    private var conferenciaCega = ""
    private var primeiroEnvio = false
    private var tag = ""
    private var tagDoLink: String?
    private var pulouTag = false
    private var sugestaoDeRede: Holding?
    private var redeConfirmada = false
    private var textoDoValor = ""
    private var tudo = false
    private var disponivel: Spendable?
    private var nivelDaTaxa: FeeLevel = .normal
    private var plano: SigningPlan?
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
        struct Parecido: Encodable { let conhecido: String; let rotulo: String; let trechoColado: Trecho?; let trechoConhecido: Trecho? }
        struct OutroID: Encodable {
            let conhecido: String; let idConhecido: String; let rotulo: String; let trechoColado: Trecho?; let trechoConhecido: Trecho?
        }
        struct Cego: Encodable { let fonte: String; let trecho: Trecho }
        struct Sugestao: Encodable { let ativo: String; let simbolo: String; let redeNome: String }
        struct Disponivel: Encodable { let quantidade: String; let notaDeReserva: String?; let notaDeTaxa: String? }
        struct LinhaDaPlaca: Encodable { let rotulo: String; let valor: String; let endereco: Bool }
        struct Linha: Encodable { let rotulo: String; let valor: String }
        struct Plano: Encodable {
            let titulo: String; let placa: [LinhaDaPlaca]; let linhas: [Linha]; let avisos: [String]; let saida: String
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
    struct MinhaCarteira: Encodable { let id: String; let nome: String; let endereco: String }

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
                    trechoColado: trechoDoParecido.map(trecho), trechoConhecido: AddressPoisoning.differingSegment(conhecido, from: destino.address, chain: chain).map(trecho)
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
        let cego: Estado.Cego? = (parecido == nil) ? trechoCego.map { Estado.Cego(fonte: fonteCega, trecho: trecho($0)) } : nil
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
            primeiroEnvio: primeiroEnvio, historicoLido: historicoLido, parecido: parecidoDTO, outroID: outroDTO, cego: cego,
            precisaConfirmarRede: precisaConfirmarRede, notaDaRede: precisaConfirmarRede ? notaDaConfirmacao(chain) : nil,
            textoDaConfirmacaoDeRede: precisaConfirmarRede ? (chain.family == .near ? Textos.t("Este endereço é de uma conta NEAR")
                : preencher(Textos.t("Quem vai receber aceita %@ pela %@"), asset.symbol, chain.name)) : nil,
            muxed: muxed, precisaEtapaDaTag: precisaEtapaDaTag, exigeTag: infoDoDestino?.requiresTag == true, tag: tag,
            tagDoLink: tagDoLink != nil && tagDoLink == tag, problemaDaTag: problemaDaTag, liberado: liberado,
            podeContinuar: destino != nil && historicoLido && liberado && problemaDaTag == nil && (!precisaConfirmarRede || redeConfirmada),
            disponivel: disponivel.map { Estado.Disponivel(quantidade: $0.amount.decimalString, notaDeReserva: $0.reserveNote, notaDeTaxa: $0.feeNote) },
            ativacao: infoDoDestino?.activationMinimum.map { Fmt.cripto($0, casas: asset.decimals, simbolo: asset.symbol) },
            valor: textoDoValor, tudo: tudo, plano: plano.map(planoDTO), erro: erro, resultado: resultado, detalheIncerto: detalheIncerto,
            linhaDoEnvio: linhaDoEnvio(), tempoDeConfirmacao: chain.typicalConfirmationSeconds,
            contatos: metadata.contacts.filter { $0.chainID == chain.id }.map { Contato(nome: $0.name, endereco: $0.address, tag: $0.tag) },
            minhasCarteiras: minhasCarteiras(chain, metadata).map { MinhaCarteira(id: $0.wallet.id.uuidString, nome: $0.wallet.name, endereco: $0.address) },
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
        if let segmento = trechoCego, parecido == nil {
            let digitado = conferenciaCega.trimmingCharacters(in: .whitespaces).lowercased()
            guard digitado.count == segmento.length, digitado == segmento.text(in: fonteCega).lowercased() else { return false }
        }
        if outroID != nil {
            guard let address = destino?.address, AddressPoisoning.muxedIDConfirmed(conferenciaDoOutroID, address: address) else { return false }
        }
        guard parecido != nil, let address = destino?.address else { return true }
        guard let segmento = trechoDoParecido else { return false }
        let digitado = conferenciaDoParecido.trimmingCharacters(in: .whitespaces).lowercased()
        return digitado.count == segmento.length && digitado == segmento.text(in: address).lowercased()
    }

    private var problemaDaTag: String? {
        guard !tag.isEmpty, let chain else { return nil }
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
        if let carteira = metadata.wallets.first(where: { !$0.isWatchOnly && $0.account(chain)?.address == address }) {
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

    /// Para quem esta carteira ja pagou nesta rede, do historico da propria rede. Sem ele, o
    /// primeiro envio pede o trecho escondido.
    func lerHistorico() async {
        guard let chain, let conta else {
            trava.withLock { historicoLido = true }
            return
        }
        trava.withLock { historicoLido = false }
        var lido: [ActivityEntry]?
        if let fonte = ActivitySources.source(for: chain) {
            lido = try? await fonte.history(chain: chain, account: conta, usage: wallet.utxoUsage[chain.id])
        }
        trava.withLock {
            guard self.chain?.id == chain.id else { return }
            defer { historicoLido = true }
            guard let entradas = lido else {
                historicoIndisponivel = true
                if destino != nil { validar() }
                return
            }
            historicoIndisponivel = false
            let pagos = entradas.compactMap { entrada -> String? in
                guard entrada.direction == .sent, entrada.status == .confirmed, !entrada.suspicious else { return nil }
                return entrada.counterparty
            }
            historico = Array(Set(pagos))
            if destino != nil { validar() }
        }
    }

    func mudarDestino(_ texto: String) {
        trava.withLock {
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
            } catch PaymentLink.Problem.unknownScheme {
                problema = Textos.t("O app não reconhece este tipo de link. Cole só o endereço.")
            } catch PaymentLink.Problem.unsupportedNetwork {
                problema = Textos.t("Este pedido de pagamento é de uma rede que a Escalibur não envia. Confira com quem pediu.")
            } catch PaymentLink.Problem.unsupportedMemo {
                problema = Textos.t("Este pedido traz um memo que o app não envia como está. Cole só o endereço e digite o memo, conferindo com quem pediu.")
            } catch {
                problema = Textos.t("Este pedido de pagamento não pôde ser lido com segurança. Peça só o endereço.")
            }
            if problema == nil, let leitura, let chain {
                if let pedida = leitura.chainID, pedida != chain.id {
                    let nome = Chain.find(pedida)?.name ?? Textos.t("outra rede")
                    problema = preencher(Textos.t("Este pedido é da rede %@, e o envio é pela %@. Confira com quem pediu antes de enviar."), nome, chain.name)
                } else if let familia = leitura.family, familia != chain.family {
                    problema = preencher(Textos.t("Este pedido é de outra rede, e o envio é pela %@. Confira com quem pediu antes de enviar."), chain.name)
                }
            }
            let endereco = problema == nil ? (leitura?.address ?? "") : ""
            problemaDoLink = problema.map { (texto: endereco, mensagem: $0) }
            textoDoDestino = endereco
            tag = ""
            tagDoLink = nil
            validar()
            if problema == nil, let tagLida = leitura?.tag, !tagLida.isEmpty, let chain, chain.destinationTag != .none, destino != nil, !muxed {
                tag = tagLida
                tagDoLink = tagLida
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
        // A frase digitada ou colada no campo do destino sai dele na hora.
        if Self.pareceFrase(texto) {
            textoDoDestino = ""
            let mensagem = Textos.t("Este código traz as palavras de uma senha de carteira, não um endereço. Quem tem essas palavras tem o saldo: não mostre a ninguém.")
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
            destino = destination
            if let tagDoEndereco = destination.tag { tag = String(tagDoEndereco) }
            if chain.destinationTag == .none || muxed { tag = ""; tagDoLink = nil }
            let metadata = Sessao.shared.metadata
            let enviados = metadata.sentTo[chain.id] ?? []
            primeiroEnvio = !enviados.contains(destination.address)
            let contatos = metadata.contacts.filter { $0.chainID == chain.id }.map(\.address)
            let carteiras = metadata.wallets.filter { !$0.isWatchOnly }.compactMap { $0.account(chain)?.address }
            let conhecidos = conhecidos(chain)
            parecido = AddressPoisoning.lookalike(destination.address, among: conhecidos, chain: chain)
            trechoDoParecido = parecido.flatMap { AddressPoisoning.differingSegment(destination.address, from: $0, chain: chain) }
            outroID = AddressPoisoning.sameAccountOtherID(destination.address, among: conhecidos, tagged: contatosComTag(chain), chain: chain)
            if parecido == nil, outroID == nil, primeiroEnvio, historicoIndisponivel,
               !contatos.contains(destination.address), !carteiras.contains(destination.address) {
                fonteCega = texto
                trechoCego = AddressPoisoning.blindSegment(texto, chain: chain)
            }
        case .failure(let falha):
            problema = Self.mensagem(falha, chain: chain)
            if case .otherNetwork(let outra) = falha { sugestaoDeRede = sugestao(para: outra) }
        }
    }

    /// Texto que parece a senha de uma carteira: nunca vai para o campo do endereco.
    private static let palavrasBIP39: Set<String> = Set(WordLexicon.entries.compactMap(\.folded))

    /// A maior sequencia de palavras seguidas do texto que estao em alguma lista BIP-39.
    static func maiorSequenciaDePalavras(_ texto: String) -> Int {
        var maior = 0, seguidas = 0
        for pedaco in texto.split(whereSeparator: { !$0.isLetter }) {
            if palavrasBIP39.contains(WordLexicon.fold(String(pedaco))) {
                seguidas += 1
                maior = max(maior, seguidas)
            } else {
                seguidas = 0
            }
        }
        return maior
    }

    static func pareceFrase(_ texto: String) -> Bool {
        let espacado = texto.replacingOccurrences(of: "[,;\\-]", with: " ", options: .regularExpression)
        return Mnemonic.words(in: espacado).count >= 12
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
                  !(chain.family == .tron && carteira.tronForeignControl == true) else { return nil }
            return (carteira, address)
        }
    }

    /// Um contato salvo (com a tag dele) ou outra carteira do dono (sem tag).
    func escolher(endereco: String, tag: String?) {
        trava.withLock {
            textoDoDestino = endereco
            self.tag = tag ?? ""
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
            validar()
        }
    }

    func conferir(parecido: String?, outroID: String?, cego: String?, redeConfirmada: Bool?, tag: String?) {
        trava.withLock {
            if let parecido { conferenciaDoParecido = parecido }
            if let outroID { conferenciaDoOutroID = outroID }
            if let cego { conferenciaCega = cego }
            if let redeConfirmada { self.redeConfirmada = redeConfirmada }
            if let tag { self.tag = String(tag.prefix(120)) }
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
            conferenciaCega = ""
            tag = ""
            tagDoLink = nil
        }
    }

    /// Continuar do destino: a rede diz se o destino existe e se exige tag.
    func continuar() async {
        let (destino, chain, motor, pode) = trava.withLock { (self.destino, self.chain, self.motor, montarEstado().podeContinuar) }
        guard pode, let destino, let chain else { return }
        guard let motor else {
            trava.withLock { problema = SendEngineError.unsupported(chain).errorDescription }
            return
        }
        do {
            let info = try await motor.destination(destino.address, chain: chain)
            trava.withLock {
                infoDoDestino = info
                etapa = precisaEtapaDaTag && destino.tag == nil ? .tag : .valor
            }
        } catch {
            trava.withLock { problema = (error as? LocalizedError)?.errorDescription ?? Textos.t("Não foi possível consultar o destino agora.") }
        }
    }

    func definirTag(_ texto: String, pular: Bool) {
        trava.withLock {
            if pular {
                pulouTag = true
                tag = ""
                etapa = .valor
            } else if !texto.isEmpty {
                tag = String(texto.prefix(120))
                if problemaDaTag == nil { etapa = .valor }
            }
        }
    }

    func voltar(para etapa: Etapa) {
        trava.withLock {
            self.etapa = etapa
            erro = nil
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
            nonceQueue: FilaDeNonces.fila(metadata, carteira: wallet.id, rede: chain, endereco: conta.address)
        )
    }

    func carregarDisponivel() async {
        let (motor, sonda) = trava.withLock { (motor, pedido(quantidade: holding.amount, tudo: true)) }
        guard let motor, let sonda else { return }
        let lido = try? await motor.spendable(sonda)
        trava.withLock { disponivel = lido }
    }

    func revisar() async {
        let preparo = trava.withLock { () -> (any SendEngine, Chain, DerivedAccount, BigUInt)? in
            erro = nil
            guard let motor, let chain, let conta, let quantidade, !quantidade.isZero else { return nil }
            return (motor, chain, conta, quantidade)
        }
        guard let (motor, chain, conta, _) = preparo else { return }
        await FilaDeNonces.podar(carteira: wallet.id, rede: chain, endereco: conta.address)
        guard let pedido = trava.withLock({ quantidade.flatMap { pedido(quantidade: $0, tudo: tudo) } }) else { return }
        do {
            let novo = try await motor.plan(pedido)
            trava.withLock {
                guard confere(novo) else {
                    plano = nil
                    erro = Textos.t("O envio montado não confere com o destino digitado. Nada foi assinado.")
                    return
                }
                plano = novo
                etapa = .revisao
            }
        } catch {
            if (error as? SendEngineError)?.isLocalNonceQueueAhead == true {
                FilaDeNonces.esquecer(carteira: wallet.id, rede: chain, endereco: conta.address)
            }
            trava.withLock { erro = (error as? LocalizedError)?.errorDescription ?? Textos.t("Não foi possível preparar o envio.") }
        }
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
                            saida: (plano.review.outgoing?.amount ?? quantidade ?? BigUInt()).decimalString)
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
        case .lookalikeAddress(let conhecido): return preencher(Textos.t("Endereço parecido com %@."), Fmt.endereco(conhecido, chain: chain))
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
        }
    }

    // MARK: Assinar e transmitir

    /// A conferencia do destino vale ate a assinatura: se a validacao rodou de novo, o desafio volta
    /// para a tela do destino e nada e assinado. O plano confere de novo, e plano vencido volta.
    /// Carteira com passphrase: ela chega antes da biometria ou do PIN e o assinador confere.
    func assinar(_ credencial: Credencial, passphrase: SecureBytes?, folga: Int?) async throws {
        defer { passphrase?.wipe() }
        let preparo = trava.withLock { () -> (SigningPlan, any SendEngine, Chain)? in
            erro = nil
            guard let plano, let motor, let chain else { return nil }
            guard historicoLido, liberado else {
                etapa = .destino
                return nil
            }
            guard confere(plano) else {
                erro = Textos.t("O envio montado não confere com o destino digitado. Nada foi assinado.")
                return nil
            }
            guard !plano.isExpired() else {
                etapa = .valor
                erro = Textos.t("Os dados da rede venceram. Revise de novo.")
                return nil
            }
            return (plano, motor, chain)
        }
        guard let (plano, motor, chain) = preparo else {
            credencial.zerar()
            return
        }
        let carteira = Sessao.shared.metadata.wallets.first { $0.id == plano.walletID }
        if PortaDaPassphrase.precisa(carteira), passphrase == nil {
            credencial.zerar()
            throw Nucleo.Falha(erro: "envio.pedePassphrase")
        }
        let conferir = PortaDaPassphrase.pede(carteira) ? passphrase : nil
        if conferir != nil {
            do { try PortaDaPassphrase.comecar() } catch { credencial.zerar(); throw error }
        }
        let assinado: [SignedTransaction]
        do {
            assinado = try Sessao.shared.comChaveRaiz(credencial) { rk in
                try Signer.sign(plano, rootKey: rk, vault: Chaves.wallets, passphrase: conferir)
            }
        } catch {
            if conferir != nil {
                if (error as? Signer.Failure) == .passphraseMismatch { PortaDaPassphrase.errou() } else { PortaDaPassphrase.devolver() }
            }
            throw error
        }
        if conferir != nil {
            PortaDaPassphrase.passou()
            PortaDaPassphrase.comecarFolga(plano.walletID, minutos: folga)
        }
        trava.withLock { etapa = .enviando }
        avisar()
        await transmitir(assinado, plano: plano, motor: motor, chain: chain)
    }

    /// Transmite os bytes assinados. Erro aqui nao quer dizer que nada saiu: a tela diz isso,
    /// acompanha o id que ja se conhece e so oferece transmitir de novo os mesmos bytes.
    private func transmitir(_ assinado: [SignedTransaction], plano: SigningPlan, motor: any SendEngine, chain: Chain) async {
        if let endereco = conta?.address {
            FilaDeNonces.anotar(carteira: wallet.id, rede: chain, endereco: endereco, plano: plano, assinado: assinado)
        }
        let usoAtual = Sessao.shared.metadata.wallets.first { $0.id == wallet.id }?.utxoUsage[chain.id]
        if let uso = motor.usage(after: plano, current: usoAtual) {
            try? Sessao.shared.atualizar(wallet.id) { $0.utxoUsage[chain.id] = uso }
        }
        do {
            let id = try await motor.broadcast(assinado, chain: chain)
            trava.withLock {
                assinadoIncerto = nil
                detalheIncerto = nil
            }
            await concluir(id: id, motor: motor, chain: chain)
        } catch {
            trava.withLock {
                idDoResultado = assinado.last?.id
                assinadoIncerto = assinado
                detalheIncerto = (error as? LocalizedError)?.errorDescription
                etapa = .incerto
            }
        }
    }

    private func concluir(id: String, motor: any SendEngine, chain: Chain) async {
        let endereco = trava.withLock { () -> String? in
            idDoResultado = id
            etapa = .enviado
            return destino?.address
        }
        try? Sessao.shared.alterar { metadata in
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
            }
        } else {
            trava.withLock { situacao = agora }
        }
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
}

/// A fila local de nonces EVM, por carteira, rede e conta (o `NonceQueue` do iOS).
enum FilaDeNonces {
    static let velhaDepois: TimeInterval = 30 * 60

    static func chave(carteira: UUID, rede: Chain, endereco: String) -> String {
        "\(carteira.uuidString)|\(rede.id)|\(endereco.lowercased())"
    }

    static func fila(_ metadata: Metadata, carteira: UUID, rede: Chain, endereco: String) -> PendingNonceQueue? {
        guard rede.family == .evm, let entradas = metadata.pendingEVM?[chave(carteira: carteira, rede: rede, endereco: endereco)], !entradas.isEmpty
        else { return nil }
        return PendingNonceQueue.trailingRun(entradas.map { ($0.nonce, $0.hash) })
    }

    static func anotar(carteira: UUID, rede: Chain, endereco: String, plano: SigningPlan, assinado: [SignedTransaction]) {
        guard rede.family == .evm, plano.transactions.count == assinado.count else { return }
        let agora = Date()
        let novas = zip(plano.transactions, assinado).compactMap { transacao, assinatura -> PendingEVMTransaction? in
            guard let evm = transacao as? EVMTransaction else { return nil }
            return PendingEVMTransaction(nonce: evm.nonce, hash: assinatura.id, sentAt: agora)
        }
        guard !novas.isEmpty else { return }
        let chave = chave(carteira: carteira, rede: rede, endereco: endereco)
        try? Sessao.shared.alterar { metadata in
            var todas = metadata.pendingEVM ?? [:]
            let mantidas = (todas[chave] ?? []).filter { velha in !novas.contains { $0.nonce == velha.nonce } }
            todas[chave] = mantidas + novas
            metadata.pendingEVM = todas
        }
    }

    static func podar(carteira: UUID, rede: Chain, endereco: String) async {
        let chave = chave(carteira: carteira, rede: rede, endereco: endereco)
        guard rede.family == .evm, let entradas = Sessao.shared.metadata.pendingEVM?[chave], !entradas.isEmpty,
              let motor = SendEngines.engine(for: rede) else { return }
        var mantidas = [PendingEVMTransaction]()
        for entrada in entradas {
            if Date().timeIntervalSince(entrada.sentAt) > velhaDepois { continue }
            if case .pending = await motor.status(entrada.hash, chain: rede) { mantidas.append(entrada) }
        }
        guard mantidas != entradas else { return }
        try? Sessao.shared.alterar { $0.pendingEVM?[chave] = mantidas.isEmpty ? nil : mantidas }
    }

    static func esquecer(carteira: UUID, rede: Chain, endereco: String) {
        try? Sessao.shared.alterar { $0.pendingEVM?[chave(carteira: carteira, rede: rede, endereco: endereco)] = nil }
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
        case "envio.revisar": Nucleo.esperarSemErro { await envio.revisar() }
        case "envio.retransmitir": Nucleo.esperarSemErro { await envio.retransmitir() }
        case "envio.acompanhar": Nucleo.esperarSemErro { await envio.acompanhar() }
        default: throw Nucleo.Falha(erro: "metodo desconhecido: \(metodo)")
        }
        return try retrato(envio)
    }

    /// "envio.assinar": a credencial e, na carteira com passphrase, a passphrase depois dela.
    static func assinar(_ credencial: Credencial, passphrase: SecureBytes?, folga: Int?) throws -> Data {
        guard let envio = atual else {
            credencial.zerar()
            passphrase?.wipe()
            throw Nucleo.Falha(erro: "envio.semEnvio")
        }
        let pedido = Embrulho((credencial, passphrase))
        try esperar { try await envio.assinar(pedido.valor.0, passphrase: pedido.valor.1, folga: folga) }
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
                                       pedePassphrase: PortaDaPassphrase.precisa(envio.wallet), nomeDaCarteira: envio.wallet.name))
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
    }
}
