import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation

/// A versao do contrato da carteira TON de quem importa uma frase (auditoria 8, 14/11/2026). A Escalibur cria a V4R2, e o
/// Tonkeeper e o MyTonWallet criam a W5 com a mesma chave (`TONDerivationScheme.importCandidates`): importada daqui, a carteira
/// W5 aparecia com saldo zero no endereco da V4R2, e o dono achava que tinha perdido o dinheiro. Depois de gravar, o app
/// confere os dois enderecos da mesma chave e passa para a W5 quando so ela teve movimento. O caminho da Ledger Live pede a
/// frase de novo (outra chave) e fica de fora.
public enum TONDiscovery {
    public enum Answer: Sendable, Equatable {
        /// A guardada fica: ja e a W5, a V4R2 teve movimento, ou a W5 nunca teve.
        case keep
        /// A V4R2 nunca teve movimento e a W5 da mesma chave teve: a conta passa a ser esta.
        case switchTo(DerivedAccount)
        /// Sem resposta: a proxima conferencia pergunta de novo.
        case unknown
    }

    public static func check(_ account: DerivedAccount) async -> Answer {
        guard account.chainID == Chain.ton.id, !account.isAddressOnly, case .success(let stored) = TONAddress.parse(account.address),
              let v4 = try? TONWallet(publicKey: account.publicKey, version: .v4r2),
              let w5 = try? TONWallet(publicKey: account.publicKey, version: .v5r1)
        else { return .keep }
        guard v4.address == stored.address else { return .keep }
        guard let oldUsed = try? await TONReader.shared.hasActivity(v4.address) else { return .unknown }
        guard !oldUsed else { return .keep }
        guard let newUsed = try? await TONReader.shared.hasActivity(w5.address) else { return .unknown }
        guard newUsed else { return .keep }
        // Na mesma grafia da guardada (a amigavel sem bounce, como `TONAddress.walletAddress`).
        let address = w5.address.friendly(bounceable: stored.bounceable ?? false)
        return .switchTo(DerivedAccount(chainID: account.chainID, path: account.path, address: address, publicKey: account.publicKey, accountXPub: nil))
    }
}
