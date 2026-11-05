import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import SwiftUI

/// T3 a T5: revisar o plano da troca ou da ordem limite, assinar e acompanhar.
///
/// Mesma regra do envio: a tela mostra o plano que o motor montou e validou, nunca a
/// intencao, e o plano precisa ser desta carteira e desta rede antes de qualquer
/// assinatura.
struct TradeReviewFlow: View {
    enum Kind: Sendable {
        case swap(TradeRequest, TradeQuote)
        case limit(LimitOrderRequest)
        /// Cancelar uma ordem aberta, pelo jeito escolhido.
        case cancel(OpenOrder, OpenOrder.Cancellation)
    }

    struct Item: Identifiable {
        let id = UUID()
        let kind: Kind
        let chain: Chain
        /// Valor vendido em moeda do dono, para a camada de voz; nil sem cotacao.
        let fiat: Double?
        /// Ordem limite: refazer quando vencer (`LimitRenewalCenter`).
        var renewLimit = false
        /// Refazendo uma ordem vencida: o id dela, que sai da lista quando a nova sai.
        var replacesRenewal: String? = nil
        /// Editando uma ordem aberta (pedido do dono, 17/10/2026): etapa 1, cancelar esta;
        /// etapa 2, a ordem nova de `kind`.
        var cancelFirst: Replacement? = nil
    }

    /// A ordem que a edicao substitui, e o jeito de cancelar.
    struct Replacement: Sendable {
        let order: OpenOrder
        let via: OpenOrder.Cancellation
    }

    @Environment(AppSession.self) private var session
    @Environment(AuthCoordinator.self) private var auth
    @Environment(Portfolio.self) private var portfolio
    let item: Item
    let onClose: (_ completed: Bool) -> Void
    /// A troca ou a ordem que nao foi montada: o erro volta para a tela da troca, no lugar
    /// desta tela so com o erro e o tentar de novo (pedido do dono, 17/10/2026).
    var onPlanFailed: ((String) -> Void)? = nil
    #if DEBUG
    /// `-tela carregando` e `-tela enviando`: a tela parada numa etapa, sem rede.
    var debugStage: Stage?
    #endif

    /// `unsure`: assinado e enviado sem resposta certa (auditoria 2, M3).
    /// `waitingCancel`: na edicao, o cancelamento da ordem antiga saiu e a tela espera ele confirmar
    /// antes de montar a nova (segunda passada da auditoria de 03/11/2026).
    enum Stage { case planning, review, sending, waitingCancel, done, unsure, refused }
    @State private var stage: Stage = .planning
    @State private var plan: SigningPlan?
    @State private var error: String?
    @State private var ids: [String] = []
    /// O que foi assinado e enviado sem resposta certa: so isto pode ir de novo.
    @State private var unsureSigned: [SignedTransaction]?
    @State private var unsureDetail: String?
    /// A CoW recusou com certeza e disse por que: nada foi criado (01/11/2026).
    @State private var refusedReason: String?
    /// O que ja tinha entrado na rede antes da recusa, e a ordem assinada que a CoW diz ter recusado:
    /// a palavra e dela, e so o cancelamento na cadeia nao depende dela (auditoria de 03/11/2026).
    @State private var refusedNotes: [String] = []
    @State private var refusedOrder: OpenOrder?
    /// A troca imediata enviada, como a rede responde, todas as transacoes do plano.
    @State private var swapOutcome: TradeOutcome = .pending
    @State private var cancellingRefused: Item?
    /// Edicao: a etapa 1 (cancelar a atual) ja saiu, e a etapa da vez e a ordem nova.
    @State private var cancelled = false

    /// O que esta tela assina agora: na edicao, primeiro o cancelamento, depois a ordem nova.
    private var kind: Kind {
        if let replacing = item.cancelFirst, !cancelled { return .cancel(replacing.order, replacing.via) }
        return item.kind
    }

    /// "Etapa 1 de 2" e "Etapa 2 de 2" na edicao; nil fora dela.
    private var stepLine: String? {
        guard item.cancelFirst != nil else { return nil }
        return cancelled ? String(localized: "Etapa 2 de 2: a ordem nova") : String(localized: "Etapa 1 de 2: cancelar a ordem atual")
    }

    private var engine: (any TradeEngine)? { TradeEngines.engine(for: item.chain) }
    private var isLimit: Bool { if case .limit = kind { return true }; return false }
    private var isCancel: Bool { if case .cancel = kind { return true }; return false }

    /// Os textos de cada etapa, por tipo: troca, ordem limite ou cancelamento.
    private func text(swap: String, limit: String, cancel: String) -> String {
        switch kind {
        case .swap: return swap
        case .limit: return limit
        case .cancel: return cancel
        }
    }

