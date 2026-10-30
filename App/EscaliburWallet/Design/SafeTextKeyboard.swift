import SwiftUI
import UIKit

/// O Safe Keyboard em todo campo de texto do app (pedido do dono, 17/10/2026): com ele
/// ligado em Seguranca (ou no Super Security), qualquer campo que abre o teclado abre o do
/// app, e nao o do iPhone. O das palavras (`WordKeyboardView`) continua nos campos das
/// palavras, que ja trazem o proprio; os outros ganham este, com letras, numeros, simbolos
/// e acentos, ou so os algarismos nos campos de valor.
///
/// **Como.** Quando um `UITextField` ou `UITextView` comeca a editar, o instalador poe este
/// teclado como `inputView` e recarrega: o iOS sobe ele no lugar do do sistema. Vale para
/// os campos do SwiftUI (que sao `UITextField` por baixo) sem mexer em cada tela. As teclas
/// escrevem pelo proprio campo (`UIKeyInput`): o delegate e o SwiftUI veem como digitacao
/// comum. O globo devolve o teclado do iPhone so naquele campo, enquanto ele existir.
@MainActor
final class SafeKeyboardInstaller {
    static let shared = SafeKeyboardInstaller()

    /// Lido a cada campo: o ajuste muda com o app aberto.
    var isOn: () -> Bool = { false }
    /// Com o Super Security ligado, o Safe Keyboard nao desliga: sem o globo (pedido do dono,
    /// 18/10/2026).
    var isLocked: () -> Bool = { false }
    /// Os campos em que o dono escolheu o teclado do iPhone pelo globo.
    private let optedOut = NSHashTable<UIView>.weakObjects()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        center.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { note in
            let field = note.object as? UITextField
            MainActor.assumeIsolated { self.install(field) }
        }
        center.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: .main) { note in
            let view = note.object as? UITextView
            MainActor.assumeIsolated { self.install(view) }
        }
    }

    private func install(_ field: (UIView & UITextInput)?) {
        guard let field, isOn(), !optedOut.contains(field) else { return }
        // O campo das palavras ja traz o teclado dele.
        if let textField = field as? UITextField, textField.inputView != nil { return }
        if let textView = field as? UITextView, textView.inputView != nil || !textView.isEditable { return }
        let type = (field as? UITextField)?.keyboardType ?? (field as? UITextView)?.keyboardType ?? .default
        let layout: SafeTextKeyboardModel.Layout
        switch type {
        case .decimalPad: layout = .decimal
        case .numberPad, .asciiCapableNumberPad: layout = .digits
        default: layout = .text
        }
        let model = SafeTextKeyboardModel(layout: layout, target: field)
        model.offersSystemKeyboard = !isLocked()
        model.systemKeyboard = { [weak self, weak field] in
            guard let self, let field else { return }
            self.optedOut.add(field)
            (field as? UITextField)?.inputView = nil
            (field as? UITextView)?.inputView = nil
            field.reloadInputViews()
        }
        let input = SafeTextKeyboardInputView(model: model)
        (field as? UITextField)?.inputView = input
        (field as? UITextView)?.inputView = input
        field.reloadInputViews()
    }
}

@MainActor
@Observable
final class SafeTextKeyboardModel {
    enum Layout { case text, decimal, digits }
    enum Page { case letters, numbers, symbols, accents }

    let layout: Layout
    var page: Page = .letters
    var shift = false
    @ObservationIgnored weak var target: (UIView & UITextInput)?
    @ObservationIgnored var systemKeyboard: () -> Void = {}
    /// O globo do teclado do iPhone; fora no Super Security.
    var offersSystemKeyboard = true

    init(layout: Layout, target: (UIView & UITextInput)?) {
        self.layout = layout
        self.target = target
    }

    func type(_ text: String) {
        if allows(text, deleting: false) { target?.insertText(text) }
        // Maiuscula vale para uma letra, como no do iPhone.
        if shift, page == .letters || page == .accents { shift = false }
    }

    func delete() {
        if allows("", deleting: true) { target?.deleteBackward() }
    }

    /// O delegate do campo decide, como com o teclado do iPhone: o `insertText` sozinho nao
    /// passa por ele, e o campo de senha (`SecureInputField`) escreve no buffer seguro ali
    /// e devolve `false`. Sem isto, as letras iam para o texto do campo e nao para o buffer.
    private func allows(_ text: String, deleting: Bool) -> Bool {
        guard let target, let selected = target.selectedTextRange else { return true }
        var start = target.offset(from: target.beginningOfDocument, to: selected.start)
        var length = target.offset(from: selected.start, to: selected.end)
        if deleting, length == 0 {
            guard start > 0 else { return false }
            start -= 1
            length = 1
        }
        let range = NSRange(location: start, length: length)
        if let field = target as? UITextField, let delegate = field.delegate {
            return delegate.textField?(field, shouldChangeCharactersIn: range, replacementString: text) ?? true
        }
        if let view = target as? UITextView, let delegate = view.delegate {
            return delegate.textView?(view, shouldChangeTextIn: range, replacementText: text) ?? true
        }
        return true
    }

