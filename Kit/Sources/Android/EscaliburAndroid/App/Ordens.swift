import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburNetwork
import Foundation

/// As ordens limite abertas desta carteira em todas as redes com ordem limite, lidas da rede (o
/// `OpenOrdersSection` e o `OpenOrdersBook` do iOS). Nao depende da rede escolhida na troca. A
/// interface rele a cada 6 s enquanto a lista esta na tela; a ordem que some da lista (executou ou
/// venceu) fica com o resultado final ate a lista ser lida do zero.
///
/// O resto da troca usa o livro: o disponivel de uma ordem nova desconta o que ainda falta vender
/// nas abertas do mesmo ativo, e a ordem com cancelamento enviado sai da lista na hora, mas continua
/// contando no que esta preso ate a rede parar de lista-la.
final class Ordens: @unchecked Sendable {
    static let shared = Ordens()
    private let trava = NSLock()

    private var carteiraID: UUID?
    /// nil: ainda nao lida nesta carteira.
    private var ordens: [OpenOrder]?
    private var falha: String?
    /// Cancelamento enviado e ainda listado pela rede: id da ordem e quando foi enviado.
    private var cancelando: [String: Date] = [:]
    /// As que sairam da lista nesta visita, com o andamento final.
    private var terminadas: [(ordem: OpenOrder, andamento: OrderProgress)] = []
    /// Redes que nao responderam na ultima leitura (as outras continuam na lista).
    private var semResposta: [Chain] = []

    private init() {}

    // MARK: O que a troca consulta

    /// O que ainda falta vender nas ordens abertas que vendem este ativo (as com cancelamento
    /// enviado contam ate a rede confirmar: ate la elas ainda executam).
    func travado(_ ativo: Asset) -> BigUInt {
        let id = ativo.id.lowercased()
        return trava.withLock {
            guard carteiraID == Sessao.shared.metadata.selectedWallet?.id else { return BigUInt() }
            return (ordens ?? []).filter { $0.sellAssetID.lowercased() == id && $0.chain.id == ativo.chainID }
                .reduce(BigUInt()) { $0 + $1.remainingSell }
        }
    }

    func marcarCancelando(_ id: String) { trava.withLock { cancelando[id] = Date() } }

    /// Cancelamento enviado ha menos de 10 minutos. Se a transacao falhar na rede, a ordem volta a
    /// aparecer depois disso: uma ordem viva nunca fica escondida de vez. Chamar com a trava.
    private func cancelandoAgora(_ id: String) -> Bool {
        guard let enviado = cancelando[id] else { return false }
        return Date().timeIntervalSince(enviado) < 600
    }

    /// Tambem a do Enviar, lida so na rede dele: o cancelar de la passa pela mesma revisao.
    func ordem(_ id: String) -> OpenOrder? {
        trava.withLock { ordens?.first { $0.id == id } ?? doEnvio?.ordens.first { $0.id == id } }
    }

    // MARK: O que o envio consulta

    /// As ordens abertas que vendem o ativo do envio, lidas so na rede dele, e nao em todas (o
    /// `loadSellingOrders` do iOS): o Enviar mostra quanto esta reservado e deixa cancelar a ordem ou
    /// enviar so o livre.
    private var doEnvio: (carteira: UUID, ordens: [OpenOrder])?

    struct DoEnvio: Encodable {
        /// O que falta vender nelas, em unidades inteiras do ativo (texto decimal). As com cancelamento
        /// enviado contam ate a rede parar de lista-las: ate la elas ainda executam.
        let reservado: String
        let ordens: [Linha]
        let cancelando: [String]
    }

    func lerDoEnvio(_ ativo: Asset) async {
        let metadata = Sessao.shared.metadata
        guard let carteira = metadata.selectedWallet, let rede = ativo.chain, let motor = TradeEngines.engine(for: rede), motor.supportsLimitOrders,
              let conta = carteira.account(rede), let lidas = try? await motor.openOrders(account: conta) else { return }
        let id = ativo.id.lowercased()
        trava.withLock { doEnvio = (carteira.id, lidas.filter { $0.sellAssetID.lowercased() == id && $0.chain.id == rede.id }) }
    }

    func retratoDoEnvio(_ ativo: Asset) -> DoEnvio? {
        let carteira = Sessao.shared.metadata.selectedWallet
        let podeAssinar = carteira?.isWatchOnly == false
        let id = ativo.id.lowercased()
        return trava.withLock {
            guard let lidas = doEnvio, lidas.carteira == carteira?.id else { return nil }
            let doAtivo = lidas.ordens.filter { $0.sellAssetID.lowercased() == id && $0.chain.id == ativo.chainID }
            guard !doAtivo.isEmpty else { return nil }
            return DoEnvio(
                reservado: doAtivo.reduce(BigUInt()) { $0 + $1.remainingSell }.decimalString,
                ordens: doAtivo.map { linha($0, podeAssinar: podeAssinar) },
                cancelando: doAtivo.map(\.id).filter(cancelandoAgora)
            )
        }
    }

