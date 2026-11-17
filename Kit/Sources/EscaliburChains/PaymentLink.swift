import EscaliburCore
import Foundation

/// O endereco de um QR ou de um link de pagamento (BIP-21, EIP-681, "xrpl:",
/// "solana:", "ton://transfer/", SEP-7 da Stellar), e a tag ou o memo quando o link
/// traz um. Valor e rotulo do link sao ignorados: o dono digita.
///
/// O EIP-681 passa pela leitura estrita do `EIP681Request`: num pedido de token, o
/// endereco logo depois de "ethereum:" e o contrato, e quem recebe vem em `address=`.
/// Cortar o texto no "/" mandava o token para o proprio contrato (auditoria 2, B5).
///
/// A tag e o memo antes eram descartados sem aviso: o QR de deposito de uma corretora no
/// XRP Ledger virava so o endereco, e o deposito sem tag nao era creditado (auditoria 4,
/// B5). Agora vao para o campo, mostrados para o dono conferir.
///
/// O esquema diz a rede, e nao so no EIP-681: "litecoin:3J98..." ou "bitcoincash:1Boat..."
/// eram lidos como um endereco qualquer, e a tela de Bitcoin aceitava, porque a Litecoin
/// antiga e o Bitcoin Cash usam enderecos com a forma dos do Bitcoin (auditoria 4, B-4).
/// Agora a leitura diz a rede e a familia do esquema, e esquema de rede que o app nao tem
/// (ou que ele nao conhece) e recusado.
public enum PaymentLink {
    public struct Reading: Equatable, Sendable {
        public let address: String
        /// A rede que o link pede, quando ele diz: o `@chain_id` do EIP-681, ou o esquema
        /// de uma rede de esquema proprio ("litecoin:" e a Litecoin, "ripple:" o XRP
        /// Ledger). Quem le recusa o link cuja rede nao e a da tela. Nil sem esquema, e no
        /// "ethereum:" sem `@chain_id`, que serve a qualquer rede EVM.
        public let chainID: String?
        /// A familia que o esquema indica: `.evm` no "ethereum:", com ou sem `@chain_id`, e
        /// a da rede nos outros. Nil sem esquema.
        public let family: ChainFamily?
        /// A tag de destino ou o memo que o link traz: `dt` do XRP Ledger, `text` da TON,
        /// `memo` do SEP-7. Nil quando nao traz.
        public let tag: String?
        /// A moeda que o link pede, quando nao e a da rede (rodada 1 da auditoria 8): a tela compara com a dela
        /// (`PaymentLink.matches`) e recusa a diferente, em vez de pagar outra moeda ao endereco que pediu USDC.
        public let asset: RequestedAsset?
        /// O prazo do pedido (o `exp` da TON, em segundos Unix): a tela confere de novo na hora de assinar, porque o link
        /// lido valido pode vencer antes do envio (rodada 3 da auditoria 8).
        public let expiresAt: UInt64?

        init(address: String, chainID: String?, family: ChainFamily?, tag: String? = nil, asset: RequestedAsset? = nil, expiresAt: UInt64? = nil) {
            self.address = address
            self.chainID = chainID
            self.family = family
            self.tag = tag
            self.asset = asset
            self.expiresAt = expiresAt
        }

        init(address: String, chain: Chain, tag: String? = nil, asset: RequestedAsset? = nil, expiresAt: UInt64? = nil) {
            self.init(address: address, chainID: chain.id, family: chain.family, tag: tag, asset: asset, expiresAt: expiresAt)
        }
    }

    /// O prazo vencido de um pedido lido: na hora de assinar, a tela recusa (rodada 3 da auditoria 8).
    public static func expired(_ expiresAt: UInt64?, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return UInt64(max(0, now.timeIntervalSince1970)) > expiresAt
    }

