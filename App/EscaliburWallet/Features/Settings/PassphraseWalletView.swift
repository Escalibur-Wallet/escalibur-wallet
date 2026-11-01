import EscaliburChains
import EscaliburCore
import EscaliburEngines
import SwiftUI

/// S3: criar a carteira da 25ª palavra a partir da carteira selecionada. A frase nao
/// aparece: o cofre abre, deriva a carteira nova e grava, com uma confirmacao so. Em tres
/// passos (pedido do dono, 16/10/2026): o que e, a checagem do aparelho e so entao os
/// campos da passphrase.
struct PassphraseWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    let base: WalletMeta

    @State private var checking = false
    @State private var entering = false
    @State private var howItWorks = false
    /// A carteira abriu: as duas telas de cima saem sem animacao e esta sai ao reaparecer.
    @State private var opened = false

    private var wordCount: Int {
        if case .phrase(let count) = base.kind { return count }
        return 12
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // A parede de pixels com a porta escondida: as palavras abrem a de sempre, e a
                // chave da passphrase revela a outra (pedido do dono, 17/10/2026).
                // O conteudo um pouco mais para cima (pedido do dono, 18/10/2026).
                PassphrasePixelScene(scene: .hiddenDoor, height: 190)
                    .padding(.top, -20)
                VStack(spacing: Space.xs) {
                    Text("Carteira com passphrase").typeStyle(.title).foregroundStyle(Palette.ink)
                    Text("Uma senha extra, escolhida por você. Junto com a senha de \(base.name), ela abre outra carteira, com outros endereços.")
                        .typeStyle(.body).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .padding(.top, Space.md)
                // O passo a passo com animacao (pedido do dono, 16/10/2026).
                Button { howItWorks = true } label: {
                    Label("Como funciona", systemImage: "play.circle").typeStyle(.label).foregroundStyle(Palette.ink)
                        .padding(.horizontal, Space.sm).frame(height: 34)
                        .background(Capsule(style: .continuous).fill(Palette.rail))
                }
                .buttonStyle(.plain)
                .padding(.top, Space.md)
                .accessibilityIdentifier("passphrase-como-funciona")

                VStack(alignment: .leading, spacing: Space.md) {
                    PassphrasePoint(icon: "eye.slash", text: String(localized: "Quem achar só as \(wordCount) palavras vê a carteira de sempre, não a da passphrase."))
                    PassphrasePoint(icon: "pencil.and.list.clipboard", text: String(localized: "Anote a passphrase longe das \(wordCount). Para abrir a carteira com passphrase em outro aparelho, você vai precisar das duas."))
                    // Na mesma cor dos outros pontos (pedido do dono, 16/10/2026).
                    PassphrasePoint(icon: "exclamationmark.triangle", text: String(localized: "Esquecer a passphrase é perder o acesso à carteira com passphrase. Ninguém recupera, nem a Escalibur."))
                }
                .padding(Space.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.body))
                .padding(.top, Space.lg)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.md)
        }
        .safeAreaInset(edge: .bottom) {
            ActionFooter {
                PrimaryButton(title: String(localized: "Continuar")) { checking = true }
            }
        }
        .background(Palette.void.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if opened { dismiss() } }
        .sheet(isPresented: $howItWorks) { PassphraseHowItWorks() }
        .navigationDestination(isPresented: $checking) {
            DeviceCheckView(slideTitle: String(localized: "Deslize para digitar a passphrase"),
                            consent: String(localized: "Estou ciente de que este iPhone falhou na verificação de integridade e de que digitar a passphrase aqui pode expor a carteira. Quero seguir mesmo assim.")) {
                entering = true
            }
            .navigationDestination(isPresented: $entering) {
                // Aberta a carteira, volta de uma vez para onde o caminho comecou.
                PassphraseEntryView(base: base) {
                    opened = true
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { checking = false }
                    // Aberta, a carteira nova ja e a selecionada: o app vai para a Carteira
                    // (pedido do dono, 17/10/2026), com os Ajustes de volta ao comeco.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        router.tab = .wallet
                    }
                }
            }
        }
    }
}

