import EscaliburCore
import Foundation

/// Deteccao de envenenamento de endereco.
///
/// O golpe: o atacante gera um endereco com o comeco e o fim iguais aos de um que o
/// dono ja usou e manda um valor minusculo, para o endereco falso aparecer no
/// historico. Quem copia de la, conferindo so as pontas, paga o atacante.
///
/// A comparacao ignora o prefixo fixo de cada rede (o atacante nao precisa gerar
/// "0x" nem "bc1q", entao eles nao contam como coincidencia) e olha as pontas do
/// resto. Duas formas da mesma conta (caixa do EIP-55, amigavel e crua da TON) nao
/// sao parecidas: sao a mesma.
public enum AddressPoisoning {
    /// Coincidencias de ponta que um atacante consegue gerar em minutos. Acima disso
    /// o custo cresce 16 a 58 vezes por caractere.
    static let minimumPrefix = 3
    static let minimumSuffix = 3
    static let minimumTotal = 7
    /// Uma ponta so, longa: quem confere so o comeco ou so o fim cai em 2+6, 2+8 ou 0+10,
    /// que as duas pontas juntas deixavam passar (auditoria 4, C7-07). Ao acaso, cinco
    /// caracteres iguais numa ponta saem uma vez em um milhao de pares, em hexadecimal
    /// (16^5 = 2^20).
    static let singleEnd = 5
    /// A mesma ponta so, com 32 simbolos ou mais (bech32, base58, base32 da Stellar,
    /// base64 da TON): quatro caracteres ja sao os mesmos 20 bits (32^4 = 2^20). O sosia que
    /// casa so os 4 do fim, os que a tela mostra, custa o mesmo milhao de tentativas que
    /// os 5 do hexadecimal, e passava sem aviso (revisao dos enderecos parecidos, B-5).
    static let singleEndWide = 4
    /// Na Cardano, o comeco do corpo e a credencial de pagamento inteira (28 bytes, 44
    /// caracteres de bech32): com ela igual, os dois enderecos sao da mesma chave de
    /// pagamento, com outra parte de stake, e nao um sosia gerado.
    static let cardanoPaymentCharacters = 44
    /// Na Cardano, a credencial de stake de um endereco e publica: o atacante poe a de um
    /// endereco que o dono usou no seu, com o pagamento dele, e a segunda metade dos dois
    /// fica igual de graca. Com o stake igual e o pagamento diferente, tres caracteres
    /// iguais no fim (o checksum) ja marcam (B-5).
    static let cardanoSameStakeSuffix = 3
    /// "addr1", e os caracteres 0 a 20 do dado: o cabecalho e o comeco do pagamento. Do 26 ao 31 sao os bits 105 a 134, todos do
    /// pagamento.
    static let cardanoPaymentSegmentStart = 26

    /// Menos que isso depois do prefixo da rede nao e endereco gerado (nome curto da NEAR).
    /// O tamanho conta o registro do nome da NEAR: tirar o ".near" do corpo nao deixa de
    /// comparar um nome que ja era comparado.
    public static let minimumLength = 16

