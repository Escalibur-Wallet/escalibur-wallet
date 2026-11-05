import EscaliburChains
import EscaliburCore
import Foundation

/// Uma ordem limite da CoW assinada neste aparelho que a CoW disse ter recusado, ou cuja criacao
/// ficou sem resposta certa (segunda passada da auditoria de 03/11/2026). A assinatura vale ate o
/// `validTo` do UID, e uma API maliciosa pode guardar a ordem e responder "recusei": o app guarda o
/// que ela e (nada de segredo: o UID, os ativos, os valores e o vencimento), mostra em Ordens abertas
/// como ordem viva, conta no que esta preso e oferece o cancelamento na cadeia. Sai quando vence ou
/// quando a cadeia, e nao a API, diz que ela terminou.
public struct SignedOrderRecord: Codable, Equatable, Sendable {
    public let walletID: UUID
    /// O UID da CoW, hex com `0x`.
    public let id: String
    public let chainID: String
    public let sellAssetID: String
    public let buyAssetID: String
    /// O que a ordem vende inteira e o minimo que recebe por isso.
    public let sellAmount: BigUInt
    public let minimumBuy: BigUInt
    public let expiresAt: Date
    public let createdAt: Date
    /// O que a cadeia ja liquidou na ultima leitura do `filledAmount` (zero ate ler).
    public var filled: BigUInt

    /// nil fora da CoW ou com um UID que nao e da CoW: so ela tem o registro na cadeia que diz quando
    /// a ordem terminou.
    public init?(_ order: OpenOrder, walletID: UUID, now: Date = Date()) {
        guard CoWProtocol.supports(order.chain), order.id.hasPrefix("0x"), let uid = Hex.decode(order.id),
              uid.count == CoWProtocol.uidLength, let validTo = CoWProtocol.validTo(ofUID: uid) else { return nil }
        self.walletID = walletID
        id = order.id.lowercased()
        chainID = order.chain.id
        sellAssetID = order.sellAssetID
        buyAssetID = order.buyAssetID
        sellAmount = order.totalSell ?? order.remainingSell
        minimumBuy = order.minimumBuy
        expiresAt = Date(timeIntervalSince1970: TimeInterval(validTo))
        createdAt = order.createdAt ?? now
        filled = 0
    }

    /// Terminou na cadeia: liquidada por inteiro, ou cancelada (o `invalidateOrder` leva o
    /// `filledAmount` ao maximo).
    public var finished: Bool { filled >= sellAmount }

    /// Como a lista mostra: `sources` 0 (nenhuma fonte listou, so este aparelho sabe dela) e so o
    /// cancelamento na cadeia, o unico que nao depende da CoW.
    public var order: OpenOrder? {
        guard let chain = Chain.all.first(where: { $0.id == chainID }), !sellAmount.isZero else { return nil }
        let remaining = sellAmount.subtractingReportingUnderflow(filled) ?? 0
        // O minimo pelo que falta vender, no preco gravado: para cima, nunca abaixo dele.
        let minimum = filled.isZero ? minimumBuy : (minimumBuy * remaining + sellAmount - 1) / sellAmount
        return OpenOrder(
            id: id, chain: chain, sellAssetID: sellAssetID, buyAssetID: buyAssetID, remainingSell: remaining, minimumBuy: minimum,
            expiresAt: expiresAt, sources: 0, cancellations: [.onchain], totalSell: sellAmount, createdAt: createdAt
        )
    }
}

/// O que a cadeia diz de uma ordem guardada: quanto o contrato ja liquidou (o maximo depois do
/// `invalidateOrder`, o menor de duas fontes) e o tempo do ultimo bloco (o menor de duas fontes).
public struct SignedOrderChainState: Sendable, Equatable {
    public let filled: BigUInt
    public let chainTime: Date

    public init(filled: BigUInt, chainTime: Date) {
        self.filled = filled
        self.chainTime = chainTime
    }
}

