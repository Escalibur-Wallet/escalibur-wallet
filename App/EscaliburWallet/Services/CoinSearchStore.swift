import EscaliburCore
import EscaliburNetwork
import Foundation

/// A busca de Receber no CoinGecko (`CoinCatalog`): so o que o dono digitou, e as redes
/// de uma moeda quando ele toca nela. Guarda as respostas na memoria enquanto o app esta
/// aberto: voltar a uma busca ou a uma moeda nao pergunta de novo.
///
/// A lista embarcada (`CoinList`, catalogo-moedas.json) responde quando o CoinGecko pede
/// pausa: as redes de uma moeda saem dela na hora, e a busca cai nela quando as duas fontes
/// nao respondem (pedido do dono, 30/10/2026: a pausa nunca deve aparecer).
@MainActor
@Observable
final class CoinSearchStore {
    static let shared = CoinSearchStore()

    enum Status: Equatable {
        case loading
        /// As fontes e a lista nao responderam: tentando de novo, sem dizer por que.
        case retrying
        case loaded([CoinSearchResult])
        case failed
        /// Parece o comeco das palavras de uma carteira: a busca nao saiu do iPhone.
        case phrase
    }

    private(set) var searches: [String: Status] = [:]
    private(set) var coins: [String: CatalogCoin] = [:]
    private(set) var coinFailures: Set<String> = []
    /// A lista embarcada, lida uma vez, fora da linha principal (2,7 MB).
    private var list: Task<CoinList?, Never>?
    /// Quanto a tela espera a leitura na rede, que traz o aviso do CoinGecko, antes de
    /// mostrar a moeda pela lista.
    static let onlineWait: Duration = .seconds(2)

    /// Espera antes de cada tentativa, em segundos: a primeira na hora. O limite por IP do
    /// CoinGecko sem chave dura por volta de um minuto, e as tentativas cobrem esse tempo.
    static let retryDelays: [Double] = [0, 4, 10, 20, 30]

    static func key(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func status(_ query: String) -> Status? { searches[Self.key(query)] }

    /// Chamada pela tela a cada mudanca do texto, dentro de uma tarefa que o SwiftUI
    /// cancela quando o texto muda de novo: a espera curta antes de perguntar evita uma
    /// chamada por letra.
    func search(_ query: String) async {
        let key = Self.key(query)
        guard key.count >= 2 else { return }
        if Self.looksLikePhrase(key) {
            searches[key] = .phrase
            return
        }
        if case .loaded? = searches[key] { return }
        searches[key] = .loading
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else {
            searches[key] = nil
            return
        }
        for (attempt, delay) in Self.retryDelays.enumerated() {
            if attempt > 0 {
                searches[key] = .retrying
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else {
                    searches[key] = nil
                    return
                }
            }
            if let found = try? await CoinCatalog.search(key) {
                // Resposta do CoinPaprika (o CoinGecko em pausa) ou nada achado: a lista
                // embarcada primeiro, que tem as moedas pequenas que o CoinPaprika nao tem.
                let reserve = found.isEmpty || found.contains { $0.id.hasPrefix(CoinCatalog.paprikaPrefix) }
                let local = reserve ? await localSearch(key) : []
                guard !local.isEmpty else {
                    searches[key] = .loaded(found)
                    return
                }
                let extra = found.filter { result in !local.contains { $0.symbol == result.symbol && $0.name == result.name } }
                searches[key] = .loaded(local + extra)
                return
            }
            guard !Task.isCancelled else {
                searches[key] = nil
                return
            }
            // As duas fontes fora: a lista embarcada, sem logo, com as mesmas conferencias.
            let local = await localSearch(key)
            if !local.isEmpty {
                searches[key] = .loaded(local)
                return
            }
        }
        searches[key] = .failed
    }

    /// A busca na lista embarcada, fora da linha principal (sao 22 mil moedas).
    private func localSearch(_ key: String) async -> [CoinSearchResult] {
        guard let list = await coinList() else { return [] }
        return await Task.detached(priority: .userInitiated) { list.search(key) }.value
    }

    /// A lista embarcada, ou nil se o arquivo faltar ou nao abrir.
    private func coinList() async -> CoinList? {
        if list == nil {
            list = Task.detached(priority: .userInitiated) {
                guard let url = Bundle.main.url(forResource: "catalogo-moedas", withExtension: "json"),
                      let data = try? Data(contentsOf: url) else { return nil }
                return try? CoinList(data: data)
            }
        }
        return await list?.value
    }

    func retry(_ query: String) { searches[Self.key(query)] = nil }

    /// Tres palavras ou mais das listas BIP-39: quem digita (ou cola) a frase aqui, por engano
    /// ou levado por um golpe, mandaria ao CoinGecko o bastante para o resto cair numa GPU
    /// (auditoria 6, A6-11). Nome de moeda quase nunca tem tres palavras da lista.
    static func looksLikePhrase(_ key: String) -> Bool {
        let words = key.split { !$0.isLetter }
        guard words.count >= 3 else { return false }
        let lists = BIP39Language.allCases.compactMap { try? WordlistStore.shared.wordlist(for: $0) }
        return words.filter { word in lists.contains { $0.contains(String(word)) } }.count >= 3
    }

    /// As redes de uma moeda, lidas uma vez por abertura do app.
    /// `symbol` e `name` acham a mesma moeda no CoinPaprika, para juntar as redes das duas
    /// fontes (`CoinCatalog.coinAllNetworks`).
    func coin(_ id: String, symbol: String? = nil, name: String? = nil) async {
        guard coins[id] == nil else { return }
        coinFailures.remove(id)
        if let local = await coinList()?.coin(id: id) {
            await coin(id, local: local, symbol: symbol, name: name)
            return
        }
        for (attempt, delay) in Self.retryDelays.enumerated() {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            if let coin = try? await CoinCatalog.coinAllNetworks(id: id, symbol: symbol, name: name) {
                coins[id] = coin
                return
            }
            guard !Task.isCancelled else { return }
        }
        coinFailures.insert(id)
    }

    /// A moeda esta na lista embarcada. A leitura na rede ainda vale (o aviso de golpe e as
    /// redes do CoinPaprika), mas a tela so espera por ela `onlineWait`: com o CoinGecko em
    /// pausa, a moeda aparece pela lista. Se a leitura chegar depois, so o aviso entra, para a
    /// tela nao trocar de rede debaixo do dedo.
    private func coin(_ id: String, local: CatalogCoin, symbol: String?, name: String?) async {
        let online = Task { try? await CoinCatalog.coinAllNetworks(id: id, symbol: symbol, name: name) }
        enum First { case online(CatalogCoin?), late }
        let first = await withTaskGroup(of: First.self) { group -> First in
            group.addTask { .online(await online.value) }
            group.addTask {
                try? await Task.sleep(for: CoinSearchStore.onlineWait)
                return .late
            }
            let first = await group.next() ?? .late
            group.cancelAll()
            return first
        }
        switch first {
        case .online(let fresh?):
            coins[id] = local.merged(with: fresh, addingNetworks: true)
        case .online(nil):
            coins[id] = local
        case .late:
            coins[id] = local
            if let fresh = await online.value, fresh.hasNotice, let shown = coins[id] {
                coins[id] = shown.merged(with: fresh, addingNetworks: false)
            }
        }
    }
}
