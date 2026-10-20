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
        /// O endereco na Tron, so para conferir quem controla a conta (`tron`); nao aparece na lista.
        let tron: String?
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

    /// A primeira palavra (1 a N) que nao esta na lista em ingles, ou nil: a frase escolhida a
    /// dedo e so em ingles, como a sorteada.
    static func foraDoIngles(_ frase: SecureBytes) -> Int? {
        guard let lista = try? WordlistStore.shared.wordlist(for: .english) else { return nil }
        return frase.withUnsafeBytes { raw -> Int? in
            var inicio = 0
            var posicao = 0
            for indice in 0...raw.count where indice == raw.count || raw[indice] == 0x20 {
                if indice > inicio {
                    posicao += 1
                    var palavra = Array(raw[inicio..<indice])
                    defer { palavra.resetBytes() }
                    if lista.position(nfkd: palavra) == nil { return posicao }
                }
                inicio = indice + 1
            }
            return nil
        }
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
    /// So deriva, sem rede: a tela das palavras fica em silencio.
    static func previa(_ frase: SecureBytes, passphrase: SecureBytes?) throws -> Previa {
        let secret = try segredo(frase, passphrase: passphrase)
        defer { secret.wipe() }
        let (contas, digital) = try AccountDeriver.derive(secret, chains: redesDaPrevia + [.tron])
        let enderecos = redesDaPrevia.compactMap { rede in
            contas.first { $0.chainID == rede.id }.map { Previa.Endereco(rede: rede.id, nome: rede.name, endereco: $0.address) }
        }
        return Previa(digital: digital.hex.uppercased(), enderecos: enderecos, tron: contas.first { $0.chainID == Chain.tron.id }?.address)
    }

    /// Quem controla a conta na Tron, ja fora da tela das palavras. Sem rede ou com a conta ainda
    /// nao ativada, nada a dizer: o envio na Tron confere de novo antes de qualquer saldo.
    static func tronComOutraChave(_ texto: String) async -> Bool {
        guard let endereco = TronAddress(texto), let controle = try? await TronReader.shared.ownerControl(owner: endereco) else { return false }
        return controle.isCompromised
    }

    /// Os idiomas em que todas as palavras ja fechadas existem: as sugestoes seguem eles. Nil:
    /// qualquer um.
    static func idiomas(_ frase: SecureBytes) -> [String]? {
        let palavras = Nucleo.dividirPorEspaco(frase)
        frase.wipe()
        defer { palavras.forEach { $0.wipe() } }
        guard let achados = WordLexicon.languages(containing: palavras), !achados.isEmpty else { return nil }
        return achados.map(\.rawValue).sorted()
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

/// So observar um endereco (o WatchAddressView do iOS): a rede reconhecida pelo formato e a
/// carteira sem chave nenhuma.
enum Observacao {
    struct Rede: Encodable { let id: String; let nome: String; let coingecko: String }

    struct Reconhecida: Encodable {
        let rede: Rede
        let evm: Bool
        /// Na EVM o mesmo endereco vale em todas: as redes onde ele vai aparecer.
        let redesEVM: [Rede]
    }

    static func rede(_ chain: Chain) -> Rede { Rede(id: chain.id, nome: chain.name, coingecko: chain.coingeckoID) }

    static func reconhecer(_ texto: String) -> Reconhecida? {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty, let chain = Address.guessChain(limpo) else { return nil }
        return Reconhecida(rede: rede(chain), evm: chain.family == .evm, redesEVM: chain.family == .evm ? Chain.evmChains.map(rede) : [])
    }

    static func guardar(_ texto: String, nome: String) throws -> WalletMeta {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Envio.pareceFrase(limpo), let chain = Address.guessChain(limpo),
              case .success(let destino) = Address.validate(limpo, for: chain) else { throw Nucleo.Falha(erro: "observar.invalido") }
        // Endereco M da Stellar e um cliente dentro de uma conta: o saldo e o da conta base.
        let observado = chain.family == .stellar ? (StellarMuxedAccount(address: destino.address)?.account.address ?? destino.address) : destino.address
        let limpoNome = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        return try Sessao.shared.adicionarObservacao(rede: chain, endereco: observado, nome: String((limpoNome.isEmpty ? Textos.t("Carteira fria") : limpoNome).prefix(40)))
    }
}
