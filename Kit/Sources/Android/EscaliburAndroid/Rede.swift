import CJNI
import EscaliburNetwork
import Foundation

/// A rede do nucleo no Android: o HttpsURLConnection do sistema, pela classe Kotlin
/// app.escalibur.wallet.nucleo.Rede, so com TLS 1.2 e 1.3 (AndroidTransport, em
/// EscaliburNetwork, diz por que nao a libcurl do Swift SDK).
///
/// A ligacao com a classe e feita no JNI_OnLoad, na thread do Java que carregou a biblioteca:
/// so ela enxerga as classes do app. As threads do nucleo que vao a rede nao sao do Java e se
/// prendem a maquina virtual a cada requisicao.
enum Rede {
    private struct Ligacao: @unchecked Sendable {
        let vm: UnsafeMutablePointer<JavaVM?>
        let classe: jclass
        let classeString: jclass
        let requisitar: jmethodID
        let cancelar: jmethodID
    }

    /// Gravada uma vez no JNI_OnLoad, antes de a biblioteca voltar ao Java: toda leitura vem depois.
    nonisolated(unsafe) private static var ligacao: Ligacao?

    /// Os codigos negativos que o Kotlin devolve no lugar do status HTTP.
    enum Falha: Int32 {
        case semRede = -1, prazo = -2, tls = -3, cancelado = -4, recusado = -5, outra = -6, semConexao = -7

        var erro: URLError {
            switch self {
            case .semRede: URLError(.notConnectedToInternet)
            case .prazo: URLError(.timedOut)
            case .tls: URLError(.secureConnectionFailed)
            case .cancelado: URLError(.cancelled)
            case .recusado: URLError(.unsupportedURL)
            case .outra: URLError(.badServerResponse)
            case .semConexao: URLError(.cannotConnectToHost)
            }
        }
    }

    static func prender(_ vm: UnsafeMutablePointer<JavaVM?>, _ java: JavaEnv) -> Bool {
        guard let classe = java.globalClass("app/escalibur/wallet/nucleo/Rede"),
              let classeString = java.globalClass("java/lang/String"),
              let requisitar = java.staticMethod(classe, "requisitar", "(JLjava/lang/String;Ljava/lang/String;[Ljava/lang/String;[BIII)[B"),
              let cancelar = java.staticMethod(classe, "cancelar", "(J)V")
        else { return false }
        ligacao = Ligacao(vm: vm, classe: classe, classeString: classeString, requisitar: requisitar, cancelar: cancelar)
        AndroidTransport.install(.init(perform: Rede.executar, cancel: Rede.cancelar))
        return true
    }

    @Sendable static func executar(_ pedido: AndroidTransport.Request) throws -> AndroidTransport.Response {
        guard let ligacao else { throw URLError(.notConnectedToInternet) }
        let bruto = try naMaquina(ligacao.vm) { java -> Data? in
            let cabecalhos = pedido.headers.flatMap { [$0.key, $0.value] }
            guard let metodo = java.string(pedido.method), let endereco = java.string(pedido.url),
                  let lista = java.stringArray(cabecalhos, classe: ligacao.classeString)
            else { return nil }
            let corpo = pedido.body.flatMap { java.byteArray($0) }
            defer { [metodo, endereco, lista, corpo].forEach(java.deleteLocal) }
            var argumentos = [jvalue](repeating: jvalue(), count: 8)
            argumentos[0].j = pedido.id
            argumentos[1].l = metodo
            argumentos[2].l = endereco
            argumentos[3].l = lista
            argumentos[4].l = corpo
            argumentos[5].i = milissegundos(pedido.timeout)
            argumentos[6].i = milissegundos(pedido.deadline)
            argumentos[7].i = jint(clamping: pedido.limit)
            let resultado = java.callStatic(ligacao.classe, ligacao.requisitar, argumentos)
            defer { java.deleteLocal(resultado) }
            return java.bytes(resultado)
        }
        guard let bruto else { throw URLError(.badServerResponse) }
        return try decodificar(bruto)
    }

    @Sendable static func cancelar(_ id: Int64) {
        guard let ligacao else { return }
        try? naMaquina(ligacao.vm) { java in
            var argumento = jvalue()
            argumento.j = id
            java.callStaticVoid(ligacao.classe, ligacao.cancelar, [argumento])
        }
    }

    /// O formato do Kotlin: o status (ou o codigo da falha) e o tamanho dos cabecalhos em 4 bytes
    /// cada, big-endian; os cabecalhos como "nome\0valor\0"; e o corpo.
    static func decodificar(_ bruto: Data) throws -> AndroidTransport.Response {
        let bytes = [UInt8](bruto)
        guard bytes.count >= 8 else { throw URLError(.badServerResponse) }
        func inteiro(_ inicio: Int) -> Int32 {
            Int32(bitPattern: bytes[inicio..<inicio + 4].reduce(0) { $0 << 8 | UInt32($1) })
        }
        let status = inteiro(0)
        let tamanho = Int(inteiro(4))
        if status < 0 { throw (Falha(rawValue: status) ?? .outra).erro }
        guard tamanho >= 0, 8 + tamanho <= bytes.count else { throw URLError(.badServerResponse) }
        let partes = bytes[8..<8 + tamanho].split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        var cabecalhos: [String: String] = [:]
        var indice = 0
        while indice + 1 < partes.count {
            cabecalhos[partes[indice]] = partes[indice + 1]
            indice += 2
        }
        return AndroidTransport.Response(status: Int(status), headers: cabecalhos, body: Data(bytes[(8 + tamanho)...]))
    }

    private static func milissegundos(_ segundos: TimeInterval) -> jint {
        jint(clamping: Int((max(segundos, 1) * 1000).rounded()))
    }

    /// Prende a thread a maquina virtual do Java pelo tempo da chamada (se ainda nao estava).
    private static func naMaquina<T>(_ vm: UnsafeMutablePointer<JavaVM?>, _ corpo: (JavaEnv) throws -> T) throws -> T {
        let interface = vm.pointee!.pointee
        var bruto: UnsafeMutableRawPointer?
        if interface.GetEnv(vm, &bruto, jint(JNI_VERSION_1_6)) == JNI_OK, let bruto {
            return try corpo(JavaEnv(env: bruto.assumingMemoryBound(to: JNIEnv?.self)))
        }
        var env: UnsafeMutablePointer<JNIEnv?>?
        guard interface.AttachCurrentThread(vm, &env, nil) == JNI_OK, let env else { throw URLError(.notConnectedToInternet) }
        defer { _ = interface.DetachCurrentThread(vm) }
        return try corpo(JavaEnv(env: env))
    }
}
