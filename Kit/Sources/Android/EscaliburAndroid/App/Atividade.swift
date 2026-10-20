import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburNetwork
import Foundation

/// O ultimo historico lido de cada carteira, nos metadados cifrados (o CachedActivity do iOS):
/// so o que a rede ja mostra publicamente.
struct CachedActivity: Codable, Equatable {
    let id: String
    let chainID: String
    let direction: String
    let asset: Asset?
    let amount: BigUInt
    let counterparty: String?
    let date: Date
    let status: String
    let statusNote: String?
    let fee: BigUInt?
    let hash: String
    let suspicious: Bool
    let receivedAsset: Asset?
    let receivedAmount: BigUInt?

    static let limit = 300

    init(_ entry: ActivityEntry) {
        id = entry.id
        chainID = entry.chainID
        direction = entry.direction.rawValue
        asset = entry.asset
        amount = entry.amount
        counterparty = entry.counterparty
        date = entry.date
        switch entry.status {
        case .pending(let note): (status, statusNote) = ("pendente", note)
        case .confirmed: (status, statusNote) = ("confirmada", nil)
        case .failed(let note): (status, statusNote) = ("falhou", note)
        }
        fee = entry.fee
        hash = entry.hash
        suspicious = entry.suspicious
        receivedAsset = entry.receivedAsset
        receivedAmount = entry.receivedAmount
    }

    var entry: ActivityEntry? {
        guard let direction = ActivityEntry.Direction(rawValue: direction) else { return nil }
        let state: ActivityEntry.Status
        switch status {
        case "pendente": state = .pending(statusNote)
        case "confirmada": state = .confirmed
        case "falhou": state = .failed(statusNote)
        default: return nil
        }
        return ActivityEntry(
            id: id, chainID: chainID, direction: direction, asset: asset, amount: amount, counterparty: counterparty, date: date,
            status: state, fee: fee, hash: hash, suspicious: suspicious, receivedAsset: receivedAsset, receivedAmount: receivedAmount
        )
    }
}

/// A ultima leitura do historico de uma rede: quando, e o saldo dela naquela hora.
struct ActivityFetch: Codable, Equatable {
    let at: Date
    let balanceMark: String?
    let empty: Bool

    static func mark(_ balance: ChainBalance?) -> String? {
        guard let balance else { return nil }
        return balance.holdings.map { "\($0.asset.id)=\($0.amount.decimalString)" }.sorted().joined(separator: ";")
    }

    static let activeLifetime: TimeInterval = 600
    static let emptyLifetime: TimeInterval = 12 * 3600

    func isStale(balanceMark now: String?, hasPending: Bool, at date: Date = Date()) -> Bool {
        if hasPending { return true }
        if let now, now != balanceMark { return true }
        let lifetime = empty && (now == nil || now == "") ? Self.emptyLifetime : Self.activeLifetime
        return date.timeIntervalSince(at) > lifetime
    }
}

/// O historico da carteira escolhida (o ActivityFeed do iOS): abre com o guardado e troca rede
/// por rede conforme cada uma responde. So pergunta a rede que pode ter mudado, no maximo 4 por
/// vez, as com saldo primeiro. Cada rede que responde vai para a interface pelo evento "atividade".
final class Atividade: @unchecked Sendable {
    static let shared = Atividade()

    private let trava = NSLock()
    private var carteiraID: UUID?
    private var porRede: [String: [ActivityEntry]] = [:]
    private var falhas: [Chain] = []
    private var indisponiveis: [(chain: Chain, motivo: String)] = []
    private var carregando = false
    private var lidaUmaVez = false
    private var restantes = 0
    private var geracao = 0

    static let leiturasParalelas = 4
    static let esperas: [UInt64] = [2, 5]

    func esquecer() {
        trava.withLock {
            carteiraID = nil
            porRede = [:]
            falhas = []
            indisponiveis = []
            lidaUmaVez = false
            geracao += 1
        }
    }

    // MARK: O retrato