    private var assets: (sell: Asset?, buy: Asset?) {
        switch kind {
        case .swap(let request, _): return (request.sell, request.buy)
        case .limit(let request): return (request.sell, request.buy)
        case .cancel(let order, _):
            // A ordem pode ser de token fora da lista: o que a carteira conhece dele.
            return (TradedAssets.resolve(order.sellAssetID, listed: order.sell, chain: order.chain, session: session, portfolio: portfolio),
                    TradedAssets.resolve(order.buyAssetID, listed: order.buy, chain: order.chain, session: session, portfolio: portfolio))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .planning: planning
                case .review: review
                case .sending: sending
                case .waitingCancel: waitingCancel
                case .done: done
                case .unsure: unsure
                case .refused: refused
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, waits ? 0 : Space.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // A animacao de espera fica no meio da tela, nao no meio do espaco abaixo do
            // botao de fechar.
            .ignoresSafeArea(.container, edges: waits ? .vertical : [])
            .background(Palette.void.ignoresSafeArea())
            .toolbar {
                // Transmitindo, ou esperando o cancelamento da edicao confirmar (a ordem antiga ja saiu), nao fecha.
                if stage != .sending && stage != .waitingCancel {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { onClose(stage == .done || cancelled) } label: {
                            Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                        }
                        .accessibilityLabel("Fechar")
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        // O cancelamento na cadeia da ordem que a CoW diz ter recusado: a mesma revisao das ordens abertas.
        .fullScreenCover(item: $cancellingRefused) { cancel in
            TradeReviewFlow(item: cancel, onClose: { done in
                cancellingRefused = nil
                if done { onClose(cancelled) }
            })
        }
        .task {
            #if DEBUG
            if let debugStage {
                stage = debugStage
                return
            }
            #endif
            await makePlan()
        }
    }

    // MARK: Etapas

    /// Montando ou enviando: so a animacao e o texto, no centro da tela.
    private var waits: Bool { (stage == .planning && error == nil) || stage == .sending || stage == .waitingCancel }

    private var planning: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if let error {
                Text(text(swap: String(localized: "A troca não foi montada"), limit: String(localized: "A ordem não foi montada"), cancel: String(localized: "O cancelamento não foi montado")))
                    .typeStyle(.title).foregroundStyle(Palette.ink)
                Banner(kind: .failure, title: error)
                Spacer()
                PrimaryButton(title: String(localized: "Tentar de novo")) { Task { await makePlan() } }
                    .padding(.bottom, Space.xs)
            } else {
                Spacer()
                SwapProcessingIndicator(sell: assets.sell, buy: assets.buy, cancelling: isCancel).frame(maxWidth: .infinity)
                Text(text(swap: String(localized: "Recotando e simulando a troca antes de mostrar."), limit: String(localized: "Montando a ordem e conferindo os dados da rede."),
                          cancel: String(localized: "Montando o cancelamento e conferindo a ordem na rede.")))
                    .typeStyle(.body).foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    .padding(.top, Space.lg)
                Spacer()
            }
        }
    }

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let plan {
                    if let stepLine {
                        Text(stepLine).typeStyle(.note).fontWeight(.semibold).foregroundStyle(Palette.inkSoft)
                            .padding(.bottom, Space.sm)
                            .accessibilityIdentifier("etapa-edicao")
                    }
                    if !isCancel {
                        TradeDirectionHeader(sell: assets.sell, buy: assets.buy, sellAmount: plan.review.outgoing?.amount,
                                             buyMinimum: plan.review.incomingMinimum?.amount)
                            .padding(.bottom, Space.lg)
                    }
                    Text(plan.review.title).typeStyle(.title).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let fiat {
                        Text("cerca de \(Fmt.fiat(fiat, session.currency))").typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.top, 2)
                    }
                    PlanVerbatimPlate(review: plan.review, collapsible: true).padding(.top, Space.lg)
                    PlanDetailLines(review: plan.review, extra: [(String(localized: "De"), session.selectedWallet?.name ?? "")]
                        + (item.renewLimit ? [(String(localized: "Quando vencer"), String(localized: "O app avisa e pergunta se refaz, com o mesmo preço"))] : []))
                        .padding(.top, Space.lg)
                    // Na ordem limite, o aviso das duas assinaturas sai (pedido do dono, 17/10/2026).
                    if !isLimit, plan.review.transactionCount > 1 {
                        Banner(kind: .neutral, title: String(localized: "Você vai assinar \(plan.review.transactionCount) transações de uma vez"),
                               message: String(localized: "A autorização do token vai antes e a troca logo depois, em transações separadas. Se a troca não sair, a autorização continua valendo, só para este valor e só para o contrato desta troca."))
                            .padding(.top, Space.md)
                    }
                    ForEach(Array(plan.review.warnings.enumerated()), id: \.offset) { _, warning in
                        Banner(kind: .caution, title: PlanWarningText.text(warning, chain: plan.chain)).padding(.top, Space.sm)
                    }
                }
                if let error { Banner(kind: .failure, title: error).padding(.top, Space.md) }
            }
            .padding(.bottom, Space.lg)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: text(swap: String(localized: "Confirmar troca"), limit: String(localized: "Criar ordem limite"), cancel: String(localized: "Cancelar a ordem"))) {
                Task { await confirm() }
            }
                .padding(.top, Space.sm)
                .padding(.bottom, Space.xs)
                .background(Palette.void)
        }
    }

    private var sending: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Spacer()
            SwapProcessingIndicator(sell: assets.sell, buy: assets.buy, cancelling: isCancel).frame(maxWidth: .infinity)
            Text(text(swap: String(localized: "Enviando a troca"), limit: String(localized: "Enviando a ordem"), cancel: String(localized: "Enviando o cancelamento"))).typeStyle(.title).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity).padding(.top, Space.lg)
            Text(sendingNote).typeStyle(.body).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private var waitingCancel: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Spacer()
            SwapProcessingIndicator(sell: assets.sell, buy: assets.buy, cancelling: true).frame(maxWidth: .infinity)
            Text("Esperando o cancelamento confirmar na rede").typeStyle(.title).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, Space.lg)
            Text("A ordem nova é montada depois que o cancelamento da antiga confirmar.").typeStyle(.body).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    /// A troca pela CoW: o id devolvido e o UID da ordem, e a tela acompanha o
    /// preenchimento. A ordem limite nao: ela espera o preco, e o andamento fica em Ordens
    /// abertas (pedido do dono, 11/10/2026).
    private var followedOrder: (id: String, kind: OrderProgressPanel.Kind, account: DerivedAccount)? {
        guard let plan, plan.transactions.last is EIP712ValidatedMessage, let id = ids.first,
              let account = session.selectedWallet?.account(item.chain) else { return nil }
        if case .swap = kind { return (id, .swap, account) }
        return nil
    }

    @ViewBuilder
    private var done: some View {
        if case .swap = kind, followedOrder == nil, let last = ids.last {
            swapResult(last, all: ids)
        } else if let order = followedOrder {
            VStack(spacing: 0) {
                Spacer()
                OrderProgressPanel(kind: order.kind, chain: item.chain, orderID: order.id, account: order.account,
                                   sell: assets.sell, buy: assets.buy)
                Spacer()
                PrimaryButton(title: String(localized: "Concluir")) { onClose(true) }.padding(.top, Space.sm).padding(.bottom, Space.xs)
            }
        } else {
            plainDone
        }
    }

    /// O selo e o texto no meio da tela inteira, nao do espaco entre o fechar e os botoes
    /// (pedido do dono, 17/10/2026); os botoes ficam por cima, embaixo.
    private var plainDone: some View {
        VStack(spacing: 0) {
            Spacer()
            if !isLimit, !isOffchainCancel, let last = ids.last, let url = item.chain.explorerURL(tx: last) {
                Link(destination: url) {
                    Text("Ver no \(item.chain.explorerName)").typeStyle(.action)
                        .frame(maxWidth: .infinity).frame(height: Height.secondary)
                }
                .buttonStyle(SecondaryStyle())
            }
            PrimaryButton(title: String(localized: "Concluir")) { onClose(true) }.padding(.top, Space.sm).padding(.bottom, Space.xs)
        }
        .background {
            VStack(spacing: 0) {
                // A moeda da ordem e o checkmark, girando como uma moeda jogada.
                CoinFlipBadge(asset: assets.sell)
                Text(text(swap: String(localized: "Troca enviada"), limit: String(localized: "Ordem limite criada"), cancel: String(localized: "Ordem cancelada")))
                    .typeStyle(.title).foregroundStyle(Palette.ink).padding(.top, Space.lg)
                    .multilineTextAlignment(.center)
                Text(doneMessage)
                    .typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.top, Space.xs)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Um pouco acima do meio: com o botao embaixo, o meio exato parecia baixo
            // (pedido do dono, 18/10/2026).
            .offset(y: -56)
            .ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: stage == .done)
    }

    /// A troca imediata depois de enviada: a rede aceitar a transmissao nao quer dizer que a troca saiu. A
    /// tela acompanha a transacao ate a rede responder em duas fontes, e so entao diz concluida (o visto e a
    /// vibracao) ou que falhou, com a taxa da rede cobrada. Antes ela mostrava o visto logo na transmissao, e
    /// uma troca que reverteu no bloco parecia feita (moeda com taxa, 03/11/2026).
    private func swapResult(_ transaction: String, all: [String]) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                switch swapOutcome {
                case .failed(let reason, let partial):
                    Image(systemName: "xmark.circle").font(.system(size: 44)).foregroundStyle(Palette.down)
                    Text("A troca falhou na rede").typeStyle(.title).foregroundStyle(Palette.ink).padding(.top, Space.md)
                    Text(reason).typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.top, Space.xs)
                    // So diz que o valor ficou quando nenhuma parte da troca saiu (a troca dividida pode ter saido em parte).
                    Text(partial ? String(localized: "Parte da troca saiu antes da falha. Confira o saldo e a Atividade.")
                                 : String(localized: "Moedas que cobram taxa na compra ou na venda costumam falhar assim. O que você vendia continua na carteira."))
                        .typeStyle(.note).foregroundStyle(Palette.inkMuted).padding(.top, Space.sm)
                case .done(let detail):
                    CoinFlipBadge(asset: assets.sell)
                    Text("Troca concluída").typeStyle(.title).foregroundStyle(Palette.ink).padding(.top, Space.lg)
                    Text(detail ?? String(localized: "Confirmado na rede.")).typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.top, Space.xs)
                case .pending:
                    SwapProcessingIndicator(sell: assets.sell, buy: assets.buy)
                    Text("Troca enviada").typeStyle(.title).foregroundStyle(Palette.ink).padding(.top, Space.lg)
                    Text("Esperando a rede confirmar. Pode fechar: a Atividade mostra o resultado.")
                        .typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.top, Space.xs)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            Spacer()
            if let url = item.chain.explorerURL(tx: transaction) {
                Link(destination: url) {
                    Text("Ver no \(item.chain.explorerName)").typeStyle(.action)
                        .frame(maxWidth: .infinity).frame(height: Height.secondary)
                }
                .buttonStyle(SecondaryStyle())
            }
            PrimaryButton(title: String(localized: "Concluir")) { onClose(true) }.padding(.top, Space.sm).padding(.bottom, Space.xs)
        }
        .sensoryFeedback(trigger: swapOutcome) { _, now in
            switch now {
            case .done: return .success
            case .failed: return .error
            case .pending: return nil
            }
        }
        .task(id: all.joined()) { await followSwap(all) }
    }

    /// Pergunta a rede por todas as transacoes do plano a cada 5 segundos, por ate 10 minutos, ate todas
    /// confirmarem ou uma falhar (`TradeOutcome`, a mesma regra do Android).
    private func followSwap(_ transactions: [String]) async {
        guard let engine = SendEngines.engine(for: item.chain) else { return }
        var statuses: [String: TransferStatus] = [:]
        for _ in 0..<120 {
            for id in transactions where statuses[id] == nil {
                let now = await engine.status(id, chain: item.chain)
                if case .pending = now { continue }
                statuses[id] = now
            }
            let outcome = TradeOutcome.of(plan, ids: transactions, statuses: statuses)
            if outcome != .pending {
                swapOutcome = outcome
                portfolio.show(session.selectedWallet, session: session, force: true)
                return
            }
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
        }
    }

    /// Ordem da CoW com autorizacao antes: a CoW so aceita a ordem depois que a
    /// autorizacao confirma na rede, e a espera e essa.
    private var sendingNote: String {
        guard let plan, plan.transactions.last is EIP712ValidatedMessage, plan.transactions.count > 1 else {
            return String(localized: "Não feche o app até terminar.")
        }
        return String(localized: "A autorização vai primeiro. A ordem segue para a CoW assim que ela confirmar na \(item.chain.name). Não feche o app até terminar.")
    }

    // MARK: Acoes

    private var isOffchainCancel: Bool {
        if case .cancel(_, .offchain) = kind { return true }
        return false
    }

    private var doneMessage: String {
        switch kind {
        case .swap: return String(localized: "O saldo novo aparece quando a rede confirmar.")
        case .limit: return String(localized: "A ordem fica aberta até executar, vencer ou você cancelar.")
        case .cancel(_, .offchain): return String(localized: "A CoW recebeu o pedido. Se um solver já estava executando a ordem, ela ainda pode sair.")
        case .cancel(_, .onchain): return String(localized: "A ordem deixa de valer quando a rede confirmar a transação.")
        }
    }

    /// O plano nao saiu. Na troca e na ordem nova, antes de qualquer etapa assinada, o erro
    /// volta para a tela da troca; no cancelamento (e depois dele, na edicao), fica aqui.
    /// O ativo que esta etapa vende (a troca e a ordem limite); o cancelamento nao vende nada.
    private var soldAsset: Asset? {
        switch kind {
        case .swap(let request, _): return request.sell
        case .limit(let request): return request.sell
        case .cancel: return nil
        }
    }

    private func planFailed(_ message: String) {
        if let onPlanFailed, !isCancel, !cancelled { onPlanFailed(message) } else { error = message }
    }

    private func makePlan() async {
        guard let engine else {
            planFailed(String(localized: "Troca nesta rede ainda não está disponível."))
            return
        }
        error = nil
        stage = .planning
        guard let wallet = session.selectedWallet, let account = wallet.account(item.chain) else {
            planFailed(String(localized: "Esta carteira não tem conta nesta rede."))
            return
        }
        // A fila de nonces EVM desta conta, sem o que a rede ja confirmou, entra no
        // pedido: o planejador sabe o que este aparelho ja transmitiu.
        await NonceQueue.prune(session, wallet: wallet.id, chain: item.chain, address: account.address)
        let queue = NonceQueue.queue(session, wallet: wallet.id, chain: item.chain, address: account.address)
        // Uma transacao anterior desta conta que a rede ainda nao viu, ou que tira o mesmo ativo e ainda nao
        // confirmou: o plano pularia o nonce dela, ou leria o saldo de antes dela (auditoria de 03/11/2026). A
        // transacao nao vista so pesa no plano com transacao na cadeia: conferida de novo depois de montar.
        if let reason = NonceQueue.blockedReason(session, wallet: wallet.id, chain: item.chain, address: account.address, asset: soldAsset,
                                                 usesNonce: false) {
            planFailed(reason)
            return
        }
        do {
            let built: SigningPlan
            switch kind {
            case .swap(let r, let quote):
                let request = TradeRequest(walletID: r.walletID, chain: r.chain, account: r.account, sell: r.sell, buy: r.buy,
                                           amountIn: r.amountIn, slippageBasisPoints: r.slippageBasisPoints, nonceQueue: queue,
                                           inParts: r.inParts)
                built = try await engine.plan(request, quote: quote)
            case .limit(let r):
                // Editando, depois do cancelamento confirmado: a ordem antiga sai da soma das abertas.
                let request = LimitOrderRequest(walletID: r.walletID, chain: r.chain, account: r.account, sell: r.sell, buy: r.buy,
                                                amountIn: r.amountIn, minimumOut: r.minimumOut, validFor: r.validFor, nonceQueue: queue,
                                                replacing: cancelled ? item.cancelFirst?.order.id : nil)
                built = try await engine.planLimitOrder(request)
            case .cancel(let order, let via):
                built = try await engine.planCancel(order, walletID: wallet.id, account: account, via: via, nonceQueue: queue)
            }
            guard planMatches(built) else {
                planFailed(String(localized: "O plano montado não confere com a troca pedida. Nada foi assinado."))
                return
            }
            if let reason = NonceQueue.blockedReason(session, wallet: wallet.id, chain: item.chain, address: account.address, asset: nil,
                                                     usesNonce: built.transactions.contains { $0 is EVMTransaction }) {
                planFailed(reason)
                return
            }
            plan = built
            stage = .review
        } catch {
            if (error as? SendEngineError)?.isLocalNonceQueueAhead == true {
                NonceQueue.clear(session, wallet: wallet.id, chain: item.chain, address: account.address)
            }
            planFailed((error as? LocalizedError)?.errorDescription ?? String(localized: "Não foi possível montar agora. Tente de novo."))
        }
    }

    /// Desta carteira, desta rede e do tipo pedido; vende o ativo pedido, nunca mais
    /// que o valor; garante pelo menos o minimo mostrado do ativo comprado; e o que
    /// entra vai para a propria conta (auditoria 2, M1). O resto foi validado pelo
    /// planejador da rede (minimo decodificado da transacao, contrato na lista).
    private func planMatches(_ plan: SigningPlan) -> Bool {
        guard let wallet = session.selectedWallet, plan.walletID == wallet.id, plan.chain.id == item.chain.id else { return false }
        do {
            switch kind {
            case .swap(let request, let quote):
                guard plan.review.kind == .swap else { return false }
                try PlanIntentCheck.trade(plan.review, sell: request.sell, amountIn: request.amountIn, buy: request.buy,
                                          minimumOut: quote.minimumOut(inParts: request.inParts), owner: request.account.address,
                                          chain: item.chain)
            case .limit(let request):
                guard plan.review.kind == .limitOrder else { return false }
                try PlanIntentCheck.trade(plan.review, sell: request.sell, amountIn: request.amountIn, buy: request.buy,
                                          minimumOut: request.minimumOut, owner: request.account.address, chain: item.chain)
            case .cancel:
                // Cancelar nao move valor: o plano tem de ser so um cancelamento.
                guard plan.review.kind == .cancelOrder, plan.review.outgoing == nil || plan.review.outgoing?.amount == 0 else { return false }
            }
            return true
        } catch {
            return false
        }
    }

    /// O valor vendido em moeda do dono, do que o plano move: e o que a voz e o
    /// "cerca de" usam. Sem plano, a estimativa da tela anterior.
    private var fiat: Double? {
        guard let outgoing = plan?.review.outgoing else { return item.fiat }
        guard let sell = assets.sell, let price = sell.coingeckoID.flatMap({ portfolio.quotes[$0]?.price }) else { return nil }
        return Fmt.double(outgoing.amount, decimals: sell.decimals) * price
    }

    /// O mesmo valor para a voz, so do plano e com a cotacao da fonte: a estimativa da tela anterior e o preco convertido
    /// na troca de moeda nao decidem se a voz e pedida (sem valor, ela e pedida).
    private var voiceFiat: Double? {
        guard let outgoing = plan?.review.outgoing, let sell = assets.sell, sell.coingeckoID != nil,
              let price = portfolio.firmPrice(of: sell) else { return nil }
        return Fmt.double(outgoing.amount, decimals: sell.decimals) * price
    }

    private func confirm() async {
        guard let plan, let engine else { return }
        guard !plan.isExpired() else {
            await makePlan()
            error = String(localized: "Os dados da rede venceram. Confira de novo.")
            return
        }
        guard planMatches(plan) else { return }
        // Ate a assinatura: outra transacao desta conta pode ter saido depois da revisao.
        if let wallet = session.selectedWallet, let account = wallet.account(item.chain),
           let reason = NonceQueue.blockedReason(session, wallet: wallet.id, chain: item.chain, address: account.address, asset: soldAsset,
                                                 usesNonce: plan.transactions.contains { $0 is EVMTransaction }) {
            error = reason
            return
        }
        // Cancelar nao tira valor da carteira: a voz fica para o que tira.
        if !isCancel {
            guard await VoiceGate.shared.confirm(.send(fiat: voiceFiat), session: session) else { return }
        }
        // O autoteste da assinatura antes da passphrase e do PIN, fora da thread principal: com um defeito do aparelho,
        // nada e pedido a toa (o Signer confere de novo antes de abrir o cofre; revisao da decima terceira passada).
        guard (try? await Offload.run({ SigningSelfTest.passed(for: plan) })) == true else {
            error = SigningSelfTest.Failure().errorDescription
            return
        }
        // Carteira com passphrase: a passphrase antes do Face ID ou do PIN, conferida dentro
        // do assinador. Cancelar uma ordem nao tira valor: nao pede (pedido do dono, 16/10/2026).
        var typedPassphrase: SecureBytes?
        if !isCancel, PassphraseGate.needed(session.metadata.wallets.first { $0.id == plan.walletID }),
           let wallet = session.metadata.wallets.first(where: { $0.id == plan.walletID }) {
            guard let typed = await PassphraseGate.shared.ask(wallet) else { return }
            typedPassphrase = typed
        }
        defer { typedPassphrase?.wipe() }
        let checkPassphrase = typedPassphrase
        // A tentativa conta antes de o cofre conferir; com muitas erradas, espera.
        if checkPassphrase != nil, let wait = PassphraseGate.shared.begin(session, wallet: plan.walletID) {
            self.error = wait
            return
        }
        let signed: [SignedTransaction]
        do {
            guard let result = try await auth.perform(session, reason: plan.review.title, { rk in
                try Signer.sign(plan, rootKey: rk, vault: KeyServices.wallets, passphrase: checkPassphrase)
            }) else {
                if checkPassphrase != nil { PassphraseGate.shared.refund(session, wallet: plan.walletID) }
                return
            }
            signed = result
            // A passphrase confere (o assinador assinou): a conta zera, e o buffer sai ja.
            if checkPassphrase != nil {
                PassphraseGate.shared.passed(session, wallet: plan.walletID)
                PassphraseGate.shared.confirmGrace(plan.walletID)
            }
            checkPassphrase?.wipe()
        } catch {
            checkPassphrase?.wipe()
            if (error as? Signer.Failure) == .passphraseMismatch {
                PassphraseGate.shared.failed(session, wallet: plan.walletID)
            } else if checkPassphrase != nil {
                // Parou antes da passphrase (PIN errado, cofre): nada foi conferido, a tentativa volta.
                PassphraseGate.shared.refund(session, wallet: plan.walletID)
            }
            self.error = (error as? Signer.Failure) == .passphraseMismatch ? PassphraseGate.mismatchMessage
                : AuthCoordinator.refusalMessage(error) ?? (error as? LocalizedError)?.errorDescription
                ?? text(swap: String(localized: "A troca não saiu. Nada foi debitado."), limit: String(localized: "A ordem não saiu. Nada foi debitado."),
                        cancel: String(localized: "O cancelamento não saiu. A ordem continua aberta."))
            stage = .review
            return
        }
        await transmit(signed, plan: plan, engine: engine)
    }

    /// Envia o que foi assinado. Erro aqui nao quer dizer que nada saiu: a resposta pode
    /// ter se perdido depois de a rede (ou a CoW) receber. A tela diz isso e so oferece
    /// enviar de novo os mesmos bytes, que tem o mesmo id e nao pagam duas vezes.
    private func transmit(_ signed: [SignedTransaction], plan: SigningPlan, engine: any TradeEngine) async {
        // A epoca dos avisos antes de tudo: um apagar tudo durante o envio nao acompanha a ordem (decima primeira
        // passada), e a leitura, que espera o ator, fica antes da trava, e nao entre ela e o envio (decima segunda).
        let noticeEpoch = await LimitOrderWatch.shared.currentEpoch()
        // Travou entre assinar e enviar: nada sai (ver o envio). Destravado, o dono envia de novo.
        guard session.phase == .unlocked else {
            error = WalletError.locked.errorDescription
            stage = unsureSigned == nil ? .review : .unsure
            return
        }
        // A carteira com passphrase fica fora dos avisos de ordem, decidido aqui, antes de enviar, pela carteira do
        // plano: travado durante o envio, a carteira escolhida vira nil, e `nil != true` acompanhava a ordem dela
        // (sexta passada da auditoria de 03/11/2026). Sem a carteira, fica de fora.
        let orderNotices = session.metadata.wallets.first(where: { $0.id == plan.walletID })?.hasPassphrase == false
        if let wallet = session.selectedWallet, let account = wallet.account(item.chain) {
            // A troca imediata na Ethereum sai pela rota privada (protecao de MEV), e a poda espera mais por ela. A
            // "em partes" e da CoW: a autorizacao e o embrulho dela saem pela publica.
            var swapOnEthereum = false
            if case .swap(let request, _) = kind { swapOnEthereum = item.chain.evmChainID == 1 && !request.inParts }
            NonceQueue.record(session, wallet: wallet.id, chain: item.chain, address: account.address, plan: plan, signed: signed,
                              sells: soldAsset?.id, privately: swapOnEthereum)
        }
        stage = .sending
        do {
            if !isCancel { VoiceGate.shared.noteSendTransmitted(session: session) }
            ids = try await engine.submit(signed, plan: plan)
            unsureSigned = nil
            // Saiu: o que fica anotado vale mesmo que o app tenha travado durante o envio.
            switch kind {
            case .swap(let request, _): session.whenUnlocked { TradedAssets.remember([request.sell, request.buy], session: $0) }
            case .limit(let request): session.whenUnlocked { TradedAssets.remember([request.sell, request.buy], session: $0) }
            // O cancelamento saiu: a ordem sai da lista ate a rede responder. Os avisos de executada e de
            // vencimento so saem com o cancelamento na cadeia confirmado (`settleCancellations`, ou a ordem
            // que some da lista); falhou, a ordem volta.
            case .cancel(let order, let via):
                OpenOrdersBook.shared.markCancelling(order.id, transaction: via == .onchain ? ids.last : nil, chain: order.chain)
            }
            if case .limit(let request) = kind, let orderID = ids.first {
                let old = item.replacesRenewal, renew = item.renewLimit
                let walletID = plan.walletID
                session.whenUnlocked { session in
                    // Depois de um apagar tudo, o destravar seguinte e o de outra carteira: a renovacao da ordem antiga,
                    // cujo UID traz o endereco antigo, nao entra nela (decima segunda passada da auditoria de 03/11/2026).
                    guard session.metadata.wallets.contains(where: { $0.id == walletID }) else { return }
                    if let old { LimitRenewalCenter.shared.forget(old, session: session) }
                    if renew { LimitRenewalCenter.shared.register(orderID: orderID, request: request, session: session, notify: orderNotices) }
                }
                // Avisos de 24 horas antes de vencer e de executada: pede a permissao de
                // notificacao aqui, com a ordem na tela, se ainda nao pediu. A carteira com
                // passphrase fica de fora: o UID traz o endereco, e o arquivo dos avisos abre
                // com o iPhone bloqueado (revisao da auditoria 4, C7-03).
                if orderNotices, CoWProtocol.supports(request.chain),
                   let uid = Hex.decode(orderID), let validTo = CoWProtocol.validTo(ofUID: uid) {
                    let chainID = request.chain.id
                    Task {
                        _ = await PriceAlertCenter.requestPermission()
                        await LimitOrderWatch.shared.track(id: orderID, chainID: chainID, expiresAt: Date(timeIntervalSince1970: TimeInterval(validTo)),
                                                           epoch: noticeEpoch)
                    }
                }
            }
            // Edicao: o cancelamento saiu; a etapa 2 monta a ordem nova na mesma tela, depois de ele
            // confirmar na rede (o pedido a CoW fora da cadeia nao tem transacao para esperar).
            if item.cancelFirst != nil, !cancelled, case .cancel(let order, let via) = kind {
                OpenOrdersBook.shared.markCancelling(order.id)
                if via == .onchain, let transaction = ids.last {
                    stage = .waitingCancel
                    switch await CancellationWait.untilConfirmed(transaction, chain: item.chain) {
                    case .confirmed: break
                    case .failed(let reason):
                        // A transacao do cancelamento falhou: a ordem antiga continua aberta, e nada novo e montado.
                        OpenOrdersBook.shared.unmarkCancelling(order.id)
                        refusedReason = reason
                        refusedNotes = []
                        refusedOrder = nil
                        stage = .refused
                        return
                    case .timedOut:
                        // Sem confirmar no prazo: o reenvio dos mesmos bytes, como em qualquer envio incerto. A
                        // tela segue acompanhando o cancelamento, e a etapa 2 continua sozinha quando ele
                        // confirmar (terceira passada da auditoria de 03/11/2026).
                        unsureSigned = signed
                        unsureDetail = nil
                        stage = .unsure
                        Task {
                            guard case .confirmed = await CancellationWait.untilConfirmed(transaction, chain: item.chain),
                                  stage == .unsure, !cancelled else { return }
                            await continueEdit(after: order)
                        }
                        return
                    }
                }
                await continueEdit(after: order)
                return
            }
            stage = .done
            portfolio.show(session.selectedWallet, session: session, force: true)
        } catch let refusal as TradeRefusedForSure {
            // A CoW diz que recusou, com o motivo: enviar de novo nao muda nada. O que entrou na rede
            // antes e a ordem assinada ficam na tela, e a ordem continua acompanhada.
            ids = []
            unsureSigned = nil
            refusedReason = refusal.reason
            // So o cancelamento na cadeia foi esperado ate confirmar: o pedido a CoW fora dela nao tem como.
            // O pedido fora dela foi aceito pela CoW, sem confirmacao na cadeia: a nota diz isso, e onde conferir
            // (decima primeira passada).
            refusedNotes = refusal.notes + (!cancelled || item.cancelFirst == nil ? [] : item.cancelFirst?.via == .onchain
                ? [String(localized: "A ordem anterior já tinha sido cancelada.")]
                : [String(localized: "O pedido de cancelamento da ordem anterior foi aceito pela CoW. Confira em Ordens abertas.")])
            refusedOrder = refusal.signedOrder
            if let order = refusal.signedOrder { watchRefused(order, walletID: plan.walletID, notices: orderNotices, epoch: noticeEpoch) }
            // Os ativos ficam lembrados: a ordem guardada mostra nome e casas mesmo depois de sair do saldo.
            if case .limit(let request) = kind { session.whenUnlocked { TradedAssets.remember([request.sell, request.buy], session: $0) } }
            stage = .refused
        } catch let uncertain as TradeSubmissionUncertain {
            // A ordem assinada saiu para a CoW sem resposta certa: o mesmo incerto, mais o que ja entrou
            // na rede, o acompanhamento e o cancelamento na cadeia (segunda passada da auditoria de 03/11/2026).
            ids = signed.map(\.id)
            unsureSigned = signed
            unsureDetail = uncertain.detail
            refusedNotes = uncertain.notes
            refusedOrder = uncertain.signedOrder
            watchRefused(uncertain.signedOrder, walletID: plan.walletID, notices: orderNotices, epoch: noticeEpoch)
            if case .limit(let request) = kind { session.whenUnlocked { TradedAssets.remember([request.sell, request.buy], session: $0) } }
            stage = .unsure
        } catch {
            ids = signed.map(\.id)
            unsureSigned = signed
            unsureDetail = (error as? LocalizedError)?.errorDescription
            stage = .unsure
        }
    }

    /// Edicao: o cancelamento da ordem antiga confirmou (ou foi o pedido a CoW, que nao tem transacao);
    /// a etapa 2 monta a ordem nova na mesma tela.
    private func continueEdit(after order: OpenOrder) async {
        Task { await LimitOrderWatch.shared.forget(order.id) }
        cancelled = true
        plan = nil
        ids = []
        unsureSigned = nil
        portfolio.show(session.selectedWallet, session: session, force: true)
        await makePlan()
    }

    /// A recusa da CoW: o titulo diz que e a palavra dela, o texto, o motivo exato, e as notas, o que
    /// ja entrou na rede. Com a ordem assinada, o cancelamento na cadeia.
    private var refused: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Image(systemName: "xmark.circle").font(.system(size: 44)).foregroundStyle(Palette.down)
            Text(text(swap: String(localized: "A CoW diz que recusou a ordem"), limit: String(localized: "A CoW diz que recusou a ordem"),
                      cancel: String(localized: "O cancelamento não saiu. A ordem continua aberta.")))
                .typeStyle(.title).foregroundStyle(Palette.ink).padding(.top, Space.md)
                .fixedSize(horizontal: false, vertical: true)
            if let refusedReason {
                Text(refusedReason).typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.top, Space.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(refusedNotes, id: \.self) { note in
                Text(note).typeStyle(.note).foregroundStyle(Palette.inkSoft).padding(.top, Space.sm)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let refusedOrder {
                SecondaryButton(title: String(localized: "Cancelar ordem limite na cadeia")) {
                    cancellingRefused = Item(kind: .cancel(refusedOrder, .onchain), chain: refusedOrder.chain, fiat: nil)
                }
                .padding(.bottom, Space.sm)
            }
            PrimaryButton(title: String(localized: "Voltar")) { onClose(cancelled) }
                .padding(.bottom, Space.xs)
        }
    }

    /// A ordem assinada que a CoW diz ter recusado segue nos avisos de executada e de vencimento,
    /// como uma ordem criada (fora a carteira com passphrase, como no envio).
    private func watchRefused(_ order: OpenOrder, walletID: UUID, notices: Bool, epoch: Int) {
        // Guardada ate vencer: aparece em Ordens abertas com o cancelamento na cadeia, tambem depois de
        // fechar esta tela, ate a cadeia dizer que terminou (segunda passada da auditoria de 03/11/2026).
        if let record = SignedOrderRecord(order, walletID: walletID) {
            session.whenUnlocked { session in
                // A carteira removida enquanto travado nao ganha a ordem de volta.
                guard session.metadata.wallets.contains(where: { $0.id == walletID }) else { return }
                session.metadata.signedOrders = SignedOrders.adding(record, to: session.metadata.signedOrders)
                try? session.persist()
            }
        }
        guard notices, CoWProtocol.supports(order.chain),
              let uid = Hex.decode(order.id), let validTo = CoWProtocol.validTo(ofUID: uid) else { return }
        let id = order.id, chainID = order.chain.id
        Task {
            _ = await PriceAlertCenter.requestPermission()
            await LimitOrderWatch.shared.track(id: id, chainID: chainID, expiresAt: Date(timeIntervalSince1970: TimeInterval(validTo)), epoch: epoch)
        }
    }

    private var unsure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Image(systemName: "questionmark.circle").font(.system(size: 44)).foregroundStyle(Palette.caution)
            Text(text(swap: String(localized: "Não deu para confirmar a troca"), limit: String(localized: "Não deu para confirmar a ordem"),
                      cancel: String(localized: "Não deu para confirmar o cancelamento")))
                .typeStyle(.title).foregroundStyle(Palette.ink).padding(.top, Space.md)
            Text("A resposta não veio com certeza, e o que foi assinado pode já estar a caminho. Não monte de novo: enviar de novo usa os mesmos dados e não paga duas vezes. Confira na Atividade antes de qualquer outra operação.")
                .typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.top, Space.xs)
                .fixedSize(horizontal: false, vertical: true)
            if let unsureDetail {
                Text(unsureDetail).typeStyle(.note).foregroundStyle(Palette.inkMuted).padding(.top, Space.sm)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A ordem que pode estar com a CoW: o que ja entrou na rede e o cancelamento na cadeia.
            if stage == .unsure, refusedOrder != nil {
                ForEach(refusedNotes, id: \.self) { note in
                    Text(note).typeStyle(.note).foregroundStyle(Palette.inkSoft).padding(.top, Space.sm)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if let refusedOrder {
                SecondaryButton(title: String(localized: "Cancelar ordem limite na cadeia")) {
                    cancellingRefused = Item(kind: .cancel(refusedOrder, .onchain), chain: refusedOrder.chain, fiat: nil)
                }
                .padding(.bottom, Space.sm)
            }
            if !isLimit, !isOffchainCancel, let last = ids.last, let url = item.chain.explorerURL(tx: last) {
                Link(destination: url) {
                    Text("Procurar no \(item.chain.explorerName)").typeStyle(.action)
                        .frame(maxWidth: .infinity).frame(height: Height.secondary)
                }
                .buttonStyle(SecondaryStyle())
            }
            PrimaryButton(title: String(localized: "Enviar de novo")) {
                guard let signed = unsureSigned, let plan, let engine else { return }
                Task { await transmit(signed, plan: plan, engine: engine) }
            }
            .padding(.top, Space.sm)
            TertiaryButton(title: String(localized: "Fechar e acompanhar na Atividade")) { onClose(true) }.frame(maxWidth: .infinity)
                .padding(.bottom, Space.xs)
        }
    }
}
