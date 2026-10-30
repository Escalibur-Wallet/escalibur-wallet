import EscaliburCore
import Foundation

/// O endereco de uma carteira deste aparelho em outra rede com o mesmo formato (revisao de blockchain
/// de 26/10/2026). Sui e Aptos escrevem o endereco do mesmo jeito (0x e 64 hex), e a conta implicita da
/// NEAR e o mesmo hex sem o 0x, mas cada rede tira o endereco da chave de um jeito: o endereco Aptos do
/// dono, colado na Sui, e um endereco Sui que nenhuma chave dele controla. Parece "meu", e o envio se
/// perde inteiro. EVM fica de fora: o mesmo endereco e da mesma chave em toda rede EVM.
public enum CrossNetworkSelf {
    static let families: Set<ChainFamily> = [.sui, .aptos, .near]

    /// A outra rede em que `destination` e de uma carteira deste aparelho, ou nil.
    public static func network(of destination: String, on chain: Chain, own accounts: [DerivedAccount]) -> Chain? {
        guard families.contains(chain.family), let key = normalized(destination) else { return nil }
        for account in accounts {
            guard let other = Chain.find(account.chainID), other.family != chain.family, families.contains(other.family),
                  normalized(account.address) == key else { continue }
            return other
        }
        return nil
    }

    /// Minusculas, sem o 0x e com os zeros a esquerda que a Aptos e a Sui podem omitir.
    static func normalized(_ text: String) -> String? {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard !hex.isEmpty, hex.count <= 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return String(repeating: "0", count: 64 - hex.count) + hex
    }
}
