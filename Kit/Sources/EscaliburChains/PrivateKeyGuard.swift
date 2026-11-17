import EscaliburCore
import Foundation

/// Texto que e uma chave privada, e nao um endereco: como a frase (`PaymentLink.looksLikePhrase`), nunca fica num campo de
/// endereco nem vai para uma busca, por colar, digitar ou ler QR. So a frase era barrada, e a chave colada no Para ficava em
/// claro na tela (revisao dos 3 agentes, 09/11/2026).
///
/// Os 64 hexadecimais nao entram aqui: sao tambem a conta implicita da NEAR e o endereco da Sui e da Aptos. Por rede, eles
/// passam por `looksLikeHexKey(_:on:)`; no que vai a rede e fica publico, por `publicTextHasSecret`.
///
/// Toda entrada passa antes por `visible`: o texto em NFKC (os algarismos e as letras de largura cheia viram os comuns) e sem os
/// caracteres de formato (o espaco de largura zero, o hifen suave), que o `Mnemonic.canonicalize` tira ao importar e que
/// furavam todas as regras daqui.
public enum PrivateKeyGuard {
    /// O que um texto livre traz, para o aviso dizer o que fazer.
    public enum FreeTextSecret: Equatable, Sendable {
        case none
        /// Uma chave, o SeedQR ou os numeros do Xaman.
        case secret
        /// Palavras seguidas das listas BIP-39, com o trecho que pesou: o aviso o mostra, para quem so conversava trocar uma.
        case words(String)
        /// Hexadecimais longos: uma chave da MetaMask ou o codigo de uma transacao, que tem campo proprio.
        case hex
        /// 64 hexadecimais no ID da transacao sem a rede escolhida: so a rede diz se e o codigo de uma transacao dela ou uma chave.
        case needsNetwork
    }

    /// A chave sozinha, ou dentro do texto: entre aspas (retas ou curvas), crases ou colchetes, com pontuacao no fim, com rotulo
    /// ("WIF: 5H..."), com o esquema de um link ("bitcoin:", "stellar:"), num arquivo .env ("PRIVATE_KEY=..."), partida em linhas,
    /// no vetor de numeros da Solana ou nos numeros secretos do Xaman.
    public static func looksLikePrivateKey(_ raw: String) -> Bool {
        let text = visible(raw)
        guard (16...4096).contains(text.count) else { return false }
        return hasKey(text, signatureAllowed: false)
    }

    /// O segredo num campo de endereco (o Para, o contato, o observar): as 12 palavras soltas ou mais (separadas por espaco,
    /// virgula, ponto e virgula ou hifen), um pedaco da frase, a chave, o SeedQR e os 64 hexadecimais com o rotulo de chave.
    /// Nenhum endereco das redes do app forma seis palavras seguidas das listas.
    public static func looksLikeSecretInAddressField(_ raw: String) -> Bool {
        let text = visible(raw)
        let spaced = text.replacingOccurrences(of: "[,;\\-]", with: " ", options: .regularExpression)
        if Mnemonic.words(in: spaced).count >= 12 { return true }
        return looksLikePrivateKey(text) || phraseRun(text) != nil || looksLikeSeedNumbers(text) || pieces(text).contains(where: isSeedQR)
            || hasLabeledHexKey(text) || longestHanRun(text) >= 6
    }

    /// Os 64 hexadecimais com o rotulo de chave antes ("PRIVATE_KEY=", "minha chave privada:"): o aviso e o da chave.
    public static func looksLikeLabeledHexKey(_ raw: String) -> Bool {
        hasLabeledHexKey(visible(raw))
    }

    /// O que o Colar do app tira tambem da area de transferencia, igual nas duas plataformas: o segredo de um campo de endereco,
    /// o do texto livre, os 64 hexadecimais que nesta rede nao sao endereco e o link que o `PaymentLink` recusa por segredo.
    public static func clipboardHasSecret(_ raw: String, on chain: Chain?) -> Bool {
        if looksLikeSecretInAddressField(raw) || containsSecret(raw) || looksLikeHexKey(raw, on: chain) { return true }
        do {
            _ = try PaymentLink.read(raw)
            return false
        } catch PaymentLink.Problem.containsPhrase, PaymentLink.Problem.containsPrivateKey {
            return true
        } catch {
            return false
        }
    }

    /// Texto livre (o ID da transacao no suporte) com um segredo: a chave em algum lugar do texto, o SeedQR ou as palavras
    /// seguidas de uma lista BIP-39. Contar palavras soltas, de qualquer texto, recusava todo chamado de 12 palavras (revisao dos
    /// 3 agentes, 09/11/2026). A assinatura de uma transacao da Solana (64 bytes, como a chave) passa, e os 64 hexadecimais
    /// tambem: ali eles sao o codigo da transacao.
    public static func containsSecret(_ raw: String) -> Bool {
        freeTextSecret(raw, hexAllowed: true) != .none
    }

    /// O que vai a rede e fica publico para sempre (o comentario da TON, o memo da Stellar, a tag), e o texto do chamado do
    /// suporte: alem do `containsSecret`, 48 hexadecimais ou mais seguidos, com ou sem 0x, com rotulo ("pk-", "key_") ou em
    /// grupos (a chave da MetaMask, da TronLink, a semente da Polkadot, o par de 128 cortado). Nenhuma corretora pede um
    /// comentario assim, o memo de hash da Stellar o app nao usa, e o codigo da transacao do chamado tem campo proprio.
    public static func publicTextHasSecret(_ raw: String) -> Bool {
        freeTextSecret(raw, hexAllowed: false) != .none
    }

    /// O texto livre e o que ele traz. `hexAllowed`: os hexadecimais longos passam (o campo do ID da transacao).
    /// No texto livre, as palavras de funcao do ingles (you, this, can, now) contam como posicao, nao como palavra da lista.
    /// `addressesOn`: no texto do chamado, passam so os 64 hexadecimais que o app ja conhece na rede escolhida (`known`) e a TON
    /// crua no chamado da TON; com rotulo de chave, so o conhecido.
    /// `known`: os enderecos da rede que o app ja conhece (as contas, os contatos, os destinos de envios), em hex minusculo sem
    /// 0x. So eles passam no texto: o formato sozinho nao separa a chave da Petra do endereco da Aptos.
    public static func freeTextSecret(_ raw: String, hexAllowed: Bool, addressesOn chain: Chain? = nil, known: Set<String> = []) -> FreeTextSecret {
        let text = visible(raw)
        guard !text.isEmpty else { return .none }
        // Mais do que a conferencia alcanca nao sai: os campos param em 4096.
        guard text.count <= 4096 else { return .secret }
        if looksLikeSeedNumbers(text) || pieces(text).contains(where: isSeedQR) { return .secret }
        if text.count >= 16, hasKey(text, signatureAllowed: true) || hasCutSolanaKey(text) { return .secret }
        if let run = phraseRun(text, conversational: true) { return .words(run) }
        // Com rotulo de chave ("chave privada: 0x..."), o hex nunca e o endereco da rede: a chave da Petra no chamado da Aptos saia.
        // A TON crua no chamado da TON e endereco, tambem com um rotulo por perto ("importei a seed e o endereco ficou 0:...").
        var known = known
        if chain?.family == .ton { known.formUnion(pieces(text).filter { isHex64($0) && isTONRaw($0, in: text) }.map(hexKey)) }
        if !hexAllowed, hasLabeledHexKey(text, known: known) { return .secret }
        if !hexAllowed, hasLongHex(withoutAddresses(text, on: chain, known: known)) { return .hex }
        return .none
    }

