import EscaliburChains
import EscaliburCore
import EscaliburKeys
import SwiftUI

/// S1: Ajustes.
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var openingEnvelope = false
    @State private var alerts: PriceAlertFile?
    @State private var receipts: ReceiptWatchFile?

    private var alertsValue: String? {
        guard let alerts else { return nil }
        guard alerts.enabled, !alerts.coins.isEmpty else { return String(localized: "Desligados") }
        return alerts.coins.count == 1 ? String(localized: "1 moeda") : String(localized: "\(alerts.coins.count) moedas")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TabTitle(String(localized: "Ajustes"))

                    SettingsGroup {
                        NavigationLink { WalletsListView() } label: {
                            SettingsRow(icon: MainTabs.walletSymbol, title: String(localized: "Carteiras"), value: "\(session.metadata.wallets.count)")
                        }
                        NavigationLink { SecuritySettingsView() } label: {
                            SettingsRow(icon: "lock", title: String(localized: "Segurança"))
                        }
                        NavigationLink { ContactsView() } label: {
                            SettingsRow(icon: "book.closed", title: String(localized: "Endereços salvos"), value: session.metadata.contacts.isEmpty ? nil : "\(session.metadata.contacts.count)")
                        }
                        Button { openingEnvelope = true } label: {
                            SettingsRow(icon: "envelope.open", title: String(localized: "Abrir um envelope"))
                        }
                    }
                    .padding(.top, Space.lg)

                    SettingsSection(title: String(localized: "Preferências")) {
                        NavigationLink { NetworksSettingsView() } label: {
                            SettingsRow(icon: "network", title: String(localized: "Redes"),
                                        value: String(localized: "\(Chain.all.count - session.metadata.settings.disabledChainIDs.count) ligadas"))
                        }
                        NavigationLink { PriceAlertsView() } label: {
                            SettingsRow(icon: "bell", title: String(localized: "Alertas de preço"), value: alertsValue)
                        }
                        .accessibilityIdentifier("ajustes-alertas")
                        NavigationLink { ReceiptWatchView() } label: {
                            SettingsRow(icon: "arrow.down.circle", title: String(localized: "Aviso de recebimento"),
                                        value: receipts.map { $0.enabled ? String(localized: "Ligado") : String(localized: "Desligado") })
                        }
                        .accessibilityIdentifier("ajustes-recebimento")
                    }

                    SettingsSection(title: String(localized: "Sobre")) {
                        NavigationLink { SupportView() } label: {
                            SettingsRow(icon: "questionmark.circle", title: String(localized: "Suporte"))
                        }
                        .accessibilityIdentifier("ajustes-suporte")
                        NavigationLink { AboutView() } label: {
                            SettingsRow(icon: "info.circle", title: String(localized: "Taxas, código auditável e versão"))
                        }
                    }
                }
                .padding(.bottom, Space.xl)
            }
            .background(Palette.void.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .statusBarBackdrop()
            .onAppear {
                Task { alerts = await PriceAlertCenter.shared.file() }
                Task { receipts = await ReceiptWatchCenter.shared.file() }
            }
        }
        .fullScreenCover(isPresented: $openingEnvelope) {
            OpenEnvelopeFlow(initialURL: nil) { openingEnvelope = false }
        }
    }
}

// MARK: Componentes de ajuste

struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .buttonStyle(RowStyle(surface: .body))
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.body)
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Palette.edge, lineWidth: 1)))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(.horizontal, Space.gutter)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).typeStyle(.note).foregroundStyle(Palette.inkSoft).padding(.horizontal, Space.gutter)
            SettingsGroup { content }
        }
        .padding(.top, Space.lg)
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    var valueColor: Color = Palette.inkSoft
    var chevron = true

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: icon).font(.system(size: 17, weight: .regular)).foregroundStyle(Palette.inkSoft).frame(width: 28)
            Text(title).typeStyle(.body).foregroundStyle(Palette.ink)
            Spacer()
            if let value { Text(value).typeStyle(.note).foregroundStyle(valueColor) }
            if chevron { Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkMuted) }
        }
        .padding(.horizontal, Space.md)
        .frame(minHeight: Height.rowCompact)
        .contentShape(Rectangle())
    }
}

// MARK: Carteiras

struct WalletsListView: View {
    @Environment(AppSession.self) private var session
    @Environment(AuthCoordinator.self) private var auth
    @Environment(ToastCenter.self) private var toasts
    @State private var adding = false
    @State private var reorder = WalletReorder()
    /// A linha com o apagar a mostra, e a carteira no popup de apagar.
    @State private var swiped: UUID?
    @State private var deleting: WalletMeta?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsGroup {
                    let wallets = session.metadata.wallets
                    ForEach(Array(wallets.enumerated()), id: \.element.id) { index, wallet in
                        NavigationLink { WalletSettingsView(walletID: wallet.id) } label: {
                            HStack(spacing: Space.sm) {
                                WalletGlyph(id: wallet.id, size: 32, selected: true, plain: true, passphrase: wallet.hasPassphrase)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: wallet.name).typeStyle(.row).foregroundStyle(Palette.ink)
                                    Text(wallet.hasBackup || wallet.isWatchOnly ? originText(wallet)
                                         : (wallet.wordsConfirmed ? String(localized: "Passphrase não conferida") : String(localized: "Palavras não confirmadas")))
                                        .typeStyle(.note).foregroundStyle(wallet.hasBackup || wallet.isWatchOnly ? Palette.inkSoft : Palette.caution)
                                }
                                Spacer()
                                Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkMuted)
                            }
                            .padding(.horizontal, Space.md).frame(height: Height.row)
                            .background(reorder.dragging == wallet.id ? Palette.rail : Color.clear)
                        }
                        .disabled(reorder.justDropped)
                        .swipeToDelete(id: wallet.id, open: $swiped) { deleting = wallet }
                        .walletReorder(reorder, id: wallet.id, index: index, count: wallets.count, rowHeight: Height.row, session: session)
                    }
                }
                .padding(.top, Space.md)
                if session.metadata.wallets.count > 1 {
                    Text("Segure uma carteira e arraste para mudar a ordem.").typeStyle(.note).foregroundStyle(Palette.inkMuted)
                        .padding(.horizontal, Space.gutter).padding(.top, Space.xs)
                }
                SecondaryButton(title: String(localized: "Adicionar carteira")) { adding = true }
                    .padding(.horizontal, Space.gutter).padding(.top, Space.lg)
            }
        }
        .scrollDisabled(reorder.dragging != nil)
        .background(Palette.void.ignoresSafeArea())
        .navigationTitle("Carteiras")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $adding) { AddWalletView(isFirst: false) { adding = false } }
        .fullScreenCover(item: $deleting) { wallet in
            RemoveWalletScreen(wallet: wallet) { confirmed in
                deleting = nil
                guard confirmed else { return }
                Task { _ = await WalletRemoval.remove(wallet, session: session, auth: auth, toasts: toasts) }
            }
        }
    }

    private func originText(_ wallet: WalletMeta) -> String {
        switch wallet.origin {
        case .created: if case .phrase(let n) = wallet.kind { return String(localized: "\(n) palavras") }; return ""
        case .importedPhrase: return String(localized: "Importada com a senha da carteira")
        case .importedEnvelope: return String(localized: "Importada de envelope")
        case .watch: return String(localized: "Só observar")
        }
    }
}

