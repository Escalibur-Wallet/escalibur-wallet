import CryptoKit
import EscaliburChains
import EscaliburCore
import EscaliburNetwork
import Foundation
import UserNotifications

// Os avisos da ordem limite sem servidor (pedido do dono, 14/10/2026): um dia antes de
// vencer, e quando ela executa.
//
// O de 24 horas e um alarme local, marcado quando a ordem passa a ser acompanhada: nao
// precisa de rede. O de executada precisa: o proprio iPhone pergunta a CoW pelo andamento
// de cada ordem acompanhada, na checagem de segundo plano dos alertas de preco e na
// abertura do app.
//
// Para perguntar com o iPhone bloqueado, o UID de cada ordem aberta (que traz o endereco
// do dono e o prazo, os mesmos dados que a CoW publica) fica num arquivo proprio com a
// protecao ate o primeiro desbloqueio (classe C), fora dos metadados cifrados. A ordem sai
// do arquivo quando termina, e o arquivo some quando nao sobra nenhuma.
//
// Este arquivo nao toca no cofre, no chaveiro nem nos metadados cifrados, e verificar.sh
// confere: as ordens chegam de fora, pelo app destravado (`track`).

/// O que o aviso guarda: as ordens abertas a acompanhar.
struct LimitOrderWatchFile: Codable, Equatable {
    struct Order: Codable, Equatable {
        /// O UID da ordem na CoW, em hex.
        let id: String
        let chainID: String
        let expiresAt: Date
    }

    var orders: [Order] = []
}

