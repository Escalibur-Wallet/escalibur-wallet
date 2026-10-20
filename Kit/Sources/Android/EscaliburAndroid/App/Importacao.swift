import EscaliburChains
import EscaliburCore
import EscaliburKeys
import EscaliburNetwork
import Foundation

/// Importar uma carteira pelas palavras: a mesma conferencia do iOS (ImportPhraseView e
/// ImportPreview), com a frase so em buffer seguro.
enum Importacao {
    struct Validacao: Encodable {
        /// "valida", "tamanho", "desconhecida", "conferencia", "idiomas", "ambigua".
        let resultado: String
        let idioma: String?
        let contagem: Int?
        let posicao: Int?
    }

    struct Previa: Encodable {
        struct Endereco: Encodable { let rede: String; let nome: String; let endereco: String }
        let digital: String
        let enderecos: [Endereco]
        /// A rede mostrou outra chave no controle da conta da Tron (o golpe da "frase com saldo").
        let tronOutraChave: Bool
    }

    static let redesDaPrevia: [Chain] = [.bitcoin, .ethereum, .solana]

    /// A frase, como digitada, e a frase que vale: digitada sem acento, ela fecha no idioma dela
    /// trocando cada palavra pela de acento.
    static func resolver(_ frase: SecureBytes) -> (SecureBytes, Mnemonic.Validation) {
        let veredito = BIP39.validate(frase)
        if case .valid = veredito { return (copia(frase), veredito) }
        let palavras = Nucleo.dividirPorEspaco(frase)
        defer { palavras.forEach { $0.wipe() } }
        if let resolvida = WordLexicon.resolve(palavras) {
            return (resolvida.phrase, .valid(language: resolvida.language))
        }
        return (copia(frase), veredito)
    }

    static func validar(_ frase: SecureBytes) -> Validacao {
        defer { frase.wipe() }
        let (canonica, veredito) = resolver(frase)
        canonica.wipe()
        switch veredito {
        case .valid(let idioma): return Validacao(resultado: "valida", idioma: idioma.rawValue, contagem: nil, posicao: nil)
        case .wrongLength(let contagem): return Validacao(resultado: "tamanho", idioma: nil, contagem: contagem, posicao: nil)
        case .unknownWords(let posicoes, _): return Validacao(resultado: "desconhecida", idioma: nil, contagem: nil, posicao: (posicoes.first ?? 0) + 1)
        case .checksumFailed: return Validacao(resultado: "conferencia", idioma: nil, contagem: nil, posicao: nil)
        case .mixedLanguages: return Validacao(resultado: "idiomas", idioma: nil, contagem: nil, posicao: nil)
        case .ambiguousLanguage: return Validacao(resultado: "ambigua", idioma: nil, contagem: nil, posicao: nil)
        }
    }

    private static func segredo(_ frase: SecureBytes, passphrase: SecureBytes?) throws -> WalletSecret {
        let (canonica, veredito) = resolver(frase)
        frase.wipe()
        guard case .valid(let idioma) = veredito else {
            canonica.wipe()
            passphrase?.wipe()
            throw Nucleo.Falha(erro: "frase.invalida")
        }
        return try WalletSecret.from(phrase: canonica, language: idioma, passphrase: passphrase)
    }

    /// Os primeiros enderecos e a impressao digital, antes de guardar: frase com uma palavra
    /// trocada que ainda fecha, ou 25a palavra diferente, abre outra carteira, vazia, sem aviso.
    static func previa(_ frase: SecureBytes, passphrase: SecureBytes?) async throws -> Previa {
        let secret = try segredo(frase, passphrase: passphrase)
        defer { secret.wipe() }
        let (contas, digital) = try AccountDeriver.derive(secret, chains: redesDaPrevia + [.tron])
        let enderecos = redesDaPrevia.compactMap { rede in
            contas.first { $0.chainID == rede.id }.map { Previa.Endereco(rede: rede.id, nome: rede.name, endereco: $0.address) }
        }
        var outraChave = false
        if let texto = contas.first(where: { $0.chainID == Chain.tron.id })?.address, let endereco = TronAddress(texto),
           let controle = try? await TronReader.shared.ownerControl(owner: endereco) {
            outraChave = controle.isCompromised
        }
        return Previa(digital: digital.hex.uppercased(), enderecos: enderecos, tronOutraChave: outraChave)
    }

    static func importar(_ frase: SecureBytes, passphrase: SecureBytes?, palavras: Int, tronComOutraChave: Bool, credencial: Credencial) throws -> WalletMeta {
        let secret: WalletSecret
        do {
            secret = try segredo(frase, passphrase: passphrase)
        } catch {
            credencial.zerar()
            throw error
        }
        let quantas = Sessao.shared.metadata.wallets.count
        let nome = quantas == 0 ? Textos.carteiraPrincipal : Textos.carteira(quantas + 1)
        return try Sessao.shared.adicionarCarteira(
            secret, nome: nome, origem: .importedPhrase, palavras: palavras, copiaConfirmada: true,
            tronComOutraChave: tronComOutraChave, credencial: credencial
        )
    }

    private static func copia(_ origem: SecureBytes) -> SecureBytes {
        let destino = SecureBytes(capacity: max(origem.count, 1))
        origem.withUnsafeBytes { destino.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        return destino
    }
}

extension Nucleo {
    /// As palavras da frase, cada uma no seu buffer seguro.
    static func dividirPorEspaco(_ frase: SecureBytes) -> [SecureBytes] {
        frase.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var palavras: [SecureBytes] = []
            var inicio = 0
            for indice in 0...bytes.count where indice == bytes.count || bytes[indice] == 0x20 {
                if indice > inicio {
                    let palavra = SecureBytes(capacity: indice - inicio)
                    palavra.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[inicio..<indice]))
                    palavras.append(palavra)
                }
                inicio = indice + 1
            }
            return palavras
        }
    }
}
