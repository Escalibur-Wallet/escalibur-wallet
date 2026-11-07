// A lista assinada de versoes da Escalibur Wallet (docs/seguranca.md, "Versao autorizada").
//
//   swift tools/versoes/versoes.swift criar-chave <id>
//       cria a chave de assinatura no Secure Enclave deste Mac, presa a ele e ao Touch ID
//       (ou a senha do Mac) a cada assinatura; guarda so a referencia, em ~/.escalibur, e
//       imprime a chave publica para ReleaseKeys.swift
//   swift tools/versoes/versoes.swift autorizar <versao> <build> <id>
//       confere a lista de site/versoes.json, acrescenta a versao e assina de novo (pede o
//       Touch ID)
//   swift tools/versoes/versoes.swift liberar <versao> <build> <id>
//       depois de a Apple publicar o build do dono, com o build aprovado que o App Store Connect
//       mostra (tem de ser um dos autorizados da versao; docs/release.md): marca
//       a versao como liberada, e so entao a tela de atualizar do app empurra para ela. Confere
//       antes, na App Store, que a versao no ar e essa. Assina de novo (pede o Touch ID)
//   swift tools/versoes/versoes.swift obrigatoria <minima|-> <versoes|-> <id>
//       a atualizacao obrigatoria: quem esta abaixo de <minima>, ou numa das <versoes> (separadas
//       por virgula), perde o "Vou atualizar depois" no app. "-" nos dois tira a obrigacao. Assina
//       de novo (pede o Touch ID)
//   swift tools/versoes/versoes.swift liberar-android <build|-> <id>
//       o Android: depois de o lancamento do build chegar a 100% na producao da Play (a ferramenta
//       confere pela API da Play, com a conta de servico do tools/android/play.py, e que o pacote na
//       Play e o que este Mac enviou), marca o build como o liberado, e so entao a tela de atualizar
//       do app Android empurra para ele. "-" tira a liberacao (incidente). Assina de novo (pede o Touch ID)
//   swift tools/versoes/versoes.swift obrigatoria-android <build|-> <id>
//       a atualizacao obrigatoria do Android: os builds abaixo de <build> perdem o "Vou atualizar
//       depois". "-" tira. Assina de novo (pede o Touch ID)
//   swift tools/versoes/versoes.swift conferir
//       confere as assinaturas de site/versoes.json contra as chaves e o limiar de
//       ReleaseKeys.swift, e que a lista do app tem o mesmo texto
//   swift tools/versoes/versoes.swift copiar
//       escreve de novo as duas listas a partir de site/versoes.json, sem assinar (depois de
//       renomear uma chave)
//   swift tools/versoes/versoes.swift conferir-app <caminho do .app>
//       confere, no app pronto, que a lista que vai dentro dele confere e autoriza a versao e
//       o build do Info.plist dele
//
// A chave privada nunca sai do chip: o arquivo em ~/.escalibur so serve neste Mac, e cada
// assinatura pede a presenca do dono. Nada disto passa pelo GitHub nem pela Apple.
import CryptoKit
import Foundation
import LocalAuthentication
import Security

let raiz = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let arquivo = raiz.appendingPathComponent("site/versoes.json")
/// A lista que vai dentro do app: o mesmo texto assinado, so com as assinaturas das chaves de
/// ReleaseKeys.swift.
let arquivoApp = raiz.appendingPathComponent("App/EscaliburWallet/Resources/Versoes/versoes.json")
/// Nomes antigos de uma chave confiada: o mesmo par de chaves, com o nome que os builds de
/// antes conhecem. A assinatura vale so para o texto, entao a lista do site levaria a mesma
/// assinatura sob os dois nomes; a do app, so sob o nome de hoje. Vazio desde 23/10/2026: o
/// nome antigo da chave do Mac saiu da lista publica (os builds 7 a 10 do TestFlight deixam
/// de conferir a lista do site).
let nomesAntigos: [String: String] = [:]
let pasta = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".escalibur")
let app = "app.escalibur.wallet"

func sair(_ texto: String) -> Never {
    FileHandle.standardError.write(Data((texto + "\n").utf8))
    exit(1)
}

func hex(_ dados: Data) -> String { dados.map { String(format: "%02x", $0) }.joined() }

struct Envelope: Codable { var manifesto: String; var assinaturas: [Assinatura] }
struct Assinatura: Codable { let chave: String; let p256: String }
struct Versao: Codable { let versao: String; var builds: [String]; let publicada: String; var liberada: String? }
/// Opcional no formato 1: sem obrigacao, a chave nem aparece, e o texto assinado fica como o de antes.
struct Obrigatoria: Codable { var minima: String?; var versoes: [String]? }
/// O build do Android liberado (`ReleaseManifest.Android`), opcional como a obrigacao: o dia, o minSdk dele e a regra.
struct Android: Codable { var build: String; var liberada: String; var sdk: Int?; var minimo: String? }
struct Manifesto: Codable {
    let formato: Int; let app: String; var emitido: String; var obrigatoria: Obrigatoria?; var android: Android?; var versoes: [Versao]
}

