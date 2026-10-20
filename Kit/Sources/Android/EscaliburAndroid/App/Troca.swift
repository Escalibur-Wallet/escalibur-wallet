import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import EscaliburNetwork
import Foundation

/// A aba Trocar: o `TradeModel` e o `TradeReviewFlow` do iOS (Features/Trade), sem a interface. A
/// troca imediata, a ordem limite e o cancelamento de uma ordem aberta; a cotacao, o plano e cada
/// conferencia antes de assinar rodam aqui, iguais ao iOS. A interface (Kotlin) so mostra o retrato
/// (`Estado`) e devolve o que o dono escolheu.
///
/// A aba tem a sua troca (`aba`). Editar uma ordem e cancelar uma ordem abrem outras, com o proprio
/// formulario e a propria revisao, como as telas separadas do iOS: o formulario da aba nao muda.
final class Troca: @unchecked Sendable {
    enum Etapa: String, Encodable { case formulario, montando, revisao, enviando, enviada, incerta }
    enum Modo: String, Encodable { case agora, limite }

    /// O que a revisao assina.
    enum Operacao: @unchecked Sendable {
        case troca(TradeRequest, TradeQuote)
        case limite(LimitOrderRequest)
        case cancelar(OpenOrder, OpenOrder.Cancellation)

        var rede: Chain {
            switch self {
            case .troca(let pedido, _): return pedido.chain
            case .limite(let pedido): return pedido.chain
            case .cancelar(let ordem, _): return ordem.chain
            }
        }

        var cancela: Bool { if case .cancelar = self { return true }; return false }
        var limite: Bool { if case .limite = self { return true }; return false }
    }

    /// A ordem aberta em edicao: a revisao cancela esta antes de criar a nova.
    struct Edicao {
        let ordem: OpenOrder
        let via: OpenOrder.Cancellation
        let sell: Asset
        let buy: Asset
    }

    // MARK: As instancias

    static let aba = Troca(alvo: "aba")
    private static let travaDasOutras = NSLock()
    nonisolated(unsafe) private static var outras: [String: Troca] = [:]

    /// A troca de uma tela: a da aba, ou a de editar e a de cancelar uma ordem.
    static func instancia(_ alvo: String?) throws -> Troca {
        guard let alvo, alvo != "aba" else { return aba }
        guard let outra = travaDasOutras.withLock({ outras[alvo] }) else { throw Nucleo.Falha(erro: "troca.semTela") }
        return outra
    }

    let alvo: String
    private let trava = NSLock()

    private init(alvo: String) { self.alvo = alvo }

    // MARK: O formulario

    private var carteiraID: UUID?
    private var modo: Modo = .agora
    private var chain: Chain?
    private var sell: Asset?
    private var buy: Asset?
    private var textoDoValor = ""
    /// Sobem quando o proprio nucleo muda o texto (fracao do saldo, inverter, outra rede, troca
    /// concluida): so entao o campo da interface copia o retrato. O que o dono digita nao sobe.
    private var versaoDoValor = 0
    private var versaoDoRecebido = 0
    private var versaoDoPreco = 0
    /// O dono digitou em "Voce recebe". Na troca imediata o valor a pagar sai do `ExactOutSolver`;
    /// na ordem limite, o preco ou o valor vendido sai da conta.
    private var recebeExato = false
    private var textoDoRecebido = ""
    private var entradaCalculada: BigUInt?
    private var resolvendo = false
    /// Nem a ultima tentativa chegou ao recebido digitado: o garantido fica abaixo.
    private var abaixoDoAlvo = false
    private var tolerancia = 50
    private var automatica = true
    private var cotacao: TradeQuote?
    /// O pedido de que a cotacao mostrada e: com o valor ja mudado, ela fica na tela ate a nova
    /// chegar, mas nao vai para a revisao.
    private var chaveDaCotacao: String?
    private var cotando = false
    private var erro: String?
    private var emPartes = false
    /// O impacto que o dono aceitou, em %. Vale enquanto a cotacao nao piorar; trocar par,
    /// valor ou rede zera (auditoria 2, B1).
    private var impactoAceito: Double?
    /// O provedor que o dono escolheu na rota, para este par: as recotacoes seguem nele enquanto
    /// ele estiver na rodada.
    private var escolhido: (provedor: String, par: String)?
    /// O plano que nao saiu: o erro volta para o formulario.
    private var erroDoPlano: String?

    // Ordem limite
    private var textoDoPreco = ""
    /// O preco-alvo que o app preencheu (o de agora). Enquanto o dono nao muda o campo, trocar o
    /// par preenche de novo.
    private var precoAuto: String?
    /// O par (e se havia preco de mercado) da ultima vez que o app preencheu o preco.
    private var chaveDoAlvo: String?
    /// Por quanto tempo a ordem vale; nil e "ate cancelar".
    private var validade: TimeInterval? = 30 * 86_400
    /// O preco que o dono confirmou mesmo abaixo do mercado, como digitado.
    private var precoAceito: String?
    private enum Deriva { case preco, valor }
    /// Na ordem limite, o que acompanha o recebido digitado.
    private var deriva: Deriva = .preco
    private(set) var edicao: Edicao?

    // MARK: A revisao

    private(set) var etapa: Etapa = .formulario
    /// Cada revisao tem o seu numero: o plano de uma revisao fechada nao entra noutra.
    private var rodada = 0
    private var operacao: Operacao?
    /// Edicao: a etapa 1 (cancelar a atual) antes da ordem nova.
    private var cancelarAntes: (ordem: OpenOrder, via: OpenOrder.Cancellation)?
    private var cancelou = false
    /// Os ativos da revisao (no cancelamento, os da ordem, que podem estar fora da lista).
    private var ativosDaRevisao: (vende: Asset?, compra: Asset?) = (nil, nil)
    private var plano: SigningPlan?
    private var erroDaRevisao: String?
    /// O cancelamento (ou a ordem nova depois dele) nao foi montado: o erro fica na revisao, com o
    /// tentar de novo.
    private var falhaDaMontagem: String?
    private var valorEmMoeda: Double?
    private var ids: [String] = []
    private var assinadoIncerto: [SignedTransaction]?
    private var detalheIncerto: String?
    private var situacao: TransferStatus = .pending
    private var andamento: OrderProgress?
    private var semAndamento = false

    /// O que a revisao assina agora: na edicao, primeiro o cancelamento, depois a ordem nova.
    private var atual: Operacao? {
        if let antes = cancelarAntes, !cancelou { return .cancelar(antes.ordem, antes.via) }
        return operacao
    }

    private var carteira: WalletMeta? { Sessao.shared.metadata.selectedWallet }
    private var motor: (any TradeEngine)? { chain.flatMap { TradeEngines.engine(for: $0) } }
    private var par: String { "\(chain?.id ?? "")|\(sell?.id ?? "")|\(buy?.id ?? "")" }

    // MARK: O pedido

    /// A carteira escolhida mudou: a cotacao era da outra. Sem rede ainda, a primeira com troca.
    /// Chamar com a trava.
    private func acompanharCarteira() {
        let id = carteira?.id
        if id != carteiraID {
            carteiraID = id
            cotacao = nil
            chaveDaCotacao = nil
            erro = nil
            impactoAceito = nil
            erroDoPlano = nil
        }
        if chain == nil, let primeira = TradeEngines.chains.first {
            reiniciar(primeira)
            versaoDoValor += 1
            versaoDoRecebido += 1
        }
    }

    /// Chamar com a trava.
    private func reiniciar(_ rede: Chain) {
        chain = rede
        // Prazo que a rede nova nao tem (o "ate cancelar" fora do XRP Ledger) volta aos 30 dias.
        if validade == nil, rede.family != .xrpl { validade = 30 * 86_400 }
        sell = .native(rede)
        buy = TokenRegistry.tokens.first { $0.chainID == rede.id && $0.isStablecoin }
        cotacao = nil
        chaveDaCotacao = nil
        emPartes = false
        erro = nil
        textoDoValor = ""
        limparRecebido()
        escolhido = nil
        erroDoPlano = nil
    }

    private func limparRecebido() {
        recebeExato = false
        textoDoRecebido = ""
        entradaCalculada = nil
        resolvendo = false
        abaixoDoAlvo = false
    }

    private var quantidade: BigUInt? {
        guard let sell else { return nil }
        if modo == .agora, recebeExato { return entradaCalculada }
        return Fmt.lerQuantidade(textoDoValor, casas: sell.decimals)
    }

    private var recebidoQuerido: BigUInt? {
        buy.flatMap { Fmt.lerQuantidade(textoDoRecebido, casas: $0.decimals) }
    }

    /// A tolerancia do pedido: a automatica (o par, o dia e a rede) ou a escolhida no controle. O
    /// impacto que a API do agregador informa nunca entra (auditoria 3, M1).
    private func toleranciaAgora() -> Int {
        guard automatica, let sell, let buy, let chain else { return tolerancia }
        let variacoes = [sell, buy].compactMap { Saldos.shared.variacao($0) }.map(abs)
        return AutoSlippage.basisPoints(sell: sell, buy: buy, chainID: chain.id, volatilityPercent: variacoes.max())
    }

    /// Com o recebido digitado, o valor a pagar e do app: a busca so recomeca quando o recebido,
    /// o par, a tolerancia ou a execucao (em partes) mudam.
    private var chave: String {
        let valor = recebeExato ? "recebe:\(textoDoRecebido)|\(emPartes)" : "paga:\(textoDoValor)"
        return "\(carteiraID?.uuidString ?? "")|\(modo.rawValue)|\(par)|\(valor)|\(toleranciaAgora())"
    }

    /// So a troca imediata cota; a ordem limite sai do preco digitado.
    private var podeCotar: Bool {
        guard modo == .agora, motor != nil, let carteira, !carteira.isWatchOnly, let chain, carteira.account(chain) != nil, sell != nil, buy != nil
        else { return false }
        if recebeExato { return !(recebidoQuerido ?? BigUInt()).isZero }
        return !(quantidade ?? BigUInt()).isZero
    }

    private var cotacaoAtual: TradeQuote? { chaveDaCotacao == chave ? cotacao : nil }

    /// O que a tela mostra em "Voce recebe": o minimo garantido da execucao escolhida, gravado na
    /// transacao ou na ordem assinada. Chega ele ou mais.
    private var minimoMostrado: BigUInt? {
        cotacao.map { $0.minimumOut(inParts: emPartes && $0.parts != nil) }
    }

    private var aceitouImpacto: Bool {
        guard let aceito = impactoAceito, let agora = cotacao?.priceImpactPercent else { return false }
        return agora <= aceito
    }