extension SignedOrderRecord {
    /// A CoW lista esta mesma ordem, com os mesmos ativos, o mesmo valor e o mesmo vencimento. Com outro
    /// valor no mesmo UID ela mente, e a guardada fica no lugar (terceira passada da auditoria de 03/11/2026).
    func matches(_ listed: OpenOrder) -> Bool {
        listed.id.lowercased() == id && listed.chain.id == chainID
            && listed.sellAssetID.lowercased() == sellAssetID.lowercased() && listed.buyAssetID.lowercased() == buyAssetID.lowercased()
            && (listed.totalSell ?? listed.remainingSell) == sellAmount
            && listed.expiresAt.map { Int($0.timeIntervalSince1970) } == Int(expiresAt.timeIntervalSince1970)
    }
}

/// As ordens assinadas guardadas (`SignedOrderRecord`), as mesmas regras no iOS e no Android.
public enum SignedOrders {
    /// O contrato aceita a ordem enquanto `validTo >= block.timestamp`, e redes com varios blocos no mesmo
    /// segundo (Arbitrum, BNB) ainda executam no segundo do vencimento: a guardada so sai um minuto depois
    /// (quarta passada da auditoria de 03/11/2026).
    public static let expiryMargin: TimeInterval = 60

    /// Guarda uma ordem: a mesma ordem guardada de novo nao duplica.
    public static func adding(_ record: SignedOrderRecord, to records: [SignedOrderRecord]?) -> [SignedOrderRecord] {
        (records ?? []).filter { $0.id != record.id } + [record]
    }

    /// Le na cadeia o que cada guardada desta carteira ja liquidou e devolve as que continuam: sai a
    /// vencida pelo tempo do bloco (o contrato compara o `validTo` com ele, e nao com o relogio do
    /// aparelho) e a que a cadeia da por terminada. A que a cadeia nao respondeu fica como estava: uma
    /// ordem que ainda pode executar nunca some por falta de resposta. As de outras carteiras e as das
    /// redes em `skippingChains` (desligadas em Ajustes) voltam intactas, sem consulta: ler o UID de uma
    /// carteira com a tela de outra ligaria as duas nos provedores, e o UID traz o dono (terceira passada
    /// da auditoria de 03/11/2026).
    /// `existingWallets`: as carteiras que ainda existem; a guardada de outra sai, sem consulta (o UID traz o
    /// endereco da carteira apagada, quarta passada da auditoria de 03/11/2026).
    public static func refreshed(_ records: [SignedOrderRecord], wallet: UUID, existingWallets: Set<UUID>? = nil,
                                 skippingChains: Set<String> = [],
                                 state: (SignedOrderRecord) async -> SignedOrderChainState?) async -> [SignedOrderRecord] {
        var kept: [SignedOrderRecord] = []
        for var record in records {
            if let existingWallets, !existingWallets.contains(record.walletID) { continue }
            guard record.walletID == wallet, !skippingChains.contains(record.chainID), let read = await state(record) else {
                kept.append(record)
                continue
            }
            guard read.chainTime <= record.expiresAt.addingTimeInterval(expiryMargin) else { continue }
            if read.filled > record.filled { record.filled = read.filled }
            if !record.finished { kept.append(record) }
        }
        return kept
    }

    /// A lista da CoW com as guardadas desta carteira: a que a CoW nao lista entra como aberta; a que ela
    /// lista igual aparece uma vez, a da CoW; a que ela lista com outros valores no mesmo UID e trocada pela
    /// guardada. A guardada continua ate a cadeia dizer que terminou, mesmo quando a CoW a lista.
    public static func merged(_ listed: [OpenOrder], records: [SignedOrderRecord]?, wallet: UUID) -> [OpenOrder] {
        var out = listed
        for record in records ?? [] where record.walletID == wallet && !record.finished {
            guard let order = record.order else { continue }
            if let index = out.firstIndex(where: { $0.id.lowercased() == record.id }) {
                if !record.matches(out[index]) { out[index] = order }
            } else {
                out.append(order)
            }
        }
        return out
    }

    /// O que a cadeia diz de uma guardada, lido pelo motor da rede dela. nil sem resposta.
    public static func onChainState(_ record: SignedOrderRecord) async -> SignedOrderChainState? {
        guard let order = record.order, let engine = TradeEngines.engine(for: order.chain) else { return nil }
        return try? await engine.onChainState(order)
    }
}