/// S2: uma carteira.
struct WalletSettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(AuthCoordinator.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    let walletID: UUID

    @State private var name = ""
    @State private var revealing = false
    @State private var sealing = false
    @State private var confirmRemove = false
    @State private var backingUp = false
    @State private var confirmingPassphrase = false

    private var wallet: WalletMeta? { session.metadata.wallets.first { $0.id == walletID } }

    var body: some View {
        ScrollView {
            if let wallet {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("", text: $name)
                        .typeStyle(.title).foregroundStyle(Palette.ink)
                        .onSubmit { rename(wallet) }
                        .padding(.horizontal, Space.gutter)

                    if !wallet.isWatchOnly {
                        // Tocar leva a cada copia (pedido do dono, 15/10/2026): o papel abre as
                        // palavras (e a conferencia, se ainda nao foi feita); o envelope, o lacre.
                        SettingsSection(title: String(localized: "Cópias")) {
                            Button { revealing = true } label: {
                                SettingsRow(icon: "doc.text", title: String(localized: "Papel"),
                                            value: wallet.wordsConfirmed ? (wallet.backupConfirmedAt.map { String(localized: "confirmado em \(Self.day($0))") } ?? String(localized: "importada")) : String(localized: "não confirmado"),
                                            valueColor: wallet.wordsConfirmed ? Palette.inkSoft : Palette.caution)
                            }
                            .accessibilityIdentifier("copia-papel")
                            if wallet.hasPassphrase {
                                Button { if wallet.passphraseConfirmed { revealing = true } else { confirmingPassphrase = true } } label: {
                                    SettingsRow(icon: "key.horizontal", title: String(localized: "Passphrase"),
                                                value: wallet.passphraseConfirmedAt.map { String(localized: "conferida em \(Self.day($0))") } ?? String(localized: "não conferida"),
                                                valueColor: wallet.passphraseConfirmed ? Palette.inkSoft : Palette.caution)
                                }
                                .accessibilityIdentifier("copia-passphrase")
                            }
                            Button { sealing = true } label: {
                                SettingsRow(icon: "envelope", title: String(localized: "Envelope Escalibur"),
                                            value: wallet.envelopeSealedAt.map { String(localized: "lacrado em \(Self.day($0))") } ?? String(localized: "nenhum"))
                            }
                            .accessibilityIdentifier("copia-envelope")
                        }
                        // Carteira com passphrase: pedir a passphrase para mover saldo, ligado de
                        // fabrica (pedido do dono, 16/10/2026). Desligar pede a passphrase e o PIN.
                        if wallet.hasPassphrase {
                            SettingsSection(title: String(localized: "Segurança")) {
                                Toggle(isOn: Binding(get: { PassphraseGate.asks(wallet) }, set: { on in
                                    Task { await setPassphraseToSend(on, wallet: wallet) }
                                })) {
                                    HStack(alignment: .top, spacing: Space.sm) {
                                        Image(systemName: "lock.shield").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.inkSoft).frame(width: 24)
                                            .padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Pedir a passphrase para enviar").typeStyle(.body).foregroundStyle(Palette.ink)
                                            Text("Envios, trocas e pontes desta carteira pedem a passphrase antes do \(KeyServices.biometryName) ou do PIN.")
                                                .typeStyle(.note).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .tint(Palette.success)
                                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                                .accessibilityIdentifier("pedir-passphrase")
                            }
                        }
                        if let last = wallet.lastRevealedAt {
                            Text("Última vez que a senha da carteira foi exibida: \(Fmt.relative(last, inSentence: true)).")
                                .typeStyle(.note).foregroundStyle(Palette.inkMuted).padding(.horizontal, Space.gutter).padding(.top, Space.xs)
                        }
                        SettingsGroup {
                            Button { revealing = true } label: { SettingsRow(icon: MainTabs.walletSymbol, title: String(localized: "Ver a senha da carteira")) }
                            Button { sealing = true } label: { SettingsRow(icon: "envelope.badge.shield.half.filled", title: String(localized: "Criptografar a senha da carteira")) }
                            // A base e sempre a carteira de sempre: a partir de uma com passphrase, cada
                            // carteira nova seria outra base, com a conta de tentativas zerada (revisao de
                            // seguranca de 26/10/2026).
                            if !wallet.hasPassphrase {
                                NavigationLink { PassphraseWalletView(base: wallet) } label: {
                                    SettingsRow(icon: "key.horizontal", title: String(localized: "Abrir ou criar com passphrase"))
                                }
                            }
                        }
                        .padding(.top, Space.lg)
                    }

                    // Sem copia conferida, a carteira nao recebe por caminho nenhum: o endereco
                    // daqui era o atalho que sobrava (auditoria 4, C7-01).
                    if !wallet.hasBackup, !wallet.isWatchOnly {
                        SettingsSection(title: String(localized: "Endereços")) {
                            Button { backingUp = true } label: {
                                SettingsRow(icon: "exclamationmark.triangle",
                                            title: wallet.wordsConfirmed ? String(localized: "Confira a passphrase para ver os endereços") : String(localized: "Grave as palavras para ver os endereços"),
                                            valueColor: Palette.caution)
                            }
                            .accessibilityIdentifier("enderecos-bloqueados")
                        }
                    } else {
                    SettingsSection(title: String(localized: "Endereços")) {
                        ForEach(wallet.accounts, id: \.chainID) { account in
                            if let chain = Chain.find(account.chainID), chain.family == .tron, wallet.tronForeignControl == true {
                                // A conta da Tron tem outra chave no controle, visto na importacao:
                                // o endereco nao aparece nem copia (segunda revisao, C7-05).
                                SettingsRow(icon: "exclamationmark.octagon", title: String(localized: "Tron: controlada por outra chave"), valueColor: Palette.down, chevron: false)
                            } else if let chain = Chain.find(account.chainID) {
                                Button {
                                    Pasteboard.copyAddress(account.address)
                                    toasts.show(String(localized: "Endereço copiado."))
                                } label: {
                                    HStack(spacing: Space.sm) {
                                        NetworkBadge(chain: chain, size: 24, ring: Palette.body)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(chain.name).typeStyle(.note).foregroundStyle(Palette.ink)
                                            Text(verbatim: Fmt.address(account.address, chain: chain, head: 8, tail: 6)).typeStyle(.monoSmall).foregroundStyle(Palette.inkSoft)
                                        }
                                        Spacer()
                                        Image(systemName: "doc.on.doc").font(.system(size: 13)).foregroundStyle(Palette.inkMuted)
                                    }
                                    .padding(.horizontal, Space.md).frame(minHeight: Height.row)
                                }
                            }
                        }
                    }
                    }

                    DestructiveButton(title: String(localized: "Remover deste iPhone")) { confirmRemove = true }
                        .padding(.horizontal, Space.gutter).padding(.top, Space.xl)
                }
                .padding(.vertical, Space.md)
                .onAppear { name = wallet.name }
            }
        }
        .background(Palette.void.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $revealing) {
            if let wallet { RevealFlow(wallet: wallet, purpose: wallet.wordsConfirmed ? .reveal : .backup) { revealing = false } }
        }
        .fullScreenCover(isPresented: $backingUp) {
            if let wallet { BackupNowFlow(wallet: wallet) { backingUp = false } }
        }
        .fullScreenCover(isPresented: $confirmingPassphrase) {
            if let wallet { ConfirmPassphraseView(wallet: wallet) { confirmingPassphrase = false } }
        }
        .fullScreenCover(isPresented: $sealing) {
            if let wallet { SealEnvelopeFlow(wallet: wallet) { sealing = false } }
        }
        .fullScreenCover(isPresented: $confirmRemove) {
            if let wallet {
                RemoveWalletScreen(wallet: wallet) { confirmed in
                    confirmRemove = false
                    if confirmed { Task { await remove() } }
                }
            }
        }
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(Fmt.locale))
    }

    /// Ligar e na hora. Desligar pede a passphrase e o PIN (nunca so o rosto), e a passphrase
    /// e conferida com a do cofre: quem viu o PIN nao tira a protecao.
    private func setPassphraseToSend(_ on: Bool, wallet: WalletMeta) async {
        if !on {
            guard let typed = await PassphraseGate.shared.ask(wallet, reason: String(localized: "Para deixar de pedir a passphrase nos envios de \(wallet.name), digite a passphrase. Depois vem o PIN.")) else { return }
            defer { typed.wipe() }
            let id = wallet.id
            if let wait = PassphraseGate.shared.begin(session, wallet: id) {
                toasts.show(wait)
                return
            }
            do {
                guard let matches = try await auth.perform(session, reason: String(localized: "Deixar de pedir a passphrase em \(wallet.name)"), presence: .pin, { rk in
                    let secret = try KeyServices.wallets.open(walletID: id, rk: rk)
                    defer { secret.wipe() }
                    return PassphraseGate.matches(secret.passphrase, typed)
                }) else {
                    PassphraseGate.shared.refund(session, wallet: id)
                    return
                }
                guard matches else {
                    PassphraseGate.shared.failed(session, wallet: id)
                    toasts.show(PassphraseGate.mismatchMessage)
                    return
                }
                PassphraseGate.shared.passed(session, wallet: id)
            } catch {
                // Nada foi conferido: a tentativa volta.
                PassphraseGate.shared.refund(session, wallet: id)
                toasts.show(AuthCoordinator.refusalMessage(error) ?? String(localized: "Não foi possível mudar agora."))
                return
            }
        }
        guard var updated = session.metadata.wallets.first(where: { $0.id == wallet.id }) else { return }
        updated.passphraseToSend = on
        session.update(updated)
    }

    private func rename(_ wallet: WalletMeta) {
        var updated = wallet
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updated.name = String(trimmed.prefix(40))
        session.update(updated)
    }

    private func remove() async {
        guard let wallet else { return }
        if await WalletRemoval.remove(wallet, session: session, auth: auth, toasts: toasts) { dismiss() }
    }
}

