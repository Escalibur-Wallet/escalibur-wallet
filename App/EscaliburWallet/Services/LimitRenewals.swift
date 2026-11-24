import CryptoKit
import EscaliburChains
import EscaliburCore
import EscaliburEngines
import Foundation
import UserNotifications

/// Uma ordem limite que o dono pediu para refazer quando vencer.
///
/// Sem servidor, e com a chave so no iPhone, nada refaz a ordem sozinho: quem assina e o
/// dono. O app guarda os dados da ordem nos metadados cifrados (rede, ativos, valor,
/// preco e prazo; nada de segredo), avisa com uma notificacao local quando o prazo
/// acaba e, na abertura seguinte, pergunta se refaz. Refazer passa pela mesma revisao,
/// voz, PIN ou Face ID e assinatura de qualquer ordem.
struct LimitRenewal: Codable, Equatable, Hashable, Identifiable {
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

    var id: String { orderID }
}

/// Uma ordem vencida, pronta para a pergunta: o que ainda falta vender (ela pode ter
/// saido em parte) e o minimo pelo mesmo preco.
struct DueRenewal: Identifiable, Equatable {
    let record: LimitRenewal
    let chain: Chain
    let sell: Asset
    let buy: Asset
    let amountIn: BigUInt
    let minimumOut: BigUInt
    /// Quanto da ordem vencida chegou a sair, de 0 a 1.
    let filledFraction: Double

    var id: String { record.orderID }

    /// O minimo pelo que falta vender, no preco da ordem: para cima, nunca abaixo dele.
    static func minimum(_ record: LimitRenewal, remaining: BigUInt) -> BigUInt {
        guard !record.amountIn.isZero else { return 0 }
        return (record.minimumOut * remaining + record.amountIn - BigUInt(1)) / record.amountIn
    }
}

@MainActor
@Observable
final class LimitRenewalCenter {
    static let shared = LimitRenewalCenter()
    nonisolated static let category = "ordem-limite"

    /// So as redes com andamento de ordem lido da rede: a CoW. No XRP Ledger e na
    /// Stellar a oferta que some pode ter executado, e o app nao saberia se refaz.
    static func supports(_ chain: Chain) -> Bool { CoWProtocol.supports(chain) }

    private(set) var due: [DueRenewal] = []
    /// Deixadas para depois nesta abertura do app.
    var postponed: Set<String> = []
    /// Cada leitura sobe a geracao, e so a ultima grava: a de outra carteira, ou de antes de travar, nao poe as vencidas
    /// dela na pergunta (revisao da decima terceira passada).
    private var generation = 0

    /// So as da carteira escolhida: a de outra carteira nunca vira pergunta nem ordem nesta.
    func pending(for wallet: UUID?) -> [DueRenewal] {
        due.filter { !postponed.contains($0.id) && $0.record.walletID == wallet }
    }

    /// Ao travar e ao apagar tudo (`wallet` nil): nada da leitura de antes fica para a pergunta, e a leitura em curso nao
    /// grava. Ao remover uma carteira, so as vencidas dela saem (a leitura em curso ja confere se a carteira existe).
    func forget(_ wallet: UUID? = nil) {
        guard let wallet else {
            due = []
            postponed = []
            generation += 1
            return
        }
        due.removeAll { $0.record.walletID == wallet }
    }

    func isRenewing(_ orderID: String, session: AppSession) -> Bool {
        session.metadata.limitRenewals?.contains { $0.orderID == orderID } == true
    }