    /// Um jeito so de cancelar, o garantido: a transacao na rede, que invalida a ordem de vez. O
    /// pedido gratis a CoW nao garante (um solver que ja estava executando ainda conclui).
    static func maisSeguro(_ opcoes: [OpenOrder.Cancellation]) -> OpenOrder.Cancellation? {
        opcoes.contains(.onchain) ? .onchain : opcoes.first
    }

    /// O ativo de uma ordem pelo id: o da lista, a moeda adicionada, o que esta no saldo e o que ja
    /// passou por uma troca deste aparelho. Fora disso, nil: sem nome nem casas que poderiam estar
    /// errados.
    static func resolver(_ id: String, listado: Asset?, rede: Chain) -> Asset? {
        if let listado { return listado }
        let metadata = Sessao.shared.metadata
        if let custom = metadata.customTokens.first(where: { $0.id == id }) { return custom }
        if let carteira = metadata.selectedWallet,
           let tido = Saldos.shared.saldo(rede, carteira: carteira.id)?.unlisted?.first(where: { $0.asset.id == id && !$0.isSuspicious }) {
            return tido.asset
        }
        return metadata.tradedAssets?.first { $0.id == id }
    }

    // MARK: Ler

    /// `inicial`: a primeira leitura da visita limpa as terminadas e mostra o erro. As seguintes so
    /// trocam a lista quando a leitura volta; falha no meio mantem a lista que havia.
    func ler(inicial: Bool) async {
        let metadata = Sessao.shared.metadata
        guard let carteira = metadata.selectedWallet else { return }
        let desligadas = metadata.settings.disabledChainIDs
        let alvos: [(Chain, any TradeEngine, DerivedAccount)] = TradeEngines.chains.compactMap { rede in
            guard !desligadas.contains(rede.id), let motor = TradeEngines.engine(for: rede), motor.supportsLimitOrders,
                  let conta = carteira.account(rede) else { return nil }
            return (rede, motor, conta)
        }
        let antes = trava.withLock { () -> [OpenOrder] in
            if carteiraID != carteira.id {
                carteiraID = carteira.id
                ordens = nil
                terminadas = []
                cancelando = [:]
            }
            if inicial {
                terminadas = []
                falha = nil
            }
            return ordens ?? []
        }
        // Todas as redes ao mesmo tempo; a que nao responde nao segura as outras.
        let resultados = await withTaskGroup(of: (Chain, [OpenOrder]?).self) { grupo in
            for (rede, motor, conta) in alvos {
                grupo.addTask { (rede, try? await motor.openOrders(account: conta)) }
            }
            var saida: [(Chain, [OpenOrder]?)] = []
            for await resultado in grupo { saida.append(resultado) }
            return saida
        }
        let responderam = resultados.compactMap { rede, lidas in lidas.map { (rede, $0) } }
        let falharam = resultados.filter { $0.1 == nil }.map(\.0)
        guard !responderam.isEmpty || alvos.isEmpty else {
            trava.withLock {
                if inicial || ordens == nil { falha = Textos.t("Não foi possível ler as ordens agora. Tente de novo.") }
            }
            return
        }
        let posicao = Dictionary(Chain.all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { primeiro, _ in primeiro })
        var lidas = responderam.flatMap(\.1)
        // Uma rede que nao respondeu agora fica com o que mostrava.
        let idsQueFalharam = Set(falharam.map(\.id))
        lidas += antes.filter { idsQueFalharam.contains($0.chain.id) }
        lidas.sort {
            (posicao[$0.chain.id] ?? .max, $0.expiresAt ?? .distantFuture) < (posicao[$1.chain.id] ?? .max, $1.expiresAt ?? .distantFuture)
        }
        // A que saiu da lista (numa rede que respondeu) terminou: le o andamento final. Executada
        // ou vencida fica na lista com o resultado; cancelada sai de vez.
        let atuais = Set(lidas.map(\.id))
        let redesQueResponderam = Set(responderam.map(\.0.id))
        let jaTerminadas = trava.withLock { Set(terminadas.map(\.ordem.id)) }
        var novasTerminadas: [(OpenOrder, OrderProgress)] = []
        for saiu in antes where redesQueResponderam.contains(saiu.chain.id) && !atuais.contains(saiu.id) && !jaTerminadas.contains(saiu.id) {
            guard let motor = TradeEngines.engine(for: saiu.chain), let conta = carteira.account(saiu.chain) else { continue }
            if let andamento = try? await motor.orderProgress(id: saiu.id, account: conta), andamento.isFinal {
                if andamento.state != .cancelled { novasTerminadas.append((saiu, andamento)) }
                VigiaDeOrdens.assentar(saiu.id, executada: andamento.state == .filled)
            }
        }
        // Ordem da CoW aberta (criada antes destes avisos, ou em outro aparelho): passa a ser
        // acompanhada para o aviso de vencimento e o de executada. A carteira com passphrase fica de
        // fora: o UID traz o endereco, e o arquivo dos avisos abre com o app travado.
        if !carteira.hasPassphrase {
            for aberta in lidas where !trava.withLock({ cancelandoAgora(aberta.id) }) {
                guard let vence = aberta.expiresAt else { continue }
                VigiaDeOrdens.acompanhar(id: aberta.id, rede: aberta.chain, venceEm: vence)
            }
        }
        trava.withLock {
            guard carteiraID == carteira.id else { return }
            ordens = lidas
            falha = nil
            terminadas += novasTerminadas
            semResposta = falharam.sorted { (posicao[$0.id] ?? .max) < (posicao[$1.id] ?? .max) }
            cancelando = cancelando.filter { atuais.contains($0.key) }
        }
    }

