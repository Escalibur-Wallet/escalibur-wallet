import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation

/// Quem mais tem poder sobre as contas de uma carteira, rede por rede (`ForeignControl`; auditoria 8, 14/11/2026). Os dois
/// apps chamam a mesma conferencia: depois de gravar ou abrir a carteira, ao abrir o Receber de uma rede (a hora do
/// deposito) e uma vez por dia ao destravar. Cada leitura pede dois operadores de acordo; sem acordo, ou sem rede, nada
/// muda na carteira.
public enum ForeignControlCheck {
    public enum Verdict: Sendable, Equatable {
        /// Os operadores veem a conta so com a chave da frase.
        case clean
        case foreign(ForeignControl)
        /// Sem resposta, ou sem acordo: a marca guardada fica como estava.
        case unknown
    }

    /// Quantas redes ao mesmo tempo: os provedores publicos limitam por IP.
    static let parallelism = 3

    /// A conta de uma rede. Na Tron, o mesmo veredito que poe a marca propria dela (`tronForeignControl`). `marked`: a conta ja
    /// tem a marca, e "limpa" so vale com todos os operadores de acordo, onde a leitura pergunta a mais de dois: tirar a marca
    /// reabre o deposito (rodada 1 da auditoria 8).
    public static func check(_ account: DerivedAccount, marked: Bool = false) async -> Verdict {
        guard let chain = Chain.find(account.chainID), !account.isAddressOnly else { return .unknown }
        do {
            switch chain.family {
            case .evm:
                guard let owner = try? EVMAddress(account.address) else { return .unknown }
                switch try await EVMReader.shared.accountCode(chain: chain, account: owner, everyone: marked) {
                case .some(.none): return .clean
                case .some(.delegation(let delegate)): return .foreign(ForeignControl(kind: .delegation, detail: delegate.checksummed))
                case .some(.contract): return .foreign(ForeignControl(kind: .delegation))
                case nil: return .unknown
                }
            case .tron:
                guard let owner = TronAddress(account.address),
                      let control = try await TronReader.shared.agreedOwnerControl(owner: owner, everyone: marked) else { return .unknown }
                return control.isCompromised ? .foreign(ForeignControl(kind: .otherKey)) : .clean
            case .xrpl:
                guard let foreign = try await XRPLReader.shared.foreignControl(address: account.address, everyone: marked) else { return .unknown }
                return verdict(foreign)
            case .stellar:
                guard let id = StellarAccountID(address: account.address),
                      let foreign = try await StellarReader().foreignSigners(id) else { return .unknown }
                return verdict(foreign)
            case .near:
                guard case .success(let owner) = NEARAccountID.parse(account.address),
                      let foreign = try await NEARReader.shared.foreignFullAccessKeys(owner: owner, publicKey: account.publicKey, everyone: marked)
                else { return .unknown }
                return verdict(foreign)
            case .ton:
                let wallet = try TONSendEngine.wallet(of: account)
                return verdict(try await TONReader.shared.foreignExtensions(address: wallet.address, version: wallet.version))
            case .polkadot:
                guard case .success(let owner) = PolkadotAddress.parse(account.address),
                      let foreign = try await PolkadotReader.shared.proxies(owner: owner, everyone: marked) else { return .unknown }
                return verdict(foreign)
            case .aptos:
                guard case .success(let owner) = AptosAddress.parse(account.address) else { return .unknown }
                return verdict(try await AptosReader.shared.authenticationKeyRotated(owner: owner, everyone: marked))
            case .solana:
                guard let owner = try? SolanaPublicKey(base58: account.address) else { return .unknown }
                let foreign = try await SolanaNetworkReader.shared.foreignControl(owner: owner, everyone: marked)
                return foreign ? .foreign(ForeignControl(kind: .otherKey)) : .clean
            case .utxo, .sui, .cardano:
                // A chave da frase e a unica que assina por estas contas: nao ha outra para ler.
                return .clean
            }
        } catch {
            return .unknown
        }
    }

    static func verdict(_ foreign: Bool) -> Verdict {
        foreign ? .foreign(ForeignControl(kind: .otherKey)) : .clean
    }

    /// Todas as contas, poucas redes por vez, pelo id da rede. `marked`: as redes que ja tem a marca.
    public static func check(_ accounts: [DerivedAccount], marked: Set<String> = []) async -> [String: Verdict] {
        // So as redes que tem o que ler: a "limpa" sem consulta do Bitcoin, da Sui e da Cardano fazia a conferencia sem rede
        // nenhuma contar como respondida, e a do dia esperava 24 h sem ter lido nada (rodada 5 da auditoria 8).
        let reading = accounts.filter { account in Chain.find(account.chainID).map(reads) ?? false }
        let unique = reading.reduce(into: [String: DerivedAccount]()) { $0[$1.chainID] = $0[$1.chainID] ?? $1 }.values.sorted { $0.chainID < $1.chainID }
        var verdicts: [String: Verdict] = [:]
        var index = 0
        // Cancelada (a pausa da rodada do dia), os lotes seguintes nem saem (rodada 3 da auditoria 8).
        while index < unique.count, !Task.isCancelled {
            let batch = Array(unique[index..<min(index + parallelism, unique.count)])
            index += batch.count
            await withTaskGroup(of: (String, Verdict).self) { group in
                for account in batch { group.addTask { (account.chainID, await check(account, marked: marked.contains(account.chainID))) } }
                for await (chainID, verdict) in group { verdicts[chainID] = verdict }
            }
        }
        return verdicts
    }

