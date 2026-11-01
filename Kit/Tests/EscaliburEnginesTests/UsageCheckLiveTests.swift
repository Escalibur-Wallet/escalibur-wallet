import EscaliburChains
import EscaliburCore
import EscaliburKeys
import Foundation
import Testing
@testable import EscaliburEngines

/// A busca de movimento da carteira com passphrase contra os provedores reais, so com
/// ESCALIBUR_REDE=1. So leitura. A carteira sorteada agora nunca foi usada; a frase de teste do
/// BIP-39 ("abandon ... about") tem movimento em varias redes ha anos.
@Suite("Busca de movimento ao vivo", .enabled(if: ProcessInfo.processInfo.environment["ESCALIBUR_REDE"] == "1"), .serialized)
struct UsageCheckLiveTests {
    func accounts(_ phrase: SecureBytes) throws -> [DerivedAccount] {
        let secret = try WalletSecret.from(phrase: phrase, language: .english)
        defer { secret.wipe() }
        return try AccountDeriver.derive(secret).accounts
    }

    @Test("Carteira sorteada agora: nenhum movimento")
    func freshWalletNeverUsed() async throws {
        let start = Date.now
        let outcome = await UsageCheck.run(try accounts(BIP39.generate(wordCount: 12)))
        print("sorteada:", outcome, String(format: "%.1f s", Date.now.timeIntervalSince(start)))
        switch outcome {
        case .used: Issue.record("uma carteira sorteada agora nao pode ter movimento")
        case .never, .incomplete: break
        }
    }

    @Test("Frase de teste do BIP-39: tem movimento")
    func knownWalletUsed() async throws {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let start = Date.now
        let outcome = await UsageCheck.run(try accounts(BIP39.canonical(phrase)))
        print("conhecida:", outcome, String(format: "%.1f s", Date.now.timeIntervalSince(start)))
        #expect(outcome == .used)
    }
}
