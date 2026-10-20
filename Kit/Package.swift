// swift-tools-version: 6.0
//
// O nucleo da Escalibur Wallet.
//
// Quatro modulos Swift, com fronteiras verificadas por script (tools/verificar.sh):
//
//   EscaliburCore     primitivas: buffer seguro, hashes, curvas, Argon2id, BIP-39,
//                     codificacoes e o envelope .esclbr compartilhado com o Escalibur.
//   EscaliburChains   as redes: enderecos, transacoes, validacao do que se assina.
//                     Puro: sem rede e sem chave privada. Diz O QUE assinar.
//   EscaliburKeys     chaveiro, Secure Enclave, derivacao privada e o assinador, que
//                     so aceita um plano validado por EscaliburChains.
//   EscaliburNetwork  provedores, RPC, precos, cotacoes. Nunca ve seed, chave, PIN
//                     ou senha, e nunca importa EscaliburKeys.
//   EscaliburEngines  os motores de envio, troca e historico de cada rede: juntam o
//                     leitor (Network) e o planejador (Chains). Nao depende do modulo de
//                     chaves: nao enxerga chaveiro, Secure Enclave, cofre nem assinador.
//
// As duas bibliotecas em C sao compiladas do fonte, dentro do repositorio, e
// travadas por digesto (secp256k1.lock, argon2.lock). Nenhum pacote remoto.
import PackageDescription

import class Foundation.ProcessInfo

/// Onde o CryptoKit nao existe: o build Android (e o Linux, para conferir).
let foraDaApple: [Platform] = [.android, .linux]