    /// Depois de a ordem ir para a rede: guarda os dados e agenda o aviso do fim do prazo,
    /// lido do proprio UID (os ultimos 4 bytes sao o `validTo`).
    /// `notify`: o aviso do fim do prazo. A carteira com passphrase fica sem ele: a hora do aviso e o fim do prazo que
    /// o UID traz, e liga o aviso a ordem e ao dono; a pergunta aparece ao destravar (setima passada de 03/11/2026).
    func register(orderID: String, request: LimitOrderRequest, session: AppSession, notify: Bool) {
        guard Self.supports(request.chain), orderID.hasPrefix("0x"), let uid = Hex.decode(orderID),
              let validTo = CoWProtocol.validTo(ofUID: uid) else { return }
        let record = LimitRenewal(
            orderID: orderID, walletID: request.walletID, chainID: request.chain.id, sellAssetID: request.sell.id,
            buyAssetID: request.buy.id, amountIn: request.amountIn, minimumOut: request.minimumOut,
            validFor: request.validFor ?? CoWProtocol.untilCancelledValidity, expiresAt: Date(timeIntervalSince1970: TimeInterval(validTo))
        )
        var list = session.metadata.limitRenewals ?? []
        list.removeAll { $0.orderID == orderID }
        list.append(record)
        session.metadata.limitRenewals = list
        try? session.persist()
        if notify { Self.scheduleNotice(record) }
    }

    func forget(_ orderID: String, session: AppSession) {
        session.metadata.limitRenewals?.removeAll { $0.orderID == orderID }
        try? session.persist()
        due.removeAll { $0.id == orderID }
        Self.forgetNotices([orderID])
    }