/// O ultimo passo: os dois campos da passphrase e o nome da carteira nova.
struct PassphraseEntryView: View {
    @Environment(AppSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(AuthCoordinator.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let base: WalletMeta
    let onDone: () -> Void

    @State private var passphrase = SecureBytes(capacity: PassphraseLimit.fieldCapacity)
    @State private var passphraseLength = 0
    /// Segurar o dedo numa das duas mostra as duas.
    @State private var revealPassphrase = false
    @State private var again = SecureBytes(capacity: PassphraseLimit.fieldCapacity)
    @State private var againLength = 0
    /// A dica embaixo da repeticao, que espera o campo nascer.
    @State private var hintShown = false
    @State private var name = ""
    @State private var message: String?
    @State private var working = false
    /// A cifra viva do que foi digitado, como na senha do envelope (pedido do dono,
    /// 16/10/2026): glifos que trocam no lugar dos pontos.
    @State private var cipher = LiveCipher()
    /// A carteira nova neste iPhone, enquanto o app procura movimento nela, e a escolhida antes.
    @State private var fresh: (wallet: WalletMeta, previous: UUID?)?

    var body: some View {
        if let fresh {
            PassphraseUsageView(wallet: fresh.wallet, previous: fresh.previous, onUse: onDone) {
                passphraseLength = 0
                againLength = 0
                cipher.clearAll()
                self.fresh = nil
            }
        } else {
            form
        }
    }

    private var form: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xs) {
                // O selo das telas onde se digita um segredo, como na senha da carteira (pedido
                // do dono, 18/10/2026).
                CipherEmblem().frame(maxWidth: .infinity).padding(.bottom, Space.xs)
                // O titulo e o texto no centro (pedido do dono, 22/10/2026).
                Text("Digite a passphrase").typeStyle(.title).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                Text("Escreva igual ao que você anotou. Diferença de maiúscula, acento ou espaço já abre outra carteira.")
                    .typeStyle(.body).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Space.md)
                Text("Passphrase").typeStyle(.note).foregroundStyle(Palette.inkSoft)
                PasswordBox(buffer: passphrase, length: $passphraseLength, placeholder: String(localized: "Passphrase"), reveal: $revealPassphrase,
                            glyphs: glyphs(0, count: passphraseLength))
                // A repeticao so aparece quando a primeira comeca a ser digitada (pedido do dono,
                // 16/10/2026). O campo inteiro nasce dos pixels (pedido do dono, 24/10/2026).
                if passphraseLength > 0 || againLength > 0 {
                    PasswordBox(buffer: again, length: $againLength, placeholder: String(localized: "Repita a passphrase"), reveal: $revealPassphrase,
                                onSubmit: { Task { await create() } }, glyphs: glyphs(1, count: againLength))
                        .id("repita")
                        .transition(repeatTransition)
                    if PassphraseLimit.overflows(passphraseLength) || PassphraseLimit.overflows(againLength) {
                        Text(PassphraseLimit.message).typeStyle(.note).foregroundStyle(Palette.down)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // A dica entra quando o campo termina de nascer, sem esmaecer.
                    Text("Segure o dedo num campo para conferir as duas.")
                        .typeStyle(.note).foregroundStyle(Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(hintShown ? 1 : 0)
                        .transition(.identity)
                }
                Text("Nome").typeStyle(.note).foregroundStyle(Palette.inkSoft).padding(.top, Space.sm)
                TextField("", text: $name)
                    .typeStyle(.row).foregroundStyle(Palette.ink)
                    .padding(.horizontal, Space.md).frame(height: Height.field)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.body)
                        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Palette.edge, lineWidth: 1)))
                if let message {
                    Banner(kind: .failure, title: message).padding(.top, Space.sm)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.md)
        }
        .scrollDismissesKeyboard(.interactively)
        // Com o teclado aberto, o botao de baixo cobria a repeticao: ao comecar a digitar a
        // passphrase, a tela sobe ate ela (visto no teste de interface).
        .onChange(of: passphraseLength) { old, new in
            if old == 0, new > 0 { withAnimation(Motion.fade) { proxy.scrollTo("repita", anchor: .center) } }
        }
        .onChange(of: passphraseLength > 0 || againLength > 0) { _, shown in
            guard shown else { hintShown = false; return }
            Task { @MainActor in
                if !reduceMotion { try? await Task.sleep(for: .seconds(PixelBirth.duration)) }
                hintShown = passphraseLength > 0 || againLength > 0
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: passphraseLength > 0 || againLength > 0)
        #if DEBUG
        // `-tela passphrase-repita`: uma letra entra sozinha na passphrase, e a repeticao aparece.
        .task {
            guard DebugDemo.screen == "passphrase-repita" else { return }
            try? await Task.sleep(for: .seconds(1.5))
            [UInt8(0x61)].withUnsafeBufferPointer { passphrase.append(contentsOf: $0) }
            passphraseLength = passphrase.count
        }
        #endif
        }
        .safeAreaInset(edge: .bottom) {
            ActionFooter {
                PrimaryButton(title: String(localized: "Abrir carteira"), enabled: passphraseLength > 0 && againLength > 0
                              && !PassphraseLimit.overflows(passphraseLength) && !PassphraseLimit.overflows(againLength), loading: working) {
                    Task { await create() }
                }
            }
        }
        .background(Palette.void.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .guardedAgainstCapture()
        .onAppear { if name.isEmpty { name = String(localized: "\(base.name) com passphrase") } }
        .onChange(of: passphraseLength) { _, _ in cipher.seal(0, buffer: passphrase) }
        .onChange(of: againLength) { _, _ in cipher.seal(1, buffer: again) }
        .onDisappear {
            passphrase.wipe()
            again.wipe()
            cipher.clearAll()
        }
    }

    /// A repeticao nasce dos pixels; com Reduzir Movimento, so aparece.
    private var repeatTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: PixelBirth(progress: 1), identity: PixelBirth(progress: 0))
                .animation(.linear(duration: PixelBirth.duration)),
            removal: .opacity
        )
    }

    private func glyphs(_ slot: Int, count: Int) -> ((UInt64) -> String)? {
        guard count > 0 else { return nil }
        let cipher = self.cipher
        return { tick in cipher.glyphs(slot, count: count, tick: tick) }
    }

    private func create() async {
        guard !working, passphraseLength > 0 else { return }
        message = nil
        guard Hash.constantTimeEqual(passphrase, again) else {
            message = String(localized: "As duas versões da passphrase não conferem.")
            return
        }
        guard PassphraseLimit.fits(passphrase) else {
            message = PassphraseLimit.message
            return
        }
        guard PassphraseWalletView.isWritable(passphrase) else {
            message = String(localized: "A passphrase tem um caractere invisível ou um espaço diferente do espaço comum. Escreva de novo, só com letras, números, símbolos e espaço comum: é o que dá para anotar no papel.")
            return
        }
        // Criar e uma porta de chute: a passphrase certa reabre a carteira que ja existe, e o
        // app diz isso. Toda criacao conta (revisao de seguranca de 16/10/2026), numa espera
        // mais curta que zera depois de um dia sem tentar: e por aqui que o dono que esqueceu
        // a passphrase tenta lembrar (pedido do dono, 25/10/2026).
        if let wait = PassphraseGate.shared.begin(session, wallet: base.id, creation: true) {
            message = wait
            return
        }
        working = true
        defer { working = false }
        // O cofre fica com uma copia: os campos continuam donos dos seus buffers.
        let copy = SecureBytes(capacity: passphrase.count)
        passphrase.withUnsafeBytes { copy.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        defer { copy.wipe() }
        let title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let walletName = title.isEmpty ? String(localized: "\(base.name) com passphrase") : title
        let before = Set(session.metadata.wallets.map(\.id))
        let previous = session.metadata.selectedWalletID
        do {
            guard let opened = try await auth.retrying(reason: String(localized: "Abrir a carteira com passphrase"), { credential in
                try await session.addPassphraseWallet(base: base, passphrase: copy, name: walletName, credential: credential)
            }) else {
                PassphraseGate.shared.refund(session, wallet: base.id, creation: true)
                return
            }
            // Conta na espera, sem o aviso de passphrase errada: aqui nada errou.
            PassphraseGate.shared.failed(session, wallet: base.id, warn: false, creation: true)
            passphrase.wipe()
            again.wipe()
            // A mesma frase com a mesma passphrase e a mesma carteira: ela ja estava aqui.
            if before.contains(opened.id) {
                toasts.show(String(localized: "Esta carteira já está aberta, como \(opened.name). Ela passa a ser a carteira em uso."))
                onDone()
                return
            }
            // Nova neste iPhone: antes de abrir, o app procura movimento nela (pedido do dono, 25/10/2026).
            withAnimation(Motion.fade) { fresh = (opened, previous) }
        } catch let error as WalletError {
            // Nada foi criado nem reaberto: a tentativa volta.
            PassphraseGate.shared.refund(session, wallet: base.id, creation: true)
            message = error.errorDescription
        } catch {
            PassphraseGate.shared.refund(session, wallet: base.id, creation: true)
            message = AuthCoordinator.refusalMessage(error) ?? String(localized: "Não foi possível criar a carteira agora.")
        }
    }
}

