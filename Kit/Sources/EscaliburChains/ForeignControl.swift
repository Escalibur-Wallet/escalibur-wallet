import Foundation

/// Outra chave, conta ou contrato com poder sobre uma conta da carteira, lido na rede (auditoria 8, 14/11/2026): a
/// delegacao EIP-7702 na EVM, a `RegularKey` ou os assinantes no XRP Ledger, os assinantes da Stellar, a chave de acesso
/// total da NEAR, o plugin ou a extensao da TON, o procurador da Polkadot, a chave girada da Aptos e as permissoes da Tron.
/// O que entra numa conta assim pode sair sem a assinatura do dono: e o golpe da "frase com saldo" e o sinal de uma frase
/// vazada. Fica guardado por rede na carteira so com dois operadores de acordo (na primeira onda, ou com margem de dois no
/// total), e so sai com todos os que respondem, e pelo menos tres, vendo a conta limpa, cada um na propria ponta (rodada 2).
public struct ForeignControl: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// Um contrato instalado na conta (EIP-7702), ou codigo na conta.
        case delegation
        /// Outra chave ou conta que assina por ela.
        case otherKey
    }

    public let kind: Kind
    /// O contrato da delegacao (EVM), para o dono reconhecer o que instalou; nil nas outras.
    public let detail: String?

    public init(kind: Kind, detail: String? = nil) {
        self.kind = kind
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey { case kind, detail }

    /// Um tipo que esta versao nao conhece (de uma versao mais nova) le como outra chave: os metadados abrem, e o aviso fica.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = Kind(rawValue: (try? container.decode(String.self, forKey: .kind)) ?? "") ?? .otherKey
        detail = try? container.decodeIfPresent(String.self, forKey: .detail)
    }
}
