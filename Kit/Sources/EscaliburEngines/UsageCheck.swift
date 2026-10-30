import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation

/// A carteira ja teve movimento em alguma rede? Para quem abre uma carteira com passphrase (pedido
/// do dono, 25/10/2026): toda passphrase abre alguma carteira, e a passphrase com uma letra trocada
/// abria uma carteira vazia sem aviso nenhum. Le o historico de cada rede com os mesmos leitores da
/// Atividade, quatro de cada vez, e para no primeiro movimento.
///
/// "Nunca" so quando toda rede foi lida (revisao de blockchain de 26/10/2026): antes, o indexador que
/// recusava o app (Base, Arbitrum, Polygon) e a rede sem historico (X Layer, Sonic) contavam como
/// vazias, e a tela dizia "nunca usada" para a passphrase certa. Agora:
/// - qualquer item do historico conta, ate o suspeito: endereco nunca usado nao recebe nem poeira;
/// - na EVM vale tambem o nonce e o saldo, de dois provedores (`EVMReader.accountFootprint`), e,
///   sem historico, os saldos de token; nada disso depende de indexador;
/// - rede que nao respondeu entra na lista de nao lidas, nunca na de vazias.
public enum UsageCheck {
    public enum Outcome: Equatable, Sendable {
        case used
        case never
        /// Nenhum movimento nas redes que responderam; estas (ids) nao responderam, nem na segunda vez.
        case incomplete(failed: [String])
    }

    /// Quantas redes leem ao mesmo tempo: os provedores gratis cortam a rajada.
    static let parallelReads = 4
    static let retryDelay: Duration = .seconds(3)

    enum Read: Sendable, Equatable { case used, empty, failed }

    public static func run(_ accounts: [DerivedAccount]) async -> Outcome {
        let jobs: [(chain: Chain, account: DerivedAccount)] = accounts.compactMap { account in
            guard let chain = Chain.find(account.chainID) else { return nil }
            return (chain, account)
        }
        var pending = jobs
        var failed: [String] = []
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(for: retryDelay) }
            if Task.isCancelled { break }
            failed = []
            let found = await withTaskGroup(of: (String, Read).self) { group -> Bool in
                var queue = pending[...]
                func next() {
                    guard let job = queue.popFirst() else { return }
                    group.addTask { (job.chain.id, await read(job.chain, account: job.account)) }
                }
                for _ in 0..<parallelReads { next() }
                for await (chainID, result) in group {
                    switch result {
                    case .used:
                        group.cancelAll()
                        return true
                    case .empty: break
                    case .failed: failed.append(chainID)
                    }
                    next()
                }
                return false
            }
            if found { return .used }
            pending = jobs.filter { failed.contains($0.chain.id) }
            if pending.isEmpty { return .never }
        }
        return .incomplete(failed: failed)
    }

    /// Uma rede: o historico e, na EVM, o rastro da conta.
    static func read(_ chain: Chain, account: DerivedAccount) async -> Read {
        let history: Read
        if let source = ActivitySources.source(for: chain) {
            history = await readHistory(source, chain: chain, account: account)
        } else {
            history = .failed
        }
        guard chain.family == .evm, history != .used else { return history }
        return await combine(history: history, footprint: await evmFootprint(chain, account: account), tokens: {
            history == .failed ? await evmTokens(chain, account: account) : .empty
        })
    }

    /// Na EVM: movimento no historico ou no rastro decide; sem historico, vazio so com o rastro e os
    /// saldos de token lidos e zerados. Historico lido e vazio com o rastro sem responder fica vazio,
    /// como antes desta conferencia.
    static func combine(history: Read, footprint: Read, tokens: () async -> Read) async -> Read {
        if history == .used || footprint == .used { return .used }
        if history == .empty { return .empty }
        guard footprint == .empty else { return .failed }
        return await tokens()
    }

    private static func readHistory(_ source: any ActivitySource, chain: Chain, account: DerivedAccount) async -> Read {
        do {
            let items = try await source.history(chain: chain, account: account, usage: nil)
            return items.isEmpty ? .empty : .used
        } catch {
            // Indexador que recusa, rede sem historico nesta versao ou falha de rede: nao foi lida.
            return .failed
        }
    }

    private static func evmFootprint(_ chain: Chain, account: DerivedAccount) async -> Read {
        guard let address = try? EVMEngineSupport.account(account, chain: chain).address,
              let footprint = try? await EVMReader.shared.accountFootprint(chain: chain, address: address)
        else { return .failed }
        return footprint.nonce > 0 || footprint.nativeBalance > 0 ? .used : .empty
    }

    private static func evmTokens(_ chain: Chain, account: DerivedAccount) async -> Read {
        guard let balance = try? await BalanceService.shared.balance(chain: chain, addresses: [account.address]) else { return .failed }
        let holds = balance.holdings.contains { $0.amount > 0 } || !(balance.unlisted ?? []).isEmpty
        return holds ? .used : .empty
    }
}