// MARK: Seguranca

/// S3: Seguranca.
struct SecuritySettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(AuthCoordinator.self) private var auth
    @Environment(ToastCenter.self) private var toasts
    /// A carteira no popup de apagar.
    @State private var deleting: WalletMeta?
    @State private var biometryPIN = false
    @State private var changingPIN = false
    /// O estado do Face ID visto pela chave, relido depois de cada mudanca: desligar agora
    /// pede o PIN e o rosto, e o dono pode desistir no meio.
    @State private var biometryOn = KeyServices.root.isBiometryEnabled
    @State private var biometryError: String?
    @State private var addressError: String?

    /// Quando a conferencia do endereco foi ligada nesta abertura do app, no relogio que nao volta.
    private static var addressOnAt: TimeInterval?

    /// Liga na hora; desligar tira uma barreira e pede o PIN, como o Safe Keyboard. No primeiro
    /// minuto depois de ligar, desligar nao pede (pedido do dono, 24/10/2026): quem ligou sem
    /// querer volta atras, e a barreira desfeita e a que acabou de nascer.
    private func setConfirmEveryAddress(_ on: Bool) async {
        guard !session.hardenedModeOn, on != session.confirmEveryAddressOn else { return }
        let justTurnedOn = Self.addressOnAt.map { ProcessInfo.processInfo.systemUptime - $0 < 60 } ?? false
        if !on, !justTurnedOn {
            do {
                guard try await auth.perform(session, reason: String(localized: "Desligar a conferência do endereço"), presence: .pin, { _ in () }) != nil else { return }
            } catch {
                addressError = AuthCoordinator.refusalMessage(error) ?? String(localized: "Não foi possível salvar. Tente de novo.")
                return
            }
        }
        let previous = session.metadata.settings.confirmEveryAddress
        session.metadata.settings.confirmEveryAddress = on
        do {
            try session.persist()
            Self.addressOnAt = on ? ProcessInfo.processInfo.systemUptime : nil
            addressError = nil
        } catch {
            session.metadata.settings.confirmEveryAddress = previous
            addressError = String(localized: "Não foi possível salvar. Tente de novo.")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if session.hardenedHold > 0 {
                    Banner(kind: .caution, title: AuthCoordinator.hardenedHoldMessage(session.hardenedHold))
                        .padding(.horizontal, Space.gutter)
                        .padding(.top, Space.md)
                        .accessibilityIdentifier("reforcado-espera")
                }
                SettingsGroup {
                    Button {
                        // Na espera de "Esperar 24 horas", trocar o PIN espera: recusa antes do teclado.
                        do {
                            if session.hardenedModeOn { try KeyServices.root.checkHardenedAllowed() }
                            biometryError = nil
                            changingPIN = true
                        } catch {
                            biometryError = AuthCoordinator.refusalMessage(error)
                        }
                    } label: { SettingsRow(icon: "circle.grid.3x3", title: String(localized: "Mudar o PIN")) }
                    NavigationLink { HardenedModeView() } label: {
                        SettingsRow(icon: "lock.shield", title: String(localized: "Super Security"),
                                    value: session.hardenedModeOn ? String(localized: "Ligado") : String(localized: "Desligado"))
                    }
                    .accessibilityIdentifier("ajustes-reforcado")
                    NavigationLink { OwnKeyboardView() } label: {
                        SettingsRow(icon: "keyboard", title: String(localized: "Safe Keyboard"),
                                    value: session.ownKeyboardOn ? String(localized: "Ligado") : String(localized: "Desligado"))
                    }
                    .accessibilityIdentifier("ajustes-teclado")
                    if !session.hardenedModeOn {
                    Toggle(isOn: Binding(get: { biometryOn }, set: { on in
                        if on { biometryPIN = true } else { Task { await turnBiometryOff() } }
                    })) {
                        HStack(spacing: Space.sm) {
                            Image(systemName: KeyServices.biometryIcon).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.inkSoft).frame(width: 24)
                            Text("\(KeyServices.biometryName)").typeStyle(.body).foregroundStyle(KeyServices.biometryAvailable ? Palette.ink : Palette.inkMuted)
                        }
                    }
                    .tint(Palette.success)
                    .disabled(!KeyServices.biometryAvailable)
                    .padding(.horizontal, Space.md).frame(minHeight: Height.rowCompact)
                    }
                    if VoiceGate.featureEnabled {
                        NavigationLink { VoiceSettingsView() } label: {
                            SettingsRow(icon: "waveform", title: String(localized: "Confirmação por voz"), value: session.metadata.settings.voice.enabled ? String(localized: "Ligada") : String(localized: "Desligada"))
                        }
                    }
                    NavigationLink { AutoLockView() } label: {
                        SettingsRow(icon: "lock.rotation", title: String(localized: "Bloquear o app"), value: AutoLockView.label(session.metadata.settings.autoLockSeconds))
                    }
                }
                .padding(.top, Space.md)

                Text(biometryError ?? (KeyServices.biometryAvailable
                     ? String(localized: "Com o \(KeyServices.biometryName) ligado, ver as palavras, lacrar um envelope e remover carteira pedem o PIN e o rosto. Depois de reiniciar o iPhone ou de a bateria acabar, o \(KeyServices.biometryName) só volta a valer depois do PIN digitado uma vez.")
                     : (KeyServices.biometryName == "Touch ID" ? String(localized: "Para usar o Touch ID aqui, cadastre uma digital em Ajustes do iPhone, em Touch ID e código.") : String(localized: "Para usar o \(KeyServices.biometryName) aqui, cadastre um rosto em Ajustes do iPhone, em \(KeyServices.biometryName) e código."))))
                    .typeStyle(.note).foregroundStyle(biometryError == nil ? Palette.inkMuted : Palette.down)
                    .padding(.horizontal, Space.gutter).padding(.top, Space.xs)
                    .fixedSize(horizontal: false, vertical: true)

                // Conferir o endereco em todo envio (pedido do dono, 23/10/2026): desligada de fabrica,
                // sempre ligada no Super Security, e desligar pede o PIN, como o Safe Keyboard.
                SettingsGroup {
                    Toggle(isOn: Binding(get: { session.confirmEveryAddressOn }, set: { on in Task { await setConfirmEveryAddress(on) } })) {
                        HStack(spacing: Space.sm) {
                            Image(systemName: "checkmark.shield").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.inkSoft).frame(width: 24)
                            Text("Conferir o endereço em todo envio").typeStyle(.body).foregroundStyle(Palette.ink)
                        }
                    }
                    .tint(Palette.success)
                    .disabled(session.hardenedModeOn)
                    .padding(.horizontal, Space.md).frame(minHeight: Height.rowCompact)
                    .accessibilityIdentifier("ajustes-conferir-endereco")
                }
                .padding(.top, Space.lg)
                Text(addressError ?? (session.hardenedModeOn
                     ? String(localized: "No Super Security, a conferência do endereço fica sempre ligada.")
                     : String(localized: "Todo envio pede os 6 últimos caracteres do endereço de destino, lidos de onde você copiou.")))
                    .typeStyle(.note).foregroundStyle(addressError == nil ? Palette.inkMuted : Palette.down)
                    .padding(.horizontal, Space.gutter).padding(.top, Space.xs)
                    .fixedSize(horizontal: false, vertical: true)

                if let wallet = session.selectedWallet, !wallet.isWatchOnly, !wallet.hasPassphrase {
                    SettingsGroup {
                        NavigationLink { PassphraseWalletView(base: wallet) } label: {
                            SettingsRow(icon: "key.horizontal", title: String(localized: "Carteira com passphrase"))
                        }
                    }
                    .padding(.top, Space.lg)
                    Text("Outra carteira, aberta pela senha de \(wallet.name) com uma passphrase que só você sabe.")
                        .typeStyle(.note).foregroundStyle(Palette.inkMuted)
                        .padding(.horizontal, Space.gutter).padding(.top, Space.xs)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // No lugar do "Apagar depois de PINs errados", que foi para "Bloquear o app": apagar
                // deste iPhone a carteira aberta, com o popup e a confirmacao de sempre (pedido do
                // dono, 24/10/2026).
                if let wallet = session.selectedWallet {
                    SettingsGroup {
                        Button { deleting = wallet } label: {
                            SettingsRow(icon: "trash", title: String(localized: "Apagar carteira deste iPhone"))
                        }
                        .accessibilityIdentifier("ajustes-apagar-carteira")
                    }
                    .padding(.top, Space.lg)
                }

                Text(session.hardenedModeOn
                     ? String(localized: "Super Security: abrir o app e todo envio, troca e ordem pedem o PIN e o \(KeyServices.biometryName).")
                     : String(localized: "Todo envio, troca e ordem pede \(KeyServices.biometryName) ou PIN."))
                    .typeStyle(.note).foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, Space.gutter).padding(.top, Space.lg)
            }
        }
        .background(Palette.void.ignoresSafeArea())
        .navigationTitle("Segurança")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $biometryPIN, onDismiss: { biometryOn = KeyServices.root.isBiometryEnabled }) { EnableBiometrySheet { biometryPIN = false } }
        .fullScreenCover(isPresented: $changingPIN) { ChangePINFlow { changingPIN = false } }
        .fullScreenCover(item: $deleting) { wallet in
            RemoveWalletScreen(wallet: wallet) { confirmed in
                deleting = nil
                guard confirmed else { return }
                Task { _ = await WalletRemoval.remove(wallet, session: session, auth: auth, toasts: toasts) }
            }
        }
        .onAppear {
            biometryOn = KeyServices.root.isBiometryEnabled
            session.refreshHardenedHold()
        }
    }

    /// Desligar pede o PIN e o rosto (A1): com o Face ID desligado, o que pedia os dois
    /// passa a pedir so o PIN, e quem viu o PIN desligaria aqui antes de ver as palavras.
    private func turnBiometryOff() async {
        biometryError = nil
        do {
            _ = try await auth.retrying(reason: String(localized: "Desligar o \(KeyServices.biometryName)"), presence: .pinAndBiometry) { credential in
                try await session.disableBiometry(credential)
            }
        } catch {
            biometryError = AuthCoordinator.refusalMessage(error)
        }
        biometryOn = KeyServices.root.isBiometryEnabled
    }
}