    /// O chamado do suporte. O texto: sem hexadecimais longos, fora o endereco da rede escolhida. O ID da transacao: os 64
    /// hexadecimais passam so no formato do codigo de transacao da rede (com ou sem 0x); sem a rede, ela e pedida antes. A chave
    /// da MetaMask movida do texto para o ID saia por e-mail (revisao dos 3 agentes, 09/11/2026).
    public static func supportSecret(details: String, transaction: String, chain: Chain?, known: Set<String> = []) -> FreeTextSecret {
        let found = freeTextSecret(details, hexAllowed: false, addressesOn: chain, known: known)
        if found != .none { return found }
        let id = visible(transaction)
        let inID = freeTextSecret(id, hexAllowed: true)
        if inID != .none { return inID }
        // Partido em linhas, em grupos ou com hifen, o hex tambem e conferido, com e sem o rotulo.
        let compact = id.filter { !$0.isWhitespace && $0 != "-" }
        if hasLabeledHexKey(id) || hasLabeledHexKey(id.filter { !$0.isWhitespace }) { return .secret }
        let candidates = [id, compact] + pieces(id) + pieces(compact)
        // Dois codigos de transacao da rede lado a lado nao sao uma chave de 128.
        let fitting = pieces(id).filter { piece in isHex64(piece) && chain.map { transactionHashFits(piece, on: $0) } == true }.count
        // A chave do xrpl.js (66, com 00 ou ED na frente) e os 128 hexadecimais nao tem o tamanho de codigo de transacao nenhum.
        for piece in candidates {
            let lower = piece.lowercased()
            let body = lower.hasPrefix("0x") ? lower.dropFirst(2) : Substring(lower)
            guard body.allSatisfy(\.isHexDigit) else { continue }
            // O UID de uma ordem da CoW (56 bytes: o digesto, o dono e o prazo), com o dono sendo uma conta desta carteira: nao e
            // chave, e o dono o cola no ID para o suporte achar a ordem (rodada 1 da auditoria 8).
            if Self.isOwnCoWOrderUID(body, known: known) { continue }
            // So 64, ou dois ou tres codigos da rede lado a lado; qualquer outro hex de 48 ou mais (a chave do xrpl.js com 66, o
            // cborHex da Cardano com 68, a chave cortada, os 128 que nao sao dois codigos) nao e codigo de transacao.
            if body.count >= 48, !(body.count % 64 == 0 && body.count / 64 <= max(fitting, 1)) { return .secret }
        }
        for piece in candidates where isHex64(piece) {
            guard let chain else { return .needsNetwork }
            if !transactionHashFits(piece, on: chain) { return .secret }
        }
        return .none
    }

    /// 112 hexadecimais com os bytes 32 a 52 iguais a um endereco EVM que o app conhece (o dono da ordem da CoW).
    static func isOwnCoWOrderUID(_ body: Substring, known: Set<String>) -> Bool {
        guard body.count == 112 else { return false }
        let owner = String(body.dropFirst(64).prefix(40))
        return known.contains { address in
            let lower = address.lowercased()
            return (lower.hasPrefix("0x") ? String(lower.dropFirst(2)) : lower) == owner
        }
    }

    /// Os 64 hexadecimais (com ou sem 0x) que, nesta rede, nao sao endereco: a chave da MetaMask, da TronLink ou a semente da
    /// Polkadot (ou o codigo de uma transacao). Na NEAR, o sem 0x so e conta quando o ponto esta na curva; na Sui e na Aptos, so
    /// o com 0x. Sem rede (o endereco so de observacao), so o que nao e endereco em lugar nenhum.
    ///
    /// Tambem com enfeite (aspas, ponto final, rotulo, partido em linhas ou em grupos): enfeitado, nunca e endereco, e na NEAR e
    /// sem rede vira chave mesmo com o ponto na curva. E os 66 hexadecimais da chave do xrpl.js (00 ou ED na frente). O endereco
    /// cru da TON ("0:", "-1:") passa.
    public static func looksLikeHexKey(_ raw: String, on chain: Chain?) -> Bool {
        let shown = visible(raw)
        let bare = shown.filter { !$0.isWhitespace }.trimmingCharacters(in: decorations)
        let xrplKey = { (piece: String) -> Bool in
            let lower = piece.lowercased()
            return lower.count == 66 && (lower.hasPrefix("00") || lower.hasPrefix("ed")) && lower.allSatisfy(\.isHexDigit)
        }
        if xrplKey(bare) || pieces(shown).contains(where: xrplKey) { return true }
        // O hex logo depois de "0:" ou "-1:" (sem letra ou algarismo antes e sem 0x) e o endereco cru da TON, tambem dentro de um
        // link, na TON, sem rede, ou quando o texto inteiro e um (colado na rede errada, a validacao sugere a TON). Um rotulo que
        // termina em 1 ("Wallet 1:") ou com espaco ou linha entre os dois-pontos e o hex ("Conta 0: ") nao conta: a chave ficava a
        // vista. "Conta 0:<hex>", grudado, passa como a TON crua, que tem essa forma.
        let wholeTONRaw = shown.range(of: "^(?:ton://transfer/)?(?:0|-1):[0-9A-Fa-f]{64}(?:\\?.*)?$", options: .regularExpression) != nil
        let tonRawAllowed = chain == nil || chain?.family == .ton || wholeTONRaw
        // Nas redes em que 64 hexadecimais nunca sao endereco, qualquer trecho longo de hex e chave, com uma palavra do lado ("MetaMask
        // <hex>") ou partido em linhas.
        if let family = chain?.family, ![.near, .sui, .aptos, .ton].contains(family), !wholeTONRaw, hasLongHex(shown) { return true }
        // Os pedacos do texto como ele esta (a palavra vizinha separada por espaco) e sem os espacos (a chave partida em linhas).
        // E sem o hifen (a chave em grupos "4c4c-4c4c-..."), que conta como enfeite.
        let joined = bare.filter { $0 != "-" }
        let candidates = (isHex64(bare) ? [bare] : []) + (isHex64(joined) && joined != bare ? [joined] : [])
            + pieces(shown).filter(isHex64) + pieces(bare).filter(isHex64)
        let usable = candidates.filter { !(tonRawAllowed && isTONRaw($0, in: shown)) }
        // O link da NEAR para a conta implicita ("near:<hex>"), e o da Sui e da Aptos ("sui:0x..."), nao sao enfeite: o PaymentLink
        // os le.
        let link = { (hex: String) -> Bool in
            guard let reading = try? PaymentLink.parse(shown), let family = reading.family else { return false }
            return [.near, .sui, .aptos].contains(family) && reading.address == hex
        }
        return usable.contains { text in
            let decorated = text != shown && !link(text)
            let has0x = text.hasPrefix("0x") || text.hasPrefix("0X")
            let body = has0x ? String(text.dropFirst(2)) : text
            let onCurve = Hex.decode(body.lowercased()).map(Edwards25519.isOnCurve) ?? false
            switch chain?.family {
            case .near?: return has0x || decorated || !onCurve
            // Enfeitado ("(0) 0x...", entre aspas, com palavra), o 0x mais 64 nao e o endereco colado: e a chave da Petra.
            case .sui?, .aptos?: return !has0x || decorated
            // Sem rede (o observar, a moeda custom sem rede), nenhum fluxo aceita 64 hex: o app nao da palpite de Sui, Aptos nem da
            // implicita da NEAR, e a moeda custom nao existe nessas redes. Metade das chaves da MetaMask passava pela curva.
            case nil: return true
            default: return true
            }
        }
    }

