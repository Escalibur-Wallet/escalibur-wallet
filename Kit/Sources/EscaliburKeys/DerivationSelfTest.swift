import EscaliburChains
import EscaliburCore
import Foundation

/// Os vetores publicos da frase ao endereco, conferidos no proprio aparelho antes de qualquer derivacao de carteira
/// (decima terceira passada da auditoria de 03/11/2026). E o binario que vai para a loja (no Android, otimizado e com a
/// biblioteca do Swift estatica), no aparelho do dono: um resultado diferente seria uma carteira que o papel nao reabre em
/// outro app, e nenhuma carteira e criada, importada ou ganha rede nova.
///
/// Tudo pelo caminho das carteiras (`WalletSecret.from`, `seed()`, `AccountDeriver`), e nao por uma sobrecarga que so o
/// teste usa (revisao da decima terceira passada):
/// - a seed BIP-39 com a passphrase "TREZOR" (trezor/python-mnemonic, vectors.json, english[0]);
/// - a seed da frase japonesa do bip32JP (test_JP_BIP39.json, vetor 0): a lista japonesa e a passphrase (o ㍍ e as kana
///   com dakuten) so dao esta seed com o NFKD (o NFD, o NFC e o NFKC dao outras), tanto a frase gerada aqui quanto a
///   digitada, com o espaco ideografico e o ぞ composto, que passa pela normalizacao da importacao;
/// - o endereco de cada rede que nao e EVM, e o da Ethereum pelas EVM, que derivam pelo mesmo caminho: da frase abandon, Bitcoin pelo BIP-84, Ethereum e Solana pelo python-hdwallet, XRPL e
///   Tron pelo firmware da Keystone, Stellar pela SEP-0005 (teste 5); da frase shoot, as demais pela Trust Wallet Core
///   (CoinAddressDerivationTests.swift);
/// - o recebimento 1 e o troco 0 do Bitcoin pela xpub da conta (BIP-84), a derivacao publica que acompanha os saldos e
///   confere o troco.
public enum DerivationSelfTest {
    public struct Failure: LocalizedError, Sendable {
        public init() {}

        public var errorDescription: String? {
            kitText("Este aparelho calculou um endereço de teste diferente do esperado. Por segurança, nenhuma carteira é criada ou importada aqui.")
        }
    }

    /// Conferido na primeira derivacao. Um valor diferente do esperado recusa ate o app fechar, mesmo que a proxima conta
    /// desse certo (um defeito intermitente); so um erro de agora (uma leitura que falhou) e conferido de novo.
    public static var passed: Bool {
        cache.passed {
            do { return try check() } catch { return nil }
        }
    }

    /// Para criar e importar: antes de abrir a RK e de gravar qualquer coisa no cofre.
    public static func require() throws {
        guard passed else { throw Failure() }
    }

    /// Tres estados: ainda nao conferido (ou um erro de agora), passou, e falhou (vale ate o processo morrer).
    final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Bool?

