import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation

/// O que a carteira recebe e em que endereco: a mesma conta do Receber do iOS (ReceiveSheet e
/// ReceiveCoin), sem a interface.
enum Receber {
    /// Um ativo que a carteira recebe numa rede.
    struct Ativo: Encodable {
        let id: String
        let rede: String
        let redeNome: String
        let redeCoingecko: String
        let familia: String
        let simbolo: String
        let nome: String
        let coingecko: String?
        let nativo: Bool
        /// O contrato (ou o emissor, na XRP Ledger e na Stellar) que quem envia tem de usar.
        let contrato: String?
        let usaEmissor: Bool
        let emitido: Bool
        /// O padrao do token na rede ("ERC-20", "TRC-20"), para achar a opcao certa na corretora.
        let padrao: String
        let custom: Bool
        /// A moeda que esta forma representa (o BTC no WBTC), e a rede nativa dela.
        let formaDe: String?
        let formaDeRedeNome: String?
        let formaDeSimbolo: String?

        init(_ asset: Asset) {
            let chain = asset.chain
            id = asset.id
            rede = asset.chainID
            redeNome = chain?.name ?? asset.chainID
            redeCoingecko = chain?.coingeckoID ?? ""
            familia = chain?.family.rawValue ?? ""
            simbolo = asset.symbol
            nome = asset.kind == .native ? (chain?.nativeName ?? asset.name) : asset.name
            coingecko = asset.coingeckoID
            nativo = asset.kind == .native
            contrato = CustomToken.reference(asset.kind)
            usaEmissor = chain.map(CustomToken.usesIssuer) ?? false
            if case .issued = asset.kind { emitido = true } else { emitido = false }
            padrao = chain.map(Receber.padrao) ?? ""
            custom = asset.isCustom
            let base = asset.coingeckoID.flatMap { Receber.formas[$0] }
            formaDe = base
            let casa = base.flatMap { id in Chain.all.first { $0.coingeckoID == id } }
            formaDeRedeNome = casa?.name
            formaDeSimbolo = casa?.nativeSymbol
        }
    }

    /// Uma moeda na lista de receber, com as redes em que a carteira recebe essa moeda.
    struct Moeda: Encodable {
        let id: String
        let simbolo: String
        let nome: String
        let coingecko: String?
        let custom: Bool
        let ativos: [Ativo]
        /// As versoes embrulhadas (WBTC e cbBTC no BTC): mais uma rede, cada uma com o seu token.
        let outrasFormas: [Ativo]
        let naCarteira: Bool
    }

    struct Endereco: Encodable {
        let endereco: String
        /// XRP Ledger, Stellar, Tron, Polkadot e NEAR: a conta so existe depois do primeiro recebimento.
        let existe: Bool
        /// Token emitido (XRP Ledger, Stellar): a conta ja tem a linha de confianca com o emissor.
        let temLinha: Bool
        let observacao: Bool
        let tronOutraChave: Bool
    }

    /// Tokens que representam outra moeda, pelo id de preco: aparecem tambem dentro dela no
    /// Receber. So agrupamento de tela.
    static let formas: [String: String] = [
        "wrapped-bitcoin": "bitcoin", "binance-bitcoin": "bitcoin", "coinbase-wrapped-btc": "bitcoin",
        "weth": "ethereum",
        "binance-peg-xrp": "ripple", "binance-peg-dogecoin": "dogecoin", "binance-peg-cardano": "cardano",
        "binance-peg-polkadot": "polkadot", "binance-peg-litecoin": "litecoin", "binance-peg-avalanche": "avalanche-2",
        "binance-peg-near-protocol": "near", "binance-peg-sol": "solana", "sol-wormhole": "solana",
    ]

    static func padrao(_ chain: Chain) -> String {
        switch chain.family {
        case .evm: return chain.id == "bnb" ? "BEP-20" : "ERC-20"
        case .tron: return "TRC-20"
        case .solana: return "SPL"
        case .ton: return Textos.t("Jetton")
        case .stellar, .xrpl: return Textos.t("Ativo emitido")
        case .utxo, .sui, .cardano, .polkadot, .near, .aptos: return ""
        }
    }

