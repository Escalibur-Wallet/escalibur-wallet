import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import EscaliburNetwork
import SwiftUI

/// O que a carteira importada vai ser, mostrado antes de guardar: os primeiros
/// enderecos e a impressao digital.
///
/// Frase com uma palavra trocada que ainda fecha o checksum, ou 25a palavra diferente,
/// abrem outra carteira, valida e vazia, sem aviso nenhum. Quem ja usou a carteira
/// reconhece os enderecos; a impressao digital e a mesma que carteiras de hardware e
/// o Sparrow mostram.
struct ImportPreview: Sendable {
    let fingerprint: String
    let addresses: [(chain: Chain, address: String)]
    /// O endereco na Tron, so para conferir quem controla a conta (o golpe da "frase com
    /// saldo"); nao aparece na lista.
    let tronAddress: String?

    static let chains: [Chain] = [.bitcoin, .ethereum, .solana]

    /// Deriva fora da thread principal. O segredo nao e zerado aqui: quem chama
    /// ainda vai guarda-lo ou descarta-lo.
    static func make(_ secret: WalletSecret) async throws -> ImportPreview {
        try await Offload.run {
            let (accounts, fingerprint) = try AccountDeriver.derive(secret, chains: chains + [.tron])
            let addresses = chains.compactMap { chain in accounts.first { $0.chainID == chain.id }.map { (chain, $0.address) } }
            let tron = accounts.first { $0.chainID == Chain.tron.id }?.address
            return ImportPreview(fingerprint: fingerprint.hex.uppercased(), addresses: addresses, tronAddress: tron)
        }
    }
}

/// A conferencia antes de guardar uma carteira que veio de fora (auditoria 4, C7-05): a
/// frase digitada ou o envelope aberto pode ser de outra pessoa. No golpe da "frase com
/// saldo" (ou do falso suporte), o golpista entrega as palavras de uma carteira com USDT
/// que ele controla por outra chave, e quem deposita a taxa perde o deposito. A tela diz
/// isso com aceite, e na Tron confere na rede quem controla a conta.
struct ImportPreviewView: View {
    enum Source { case phrase, envelope }

    let preview: ImportPreview
    let hasPassphrase: Bool
    /// Importando com o interruptor da passphrase: estes sao os enderecos das palavras, e a passphrase vem depois.
    var passphraseNext = false
    var source: Source = .phrase
    let saving: Bool
    /// Guarda, dizendo se a conta da Tron tem outra chave no controle: a carteira grava a
    /// marca, e o Receber da Tron nela fica fechado.
    /// O que a previa viu: a Tron com outra chave, e a delegacao EVM com dois de acordo, que entra como marca ao gravar (rodada 4).
    let onSave: (_ tronForeign: Bool, _ evmForeign: (chain: Chain, control: ForeignControl)?) -> Void
    let onBack: () -> Void

