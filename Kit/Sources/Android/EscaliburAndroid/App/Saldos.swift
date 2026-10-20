import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburNetwork
import Foundation

/// Os saldos e precos da carteira em uso: o `Portfolio` do iOS (App/Services/Portfolio.swift),
/// com a mesma leitura (seis redes por vez, as com saldo primeiro, mais duas tentativas para quem
/// falhou) e a mesma conta das linhas. A cada rede que chega, a interface recebe o retrato novo
/// pelo evento "saldos".
final class Saldos: @unchecked Sendable {
    static let shared = Saldos()

    /// Um ativo na lista: o mesmo ativo em varias redes vira uma linha so.
    struct Linha: Encodable {
        let id: String
        let simbolo: String
        let nome: String
        let coingecko: String?
        let estavel: Bool
        let posicoes: [Posicao]
        let preco: Double?
        let variacao24h: Double?
        let valor: Double?
        let casas: Int
        /// A soma das redes nas casas da linha, em unidades inteiras (texto decimal).
        let total: String
        let reconhecido: Bool
        let custom: Bool
        let conferido: Bool
    }

    struct Posicao: Encodable {
        let rede: String
        let redeNome: String
        let ativo: String
        let quantidade: String
        let disponivel: String
        let casas: Int
        let contrato: String?
    }

    struct Outro: Encodable {
        let id: String
        let simbolo: String
        let nome: String
        let rede: String
        let quantidade: String
        let casas: Int
        let preco: Double?
        let valor: Double?
        let suspeito: Bool
        let logo: String?
    }

    struct Retrato: Encodable {
        let carteira: String?
        let linhas: [Linha]
        let todasAsLinhas: [Linha]
        let outros: [Outro]
        let suspeitos: [Outro]
        let total: Double
        let variacao24h: Double
        let variacao24hPct: Double
        let carregando: Bool
        let falhas: [String]
        let atualizado: Date?
        let semRede: Bool
        let tokensDesconhecidos: Int
        let moeda: String
        /// O preco do bitcoin nas outras moedas, para o total em outra unidade.
        let bitcoin: [String: Double]
    }

    private let trava = NSLock()
    private var carteiraID: UUID?
    private var saldos: [String: ChainBalance] = [:]
    private var cotacoes: [String: Quote] = [:]
    private var cotacoesPorContrato: [String: Quote] = [:]
    private var precosDoBitcoin: [String: Double] = [:]
    private var carregando = false
    private var pendente = false
    private var falhas: [Chain] = []
    private var atualizado: Date?
    private var semRede = false
    private var lidas: Set<UUID> = []
    private var ultimaLeitura: [UUID: Date] = [:]

    static let intervaloAutomatico: TimeInterval = 60
    static let intervaloRedeVazia: TimeInterval = 300
    static let leiturasParalelas = 6
    static let prefixoDeContrato = "contrato:"

    /// Travou ou apagou: nada da carteira fica na memoria.
    func esquecer() {
        trava.withLock {
            carteiraID = nil
            saldos = [:]
            cotacoes = [:]
            cotacoesPorContrato = [:]
            falhas = []
            atualizado = nil
            lidas = []
            ultimaLeitura = [:]
        }
    }

    /// Mostra o cache da carteira em uso na hora.
    func mostrar() -> Retrato {
        let metadata = Sessao.shared.metadata
        guard let wallet = metadata.selectedWallet else { return retrato(nil, metadata) }
        trava.withLock {
            if carteiraID != wallet.id {
                carteiraID = wallet.id
                saldos = metadata.balanceCache[wallet.id] ?? [:]
                cotacoes = metadata.quoteCache.filter { !$0.key.hasPrefix(Self.prefixoDeContrato) }
                cotacoesPorContrato = Dictionary(uniqueKeysWithValues: metadata.quoteCache.compactMap { chave, cotacao in
                    chave.hasPrefix(Self.prefixoDeContrato) ? (String(chave.dropFirst(Self.prefixoDeContrato.count)), cotacao) : nil
                })
                atualizado = metadata.cachedAt
                falhas = []
            }
        }
        return retrato(wallet, metadata)
    }

