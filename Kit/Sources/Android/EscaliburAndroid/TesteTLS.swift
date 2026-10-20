#if DEBUG
import EscaliburNetwork
import Foundation

/// So no build de depuracao: confere, no aparelho, o que o transporte de rede do Android faz com
/// certificado ruim e TLS antigo. Fala direto com o transporte, sem o HTTPClient, porque estes
/// hosts estao fora da lista do app de proposito.
enum TesteTLS {
    static let casos: [(String, String)] = [
        ("valido", "https://badssl.com/"),
        ("expirado", "https://expired.badssl.com/"),
        ("autoassinado", "https://self-signed.badssl.com/"),
        ("outro dominio", "https://wrong.host.badssl.com/"),
        ("raiz nao confiavel", "https://untrusted-root.badssl.com/"),
        ("revogado", "https://revoked.badssl.com/"),
        ("TLS 1.0", "https://tls-v1-0.badssl.com:1010/"),
        ("TLS 1.1", "https://tls-v1-1.badssl.com:1011/"),
        ("TLS 1.2", "https://tls-v1-2.badssl.com:1012/"),
        ("http", "http://http.badssl.com/"),
    ]

    static func rodar() async -> [String: String] {
        var resultado: [String: String] = [:]
        for (indice, (nome, endereco)) in casos.enumerated() {
            let pedido = AndroidTransport.Request(
                id: -Int64(indice + 1), method: "GET", url: endereco, headers: ["User-Agent": "EscaliburWallet"],
                body: nil, timeout: 10, deadline: 30, limit: 1024 * 1024
            )
            do {
                let resposta = try Rede.executar(pedido)
                resultado[nome] = "ABRIU (HTTP \(resposta.status))"
            } catch {
                resultado[nome] = "recusado: \((error as? URLError)?.code.rawValue ?? 0)"
            }
        }
        return resultado
    }
}
#endif