    /// Tira da agenda do sistema os avisos destas ordens (tambem os de antes do resumo).
    static func forgetNotices(_ orderIDs: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: orderIDs.flatMap { [noticeID($0), "ordem-limite.\(legacyDigest($0))", "ordem-limite.\($0)"] }
        )
    }

    /// Le na rede as ordens vencidas da carteira escolhida. Executada ou cancelada sai da
    /// lista; vencida com algo a vender vira pergunta; sem resposta da rede, fica para a
    /// proxima vez.
    func refresh(session: AppSession) async {
        guard session.phase == .unlocked, let wallet = session.selectedWallet, !wallet.isWatchOnly else { return }
        #if DEBUG
        if previewing { return }
        #endif
        generation += 1
        let mine = generation
        let now = Date()
        var found: [DueRenewal] = []
        for record in session.metadata.limitRenewals ?? [] where record.walletID == wallet.id && record.expiresAt <= now {
            guard let chain = Chain.all.first(where: { $0.id == record.chainID }), let engine = TradeEngines.engine(for: chain), let account = wallet.account(chain),
                  let sell = Self.listed(record.sellAssetID, chain: chain), let buy = Self.listed(record.buyAssetID, chain: chain)
            else {
                forget(record.orderID, session: session)
                continue
            }
            guard let progress = try? await engine.orderProgress(id: record.orderID, account: account) else { continue }
            switch progress.state {
            case .filled, .cancelled:
                forget(record.orderID, session: session)
            case .open:
                continue
            case .expired:
                let sold = min(progress.soldSell, record.amountIn)
                let remaining = record.amountIn - sold
                guard !remaining.isZero else {
                    forget(record.orderID, session: session)
                    continue
                }
                found.append(DueRenewal(
                    record: record, chain: chain, sell: sell, buy: buy, amountIn: remaining,
                    minimumOut: DueRenewal.minimum(record, remaining: remaining), filledFraction: progress.fraction
                ))
            }
        }
        // A ultima leitura, da carteira que ainda e a escolhida e ainda existe, com o app destravado.
        guard generation == mine, session.phase == .unlocked, session.selectedWallet?.id == wallet.id,
              session.metadata.wallets.contains(where: { $0.id == wallet.id }) else { return }
        due = found
    }

    #if DEBUG
    /// `-tela refazer`: uma ordem vencida de mentira, so para conferir o desenho.
    func preview(_ item: DueRenewal) {
        previewing = true
        due = [item]
    }

    private var previewing = false
    #endif

    static func listed(_ id: String, chain: Chain) -> Asset? {
        TokenRegistry.assets(on: chain).first { $0.id == id }
    }

    // MARK: Aviso

    /// Um resumo do UID, e nao o UID: o pedido de notificacao fica no armazenamento do sistema, fora do cofre, e o
    /// UID traz o endereco do dono (o da carteira com passphrase inclusive). O app so precisa saber que e uma ordem
    /// (quinta passada da auditoria de 03/11/2026, como no Android). Com a chave desta instalacao: sem ela, o resumo
    /// se desfazia por dicionario, porque o UID de toda ordem executada e publico na cadeia (sexta passada).
    nonisolated static func digest(_ orderID: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(orderID.lowercased().utf8), using: NoticeKey.current())
            .prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// O resumo sem chave da versao anterior: so para tirar da agenda o que ela marcou.
    nonisolated static func legacyDigest(_ orderID: String) -> String {
        SHA256.hash(data: Data(orderID.lowercased().utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func noticeID(_ orderID: String) -> String { "ordem-limite.\(digest(orderID))" }

    /// O aviso nao diz ativo nem valor: a tela bloqueada nao conta o que a carteira tem.
    static func scheduleNotice(_ record: LimitRenewal) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "O prazo de uma ordem limite acabou")
        content.body = String(localized: "Abra a Escalibur: se ainda faltar vender, o app pergunta se refaz com o mesmo preço.")
        content.categoryIdentifier = category
        // So que e uma ordem: o toque abre a ordem limite, e o id nao precisa ir junto.
        content.userInfo = ["ordem": "1"]
        let interval = max(60, record.expiresAt.timeIntervalSinceNow + 60)
        let request = UNNotificationRequest(
            identifier: noticeID(record.orderID), content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}

/// Uma vez, depois de atualizar: os avisos de ordem agendados e mostrados pelas versoes anteriores saem (o id levava o
/// UID cru ou o resumo sem chave, e a carteira com passphrase tambem tinha o aviso do fim do prazo), e os de agora
/// sao marcados de novo, no formato novo (setima passada da auditoria de 03/11/2026).
@MainActor
enum NoticeMigration {
    static var marker: URL { NoticeKey.directory.appendingPathComponent("formato-2") }

    static func runOnce(_ session: AppSession) {
        guard session.phase == .unlocked else { return }
        // A cada destravar: a ordem da carteira com passphrase sai do arquivo das ordens (classe C, com o UID e o dono),
        // se uma versao anterior a deixou entrar; o endereco de uma carteira sem passphrase fica (oitava passada).
        let wallets = session.metadata.wallets
        let hidden = Set(wallets.filter(\.hasPassphrase).flatMap(AppSession.evmOwners))
            .subtracting(wallets.filter { !$0.hasPassphrase }.flatMap(AppSession.evmOwners))
        let pending = !FileManager.default.fileExists(atPath: marker.path)
        guard pending else {
            if !hidden.isEmpty { Task { await LimitOrderWatch.shared.purge(owners: hidden) } }
            return
        }
        let now = Date()
        let renewals = (session.metadata.limitRenewals ?? []).filter { record in
            session.metadata.wallets.first { $0.id == record.walletID }?.hasPassphrase == false && record.expiresAt > now
        }
        let marker = self.marker
        // A epoca do travar e do apagar tudo: travou ou apagou no meio, para, sem marcar nada (um apagar tudo logo
        // depois recriava a chave e agendava avisos das carteiras apagadas; oitava passada). O que ja saiu sai de novo
        // no proximo destravar.
        let epoch = session.lockEpoch
        let still = { session.lockEpoch == epoch && session.phase == .unlocked }
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("ordem-limite.") }
            guard still() else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("ordem-limite.") }
            guard still() else { return }
            center.removeDeliveredNotifications(withIdentifiers: delivered)
            await LimitOrderWatch.shared.purge(owners: hidden)
            guard still() else { return }
            for record in renewals { LimitRenewalCenter.scheduleNotice(record) }
            await LimitOrderWatch.shared.rescheduleWarnings()
            guard still() else { return }
            NoticeKey.mark(marker)
        }
    }
}
