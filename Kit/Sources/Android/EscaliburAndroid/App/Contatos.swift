import EscaliburChains
import EscaliburCore
import Foundation

/// Os enderecos salvos (o ContactsView e o AddContactSheet do iOS). Um endereco salvo vira de
/// confianca: atalho no envio e conhecido na conferencia de endereco parecido. Por isso ele nasce
/// conferido contra tudo que o dono ja usou na rede, com um trecho do meio digitado olhando a
/// fonte, e gravar pede a biometria ou o PIN.
enum Contatos {
    struct Resumo: Encodable {
        let id: String, nome: String, rede: String, redeNome: String, redeCoingecko: String, endereco: String, tag: String?
    }

    static func lista() -> [Resumo] {
        Sessao.shared.metadata.contacts.compactMap { contato in
            guard let chain = Chain.find(contato.chainID) else { return nil }
            return Resumo(id: contato.id.uuidString, nome: contato.name, rede: chain.id, redeNome: chain.name, redeCoingecko: chain.coingeckoID,
                          endereco: contato.address, tag: contato.tag)
        }
    }

    static func remover(_ id: UUID) throws {
        try Sessao.shared.alterar { $0.contacts.removeAll { $0.id == id } }
    }

    struct Recente: Encodable { let rede: String; let redeNome: String; let redeCoingecko: String; let endereco: String }

    /// Para onde esta carteira ja enviou e ainda nao esta salvo: tocar preenche a rede e o
    /// endereco, e a conferencia do meio continua.
    static func recentes() -> [Recente] {
        let metadata = Sessao.shared.metadata
        let salvos = Set(metadata.contacts.map { "\($0.chainID)|\($0.address.lowercased())" })
        var vistos = Set<String>()
        var saida: [Recente] = []
        for (rede, lista) in metadata.sentTo.sorted(by: { $0.key < $1.key }) {
            guard let chain = Chain.find(rede) else { continue }
            for endereco in lista.reversed() {
                let chave = "\(rede)|\(endereco.lowercased())"
                guard !salvos.contains(chave), vistos.insert(chave).inserted else { continue }
                saida.append(Recente(rede: chain.id, redeNome: chain.name, redeCoingecko: chain.coingeckoID, endereco: endereco))
            }
        }
        return Array(saida.prefix(6))
    }

    struct Rede: Encodable { let id: String; let nome: String; let coingecko: String }

    struct Conferencia: Encodable {
        let valido: Bool
        let problema: String?
        /// O endereco colado parece de outra rede: o app sugere, nao troca sozinho.
        let sugestao: Rede?
        let destino: String?
        let tipoDeTag: String
        let parecido: Envio.Estado.Parecido?
        let outroID: Envio.Estado.OutroID?
        /// O trecho que o dono digita, e onde ele e lido (escondido quando nao ha parecido).
        let trecho: Envio.Trecho?
        let fonte: String
        let escondido: Bool
        let conferido: Bool
        let conflitoDoMemo: Envio.Estado.OutroID?
        let memoConferido: Bool
    }

    private struct Calculo {
        var destino: Address.Destination?
        var problema: String?
        var sugestao: Chain?
        var parecido: String?
        var outroID: AddressPoisoning.SameAccount?
        var segmento: AddressPoisoning.Segment?
        var fonte = ""
        var conferido = false
        var memoOutroID: AddressPoisoning.SameAccount?
    }

    private static func calcular(_ chain: Chain, endereco texto: String, tag: String, conferencia: String) -> Calculo {
        var c = Calculo()
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else { return c }
        if Envio.pareceFrase(limpo) {
            c.problema = Textos.t("Este código traz as palavras de uma senha de carteira, não um endereço. Quem tem essas palavras tem o saldo: não mostre a ninguém.")
            return c
        }
        switch Address.validate(limpo, for: chain) {
        case .success(let destino):
            c.destino = destino
        case .failure(let falha):
            c.problema = Envio.mensagem(falha, chain: chain)
            if let palpite = Address.guessChain(limpo), palpite.id != chain.id { c.sugestao = palpite }
            return c
        }
        guard let destino = c.destino else { return c }
        let metadata = Sessao.shared.metadata
        let conhecidos = (metadata.sentTo[chain.id] ?? []) + metadata.contacts.filter { $0.chainID == chain.id }.map(\.address)
            + metadata.wallets.filter { !$0.isWatchOnly }.compactMap { $0.account(chain)?.address }
        let comTag = metadata.contacts.filter { $0.chainID == chain.id }.compactMap { contato in contato.tag.map { (address: contato.address, tag: $0) } }
        c.parecido = AddressPoisoning.lookalike(destino.address, among: conhecidos, chain: chain)
        if c.parecido == nil {
            c.outroID = AddressPoisoning.sameAccountOtherID(destino.address, among: conhecidos, tagged: comTag, chain: chain)
        }
        if let parecido = c.parecido {
            c.segmento = AddressPoisoning.differingSegment(destino.address, from: parecido, chain: chain)
            c.fonte = destino.address
        } else {
            c.segmento = AddressPoisoning.blindSegment(limpo, chain: chain)
            c.fonte = limpo
        }
        if c.outroID != nil {
            c.conferido = AddressPoisoning.muxedIDConfirmed(conferencia, address: destino.address)
        } else if let segmento = c.segmento {
            let digitado = conferencia.trimmingCharacters(in: .whitespaces).lowercased()
            c.conferido = digitado.count == segmento.length && digitado == segmento.text(in: c.fonte).lowercased()
        } else {
            c.conferido = c.parecido == nil
        }
        if c.parecido == nil, c.outroID == nil, chain.family == .stellar, !tag.isEmpty, StellarMuxedAccount(address: destino.address)?.isMuxed == false {
            c.memoOutroID = AddressPoisoning.sameAccountOtherID(destino.address, tag: tag, among: conhecidos, tagged: comTag, chain: chain)
        }
        return c
    }

