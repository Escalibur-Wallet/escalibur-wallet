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
        let todas = nativas + tokens.sorted { (posicao[$0.0] ?? .max, $0.0) < (posicao[$1.0] ?? .max, $1.0) }
        let fixas = todas.filter { primeiras.contains($0.0) }.sorted { primeiras.firstIndex(of: $0.0)! < primeiras.firstIndex(of: $1.0)! }
        return fixas + todas.filter { !primeiras.contains($0.0) }
    }

    /// As primeiras da lista, nesta ordem, e depois as outras como antes (pedido do dono,
    /// 30/10/2026): BTC, XRP, ETH, USDT, USDC, XLM, BNB e TRX. A mesma do iOS.
    static let primeiras = ["bitcoin", "ripple", "ethereum", "tether", "usd-coin", "stellar", "binancecoin", "tron"]

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

    /// `rede`: a moeda achada na busca, fora da lista; o endereco e o da conta nessa rede.
    static func endereco(ativo id: String, rede: String? = nil) throws -> Endereco {
        let metadata = Sessao.shared.metadata
        guard let wallet = metadata.selectedWallet else { throw Sessao.Falha.carteiraNaoEncontrada }
        let achado = recebiveis(metadata).first(where: { $0.id == id })
        guard let chain = achado?.chain ?? rede.flatMap(Chain.find), achado != nil || CustomToken.supports(chain),
              let conta = wallet.account(chain) else { throw Nucleo.Falha(erro: "ativo desconhecido") }
        let ativo = achado ?? Asset(chainID: chain.id, kind: .native, symbol: "", name: "", decimals: 0, coingeckoID: nil,
                                    isStablecoin: false, origin: .discovered)
        let saldo = metadata.balanceCache[wallet.id]?[chain.id]
        return Endereco(
            endereco: conta.address, existe: saldo?.accountExists ?? true,
            temLinha: saldo?.holdings.contains { $0.asset.id == ativo.id } ?? false,
            observacao: wallet.isWatchOnly, tronOutraChave: chain.family == .tron && wallet.tronForeignControl == true
        )
    }

    // MARK: Busca fora da lista

    /// A busca de qualquer moeda, a mesma do iOS (`CoinSearchStore`, pedido do dono, 30/10/2026: o
    /// Android so filtrava a lista verificada). O CoinGecko primeiro; com ele em pausa (resposta do
    /// CoinPaprika) ou sem nada, a lista embarcada antes; as duas fontes fora, so a lista.
    struct Resultado: Encodable {
        let id: String
        let simbolo: String
        let nome: String
        let posicao: Int?
    }

    struct Busca: Encodable {
        /// "ok", "frase" (parece o comeco das palavras de uma carteira: nada saiu do celular) ou
        /// "falhou" (as fontes e a lista nao responderam).
        let estado: String
        let resultados: [Resultado]
    }

    static func buscar(_ texto: String) async -> Busca {
        let chave = texto.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard chave.count >= 2 else { return Busca(estado: "ok", resultados: []) }
        if pareceFrase(chave) { return Busca(estado: "frase", resultados: []) }
        func saida(_ lista: [CoinSearchResult]) -> Busca {
            Busca(estado: "ok", resultados: lista.map { Resultado(id: $0.id, simbolo: $0.symbol, nome: $0.name, posicao: $0.rank) })
        }
        if let achados = try? await CoinCatalog.search(chave) {
            let reserva = achados.isEmpty || achados.contains { $0.id.hasPrefix(CoinCatalog.paprikaPrefix) }
            let locais = reserva ? (lista()?.search(chave) ?? []) : []
            guard !locais.isEmpty else { return saida(achados) }
            return saida(locais + achados.filter { r in !locais.contains { $0.symbol == r.symbol && $0.name == r.name } })
        }
        let locais = lista()?.search(chave) ?? []
        return locais.isEmpty ? Busca(estado: "falhou", resultados: []) : saida(locais)
    }

    /// Tres palavras ou mais das listas BIP-39: quem cola a frase aqui mandaria ao CoinGecko o
    /// bastante para o resto cair numa GPU (auditoria 6, A6-11). A mesma regra do iOS.
    static func pareceFrase(_ chave: String) -> Bool {
        let palavras = chave.split { !$0.isLetter }
        guard palavras.count >= 3 else { return false }
        let listas = BIP39Language.allCases.compactMap { try? WordlistStore.shared.wordlist(for: $0) }
        return palavras.filter { palavra in listas.contains { $0.contains(String(palavra)) } }.count >= 3
    }

    /// As redes de uma moeda da busca em que esta carteira recebe ela.
    struct Redes: Encodable {
        let id: String
        let simbolo: String
        let nome: String
        /// O CoinGecko publicou um aviso sobre a moeda (ataque, migracao, golpe).
        let aviso: Bool
        /// Uma por rede, com o contrato, e se ja esta entre as moedas custom da carteira.
        let ativos: [AtivoDoCatalogo]
        /// Redes em que a moeda existe e a carteira tem, mas que estao desligadas nela.
        let desligadas: [String]
    }

    struct AtivoDoCatalogo: Encodable {
        let ativo: Ativo
        let jaAdicionada: Bool
    }

    /// A lista embarcada primeiro, sem esperar; a leitura na rede (o aviso e as redes do
    /// CoinPaprika) entra se responder em ate 2 s, como no iOS. Sem a moeda na lista, so a rede.
    static func redes(id: String, simbolo: String?, nome: String?) async throws -> Redes {
        let local = lista()?.coin(id: id)
        let moeda: CatalogCoin
        if let local {
            let naRede = await comPrazo(segundos: 2) { try? await CoinCatalog.coinAllNetworks(id: id, symbol: simbolo, name: nome) }
            moeda = naRede.map { local.merged(with: $0, addingNetworks: true) } ?? local
        } else {
            moeda = try await CoinCatalog.coinAllNetworks(id: id, symbol: simbolo, name: nome)
        }
        let metadata = Sessao.shared.metadata
        let contas = Set(metadata.selectedWallet?.accounts.map(\.chainID) ?? [])
        let conhecidos = Set(recebiveis(metadata).map(\.id))
        var ativos: [AtivoDoCatalogo] = []
        for rede in moeda.networks where contas.contains(rede.chainID) {
            guard let ativo = ativoDoCatalogo(moeda, rede), !conhecidos.contains(ativo.id) else { continue }
            ativos.append(AtivoDoCatalogo(ativo: Ativo(ativo), jaAdicionada: jaAdicionada(ativo, metadata)))
        }
        let desligadas = moeda.networks.filter { !contas.contains($0.chainID) }.compactMap { $0.chain?.name }
        return Redes(id: moeda.id, simbolo: moeda.symbol, nome: moeda.name, aviso: moeda.hasNotice, ativos: ativos, desligadas: desligadas)
    }

    /// A moeda da busca como ativo: token fora da lista, so para mostrar. O contrato passa pela
    /// validacao completa da moeda custom; invalido, nil. O mesmo `catalogAsset` do iOS.
    static func ativoDoCatalogo(_ moeda: CatalogCoin, _ rede: CatalogCoin.Network) -> Asset? {
        guard let chain = rede.chain, case .token(let contrato)? = try? CustomToken.kind(chain: chain, address: rede.contract) else { return nil }
        let preco = moeda.id.hasPrefix(CoinCatalog.paprikaPrefix) ? nil : moeda.id
        return Asset(chainID: chain.id, kind: .token(contract: contrato), symbol: moeda.symbol, name: moeda.name, decimals: 0,
                     coingeckoID: preco, isStablecoin: false, origin: .discovered)
    }

    /// O mesmo contrato na mesma rede ja esta entre as custom (na EVM, sem olhar a caixa).
    static func jaAdicionada(_ ativo: Asset, _ metadata: Metadata) -> Bool {
        guard let referencia = CustomToken.reference(ativo.kind), let chain = ativo.chain else { return false }
        return metadata.customTokens.contains { token in
            guard token.chainID == chain.id, let salvo = CustomToken.reference(token.kind) else { return false }
            return chain.family == .evm ? salvo.lowercased() == referencia.lowercased() : salvo == referencia
        }
    }

    /// O resultado de `operacao`, ou nil se passar de `segundos`.
    static func comPrazo<T: Sendable>(segundos: Double, _ operacao: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { grupo in
            grupo.addTask { await operacao() }
            grupo.addTask {
                try? await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
                return nil
            }
            let primeiro = await grupo.next() ?? nil
            grupo.cancelAll()
            return primeiro
        }
    }

    /// A lista embarcada (catalogo-moedas.json, a mesma do iOS), que o app copia do APK para a pasta
    /// dos recursos do nucleo. Lida uma vez.
    nonisolated(unsafe) private static var listaLida: CoinList??
    private static let trava = NSLock()

    static func lista() -> CoinList? {
        trava.lock()
        defer { trava.unlock() }
        if let listaLida { return listaLida }
        let lida = CoreResources.directory.flatMap { pasta in
            (try? Data(contentsOf: URL(fileURLWithPath: pasta).appendingPathComponent("catalogo-moedas.json"))).flatMap { try? CoinList(data: $0) }
        }
        listaLida = .some(lida)
        return lida
    }
}