    // MARK: A frase

    /// As palavras das listas BIP-39 no texto, e o trecho que pesou:
    /// - seis seguidas da lista (a frase inteira ou um pedaco dela);
    /// - nove da lista, ou do comeco de 4 letras, em quaisquer doze seguidas (a frase com tres erros de digitacao);
    /// - oito seguidas contando o comeco de 4 letras de uma palavra latina (a frase gravada na placa de aco);
    /// - oito seguidas da lista do SLIP-39 (a parte do backup do Trezor, que sozinha e a carteira inteira);
    /// - a frase chinesa digitada sem espaco, inteira e com o checksum do BIP-39 fechando.
    /// As latinas sao comparadas sem acento; o japones, o coreano e os dois chineses, como estao. Uma letra latina sozinha nao
    /// conta nem quebra a conta, para a frase numerada ("a) abandon b) ability") seguir contando. `conversational`: no texto do
    /// chamado, as palavras de funcao do ingles nao contam, e o chamado normal em ingles nao e barrado.
    public static func phraseRun(_ raw: String, conversational: Bool = false) -> String? {
        phraseRun(raw, conversational: conversational, transformed: false)
    }

    private static func phraseRun(_ raw: String, conversational: Bool, transformed: Bool) -> String? {
        let text = transformed ? raw : visible(raw)
        if let han = hanPhrase(text) { return han }
        // As palavras de funcao do ingles (no texto livre) contam como posicao, mas nao como palavra: tiradas da conta, a frase com
        // dois ou tres erros e uma "about" voltava a passar no comentario (revisao dos 3 agentes, 09/11/2026).
        if let glued = gluedPhrase(text) ?? gluedPhrase(Self.joiningSpacedLetters(text)) { return glued }
        // A frase com algarismo no lugar de letra ("ab4nd0n 4b1l1ty"): lida de novo com as letras de volta (rodada 1 da auditoria 8).
        if !transformed, text.contains(where: \.isNumber) {
            for undone in Self.undigited(text) where undone != text {
                if let found = phraseRun(undone, conversational: conversational, transformed: true) { return found }
            }
        }
        let all = phraseTokens(text, conversational: conversational)
        let tokens = all.filter { $0.kind != .neutral }
        guard all.count >= 6 else { return nil }
        func snippet(_ list: [PhraseToken], _ first: Int, _ last: Int) -> String {
            String(text[list[first].range.lowerBound..<list[last].range.upperBound])
        }
        // A primeira sequencia com o tamanho e o minimo de palavras da lista, inteira (o aviso mostra tudo o que pesou).
        func run(_ list: [PhraseToken], _ minimum: Int, words: Int, _ counts: (PhraseToken) -> Bool) -> String? {
            var start = 0
            for index in Array(list.indices) + [list.count] {
                if index < list.count, counts(list[index]) { continue }
                let span = list[start..<index]
                if span.count >= minimum, span.filter({ $0.kind == .word }).count >= words { return snippet(list, start, index - 1) }
                start = index + 1
            }
            return nil
        }
        if let found = run(all, 6, words: 5, { $0.kind == .word || $0.kind == .neutral }) { return found }
        // A janela de 12 (ou o texto todo, com 10 ou 11): no maximo tres de fora das listas, e ao menos sete da lista.
        let size = min(12, all.count)
        if size >= 10 {
            for first in 0...(all.count - size) {
                let window = all[first..<first + size]
                let real = window.filter { $0.kind == .word || $0.kind == .prefix }.count
                let neutral = window.filter { $0.kind == .neutral }.count
                if real + neutral >= size - 3, real >= 7 { return snippet(all, first, first + size - 1) }
            }
        }
        return run(tokens, 8, words: 0, { $0.kind != .other }) ?? run(tokens, 8, words: 0, { $0.slip })
    }

    /// Quantas palavras do texto estao numa lista, ou sao o comeco de 4 letras de uma: a busca de moedas nao manda tres.
    public static func listTokenCount(_ raw: String) -> Int {
        phraseTokens(visible(raw), conversational: false).filter { $0.kind != .other }.count
    }

