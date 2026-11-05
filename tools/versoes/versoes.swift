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
struct Manifesto: Codable { let formato: Int; let app: String; var emitido: String; var obrigatoria: Obrigatoria?; var versoes: [Versao] }

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
    let versoes = manifesto.versoes.map { "\($0.versao) (\($0.builds.joined(separator: ", ")))\($0.liberada.map { " liberada em \($0)" } ?? "")" }
        .joined(separator: "; ")
    guard let obrigatoria = manifesto.obrigatoria else { return versoes }
    return versoes + "; atualizacao obrigatoria para: " + regra(obrigatoria)
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
    sair("comandos: criar-chave <id> | autorizar <versao> <build> <id> | liberar <versao> <build> <id> | obrigatoria <minima|-> <versoes|-> <id> | conferir | copiar | conferir-app <app>")
}
