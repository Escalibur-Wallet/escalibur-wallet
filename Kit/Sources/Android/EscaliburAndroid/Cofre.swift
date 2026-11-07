import CJNI
import Crypto
import EscaliburCore
import EscaliburKeys
import Foundation

/// O chaveiro e o Secure Enclave do Android, para o mesmo cofre do iOS (RootKeyVault e
/// WalletVault): o Keystore, pela classe Kotlin app.escalibur.wallet.nucleo.Cofre, que descreve
/// cada chave. Aqui so a traducao dos codigos para os erros que o cofre ja conhece.
enum Cofre {
    /// Os codigos de Cofre.kt.
    enum Codigo: Int32 {
        case ok = 0, ausente, senha, falha, duplicado, semBloqueio, cancelado, semChave, indisponivel
        /// O celular bloqueou antes de o Keystore usar a chave: nada foi conferido.
        case bloqueado
    }

    /// Depois de `Java.ligar`, no JNI_OnLoad: o que o cofre pergunta ao sistema.
    static func instalar() {
        KeyPlatform.install(KeyPlatform(
            biometry: {
                switch (try? chamarInt("Cofre.estadoDaBiometria", [])) ?? 2 {
                case 0: .ready
                case 1: .notEnrolled
                case 3: .lockedOut
                default: .unavailable
                }
            },
            biometryState: { try? chamarBytes("Cofre.cadastroDaBiometria", []) },
            bootIdentity: {
                // O numero de boots do sistema; sem ele, o boot_id do kernel.
                (try? chamarBytes("Cofre.boot", [])).map { [UInt8]($0) } ?? KeyPlatform.kernelBootID()
            }
        ))
    }

    // MARK: Chamadas

    /// Os argumentos de uma chamada: texto, bytes (copiados para um byte[] que o Kotlin zera),
    /// inteiro ou booleano.
    enum Argumento {
        case texto(String?)
        case bytes(Data?)
        case segredo(SecureBytes)
        case inteiro(Int32)
        case booleano(Bool)
    }

    private static func comArgumentos<T>(_ java: JavaEnv, _ argumentos: [Argumento], _ corpo: ([jvalue]) throws -> T) rethrows -> T {
        var locais: [jobject?] = []
        defer { locais.forEach(java.deleteLocal) }
        let valores = argumentos.map { argumento -> jvalue in
            var valor = jvalue()
            switch argumento {
            case .texto(let texto):
                let local = texto.flatMap { java.string($0) }
                locais.append(local)
                valor.l = local
            case .bytes(let dados):
                let local = dados.flatMap { java.byteArray($0) }
                locais.append(local)
                valor.l = local
            case .segredo(let segredo):
                let local = java.byteArray(segredo)
                locais.append(local)
                valor.l = local
            case .inteiro(let inteiro):
                valor.i = inteiro
            case .booleano(let booleano):
                valor.z = java.booleano(booleano)
            }
            return valor
        }
        return try corpo(valores)
    }

    static func chamarInt(_ nome: String, _ argumentos: [Argumento]) throws -> Int32 {
        let metodo = try Java.metodo(nome)
        let resultado = try Java.naMaquina { java in comArgumentos(java, argumentos) { java.callStaticInt(metodo, $0) } }
        guard let resultado else { throw EnclaveError.failed(nome) }
        return resultado
    }

    static func chamarVoid(_ nome: String, _ argumentos: [Argumento]) {
        guard let metodo = try? Java.metodo(nome) else { return }
        try? Java.naMaquina { java in comArgumentos(java, argumentos) { java.callStaticVoid(metodo, $0) } }
    }

    /// Para o que nao e segredo (a identidade do boot, o hash do cadastro). Nil quando o Kotlin
    /// devolve null.
    static func chamarBytes(_ nome: String, _ argumentos: [Argumento]) throws -> Data? {
        let metodo = try Java.metodo(nome)
        return try Java.naMaquina { java in
            comArgumentos(java, argumentos) { valores in
                let resultado = java.callStatic(metodo, valores)
                defer { java.deleteLocal(resultado) }
                return java.bytes(resultado)
            }
        }
    }

    /// Uma chamada que devolve [codigo] e, com ok, um segredo: lido direto para o buffer seguro,
    /// e o byte[] do Java zerado no lugar.
    static func chamarSegredo(_ nome: String, _ argumentos: [Argumento]) throws -> (Codigo, SecureBytes?) {
        let metodo = try Java.metodo(nome)
        return try Java.naMaquina { java in
            comArgumentos(java, argumentos) { valores in
                let resultado = java.callStatic(metodo, valores)
                defer { java.deleteLocal(resultado) }
                guard let primeiro = java.firstByte(resultado) else { return (.falha, nil) }
                let codigo = Codigo(rawValue: Int32(primeiro)) ?? .falha
                guard codigo == .ok else { return (codigo, nil) }
                return (.ok, java.secureBytes(resultado, from: 1))
            }
        }
    }
}

