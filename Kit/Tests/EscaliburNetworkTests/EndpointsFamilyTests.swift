import EscaliburChains
import Foundation
import Testing
@testable import EscaliburNetwork

/// Uma empresa so vai na frente em uma familia de redes (auditoria de privacidade,
/// 22/10/2026): quem recebe do mesmo celular, no mesmo segundo, o endereco da Ethereum e o
/// da Solana liga as duas contas no proprio registro.
@Suite("Provedores: uma empresa na frente de uma familia so")
struct EndpointsFamilyTests {
    /// Quem recebe os enderecos de cada familia na leitura normal: o primeiro da lista, e nas
    /// redes UTXO todos os que repartem os enderecos (`sharesAddressLoad`).
    static func leaders() -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        func add(_ family: String, _ providers: [ProviderPool.Provider]) {
            guard let first = providers.first else { return }
            out[family, default: []].insert(first.operatorName)
        }
        for providers in Endpoints.evm.values { add("evm", providers) }
        for chain in [Chain.bitcoin, .litecoin, .dogecoin] {
            let leading = UTXOReader.providers(for: chain).prefix { UTXOBackend.of($0).sharesAddressLoad }
            out[chain.id, default: []].formUnion(leading.map(\.operatorName))
        }
        add("solana", Endpoints.solana)
        add("xrpl", Endpoints.xrpl)
        add("stellar", Endpoints.stellar)
        add("tron", Endpoints.tron)
        add("ton", Endpoints.ton)
        add("sui", Endpoints.sui)
        add("polkadot", Endpoints.polkadot)
        add("near", Endpoints.near)
        add("aptos", Endpoints.aptos)
        return out
    }

    @Test("Nenhuma empresa recebe na frente os enderecos de duas familias")
    func oneFamilyPerOperator() {
        var families: [String: [String]] = [:]
        for (family, operators) in Self.leaders() {
            for name in operators { families[name, default: []].append(family) }
        }
        let shared = families.filter { $0.value.count > 1 }.mapValues { $0.sorted() }
        #expect(shared.isEmpty, "na frente de mais de uma familia: \(shared)")
    }

    /// Operadores de verdade, e nao enderecos (revisao dos tres agentes de 15/11/2026): as dataseeds da BNB Chain (bnbchain.org,
    /// defibit.io e ninicoin.io, a mesma NodeReal atras) contavam como tres, e a BNB Chain sozinha escondia a delegacao 7702.
    @Test("Toda EVM com tres operadores na leitura e dois na simulacao, e as dataseeds da BNB Chain como um so")
    func distinctOperators() {
        let reads = Endpoints.evm.merging(Endpoints.evmContingency) { $0 + $1 }
        for (chain, providers) in reads {
            #expect(Set(providers.map(\.operatorName)).count >= 3, "\(chain): \(providers.map(\.operatorName))")
        }
        // A lista vazia e a rede sem simulacao (a troca nao abre la).
        for (chain, providers) in Endpoints.tradeSimulation where !providers.isEmpty {
            #expect(Set(providers.map(\.operatorName)).count >= 2, "\(chain): \(providers.map(\.operatorName))")
        }
        let dataseeds = (reads["bnb"] ?? []) + (Endpoints.tradeSimulation["bnb"] ?? [])
        for provider in dataseeds where ["bnbchain.org", "defibit.io", "ninicoin.io"].contains(where: { provider.baseURL.host?.hasSuffix($0) == true }) {
            #expect(provider.operatorName == "bnbchain", "\(provider.baseURL.host ?? "")")
        }
        #expect(!(reads.values.joined().contains { $0.baseURL.host == "1rpc.io" }))
    }

    @Test("A Litecoin reparte entre o litecoinspace e a Bitcore, e a Dogecoin fica com a Atomic")
    func utxoLeaders() {
        let leaders = Self.leaders()
        #expect(leaders["litecoin"] == ["litecoinspace", "bitcore"])
        #expect(leaders["dogecoin"] == ["atomic"])
        #expect(leaders["solana"] == ["solana"])
        #expect(leaders["aptos"] == ["sentio"])
    }
}