    /// `forcar`: o dono pediu (puxar, tentar de novo). Sem ele, so le se a ultima leitura tiver
    /// mais de 1 minuto, e pula a rede vazia lida ha pouco.
    func atualizar(forcar: Bool) async {
        _ = mostrar()
        guard let wallet = Sessao.shared.metadata.selectedWallet else { return }
        let seguir = trava.withLock { () -> Bool in
            if !forcar, lidas.contains(wallet.id), let ultima = ultimaLeitura[wallet.id],
               Date().timeIntervalSince(ultima) < Self.intervaloAutomatico {
                return false
            }
            guard !carregando else { pendente = true; return false }
            carregando = true
            return true
        }
        guard seguir else { return }
        emitir()
        await ler(wallet, forcar: forcar)
        while trava.withLock({ pendente && carteiraID == wallet.id }) {
            trava.withLock { pendente = false }
            await ler(wallet, forcar: true)
        }
        trava.withLock {
            pendente = false
            carregando = false
        }
        emitir()
    }

    static func redeVaziaConhecida(_ saldo: ChainBalance?) -> Bool {
        guard let saldo else { return false }
        return saldo.holdings.allSatisfy { $0.amount.isZero } && (saldo.unlisted ?? []).isEmpty
    }

    private func ler(_ wallet: WalletMeta, forcar: Bool) async {
        let metadata = Sessao.shared.metadata
        let desligadas = metadata.settings.disabledChainIDs
        let agora = Date()
        let conhecidos = trava.withLock { saldos }
        let alvos: [(Chain, [String])] = wallet.accounts.compactMap { conta -> (Chain, [String])? in
            guard let rede = Chain.find(conta.chainID), !desligadas.contains(rede.id) else { return nil }
            if !forcar, Self.redeVaziaConhecida(conhecidos[rede.id]), let lida = conhecidos[rede.id]?.fetchedAt,
               agora.timeIntervalSince(lida) < Self.intervaloRedeVazia {
                return nil
            }
            return (rede, Self.enderecos(conta, rede: rede, uso: wallet.utxoUsage[rede.id]))
        }
        .sorted { (conhecidos[$0.0.id]?.holdings.isEmpty == false ? 1 : 0) > (conhecidos[$1.0.id]?.holdings.isEmpty == false ? 1 : 0) }
        defer { trava.withLock { ultimaLeitura[wallet.id] = .now } }

        let custom = metadata.customTokens
        let ids = Set(Chain.all.map(\.coingeckoID) + TokenRegistry.tokens.compactMap(\.coingeckoID))
        let moeda = metadata.settings.currency
        async let cotadas = try? MarketService.shared.quotes(ids: Array(ids), currency: moeda)
        async let referencias = Self.precosDoBitcoin(exceto: moeda)

        var novos: [String: ChainBalance] = [:]
        var falharam: [Chain] = []
        func lerGrupo(_ grupo: [(Chain, [String])]) async {
            await withTaskGroup(of: (Chain, ChainBalance?).self) { tarefas in
                var fila = grupo[...]
                func proxima() {
                    guard let (rede, enderecos) = fila.popFirst() else { return }
                    tarefas.addTask { (rede, try? await BalanceService.shared.balance(chain: rede, addresses: enderecos, custom: custom)) }
                }
                for _ in 0..<Self.leiturasParalelas { proxima() }
                for await (rede, saldo) in tarefas {
                    proxima()
                    if let saldo {
                        novos[rede.id] = saldo
                        let mesma = trava.withLock { () -> Bool in
                            guard carteiraID == wallet.id else { return false }
                            saldos[rede.id] = saldo
                            return true
                        }
                        if mesma { emitir() }
                    } else {
                        falharam.append(rede)
                    }
                }
            }
        }
        await lerGrupo(alvos)
        // Mais duas tentativas, 2 s e 6 s depois: provedor gratis corta rajada.
        for espera in [2, 6] where !falharam.isEmpty {
            try? await Task.sleep(nanoseconds: UInt64(espera) * 1_000_000_000)
            let denovo = alvos.filter { alvo in falharam.contains { $0.id == alvo.0.id } }
            falharam = []
            await lerGrupo(denovo)
        }

        let novasCotacoes = await cotadas
        var precos = await referencias
        if let btc = novasCotacoes?["bitcoin"]?.price { precos[moeda] = btc }
        let mesmaMoeda = Sessao.shared.metadata.settings.currency == moeda
        let continua = trava.withLock { () -> Bool in
            precosDoBitcoin.merge(precos) { $1 }
            semRede = novos.isEmpty && novasCotacoes == nil && !alvos.isEmpty
            if !novos.isEmpty { lidas.insert(wallet.id) }
            guard carteiraID == wallet.id else { return false }
            for (id, saldo) in novos { saldos[id] = saldo }
            if let novasCotacoes, !novasCotacoes.isEmpty, mesmaMoeda { cotacoes = novasCotacoes }
            falhas = falharam.filter { !Self.redeVaziaConhecida(saldos[$0.id]) }.sorted { $0.name < $1.name }
            if !novos.isEmpty { atualizado = .now }
            return true
        }
        guard continua else { return }
        emitir()

        // Preco por contrato: moedas custom e outros tokens sem suspeita. Nunca pelo simbolo.
        let comPrecoPorContrato = Self.precificadosPorContrato(trava.withLock { saldos })
        if !comPrecoPorContrato.isEmpty {
            let achados = await MarketService.shared.tokenQuotes(comPrecoPorContrato, currency: moeda)
            let aindaNaMoeda = Sessao.shared.metadata.settings.currency == moeda
            trava.withLock {
                if carteiraID == wallet.id, aindaNaMoeda { cotacoesPorContrato.merge(achados) { $1 } }
            }
            emitir()
        }
        await reconhecer(wallet)
        guarda(wallet, moeda: moeda)
    }