    /// A cotacao nova, pelo provedor que o dono escolheu se ele ainda esta na rodada.
    private func comEscolha(_ nova: TradeQuote) -> TradeQuote {
        guard let escolhido, escolhido.par == par else {
            self.escolhido = nil
            return nova
        }
        if nova.legs.count == 1, nova.legs[0].provider == escolhido.provedor { return nova }
        if let alternativa = nova.alternatives.first(where: { $0.provider == escolhido.provedor }), let trocada = nova.choosing(alternativa) {
            return trocada
        }
        self.escolhido = nil
        return nova
    }

    // MARK: Saldo

    private func posicao(_ ativo: Asset?) -> (quantidade: BigUInt, livre: BigUInt)? {
        guard let ativo, let rede = ativo.chain, let carteira else { return nil }
        let saldo = Saldos.shared.saldo(rede, carteira: carteira.id)
        if let item = saldo?.holdings.first(where: { $0.asset.id == ativo.id }) {
            return (item.amount, saldo?.available(item) ?? item.amount)
        }
        if let fora = saldo?.unlisted?.first(where: { $0.asset.id == ativo.id }) { return (fora.amount, fora.amount) }
        return nil
    }

    /// O que ainda falta vender nas ordens abertas do ativo. Editando, o da ordem editada volta a
    /// ser livre: ela sai antes.
    private func travado(_ ativo: Asset) -> BigUInt {
        var preso = Ordens.shared.travado(ativo)
        if let edicao, edicao.sell.id == ativo.id { preso = preso.subtractingReportingUnderflow(edicao.ordem.remainingSell) ?? BigUInt() }
        return preso
    }

    /// O que da para usar do ativo: o saldo menos a reserva da rede (XRP Ledger, Stellar) e menos o
    /// que ainda falta vender nas ordens abertas dele. Na troca imediata tambem: gastar o que uma
    /// ordem aberta ainda vai vender faria a ordem falhar quando o preco chegasse.
    private func livre(_ ativo: Asset?) -> BigUInt {
        guard let ativo, let item = posicao(ativo) else { return BigUInt() }
        return item.livre.subtractingReportingUnderflow(travado(ativo)) ?? BigUInt()
    }

    private var passou: Bool {
        guard let quantidade, let sell else { return false }
        return quantidade > livre(sell)
    }

    private func textoDoSaldo(_ ativo: Asset?) -> String? {
        guard let ativo else { return nil }
        let texto = Fmt.cripto(livre(ativo), casas: ativo.decimals, simbolo: ativo.symbol)
        if ativo.id == sell?.id, !travado(ativo).isZero { return preencher(Textos.t("Livre %@, o resto em ordens"), texto) }
        if let item = posicao(ativo), item.quantidade > item.livre { return preencher(Textos.t("Disponível %@"), texto) }
        return preencher(Textos.t("Saldo %@"), texto)
    }

    private var precoDeMercado: Double? {
        guard let sell, let buy, let deVenda = Saldos.shared.preco(sell), let deCompra = Saldos.shared.preco(buy), deVenda > 0, deCompra > 0 else { return nil }
        return deVenda / deCompra
    }

    // MARK: Mudar o pedido

    /// Aplica o que o dono mudou. Pedido novo (par, valor, rede ou tolerancia): o aceite do
    /// impacto era do outro, e a cotacao de antes fica na tela so ate a nova chegar.
    func definir(_ mudanca: JSONValue) {
        trava.withLock {
            acompanharCarteira()
            guard etapa == .formulario else { return }
            let antes = chave
            let textosAntes = (textoDoValor, textoDoRecebido, textoDoPreco)
            defer {
                if textoDoValor != textosAntes.0, mudanca["valor"] == nil { versaoDoValor += 1 }
                if textoDoRecebido != textosAntes.1, mudanca["recebe"] == nil { versaoDoRecebido += 1 }
                if textoDoPreco != textosAntes.2, mudanca["preco"] == nil { versaoDoPreco += 1 }
            }
            if let novo = mudanca["modo"]?.stringValue.flatMap(Modo.init(rawValue:)), novo != modo, edicao == nil {
                modo = novo
                // Outro modo: o recebido digitado era do anterior (o valor a pagar fica).
                limparRecebido()
            }
            if let id = mudanca["rede"]?.stringValue, edicao == nil, let rede = TradeEngines.chains.first(where: { $0.id == id }), rede.id != chain?.id {
                reiniciar(rede)
            }
            if let id = mudanca["vende"]?.stringValue, edicao == nil, let ativo = ativoDaLista(id), ativo.id != buy?.id {
                sell = ativo
                cotacao = nil
            }
            if let id = mudanca["compra"]?.stringValue, edicao == nil, let ativo = ativoDaLista(id), ativo.id != sell?.id {
                buy = ativo
                cotacao = nil
                // Outra moeda a receber: o recebido digitado era em outra unidade.
                if recebeExato {
                    limparRecebido()
                    if modo == .agora { textoDoValor = "" }
                }
            }
            if mudanca["inverter"]?.boolValue == true, edicao == nil {
                swap(&sell, &buy)
                textoDoValor = ""
                cotacao = nil
                limparRecebido()
            }
            if let texto = mudanca["valor"]?.stringValue {
                textoDoValor = String(texto.prefix(40))
                limparRecebido()
            }
            if let fracao = mudanca["fracao"]?.doubleValue, let sell {
                let total = livre(sell)
                let parte = fracao >= 1 ? total : total * BigUInt(UInt64((min(max(fracao, 0), 1) * 100).rounded())) / BigUInt(100)
                textoDoValor = Fmt.decimalSimples(parte, casas: sell.decimals)
                limparRecebido()
            }
            if let texto = mudanca["recebe"]?.stringValue {
                if modo == .limite {
                    digitarRecebidoDaOrdem(String(texto.prefix(40)))
                } else {
                    textoDoRecebido = String(texto.prefix(40))
                    recebeExato = true
                }
            }
            // Saiu de "Voce recebe" sem digitar nada: volta a valer o valor de entrada. Na troca
            // imediata, o valor a pagar era do app e sai junto.
            if mudanca["saiuDoRecebe"]?.boolValue == true, recebeExato, textoDoRecebido.isEmpty {
                limparRecebido()
                if modo == .agora { textoDoValor = "" }
            }
            if let bps = mudanca["tolerancia"]?.doubleValue {
                automatica = false
                tolerancia = min(max(Int((bps / 10).rounded()) * 10, 10), 1_000)
            }
            if mudanca["automatica"]?.boolValue == true { automatica = true }
            if let partes = mudanca["partes"]?.boolValue { emPartes = partes && cotacao?.parts != nil }
            if let aceita = mudanca["aceitarImpacto"]?.boolValue { impactoAceito = aceita ? cotacao?.priceImpactPercent : nil }
            if let provedor = mudanca["rota"]?.stringValue, let atual = cotacaoAtual,
               let alternativa = atual.alternatives.first(where: { $0.provider == provedor }), let trocada = atual.choosing(alternativa) {
                escolhido = (provedor, par)
                impactoAceito = nil
                cotacao = trocada
            }
            if let texto = mudanca["preco"]?.stringValue {
                textoDoPreco = String(texto.prefix(40))
                precoMudou()
            }
            if let percentual = mudanca["percentual"]?.doubleValue { definirAlvo(Int(percentual)) }
            if let aceita = mudanca["aceitarPreco"]?.boolValue { precoAceito = aceita ? textoDoPreco : nil }
            if let segundos = mudanca["validade"]?.doubleValue, let chain,
               Self.validades(chain).contains(where: { $0.segundos == segundos }) { validade = segundos }
            if mudanca["ateCancelar"]?.boolValue == true, let chain, Self.validades(chain).contains(where: { $0.segundos == nil }) { validade = nil }
            if mudanca["limparErroDoPlano"]?.boolValue == true { erroDoPlano = nil }
            preencherAlvo()
            guard chave != antes else { return }
            impactoAceito = nil
            erroDoPlano = nil
            erro = nil
            if !podeCotar {
                cotacao = nil
                chaveDaCotacao = nil
                cotando = false
                if recebeExato, modo == .agora {
                    entradaCalculada = nil
                    resolvendo = false
                    abaixoDoAlvo = false
                }
            } else if recebeExato {
                // O valor a pagar some ate a primeira resposta; nas recotacoes, fica o anterior.
                resolvendo = true
            }
        }
    }

    // MARK: Cotar

    /// Uma rodada de cotacao do pedido `pedida` (a `chave` que a interface viu). A interface chama
    /// de novo a cada 15 s enquanto o pedido nao muda. A resposta de um pedido que ja mudou nao
    /// entra, nem o erro dela.
    func cotar(_ pedida: String) async {
        struct Preparo: @unchecked Sendable {
            let motor: any TradeEngine, carteira: UUID, chain: Chain, conta: DerivedAccount, sell: Asset, buy: Asset
            let tolerancia: Int, exato: Bool, querido: BigUInt?, quantidade: BigUInt?, partes: Bool, estimativa: BigUInt?
        }
        let preparo = trava.withLock { () -> Preparo? in
            acompanharCarteira()
            guard etapa == .formulario, pedida == chave, podeCotar, let motor, let carteira, let chain, let conta = carteira.account(chain),
                  let sell, let buy else { return nil }
            cotando = true
            erro = nil
            let querido = recebidoQuerido
            return Preparo(motor: motor, carteira: carteira.id, chain: chain, conta: conta, sell: sell, buy: buy, tolerancia: toleranciaAgora(),
                           exato: recebeExato, querido: querido, quantidade: quantidade, partes: emPartes,
                           estimativa: querido.flatMap { estimativa(querido: $0, sell: sell, buy: buy) })
        }
        guard let p = preparo else { return }
        do {
            if p.exato, let querido = p.querido {
                let solucao = try await ExactOutSolver.solve(
                    want: querido, start: p.estimativa, unit: BigUInt.power(of: 10, p.sell.decimals), inParts: p.partes
                ) { valor in
                    try await p.motor.quote(TradeRequest(walletID: p.carteira, chain: p.chain, account: p.conta, sell: p.sell, buy: p.buy,
                                                         amountIn: valor, slippageBasisPoints: p.tolerancia))
                }
                trava.withLock {
                    guard pedida == chave else { return }
                    entradaCalculada = solucao.amountIn
                    if solucao.quote.parts == nil { emPartes = false }
                    cotacao = solucao.quote
                    chaveDaCotacao = chave
                    abaixoDoAlvo = !solucao.reached
                }
            } else if let quantidade = p.quantidade {
                let nova = try await p.motor.quote(TradeRequest(walletID: p.carteira, chain: p.chain, account: p.conta, sell: p.sell, buy: p.buy,
                                                                amountIn: quantidade, slippageBasisPoints: p.tolerancia))
                trava.withLock {
                    guard pedida == chave else { return }
                    if nova.parts == nil { emPartes = false }
                    cotacao = comEscolha(nova)
                    chaveDaCotacao = chave
                }
            }
        } catch {
            trava.withLock {
                guard pedida == chave else { return }
                cotacao = nil
                chaveDaCotacao = nil
                if p.exato { entradaCalculada = nil }
                erro = (error as? LocalizedError)?.errorDescription ?? preencher(
                    p.chain.id == "xrpl" ? Textos.t("Nenhum provedor troca %@ por %@ no %@ agora. Tente um valor menor ou outro par.")
                        : Textos.t("Nenhum provedor troca %@ por %@ na %@ agora. Tente um valor menor ou outro par."),
                    p.sell.symbol, p.buy.symbol, p.chain.name
                )
            }
        }
        trava.withLock {
            guard pedida == chave else { return }
            cotando = false
            resolvendo = false
        }
    }