    /// O "Ir": no campo de uma linha, o mesmo caminho da tecla do iPhone (o `onSubmit` do
    /// SwiftUI vem dele); no de varias linhas, a quebra de linha.
    func submit() {
        if let field = target as? UITextField {
            if field.delegate?.textFieldShouldReturn?(field) ?? true { field.sendActions(for: .editingDidEndOnExit) }
        } else {
            target?.insertText("\n")
        }
    }

    func dismiss() { target?.resignFirstResponder() }
}

struct SafeTextKeyboardView: View {
    let model: SafeTextKeyboardModel

    static let keyHeight: CGFloat = 44
    static let rowSpacing: CGFloat = 10
    static let height: CGFloat = keyHeight * 4 + rowSpacing * 3 + 8 + 6
    /// A barra do alto no teclado de texto: o nome do teclado e o "Pronto", na altura da barra
    /// de sugestoes do teclado das palavras. Sem ela, o teclado da passphrase parecia baixo e
    /// sem acabamento (pedido do dono, 18/10/2026). Nada de sugestao aqui: ela mostraria a
    /// senha.
    static let barHeight: CGFloat = 44

    static func height(for layout: SafeTextKeyboardModel.Layout) -> CGFloat {
        layout == .text ? height + barHeight : height
    }

    private static let letters: [[String]] = [Array("qwertyuiop").map(String.init), Array("asdfghjkl").map(String.init), Array("zxcvbnm").map(String.init)]
    private static let numbers: [[String]] = [Array("1234567890").map(String.init), ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""], [".", ",", "?", "!", "'"]]
    private static let symbols: [[String]] = [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"], [".", ",", "?", "!", "'"]]
    private static let accents: [[String]] = [["á", "à", "â", "ã", "ä", "é", "è", "ê", "ë", "í"], ["ì", "î", "ï", "ó", "ò", "ô", "õ", "ö", "ú"], ["ù", "û", "ü", "ç", "ñ", "ý", "ÿ"]]

    var body: some View {
        VStack(spacing: 0) {
            if model.layout == .text { bar }
            GeometryReader { geo in
                let spacing: CGFloat = 6
                let unit = (geo.size.width - 6 - spacing * 9) / 10
                Group {
                    switch model.layout {
                    case .text: textKeys(unit: unit, spacing: spacing)
                    case .decimal, .digits: numberPad(width: geo.size.width - 6, spacing: spacing)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
            .frame(height: Self.height)
        }
        .frame(height: Self.height(for: model.layout))
        .background(Palette.body)
    }

    private var bar: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
            Text("Safe Keyboard").typeStyle(.note)
            Spacer(minLength: 0)
            Button { model.dismiss() } label: {
                Text("Pronto").typeStyle(.action).foregroundStyle(Palette.ink)
                    .padding(.horizontal, Space.sm)
                    .frame(height: Self.barHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Fechar o teclado"))
            .accessibilityIdentifier("safe-pronto")
        }
        .foregroundStyle(Palette.inkMuted)
        .padding(.leading, Space.md)
        .padding(.trailing, Space.xs)
        .frame(height: Self.barHeight)
    }

    // MARK: Texto

    private var rows: [[String]] {
        switch model.page {
        case .letters: return Self.letters
        case .numbers: return Self.numbers
        case .symbols: return Self.symbols
        case .accents: return Self.accents
        }
    }

    private func textKeys(unit: CGFloat, spacing: CGFloat) -> some View {
        let rows = self.rows
        let upper = model.shift && (model.page == .letters || model.page == .accents)
        return VStack(spacing: Self.rowSpacing) {
            HStack(spacing: spacing) { ForEach(rows[0], id: \.self) { character($0, upper: upper, width: unit) } }
            HStack(spacing: spacing) { ForEach(rows[1], id: \.self) { character($0, upper: upper, width: unit) } }
            HStack(spacing: spacing) {
                switch model.page {
                case .letters, .accents:
                    key(width: unit * 1.4, label: String(localized: "Maiúscula"), identifier: "safe-maiuscula", selected: model.shift) {
                        model.shift.toggle()
                    } content: {
                        Image(systemName: model.shift ? "shift.fill" : "shift").font(.system(size: 18, weight: .medium))
                    }
                case .numbers:
                    key(width: unit * 1.4, label: String(localized: "Símbolos"), identifier: "safe-simbolos") { model.page = .symbols } content: {
                        Text(verbatim: "#+=").font(.system(size: 15, weight: .medium))
                    }
                case .symbols:
                    key(width: unit * 1.4, label: String(localized: "Números"), identifier: "safe-numeros") { model.page = .numbers } content: {
                        Text(verbatim: "123").font(.system(size: 15, weight: .medium))
                    }
                }
                Spacer(minLength: 0)
                ForEach(rows[2], id: \.self) { character($0, upper: upper, width: model.page == .letters || model.page == .accents ? unit : unit * 1.3) }
                Spacer(minLength: 0)
                key(width: unit * 1.4, label: String(localized: "Apagar"), identifier: "safe-apagar") { model.delete() } content: {
                    Image(systemName: "delete.left").font(.system(size: 18, weight: .medium))
                }
            }
            HStack(spacing: spacing) {
                key(width: unit * 1.5, label: model.page == .letters ? String(localized: "Números") : String(localized: "Letras"), identifier: "safe-pagina") {
                    model.page = model.page == .letters ? .numbers : .letters
                } content: {
                    Text(verbatim: model.page == .letters ? "123" : "ABC").font(.system(size: 15, weight: .medium))
                }
                key(width: unit * 1.2, label: String(localized: "Acentos"), identifier: "safe-acentos", selected: model.page == .accents) {
                    model.page = model.page == .accents ? .letters : .accents
                } content: {
                    Text(verbatim: "áé").font(.system(size: 15, weight: .medium))
                }
                key(width: nil, label: String(localized: "Espaço"), identifier: "safe-espaco") { model.type(" ") } content: {
                    // O nome do teclado foi para a barra do alto.
                    Text("espaço").typeStyle(.note).foregroundStyle(Palette.inkMuted)
                }
                if model.offersSystemKeyboard {
                    key(width: unit * 1.2, label: String(localized: "Usar o teclado do iPhone"), identifier: "safe-sistema") { model.systemKeyboard() } content: {
                        Image(systemName: "globe").font(.system(size: 17, weight: .medium))
                    }
                }
                key(width: unit * 1.7, label: String(localized: "Ir"), identifier: "safe-ir", strong: true) { model.submit() } content: {
                    Image(systemName: "return").font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    private func character(_ value: String, upper: Bool, width: CGFloat) -> some View {
        let shown = upper ? value.uppercased() : value
        return key(width: width, label: shown, identifier: "safe-\(value)") { model.type(shown) } content: {
            Text(verbatim: shown).font(.system(size: 22, weight: .regular))
        }
    }

    // MARK: Numeros

    private func numberPad(width: CGFloat, spacing: CGFloat) -> some View {
        let column = (width - spacing * 2) / 3
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
        return VStack(spacing: Self.rowSpacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { digit in
                        key(width: column, label: digit, identifier: "safe-\(digit)") { model.type(digit) } content: {
                            Text(verbatim: digit).font(.system(size: 24, weight: .regular))
                        }
                    }
                }
            }
            HStack(spacing: spacing) {
                if model.layout == .decimal {
                    key(width: column, label: Fmt.decimal, identifier: "safe-decimal") { model.type(Fmt.decimal) } content: {
                        Text(verbatim: Fmt.decimal).font(.system(size: 24, weight: .regular))
                    }
                } else {
                    key(width: column, label: String(localized: "Fechar o teclado"), identifier: "safe-fechar") { model.dismiss() } content: {
                        Image(systemName: "keyboard.chevron.compact.down").font(.system(size: 17, weight: .medium))
                    }
                }
                key(width: column, label: "0", identifier: "safe-0") { model.type("0") } content: {
                    Text(verbatim: "0").font(.system(size: 24, weight: .regular))
                }
                key(width: column, label: String(localized: "Apagar"), identifier: "safe-apagar") { model.delete() } content: {
                    Image(systemName: "delete.left").font(.system(size: 18, weight: .medium))
                }
            }
        }
    }

    // MARK: Tecla

    private func key(width: CGFloat?, label: String, identifier: String, strong: Bool = false, selected: Bool = false,
                     action: @escaping () -> Void, @ViewBuilder content: () -> some View) -> some View {
        Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
            content()
                .foregroundStyle(strong ? Palette.onLive : Palette.ink)
                .frame(width: width, height: Self.keyHeight)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .contentShape(Rectangle())
        }
        .buttonStyle(SafeKeyStyle(fill: strong ? Palette.live : (selected ? Palette.edgeStrong : Palette.control),
                                  pressedFill: strong ? Palette.livePress : Palette.edgeStrong))
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// A tecla apertada so muda de tom, sem o balao com a letra em cima.
private struct SafeKeyStyle: ButtonStyle {
    let fill: Color
    let pressedFill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(configuration.isPressed ? pressedFill : fill))
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// O teclado como `inputView`, na camada que sai em branco na captura (a tecla apertada diz
/// a letra), como o das palavras.
final class SafeTextKeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    private let host: UIHostingController<SafeTextKeyboardView>
    private let secure: SecureCanvas?

    var enableInputClicksWhenVisible: Bool { true }

    @MainActor
    init(model: SafeTextKeyboardModel) {
        host = UIHostingController(rootView: SafeTextKeyboardView(model: model))
        secure = SecureCanvas()
        let bottom = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.bottom ?? 0
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: SafeTextKeyboardView.height(for: model.layout) + bottom), inputViewStyle: .default)
        allowsSelfSizing = true
        backgroundColor = UIColor(Palette.body)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        if let canvas = secure?.view {
            canvas.translatesAutoresizingMaskIntoConstraints = false
            addSubview(canvas)
            NSLayoutConstraint.activate([
                canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
                canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
                canvas.topAnchor.constraint(equalTo: topAnchor),
                canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        (secure?.view ?? self).addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            host.view.heightAnchor.constraint(equalToConstant: SafeTextKeyboardView.height(for: model.layout)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