    /// Guarda o que foi lido nos metadados, para a proxima abertura mostrar na hora.
    private func guarda(_ wallet: WalletMeta, moeda: String) {
        let (copia, cotacoesAgora, porContrato, quando) = trava.withLock { (saldos, cotacoes, cotacoesPorContrato, atualizado) }
        try? Sessao.shared.alterar { metadata in
            metadata.balanceCache[wallet.id] = copia
            if metadata.settings.currency == moeda {
                var cache = cotacoesAgora
                for (id, cotacao) in porContrato { cache[Self.prefixoDeContrato + id] = cotacao }
                metadata.quoteCache = cache
            }
            metadata.cachedAt = quando
        }
    }

    /// Pergunta ao CoinGecko pelos tokens fora da lista, sem suspeita, ainda sem resposta de menos
    /// de 7 dias: no maximo 8 por leitura, um a cada 1,5 s.
    private func reconhecer(_ wallet: WalletMeta) async {
        let agora = Date.now
        let metadata = Sessao.shared.metadata
        var conhecidos = metadata.recognizedTokens ?? [:]
        var sem = metadata.unrecognizedChecks ?? [:]
        let custom = Set(metadata.customTokens.map(\.id))
        let ativos = trava.withLock { Chain.all.compactMap { saldos[$0.id]?.unlisted }.flatMap { $0 } }
            .filter { !$0.isSuspicious && !custom.contains($0.asset.id) }.map(\.asset)
        let pendentes = ativos.filter { ativo in
            if let identidade = conhecidos[ativo.id] { return !TokenRecognitionRules.isValid(identidade, for: ativo, now: agora) }
            if let conferido = sem[ativo.id] { return agora.timeIntervalSince(conferido) >= TokenRecognitionRules.lifetime }
            return true
        }
        guard !pendentes.isEmpty else { return }
        var mudou = false
        for (indice, ativo) in pendentes.prefix(8).enumerated() {
            if indice > 0 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            do {
                if let identidade = try await MarketService.shared.tokenIdentity(ativo, now: agora) {
                    conhecidos[ativo.id] = identidade
                    sem[ativo.id] = nil
                } else {
                    conhecidos[ativo.id] = nil
                    sem[ativo.id] = agora
                }
                mudou = true
            } catch {
                continue
            }
        }
        guard mudou else { return }
        try? Sessao.shared.alterar {
            $0.recognizedTokens = conhecidos
            $0.unrecognizedChecks = sem
        }
        emitir()
    }

    static func precificadosPorContrato(_ saldos: [String: ChainBalance]) -> [Asset] {
        var custom: [Asset] = []
        var oficiais: [Asset] = []
        var outros: [Asset] = []
        for rede in Chain.all {
            guard let saldo = saldos[rede.id] else { continue }
            custom += saldo.holdings.filter { $0.asset.isCustom && !$0.amount.isZero }.map(\.asset)
            for item in saldo.unlisted ?? [] where !item.isSuspicious {
                if TokenSafety.officialOutsideList.contains(item.asset.id) { oficiais.append(item.asset) } else { outros.append(item.asset) }
            }
        }
        return custom + oficiais + outros
    }

    private static func precosDoBitcoin(exceto base: String) async -> [String: Double] {
        var saida: [String: Double] = [:]
        for moeda in ["brl", "usd", "eur"] where moeda != base {
            if let preco = try? await MarketService.shared.quotes(ids: ["bitcoin"], currency: moeda)["bitcoin"]?.price {
                saida[moeda] = preco
            }
        }
        return saida
    }

