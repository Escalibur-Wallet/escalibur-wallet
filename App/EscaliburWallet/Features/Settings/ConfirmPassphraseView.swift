import EscaliburChains
import EscaliburCore
import EscaliburKeys
import SwiftUI

/// Conferir a passphrase de uma carteira com passphrase (auditoria 4, C7-02). Antes, a
/// carteira nascia como "copia confirmada" herdada da carteira de base, e a passphrase
/// nunca era conferida: se o dono nao a tivesse anotado certo, o saldo ficava preso. Agora
/// ela so recebe depois de o dono digitar a passphrase de novo, longe da tela onde a
/// escolheu, de onde a anotou.
///
/// A passphrase nao fica no cofre (pedido do dono, 05/11/2026): a digitada confere pelo
/// fingerprint da raiz que a criacao gravou. Com `words` (as palavras que acabaram de aparecer
/// na revelacao), a seed sai delas; sem elas, o cofre abre a carteira, com o PIN. Nos dois
/// casos a tentativa conta na mesma espera das outras portas.
struct ConfirmPassphraseView: View {
    @Environment(AppSession.self) private var session
    @Environment(AuthCoordinator.self) private var auth
    let wallet: WalletMeta
    var words: PhraseDraft? = nil
    let onClose: () -> Void

    @State private var typed = SecureBytes(capacity: PassphraseLimit.fieldCapacity)
    @State private var typedLength = 0
    @State private var reveal = false
    @State private var message: String?
    @State private var working = false
    /// A cifra viva do que foi digitado, como nos outros campos de segredo (pedido do dono,
    /// 17/10/2026).
    @State private var cipher = LiveCipher()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // O selo das telas onde se digita um segredo (pedido do dono, 18/10/2026).
                CipherEmblem().frame(maxWidth: .infinity).padding(.bottom, Space.md)
                Text("Confira a passphrase").typeStyle(.title).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Digite a passphrase de \(wallet.name) a partir de onde você anotou. Diferença de maiúscula, acento ou espaço já abre outra carteira, e o que chegar nesta se perde.")
                    .typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.top, Space.sm)
                    .fixedSize(horizontal: false, vertical: true)
                PasswordBox(buffer: typed, length: $typedLength, placeholder: String(localized: "Passphrase"), focusOnAppear: true, reveal: $reveal,
                            onSubmit: { Task { await check() } }, glyphs: glyphs, wipesOnLeave: true)
                .padding(.top, Space.lg)
                .accessibilityIdentifier("conferir-passphrase")
                Text("Segure o dedo no campo para ver o que digitou.")
                    .typeStyle(.note).foregroundStyle(Palette.inkMuted).padding(.top, Space.xs)
                if let message { Banner(kind: .failure, title: message).padding(.top, Space.md) }
                Spacer()
                PrimaryButton(title: String(localized: "Conferir"), enabled: typedLength > 0, loading: working) {
                    Task { await check() }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xs)
            .background(Palette.void.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { close() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                    }
                    .accessibilityLabel("Fechar")
                }
            }
        }
        .interactiveDismissDisabled()
        .guardedAgainstCapture()
        .onChange(of: typedLength) { _, _ in cipher.seal(0, buffer: typed) }
        .onDisappear {
            typed.wipe()
            cipher.clearAll()
        }
    }

    private var glyphs: ((UInt64) -> String)? {
        guard typedLength > 0 else { return nil }
        let cipher = self.cipher, count = typedLength
        return { tick in cipher.glyphs(0, count: count, tick: tick) }
    }

    private func check() async {
        guard !working, typedLength > 0 else { return }
        message = nil
        working = true
        defer { working = false }
        // A conferencia fica com uma copia: o campo continua dono do buffer dele.
        let copy = SecureBytes(capacity: max(typed.count, 1))
        typed.withUnsafeBytes { copy.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
        defer { copy.wipe() }
        let id = wallet.id
        if PassphraseGate.unverified(session.metadata.wallets.first { $0.id == id } ?? wallet) {
            message = PassphraseGate.unverifiedMessage
            return
        }
        let fingerprint = wallet.fingerprint.flatMap(Hex.decode)
        let cardano = wallet.accounts.first { $0.chainID == Chain.cardano.id }?.publicKey
        // Toda conferencia e uma porta de chute: conta na mesma espera das outras (revisao de
        // seguranca de 16/10/2026).
        if let wait = PassphraseGate.shared.begin(session, wallet: id) {
            message = wait
            return
        }
        let result: PassphraseProof.Result
        do {
            if let words, case .valid(let language) = BIP39.validate(words.phrase) {
                let phrase = words.phrase
                result = try await Offload.run {
                    try PassphraseProof.check(phrase: phrase, language: language, typed: copy, fingerprint: fingerprint, cardanoPublicKey: cardano)
                }
            } else {
                // O PIN, nunca so o rosto: com o rosto do dono apresentado a forca, a conferencia
                // viraria um chute de passphrase por Face ID.
                guard let checked = try await auth.perform(session, reason: String(localized: "Conferir a passphrase de \(wallet.name)"), presence: .pin, { rk in
                    try PassphraseProof.check(walletID: id, rootKey: rk, vault: KeyServices.wallets, typed: copy,
                                              fingerprint: fingerprint, cardanoPublicKey: cardano)
                }) else {
                    PassphraseGate.shared.refund(session, wallet: id)
                    return
                }
                result = checked
            }
        } catch {
            // Nada foi conferido: a tentativa volta.
            PassphraseGate.shared.refund(session, wallet: id)
            message = AuthCoordinator.refusalMessage(error) ?? String(localized: "Não foi possível abrir a carteira agora.")
            return
        }
        if result == .mismatch { PassphraseGate.shared.failed(session, wallet: id, warn: false) } else { PassphraseGate.shared.passed(session, wallet: id) }
        // Gravada fora de NFKD por uma versao anterior: a copia nao traz a conta da Cardano de
        // volta (revisao do modo reforcado, N1).
        if result == .legacy {
            var marked = session.metadata.wallets.first { $0.id == id } ?? wallet
            marked.legacyCardanoPassphrase = true
            session.update(marked)
            message = HardenedEnableFlow.legacyPassphraseMessage(wallet.name)
            return
        }
        let matches = result == .match
        guard matches else {
            message = String(localized: "Não confere com a passphrase desta carteira. Confira o que você anotou, letra por letra.")
            return
        }
        var updated = session.metadata.wallets.first { $0.id == wallet.id } ?? wallet
        updated.passphraseConfirmedAt = .now
        session.update(updated)
        close()
    }

    private func close() {
        typed.wipe()
        onClose()
    }
}

/// O "Gravar agora" de uma carteira que ainda nao recebe: so a passphrase, quando as
/// palavras ja estao conferidas e ela nao; senao a revelacao com a conferencia das
/// palavras (e da passphrase logo depois, na mesma revelacao).
struct BackupNowFlow: View {
    let wallet: WalletMeta
    let onClose: () -> Void

    var body: some View {
        if wallet.wordsConfirmed, !wallet.passphraseConfirmed {
            ConfirmPassphraseView(wallet: wallet, onClose: onClose)
        } else {
            RevealFlow(wallet: wallet, purpose: .backup, onClose: onClose)
        }
    }
}