    /// A partida da busca do valor a pagar: a cotacao de agora do mesmo par, ou o preco de
    /// mercado com a tolerancia. Sem nenhum dos dois, o `ExactOutSolver` sonda com uma unidade.
    /// Chamar com a trava.
    private func estimativa(querido: BigUInt, sell: Asset, buy: Asset) -> BigUInt? {
        if let cotacao, cotacao.sell.id == sell.id, cotacao.buy.id == buy.id {
            let recebe = cotacao.minimumOut(inParts: emPartes && cotacao.parts != nil)
            if !recebe.isZero { return ExactOutSolver.ceilDiv(cotacao.amountIn * querido, recebe) }
        }
        guard let taxa = precoDeMercado else { return nil }
        let margem = 1 + Double(toleranciaAgora()) / 10_000
        return Self.unidades(Saldos.decimal(querido, casas: buy.decimals) / taxa * margem, casas: sell.decimals)
    }

    /// Um valor decimal em unidades da rede, arredondado para cima.
    static func unidades(_ valor: Double, casas: Int) -> BigUInt? {
        guard valor.isFinite, valor > 0 else { return nil }
        let texto = String(format: "%.\(min(casas, 18))f", valor)
        guard let lido = Fmt.lerQuantidade(texto, casas: casas) else { return nil }
        return lido + BigUInt(1)
    }

    // MARK: Ordem limite

    /// Os prazos da ordem limite que a rede aceita. Na CoW, de 1 a 30 dias. No XRP Ledger a oferta
    /// pode ir sem prazo de verdade. Na Stellar nao ha prazo nenhum: a oferta fica ate executar ou o
    /// dono cancelar.
    static func validades(_ rede: Chain) -> [(segundos: TimeInterval?, titulo: String)] {
        let dias: [(segundos: TimeInterval?, titulo: String)] = [
            (86_400, Textos.t("1 dia")), (604_800, Textos.t("7 dias")), (2_592_000, Textos.t("30 dias")),
        ]
        switch rede.family {
        case .xrpl: return dias + [(nil, Textos.t("Até cancelar"))]
        case .stellar: return []
        default: return dias
        }
    }

    /// O preco no campo: sem separador de milhar, com seis algarismos que contam, por menor que seja
    /// (o de um token de fracao de centavo nao vira zero).
    static func textoDoPreco(_ valor: Double) -> String {
        guard valor.isFinite, valor > 0 else { return "" }
        let casas = max(2, min(30, 5 - Int(floor(log10(valor)))))
        var texto = String(format: "%.\(casas)f", valor)
        if texto.contains(".") {
            while texto.hasSuffix("0") { texto.removeLast() }
            if texto.hasSuffix(".") { texto.removeLast() }
        }
        return texto.replacingOccurrences(of: ".", with: NumberStyle.current.decimal)
    }

    /// "0,0₄123": quatro zeros ou mais depois da virgula viram um numero pequeno.
    static func zerosCompactos(_ texto: String) -> String? {
        let partes = texto.replacingOccurrences(of: ".", with: ",").split(separator: ",", omittingEmptySubsequences: false)
        guard partes.count == 2, partes[0].allSatisfy({ $0 == "0" }), partes[1].allSatisfy(\.isNumber) else { return nil }
        let zeros = partes[1].prefix { $0 == "0" }.count
        let resto = partes[1].dropFirst(zeros)
        guard zeros >= 4, !resto.isEmpty else { return nil }
        let subscritos = Array("₀₁₂₃₄₅₆₇₈₉")
        let pequeno = String(zeros).compactMap { $0.wholeNumberValue.map { subscritos[$0] } }
        return "0\(NumberStyle.current.decimal)0" + String(pequeno) + resto.prefix(8)
    }

    /// O minimo da ordem limite em unidades da rede, calculado do preco digitado sem passar pelo
    /// texto formatado: valor vendido vezes preco, arredondado para baixo. Com o recebido digitado,
    /// ele mesmo e o minimo.
    private var minimoDaOrdem: BigUInt? {
        if recebeExato {
            guard let quantidade, !quantidade.isZero, let querido = recebidoQuerido, !querido.isZero else { return nil }
            return querido
        }
        guard let quantidade, !quantidade.isZero, let sell, let buy, let preco = Fmt.lerQuantidade(textoDoPreco, casas: 36), !preco.isZero else {
            return nil
        }
        let saida = quantidade * preco * BigUInt.power(of: 10, buy.decimals) / (BigUInt.power(of: 10, sell.decimals) * BigUInt.power(of: 10, 36))
        return saida.isZero ? nil : saida
    }

    /// Onde o preco limite fica em relacao ao mercado (auditoria 2, M6). No XRP Ledger e na
    /// Stellar a ordem abaixo do mercado cruza o livro na hora e vai vendendo ate o preco digitado.
    private enum Conferencia { case ok, abaixo(Double), muitoAbaixo(Double), muitoAcima(Double), semMercado }

    private var conferencia: Conferencia {
        guard let minimo = minimoDaOrdem, let quantidade, !quantidade.isZero, let sell, let buy else { return .ok }
        let alvo = Saldos.decimal(minimo, casas: buy.decimals) / Saldos.decimal(quantidade, casas: sell.decimals)
        guard alvo > 0 else { return .ok }
        guard let mercado = precoDeMercado else { return .semMercado }
        let razao = alvo / mercado
        if razao < 0.5 { return .muitoAbaixo((1 - razao) * 100) }
        if razao < 0.98 { return .abaixo((1 - razao) * 100) }
        if razao > 4 { return .muitoAcima(razao) }
        return .ok
    }

    private var precoConfirmado: Bool {
        switch conferencia {
        case .ok, .muitoAcima: return true
        case .muitoAbaixo: return false
        case .abaixo, .semMercado: return precoAceito == textoDoPreco
        }
    }

    /// O preco de agora no campo, mais `percentual`. Chamar com a trava.
    private func definirAlvo(_ percentual: Int) {
        guard let taxa = precoDeMercado else { return }
        let texto = Self.textoDoPreco(taxa * (1 + Double(percentual) / 100))
        textoDoPreco = texto
        precoAuto = percentual == 0 ? texto : nil
        precoMudou()
    }

    /// O preco de agora no campo, se ele esta vazio ou ainda com o que o app preencheu, quando o
    /// par muda ou o preco de mercado chega. Chamar com a trava.
    private func preencherAlvo() {
        let chaveAgora = "\(par)|\(modo.rawValue)|\(precoDeMercado != nil)"
        guard chaveAgora != chaveDoAlvo else { return }
        chaveDoAlvo = chaveAgora
        guard modo == .limite, textoDoPreco.isEmpty || textoDoPreco == precoAuto else { return }
        let antes = textoDoPreco
        definirAlvo(0)
        if textoDoPreco != antes { versaoDoPreco += 1 }
    }

    /// "Voce recebe" digitado na ordem limite. Com valor vendido, o preco sai da conta (como na
    /// CoW); sem ele, sai o valor vendido, pelo preco do campo. Chamar com a trava.
    private func digitarRecebidoDaOrdem(_ texto: String) {
        if !recebeExato { deriva = (quantidade?.isZero ?? true) ? .valor : .preco }
        textoDoRecebido = texto
        recebeExato = true
        derivar()
    }

    private func derivar() {
        guard recebeExato, let querido = recebidoQuerido, !querido.isZero, let sell, let buy else { return }
        let valorQuerido = Saldos.decimal(querido, casas: buy.decimals)
        switch deriva {
        case .preco:
            guard let quantidade, !quantidade.isZero else { return }
            textoDoPreco = Self.textoDoPreco(valorQuerido / Saldos.decimal(quantidade, casas: sell.decimals))
            precoAuto = nil
            versaoDoPreco += 1
        case .valor:
            guard let preco = Double(textoDoPreco.replacingOccurrences(of: ",", with: ".")), preco > 0, preco.isFinite,
                  let valor = Self.unidades(valorQuerido / preco, casas: sell.decimals) else { return }
            textoDoValor = Fmt.decimalSimples(ExactOutSolver.roundUp(valor), casas: sell.decimals)
            versaoDoValor += 1
        }
    }

    /// O preco mudou (digitado, chip ou o de agora). Se o valor vendido acompanha o recebido
    /// digitado, ele refaz a conta; se era o preco que acompanhava, o recebido volta a sair do preco.
    private func precoMudou() {
        guard recebeExato, modo == .limite else { return }
        if deriva == .valor { derivar() } else {
            limparRecebido()
            versaoDoRecebido += 1
        }
    }

    /// "Voce recebe" na ordem limite, calculado do preco.
    private var recebidoDaOrdem: String {
        guard let quantidade, let sell, let buy, let preco = Double(textoDoPreco.replacingOccurrences(of: ",", with: ".")), preco > 0 else { return "" }
        return Fmt.agrupado(Saldos.decimal(quantidade, casas: sell.decimals) * preco, casas: min(buy.decimals, 6), aparar: true)
    }

    // MARK: O botao