func ler() -> (Envelope, Manifesto)? {
    guard let dados = try? Data(contentsOf: arquivo) else { return nil }
    guard let envelope = try? JSONDecoder().decode(Envelope.self, from: dados),
          let manifesto = try? JSONDecoder().decode(Manifesto.self, from: Data(envelope.manifesto.utf8)) else { sair("site/versoes.json ilegivel") }
    return (envelope, manifesto)
}

/// As chaves e o limiar compilados no app (ReleaseKeys.swift): o que o app instalado aceita.
func confiadas() -> (chaves: [String: P256.Signing.PublicKey], limiar: Int) {
    let fonte = (try? String(contentsOf: raiz.appendingPathComponent("Kit/Sources/EscaliburCore/Release/ReleaseKeys.swift"), encoding: .utf8)) ?? ""
    var chaves: [String: P256.Signing.PublicKey] = [:]
    let padrao = try! NSRegularExpression(pattern: #"\"([a-z0-9-]+)\": \"([0-9a-f]{128})\""#)
    for achado in padrao.matches(in: fonte, range: NSRange(fonte.startIndex..., in: fonte)) {
        let id = String(fonte[Range(achado.range(at: 1), in: fonte)!])
        let texto = String(fonte[Range(achado.range(at: 2), in: fonte)!])
        var bytes = Data()
        var i = texto.startIndex
        while i < texto.endIndex { let j = texto.index(i, offsetBy: 2); bytes.append(UInt8(texto[i..<j], radix: 16)!); i = j }
        chaves[id] = try? P256.Signing.PublicKey(rawRepresentation: bytes)
    }
    let limiar = try! NSRegularExpression(pattern: #"static let threshold = (\d+)"#)
        .firstMatch(in: fonte, range: NSRange(fonte.startIndex..., in: fonte))
        .flatMap { Range($0.range(at: 1), in: fonte) }.flatMap { Int(fonte[$0]) }
    guard !chaves.isEmpty, let limiar, limiar >= 1 else { sair("ReleaseKeys.swift ilegivel") }
    return (chaves, limiar)
}

/// Grava as duas listas a partir do texto e das assinaturas validas. Uma assinatura feita
/// com o nome antigo vale pelo nome de hoje; a do site leva os dois nomes.
func gravar(_ texto: String, _ assinaturas: [Assinatura], _ chaves: [String: P256.Signing.PublicKey]) {
    let antigoParaNovo = Dictionary(uniqueKeysWithValues: nomesAntigos.map { ($1, $0) })
    var porChave: [String: String] = [:]
    for a in assinaturas {
        let nome = antigoParaNovo[a.chave] ?? a.chave
        guard let chave = chaves[nome], let bruta = Data(base64Encoded: a.p256),
              let assinatura = try? P256.Signing.ECDSASignature(rawRepresentation: bruta),
              chave.isValidSignature(assinatura, for: Data(texto.utf8)) else { continue }
        porChave[nome] = a.p256
    }
    let doApp = porChave.sorted { $0.key < $1.key }.map { Assinatura(chave: $0.key, p256: $0.value) }
    let doSite = doApp + doApp.compactMap { a in nomesAntigos[a.chave].map { Assinatura(chave: $0, p256: a.p256) } }
    let saida = JSONEncoder()
    saida.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
        try FileManager.default.createDirectory(at: arquivoApp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try saida.encode(Envelope(manifesto: texto, assinaturas: doSite)).write(to: arquivo, options: .atomic)
        try saida.encode(Envelope(manifesto: texto, assinaturas: doApp)).write(to: arquivoApp, options: .atomic)
    } catch { sair("nao gravou as listas: \(error)") }
}

/// As chaves confiadas que assinam o manifesto do envelope.
func validas(_ envelope: Envelope, _ chaves: [String: P256.Signing.PublicKey]) -> Set<String> {
    Set(envelope.assinaturas.compactMap { a -> String? in
        guard let chave = chaves[a.chave], let bruta = Data(base64Encoded: a.p256),
              let assinatura = try? P256.Signing.ECDSASignature(rawRepresentation: bruta),
              chave.isValidSignature(assinatura, for: Data(envelope.manifesto.utf8)) else { return nil }
        return a.chave
    })
}

/// Assinaturas pelo nome antigo de uma chave confiada (as listas de antes da troca de nome).
func validasPeloNomeAntigo(_ envelope: Envelope, _ chaves: [String: P256.Signing.PublicKey]) -> Int {
    let antigoParaNovo = Dictionary(uniqueKeysWithValues: nomesAntigos.map { ($1, $0) })
    let renomeado = Envelope(manifesto: envelope.manifesto, assinaturas: envelope.assinaturas.compactMap { a in
        antigoParaNovo[a.chave].map { Assinatura(chave: $0, p256: a.p256) }
    })
    return validas(renomeado, chaves).subtracting(validas(envelope, chaves)).count
}

func regra(_ obrigatoria: Obrigatoria) -> String {
    ((obrigatoria.minima.map { ["abaixo de \($0)"] } ?? []) + (obrigatoria.versoes ?? [])).joined(separator: ", ")
}

func resumo(_ manifesto: Manifesto) -> String {
    var versoes = manifesto.versoes.map { "\($0.versao) (\($0.builds.joined(separator: ", ")))\($0.liberada.map { " liberada em \($0)" } ?? "")" }
        .joined(separator: "; ")
    if let obrigatoria = manifesto.obrigatoria { versoes += "; atualizacao obrigatoria para: " + regra(obrigatoria) }
    if let android = manifesto.android {
        versoes += "; Android: build \(android.build) liberado em \(android.liberada)\(android.sdk.map { ", Android \($0)+ (SDK)" } ?? "")"
            + (android.minimo.map { ", obrigatoria abaixo do build \($0)" } ?? "")
    }
    return versoes
}

/// "1.0.10" depois de "1.0.9", como `ReleaseManifest.isNewer` no app.
func maisNova(_ a: String, _ b: String) -> Bool {
    let x = a.split(separator: ".").compactMap { Int($0) }, y = b.split(separator: ".").compactMap { Int($0) }
    for i in 0..<max(x.count, y.count) where (i < x.count ? x[i] : 0) != (i < y.count ? y[i] : 0) {
        return (i < x.count ? x[i] : 0) > (i < y.count ? y[i] : 0)
    }
    return false
}

/// A lista de site/versoes.json, so se ela confere: uma versao acrescentada no arquivo por quem
/// escreve na arvore sairia assinada junto (auditoria 6, A6-12).
func conferida(_ chaves: [String: P256.Signing.PublicKey], _ limiar: Int) -> Manifesto? {
    guard let (envelope, anterior) = ler() else {
        // A do site sumiu e a do app ficou: comecar uma lista nova derrubaria as versoes e a obrigacao sem aviso.
        guard !FileManager.default.fileExists(atPath: arquivoApp.path) else {
            sair("site/versoes.json sumiu e a lista do app continua: volte a do site (git checkout site/versoes.json).")
        }
        return nil
    }
    guard anterior.app == app, validas(envelope, chaves).count + validasPeloNomeAntigo(envelope, chaves) >= limiar else {
        sair("site/versoes.json nao confere com ReleaseKeys.swift: nao assino por cima. Volte a lista do ultimo commit (git checkout site/versoes.json) e confira.")
    }
    // Esta ferramenta reescreve o texto inteiro: um campo que ela nao conhece (de uma versao mais nova dela) sumiria calado.
    let codificador = JSONEncoder()
    codificador.outputFormatting = [.sortedKeys]
    guard let texto = try? codificador.encode(anterior), String(data: texto, encoding: .utf8) == envelope.manifesto else {
        sair("site/versoes.json tem campo que esta versao da ferramenta nao conhece: nao assino por cima. Use a versoes.swift do main.")
    }
    return anterior
}

/// A versao que a App Store mostra agora, pela mesma consulta do app, no Brasil e nos Estados Unidos.
func versaoNaLoja(_ pais: String) -> String? {
    guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(app)&country=\(pais)") else { return nil }
    let espera = DispatchSemaphore(value: 0)
    var versao: String?
    URLSession(configuration: .ephemeral).dataTask(with: url) { dados, _, _ in
        defer { espera.signal() }
        guard let dados, let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let primeiro = (json["results"] as? [[String: Any]])?.first else { return }
        versao = primeiro["version"] as? String
    }.resume()
    espera.wait()
    return versao
}

/// A hora da Apple, pelo cabecalho `Date` de uma resposta HTTPS (a mesma loja que o app consulta).
func horaDaApple() -> Date? {
    guard let url = URL(string: "https://itunes.apple.com/") else { return nil }
    var pedido = URLRequest(url: url)
    pedido.httpMethod = "HEAD"
    let espera = DispatchSemaphore(value: 0)
    var hora: Date?
    URLSession(configuration: .ephemeral).dataTask(with: pedido) { _, resposta, _ in
        defer { espera.signal() }
        guard let texto = (resposta as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date") else { return }
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "en_US_POSIX")
        formato.timeZone = TimeZone(identifier: "GMT")
        formato.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        hora = formato.date(from: texto)
    }.resume()
    espera.wait()
    return hora
}

/// Um pedido HTTPS, esperando a resposta: o status e o corpo.
func pedir(_ metodo: String, _ endereco: String, corpo: Data? = nil, tipo: String = "application/json", token: String? = nil) -> (Int, Data) {
    guard let url = URL(string: endereco) else { return (0, Data()) }
    var pedido = URLRequest(url: url)
    pedido.httpMethod = metodo
    pedido.httpBody = corpo
    pedido.setValue(tipo, forHTTPHeaderField: "Content-Type")
    if let token { pedido.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    let espera = DispatchSemaphore(value: 0)
    var resposta = (0, Data())
    URLSession(configuration: .ephemeral).dataTask(with: pedido) { dados, http, _ in
        resposta = ((http as? HTTPURLResponse)?.statusCode ?? 0, dados ?? Data())
        espera.signal()
    }.resume()
    espera.wait()
    return resposta
}

/// A chave RSA (PKCS#1) de dentro do PKCS#8 da conta de servico: SEQUENCE { INTEGER, AlgorithmIdentifier, OCTET STRING }.
func pkcs1(doPKCS8 der: Data) -> Data? {
    let b = [UInt8](der)
    var i = 0
    func elemento(_ etiqueta: UInt8) -> Range<Int>? {
        guard i + 1 < b.count, b[i] == etiqueta else { return nil }
        i += 1
        var tamanho = Int(b[i])
        i += 1
        if tamanho >= 0x80 {
            let bytes = tamanho & 0x7f
            guard (1...3).contains(bytes), i + bytes <= b.count else { return nil }
            tamanho = b[i..<(i + bytes)].reduce(0) { $0 << 8 | Int($1) }
            i += bytes
        }
        guard i + tamanho <= b.count else { return nil }
        return i..<(i + tamanho)
    }
    guard elemento(0x30) != nil, let versao = elemento(0x02) else { return nil }
    i = versao.upperBound
    guard let algoritmo = elemento(0x30) else { return nil }
    i = algoritmo.upperBound
    return elemento(0x04).map { Data(b[$0]) }
}

/// O build na Play, so lendo (abre uma edicao, le a faixa e os pacotes e descarta a edicao), com a conta de servico do
/// tools/android/play.py. Recusa, dizendo por que: o lancamento fora de 100% (fracao ou paises), o pacote na Play que nao e o
/// que este Mac enviou (`~/.escalibur/android/enviados.json`, gravado pelo play.py no envio) e um versionCode mais novo na
/// Play fora dos autorizados (revisao dos 3 agentes de 07/11/2026). Aqui em Swift, e nao chamando o play.py: o Python de um
/// processo filho roda com `-I`, que deixa de fora o PyJWT instalado na pasta do usuario. A chave nunca e impressa.
func conferirNaPlay(_ build: String, autorizados: Set<String>) {
    let arquivo = pasta.appendingPathComponent("android/play-api.json")
    guard let dados = try? Data(contentsOf: arquivo), let conta = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
          let email = conta["client_email"] as? String, let pem = conta["private_key"] as? String,
          let idDaChave = conta["private_key_id"] as? String, let enderecoDoToken = conta["token_uri"] as? String else {
        sair("sem a conta de servico da Play em \(arquivo.path)")
    }
    let base64 = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
    let atributos = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary
    guard let der = Data(base64Encoded: base64), let rsa = pkcs1(doPKCS8: der),
          let chave = SecKeyCreateWithData(rsa as CFData, atributos, nil) else { sair("a chave da conta de servico da Play nao le") }
    func base64url(_ dados: Data) -> String {
        dados.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    let agora = Int(Date().timeIntervalSince1970)
    let cabecalho = try! JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT", "kid": idDaChave])
    let afirmacao = try! JSONSerialization.data(withJSONObject: ["iss": email, "scope": "https://www.googleapis.com/auth/androidpublisher",
                                                                "aud": enderecoDoToken, "iat": agora, "exp": agora + 3600])
    let assinado = base64url(cabecalho) + "." + base64url(afirmacao)
    guard let assinatura = SecKeyCreateSignature(chave, .rsaSignatureMessagePKCS1v15SHA256, Data(assinado.utf8) as CFData, nil) as Data? else {
        sair("nao assinou o pedido de acesso a Play")
    }
    let (_, resposta) = pedir("POST", enderecoDoToken, corpo: Data("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(assinado).\(base64url(assinatura))".utf8),
                              tipo: "application/x-www-form-urlencoded")
    guard let token = (try? JSONSerialization.jsonObject(with: resposta) as? [String: Any])?["access_token"] as? String else {
        sair("a Play nao deu acesso a conta de servico")
    }
    let api = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(app)"
    guard let edicao = (try? JSONSerialization.jsonObject(with: pedir("POST", api + "/edits", corpo: Data("{}".utf8), token: token).1) as? [String: Any])?["id"] as? String else {
        sair("a Play nao abriu a edicao")
    }
    let faixa = try? JSONSerialization.jsonObject(with: pedir("GET", api + "/edits/\(edicao)/tracks/production", token: token).1) as? [String: Any]
    let pacotes = try? JSONSerialization.jsonObject(with: pedir("GET", api + "/edits/\(edicao)/bundles", token: token).1) as? [String: Any]
    _ = pedir("DELETE", api + "/edits/\(edicao)", token: token)
    let lancamentos = faixa?["releases"] as? [[String: Any]] ?? []
    guard let lancamento = lancamentos.first(where: { ($0["versionCodes"] as? [String])?.contains(build) == true }) else {
        sair("o \(build) nao esta na faixa de producao da Play")
    }
    let estado = lancamento["status"] as? String ?? "?"
    let fracao = lancamento["userFraction"] as? Double
    print("Play, producao: \(build) \(estado)\(fracao.map { " para \(Int($0 * 100))%" } ?? "")")
    // So este build no lancamento: um codigo a mais nele seria um pacote que a lista nao confere aqui.
    guard estado == "completed", fracao == nil, lancamento["countryTargeting"] == nil, (lancamento["versionCodes"] as? [String]) == [build] else {
        sair("o build \(build) nao esta em 100% na producao da Play (fracao ou paises): libere depois de completar o lancamento")
    }
    // O pacote na Play e o que este Mac enviou: um build de terceiro com o mesmo numero (enviado antes do dono) nao passa.
    guard let lista = pacotes?["bundles"] as? [[String: Any]], !lista.isEmpty else { sair("a Play nao mostrou os pacotes") }
    func codigo(_ pacote: [String: Any]) -> Int? { (pacote["versionCode"] as? Int) ?? (pacote["versionCode"] as? String).flatMap { Int($0) } }
    let enviados = (try? Data(contentsOf: pasta.appendingPathComponent("android/enviados.json")))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
    guard let nosso = enviados[build] else {
        sair("este Mac nao enviou o build \(build) (sem ele em ~/.escalibur/android/enviados.json): se o envio falhou como repetido, e incidente")
    }
    guard let naPlay = lista.first(where: { codigo($0) == Int(build) })?["sha256"] as? String, naPlay == nosso else {
        sair("o pacote do build \(build) na Play nao e o que este Mac enviou: e incidente, nao libere")
    }
    // Um pacote mais novo na Play que nao saiu deste Mac: os numeros sao autorizados antes de o binario existir, entao estar
    // na lista nao basta (revisao dos 3 agentes de 07/11/2026, segunda rodada). Fora da lista tambem conta.
    let estranhos = lista.filter { pacote in
        guard let numero = codigo(pacote), numero > Int(build)! else { return false }
        guard let digesto = pacote["sha256"] as? String else { return true }
        return enviados[String(numero)] != digesto || !autorizados.contains(String(numero))
    }.compactMap(codigo)
    guard estranhos.isEmpty else {
        sair("a Play tem build mais novo que nao saiu deste Mac (\(estranhos.map(String.init).joined(separator: ", "))): e incidente, nao libere")
    }
}

/// Assina o manifesto com a chave <id> deste Mac (pede o Touch ID, com o motivo) e grava as duas listas. O app ignora a
/// lista mais antiga que uma ja vista: o relogio deste Mac tem de bater com o da Apple (nenhuma lista sai com emissao no
/// futuro, nem no passado), e a emissao sempre passa da anterior.
func assinar(_ manifesto: Manifesto, anterior: String?, id: String, motivo: String, _ chaves: [String: P256.Signing.PublicKey], _ limiar: Int) {
    guard let apple = horaDaApple() else { sair("sem a hora da Apple (itunes.apple.com): confira a internet antes de assinar") }
    guard abs(Date().timeIntervalSince(apple)) <= 300 else {
        sair("o relogio deste Mac esta \(Int(Date().timeIntervalSince(apple))) s fora da hora da Apple: acerte o relogio antes de assinar")
    }
    var manifesto = manifesto
    // Uma lista de antes desta conferencia saiu com o relogio adiantado: a nova passa dela por um segundo, e o app aceita
    // (o piso dele nao sobe mais de um dia a frente do relogio do aparelho).
    let iso = ISO8601DateFormatter()
    if let anterior, manifesto.emitido <= anterior {
        guard let data = iso.date(from: anterior) else { sair("a emissao da lista anterior nao le (\(anterior)): nao assino") }
        manifesto.emitido = iso.string(from: data.addingTimeInterval(1))
        print("aviso: a lista anterior saiu com emissao no futuro (\(anterior)); esta sai com \(manifesto.emitido)")
    }
    let codificador = JSONEncoder()
    codificador.outputFormatting = [.sortedKeys]
    guard let texto = String(data: try! codificador.encode(manifesto), encoding: .utf8) else { sair("nao codificou") }
    let referencia = pasta.appendingPathComponent("versoes-\(id).chave")
    guard let blob = try? Data(contentsOf: referencia) else { sair("sem a chave \(id) neste Mac (\(referencia.path))") }
    // O pedido de presenca, com o motivo escrito, antes de usar a chave: o mesmo contexto
    // libera a assinatura logo em seguida.
    let contexto = LAContext()
    contexto.localizedReason = "assinar a lista de versões da Escalibur Wallet"
    let espera = DispatchSemaphore(value: 0)
    var liberado = false
    var falha: Error?
    print("a lista inteira que vai ser assinada: \(resumo(manifesto))")
    print("confirme no Touch ID (ou com a senha do Mac) para \(motivo)")
    contexto.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: motivo + " da Escalibur Wallet") { ok, erro in
        liberado = ok
        falha = erro
        espera.signal()
    }
    espera.wait()
    guard liberado else { sair("presenca nao confirmada: \(falha.map { "\($0)" } ?? "")") }
    do {
        let chave = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: contexto)
        let assinatura = try chave.signature(for: Data(texto.utf8))
        let antigoParaNovo = Dictionary(uniqueKeysWithValues: nomesAntigos.map { ($1, $0) })
        let nome = antigoParaNovo[id] ?? id
        guard chaves[nome] != nil else { sair("a chave \(id) nao esta em ReleaseKeys.swift") }
        gravar(texto, [Assinatura(chave: nome, p256: assinatura.rawRepresentation.base64EncodedString())], chaves)
        print("site/versoes.json e a lista do app assinados por \(nome): \(resumo(manifesto))")
        // As outras assinaturas eram do texto de antes: com limiar acima de um, as outras
        // chaves assinam de novo.
        if limiar > 1 { print("falta(m) \(limiar - 1) assinatura(s) de outra chave: a lista nova so vale com elas") }
    } catch { sair("nao assinou: \(error)") }
}

func agora() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: Date())
}

