import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import EscaliburNetwork
import Foundation

/// A ponte da aba Trocar: levar a mesma moeda da sua conta numa rede para a sua conta em outra (o
/// `BridgeFormModel`, o `BridgeReviewFlow` e o `BridgeCenter` do iOS, sem a interface). A revisao cota
/// de novo ao montar, e o plano e conferido contra o pedido (`PlanIntentCheck.bridge`) antes de
/// mostrar e de novo antes de assinar. As pontes ficam nos metadados (`BridgeRecord`, sem segredo) e
/// sao acompanhadas enquanto o app esta aberto; a chegada so conta conferida no destino.
final class Ponte: @unchecked Sendable {
    enum Etapa: String, Encodable { case formulario, montando, revisao, enviando, enviada, incerta }

    static let shared = Ponte()
    private let trava = NSLock()
    private init() {}

    // MARK: O formulario

    private var carteiraID: UUID?
    private var de: Chain = .base
    private var para: Chain = .arbitrum
    private var moeda: BridgeAsset = .usdc
    private var textoDoValor = ""
    private var versaoDoValor = 0
    private var rota: BridgeRoute = .cctpFast
    private var opcoes: [ValidatedBridgeQuote] = []
    private var cotando = false
    private var erro: String?

    // MARK: A revisao

    private var etapa: Etapa = .formulario
    private var rodada = 0
    private var pedido: (intencao: BridgeIntent, rota: BridgeRoute)?
    private var cotada: ValidatedBridgeQuote?
    private var plano: SigningPlan?
    private var erroDaRevisao: String?
    private var falhaDaMontagem: String?
    private var valorEmMoeda: Double?
    private var registro: UUID?
    private var assinadoIncerto: [SignedTransaction]?
    private var detalheIncerto: String?

    // MARK: O acompanhamento

    /// O ultimo andamento lido de cada ponte em curso, por id.
    private var andamentos: [UUID: BridgeEngine.Progress] = [:]
    private var lendo = false

    private var carteira: WalletMeta? { Sessao.shared.metadata.selectedWallet }
    private var deNaPonte: BridgeChain? { BridgeAllowlist.chain(de) }
    private var paraNaPonte: BridgeChain? { BridgeAllowlist.chain(para) }
    private var moedasDaRota: [BridgeAsset] { BridgeEngine.assets(from: de, to: para) }
    private var ativoQueSai: Asset? { deNaPonte.flatMap { moeda.asset(on: $0) } }
    private var ativoQueChega: Asset? { paraNaPonte.flatMap { moeda.asset(on: $0) } }
    /// As casas do que sai e do que chega: o USDC e o USDT da BNB tem 18, os outros 6.
    private var casasQueSaem: Int { deNaPonte.map { moeda.decimals(on: $0) } ?? 18 }
    private var casasQueChegam: Int { paraNaPonte.map { moeda.decimals(on: $0) } ?? 18 }

    private var quantidade: BigUInt? {
        guard let lido = TradeDecimal(textoDoValor), lido.scale <= casasQueSaem else { return nil }
        return lido.mantissa * BigUInt.power(of: 10, casasQueSaem - lido.scale)
    }

    /// A opcao escolhida, ou a primeira cotada.
    private var escolhida: ValidatedBridgeQuote? { opcoes.first { $0.route == rota } ?? opcoes.first }

    private var chave: String { "\(carteiraID?.uuidString ?? "")|\(de.id)|\(para.id)|\(moeda.rawValue)|\(textoDoValor)" }

    /// Chamar com a trava.
    private func acompanharCarteira() {
        let id = carteira?.id
        guard id != carteiraID else { return }
        carteiraID = id
        opcoes = []
        erro = nil
    }

    /// Chamar com a trava.
    private func mudou() {
        if !moedasDaRota.contains(moeda) { moeda = moedasDaRota.first ?? .usdc }
        opcoes = []
        erro = nil
    }

    private var saldo: BigUInt {
        guard let ativo = ativoQueSai, let carteira else { return BigUInt() }
        return Saldos.shared.saldo(de, carteira: carteira.id)?.holdings.first { $0.asset.id == ativo.id }?.amount ?? BigUInt()
    }

    private var passou: Bool { (quantidade ?? BigUInt()) > saldo }

    // MARK: Mudar o pedido

