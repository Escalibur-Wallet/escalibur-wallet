import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import EscaliburNetwork
import Foundation

// Os avisos sem servidor do Android: os alertas de preco, o aviso de recebimento e os da ordem
// limite (o PriceAlertCenter, o ReceiptWatchCenter e o LimitOrderWatch do iOS). O proprio celular
// confere de tempos em tempos, quando o Android deixa, e o app publica notificacoes locais.
// Nenhuma notificacao remota, nenhum token de push, nenhum servidor da Escalibur.
//
// Os arquivos ficam numa pasta propria, na pasta sem backup do app, fora dos metadados cifrados:
// a checagem do segundo plano roda com o app travado, quando o cofre nao abre. No Android essa
// pasta so abre depois do primeiro desbloqueio do aparelho (a classe C do iOS). Nada de chave,
// frase, saldo ou nome de carteira: as moedas escolhidas, os enderecos publicos e o ultimo saldo
// visto, e os UIDs das ordens abertas.
//
// O nucleo so diz o que aconteceu; o texto da notificacao e montado no app, com os formatos da
// regiao.

/// O que um aviso diz. `id` e a etiqueta da notificacao: um aviso novo com o mesmo id substitui o
/// anterior.
struct Aviso: Encodable {
    let id: String
    /// "precos", "recebimentos", "ordens" ou "pontes": o canal de notificacao do Android.
    let canal: String
    /// precos: passou, caiu, subiu, desceu, discreto, mais. recebimentos: recebeu, discreto,
    /// mais. ordens: executada, vence24h, prazo. pontes: chegou.
    let tipo: String
    var moeda: String? = nil
    var nome: String? = nil
    var nivel: Double? = nil
    var preco: Double? = nil
    var variacao: Double? = nil
    var unidade: String? = nil
    var quantia: String? = nil
    var rede: String? = nil
    var quantos: Int? = nil
    var ordem: String? = nil
}

enum Vigias {
    /// A pasta dos arquivos, ao lado da carteira na pasta sem backup do app.
    nonisolated(unsafe) static var pasta: URL?
    static let trava = NSLock()
    /// Avisos que sairam com o app aberto (ordem executada vista na lista, ponte que chegou),
    /// esperando a proxima conferencia para virar notificacao.
    nonisolated(unsafe) private static var fila: [Aviso] = []

    static func arquivo(_ nome: String) -> URL? { pasta?.appendingPathComponent(nome) }

    static func ler<T: Decodable>(_ tipo: T.Type, _ nome: String) -> T? {
        guard let url = arquivo(nome), let dados = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(tipo, from: dados)
    }

    static func gravar<T: Encodable>(_ valor: T, _ nome: String) {
        guard let pasta, let url = arquivo(nome), let dados = try? JSONEncoder().encode(valor) else { return }
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        try? dados.write(to: url, options: .atomic)
    }