    /// O primeiro endereco de `known` parecido com `address`, se houver.
    ///
    /// `forHiding`: a triagem da Atividade, que esconde o recebimento sem como mostrar. Ali ficam de fora as regras dos nomes
    /// curtos da NEAR (o mesmo nome em outro registro, uma edicao abaixo de 8 letras): "alexa.near" mandando 50 NEAR depois de
    /// o dono pagar "alex.near" sumia. No envio e no contato elas valem, e o custo e so digitar o nome (revisao dos 3 agentes,
    /// 08/11/2026).
    public static func lookalike(_ address: String, among known: [String], chain: Chain, forHiding: Bool = false) -> String? {
        let shortNames = !forHiding
        guard let target = Compared(address, chain: chain, shortNames: shortNames) else { return nil }
        let targetAccount = Address.canonicalRecipient(address, chain: chain)
        return known.first { other in
            guard let compared = Compared(other, chain: chain, shortNames: shortNames), compared.text != target.text else { return false }
            if let targetAccount, Address.canonicalRecipient(other, chain: chain) == targetAccount { return false }
            // Na Stellar, o endereco M e a conta base G dele (ou dois M da mesma base) sao
            // a mesma conta com ids diferentes, nao um sosia. O ID trocado entre dois M e
            // outra conferencia (`sameAccountOtherID`).
            if chain.family == .stellar, let a = StellarMuxedAccount(address: other.trimmingCharacters(in: .whitespacesAndNewlines))?.account,
               let b = StellarMuxedAccount(address: address.trimmingCharacters(in: .whitespacesAndNewlines))?.account, a == b {
                return false
            }
            let candidate = compared.body
            let head = commonPrefix(candidate, target.body)
            let tail = commonPrefix(String(candidate.reversed()), String(target.body.reversed()))
            if chain.family == .cardano {
                if head >= cardanoPaymentCharacters { return false }
                if tail >= cardanoSameStakeSuffix, cardanoSameStakeOtherPayment(address, other) { return true }
            }
            if head >= minimumPrefix && tail >= minimumSuffix && head + tail >= minimumTotal { return true }
            // O mesmo nome com outro registro ("bob.near" e "bob.tg"): contas diferentes, de donos diferentes.
            if shortNames, chain.family == .near, !candidate.isEmpty, candidate == target.body { return true }
            if chain.family == .near, !isHex64(candidate), !isHex64(target.body), similarNames(candidate, target.body, shortNames: shortNames) { return true }
            guard let single = singleEndLength(chain, candidate, target.body) else { return false }
            return max(head, tail) >= single
        }
    }

    /// Dois nomes da NEAR parecidos entre si: ate 2 edicoes (letra trocada, posta ou
    /// tirada) com corpo de 8 ou mais, ou um comeco comum que cobre o nome menor menos 2.
    /// Registrar um nome sob ".near" custa centavos e nao pede nenhum caractere gerado:
    /// "coinbase-hot-wa11et", "coinbase-hot-wallets" e "binance-deposit-02" imitam
    /// "coinbase-hot-wallet" e "binance-deposit-01" so com o fim mudado, e o fim do corpo,
    /// sem o ".near", ja nao contava como ponta (revisao do B-9).
    ///
    /// As duas regras valem tambem sobre o nome como o olho le (`visualFold`): com tres
    /// trocas ou mais, "coinbase-h0t-wa11et" e "binanse-dep0sit-07" passavam.
    static func similarNames(_ a: String, _ b: String, shortNames: Bool = true) -> Bool {
        similarSpelling(a, b, shortNames: shortNames) || similarSpelling(visualFold(a), visualFold(b), shortNames: shortNames)
    }

    static func similarSpelling(_ a: String, _ b: String, shortNames: Bool = true) -> Bool {
        let shorter = min(a.count, b.count)
        if commonPrefix(a, b) >= max(nameSharedPrefix, shorter - 2) { return true }
        // Nome curto: uma edicao so ("bob" e "bod", e "b0b" pelo `visualFold`), ou o menor inteiro no comeco do maior ("alice" e
        // "alice01", "alice-pay", "alice.nearx" de "alice.nearx.near"). Antes nada marcava abaixo de 8 letras (revisao dos 3 agentes,
        // 08/11/2026).
        if shorter < nameMinimumForEdits {
            return shortNames && (commonPrefix(a, b) == shorter || editDistance(a, b, limit: 1) <= 1)
        }
        return editDistance(a, b, limit: nameEdits) <= nameEdits
    }

    static let nameSharedPrefix = 6
    static let nameMinimumForEdits = 8
    static let nameEdits = 2

