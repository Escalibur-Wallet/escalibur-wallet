// O que o nucleo usa da Apple, para o build Android: os mesmos nomes e contratos, sobre a
// BoringSSL (Sources/SwiftCrypto, travada em swift-crypto.lock). Nada disto compila no iOS
// nem no macOS, onde o nucleo usa o Security, o os e o Darwin do sistema.
#if !canImport(Darwin)
import CCryptoBoringSSL
import Foundation

/// O gerador do sistema: `RAND_bytes` le o do kernel (`getrandom`). O mesmo contrato do
/// `SecRandomCopyBytes`: zero quando encheu tudo.
let kSecRandomDefault: Int? = nil
let errSecSuccess: Int32 = 0

func SecRandomCopyBytes(_ generator: Int?, _ count: Int, _ bytes: UnsafeMutableRawPointer) -> Int32 {
    guard count > 0 else { return errSecSuccess }
    return CCryptoBoringSSL_RAND_bytes(bytes.assumingMemoryBound(to: UInt8.self), count) == 1 ? errSecSuccess : -1
}

/// O HMAC e o PBKDF2 do CommonCrypto, com os mesmos nomes, constantes e retornos, sobre o
/// HMAC e o PKCS5_PBKDF2_HMAC da BoringSSL.
typealias CCHmacAlgorithm = UInt32
let kCCHmacAlgSHA256: UInt32 = 2
let kCCHmacAlgSHA512: UInt32 = 4

func CCHmac(_ algorithm: CCHmacAlgorithm, _ key: UnsafeRawPointer?, _ keyLength: Int,
            _ data: UnsafeRawPointer?, _ dataLength: Int, _ macOut: UnsafeMutableRawPointer) {
    let digest: OpaquePointer?
    let size: UInt32
    switch algorithm {
    case kCCHmacAlgSHA256: (digest, size) = (CCryptoBoringSSL_EVP_sha256(), 32)
    case kCCHmacAlgSHA512: (digest, size) = (CCryptoBoringSSL_EVP_sha512(), 64)
    default: preconditionFailure("HMAC: algoritmo fora do que o nucleo usa")
    }
    var length: UInt32 = 0
    let ok = CCryptoBoringSSL_HMAC(digest, key, keyLength, data?.assumingMemoryBound(to: UInt8.self), dataLength,
                                   macOut.assumingMemoryBound(to: UInt8.self), &length)
    precondition(ok != nil && length == size, "HMAC falhou")
}

typealias CCPBKDFAlgorithm = UInt32
typealias CCPseudoRandomAlgorithm = UInt32
let kCCPBKDF2: UInt32 = 2
let kCCPRFHmacAlgSHA512: UInt32 = 5
let kCCSuccess: Int32 = 0

func CCKeyDerivationPBKDF(_ algorithm: CCPBKDFAlgorithm, _ password: UnsafePointer<CChar>?, _ passwordLength: Int,
                          _ salt: UnsafePointer<UInt8>?, _ saltLength: Int, _ prf: CCPseudoRandomAlgorithm,
                          _ rounds: UInt32, _ derivedKey: UnsafeMutablePointer<UInt8>, _ derivedKeyLength: Int) -> Int32 {
    guard algorithm == kCCPBKDF2, prf == kCCPRFHmacAlgSHA512 else { return -1 }
    return CCryptoBoringSSL_PKCS5_PBKDF2_HMAC(password, passwordLength, salt, saltLength, rounds,
                                              CCryptoBoringSSL_EVP_sha512(), derivedKeyLength, derivedKey) == 1 ? kCCSuccess : -1
}

/// Zeragem que o otimizador nao remove: `OPENSSL_cleanse`, no lugar do `memset_s` do C11, que o
/// Android nao tem. Publica: o modulo de chaves tambem zera com ela.
@discardableResult
public func memset_s(_ destination: UnsafeMutableRawPointer!, _ maximum: Int, _ value: Int32, _ count: Int) -> Int32 {
    guard let destination, count > 0 else { return 0 }
    precondition(value == 0 && count <= maximum)
    CCryptoBoringSSL_OPENSSL_cleanse(destination, count)
    return 0
}

/// O que as redes usam do CoreFoundation para ler numeros do JSON: saber se o `NSNumber` veio
/// de um booleano ou de um fracionario. Sem o CoreFoundation, pelo tipo que o JSON gravou no
/// numero ("c" e "B" para booleano, "f" e "d" para fracionario); o JSON nunca grava inteiro de
/// 8 bits.
public func CFBooleanGetTypeID() -> UInt { 1 }

public func CFGetTypeID(_ value: AnyObject?) -> UInt {
    guard let number = value as? NSNumber else { return 0 }
    return ["c", "B"].contains(String(cString: number.objCType)) ? CFBooleanGetTypeID() : 2
}

public func CFNumberIsFloatType(_ number: NSNumber) -> Bool {
    ["f", "d"].contains(String(cString: number.objCType))
}

/// A trava de estado do `os` (OSAllocatedUnfairLock), com a mesma interface que o nucleo usa.
public final class OSAllocatedUnfairLock<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    public init(initialState: State) { state = initialState }

    public func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}

/// O registro do `os` (Logger), com a mesma interpolacao (`privacy:`): no Android, nada sai do
/// app.
struct Logger {
    init(subsystem: String, category: String) {}
    func error(_ message: OSLogMessage) {}
    func info(_ message: OSLogMessage) {}
}

struct OSLogPrivacy {
    static let `public` = OSLogPrivacy()
    static let `private` = OSLogPrivacy()
}

struct OSLogMessage: ExpressibleByStringInterpolation {
    struct StringInterpolation: StringInterpolationProtocol {
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) {}
        mutating func appendInterpolation<T>(_ value: T, privacy: OSLogPrivacy = .private) {}
    }
    init(stringLiteral value: String) {}
    init(stringInterpolation: StringInterpolation) {}
}
#endif
