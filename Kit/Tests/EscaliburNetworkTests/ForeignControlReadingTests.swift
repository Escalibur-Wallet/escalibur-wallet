import EscaliburChains
import EscaliburCore
import Foundation
import Testing
@testable import EscaliburNetwork

/// Outra chave, conta ou contrato no controle de uma conta da carteira, lido em cada rede (auditoria 8, 14/11/2026).
@Suite("Outra chave no controle: as leituras")
struct ForeignControlReadingTests {
    @Test("EVM: a conta comum nao tem codigo; a delegacao EIP-7702 e 0xef0100 e o contrato; o resto e codigo")
    func evmCode() throws {
        #expect(EVMReader.classify(code: []) == .none)
        let delegate = try EVMAddress("0x63c0c19a282a1B52b07dD5a65b58948A07DAE32B")
        #expect(EVMReader.classify(code: [0xef, 0x01, 0x00] + delegate.bytes) == .delegation(delegate))
        #expect(EVMReader.classify(code: [0x60, 0x80, 0x60, 0x40]) == .contract)
        // O prefixo certo com o tamanho errado nao e delegacao.
        #expect(EVMReader.classify(code: [0xef, 0x01, 0x00] + delegate.bytes + [0]) == .contract)
    }

    @Test("Tron: a marca guardada so com os dois de acordo; um de cada, nada")
    func tronAgreement() throws {
        let clean = try TronReader.parseOwnerAccount(try ReaderFixtures.data("tron", "getaccount-dono"), owner: TronReaderTests.owner)
        let dirty = try TronReader.parseOwnerAccount(try ReaderFixtures.data("tron", "getaccount-controle-dividido"), owner: TronReaderTests.shared)
        #expect(TronReader.agreed([dirty, dirty])?.isCompromised == true)
        #expect(TronReader.agreed([clean, clean])?.isCompromised == false)
        #expect(TronReader.agreed([clean, dirty]) == nil)
        #expect(TronReader.agreed([clean]) == nil)
        // Rodada 2: para tirar a marca, pelo menos tres limpos (ou todos, se forem menos); dois limpos nao bastam.
        #expect(TronReader.agreed([clean, clean], floor: 3) == nil)
        #expect(TronReader.agreed([clean, clean, clean], floor: 3)?.isCompromised == false)
        #expect(TronReader.agreed([dirty, dirty], floor: 3)?.isCompromised == true)
        // O aviso na hora continua com um so.
        #expect(try TronReader.combine([clean, dirty]).control.isCompromised)
    }