/// O armazenamento dos itens do cofre no Android (o `KeychainStore` do iOS): arquivos cifrados
/// pelo Keystore, na pasta sem backup do app.
public final class KeystoreStore: SecretStore, @unchecked Sendable {
    public init() {}

    public func read(_ account: String, context: LAContext?) throws -> Data? {
        defer { context?.invalidate() }
        // A senha de aplicativo (o AP do PIN) nao vai ao Kotlin: o item novo nao a usa, e o PIN e
        // conferido pela chave do slot no hardware. So o item do formato antigo a pede ("senha"), e
        // abrir com a certa o passa ao novo (revisao de seguranca do Android de 26/10/2026).
        var (codigo, conteudo) = try Cofre.chamarSegredo("Cofre.ler", [.texto(account), .bytes(nil)])
        if codigo == .senha, let senha = context?.credential {
            (codigo, conteudo) = try Cofre.chamarSegredo("Cofre.ler", [.texto(account), .bytes(senha)])
        }
        switch codigo {
        case .ok:
            guard let conteudo else { throw StoreError.unexpected(errSecIO) }
            defer { conteudo.wipe() }
            return conteudo.withUnsafeBytes { Data($0) }
        case .ausente: return nil
        case .senha: throw StoreError.authenticationFailed
        case .bloqueado: throw StoreError.interactionNotAllowed
        default: throw StoreError.unexpected(errSecIO)
        }
    }

    public func add(_ data: Data, account: String, protection: ItemProtection, context: LAContext?) throws {
        defer { context?.invalidate() }
        let codigo = try Cofre.chamarInt("Cofre.gravar", [
            .texto(account), .bytes(data), .inteiro(protection == .applicationPassword ? 1 : 0),
            .bytes(nil), .booleano(true),
        ])
        switch Cofre.Codigo(rawValue: codigo) {
        case .ok?: return
        case .duplicado?: throw StoreError.unexpected(errSecDuplicateItem)
        case .semBloqueio?: throw StoreError.passcodeNotSet
        case .senha?: throw StoreError.unexpected(errSecParam)
        default: throw StoreError.unexpected(errSecIO)
        }
    }

    public func update(_ data: Data, account: String) throws {
        let codigo = try Cofre.chamarInt("Cofre.gravar", [.texto(account), .bytes(data), .inteiro(0), .bytes(nil), .booleano(false)])
        switch Cofre.Codigo(rawValue: codigo) {
        case .ok?: return
        case .ausente?: throw StoreError.unexpected(errSecItemNotFound)
        default: throw StoreError.unexpected(errSecIO)
        }
    }

    public func delete(_ account: String) throws {
        guard try Cofre.chamarInt("Cofre.apagar", [.texto(account)]) == Cofre.Codigo.ok.rawValue else { throw StoreError.unexpected(errSecIO) }
    }

    public func deleteAll() throws {
        guard try Cofre.chamarInt("Cofre.apagarTudo", []) == Cofre.Codigo.ok.rawValue else { throw StoreError.unexpected(errSecIO) }
    }

    public func exists(_ account: String) -> Bool { probe(account) == .present }

    public func probe(_ account: String) -> ItemState {
        switch (try? Cofre.chamarInt("Cofre.sondar", [.texto(account)])).flatMap(Cofre.Codigo.init(rawValue:)) {
        case .ok?: .present
        case .ausente?: .absent
        default: .unknown
        }
    }

    /// A senha vai para o Kotlin so na proxima operacao, e o contexto a zera na volta.
    public func applicationPasswordContext(_ password: SecureBytes) throws -> LAContext? {
        password.withUnsafeBytes { LAContext(credential: Data($0)) }
    }
}

/// As chaves de hardware de cada slot no Android (o `SecureEnclaveWrapper` do iOS), com as
/// mesmas regras: a do aparelho nunca e trocada em silencio, os slots do PIN so embrulham com a
/// senha, e a `kand.qualquer` nunca embrulha um segredo do tamanho da RK.
public final class KeystoreWrapper: KeyWrapper, @unchecked Sendable {
    public init() {}

    public func createKey(_ slot: WrapSlot) throws {
        // "Nao sei" nunca vira "nao existe": a chave do aparelho nunca e trocada em silencio.
        if slot == .device, probeKey(.device) != .absent { throw EnclaveError.failed("chave do aparelho ja existe") }
        guard slot == .device || slot.usesBiometry else { throw EnclaveError.failed("o slot do PIN pede senha") }
        try criar(slot)
    }