let argumentos = Array(CommandLine.arguments.dropFirst())
switch argumentos.first {
case "criar-chave":
    guard argumentos.count == 2 else { sair("uso: criar-chave <id>") }
    let destino = pasta.appendingPathComponent("versoes-\(argumentos[1]).chave")
    guard !FileManager.default.fileExists(atPath: destino.path) else { sair("ja existe: \(destino.path)") }
    var erro: Unmanaged<CFError>?
    guard let acesso = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &erro) else { sair("controle de acesso recusado") }
    do {
        let chave = try SecureEnclave.P256.Signing.PrivateKey(accessControl: acesso)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        try chave.dataRepresentation.write(to: destino, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destino.path)
        print("chave \(argumentos[1]) criada no Secure Enclave; referencia em \(destino.path)")
        print("publica (rawRepresentation): \(hex(chave.publicKey.rawRepresentation))")
    } catch { sair("nao criou: \(error)") }

case "autorizar":
    guard argumentos.count == 4 else { sair("uso: autorizar <versao> <build> <id>") }
    let (versao, build, id) = (argumentos[1], argumentos[2], argumentos[3])
    guard versao.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil, Int(build) != nil else { sair("versao X.Y.Z e build numerico") }
    let (chaves, limiar) = confiadas()
    let anterior = conferida(chaves, limiar)
    var manifesto = anterior ?? Manifesto(formato: 1, app: app, emitido: agora(), obrigatoria: nil, versoes: [])
    if let indice = manifesto.versoes.firstIndex(where: { $0.versao == versao }) {
        if !manifesto.versoes[indice].builds.contains(build) { manifesto.versoes[indice].builds.append(build) }
    } else {
        let dia = String(agora().prefix(10))
        manifesto.versoes.append(Versao(versao: versao, builds: [build], publicada: dia, liberada: nil))
    }
    manifesto.emitido = agora()
    assinar(manifesto, anterior: anterior?.emitido, id: id, motivo: "assinar a versão \(versao) (\(build))", chaves, limiar)