    private static func memoConferido(_ tag: String, _ conferencia: String) -> Bool {
        guard let id = UInt64(tag.trimmingCharacters(in: .whitespaces)) else { return false }
        return AddressPoisoning.idConfirmed(conferencia, id: id)
    }

    static func conferir(rede: String, endereco: String, tag: String, conferencia: String, conferenciaDoMemo: String, comMemo: Bool) -> Conferencia {
        guard let chain = Chain.find(rede) else {
            return Conferencia(valido: false, problema: nil, sugestao: nil, destino: nil, tipoDeTag: "none", parecido: nil, outroID: nil, trecho: nil,
                               fonte: "", escondido: false, conferido: false, conflitoDoMemo: nil, memoConferido: true)
        }
        let c = calcular(chain, endereco: endereco, tag: tag, conferencia: conferencia)
        let trecho = { (s: AddressPoisoning.Segment) in Envio.Trecho(inicio: s.start, tamanho: s.length) }
        let parecidoDTO: Envio.Estado.Parecido? = c.parecido.flatMap { conhecido in
            c.destino.map { destino in
                Envio.Estado.Parecido(conhecido: conhecido, rotulo: rotulo(conhecido, chain: chain), trechoColado: c.segmento.map(trecho),
                                      trechoConhecido: AddressPoisoning.differingSegment(conhecido, from: destino.address, chain: chain).map(trecho))
            }
        }
        func outroDTO(_ conhecido: AddressPoisoning.SameAccount, colado: String?) -> Envio.Estado.OutroID {
            Envio.Estado.OutroID(conhecido: conhecido.known, idConhecido: String(conhecido.knownID), rotulo: rotulo(conhecido.known, chain: chain),
                                 trechoColado: colado.flatMap(AddressPoisoning.muxedIDSegment).map(trecho),
                                 trechoConhecido: AddressPoisoning.muxedIDSegment(conhecido.known).map(trecho))
        }
        let conflito = comMemo ? c.memoOutroID : nil
        return Conferencia(
            valido: c.destino != nil, problema: c.problema, sugestao: c.sugestao.map { Rede(id: $0.id, nome: $0.name, coingecko: $0.coingeckoID) },
            destino: c.destino?.address, tipoDeTag: chain.destinationTag.rawValue, parecido: parecidoDTO,
            outroID: c.outroID.map { outroDTO($0, colado: c.destino?.address) }, trecho: c.segmento.map(trecho), fonte: c.fonte,
            escondido: c.parecido == nil, conferido: c.conferido, conflitoDoMemo: conflito.map { outroDTO($0, colado: nil) },
            memoConferido: conflito == nil || memoConferido(tag, conferenciaDoMemo)
        )
    }

