import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation

/// Gerenciar ativos (o `ManageAssetsView` do iOS) e as moedas custom (o `AddCustomTokenView`):
/// esconder um ativo da Carteira e do total, ler uma moeda na propria rede antes de guardar,
/// com dois provedores concordando nas casas, e remover. Os textos que dependem da rede vao como
/// codigo, e a tela escreve (`problema`); os da leitura ja vem escritos (`mensagem`).
enum Ativos {
    /// Uma moeda lida na rede, como a previa mostra.
    struct Token: Encodable {
        let id: String
        let simbolo: String
        let nome: String
        let rede: String
        let redeNome: String
        let casas: Int
        let fontes: [String]
        let notaDasCasas: String?
        /// Os sinais de golpe (`TokenSafety.Reason`), pelo nome: a tela tem o texto de cada um.
        let motivos: [String]
        let notas: [String]
        let envioIndisponivel: String?
        /// O contrato, o mint ou o mestre do jetton; na XRPL e na Stellar, o emissor.
        let referencia: String?
        let codigo: String?
        /// O nome do campo na rede ("Contrato do token", "Mint do token") e o explorador que mostra o token.
        let rotulo: String
        let explorador: String?
        let exploradorNome: String?
    }

    struct Opcao: Encodable {
        let rede: String
        let redeNome: String
        let token: Token
    }

    /// O resultado de encontrar ou ler: a moeda, as redes para escolher, ou o problema.
    struct Resposta: Encodable {
        var token: Token?
        var opcoes: [Opcao] = []
        /// "vazio", "enderecoInvalido", "codigoInvalido", "redeSemCustom", "naoToken", "listada",
        /// "jaNaCarteira", "naoAchado", "emissor".
        var problema: String?
        var redeNome: String?
        var simboloListado: String?
        var mensagem: String?
    }

    struct Custom: Encodable {
        let id: String
        let simbolo: String
        let rede: String
        let redeNome: String
        let referencia: String
    }

    struct Lista: Encodable {
        let custom: [Custom]
        let ocultos: [String]
    }

    /// As moedas lidas esperando o dono conferir: so estas podem ser adicionadas.
    private static let trava = NSLock()
    nonisolated(unsafe) private static var lidas: [String: Asset] = [:]

    static func chamar(_ metodo: String, _ pedido: JSONValue) throws -> Data {
        switch metodo {
        case "ativos.lista":
            return try Nucleo.json(lista())
        case "ativos.visivel":
            try mostrar(pedido["id"]?.stringValue ?? "", visivel: pedido["visivel"]?.boolValue ?? true)
            return try Nucleo.json(Saldos.shared.retratoAtual())
        case "tokens.encontrar":
            let texto = pedido["texto"]?.stringValue ?? ""
            return try Nucleo.json(try esperar { await encontrar(texto) })
        case "tokens.ler":
            let rede = pedido["rede"]?.stringValue
            let endereco = pedido["endereco"]?.stringValue ?? ""
            let codigo = pedido["codigo"]?.stringValue ?? ""
            let emissor = pedido["emissor"]?.stringValue ?? ""
            return try Nucleo.json(try esperar { await ler(rede: rede, endereco: endereco, codigo: codigo, emissor: emissor) })
        case "tokens.adicionar":
            return try Nucleo.json(["simbolo": try adicionar(pedido["id"]?.stringValue ?? "")])
        case "tokens.remover":
            try remover(pedido["id"]?.stringValue ?? "")
            return try Nucleo.json(lista())
        default:
            throw Nucleo.Falha(erro: "metodo desconhecido: \(metodo)")
        }
    }

    // MARK: Gerenciar

    static func lista() -> Lista {
        let metadata = Sessao.shared.metadata
        let custom = metadata.customTokens.compactMap { asset -> Custom? in
            guard let referencia = CustomToken.reference(asset.kind) else { return nil }
            return Custom(id: asset.id, simbolo: asset.symbol, rede: asset.chainID, redeNome: asset.chain?.name ?? asset.chainID, referencia: referencia)
        }
        return Lista(custom: custom, ocultos: Array(metadata.selectedWallet?.hiddenAssetIDs ?? []).sorted())
    }