        func passed(_ run: () -> Bool?) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if result == nil { result = run() }
            return result == true
        }
    }

    private static let cache = Cache()

    /// De onde sai a carteira de teste. A frase dos vetores do BIP-39 e do bip32JP e a da entropia zero, gerada aqui pelo
    /// mesmo `BIP39.phrase(fromEntropy:)` das carteiras: o texto em ingles dela nao fica no binario, onde marca o modo demo
    /// e a conferencia do build recusa (revisao da decima terceira passada). A japonesa tambem vai digitada, pela importacao.
    enum Source {
        case zeroEntropy(BIP39Language)
        case phrase(String, BIP39Language)
    }

    static let shoot = "shoot island position soft burden budget tooth cruel issue economy destroy above"
    static let japanese = Array(repeating: "\u{3042}\u{3044}\u{3053}\u{304F}\u{3057}\u{3093}", count: 11).joined(separator: "\u{3000}")
        + "\u{3000}\u{3042}\u{304A}\u{305E}\u{3089}"
    static let japanesePassphrase = "\u{334D}\u{30AC}\u{30D0}\u{30F4}\u{30A1}\u{3071}\u{3070}\u{3050}\u{309E}\u{3061}\u{3062}\u{5341}\u{4EBA}\u{5341}\u{8272}"

    static let seeds: [(source: Source, passphrase: String, seed: String)] = [
        (.zeroEntropy(.english), "TREZOR", "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"),
        (.zeroEntropy(.japanese), japanesePassphrase, "a262d6fb6122ecf45be09c50492b31f92e9beb7d9a845987a02cefda57a15f9c467a17872029a9e92299b5cbdf306e3a0ee620245cbd508959b6cb7ca637bd55"),
        (.phrase(japanese, .japanese), japanesePassphrase, "a262d6fb6122ecf45be09c50492b31f92e9beb7d9a845987a02cefda57a15f9c467a17872029a9e92299b5cbdf306e3a0ee620245cbd508959b6cb7ca637bd55"),
    ]

    static let addresses: [(source: Source, accounts: [(chain: Chain, address: String)])] = [
        (.zeroEntropy(.english), [
            (.bitcoin, "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"),
            (.ethereum, "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"),
            (.solana, "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk"),
            (.xrpl, "rHsMGQEkVNJmpGWs8XUBoTBiAAbwxZN5v3"),
            (.tron, "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"),
            (.stellar, "GB3JDWCQJCWMJ3IILWIGDTQJJC5567PGVEVXSCVPEQOTDN64VJBDQBYX"),
        ]),
        (.phrase(shoot, .english), [
            (.ton, "UQDgEMqToTacHic7SnvnPFmvceG5auFkCcAw0mSCvzvKUaT4"),
            (.sui, "0xada112cfb90b44ba889cc5d39ac2bf46281e4a91f7919c693bcd9b8323e81ed2"),
            (.cardano, "addr1qyr8jjfnypp95eq74aqzn7ss687ehxclgj7mu6gratmg3mul2040vt35dypp042awzsjk5xm3zr3zm5qh7454uwdv08s84ray2"),
            (.polkadot, "13nN6BGAoJwd7Nw1XxeBCx5YcBXuYnL94Mh7i3xBprqVSsFk"),
            (.near, "0c91f6106ff835c0195d5388565a2d69e25038a7e23d26198f85caf6594117ec"),
            (.aptos, "0x07968dab936c1bad187c60ce4082f307d030d780e91e694ae03aef16aba73f30"),
            (.litecoin, "ltc1qhd8fxxp2dx3vsmpac43z6ev0kllm4n53t5sk0u"),
            (.dogecoin, "DJRFZNg8jkUtjcpo2zJd92FUAzwRjitw6f"),
        ]),
    ]

    /// O recebimento 1 e o troco 0 da conta Bitcoin da frase abandon, pela xpub (BIP-84).
    static let publicChildren: [(path: [UInt32], address: String)] = [
        ([0, 1], "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g"),
        ([1, 0], "bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el"),
    ]

    static func secret(_ source: Source, passphrase: String) throws -> WalletSecret {
        // O segredo fica com o buffer da passphrase (o ASCII entra sem copia), e o `wipe()` dele o zera.
        let typed = SecureBytes(capacity: max(passphrase.utf8.count, 1))
        Array(passphrase.utf8).withUnsafeBufferPointer { typed.append(contentsOf: $0) }
        let words: SecureBytes
        let language: BIP39Language
        switch source {
        case .zeroEntropy(let idioma):
            let entropy = SecureBytes(capacity: 16)
            entropy.replaceAll(with: [UInt8](repeating: 0, count: 16))
            defer { entropy.wipe() }
            words = try BIP39.phrase(fromEntropy: entropy, language: idioma)
            language = idioma
        case .phrase(let phrase, let idioma):
            words = BIP39.canonical(phrase)
            language = idioma
        }
        defer { words.wipe() }
        return try WalletSecret.from(phrase: words, language: language, passphrase: typed)
    }

    static func check() throws -> Bool {
        for vector in seeds {
            let wallet = try secret(vector.source, passphrase: vector.passphrase)
            defer { wallet.wipe() }
            let seed = try wallet.seed()
            defer { seed.wipe() }
            guard seed.withUnsafeBytes({ Hex.encode(Array($0)) }) == vector.seed else { return false }
        }
        // Uma familia nova nao entra sem um vetor, nem uma rede nova numa familia que ja existe: toda rede que nao e EVM tem
        // o seu, e a EVM so passa pelo caminho e pela moeda da Ethereum (revisao da decima terceira passada).
        guard Set(addresses.flatMap { $0.accounts.map(\.chain.family) }) == Set(ChainFamily.allCases) else { return false }
        let covered = Set(addresses.flatMap { $0.accounts.map(\.chain.id) })
        guard Chain.all.allSatisfy({ chain in
            covered.contains(chain.id)
                || (chain.family == .evm && chain.coinType == Chain.ethereum.coinType && DefaultPaths.path(for: chain) == DefaultPaths.path(for: .ethereum))
        }) else { return false }
        for (source, expected) in addresses {
            let wallet = try secret(source, passphrase: "")
            defer { wallet.wipe() }
            let (accounts, _) = try AccountDeriver.deriveUnchecked(wallet, chains: expected.map(\.chain))
            for (chain, address) in expected {
                guard let account = accounts.first(where: { $0.chainID == chain.id }), account.address == address else { return false }
                guard chain.id == Chain.bitcoin.id else { continue }
                guard let xpub = account.accountXPub else { return false }
                for child in publicChildren {
                    guard try Address.from(publicKey: xpub.derive(child.path).publicKey, chain: chain) == child.address else { return false }
                }
            }
        }
        return true
    }
}