/// O arquivo das ordens acompanhadas, num diretorio proprio com protecao ate o primeiro
/// desbloqueio (classe C), fora do backup: a checagem roda com o iPhone bloqueado.
enum LimitOrderWatchStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ordens", isDirectory: true)
    }

    static var file: URL { directory.appendingPathComponent("ordens.json") }

    static func load() -> LimitOrderWatchFile {
        guard let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(LimitOrderWatchFile.self, from: data) else {
            return LimitOrderWatchFile()
        }
        return decoded
    }

    static func save(_ value: LimitOrderWatchFile) throws {
        guard !value.orders.isEmpty else {
            erase()
            return
        }
        try prepareDirectory()
        let data = try JSONEncoder().encode(value)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func erase() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func prepareDirectory() throws {
        let files = FileManager.default
        let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        if files.fileExists(atPath: directory.path) {
            try files.setAttributes(protection, ofItemAtPath: directory.path)
        } else {
            try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: protection)
        }
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

/// Quem acompanha e avisa. Um ator: a checagem do segundo plano, a da abertura e a lista
/// de ordens abertas nunca gravam o arquivo ao mesmo tempo.
actor LimitOrderWatch {
    static let shared = LimitOrderWatch()

    /// Quanto antes do fim do prazo sai o aviso.
    static let warningLead: TimeInterval = 24 * 60 * 60
    /// Ordem que vence em menos que isto nao ganha aviso de vencimento: ele chegaria
    /// junto com a propria ordem.
    static let warningFloor: TimeInterval = 60 * 60

    private var current: LimitOrderWatchFile?
    private var checking = false
    /// Sobe a cada apagar tudo: o que estava esperando a rede quando o apagar chegou para, sem acompanhar, avisar nem
    /// recriar a chave dos avisos (decima passada da auditoria de 03/11/2026).
    private var epoch = 0

    /// A epoca de agora: quem le a rede antes de acompanhar ou de assentar uma ordem guarda esta, e o `track` e o
    /// `settle` recusam se um apagar tudo passou no meio (decima primeira passada da auditoria de 03/11/2026).
    func currentEpoch() -> Int { epoch }

    func file() -> LimitOrderWatchFile {
        if let current { return current }
        let loaded = LimitOrderWatchStore.load()
        current = loaded
        return loaded
    }

    private func store(_ value: LimitOrderWatchFile) {
        current = value
        try? LimitOrderWatchStore.save(value)
        BackgroundCheck.reschedule()
    }

    /// Uma ordem da CoW, nova ou vista na lista de abertas: passa a ser acompanhada e
    /// ganha o aviso de 24 horas antes do fim do prazo. Ja acompanhada, nada muda.
    func track(id: String, chainID: String, expiresAt: Date, now: Date = .now, epoch lida: Int) {
        // Um apagar tudo depois da leitura: a ordem lida antes dele nao volta ao arquivo, com o UID e o aviso.
        guard lida == epoch, expiresAt > now, id.hasPrefix("0x"), Hex.decode(id)?.count == CoWProtocol.uidLength else { return }
        // Dono de carteira removida nesta sessao: uma leitura que terminou depois da remocao nao volta a acompanhar.
        guard !forgottenOwners.contains(Self.owner(ofUID: id) ?? "") else { return }
        var value = file()
        guard !value.orders.contains(where: { $0.id == id }) else { return }
        value.orders.append(.init(id: id, chainID: chainID, expiresAt: expiresAt))
        store(value)
        Self.scheduleWarning(id: id, expiresAt: expiresAt, now: now)
    }

    /// A ordem terminou (ou o dono cancelou): sai do arquivo, e o aviso de vencimento
    /// marcado sai da agenda.
    func forget(_ id: String) {
        // Antes do resumo: a que nao esta no arquivo nao tem aviso marcado, e o resumo recriaria a chave depois de um
        // apagar tudo (decima passada).
        var value = file()
        guard value.orders.contains(where: { $0.id == id }) else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.warningIDs(id))
        value.orders.removeAll { $0.id == id }
        store(value)
    }

    /// Os donos de carteiras removidas nesta sessao: `track` recusa as ordens deles (quinta passada de 03/11/2026).
    private var forgottenOwners: Set<String> = []

    /// As ordens destes donos saem do arquivo e da agenda, sem mexer nos esquecidos: a da carteira com passphrase que
    /// uma versao anterior acompanhou (o app travado durante o envio a deixava entrar; oitava passada de 03/11/2026).
    func purge(owners: Set<String>) {
        guard !owners.isEmpty else { return }
        let gone = file().orders.map(\.id).filter { owners.contains(Self.owner(ofUID: $0) ?? "") }
        for id in gone { forget(id) }
    }

    /// Os avisos de 24 horas marcados de novo, no formato de agora (a migracao dos avisos, setima passada).
    func rescheduleWarnings(now: Date = .now) {
        for order in file().orders where order.expiresAt > now {
            Self.scheduleWarning(id: order.id, expiresAt: order.expiresAt, now: now)
        }
    }

    /// A carteira adicionada de novo nesta sessao: os donos dela voltam a ter os avisos (sexta passada).
    func remember(owners: Set<String>) {
        forgottenOwners.subtract(owners)
    }

    /// A carteira removida: saem as ordens dela, pelo dono no UID (bytes 32 a 52) ou pelo id, com os avisos.
    func forget(owners: Set<String>, ids: Set<String>) {
        forgottenOwners.formUnion(owners)
        let gone = file().orders.map(\.id).filter { id in
            ids.contains(id.lowercased()) || owners.contains(Self.owner(ofUID: id) ?? "")
        }
        for id in gone { forget(id) }
        // O aviso de executada que saiu entre o remover e este esquecer (o remover chama aqui numa tarefa) sai da
        // Central tambem (revisao da decima terceira passada).
        if !owners.isEmpty || !ids.isEmpty { UNUserNotificationCenter.current().removeAllDeliveredNotifications() }
    }

    /// O dono que o UID da CoW traz, em hex minusculo sem `0x`.
    static func owner(ofUID id: String) -> String? {
        let hex = id.lowercased().hasPrefix("0x") ? String(id.lowercased().dropFirst(2)) : id.lowercased()
        guard hex.count == 112 else { return nil }
        return String(hex.dropFirst(64).prefix(40))
    }

    /// Apagar tudo: o arquivo e os avisos de vencimento marcados. Sem calcular ids: o resumo com chave recriaria a
    /// chave que o apagar acabou de tirar (setima passada da auditoria de 03/11/2026). Os avisos de ordem saem pelo
    /// prefixo, agendados e mostrados.
    func erase() async {
        epoch &+= 1
        // O arquivo sai antes da primeira espera: um `track` ou `settle` que entra no ator durante elas ja ve o
        // arquivo vazio e a epoca nova (decima primeira passada da auditoria de 03/11/2026).
        current = LimitOrderWatchFile()
        LimitOrderWatchStore.erase()
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("ordem-limite.") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("ordem-limite.") }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
        // De novo depois das esperas: o que entrou no meio sai pelo prefixo tambem.
        current = LimitOrderWatchFile()
        LimitOrderWatchStore.erase()
        let tarde = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("ordem-limite.") }
        center.removePendingNotificationRequests(withIdentifiers: tarde)
        // Por ultimo: um `forget` que rodava no ator quando o apagar tudo chegou podia ter recriado a chave (nona
        // passada da auditoria de 03/11/2026).
        NoticeKey.erase()
        BackgroundCheck.reschedule()
    }

    /// A lista de ordens abertas viu a ordem sair com o andamento final. Executada avisa
    /// (se ainda estava acompanhada: o aviso sai uma vez so); o resto so sai do arquivo.
    func settle(_ id: String, filled: Bool, epoch lida: Int) async {
        guard lida == epoch else { return }
        let watched = file().orders.contains { $0.id == id }
        forget(id)
        if filled, watched { await postFilled(id: id) }
    }

    /// Pergunta a CoW pelo andamento de cada ordem acompanhada. Sem resposta, fica para a
    /// proxima vez.
    func check(now: Date = .now) async {
        let orders = file().orders
        guard !orders.isEmpty, !checking else { return }
        checking = true
        defer { checking = false }
        let start = epoch
        let client = CoWClient()
        for order in orders {
            // Apagou tudo no meio: a lista lida antes nao vai mais a CoW (o UID traz o dono).
            guard epoch == start else { return }
            guard let chain = Chain.all.first(where: { $0.id == order.chainID }), let uid = Hex.decode(order.id) else {
                forget(order.id)
                continue
            }
            // Vencida, sai mesmo sem resposta: a ordem que a CoW nunca teve (a recusada) respondia 404
            // para sempre, e o UID, que traz o endereco, ia a ela a cada checagem (auditoria de 03/11/2026).
            if order.expiresAt <= now {
                forget(order.id)
                continue
            }
            guard let status = try? await client.order(uid: uid, chain: chain) else { continue }
            guard epoch == start else { return }
            switch status.status {
            case .fulfilled:
                await settle(order.id, filled: true, epoch: start)
            case .cancelled, .expired:
                forget(order.id)
            case .open, .presignaturePending, .unknown:
                if status.invalidated || TimeInterval(status.validTo) <= now.timeIntervalSince1970 { forget(order.id) }
            }
        }
    }

    // MARK: Notificacao

    /// Um resumo do UID, e nao o UID: o pedido fica no armazenamento do sistema, fora do cofre (quinta passada da
    /// auditoria de 03/11/2026).
    static func warningID(_ id: String) -> String { "ordem-limite.24h.\(LimitRenewalCenter.digest(id))" }

    /// O de agora e os que versoes anteriores marcaram (o resumo sem chave e o UID cru), para tirar da agenda.
    static func warningIDs(_ id: String) -> [String] {
        [warningID(id), "ordem-limite.24h.\(LimitRenewalCenter.legacyDigest(id))", "ordem-limite.24h.\(id)"]
    }

    /// Os avisos nao dizem ativo nem valor: a tela bloqueada nao conta o que a carteira
    /// tem (a mesma regra do aviso de prazo de `LimitRenewalCenter`).
    static func scheduleWarning(id: String, expiresAt: Date, now: Date) {
        let fireIn = expiresAt.timeIntervalSince(now) - warningLead
        guard fireIn >= warningFloor else { return }
        let request = UNNotificationRequest(
            identifier: warningID(id),
            content: content(id: id, title: String(localized: "Sua ordem limite vence em 24 horas"), body: String(localized: "Se ela ainda não executou, abra a Escalibur para ver ou mudar o preço.")),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: fireIn, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// O aviso de executada, do ator: o id sai antes de qualquer espera, e um apagar tudo durante ela nao deixa o aviso
    /// na tela (decima passada da auditoria de 03/11/2026).
    func postFilled(id: String) async {
        let start = epoch
        // O dono conferido antes e depois de cada espera: a carteira removida durante ela nao avisa (revisao da decima
        // terceira passada).
        let owner = Self.owner(ofUID: id) ?? ""
        guard !forgottenOwners.contains(owner) else { return }
        let identifier = "ordem-limite.executada.\(LimitRenewalCenter.digest(id))"
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized, epoch == start, !forgottenOwners.contains(owner) else { return }
        let request = UNNotificationRequest(
            identifier: identifier,
            content: Self.content(id: id, title: String(localized: "Sua ordem limite foi executada"), body: String(localized: "A troca saiu no seu preço. O saldo novo já está na carteira.")),
            trigger: nil
        )
        try? await center.add(request)
        if epoch != start || forgottenOwners.contains(owner) { center.removeDeliveredNotifications(withIdentifiers: [identifier]) }
    }

    private static func content(id: String, title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = LimitRenewalCenter.category
        content.userInfo = ["ordem": "1"]
        return content
    }
}

/// A chave dos resumos dos avisos de ordem: 32 bytes aleatorios por instalacao, numa pasta do app fora do backup,
/// com a mesma protecao do arquivo das ordens (a checagem do segundo plano roda com o iPhone bloqueado). Some so no
/// apagar tudo, junto com todas as notificacoes (sexta passada da auditoria de 03/11/2026).
enum NoticeKey {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: SymmetricKey?

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Avisos", isDirectory: true)
    }

    static var file: URL { directory.appendingPathComponent("chave") }

    nonisolated static func current() -> SymmetricKey {
        lock.withLock {
            if let cached { return cached }
            if let data = try? Data(contentsOf: file), data.count == 32 {
                cached = SymmetricKey(data: data)
                return cached!
            }
            let key = SymmetricKey(size: .bits256)
            try? store(key)
            cached = key
            return key
        }
    }

    private static func store(_ key: SymmetricKey) throws {
        let files = FileManager.default
        let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        if !files.fileExists(atPath: directory.path) {
            try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: protection)
        }
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        try key.withUnsafeBytes { Data($0) }.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    nonisolated static func erase() {
        lock.withLock {
            cached = nil
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// A marca de que os avisos ja estao no formato de agora, ao lado da chave (some com ela no apagar tudo).
    nonisolated static func mark(_ url: URL) {
        lock.withLock {
            let files = FileManager.default
            let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            if !files.fileExists(atPath: directory.path) {
                try? files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: protection)
            }
            try? Data().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