    static func apagar(_ nome: String) {
        guard let url = arquivo(nome) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func enfileirar(_ aviso: Aviso) {
        trava.withLock { fila.append(aviso) }
    }

    /// A conferencia: os tres vigias e o que ficou na fila. `forcar` ignora o intervalo minimo
    /// (a checagem do segundo plano e a moeda nova na lista).
    static func conferir(forcar: Bool) async -> [Aviso] {
        async let precos = AlertasDePreco.conferir(forcar: forcar)
        async let recebidos = AvisoDeRecebimento.conferir(forcar: forcar)
        async let ordens = VigiaDeOrdens.conferir()
        let novos = await precos + recebidos + ordens
        let pendentes = trava.withLock { () -> [Aviso] in
            let saida = fila
            fila = []
            return saida
        }
        return pendentes + novos
    }

    /// Se a checagem do segundo plano precisa ficar na agenda.
    static var precisaDeAgenda: Bool {
        let precos = AlertasDePreco.arquivo()
        let ordens = VigiaDeOrdens.arquivo()
        return (precos.enabled && !precos.coins.isEmpty) || AvisoDeRecebimento.arquivo().enabled || !ordens.orders.isEmpty || !(ordens.notices?.isEmpty ?? true)
    }

    /// Apagar tudo (as carteiras sairam do aparelho): nenhum arquivo fica.
    static func apagarTudo() {
        trava.withLock { fila = [] }
        AlertasDePreco.apagar()
        AvisoDeRecebimento.desligar()
        VigiaDeOrdens.apagar()
    }

    struct Estado: Encodable {
        let agendar: Bool
        let avisos: [Aviso]
    }

    /// O simbolo como aparece num aviso: so letras e algarismos, no maximo 10.
    static func simboloSeguro(_ simbolo: String) -> String {
        let limpo = simbolo.uppercased().unicodeScalars.filter { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
        let texto = String(String.UnicodeScalarView(limpo).prefix(10))
        return texto.isEmpty ? Textos.t("Moeda") : texto
    }
}

// MARK: Alertas de preco

/// O que os alertas guardam: as moedas escolhidas uma a uma, as regras e o ultimo preco visto.
struct PriceAlertFile: Codable, Equatable {
    var enabled = false
    var roundNumbers = true
    /// Variacao em 24 h que avisa, em %; nil desliga.
    var moveThreshold: Double? = 10
    var currency = "brl"
    /// Moeda e preco na notificacao. Desligado, a tela bloqueada so diz "Alerta de preço".
    var showDetails = true
    var coins: [WatchedCoin] = []
    var memory: [String: PriceAlertMemory] = [:]
    var lastCheck: Date?
    /// O dono ja escolheu (ou o app ja ligou de fabrica): o padrao nao volta a ligar.
    var chosen: Bool?

    /// No maximo 7 moedas, como no iOS.
    static let maxCoins = 7
    static let thresholds: [Double] = [5, 10, 15, 20]

    func watches(_ id: String) -> Bool { coins.contains { $0.id == id } }
}

enum AlertasDePreco {
    static let nome = "alertas.json"
    /// Com o app aberto, uma checagem a cada 10 minutos no maximo.
    static let intervaloAberto: TimeInterval = 10 * 60
    static let maximoPorVez = 4
    nonisolated(unsafe) private static var conferindo = false

    /// Ligar sem moeda nenhuma ja vem com Bitcoin, Ethereum, XRP e Solana: fixas, nao saem do saldo.
    static let padrao = [
        WatchedCoin(id: "bitcoin", symbol: "BTC", name: "Bitcoin"),
        WatchedCoin(id: "ethereum", symbol: "ETH", name: "Ethereum"),
        WatchedCoin(id: "ripple", symbol: "XRP", name: "XRP"),
        WatchedCoin(id: "solana", symbol: "SOL", name: "Solana"),
    ]

    static func arquivo() -> PriceAlertFile {
        Vigias.trava.withLock { Vigias.ler(PriceAlertFile.self, nome) ?? PriceAlertFile() }
    }

    /// Muda e grava. A memoria de moeda que saiu da lista sai junto.
    @discardableResult
    static func mudar(_ mudanca: (inout PriceAlertFile) -> Void) -> PriceAlertFile {
        Vigias.trava.withLock {
            var valor = Vigias.ler(PriceAlertFile.self, nome) ?? PriceAlertFile()
            mudanca(&valor)
            valor.memory = valor.memory.filter { id, _ in valor.watches(id) }
            Vigias.gravar(valor, nome)
            return valor
        }
    }

    static func apagar() {
        Vigias.trava.withLock { Vigias.apagar(nome) }
    }

    /// A moeda dos alertas: a escolhida em Ativos; com bitcoin, dolar.
    static func moedaDoApp(_ settings: Settings) -> String {
        switch settings.totalUnit {
        case "brl": return "brl"
        case "usd", "btc": return "usd"
        case "eur": return "eur"
        default: return ["brl", "usd", "eur"].contains(settings.currency) ? settings.currency : "usd"
        }
    }

    /// A moeda do app mudou: os precos guardados eram de outra moeda e viram base nova.
    static func acompanharMoeda(_ moeda: String) {
        guard arquivo().currency != moeda else { return }
        mudar { arquivo in
            arquivo.currency = moeda
            arquivo.memory = [:]
        }
    }

    /// Le os precos confirmados por duas fontes, aplica as regras e diz o que avisar.
    static func conferir(forcar: Bool, agora: Date = .now) async -> [Aviso] {
        let antes = arquivo()
        guard antes.enabled, !antes.coins.isEmpty else { return [] }
        if !forcar, let ultima = antes.lastCheck, agora.timeIntervalSince(ultima) < intervaloAberto { return [] }
        guard Vigias.trava.withLock({ () -> Bool in
            guard !conferindo else { return false }
            conferindo = true
            return true
        }) else { return [] }
        defer { Vigias.trava.withLock { conferindo = false } }
        let cotacoes = await MarketService.shared.alertQuotes(ids: antes.coins.map(\.id), currency: antes.currency)

        // A tela de ajustes pode ter mudado o arquivo durante a leitura: vale o de agora.
        var eventos: [(WatchedCoin, PriceAlertEvent, Quote)] = []
        let depois = mudar { valor in
            guard valor.enabled, valor.currency == antes.currency else { return }
            for moeda in valor.coins {
                guard let cotacao = cotacoes[moeda.id] else { continue }
                var memoria = valor.memory[moeda.id] ?? PriceAlertMemory()
                let novos = PriceAlertRules.evaluate(
                    price: cotacao.price, change24h: cotacao.change24h, memory: &memoria,
                    roundNumbers: valor.roundNumbers, moveThreshold: valor.moveThreshold, now: agora
                )
                valor.memory[moeda.id] = memoria
                eventos += novos.map { (moeda, $0, cotacao) }
            }
            valor.lastCheck = agora
        }
        guard !eventos.isEmpty, depois.enabled else { return [] }
        guard depois.showDetails else {
            // Discreto: um aviso so, sem moeda e sem valor.
            return [Aviso(id: "precos.discreto", canal: "precos", tipo: "discreto")]
        }
        let mostrados = eventos.count > maximoPorVez ? Array(eventos.prefix(maximoPorVez - 1)) : eventos
        var saida = mostrados.map { moeda, evento, cotacao -> Aviso in
            let (tipo, nivel, variacao): (String, Double?, Double?) = switch evento {
            case .crossedUp(let nivel): ("passou", nivel, cotacao.change24h)
            case .crossedDown(let nivel): ("caiu", nivel, cotacao.change24h)
            case .moved(let variacao): (variacao >= 0 ? "subiu" : "desceu", nil, variacao)
            }
            return Aviso(id: "preco.\(moeda.id)", canal: "precos", tipo: tipo, moeda: moeda.id, nome: nomeDa(moeda), nivel: nivel,
                         preco: cotacao.price, variacao: variacao, unidade: depois.currency)
        }
        if eventos.count > mostrados.count {
            saida.append(Aviso(id: "precos.mais", canal: "precos", tipo: "mais", quantos: eventos.count - mostrados.count))
        }
        return saida
    }

    /// O nome vem da lista compilada do app, nunca do provedor: o texto do provedor seria texto de
    /// quem quiser na tela bloqueada. Fora da lista, so o simbolo, filtrado.
    static func nomeDa(_ moeda: WatchedCoin) -> String {
        if let rede = Chain.all.first(where: { $0.coingeckoID == moeda.id }) { return Asset.native(rede).name }
        if let token = TokenRegistry.tokens.first(where: { $0.coingeckoID == moeda.id }) { return token.name }
        return Vigias.simboloSeguro(moeda.symbol)
    }
}

// MARK: Aviso de recebimento

/// O que o aviso guarda: as contas a conferir e o ultimo saldo visto de cada ativo.
struct ReceiptWatchFile: Codable, Equatable {
    struct Account: Codable, Equatable, Hashable {
        let chainID: String
        /// Um endereco; nas redes UTXO, os dois ultimos de recebimento usados e o proximo
        /// (`UTXOUsage.receiptIndices`).
        let addresses: [String]
        /// A conta, sem endereco: um resumo da rede e do primeiro endereco dela. E a chave do saldo
        /// visto, que nao muda quando o endereco UTXO de recebimento anda.
        var owner: String? = nil
        /// De uma carteira de so observar: so entra com `includeWatchOnly`.
        var watchOnly: Bool? = nil

        var key: String { owner ?? addresses.first ?? "" }
    }

    struct Seen: Codable, Equatable {
        var amount: BigUInt
        let symbol: String
        let decimals: Int
    }

    var enabled = false
    /// Valor e moeda na notificacao. Desligado, a tela bloqueada so diz que entrou moeda.
    var showDetails = false
    var accounts: [Account] = []
    /// "rede|conta|ativo" -> o ultimo saldo visto.
    var seen: [String: Seen] = [:]
    var lastCheck: Date?
    var chosen: Bool?
    /// Sorteado ao ligar: fixa o provedor de cada endereco UTXO nesta instalacao.
    var salt: UInt64?
    /// Nas redes UTXO, o ultimo valor confirmado de cada endereco ("rede|endereco"): a conferencia e
    /// endereco por endereco (`BalanceService.receiptBalance`).
    var addressSeen: [String: UInt64]?
    /// As carteiras de so observar tambem entram. Comeca desligado: em geral e a carteira fria, e
    /// conferi-la junto com as outras liga as duas no provedor.
    var includeWatchOnly: Bool?

    /// As contas que entram, pela escolha de so observar.
    func admitted(_ all: [Account]) -> [Account] {
        includeWatchOnly == true ? all : all.filter { $0.watchOnly != true }
    }
}

enum AvisoDeRecebimento {
    static let nome = "recebimentos.json"
    /// O atraso maximo de cada rede numa rodada: as consultas de todas as redes nao saem juntas.
    static let atrasoMaximo = 2_500
    /// Com o app aberto, uma checagem a cada 2 minutos no maximo.
    static let intervaloAberto: TimeInterval = 2 * 60
    static let maximoPorVez = 4
    nonisolated(unsafe) private static var conferindo = false

    static func arquivo() -> ReceiptWatchFile {
        Vigias.trava.withLock { Vigias.ler(ReceiptWatchFile.self, nome) ?? ReceiptWatchFile() }
    }

    @discardableResult
    static func mudar(_ mudanca: (inout ReceiptWatchFile) -> Void) -> ReceiptWatchFile {
        Vigias.trava.withLock {
            var valor = Vigias.ler(ReceiptWatchFile.self, nome) ?? ReceiptWatchFile()
            mudanca(&valor)
            Vigias.gravar(valor, nome)
            return valor
        }
    }

    /// As contas que o aviso confere: as das carteiras que podem receber, nas redes ligadas, so os
    /// enderecos publicos. As de so observar vem marcadas, e so entram se o dono quiser
    /// (`ReceiptWatchFile.includeWatchOnly`). A carteira com passphrase fica de fora: o arquivo abre com o app travado,
    /// e com ela nele quem extrai os dados do aparelho acha a carteira que o dono quis esconder. A
    /// que ainda nao tem copia conferida tambem: ela nao recebe.
    static func contas(_ metadata: Metadata) -> [ReceiptWatchFile.Account] {
        let desligadas = metadata.settings.disabledChainIDs
        var saida: [ReceiptWatchFile.Account] = []
        var vistas = Set<String>()
        // As de so observar por ultimo: com o mesmo endereco numa carteira normal, vale a normal.
        let carteiras = metadata.wallets.filter { !$0.isWatchOnly } + metadata.wallets.filter(\.isWatchOnly)
        for carteira in carteiras where !carteira.hasPassphrase && (carteira.hasBackup || carteira.isWatchOnly) {
            for conta in carteira.accounts {
                guard let rede = Chain.all.first(where: { $0.id == conta.chainID }), !desligadas.contains(rede.id) else { continue }
                // A conta da Tron com outra chave no controle nao recebe por caminho nenhum.
                if rede.family == .tron, carteira.tronForeignControl == true { continue }
                let enderecos = enderecosDoAviso(conta, rede: rede, uso: carteira.utxoUsage[rede.id])
                guard vistas.insert("\(rede.id)|\(conta.address)").inserted else { continue }
                saida.append(.init(chainID: rede.id, addresses: enderecos, owner: dono(rede, conta.address), watchOnly: carteira.isWatchOnly))
            }
        }
        return saida
    }

    /// Nas redes UTXO, so o recebimento: os dois ultimos enderecos usados e o proximo.
    static func enderecosDoAviso(_ conta: DerivedAccount, rede: Chain, uso: UTXOUsage?) -> [String] {
        guard rede.family == .utxo, let xpub = conta.accountXPub else { return [conta.address] }
        let saida = (uso ?? UTXOUsage()).receiptIndices.compactMap { indice -> String? in
            guard let chave = try? xpub.derive([0, UInt32(indice)]) else { return nil }
            return try? Address.from(publicKey: chave.publicKey, chain: rede)
        }
        return saida.isEmpty ? [conta.address] : saida
    }

    /// A conta no arquivo sem o endereco: 8 bytes do SHA-256 da rede e do primeiro endereco.
    static func dono(_ rede: Chain, _ endereco: String) -> String {
        Hex.encode(Array(Hash.sha256(Array("\(rede.id)|\(endereco)".utf8)).prefix(8)))
    }

    /// Liga com as contas de agora. A primeira leitura so marca o saldo de partida: ligar nao
    /// avisa do que ja estava na carteira. Ligado pelo dono em Ajustes, vem junto o valor e a moeda;
    /// ligado de fabrica, a tela bloqueada so diz que entrou moeda.
    static func ligar(contas: [ReceiptWatchFile.Account], detalhes: Bool) {
        mudar { arquivo in
            arquivo.enabled = true
            arquivo.chosen = true
            arquivo.showDetails = detalhes
            arquivo.salt = arquivo.salt ?? (try? SecureRandom.uint64())
            arquivo.accounts = arquivo.admitted(contas)
            arquivo.seen = [:]
            arquivo.addressSeen = [:]
        }
    }

    /// Desliga e apaga: os enderecos nao ficam no aparelho sem uso. Fica so a escolha.
    static func desligar(escolhido: Bool = false) {
        Vigias.trava.withLock {
            Vigias.apagar(nome)
            if escolhido { Vigias.gravar(ReceiptWatchFile(chosen: true), nome) }
        }
    }

    /// As contas de agora, do app destravado. Conta que saiu leva junto o saldo visto.
    static func acompanhar(contas todas: [ReceiptWatchFile.Account]) {
        var atual = arquivo()
        // Sal que nao saiu (sorteio falhou ao ligar): sorteia de novo agora.
        if atual.enabled, atual.salt == nil, let sal = try? SecureRandom.uint64() { atual = mudar { $0.salt = sal } }
        let contas = atual.admitted(todas)
        guard atual.enabled, atual.accounts != contas else { return }
        let manter = Set(contas.map { "\($0.chainID)|\($0.key)" })
        let enderecos = Set(contas.flatMap { conta in conta.addresses.map { "\(conta.chainID)|\($0)" } })
        mudar { arquivo in
            arquivo.accounts = contas
            arquivo.seen = arquivo.seen.filter { chave, _ in manter.contains(chave.split(separator: "|").prefix(2).joined(separator: "|")) }
            arquivo.addressSeen = arquivo.addressSeen?.filter { enderecos.contains($0.key) }
        }
    }

    /// Le o saldo de cada conta, compara com o ultimo visto e diz o que subiu. Token fora da lista
    /// nao conta: e por onde chega o spam.
    static func conferir(forcar: Bool, agora: Date = .now) async -> [Aviso] {
        let antes = arquivo()
        guard antes.enabled, !antes.accounts.isEmpty else { return [] }
        if !forcar, let ultima = antes.lastCheck, agora.timeIntervalSince(ultima) < intervaloAberto { return [] }
        guard Vigias.trava.withLock({ () -> Bool in
            guard !conferindo else { return false }
            conferindo = true
            return true
        }) else { return [] }
        defer { Vigias.trava.withLock { conferindo = false } }

        let sal = antes.salt ?? 0
        let saldos = await withTaskGroup(of: (ReceiptWatchFile.Account, ChainBalance?).self) { grupo in
            // Em ordem sorteada e cada rede com um atraso proprio: as consultas de todas as redes
            // nao saem juntas, no mesmo segundo, a cada rodada.
            for conta in (try? SecureRandom.mixed(antes.accounts)) ?? antes.accounts {
                guard let rede = Chain.all.first(where: { $0.id == conta.chainID }), !conta.addresses.isEmpty else { continue }
                let (visto, vistoPorEndereco) = vistos(de: conta, em: antes)
                // So o que ja entrou num bloco, e toda mudanca conferida por outro dono: o aviso diz que
                // o saldo ja esta na carteira.
                grupo.addTask {
                    try? await Task.sleep(nanoseconds: UInt64((try? SecureRandom.index(below: atrasoMaximo + 1)) ?? 0) * 1_000_000)
                    return (conta, try? await BalanceService.shared.receiptBalance(
                        chain: rede, addresses: conta.addresses, salt: sal, seen: visto, seenAddresses: vistoPorEndereco
                    ))
                }
            }
            var saida: [(ReceiptWatchFile.Account, ChainBalance)] = []
            for await (conta, saldo) in grupo { if let saldo { saida.append((conta, saldo)) } }
            return saida
        }

        var eventos: [ReceiptEvent] = []
        let depois = mudar { valor in
            guard valor.enabled else { return }
            eventos = comparar(saldos, visto: &valor.seen)
            for (conta, saldo) in saldos {
                for (endereco, quantia) in saldo.perAddress ?? [:] { valor.addressSeen = (valor.addressSeen ?? [:]).merging(["\(conta.chainID)|\(endereco)": quantia]) { $1 } }
            }
            valor.lastCheck = agora
        }
        guard !eventos.isEmpty, depois.enabled else { return [] }
        guard depois.showDetails else {
            return [Aviso(id: "recebimento.discreto", canal: "recebimentos", tipo: "discreto")]
        }
        let marca = Int(agora.timeIntervalSince1970)
        var saida = eventos.prefix(maximoPorVez).map { evento -> Aviso in
            let rede = Chain.all.first { $0.id == evento.chainID }?.name ?? evento.chainID
            let simbolo = Vigias.simboloSeguro(evento.symbol)
            return Aviso(id: "recebimento.\(evento.chainID).\(simbolo).\(marca)", canal: "recebimentos", tipo: "recebeu",
                         quantia: Fmt.cripto(evento.amount, casas: evento.decimals, simbolo: simbolo), rede: rede)
        }
        if eventos.count > maximoPorVez {
            saida.append(Aviso(id: "recebimento.mais", canal: "recebimentos", tipo: "mais", quantos: eventos.count - maximoPorVez))
        }
        return saida
    }

    struct ReceiptEvent: Equatable {
        let chainID: String
        let symbol: String
        let decimals: Int
        let amount: BigUInt
    }

    /// O saldo visto da conta, por ativo, e o de cada endereco dela.
    static func vistos(de conta: ReceiptWatchFile.Account, em arquivo: ReceiptWatchFile) -> ([String: BigUInt], [String: UInt64]) {
        let prefixo = "\(conta.chainID)|\(conta.key)|"
        var ativos: [String: BigUInt] = [:]
        for (chave, visto) in arquivo.seen where chave.hasPrefix(prefixo) { ativos[String(chave.dropFirst(prefixo.count))] = visto.amount }
        var enderecos: [String: UInt64] = [:]
        for endereco in conta.addresses { if let valor = arquivo.addressSeen?["\(conta.chainID)|\(endereco)"] { enderecos[endereco] = valor } }
        return (ativos, enderecos)
    }

    /// O que subiu desde o ultimo saldo visto, atualizando o visto. Ativo visto pela primeira vez so
    /// marca a base; ativo que saiu do saldo (enviado inteiro) volta a zero, e o proximo que chegar
    /// avisa, mesmo menor que o saldo antigo.
    static func comparar(_ saldos: [(ReceiptWatchFile.Account, ChainBalance)], visto: inout [String: ReceiptWatchFile.Seen]) -> [ReceiptEvent] {
        var eventos: [ReceiptEvent] = []
        for (conta, saldo) in saldos {
            let prefixo = "\(conta.chainID)|\(conta.key)|"
            // Ativo que nao foi lido nesta rodada nao conta como enviado: zerado aqui, a volta dele
            // avisava o saldo inteiro como recebido.
            let presentes = Set(saldo.holdings.map { "\(prefixo)\($0.asset.id)" } + (saldo.unread ?? []).map { "\(prefixo)\($0)" })
            for chave in visto.keys where chave.hasPrefix(prefixo) && !presentes.contains(chave) { visto[chave]?.amount = 0 }
            for posicao in saldo.holdings {
                let chave = "\(prefixo)\(posicao.asset.id)"
                if let anterior = visto[chave], posicao.amount > anterior.amount {
                    eventos.append(ReceiptEvent(chainID: conta.chainID, symbol: posicao.asset.symbol, decimals: posicao.asset.decimals,
                                                amount: posicao.amount - anterior.amount))
                }
                visto[chave] = .init(amount: posicao.amount, symbol: posicao.asset.symbol, decimals: posicao.asset.decimals)
            }
        }
        return eventos
    }
}

// MARK: Ordens limite

/// As ordens abertas da CoW acompanhadas: o UID (que traz o endereco do dono e o prazo, os mesmos
/// dados que a CoW publica), a rede e quando vence.
struct LimitOrderWatchFile: Codable, Equatable {
    struct Order: Codable, Equatable {
        let id: String
        let chainID: String
        let expiresAt: Date
        /// O aviso de 24 horas ja saiu (ou a ordem nasceu perto demais do fim para ele).
        var warned: Bool
    }

    /// O aviso do fim do prazo das ordens que o dono pediu para refazer. So um resumo do UID e a
    /// hora: a carteira com passphrase tambem ganha o aviso, e o arquivo nao diz de quem e a ordem.
    struct Notice: Codable, Equatable {
        let key: String
        let at: Date
    }

    var orders: [Order] = []
    var notices: [Notice]?
}

enum VigiaDeOrdens {
    static let nome = "ordens.json"
    /// Quanto antes do fim do prazo sai o aviso.
    static let antecedencia: TimeInterval = 24 * 60 * 60
    /// Ordem que vence em menos que isto alem das 24 horas nao ganha o aviso: ele chegaria junto
    /// com a propria ordem.
    static let folga: TimeInterval = 60 * 60
    nonisolated(unsafe) private static var conferindo = false

    static func arquivo() -> LimitOrderWatchFile {
        Vigias.trava.withLock { Vigias.ler(LimitOrderWatchFile.self, nome) ?? LimitOrderWatchFile() }
    }

    private static func mudar(_ mudanca: (inout LimitOrderWatchFile) -> Void) {
        Vigias.trava.withLock {
            var valor = Vigias.ler(LimitOrderWatchFile.self, nome) ?? LimitOrderWatchFile()
            mudanca(&valor)
            if valor.orders.isEmpty, valor.notices?.isEmpty ?? true { Vigias.apagar(nome) } else { Vigias.gravar(valor, nome) }
        }
    }

    static func apagar() {
        Vigias.trava.withLock { Vigias.apagar(nome) }
    }

    /// Uma ordem da CoW, nova ou vista na lista de abertas: passa a ser acompanhada. Ja
    /// acompanhada, nada muda.
    static func acompanhar(id: String, rede: Chain, venceEm: Date, agora: Date = .now) {
        guard venceEm > agora, CoWProtocol.supports(rede), id.hasPrefix("0x"), Hex.decode(id)?.count == CoWProtocol.uidLength else { return }
        mudar { arquivo in
            guard !arquivo.orders.contains(where: { $0.id == id }) else { return }
            let semAviso = venceEm.timeIntervalSince(agora) - antecedencia < folga
            arquivo.orders.append(.init(id: id, chainID: rede.id, expiresAt: venceEm, warned: semAviso))
        }
    }

    /// O resumo do UID que o aviso do fim do prazo guarda: nao volta ao UID nem ao endereco.
    private static func resumo(_ id: String) -> String {
        Hex.encode(Array(Hash.sha256(Array(id.utf8)).prefix(12)))
    }

    static func marcarFimDoPrazo(_ id: String, em: Date) {
        let chave = resumo(id)
        mudar { arquivo in
            var lista = arquivo.notices ?? []
            lista.removeAll { $0.key == chave }
            lista.append(.init(key: chave, at: em))
            arquivo.notices = lista
        }
    }

    static func desmarcarFimDoPrazo(_ id: String) {
        let chave = resumo(id)
        mudar { $0.notices?.removeAll { $0.key == chave } }
    }

    /// A ordem terminou (ou o dono cancelou): sai do arquivo.
    static func esquecer(_ id: String) {
        mudar { $0.orders.removeAll { $0.id == id } }
    }

    /// A lista de ordens abertas viu a ordem sair com o andamento final. Executada avisa (se ainda
    /// estava acompanhada: o aviso sai uma vez so); o resto so sai do arquivo.
    static func assentar(_ id: String, executada: Bool) {
        let acompanhada = arquivo().orders.contains { $0.id == id }
        esquecer(id)
        if executada, acompanhada { Vigias.enfileirar(Aviso(id: "ordem-limite.executada.\(id)", canal: "ordens", tipo: "executada", ordem: id)) }
    }

    /// O aviso de 24 horas das que estao perto do fim, e a pergunta a CoW pelo andamento de cada
    /// uma. Sem resposta, fica para a proxima vez. Os avisos nao dizem ativo nem valor.
    static func conferir(agora: Date = .now) async -> [Aviso] {
        let lido = arquivo()
        let ordens = lido.orders
        guard !ordens.isEmpty || !(lido.notices?.isEmpty ?? true), Vigias.trava.withLock({ () -> Bool in
            guard !conferindo else { return false }
            conferindo = true
            return true
        }) else { return [] }
        defer { Vigias.trava.withLock { conferindo = false } }
        var saida: [Aviso] = []
        // O fim do prazo das que o dono pediu para refazer: nao precisa de rede.
        let venceram = (lido.notices ?? []).filter { $0.at <= agora }
        if !venceram.isEmpty {
            let chaves = Set(venceram.map(\.key))
            mudar { $0.notices?.removeAll { chaves.contains($0.key) } }
            saida += venceram.map { Aviso(id: "ordem-limite.prazo.\($0.key)", canal: "ordens", tipo: "prazo", ordem: "") }
        }
        let perto = ordens.filter { !$0.warned && $0.expiresAt > agora && $0.expiresAt.timeIntervalSince(agora) <= antecedencia }
        if !perto.isEmpty {
            let ids = Set(perto.map(\.id))
            mudar { arquivo in
                for indice in arquivo.orders.indices where ids.contains(arquivo.orders[indice].id) { arquivo.orders[indice].warned = true }
            }
            saida += perto.map { Aviso(id: "ordem-limite.24h.\($0.id)", canal: "ordens", tipo: "vence24h", ordem: $0.id) }
        }
        let cliente = CoWClient()
        for ordem in ordens {
            guard let rede = Chain.all.first(where: { $0.id == ordem.chainID }), let uid = Hex.decode(ordem.id) else {
                esquecer(ordem.id)
                continue
            }
            guard let andamento = try? await cliente.order(uid: uid, chain: rede) else { continue }
            switch andamento.status {
            case .fulfilled:
                esquecer(ordem.id)
                saida.append(Aviso(id: "ordem-limite.executada.\(ordem.id)", canal: "ordens", tipo: "executada", ordem: ordem.id))
            case .cancelled, .expired:
                esquecer(ordem.id)
            case .open, .presignaturePending, .unknown:
                if andamento.invalidated || TimeInterval(andamento.validTo) <= agora.timeIntervalSince1970 { esquecer(ordem.id) }
            }
        }
        return saida
    }
}

// MARK: Pedidos do app

extension Vigias {
    struct EstadoDosAlertas: Encodable {
        let ligado: Bool
        let redondos: Bool
        let variacao: Double?
        let detalhes: Bool
        let moedas: [WatchedCoin]
        let maximo: Int
        let limites: [Double]
        let unidade: String
    }

    struct EstadoDoRecebimento: Encodable {
        let ligado: Bool
        let detalhes: Bool
        let soObservar: Bool
    }

    static func estadoDosAlertas() -> EstadoDosAlertas {
        let arquivo = AlertasDePreco.arquivo()
        return EstadoDosAlertas(ligado: arquivo.enabled, redondos: arquivo.roundNumbers, variacao: arquivo.moveThreshold, detalhes: arquivo.showDetails,
                                moedas: arquivo.coins, maximo: PriceAlertFile.maxCoins, limites: PriceAlertFile.thresholds, unidade: arquivo.currency)
    }

    static func estadoDoRecebimento() -> EstadoDoRecebimento {
        let arquivo = AvisoDeRecebimento.arquivo()
        return EstadoDoRecebimento(ligado: arquivo.enabled, detalhes: arquivo.showDetails, soObservar: arquivo.includeWatchOnly == true)
    }

    static func chamar(_ metodo: String, _ pedido: JSONValue) throws -> Data {
        switch metodo {
        case "vigias.preparar":
            // A checagem do segundo plano, com o app fechado: so a pasta, sem abrir a sessao.
            if pasta == nil, let caminho = pedido["pasta"]?.stringValue { pasta = URL(fileURLWithPath: caminho) }
            return try Nucleo.json(["agendar": precisaDeAgenda])
        case "vigias.conferir":
            let forcar = pedido["forcar"]?.boolValue ?? false
            let avisos = try esperar { await conferir(forcar: forcar) }
            return try Nucleo.json(Estado(agendar: precisaDeAgenda, avisos: avisos))
        case "vigias.agenda":
            return try Nucleo.json(["agendar": precisaDeAgenda])

        case "alertas.estado":
            return try Nucleo.json(estadoDosAlertas())
        case "alertas.mudar":
            let moedaDoApp = Sessao.shared.fase == .unlocked ? AlertasDePreco.moedaDoApp(Sessao.shared.metadata.settings) : nil
            AlertasDePreco.mudar { arquivo in
                arquivo.chosen = true
                if let ligado = pedido["ligado"]?.boolValue {
                    arquivo.enabled = ligado
                    if ligado {
                        if arquivo.coins.isEmpty { arquivo.coins = AlertasDePreco.padrao }
                        if let moedaDoApp, arquivo.currency != moedaDoApp {
                            arquivo.currency = moedaDoApp
                            arquivo.memory = [:]
                        }
                    }
                }
                if let redondos = pedido["redondos"]?.boolValue { arquivo.roundNumbers = redondos }
                if pedido["semVariacao"]?.boolValue == true { arquivo.moveThreshold = nil }
                if let variacao = pedido["variacao"]?.doubleValue, PriceAlertFile.thresholds.contains(variacao) { arquivo.moveThreshold = variacao }
                if let detalhes = pedido["detalhes"]?.boolValue { arquivo.showDetails = detalhes }
                if let tirar = pedido["tirar"]?.stringValue { arquivo.coins.removeAll { $0.id == tirar } }
                if let novo = pedido["por"], let id = novo["id"]?.stringValue, !arquivo.watches(id), arquivo.coins.count < PriceAlertFile.maxCoins {
                    let imagem = novo["imagem"]?.stringValue.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
                    arquivo.coins.append(WatchedCoin(id: id, symbol: novo["simbolo"]?.stringValue ?? "", name: novo["nome"]?.stringValue ?? "", image: imagem))
                }
            }
            return try Nucleo.json(estadoDosAlertas())
        case "recebimentos.estado":
            return try Nucleo.json(estadoDoRecebimento())
        case "recebimentos.ligar":
            guard Sessao.shared.fase == .unlocked else { throw Nucleo.Falha(erro: "sessao.travada") }
            AvisoDeRecebimento.ligar(contas: AvisoDeRecebimento.contas(Sessao.shared.metadata), detalhes: true)
            return try Nucleo.json(estadoDoRecebimento())
        case "recebimentos.desligar":
            AvisoDeRecebimento.desligar(escolhido: true)
            return try Nucleo.json(estadoDoRecebimento())
        case "recebimentos.soObservar":
            // Carteiras de so observar no aviso, ou fora dele.
            let ligado = pedido["ligado"]?.boolValue ?? false
            AvisoDeRecebimento.mudar { $0.includeWatchOnly = ligado }
            if Sessao.shared.fase == .unlocked { AvisoDeRecebimento.acompanhar(contas: AvisoDeRecebimento.contas(Sessao.shared.metadata)) }
            return try Nucleo.json(estadoDoRecebimento())
        case "recebimentos.detalhes":
            let ligado = pedido["ligado"]?.boolValue ?? false
            AvisoDeRecebimento.mudar { $0.showDetails = ligado }
            return try Nucleo.json(estadoDoRecebimento())
        case "vigias.padrao":
            // Os alertas de preco vem ligados de fabrica: na primeira vez que a carteira abre sem o dono
            // ter escolhido, o app pede a permissao e liga. O aviso de recebimento nao: ele so liga em
            // Ajustes, onde o preco dele esta dito (auditoria de privacidade, 22/10/2026).
            let oferecer = Sessao.shared.fase == .unlocked && !Sessao.shared.metadata.wallets.isEmpty
                && AlertasDePreco.arquivo().chosen != true
            return try Nucleo.json(["oferecer": oferecer])
        case "vigias.ligarDeFabrica":
            // Qualquer resposta vale para sempre; sem permissao, fica desligado.
            guard Sessao.shared.fase == .unlocked, !Sessao.shared.metadata.wallets.isEmpty else { return try Nucleo.json(["ok": false]) }
            let permitido = pedido["permitido"]?.boolValue ?? false
            let metadata = Sessao.shared.metadata
            AlertasDePreco.mudar { arquivo in
                guard arquivo.chosen != true else { return }
                arquivo.chosen = true
                guard permitido else { return }
                arquivo.enabled = true
                arquivo.currency = AlertasDePreco.moedaDoApp(metadata.settings)
                if arquivo.coins.isEmpty { arquivo.coins = AlertasDePreco.padrao }
            }
            return try Nucleo.json(["ok": true])
        case "vigias.acompanhar":
            // Com o app destravado: as contas de agora e a moeda escolhida em Ativos.
            guard Sessao.shared.fase == .unlocked else { return try Nucleo.json(["ok": false]) }
            let metadata = Sessao.shared.metadata
            AvisoDeRecebimento.acompanhar(contas: AvisoDeRecebimento.contas(metadata))
            AlertasDePreco.acompanharMoeda(AlertasDePreco.moedaDoApp(metadata.settings))
            return try Nucleo.json(["ok": true])
        default:
            throw Nucleo.Falha(erro: "metodoDesconhecido")
        }
    }
}
