import EscaliburChains
import EscaliburCore
import EscaliburEngines
import Foundation

/// Uma ordem limite que o dono pediu para refazer quando vencer (o LimitRenewal do iOS).
///
/// Sem servidor, e com a chave so no celular, nada refaz a ordem sozinho: quem assina e o dono. O
/// app guarda os dados da ordem nos metadados cifrados (rede, ativos, valor, preco e prazo; nada de
/// segredo), avisa quando o prazo acaba e, na abertura seguinte, pergunta se refaz. Refazer passa
/// pela mesma revisao, PIN ou biometria e assinatura de qualquer ordem.
struct LimitRenewal: Codable, Equatable, Hashable {
    /// O id da ordem na rede: o UID da CoW.
    let orderID: String
    let walletID: UUID
    let chainID: String
    let sellAssetID: String
    let buyAssetID: String
    let amountIn: BigUInt
    let minimumOut: BigUInt
    let validFor: TimeInterval
    let expiresAt: Date
}

enum Renovacoes {
    /// Uma ordem vencida, pronta para a pergunta: o que ainda falta vender (ela pode ter saido em
    /// parte) e o minimo pelo mesmo preco.
    struct Vencida {
        let registro: LimitRenewal
        let rede: Chain
        let vende: Asset
        let compra: Asset
        let quantia: BigUInt
        let minimo: BigUInt
        /// Quanto da ordem vencida chegou a sair, de 0 a 1.
        let fracao: Double
    }

    private static let trava = NSLock()
    nonisolated(unsafe) private static var vencidas: [Vencida] = []
    /// Deixadas para depois nesta abertura do app.
    nonisolated(unsafe) private static var depois: Set<String> = []
    nonisolated(unsafe) private static var lendo = false

    /// So as redes com andamento de ordem lido da rede: a CoW. No XRP Ledger e na Stellar a oferta
    /// que some pode ter executado, e o app nao saberia se refaz.
    static func suporta(_ rede: Chain) -> Bool { CoWProtocol.supports(rede) }

    static func renova(_ id: String) -> Bool {
        Sessao.shared.metadata.limitRenewals?.contains { $0.orderID == id } == true
    }