    // MARK: O retrato

    struct Linha: Encodable {
        let id: String
        let rede: String
        let redeNome: String
        let redeCoingecko: String
        let vende: Troca.Estado.Ativo?
        let titulo: String
        let tituloCurto: String
        let detalhe: String
        let porNoMinimo: String
        let preco: String?
        let precoCurto: String?
        let vence: Double?
        let fracao: Double?
        let recebido: String?
        let falta: String?
        let criada: Double?
        let onde: String
        let podeCancelar: Bool
        let explicacao: String
    }

    struct Terminada: Encodable {
        let id: String
        let vende: Troca.Estado.Ativo?
        let titulo: String
        let resultado: String
        let executada: Bool
        let fracao: Double
    }

    struct Retrato: Encodable {
        let carregando: Bool
        let falha: String?
        let ordens: [Linha]
        let terminadas: [Terminada]
        let semResposta: String?
        let podeAssinar: Bool
    }

    func retrato() -> Retrato {
        let carteira = Sessao.shared.metadata.selectedWallet
        let podeAssinar = carteira?.isWatchOnly == false
        return trava.withLock {
            guard carteiraID == carteira?.id else {
                return Retrato(carregando: true, falha: nil, ordens: [], terminadas: [], semResposta: nil, podeAssinar: podeAssinar)
            }
            let mostradas = (ordens ?? []).filter { !cancelandoAgora($0.id) }
            return Retrato(
                carregando: ordens == nil && falha == nil, falha: falha,
                ordens: mostradas.map { linha($0, podeAssinar: podeAssinar) },
                terminadas: terminadas.map { terminada($0.ordem, $0.andamento) },
                semResposta: semResposta.isEmpty ? nil
                    : preencher(Textos.t("Sem resposta agora: %@. A lista tenta de novo sozinha."), semResposta.map(\.name).joined(separator: ", ")),
                podeAssinar: podeAssinar
            )
        }
    }

    /// Ativo fora da lista (ordem criada fora da carteira) nao ganha nome nem casas da rede:
    /// aparece como tal, sem numero que poderia estar errado.
    static func quantia(_ valor: BigUInt, _ ativo: Asset?) -> String {
        guard let ativo else { return Textos.t("um token fora da lista") }
        return Fmt.cripto(valor, casas: ativo.decimals, simbolo: ativo.symbol)
    }

    /// O preco limite: quanto do comprado por uma unidade do vendido, pelo minimo gravado na ordem.
    /// A linha da lista ("Preço: 1 XRP = 1,32 RLUSD") e so o preco, para o detalhe.
    static func preco(_ ordem: OpenOrder, vende: Asset?, compra: Asset?) -> (linha: String, curto: String)? {
        guard let vende, let compra, !ordem.remainingSell.isZero else { return nil }
        let vendido = Saldos.decimal(ordem.remainingSell, casas: vende.decimals)
        let comprado = Saldos.decimal(ordem.minimumBuy, casas: compra.decimals)
        guard vendido > 0, comprado > 0 else { return nil }
        let texto = Troca.textoDoPreco(comprado / vendido)
        let numero = Troca.zerosCompactos(texto) ?? texto
        return (preencher(Textos.t("Preço: 1 %@ = %@ %@"), vende.symbol, numero, compra.symbol), "1 \(vende.symbol) = \(numero) \(compra.symbol)")
    }

