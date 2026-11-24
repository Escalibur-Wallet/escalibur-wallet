import EscaliburCore
import EscaliburNetwork
import UIKit
import Foundation

/// O alarme de atualizacao nao confirmada (docs/seguranca.md, "Versao autorizada"). Ao voltar
/// para a frente, no maximo a cada 6 horas, pergunta a App Store qual e a versao mais nova e
/// confere se ela esta na lista assinada pela Escalibur (`ReleaseWatch`). Fora da lista, ou
/// com a lista sumida ou mexida, o app inteiro fica atras da trava (`UpdateAlarmView`), no
/// lugar do aviso na Carteira (pedido do dono, 18/10/2026).
///
/// A trava sai sozinha depois da conferencia da Escalibur: assinada a versao (alarme falso),
/// ou tirada da loja a versao de fora e publicada uma assinada, a proxima conferencia responde
/// "confirmada" ou "nada novo" e a trava some. Enquanto ela esta na tela, a conferencia repete
/// a cada volta para a frente (no minimo 1 minuto entre duas) e a cada 5 minutos.
@MainActor
@Observable
final class UpdateGuard {
    static let shared = UpdateGuard()

    private(set) var verdict: ReleaseWatch.Verdict
    /// O dono deslizou "Usar em emergência": a trava sai ate o app fechar.
    private(set) var emergency = false
    /// O dono deslizou "Vou atualizar depois": a tela da versao desatualizada sai ate o app fechar.
    private(set) var postponed = false
    /// O dono tocou "Atualizar agora" e continua nesta versao (atualizar mata o app): a tela obrigatoria ganha o "Usar em
    /// emergência", para quem nao consegue instalar (outro Apple ID, Tempo de Uso, loja de outro pais).
    private(set) var triedUpdate = false
    /// O dono deslizou "Usar em emergência" na tela obrigatoria: ela sai ate o app fechar.
    private(set) var updateEmergency = false
    private var updating = false
    /// A conferencia do "Atualizar agora" ficou sem resposta: a tela diz, em vez de o botao parecer morto.
    private(set) var updateUnchecked = false
    /// O app na App Store, para o "Atualizar agora": o Apple ID do app no App Store Connect. A tela obrigatoria so vale
    /// quando a consulta da loja devolve este mesmo app.
    static let appStoreID = 6823379335
    static let storeURL = URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)")!
    private var lastCheck: Date?
    private var checking = false
    private var recheck: Task<Void, Never>?
    static let interval: TimeInterval = 6 * 3600
    static let alarmInterval: TimeInterval = 60

    init() {
        verdict = Self.stored()
        triedUpdate = Self.triedRecently()
    }

    /// O build instalado, para a tentativa guardada valer so nele.
    private static var installedBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }

    /// "Atualizar agora" tocado neste build nas ultimas 24 horas: a saida da obrigatoria continua depois de o sistema fechar o
    /// app com a loja na frente (revisao dos 3 agentes de 07/11/2026). Ela so libera o deslizar que o toque ja liberaria.
    private static func triedRecently() -> Bool {
        guard let saved = Preferences.updateTried else { return false }
        let parts = saved.split(separator: "|").map(String.init)
        guard parts.count == 2, parts[0] == installedBuild, let seconds = Double(parts[1]) else { return false }
        let age = Date().timeIntervalSince1970 - seconds
        return age >= 0 && age < 24 * 3600
    }

    private func markTried() {
        triedUpdate = true
        Preferences.updateTried = "\(Self.installedBuild)|\(Int(Date().timeIntervalSince1970))"
    }

    func check() async {
        #if DEBUG
        // `-alarme-versao`: a trava, para ver a tela sem uma versao de verdade na loja.
        if DebugDemo.arguments.contains("-alarme-versao") {
            verdict = .unconfirmed("1.0.1")
            refreshLock()
            return
        }
        // `-versao-expirada`: a tela de atualizar, como se a loja tivesse uma versao nova confirmada.
        if DebugDemo.arguments.contains("-versao-expirada") {
            verdict = .confirmed("1.0.2")
            refreshLock()
            return
        }
        // `-versao-obrigatoria`: a mesma tela sem o "Vou atualizar depois", como se a lista obrigasse esta versao.
        if DebugDemo.arguments.contains("-versao-obrigatoria") {
            // `-tentou-atualizar`: como quem voltou da loja sem conseguir, com o "Usar em emergência".
            triedUpdate = DebugDemo.arguments.contains("-tentou-atualizar")
            verdict = .required("1.0.2")
            refreshLock()
            return
        }
        #endif
        refreshLock()
        // Com a trava ou uma tela de atualizar na frente, de minuto em minuto: tirada a obrigacao da lista, a tela sai na volta
        // seguinte. Adiada ou em emergencia, volta as 6 horas: a cada volta, a Apple e o GitHub veriam o IP de quem adiou, e o
        // "Atualizar agora" ja confere de novo antes de abrir a loja.
        let wait = alarm != nil || updateOnScreen ? Self.alarmInterval : Self.interval
        guard !checking, lastCheck.map({ Date().timeIntervalSince($0) >= wait }) ?? true else { return }
        checking = true
        defer { checking = false }
        apply(await Self.lookup())
    }

    /// Pergunta a App Store e confere a lista assinada.
    private static func lookup() async -> (verdict: ReleaseWatch.Verdict, issued: Date?) {
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let bundle = Bundle.main.bundleIdentifier ?? "app.escalibur.wallet"
        let country = Locale.current.region?.identifier ?? "US"
        return await ReleaseWatch.check(installed: installed, bundleID: bundle, country: country, systemVersion: UIDevice.current.systemVersion,
                                        appStoreID: appStoreID, issuedFloor: issuedFloor)
    }

    private func apply(_ result: (verdict: ReleaseWatch.Verdict, issued: Date?)) {
        // O piso so sobe ate um dia a frente deste relogio: uma lista com o relogio do Mac adiantado nao trava o piso no futuro.
        if let issued = result.issued, issued <= Date().addingTimeInterval(86_400), Self.issuedFloor.map({ issued > $0 }) ?? true {
            Preferences.releaseIssued = issued
        }
        // Sem resposta agora, ou so uma lista mais antiga que a ja vista: fica o que se sabia. A tela obrigatoria vira a de
        // deixar para depois: sem internet nao ha o que instalar, e uma lista velha nao sustenta a obrigacao. Sem resposta,
        // tenta de novo na proxima volta; com a lista velha, espera o intervalo normal (cada volta mostraria o IP a Apple e
        // ao GitHub).
        let stale: Bool
        if case .stale = result.verdict { stale = true } else { stale = false }
        guard result.verdict != .unknown, !stale else {
            if stale { lastCheck = .now }
            if case .required(let version) = verdict {
                verdict = .confirmed(version)
                refreshLock()
            }
            return
        }
        lastCheck = .now
        updateUnchecked = false
        verdict = result.verdict
        Self.store(result.verdict)
        refreshLock()
    }

    /// A emissao da lista mais nova ja vista: a que vai dentro do app, ou a de uma conferencia anterior.
    private static var issuedFloor: Date? {
        [Preferences.releaseIssued, bundledIssued].compactMap { $0 }.max()
    }

    private static let bundledIssued: Date? = {
        guard let url = Bundle.main.url(forResource: "versoes", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return (try? ReleaseManifest.verified(data, app: Bundle.main.bundleIdentifier ?? "app.escalibur.wallet")).flatMap(ReleaseWatch.issued)
    }()

    /// A trava, quando ha. Quem ve esta tela esta na versao anterior, a que roda esta
    /// conferencia: a versao de fora nao rodou aqui.
    var alarm: UpdateAlarmView.Content? {
        let message: String
        switch verdict {
        case .unconfirmed(let version):
            message = String(localized: "Alguém tentou adulterar o código da Escalibur: a versão \(version) apareceu na App Store sem a assinatura da Escalibur. A equipe da Escalibur está investigando.")
        case .tampered(let version):
            message = String(localized: "Alguém mexeu na lista assinada que confirma cada versão da Escalibur, e a versão \(version) da App Store não pode ser confirmada. A equipe da Escalibur está investigando.")
        case .upToDate, .confirmed, .required, .unknown, .stale:
            return nil
        }
        return UpdateAlarmView.Content(
            title: String(localized: "Detectamos uma tentativa de hack"),
            message: message,
            safeTitle: String(localized: "Seus fundos estão seguros"),
            safeText: String(localized: "As palavras da carteira continuam cifradas somente no chip de segurança deste celular. A versão possivelmente adulterada não chegou a rodar aqui."),
            steps: [
                String(localized: "Não atualize o app por enquanto, até a Escalibur confirmar a versão nova. Desligue a atualização automática em Ajustes, App Store, Atualizações de Apps."),
                String(localized: "Por enquanto, recomendamos não visualizar as palavras da carteira. Acompanhe o aviso no site da Escalibur: quando a Escalibur confirmar que está tudo certo, este alerta some sozinho."),
            ],
            note: String(localized: "Só se precisar mexer nos fundos agora."))
    }

    /// A versao nova da loja, confirmada pela lista assinada: a instalada esta desatualizada.
    var newerVersion: String? {
        switch verdict {
        case .confirmed(let version), .required(let version): return version
        case .upToDate, .unconfirmed, .tampered, .unknown, .stale: return nil
        }
    }

    /// A lista assinada obriga esta versao a atualizar: a tela sai sem o "Vou atualizar depois".
    var mandatory: Bool {
        if case .required = verdict { return true }
        return false
    }

    /// Uma tela de atualizar na frente: nem adiada, nem em emergencia, e sem a trava por cima.
    private var updateOnScreen: Bool {
        alarm == nil && newerVersion != nil && (mandatory ? !updateEmergency : !postponed)
    }

    private func refreshLock() {
        if let alarm, !emergency {
            UpdateAlarmWindow.shared.show(alarm) { [weak self] in self?.useInEmergency() }
        } else {
            UpdateAlarmWindow.shared.hide()
        }
        if updateOnScreen, let version = newerVersion {
            UpdateRequiredWindow.shared.show(version: version, mandatory: mandatory, allowEmergency: triedUpdate, unchecked: updateUnchecked,
                                             onUpdate: { [weak self] in
                self?.update(version)
            }, onLater: { [weak self] in self?.updateLater() })
        } else {
            UpdateRequiredWindow.shared.hide()
        }
        // Com alarme, de 5 em 5 minutos (em emergencia tambem: confirmada a versao, o alarme
        // sai e a proxima abertura ja vem sem trava). Com a tela obrigatoria na frente tambem.
        if alarm == nil, !mandatory || updateEmergency {
            recheck?.cancel()
            recheck = nil
        } else if recheck == nil {
            recheck = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(300))
                    guard !Task.isCancelled else { return }
                    await self?.check()
                }
            }
        }
    }

    /// "Atualizar agora": confere de novo antes de abrir a loja. A conferencia da tela pode ser de horas atras, e uma versao
    /// que entrou na loja depois dela, fora da lista, seria instalada sem o alarme (revisao dos 3 agentes de 05/11/2026).
    /// Sem resposta, ou com outra versao, a loja nao abre e a tela mostra o que a conferencia nova achou.
    private func update(_ shown: String) {
        guard !updating else { return }
        #if DEBUG
        // Nas telas de demonstracao, sem loja: como quem voltou da loja sem conseguir.
        if DebugDemo.arguments.contains(where: { $0.hasPrefix("-versao-") }) {
            triedUpdate = true
            refreshLock()
            return
        }
        #endif
        updating = true
        Task {
            defer { updating = false }
            let result = await Self.lookup()
            apply(result)
            // A lista velha (`.stale`) ainda vale aqui: ela so sai com a versao da loja na lista, e a tela veio de uma lista
            // mais nova que a liberou. Abre se a loja continua na versao da tela.
            let same: Bool
            let stale: Bool
            switch result.verdict {
            case .stale(let store):
                same = store == shown
                stale = true
            default:
                same = result.verdict != .unknown && newerVersion == shown
                stale = false
            }
            // Sem resposta, ou so a lista velha com outra versao na loja: a loja nao abre, e a tela diz.
            updateUnchecked = !same && (result.verdict == .unknown || stale)
            guard same, alarm == nil else {
                // A loja nao abriu e a obrigatoria continua (outra versao na conferencia nova): a saida aparece do mesmo jeito.
                if mandatory { markTried() }
                refreshLock()
                return
            }
            // Antes de abrir: com a loja na frente, o sistema pode fechar o app, e a saida tem de estar guardada. So na
            // obrigatoria: na comum, o toque guardado daria a saida a uma obrigatoria que viesse depois, sem tentativa nela.
            if mandatory { markTried() }
            _ = await UIApplication.shared.open(Self.storeURL)
            // Quem atualiza nao volta para este processo: quem volta, ou nao viu a loja abrir, nao conseguiu.
            refreshLock()
        }
    }

    /// "Vou atualizar depois", ou "Usar em emergência" na tela obrigatoria depois de tentar atualizar.
    private func updateLater() {
        // Em emergencia, nenhuma das duas telas volta ate o app fechar, nem a comum, se a obrigatoria cair para ela.
        if mandatory { updateEmergency = true }
        postponed = true
        // Os pixels do deslizar terminam antes de a tela sair, como na trava.
        Task {
            try? await Task.sleep(for: .milliseconds(Int(PixelFill.finale * 1000)))
            refreshLock()
        }
    }

    private func useInEmergency() {
        emergency = true
        // O selo dos pixels termina antes de a trava sair.
        Task {
            try? await Task.sleep(for: .milliseconds(Int(PixelFill.finale * 1000)))
            refreshLock()
        }
    }

    /// O alarme fica guardado entre aberturas (`Preferences.updateAlarm`): sem internet na
    /// volta seguinte, a trava continua. So uma conferencia que responde (versao confirmada,
    /// ou nada novo na loja) tira.
    private static func stored() -> ReleaseWatch.Verdict {
        guard let saved = Preferences.updateAlarm else { return .upToDate }
        let parts = saved.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return .upToDate }
        switch parts[0] {
        case "nao-confirmada": return .unconfirmed(parts[1])
        case "lista-mexida": return .tampered(parts[1])
        default: return .upToDate
        }
    }

    private static func store(_ verdict: ReleaseWatch.Verdict) {
        switch verdict {
        case .unconfirmed(let version): Preferences.updateAlarm = "nao-confirmada|\(version)"
        case .tampered(let version): Preferences.updateAlarm = "lista-mexida|\(version)"
        // A obrigatoria nao fica guardada: sem internet, nao ha versao nova para instalar, e a tela so prenderia os fundos.
        case .upToDate, .confirmed, .required: Preferences.updateAlarm = nil
        case .unknown, .stale: break
        }
    }
}
