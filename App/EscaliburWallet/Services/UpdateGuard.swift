import EscaliburNetwork
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
    private var lastCheck: Date?
    private var checking = false
    private var recheck: Task<Void, Never>?
    static let interval: TimeInterval = 6 * 3600
    static let alarmInterval: TimeInterval = 60

    init() {
        verdict = Self.stored()
    }

    func check() async {
        #if DEBUG
        // `-alarme-versao`: a trava, para ver a tela sem uma versao de verdade na loja.
        if DebugDemo.arguments.contains("-alarme-versao") {
            verdict = .unconfirmed("1.0.1")
            refreshLock()
            return
        }
        #endif
        refreshLock()
        let wait = alarm == nil ? Self.interval : Self.alarmInterval
        guard !checking, lastCheck.map({ Date().timeIntervalSince($0) >= wait }) ?? true else { return }
        checking = true
        defer { checking = false }
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let bundle = Bundle.main.bundleIdentifier ?? "app.escalibur.wallet"
        let country = Locale.current.region?.identifier ?? "US"
        let result = await ReleaseWatch.check(installed: installed, bundleID: bundle, country: country)
        // Sem resposta agora: fica o que se sabia, e tenta de novo na proxima volta.
        guard result != .unknown else { return }
        lastCheck = .now
        verdict = result
        Self.store(result)
        refreshLock()
    }

    /// A trava, quando ha. Quem ve esta tela esta na versao anterior, a que roda esta
    /// conferencia: a versao de fora nao rodou aqui.
    var alarm: UpdateAlarmView.Content? {
        let message: String
        switch verdict {
        case .unconfirmed(let version):
            message = String(localized: "Alguém tentou adulterar o código da Escalibur: a versão \(version) apareceu na App Store sem a assinatura da Escalibur. A equipe da Escalibur está investigando.")
        case .tampered(let version):
            message = String(localized: "Alguém mexeu na lista assinada que confirma cada versão da Escalibur, e a versão \(version) da App Store não pode ser confirmada. A equipe da Escalibur está investigando.")
        case .upToDate, .confirmed, .unknown:
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

    private func refreshLock() {
        if let alarm, !emergency {
            UpdateAlarmWindow.shared.show(alarm) { [weak self] in self?.useInEmergency() }
        } else {
            UpdateAlarmWindow.shared.hide()
        }
        // Com alarme, de 5 em 5 minutos (em emergencia tambem: confirmada a versao, o alarme
        // sai e a proxima abertura ja vem sem trava).
        if alarm == nil {
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
        case .upToDate, .confirmed: Preferences.updateAlarm = nil
        case .unknown: break
        }
    }
}