    /// As marcas da carteira depois de uma conferencia: a de fora entra (ou troca o contrato), a limpa sai, e a sem resposta
    /// fica como estava. A Tron fica de fora: ela tem a marca propria, que fecha o Receber (`tronMark`). Nil quando nao
    /// sobra marca. `startingFrom`: as marcas de quando a conferencia comecou, as que ela leu com todos os operadores; a limpa
    /// so tira a marca que ainda e a mesma de entao. Uma conferencia de dois que terminava depois de outra por a marca a apagava
    /// (rodada 2), e a que comecou com a marca e terminou por ultimo apagava a nova, posta no meio (rodada 3 da auditoria 8).
    public static func apply(_ verdicts: [String: Verdict], to marks: [String: ForeignControl]?, startingFrom start: [String: ForeignControl]?) -> [String: ForeignControl]? {
        var updated = marks ?? [:]
        for (chainID, verdict) in verdicts where chainID != Chain.tron.id {
            switch verdict {
            case .foreign(let control): updated[chainID] = control
            case .clean where start?[chainID] != nil && updated[chainID] == start?[chainID]: updated[chainID] = nil
            case .clean, .unknown: continue
            }
        }
        return updated.isEmpty ? nil : updated
    }

    /// A marca da Tron depois de uma conferencia: `true` com outra chave, `nil` limpa, e a de antes sem resposta.
    public static func tronMark(_ verdicts: [String: Verdict], previous: Bool?) -> Bool? {
        switch verdicts[Chain.tron.id] {
        case .foreign: return true
        case .clean: return nil
        case .unknown, nil: return previous
        }
    }

    /// A rede tem outra chave para ler: no Bitcoin e nas outras UTXO, na Sui e na Cardano, so a chave da frase assina.
    public static func reads(_ chain: Chain) -> Bool { ![.utxo, .sui, .cardano].contains(chain.family) }

    /// Quanto tempo a conferencia do destravar espera entre uma e outra, por carteira.
    public static let interval: TimeInterval = 24 * 60 * 60

    /// A espera sorteada antes da conferencia do destravar, de 30 s a 5 min, para ela nao sair colada no destravar (quem ve a
    /// rede nao liga o destravar a consulta). Aqui, e nao no app: la, a unica fonte de aleatoriedade e o SecRandomCopyBytes.
    public static func checkDelay() -> TimeInterval {
        var generator = SystemRandomNumberGenerator()
        return Double.random(in: 30...300, using: &generator)
    }

    /// As redes EVM que a previa da importacao confere, antes de guardar: onde o golpe da "frase com saldo" com delegacao
    /// EIP-7702 aparece (o USDT e a taxa). As outras entram na conferencia completa, logo depois de gravar.
    public static let previewChains: [Chain] = [.ethereum, .bnb, .base, .arbitrum, .polygon, .optimism]

    /// A primeira rede da previa em que o endereco EVM tem contrato instalado, com dois operadores de acordo; nil sem
    /// nenhuma (ou sem resposta). Para o aviso na previa, como o da Tron.
    /// `skipping`: as redes desligadas nos Ajustes, que nao sao consultadas por nada; a marca vista numa delas nunca seria
    /// relida e fecharia o Receber de todas as EVM (rodada 5 da auditoria 8).
    public static func previewDelegation(address: String, skipping: Set<String> = []) async -> (chain: Chain, control: ForeignControl)? {
        guard let owner = try? EVMAddress(address) else { return nil }
        let chains = previewChains.filter { !skipping.contains($0.id) }
        // Poucas por vez, como na conferencia completa: os provedores publicos limitam por IP.
        for start in stride(from: 0, to: chains.count, by: parallelism) {
            let batch = Array(chains[start..<min(start + parallelism, chains.count)])
            let found = await withTaskGroup(of: (Int, ForeignControl?).self) { group in
                for (offset, chain) in batch.enumerated() {
                    group.addTask {
                        let code = (try? await EVMReader.shared.accountCode(chain: chain, account: owner)) ?? nil
                        switch code {
                        case .some(.delegation(let delegate)): return (offset, ForeignControl(kind: .delegation, detail: delegate.checksummed))
                        case .some(.contract): return (offset, ForeignControl(kind: .delegation))
                        case .some(.none), nil: return (offset, nil)
                        }
                    }
                }
                var all: [(Int, ForeignControl)] = []
                for await (offset, control) in group { if let control { all.append((offset, control)) } }
                return all.min { $0.0 < $1.0 }
            }
            if let found { return (batch[found.0], found.1) }
        }
        return nil
    }
}

public extension ForeignControl {
    /// O aviso, igual no Receber, na revisao e na previa da importacao das duas plataformas. A tela ja diz a rede.
    var message: String {
        switch kind {
        case .delegation:
            if let detail, detail.count > 12 {
                let short = String(detail.prefix(6)) + "…" + String(detail.suffix(4))
                return kitText("Esta conta tem um contrato instalado por delegação (EIP-7702), o \(short). Quem controla esse contrato pode mover o que entrar nela. Se não foi você quem o instalou, a senha da carteira vazou: não deposite aqui e passe o saldo para outra carteira.")
            }
            return kitText("Esta conta tem código de contrato nesta rede. Quem controla esse código pode mover o que entrar nela. Se não foi você, a senha da carteira vazou: não deposite aqui e passe o saldo para outra carteira.")
        case .otherKey:
            return kitText("Outra chave ou conta também tem poder sobre esta conta nesta rede. O que entrar aqui pode sair sem a sua assinatura. Se não foi você quem a adicionou, a senha da carteira vazou: não deposite aqui e passe o saldo para outra carteira.")
        }
    }
}
