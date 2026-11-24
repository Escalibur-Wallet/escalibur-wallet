import Foundation
import Testing
@testable import EscaliburChains

@Suite("Link de pagamento")
struct PaymentLinkTests {
    let usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    let to = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"

    @Test("QR de token EIP-681: o destino e o address=, nunca o contrato")
    func tokenRequest() throws {
        let reading = try PaymentLink.read("ethereum:\(usdc)@8453/transfer?address=\(to)&uint256=1.5e6")
        #expect(reading.address == to)
        #expect(reading.address != usdc)
        #expect(reading.chainID == "base")
        let noChain = try PaymentLink.read("ethereum:pay-\(usdc)/transfer?address=\(to.lowercased())&uint256=1")
        #expect(noChain.address == to)
        #expect(noChain.chainID == nil)
    }

    @Test("EIP-681 nativo, com rede")
    func nativeRequest() throws {
        let reading = try PaymentLink.read("  ethereum:\(to)@137?value=1e18\n")
        #expect(reading.address == to)
        #expect(reading.chainID == "polygon")
    }

    @Test("EIP-681 recusado nao vira endereco")
    func refused() {
        #expect(throws: PaymentLink.Problem.invalidEthereumRequest(.ensNotSupported)) {
            try PaymentLink.read("ethereum:vitalik.eth?value=1")
        }
        #expect(throws: PaymentLink.Problem.invalidEthereumRequest(.unsupportedFunction("approve"))) {
            try PaymentLink.read("ethereum:\(usdc)/approve?address=\(to)&uint256=1")
        }
        #expect(throws: PaymentLink.Problem.tooLong) {
            try PaymentLink.read("bitcoin:" + String(repeating: "a", count: 600))
        }
    }

    @Test("Tag e memo do link vao junto: XRP Ledger dt, TON text, Stellar SEP-7")
    func tagsAndMemos() throws {
        let xrp = try PaymentLink.read("xrpl:rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh?dt=12345")
        #expect(xrp.address == "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh" && xrp.tag == "12345")
        let ton = try PaymentLink.read("ton://transfer/EQD__________________________________________0vo?amount=1&text=dep%C3%B3sito%2042")
        #expect(ton.address == "EQD__________________________________________0vo" && ton.tag == "depósito 42")
        let g = "GA7QYNF7SOWQ3GLR2BGMZEHXAVIRZA4KVWLTJJFC7MGXUA74P7UJVSGZ"
        let sep7 = try PaymentLink.read("web+stellar:pay?destination=\(g)&amount=10&memo=987&memo_type=MEMO_ID")
        #expect(sep7.address == g && sep7.tag == "987")
        #expect(try PaymentLink.read("web+stellar:pay?destination=\(g)&memo=conta-7").tag == "conta-7")
        #expect(try PaymentLink.read("web+stellar:pay?destination=\(g)").tag == nil)
        // Memo de texto so com numeros iria como memo ID; hash e retorno o app nao envia.
        #expect(throws: PaymentLink.Problem.unsupportedMemo) { try PaymentLink.read("web+stellar:pay?destination=\(g)&memo=987&memo_type=MEMO_TEXT") }
        #expect(throws: PaymentLink.Problem.unsupportedMemo) { try PaymentLink.read("web+stellar:pay?destination=\(g)&memo=abc&memo_type=MEMO_HASH") }
        #expect(throws: PaymentLink.Problem.unsupportedStellarRequest) { try PaymentLink.read("web+stellar:tx?xdr=AAAA") }
        #expect(throws: PaymentLink.Problem.duplicateParameter("dt")) { try PaymentLink.read("xrpl:rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh?dt=1&dt=2") }
        // O destino M (69 caracteres) vai inteiro.
        let m = "MA7QYNF7SOWQ3GLR2BGMZEHXAVIRZA4KVWLTJJFC7MGXUA74P7UJVAAAAAAAAAAAAAJLK"
        #expect(try PaymentLink.read("web+stellar:pay?destination=\(m)").address == m)
        // MEMO_ID so na forma que sai como ID; tag invisivel, com direcao trocada, com espaco
        // nas pontas ou longa demais e recusada, nunca cortada; X-address com dt tambem.
        #expect(throws: PaymentLink.Problem.unsupportedMemo) { try PaymentLink.read("web+stellar:pay?destination=\(g)&memo=007&memo_type=MEMO_ID") }
        #expect(throws: PaymentLink.Problem.unsupportedMemo) { try PaymentLink.read("web+stellar:pay?destination=\(g)&memo=%2B5&memo_type=MEMO_ID") }
        #expect(throws: PaymentLink.Problem.invalidTag) { try PaymentLink.read("xrpl:rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh?dt=12345%E2%80%8B") }
        #expect(throws: PaymentLink.Problem.invalidTag) { try PaymentLink.read("ton://transfer/EQD__________________________________________0vo?text=%E2%80%AE54321") }
        #expect(throws: PaymentLink.Problem.invalidTag) { try PaymentLink.read("ton://transfer/EQD__________________________________________0vo?text=%2042") }
        #expect(throws: PaymentLink.Problem.invalidTag) { try PaymentLink.read("ton://transfer/EQD__________________________________________0vo?text=" + String(repeating: "a", count: 65)) }
        #expect(throws: PaymentLink.Problem.invalidTag) { try PaymentLink.read("xrpl:XVLhHMPHU98es4dbozjVtdWzVrDjtV18pX8yuPT7y4xaEHi?dt=5") }
        // Em outros esquemas, o que nao e tag fica de fora.
        #expect(try PaymentLink.read("bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=0.1&dt=5").tag == nil)
    }

    @Test("Codigo com as palavras de uma carteira, ou SeedQR, nunca vira destino")
    func phrases() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        #expect(throws: PaymentLink.Problem.containsPhrase) { try PaymentLink.read(phrase) }
        #expect(throws: PaymentLink.Problem.containsPhrase) { try PaymentLink.read("  " + phrase.uppercased() + "\n") }
        #expect(throws: PaymentLink.Problem.containsPhrase) { try PaymentLink.read(String(repeating: "0000", count: 12)) }
        #expect(throws: PaymentLink.Problem.containsPhrase) { try PaymentLink.read(String(repeating: "1234", count: 24)) }
        #expect((try? PaymentLink.read("abandon abandon about")) != nil)
    }

    @Test("Regressao B-4: o esquema diz a rede e a familia, com os ids de Chain.swift")
    func schemeNetwork() throws {
        let g = "GA7QYNF7SOWQ3GLR2BGMZEHXAVIRZA4KVWLTJJFC7MGXUA74P7UJVSGZ"
        let cases: [(link: String, address: String, chain: Chain)] = [
            ("bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=0.1", "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", .bitcoin),
            ("BITCOIN:BC1QAR0SRRR7XFKVY5L643LYDNW9RE59GTZZWF5MDQ", "BC1QAR0SRRR7XFKVY5L643LYDNW9RE59GTZZWF5MDQ", .bitcoin),
            ("litecoin:3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy", "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy", .litecoin),
            ("dogecoin:DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L?amount=5", "DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L", .dogecoin),
            ("solana:7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU", "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU", .solana),
            ("xrpl:rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh", "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh", .xrpl),
            ("ripple:rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh?dt=7", "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh", .xrpl),
            ("ton://transfer/EQD__________________________________________0vo", "EQD__________________________________________0vo", .ton),
            ("web+stellar:pay?destination=\(g)", g, .stellar),
            ("tron:TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", .tron),
        ]
        for item in cases {
            let reading = try PaymentLink.read(item.link)
            #expect(reading.address == item.address, "\(item.link)")
            #expect(reading.chainID == item.chain.id && reading.family == item.chain.family, "\(item.link)")
            // O id e o de uma rede de verdade: a tela compara com o `id` da dela.
            #expect(Chain.find(item.chain.id) == item.chain)
        }
        // O P2SH da Litecoin antiga tem a forma de um endereco de Bitcoin: so o esquema diz
        // a rede, e a tela de Bitcoin recusa pelo `chainID`.
        #expect(try PaymentLink.read("litecoin:3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy").chainID != Chain.bitcoin.id)
        // EIP-681: a familia sempre; a rede, so com `@chain_id`.
        let any = try PaymentLink.read("ethereum:\(to)?value=1")
        #expect(any.chainID == nil && any.family == .evm)
        let base = try PaymentLink.read("ethereum:\(to)@8453?value=1")
        #expect(base.chainID == "base" && base.family == .evm)
        // Sem esquema, nem rede nem familia: a tela valida o endereco como e.
        let plain = try PaymentLink.read("rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh")
        #expect(plain.chainID == nil && plain.family == nil)
        let raw = try PaymentLink.read("0:83dfd552e63729b472fcbcc8c45ebcc6691702558b68ec7527e1ba403a0f31a8")
        #expect(raw.chainID == nil && raw.family == nil)
    }

    @Test("Regressao B-4: esquema de rede que o app nao tem, ou desconhecido, e recusado")
    func unsupportedSchemes() throws {
        // O Bitcoin Cash usa enderecos legados iguais aos do Bitcoin: lido como endereco
        // qualquer, ia para a tela de Bitcoin.
        #expect(throws: PaymentLink.Problem.unsupportedNetwork("bitcoincash")) {
            try PaymentLink.read("bitcoincash:1BoatSLRHtKNngkdXEeobR76b53LETtpyT")
        }
        #expect(throws: PaymentLink.Problem.unsupportedNetwork("bitcoincash")) {
            try PaymentLink.read("BitcoinCash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a?amount=1")
        }
        for scheme in ["ecash", "monero", "zcash", "dash"] {
            #expect(throws: PaymentLink.Problem.unsupportedNetwork(scheme)) { try PaymentLink.read("\(scheme):1BoatSLRHtKNngkdXEeobR76b53LETtpyT") }
        }
        for scheme in ["https", "wc", "base"] {
            #expect(throws: PaymentLink.Problem.unknownScheme(scheme)) { try PaymentLink.read("\(scheme):1BoatSLRHtKNngkdXEeobR76b53LETtpyT") }
        }
        // As redes que o app envia continuam lidas pelo esquema delas, com a rede dita.
        let g = "GA7QYNF7SOWQ3GLR2BGMZEHXAVIRZA4KVWLTJJFC7MGXUA74P7UJVSGZ"
        #expect(try PaymentLink.read("stellar:\(g)").chainID == "stellar")
        for (scheme, id) in [("cardano", "cardano"), ("sui", "sui"), ("aptos", "aptos"), ("near", "near"), ("polkadot", "polkadot")] {
            #expect(try PaymentLink.read("\(scheme):abc").chainID == id)
        }
    }

    @Test("Outros esquemas: so o endereco")
    func otherSchemes() throws {
        #expect(try PaymentLink.read("bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=0.1&label=x").address
            == "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
        #expect(try PaymentLink.read("solana:7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU?amount=1").address
            == "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU")
        #expect(try PaymentLink.read("rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh").address == "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh")
    }

    @Test("Auditoria 8: nada do link e cortado calado; a tag e o memo sao lidos, o que o app nao envia recusa")
    func nothingDroppedSilently() throws {
        let r = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
        // Sem esquema, a forma que algumas corretoras dao ao deposito no XRP Ledger: a tag vai junto, e a rede e a do XRP.
        let plain = try PaymentLink.read("\(r)?dt=12345")
        #expect(plain.address == r && plain.tag == "12345" && plain.chainID == Chain.xrpl.id)
        // Sem esquema, com outra coisa depois do endereco: recusa, em vez de ficar so com o endereco.
        #expect(throws: PaymentLink.Problem.unreadParameter("memo")) { try PaymentLink.read("\(r)?memo=5") }
        #expect(throws: PaymentLink.Problem.unreadParameter("amount")) { try PaymentLink.read("\(r)?dt=1&amount=2") }
        #expect(throws: PaymentLink.Problem.unreadParameter("dt")) { try PaymentLink.read("0x2652742DE21ED9a6c37e73b0E3a51b239A6D1008?dt=1") }
        // Sem esquema e sem consulta, o texto inteiro e o endereco: o "@" ou a "/" nao corta mais nada.
        #expect(try PaymentLink.read("0x2652742DE21ED9a6c37e73b0E3a51b239A6D1008@56").address == "0x2652742DE21ED9a6c37e73b0E3a51b239A6D1008@56")
        // "stellar:" com memo: lido como no SEP-7.
        let g = "GA7QYNF7SOWQ3GLR2BGMZEHXAVIRZA4KVWLTJJFC7MGXUA74P7UJVSGZ"
        #expect(try PaymentLink.read("stellar:\(g)?memo=conta-7").tag == "conta-7")
        #expect(throws: PaymentLink.Problem.unsupportedMemo) { try PaymentLink.read("stellar:\(g)?memo=987") }
        // Solana Pay: o `reference` e o `memo` mudam o que o comerciante ve; o `spl-token` e o valor, o dono escolhe na tela.
        let sol = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
        #expect(throws: PaymentLink.Problem.unreadParameter("reference")) { try PaymentLink.read("solana:\(sol)?amount=1&reference=\(sol)") }
        #expect(throws: PaymentLink.Problem.unreadParameter("memo")) { try PaymentLink.read("solana:\(sol)?memo=pedido-9") }
        #expect(try PaymentLink.read("solana:\(sol)?amount=1&spl-token=\(sol)&label=Loja").address == sol)
        // TON: o `bin` e o `init` sao a chamada de um contrato.
        let ton = "EQD__________________________________________0vo"
        #expect(throws: PaymentLink.Problem.unreadParameter("bin")) { try PaymentLink.read("ton://transfer/\(ton)?amount=1&bin=te6cc") }
        #expect(throws: PaymentLink.Problem.unreadParameter("init")) { try PaymentLink.read("ton://transfer/\(ton)?init=te6cc") }
        #expect(try PaymentLink.read("ton://transfer/\(ton)?amount=1&text=deposito").tag == "deposito")
        // SEP-7 da rede de testes, ou com parametro desconhecido: recusa.
        #expect(throws: PaymentLink.Problem.unreadParameter("network_passphrase")) {
            try PaymentLink.read("web+stellar:pay?destination=\(g)&network_passphrase=Test%20SDF%20Network%20%3B%20September%202015")
        }
        #expect(throws: PaymentLink.Problem.unreadParameter("xdr")) { try PaymentLink.read("web+stellar:pay?destination=\(g)&xdr=AAAA") }
        // Outras redes: so o valor, o rotulo e a mensagem ficam de fora.
        #expect(throws: PaymentLink.Problem.unreadParameter("memo")) { try PaymentLink.read("tron:TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t?memo=1") }
        #expect(try PaymentLink.read("tron:TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t?amount=5&label=x").address == "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t")
        // BIP-21: o opcional que o app nao conhece (lightning, pj) fica de fora, como manda o BIP; o `req-` recusa.
        let btc = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        #expect(try PaymentLink.read("bitcoin:\(btc)?amount=0.1&lightning=lnbc1&pj=https://x").address == btc)
        #expect(throws: PaymentLink.Problem.unreadParameter("req-foo")) { try PaymentLink.read("bitcoin:\(btc)?req-foo=1") }
        // Depois do endereco com esquema, so a consulta.
        #expect(throws: PaymentLink.Problem.unreadParameter("/")) { try PaymentLink.read("solana:\(sol)/extra") }
    }

    @Test("Rodada 1: a moeda pedida no link e lida e conferida com a da tela; o callback do SEP-7 recusa")
    func requestedAsset() throws {
        let sol = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
        let usdc = try #require(TokenRegistry.tokens.first { $0.chainID == Chain.solana.id && $0.symbol == "USDC" })
        let usdt = try #require(TokenRegistry.tokens.first { $0.chainID == Chain.solana.id && $0.symbol == "USDT" })
        guard case .token(let mint) = usdc.kind else { Issue.record("USDC da Solana sem mint"); return }
        let reading = try PaymentLink.read("solana:\(sol)?amount=1&spl-token=\(mint)")
        #expect(reading.asset == .token(mint))
        #expect(PaymentLink.matches(reading.asset, asset: usdc))
        #expect(!PaymentLink.matches(reading.asset, asset: usdt))
        #expect(PaymentLink.matches(nil, asset: usdt))
        // Na EVM, o contrato sem diferenca de maiusculas.
        let base = Asset(chainID: Chain.base.id, kind: .token(contract: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"), symbol: "USDC",
                         name: "USDC", decimals: 6, coingeckoID: nil, isStablecoin: true)
        #expect(PaymentLink.matches(.token("0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"), asset: base))
        #expect(!PaymentLink.matches(.issued(code: "USDC", issuer: "x"), asset: base))
        // SEP-7: o ativo emitido e lido; o XLM e a moeda da rede; o callback manda a transacao assinada para fora da rede.
        let g = "GA7QYNF7SOWQ3GLR2BGMZEHXAVIRZA4KVWLTJJFC7MGXUA74P7UJVSGZ"
        let issuer = "GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN"
        #expect(try PaymentLink.read("web+stellar:pay?destination=\(g)&asset_code=USDC&asset_issuer=\(issuer)").asset == .issued(code: "USDC", issuer: issuer))
        #expect(try PaymentLink.read("web+stellar:pay?destination=\(g)&asset_code=XLM").asset == nil)
        #expect(throws: PaymentLink.Problem.unreadParameter("callback")) {
            try PaymentLink.read("web+stellar:pay?destination=\(g)&callback=url%3Ahttps%3A%2F%2Fx.test")
        }
    }

    @Test("Rodada 2: o exp da TON vencido recusa; o codigo da moeda como a rede guarda")
    func expiryAndCodes() throws {
        let ton = "EQD__________________________________________0vo"
        let now = UInt64(Date().timeIntervalSince1970)
        #expect(throws: PaymentLink.Problem.expiredRequest) { try PaymentLink.read("ton://transfer/\(ton)?amount=1&exp=\(now - 60)") }
        #expect(try PaymentLink.read("ton://transfer/\(ton)?amount=1&exp=\(now + 600)").address == ton)
        #expect(throws: PaymentLink.Problem.unreadParameter("exp")) { try PaymentLink.read("ton://transfer/\(ton)?exp=amanha") }
        // Rodada 3: tambem no "ton:" sem o //transfer/.
        #expect(throws: PaymentLink.Problem.expiredRequest) { try PaymentLink.read("ton:\(ton)?amount=1&exp=\(now - 60)") }
        #expect(try PaymentLink.read("ton:\(ton)?amount=1&exp=\(now + 600)").address == ton)
        // O prazo vai junto, para a tela conferir de novo na assinatura.
        #expect(try PaymentLink.read("ton://transfer/\(ton)?exp=\(now + 600)").expiresAt == now + 600)
        #expect(try PaymentLink.read("ton:\(ton)?exp=\(now + 600)").expiresAt == now + 600)
        #expect(try PaymentLink.read("ton:\(ton)").expiresAt == nil)
        #expect(PaymentLink.expired(now - 1) && !PaymentLink.expired(now + 600) && !PaymentLink.expired(nil))
        // XRP Ledger: o RLUSD do link casa com o guardado em hex; o de tres letras compara como esta.
        #expect(PaymentLink.xrplCurrency("RLUSD") == "524C555344000000000000000000000000000000")
        #expect(PaymentLink.xrplCurrency("524c555344000000000000000000000000000000") == "524C555344000000000000000000000000000000")
        #expect(PaymentLink.xrplCurrency("USD") == "USD" && PaymentLink.xrplCurrency("usd") != PaymentLink.xrplCurrency("USD"))
        let issuer = "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"
        let rlusd = Asset(chainID: Chain.xrpl.id, kind: .issued(code: "524C555344000000000000000000000000000000", issuer: issuer), symbol: "RLUSD",
                          name: "RLUSD", decimals: 15, coingeckoID: nil, isStablecoin: true)
        #expect(PaymentLink.matches(.issued(code: "RLUSD", issuer: issuer), asset: rlusd))
        #expect(!PaymentLink.matches(.issued(code: "RLUSD", issuer: "rOutroEmissor"), asset: rlusd))
        // Stellar: maiuscula e minuscula sao moedas diferentes.
        let g = "GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN"
        let usdc = Asset(chainID: Chain.stellar.id, kind: .issued(code: "USDC", issuer: g), symbol: "USDC", name: "USDC", decimals: 7,
                         coingeckoID: nil, isStablecoin: true)
        #expect(PaymentLink.matches(.issued(code: "USDC", issuer: g), asset: usdc))
        #expect(!PaymentLink.matches(.issued(code: "usdc", issuer: g), asset: usdc))
        // Rodada 3: so "XRP" exato e a moeda da rede no XRP Ledger.
        let r = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
        #expect(try PaymentLink.requestedAsset("xrpl:\(r)?currency=XRP", chain: .xrpl) == nil)
        #expect(throws: PaymentLink.Problem.unreadParameter("currency")) { try PaymentLink.requestedAsset("xrpl:\(r)?currency=xrp", chain: .xrpl) }
    }
}