    /// Depois de a ordem ir para a rede: guarda os dados e marca o aviso do fim do prazo, lido do
    /// proprio UID (os ultimos 4 bytes sao o `validTo`).
    static func registrar(_ id: String, pedido: LimitOrderRequest) {
        guard suporta(pedido.chain), id.hasPrefix("0x"), let uid = Hex.decode(id), let vence = CoWProtocol.validTo(ofUID: uid) else { return }
        let registro = LimitRenewal(
            orderID: id, walletID: pedido.walletID, chainID: pedido.chain.id, sellAssetID: pedido.sell.id, buyAssetID: pedido.buy.id,
            amountIn: pedido.amountIn, minimumOut: pedido.minimumOut, validFor: pedido.validFor ?? CoWProtocol.untilCancelledValidity,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(vence))
        )
        // Depois do envio da ordem: vale mesmo que o app tenha travado durante ele.
        Sessao.shared.alterarOuDepois { metadata in
            var lista = metadata.limitRenewals ?? []
            lista.removeAll { $0.orderID == id }
            lista.append(registro)
            metadata.limitRenewals = lista
        }
        VigiaDeOrdens.marcarFimDoPrazo(id, em: registro.expiresAt.addingTimeInterval(60))
    }

    static func esquecer(_ id: String) {
        Sessao.shared.alterarOuDepois { $0.limitRenewals?.removeAll { $0.orderID == id } }
        VigiaDeOrdens.desmarcarFimDoPrazo(id)
        trava.withLock { vencidas.removeAll { $0.registro.orderID == id } }
    }

    /// O minimo pelo que falta vender, no preco da ordem: para cima, nunca abaixo dele.
    static func minimo(_ registro: LimitRenewal, resta: BigUInt) -> BigUInt {
        guard !registro.amountIn.isZero else { return 0 }
        return (registro.minimumOut * resta + registro.amountIn - BigUInt(1)) / registro.amountIn
    }

    private static func ativo(_ id: String, _ rede: Chain) -> Asset? {
        if Asset.native(rede).id == id { return .native(rede) }
        return TokenRegistry.assets(on: rede).first { $0.id == id } ?? Ordens.resolver(id, listado: nil, rede: rede)
    }

    /// Le na rede as ordens vencidas da carteira escolhida. Executada ou cancelada sai da lista;
    /// vencida com algo a vender vira pergunta; sem resposta da rede, fica para a proxima vez.
    static func atualizar() async {
        guard Sessao.shared.fase == .unlocked, let carteira = Sessao.shared.metadata.selectedWallet, !carteira.isWatchOnly,
              trava.withLock({ () -> Bool in
                  guard !lendo else { return false }
                  lendo = true
                  return true
              }) else { return }
        defer { trava.withLock { lendo = false } }
        let agora = Date()
        var achadas: [Vencida] = []
        for registro in Sessao.shared.metadata.limitRenewals ?? [] where registro.walletID == carteira.id && registro.expiresAt <= agora {
            guard let rede = Chain.all.first(where: { $0.id == registro.chainID }), let motor = TradeEngines.engine(for: rede),
                  let conta = carteira.account(rede), let vende = ativo(registro.sellAssetID, rede), let compra = ativo(registro.buyAssetID, rede) else {
                esquecer(registro.orderID)
                continue
            }
            guard let andamento = try? await motor.orderProgress(id: registro.orderID, account: conta) else { continue }
            switch andamento.state {
            case .filled, .cancelled:
                esquecer(registro.orderID)
            case .open:
                continue
            case .expired:
                let resta = registro.amountIn - min(andamento.soldSell, registro.amountIn)
                guard !resta.isZero else {
                    esquecer(registro.orderID)
                    continue
                }
                achadas.append(Vencida(registro: registro, rede: rede, vende: vende, compra: compra, quantia: resta,
                                       minimo: minimo(registro, resta: resta), fracao: andamento.fraction))
            }
        }
        trava.withLock { vencidas = achadas }
    }

    static func vencida(_ id: String) -> Vencida? {
        trava.withLock { vencidas.first { $0.registro.orderID == id } }
    }

    static func adiar(_ id: String) {
        trava.withLock { _ = depois.insert(id) }
    }

    // MARK: A pergunta

    struct Pergunta: Encodable {
        let id: String
        let vende: Troca.Estado.Ativo
        let titulo: String
        let minimo: String
        let texto: String
        let parcial: String?
        let abaixoDoMercado: String?
        let mais: String?
    }

    static func validade(_ segundos: TimeInterval) -> String {
        let dias = max(1, Int((segundos / 86_400).rounded()))
        return dias == 1 ? Textos.t("1 dia") : preencher(Textos.t("%lld dias"), "\(dias)")
    }

    /// A primeira vencida que o dono nao deixou para depois.
    static func pergunta() -> Pergunta? {
        let pendentes = trava.withLock { vencidas.filter { !depois.contains($0.registro.orderID) } }
        guard let v = pendentes.first else { return nil }
        let quantia = Saldos.decimal(v.quantia, casas: v.vende.decimals)
        let alvo = quantia > 0 ? Saldos.decimal(v.minimo, casas: v.compra.decimals) / quantia : 0
        // O mercado ja paga mais que o preco da ordem: refeita, ela sai na hora.
        var abaixo = false
        if let precoDaVenda = Saldos.shared.preco(v.vende), let precoDaCompra = Saldos.shared.preco(v.compra), precoDaVenda > 0, precoDaCompra > 0, alvo > 0 {
            abaixo = alvo < (precoDaVenda / precoDaCompra) * 0.98
        }
        let fracao = v.fracao * 100
        let restantes = pendentes.count - 1
        return Pergunta(
            id: v.registro.orderID, vende: Troca.dto(v.vende),
            titulo: preencher(Textos.t("Vender %@"), Fmt.cripto(v.quantia, casas: v.vende.decimals, simbolo: v.vende.symbol)),
            minimo: preencher(Textos.t("por no mínimo %@"), Fmt.cripto(v.minimo, casas: v.compra.decimals, simbolo: v.compra.symbol)),
            texto: preencher(Textos.t("1 %@ a %@ %@, na %@. Refeita, vale por mais %@."), v.vende.symbol, Fmt.agrupado(alvo, casas: 6, aparar: true),
                             v.compra.symbol, v.rede.name, validade(v.registro.validFor)),
            parcial: v.fracao > 0 ? preencher(Textos.t("%@ da ordem chegou a sair antes de vencer. Refazer vende o que falta, no mesmo preço."),
                                              Fmt.agrupado(fracao, casas: fracao < 10 ? 1 : 0, aparar: true) + "%") : nil,
            abaixoDoMercado: abaixo ? Textos.t("O mercado já paga mais que o preço desta ordem. Refeita agora, ela sai na hora, ao preço de mercado ou melhor.") : nil,
            mais: restantes <= 0 ? nil : restantes == 1 ? Textos.t("Mais 1 ordem vencida depois desta")
                : preencher(Textos.t("Mais %lld ordens vencidas depois desta"), "\(restantes)")
        )
    }
}