    func definir(_ mudanca: JSONValue) {
        trava.withLock {
            acompanharCarteira()
            guard etapa == .formulario else { return }
            let antes = textoDoValor
            defer { if textoDoValor != antes, mudanca["valor"] == nil { versaoDoValor += 1 } }
            if let id = mudanca["de"]?.stringValue, let rede = BridgeEngine.chains.first(where: { $0.id == id }) {
                if rede.id == para.id { para = de }
                de = rede
                // A Tron so recebe USDT, e so da Ethereum e da Arbitrum: de outra origem, o destino
                // volta a uma rede EVM.
                if para == .tron, !BridgeEngine.assets(from: rede, to: .tron).contains(.usdt) { para = rede == .arbitrum ? .base : .arbitrum }
                mudou()
            }
            if let id = mudanca["para"]?.stringValue, let rede = BridgeEngine.destinations.first(where: { $0.id == id }) {
                if rede.id == de.id { de = para }
                para = rede
                // Para a Tron: USDT, saindo da Ethereum ou da Arbitrum.
                if rede == .tron {
                    if !BridgeEngine.assets(from: de, to: .tron).contains(.usdt) { de = .ethereum }
                    moeda = .usdt
                }
                mudou()
            }
            // A Tron nunca e origem: com ela num dos lados, inverter nao faz sentido.
            if mudanca["inverter"]?.boolValue == true, de != .tron, para != .tron {
                swap(&de, &para)
                mudou()
            }
            if let nome = mudanca["moeda"]?.stringValue, let nova = BridgeAsset(rawValue: nome), moedasDaRota.contains(nova) {
                moeda = nova
                textoDoValor = ""
                mudou()
            }
            if let texto = mudanca["valor"]?.stringValue { textoDoValor = String(texto.prefix(40)) }
            if let fracao = mudanca["fracao"]?.doubleValue {
                let tido = saldo
                var parte = fracao >= 1 ? tido : tido * BigUInt(UInt64((min(max(fracao, 0), 1) * 100).rounded())) / BigUInt(100)
                // ETH nativo: deixa o gas do deposito na conta (na BNB o ETH e token, e o gas e BNB).
                if let origem = deNaPonte, moeda.isNativeInput(on: origem), fracao >= 1 {
                    let reserva = BigUInt(decimal: de == .ethereum ? "5000000000000000" : "300000000000000") ?? BigUInt()
                    parte = parte > reserva ? parte - reserva : BigUInt()
                }
                textoDoValor = Fmt.decimalSimples(parte, casas: casasQueSaem)
            }
            if let nome = mudanca["rota"]?.stringValue, let nova = BridgeRoute(rawValue: nome) { rota = nova }
            if textoDoValor != antes || mudanca["de"] != nil || mudanca["para"] != nil || mudanca["moeda"] != nil {
                opcoes = []
                erro = nil
            }
        }
    }

    // MARK: Cotar

    /// As opcoes da ponte para o pedido `pedida` (a `chave` que a interface viu). A resposta de um
    /// pedido que ja mudou nao entra.
    func cotar(_ pedida: String) async {
        let preparo = trava.withLock { () -> (BridgeIntent?, String?)? in
            acompanharCarteira()
            guard etapa == .formulario, pedida == chave, let carteira, !carteira.isWatchOnly, let quantidade, !quantidade.isZero,
                  let conta = carteira.account(de), let dono = try? EVMAddress(conta.address) else { return nil }
            // Na Tron, quem recebe e a conta Tron desta carteira.
            var tron: TronAddress?
            if para == .tron {
                guard let conta = carteira.account(.tron), let endereco = TronAddress(base58: conta.address) else {
                    return (nil, Textos.t("Esta carteira não tem conta na Tron para receber."))
                }
                tron = endereco
            }
            do {
                let intencao = try BridgeIntent(owner: dono, asset: moeda, from: de, to: para, amount: quantidade, tronRecipient: tron)
                cotando = true
                return (intencao, nil)
            } catch let recusa as BridgeRefusal {
                return (nil, Self.textoDaRecusa(recusa))
            } catch {
                return (nil, Textos.t("Não foi possível cotar a ponte agora."))
            }
        }
        guard let (intencao, falha) = preparo else { return }
        guard let intencao else {
            trava.withLock { if pedida == chave { erro = falha } }
            return
        }
        do {
            let novas = try await BridgeEngine.shared.quotes(intencao)
            trava.withLock {
                guard pedida == chave else { return }
                opcoes = novas
                if !novas.contains(where: { $0.route == rota }), let primeira = novas.first { rota = primeira.route }
            }
        } catch let recusa as BridgeRefusal {
            trava.withLock { if pedida == chave { erro = Self.textoDaRecusa(recusa) } }
        } catch {
            trava.withLock {
                if pedida == chave { erro = (error as? LocalizedError)?.errorDescription ?? Textos.t("Não foi possível cotar a ponte agora.") }
            }
        }
        trava.withLock { if pedida == chave { cotando = false } }
    }

    /// O texto das recusas que acontecem antes da cotacao (no pedido).
    static func textoDaRecusa(_ recusa: BridgeRefusal) -> String {
        switch recusa {
        case .aboveBurnLimit: return Textos.t("O CCTP da Circle leva até 10 milhões de USDC por vez. Faça em partes.")
        case .unsupportedRoute: return Textos.t("A ponte ainda não leva esta moeda entre estas redes.")
        case .sameChain: return Textos.t("Escolha redes diferentes.")
        default: return Textos.t("A ponte recusou este pedido.")
        }
    }