    /// Esconder tira da Carteira e do total; o saldo continua na rede.
    static func mostrar(_ id: String, visivel: Bool) throws {
        guard !id.isEmpty else { return }
        try Sessao.shared.alterar { metadata in
            guard let indice = metadata.wallets.firstIndex(where: { $0.id == metadata.selectedWalletID }) else { return }
            if visivel { metadata.wallets[indice].hiddenAssetIDs.remove(id) } else { metadata.wallets[indice].hiddenAssetIDs.insert(id) }
        }
        Saldos.shared.reemitir()
    }

    static func remover(_ id: String) throws {
        try Sessao.shared.alterar { metadata in
            metadata.customAssets = metadata.customTokens.filter { $0.id != id }
        }
        Saldos.shared.reemitir()
        Task.detached { await Saldos.shared.atualizar(forcar: true) }
    }

    // MARK: Adicionar

    /// As redes com moeda custom em que esta carteira tem conta (todas, se nenhuma).
    private static func redes() -> [Chain] {
        let contas = Set(Sessao.shared.metadata.selectedWallet?.accounts.map(\.chainID) ?? [])
        let todas = Chain.all.filter(CustomToken.supports)
        let minhas = todas.filter { contas.contains($0.id) }
        return minhas.isEmpty ? todas : minhas
    }

    private static func jaNaCarteira(_ chain: Chain, _ kind: Asset.Kind) -> Bool {
        Sessao.shared.metadata.customTokens.contains { $0.chainID == chain.id && $0.kind == kind }
    }

    private static func problema(_ problema: CustomToken.Problem, _ chain: Chain) -> Resposta {
        var resposta = Resposta(redeNome: chain.name)
        switch problema {
        case .unsupportedChain: resposta.problema = "redeSemCustom"
        case .empty: resposta.problema = "vazio"
        case .invalidAddress: resposta.problema = "enderecoInvalido"
        case .invalidCode: resposta.problema = "codigoInvalido"
        case .alreadyListed(let listada):
            resposta.problema = "listada"
            resposta.simboloListado = listada.symbol
        case .notAToken: resposta.problema = "naoToken"
        }
        return resposta
    }

    private static func guardar(_ facts: TokenFacts) -> Token {
        let asset = facts.asset
        trava.withLock { lidas[asset.id] = asset }
        var codigo: String?
        if case .issued(let code, _) = asset.kind { codigo = code }
        return Token(
            id: asset.id, simbolo: asset.symbol, nome: asset.name, rede: asset.chainID, redeNome: asset.chain?.name ?? asset.chainID,
            casas: asset.decimals, fontes: facts.sources, notaDasCasas: facts.decimalsNote, motivos: facts.reasons.map(\.rawValue),
            notas: facts.notes, envioIndisponivel: asset.chain.flatMap(CustomToken.sendUnavailableReason),
            referencia: CustomToken.reference(asset.kind), codigo: codigo,
            rotulo: asset.chain.map(CustomToken.addressLabel) ?? "",
            explorador: asset.chain.flatMap { rede in
                guard CustomToken.explorerShowsToken(rede), let referencia = CustomToken.reference(asset.kind) else { return nil }
                return rede.explorerURL(address: referencia)?.absoluteString
            },
            exploradorNome: asset.chain?.explorerName
        )
    }