/// Quantos PINs errados apagam as carteiras deste iPhone, ou nunca. Mora em "Bloquear o app" e
/// abre ali mesmo, embaixo da linha, em vez de outra tela (pedido do dono, 24/10/2026).
struct WipeAfterErrorsSection: View {
    @Environment(AppSession.self) private var session
    @Environment(AuthCoordinator.self) private var auth
    @State private var current = KeyServices.root.wipeThreshold
    @State private var error: String?
    @State private var open = WipeAfterErrorsSection.startsOpen

    static let options: [UInt32?] = [nil] + PINPolicy.wipeOptions.map { Optional($0) }

    /// `-tela bloqueio` abre ja aberta, para conferir.
    private static var startsOpen: Bool {
        #if DEBUG
        return DebugDemo.screen == "bloqueio"
        #else
        return false
        #endif
    }

    static func label(_ threshold: UInt32?) -> String {
        threshold.map { String(localized: "Depois de \($0) erros") } ?? String(localized: "Nunca")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup {
                Button { withAnimation(Motion.select) { open.toggle() } } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "trash").font(.system(size: 17, weight: .regular)).foregroundStyle(Palette.inkSoft).frame(width: 28)
                        Text("Apagar depois de PINs errados").typeStyle(.body).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(Self.label(current)).typeStyle(.note).foregroundStyle(Palette.inkSoft)
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkMuted)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .padding(.horizontal, Space.md)
                    .frame(minHeight: Height.rowCompact)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("bloquear-apagar-erros")
                .accessibilityValue(Self.label(current))
                if open {
                    ForEach(Self.options, id: \.self) { option in
                        Button { Task { await choose(option) } } label: {
                            HStack {
                                Text(Self.label(option)).typeStyle(.body).foregroundStyle(Palette.ink)
                                Spacer()
                                if current == option {
                                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                                }
                            }
                            // Alinhadas ao titulo da linha, depois do icone.
                            .padding(.leading, Space.md + 28 + Space.sm).padding(.trailing, Space.md)
                            .frame(minHeight: Height.rowCompact)
                            .contentShape(Rectangle())
                        }
                        .transition(.opacity)
                    }
                }
            }
            if open || error != nil {
                // So o PIN errado conta, tambem no Super Security: o rosto que nao confirma nao conta
                // (decisao do dono, 25/10/2026).
                Text(error ?? String(localized: "Contra quem pega o iPhone e tenta adivinhar o PIN. Depois do número escolhido de PINs errados seguidos, este iPhone apaga as carteiras; só a senha de cada carteira ou um envelope traz de volta. Mudar pede o PIN."))
                    .typeStyle(.note).foregroundStyle(error == nil ? Palette.inkMuted : Palette.down)
                    .padding(.horizontal, Space.gutter).padding(.top, Space.xs)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    /// Qualquer mudanca pede o PIN: ligar e uma forma de destruir as carteiras errando
    /// de proposito; desligar ou afrouxar tira a barreira contra quem tenta adivinhar.
    private func choose(_ option: UInt32?) async {
        guard option != current else { return }
        if option != nil, let missing = session.metadata.wallets.first(where: { !$0.hasBackup && !$0.isWatchOnly }) {
            error = String(localized: "Confirme a cópia de \(missing.name) antes de ligar.")
            return
        }
        error = nil
        let reason = option.map { String(localized: "Apagar depois de \($0) PINs errados") } ?? String(localized: "Nunca apagar por PINs errados")
        do {
            guard try await auth.perform(session, reason: reason, presence: .pin, { _ in true }) == true else { return }
        } catch {
            self.error = AuthCoordinator.refusalMessage(error)
            return
        }
        do {
            try KeyServices.root.setWipeAfterErrors(option)
            current = option
        } catch {
            self.error = String(localized: "Não foi possível mudar agora. Tente de novo.")
        }
    }
}