    // MARK: O botao

    private var botao: (titulo: String, ligado: Bool) {
        guard let quantidade, !quantidade.isZero else { return (Textos.t("Digite um valor"), false) }
        if passou { return (preencher(Textos.t("Saldo de %@ insuficiente na %@"), moeda.symbol, de.name), false) }
        if cotando, opcoes.isEmpty { return (Textos.t("Cotando a ponte"), false) }
        return (Textos.t("Revisar ponte"), carteira?.isWatchOnly == false && escolhida != nil)
    }

    // MARK: Revisar

    func revisar() async {
        let numero = trava.withLock { () -> Int? in
            acompanharCarteira()
            guard etapa == .formulario, botao.ligado, let opcao = escolhida else { return nil }
            pedido = (opcao.intent, opcao.route)
            valorEmMoeda = ativoQueSai.flatMap { Saldos.shared.preco($0) }.map { Saldos.decimal(opcao.intent.amount, casas: casasQueSaem) * $0 }
            cotada = nil
            plano = nil
            erroDaRevisao = nil
            falhaDaMontagem = nil
            registro = nil
            assinadoIncerto = nil
            detalheIncerto = nil
            rodada += 1
            etapa = .montando
            return rodada
        }
        guard let numero else { return }
        avisar()
        await montar(numero)
    }

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

    /// A cotacao vale 60 segundos: a revisao cota de novo ao montar. O erro fica na revisao, com o
    /// tentar de novo.
    private func montar(_ numero: Int) async {
        let preparo = trava.withLock { () -> (BridgeIntent, BridgeRoute, WalletMeta)? in
            guard rodada == numero, etapa == .montando, let pedido, let carteira, !carteira.isWatchOnly else { return nil }
            return (pedido.intencao, pedido.rota, carteira)
        }
        guard let (intencao, rotaPedida, carteira) = preparo else { return }
        guard let conta = carteira.account(intencao.from.chain), let destino = carteira.account(intencao.to.chain) else {
            trava.withLock { if rodada == numero { falhaDaMontagem = Textos.t("Esta carteira não tem conta nas duas redes.") } }
            return
        }
        let origem = intencao.from.chain
        await FilaDeNonces.podar(carteira: carteira.id, rede: origem, endereco: conta.address)
        let fila = FilaDeNonces.fila(Sessao.shared.metadata, carteira: carteira.id, rede: origem, endereco: conta.address)
        do {
            let novas = try await BridgeEngine.shared.quotes(intencao)
            guard let fresca = novas.first(where: { $0.route == rotaPedida }) ?? novas.first else {
                trava.withLock { if rodada == numero { falhaDaMontagem = Textos.t("A ponte não cotou esta rota agora. Tente de novo.") } }
                return
            }
            let novo = try await BridgeEngine.shared.plan(fresca, walletID: carteira.id, account: conta, destination: destino, nonceQueue: fila)
            trava.withLock {
                guard rodada == numero, etapa == .montando else { return }
                guard confere(novo, cotada: fresca) else {
                    falhaDaMontagem = Textos.t("O plano montado não confere com a ponte pedida. Nada foi assinado.")
                    return
                }
                cotada = fresca
                plano = novo
                etapa = .revisao
            }
        } catch {
            if (error as? SendEngineError)?.isLocalNonceQueueAhead == true {
                FilaDeNonces.esquecer(carteira: carteira.id, rede: origem, endereco: conta.address)
            }
            trava.withLock {
                guard rodada == numero, etapa == .montando else { return }
                falhaDaMontagem = (error as? LocalizedError)?.errorDescription ?? Textos.t("Não foi possível montar agora. Tente de novo.")
            }
        }
    }

    /// Desta carteira e da rede de origem; sai exatamente o valor pedido; chega pelo menos o minimo
    /// mostrado, na rede de destino; e quem recebe e a propria conta. Chamar com a trava.
    private func confere(_ plano: SigningPlan, cotada: ValidatedBridgeQuote) -> Bool {
        guard let pedido, let carteira, plano.walletID == carteira.id, plano.chain.id == pedido.intencao.from.chain.id,
              cotada.intent == pedido.intencao,
              let vende = pedido.intencao.asset.asset(on: pedido.intencao.from), let recebe = pedido.intencao.asset.asset(on: pedido.intencao.to)
        else { return false }
        let intencao = pedido.intencao
        return (try? PlanIntentCheck.bridge(plano.review, sell: vende, amount: intencao.amount, from: intencao.from.chain, receive: recebe,
                                            minimumOut: cotada.minimumReceived, to: intencao.to.chain, owner: intencao.recipientText)) != nil
    }

