import SwiftUI

/// A trava de alerta de seguranca: o app inteiro fica atras desta tela (pedido do dono,
/// 18/10/2026). Diz o que aconteceu, o que continua protegido e o que fazer; o deslizar entra
/// na carteira em emergencia, ate o app fechar. Sem `onEmergency`, o rodape mostra `footer`
/// no lugar do deslizar. O texto vem de quem trava (`UpdateGuard`, a versao nova da loja fora
/// da lista assinada).
struct UpdateAlarmView: View {
    struct Content: Equatable {
        let title: String
        let message: String
        let safeTitle: String
        let safeText: String
        let steps: [String]
        let note: String
        /// O rodape sem deslizar.
        var footer: String?
    }

    let content: Content
    let onEmergency: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CipherEmblem(size: 96, symbol: "exclamationmark.shield.fill", tint: Palette.down)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.xl)
                // O rotulo e o titulo no meio, em branco (pedido do dono, 18/10/2026).
                Text("Alerta de segurança")
                    .typeStyle(.note).fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.lg)
                Text(content.title)
                    .typeStyle(.title).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("alarme-versao")
                    .padding(.top, Space.xs)
                Text(content.message)
                    .typeStyle(.body).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.base)
                safe.padding(.top, Space.lg)
                Text("O que fazer agora")
                    .typeStyle(.heading).foregroundStyle(Palette.ink)
                    .padding(.top, Space.lg)
                VStack(alignment: .leading, spacing: Space.md) {
                    ForEach(Array(content.steps.enumerated()), id: \.offset) { index, text in
                        step(content.steps.count > 1 ? index + 1 : nil, text)
                    }
                }
                .padding(.top, Space.md)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            ActionFooter {
                if let onEmergency {
                    SlideToConfirm(title: String(localized: "Usar em emergência")) { onEmergency() }
                        .accessibilityIdentifier("alarme-emergencia")
                } else if let footer = content.footer {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "lock.fill").font(.system(size: 15, weight: .semibold))
                        Text(footer).typeStyle(.action)
                    }
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Palette.rail, in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("alarme-rodape")
                }
                Text(content.note)
                    .typeStyle(.note).foregroundStyle(Palette.inkMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .background(Palette.void.ignoresSafeArea())
    }

    private var safe: some View {
        HStack(alignment: .center, spacing: Space.md) {
            // Os pixels que cifram, os mesmos do deslizar: o que esta cifrado continua cifrado
            // (pedido do dono, 18/10/2026).
            CipherEmblem(size: 76, symbol: "lock.fill", tint: Palette.success)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(content.safeTitle).typeStyle(.row).foregroundStyle(Palette.ink)
                Text(content.safeText)
                    .typeStyle(.note).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.body, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func step(_ number: Int?, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            if let number {
                Text("\(number)")
                    .typeStyle(.note).fontWeight(.semibold).foregroundStyle(Palette.ink)
                    .frame(width: 24, height: 24)
                    .background(Palette.control, in: Circle())
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 7 }
            }
            Text(text)
                .typeStyle(.body).foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A versao esta desatualizada: a App Store ja tem uma versao mais nova, confirmada pela lista assinada da Escalibur (pedido do
/// dono, 05/11/2026). O botao abre a App Store; o deslizar, com os mesmos pixels da trava, deixa para depois, ate o app
/// fechar. Com a lista obrigando esta versao (`mandatory`), so o botao; depois de tentar atualizar sem conseguir
/// (`allowEmergency`), o "Usar em emergência" da trava. Uma versao fora da lista nunca chega aqui: ela e a trava de cima
/// (`UpdateAlarmView`).
struct UpdateRequiredView: View {
    let version: String
    let mandatory: Bool
    let allowEmergency: Bool
    /// A conferencia do "Atualizar agora" ficou sem resposta.
    let unchecked: Bool
    let onUpdate: () -> Void
    let onLater: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // A seta num circulo simples, sem o anel de pixels (pedido do dono, 05/11/2026).
                Circle().fill(Palette.control)
                    .frame(width: 72, height: 72)
                    .overlay {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.xl)
                    .accessibilityHidden(true)
                Text(mandatory ? String(localized: "Atualização obrigatória") : String(localized: "Atualização"))
                    .typeStyle(.note).fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.lg)
                Text("Esta versão está desatualizada")
                    .typeStyle(.title).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("versao-desatualizada")
                    .padding(.top, Space.xs)
                Text(mandatory
                     ? String(localized: "A versão \(version) da Escalibur já está na App Store, confirmada pela lista assinada da Escalibur. Esta atualização é obrigatória: atualize para continuar usando o app.")
                     : String(localized: "A versão \(version) da Escalibur já está na App Store, confirmada pela lista assinada da Escalibur. Atualize para continuar com as correções mais recentes."))
                    .typeStyle(.body).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.base)
                HStack(alignment: .center, spacing: Space.md) {
                    CipherEmblem(size: 76, symbol: "lock.fill", tint: Palette.success)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Seus fundos estão seguros").typeStyle(.row).foregroundStyle(Palette.ink)
                        Text("Atualizar não pede suas palavras e mantém suas carteiras como estão.")
                            .typeStyle(.note).foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.body, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .accessibilityElement(children: .combine)
                .padding(.top, Space.lg)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            ActionFooter {
                PrimaryButton(title: String(localized: "Atualizar agora")) { onUpdate() }
                    .accessibilityIdentifier("versao-atualizar")
                if unchecked {
                    Text("Não deu para conferir a App Store agora. Tente de novo em instantes.")
                        .typeStyle(.note).foregroundStyle(Palette.inkMuted)
                        .multilineTextAlignment(.center)
                }
                if !mandatory {
                    SlideToConfirm(title: String(localized: "Vou atualizar depois")) { onLater() }
                        .accessibilityIdentifier("versao-depois")
                    Text("A tela volta na próxima vez que você abrir o app.")
                        .typeStyle(.note).foregroundStyle(Palette.inkMuted)
                        .multilineTextAlignment(.center)
                } else if allowEmergency {
                    SlideToConfirm(title: String(localized: "Usar em emergência")) { onLater() }
                        .accessibilityIdentifier("versao-emergencia")
                    Text("Só se precisar mexer nos fundos agora.")
                        .typeStyle(.note).foregroundStyle(Palette.inkMuted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .background(Palette.void.ignoresSafeArea())
    }
}

/// A janela da versao desatualizada: abaixo da trava, para a trava, se houver, ficar por cima.
@MainActor
final class UpdateRequiredWindow {
    static let shared = UpdateRequiredWindow()
    private var window: UIWindow?
    private var showing: (version: String, mandatory: Bool, allowEmergency: Bool, unchecked: Bool)?
    /// A tela obrigatoria na frente: o Face ID automatico da tela de bloqueio nao abre por cima dela.
    var covering: Bool { showing?.mandatory == true }

    func show(version: String, mandatory: Bool, allowEmergency: Bool, unchecked: Bool, onUpdate: @escaping () -> Void, onLater: @escaping () -> Void) {
        guard window == nil || showing?.version != version || showing?.mandatory != mandatory || showing?.allowEmergency != allowEmergency
                || showing?.unchecked != unchecked,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let view = UpdateRequiredView(version: version, mandatory: mandatory, allowEmergency: allowEmergency, unchecked: unchecked,
                                      onUpdate: onUpdate, onLater: onLater)
            .preferredColorScheme(.dark)
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = UIColor(Palette.void)
        let window = self.window ?? UIWindow(windowScene: scene)
        // Abaixo do pedido de PIN e de voz (`OverlayWindow`, `.alert + 1`): um pedido aberto quando a tela chega termina ou
        // cancela por cima dela, em vez de ficar escondido sem resposta.
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 0.5)
        window.rootViewController = host
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        self.window = window
        showing = (version, mandatory, allowEmergency, unchecked)
    }

    func hide() {
        guard let window else { return }
        UIView.animate(withDuration: 0.3, animations: { window.alpha = 0 }, completion: { _ in
            window.isHidden = true
        })
        self.window = nil
        showing = nil
    }
}

/// A janela da trava: acima de tudo, ate do pedido de PIN (`OverlayWindow`), para cobrir o
/// app de onde quer que ele esteja, com envio ou folha aberta.
@MainActor
final class UpdateAlarmWindow {
    static let shared = UpdateAlarmWindow(level: .alert + 2)
    /// Alguma trava na tela agora.
    static var covering: Bool { !visible.isEmpty }
    private static var visible = Set<ObjectIdentifier>()
    private let level: UIWindow.Level
    private var window: UIWindow?
    private var showing: UpdateAlarmView.Content?

    init(level: UIWindow.Level) {
        self.level = level
    }

    func show(_ content: UpdateAlarmView.Content, onEmergency: (() -> Void)?) {
        // A mesma trava de novo (a conferencia repete enquanto ela esta na tela): nada muda,
        // e o deslizar nao volta ao comeco no meio do gesto.
        guard window == nil || showing != content,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let host = UIHostingController(rootView: UpdateAlarmView(content: content, onEmergency: onEmergency).preferredColorScheme(.dark))
        host.view.backgroundColor = UIColor(Palette.void)
        let window = self.window ?? UIWindow(windowScene: scene)
        window.windowLevel = level
        window.rootViewController = host
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        self.window = window
        showing = content
        Self.visible.insert(ObjectIdentifier(self))
    }

    func hide() {
        guard let window else { return }
        UIView.animate(withDuration: 0.3, animations: { window.alpha = 0 }, completion: { _ in
            window.isHidden = true
        })
        self.window = nil
        showing = nil
        Self.visible.remove(ObjectIdentifier(self))
    }
}