    public func createKey(_ slot: WrapSlot, password: Data) throws {
        guard slot.usesPassword else { throw EnclaveError.failed("senha so nos slots do PIN") }
        // A senha nao entra na criacao: entra em cada embrulho, como AAD que o hardware confere.
        try criar(slot)
    }

    private func criar(_ slot: WrapSlot) throws {
        guard try Cofre.chamarInt("Cofre.criarChave", [.texto(slot.rawValue)]) == Cofre.Codigo.ok.rawValue else {
            throw EnclaveError.unavailable
        }
    }

    public func hasKey(_ slot: WrapSlot) -> Bool { probeKey(slot) == .present }

    public func probeKey(_ slot: WrapSlot) -> ItemState {
        switch (try? Cofre.chamarInt("Cofre.sondarChave", [.texto(slot.rawValue)])).flatMap(Cofre.Codigo.init(rawValue:)) {
        case .ok?: .present
        case .ausente?: .absent
        default: .unknown
        }
    }

    public func deleteKey(_ slot: WrapSlot) {
        Cofre.chamarVoid("Cofre.apagarChave", [.texto(slot.rawValue)])
    }

    public func wrap(_ secret: SecureBytes, slot: WrapSlot) throws -> Data {
        if slot == .hardenedBiometryAny, secret.count <= 32 { throw EnclaveError.failed("kand.qualquer so embrulha o miolo") }
        guard !slot.usesPassword else { throw EnclaveError.failed("o slot do PIN embrulha com a senha") }
        return slot.usesBiometry ? try embrulharHibrido(secret, slot: slot) : try embrulhar(secret, slot: slot)
    }

    public func wrap(_ secret: SecureBytes, slot: WrapSlot, password: Data) throws -> Data {
        guard slot.usesPassword else { throw EnclaveError.failed("senha so nos slots do PIN") }
        return try embrulharPeloPin(secret, slot: slot, password: password)
    }

    /// O slot do aparelho: o AES-GCM e do Keystore, no hardware.
    private func embrulhar(_ secret: SecureBytes, slot: WrapSlot) throws -> Data {
        let (codigo, blob) = try Cofre.chamarSegredo("Cofre.embrulhar", [.texto(slot.rawValue), .segredo(secret), .bytes(nil)])
        guard codigo == .ok, let blob else { throw codigo == .semChave ? EnclaveError.keyMissing : EnclaveError.failed("embrulho") }
        defer { blob.wipe() }
        return blob.withUnsafeBytes { Data($0) }
    }

    public func unwrap(_ blob: Data, slot: WrapSlot, reason: String?) throws -> SecureBytes {
        if slot.usesBiometry { return try desembrulharHibrido(blob, slot: slot, reason: reason) }
        return try abrir(Cofre.chamarSegredo("Cofre.desembrulhar", [.texto(slot.rawValue), .bytes(blob), .bytes(nil), .texto(reason)]), senha: false)
    }

    public func unwrap(_ blob: Data, slot: WrapSlot, password: Data) throws -> SecureBytes {
        if slot.usesPassword, blob.first == Self.versaoDoPin { return try desembrulharPeloPin(blob, slot: slot, password: password) }
        // O formato 1 (a senha so no AAD), dos cofres de teste do emulador: AES-GCM do Keystore.
        return try abrir(Cofre.chamarSegredo("Cofre.desembrulhar", [.texto(slot.rawValue), .bytes(blob), .bytes(password), .texto(nil)]), senha: true)
    }

    private func abrir(_ resposta: (Cofre.Codigo, SecureBytes?), senha: Bool) throws -> SecureBytes {
        if case (.ok, let segredo?) = resposta { return segredo }
        throw Self.erro(resposta.0, senha: senha)
    }

    private static func erro(_ codigo: Cofre.Codigo, senha: Bool) -> EnclaveError {
        switch codigo {
        case .senha: senha ? .wrongPassword : .failed("desembrulho")
        case .semChave: .keyMissing
        case .bloqueado: .locked
        // Cancelar, nao reconhecer e o bloqueio do sistema: "nao desta vez". Quem decide se o
        // cadastro mudou e o RootKeyVault, pelo estado.
        case .cancelado, .indisponivel: .cancelled
        default: .failed("desembrulho")
        }
    }

