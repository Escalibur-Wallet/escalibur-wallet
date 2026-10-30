#if !canImport(LocalAuthentication)
import EscaliburCore
import Foundation

// Fora da Apple (o build Android): o que o modulo de chaves usa do iOS e nao existe aqui. O
// chaveiro e o Secure Enclave nao tem equivalente neste arquivo: no Android, o armazenamento e
// as chaves de hardware sao do Keystore, implementados no app (EscaliburAndroid) sobre os
// protocolos `SecretStore` e `KeyWrapper`, com a mesma logica do cofre por cima.

public typealias OSStatus = Int32

/// Os codigos do chaveiro que o armazenamento do Android devolve nos mesmos casos.
public let errSecIO: OSStatus = -36
public let errSecParam: OSStatus = -50
public let errSecAuthFailed: OSStatus = -25293
public let errSecDuplicateItem: OSStatus = -25299
public let errSecItemNotFound: OSStatus = -25300
public let errSecInteractionNotAllowed: OSStatus = -25308

/// No iOS, o contexto que leva a senha de aplicativo (derivada do PIN) ate o chaveiro e o
/// Secure Enclave. Aqui, so isso: a credencial da proxima operacao do armazenamento, que o
/// armazenamento zera na volta (`invalidate`), como o `KeychainStore` solta a dele.
public final class LAContext: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?

    public init(credential: Data) { stored = credential }

    public var credential: Data? { lock.withLock { stored } }

    public func invalidate() {
        lock.withLock {
            if let count = stored?.count, count > 0 { stored?.resetBytes(in: 0..<count) }
            stored = nil
        }
    }
}

/// O que o cofre pergunta ao sistema e que no iOS vem do LocalAuthentication e do kernel. No
/// Android vem do BiometricManager, do Keystore e do sistema, e o app instala ao abrir.
public struct KeyPlatform: Sendable {
    /// A biometria forte (classe 3) do aparelho agora.
    public enum Biometry: Sendable { case ready, notEnrolled, unavailable, lockedOut }

    public let biometry: @Sendable () -> Biometry
    /// Muda quando o cadastro de biometria muda (digital ou rosto novo, ou todos tirados), como o
    /// `evaluatedPolicyDomainState` do iOS. Nil sem biometria cadastrada.
    public let biometryState: @Sendable () -> Data?
    /// 16 bytes que so mudam quando o aparelho reinicia.
    public let bootIdentity: @Sendable () -> [UInt8]?

    public init(
        biometry: @escaping @Sendable () -> Biometry,
        biometryState: @escaping @Sendable () -> Data?,
        bootIdentity: @escaping @Sendable () -> [UInt8]?
    ) {
        self.biometry = biometry
        self.biometryState = biometryState
        self.bootIdentity = bootIdentity
    }

    /// Antes de o app instalar: sem biometria, e o boot pelo `boot_id` do kernel.
    static let none = KeyPlatform(biometry: { .unavailable }, biometryState: { nil }, bootIdentity: { kernelBootID() })

    /// O `boot_id` do Linux: um UUID novo a cada boot. Sem ele, o boot fica desconhecido e o PIN
    /// e pedido sempre (nunca o contrario).
    public static func kernelBootID() -> [UInt8]? {
        guard let text = try? String(contentsOfFile: "/proc/sys/kernel/random/boot_id", encoding: .utf8),
              let uuid = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return withUnsafeBytes(of: uuid.uuid) { Array($0) }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var installed: KeyPlatform?

    /// Uma vez, na abertura do app.
    public static func install(_ platform: KeyPlatform) {
        lock.withLock { if installed == nil { installed = platform } }
    }

    public static var current: KeyPlatform { lock.withLock { installed ?? .none } }
}
#endif