    /// Pares de letras que se leem como uma so, e os caracteres que se passam por outros
    /// num nome de conta (so minusculas, algarismos, "-", "_" e "."): "rn" por "m", "vv" por
    /// "w", "cl" por "d", "0" por "o", "5" por "s", e "1", "i" e "l" juntos. Ficam de fora o
    /// "_" no lugar do "-" (ja e uma edicao, e dobrado somava nomes de numeros diferentes,
    /// "camila-5948" e "camila_9998") e os algarismos que so lembram letras (2, 6, 8, 9),
    /// que transformavam numeros em palavras ("andrew-9016" e "andrew-gomes") sem ganhar
    /// sosia nenhum nas amostras (teste `nearVisualMimics`).
    static let visualPairs: [(String, String)] = [("rn", "m"), ("vv", "w"), ("cl", "d")]
    static let visualSingles: [Character: Character] = ["0": "o", "1": "l", "i": "l", "5": "s"]

    /// O nome como o olho le: dois nomes que so diferem por um sosia visual dobram no mesmo.
    static func visualFold(_ name: String) -> String {
        var text = name
        for (pair, single) in visualPairs { text = text.replacingOccurrences(of: pair, with: single) }
        return String(text.map { visualSingles[$0] ?? $0 })
    }

    /// Distancia de edicao (Levenshtein) entre `a` e `b`, parando em `limit + 1`.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard abs(x.count - y.count) <= limit else { return limit + 1 }
        guard !x.isEmpty, !y.isEmpty else { return max(x.count, y.count) }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + [Int](repeating: 0, count: y.count)
            for j in 1...y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            if current.min()! > limit { return limit + 1 }
            previous = current
        }
        return min(previous[y.count], limit + 1)
    }

    /// Um endereco como a comparacao le, em minusculas: `text`, tudo depois do prefixo da
    /// rede, diz se dois sao o mesmo; `body`, tambem sem o sufixo de nome da NEAR, e de
    /// onde saem as pontas. O mesmo nome sob ".near" e sob ".tg" tem o corpo igual e o
    /// texto diferente: sao contas diferentes, e as duas pontas iguais o marcam.
    private struct Compared {
        let text: String
        let body: String

        init?(_ address: String, chain: Chain, shortNames: Bool) {
            text = AddressPoisoning.afterPrefix(address, chain: chain)
            // O nome da NEAR entra curto ou nao: e escolhido letra a letra e registrado por centavos, e "bob.near" ficava fora de
            // toda comparacao (revisao dos 3 agentes, 08/11/2026). O tamanho minimo e o de endereco gerado.
            let named = shortNames && AddressPoisoning.wholeNEARName(address.trimmingCharacters(in: .whitespacesAndNewlines), chain: chain) != nil
            guard named || text.count >= AddressPoisoning.minimumLength else { return nil }
            body = AddressPoisoning.body(address, chain: chain)
        }
    }

    /// Quantos caracteres iguais numa ponta so ja fazem o par parecido, ou `nil` quando a
    /// regra da ponta so nao vale. Quatro com 32 simbolos ou mais, cinco em hexadecimal:
    /// os dois sao 20 bits, e ao acaso saem perto de duas vezes em um milhao de pares
    /// (as taxas medidas por rede estao no teste).
    static func singleEndLength(_ chain: Chain, _ a: String, _ b: String) -> Int? {
        switch chain.family {
        case .evm, .sui, .aptos:
            return singleEnd
        case .near:
            // Conta com nome e escolhida letra a letra, e nomes com o mesmo comeco ou o
            // mesmo fim sao comuns ("alex...", "...-wallet"): entre dois nomes a ponta so nao
            // vale, e a regra e a de `similarNames`. Com uma conta implicita (64 caracteres
            // hexadecimais) de um lado, vale: um nome feito dos 59 primeiros hex de uma
            // implicita, mais ".near", e um sosia dela. Pelo tamanho so, um nome de 64
            // letras tambem entrava (revisao dos enderecos parecidos, B-9).
            return isHex64(a) || isHex64(b) ? singleEnd : nil
        case .ton:
            // A grafia crua ("0:" e 64 hex) e hexadecimal; a amigavel, base64.
            return isHex64(a) && isHex64(b) ? singleEnd : singleEndWide
        case .utxo, .tron, .xrpl, .stellar, .solana, .cardano, .polkadot:
            return singleEndWide
        }
    }

    /// 64 caracteres hexadecimais (o corpo ja vem em minusculas).
    static func isHex64(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    /// Dois enderecos base da Cardano com a mesma credencial de stake e pagamentos
    /// diferentes.
    static func cardanoSameStakeOtherPayment(_ a: String, _ b: String) -> Bool {
        guard case .success(let first) = CardanoAddress.parse(a), case .success(let second) = CardanoAddress.parse(b),
              let stake = first.stakeHash, stake == second.stakeHash
        else { return false }
        return first.paymentHash != second.paymentHash
    }

    // MARK: Mesma conta, outro ID (Stellar)

    /// O conhecido com a mesma conta base de `address` e outro ID, quando nenhum conhecido
    /// tem a mesma conta com o mesmo ID (revisao dos enderecos parecidos, B-6).
    ///
    /// `lookalike` deixa de fora, de proposito, dois M da mesma base: sao a mesma conta, e
    /// nao um sosia gerado. So que numa corretora o ID e o que diz de qual cliente e o
    /// deposito. Um programa que troca o endereco copiado pode decodificar o M, trocar so
    /// o ID pelo de uma conta do atacante na mesma corretora e codificar de novo: o
    /// endereco continua valido, da mesma conta, e passava por todas as conferencias.
    ///
    /// O que se compara e o par (conta base, ID): o M traz os dois, e um G traz o ID no memo
    /// que vai junto. Por isso `tag` e o memo de um destino G, e `tagged` sao os contatos G
    /// salvos com o memo (revisao do B-6). Um G sem memo (o historico da rede so da a conta
    /// base) nao diz qual ID o dono usou, e nao tem o que comparar.
    public static func sameAccountOtherID(_ address: String, tag: String? = nil, among known: [String],
                                          tagged: [(address: String, tag: String)] = [], chain: Chain) -> SameAccount? {
        guard chain.family == .stellar, let target = muxedPair(address, tag: tag) else { return nil }
        let pairs = known.compactMap { text in muxedPair(text, tag: nil).map { (text: text, pair: $0) } }
            + tagged.compactMap { entry in muxedPair(entry.address, tag: entry.tag).map { (text: entry.address, pair: $0) } }
        // O mesmo par ja usado: e o destino de sempre.
        if pairs.contains(where: { $0.pair == target }) { return nil }
        return pairs.first { $0.pair.account == target.account }.map { SameAccount(known: $0.text, knownID: $0.pair.id) }
    }

    /// Um conhecido com a mesma conta base e outro ID.
    public struct SameAccount: Equatable, Sendable {
        /// O endereco como o dono o tem: um M, ou o G de um contato salvo com o ID no memo.
        public let known: String
        /// O ID desse conhecido.
        public let knownID: UInt64
    }

    /// Conta base e ID: do M, ou do G com um memo que e numero.
    static func muxedPair(_ address: String, tag: String?) -> (account: StellarAccountID, id: UInt64)? {
        guard let account = muxedAccount(address) else { return nil }
        if let id = account.id { return (account.account, id) }
        guard let tag, let id = UInt64(tag.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return (account.account, id)
    }

    /// O dono confirmou o ID de um M com a mesma conta de um conhecido: digitou o numero
    /// do ID que quem vai receber mostra, ou os 6 ultimos caracteres do endereco, lidos onde
    /// ele foi copiado (revisao do B-6).
    ///
    /// Os 6 ultimos so valem como resposta porque nenhum dos dois esta na tela enquanto o
    /// desafio esta: o trecho do ID do colado (que inclui os 6 ultimos) vem escondido, e o
    /// campo do endereco colado some ate o dono apertar "Editar", que desfaz o desafio.
    public static func muxedIDConfirmed(_ typed: String, address: String) -> Bool {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = muxedAccount(text)?.id else { return false }
        if idConfirmed(typed, id: id) { return true }
        let answer = typed.filter { !$0.isWhitespace }
        return answer.count == muxedTailLength && answer.uppercased() == String(text.suffix(muxedTailLength)).uppercased()
    }

    static let muxedTailLength = 6

    /// O numero digitado e `id`. Vale com espacos e com os algarismos do teclado do idioma
    /// (arabicos orientais, persas, devanagari), que viram 0 a 9.
    public static func idConfirmed(_ typed: String, id: UInt64) -> Bool {
        guard let digits = asciiDigits(typed), let number = UInt64(digits) else { return false }
        return number == id
    }

    /// Os algarismos de `text` em 0 a 9, sem os espacos; `nil` se houver qualquer outra coisa.
    static func asciiDigits(_ text: String) -> String? {
        var out = ""
        for scalar in text.unicodeScalars where !scalar.properties.isWhitespace {
            guard scalar.properties.numericType == .decimal, let value = scalar.properties.numericValue,
                  let digit = Int(exactly: value), (0...9).contains(digit) else { return nil }
            out += String(digit)
        }
        return out.isEmpty ? nil : out
    }

    /// O trecho que o dono digita lendo na fonte, quando nao ha com o que comparar: os 6 do
    /// meio do endereco. Num M da Stellar o meio ainda e a chave, igual em todo M da mesma
    /// conta, e a troca so do ID passava; ali o trecho e o fim, o ID e o checksum (revisao
    /// do B-6). Na NEAR com nome, o nome inteiro, com o registro, como no envio (`tailSegment(_:chain:)`): o meio de um nome
    /// o golpista registra por centavos, e nome com menos de 10 caracteres ficava sem desafio (revisao dos 3 agentes, 08/11/2026).
    public static func blindSegment(_ address: String, chain: Chain, length: Int = 6) -> Segment? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let whole = wholeNEARName(text, chain: chain) { return whole }
        // Cardano com stake: o meio (indices 48 a 53) caia 17 bits no pagamento e 13 no stake, que o sosia escolhe de graca, e o
        // sosia saia em segundos de CPU. Os 6 do indice 26 sao do pagamento inteiros, 30 bits como nas outras redes (revisao dos
        // 3 agentes, 09/11/2026).
        if chain.family == .cardano, case .success(let cardano) = CardanoAddress.parse(text), cardano.stakeHash != nil,
           text.count >= cardanoPaymentSegmentStart + length + 6 {
            return Segment(start: cardanoPaymentSegmentStart, length: length)
        }
        if chain.family == .stellar, muxedAccount(text)?.isMuxed == true {
            return Segment(start: text.count - length, length: length)
        }
        return middleSegment(address, length: length)
    }

    /// O trecho do endereco M depois da chave: o ID e o checksum, o que muda quando so o
    /// ID muda. A versao e a chave ocupam 33 bytes, 264 bits; o caractere 52 ainda leva os
    /// 4 ultimos bits da chave (e o bit mais alto do ID), e do 53 em diante e so ID e
    /// checksum.
    public static func muxedIDSegment(_ address: String) -> Segment? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account = muxedAccount(text), account.isMuxed, text.count > muxedIDStart else { return nil }
        return Segment(start: muxedIDStart, length: text.count - muxedIDStart)
    }

    static let muxedIDStart = (1 + 32) * 8 / 5 + 1

    static func muxedAccount(_ address: String) -> StellarMuxedAccount? {
        StellarMuxedAccount(address: address.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Um trecho do endereco, em posicoes de caractere do texto como ele e mostrado.
    public struct Segment: Equatable, Sendable {
        public let start: Int
        public let length: Int

        public init(start: Int, length: Int) {
            self.start = start
            self.length = length
        }

        /// O trecho dentro de `address`.
        public func text(in address: String) -> String {
            String(address.dropFirst(start).prefix(length))
        }
    }

    /// Os `length` caracteres do meio do endereco: o que o dono le e digita quando nao ha
    /// com o que comparar (historico da rede ilegivel, auditoria 3, B1).
    public static func middleSegment(_ address: String, length: Int = 6) -> Segment? {
        let count = address.count
        guard count >= length + 4 else { return nil }
        return Segment(start: (count - length) / 2, length: length)
    }

    /// Os `length` ultimos caracteres do endereco: o desafio de "Conferir o endereco em todo
    /// envio" (Ajustes, Seguranca), que o dono le na fonte e digita (pedido do dono, 23/10/2026).
    public static func tailSegment(_ address: String, length: Int = 6) -> Segment? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= length + 4 else { return nil }
        return Segment(start: text.count - length, length: length)
    }

    /// O fim do endereco para o desafio do envio. Na NEAR com nome, o nome inteiro, com o registro (".near", ".tg"): quem
    /// registra escolhe as letras, entao qualquer pedaco do nome sai quase de graca para o golpista, e sem o registro
    /// "alice.near" passava no lugar de "alice.tg" (revisao dos 3 agentes, 08/11/2026).
    public static func tailSegment(_ address: String, chain: Chain, length: Int = 6) -> Segment? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let whole = wholeNEARName(text, chain: chain) { return whole }
        return tailSegment(text, length: length)
    }

    /// A conta NEAR com nome inteira, como trecho; nil fora dela.
    public static func wholeNEARName(_ text: String, chain: Chain) -> Segment? {
        guard chain.family == .near, case .success(let account) = NEARAccountID.parse(text), account.kind == .named else { return nil }
        return Segment(start: 0, length: text.count)
    }

    /// O campo do destino recebeu o endereco inteiro de uma vez (o Colar do menu, por cima ou nao de uma selecao): o que entrou,
    /// medido pelo comeco e pelo fim em comum, tem mais de um caractere e ponto, ou trocou caracteres, ou o resultado termina no
    /// registro ou tem 32 ou mais. Deslizar
    /// no teclado ou aceitar uma sugestao poe uma palavra sem ponto, e contar so o tamanho armava o desafio no comeco do nome;
    /// colar por cima de um texto do mesmo tamanho nao armava (revisao dos 3 agentes, 09/11/2026).
    public static func enteredWhole(from old: String, to new: String) -> Bool {
        let a = Array(old), b = Array(new)
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        var end = 0
        while end < a.count - start, end < b.count - start, a[a.count - 1 - end] == b[b.count - 1 - end] { end += 1 }
        // So o trecho que entrou: deslizar "alice" no teclado depois de "pay." dava ponto no resultado e armava no meio do nome. O
        // registro no fim conta (completar "alice." com "near"). Sem ponto, so as contas de topo antigas da NEAR, de 32 caracteres
        // ou mais: desde a NEP-492 so o registrador cria conta de topo, e os nomes curtos sem ponto sao dos projetos.
        let inserted = b[start..<(b.count - end)]
        // Trocar caracteres (colar por cima de um nome parecido, "a1ic3.sweat" sobre "alice.sweat") e entrada inteira: deslizar no
        // teclado so acrescenta.
        // So quando o resultado pode ser conta que o golpista registra (com ponto, ou 32 ou mais): a sugestao do teclado que troca
        // uma palavra ("allure" por "alice") nao arma no meio do nome.
        let removed = a.count - start - end
        let registrable = new.contains(".") || new.count >= 32
        // Mais de um caractere de uma vez, ou um trocado por outro (colar por cima de um nome com uma letra de diferenca). Os 32 sao
        // do que entrou, e nao do resultado: deslizar uma palavra no fim de um nome longo nao arma no meio dele.
        guard inserted.count > 1 || (removed > 0 && !inserted.isEmpty) else { return false }
        return inserted.contains(".") || (removed > 0 && registrable) || new.hasSuffix(".near") || new.hasSuffix(".tg") || inserted.count >= 32
    }

    /// Texto que nao vale na rede escolhida mas e um nome da NEAR (a sugestao da NEAR, ou um nome fora de ".near" e ".tg"): colado
    /// inteiro, o campo fica escondido ate a troca de rede. O bech32 e o addr1 de outra rede tambem passam pela gramatica do nome,
    /// e ficam de fora pela sugestao da rede deles (revisao dos 3 agentes, 09/11/2026).
    public static func looksLikeNEARName(_ text: String) -> Bool {
        guard let near = Chain.all.first(where: { $0.id == "near" }), wholeNEARName(text, chain: near) != nil else { return false }
        if let guess = Address.guessChain(text) { return guess.id == near.id }
        // Sem sugestao: com ponto (um nome fora de ".near" e ".tg"), ou uma conta de topo antiga, de 32 ou mais, que nao comeca
        // como o bech32 de outra rede: um bc1 cortado fica a vista com o erro.
        if text.contains(".") { return true }
        // Hexadecimal (um 0x ou uma chave cortados, o EVM sem 0x, a Tron em hex) e bech32 de rede fora do app nao sao nome: ficam
        // a vista com o erro (revisao dos 3 agentes, 09/11/2026).
        if text.hasPrefix("0x") || text.allSatisfy(\.isHexDigit) || Bech32.decode(text) != nil { return false }
        return text.count >= 32 && !["bc1", "ltc1", "tb1", "addr1", "addr_test1", "stake1", "stake_test1"].contains(where: text.hasPrefix)
    }

    /// O texto vale como destino noutra rede (o nome da NEAR so com `looksLikeNEARName`, porque quase todo texto minusculo passa na
    /// gramatica dele): no contato a rede e livre, e o endereco da Sui, da Aptos ou a conta implicita da NEAR, que nao tem sugestao,
    /// ficava a vista ate a troca e o desafio (revisao dos 3 agentes, 09/11/2026).
    public static func validElsewhere(_ text: String, than chain: Chain) -> Bool {
        Chain.all.contains { other in
            guard other.id != chain.id, case .success = Address.validate(text, for: other) else { return false }
            return wholeNEARName(text, chain: other) == nil || looksLikeNEARName(text)
        }
    }

    /// Um nome da NEAR (com ponto) colado noutra rede, sem sugestao: o aviso diz que e um nome, e nao manda copiar de novo.
    public static func nameNotAddress(_ text: String, on chain: Chain) -> Bool {
        guard chain.family != .near, text.contains("."), let near = Chain.all.first(where: { $0.id == "near" }) else { return false }
        return wholeNEARName(text, chain: near) != nil
    }

    /// O maximo que o campo do nome inteiro aceita: mais que o trecho, para quem digita o nome verdadeiro, mais comprido que o
    /// colado, nao parar no tamanho dele e passar com o comeco (revisao dos 3 agentes, 08/11/2026).
    public static let wholeNameLimit = NEARAccountID.maxLength

    /// O digitado responde o trecho de `address`: o mesmo tamanho e o mesmo texto. A caixa conta onde ela e parte do endereco
    /// (`caseMatters`): ali, aceitar qualquer caixa barateava de 30 a 60 vezes o sosia que passa nos 6 (revisao dos 3 agentes,
    /// 08/11/2026; o dono escolheu a caixa exata). Sem rede, exata.
    public static func answers(_ typed: String, segment: Segment, of address: String, chain: Chain?) -> Bool {
        let answer = typed.trimmingCharacters(in: .whitespaces)
        let expected = segment.text(in: address)
        guard answer.count == segment.length else { return false }
        guard let chain, !caseMatters(address, chain: chain) else { return answer == expected }
        return answer.lowercased() == expected.lowercased()
    }

    /// A caixa e parte do endereco: base58 (Solana, Tron, XRPL, Polkadot, Bitcoin, Litecoin e Dogecoin antigos, Cardano Byron) e o
    /// base64 da forma amigavel da TON. Nao e no hexadecimal (o EIP-55 e so conferencia), no bech32, no nome da NEAR e no base32 da
    /// Stellar, que tem uma caixa so.
    public static func caseMatters(_ address: String, chain: Chain) -> Bool {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch chain.family {
        case .evm, .sui, .aptos, .near, .stellar:
            return false
        case .utxo:
            if let hrp = UTXOParams.for(chain).bech32HRP, text.hasPrefix(hrp + "1") { return false }
            return true
        case .cardano:
            return !text.hasPrefix("addr")
        case .ton:
            return !text.contains(":")
        case .tron, .xrpl, .solana, .polkadot:
            return true
        }
    }

    /// O trecho e o endereco inteiro: na NEAR com nome, o dono digita o nome todo.
    public static func coversAll(_ segment: Segment, of address: String) -> Bool {
        segment.start == 0 && segment.length == address.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    /// Onde `address` comeca a diferir de `other`: os `length` caracteres a partir da
    /// primeira diferenca depois do prefixo da rede. E o trecho que o desafio pede:
    /// as pontas o atacante copia, o meio ele nao consegue (auditoria 2, M2).
    /// Na NEAR com nome, o nome inteiro, como nos desafios escondidos: nome curto ficava sem trecho, e o Continuar travava.
    public static func differingSegment(_ address: String, from other: String, chain: Chain, length: Int = 6) -> Segment? {
        let shown = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let whole = wholeNEARName(shown, chain: chain) { return whole }
        let target = afterPrefix(shown, chain: chain)
        let candidate = afterPrefix(other, chain: chain)
        guard target.count >= length, target != candidate else { return nil }
        let fixed = shown.count - target.count
        let first = fixed + commonPrefix(target, candidate)
        let start = min(first, shown.count - length)
        return Segment(start: max(start, fixed), length: length)
    }

    /// O endereco sem o prefixo que a rede impoe (e, na NEAR, sem o registro do nome), em
    /// minusculas.
    static func body(_ address: String, chain: Chain) -> String {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return bodySegment(text, chain: chain).text(in: text).lowercased()
    }

    /// Tudo depois do prefixo que a rede impoe, em minusculas, com o registro do nome da
    /// NEAR: e por ele que se sabe se dois enderecos sao o mesmo texto.
    static func afterPrefix(_ address: String, chain: Chain) -> String {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.dropFirst(bodySegment(text, chain: chain).start)).lowercased()
    }

    /// Onde fica o corpo do endereco, no texto como ele e mostrado (sem espaco nas pontas):
    /// tudo depois do prefixo que a rede impoe e, na NEAR, antes do registro do nome. A
    /// tela abrevia por aqui (`Fmt.address`), para os 6 do comeco serem do corpo, e nao o
    /// "addr1q" que todo endereco tem.
    public static func bodySegment(_ address: String, chain: Chain) -> Segment {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let count = text.count
        let start: Int
        switch chain.family {
        case .evm, .sui, .aptos:
            start = text.hasPrefix("0x") ? 2 : 0
        case .utxo:
            if let hrp = UTXOParams.for(chain).bech32HRP, text.hasPrefix(hrp + "1") {
                start = min(hrp.count + 2, count)  // hrp, separador e versao (q, p)
            } else {
                start = min(1, count)  // caractere de versao do base58
            }
        case .tron, .xrpl, .stellar:
            start = min(1, count)
        case .ton:
            start = text.hasPrefix("0:") || count > 2 ? 2 : 0
        case .solana:
            start = 0
        case .cardano:
            // "addr1" e o caractere do cabecalho (tipo de endereco), que o atacante copia
            // de graca, como o hrp e a versao do bech32 no Bitcoin.
            start = text.hasPrefix("addr1") && count > 6 ? 6 : 0
        case .polkadot:
            // O prefixo de rede 0 faz todo endereco da Polkadot comecar com 1.
            start = min(1, count)
        case .near:
            // Conta implicita sem prefixo; nome inteiro, que o dono escolhe letra a letra,
            // menos o registro do fim (".near", ".tg"): ele e igual por desenho, e contado
            // como ponta fazia "alexis-exchange.near" parecido com "alexander-wallet.near"
            // (B-9).
            if let suffix = NEARAccountID.registrySuffixes.first(where: { text.hasSuffix($0) && count > $0.count }) {
                return Segment(start: 0, length: count - suffix.count)
            }
            start = 0
        }
        return Segment(start: start, length: count - start)
    }

    static func commonPrefix(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }
}