    /// Grava depois de tudo conferido de novo aqui. O memo que bate com outra conta conhecida
    /// pede a conferencia dele antes ("contato.conferirMemo").
    static func salvar(rede: String, endereco: String, nome: String, tag: String, conferencia: String, conferenciaDoMemo: String?,
                       credencial: Credencial) throws -> Resumo {
        guard let chain = Chain.find(rede) else {
            credencial.zerar()
            throw Nucleo.Falha(erro: "rede desconhecida")
        }
        let c = calcular(chain, endereco: endereco, tag: tag, conferencia: conferencia)
        let titulo = String(nome.trimmingCharacters(in: .whitespaces).prefix(40))
        guard let destino = c.destino, c.conferido, !titulo.isEmpty else {
            credencial.zerar()
            throw Nucleo.Falha(erro: "contato.naoConferido")
        }
        if c.memoOutroID != nil, !(conferenciaDoMemo.map { memoConferido(tag, $0) } ?? false) {
            credencial.zerar()
            throw Nucleo.Falha(erro: "contato.conferirMemo")
        }
        // So rede que tem tag guarda tag.
        let tagFinal = chain.destinationTag == .none ? nil : (destino.tag.map(String.init) ?? (tag.isEmpty ? nil : String(tag.prefix(120))))
        if let tagFinal, Envio.problemaDaTag(tagFinal, rede: chain) != nil {
            credencial.zerar()
            throw Nucleo.Falha(erro: chain.destinationTag == .stellarMemo ? "contato.memoInvalido" : "contato.tagInvalida")
        }
        try Sessao.shared.comChaveRaiz(credencial) { _ in }
        let contato = Contact(id: UUID(), name: titulo, chainID: chain.id, address: destino.address, tag: tagFinal)
        try Sessao.shared.alterar { $0.contacts.append(contato) }
        return Resumo(id: contato.id.uuidString, nome: titulo, rede: chain.id, redeNome: chain.name, redeCoingecko: chain.coingeckoID,
                      endereco: destino.address, tag: tagFinal)
    }

    struct Lido: Encodable { let endereco: String; let tag: String?; let problema: String? }

    /// O que veio do QR: a mesma leitura do envio. A frase nunca vira endereco, e o link de outra
    /// rede que a escolhida nao entra.
    static func lerLink(_ texto: String, rede: String) -> Lido {
        guard let chain = Chain.find(rede) else { return Lido(endereco: "", tag: nil, problema: nil) }
        let leitura: PaymentLink.Reading
        do {
            leitura = try PaymentLink.read(texto)
        } catch PaymentLink.Problem.containsPhrase {
            return Lido(endereco: "", tag: nil, problema: Textos.t("Este código traz as palavras de uma senha de carteira, não um endereço. Quem tem essas palavras tem o saldo: não mostre a ninguém."))
        } catch PaymentLink.Problem.tooLong {
            return Lido(endereco: "", tag: nil, problema: Textos.t("Este código é longo demais para ser um endereço."))
        } catch PaymentLink.Problem.unknownScheme {
            return Lido(endereco: "", tag: nil, problema: Textos.t("O app não reconhece este tipo de link. Cole só o endereço."))
        } catch PaymentLink.Problem.unsupportedNetwork {
            return Lido(endereco: "", tag: nil, problema: Textos.t("Este pedido de pagamento é de uma rede que a Escalibur não envia. Confira com quem pediu."))
        } catch PaymentLink.Problem.unsupportedMemo {
            return Lido(endereco: "", tag: nil, problema: Textos.t("Este pedido traz um memo que o app não envia como está. Cole só o endereço e digite o memo, conferindo com quem pediu."))
        } catch {
            return Lido(endereco: "", tag: nil, problema: Textos.t("Este pedido de pagamento não pôde ser lido com segurança. Peça só o endereço."))
        }
        if let pedida = leitura.chainID, pedida != chain.id {
            let nome = Chain.find(pedida)?.name ?? Textos.t("outra rede")
            return Lido(endereco: "", tag: nil, problema: preencher(Textos.t("Este pedido é da rede %@, e o envio é pela %@. Confira com quem pediu antes de enviar."), nome, chain.name))
        }
        if let familia = leitura.family, familia != chain.family {
            return Lido(endereco: "", tag: nil, problema: preencher(Textos.t("Este pedido é de outra rede, e o envio é pela %@. Confira com quem pediu antes de enviar."), chain.name))
        }
        return Lido(endereco: leitura.address, tag: leitura.tag?.isEmpty == false ? leitura.tag : nil, problema: nil)
    }

    /// De onde o dono conhece um endereco: "voce ja pagou" e "salvo, nunca recebeu" pesam diferente.
    static func rotulo(_ endereco: String, chain: Chain) -> String {
        let metadata = Sessao.shared.metadata
        if (metadata.sentTo[chain.id] ?? []).contains(endereco) { return Textos.t("Você já pagou") }
        if let carteira = metadata.wallets.first(where: { !$0.isWatchOnly && $0.account(chain)?.address == endereco }) {
            return preencher(Textos.t("Sua carteira %@"), carteira.name)
        }
        if let contato = metadata.contacts.first(where: { $0.chainID == chain.id && $0.address == endereco }) {
            return preencher(Textos.t("Salvo como %@, nunca recebeu daqui"), contato.name)
        }
        return Textos.t("Você já usou")
    }
}