struct EnableBiometrySheet: View {
    @Environment(AppSession.self) private var session
    let onDone: () -> Void
    @State private var entry = PINEntry()
    @State private var working = false

    var body: some View {
        PINScreen(title: String(localized: "Confirme com o PIN"), subtitle: String(localized: "Para ligar o \(KeyServices.biometryName)."), entry: entry, working: working, onComplete: {
            Task {
                working = true
                defer { working = false }
                do {
                    try await session.enableBiometry(pin: entry.take())
                    onDone()
                } catch RootKeyVault.Failure.wrongPIN(let remaining) {
                    entry.fail(AuthCoordinator.wrongPINMessage(remaining))
                } catch RootKeyVault.Failure.wiped {
                    onDone()
                } catch RootKeyVault.Failure.throttled(let seconds) {
                    entry.fail(String(localized: "Tentativas demais. Tente de novo em \(LockView.duration(seconds))."))
                } catch RootKeyVault.Failure.cancelled {
                    entry.fail(String(localized: "O \(KeyServices.biometryName) não confirmou. Ele continua desligado."))
                } catch {
                    entry.fail(String(localized: "Não foi possível ligar o \(KeyServices.biometryName) agora."))
                }
            }
        }) {
            TertiaryButton(title: String(localized: "Cancelar"), action: onDone)
        }
    }
}

struct ChangePINFlow: View {
    @Environment(AppSession.self) private var session
    let onDone: () -> Void
    @State private var step = 0
    @State private var entry = PINEntry()
    @State private var current: SecureBytes?
    @State private var newPIN: SecureBytes?
    @State private var working = false

    var body: some View {
        PINScreen(
            title: [String(localized: "Digite o PIN atual"), String(localized: "Escolha o novo PIN"), String(localized: "Repita o novo PIN")][step],
            subtitle: step == 1
                ? (entry.length == 4
                    ? String(localized: "Quatro dígitos são mais fáceis de adivinhar que seis. Não use o código do iPhone: quem rouba o iPhone geralmente já viu esse código.")
                    : String(localized: "Não use o código do iPhone: quem rouba o iPhone geralmente já viu esse código."))
                : nil,
            entry: entry, working: working, onComplete: advance
        ) {
            VStack(spacing: Space.sm) {
                PINLengthToggle(entry: entry)
                    .opacity(step == 1 ? 1 : 0)
                    .disabled(step != 1)
                    .accessibilityHidden(step != 1)
                TertiaryButton(title: String(localized: "Cancelar")) { current?.wipe(); newPIN?.wipe(); onDone() }
            }
        }
    }

    /// Antes do ponto sem volta, qualquer falha deixa o PIN atual valendo.
    static func message(for error: Error) -> String {
        switch error as? RootKeyVault.Failure {
        case .wrongPIN: return String(localized: "O PIN atual não confere.")
        case .throttled(let seconds): return String(localized: "Tentativas demais. Tente de novo em \(LockView.duration(seconds)).")
        case .malformedPIN: return String(localized: "O PIN precisa ter 4 ou 6 números.")
        case .biometryNotConfirmed: return String(localized: "O \(KeyServices.biometryName) não confirmou. O PIN atual continua valendo.")
        case .biometryLockedOut, .biometryUnavailable, .hardenedSlotLost, .biometryHold, .biometryNotEnrolled, .hardenedFaceKeyFailed:
            return AuthCoordinator.refusalMessage(error) ?? String(localized: "Não foi possível trocar. O PIN atual continua valendo.")
        default: return String(localized: "Não foi possível trocar. O PIN atual continua valendo.")
        }
    }

    private func advance() {
        let pin = entry.take()
        switch step {
        case 0:
            current = pin
            step = 1
            entry.choose(length: PINPolicy.digits)
        case 1:
            newPIN = pin
            step = 2
        default:
            guard let current, let newPIN else { return }
            let same = Hash.constantTimeEqual(newPIN, pin)
            pin.wipe()
            guard same else {
                entry.fail(String(localized: "Os dois não conferem. Escolha de novo."))
                step = 1
                return
            }
            working = true
            Task {
                do {
                    let reason = String(localized: "Mudar o PIN")
                    let confirm = String(localized: "Confirme o \(KeyServices.biometryName) para conferir o PIN novo")
                    try await Offload.run {
                        defer { current.wipe(); newPIN.wipe() }
                        // Modo reforcado: o PIN atual e o rosto abrem, e o rk.and e regravado com
                        // o PIN novo, conferido com o rosto antes do commit.
                        if KeyServices.root.securityMode == .hardened {
                            try KeyServices.root.changeHardenedPIN(currentPIN: current, newPIN: newPIN, reason: reason, confirmReason: confirm)
                            return
                        }
                        let rk = try KeyServices.root.unlock(pin: current)
                        defer { rk.wipe() }
                        try KeyServices.root.changePIN(rk: rk, newPIN: newPIN)
                    }
                    onDone()
                } catch RootKeyVault.Failure.wiped {
                    session.eraseEverything()
                    onDone()
                } catch {
                    working = false
                    step = 0
                    entry.useStoredLength()
                    entry.fail(Self.message(for: error))
                }
            }
        }
    }
}

