import CJNI
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
        let (codigo, conteudo) = try Cofre.chamarSegredo("Cofre.ler", [.texto(account), .bytes(context?.credential)])
        switch codigo {
        case .ok:
            guard let conteudo else { throw StoreError.unexpected(errSecIO) }
            defer { conteudo.wipe() }
            return conteudo.withUnsafeBytes { Data($0) }
        case .ausente: return nil
        case .senha: throw StoreError.authenticationFailed
        default: throw StoreError.unexpected(errSecIO)
        }
    }

    public func add(_ data: Data, account: String, protection: ItemProtection, context: LAContext?) throws {
        defer { context?.invalidate() }
        let codigo = try Cofre.chamarInt("Cofre.gravar", [
            .texto(account), .bytes(data), .inteiro(protection == .applicationPassword ? 1 : 0),
            .bytes(protection == .applicationPassword ? context?.credential : nil), .booleano(true),
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
        if slot == .device, hasKey(.device) { throw EnclaveError.failed("chave do aparelho ja existe") }
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
        return try embrulhar(secret, slot: slot, password: nil)
    }

    public func wrap(_ secret: SecureBytes, slot: WrapSlot, password: Data) throws -> Data {
        guard slot.usesPassword else { throw EnclaveError.failed("senha so nos slots do PIN") }
        return try embrulhar(secret, slot: slot, password: password)
    }

    private func embrulhar(_ secret: SecureBytes, slot: WrapSlot, password: Data?) throws -> Data {
        let (codigo, blob) = try Cofre.chamarSegredo("Cofre.embrulhar", [.texto(slot.rawValue), .segredo(secret), .bytes(password)])
        guard codigo == .ok, let blob else { throw codigo == .semChave ? EnclaveError.keyMissing : EnclaveError.failed("embrulho") }
        defer { blob.wipe() }
        return blob.withUnsafeBytes { Data($0) }
    }

    public func unwrap(_ blob: Data, slot: WrapSlot, reason: String?) throws -> SecureBytes {
        try abrir(Cofre.chamarSegredo("Cofre.desembrulhar", [.texto(slot.rawValue), .bytes(blob), .bytes(nil), .texto(reason)]), senha: false)
    }

    public func unwrap(_ blob: Data, slot: WrapSlot, password: Data) throws -> SecureBytes {
        try abrir(Cofre.chamarSegredo("Cofre.desembrulhar", [.texto(slot.rawValue), .bytes(blob), .bytes(password), .texto(nil)]), senha: true)
    }

    private func abrir(_ resposta: (Cofre.Codigo, SecureBytes?), senha: Bool) throws -> SecureBytes {
        switch resposta {
        case (.ok, let segredo?): return segredo
        case (.senha, _): throw senha ? EnclaveError.wrongPassword : EnclaveError.failed("desembrulho")
        case (.semChave, _): throw EnclaveError.keyMissing
        // Cancelar, nao reconhecer e o bloqueio do sistema: "nao desta vez". Quem decide se o
        // cadastro mudou e o RootKeyVault, pelo estado.
        case (.cancelado, _), (.indisponivel, _): throw EnclaveError.cancelled
        default: throw EnclaveError.failed("desembrulho")
        }
    }

    public func unwrap(_ blob: Data, slot: WrapSlot, reason: String, watching watch: Data, with watchSlot: WrapSlot) throws -> (SecureBytes, WatchResult) {
        let (codigo, corpo) = try Cofre.chamarSegredo("Cofre.desembrulharVigiando", [
            .texto(slot.rawValue), .bytes(blob), .texto(reason), .texto(watchSlot.rawValue), .bytes(watch),
        ])
        guard codigo == .ok, let corpo else { return (try abrir((codigo, nil), senha: false), .unknown) }
        defer { corpo.wipe() }
        // [vigia][tamanho do segredo em 4 bytes][segredo][conteudo da vigia]
        return try corpo.withUnsafeBytes { raw -> (SecureBytes, WatchResult) in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes.count >= 5 else { throw EnclaveError.failed("desembrulho") }
            let tamanho = Int(bytes[1]) << 24 | Int(bytes[2]) << 16 | Int(bytes[3]) << 8 | Int(bytes[4])
            guard tamanho > 0, 5 + tamanho <= bytes.count else { throw EnclaveError.failed("desembrulho") }
            let segredo = SecureBytes(capacity: tamanho)
            segredo.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[5..<(5 + tamanho)]))
            switch bytes[0] {
            case 0:
                let vigia = SecureBytes(capacity: max(bytes.count - 5 - tamanho, 1))
                vigia.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[(5 + tamanho)...]))
                return (segredo, .opened(vigia))
            case 1: return (segredo, .gone)
            default: return (segredo, .unknown)
            }
        }
    }
}
