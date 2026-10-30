#if os(Android)
import Foundation
import FoundationNetworking

/// O transporte do HTTPClient no Android.
///
/// O URLSession do Swift SDK para Android fala pela libcurl dele, que aceitava TLS 1.0 e 1.1 e
/// nao tem opcao de TLS minimo (conferido no emulador contra o badssl.com, 20/10/2026). No
/// Android a requisicao sai pelo HttpsURLConnection do proprio sistema, so com TLS 1.2 e 1.3,
/// que o app instala ao abrir (`install`). Sem transporte instalado nenhuma requisicao sai:
/// nao ha volta para a libcurl.
///
/// O HTTPClient continua decidindo tudo o que decide no iOS: hosts, portas, caminhos, tamanho
/// da resposta, recusa de redirecionamento e silencio. O transporte so leva e traz.
public enum AndroidTransport {
    public struct Request: Sendable {
        /// Para cancelar no meio (`HTTPClient.beginQuiet` cancela o que estiver no ar).
        public let id: Int64
        public let method: String
        public let url: String
        public let headers: [String: String]
        public let body: Data?
        /// Conexao e cada leitura.
        public let timeout: TimeInterval
        /// A requisicao inteira.
        public let deadline: TimeInterval
        /// O transporte para de ler aqui: um byte alem do limite do HTTPClient, para ele ver
        /// que passou e recusar.
        public let limit: Int

        public init(id: Int64, method: String, url: String, headers: [String: String], body: Data?, timeout: TimeInterval, deadline: TimeInterval, limit: Int) {
            self.id = id
            self.method = method
            self.url = url
            self.headers = headers
            self.body = body
            self.timeout = timeout
            self.deadline = deadline
            self.limit = limit
        }
    }

    public struct Response: Sendable {
        public let status: Int
        public let headers: [String: String]
        public let body: Data

        public init(status: Int, headers: [String: String], body: Data) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    public struct Functions: Sendable {
        let perform: @Sendable (Request) throws -> Response
        let cancel: @Sendable (Int64) -> Void

        public init(perform: @escaping @Sendable (Request) throws -> Response, cancel: @escaping @Sendable (Int64) -> Void) {
            self.perform = perform
            self.cancel = cancel
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var installed: Functions?
    nonisolated(unsafe) private static var lastID: Int64 = 0

    /// Uma vez, na abertura do app. Uma segunda chamada nao troca o transporte.
    public static func install(_ functions: Functions) {
        lock.withLock { if installed == nil { installed = functions } }
    }

    public static var isInstalled: Bool { lock.withLock { installed != nil } }

    static var current: Functions? { lock.withLock { installed } }

    static func nextID() -> Int64 {
        lock.withLock {
            lastID += 1
            return lastID
        }
    }
}

/// O `URLProtocol` que o HTTPClient usa no Android no lugar do da libcurl. Entrega ao URLSession
/// a resposta inteira de uma vez; o HTTPClient confere status, tamanho e corpo como no iOS.
final class AndroidURLProtocol: URLProtocol {
    private let lock = NSLock()
    private var stopped = false
    private var id: Int64?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let transport = AndroidTransport.current else {
            return finish(.failure(URLError(.notConnectedToInternet)))
        }
        guard let url = request.url else { return finish(.failure(URLError(.badURL))) }
        let id = AndroidTransport.nextID()
        lock.withLock { self.id = id }

        var headers = request.allHTTPHeaderFields ?? [:]
        // O HttpsURLConnection mandaria "Dalvik/... (Linux; Android ...; modelo)": o aparelho
        // fala com os provedores como no iOS, sem entregar versao nem modelo.
        if headers["User-Agent"] == nil { headers["User-Agent"] = HTTPClient.userAgent }
        if headers["Accept-Language"] == nil { headers["Accept-Language"] = "en" }
        let outgoing = AndroidTransport.Request(
            id: id, method: request.httpMethod ?? "GET", url: url.absoluteString, headers: headers,
            body: request.httpBody ?? Self.read(request.httpBodyStream),
            timeout: request.timeoutInterval, deadline: HTTPClient.resourceTimeout,
            limit: HTTPClient.maxResponseBytes + 1
        )
        // O URLProtocol do FoundationNetworking nao e Sendable; este so muda estado sob a trava.
        let this = Unchecked(self)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try transport.perform(outgoing) }
            this.value.finish(result.map { response in
                (HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers), response.body)
            })
        }
    }

    override func stopLoading() {
        let id = lock.withLock { () -> Int64? in
            stopped = true
            return self.id
        }
        if let id { AndroidTransport.current?.cancel(id) }
    }

    /// Depois de `stopLoading` nada mais chega ao URLSession: ele ja fechou a tarefa.
    private func finish(_ result: Result<(HTTPURLResponse?, Data), Error>) {
        guard lock.withLock({ !stopped }) else { return }
        switch result {
        case .success((let response?, let body)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
            client?.urlProtocolDidFinishLoading(self)
        case .success((nil, _)):
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private struct Unchecked: @unchecked Sendable {
        let value: AndroidURLProtocol
        init(_ value: AndroidURLProtocol) { self.value = value }
    }

    /// O corpo de um POST, se o URLSession o passou como fluxo.
    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
#endif