    public func unwrap(_ blob: Data, slot: WrapSlot, reason: String, watching watch: Data, with watchSlot: WrapSlot) throws -> (SecureBytes, WatchResult) {
        guard slot.usesBiometry, let (chaveCifrada, corpo) = Self.partesHibridas(blob) else { throw EnclaveError.failed("desembrulho") }
        let vigia = Self.partesHibridas(watch)
        let (codigo, resposta) = try Cofre.chamarSegredo("Cofre.abrirChaveVigiando", [
            .texto(slot.rawValue), .bytes(Data(chaveCifrada)), .texto(reason), .texto(watchSlot.rawValue), .bytes(vigia.map { Data($0.0) }),
        ])
        guard codigo == .ok, let resposta else { throw Self.erro(codigo, senha: false) }
        defer { resposta.wipe() }
        // [vigia][chave 32][chave da vigia 32, so se abriu]
        return try resposta.withUnsafeBytes { raw -> (SecureBytes, WatchResult) in
            guard raw.count == 1 + 32 || raw.count == 1 + 64 else { throw EnclaveError.failed("desembrulho") }
            let chave = SymmetricKey(data: UnsafeRawBufferPointer(rebasing: raw[1..<33]))
            guard let segredo = Self.abrirAES(corpo, chave: chave, aad: Self.aad(slot, pin: false)) else {
                throw EnclaveError.failed("desembrulho")
            }
            switch raw[0] {
            case 0:
                guard raw.count == 1 + 64, let vigia else { return (segredo, .unknown) }
                let chaveDaVigia = SymmetricKey(data: UnsafeRawBufferPointer(rebasing: raw[33..<65]))
                guard let conteudo = Self.abrirAES(vigia.1, chave: chaveDaVigia, aad: Self.aad(watchSlot, pin: false)) else {
                    return (segredo, .unknown)
                }
                return (segredo, .opened(conteudo))
            case 1: return (segredo, .gone)
            default: return (segredo, .unknown)
            }
        }
    }

    // MARK: O embrulho dos slots de biometria e do PIN, feito aqui
    //
    // O Kotlin so faz o que o Keystore faz: a RSA que abre a chave AES do embrulho (depois da biometria) e o
    // HMAC da senha do PIN. O AES-GCM e o HKDF ficam aqui, sobre buffers que o nucleo zera: no Kotlin, o
    // SecretKeySpec e a Conscrypt guardavam copias da chave raiz e das chaves do embrulho no heap do Java
    // (auditoria das chaves de 06/11/2026). Os formatos sao os de antes, byte a byte:
    // - biometria: [1][tamanho da chave cifrada, 4 bytes][chave AES cifrada pela RSA][iv 12][cifrado][tag 16]
    // - PIN: [2][sal 16][iv 12][cifrado][tag 16], com a chave = HKDF-SHA256(HMAC do Keystore, sal, info do slot)
    // O AAD e "escalibur-wallet/android/v1/embrulho\0" e o slot; no PIN, mais o byte 2.

    static let versaoHibrida: UInt8 = 1
    static let versaoDoPin: UInt8 = 2

    static func aad(_ slot: WrapSlot, pin: Bool) -> Data {
        var aad = Data("escalibur-wallet/android/v1/embrulho\u{0}\(slot.rawValue)".utf8)
        if pin { aad.append(versaoDoPin) }
        return aad
    }

    /// A chave cifrada e o resto ([iv][cifrado][tag]) de um embrulho de biometria.
    static func partesHibridas(_ blob: Data) -> ([UInt8], ArraySlice<UInt8>)? {
        let bytes = [UInt8](blob)
        guard bytes.count >= 1 + 4 + 12 + 16, bytes[0] == versaoHibrida else { return nil }
        let tamanho = Int(bytes[1]) << 24 | Int(bytes[2]) << 16 | Int(bytes[3]) << 8 | Int(bytes[4])
        guard tamanho > 0, 5 + tamanho + 12 + 16 <= bytes.count else { return nil }
        return (Array(bytes[5..<(5 + tamanho)]), bytes[(5 + tamanho)...])
    }