    /// Onde a ordem esta: o livro da CoW nas redes EVM, o livro do proprio ledger nas outras.
    static func onde(_ rede: Chain) -> String {
        switch rede.family {
        case .evm: return "CoW Protocol"
        case .xrpl: return Textos.t("Livro de ofertas do XRP Ledger")
        case .stellar: return Textos.t("Livro de ofertas da Stellar")
        default: return rede.name
        }
    }

    static func explicacao(_ via: OpenOrder.Cancellation?) -> String {
        switch via {
        case .onchain?: return Textos.t("A carteira envia uma transação que invalida a ordem de vez, com a taxa da rede. Depois que ela confirmar, a ordem não executa mais, e o que não foi vendido continua na sua carteira.")
        case .offchain?: return Textos.t("A carteira pede à CoW para parar de oferecer a ordem. O que não foi vendido continua na sua carteira.")
        case nil: return Textos.t("Esta ordem não pode ser cancelada pela carteira.")
        }
    }

    /// Chamar com a trava (so le o que nao muda).
    private func linha(_ ordem: OpenOrder, podeAssinar: Bool) -> Linha {
        let vende = Self.resolver(ordem.sellAssetID, listado: ordem.sell, rede: ordem.chain)
        let compra = Self.resolver(ordem.buyAssetID, listado: ordem.buy, rede: ordem.chain)
        let total = Self.quantia(ordem.totalSell ?? ordem.remainingSell, vende)
        let porNoMinimo = preencher(Textos.t("por no mínimo %@"), Self.quantia(ordem.minimumBuy, compra))
        let recebido = ordem.receivedBuy.flatMap { $0.isZero ? nil : Self.quantia($0, compra) }
        let falta = Self.quantia(ordem.remainingSell, vende)
        let via = Self.maisSeguro(ordem.cancellations)
        let precos = Self.preco(ordem, vende: vende, compra: compra)
        return Linha(
            id: ordem.id, rede: ordem.chain.id, redeNome: ordem.chain.name, redeCoingecko: ordem.chain.coingeckoID,
            vende: vende.map(Troca.dto), titulo: preencher(Textos.t("Vende %@ na %@"), total, ordem.chain.name),
            tituloCurto: preencher(Textos.t("Vende %@"), total),
            detalhe: recebido.map { preencher(Textos.t("Recebido %@, falta vender %@"), $0, falta) } ?? porNoMinimo,
            porNoMinimo: porNoMinimo, preco: precos?.linha, precoCurto: precos?.curto,
            vence: ordem.expiresAt.map { $0.timeIntervalSince1970 * 1000 }, fracao: ordem.filledFraction,
            recebido: recebido, falta: recebido == nil ? nil : falta, criada: ordem.createdAt.map { $0.timeIntervalSince1970 * 1000 },
            onde: Self.onde(ordem.chain), podeCancelar: podeAssinar && via != nil && vende != nil && compra != nil,
            explicacao: Self.explicacao(via)
        )
    }

    private func terminada(_ ordem: OpenOrder, _ andamento: OrderProgress) -> Terminada {
        let vende = Self.resolver(ordem.sellAssetID, listado: ordem.sell, rede: ordem.chain)
        let compra = Self.resolver(ordem.buyAssetID, listado: ordem.buy, rede: ordem.chain)
        let percentual = Self.percentual(andamento.fraction)
        let resultado: String
        switch andamento.state {
        case .filled: resultado = preencher(Textos.t("Executada. Recebido %@"), Self.quantia(andamento.receivedBuy, compra))
        case .expired: resultado = andamento.fraction > 0 ? preencher(Textos.t("Venceu com %@ preenchido"), percentual) : Textos.t("Venceu sem preencher")
        case .cancelled: resultado = andamento.fraction > 0 ? preencher(Textos.t("Cancelada com %@ preenchido"), percentual) : Textos.t("Cancelada")
        case .open: resultado = ""
        }
        return Terminada(id: ordem.id, vende: vende.map(Troca.dto), titulo: preencher(Textos.t("Vende %@"), Self.quantia(andamento.totalSell, vende)),
                         resultado: resultado, executada: andamento.state == .filled, fracao: andamento.fraction)
    }

    /// "37%": para baixo, nunca 0% com algo preenchido nem 100% sem estar inteira.
    static func percentual(_ fracao: Double) -> String {
        guard fracao > 0 else { return "0%" }
        guard fracao < 1 else { return "100%" }
        let inteiro = Int((fracao * 100).rounded(.down))
        return inteiro == 0 ? "<1%" : "\(min(inteiro, 99))%"
    }
}