    /// A moeda pedida: o contrato do EIP-681, o mint do Solana Pay, o mestre do jetton da TON, ou o codigo e o emissor da
    /// Stellar e do XRP Ledger.
    public enum RequestedAsset: Equatable, Sendable {
        case token(String)
        case issued(code: String, issuer: String)
    }

    /// A moeda da tela e a que o link pede. Sem moeda pedida, qualquer uma.
    public static func matches(_ requested: RequestedAsset?, asset: Asset) -> Bool {
        guard let requested else { return true }
        switch (requested, asset.kind) {
        case (.token(let wanted), .token(let contract)):
            switch asset.chain?.family {
            case .evm?: return wanted.lowercased() == contract.lowercased()
            case .ton?:
                guard case .success(let a) = TONAddress.parse(wanted), case .success(let b) = TONAddress.parse(contract) else { return false }
                return a.address == b.address
            default: return wanted == contract
            }
        case (.issued(let code, let issuer), .issued(let assetCode, let assetIssuer)):
            // O codigo como a rede o guarda: na Stellar e no XRP Ledger maiuscula e minuscula sao moedas diferentes, e no XRP
            // Ledger o codigo de mais de tres letras e guardado em hexadecimal (rodada 2 da auditoria 8).
            guard issuer == assetIssuer else { return false }
            if asset.chain?.family == .xrpl { return xrplCurrency(code) == xrplCurrency(assetCode) }
            return code == assetCode
        default:
            return false
        }
    }

    /// O codigo da moeda no XRP Ledger como o ledger compara: os de tres caracteres como estao, e o resto nos 40 hexadecimais
    /// (o `currency=RLUSD` do link e o RLUSD guardado em hex sao a mesma moeda).
    static func xrplCurrency(_ code: String) -> String {
        if code.count == 40, code.allSatisfy(\.isHexDigit) { return code.uppercased() }
        let bytes = Array(code.utf8)
        guard code.count != 3, bytes.count <= 20 else { return code }
        return (bytes + [UInt8](repeating: 0, count: 20 - bytes.count)).map { String(format: "%02X", $0) }.joined()
    }

    public enum Problem: Error, Equatable, Sendable {
        case tooLong
        /// Pedido `ethereum:` que a leitura estrita recusou (ENS, funcao desconhecida,
        /// rede fora da lista, parametro repetido).
        case invalidEthereumRequest(EIP681Request.Problem)
        /// O codigo traz palavras de uma senha de carteira (ou um SeedQR), nao um
        /// endereco: nunca vai para o campo do destino (auditoria 4, C7-13).
        case containsPhrase
        /// O codigo traz uma chave privada (o WIF de uma carteira de papel, uma semente da Stellar), nao um endereco
        /// (revisao dos 3 agentes, 09/11/2026).
        case containsPrivateKey
        /// Pedido da Stellar que nao e de pagamento (`tx`), ou sem destino.
        case unsupportedStellarRequest
        /// Memo que o app nao envia (hash, retorno), ou memo de texto so com numeros, que o
        /// app enviaria como memo ID: o dono digita o memo a mao, conferindo.
        case unsupportedMemo
        /// O mesmo parametro duas vezes no trecho que o app le.
        case duplicateParameter(String)
        /// Tag ou memo com caractere invisivel, de controle ou espaco nas pontas, longo
        /// demais, ou com duas tags (X-address do XRP Ledger, que ja traz a sua, e um `dt`).
        case invalidTag
        /// O esquema do link (o valor, em minusculas) e de uma rede em que o app nao envia,
        /// como "bitcoincash", cujos enderecos tem a forma dos do Bitcoin, ou de nenhuma que
        /// ele conheca. O resto do link nunca vira destino da rede da tela (auditoria 4, B-4).
        case unsupportedNetwork(String)
        /// Esquema que o app nao conhece: o resto nunca e lido como endereco da tela.
        case unknownScheme(String)
        /// O link pede o que o app nao envia (o `reference` e o `memo` do Solana Pay, o `bin` e o `init` da TON, um
        /// parametro desconhecido), ou traz algo alem do endereco sem esquema: sair so com o endereco pagava sem o
        /// comerciante ou a corretora ver o pagamento. O nome do parametro, em minusculas (auditoria 8, 14/11/2026).
        case unreadParameter(String)
        /// O pedido da TON com o `exp` ja passado: a cobranca venceu, e o comerciante pode nao creditar o que chegar
        /// (rodada 2 da auditoria 8).
        case expiredRequest
    }