    struct Item: Encodable {
        let id: String, rede: String, redeNome: String, redeCoingecko: String, direcao: String
        let simbolo: String, coingecko: String?, casas: Int, custom: Bool, quantidade: String
        let contraparte: String?, data: Date, situacao: String, nota: String?
        let taxa: String?, simboloNativo: String, casasNativas: Int, hash: String
        let recebidoSimbolo: String?, recebidoCoingecko: String?, recebidoCasas: Int?, recebidoQuantidade: String?, recebidoCustom: Bool
        let explorador: String, urlDoExplorador: String?
        let conferivel: Bool
    }

    struct SemHistorico: Encodable { let rede: String; let nome: String; let coingecko: String; let explorador: String; let url: String? }

    struct Retrato: Encodable {
        let carregando: Bool
        let lidaUmaVez: Bool
        let restantes: Int
        let falhas: [String]
        let semHistorico: [SemHistorico]
        let suspeitas: Int
        let itens: [Item]
        let redes: Int
    }

    func mostrar() -> Retrato {
        let metadata = Sessao.shared.metadata
        guard let wallet = metadata.selectedWallet else {
            return Retrato(carregando: false, lidaUmaVez: true, restantes: 0, falhas: [], semHistorico: [], suspeitas: 0, itens: [], redes: 0)
        }
        trava.withLock {
            if carteiraID != wallet.id {
                carteiraID = wallet.id
                let guardado = (metadata.activityCache?[wallet.id] ?? []).compactMap(\.entry)
                porRede = Dictionary(grouping: guardado, by: \.chainID)
                falhas = []
                indisponiveis = []
                lidaUmaVez = !guardado.isEmpty
            }
        }
        return retrato(wallet)
    }

    private func retrato(_ wallet: WalletMeta) -> Retrato {
        let saldos = Saldos.shared
        return trava.withLock {
            let todos = porRede.values.flatMap { $0 }
            let itens = todos.filter { !$0.suspicious }.sorted { $0.date > $1.date }.compactMap { item(wallet, $0) }
            // Redes sem historico publico: so as em que a carteira tem saldo.
            let sem = indisponiveis.filter { saldos.saldo($0.chain, carteira: wallet.id)?.holdings.contains { !$0.amount.isZero } == true }
                .map { par -> SemHistorico in
                    let url = wallet.account(par.chain).flatMap { par.chain.explorerURL(address: $0.address)?.absoluteString }
                    return SemHistorico(rede: par.chain.id, nome: par.chain.name, coingecko: par.chain.coingeckoID, explorador: par.chain.explorerName, url: url)
                }
            return Retrato(carregando: carregando, lidaUmaVez: lidaUmaVez, restantes: restantes, falhas: falhas.map(\.name).sorted(), semHistorico: sem,
                           suspeitas: todos.filter(\.suspicious).count, itens: itens, redes: wallet.accounts.count)
        }
    }

    private func item(_ wallet: WalletMeta, _ entrada: ActivityEntry) -> Item? {
        guard let chain = Chain.find(entrada.chainID) else { return nil }
        let (situacao, nota): (String, String?)
        switch entrada.status {
        case .pending(let detalhe): (situacao, nota) = ("pendente", detalhe)
        case .confirmed: (situacao, nota) = ("confirmada", nil)
        case .failed(let motivo): (situacao, nota) = ("falhou", motivo)
        }
        let asset = entrada.asset
        return Item(
            id: entrada.id, rede: chain.id, redeNome: chain.name, redeCoingecko: chain.coingeckoID, direcao: entrada.direction.rawValue,
            simbolo: asset?.symbol ?? chain.nativeSymbol, coingecko: asset?.coingeckoID ?? (asset == nil ? chain.coingeckoID : nil),
            casas: asset?.decimals ?? chain.nativeDecimals, custom: asset?.origin != nil || entrada.suspicious, quantidade: entrada.amount.decimalString,
            contraparte: entrada.counterparty, data: entrada.date, situacao: situacao, nota: nota, taxa: entrada.fee?.decimalString,
            simboloNativo: chain.nativeSymbol, casasNativas: chain.nativeDecimals, hash: entrada.hash,
            recebidoSimbolo: entrada.receivedAsset?.symbol, recebidoCoingecko: entrada.receivedAsset?.coingeckoID, recebidoCasas: entrada.receivedAsset?.decimals,
            recebidoQuantidade: entrada.receivedAmount?.decimalString, recebidoCustom: entrada.receivedAsset?.origin != nil,
            explorador: chain.explorerName, urlDoExplorador: chain.explorerURL(tx: entrada.hash)?.absoluteString,
            conferivel: entrada.direction == .received && chain.family == .evm && entrada.status == .confirmed
        )
    }