    /// A rede pelo contrato: as redes da carteira em que o formato vale, lidas ao mesmo tempo; fica
    /// a que tem o token. Mais de uma (o mesmo endereco em varias EVM), o dono escolhe.
    static func encontrar(_ bruto: String) async -> Resposta {
        let texto = bruto.trimmingCharacters(in: .whitespacesAndNewlines)
        var listada: Resposta?
        var candidatos: [(Chain, Asset.Kind)] = []
        for rede in redes() where !CustomToken.usesIssuer(rede) {
            do {
                candidatos.append((rede, try CustomToken.kind(chain: rede, address: texto)))
            } catch let falha as CustomToken.Problem {
                if case .alreadyListed = falha { listada = problema(falha, rede) }
            } catch {}
        }
        guard !candidatos.isEmpty else { return listada ?? Resposta(problema: "enderecoNenhumaRede") }
        let novos = candidatos.filter { !jaNaCarteira($0.0, $0.1) }
        guard !novos.isEmpty else { return Resposta(problema: "jaNaCarteira") }
        // Uma rede que nao respondeu nao e uma rede sem o token: sem nenhum achado, o aviso diz
        // para tentar de novo em vez de dizer que o contrato nao existe.
        var achados: [(Chain, TokenFacts)] = []
        var semResposta = false
        await withTaskGroup(of: (Chain, Result<TokenFacts, TokenInspectionError>).self) { grupo in
            for (rede, kind) in novos {
                grupo.addTask {
                    do {
                        return (rede, .success(try await TokenInspector.shared.inspect(chain: rede, kind: kind)))
                    } catch {
                        return (rede, .failure(error as? TokenInspectionError ?? .notEnoughSources))
                    }
                }
            }
            for await (rede, resultado) in grupo {
                switch resultado {
                case .success(let facts): achados.append((rede, facts))
                case .failure(.notAToken), .failure(.unsupported): break
                case .failure: semResposta = true
                }
            }
        }
        let ordem = Dictionary(Chain.all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { primeiro, _ in primeiro })
        achados.sort { (ordem[$0.0.id] ?? .max) < (ordem[$1.0.id] ?? .max) }
        if achados.count == 1, let unico = achados.first { return Resposta(token: guardar(unico.1)) }
        if achados.count > 1 {
            return Resposta(opcoes: achados.map { Opcao(rede: $0.0.id, redeNome: $0.0.name, token: guardar($0.1)) })
        }
        if let listada { return listada }
        if semResposta { return Resposta(mensagem: TokenInspectionError.notEnoughSources.errorDescription) }
        return Resposta(problema: "naoAchado")
    }

    /// Com a rede escolhida, ou a moeda emitida (a rede sai do emissor: r... e XRP Ledger, G... e Stellar).
    static func ler(rede id: String?, endereco: String, codigo: String, emissor: String) async -> Resposta {
        var alvo = id.flatMap(Chain.find)
        if alvo == nil {
            let limpo = emissor.trimmingCharacters(in: .whitespacesAndNewlines)
            alvo = limpo.hasPrefix("r") ? Chain.find("xrpl") : (limpo.hasPrefix("G") ? Chain.find("stellar") : nil)
            guard alvo != nil else { return Resposta(problema: "emissor") }
        }
        guard let rede = alvo else { return Resposta(problema: "emissor") }
        let kind: Asset.Kind
        do {
            kind = CustomToken.usesIssuer(rede)
                ? try CustomToken.kind(chain: rede, code: codigo, issuer: emissor)
                : try CustomToken.kind(chain: rede, address: endereco)
        } catch let falha as CustomToken.Problem {
            return problema(falha, rede)
        } catch {
            return Resposta(problema: "enderecoInvalido", redeNome: rede.name)
        }
        if jaNaCarteira(rede, kind) { return Resposta(problema: "jaNaCarteira") }
        do {
            return Resposta(token: guardar(try await TokenInspector.shared.inspect(chain: rede, kind: kind)))
        } catch {
            return Resposta(mensagem: (error as? LocalizedError)?.errorDescription ?? Textos.t("Não foi possível ler a moeda na rede agora."))
        }
    }

    /// Guarda a moeda que o dono conferiu na previa, e le a rede dela de novo.
    static func adicionar(_ id: String) throws -> String {
        guard let asset = trava.withLock({ lidas[id] }) else { throw Nucleo.Falha(erro: "tokens.naoLida") }
        try Sessao.shared.alterar { metadata in
            var lista = metadata.customTokens
            guard !lista.contains(where: { $0.id == asset.id }) else { return }
            lista.append(asset)
            metadata.customAssets = lista
        }
        trava.withLock { lidas = [:] }
        Saldos.shared.reemitir()
        Task.detached { await Saldos.shared.atualizar(forcar: true) }
        return asset.symbol
    }
}
