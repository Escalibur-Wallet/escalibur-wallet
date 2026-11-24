import EscaliburChains
import EscaliburCore
import Foundation

/// O unico lugar do app onde uma chave privada assina alguma coisa.
///
/// Recebe um `SigningPlan` (que so existe se passou pela validacao da rede) e a RK
/// recem-destrancada por presenca do dono. Sincrono de ponta a ponta, sem `await`:
/// funcao assincrona guarda variaveis locais num contexto no heap que e liberado sem
/// zerar, e aqui as variaveis locais sao a seed e as chaves (docs/seguranca.md §2.9).
///
/// ```
/// rk ─► DEK ─► registro ─► frase ─► seed ─► chave de cada pedido ─► assinatura
///   cada etapa zera a anterior; a seed e as chaves somem no fim do plano
/// ```
public enum Signer {
    public enum Failure: Error, Equatable, Sendable {
        case expired
        /// A chave derivada nao e a que a transacao espera: caminho errado ou
        /// carteira errada. Nada foi assinado.
        case unexpectedKey
        /// A assinatura produzida nao verificou. Com nonce deterministico, uma
        /// assinatura defeituosa pode entregar a chave; ela nunca sai daqui.
        case verificationFailed
        case unsupportedScheme(SignatureScheme)
        /// A passphrase digitada nao da a carteira (o fingerprint da raiz nao bate). Nada foi
        /// assinado.
        case passphraseMismatch
    }

    /// Assina todas as transacoes do plano, na ordem. Consome e zera a RK.
    ///
    /// `passphrase`: numa carteira com passphrase, a que o dono acabou de digitar (ou a que a
    /// folga de alguns minutos guarda na memoria). O cofre nao tem passphrase nenhuma (pedido do
    /// dono, 05/11/2026): a seed nasce da entropia do cofre com esta, em NFKD, e a raiz tem de dar
    /// o `fingerprint` que a criacao gravou, antes de nascer qualquer chave; nao da, nada e
    /// assinado. Com o fingerprint, a raiz confere tambem sem passphrase. O chamador continua dono do buffer. Sem valor padrao: cada chamador diz se ha
    /// passphrase, e um chamador novo nao fura a regra esquecendo o parametro. Sem ela, uma
    /// carteira com passphrase daria as chaves da carteira de base, que a `expectedPublicKey`
    /// recusa.
    public static func sign(_ plan: SigningPlan, rootKey rk: SecureBytes, vault: WalletVault,
                            passphrase typed: SecureBytes?, fingerprint: [UInt8]?) throws -> [SignedTransaction] {
        // Por ultimo: a pilha que as contas da BoringSSL deixaram (StackWipe).
        defer { StackWipe.below() }
        defer { rk.wipe() }
        guard !plan.isExpired() else { throw Failure.expired }
        // O nonce conferido antes de abrir o cofre. A derivacao aqui nao passa pelo `DerivationSelfTest`, de proposito: a
        // chave tem de bater com a `expectedPublicKey` e a assinatura e verificada, e uma derivacao errada so falha fechado.
        // Recusar o envio por ela congelaria o saldo sem proteger nada (revisao da decima terceira passada).
        guard SigningSelfTest.passed(for: plan) else { throw SigningSelfTest.Failure() }

        let secret = PassphraseProof.joining(try vault.open(walletID: plan.walletID, rk: rk), typed)
        rk.wipe()
        defer { secret.wipe() }
        let seed = try secret.seed()
        defer { seed.wipe() }

        var masters: [Curve: HDKey] = [:]
        defer { masters.values.forEach { $0.wipe() } }
        func master(_ curve: Curve) throws -> HDKey {
            if let cached = masters[curve] { return cached }
            let made = try HDKey.master(seed: seed, curve: curve)
            masters[curve] = made
            return made
        }
        // A raiz confere antes de qualquer chave de pedido, com ou sem passphrase: a carteira com passphrase que chegasse
        // sem ela daria a raiz da carteira de base, e a recusa vem aqui, e nao na chave de cada pedido.
        if let fingerprint {
            guard Hash.constantTimeEqual(try master(.secp256k1).fingerprint(), fingerprint) else {
                throw typed == nil ? Failure.unexpectedKey : Failure.passphraseMismatch
            }
        } else if typed != nil {
            throw Failure.passphraseMismatch
        }
        // Cardano: a mestra Icarus sai da entropia (CIP-3), antes de o segredo ser zerado. A passphrase com acento que uma
        // versao anterior gravou fora de NFKD deu a conta da Cardano pelos bytes digitados: a mestra deles fica de reserva,
        // para essa carteira mover o saldo da Cardano como a tela de aviso pede.
        let cardano = try CardanoSigning.master(for: plan, secret: secret)
        defer { cardano?.wipe() }
        let legacyCardano = try typed.flatMap { try PassphraseProof.legacyCardanoMaster(for: plan, stored: secret, typed: $0) }
        defer { legacyCardano?.wipe() }
        secret.wipe()

        var signed: [SignedTransaction] = []
        for transaction in plan.transactions {
            var signatures: [ProducedSignature] = []
            for request in transaction.signingRequests {
                if request.scheme == .ed25519Cardano {
                    do {
                        signatures.append(try CardanoSigning.sign(request, master: cardano))
                    } catch Failure.unexpectedKey where legacyCardano != nil {
                        signatures.append(try CardanoSigning.sign(request, master: legacyCardano))
                    }
                    continue
                }
                let key = try master(request.curve).derive(request.path)
                defer { key.wipe() }
                signatures.append(try sign(request, with: key))
            }
            signed.append(try transaction.assemble(with: signatures))
        }
        return signed
    }