    /// A maior sequencia de palavras seguidas do texto que estao numa lista BIP-39.
    public static func longestWordRun(_ raw: String) -> Int {
        var longest = 0, run = 0
        for token in phraseTokens(visible(raw), conversational: false) {
            run = token.kind == .word ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    /// A maior sequencia de caracteres seguidos que estao nas listas chinesas: a frase digitada sem espaco, como o teclado chines
    /// escreve. So para a busca: num texto em chines, doze seguidos da lista aparecem em conversa comum.
    public static func longestHanRun(_ raw: String) -> Int {
        var longest = 0, run = 0
        for character in visible(raw) {
            run = hanWords.contains(String(character)) ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    /// O SeedQR (a frase em numeros): 48 ou 96 algarismos, juntos ou em grupos de 4, cada grupo um indice da lista (ate 2047). Um
    /// grupo fora disso e tolerado (um erro de digitacao).
    public static func looksLikeSeedNumbers(_ raw: String) -> Bool {
        let text = visible(raw)
        if isSeedQR(text.filter { !$0.isWhitespace }) { return true }
        // Os grupos no meio do texto, numerados ("1. 0012"), com hifen ou com virgula. Uma letra ou uma barra entre eles recomeca
        // a conta: doze datas ("01/10/2025") ou valores com o mes ("jan 1500") nao sao SeedQR.
        var groups = 0, wrong = 0
        var separator = "", digits = ""
        func take() {
            if separator.contains(where: { $0.isLetter || $0 == "/" }) { groups = 0; wrong = 0 }
            switch digits.count {
            case 4:
                if (Int(digits) ?? 9999) > 2047 { wrong += 1 }
                if wrong > 1 { groups = 0; wrong = 0 } else { groups += 1 }
            case 1, 2: break
            default: groups = 0; wrong = 0
            }
            separator = ""
            digits = ""
        }
        for character in text {
            if ("0"..."9").contains(character) {
                digits.append(character)
            } else {
                if !digits.isEmpty {
                    take()
                    if groups >= 12 { return true }
                }
                separator.append(character)
            }
        }
        if !digits.isEmpty { take() }
        return groups >= 12
    }

    private enum TokenKind { case word, prefix, other, neutral }
    private struct PhraseToken {
        let range: Range<String.Index>
        let kind: TokenKind
        /// Na lista do SLIP-39.
        let slip: Bool
    }

    /// O que separa as palavras: o que nao e letra, e a letra modificadora (U+02BC, U+02C8, que se leem como apostrofo e acento,
    /// e que nenhuma lista tem): "abandonʼability" colava as duas e passava (auditoria 8, 14/11/2026).
    static func isWordSeparator(_ character: Character) -> Bool {
        !character.isLetter || character.unicodeScalars.allSatisfy { $0.properties.generalCategory == .modifierLetter }
    }

    /// A palavra como a lista a guarda: as letras de outro alfabeto identicas a uma latina trocadas por ela (o "а" e o "е"
    /// cirilicos, o "ο" grego; `TokenSafety.fold`), sem acento e em minusculas. "аbаndоn" com tres cirilicas passava.
    static func listForm(_ word: String) -> String {
        WordLexicon.fold(TokenSafety.fold(word)).lowercased()
    }

    /// A frase colada sem espaco, ou em CamelCase ("abandonabilityable...", "AbandonAbilityAble..."): um trecho so de letras, de
    /// 18 ou mais, que se divide inteiro em seis ou mais palavras das listas latinas. A frase colada tem as palavras inteiras da
    /// lista; o texto comum colado (um usuario, uma frase em ingles ou portugues) tem palavras de fora, e nao se divide
    /// (medido em 5 mil textos colados de palavras de dicionario, nenhum barrado; auditoria 8, 14/11/2026).
    static func gluedPhrase(_ text: String) -> String? {
        for token in text.split(whereSeparator: isWordSeparator) where token.count >= 18 {
            let letters = Array(listForm(String(token)))
            guard letters.allSatisfy(\.isASCII) else { continue }
            if wordsCovering(letters) >= 6 { return String(token) }
        }
        return nil
    }

    /// O texto com os algarismos de dentro das palavras trocados pela letra que imitam (0 o, 1 i ou l, 3 e, 4 a, 5 s, 7 t), nas
    /// duas leituras do 1. So nas palavras com duas letras ou mais: "100 USDT" fica como esta.
    static func undigited(_ text: String) -> [String] {
        let common: [Character: Character] = ["0": "o", "3": "e", "4": "a", "5": "s", "7": "t"]
        return [Character("i"), Character("l")].map { one -> String in
            var out = ""
            var word = ""
            func flush() {
                if word.filter(\.isLetter).count >= 2 {
                    out += String(word.map { $0 == "1" ? one : (common[$0] ?? $0) })
                } else {
                    out += word
                }
                word = ""
            }
            for character in text {
                if character.isLetter || character.isNumber { word.append(character) } else { flush(); out.append(character) }
            }
            flush()
            return out
        }
    }

    /// As letras soltas seguidas ("a b a n d o n", "a.b.a.n.d.o.n") juntas num trecho so, para a frase colada: tres ou mais
    /// letras sozinhas, separadas por um caractere que nao e letra (rodada 1 da auditoria 8).
    static func joiningSpacedLetters(_ text: String) -> String {
        let characters = Array(text)
        func alone(_ index: Int) -> Bool {
            characters[index].isLetter && (index == 0 || !characters[index - 1].isLetter)
                && (index + 1 == characters.count || !characters[index + 1].isLetter)
        }
        var out = ""
        var index = 0
        while index < characters.count {
            if alone(index) {
                var run = [characters[index]]
                var last = index
                while last + 2 < characters.count, !characters[last + 1].isLetter, alone(last + 2) {
                    run.append(characters[last + 2])
                    last += 2
                }
                if run.count >= 3 {
                    out += String(run)
                    index = last + 1
                    continue
                }
            }
            out.append(characters[index])
            index += 1
        }
        return out
    }

    /// Quantas palavras das listas latinas, no maximo, cobrem o trecho inteiro, de ponta a ponta; 0 se nao cobrem.
    static func wordsCovering(_ letters: [Character]) -> Int {
        let count = letters.count
        var best = [Int](repeating: -1, count: count + 1)
        best[0] = 0
        for start in 0..<count where best[start] >= 0 {
            for length in latinWordLengths where start + length <= count {
                guard latinWords.contains(String(letters[start..<(start + length)])) else { continue }
                best[start + length] = max(best[start + length], best[start] + 1)
            }
        }
        return max(best[count], 0)
    }

    private static func phraseTokens(_ text: String, conversational: Bool) -> [PhraseToken] {
        text.split(whereSeparator: isWordSeparator).compactMap { token in
            let word = String(token)
            let range = token.startIndex..<token.endIndex
            if otherWords.contains(word.decomposedStringWithCompatibilityMapping) { return PhraseToken(range: range, kind: .word, slip: false) }
            let folded = listForm(word)
            let slip = slipWords.contains(folded)
            // No texto livre, a palavra de funcao do ingles e neutra: conta como posicao, nao como palavra da lista.
            if conversational, englishFunctionWords.contains(folded) { return PhraseToken(range: range, kind: .neutral, slip: slip) }
            if latinWords.contains(folded) { return PhraseToken(range: range, kind: .word, slip: slip) }
            // O ordinal ou o numero da linha grudado no algarismo ("1st", "2nd", "No.1", "#3"): nao conta nem quebra a conta. So depois
            // das listas: a palavra coreana ou chinesa numerada ("1步", "①대문") e da lista e conta.
            if word.count <= 3, isNumbering(range, in: text) { return nil }
            if folded.count <= 1, folded.allSatisfy(\.isASCII) { return nil }
            return PhraseToken(range: range, kind: folded.count == 4 && latinPrefixes.contains(folded) ? .prefix : .other, slip: slip)
        }
    }

    /// O pedaco de letras grudado num algarismo, antes ou depois, ou separado dele por um de ".#:º°".
    private static func isNumbering(_ range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex, text[text.index(before: range.lowerBound)].isNumber { return true }
        guard range.upperBound < text.endIndex else { return false }
        let next = text[range.upperBound]
        if next.isNumber { return true }
        let after = text.index(after: range.upperBound)
        return ".#:º°".contains(next) && after < text.endIndex && text[after].isNumber
    }

    /// A frase chinesa sem espaco: a sequencia maxima de caracteres das listas chinesas com 12, 15, 18, 21 ou 24 deles, em que o
    /// checksum do BIP-39 fecha; e, dentro de uma sequencia maior ("我的助记词是这个" mais a frase), toda janela desses tamanhos em
    /// que o checksum fecha e ao menos metade dos caracteres esta fora dos 512 mais comuns da lista. A lista chinesa vem em ordem
    /// de frequencia: a frase sorteada tem caracteres raros, a conversa tem os comuns. Sem esse filtro, uma janela qualquer fecha o
    /// checksum 1 vez em 16; com ele, so a palavra-chave perto da frase ja nao bastava, e testar toda janela barrava 17 de 25
    /// chamados (revisao dos 3 agentes, 09/11/2026).
    private static func hanPhrase(_ text: String) -> String? {
        func valid(_ characters: ArraySlice<Character>) -> Bool {
            switch Mnemonic.validate(characters.map(String.init).joined(separator: " ")) {
            case .valid, .ambiguousLanguage: return true
            default: return false
            }
        }
        func uncommon(_ window: ArraySlice<Character>) -> Bool {
            window.filter { (hanRank[$0] ?? 0) >= 512 }.count * 2 >= window.count
        }
        let lengths = [24, 21, 18, 15, 12]
        var runs: [(start: String.Index, characters: [Character])] = []
        var inRun = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if hanWords.contains(String(character)) {
                if !inRun { runs.append((index, [])) }
                runs[runs.count - 1].characters.append(character)
                inRun = true
            } else {
                inRun = false
            }
            index = text.index(after: index)
        }
        for run in runs {
            let characters = run.characters
            func snippet(_ offset: Int, _ length: Int) -> String {
                let first = text.index(run.start, offsetBy: offset)
                return String(text[first..<text.index(first, offsetBy: length)])
            }
            if lengths.contains(characters.count), valid(characters[...]) { return snippet(0, characters.count) }
            guard characters.count > 12, characters.count <= 240 else { continue }
            for length in lengths where length < characters.count {
                for offset in 0...(characters.count - length) {
                    let window = characters[offset..<offset + length]
                    if uncommon(window), valid(window) { return snippet(offset, length) }
                }
            }
        }
        return nil
    }

    // MARK: Os formatos

    /// O texto em NFKC, sem os caracteres de formato e sem os espacos das pontas.
    public static func visible(_ raw: String) -> String {
        let scalars = raw.precomposedStringWithCompatibilityMapping.unicodeScalars.filter { $0.properties.generalCategory != .format }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A chave em algum lugar do texto: inteira, num pedaco, em pedacos vizinhos juntados (o WIF copiado de um papel em duas
    /// linhas), no vetor da Solana ou nos numeros do Xaman no meio de uma frase.
    static func hasKey(_ text: String, signatureAllowed: Bool) -> Bool {
        let text = String(text.prefix(4096))
        let found = { (candidate: String) in isKey(candidate) || isLongHex(candidate, signatureAllowed: signatureAllowed) }
        if found(text) || hasSolanaArray(text) || hasSecretNumbers(text) { return true }
        // Sem os espacos primeiro, e so depois sem o hifen: a AIP-80 em duas linhas ("ed25519-priv-0x...") perdia o tipo.
        let compact = text.filter { !$0.isWhitespace }
        if compact != text, found(compact) || hasSecretNumbers(compact) { return true }
        let joined = compact.filter { $0 != "-" }
        if joined != compact, found(joined) { return true }
        return pieces(text).contains(where: found) || neighbours(text).contains(where: found)
    }

    /// A chave da Solana em base58 cortada no fim: de 61 a 84 caracteres, com minuscula. Os 45 primeiros ja fixam a semente.
    /// Nenhum endereco (ate 44), assinatura (85 a 88), SS58 (47 e 48) ou Byron (59 e 104) tem esse tamanho, e o M da Stellar so
    /// tem maiusculas. So no texto livre.
    static func hasCutSolanaKey(_ text: String) -> Bool {
        pieces(text).contains { piece in
            // So hex (o codigo de uma transacao) nao conta: todo algarismo de hex, fora o 0, tambem e base58. O bech32 (o Taproot e o
            // P2WSH tem 62) e de uma caixa so; o base58 de 61 caracteres ou mais tem maiuscula e minuscula.
            (61...84).contains(piece.count) && piece.allSatisfy(base58Charset.contains) && piece.contains(where: \.isLowercase)
                && piece.contains(where: \.isUppercase) && !piece.allSatisfy(\.isHexDigit) && Bech32.decode(piece, maxLength: 90) == nil
        }
    }

    /// O hex logo depois de "0:" ou "-1:", sem letra ou algarismo antes: o endereco cru da TON.
    static func isTONRaw(_ hex: String, in text: String) -> Bool {
        // "0:0x<hex>" nao e a TON crua: ela nunca tem 0x.
        guard !hex.lowercased().hasPrefix("0x") else { return false }
        return text.range(of: "(?<![A-Za-z0-9])(?:0|-1):" + NSRegularExpression.escapedPattern(for: hex), options: .regularExpression) != nil
    }

    /// O texto sem os 64 hexadecimais que o app ja conhece nesta rede (as contas, os contatos, os destinos de envios), sem o
    /// endereco cru da TON no chamado da TON e sem o pacote de um tipo de moeda da Move ("0x<64>::usdc::USDC"): no texto do chamado,
    /// citar o proprio endereco nao barra. Um 0x mais 64 desconhecido na Aptos ou na Sui pode ser a chave da Petra.
    static func withoutAddresses(_ text: String, on chain: Chain?, known: Set<String>) -> String {
        guard let chain else { return text }
        var out = text
        if [.sui, .aptos].contains(chain.family) {
            // So o tipo inteiro ("0x<64>::modulo::Nome"): "0x<chave>::" sozinho nao tira nada.
            out = out.replacingOccurrences(of: "0[xX][0-9A-Fa-f]{64}::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*", with: " ", options: .regularExpression)
        }
        for piece in pieces(text) where isHex64(piece) && (known.contains(hexKey(piece)) || (chain.family == .ton && isTONRaw(piece, in: text))) {
            out = out.replacingOccurrences(of: piece, with: " ")
        }
        return out
    }

    /// Os contratos publicos da rede que um chamado cita (o USDC e o USDt oficiais fora da lista, as moedas custom da carteira), pelo
    /// id do ativo ("rede:contrato"): o hex deles passa como endereco conhecido, igual no iOS e no Android.
    public static func publicContracts(on chain: Chain, assetIDs: [String]) -> Set<String> {
        let prefix = chain.id + ":"
        return Set((Array(TokenSafety.officialOutsideList) + assetIDs).filter { $0.hasPrefix(prefix) }.map { id in
            hexKey(String(id.dropFirst(prefix.count).prefix { $0 != ":" }))
        })
    }

    /// O hex como os enderecos conhecidos sao comparados: minusculo e sem 0x.
    public static func hexKey(_ text: String) -> String {
        let lower = text.lowercased()
        return lower.hasPrefix("0x") ? String(lower.dropFirst(2)) : lower
    }

    /// O codigo de transacao de 64 hexadecimais que a rede usa: com 0x na EVM, na Aptos e na Polkadot; sem 0x no Bitcoin, na
    /// Litecoin, na Dogecoin, na Tron, na Cardano, na Stellar, no XRP Ledger e na TON. Na Solana, na NEAR e na Sui o codigo e
    /// base58: 64 hexadecimais ali so podem ser chave. Ficam ambiguos a Tron sem 0x e a Polkadot com 0x.
    static func transactionHashFits(_ piece: String, on chain: Chain) -> Bool {
        let has0x = piece.hasPrefix("0x") || piece.hasPrefix("0X")
        switch chain.family {
        case .evm, .aptos, .polkadot: return has0x
        case .utxo, .tron, .cardano, .stellar, .xrpl, .ton: return !has0x
        case .solana, .near, .sui: return false
        }
    }

    static func isKey(_ text: String) -> Bool {
        guard (16...512).contains(text.count) else { return false }
        if hasTypedKey(text) { return true }
        // Bech32 com a chave no prefixo: Cardano ("ed25519e_sk1", "addr_xsk1", "root_xsk1", "xprv1").
        if let hrp = Bech32.decode(text, maxLength: 512)?.hrp.lowercased(), hrp.hasSuffix("_sk") || hrp.hasSuffix("xsk") || hrp == "xprv" {
            return true
        }
        // A chave da Cardano pelo prefixo, mesmo sem o fim (copiada pela metade, o checksum nao confere e os 64 bytes estao ali).
        let lower = text.lowercased()
        if text.count >= 40, let prefix = cardanoKeyPrefixes.first(where: { lower.hasPrefix($0) }),
           lower.dropFirst(prefix.count).allSatisfy(bech32Charset.contains) {
            return true
        }
        // Stellar: a semente "S".
        if text.count == 56, StellarKey.decode(text, version: stellarSeedVersion)?.count == 32 { return true }
        // Base58Check: o WIF do Bitcoin, da Litecoin e da Dogecoin; a chave estendida privada, de qualquer versao (pelo BIP-32,
        // o byte 45 e 0x00 na privada e 02 ou 03 na publica); e a chave cifrada do BIP-38 ("6P").
        if let payload = Base58.bitcoin.decodeCheck(text) {
            if payload.count == 33 || payload.count == 34, wifVersions.contains(payload[0]) { return true }
            if payload.count == 78, payload[45] == 0x00 { return true }
            if payload.count == 39, payload[0] == 0x01, payload[1] == 0x42 || payload[1] == 0x43 { return true }
        }
        // XRPL: a semente "s" secp256k1 (versao 33, 16 bytes) e a "sEd" ed25519 (19 bytes, 01 E1 4B), no alfabeto da Ripple.
        if let payload = Base58.ripple.decodeCheck(text),
           (payload.count == 17 && payload[0] == 0x21) || (payload.count == 19 && payload.starts(with: [0x01, 0xE1, 0x4B])) {
            return true
        }
        // Solana: a chave de 64 bytes em base58 e sempre a semente seguida da publica dela. Sem checksum, so essa conta separa a
        // chave da assinatura de uma transacao e de dois enderecos colados um no outro.
        if (85...90).contains(text.count), let bytes = Base58.bitcoin.decode(text), bytes.count == 64 {
            return isKeyPair(bytes)
        }
        return false
    }

    /// Com o tipo escrito: NEAR ("ed25519:" com 64 bytes, "secp256k1:" com 32), Aptos (AIP-80) e Sui ("suiprivkey1"). Tambem
    /// cortadas no fim, sem o checksum, que se recalcula: "ed25519:" com mais caracteres que a chave publica da NEAR (43 ou 44),
    /// a AIP-80 com 40 hexadecimais ou mais, a Sui com 40 caracteres bech32 ou mais. A chave publica e um nome com o mesmo
    /// comeco ("ed25519-priv-alice.near") passam.
    static func hasTypedKey(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("ed25519:") {
            // A chave da NEAR e a semente seguida da publica; a assinatura, com os mesmos 64 bytes, passa.
            let body = text.dropFirst(8)
            if let bytes = Base58.bitcoin.decode(String(body)), bytes.count == 64 { return isKeyPair(bytes) }
            return body.count >= 45 && body.allSatisfy(base58Charset.contains)
        }
        if lower.hasPrefix("secp256k1:") { return Base58.bitcoin.decode(String(text.dropFirst(10)))?.count == 32 }
        for prefix in ["ed25519-priv-0x", "secp256k1-priv-0x"] where lower.hasPrefix(prefix) {
            let body = lower.dropFirst(prefix.count)
            return body.count >= 40 && body.allSatisfy(\.isHexDigit)
        }
        if lower.hasPrefix("suiprivkey1") {
            return Bech32.decode(lower, maxLength: 512)?.hrp == "suiprivkey"
                || (lower.count >= 51 && lower.dropFirst(11).allSatisfy(bech32Charset.contains))
        }
        return false
    }

    /// Os 128 hexadecimais (com ou sem 0x): o par de chaves ed25519 da Solana, da TON ou da NEAR em hex. Nenhum endereco tem
    /// esse tamanho. No texto livre, so o par: a assinatura em hex passa.
    static func isLongHex(_ text: String, signatureAllowed: Bool) -> Bool {
        let body = text.hasPrefix("0x") || text.hasPrefix("0X") ? text.dropFirst(2) : Substring(text)
        guard body.count == 128, body.allSatisfy(\.isHexDigit) else { return false }
        return !signatureAllowed || Hex.decode(body.lowercased()).map(isKeyPair) ?? false
    }

    /// 64 bytes que sao a semente ed25519 seguida da publica dela: o par de chaves, e nao a assinatura de uma transacao (o R e
    /// o S dela nunca dao essa conta). A semente vai para um buffer que zera.
    static func isKeyPair(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 64 else { return false }
        let seed = SecureBytes(capacity: 32)
        defer { seed.wipe() }
        bytes[0..<32].withUnsafeBufferPointer { seed.append(contentsOf: $0) }
        guard let publicKey = try? Ed25519.publicKey(of: seed) else { return false }
        return publicKey.elementsEqual(bytes[32..<64])
    }

    /// Os 64 hexadecimais, com ou sem 0x.
    static func isHex64(_ text: String) -> Bool {
        let body = text.hasPrefix("0x") || text.hasPrefix("0X") ? text.dropFirst(2) : Substring(text)
        return body.count == 64 && body.allSatisfy(\.isHexDigit)
    }

    /// 48 hexadecimais ou mais seguidos, dentro de qualquer coisa ("pk-", "key_", "0x"), ou em grupos de 2 a 47 separados por
    /// espaco, linha, hifen, ponto, virgula, dois-pontos, barra, sublinhado ou barra vertical, cada grupo com ou sem "0x" (a chave
    /// copiada em duas linhas, em pares "4c 08 83", com ponto a cada 8, na lista "0x4c, 0x08"; auditoria 8, 14/11/2026). O endereco
    /// da EVM ("0x" mais 40) passa, sozinho ou ao lado de outro.
    static func hasLongHex(_ text: String) -> Bool {
        // So algarismos nao conta: um boleto de 48 numeros e hex valido, e uma chave sem nenhuma letra de a a f nao existe na pratica.
        if text.split(whereSeparator: { !$0.isHexDigit }).contains(where: { $0.count >= 48 && $0.contains(where: \.isLetter) }) { return true }
        // Os grupos seguidos, e se cada um tem letra e algarismo juntos. A letra de a a f so conta assim: "de", "da", "cada" e
        // "face" sao palavras, e "os envios de 01/10/2025..." virava chave; nos 32 pares de uma chave de verdade, algum tem os
        // dois, salvo uma vez em um bilhao.
        var run: [(size: Int, mixed: Bool)] = []
        for token in text.split(whereSeparator: { $0.isWhitespace || "-.,;:/_|".contains($0) }) {
            let has0x = token.hasPrefix("0x") || token.hasPrefix("0X")
            let body = has0x ? token.dropFirst(2) : token
            if (2...47).contains(body.count), body.allSatisfy(\.isHexDigit), !(has0x && body.count == 40) {
                run.append((body.count, body.contains(where: \.isLetter) && body.contains(where: \.isNumber)))
                for start in run.indices where Self.keyGroups(run[start...]) { return true }
            } else {
                run = []
            }
        }
        return false
    }

    /// Grupos que formam uma chave: 48 hexadecimais ou mais, algum grupo com letra e algarismo, e na forma de uma chave
    /// partida: em duas linhas, em qualquer ponto de corte, ou em grupos do mesmo tamanho (2, 4, 8, 16 ou 32), o ultimo menor
    /// ou igual. A data ("01/10/2025", grupos de 2, 2 e 4), o UUID (8, 4, 4, 4 e 12) e a lista de codigos de 6 algarismos nao
    /// tem essa forma, e passam (rodada 1 da auditoria 8).
    static func keyGroups(_ groups: ArraySlice<(size: Int, mixed: Bool)>) -> Bool {
        guard groups.reduce(0, { $0 + $1.size }) >= 48, groups.contains(where: { $0.mixed }), let first = groups.first, let last = groups.last else {
            return false
        }
        if groups.count == 2 { return true }
        guard [2, 4, 8, 16, 32].contains(first.size) else { return false }
        return groups.dropLast().allSatisfy { $0.size == first.size } && last.size <= first.size
    }

    /// Os 64 hexadecimais com o rotulo de chave antes ("PRIVATE_KEY=", "minha chave privada:", "seed"), nas linguas do app, ate 160
    /// caracteres antes de cada vez que o hex aparece. Os rotulos curtos ("pk", "sk", "key", "keys", "cle", "키", "鍵") so contam como
    /// palavra inteira, tambem no camelCase ("deployerKey"); as expressoes de chave publica saem antes ("public key", "chave
    /// publica", "公钥"), e "publish" ou "عام" sozinhos nao anulam o rotulo. O endereco que o app ja conhece passa.
    static func hasLabeledHexKey(_ text: String, known: Set<String> = []) -> Bool {
        // Tambem o hex grudado num rotulo por "_" ou "-" ("pk-<hex>", "PRIVATE_KEY_<hex>").
        let candidates = Set(pieces(text) + pieces(text).flatMap { $0.split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init) })
        for piece in candidates where isHex64(piece) && !known.contains(hexKey(piece)) {
            var from = text.startIndex
            while from < text.endIndex, let range = text.range(of: piece, range: from..<text.endIndex) {
                from = range.upperBound
                let raw = String(text[..<range.lowerBound].suffix(160))
                // A variavel de ambiente em maiusculas ("WALLETKEY=", "MYKEY:"), menos a da chave publica.
                if let name = raw.range(of: "[A-Za-z0-9_]*[Kk][Ee][Yy][\"'\\s]*[=:][\"'\\s]*$", options: .regularExpression),
                   !raw.suffix(raw.distance(from: name.lowerBound, to: raw.endIndex) + 12).lowercased().contains("pub") {
                    return true
                }
                let split = raw.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
                var before = WordLexicon.fold(split).lowercased().replacingOccurrences(of: "ı", with: "i")
                // "비공개" e privado, e contem "공개" (publico): marcado antes de tirar a chave publica.
                before = before.replacingOccurrences(of: foldedPrivateKorean, with: " priv ")
                for phrase in publicKeyPhrases { before = before.replacingOccurrences(of: phrase, with: " ") }
                let words = before.split(whereSeparator: { !$0.isLetter }).map(String.init)
                let short = words.contains { word in shortKeyLabels.contains(word) || (word.hasSuffix("s") && shortKeyLabels.contains(String(word.dropLast()))) }
                let prefixed = words.contains { word in wordPrefixLabels.contains(where: word.hasPrefix) }
                if short || prefixed || keyLabels.contains(where: before.contains) { return true }
            }
        }
        return false
    }

    /// O SeedQR: a frase em numeros, 48 ou 96 algarismos, cada grupo de 4 um indice da lista (ate 2047). Um boleto de 48
    /// algarismos quase nunca da essa conta.
    static func isSeedQR(_ text: String) -> Bool {
        guard text.utf8.count == 48 || text.utf8.count == 96, text.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return false }
        let digits = Array(text)
        // Um grupo fora da lista e tolerado: o erro de digitacao.
        return stride(from: 0, to: digits.count, by: 4).filter { (Int(String(digits[$0..<$0 + 4])) ?? 9999) > 2047 }.count <= 1
    }

    /// O vetor da Solana (o id.json do solana-keygen): 64 numeros de 0 a 255 entre colchetes, sozinho ou no meio do texto.
    static func hasSolanaArray(_ text: String) -> Bool {
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "[") {
            rest = rest[rest.index(after: open)...]
            guard let close = rest.firstIndex(of: "]") else { return false }
            let numbers = rest[..<close].split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if numbers.count == 64, numbers.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) { return true }
        }
        return false
    }

    /// Os numeros secretos do Xaman (XLS-12): oito blocos de seis algarismos, os cinco primeiros ate 65535 e o sexto a conta
    /// valor x (2 x posicao + 1) mod 9, com a posicao de 0 a 7. Sozinhos ou no meio do texto, com o que vier entre eles: a letra
    /// ou o numero da linha, o bloco partido em 3 e 3, os 48 algarismos do QR. Com a conta, sete dos oito bastam (um erro de
    /// digitacao), e oito numeros quaisquer de seis algarismos (datas, alturas de bloco) passam.
    static func hasSecretNumbers(_ text: String) -> Bool {
        let runs = text.split(whereSeparator: { !("0"..."9").contains($0) }).map(String.init)
        var blocks: [String?] = []
        var index = 0
        while index < runs.count {
            let run = runs[index]
            switch run.count {
            case 6: blocks.append(run)
            case 3 where index + 1 < runs.count && runs[index + 1].count == 3:
                blocks.append(run + runs[index + 1])
                index += 1
            case 48:
                let digits = Array(run)
                blocks += stride(from: 0, to: 48, by: 6).map { String(digits[$0..<$0 + 6]) }
            case 1, 2: break
            default: blocks.append(nil)
            }
            index += 1
        }
        guard blocks.count >= 8 else { return false }
        for start in 0...(blocks.count - 8) {
            let window = blocks[start..<start + 8]
            guard window.allSatisfy({ $0 != nil }) else { continue }
            let valid = window.enumerated().filter { validSecretNumber($0.element ?? "", position: $0.offset) }.count
            if valid >= 6 { return true }
        }
        return false
    }

    static func validSecretNumber(_ block: String, position: Int) -> Bool {
        guard block.count == 6, let value = Int(block.prefix(5)), value <= 65535, let check = Int(block.suffix(1)) else { return false }
        return value * (position * 2 + 1) % 9 == check
    }

    /// Os pedacos do texto: o que esta entre tudo que nao e letra, algarismo, ":", "_" ou "-" do ASCII. As aspas curvas que o
    /// iPhone poe sozinho (“ ”, « », 「 」), o ".env" ("="), o link ("?", "&", "/") e o descritor separam; nas pontas sai a
    /// pontuacao, e o esquema de um link ("bitcoin:", que nao e um tipo de chave) tambem.
    static func pieces(_ text: String) -> [String] {
        text.components(separatedBy: pieceSeparators).compactMap { raw -> String? in
            var piece = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".:!-_"))
            let lower = piece.lowercased()
            if let colon = piece.lastIndex(of: ":"), !lower.hasPrefix("ed25519:"), !lower.hasPrefix("secp256k1:") {
                piece = String(piece[piece.index(after: colon)...])
            }
            return piece.count >= 16 ? piece : nil
        }
    }

    /// Pedacos vizinhos juntados, separados so por espaco ou linha, do tamanho de uma chave: a chave copiada de um papel em
    /// linhas ou em grupos de 4. So os tamanhos dos formatos em base58 e em hex vao para a conferencia.
    static func neighbours(_ text: String) -> [String] {
        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty }
        var out: [String] = []
        for start in tokens.indices {
            var joined = ""
            for token in tokens[start..<min(start + 32, tokens.count)] {
                guard token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { break }
                joined += token
                if joined.count > 130 { break }
                if joined != token, keyLengths.contains(joined.count) { out.append(joined) }
            }
        }
        return out
    }

    /// XRPL "s" e "sEd", WIF, Stellar "S", BIP-38, Solana, xprv, 128 hex.
    private static let keyLengths: Set<Int> = [29, 30, 31, 51, 52, 56, 58, 85, 86, 87, 88, 89, 90, 111, 128, 130]
    private static let pieceSeparators = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:_-").inverted
    private static let latinWords: Set<String> = Set(WordLexicon.entries.compactMap(\.folded))
    /// Os tamanhos das palavras latinas (de 3 a 9 letras nas seis listas).
    private static let latinWordLengths: [Int] = Set(latinWords.map(\.count)).sorted()
    /// O comeco de 4 letras das palavras latinas mais longas: a placa de aco guarda so ele.
    private static let latinPrefixes: Set<String> = Set(WordLexicon.entries.compactMap { $0.folded }.filter { $0.count > 4 }.map { String($0.prefix(4)) })
    private static let otherWords: Set<String> = Set(WordLexicon.entries.filter { $0.folded == nil }.map { $0.word.decomposedStringWithCompatibilityMapping })
    private static let hanWords: Set<String> = Set(WordLexicon.entries.filter { [.chineseSimplified, .chineseTraditional].contains($0.language) }.map(\.word))
    private static let cardanoKeyPrefixes = ["ed25519e_sk1", "ed25519_sk1", "addr_xsk1", "addr_sk1", "acct_xsk1", "root_xsk1", "stake_xsk1", "xprv1"]
    private static let bech32Charset = Set("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let base58Charset = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    /// Rotulos de chave, sem acento e em minusculas, nas linguas do app.
    /// Rotulos de chave, nas linguas do app, dobrados como o texto (sem acento, minusculos): sem isso, "открытый" (o "й" vira "и")
    /// nunca casava.
    private static let keyLabels: [String] = [
        "priv", "secret", "segred", "seed", "chave", "clave", "gizli", "ozel anahtar", "rahasia", "khoa rieng", "khoa bi mat",
        "приват", "секрет", "закрыт", "私钥", "私鑰", "私密金鑰", "私密金钥", "秘密鍵", "秘密キー", "プライベートキー", "개인키", "개인 키",
        "비밀 키", "비밀키", "프라이빗 키", "프라이빗키", "निजी", "कुंजी", "المفتاح الخاص", "مفتاح", "kunci", "ключ", "klic", "schlussel",
        "anahtar", "密钥", "密鑰", "非公开", "不公开", "khoa ca nhan",
    ].map { WordLexicon.fold($0).lowercased() }
    /// So como comeco de palavra: "sement" pegava "reimbursement" e "advertisement".
    private static let wordPrefixLabels: [String] = ["sement", "semill"]
    /// So como palavra inteira (com as particulas do coreano).
    private static let shortKeyLabels: Set<String> = Set(["key", "pk", "sk", "cle", "khoa", "키", "키는", "키를", "키가", "키도", "키의", "鍵"].map {
        WordLexicon.fold($0).lowercased()
    })
    /// A chave publica nao e chave: a expressao sai do texto antes de procurar o rotulo.
    private static let publicKeyPhrases: [String] = [
        "public key", "public_key", "publickey", "pubkey", "pub key", "pub_key", "chave publica", "clave publica", "cle publique",
        "offentlicher schlussel", "offentliche schlussel", "kunci publik", "acik anahtar", "khoa cong khai", "verejny klic",
        "открытый ключ", "публичный ключ", "公钥", "公鑰", "公開鍵", "공개키", "공개 키", "المفتاح العام", "المفتاح العمومي", "सार्वजनिक कुंजी",
    ].map { WordLexicon.fold($0).lowercased() }
    private static let foldedPrivateKorean = WordLexicon.fold("비공개").lowercased()
    /// O que enfeita um valor copiado: aspas, colchetes, pontuacao das pontas.
    private static let decorations = CharacterSet(charactersIn: "\"'`“”‘’«»「」()[]{}<>.,;:!?")
    /// A posicao de cada caractere chines na lista (a menor das duas): a lista vem em ordem de frequencia.
    private static let hanRank: [Character: Int] = {
        var rank: [Character: Int] = [:]
        for language in [BIP39Language.chineseSimplified, .chineseTraditional] {
            for (index, entry) in WordLexicon.entries.filter({ $0.language == language }).enumerated() {
                if let character = entry.word.first { rank[character] = min(index, rank[character] ?? index) }
            }
        }
        return rank
    }()
    /// A lista do SLIP-39 (o backup do Trezor), conferida pelo digesto ao abrir.
    private static let slipWords: Set<String> = Set((try? WordlistStore.shared.slip39().words) ?? [])
    /// As palavras de funcao do ingles que estao na lista: no texto do chamado, nao contam (o chamado normal em ingles batia seis
    /// seguidas, como "check this order again, please").
    private static let englishFunctionWords: Set<String> = [
        "about", "above", "across", "again", "all", "almost", "alone", "already", "also", "always", "among", "another", "any",
        "around", "away", "because", "before", "behind", "below", "between", "can", "during", "either", "else", "enough", "just",
        "more", "much", "must", "never", "next", "nothing", "now", "often", "once", "only", "other", "over", "please", "rather",
        "same", "since", "soon", "still", "such", "sure", "that", "then", "there", "they", "this", "today", "together", "under",
        "until", "upon", "very", "what", "when", "where", "will", "you",
    ]
    static let stellarSeedVersion: UInt8 = 18 << 3
    /// Bitcoin (e testnet), Litecoin, Dogecoin.
    static let wifVersions: Set<UInt8> = [0x80, 0xEF, 0xB0, 0x9E]
}