/// Depois de abrir uma carteira com passphrase nova neste iPhone: procura movimento nela, rede por
/// rede. Toda passphrase abre alguma carteira, e quem tentava lembrar a sua so via que tinha errado
/// uma letra pelo saldo zerado (pedido do dono, 25/10/2026). Com movimento, abre a carteira. Sem
/// nenhum, diz isso e deixa tentar outra passphrase, sem guardar a carteira vazia.
struct PassphraseUsageView: View {
    @Environment(AppSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    let wallet: WalletMeta
    let previous: UUID?
    let onUse: () -> Void
    let onRetry: () -> Void

    private enum Phase: Equatable { case checking, never, incomplete(String) }
    @State private var phase = Phase.checking
    @State private var round = 0
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.lg)
            UsageSearchArt(settled: phase != .checking)
            VStack(spacing: Space.sm) {
                Text(title).typeStyle(.title).foregroundStyle(Palette.ink)
                Text(detail).typeStyle(.body).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.top, Space.md)
            .animation(Motion.fade, value: phase)
            if let message {
                Banner(kind: .failure, title: message).padding(.top, Space.md)
            }
            Spacer(minLength: Space.lg)
            buttons
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.xs)
        .background(Palette.void.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Daqui so se sai decidindo: usar a carteira ou tentar outra passphrase.
        .navigationBarBackButtonHidden(true)
        .task(id: round) { await check() }
    }

    private var title: String {
        switch phase {
        case .checking: String(localized: "Procurando movimento")
        case .never: String(localized: "Esta carteira ainda não foi usada")
        case .incomplete: String(localized: "Nenhuma transferência até agora")
        }
    }

    private var detail: String {
        switch phase {
        case .checking:
            String(localized: "Conferindo as redes desta carteira, uma a uma. Leva alguns segundos.")
        case .never:
            String(localized: "Nas redes que a Escalibur lê, ela nunca recebeu nem enviou nada. Tem certeza de que a passphrase está certa? Maiúsculas, acentos e espaços contam. Se é uma carteira nova, pode usar. Outros apps podem guardar saldo em caminhos que a Escalibur não lê, como o Taproot do Bitcoin.")
        case .incomplete(let names):
            String(localized: "Nas redes que responderam, esta carteira nunca teve movimento. Não responderam agora: \(names).")
        }
    }

    @ViewBuilder private var buttons: some View {
        switch phase {
        case .checking:
            TertiaryButton(title: String(localized: "Abrir sem esperar")) { onUse() }
                .frame(maxWidth: .infinity)
        case .never:
            // O botao principal nao empurra para descartar: a busca nao le todo caminho que outro
            // app usa (revisao de blockchain de 26/10/2026).
            PrimaryButton(title: String(localized: "Usar esta carteira")) { onUse() }
            TertiaryButton(title: String(localized: "Tentar outra passphrase")) { retry() }
                .frame(maxWidth: .infinity).padding(.top, Space.xs)
        case .incomplete:
            PrimaryButton(title: String(localized: "Procurar de novo")) { round += 1 }
            TertiaryButton(title: String(localized: "Tentar outra passphrase")) { retry() }
                .frame(maxWidth: .infinity).padding(.top, Space.xs)
            TertiaryButton(title: String(localized: "Usar esta carteira")) { onUse() }
                .frame(maxWidth: .infinity)
        }
    }

    private func check() async {
        message = nil
        withAnimation(Motion.fade) { phase = .checking }
        let outcome = await UsageCheck.run(wallet.accounts)
        guard !Task.isCancelled else { return }
        switch outcome {
        case .used:
            toasts.show(String(localized: "Esta carteira já teve movimento. Ela passa a ser a carteira em uso."))
            onUse()
        case .never:
            withAnimation(Motion.fade) { phase = .never }
        case .incomplete(let failed):
            let names = failed.compactMap { Chain.find($0)?.name }
            withAnimation(Motion.fade) { phase = .incomplete(ListFormatter.localizedString(byJoining: names)) }
        }
    }

    /// A carteira vazia sai, e a de antes volta a ser a escolhida.
    private func retry() {
        do {
            try session.discardFreshPassphraseWallet(wallet.id, restoring: previous)
            onRetry()
        } catch {
            message = (error as? LocalizedError)?.errorDescription
        }
    }
}

