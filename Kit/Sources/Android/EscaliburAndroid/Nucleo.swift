import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburNetwork
import Foundation

/// Os metodos que o app Android chama pela ponte. Cada um recebe e devolve JSON; nenhum
/// recebe nem devolve segredo.
enum Nucleo {
    struct Falha: Error, Encodable {
        let erro: String
    }

    static func chamar(_ metodo: String, _ entrada: Data) throws -> Data {
        switch metodo {
        case "iniciar":
            // A rede do nucleo ja foi ligada ao transporte do Android no JNI_OnLoad.
            return try json(["rede": AndroidTransport.isInstalled])
        case "versao":
            return try json(Versao(nucleo: "1.0.0", redes: Chain.all.count))
        case "redes":
            return try json(Chain.all.map(RedeResumo.init))
        case "saldo":
            let pedido = try JSONDecoder().decode(PedidoSaldo.self, from: entrada)
            guard let rede = Chain.all.first(where: { $0.id == pedido.rede }) else { throw Falha(erro: "rede desconhecida: \(pedido.rede)") }
            let saldo = try esperar { try await BalanceService.shared.balance(chain: rede, addresses: pedido.enderecos) }
            return try json(saldo)
        #if DEBUG
        case "tls.teste":
            // So no build de depuracao: o transporte de rede do Android contra os servidores de
            // teste do badssl.com. Cada um tem de ser recusado, menos o "valido".
            return try json(esperar { await TesteTLS.rodar() })
        #endif
        default:
            throw Falha(erro: "metodo desconhecido: \(metodo)")
        }
    }

    static func erro(_ error: Error) -> Data {
        let texto = (error as? Falha)?.erro ?? String(describing: error)
        return (try? json(["erro": texto])) ?? Data(#"{"erro":"falha"}"#.utf8)
    }

    static func json<T: Encodable>(_ valor: T) throws -> Data {
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.sortedKeys]
        return try codificador.encode(valor)
    }

    struct Versao: Encodable { let nucleo: String; let redes: Int }

    struct RedeResumo: Encodable {
        let id: String, nome: String, familia: String, simbolo: String
        init(_ chain: Chain) {
            id = chain.id
            nome = chain.name
            familia = chain.family.rawValue
            simbolo = chain.nativeSymbol
        }
    }

    struct PedidoSaldo: Decodable { let rede: String; let enderecos: [String] }
}
