import Testing
@testable import EscaliburNetwork

@Suite("Porta da busca de moedas")
struct CoinSearchGateTests {
    @Test("O pedaco de chave fica no aparelho, o nome de moeda vai")
    func gate() {
        #expect(CoinCatalog.mayCarrySecret("sp5fghtJtpUo"))
        #expect(CoinCatalog.mayCarrySecret("4c0883a69102"))
        #expect(CoinCatalog.mayCarrySecret("HarryPotterObamaSonic10Inu"))
        #expect(!CoinCatalog.mayCarrySecret("Decentraland"))
        #expect(!CoinCatalog.mayCarrySecret("wrapped bitcoin"))
        #expect(!CoinCatalog.mayCarrySecret("USDT"))
        // A frase chinesa digitada sem espaco.
        #expect(CoinCatalog.mayCarrySecret("的一是在不了有和人这中大"))
        #expect(!CoinCatalog.mayCarrySecret("比特币"))
        // Tres palavras da lista, ou do comeco de 4 letras, nao saem.
        #expect(CoinCatalog.mayCarrySecret("abandon ability able"))
        #expect(CoinCatalog.mayCarrySecret("aban abil abou"))
    }
}
