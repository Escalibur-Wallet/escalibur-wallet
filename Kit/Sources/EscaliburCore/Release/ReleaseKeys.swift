import CryptoKit
import Foundation

/// As chaves que autorizam uma versao do app (docs/seguranca.md, "Versao autorizada"). Ficam
/// compiladas no binario: trocar a lista no GitHub nao muda o que o app instalado aceita, e
/// a Apple nao tem nenhuma delas. Cada uma e P-256 e assina fora do GitHub e da Apple, com a
/// presenca do dono: hoje a do Secure Enclave do Mac do dono; depois, chaves fisicas
/// (YubiKey), que entram aqui numa versao assinada pelas de antes.
public enum ReleaseKeys {
    /// id da chave e a chave publica (rawRepresentation, 64 bytes em hex). A do Mac do dono
    /// se chamava de outro jeito ate o build 10; e o mesmo par de chaves, e a lista do site
    /// assina tambem com o nome antigo, que os builds 7 a 10 conhecem (tools/versoes).
    static let published: [String: String] = [
        "escalibur-mac-1": "fc5a4a28110ef451994dd6ada1acbef69c1ecd6fbc221dd40805daefa394149162577550b0d17f993dfb3b8a202330fe50ee45c7ca9c3f0d70933d406fa3983c",
    ]

    /// Quantas chaves diferentes precisam assinar a lista.
    public static let threshold = 1

    public static let trusted: [String: P256.Signing.PublicKey] = published.compactMapValues { text in
        Hex.decode(text).flatMap { try? P256.Signing.PublicKey(rawRepresentation: $0) }
    }
}