    @Environment(AppSession.self) private var session
    @State private var accepted = false
    /// A conta da Tron com outra chave no controle: nil enquanto nao se sabe (sem rede,
    /// conta nova), e a conferencia nunca segura o Guardar.
    @State private var tronForeign = false
    /// A conta EVM com contrato instalado por delegacao (EIP-7702) numa das redes da previa: a versao do mesmo golpe na
    /// EVM depois do Pectra (auditoria 8, 14/11/2026). O aviso, e a marca ao gravar (rodada 4).
    @State private var evmForeign: (chain: Chain, control: ForeignControl)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Confira antes de guardar").typeStyle(.title).foregroundStyle(Palette.ink)
                Text(hasPassphrase
                     ? "Se esta carteira já recebeu antes, estes endereços são os que você conhece. Se não baterem, a frase ou a passphrase está diferente, e o que abriria aqui é outra carteira, vazia."
                     : passphraseNext
                     ? "Estes são os endereços das palavras sozinhas, sem a passphrase. Se você só usa a carteira com passphrase, eles podem nunca ter recebido nada. Esta importação guarda só a carteira com passphrase: você digita a passphrase na próxima tela."
                     : "Se esta carteira já recebeu antes, estes endereços são os que você conhece. Se não baterem, alguma palavra está diferente, e o que abriria aqui é outra carteira, vazia.")
                    .typeStyle(.body).foregroundStyle(Palette.inkSoft).padding(.top, Space.sm)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Space.md) {
                    ForEach(preview.addresses, id: \.chain.id) { item in
                        VStack(alignment: .leading, spacing: Space.xs) {
                            HStack(spacing: Space.xs) {
                                NetworkBadge(chain: item.chain, size: 20, ring: Palette.body)
                                Text(item.chain.name).typeStyle(.note).foregroundStyle(Palette.inkSoft)
                            }
                            AddressBlocks(address: item.address)
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Impressão digital da carteira").typeStyle(.note).foregroundStyle(Palette.inkSoft)
                        Text(verbatim: preview.fingerprint).typeStyle(.row).foregroundStyle(Palette.ink)
                        Text(passphraseNext ? "A desta frase sem a passphrase. Com a passphrase, a impressão digital é outra."
                             : "A mesma que carteiras de hardware mostram para esta frase.")
                            .typeStyle(.note).foregroundStyle(Palette.inkMuted)
                    }
                }
                .padding(.top, Space.lg)

                if tronForeign {
                    Banner(kind: .failure, title: String(localized: "Na Tron, esta conta é controlada por outra chave"),
                           message: String(localized: "É o golpe da frase com saldo: o que entrar nela, quem controla a outra chave leva. Não deposite nada nesta carteira."))
                        .padding(.top, Space.lg)
                        .accessibilityIdentifier("importar-tron-outra-chave")
                }
                if let evmForeign {
                    Banner(kind: .failure, title: evmForeign.chain.name, message: evmForeign.control.message)
                        .padding(.top, Space.lg)
                        .accessibilityIdentifier("importar-evm-delegacao")
                }

            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.md)
        }
        .safeAreaInset(edge: .bottom) {
            ActionFooter {
                // O aceite fica junto do Guardar, sempre a vista: no fim da lista, abaixo do
                // aviso da Tron, ele ficava atras do rodape.
                consent
                // Com a passphrase depois, nada e guardado aqui: o PIN e a tela da passphrase vem a seguir.
                PrimaryButton(title: passphraseNext ? String(localized: "Continuar") : String(localized: "Guardar esta carteira"),
                              enabled: accepted, loading: saving) { onSave(tronForeign, evmForeign) }
                TertiaryButton(title: String(localized: "Voltar e conferir"), action: onBack)
                    // Guardando (ou confirmando o PIN), voltar espera: a conferencia nao sai por baixo do PIN.
                    .disabled(saving)
            }
        }
        .background(Palette.void.ignoresSafeArea())
        // A rodada do dia da carteira escolhida para antes: a previa consulta a importada, e as duas nao saem juntas do mesmo IP
        // (rodada 4 da auditoria 8).
        // Numa tarefa so, com a pausa antes das duas leituras (rodada 5); com passphrase, nada e poupado.
        .task {
            // Comecada depois de a previa sumir (no mesmo quadro), nada: a marca da previa aberta ficava presa ate travar (rodada 7).
            guard !Task.isCancelled else { return }
            // Com a passphrase depois tambem: a rodada do dia fica segura ate a tela de importar fechar, e a base nao sai junto da
            // com passphrase que abre logo depois (rodada 8). As duas leituras daqui nao saem nesse caso.
            session.beginPreview(hidden: hasPassphrase || passphraseNext)
            async let tron: Void = checkTron()
            async let evm: Void = checkEVM()
            _ = await (tron, evm)
        }
        // Com a passphrase depois, a com passphrase vai abrir: a rodada da base nao volta agora (rodada 6).
        .onDisappear { if !passphraseNext { session.resumeControlChecks() } }
    }

    /// O aceite: quem tem as palavras (ou o envelope e a senha dele) tem a carteira.
    private var consent: some View {
        Button { accepted.toggle() } label: {
            HStack(alignment: .top, spacing: Space.sm) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accepted ? Palette.control : Palette.void)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(accepted ? Palette.inkSoft : Palette.edgeStrong, lineWidth: 1.5))
                    .overlay {
                        if accepted {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ink)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .padding(.top, 1)
                Text(source == .envelope
                     ? String(localized: "Entendo que quem me mandou este envelope e a senha dele controla esta carteira e pode levar o que entrar nela. Só deposito aqui se o envelope for meu.")
                     : String(localized: "Entendo que quem me deu estas palavras controla esta carteira e pode levar o que entrar nela. Só deposito aqui se as palavras forem só minhas."))
                    .typeStyle(.note).foregroundStyle(accepted ? Palette.ink : Palette.inkSoft)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Space.md)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.body)
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(accepted ? Palette.edgeStrong : Palette.edge, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(accepted ? "Marcado" : "Desmarcado")
        .accessibilityAddTraits(accepted ? .isSelected : [])
        .accessibilityIdentifier("importar-aceite")
        .sensoryFeedback(.selection, trigger: accepted)
    }

    /// As permissoes da conta na Tron, como docs/blockchain.md §2.6 promete para a
    /// importacao. Sem rede ou com a conta ainda nao ativada, nada a dizer: o envio na Tron
    /// confere de novo antes de qualquer saldo (`TronSendEngine`).
    /// Com a passphrase depois, nada: a carteira das palavras nao e guardada, e a Tron conferida e a da carteira com
    /// passphrase, quando ela abre. Consultar as duas juntas ligaria uma a outra para quem ve a rede (revisao, 08/11/2026).
    private func checkTron() async {
        // A Tron desligada nos Ajustes nao e consultada por nada (rodada 5 da auditoria 8).
        guard !passphraseNext, !session.metadata.settings.disabledChainIDs.contains(Chain.tron.id),
              let text = preview.tronAddress, let address = TronAddress(text) else { return }
        guard let control = try? await TronReader.shared.ownerControl(owner: address) else { return }
        tronForeign = control.isCompromised
    }

    /// A conta EVM nas redes da previa (`ForeignControlCheck.previewChains`), pela mesma regra da Tron: nada com a
    /// passphrase depois, e sem rede, nada a dizer.
    private func checkEVM() async {
        guard !passphraseNext, let text = preview.addresses.first(where: { $0.chain.family == .evm })?.address else { return }
        evmForeign = await ForeignControlCheck.previewDelegation(address: text, skipping: session.metadata.settings.disabledChainIDs)
    }
}