/// As opcoes com que a propria swift-crypto se compila (o Package.swift dela, versao 5.0.1).
let swiftCryptoSettings: [SwiftSetting] = [
    .define("CRYPTO_IN_SWIFTPM"),
    .enableExperimentalFeature("Lifetimes"),
    .enableExperimentalFeature("SourceWarningControl"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "EscaliburKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EscaliburCore", targets: ["EscaliburCore"]),
        .library(name: "EscaliburChains", targets: ["EscaliburChains"]),
        .library(name: "EscaliburKeys", targets: ["EscaliburKeys"]),
        .library(name: "EscaliburNetwork", targets: ["EscaliburNetwork"]),
        .library(name: "EscaliburEngines", targets: ["EscaliburEngines"]),
    ],
    targets: [
        .target(
            name: "CSecp256k1",
            path: "Sources/CSecp256k1",
            exclude: ["upstream/COPYING"],
            sources: [
                "upstream/src/secp256k1.c",
                "upstream/src/precomputed_ecmult.c",
                "upstream/src/precomputed_ecmult_gen.c",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("ENABLE_MODULE_RECOVERY", to: "1"),
                .define("ENABLE_MODULE_EXTRAKEYS", to: "1"),
                .define("ENABLE_MODULE_SCHNORRSIG", to: "1"),
                .define("ECMULT_WINDOW_SIZE", to: "15"),
                .define("COMB_BLOCKS", to: "43"),
                .define("COMB_TEETH", to: "6"),
                .headerSearchPath("upstream"),
                .headerSearchPath("upstream/src"),
            ]
        ),
        .target(
            name: "CArgon2",
            path: "Sources/CArgon2",
            exclude: ["LICENSE.txt"],
            // escalibur_blake2b.c nao e do Argon2: so expoe o BLAKE2b de referencia ao Swift.
            sources: ["argon2.c", "core.c", "encoding.c", "ref.c", "thread.c", "blake2/blake2b.c", "escalibur_blake2b.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        // A swift-crypto da Apple (Sources/SwiftCrypto, travada por digesto em swift-crypto.lock),
        // so fora das plataformas Apple: o mesmo CryptoKit, sobre a BoringSSL, para o build
        // Android. No iOS e no macOS o nucleo usa o CryptoKit do sistema, e nada disto compila.
        .target(
            name: "CCryptoBoringSSL",
            path: "Sources/SwiftCrypto/CCryptoBoringSSL",
            exclude: ["hash.txt", "CMakeLists.txt", "PrivacyInfo.xcprivacy",
                      "crypto/bio/connect.cc", "crypto/bio/socket_helper.cc", "crypto/bio/socket.cc"]
        ),
        .target(
            name: "CXKCP",
            path: "Sources/SwiftCrypto/CXKCP",
            exclude: ["CMakeLists.txt", "PrivacyInfo.xcprivacy", "vendored-sources.txt"],
            cSettings: [
                .define("XKCP_has_KeccakP1600"),
                .headerSearchPath("include"), .headerSearchPath("high"), .headerSearchPath("low"),
                .headerSearchPath("low/KeccakP-1600"), .headerSearchPath("low/common"), .headerSearchPath("common"),
            ]
        ),
        .target(
            name: "CXKCPShims",
            dependencies: ["CXKCP"],
            path: "Sources/SwiftCrypto/CXKCPShims",
            exclude: ["CMakeLists.txt", "PrivacyInfo.xcprivacy"]
        ),
        .target(
            name: "CryptoBoringWrapper",
            dependencies: ["CCryptoBoringSSL"],
            path: "Sources/SwiftCrypto/CryptoBoringWrapper",
            exclude: ["CMakeLists.txt", "PrivacyInfo.xcprivacy"],
            swiftSettings: swiftCryptoSettings
        ),
        .target(
            name: "Crypto",
            dependencies: [
                .target(name: "CCryptoBoringSSL", condition: .when(platforms: foraDaApple)),
                .target(name: "CryptoBoringWrapper", condition: .when(platforms: foraDaApple)),
                .target(name: "CXKCP", condition: .when(platforms: foraDaApple)),
                .target(name: "CXKCPShims", condition: .when(platforms: foraDaApple)),
            ],
            path: "Sources/SwiftCrypto/Crypto",
            exclude: ["vendored-sources.txt", "CMakeLists.txt", "PrivacyInfo.xcprivacy",
                      "Signatures/BoringSSL/MLDSA_boring.swift.gyb", "KEM/BoringSSL/MLKEM_boring.swift.gyb"],
            swiftSettings: swiftCryptoSettings
        ),
        .target(
            name: "EscaliburCore",
            dependencies: [
                "CSecp256k1", "CArgon2",
                .target(name: "Crypto", condition: .when(platforms: foraDaApple)),
                .target(name: "CCryptoBoringSSL", condition: .when(platforms: foraDaApple)),
            ],
            path: "Sources/EscaliburCore",
            resources: [.copy("Resources/Wordlists"), .copy("Resources/Forca")]
        ),
        .target(
            name: "EscaliburChains",
            dependencies: ["EscaliburCore"],
            path: "Sources/EscaliburChains"
        ),
        .target(
            name: "EscaliburKeys",
            dependencies: ["EscaliburCore", "EscaliburChains"],
            path: "Sources/EscaliburKeys"
        ),
        .target(
            name: "EscaliburNetwork",
            dependencies: ["EscaliburCore", "EscaliburChains", .target(name: "Crypto", condition: .when(platforms: foraDaApple))],
            path: "Sources/EscaliburNetwork"
        ),
        .target(
            name: "EscaliburEngines",
            dependencies: ["EscaliburCore", "EscaliburChains", "EscaliburNetwork"],
            path: "Sources/EscaliburEngines"
        ),
        .testTarget(
            name: "EscaliburCoreTests",
            dependencies: ["EscaliburCore", .target(name: "Crypto", condition: .when(platforms: foraDaApple))],
            path: "Tests/EscaliburCoreTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "EscaliburChainsTests",
            dependencies: ["EscaliburChains", .target(name: "Crypto", condition: .when(platforms: foraDaApple))],
            path: "Tests/EscaliburChainsTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "EscaliburKeysTests",
            dependencies: ["EscaliburKeys"],
            path: "Tests/EscaliburKeysTests"
        ),
        .testTarget(
            name: "EscaliburNetworkTests",
            dependencies: ["EscaliburNetwork", .target(name: "Crypto", condition: .when(platforms: foraDaApple))],
            path: "Tests/EscaliburNetworkTests",
            resources: [.copy("Fixtures"), .copy("FixturesB"), .copy("FixturesSolana")]
        ),
        .testTarget(
            name: "EscaliburEnginesTests",
            dependencies: ["EscaliburEngines", "EscaliburKeys"],
            path: "Tests/EscaliburEnginesTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    // A BoringSSL tem arquivos C++.
    cxxLanguageStandard: .cxx17
)

// Build Android (ESCALIBUR_ANDROID=1): sem o modulo de chaves, que usa o Secure Enclave, o
// chaveiro e o Face ID da Apple e e reescrito no app Android sobre o Keystore, e sem os testes
// que dependem dele.
if ProcessInfo.processInfo.environment["ESCALIBUR_ANDROID"] != nil {
    let soDaApple: Set<String> = ["EscaliburKeys", "EscaliburKeysTests", "EscaliburEnginesTests"]
    package.targets.removeAll { soDaApple.contains($0.name) }
    package.products.removeAll { $0.name == "EscaliburKeys" }
}