    static func sign(_ request: SigningRequest, with key: HDKey) throws -> ProducedSignature {
        let publicKey = try key.publicKey()
        guard Hash.constantTimeEqual(publicKey, request.expectedPublicKey) else { throw Failure.unexpectedKey }

        switch request.scheme {
        case .ecdsaDER:
            let der = try Secp256k1.signDER(digest: request.payload, privateKey: key.key, hedged: true)
            guard Secp256k1.verifyDER(signature: der, digest: request.payload, publicKey: publicKey) else {
                throw Failure.verificationFailed
            }
            return ProducedSignature(bytes: der)
        case .ecdsaRecoverable:
            let (compact, recovery) = try Secp256k1.signRecoverable(digest: request.payload, privateKey: key.key, hedged: true)
            let recovered = try Secp256k1.recover(digest: request.payload, compact: compact, recoveryID: recovery, compressed: true)
            guard recovered == publicKey else { throw Failure.verificationFailed }
            return ProducedSignature(bytes: compact, recoveryID: recovery)
        case .ed25519:
            let signature = try Ed25519.sign(request.payload, seed: key.key, hedged: true)
            guard Ed25519.verify(signature: signature, message: request.payload, publicKey: publicKey) else {
                throw Failure.verificationFailed
            }
            return ProducedSignature(bytes: signature)
        case .schnorrBIP340:
            throw Failure.unsupportedScheme(.schnorrBIP340)
        case .ed25519Cardano:
            // Chave BIP32-Ed25519, que o HDKey nao deriva: so pelo CardanoSigning.
            throw Failure.unsupportedScheme(.ed25519Cardano)
        }
    }
}

/// A passphrase de uma carteira com passphrase nunca e gravada (pedido do dono, 05/11/2026). O cofre guarda
/// so a entropia e o idioma; a passphrase entra digitada, so durante a operacao, e confere pelo fingerprint
/// BIP-32 da raiz que a criacao gravou nos metadados (4 bytes do hash da chave publica, que nao dizem a
/// passphrase). Quem tem o PIN e as palavras ja podia testar passphrases fora do aparelho pelos enderecos;
/// o fingerprint nao abre nada a mais.
public enum PassphraseProof {
    public enum Result: Sendable, Equatable {
        case match
        case mismatch
        /// Confere, mas uma versao anterior gravou a passphrase fora de NFKD, e a conta da Cardano dela saiu
        /// dos bytes digitados: restaurada pelas palavras, ela muda.
        case legacy
    }