struct AutoLockView: View {
    @Environment(AppSession.self) private var session
    @Environment(AuthCoordinator.self) private var auth
    @State private var error: String?
    /// 5 minutos entrou a pedido do dono (16/10/2026), e 10 minutos tambem (18/10/2026);
    /// alongar continua pedindo o PIN.
    static let options = [0, 30, 60, 300, 600]

    /// O maior prazo oferecido. Um valor gravado por uma versao anterior (15 minutos) vale
    /// como este.
    static func clamped(_ seconds: Int) -> Int { min(max(seconds, 0), options.last ?? 600) }

    /// O motivo que o Face ID mostra ao mudar o prazo.
    static func reason(_ seconds: Int) -> String {
        switch clamped(seconds) {
        case 0: return String(localized: "Bloquear o app ao sair dele")
        case 30: return String(localized: "Bloquear o app depois de 30 segundos")
        case 60: return String(localized: "Bloquear o app depois de 1 minuto")
        case 300: return String(localized: "Bloquear o app depois de 5 minutos")
        default: return String(localized: "Bloquear o app depois de 10 minutos")
        }
    }

    static func label(_ seconds: Int) -> String {
        switch clamped(seconds) {
        case 0: return String(localized: "Ao sair do app")
        case 30: return String(localized: "Depois de 30 segundos")
        case 60: return String(localized: "Depois de 1 minuto")
        case 300: return String(localized: "Depois de 5 minutos")
        default: return String(localized: "Depois de 10 minutos")
        }
    }

    var body: some View {
        ScrollView {
            SettingsGroup {
                ForEach(Self.options, id: \.self) { seconds in
                    Button {
                        Task { await choose(seconds) }
                    } label: {
                        HStack {
                            Text(Self.label(seconds)).typeStyle(.body).foregroundStyle(Palette.ink)
                            Spacer()
                            if Self.clamped(session.metadata.settings.autoLockSeconds) == seconds {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                            }
                        }
                        .padding(.horizontal, Space.md).frame(minHeight: Height.rowCompact)
                    }
                }
            }
            .padding(.top, Space.md)
            Text(error ?? String(localized: "Encurtar vale na hora. Alongar pede o PIN."))
                .typeStyle(.note).foregroundStyle(error == nil ? Palette.inkMuted : Palette.down)
                .padding(.horizontal, Space.gutter).padding(.top, Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            // O apagar depois de PINs errados mora aqui, junto do bloqueio (pedido do dono, 24/10/2026).
            WipeAfterErrorsSection()
                .padding(.top, Space.lg)
        }
        .background(Palette.void.ignoresSafeArea())
        .navigationTitle("Bloquear o app")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Encurtar so reduz a janela de quem pega o iPhone destravado. Alongar amplia, e
    /// por isso pede o PIN.
    private func choose(_ seconds: Int) async {
        error = nil
        let current = Self.clamped(session.metadata.settings.autoLockSeconds)
        guard seconds != current else { return }
        if seconds > current {
            do {
                guard try await auth.perform(session, reason: Self.reason(seconds), presence: .pin, { _ in true }) == true else { return }
            } catch {
                self.error = AuthCoordinator.refusalMessage(error)
                return
            }
        }
        let previous = session.metadata.settings.autoLockSeconds
        session.metadata.settings.autoLockSeconds = seconds
        do {
            try session.persist()
        } catch {
            session.metadata.settings.autoLockSeconds = previous
            self.error = String(localized: "Não foi possível salvar. Tente de novo.")
        }
    }
}

struct NetworksSettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Para ler saldos, cotações e enviar, o app fala direto com nós públicos de cada rede, de empresas diferentes. Não existe servidor da Escalibur no meio.")
                    .typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.horizontal, Space.gutter).padding(.top, Space.md)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsGroup {
                    ForEach(Chain.all) { chain in
                        Toggle(isOn: Binding(
                            get: { !session.metadata.settings.disabledChainIDs.contains(chain.id) },
                            set: { on in
                                if on { session.metadata.settings.disabledChainIDs.remove(chain.id) } else { session.metadata.settings.disabledChainIDs.insert(chain.id) }
                                try? session.persist()
                            }
                        )) {
                            HStack(spacing: Space.sm) {
                                NetworkBadge(chain: chain, size: 24, ring: Palette.body)
                                Text(chain.name).typeStyle(.body).foregroundStyle(Palette.ink)
                            }
                        }
                        .tint(Palette.success)
                        .padding(.horizontal, Space.md).frame(minHeight: Height.rowCompact)
                    }
                }
                .padding(.top, Space.md)
            }
        }
        .background(Palette.void.ignoresSafeArea())
        .navigationTitle("Redes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    @State private var legalDocument: LegalDocument?
    @State private var auditing = false
    /// A pagina de auditoria do site: as verificacoes, os hosts, as dependencias travadas e o
    /// codigo das chaves linha a linha. Publica tambem com o repositorio privado (18/10/2026).
    static let auditURL = URL(string: "https://escalibur-wallet.github.io/auditoria/")!  // swiftlint:disable:this force_unwrapping

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Taxas").typeStyle(.heading).foregroundStyle(Palette.ink)
                    Text("A Escalibur não cobra taxa sobre envios, recebimentos, trocas ou ordens. Você paga só a taxa da rede e, nas trocas, a do provedor, que já vem dentro do valor que você recebe.")
                        .typeStyle(.body).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    // Publicado para auditoria, nao de codigo aberto (LICENSE, 16/10/2026). A frase da
                    // licenca saiu e o "travadas por digesto" virou linguagem de gente (pedido do
                    // dono, 17/10/2026).
                    Text("Código auditável").typeStyle(.heading).foregroundStyle(Palette.ink)
                    Text("Todo o código que guarda chaves, assina e fala com as redes é publicado para quem quiser auditar, linha por linha. As bibliotecas de criptografia são compiladas a partir do código-fonte, e cada versão delas é conferida por uma impressão digital: se alguém trocar uma, a compilação para.")
                        .typeStyle(.body).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                    Text("Versão \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .typeStyle(.note).foregroundStyle(Palette.inkMuted)
                    // A auditoria aberta dentro do app, no navegador da Apple (pedido do dono,
                    // 18/10/2026; antes, no Safari). O app nao abre conexao nenhuma: quem abre e o
                    // Safari, em outro processo (`SiteBrowser`).
                    Button { auditing = true } label: {
                        Label(String(localized: "Auditar o código"), systemImage: "chevron.left.forwardslash.chevron.right")
                            .typeStyle(.action)
                            .frame(maxWidth: .infinity).frame(height: Height.secondary)
                    }
                    .buttonStyle(SecondaryStyle())
                    .padding(.top, Space.xs)
                    .accessibilityIdentifier("sobre-auditar")
                    .fullScreenCover(isPresented: $auditing) {
                        SiteBrowser(url: Self.auditURL) { auditing = false }.ignoresSafeArea()
                    }
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Preços").typeStyle(.heading).foregroundStyle(Palette.ink)
                    Text("Preços e dados de mercado: CoinGecko, com CoinPaprika e OKX de reserva. Os saldos e as transações vêm direto das redes.")
                        .typeStyle(.body).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
                SettingsGroup {
                    Button { legalDocument = .terms } label: { SettingsRow(icon: "doc.text", title: String(localized: "Termos de uso")) }
                    Button { legalDocument = .privacy } label: { SettingsRow(icon: "hand.raised", title: String(localized: "Política de privacidade")) }
                }
                // O grupo ja traz a margem da tela; aqui ela vem do VStack, e somar as duas
                // desalinhava os botoes do texto acima.
                .padding(.horizontal, -Space.gutter)
            }
            .padding(Space.gutter)
        }
        .background(Palette.void.ignoresSafeArea())
        .navigationTitle("Sobre")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $legalDocument) { LegalDocumentView(document: $0) }
    }
}