    public static let maxLength = 512
    static let maxTagLength = 64

    /// As redes de esquema proprio. O "ethereum:" (EIP-681), o "web+stellar:" (SEP-7) e o
    /// "ton://transfer/" tem leitura propria; o "ton:" daqui so cobre o "ton://" de outra
    /// acao, que nao traz endereco e continua recusado pela validacao.
    static let schemes: [String: Chain] = [
        "bitcoin": .bitcoin, "litecoin": .litecoin, "dogecoin": .dogecoin,
        "solana": .solana, "xrpl": .xrpl, "ripple": .xrpl, "tron": .tron, "ton": .ton,
        "stellar": .stellar, "cardano": .cardano, "sui": .sui, "aptos": .aptos, "near": .near, "polkadot": .polkadot,
    ]

    /// Redes conhecidas que a Escalibur nao envia, com enderecos que se parecem com os de
    /// uma rede que ela envia (o Bitcoin Cash legado e o do Bitcoin).
    static let unsupported: Set<String> = ["bitcoincash", "bchtest", "ecash", "bitcoinsv", "monero", "zcash", "dash"]

    public static func read(_ text: String) throws -> Reading {
        let reading = try parse(text)
        // O comentario, o memo ou a tag do link com uma frase ou uma chave: ia para a tela e, enviado, ficava publico na rede
        // (revisao dos 3 agentes, 09/11/2026).
        if let tag = reading.tag, PrivateKeyGuard.publicTextHasSecret(tag) {
            let phrase = PrivateKeyGuard.phraseRun(tag) != nil || PrivateKeyGuard.looksLikeSeedNumbers(tag)
            throw phrase ? Problem.containsPhrase : Problem.containsPrivateKey
        }
        return reading
    }