    /// O segredo de uso: a entropia do cofre (que passa a ser dele) e uma copia da digitada em NFKD. O
    /// chamador continua dono de `typed`.
    static func joining(_ stored: WalletSecret, _ typed: SecureBytes?) -> WalletSecret {
        stored.passphrase.wipe()
        return WalletSecret(entropy: stored.entropy, language: stored.language, passphrase: typed.map(BIP39.nfkd) ?? SecureBytes(capacity: 1))
    }

    /// A passphrase digitada da a carteira? Pelo cofre, com a RK aberta agora (consumida). `cardanoPublicKey`:
    /// a chave da conta Cardano gravada, para achar a passphrase de uma versao anterior (`legacy`).
    public static func check(walletID: UUID, rootKey rk: SecureBytes, vault: WalletVault, typed: SecureBytes,
                             fingerprint: [UInt8]?, cardanoPublicKey: [UInt8]?) throws -> Result {
        defer { rk.wipe() }
        let stored = try vault.open(walletID: walletID, rk: rk)
        rk.wipe()
        defer { stored.wipe() }
        return try check(stored, typed: typed, fingerprint: fingerprint, cardanoPublicKey: cardanoPublicKey)
    }

    /// Com o registro ja aberto (que continua de quem chama).
    public static func check(_ stored: WalletSecret, typed: SecureBytes, fingerprint: [UInt8]?, cardanoPublicKey: [UInt8]?) throws -> Result {
        let entropy = SecureBytes(capacity: stored.entropy.count)
        stored.entropy.withUnsafeBytes { entropy.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        let secret = WalletSecret(entropy: entropy, language: stored.language, passphrase: BIP39.nfkd(typed))
        defer { secret.wipe() }
        return try verify(secret, fingerprint: fingerprint, cardanoPublicKey: cardanoPublicKey)
    }

    /// Pela frase em buffer (as palavras que a tela acabou de mostrar), sem o cofre.
    public static func check(phrase: SecureBytes, language: BIP39Language, typed: SecureBytes,
                             fingerprint: [UInt8]?, cardanoPublicKey: [UInt8]?) throws -> Result {
        let stored = try WalletSecret.from(phrase: phrase, language: language)
        let secret = joining(stored, typed)
        defer { secret.wipe() }
        return try verify(secret, fingerprint: fingerprint, cardanoPublicKey: cardanoPublicKey)
    }

    /// A raiz tem o fingerprint da criacao? E, com a conta Cardano gravada, ela e a desta passphrase em NFKD? A
    /// passphrase certa com outra conta Cardano e a que uma versao anterior gravou fora de NFKD.
    static func verify(_ secret: WalletSecret, fingerprint: [UInt8]?, cardanoPublicKey: [UInt8]?) throws -> Result {
        defer { StackWipe.below() }
        guard let fingerprint, secret.passphrase.count > 0 else { return .mismatch }
        let seed = try secret.seed()
        defer { seed.wipe() }
        let root = try HDKey.master(seed: seed, curve: .secp256k1)
        defer { root.wipe() }
        guard Hash.constantTimeEqual(try root.fingerprint(), fingerprint) else { return .mismatch }
        guard let cardanoPublicKey else { return .match }
        return try CardanoKey.derivedAccount(secret).publicKey == cardanoPublicKey ? .match : .legacy
    }

    /// A mestra Icarus pelos bytes digitados, so quando o plano tem Cardano e o NFKD muda a passphrase.
    static func legacyCardanoMaster(for plan: SigningPlan, stored secret: WalletSecret, typed: SecureBytes) throws -> CardanoKey? {
        guard !Hash.constantTimeEqual(secret.passphrase, typed) else { return nil }
        let raw = rawSecret(secret, typed)
        defer { raw.wipe() }
        return try CardanoSigning.master(for: plan, secret: raw)
    }

    private static func rawSecret(_ secret: WalletSecret, _ typed: SecureBytes) -> WalletSecret {
        let entropy = SecureBytes(capacity: secret.entropy.count)
        secret.entropy.withUnsafeBytes { entropy.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        let passphrase = SecureBytes(capacity: max(typed.count, 1))
        typed.withUnsafeBytes { passphrase.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        return WalletSecret(entropy: entropy, language: secret.language, passphrase: passphrase)
    }

    /// Os enderecos das redes que faltam numa carteira com passphrase, com a passphrase digitada agora, depois de
    /// ela conferir: uma rede que entrou numa versao nova so pode nascer assim, porque o cofre nao tem a
    /// passphrase. Nao consome a RK: quem chama assina logo depois com ela. Nao confere, nada.
    public static func missingAccounts(walletID: UUID, rootKey rk: SecureBytes, vault: WalletVault, typed: SecureBytes,
                                       fingerprint: [UInt8]?, chains: [Chain]) throws -> [DerivedAccount] {
        guard !chains.isEmpty else { return [] }
        let secret = joining(try vault.open(walletID: walletID, rk: rk), typed)
        defer { secret.wipe() }
        guard try verify(secret, fingerprint: fingerprint, cardanoPublicKey: nil) == .match else { return [] }
        return try AccountDeriver.derive(secret, chains: chains).accounts
    }
}

public enum AccountDeriver {
    /// Deriva o endereco padrao de cada rede, depois de o aparelho conferir os vetores publicos (`DerivationSelfTest`): com
    /// um resultado diferente, nenhuma carteira e derivada (decima terceira passada da auditoria de 03/11/2026).
    public static func derive(_ secret: WalletSecret, chains: [Chain] = Chain.all) throws -> (accounts: [DerivedAccount], fingerprint: [UInt8]) {
        defer { StackWipe.below() }
        guard DerivationSelfTest.passed else { throw DerivationSelfTest.Failure() }
        // Duas vezes, iguais: um defeito intermitente do aparelho (memoria, otimizador) que tivesse passado no autoteste nao
        // grava um endereco que a frase nao reabre (revisao da decima terceira passada).
        let first = try deriveUnchecked(secret, chains: chains)
        let second = try deriveUnchecked(secret, chains: chains)
        guard first.accounts == second.accounts, first.fingerprint == second.fingerprint else { throw DerivationSelfTest.Failure() }
        return first
    }

    /// A derivacao em si, sem a conferencia: so para o proprio `DerivationSelfTest`.
    static func deriveUnchecked(_ secret: WalletSecret, chains: [Chain]) throws -> (accounts: [DerivedAccount], fingerprint: [UInt8]) {
        let seed = try secret.seed()
        defer { seed.wipe() }
        let secp = try HDKey.master(seed: seed, curve: .secp256k1)
        let ed = try HDKey.master(seed: seed, curve: .ed25519)
        defer { secp.wipe(); ed.wipe() }

        var accounts: [DerivedAccount] = []
        for chain in chains {
            if chain.family == .cardano {
                if let account = try? CardanoKey.derivedAccount(secret, chain: chain) { accounts.append(account) }
                continue
            }
            let path = DefaultPaths.path(for: chain)
            let master = chain.family.curve == .secp256k1 ? secp : ed
            let key = try master.derive(path)
            defer { key.wipe() }
            let publicKey = try key.publicKey()
            guard let address = try? Address.from(publicKey: publicKey, chain: chain) else { continue }
            var xpub: ExtendedPublicKey?
            if chain.family == .utxo {
                let accountPath = DerivationPath(components: Array(path.components.prefix(3)))
                let account = try master.derive(accountPath)
                defer { account.wipe() }
                xpub = try ExtendedPublicKey(publicKey: account.publicKey(), chainCode: account.chainCode.withUnsafeBytes { Array($0) })
            }
            accounts.append(DerivedAccount(chainID: chain.id, path: path, address: address, publicKey: publicKey, accountXPub: xpub))
        }
        return (accounts, try secp.fingerprint())
    }
}