// MARK: Apagar uma carteira

/// Remover uma carteira deste iPhone: o aviso do que se perde e a remocao, com PIN e Face ID
/// (menos a de so observar, que nao guarda chave). Um caminho so para a lista, a troca de
/// carteira e os ajustes da carteira.
@MainActor
enum WalletRemoval {
    static func warning(_ wallet: WalletMeta) -> String {
        if wallet.isWatchOnly { return String(localized: "O endereço sai da lista. Nada muda na rede.") }
        if !wallet.hasBackup { return String(localized: "Esta carteira não tem cópia confirmada. Removida, o saldo pode ficar inacessível para sempre.") }
        return wallet.hasPassphrase
            ? String(localized: "O saldo continua na blockchain. Sem a senha da carteira e a passphrase, ou um envelope, você não volta a acessá-lo.")
            : String(localized: "O saldo continua na blockchain. Sem a senha da carteira ou um envelope, você não volta a acessá-lo.")
    }

    /// Devolve se removeu.
    static func remove(_ wallet: WalletMeta, session: AppSession, auth: AuthCoordinator, toasts: ToastCenter) async -> Bool {
        if !wallet.isWatchOnly {
            do {
                guard try await auth.perform(session, reason: String(localized: "Remover \(wallet.name) deste iPhone"), presence: .pinAndBiometry, { _ in true }) == true else { return false }
            } catch {
                if let message = AuthCoordinator.refusalMessage(error) { toasts.show(message) }
                return false
            }
        }
        do {
            try session.remove(wallet)
            return true
        } catch {
            toasts.show(error.localizedDescription)
            return false
        }
    }
}

/// A confirmacao de remover uma carteira, no formato das telas de aviso do app, como "So voce tem a
/// chave" (pedido do dono, 24/10/2026): o que acontece com o saldo, que so as palavras anotadas
/// trazem a carteira de volta, e o deslizar de pixels embaixo, que um toque sem querer nao dispara.
/// Depois dele vem o PIN e o Face ID de sempre.
struct RemoveWalletScreen: View {
    @Environment(AppSession.self) private var session
    let wallet: WalletMeta
    let onClose: (_ confirmed: Bool) -> Void

    /// A unica carteira: removida, o app apaga tudo e volta ao comeco (`AppSession.remove`).
    private var isLast: Bool { session.metadata.wallets.allSatisfy { $0.id == wallet.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    if !wallet.isWatchOnly, !wallet.hasBackup {
                        Banner(kind: .failure, title: WalletRemoval.warning(wallet)).padding(.top, Space.lg)
                    }
                    VStack(alignment: .leading, spacing: Space.md) {
                        if wallet.isWatchOnly {
                            point("list.bullet", String(localized: "Só sai da lista"), WalletRemoval.warning(wallet))
                        } else {
                            point("link", String(localized: "Nada muda na blockchain"),
                                  String(localized: "O saldo continua na rede. Remover apaga a carteira só deste iPhone."))
                            point("key.horizontal", String(localized: "Só as palavras trazem de volta"),
                                  String(localized: "Para usar a carteira de novo, você precisa das \(wordCount) palavras que anotou, ou de um envelope Escalibur. Ninguém recupera sem elas, nem a Escalibur."))
                            if wallet.hasPassphrase {
                                point("lock", String(localized: "E a passphrase"),
                                      String(localized: "Esta carteira abre com uma passphrase. Sem ela, as palavras abrem só a carteira de sempre."))
                            }
                            point("checkmark.circle", String(localized: "Confira antes de remover"),
                                  String(localized: "Tenha as palavras com você e confira que estão certas. Depois de removida, não dá para ver as palavras por aqui."))
                        }
                        if isLast {
                            point("arrow.clockwise", String(localized: "O app recomeça do zero"),
                                  String(localized: "É a única carteira deste iPhone. Removida, o app volta a ser como recém-instalado: o PIN, os ajustes e os contatos são apagados."))
                        }
                    }
                    .padding(.top, Space.lg)
                }
                .padding(.horizontal, Space.gutter)
                // Um pouco abaixo do alto (pedido do dono, 24/10/2026).
                .padding(.top, Space.xl)
                .padding(.bottom, Space.md)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                ActionFooter {
                    SlideToConfirm(title: String(localized: "Deslize para remover")) { onClose(true) }
                        .accessibilityIdentifier("deslizar-para-remover")
                }
            }
            .background(Palette.void.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onClose(false) } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                    }
                    .accessibilityLabel("Fechar")
                }
            }
        }
    }

    private var wordCount: Int {
        if case .phrase(let count) = wallet.kind { return count }
        return 12
    }

    private var header: some View {
        VStack(spacing: Space.xs) {
            // A lixeira em pixels: a carteira cai nela (pedido do dono, 24/10/2026).
            PixelTrashScene().frame(width: 150, height: 156)
            Text("Remover \(wallet.name) deste iPhone?")
                .typeStyle(.title).foregroundStyle(Palette.ink)
                .padding(.top, Space.xs)
            Text("Antes de deslizar, confira o que acontece.")
                .typeStyle(.body).foregroundStyle(Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Palette.control))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).typeStyle(.row).foregroundStyle(Palette.ink)
                Text(detail).typeStyle(.note).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A lixeira de remover carteira, em pixels cheios como o cadeado das outras cenas (redesenhada
/// a pedido do dono, 24/10/2026). A carteira, um cartao com o fecho, aparece em cima; a tampa
/// gira na dobradica da esquerda ate quase de pe; a carteira desce para dentro, por tras da
/// frente da lixeira; a tampa fecha com um quique curto, e a lixeira fica um tempo fechada antes
/// do proximo giro. Os pixels cifram de leve no tom de cada parte. Com Reduzir Movimento, a
/// carteira parada em cima da lixeira fechada.
struct PixelTrashScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let pitch: CGFloat = 6, cell: CGFloat = 4.9
    private static let period = 3.8
    /// A lixeira, 15 de largura: a alca, a tampa, e o corpo afinando embaixo, com tres frisos.
    private static let handle = [".....#####.....", ".....#...#....."]
    private static let lid = ["###############", ".#############."]
    private static let body = ["..###########..", "..##-##-##-##..", "..##-##-##-##..", "..##-##-##-##..", "..##-##-##-##..",
                               "..##-##-##-##..", "..##-##-##-##..", "..##-##-##-##..", "...#-##-##-#...", "...#########..."]
    /// A carteira, 11 por 7: o cartao cheio e o fecho escuro do lado, com o botao claro.
    private static let wallet = ["###########", "###########", "#######----", "#######-o--", "#######----", "###########", "###########"]

    var body: some View {
        // A cada quadro da tela (60 ou 120 por segundo): a 30, a tampa fechando pulava quadros
        // (pedido do dono, 30/10/2026).
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.6 : timeline.date.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.period)
            let clock = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in draw(context, size: size, t: t, clock: clock) }
        }
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }

    private func draw(_ context: GraphicsContext, size: CGSize, t: Double, clock: Double) {
        let p = Self.pitch
        let x0 = (size.width - 15 * p) / 2
        // De baixo para cima: o corpo, um respiro, a tampa e a alca, e a carteira pairando acima.
        let bodyTop = size.height - CGFloat(Self.body.count) * p
        let lidTop = bodyTop - 3 * p
        let handleTop = lidTop - 2 * p

        // A historia: a carteira chega, a tampa abre, a carteira desce, a tampa fecha e quica. O
        // fechar leva 0,3 s (antes 0,22, rapido demais para parecer continuo).
        let arrive = Self.smooth(t / 0.4)
        let open = Self.easeOut((t - 0.55) / 0.3) * (1 - Self.smooth((t - 1.55) / 0.3))
        let bounce = t > 1.85 && t < 2.18 ? sin((t - 1.85) / 0.33 * .pi) : 0
        let fall = Self.easeIn((t - 0.85) / 0.6)
        let walletRest = handleTop - 9 * p
        let walletTop = walletRest + CGFloat(fall) * (bodyTop + 2 * p - walletRest) + CGFloat(1 - arrive) * -6

        func bit(_ a: Int, _ b: Int) -> Double {
            let phase = PixelFill.noise(a, b, 0x7A5)
            let beat = clock * 2.5 * (0.6 + 0.8 * phase) + phase * 8
            let step = beat.rounded(.down)
            let x = PixelFill.noise(a, b, Int(step)), y = PixelFill.noise(a, b, Int(step) + 1)
            return x + (y - x) * Self.smooth(beat - step)
        }
        func square(_ c: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ tone: Double, _ alpha: Double = 1) {
            guard alpha > 0.01 else { return }
            let r = CGRect(x: x - Self.cell / 2, y: y - Self.cell / 2, width: Self.cell, height: Self.cell)
            c.fill(Path(roundedRect: r, cornerRadius: Self.cell * 0.22), with: .color(PixelFill.gray(tone).opacity(alpha)))
        }

        // A carteira, cortada na boca da lixeira: dali para baixo ela esta dentro.
        var mouth = context
        mouth.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: bodyTop)))
        let walletX = x0 + 2 * p
        for (row, line) in Self.wallet.enumerated() {
            for (column, mark) in line.enumerated() where mark != "." {
                let tone = mark == "-" ? 0.34 : (mark == "o" ? 0.96 : 0.84 + 0.08 * bit(column, row + 40))
                let born = Self.smooth((arrive - 0.6 * PixelFill.noise(column, row, 0x3C1)) / 0.4)
                square(mouth, walletX + (CGFloat(column) + 0.5) * p, walletTop + (CGFloat(row) + 0.5) * p, tone, born)
            }
        }

        // O corpo, com os frisos mais escuros.
        for (row, line) in Self.body.enumerated() {
            for (column, mark) in line.enumerated() where mark != "." {
                let tone = mark == "-" ? 0.26 + 0.05 * bit(column, row) : 0.5 + 0.1 * bit(column, row)
                square(context, x0 + (CGFloat(column) + 0.5) * p, bodyTop + (CGFloat(row) + 0.5) * p, tone)
            }
        }

        // A tampa e a alca juntas, girando na dobradica da esquerda ate quase de pe: a boca fica
        // livre para a carteira passar. Fechando, um quique curto.
        let angle = Double(open) * 1.25 - bounce * 0.12
        let hinge = CGPoint(x: x0, y: lidTop + 2 * p)
        for (block, top, base) in [(Self.handle, handleTop, 0.7), (Self.lid, lidTop, 0.78)] {
            for (row, line) in block.enumerated() {
                for (column, mark) in line.enumerated() where mark == "#" {
                    let dx = (CGFloat(column) + 0.5) * p, dy = top + (CGFloat(row) + 0.5) * p - hinge.y
                    let x = hinge.x + dx * CGFloat(cos(angle)) + dy * CGFloat(sin(angle))
                    let y = hinge.y - dx * CGFloat(sin(angle)) + dy * CGFloat(cos(angle))
                    square(context, x, y, base + 0.1 * bit(column, row + 20 + (base > 0.75 ? 5 : 0)))
                }
            }
        }
    }

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    private static func smooth(_ x: Double) -> Double { let c = clamp(x); return c * c * (3 - 2 * c) }
    private static func easeIn(_ x: Double) -> Double { let c = clamp(x); return c * c * c }
    private static func easeOut(_ x: Double) -> Double { let c = 1 - clamp(x); return 1 - c * c * c }
}