case "obrigatoria":
    // A atualizacao obrigatoria (pedido do dono, 05/11/2026). O app so mostra a tela sem saida
    // quando a versao da App Store e desta lista e fica fora da regra; aqui, a regra nunca pega a
    // versao mais nova da lista, senao ninguem sairia da tela.
    guard argumentos.count == 4 else { sair("uso: obrigatoria <minima|-> <versoes separadas por virgula|-> <id>") }
    let minima = argumentos[1] == "-" ? nil : argumentos[1]
    let versoes = argumentos[2] == "-" ? [] : argumentos[2].split(separator: ",").map(String.init)
    let id = argumentos[3]
    let (chaves, limiar) = confiadas()
    guard var manifesto = conferida(chaves, limiar) else { sair("sem site/versoes.json") }
    let publicadas = manifesto.versoes.map(\.versao)
    for v in versoes + [minima].compactMap({ $0 }) {
        guard publicadas.contains(v) else { sair("\(v) nao esta na lista (\(publicadas.joined(separator: ", ")))") }
    }
    // A saida e a versao liberada mais nova: a tela do app so empurra para versao liberada.
    let liberadas = manifesto.versoes.filter { $0.liberada != nil }.map(\.versao)
    if minima != nil || !versoes.isEmpty {
        guard let nova = liberadas.max(by: { maisNova($1, $0) }) else { sair("nenhuma versao liberada: a tela obrigatoria nao teria saida (rode liberar antes)") }
        guard !versoes.contains(nova), minima.map({ maisNova($0, nova) }) != true else {
            sair("a regra pegaria a \(nova), a liberada mais nova: ninguem sairia da tela")
        }
    }
    manifesto.obrigatoria = minima == nil && versoes.isEmpty ? nil : Obrigatoria(minima: minima, versoes: versoes.isEmpty ? nil : versoes)
    let emitidaAntes = manifesto.emitido
    manifesto.emitido = agora()
    let motivo = manifesto.obrigatoria.map { "assinar a atualização obrigatória para \(regra($0))" } ?? "tirar a atualização obrigatória"
    assinar(manifesto, anterior: emitidaAntes, id: id, motivo: motivo, chaves, limiar)