    /// O titulo e se o botao principal libera, como o rodape do iOS.
    private var botao: (titulo: String, ligado: Bool) {
        guard let motor else { return (Textos.t("Troca indisponível nesta rede"), false) }
        guard let quantidade, !quantidade.isZero else {
            if recebeExato, resolvendo { return (Textos.t("Buscando o melhor preço"), false) }
            return (Textos.t("Digite um valor"), false)
        }
        if passou { return (preencher(Textos.t("Saldo de %@ insuficiente"), sell?.symbol ?? ""), false) }
        if modo == .limite {
            if case .muitoAbaixo = conferencia { return (Textos.t("Preço muito abaixo do mercado"), false) }
            return (edicao != nil ? Textos.t("Revisar a mudança") : Textos.t("Revisar ordem"),
                    motor.supportsLimitOrders && minimoDaOrdem != nil && precoConfirmado)
        }
        guard let atual = cotacaoAtual, !cotando || cotacao != nil else { return (Textos.t("Buscando o melhor preço"), false) }
        if emPartes, atual.parts != nil { return (Textos.t("Revisar troca em partes"), true) }
        let nivel = PriceImpact.level(atual.priceImpactPercent)
        if nivel == .blocked { return (Textos.t("Impacto no preço alto demais"), false) }
        let titulo = atual.needsApproval ? preencher(Textos.t("Autorizar %@ e trocar"), sell?.symbol ?? "") : Textos.t("Revisar troca")
        return (titulo, nivel == .confirm ? aceitouImpacto : true)
    }

    // MARK: Revisar

    /// Congela o pedido e monta o plano: o motor recota, valida e simula de novo. O plano que nao
    /// sai volta para o formulario com o erro.
    func revisar() async {
        let numero = trava.withLock { () -> Int? in
            acompanharCarteira()
            erroDoPlano = nil
            guard etapa == .formulario, botao.ligado, let carteira, !carteira.isWatchOnly, let chain, let conta = carteira.account(chain),
                  let sell, let buy, let quantidade, !quantidade.isZero else { return nil }
            switch modo {
            case .agora:
                guard let cotada = cotacaoAtual, cotada.amountIn == quantidade, cotada.sell.id == sell.id, cotada.buy.id == buy.id else { return nil }
                let partes = emPartes && cotada.parts != nil
                operacao = .troca(TradeRequest(walletID: carteira.id, chain: chain, account: conta, sell: sell, buy: buy, amountIn: quantidade,
                                               slippageBasisPoints: toleranciaAgora(), inParts: partes), cotada)
                cancelarAntes = nil
            case .limite:
                guard let minimo = minimoDaOrdem else { return nil }
                operacao = .limite(LimitOrderRequest(walletID: carteira.id, chain: chain, account: conta, sell: sell, buy: buy, amountIn: quantidade,
                                                     minimumOut: minimo, validFor: validade))
                // Editando: a revisao cancela a ordem atual antes de criar esta.
                cancelarAntes = edicao.flatMap { $0.ordem.chain.id == chain.id ? ($0.ordem, $0.via) : nil }
            }
            ativosDaRevisao = (sell, buy)
            valorEmMoeda = Saldos.shared.preco(sell).map { Saldos.decimal(quantidade, casas: sell.decimals) * $0 }
            return comecarRevisao()
        }
        guard let numero else { return }
        avisar()
        await montar(numero)
    }

    /// Cancelar uma ordem aberta: a revisao do cancelamento, sem formulario.
    func cancelar(_ ordem: OpenOrder) async {
        let numero = trava.withLock { () -> Int? in
            acompanharCarteira()
            guard etapa == .formulario, carteira?.isWatchOnly == false, let via = Ordens.maisSeguro(ordem.cancellations) else { return nil }
            operacao = .cancelar(ordem, via)
            cancelarAntes = nil
            ativosDaRevisao = (Ordens.resolver(ordem.sellAssetID, listado: ordem.sell, rede: ordem.chain),
                               Ordens.resolver(ordem.buyAssetID, listado: ordem.buy, rede: ordem.chain))
            valorEmMoeda = nil
            return comecarRevisao()
        }
        guard let numero else { return }
        avisar()
        await montar(numero)
    }

    /// Chamar com a trava.
    private func comecarRevisao() -> Int {
        cancelou = false
        plano = nil
        erroDaRevisao = nil
        falhaDaMontagem = nil
        ids = []
        assinadoIncerto = nil
        detalheIncerto = nil
        situacao = .pending
        andamento = nil
        semAndamento = false
        rodada += 1
        etapa = .montando
        return rodada
    }

    /// Monta de novo depois de o plano nao sair (o tentar de novo da revisao).
    func remontar() async {
        let numero = trava.withLock { () -> Int? in
            guard etapa == .montando, falhaDaMontagem != nil else { return nil }
            falhaDaMontagem = nil
            return rodada
        }
        guard let numero else { return }
        avisar()
        await montar(numero)
    }

    private func montar(_ numero: Int) async {
        let preparo = trava.withLock { () -> (Operacao, WalletMeta)? in
            guard rodada == numero, etapa == .montando, let atual, let carteira else { return nil }
            return (atual, carteira)
        }
        guard let (operacao, carteira) = preparo else { return }
        let rede = operacao.rede
        guard let motor = TradeEngines.engine(for: rede), let conta = carteira.account(rede) else {
            trava.withLock { falhou(Textos.t("Esta carteira não tem conta nesta rede.")) }
            return
        }
        // A fila de nonces EVM desta conta, sem o que a rede ja confirmou, entra no pedido: o
        // planejador sabe o que este aparelho ja transmitiu.
        await FilaDeNonces.podar(carteira: carteira.id, rede: rede, endereco: conta.address)
        let fila = FilaDeNonces.fila(Sessao.shared.metadata, carteira: carteira.id, rede: rede, endereco: conta.address)
        do {
            let novo: SigningPlan
            switch operacao {
            case .troca(let r, let cotada):
                novo = try await motor.plan(TradeRequest(walletID: r.walletID, chain: r.chain, account: r.account, sell: r.sell, buy: r.buy,
                                                         amountIn: r.amountIn, slippageBasisPoints: r.slippageBasisPoints, nonceQueue: fila,
                                                         inParts: r.inParts), quote: cotada)
            case .limite(let r):
                novo = try await motor.planLimitOrder(LimitOrderRequest(walletID: r.walletID, chain: r.chain, account: r.account, sell: r.sell,
                                                                        buy: r.buy, amountIn: r.amountIn, minimumOut: r.minimumOut,
                                                                        validFor: r.validFor, nonceQueue: fila))
            case .cancelar(let ordem, let via):
                novo = try await motor.planCancel(ordem, walletID: carteira.id, account: conta, via: via, nonceQueue: fila)
            }
            trava.withLock {
                guard rodada == numero, etapa == .montando else { return }
                guard confere(novo) else {
                    falhou(Textos.t("O plano montado não confere com a troca pedida. Nada foi assinado."))
                    return
                }
                plano = novo
                etapa = .revisao
            }
        } catch {
            if (error as? SendEngineError)?.isLocalNonceQueueAhead == true {
                FilaDeNonces.esquecer(carteira: carteira.id, rede: rede, endereco: conta.address)
            }
            trava.withLock {
                guard rodada == numero, etapa == .montando else { return }
                falhou((error as? LocalizedError)?.errorDescription ?? Textos.t("Não foi possível montar agora. Tente de novo."))
            }
        }
    }

    /// O plano nao saiu. Na troca e na ordem nova, antes de qualquer etapa assinada, o erro volta
    /// para o formulario; no cancelamento (e depois dele, na edicao), fica na revisao. Chamar com a
    /// trava.
    private func falhou(_ mensagem: String) {
        if atual?.cancela == true || cancelou {
            falhaDaMontagem = mensagem
            return
        }
        erroDoPlano = mensagem
        etapa = .formulario
        operacao = nil
        cancelarAntes = nil
        plano = nil
    }