/// Arrastar a linha para a esquerda mostra o apagar, como nas listas do iOS (pedido do dono,
/// 22/10/2026). Uma linha aberta por vez; tocar nela fecha. O arrasto so conta na horizontal: a
/// lista continua rolando e o segurar-e-arrastar da ordem continua igual.
///
/// 30/10/2026 (pedido do dono, no seletor de carteiras): o soltar do dedo no fim do arrasto
/// nao vale como toque na linha (escolhia a carteira em vez de deixar o apagar aberto); o
/// toque que fecha a linha aberta anda junto com ela e nao cobre mais o apagar; e o vermelho
/// so ocupa a parte descoberta, sem ficar por baixo da linha e aparecer nas bordas.
struct SwipeToDelete: ViewModifier {
    let id: UUID
    @Binding var open: UUID?
    var surface: Color = Palette.body
    let onDelete: () -> Void
    @State private var drag: CGFloat = 0
    /// O dedo esta arrastando a linha de lado, ou acabou de soltar.
    @State private var moving = false
    private static let width: CGFloat = 84
    /// Para a linha que e um botao com acao propria (o seletor de carteiras): um arrasto de
    /// lado acabou de acontecer, e o toque de agora nao conta.
    @MainActor static var recentlySwiped = false

    func body(content: Content) -> some View {
        let shown = open == id
        let offset = min(0, max(-Self.width * 1.3, (shown ? -Self.width : 0) + drag))
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { open = nil }
                    onDelete()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash.fill").font(.system(size: 17, weight: .semibold))
                        Text("Apagar").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: Self.width)
                    .frame(width: -offset).frame(maxHeight: .infinity)
                    .background(Palette.down)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apagar")
            }
            content
                .background(surface)
                .disabled(moving)
                .overlay {
                    if shown {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { open = nil } }
                    }
                }
                .offset(x: offset)
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                    moving = true
                    Self.recentlySwiped = true
                    if open != id, open != nil { withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { open = nil } }
                    drag = value.translation.width
                }
                .onEnded { value in
                    let final = (shown ? -Self.width : 0) + (abs(value.translation.width) > abs(value.translation.height) * 1.3 ? value.translation.width : 0)
                    let opens = final < -Self.width / 2
                    if opens, !shown { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        open = opens ? id : (open == id ? nil : open)
                        drag = 0
                    }
                    guard moving else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        moving = false
                        Self.recentlySwiped = false
                    }
                }
        )
        .accessibilityAction(named: Text("Apagar")) { onDelete() }
    }
}

extension View {
    func swipeToDelete(id: UUID, open: Binding<UUID?>, surface: Color = Palette.body, onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(id: id, open: open, surface: surface, onDelete: onDelete))
    }
}
