// A lista assinada de versoes da Escalibur Wallet (docs/seguranca.md, "Versao autorizada").
//
//   swift tools/versoes/versoes.swift criar-chave <id>
//       cria a chave de assinatura no Secure Enclave deste Mac, presa a ele e ao Touch ID
//       (ou a senha do Mac) a cada assinatura; guarda so a referencia, em ~/.escalibur, e
//       imprime a chave publica para ReleaseKeys.swift
//   swift tools/versoes/versoes.swift autorizar <versao> <build> <id>
//       confere a lista de site/versoes.json, acrescenta a versao e assina de novo (pede o
//       Touch ID)
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
struct Versao: Codable { let versao: String; var builds: [String]; let publicada: String }
struct Manifesto: Codable { let formato: Int; let app: String; var emitido: String; var versoes: [Versao] }

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

func resumo(_ manifesto: Manifesto) -> String {
    manifesto.versoes.map { "\($0.versao) (\($0.builds.joined(separator: ", ")))" }.joined(separator: "; ")
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
    let atual = ler()
    let (chaves, limiar) = confiadas()
    // So assina por cima de uma lista que confere: uma versao acrescentada no arquivo por quem
    // escreve na arvore sairia assinada junto (auditoria 6, A6-12).
    if let (envelope, anterior) = atual {
        guard anterior.app == app, validas(envelope, chaves).count + validasPeloNomeAntigo(envelope, chaves) >= limiar else {
            sair("site/versoes.json nao confere com ReleaseKeys.swift: nao assino por cima. Volte a lista do ultimo commit (git checkout site/versoes.json) e confira.")
        }
    }
    var manifesto = atual?.1 ?? Manifesto(formato: 1, app: app, emitido: agora(), versoes: [])
    if let indice = manifesto.versoes.firstIndex(where: { $0.versao == versao }) {
        if !manifesto.versoes[indice].builds.contains(build) { manifesto.versoes[indice].builds.append(build) }
    } else {
        let dia = String(agora().prefix(10))
        manifesto.versoes.append(Versao(versao: versao, builds: [build], publicada: dia))
    }
    manifesto.emitido = agora()
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
    print("confirme no Touch ID (ou com a senha do Mac) para assinar a versao \(versao) (\(build))")
    contexto.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "assinar a versão \(versao) (\(build)) da Escalibur Wallet") { ok, erro in
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
    sair("comandos: criar-chave <id> | autorizar <versao> <build> <id> | conferir | copiar | conferir-app <app>")
}