    static func parse(_ text: String) throws -> Reading {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxLength else { throw Problem.tooLong }
        guard !looksLikePhrase(trimmed) else { throw Problem.containsPhrase }
        guard !PrivateKeyGuard.looksLikePrivateKey(trimmed) else { throw Problem.containsPrivateKey }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("ethereum:") {
            let request: EIP681Request
            do { request = try EIP681Request.parse(trimmed) } catch let problem as EIP681Request.Problem {
                throw Problem.invalidEthereumRequest(problem)
            }
            switch request.payment {
            case .native(let recipient, _):
                return Reading(address: recipient.description, chainID: request.chain?.id, family: .evm)
            case .token(let contract, let recipient, _):
                return Reading(address: recipient.description, chainID: request.chain?.id, family: .evm, asset: .token(contract.checksummed))
            }
        }
        if lower.hasPrefix("web+stellar:") { return try stellarRequest(trimmed) }
        if lower.hasPrefix("ton://transfer/") {
            let rest = trimmed.dropFirst("ton://transfer/".count)
            let address = String(rest.prefix { $0 != "?" && $0 != "/" })
            guard rest.dropFirst(address.count).isEmpty || rest.dropFirst(address.count).hasPrefix("?") else {
                throw Problem.unreadParameter("/")
            }
            // O `bin` (a chamada de um contrato) e o `init` saiam calados, e o envio virava uma transferencia simples que
            // o contrato podia guardar sem creditar (auditoria 8, 14/11/2026).
            try checkParameters(trimmed, allowed: Self.ignored(.ton), read: Self.read(.ton), bip21: false)
            let expiresAt = try checkTONExpiry(trimmed)
            return Reading(address: address, chain: .ton, tag: try tag("text", in: trimmed), asset: try parameter("jetton", in: trimmed).map(RequestedAsset.token),
                           expiresAt: expiresAt)
        }
        var body = Substring(trimmed)
        var chain: Chain?
        if let colon = body.firstIndex(of: ":"), colon != body.startIndex, body[..<colon].allSatisfy({ $0.isLetter }) {
            // Esquema que nao e de uma rede do app recusa: ler o resto como endereco da tela
            // e o que mandava "bitcoincash:1Boat..." para o Bitcoin.
            let scheme = body[..<colon].lowercased()
            guard let known = Self.schemes[scheme] else {
                throw Self.unsupported.contains(scheme) ? Problem.unsupportedNetwork(scheme) : Problem.unknownScheme(scheme)
            }
            chain = known
            body = body[body.index(after: colon)...]
        }
        guard let chain else { return try schemeless(String(body)) }
        if body.hasPrefix("pay-") { body = body.dropFirst(4) }
        let address = String(body.prefix { $0 != "?" && $0 != "@" && $0 != "/" })
        // Depois do endereco, so a consulta: um "@" ou um "/" com mais coisa era cortado calado.
        guard body.dropFirst(address.count).isEmpty || body.dropFirst(address.count).hasPrefix("?") else {
            throw Problem.unreadParameter(String(body.dropFirst(address.count).prefix(1)))
        }
        try checkParameters(trimmed, allowed: Self.ignored(chain), read: Self.read(chain), bip21: chain.family == .utxo)
        let found: String?
        var expiresAt: UInt64?
        switch chain.family {
        case .xrpl: found = try tag("dt", in: trimmed)
        case .stellar: found = try stellarMemo(trimmed)
        // O comentario do "ton:" (sem o //transfer/), que o deposito da corretora pede (rodada 1 da auditoria 8).
        case .ton:
            expiresAt = try checkTONExpiry(trimmed)
            found = try tag("text", in: trimmed)
        default: found = nil
        }
        // O X-address ja traz a tag dele: um `dt` junto e uma segunda tag disputando o
        // credito, sem leitura segura.
        if found != nil, address.hasPrefix("X") { throw Problem.invalidTag }
        return Reading(address: address, chain: chain, tag: found, asset: try requestedAsset(trimmed, chain: chain), expiresAt: expiresAt)
    }

    /// O `exp` da TON (segundos Unix), no `ton://transfer/` e no `ton:`: era ignorado, e a cobranca vencida era paga (rodadas
    /// 2 e 3 da auditoria 8).
    @discardableResult
    static func checkTONExpiry(_ text: String) throws -> UInt64? {
        guard let exp = try parameter("exp", in: text) else { return nil }
        guard let deadline = UInt64(exp) else { throw Problem.unreadParameter("exp") }
        if expired(deadline) { throw Problem.expiredRequest }
        return deadline
    }

    /// A moeda pedida pelo esquema da rede: o `spl-token` do Solana Pay, o `currency` e o `issuer` do XRP Ledger (sem o emissor,
    /// ou "XRP", e a da rede). Outro par incompleto recusa.
    static func requestedAsset(_ text: String, chain: Chain) throws -> RequestedAsset? {
        switch chain.family {
        case .solana:
            return try parameter("spl-token", in: text).map(RequestedAsset.token)
        case .ton:
            return try parameter("jetton", in: text).map(RequestedAsset.token)
        case .xrpl:
            let currency = try parameter("currency", in: text), issuer = try parameter("issuer", in: text)
            switch (currency, issuer) {
            case (nil, nil): return nil
            // So "XRP" exato: o ledger diferencia maiuscula, e "xrp" sem emissor nao e a moeda da rede (rodada 3 da auditoria 8).
            case (let code?, nil) where code == "XRP": return nil
            case (let code?, let issuer?): return .issued(code: code, issuer: issuer)
            default: throw Problem.unreadParameter(currency == nil ? "issuer" : "currency")
            }
        default:
            return nil
        }
    }