case "liberar":
    // Depois de a Apple publicar o build do dono: so entao a tela de atualizar do app empurra para a versao. Antes, um build
    // de terceiro com o mesmo numero diria "confirmada" (auditoria 6, A6-01; revisao dos 3 agentes de 05/11/2026).
    guard argumentos.count == 4 else { sair("uso: liberar <versao> <build aprovado no App Store Connect> <id>") }
    let (versao, build, id) = (argumentos[1], argumentos[2], argumentos[3])
    let (chaves, limiar) = confiadas()
    guard var manifesto = conferida(chaves, limiar) else { sair("sem site/versoes.json") }
    guard let indice = manifesto.versoes.firstIndex(where: { $0.versao == versao }) else {
        sair("\(versao) nao esta na lista (\(manifesto.versoes.map(\.versao).joined(separator: ", ")))")
    }
    // O build aprovado que o App Store Connect mostra, do iPhone (os do Android, de 1000 em diante, nunca vao para la), e
    // um dos autorizados da versao. Isso so evita erro de digitacao: os builds autorizados ficam publicos antes de o
    // binario existir, e a amarra ao binario continua sendo o dono conferir no App Store Connect que o build aprovado foi
    // enviado por ele, no dia do envio (A6-01).
    guard Int(build).map({ $0 > 0 && $0 < 1000 }) == true else { sair("o build \(build) nao e do iPhone (os do Android comecam em 1000)") }
    guard manifesto.versoes[indice].builds.contains(build) else {
        sair("o build \(build) nao esta entre os autorizados da \(versao) (\(manifesto.versoes[indice].builds.joined(separator: ", "))): confira no App Store Connect")
    }
    let lojas = ["br", "us"].map { ($0, versaoNaLoja($0)) }
    guard lojas.contains(where: { $0.1 == versao }) else {
        sair("a App Store nao mostra a \(versao) no ar (\(lojas.map { "\($0.0): \($0.1 ?? "nada")" }.joined(separator: ", "))): libere depois de ela ser publicada")
    }
    print("a App Store mostra: \(lojas.map { "\($0.0) \($0.1 ?? "nada")" }.joined(separator: ", ")). Confira antes no App Store Connect que o build \(build) aprovado foi enviado por voce, no dia do envio (docs/release.md).")
    manifesto.versoes[indice].liberada = String(agora().prefix(10))
    let emitidaAntes = manifesto.emitido
    manifesto.emitido = agora()
    assinar(manifesto, anterior: emitidaAntes, id: id, motivo: "liberar a versão \(versao) (\(build)) na tela de atualizar", chaves, limiar)