    /// Enderecos a consultar: um por rede, e nas UTXO os de recebimento e troco ja usados mais o
    /// proximo, derivados da xpub (a seed nao e tocada).
    static func enderecos(_ conta: DerivedAccount, rede: Chain, uso: UTXOUsage?) -> [String] {
        guard rede.family == .utxo, let xpub = conta.accountXPub else { return [conta.address] }
        let uso = uso ?? UTXOUsage()
        var saida: [String] = []
        for (ramo, usados) in [(UInt32(0), uso.receiveUsed), (UInt32(1), uso.changeUsed)] {
            for indice in 0...UInt32(max(0, usados)) {
                if let chave = try? xpub.derive([ramo, indice]), let endereco = try? Address.from(publicKey: chave.publicKey, chain: rede) {
                    saida.append(endereco)
                }
            }
        }
        return saida.isEmpty ? [conta.address] : saida
    }

    // MARK: O retrato

    func retratoAtual() -> Retrato {
        let metadata = Sessao.shared.metadata
        return retrato(metadata.selectedWallet, metadata)
    }

    private func retrato(_ wallet: WalletMeta?, _ metadata: Metadata) -> Retrato {
        trava.withLock {
            guard let wallet, carteiraID == wallet.id else {
                return Retrato(carteira: nil, linhas: [], todasAsLinhas: [], outros: [], suspeitos: [], total: 0, variacao24h: 0, variacao24hPct: 0,
                               carregando: carregando, falhas: [], atualizado: nil, semRede: semRede, tokensDesconhecidos: 0,
                               moeda: metadata.settings.currency, bitcoin: precosDoBitcoin)
            }
            return montar(wallet, metadata)
        }
    }

    /// A mesma conta do `Portfolio.recompute` do iOS. Chamar com a trava.
    private func montar(_ wallet: WalletMeta, _ metadata: Metadata) -> Retrato {
        var agrupados: [String: [Holding]] = [:]
        var ordem: [String] = []
        var desconhecidos = 0
        var foraDaLista: [UnlistedHolding] = []
        let custom = Set(metadata.customTokens.map(\.id))
        let reconhecidos = metadata.recognizedTokens ?? [:]
        for rede in Chain.all {
            guard let saldo = saldos[rede.id] else { continue }
            if let lista = saldo.unlisted { foraDaLista += lista } else { desconhecidos += saldo.unknownTokenCount }
            for item in saldo.holdings where !item.amount.isZero {
                if item.asset.isCustom, !custom.contains(item.asset.id) { continue }
                let chave = item.asset.coingeckoID ?? item.asset.id
                if agrupados[chave] == nil { ordem.append(chave) }
                agrupados[chave, default: []].append(item)
            }
        }
        let conferidas = ordem.compactMap { chave -> Linha? in
            guard let itens = agrupados[chave], let primeiro = itens.first?.asset else { return nil }
            let cotacao = primeiro.coingeckoID.map { cotacoes[$0] } ?? cotacoesPorContrato[primeiro.id]
            return linha(id: chave, simbolo: primeiro.symbol, nome: primeiro.name, coingecko: primeiro.coingeckoID,
                         estavel: primeiro.isStablecoin, itens: itens, cotacao: cotacao, reconhecido: false)
        }
        let tokens = foraDaLista.map { item -> (UnlistedHolding, Quote?) in (item, item.isSuspicious ? nil : cotacoesPorContrato[item.asset.id]) }
        var grupos: [String: (TokenIdentity, [(UnlistedHolding, Quote?)])] = [:]
        var ordemReconhecidos: [String] = []
        var simples: [(UnlistedHolding, Quote?)] = []
        for token in tokens where !token.0.isSuspicious && !custom.contains(token.0.asset.id) {
            if let identidade = reconhecidos[token.0.asset.id], TokenRecognitionRules.isValid(identidade, for: token.0.asset, now: identidade.checkedAt) {
                let chave = "rec:" + identidade.coingeckoID
                if grupos[chave] == nil {
                    ordemReconhecidos.append(chave)
                    grupos[chave] = (identidade, [])
                }
                grupos[chave]?.1.append(token)
            } else {
                simples.append(token)
            }
        }
        let reconhecidas = ordemReconhecidos.compactMap { chave -> Linha? in
            guard let (identidade, itens) = grupos[chave] else { return nil }
            let cotada = itens.first { $0.1 != nil }?.1
            return linha(id: chave, simbolo: identidade.symbol, nome: identidade.name, coingecko: nil, estavel: false,
                         itens: itens.map { Holding(asset: $0.0.asset, amount: $0.0.amount) }, cotacao: cotada, reconhecido: true)
        }
        let todas = (conferidas + reconhecidas).sorted { ($0.valor ?? 0) > ($1.valor ?? 0) }
        let linhas = todas.filter { !wallet.hiddenAssetIDs.contains($0.id) }
        let todosOsOutros = simples.map { outro($0.0, $0.1) }
            .sorted { (($0.valor ?? 0), $1.simbolo.lowercased()) > (($1.valor ?? 0), $0.simbolo.lowercased()) }
        let outros = todosOsOutros.filter { !wallet.hiddenAssetIDs.contains($0.id) }
        let suspeitos = tokens.filter { $0.0.isSuspicious }.map { outro($0.0, nil) }

        let precificados = linhas.compactMap(\.valor) + outros.compactMap(\.valor)
        let total = precificados.reduce(0, +)
        let movimentos = linhas.map { ($0.valor, $0.variacao24h) } + outros.map { ($0.valor, cotacoesPorContrato[$0.id]?.change24h) }
        let variacao = movimentos.reduce(0.0) { soma, item in
            guard let valor = item.0, let mudanca = item.1 else { return soma }
            return soma + valor - valor / (1 + mudanca / 100)
        }
        let antes = total - variacao
        return Retrato(
            carteira: wallet.id.uuidString, linhas: linhas, todasAsLinhas: todas, outros: outros, suspeitos: suspeitos, total: total,
            variacao24h: variacao, variacao24hPct: antes > 0 ? variacao / antes * 100 : 0, carregando: carregando,
            falhas: falhas.map(\.name), atualizado: atualizado, semRede: semRede, tokensDesconhecidos: desconhecidos,
            moeda: metadata.settings.currency, bitcoin: precosDoBitcoin
        )
    }