    /// [iv 12][cifrado][tag 16] em AES-256-GCM. Nil se a tag recusa.
    static func abrirAES(_ corpo: ArraySlice<UInt8>, chave: SymmetricKey, aad: Data) -> SecureBytes? {
        guard corpo.count >= 12 + 16, let nonce = try? AES.GCM.Nonce(data: corpo.prefix(12)) else { return nil }
        let resto = corpo.dropFirst(12)
        guard let caixa = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: resto.dropLast(16), tag: resto.suffix(16)),
              var claro = try? AES.GCM.open(caixa, using: chave, authenticating: aad)
        else { return nil }
        return SecureBytes.consuming(&claro)
    }

    /// [iv 12][cifrado][tag 16], com um iv sorteado.
    static func selarAES(_ segredo: SecureBytes, chave: SymmetricKey, aad: Data) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let selado = try segredo.withUnsafeData { try AES.GCM.seal($0, using: chave, nonce: nonce, authenticating: aad) }
        return Data(nonce) + selado.ciphertext + selado.tag
    }

    /// A chave AES do embrulho do PIN: o HKDF-SHA256 da semente que o HMAC do Keystore tirou da senha.
    static func chaveDoPin(semente: SecureBytes, sal: [UInt8], slot: WrapSlot) -> SymmetricKey {
        let ikm = semente.withUnsafeBytes { SymmetricKey(data: $0) }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm, salt: sal,
            info: Array("escalibur-wallet/android/v2/embrulho\u{0}\(slot.rawValue)".utf8), outputByteCount: 32
        )
    }

    private func embrulharHibrido(_ secret: SecureBytes, slot: WrapSlot) throws -> Data {
        guard let resposta = try Cofre.chamarBytes("Cofre.publica", [.texto(slot.rawValue)]), let codigo = resposta.first else {
            throw EnclaveError.failed("embrulho")
        }
        guard codigo == UInt8(Cofre.Codigo.ok.rawValue) else {
            throw codigo == UInt8(Cofre.Codigo.semChave.rawValue) ? EnclaveError.keyMissing : EnclaveError.failed("embrulho")
        }
        let chave = try SecureBytes.random(count: 32)
        defer { chave.wipe() }
        let chaveCifrada = try RSAOAEP.encrypt(chave, publicKeyDER: [UInt8](resposta.dropFirst()))
        let corpo = try Self.selarAES(secret, chave: chave.withUnsafeBytes { SymmetricKey(data: $0) }, aad: Self.aad(slot, pin: false))
        var blob = Data([Self.versaoHibrida])
        blob += UInt32(chaveCifrada.count).bigEndianByteArray
        blob += chaveCifrada
        blob += corpo
        return blob
    }

    private func desembrulharHibrido(_ blob: Data, slot: WrapSlot, reason: String?) throws -> SecureBytes {
        guard let (chaveCifrada, corpo) = Self.partesHibridas(blob) else { throw EnclaveError.failed("desembrulho") }
        let (codigo, chave) = try Cofre.chamarSegredo("Cofre.abrirChave", [.texto(slot.rawValue), .bytes(Data(chaveCifrada)), .texto(reason)])
        guard codigo == .ok, let chave else { throw Self.erro(codigo, senha: false) }
        defer { chave.wipe() }
        guard chave.count == 32,
              let segredo = Self.abrirAES(corpo, chave: chave.withUnsafeBytes { SymmetricKey(data: $0) }, aad: Self.aad(slot, pin: false))
        else { throw EnclaveError.failed("desembrulho") }
        return segredo
    }

    private func embrulharPeloPin(_ secret: SecureBytes, slot: WrapSlot, password: Data) throws -> Data {
        let sal = try SecureBytes.random(count: 16).withUnsafeBytes { [UInt8]($0) }
        let (codigo, semente) = try Cofre.chamarSegredo("Cofre.semente", [.texto(slot.rawValue), .bytes(password), .booleano(false)])
        guard codigo == .ok, let semente, semente.count == 32 else {
            throw codigo == .semChave ? EnclaveError.keyMissing : EnclaveError.failed("embrulho")
        }
        defer { semente.wipe() }
        let corpo = try Self.selarAES(secret, chave: Self.chaveDoPin(semente: semente, sal: sal, slot: slot), aad: Self.aad(slot, pin: true))
        return Data([Self.versaoDoPin]) + sal + corpo
    }

    private func desembrulharPeloPin(_ blob: Data, slot: WrapSlot, password: Data) throws -> SecureBytes {
        let bytes = [UInt8](blob)
        guard bytes.count >= 1 + 16 + 12 + 16 else { throw EnclaveError.failed("desembrulho") }
        let (codigo, semente) = try Cofre.chamarSegredo("Cofre.semente", [.texto(slot.rawValue), .bytes(password), .booleano(true)])
        guard codigo == .ok, let semente else { throw Self.erro(codigo, senha: true) }
        defer { semente.wipe() }
        guard semente.count == 32 else { throw EnclaveError.failed("desembrulho") }
        // Senha errada da outra chave AES, e a tag recusa.
        guard let segredo = Self.abrirAES(bytes[17...], chave: Self.chaveDoPin(semente: semente, sal: Array(bytes[1..<17]), slot: slot),
                                          aad: Self.aad(slot, pin: true))
        else { throw EnclaveError.wrongPassword }
        return segredo
    }
}
