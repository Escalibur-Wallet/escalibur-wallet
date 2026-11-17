import Testing
@testable import EscaliburChains

@Suite("Trecho do meio do endereco")
struct AddressMiddleSegmentTests {
    @Test("Seis caracteres no meio, para o dono ler e digitar")
    func middle() throws {
        let address = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
        let segment = try #require(AddressPoisoning.middleSegment(address))
        #expect(segment.length == 6)
        #expect(segment.start == (address.count - 6) / 2)
        #expect(segment.text(in: address) == "E47d90")
        #expect(AddressPoisoning.middleSegment("curto") == nil)
    }

    @Test("Conferir o endereco em todo envio: os seis ultimos, sem os espacos da colagem")
    func tail() throws {
        let address = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
        let segment = try #require(AddressPoisoning.tailSegment("  \(address)\n"))
        #expect(segment.length == 6 && segment.start == address.count - 6)
        #expect(segment.text(in: address) == "aEda94")
        #expect(AddressPoisoning.tailSegment("r12345678") == nil)
    }

    @Test("NEAR com nome: o nome inteiro, com o registro")
    func nearName() throws {
        let near = try #require(Chain.find("near"))
        let named = "fulano-wallet.near"
        let segment = try #require(AddressPoisoning.tailSegment(" \(named)\n", chain: near))
        #expect(segment.text(in: named) == named)
        #expect(AddressPoisoning.coversAll(segment, of: named))
        // O dono digita o que le onde copiou (o verdadeiro); o app espera o trecho do colado. Trocar o registro,
        // uma letra ou o pai da subconta nao passa.
        let swaps = [("alice.near", "alice.tg"), ("alice.tg", "alice.near"), ("malice.near", "alice.near"),
                     ("bob.alice.near", "alice.near"), ("alice-wallet.near", "alice-walet.near")]
        for (pasted, real) in swaps {
            let asked = try #require(AddressPoisoning.tailSegment(pasted, chain: near)).text(in: pasted)
            let read = try #require(AddressPoisoning.tailSegment(real, chain: near)).text(in: real)
            #expect(asked != read, "\(pasted) passou no lugar de \(real)")
        }
        // Conta implicita (hex de 64): os seis ultimos, como em toda rede.
        let implicit = String(repeating: "a", count: 58) + "b1c2d3"
        let tail = try #require(AddressPoisoning.tailSegment(implicit, chain: near))
        #expect(tail.text(in: implicit) == "b1c2d3" && !AddressPoisoning.coversAll(tail, of: implicit))
        // Fora da NEAR, igual ao de sempre.
        let evm = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
        #expect(AddressPoisoning.tailSegment(evm, chain: .ethereum) == AddressPoisoning.tailSegment(evm))
    }

    @Test("O endereco entrou inteiro: o que entrou de uma vez, com ponto; digitar e deslizar no teclado nao")
    func enteredWhole() {
        #expect(AddressPoisoning.enteredWhole(from: "", to: "alice-wallet.near"))
        #expect(AddressPoisoning.enteredWhole(from: "alice-wallet.near", to: "alice-wa11et.near"))  // colado por cima, mesmo tamanho
        #expect(!AddressPoisoning.enteredWhole(from: "alice-wallet.nea", to: "alice-wallet.near"))  // uma tecla
        #expect(!AddressPoisoning.enteredWhole(from: "", to: "alice"))  // uma palavra do teclado
        #expect(!AddressPoisoning.enteredWhole(from: "", to: "aurora"))
        #expect(AddressPoisoning.enteredWhole(from: "", to: String(repeating: "a", count: 32)))  // conta de topo antiga, sem ponto
        #expect(!AddressPoisoning.enteredWhole(from: "pay.", to: "pay.alice"))  // deslizar uma palavra depois do ponto
        #expect(AddressPoisoning.enteredWhole(from: "alice.", to: "alice.near"))  // completar com o registro
        #expect(AddressPoisoning.enteredWhole(from: "alice.sweat", to: "a1ic3.sweat"))  // colado por cima, trocando letras
        #expect(!AddressPoisoning.enteredWhole(from: "allure", to: "alice"))  // a sugestao do teclado troca a palavra
        #expect(AddressPoisoning.enteredWhole(from: "alice.near", to: "alic3.near"))  // colado por cima, uma letra
        #expect(!AddressPoisoning.enteredWhole(from: "my-very-long-account-name-for-", to: "my-very-long-account-name-for-business"))
        #expect(!AddressPoisoning.enteredWhole(from: "alice-wallet.near", to: "alice-wallet.ne"))  // apagar
    }