    /// Desta carteira, desta rede e do tipo pedido; vende o ativo pedido, nunca mais que o valor;
    /// garante pelo menos o minimo mostrado do ativo comprado; e o que entra vai para a propria
    /// conta (auditoria 2, M1). O cancelamento nao move valor. Chamar com a trava.
    private func confere(_ plano: SigningPlan) -> Bool {
        guard let atual, let carteira, plano.walletID == carteira.id, plano.chain.id == atual.rede.id else { return false }
        do {
            switch atual {
            case .troca(let r, let cotada):
                guard plano.review.kind == .swap, r.walletID == carteira.id else { return false }
                try PlanIntentCheck.trade(plano.review, sell: r.sell, amountIn: r.amountIn, buy: r.buy, minimumOut: cotada.minimumOut(inParts: r.inParts),
                                          owner: r.account.address, chain: r.chain)
            case .limite(let r):
                guard plano.review.kind == .limitOrder, r.walletID == carteira.id else { return false }
                try PlanIntentCheck.trade(plano.review, sell: r.sell, amountIn: r.amountIn, buy: r.buy, minimumOut: r.minimumOut,
                                          owner: r.account.address, chain: r.chain)
            case .cancelar:
                guard plano.review.kind == .cancelOrder, plano.review.outgoing == nil || plano.review.outgoing?.amount.isZero == true else { return false }
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: Assinar e transmitir

    /// O plano confere de novo, e plano vencido monta de novo. Carteira com passphrase: ela chega
    /// antes da biometria ou do PIN e o assinador confere. Cancelar uma ordem nao tira valor: nao
    /// pede a passphrase.
    func assinar(_ credencial: Credencial, passphrase: SecureBytes?, folga: Int?) async throws {
        defer { passphrase?.wipe() }
        let preparo = trava.withLock { () -> (SigningPlan, any TradeEngine, Int, Bool, Bool)? in
            erroDaRevisao = nil
            guard etapa == .revisao, let plano, let atual, let motor = TradeEngines.engine(for: plano.chain) else { return nil }
            guard confere(plano) else {
                erroDaRevisao = Textos.t("O plano montado não confere com a troca pedida. Nada foi assinado.")
                return nil
            }
            if plano.isExpired() {
                self.plano = nil
                etapa = .montando
                return (plano, motor, rodada, true, atual.cancela)
            }
            return (plano, motor, rodada, false, atual.cancela)
        }
        guard let (plano, motor, numero, vencido, cancela) = preparo else {
            credencial.zerar()
            return
        }
        if vencido {
            credencial.zerar()
            avisar()
            await montar(numero)
            trava.withLock { if rodada == numero, etapa == .revisao { erroDaRevisao = Textos.t("Os dados da rede venceram. Confira de novo.") } }
            return
        }
        let dona = Sessao.shared.metadata.wallets.first { $0.id == plano.walletID }
        if !cancela, PortaDaPassphrase.precisa(dona), passphrase == nil {
            credencial.zerar()
            throw Nucleo.Falha(erro: "envio.pedePassphrase")
        }
        let conferir = !cancela && PortaDaPassphrase.pede(dona) ? passphrase : nil
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
        await transmitir(assinado, plano: plano, motor: motor, numero: numero)
    }

    /// Envia o que foi assinado. Erro aqui nao quer dizer que nada saiu: a resposta pode ter se
    /// perdido depois de a rede (ou a CoW) receber. A tela diz isso e so oferece enviar de novo os
    /// mesmos bytes, que tem o mesmo id e nao pagam duas vezes.
    private func transmitir(_ assinado: [SignedTransaction], plano: SigningPlan, motor: any TradeEngine, numero: Int) async {
        let operacao = trava.withLock { () -> Operacao? in
            guard rodada == numero, let atual else { return nil }
            etapa = .enviando
            return atual
        }
        guard let operacao else { return }
        if let conta = Sessao.shared.metadata.wallets.first(where: { $0.id == plano.walletID })?.account(plano.chain) {
            FilaDeNonces.anotar(carteira: plano.walletID, rede: plano.chain, endereco: conta.address, plano: plano, assinado: assinado)
        }
        avisar()
        do {
            let novos = try await motor.submit(assinado, plan: plano)
            switch operacao {
            case .troca(let r, _): Self.lembrar([r.sell, r.buy])
            case .limite(let r):
                Self.lembrar([r.sell, r.buy])
                // Os avisos de 24 horas antes de vencer e de executada (fora a carteira com passphrase).
                if let uid = novos.first, let bytes = Hex.decode(uid), let vence = CoWProtocol.validTo(ofUID: bytes),
                   Sessao.shared.metadata.wallets.first(where: { $0.id == r.walletID })?.hasPassphrase == false {
                    VigiaDeOrdens.acompanhar(id: uid, rede: r.chain, venceEm: Date(timeIntervalSince1970: TimeInterval(vence)))
                }
            case .cancelar(let ordem, _):
                Ordens.shared.marcarCancelando(ordem.id)
                VigiaDeOrdens.esquecer(ordem.id)
            }
            // Edicao: o cancelamento saiu; a etapa 2 monta a ordem nova na mesma revisao.
            let segue = trava.withLock { () -> Bool in
                assinadoIncerto = nil
                detalheIncerto = nil
                if cancelarAntes != nil, !cancelou, operacao.cancela {
                    cancelou = true
                    self.plano = nil
                    ids = []
                    etapa = .montando
                    return true
                }
                ids = novos
                etapa = .enviada
                return false
            }
            if segue {
                avisar()
                await montar(numero)
            }
        } catch {
            trava.withLock {
                ids = assinado.map(\.id)
                assinadoIncerto = assinado
                detalheIncerto = (error as? LocalizedError)?.errorDescription
                etapa = .incerta
            }
        }
    }

    /// Os tokens fora da lista que ja passaram por uma troca: as ordens abertas resolvem o nome
    /// deles depois (o `TradedAssets` do iOS).
    private static func lembrar(_ ativos: [Asset]) {
        let fora = ativos.filter { $0.origin != nil }
        guard !fora.isEmpty else { return }
        try? Sessao.shared.alterar { metadata in
            var lista = metadata.tradedAssets ?? []
            for ativo in fora where !lista.contains(where: { $0.id == ativo.id }) { lista.insert(ativo, at: 0) }
            metadata.tradedAssets = Array(lista.prefix(50))
        }
    }

    func retransmitir() async {
        let preparo = trava.withLock { () -> ([SignedTransaction], SigningPlan, any TradeEngine, Int)? in
            guard etapa == .incerta, let assinadoIncerto, let plano, let motor = TradeEngines.engine(for: plano.chain) else { return nil }
            return (assinadoIncerto, plano, motor, rodada)
        }
        guard let (assinado, plano, motor, numero) = preparo else { return }
        await transmitir(assinado, plano: plano, motor: motor, numero: numero)
    }

    /// A troca pela CoW: o id devolvido e o UID da ordem, e a tela acompanha o preenchimento. A
    /// ordem limite nao: ela espera o preco, e o andamento fica em Ordens abertas.
    private var ordemDaCoW: Bool {
        guard case .troca = atual else { return false }
        return plano?.transactions.last is EIP712ValidatedMessage
    }

    /// Pergunta pelo que ja saiu: na ordem da CoW, o preenchimento; na transacao, a confirmacao.
    /// Na troca incerta, a rede (ou a CoW) conhecer o que foi assinado quer dizer que saiu.
    func acompanhar() async {
        let (plano, ids, cow) = trava.withLock { (plano, ids, ordemDaCoW) }
        guard let plano, let ultimo = ids.last,
              let conta = Sessao.shared.metadata.wallets.first(where: { $0.id == plano.walletID })?.account(plano.chain) else { return }
        if cow {
            guard let motor = TradeEngines.engine(for: plano.chain), let uid = ids.first else { return }
            do {
                let lido = try await motor.orderProgress(id: uid, account: conta)
                trava.withLock {
                    andamento = lido
                    semAndamento = false
                    if etapa == .incerta {
                        assinadoIncerto = nil
                        etapa = .enviada
                    }
                }
            } catch {
                trava.withLock { semAndamento = true }
            }
            return
        }
        guard plano.transactions.last is EIP712ValidatedMessage == false, let envio = SendEngines.engine(for: plano.chain) else { return }
        let agora = await envio.status(ultimo, chain: plano.chain)
        trava.withLock {
            situacao = agora
            if etapa == .incerta, case .confirmed = agora {
                assinadoIncerto = nil
                etapa = .enviada
            }
        }
    }

    /// Fecha a revisao. Transmitindo, nao fecha. Devolve se algo saiu (a troca, a ordem ou o
    /// cancelamento, ou a etapa 1 da edicao): o formulario volta limpo e as ordens releem.
    @discardableResult
    func fechar() -> Bool {
        trava.withLock {
            guard etapa != .enviando else { return false }
            let saiu = etapa == .enviada || etapa == .incerta || cancelou
            let formulario = operacao.map { !$0.cancela } ?? false
            etapa = .formulario
            rodada += 1
            plano = nil
            operacao = nil
            cancelarAntes = nil
            cancelou = false
            erroDaRevisao = nil
            falhaDaMontagem = nil
            if saiu, formulario {
                textoDoValor = ""
                textoDoPreco = ""
                precoAuto = nil
                chaveDoAlvo = nil
                versaoDoValor += 1
                versaoDoRecebido += 1
                versaoDoPreco += 1
                limparRecebido()
                cotacao = nil
                chaveDaCotacao = nil
                impactoAceito = nil
                edicao = nil
                preencherAlvo()
            }
            return saiu
        }
    }

    // MARK: As outras telas

    /// Editar uma ordem abre a tela propria: so a ordem limite, com os valores dela (o que falta
    /// vender, o preco dela e o prazo mais perto do que restava).
    static func editar(_ ordem: OpenOrder) throws -> Troca {
        guard let via = Ordens.maisSeguro(ordem.cancellations),
              let sell = Ordens.resolver(ordem.sellAssetID, listado: ordem.sell, rede: ordem.chain),
              let buy = Ordens.resolver(ordem.buyAssetID, listado: ordem.buy, rede: ordem.chain),
              TradeEngines.engine(for: ordem.chain)?.supportsLimitOrders == true else { throw Nucleo.Falha(erro: "troca.naoEdita") }
        let troca = Troca(alvo: "edicao")
        troca.trava.withLock {
            troca.acompanharCarteira()
            troca.reiniciar(ordem.chain)
            troca.modo = .limite
            troca.sell = sell
            troca.buy = buy
            troca.textoDoValor = Fmt.decimalSimples(ordem.remainingSell, casas: sell.decimals)
            let vendido = Saldos.decimal(ordem.remainingSell, casas: sell.decimals)
            if vendido > 0 {
                troca.textoDoPreco = textoDoPreco(Saldos.decimal(ordem.minimumBuy, casas: buy.decimals) / vendido)
                troca.precoAuto = nil
            }
            let opcoes = validades(ordem.chain)
            if let vence = ordem.expiresAt {
                let resta = vence.timeIntervalSinceNow
                troca.validade = opcoes.compactMap(\.segundos).first { $0 >= resta } ?? opcoes.compactMap(\.segundos).last ?? troca.validade
            } else if opcoes.contains(where: { $0.segundos == nil }) {
                troca.validade = nil
            }
            troca.edicao = Edicao(ordem: ordem, via: via, sell: sell, buy: buy)
            troca.chaveDoAlvo = "\(troca.par)|\(troca.modo.rawValue)|\(troca.precoDeMercado != nil)"
            troca.versaoDoValor += 1
            troca.versaoDoPreco += 1
        }
        travaDasOutras.withLock { outras["edicao"] = troca }
        return troca
    }

    static func paraCancelar() -> Troca {
        let troca = Troca(alvo: "cancelamento")
        travaDasOutras.withLock { outras["cancelamento"] = troca }
        return troca
    }

    /// A tela fechou: a troca dela sai da memoria (a da aba fica).
    static func encerrar(_ alvo: String) {
        guard alvo != "aba" else { return }
        travaDasOutras.withLock { outras[alvo] = nil }
    }

    // MARK: Os atalhos

    /// Um ativo pelo id: as nativas, a lista conferida, as moedas custom e os tokens fora da lista
    /// que a carteira tem (sem suspeita).
    private func acharAtivo(_ id: String) -> Asset? {
        if let rede = Chain.all.first(where: { Asset.native($0).id == id }) { return .native(rede) }
        if let listado = TokenRegistry.tokens.first(where: { $0.id == id }) { return listado }
        if let custom = Sessao.shared.metadata.customTokens.first(where: { $0.id == id }) { return custom }
        guard let carteira else { return nil }
        for rede in Chain.all {
            if let fora = Saldos.shared.saldo(rede, carteira: carteira.id)?.unlisted?.first(where: { $0.asset.id == id && !$0.isSuspicious }) {
                return fora.asset
            }
        }
        return nil
    }

    /// O que pode ir para a troca: a lista conferida em toda rede com troca; fora da lista, so nas
    /// redes EVM e na Solana (o `TradeAccess` do iOS).
    static func permite(_ ativo: Asset) -> Bool {
        guard let rede = ativo.chain, TradeEngines.engine(for: rede) != nil else { return false }
        return ativo.origin == nil || rede.family == .evm || rede.family == .solana
    }

    /// "Trocar", "Vender" e "Comprar" de outras telas: a aba abre na troca imediata, na rede do
    /// ativo, com ele de um lado e uma stablecoin (ou a nativa) do outro.
    func preparar(ativo id: String, vende: Bool) throws {
        try trava.withLock {
            acompanharCarteira()
            guard etapa == .formulario, let ativo = acharAtivo(id), Self.permite(ativo), let rede = ativo.chain else {
                throw Nucleo.Falha(erro: "troca.indisponivel")
            }
            modo = .agora
            reiniciar(rede)
            versaoDoValor += 1
            versaoDoRecebido += 1
            let estavel = TokenRegistry.tokens.first { $0.chainID == rede.id && $0.isStablecoin && $0.id != ativo.id }
            if vende {
                sell = ativo
                if buy?.id == ativo.id { buy = estavel ?? .native(rede) }
            } else {
                buy = ativo
                if sell?.id == ativo.id { sell = estavel }
            }
        }
    }

    /// Todos os ativos da lista podem ir para a troca (o "Trocar" do detalhe do ativo).
    func permite(_ ids: [String]) -> Bool {
        trava.withLock {
            !ids.isEmpty && ids.allSatisfy { id in acharAtivo(id).map(Self.permite) ?? false }
        }
    }

    struct DaMoeda: Encodable { let comprar: String?; let vender: String? }

    /// O detalhe da moeda no Mercado: comprar pela primeira rede com troca que tem a moeda; vender
    /// o que a carteira tem dela, na rede onde ha mais.
    func daMoeda(_ coingecko: String) -> DaMoeda {
        var comprar: Asset?
        for rede in TradeEngines.chains {
            if rede.coingeckoID == coingecko { comprar = .native(rede); break }
            if let token = TokenRegistry.tokens.first(where: { $0.chainID == rede.id && $0.coingeckoID == coingecko }) { comprar = token; break }
        }
        let carteira = trava.withLock { carteira }
        let vender = carteira.flatMap { carteira in
            Saldos.shared.posicoes(carteira: carteira.id)
                .filter { $0.asset.coingeckoID == coingecko && !$0.amount.isZero && Self.permite($0.asset) }
                .max { Saldos.decimal($0.amount, casas: $0.asset.decimals) < Saldos.decimal($1.amount, casas: $1.asset.decimals) }?.asset
        }
        return DaMoeda(comprar: comprar?.id, vender: vender?.id)
    }

    // MARK: A lista de tokens

    /// O que pode ir para a troca nesta rede: a lista conferida e, nas redes EVM e na Solana, o
    /// token fora da lista que a carteira tem (sem suspeita) e a moeda que o dono adicionou (o
    /// `TradeAccess` do iOS). Chamar com a trava.
    private func candidatos() -> (conferidas: [Asset], fora: [Asset]) {
        guard let chain else { return ([], []) }
        let conferidas = TokenRegistry.assets(on: chain)
        guard (chain.family == .evm || chain.family == .solana), TradeEngines.engine(for: chain) != nil, let carteira else { return (conferidas, []) }
        let custom = Sessao.shared.metadata.customTokens.filter { $0.chainID == chain.id }
        let tidos = (Saldos.shared.saldo(chain, carteira: carteira.id)?.unlisted ?? []).filter { !$0.isSuspicious }.map(\.asset)
        var vistos = Set<String>()
        return (conferidas, (custom + tidos).filter { vistos.insert($0.id).inserted })
    }

    private func ativoDaLista(_ id: String) -> Asset? {
        let (conferidas, fora) = candidatos()
        return conferidas.first { $0.id == id } ?? fora.first { $0.id == id }
    }

    struct Opcao: Encodable {
        let ativo: Estado.Ativo
        let quantidade: String?
        let fora: Bool
    }

    /// Do maior saldo para o menor, nas duas secoes: pelo valor na moeda local quando ha preco,
    /// senao pela quantidade; sem saldo, depois, na ordem da lista. Vendendo, so o que tem saldo.
    func opcoes(vendendo: Bool) -> [Opcao] {
        trava.withLock {
            acompanharCarteira()
            let excluir = vendendo ? buy?.id : sell?.id
            let (conferidas, fora) = candidatos()
            func ordenar(_ ativos: [Asset], fora: Bool) -> [Opcao] {
                let pesados = ativos.enumerated().filter { $0.element.id != excluir }.map { indice, ativo -> (Asset, Int, Double, Double, BigUInt?) in
                    let tido = posicao(ativo)?.quantidade
                    let quantia = tido.map { Saldos.decimal($0, casas: ativo.decimals) } ?? 0
                    let preco = ativo.origin == nil ? (Saldos.shared.preco(ativo) ?? 0) : 0
                    return (ativo, indice, quantia * preco, quantia, tido)
                }
                let mostrados = vendendo ? pesados.filter { $0.3 > 0 } : pesados
                return mostrados.sorted { a, b in
                    if (a.3 > 0) != (b.3 > 0) { return a.3 > 0 }
                    if a.2 != b.2 { return a.2 > b.2 }
                    if a.3 > 0, a.3 != b.3 { return a.3 > b.3 }
                    return a.1 < b.1
                }.map { Opcao(ativo: Self.dto($0.0), quantidade: $0.4.flatMap { $0.isZero ? nil : $0.decimalString }, fora: fora) }
            }
            return ordenar(conferidas, fora: false) + ordenar(fora, fora: true)
        }
    }

    // MARK: O retrato

    struct Estado: Encodable {
        struct Rede: Encodable { let id: String; let nome: String; let coingecko: String }
        struct Ativo: Encodable {
            let id: String, simbolo: String, nome: String, rede: String, redeCoingecko: String, coingecko: String?, casas: Int
            let conferido: Bool, custom: Bool, preco: Double?
        }
        struct Perna: Encodable { let provedor: String; let fracao: Double; let recebe: String }
        struct Alternativa: Encodable { let provedor: String; let garante: String; let diferenca: String?; let usar: Bool }
        struct Partes: Encodable { let deUmaVez: String; let emPartes: String; let ganho: String?; let notaDeUmaVez: String }
        struct Cotacao: Encodable {
            let atual: Bool
            let garantido: String
            let preco: String
            let precoInvertido: String
            let rota: String
            let provedores: [String]
            let taxaDaRede: Double?
            let garantidoTexto: String
            let doProvedor: String
            let prazo: String?
            let impacto: Double?
            let nivel: String
            let partes: Partes?
            let tituloDaRota: String
            let pernas: [Perna]
            let explicacao: String
            let alternativas: [Alternativa]
        }
        struct Validade: Encodable { let segundos: Double?; let titulo: String }
        struct ConferenciaDoPreco: Encodable { let texto: String; let forte: Bool; let confirmacao: String?; let confirmado: Bool }
        struct Limite: Encodable {
            let preco: String
            let versaoDoPreco: Int
            let precoCompacto: String?
            let rotuloDoPreco: String
            let recebido: String
            let calculado: Bool
            let validades: [Validade]
            let validade: Double?
            let semPrazo: String?
            let custodia: String?
            let conferencia: ConferenciaDoPreco?
            let editando: String?
        }
        struct Linha: Encodable { let rotulo: String; let valor: String }
        struct Revisao: Encodable {
            let titulo: String
            let sai: String?
            let entra: String?
            let enderecos: [Linha]
            let linhas: [Linha]
            let avisos: [String]
            let transacoes: Int
            let nota: String
            let erro: String?
        }
        /// Os textos de cada etapa, pelo que a revisao assina: troca, ordem limite ou cancelamento.
        struct Frases: Encodable {
            let tipo: String
            let montando: String
            let naoMontou: String
            let confirmar: String
            let enviando: String
            let feito: String
            let mensagemDoFeito: String
            let incerto: String
            let passo: String?
            let explorador: Bool
        }
        struct Resultado: Encodable {
            let id: String?, explorador: String, url: String?, situacao: String, detalhe: String?, ordem: Bool
        }
        struct Andamento: Encodable { let estado: String; let fracao: Double; let recebido: String; let garantido: String }

        let alvo: String
        let carteira: String?
        let observa: Bool
        let modo: Modo
        let temLimite: Bool
        let redes: [Rede]
        let rede: Rede?
        let vende: Ativo?
        let compra: Ativo?
        let valor: String
        let versaoDoValor: Int
        let entrada: String?
        let recebeExato: Bool
        let recebido: String
        let versaoDoRecebido: Int
        let resolvendo: Bool
        let abaixoDoAlvo: String?
        let saldo: String?
        let saldoDaCompra: String?
        let temSaldo: Bool
        let passou: Bool
        let tolerancia: Int
        let automatica: Bool
        let toleranciaAuto: Int
        let chave: String
        let podeCotar: Bool
        let cotando: Bool
        let emPartes: Bool
        let cotacao: Cotacao?
        let limite: Limite?
        let erro: String?
        let erroDoPlano: String?
        let naoVerificado: String?
        let impactoAceito: Bool
        let botao: String
        let botaoLigado: Bool
        let protecao: Bool
        let etapa: Etapa
        let frases: Frases?
        let revisaoVende: Ativo?
        let revisaoCompra: Ativo?
        let falhaDaMontagem: String?
        /// Edicao: a etapa 1 (cancelar a ordem atual) ja saiu.
        let cancelou: Bool
        let revisao: Revisao?
        let resultado: Resultado?
        let andamento: Andamento?
        let semAndamento: Bool
        let detalheIncerto: String?
        let valorEmMoeda: Double?
    }

    static func dto(_ ativo: Asset) -> Estado.Ativo {
        Estado.Ativo(
            id: ativo.id, simbolo: ativo.symbol, nome: ativo.name, rede: ativo.chainID, redeCoingecko: ativo.chain?.coingeckoID ?? "",
            coingecko: ativo.coingeckoID, casas: ativo.decimals, conferido: ativo.isVerified, custom: ativo.isCustom,
            preco: Saldos.shared.preco(ativo)
        )
    }

    func estado() -> Estado {
        trava.withLock {
            acompanharCarteira()
            // O preco de mercado pode ter chegado depois: a ordem limite preenche o de agora.
            preencherAlvo()
            return montarEstado()
        }
    }

    /// Chamar com a trava.
    private func montarEstado() -> Estado {
        let metadata = Sessao.shared.metadata
        let atualCotada = cotacaoAtual
        let (titulo, ligado) = botao
        let rede = chain.map { Estado.Rede(id: $0.id, nome: $0.name, coingecko: $0.coingeckoID) }
        let semVerificar = [sell, buy].compactMap { $0 }.first { $0.origin != nil }
        let abaixo: String? = {
            guard modo == .agora, recebeExato, abaixoDoAlvo, let buy, let minimo = minimoMostrado else { return nil }
            return preencher(Textos.t("A liquidez de agora não chega a %@ %@. O garantido fica em %@."), textoDoRecebido, buy.symbol,
                             Fmt.cripto(minimo, casas: buy.decimals, simbolo: buy.symbol, cheio: true))
        }()
        return Estado(
            alvo: alvo, carteira: carteira?.id.uuidString, observa: carteira?.isWatchOnly == true, modo: modo,
            temLimite: motor?.supportsLimitOrders == true,
            redes: TradeEngines.chains.map { Estado.Rede(id: $0.id, nome: $0.name, coingecko: $0.coingeckoID) }, rede: rede,
            vende: sell.map(Self.dto), compra: buy.map(Self.dto), valor: textoDoValor, versaoDoValor: versaoDoValor, entrada: quantidade?.decimalString,
            recebeExato: recebeExato, recebido: textoDoRecebido, versaoDoRecebido: versaoDoRecebido, resolvendo: resolvendo, abaixoDoAlvo: abaixo,
            saldo: textoDoSaldo(sell), saldoDaCompra: textoDoSaldo(buy), temSaldo: !(posicao(sell)?.quantidade.isZero ?? true), passou: passou,
            tolerancia: tolerancia, automatica: automatica, toleranciaAuto: toleranciaAgora(), chave: chave, podeCotar: podeCotar,
            cotando: cotando, emPartes: emPartes && cotacao?.parts != nil,
            cotacao: modo == .agora ? cotacao.map { cotacaoDTO($0, atual: atualCotada != nil) } : nil,
            limite: modo == .limite ? limiteDTO() : nil, erro: erro, erroDoPlano: erroDoPlano,
            naoVerificado: semVerificar.map { preencher(Textos.t("%@ não está na lista verificada da Escalibur. Qualquer pessoa cria um token com qualquer nome, e alguns deixam comprar mas não deixam vender. Confira o contrato antes."), $0.symbol) },
            impactoAceito: aceitouImpacto, botao: titulo, botaoLigado: ligado,
            protecao: chain == .ethereum && metadata.settings.mevProtection,
            etapa: etapa, frases: atual.map(frases), revisaoVende: ativosDaRevisao.vende.map(Self.dto), revisaoCompra: ativosDaRevisao.compra.map(Self.dto),
            falhaDaMontagem: falhaDaMontagem, cancelou: cancelou, revisao: plano.map(revisaoDTO), resultado: resultadoDTO(), andamento: andamentoDTO(),
            semAndamento: semAndamento, detalheIncerto: detalheIncerto, valorEmMoeda: valorEmMoeda
        )
    }

    private func limiteDTO() -> Estado.Limite {
        let simboloDaCompra = buy?.symbol ?? ""
        let conferenciaDTO: Estado.ConferenciaDoPreco? = {
            let confirmado = precoAceito == textoDoPreco
            switch conferencia {
            case .ok: return nil
            case .abaixo(let percentual):
                return Estado.ConferenciaDoPreco(
                    texto: preencher(Textos.t("%@%% abaixo do preço de mercado. A ordem pode sair na hora, vendendo abaixo do mercado até este preço."),
                                     Fmt.agrupado(percentual, casas: percentual < 10 ? 1 : 0)),
                    forte: true, confirmacao: Textos.t("Conferi o preço e quero assim"), confirmado: confirmado
                )
            case .muitoAbaixo(let percentual):
                return Estado.ConferenciaDoPreco(
                    texto: preencher(Textos.t("%@%% abaixo do preço de mercado. Confira o número: a ordem sairia na hora, com prejuízo."),
                                     Fmt.agrupado(percentual, casas: 0)),
                    forte: true, confirmacao: nil, confirmado: false
                )
            case .muitoAcima(let razao):
                return Estado.ConferenciaDoPreco(
                    texto: preencher(Textos.t("%@ vezes o preço de mercado: a ordem provavelmente nunca executa."), Fmt.agrupado(razao, casas: 0)),
                    forte: false, confirmacao: nil, confirmado: true
                )
            case .semMercado:
                return Estado.ConferenciaDoPreco(texto: Textos.t("Sem preço de mercado agora para comparar. Confira o número antes de seguir."),
                                                 forte: false, confirmacao: Textos.t("Conferi o preço"), confirmado: confirmado)
            }
        }()
        let editando = edicao.map { e in
            preencher(Textos.t("Ordem de %@ por %@, na %@"), Fmt.cripto(e.ordem.remainingSell, casas: e.sell.decimals, simbolo: e.sell.symbol),
                      e.buy.symbol, e.ordem.chain.name)
        }
        return Estado.Limite(
            preco: textoDoPreco, versaoDoPreco: versaoDoPreco,
            precoCompacto: Self.zerosCompactos(textoDoPreco).map { "\($0) \(simboloDaCompra)" },
            rotuloDoPreco: preencher(Textos.t("Quando 1 %@ valer"), sell?.symbol ?? ""), recebido: recebidoDaOrdem,
            calculado: recebeExato && deriva == .valor,
            validades: chain.map { Self.validades($0).map { Estado.Validade(segundos: $0.segundos, titulo: $0.titulo) } } ?? [],
            validade: validade,
            semPrazo: chain.flatMap { rede in Self.validades(rede).isEmpty ? preencher(Textos.t("Na %@ a oferta não tem prazo: fica até executar ou você cancelar."), rede.name) : nil },
            custodia: motor?.limitCustodyNote, conferencia: conferenciaDTO, editando: editando
        )
    }

    private func frases(_ operacao: Operacao) -> Estado.Frases {
        func por(_ troca: String, _ limite: String, _ cancelar: String) -> String {
            switch operacao {
            case .troca: return troca
            case .limite: return limite
            case .cancelar: return cancelar
            }
        }
        let mensagem: String
        switch operacao {
        case .troca: mensagem = Textos.t("O saldo novo aparece quando a rede confirmar.")
        case .limite: mensagem = Textos.t("A ordem fica aberta até executar, vencer ou você cancelar.")
        case .cancelar(_, .offchain): mensagem = Textos.t("A CoW recebeu o pedido. Se um solver já estava executando a ordem, ela ainda pode sair.")
        case .cancelar(_, .onchain): mensagem = Textos.t("A ordem deixa de valer quando a rede confirmar a transação.")
        }
        var offchain = false
        if case .cancelar(_, .offchain) = operacao { offchain = true }
        return Estado.Frases(
            tipo: por("troca", "limite", "cancelar"),
            montando: por(Textos.t("Recotando e simulando a troca antes de mostrar."), Textos.t("Montando a ordem e conferindo os dados da rede."),
                          Textos.t("Montando o cancelamento e conferindo a ordem na rede.")),
            naoMontou: por(Textos.t("A troca não foi montada"), Textos.t("A ordem não foi montada"), Textos.t("O cancelamento não foi montado")),
            confirmar: por(Textos.t("Confirmar troca"), Textos.t("Criar ordem limite"), Textos.t("Cancelar a ordem")),
            enviando: por(Textos.t("Enviando a troca"), Textos.t("Enviando a ordem"), Textos.t("Enviando o cancelamento")),
            feito: por(Textos.t("Troca enviada"), Textos.t("Ordem limite criada"), Textos.t("Ordem cancelada")),
            mensagemDoFeito: mensagem,
            incerto: por(Textos.t("Não deu para confirmar a troca"), Textos.t("Não deu para confirmar a ordem"), Textos.t("Não deu para confirmar o cancelamento")),
            passo: cancelarAntes == nil ? nil : (cancelou ? Textos.t("Etapa 2 de 2: a ordem nova") : Textos.t("Etapa 1 de 2: cancelar a ordem atual")),
            explorador: !operacao.limite && !offchain
        )
    }

    private func cotacaoDTO(_ cotacao: TradeQuote, atual: Bool) -> Estado.Cotacao {
        let compra = cotacao.buy
        let partes = emPartes && cotacao.parts != nil
        let minimo = cotacao.minimumOut(inParts: partes)
        func quantia(_ valor: BigUInt) -> String { Fmt.cripto(valor, casas: compra.decimals, simbolo: compra.symbol) }
        let rota: String = {
            if partes { return Textos.t("Em partes pela CoW, conforme chega liquidez") }
            if cotacao.execution == .order { return preencher(Textos.t("Leilão da CoW, o melhor entre %lld"), "\(cotacao.providersCompared)") }
            if let escolhido, escolhido.par == par, cotacao.legs.first?.provider == escolhido.provedor {
                return preencher(Textos.t("%@, escolhido por você"), escolhido.provedor)
            }
            return cotacao.legs.count > 1
                ? preencher(Textos.t("Dividida entre %lld provedores para você receber mais"), "\(cotacao.legs.count)")
                : preencher(Textos.t("%@, o melhor entre %lld"), cotacao.legs.first?.provider ?? "", "\(cotacao.providersCompared)")
        }()
        let explicacao: String = {
            if cotacao.execution == .order {
                return Textos.t("Uma ordem assinada no leilão da CoW: os solvers disputam com a liquidez das corretoras descentralizadas e dos formadores de mercado. Se não couber de uma vez, ela é preenchida em partes, cada uma pelo mínimo garantido ou mais. O que não sair em 30 minutos continua na sua carteira, sem custo.")
            }
            return cotacao.legs.count > 1
                ? preencher(Textos.t("São %lld transações, uma por provedor, assinadas de uma vez. Cada parte é independente: se uma não passar, você fica com o que foi trocado, e o saldo daquela parte continua na sua carteira."), "\(cotacao.legs.count)")
                : Textos.t("Tudo acontece numa transação só. Ou executa inteira, ou nada sai da sua carteira.")
        }()
        let atualGarante = Saldos.decimal(cotacao.minimumOut, casas: compra.decimals)
        let alternativas = cotacao.alternatives.map { alternativa -> Estado.Alternativa in
            let outra = Saldos.decimal(alternativa.out, casas: compra.decimals)
            var diferenca: String?
            if atualGarante > 0 {
                let percentual = (outra / atualGarante - 1) * 100
                diferenca = abs(percentual) < 0.01 ? Textos.t("o mesmo") : (percentual > 0 ? "+" : "−") + Fmt.agrupado(abs(percentual), casas: 2)
                    + "%"
            }
            return Estado.Alternativa(provedor: alternativa.provider, garante: quantia(alternativa.out), diferenca: diferenca,
                                      usar: cotacao.choosing(alternativa) != nil)
        }
        let impacto = cotacao.priceImpactPercent
        let nivel: String
        switch PriceImpact.level(impacto) {
        case .normal: nivel = "normal"
        case .visible: nivel = "visivel"
        case .confirm: nivel = "confirmar"
        case .blocked: nivel = "bloqueado"
        }
        let deVenda = Saldos.decimal(cotacao.amountIn, casas: cotacao.sell.decimals)
        let deCompra = Saldos.decimal(minimo, casas: compra.decimals)
        let (preco, invertido): (String, String) = deVenda > 0 && deCompra > 0
            ? (Self.linhaDoPreco(deCompra / deVenda, base: cotacao.sell.symbol, cotada: compra.symbol),
               Self.linhaDoPreco(deVenda / deCompra, base: compra.symbol, cotada: cotacao.sell.symbol))
            : ("", "")
        let dePartes: Estado.Partes? = cotacao.parts.map { p in
            let unica = Saldos.decimal(cotacao.minimumOut, casas: compra.decimals)
            let melhor = Saldos.decimal(p.minimumOut, casas: compra.decimals)
            return Estado.Partes(
                deUmaVez: quantia(cotacao.minimumOut), emPartes: quantia(p.minimumOut),
                ganho: unica > 0 && melhor > unica ? "+" + Fmt.agrupado((melhor / unica - 1) * 100, casas: 2) + "%" : nil,
                notaDeUmaVez: cotacao.execution == .order ? Textos.t("Agora, no leilão da CoW") : Textos.t("Agora, numa transação")
            )
        }
        return Estado.Cotacao(
            atual: atual, garantido: minimo.decimalString, preco: preco, precoInvertido: invertido, rota: rota,
            provedores: Array(cotacao.legs.prefix(3).map(\.provider)), taxaDaRede: cotacao.networkFeeFiat,
            garantidoTexto: Fmt.cripto(minimo, casas: compra.decimals, simbolo: compra.symbol, cheio: true),
            doProvedor: Fmt.cripto(partes ? cotacao.parts?.expectedOut ?? cotacao.expectedOut : cotacao.expectedOut, casas: compra.decimals,
                                   simbolo: compra.symbol, cheio: true),
            prazo: cotacao.execution == .order || partes ? (partes ? Textos.t("1 hora") : Textos.t("30 minutos")) : nil,
            impacto: impacto, nivel: nivel, partes: dePartes,
            tituloDaRota: cotacao.legs.count > 1 ? Textos.t("Como a sua ordem foi dividida") : Textos.t("Rota da troca"),
            pernas: cotacao.legs.map { Estado.Perna(provedor: $0.provider, fracao: $0.fraction, recebe: quantia($0.expectedOut)) },
            explicacao: explicacao, alternativas: alternativas
        )
    }

    /// "1 SOL = 180,25 USDC". Com o preco pequeno demais para seis casas, a base cresce de mil em
    /// mil: "1 mi BNBFROG = 12,34 USDT", nunca "= 0".
    static func linhaDoPreco(_ taxa: Double, base: String, cotada: String) -> String {
        guard taxa.isFinite, taxa > 0, taxa < 0.001 else {
            return "1 \(base) = \(Fmt.agrupado(taxa, casas: 6, aparar: true)) \(cotada)"
        }
        let unidades = [Textos.t("1 mil"), Textos.t("1 mi"), Textos.t("1 bi"), Textos.t("1 tri"), Textos.t("1 quatri")]
        var escalada = taxa
        var indice = -1
        while escalada < 1, indice < unidades.count - 1 {
            escalada *= 1_000
            indice += 1
        }
        return "\(unidades[indice]) \(base) = \(Fmt.agrupado(escalada, casas: escalada < 1 ? 6 : 4, aparar: true)) \(cotada)"
    }

    private func revisaoDTO(_ plano: SigningPlan) -> Estado.Revisao {
        let review = plano.review
        let (venda, compra) = ativosDaRevisao
        let sai = zip(review.outgoing, venda).map { Fmt.cripto($0.amount, casas: $1.decimals, simbolo: $1.symbol) }
        let entra = zip(review.incomingMinimum, compra).map { Textos.t("no mínimo ") + Fmt.cripto($0.amount, casas: $1.decimals, simbolo: $1.symbol) }
        // A ordem da CoW com autorizacao antes: a CoW so aceita a ordem depois que a autorizacao
        // confirma na rede, e a espera e essa.
        let nota = plano.transactions.last is EIP712ValidatedMessage && plano.transactions.count > 1
            ? preencher(Textos.t("A autorização vai primeiro. A ordem segue para a CoW assim que ela confirmar na %@. Não feche o app até terminar."), plano.chain.name)
            : Textos.t("Não feche o app até terminar.")
        return Estado.Revisao(
            titulo: review.title, sai: atual?.cancela == true ? nil : sai, entra: atual?.cancela == true ? nil : entra,
            enderecos: review.lines.filter(\.verbatim).map { Estado.Linha(rotulo: $0.label, valor: $0.value) },
            linhas: review.lines.filter { !$0.verbatim }.map { Estado.Linha(rotulo: $0.label, valor: $0.value) }
                + [Estado.Linha(rotulo: Textos.t("De"), valor: carteira?.name ?? "")],
            avisos: review.warnings.map { Envio.textoDoAviso($0, chain: plano.chain, tipo: .tag) },
            // Na ordem limite, o aviso das duas assinaturas sai.
            transacoes: atual?.limite == true ? 1 : review.transactionCount, nota: nota, erro: erroDaRevisao
        )
    }

    private func resultadoDTO() -> Estado.Resultado? {
        guard etapa == .enviada || etapa == .incerta, let rede = atual?.rede ?? chain else { return nil }
        let (nome, detalhe): (String, String?)
        switch situacao {
        case .pending: (nome, detalhe) = ("pendente", nil)
        case .confirmed(let texto): (nome, detalhe) = ("confirmado", texto)
        case .failed(let motivo): (nome, detalhe) = ("falhou", motivo)
        }
        let ultimo = ids.last
        let mostraExplorador = atual.map(frases)?.explorador == true && !ordemDaCoW
        return Estado.Resultado(id: ultimo, explorador: rede.explorerName,
                                url: mostraExplorador ? ultimo.flatMap { rede.explorerURL(tx: $0)?.absoluteString } : nil,
                                situacao: nome, detalhe: detalhe, ordem: ordemDaCoW)
    }

    private func andamentoDTO() -> Estado.Andamento? {
        guard let andamento, let compra = ativosDaRevisao.compra else { return nil }
        let estado: String
        switch andamento.state {
        case .open: estado = "aberta"
        case .filled: estado = "preenchida"
        case .expired: estado = "vencida"
        case .cancelled: estado = "cancelada"
        }
        return Estado.Andamento(estado: estado, fracao: andamento.fraction,
                                recebido: Fmt.cripto(andamento.receivedBuy, casas: compra.decimals, simbolo: compra.symbol),
                                garantido: Fmt.cripto(andamento.minimumBuy, casas: compra.decimals, simbolo: compra.symbol))
    }
}

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

// MARK: A ponte

extension Troca {
    /// Os metodos "troca.*" e "ordens.*". As chamadas que vao a rede bloqueiam ate a resposta: o
    /// Kotlin chama de uma corrotina fora da thread principal e recebe o retrato novo. `alvo` diz a
    /// troca de qual tela: a da aba (sem alvo), a de editar uma ordem ou a de cancelar uma.
    static func chamar(_ metodo: String, _ pedido: JSONValue) throws -> Data {
        switch metodo {
        case "ordens.lista":
            let inicial = pedido["inicial"]?.boolValue ?? false
            Nucleo.esperarSemErro { await Ordens.shared.ler(inicial: inicial) }
            return try Nucleo.json(Ordens.shared.retrato())
        case "ordens.retrato":
            return try Nucleo.json(Ordens.shared.retrato())
        case "troca.editar":
            guard let ordem = Ordens.shared.ordem(pedido["ordem"]?.stringValue ?? "") else { throw Nucleo.Falha(erro: "troca.semOrdem") }
            return try retrato(try editar(ordem))
        case "troca.cancelar":
            guard let ordem = Ordens.shared.ordem(pedido["ordem"]?.stringValue ?? "") else { throw Nucleo.Falha(erro: "troca.semOrdem") }
            let troca = paraCancelar()
            Nucleo.esperarSemErro { await troca.cancelar(ordem) }
            return try retrato(troca)
        case "troca.encerrar":
            encerrar(pedido["alvo"]?.stringValue ?? "")
            return try Nucleo.json(["ok": true])
        default:
            break
        }
        let troca = try instancia(pedido["alvo"]?.stringValue)
        switch metodo {
        case "troca.estado": break
        case "troca.definir": troca.definir(pedido)
        case "troca.cotar": Nucleo.esperarSemErro { await troca.cotar(pedido["chave"]?.stringValue ?? "") }
        case "troca.opcoes": return try Nucleo.json(troca.opcoes(vendendo: pedido["vende"]?.boolValue ?? false))
        case "troca.preparar": try troca.preparar(ativo: pedido["ativo"]?.stringValue ?? "", vende: pedido["vende"]?.boolValue ?? true)
        case "troca.permite":
            let ids = (pedido["ativos"]?.arrayValue ?? []).compactMap(\.stringValue)
            return try Nucleo.json(["permite": troca.permite(ids)])
        case "troca.daMoeda": return try Nucleo.json(troca.daMoeda(pedido["coingecko"]?.stringValue ?? ""))
        case "troca.revisar": Nucleo.esperarSemErro { await troca.revisar() }
        case "troca.remontar": Nucleo.esperarSemErro { await troca.remontar() }
        case "troca.retransmitir": Nucleo.esperarSemErro { await troca.retransmitir() }
        case "troca.acompanhar": Nucleo.esperarSemErro { await troca.acompanhar() }
        case "troca.fechar": troca.fechar()
        default: throw Nucleo.Falha(erro: "metodo desconhecido: \(metodo)")
        }
        return try retrato(troca)
    }

    /// "troca.assinar": a credencial e, na carteira com passphrase, a passphrase depois dela.
    static func assinar(_ credencial: Credencial, passphrase: SecureBytes?, folga: Int?, alvo: String?) throws -> Data {
        let troca: Troca
        do { troca = try instancia(alvo) } catch {
            credencial.zerar()
            passphrase?.wipe()
            throw error
        }
        let pedido = Embrulho((credencial, passphrase))
        try esperar { try await troca.assinar(pedido.valor.0, passphrase: pedido.valor.1, folga: folga) }
        return try retrato(troca)
    }

    private static func retrato(_ troca: Troca) throws -> Data {
        let numero = contagem.withLock { () -> Int in
            ultimoNumero += 1
            return ultimoNumero
        }
        let metadata = Sessao.shared.metadata
        let carteira = metadata.selectedWallet
        return try Nucleo.json(Retrato(numero: numero, troca: troca.estado(), moeda: metadata.settings.currency,
                                       pedePassphrase: PortaDaPassphrase.precisa(carteira), nomeDaCarteira: carteira?.name ?? ""))
    }

    private static let contagem = NSLock()
    nonisolated(unsafe) private static var ultimoNumero = 0

    /// A etapa mudou no meio de uma chamada longa (montando, transmitindo): a interface fica
    /// sabendo sem esperar a resposta.
    func avisar() {
        guard let json = try? Self.retrato(self) else { return }
        Eventos.emitir("troca", json)
    }

    /// Cada retrato leva um numero crescente: a interface descarta o que chegar fora de ordem.
    struct Retrato: Encodable {
        let numero: Int
        let troca: Estado
        let moeda: String
        let pedePassphrase: Bool
        let nomeDaCarteira: String
    }
}