    private func emitir() {
        guard let wallet = Sessao.shared.metadata.selectedWallet, let json = try? Nucleo.json(retrato(wallet)) else { return }
        Eventos.emitir("atividade", json)
    }

    // MARK: A leitura

    private typealias Trabalho = (chain: Chain, account: DerivedAccount, source: any ActivitySource, usage: UTXOUsage?)

    enum Resultado: Sendable {
        case itens([ActivityEntry])
        case indisponivel(String)
        case falhou
    }

    func atualizar(forcar: Bool) async {
        _ = mostrar()
        let metadata = Sessao.shared.metadata
        guard let wallet = metadata.selectedWallet else { return }
        let (minha, emCurso) = trava.withLock { () -> (Int, Bool) in
            if carregando, carteiraID == wallet.id { return (geracao, true) }
            geracao += 1
            carregando = true
            return (geracao, false)
        }
        guard !emCurso else { return }
        defer {
            trava.withLock { if geracao == minha { carregando = false; restantes = 0 } }
            emitir()
        }
        let desligadas = metadata.settings.disabledChainIDs
        let trabalhos: [Trabalho] = wallet.accounts.compactMap { conta in
            guard let chain = Chain.find(conta.chainID), !desligadas.contains(chain.id), let source = ActivitySources.source(for: chain) else { return nil }
            return (chain, conta, source, wallet.utxoUsage[chain.id])
        }
        let ativas = Set(trabalhos.map(\.chain.id))
        var registros = metadata.activityFetched?[wallet.id] ?? [:]
        let saldos = Dictionary(uniqueKeysWithValues: trabalhos.compactMap { t in Saldos.shared.saldo(t.chain, carteira: wallet.id).map { (t.chain.id, $0) } })
        let ler: [Trabalho] = trava.withLock {
            porRede = porRede.filter { ativas.contains($0.key) }
            return trabalhos.filter { t in forcar || precisaLer(t.chain, registro: registros[t.chain.id], saldo: saldos[t.chain.id]) }
                .sorted { prioridade($0.chain, saldos) > prioridade($1.chain, saldos) }
        }
        var pendentes = ler
        var falharam: [Chain] = []
        var semHistorico: [(chain: Chain, motivo: String)] = []
        for tentativa in 0...Self.esperas.count {
            if tentativa > 0 { try? await Task.sleep(nanoseconds: Self.esperas[tentativa - 1] * 1_000_000_000) }
            guard trava.withLock({ geracao == minha }), !pendentes.isEmpty else { break }
            trava.withLock { restantes = pendentes.count }
            falharam = []
            await withTaskGroup(of: (Chain, Resultado).self) { grupo in
                var fila = pendentes[...]
                func proxima() {
                    guard let (chain, conta, source, uso) = fila.popFirst() else { return }
                    grupo.addTask { (chain, await Self.ler(source, chain: chain, account: conta, usage: uso)) }
                }
                for _ in 0..<Self.leiturasParalelas { proxima() }
                for await (chain, resultado) in grupo {
                    proxima()
                    let valida = trava.withLock { () -> Bool in
                        restantes -= 1
                        guard geracao == minha else { return false }
                        switch resultado {
                        case .itens(let itens):
                            porRede[chain.id] = itens
                            registros[chain.id] = ActivityFetch(at: Date(), balanceMark: ActivityFetch.mark(saldos[chain.id]), empty: itens.isEmpty)
                        case .indisponivel(let motivo):
                            porRede[chain.id] = nil
                            semHistorico.append((chain, motivo))
                        case .falhou:
                            falharam.append(chain)
                        }
                        falhas = falharam.sorted { $0.name < $1.name }
                        indisponiveis = semHistorico.sorted { $0.chain.name < $1.chain.name }
                        return true
                    }
                    if valida { emitir() }
                }
            }
            pendentes = ler.filter { t in falharam.contains { $0.id == t.chain.id } }
        }
        guard trava.withLock({ geracao == minha }) else { return }
        trava.withLock { lidaUmaVez = true }
        guard !ler.isEmpty else { return }
        let todos = trava.withLock { porRede.values.flatMap { $0 }.sorted { $0.date > $1.date }.prefix(CachedActivity.limit) }
        try? Sessao.shared.alterar { metadata in
            var cache = metadata.activityCache ?? [:]
            cache[wallet.id] = todos.map(CachedActivity.init)
            metadata.activityCache = cache
            var lidas = metadata.activityFetched ?? [:]
            lidas[wallet.id] = registros
            metadata.activityFetched = lidas
        }
    }