    /// O codigo sem esquema: o texto inteiro e o endereco, que a tela valida como e. Antes ele era cortado no primeiro
    /// "?", "@" ou "/", e o que vinha depois sumia sem aviso: "rHb9...?dt=12345", a forma que algumas corretoras dao ao
    /// deposito no XRP Ledger, virava so o endereco, e o deposito sem tag nao era creditado. Agora essa forma e lida
    /// (endereco classico e so o `dt`), e qualquer outra consulta recusa (auditoria 8, 14/11/2026).
    static func schemeless(_ body: String) throws -> Reading {
        guard let question = body.firstIndex(of: "?") else { return Reading(address: body, chainID: nil, family: nil) }
        let address = String(body[..<question])
        let names = parameterNames(in: body)
        var classic = false
        if address.hasPrefix("r"), case .success = Address.validate(address, for: .xrpl) { classic = true }
        guard classic, names == ["dt"] else {
            throw Problem.unreadParameter((classic ? names.first { $0 != "dt" } : names.first) ?? "?")
        }
        guard let tag = try tag("dt", in: body), !tag.isEmpty else { throw Problem.invalidTag }
        return Reading(address: address, chain: .xrpl, tag: tag)
    }

    /// Os parametros que o app ignora sem mudar o que o envio faz: o valor e o rotulo (o dono digita o valor, e o ativo e
    /// o da tela, como no EIP-681), por rede. `read`: os que ele le e mostra.
    static func ignored(_ chain: Chain) -> Set<String> {
        switch chain.family {
        case .xrpl: return ["amount", "label", "message"]
        case .solana: return ["amount", "label", "message"]
        case .ton: return ["amount"]
        default: return ["amount", "label", "message"]
        }
    }

    static func read(_ chain: Chain) -> Set<String> {
        switch chain.family {
        case .xrpl: return ["dt", "currency", "issuer"]
        case .stellar: return ["memo", "memo_type"]
        case .solana: return ["spl-token"]
        case .ton: return ["text", "jetton", "exp"]
        default: return []
        }
    }

    /// Recusa o link com parametro fora de `allowed` e `read`. No BIP-21 (`bip21`), como manda o BIP, so o `req-` que o
    /// app nao conhece recusa, e o opcional (lightning, pj) e ignorado: ele nao muda o pagamento na rede.
    static func checkParameters(_ text: String, allowed: Set<String>, read: Set<String>, bip21: Bool) throws {
        for name in parameterNames(in: text) {
            if bip21 {
                if name.hasPrefix("req-") { throw Problem.unreadParameter(name) }
                continue
            }
            guard allowed.contains(name) || read.contains(name) else { throw Problem.unreadParameter(name) }
        }
    }

    /// Os nomes dos parametros da consulta, em minusculas, na ordem do link.
    static func parameterNames(in text: String) -> [String] {
        guard let question = text.firstIndex(of: "?") else { return [] }
        return text[text.index(after: question)...].split(separator: "&", omittingEmptySubsequences: false).map { pair in
            String(pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? "").lowercased()
        }
    }