    @Test("Nome da NEAR colado na rede errada: escondido; bech32 e addr1 de outra rede, nao")
    func nearNameOnWrongNetwork() {
        #expect(AddressPoisoning.looksLikeNEARName("alice.near"))
        #expect(AddressPoisoning.looksLikeNEARName("alice.near-wallet-payments-00000000001"))
        #expect(!AddressPoisoning.looksLikeNEARName("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"))
        #expect(!AddressPoisoning.looksLikeNEARName("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t"))  // cortado, sem ponto
        #expect(AddressPoisoning.looksLikeNEARName(String(repeating: "z", count: 32)))  // conta de topo antiga
        #expect(!AddressPoisoning.looksLikeNEARName("0x9858effd232b4033e47d90003d41ec34ecaeda9"))  // 0x cortado
        #expect(!AddressPoisoning.looksLikeNEARName("9858effd232b4033e47d90003d41ec34ecaeda94"))  // EVM sem 0x
        // Na rede livre do contato: o endereco da Sui vale noutra rede; lixo e bc1 cortado nao.
        let sui = "0x" + String(repeating: "1", count: 62) + "ab"
        #expect(AddressPoisoning.validElsewhere(sui, than: .bitcoin))
        #expect(!AddressPoisoning.validElsewhere("qualquer coisa", than: .bitcoin))
        #expect(!AddressPoisoning.validElsewhere("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t", than: .ethereum))
        #expect(!AddressPoisoning.looksLikeNEARName("0x9858EfFD232B4033E47d90003D41EC34EcaEda94"))
    }

    @Test("Salvar contato NEAR com nome: o nome inteiro, tambem o curto, que antes ficava sem desafio")
    func nearContact() throws {
        let near = try #require(Chain.find("near"))
        for name in ["bob.near", "alice.tg", "alice-wallet.near"] {
            let segment = try #require(AddressPoisoning.blindSegment(name, chain: near))
            #expect(AddressPoisoning.coversAll(segment, of: name))
        }
        // Mesmo meio, outra primeira letra: o meio passava, o nome inteiro nao.
        let real = "alice-wallet.near", fake = "alicx-wallet.near"
        let asked = try #require(AddressPoisoning.blindSegment(fake, chain: near)).text(in: fake)
        #expect(asked != real)
        // Fora da NEAR com nome, o meio de sempre.
        let evm = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
        #expect(AddressPoisoning.blindSegment(evm, chain: .ethereum) == AddressPoisoning.middleSegment(evm))
    }

    @Test("A caixa conta onde ela e parte do endereco: base58 e o base64 da TON exatos; hex, bech32 e nome da NEAR sem caixa")
    func caseOfTheAnswer() throws {
        let solana = try #require(Chain.find("solana"))
        let address = "7cVfgArCheMR6Cs4t6vz5rfnqd56vZq4ndaBrY5xkxXy"
        let tail = try #require(AddressPoisoning.tailSegment(address))
        #expect(AddressPoisoning.answers("5xkxXy", segment: tail, of: address, chain: solana))
        #expect(!AddressPoisoning.answers("5xkxxy", segment: tail, of: address, chain: solana))
        #expect(!AddressPoisoning.answers("5XKXXY", segment: tail, of: address, chain: solana))
        // Hex da EVM: o EIP-55 e so conferencia.
        let evm = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
        let evmTail = try #require(AddressPoisoning.tailSegment(evm))
        #expect(AddressPoisoning.answers("aeda94", segment: evmTail, of: evm, chain: .ethereum))
        // Bitcoin: bc1 sem caixa, o antigo em base58 exato.
        let bitcoin = try #require(Chain.find("bitcoin"))
        #expect(!AddressPoisoning.caseMatters("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", chain: bitcoin))
        #expect(AddressPoisoning.caseMatters("1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2", chain: bitcoin))
        // TON: a amigavel exata, a crua sem caixa.
        let ton = try #require(Chain.find("ton"))
        #expect(AddressPoisoning.caseMatters("EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N", chain: ton))
        #expect(!AddressPoisoning.caseMatters("0:83dfd552e63729b472fcbcc8c45ebcc6691702558b68ec7527e1ba403a0f31a8", chain: ton))
        let near = try #require(Chain.find("near"))
        #expect(!AddressPoisoning.caseMatters("alice.near", chain: near))
        // Sem rede, exata.
        #expect(!AddressPoisoning.answers("5xkxxy", segment: tail, of: address, chain: nil))
    }

    @Test("Salvar contato na Cardano com stake: os 6 caem no pagamento, e nao no stake, que o sosia escolhe de graca")
    func cardanoContact() throws {
        let cardano = try #require(Chain.find("cardano"))
        let base = "addr1q94zzrtl32tjp8j96auatnhxd2y35fnk6wuxqvqm9364vp9spdkjdsmyfhvfagjzh4uzp9zs6p5djw89jac2g0ujs2eqsuy7pu"
        let segment = try #require(AddressPoisoning.blindSegment(base, chain: cardano))
        #expect(segment == AddressPoisoning.Segment(start: 26, length: 6))
        // O trecho e so do pagamento: o mesmo pagamento com outro stake da o mesmo trecho.
        let pay = [UInt8](repeating: 7, count: 32)
        let a = try CardanoAddress.base(paymentKey: pay, stakeKey: [UInt8](repeating: 1, count: 32))
        let b = try CardanoAddress.base(paymentKey: pay, stakeKey: [UInt8](repeating: 2, count: 32))
        let first = try #require(AddressPoisoning.blindSegment(a, chain: cardano))
        #expect(first == AddressPoisoning.Segment(start: 26, length: 6) && first.text(in: a) == first.text(in: b))
        // Sem stake (enterprise), o meio de sempre: tudo depois do cabecalho e pagamento.
        let enterprise = "addr1vx2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzers66hrl8"
        #expect(AddressPoisoning.blindSegment(enterprise, chain: cardano) == AddressPoisoning.middleSegment(enterprise))
    }
}
