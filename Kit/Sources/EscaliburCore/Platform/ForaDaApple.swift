// O que o nucleo usa da Apple, para o build Android: os mesmos nomes e contratos, sobre a
// BoringSSL (Sources/SwiftCrypto, travada em swift-crypto.lock). Nada disto compila no iOS
// nem no macOS, onde o nucleo usa o Security, o os e o Darwin do sistema.
#if !canImport(Darwin)
#if canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif
import CCryptoBoringSSL
import Foundation

/// O gerador do sistema: o `RAND_bytes` da BoringSSL, misturado por XOR com o `getrandom(2)` do kernel, lido aqui direto.
/// Basta um dos dois ser bom para o sorteio ser bom: um modo de build da BoringSSL que deixasse o `RAND_bytes`
/// deterministico (o de fuzzing, por um ajuste do C que nenhuma conferencia viu) nao deixa a frase previsivel (decima
/// terceira passada da auditoria de 03/11/2026). O mesmo contrato do `SecRandomCopyBytes`: zero quando encheu tudo, e
/// nada sai quando uma das duas fontes falha.
let kSecRandomDefault: Int? = nil
let errSecSuccess: Int32 = 0

func SecRandomCopyBytes(_ generator: Int?, _ count: Int, _ bytes: UnsafeMutableRawPointer) -> Int32 {
    guard count > 0 else { return errSecSuccess }
    let saida = bytes.assumingMemoryBound(to: UInt8.self)
    guard CCryptoBoringSSL_RAND_bytes(saida, count) == 1 else {
        CCryptoBoringSSL_OPENSSL_cleanse(bytes, count)
        return -1
    }
    // A metade do kernel direto na regiao presa na RAM e fora do core dump: no caso que a mistura defende (o RAND_bytes
    // deterministico), ela e o sorteio inteiro (revisao da decima terceira passada).
    let kernel = SecureBytes(capacity: count)
    defer { kernel.wipe() }
    var lido = false
    kernel.fill(count: count) { regiao in
        let base = regiao.assumingMemoryBound(to: UInt8.self)
        var feito = 0
        while feito < count {
            // Sem flag: espera o gerador do kernel estar pronto, e nunca devolve menos que o pedido sem dizer.
            let n = getrandom(base + feito, count - feito, 0)
            if n > 0 {
                feito += n
            } else if n < 0, errno == EINTR {
                continue
            } else {
                return
            }
        }
        lido = true
    }
    guard lido else {
        CCryptoBoringSSL_OPENSSL_cleanse(bytes, count)
        return -1
    }
    kernel.withUnsafeBytes { metade in for indice in 0..<count { saida[indice] ^= metade[indice] } }
    return errSecSuccess
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