    /// SEP-7: `web+stellar:pay?destination=G...&memo=...&memo_type=MEMO_ID`. So o destino
    /// e o memo; o memo de texto so com numeros e recusado, porque o app o enviaria como
    /// memo ID (`StellarEngineSupport.memo`).
    static func stellarRequest(_ text: String) throws -> Reading {
        let operation = text.dropFirst("web+stellar:".count).prefix { $0 != "?" }.lowercased()
        guard operation == "pay", let destination = try parameter("destination", in: text), !destination.isEmpty else {
            throw Problem.unsupportedStellarRequest
        }
        // Os do SEP-7 que nao mudam o pagamento na rede; outro, ou a rede de testes, recusa (auditoria 8, 14/11/2026).
        // O `callback` manda a transacao assinada para quem pediu, e nao para a rede: o app nao faz isso, e recusa (rodada 1).
        try checkParameters(text, allowed: ["destination", "amount", "msg", "origin_domain", "signature", "network_passphrase"],
                            read: ["memo", "memo_type", "asset_code", "asset_issuer"], bip21: false)
        if let network = try parameter("network_passphrase", in: text), network != "Public Global Stellar Network ; September 2015" {
            throw Problem.unreadParameter("network_passphrase")
        }
        var asset: RequestedAsset?
        switch (try parameter("asset_code", in: text), try parameter("asset_issuer", in: text)) {
        case (nil, nil): asset = nil
        case (let code?, nil) where code.uppercased() == "XLM" || code.lowercased() == "native": asset = nil
        case (let code?, let issuer?): asset = .issued(code: code, issuer: issuer)
        default: throw Problem.unreadParameter("asset_issuer")
        }
        return Reading(address: destination, chain: .stellar, tag: try stellarMemo(text), asset: asset)
    }

    /// O memo de um link da Stellar (SEP-7 ou "stellar:"), conferido como o app o envia; nil sem memo.
    static func stellarMemo(_ text: String) throws -> String? {
        guard let memo = try tag("memo", in: text), !memo.isEmpty else { return nil }
        switch (try parameter("memo_type", in: text) ?? "MEMO_TEXT").uppercased() {
        case "MEMO_ID":
            // Na forma que o app envia como ID: so digitos, sem zero a esquerda. "007" ou
            // "+5" sairiam como memo de texto.
            let digits = memo.utf8.allSatisfy { (0x30...0x39).contains($0) }
            guard digits, memo == "0" || !memo.hasPrefix("0"), UInt64(memo) != nil else { throw Problem.unsupportedMemo }
        case "MEMO_TEXT":
            guard !memo.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { throw Problem.unsupportedMemo }
        default:
            throw Problem.unsupportedMemo
        }
        return memo
    }

    /// Um parametro da query, decodificado e inteiro (o destino M da Stellar tem 69
    /// caracteres; cortar quebrava o endereco). Repetido e recusado: duas tags no mesmo
    /// link nao tem leitura segura.
    static func parameter(_ name: String, in text: String) throws -> String? {
        guard let question = text.firstIndex(of: "?") else { return nil }
        var found: String?
        for pair in text[text.index(after: question)...].split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.first.map({ $0.lowercased() == name }) == true else { continue }
            guard found == nil else { throw Problem.duplicateParameter(name) }
            let raw = parts.count > 1 ? String(parts[1]) : ""
            found = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? raw
        }
        return found
    }

    /// A tag ou o memo do link, que vai para o campo do dono: ate `maxTagLength`, sem
    /// caractere de controle ou de formato (largura zero, direcao do texto, que fazem
    /// "54321" parecer "12345") e sem espaco nas pontas. Fora disso, recusa: nada e cortado
    /// em silencio (revisao da auditoria 4, B-2 e B-3).
    static func tag(_ name: String, in text: String) throws -> String? {
        guard let value = try parameter(name, in: text) else { return nil }
        guard value.count <= maxTagLength, value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { throw Problem.invalidTag }
        for scalar in value.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned: throw Problem.invalidTag
            default: continue
            }
        }
        return value
    }

    /// Doze palavras ou mais separadas por espaco (nenhum endereco tem espaco), ou o
    /// SeedQR padrao: 48 ou 96 digitos, os indices de 12 ou 24 palavras.
    static func looksLikePhrase(_ text: String) -> Bool {
        if Mnemonic.words(in: text).count >= 12 { return true }
        // O SeedQR com cada grupo de 4 um indice da lista: um boleto de 48 algarismos colado no Para nao e frase.
        return PrivateKeyGuard.looksLikeSeedNumbers(text)
    }
}