    // MARK: Assinar e transmitir

    func assinar(_ credencial: Credencial, passphrase: SecureBytes?, folga: Int?) async throws {
        defer { passphrase?.wipe() }
        let preparo = trava.withLock { () -> (SigningPlan, ValidatedBridgeQuote, Int, Bool)? in
            erroDaRevisao = nil
            guard etapa == .revisao, let plano, let cotada else { return nil }
            guard confere(plano, cotada: cotada) else {
                erroDaRevisao = Textos.t("O plano montado não confere com a ponte pedida. Nada foi assinado.")
                return nil
            }
            if plano.isExpired() {
                self.plano = nil
                etapa = .montando
                return (plano, cotada, rodada, true)
            }
            return (plano, cotada, rodada, false)
        }
        guard let (plano, cotada, numero, vencido) = preparo else {
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
        if PortaDaPassphrase.precisa(dona), passphrase == nil {
            credencial.zerar()
            throw Nucleo.Falha(erro: "envio.pedePassphrase")
        }
        let conferir = PortaDaPassphrase.pede(dona) ? passphrase : nil
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
        await transmitir(assinado, plano: plano, cotada: cotada, numero: numero)
    }

    private func transmitir(_ assinado: [SignedTransaction], plano: SigningPlan, cotada: ValidatedBridgeQuote, numero: Int) async {
        guard trava.withLock({ () -> Bool in
            guard rodada == numero else { return false }
            etapa = .enviando
            return true
        }) else { return }
        if let conta = Sessao.shared.metadata.wallets.first(where: { $0.id == plano.walletID })?.account(plano.chain) {
            FilaDeNonces.anotar(carteira: plano.walletID, rede: plano.chain, endereco: conta.address, plano: plano, assinado: assinado)
        }
        avisar()
        do {
            let hash = try await BridgeEngine.shared.submit(assinado, plan: plano)
            let novo = BridgeRecord(quote: cotada, walletID: plano.walletID, depositTxHash: hash)
            guardar(novo)
            trava.withLock {
                assinadoIncerto = nil
                registro = novo.id
                etapa = .enviada
            }
        } catch {
            // O deposito pode ter saido: registrado pelo hash local, a ponte e acompanhada igual, e
            // some sozinha se a rede nunca viu a transacao.
            var incerto: UUID?
            if let ultimo = assinado.last {
                let novo = BridgeRecord(quote: cotada, walletID: plano.walletID, depositTxHash: ultimo.id)
                guardar(novo)
                incerto = novo.id
            }
            trava.withLock {
                assinadoIncerto = assinado
                detalheIncerto = (error as? LocalizedError)?.errorDescription
                registro = incerto
                etapa = .incerta
            }
        }
    }

    func retransmitir() async {
        let preparo = trava.withLock { () -> ([SignedTransaction], SigningPlan, ValidatedBridgeQuote, Int)? in
            guard etapa == .incerta, let assinadoIncerto, let plano, let cotada else { return nil }
            return (assinadoIncerto, plano, cotada, rodada)
        }
        guard let (assinado, plano, cotada, numero) = preparo else { return }
        await transmitir(assinado, plano: plano, cotada: cotada, numero: numero)
    }

    /// Fecha a revisao. Transmitindo, nao fecha. Depois de enviada, o valor do formulario sai.
    func fechar() {
        trava.withLock {
            guard etapa != .enviando else { return }
            if etapa == .enviada || etapa == .incerta {
                textoDoValor = ""
                versaoDoValor += 1
                opcoes = []
            }
            etapa = .formulario
            rodada += 1
            plano = nil
            cotada = nil
            pedido = nil
            erroDaRevisao = nil
            falhaDaMontagem = nil
        }
    }

    // MARK: As pontes guardadas

    /// Guarda as 50 mais recentes: o resto ja esta na Atividade das duas redes.
    private func guardar(_ novo: BridgeRecord) {
        try? Sessao.shared.alterar { metadata in
            var lista = metadata.bridges ?? []
            lista.removeAll { $0.depositTxHash == novo.depositTxHash }
            lista.append(novo)
            metadata.bridges = Array(lista.sorted { $0.createdAt > $1.createdAt }.prefix(50))
        }
        trava.withLock { andamentos[novo.id] = .depositPending }
    }

    private func registros() -> [BridgeRecord] {
        let metadata = Sessao.shared.metadata
        guard let carteira = metadata.selectedWallet else { return [] }
        return (metadata.bridges ?? []).filter { $0.walletID == carteira.id }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Le o andamento das pontes em curso. Chegada e reembolso conferidos ficam gravados.
    func atualizarPontes() async {
        guard trava.withLock({ () -> Bool in
            guard !lendo else { return false }
            lendo = true
            return true
        }) else { return }
        defer { trava.withLock { lendo = false } }
        for registro in registros() where registro.state == .pending {
            guard let lido = try? await BridgeEngine.shared.progress(registro) else { continue }
            trava.withLock { andamentos[registro.id] = lido }
            switch lido {
            case .arrived(let hash, let quantia): assentar(registro.id, estado: .arrived, hash: hash, quantia: quantia)
            case .refunded(let hash): assentar(registro.id, estado: .refunded, hash: hash, quantia: nil)
            case .depositFailed: assentar(registro.id, estado: .failed, hash: nil, quantia: nil)
            default: break
            }
        }
    }

    private func assentar(_ id: UUID, estado: BridgeRecord.State, hash: String?, quantia: BigUInt?) {
        try? Sessao.shared.alterar { metadata in
            guard var lista = metadata.bridges, let indice = lista.firstIndex(where: { $0.id == id }) else { return }
            lista[indice].state = estado
            lista[indice].settledTxHash = hash
            lista[indice].receivedAmount = quantia?.decimalString
            metadata.bridges = lista
        }
    }

    /// O texto do andamento de uma ponte, para a lista e o painel.
    private func texto(_ registro: BridgeRecord, _ andamento: BridgeEngine.Progress?) -> (titulo: String, detalhe: String, feito: Bool) {
        let origem = registro.from?.chain.name ?? registro.fromChainID
        let destino = registro.to?.chain.name ?? registro.toChainID
        switch registro.state {
        case .arrived:
            let quantia = registro.receivedAmount.flatMap(BigUInt.init(decimal:)).map {
                Fmt.cripto($0, casas: registro.to.map { registro.asset.decimals(on: $0) } ?? 18, simbolo: registro.asset.symbol)
            } ?? registro.asset.symbol
            return (preencher(Textos.t("Chegou na %@"), destino), preencher(Textos.t("%@, conferido na rede de destino."), quantia), true)
        case .refunded:
            return (preencher(Textos.t("Devolvido na %@"), origem),
                    Textos.t("Nenhum relayer entregou no prazo, e o Across devolveu o depósito para a sua conta."), true)
        case .failed:
            return (Textos.t("O depósito não saiu"), preencher(Textos.t("A transação falhou na %@. Só a taxa de rede foi cobrada."), origem), true)
        case .pending:
            switch andamento {
            case .depositPending?, nil:
                return (preencher(Textos.t("Confirmando na %@"), origem), Textos.t("O depósito está entrando na rede."), false)
            case .needsClaim?:
                return (Textos.t("A entrega da Circle falhou"),
                        Textos.t("O USDC queimado só pode ser cunhado para a sua conta. Abra de novo mais tarde; se continuar assim, a carteira resgata com a sua assinatura."), false)
            case .mismatch?:
                return (Textos.t("A entrega não confere"), Textos.t("O destino mostrou algo diferente do que você assinou. Confira a Atividade das duas redes."), false)
            default:
                if registro.route == .usdt0 {
                    return (Textos.t("A caminho da Tron"),
                            preencher(Textos.t("A LayerZero espera a confirmação na %@ e o contrato da Tether entrega o USDT na sua conta Tron, em uns minutos."), origem), false)
                }
                if registro.route.isCCTP {
                    return (preencher(Textos.t("A caminho da %@"), destino), registro.route == .cctpFast
                        ? Textos.t("A Circle atesta e entrega em menos de 1 minuto.")
                        : preencher(Textos.t("A Circle espera a finalidade da %@, uns 20 minutos, e entrega."), origem), false)
                }
                return (preencher(Textos.t("A caminho da %@"), destino), Textos.t("Um relayer do Across entrega em segundos."), false)
            }
        }
    }

    // MARK: O retrato

    struct Estado: Encodable {
        struct Rede: Encodable { let id: String; let nome: String; let coingecko: String }
        struct Rota: Encodable { let rota: String; let titulo: String }
        struct Moeda: Encodable {
            let moeda: String; let simbolo: String; let coingecko: String?; let motivo: String?; let caminho: String; let saldo: String?
        }
        struct LinhaDaPonte: Encodable {
            let id: String
            let valor: String
            let titulo: String
            let detalhe: String
            let feito: Bool
            let chegou: Bool
            let de: Rede?
            let para: Rede?
            let deposito: String?
            let nomeDoDeposito: String?
            let entrega: String?
            let nomeDaEntrega: String?
        }

        let observa: Bool
        let redesDe: [Rede]
        let redesPara: [Rede]
        let de: Rede
        let para: Rede
        let podeInverter: Bool
        let vende: Troca.Estado.Ativo?
        let chega: Troca.Estado.Ativo?
        let moedas: [Moeda]
        let valor: String
        let versaoDoValor: Int
        let emMoedaQueSai: Double?
        let emMoedaQueChega: Double?
        let chegaTexto: String
        let saldo: String?
        let temSaldo: Bool
        let passou: Bool
        let chave: String
        let podeCotar: Bool
        let cotando: Bool
        let rotas: [Rota]
        let rota: String?
        let detalhes: [String]
        let nota: String?
        let erro: String?
        let botao: String
        let botaoLigado: Bool
        let etapa: Etapa
        let revisao: Troca.Estado.Revisao?
        let falhaDaMontagem: String?
        let valorEmMoeda: Double?
        let detalheIncerto: String?
        let registro: LinhaDaPonte?
        let pontes: [LinhaDaPonte]
        let emCurso: Bool
    }

    private static func rede(_ chain: Chain) -> Estado.Rede { Estado.Rede(id: chain.id, nome: chain.name, coingecko: chain.coingeckoID) }

    func estado() -> Estado {
        let todos = registros()
        return trava.withLock {
            acompanharCarteira()
            return montarEstado(todos)
        }
    }

    /// Chamar com a trava.
    private func montarEstado(_ todos: [BridgeRecord]) -> Estado {
        let (titulo, ligado) = botao
        let opcao = escolhida
        let preco = ativoQueSai.flatMap { Saldos.shared.preco($0) }
        let emMoeda = { (valor: BigUInt?, casas: Int) -> Double? in
            guard let valor, let preco else { return nil }
            return Saldos.decimal(valor, casas: casas) * preco
        }
        // As em curso primeiro; das terminadas, as 5 mais recentes.
        let visiveis = todos.filter { $0.state == .pending } + todos.filter { $0.state != .pending }.prefix(5)
        return Estado(
            observa: carteira?.isWatchOnly == true,
            redesDe: Chain.all.filter { BridgeEngine.chains.contains($0) }.map(Self.rede),
            redesPara: Chain.all.filter { BridgeEngine.destinations.contains($0) }.map(Self.rede),
            de: Self.rede(de), para: Self.rede(para), podeInverter: de != .tron && para != .tron,
            vende: ativoQueSai.map(Troca.dto), chega: ativoQueChega.map(Troca.dto), moedas: moedasDTO(),
            valor: textoDoValor, versaoDoValor: versaoDoValor,
            emMoedaQueSai: emMoeda(quantidade, casasQueSaem), emMoedaQueChega: emMoeda(opcao?.minimumReceived, casasQueChegam),
            chegaTexto: opcao.map { Fmt.decimalSimples($0.minimumReceived, casas: casasQueChegam) } ?? "",
            saldo: ativoQueSai.map { preencher(Textos.t("Saldo %@"), Fmt.cripto(saldo, casas: $0.decimals, simbolo: $0.symbol)) },
            temSaldo: !saldo.isZero, passou: passou, chave: chave,
            podeCotar: carteira?.isWatchOnly == false && !(quantidade ?? BigUInt()).isZero,
            cotando: cotando,
            rotas: moeda == .usdc && opcoes.count > 1
                ? opcoes.map { Estado.Rota(rota: $0.route.rawValue, titulo: $0.route == .cctpFast ? Textos.t("Rápida") : Textos.t("Padrão")) } : [],
            rota: opcao?.route.rawValue, detalhes: opcao.map(detalhes) ?? [],
            nota: opcao == nil && erro == nil ? (de == .bnb || para == .bnb
                ? Textos.t("Leva a moeda para a sua conta em outra rede, pelo Across. Na BNB, o USDC, o USDT e o ETH são os da Binance (Binance-Peg): valem enquanto a Binance mantiver o lastro, e não são os da Circle nem os da Tether. Sem taxa da Escalibur.")
                : Textos.t("Leva a mesma moeda para a sua conta em outra rede. USDC pelo CCTP da própria Circle; ETH e USDT pelo Across; USDT para a Tron pela USDT0 da própria Tether. Sem taxa da Escalibur.")) : nil,
            erro: erro, botao: titulo, botaoLigado: ligado, etapa: etapa, revisao: plano.map(revisaoDTO), falhaDaMontagem: falhaDaMontagem,
            valorEmMoeda: valorEmMoeda, detalheIncerto: detalheIncerto,
            registro: registro.flatMap { id in todos.first { $0.id == id } }.map(linha),
            pontes: visiveis.map(linha), emCurso: todos.contains { $0.state == .pending }
        )
    }

    private func detalhes(_ cotacao: ValidatedBridgeQuote) -> [String] {
        let taxa = Fmt.cripto(cotacao.bridgeFee, casas: casasQueSaem, simbolo: moeda.symbol, cheio: true)
        var linhas: [String] = []
        if cotacao.route == .usdt0 {
            linhas.append(Textos.t("Pela USDT0 da própria Tether: o contrato dela entrega o mesmo valor em USDT na Tron (TRC-20)"))
            linhas.append(preencher(Textos.t("Taxa da Tether: %@"), taxa))
            let entrega = Fmt.cripto(cotacao.messageFee, casas: de.nativeDecimals, simbolo: de.nativeSymbol, cheio: true)
            linhas.append(preencher(Textos.t("Taxa de entrega na Tron: %@, paga aqui. Você não precisa de TRX"), entrega))
        } else {
            linhas.append(cotacao.route.isCCTP ? preencher(Textos.t("Pelo CCTP da Circle: queima aqui e a própria Circle cunha o mesmo USDC na %@"), para.name)
                                               : preencher(Textos.t("Pelo Across: um relayer entrega na %@ em segundos"), para.name))
            linhas.append(cotacao.route.isCCTP ? preencher(Textos.t("Taxa da ponte, no máximo: %@"), taxa) : preencher(Textos.t("Taxa da ponte: %@"), taxa))
        }
        let tempo: String
        switch cotacao.route {
        case .cctpFast: tempo = Textos.t("menos de 1 minuto")
        case .cctpStandard: tempo = Textos.t("uns 20 minutos (sem taxa do protocolo)")
        case .across: tempo = cotacao.estimatedSeconds < 120 ? Textos.t("segundos") : preencher(Textos.t("uns %lld minutos"), "\(cotacao.estimatedSeconds / 60)")
        case .usdt0: tempo = Textos.t("uns minutos")
        }
        linhas.append(preencher(Textos.t("Tempo: %@"), tempo))
        linhas.append(para == .tron ? Textos.t("Vai para a sua própria conta na Tron, desta mesma carteira")
                                    : preencher(Textos.t("Vai para a sua própria conta na %@, o mesmo endereço"), para.name))
        if de == .bnb || para == .bnb {
            linhas.append(preencher(Textos.t("Na BNB, o %@ é o da Binance (Binance-Peg): vale enquanto a Binance mantiver o lastro"), moeda.symbol))
        }
        linhas.append(Textos.t("Sem taxa da Escalibur"))
        return linhas
    }

    /// As moedas da ponte: a que nao faz esta rota aparece com o motivo. Chamar com a trava.
    private func moedasDTO() -> [Estado.Moeda] {
        BridgeAsset.allCases.map { item in
            let listado = deNaPonte.flatMap { item.asset(on: $0) }
            let motivo = motivo(item)
            var saldo: String?
            if motivo == nil, let listado, let carteira,
               let tido = Saldos.shared.saldo(de, carteira: carteira.id)?.holdings.first(where: { $0.asset.id == listado.id }) {
                let livre = Saldos.shared.saldo(de, carteira: carteira.id)?.available(tido) ?? tido.amount
                saldo = Fmt.cripto(livre, casas: tido.asset.decimals, simbolo: item.symbol)
            }
            let cctp = deNaPonte.flatMap { origem in paraNaPonte.map { BridgeAsset.usesCCTP(item, from: origem, to: $0) } } == true
            // O logo da moeda mesmo onde ela nao faz a rota (sem ativo listado na origem).
            let logo: String
            switch item {
            case .usdc: logo = "usd-coin"
            case .usdt: logo = "tether"
            case .eth: logo = "ethereum"
            case .wbtc: logo = "wrapped-bitcoin"
            }
            return Estado.Moeda(moeda: item.rawValue, simbolo: item.symbol, coingecko: listado?.coingeckoID ?? logo, motivo: motivo,
                                caminho: cctp ? Textos.t("Pelo CCTP da Circle") : Textos.t("Pelo Across"), saldo: saldo)
        }
    }

    private func motivo(_ item: BridgeAsset) -> String? {
        guard let origem = deNaPonte, let destino = paraNaPonte else { return Textos.t("Rede fora da ponte.") }
        guard !item.available(from: origem, to: destino) else { return nil }
        let semAcross = origem.across == nil ? origem.chain.name : destino.chain.name
        switch item {
        case .usdc: return Textos.t("Fora da ponte nestas redes.")
        case .eth:
            if origem.across == nil || destino.across == nil { return preencher(Textos.t("O Across não atende %@."), semAcross) }
            return Textos.t("ETH só entre redes em que ele é a moeda nativa, e na BNB, onde é o da Binance.")
        case .usdt:
            if origem.across == nil || destino.across == nil { return preencher(Textos.t("O Across não atende %@."), semAcross) }
            return Textos.t("USDT só onde o Across entrega o USDT da Tether (Ethereum, Arbitrum, Unichain e Plasma) ou o da Binance, na BNB.")
        case .wbtc:
            if origem.across == nil || destino.across == nil { return preencher(Textos.t("O Across não atende %@."), semAcross) }
            return Textos.t("WBTC só entre Ethereum, Arbitrum, Optimism e Polygon.")
        }
    }

    private func revisaoDTO(_ plano: SigningPlan) -> Troca.Estado.Revisao {
        let review = plano.review
        let intencao = pedido?.intencao
        let vende = intencao.flatMap { $0.asset.asset(on: $0.from) }
        let recebe = intencao.flatMap { $0.asset.asset(on: $0.to) }
        let sai = review.outgoing.flatMap { saida in vende.map { Fmt.cripto(saida.amount, casas: $0.decimals, simbolo: $0.symbol) } }
        let entra = review.incomingMinimum.flatMap { entrada in recebe.map { Textos.t("no mínimo ") + Fmt.cripto(entrada.amount, casas: $0.decimals, simbolo: $0.symbol) } }
        return Troca.Estado.Revisao(
            titulo: review.title, sai: sai, entra: entra,
            enderecos: review.lines.filter(\.verbatim).map { Troca.Estado.Linha(rotulo: $0.label, valor: $0.value) },
            linhas: review.lines.filter { !$0.verbatim }.map { Troca.Estado.Linha(rotulo: $0.label, valor: $0.value) }
                + [Troca.Estado.Linha(rotulo: Textos.t("Carteira"), valor: carteira?.name ?? "")],
            avisos: review.warnings.map { Envio.textoDoAviso($0, chain: plano.chain, tipo: .tag) },
            transacoes: review.transactionCount, nota: Textos.t("Não feche o app até terminar."), erro: erroDaRevisao
        )
    }

    /// Chamar com a trava (le `andamentos`).
    private func linha(_ registro: BridgeRecord) -> Estado.LinhaDaPonte {
        let (titulo, detalhe, feito) = texto(registro, andamentos[registro.id])
        let casas = registro.from.map { registro.asset.decimals(on: $0) } ?? 18
        let valor = BigUInt(decimal: registro.amount).map { Fmt.cripto($0, casas: casas, simbolo: registro.asset.symbol) } ?? ""
        let origem = registro.from?.chain
        let destino = registro.to?.chain
        return Estado.LinhaDaPonte(
            id: registro.id.uuidString, valor: valor, titulo: titulo, detalhe: detalhe, feito: feito, chegou: registro.state == .arrived,
            de: origem.map(Self.rede), para: destino.map(Self.rede),
            deposito: origem?.explorerURL(tx: registro.depositTxHash)?.absoluteString, nomeDoDeposito: origem?.explorerName,
            entrega: registro.state == .arrived ? registro.settledTxHash.flatMap { hash in destino?.explorerURL(tx: hash)?.absoluteString } : nil,
            nomeDaEntrega: destino?.explorerName
        )
    }
}

// MARK: A ponte

extension Ponte {
    static func chamar(_ metodo: String, _ pedido: JSONValue) throws -> Data {
        let ponte = Ponte.shared
        switch metodo {
        case "ponte.estado": break
        case "ponte.definir": ponte.definir(pedido)
        case "ponte.cotar": Nucleo.esperarSemErro { await ponte.cotar(pedido["chave"]?.stringValue ?? "") }
        case "ponte.revisar": Nucleo.esperarSemErro { await ponte.revisar() }
        case "ponte.remontar": Nucleo.esperarSemErro { await ponte.remontar() }
        case "ponte.retransmitir": Nucleo.esperarSemErro { await ponte.retransmitir() }
        case "ponte.atualizar": Nucleo.esperarSemErro { await ponte.atualizarPontes() }
        case "ponte.fechar": ponte.fechar()
        default: throw Nucleo.Falha(erro: "metodo desconhecido: \(metodo)")
        }
        return try retrato()
    }

    /// "ponte.assinar": a credencial e, na carteira com passphrase, a passphrase depois dela.
    static func assinar(_ credencial: Credencial, passphrase: SecureBytes?, folga: Int?) throws -> Data {
        let pedido = Embrulho((credencial, passphrase))
        try esperar { try await Ponte.shared.assinar(pedido.valor.0, passphrase: pedido.valor.1, folga: folga) }
        return try retrato()
    }

    private static func retrato() throws -> Data {
        let numero = contagem.withLock { () -> Int in
            ultimoNumero += 1
            return ultimoNumero
        }
        let metadata = Sessao.shared.metadata
        let carteira = metadata.selectedWallet
        return try Nucleo.json(Retrato(numero: numero, ponte: Ponte.shared.estado(), moeda: metadata.settings.currency,
                                       pedePassphrase: PortaDaPassphrase.precisa(carteira), nomeDaCarteira: carteira?.name ?? ""))
    }

    private static let contagem = NSLock()
    nonisolated(unsafe) private static var ultimoNumero = 0

    func avisar() {
        guard let json = try? Self.retrato() else { return }
        Eventos.emitir("ponte", json)
    }

    struct Retrato: Encodable {
        let numero: Int
        let ponte: Estado
        let moeda: String
        let pedePassphrase: Bool
        let nomeDaCarteira: String
    }
}
