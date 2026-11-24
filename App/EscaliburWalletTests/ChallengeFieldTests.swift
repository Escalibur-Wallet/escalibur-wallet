import Testing
import UIKit
@testable import EscaliburWallet

/// O campo do trecho que o dono le na fonte: um caractere por vez, sem Colar (revisao de seguranca, 08/11/2026). Colar a area
/// de transferencia, que um programa no computador pode ter trocado, dava a resposta certa no nome inteiro de uma conta NEAR.
@MainActor
struct ChallengeFieldTests {
    private func coordinator(limit: Int) -> ChallengeTextField.Coordinator {
        ChallengeTextField.Coordinator(ChallengeTextField(text: .constant(""), isFocused: .constant(false), limit: limit, identifier: "teste"))
    }

    @Test func oneCharacterAtATime() {
        let field = ChallengeUITextField()
        field.text = "alice"
        let delegate = coordinator(limit: 64)
        let end = NSRange(location: 5, length: 0)
        #expect(delegate.textField(field, shouldChangeCharactersIn: end, replacementString: "."))
        // O nome inteiro colado, ou a sugestao do teclado, entram de uma vez.
        #expect(!delegate.textField(field, shouldChangeCharactersIn: NSRange(location: 0, length: 5), replacementString: "alice-near.tg"))
        #expect(!delegate.textField(field, shouldChangeCharactersIn: end, replacementString: ".tg"))
        #expect(!delegate.textField(field, shouldChangeCharactersIn: end, replacementString: " "))
        // Apagar sempre.
        #expect(delegate.textField(field, shouldChangeCharactersIn: NSRange(location: 4, length: 1), replacementString: ""))
    }

    @Test func stopsAtTheLimit() {
        let field = ChallengeUITextField()
        field.text = "aeda94"
        let delegate = coordinator(limit: 6)
        #expect(!delegate.textField(field, shouldChangeCharactersIn: NSRange(location: 6, length: 0), replacementString: "1"))
        #expect(delegate.textField(field, shouldChangeCharactersIn: NSRange(location: 5, length: 1), replacementString: "5"))
    }

    @Test func menuHasNoPaste() {
        let field = ChallengeUITextField()
        #expect(!field.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
        #expect(!field.canPerformAction(#selector(UIResponderStandardEditActions.pasteAndMatchStyle(_:)), withSender: nil))
        #expect(!field.canPerformAction(#selector(UIResponder.captureTextFromCamera(_:)), withSender: nil))
    }
}
