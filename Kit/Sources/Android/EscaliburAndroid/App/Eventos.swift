import CJNI
import Foundation

/// O que o nucleo avisa a interface sem ela perguntar (o saldo de cada rede que chega): um nome e
/// um JSON, entregues a Eventos.kt, que repassa a quem estiver olhando.
enum Eventos {
    static func emitir(_ nome: String, _ json: Data) {
        guard let metodo = try? Java.metodo("Eventos.emitir") else { return }
        try? Java.naMaquina { java in
            guard let texto = java.string(String(decoding: json, as: UTF8.self)), let chave = java.string(nome) else { return }
            defer { java.deleteLocal(texto); java.deleteLocal(chave) }
            var argumentos = [jvalue](repeating: jvalue(), count: 2)
            argumentos[0].l = chave
            argumentos[1].l = texto
            java.callStaticVoid(metodo, argumentos)
        }
    }
}