    /// Tudo o que a carteira recebe: nativas e tokens da lista nas redes com conta, e as moedas
    /// custom (cada uma na sua linha, nunca junto de um ativo da lista).
    static func recebiveis(_ metadata: Metadata) -> [Asset] {
        let contas = Set(metadata.selectedWallet?.accounts.map(\.chainID) ?? [])
        let custom = metadata.customTokens.filter { contas.contains($0.chainID) }
        return Chain.all.filter { contas.contains($0.id) }.flatMap { TokenRegistry.assets(on: $0) } + custom
    }

    /// Agrupa pelo id de preco: primeiro as moedas nativas, na ordem das redes; depois os tokens,
    /// na ordem da lista curada.
    static func agrupar(_ ativos: [Asset]) -> [(chave: String, ativos: [Asset])] {
        var ordem: [String] = []
        var porChave: [String: [Asset]] = [:]
        for ativo in ativos {
            let chave = ativo.coingeckoID ?? (ativo.isCustom ? ativo.id : "\(ativo.symbol):\(ativo.chainID)")
            if porChave[chave] == nil { ordem.append(chave) }
            porChave[chave, default: []].append(ativo)
        }
        var posicao: [String: Int] = [:]
        for (indice, token) in TokenRegistry.tokens.enumerated() where posicao[token.coingeckoID ?? token.id] == nil {
            posicao[token.coingeckoID ?? token.id] = indice
        }
        let grupos = ordem.compactMap { chave in porChave[chave].map { (chave, $0) } }
        let nativas = grupos.filter { $0.1.contains { $0.kind == .native } }
        let tokens = grupos.filter { !$0.1.contains { $0.kind == .native } }
        return nativas + tokens.sorted { (posicao[$0.0] ?? .max, $0.0) < (posicao[$1.0] ?? .max, $1.0) }
    }

    static func moedas() -> [Moeda] {
        let metadata = Sessao.shared.metadata
        let recebiveis = recebiveis(metadata)
        let saldos = metadata.selectedWallet.flatMap { metadata.balanceCache[$0.id] } ?? [:]
        let comSaldo = Set(saldos.values.flatMap(\.holdings).filter { !$0.amount.isZero }.map(\.asset.id))
        return agrupar(recebiveis).map { grupo in
            let primeiro = grupo.ativos[0]
            let nativo = grupo.ativos.first { $0.kind == .native }
            let outras: [Asset]
            if let id = primeiro.coingeckoID, nativo != nil {
                outras = recebiveis.filter { ativo in ativo.coingeckoID.flatMap { formas[$0] } == id }
            } else {
                outras = []
            }
            return Moeda(
                id: grupo.chave, simbolo: primeiro.symbol, nome: nativo.map { $0.chain?.nativeName ?? $0.name } ?? primeiro.name,
                coingecko: primeiro.coingeckoID, custom: primeiro.isCustom, ativos: grupo.ativos.map(Ativo.init),
                outrasFormas: outras.map(Ativo.init), naCarteira: grupo.ativos.contains { comSaldo.contains($0.id) }
            )
        }
    }

    static func endereco(ativo id: String) throws -> Endereco {
        let metadata = Sessao.shared.metadata
        guard let wallet = metadata.selectedWallet else { throw Sessao.Falha.carteiraNaoEncontrada }
        guard let ativo = recebiveis(metadata).first(where: { $0.id == id }), let chain = ativo.chain,
              let conta = wallet.account(chain) else { throw Nucleo.Falha(erro: "ativo desconhecido") }
        let saldo = metadata.balanceCache[wallet.id]?[chain.id]
        return Endereco(
            endereco: conta.address, existe: saldo?.accountExists ?? true,
            temLinha: saldo?.holdings.contains { $0.asset.id == ativo.id } ?? false,
            observacao: wallet.isWatchOnly, tronOutraChave: chain.family == .tron && wallet.tronForeignControl == true
        )
    }
}