    /// Chamar com a trava.
    private func precisaLer(_ chain: Chain, registro: ActivityFetch?, saldo: ChainBalance?) -> Bool {
        guard let registro else { return true }
        if porRede[chain.id] == nil, !registro.empty { return true }
        if ActivitySources.source(for: chain) is EVMUnavailableActivitySource { return true }
        let pendente = porRede[chain.id]?.contains { if case .pending = $0.status { return true } else { return false } } ?? false
        return registro.isStale(balanceMark: ActivityFetch.mark(saldo), hasPending: pendente)
    }

    /// Chamar com a trava. A rede com saldo, depois a com historico guardado, depois o resto.
    private func prioridade(_ chain: Chain, _ saldos: [String: ChainBalance]) -> Int {
        if saldos[chain.id]?.holdings.isEmpty == false { return 2 }
        if porRede[chain.id]?.isEmpty == false { return 1 }
        return 0
    }

    private static func ler(_ source: any ActivitySource, chain: Chain, account: DerivedAccount, usage: UTXOUsage?) async -> Resultado {
        do {
            return .itens(try await source.history(chain: chain, account: account, usage: usage))
        } catch SendEngineError.unavailable(let motivo) {
            return .indisponivel(motivo)
        } catch {
            return .falhou
        }
    }

    // MARK: Conferir um recebimento

    /// Recebimento EVM que o indexador mostrou: "Confirmada" so depois de dois RPCs mostrarem o
    /// valor chegando a esta conta.
    func conferir(_ id: String) async -> (String, UInt64?) {
        let (entrada, dono) = trava.withLock { () -> (ActivityEntry?, String?) in
            let entrada = porRede.values.flatMap { $0 }.first { $0.id == id }
            let dono = entrada.flatMap { e in Chain.find(e.chainID) }.flatMap { Sessao.shared.metadata.selectedWallet?.account($0)?.address }
            return (entrada, dono)
        }
        guard let entrada, let chain = Chain.find(entrada.chainID), chain.family == .evm, let dono, let owner = try? EVMAddress(dono) else { return ("falhou", nil) }
        var contrato: EVMAddress?
        if case .token(let endereco)? = entrada.asset?.kind { contrato = try? EVMAddress(endereco.lowercased()) }
        if entrada.asset?.kind != .native, contrato == nil { return ("interna", nil) }
        guard let resultado = try? await EVMReader.shared.verifyIncoming(chain: chain, hash: entrada.hash, owner: owner, contract: contrato, amount: entrada.amount) else {
            return ("falhou", nil)
        }
        switch resultado {
        case .confirmed(let confirmacoes): return ("conferida", confirmacoes)
        case .notFound: return ("naoEncontrada", nil)
        case .mismatch: return ("naoConfere", nil)
        default: return ("interna", nil)
        }
    }
}