/// Tres cartoes de rede, no desenho da Atividade vazia: entram um a um com o status girando
/// enquanto o app procura movimento; sem nenhum, cada status assenta num traco, um depois do
/// outro. Com Reduzir Movimento, aparecem parados.
struct UsageSearchArt: View {
    let settled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var settledAt: Date?

    private static let chains: [Chain] = [.bitcoin, .ethereum, .solana]
    private static let widths: [CGFloat] = [0.62, 0.48, 0.7]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let now = timeline.date
            VStack(spacing: Space.xs) {
                ForEach(Self.chains.indices, id: \.self) { index in
                    card(index, now: now)
                }
            }
            .frame(width: 290)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 220)
        .accessibilityHidden(true)
        .onAppear { if settled { settledAt = .distantPast } }
        .onChange(of: settled) { _, done in settledAt = done ? .now : nil }
    }

    private func card(_ index: Int, now: Date) -> some View {
        let clamp = ActivityEmptyArt.clamp
        let appear = reduceMotion ? 1 : clamp((now.timeIntervalSince(start) - 0.15 - Double(index) * 0.3) / 0.4)
        let settle: Double = settledAt.map { reduceMotion ? 1 : clamp((now.timeIntervalSince($0) - Double(index) * 0.25) / 0.3) } ?? 0
        let spin = now.timeIntervalSinceReferenceDate
        return HStack(spacing: Space.sm) {
            NetworkBadge(chain: Self.chains[index], size: 40, ring: Palette.body)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(Palette.edgeStrong).frame(width: 150 * Self.widths[index], height: 9)
                Capsule().fill(Palette.control).frame(width: 90 * Self.widths[index], height: 7)
            }
            .opacity(1 - settle * 0.4)
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Palette.inkMuted, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(reduceMotion ? 0 : spin * 360))
                    .opacity(1 - settle)
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Palette.edgeStrong, lineWidth: 1.5))
                    .scaleEffect(BackupFirstArt.easeOutBack(settle))
            }
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, Space.sm)
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.body))
        .opacity(appear)
        .offset(y: (1 - appear) * 16)
    }
}

extension PassphraseWalletView {
    /// A passphrase cabe no papel? Caractere de controle, de formato (largura zero,
    /// bidirecional), separador de linha, uso privado ou um espaco que nao e o comum nao
    /// aparecem, ou aparecem iguais a outros, e quem anota perde a carteira (revisao da
    /// auditoria 4, C7-02). Lido escalar por escalar direto do buffer, sem virar String.
    static func isWritable(_ secret: SecureBytes) -> Bool {
        secret.withUnsafeBytes { raw in
            var iterator = raw.makeIterator()
            var decoder = Unicode.UTF8()
            while true {
                switch decoder.decode(&iterator) {
                case .scalarValue(let scalar):
                    switch scalar.properties.generalCategory {
                    case .format, .control, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
                        return false
                    case .spaceSeparator where scalar != " ":
                        return false
                    default:
                        continue
                    }
                case .emptyInput: return true
                case .error: return false
                }
            }
        }
    }
}

/// Um ponto da explicacao: icone do assunto e uma frase.
private struct PassphrasePoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Palette.control))
            Text(text).typeStyle(.body).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
        }
    }
}