case "liberar-android":
    // O Android le so esta lista: a Google Play nao tem consulta publica da versao mais nova (pedido do dono, 07/11/2026). O
    // build entra so com o lancamento em 100% na producao: em lancamento gradual, quem esta fora da fracao veria a tela e
    // nenhuma atualizacao na Play. O pacote do build na Play tem de ser o que este Mac enviou: a chave de upload fica so aqui,
    // mas quem e dono da conta da Play Console pode pedir ao Google outra chave de upload, e quem pode lancar promove um AAB ja
    // enviado sem chave nenhuma.
    guard argumentos.count == 3 else { sair("uso: liberar-android <build|-> <id>") }
    let (build, id) = (argumentos[1], argumentos[2])
    let (chaves, limiar) = confiadas()
    guard var manifesto = conferida(chaves, limiar) else { sair("sem site/versoes.json") }
    // "-": tira a liberacao (o Google recusou o build, o lancamento foi pausado, ou ha na Play um build que nao e do dono). O
    // app volta a "em dia", e o piso impede a lista anterior de voltar.
    if build == "-" {
        guard manifesto.android != nil else { sair("nenhum build do Android liberado") }
        manifesto.android = nil
        let emitidaAntes = manifesto.emitido
        manifesto.emitido = agora()
        assinar(manifesto, anterior: emitidaAntes, id: id, motivo: "tirar a liberação do Android", chaves, limiar)
        exit(0)
    }
    guard let numero = Int(build), numero >= 1000 else { sair("o build \(build) nao e do Android (os do Android comecam em 1000)") }
    guard let versao = manifesto.versoes.first(where: { $0.builds.contains(build) })?.versao else {
        sair("o build \(build) nao esta autorizado na lista: rode autorizar antes")
    }
    if let anterior = manifesto.android, let liberado = Int(anterior.build), numero <= liberado {
        sair("o build \(liberado) ja esta liberado: libere so um build mais novo")
    }
    conferirNaPlay(build, autorizados: Set(manifesto.versoes.flatMap(\.builds)))
    // O minSdk do build, do Gradle deste commit: o app nao obriga a atualizar um aparelho que nao instala.
    let gradle = (try? String(contentsOf: raiz.appendingPathComponent("Android/app/build.gradle.kts"), encoding: .utf8)) ?? ""
    guard let sdk = try! NSRegularExpression(pattern: #"minSdk = (\d+)"#).firstMatch(in: gradle, range: NSRange(gradle.startIndex..., in: gradle))
        .flatMap({ Range($0.range(at: 1), in: gradle) }).flatMap({ Int(gradle[$0]) }) else { sair("minSdk ilegivel em Android/app/build.gradle.kts") }
    // A API diz "completed" desde o envio, ainda na revisao do Google: so a Play Console mostra que o build ja esta no ar.
    print("a Play mostra o \(build) (\(versao)) em 100% na producao, com o pacote que este Mac enviou.")
    print("Na Play Console, confira que o \(build) ja saiu da revisao do Google e esta disponivel. Digite \(build) para confirmar:")
    guard readLine()?.trimmingCharacters(in: .whitespaces) == build else { sair("nao confirmado: nada foi assinado") }
    manifesto.android = Android(build: build, liberada: String(agora().prefix(10)), sdk: sdk, minimo: manifesto.android?.minimo)
    let emitidaAntes = manifesto.emitido
    manifesto.emitido = agora()
    assinar(manifesto, anterior: emitidaAntes, id: id, motivo: "liberar o build \(build) do Android na tela de atualizar", chaves, limiar)

case "obrigatoria-android":
    // Os builds abaixo de <build> perdem o "Vou atualizar depois". A saida e o build liberado: a regra nunca pega ele.
    guard argumentos.count == 3 else { sair("uso: obrigatoria-android <build|-> <id>") }
    let (build, id) = (argumentos[1], argumentos[2])
    let (chaves, limiar) = confiadas()
    guard var manifesto = conferida(chaves, limiar) else { sair("sem site/versoes.json") }
    guard var android = manifesto.android else { sair("nenhum build do Android liberado: a tela obrigatoria nao teria saida (rode liberar-android antes)") }
    if build == "-" {
        android.minimo = nil
    } else {
        guard let numero = Int(build), numero >= 1000 else { sair("o build \(build) nao e do Android (os do Android comecam em 1000)") }
        guard let liberado = Int(android.build), numero <= liberado else {
            sair("a regra pegaria o \(android.build), o liberado: ninguem sairia da tela")
        }
        android.minimo = build
    }
    manifesto.android = android
    let emitidaAntes = manifesto.emitido
    manifesto.emitido = agora()
    let motivo = android.minimo.map { "assinar a atualização obrigatória do Android abaixo do build \($0)" } ?? "tirar a atualização obrigatória do Android"
    assinar(manifesto, anterior: emitidaAntes, id: id, motivo: motivo, chaves, limiar)

case "conferir":
    guard let (envelope, manifesto) = ler() else { sair("sem site/versoes.json") }
    let (chaves, limiar) = confiadas()
    let assinaram = validas(envelope, chaves)
    guard assinaram.count >= limiar, manifesto.app == app else {
        sair("site/versoes.json com \(assinaram.count) de \(limiar) assinatura(s) valida(s) das chaves de ReleaseKeys.swift")
    }
    guard let dadosApp = try? Data(contentsOf: arquivoApp), let doApp = try? JSONDecoder().decode(Envelope.self, from: dadosApp) else {
        sair("sem a lista do app (\(arquivoApp.path)): rode copiar")
    }
    guard doApp.manifesto == envelope.manifesto, validas(doApp, chaves).count >= limiar,
          doApp.assinaturas.allSatisfy({ chaves[$0.chave] != nil }) else {
        sair("a lista do app nao e a de site/versoes.json, ou leva assinatura de chave que o app nao conhece: rode copiar")
    }
    print("site/versoes.json e a lista do app assinados por \(assinaram.sorted().joined(separator: ", ")): \(manifesto.versoes.map(\.versao).joined(separator: ", "))")

case "copiar":
    guard let (envelope, manifesto) = ler() else { sair("sem site/versoes.json") }
    let (chaves, limiar) = confiadas()
    guard manifesto.app == app else { sair("site/versoes.json de outro app") }
    gravar(envelope.manifesto, envelope.assinaturas, chaves)
    guard let (novo, _) = ler(), validas(novo, chaves).count >= limiar else { sair("as assinaturas nao conferem com ReleaseKeys.swift") }
    print("listas escritas: site (\(novo.assinaturas.map(\.chave).joined(separator: ", "))) e app")

case "conferir-app":
    // O app que sai do archive: um build passado errado (o CURRENT_PROJECT_VERSION da linha de
    // comando, por exemplo) sairia fora da lista que ele mesmo carrega (auditoria 6).
    guard argumentos.count == 2 else { sair("uso: conferir-app <caminho do .app>") }
    let pacote = URL(fileURLWithPath: argumentos[1])
    guard let info = NSDictionary(contentsOf: pacote.appendingPathComponent("Info.plist")),
          let versao = info["CFBundleShortVersionString"] as? String, let build = info["CFBundleVersion"] as? String,
          let identificador = info["CFBundleIdentifier"] as? String else { sair("Info.plist do app ilegivel") }
    guard let dados = try? Data(contentsOf: pacote.appendingPathComponent("versoes.json")),
          let envelope = try? JSONDecoder().decode(Envelope.self, from: dados),
          let manifesto = try? JSONDecoder().decode(Manifesto.self, from: Data(envelope.manifesto.utf8)) else { sair("o app nao leva uma versoes.json legivel") }
    let (chaves, limiar) = confiadas()
    guard manifesto.app == identificador, validas(envelope, chaves).count >= limiar else { sair("a versoes.json do app nao confere com ReleaseKeys.swift") }
    guard manifesto.versoes.contains(where: { $0.versao == versao && $0.builds.contains(build) }) else {
        sair("a versoes.json do app nao autoriza \(versao) (\(build))")
    }
    print("o app \(versao) (\(build)) leva a lista assinada que o autoriza")

default:
    sair("comandos: criar-chave <id> | autorizar <versao> <build> <id> | liberar <versao> <build> <id> | obrigatoria <minima|-> <versoes|-> <id> | liberar-android <build|-> <id> | obrigatoria-android <build|-> <id> | conferir | copiar | conferir-app <app>")
}