    @Test("XRP Ledger: a RegularKey ou a lista de assinantes (na API 1 e na 2); lista vazia ou conta inexistente, nada; sem a lista, erro")
    func xrplControl() throws {
        let address = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
        func info(_ extra: String, top: String = "") throws -> StrictJSON {
            try StrictJSON.parse(Data("""
            {"validated":true,"ledger_index":100,"account_data":{"Account":"\(address)","Sequence":5,"Balance":"25000000","OwnerCount":0,"Flags":0\(extra)}\(top)}
            """.utf8))
        }
        // A resposta que nao traz a lista pedida nao diz se a conta esta limpa (rodada 1): erro, e a marca nao sai.
        #expect(throws: ReaderError.self) { try XRPLReader.parseControl(try info(""), address: address, ledger: 100) }
        #expect(try XRPLReader.parseControl(try info(#","RegularKey":"rPEPPER7kfTD9w2To4CQk6UCfuHM9c6GDY""#), address: address, ledger: 100))
        #expect(try XRPLReader.parseControl(try info(#","signer_lists":[{"SignerQuorum":1}]"#), address: address, ledger: 100))
        #expect(try XRPLReader.parseControl(try info("", top: #","signer_lists":[{"SignerQuorum":1}]"#), address: address, ledger: 100))
        #expect(try !XRPLReader.parseControl(try info(#","signer_lists":[]"#), address: address, ledger: 100))
        let missing = try StrictJSON.parse(Data(#"{"error":"actNotFound","ledger_index":100}"#.utf8))
        #expect(try !XRPLReader.parseControl(missing, address: address, ledger: 100))
    }

    @Test("Stellar: outro assinante com peso; a propria chave, ou outro com peso zero, nao")
    func stellarSigners() throws {
        let account = "GA7QYNF7SOWQ3GLR2BGMZEHXAVIRZA4KVWLTJJFC7MGXUA74P7UJVSGZ"
        func record(_ signers: String) throws -> HorizonAccount {
            try JSONDecoder().decode(HorizonAccount.self, from: Data("""
            {"account_id":"\(account)","sequence":"1","subentry_count":0,"num_sponsoring":0,"num_sponsored":0,"balances":[],"data":{},
             "signers":\(signers)}
            """.utf8))
        }
        #expect(!StellarReader.hasForeignSigner(try record(#"[{"key":"\#(account)","weight":1,"type":"ed25519_public_key"}]"#), account: account))
        #expect(StellarReader.hasForeignSigner(try record(#"[{"key":"\#(account)","weight":1},{"key":"GBOTHER","weight":1}]"#), account: account))
        #expect(!StellarReader.hasForeignSigner(try record(#"[{"key":"\#(account)","weight":1},{"key":"GBOTHER","weight":0}]"#), account: account))
    }

    @Test("NEAR: outra chave de acesso total; a da frase e a de chamada de funcao, nao")
    func nearKeys() throws {
        let mine = "ed25519:7PGseFbWxvYVgZ89K1uTJKYoKetWs7BJtbyXDzfbAcqX"
        func list(_ keys: String) throws -> StrictJSON {
            try StrictJSON.parse(Data(#"{"block_hash":"H","keys":\#(keys)}"#.utf8))
        }
        let own = #"{"public_key":"\#(mine)","access_key":{"nonce":1,"permission":"FullAccess"}}"#
        let function = #"{"public_key":"ed25519:Other","access_key":{"nonce":1,"permission":{"FunctionCall":{"receiver_id":"app.near"}}}}"#
        let full = #"{"public_key":"ed25519:Other","access_key":{"nonce":1,"permission":"FullAccess"}}"#
        #expect(try !NEARReader.parseForeignFullAccess(try list("[\(own),\(function)]"), mine: mine, at: "H"))
        #expect(try NEARReader.parseForeignFullAccess(try list("[\(own),\(full)]"), mine: mine, at: "H"))
    }

    @Test("TON: plugin ou extensao na pilha das duas APIs; vazio e null, nada; formato desconhecido e erro")
    func tonStack() throws {
        func json(_ text: String) throws -> StrictJSON { try StrictJSON.parse(Data(text.utf8)) }
        #expect(try !TONReader.stackHasEntries(try json(#"["null", null]"#), "m"))
        #expect(try !TONReader.stackHasEntries(try json(#"["list", {"elements": []}]"#), "m"))
        #expect(try TONReader.stackHasEntries(try json(#"["list", {"elements": [["tuple", {"elements": []}]]}]"#), "m"))
        #expect(try TONReader.stackHasEntries(try json(#"["cell", {"bytes": "te6c"}]"#), "m"))
        #expect(try !TONReader.stackHasEntries(try json(#"{"type": "null"}"#), "m"))
        #expect(try !TONReader.stackHasEntries(try json(#"{"type": "tuple", "tuple": []}"#), "m"))
        #expect(try TONReader.stackHasEntries(try json(#"{"type": "tuple", "tuple": [{"type": "num", "num": "0x0"}]}"#), "m"))
        #expect(try TONReader.stackHasEntries(try json(#"{"type": "cell", "cell": "b5ee"}"#), "m"))
        #expect(throws: ReaderError.self) { try TONReader.stackHasEntries(try json(#"["num", "0x1"]"#), "m") }
    }

    @Test("Polkadot: o xxHash64 do Substrate confere com o prefixo de System.Account e com os valores de referencia")
    func xxhash() throws {
        #expect(XXHash64.twox128(Array("System".utf8)) + XXHash64.twox128(Array("Account".utf8)) == PolkadotReader.systemAccountPrefix)
        #expect(XXHash64.twox128(Array("Proxy".utf8)) + XXHash64.twox128(Array("Proxies".utf8)) == PolkadotReader.proxiesPrefix)
        #expect(XXHash64.hash([], seed: 0) == 0xEF46_DB37_51D8_E999)
        #expect(XXHash64.hash(Array("abc".utf8), seed: 0) == 0x44BC_2CF5_AD77_0999)
        #expect(Hex.encode(XXHash64.twox64(Array(0..<32))) == "b432ff16519cf5cb")
    }

    @Test("Polkadot: a chave do procurador e o prefixo, o xxHash64 e a conta; a lista vazia ou nada guardado, nada")
    func proxies() throws {
        let owner = try #require(PolkadotAddress(accountID: Array(0..<32)))
        #expect(PolkadotReader.proxiesKey(owner) == "0x1809d78346727a0ef58c0fa03bafa3231d885dcfb277f185f2d8e62a5f290c85b432ff16519cf5cb"
            + Hex.encode(Array(0..<32)))
        #expect(!PolkadotReader.hasProxies(nil))
        #expect(!PolkadotReader.hasProxies([0x00] + [UInt8](repeating: 0, count: 16)))
        #expect(PolkadotReader.hasProxies([0x04] + [UInt8](repeating: 7, count: 70)))
    }

    @Test("Solana: a conta do USDC com outro dono, delegado ou quem fecha e outro controle; a do proprio dono, nao")
    func solanaTokenControl() throws {
        let owner = try SolanaPublicKey(base58: "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU")
        let other = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
        func account(_ extra: String, holder: String? = nil) throws -> RPCAccount {
            try JSONDecoder().decode(RPCAccount.self, from: Data("""
            {"lamports":2039280,"owner":"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA","executable":false,"space":165,"data":{"program":"spl-token",
             "parsed":{"type":"account","info":{"owner":"\(holder ?? owner.base58)","mint":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
             "state":"initialized","tokenAmount":{"amount":"5","decimals":6}\(extra)}}}}
            """.utf8))
        }
        #expect(!SolanaAccountParser.tokenControlChanged(try account(""), owner: owner))
        #expect(SolanaAccountParser.tokenControlChanged(try account(#","delegate":"\#(other)""#), owner: owner))
        #expect(SolanaAccountParser.tokenControlChanged(try account(#","closeAuthority":"\#(other)""#), owner: owner))
        #expect(SolanaAccountParser.tokenControlChanged(try account("", holder: other), owner: owner))
    }
}