    private func linha(id: String, simbolo: String, nome: String, coingecko: String?, estavel: Bool, itens: [Holding],
                       cotacao: Quote?, reconhecido: Bool) -> Linha {
        let casas = itens.map(\.asset.decimals).max() ?? 0
        let total = itens.reduce(BigUInt()) { $0 + $1.amount * BigUInt.power(of: 10, casas - $1.asset.decimals) }
        let valor = cotacao.map { cotacao in itens.reduce(0.0) { $0 + Self.decimal($1.amount, casas: $1.asset.decimals) * cotacao.price } }
        let primeiro = itens.first?.asset
        return Linha(
            id: id, simbolo: simbolo, nome: nome, coingecko: coingecko, estavel: estavel,
            posicoes: itens.map { item in
                let disponivel = item.asset.chain.flatMap { saldos[$0.id] }.map { $0.available(item) } ?? item.amount
                return Posicao(rede: item.asset.chainID, redeNome: item.asset.chain?.name ?? item.asset.chainID, ativo: item.asset.id,
                               quantidade: item.amount.decimalString, disponivel: disponivel.decimalString, casas: item.asset.decimals,
                               contrato: Self.contrato(item.asset))
            },
            preco: cotacao?.price, variacao24h: cotacao?.change24h, valor: valor, casas: casas, total: total.decimalString,
            reconhecido: reconhecido, custom: primeiro?.isCustom ?? false, conferido: itens.allSatisfy { $0.asset.isVerified }
        )
    }

    private func outro(_ item: UnlistedHolding, _ cotacao: Quote?) -> Outro {
        Outro(
            id: item.asset.id, simbolo: item.asset.symbol, nome: item.asset.name, rede: item.asset.chainID,
            quantidade: item.amount.decimalString, casas: item.asset.decimals, preco: cotacao?.price,
            valor: cotacao.map { Self.decimal(item.amount, casas: item.asset.decimals) * $0.price }, suspeito: item.isSuspicious,
            logo: item.logo?.absoluteString
        )
    }

    static func contrato(_ ativo: Asset) -> String? {
        switch ativo.kind {
        case .native: return nil
        case .token(let contrato): return contrato
        case .issued(let codigo, let emissor): return "\(codigo):\(emissor)"
        }
    }

    static func decimal(_ quantidade: BigUInt, casas: Int) -> Double {
        Double(quantidade.decimalString).map { $0 / pow(10, Double(casas)) } ?? 0
    }

    private func emitir() {
        guard let json = try? Nucleo.json(retratoAtual()) else { return }
        Eventos.emitir("saldos", json)
    }
}
