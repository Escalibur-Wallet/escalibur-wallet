import EscaliburChains
import EscaliburNetwork
import SwiftUI

/// S6: enderecos salvos. Guarda nome, endereco, rede e a tag ou o memo junto, para o
/// envio seguinte preencher os dois de uma vez.
struct ContactsView: View {
    @Environment(AppSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var adding = false
    @State private var removing: Contact?

    private var contacts: [Contact] {
        session.metadata.contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            if contacts.isEmpty {
                empty
                    .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length * 0.86 }
            } else {
                VStack(spacing: Space.xs) {
                    ForEach(contacts) { contact in card(contact) }
                    Text("Endereço salvo vira atalho no envio e entra na conferência de endereço parecido. Salvar pede \(KeyServices.biometryName) ou PIN.")
                        .typeStyle(.note).foregroundStyle(Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.sm)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.md)
            }
        }
        .safeAreaInset(edge: .bottom) {
            ActionFooter { PrimaryButton(title: String(localized: "Salvar um endereço")) { adding = true } }
        }
        .background(Palette.void.ignoresSafeArea())
        .navigationTitle("Endereços salvos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { AddContactSheet() }
        .whiteAlert("Apagar \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Apagar", role: .destructive) {
                if let removing {
                    session.metadata.contacts.removeAll { $0.id == removing.id }
                    try? session.persist()
                }
                removing = nil
            }
            Button("Cancelar", role: .cancel) { removing = nil }
        } message: {
            Text("O endereço sai da lista. Nada muda na rede.")
        }
    }

    private var empty: some View {
        VStack(spacing: Space.sm) {
            SavedAddressesIllustration()
                .padding(.bottom, Space.md)
            Text("Nenhum endereço salvo").typeStyle(.title).foregroundStyle(Palette.ink).padding(.top, Space.xs)
            Text("Salve os endereços para onde você envia sempre, com a tag de destino junto quando houver. No envio, é só escolher.")
                .typeStyle(.body).foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Space.gutter)
        .frame(maxWidth: .infinity)
    }

    private func card(_ contact: Contact) -> some View {
        let chain = Chain.find(contact.chainID)
        return HStack(spacing: Space.sm) {
            if let chain { NetworkBadge(chain: chain, size: 36, ring: Palette.body) }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: contact.name).typeStyle(.row).foregroundStyle(Palette.ink).lineLimit(1)
                Text(verbatim: (chain?.name ?? contact.chainID) + (contact.tag.map { " · tag \($0)" } ?? ""))
                    .typeStyle(.note).foregroundStyle(Palette.inkSoft).lineLimit(1)
                Text(verbatim: Fmt.address(contact.address, chain: chain, head: 8, tail: 6))
                    .typeStyle(.monoSmall).foregroundStyle(Palette.inkMuted).lineLimit(1)
            }
            Spacer(minLength: Space.xs)
            Menu {
                // Nunca o endereco de uma conta deste iPhone com outra chave no controle (revisao de seguranca de 15/11/2026).
                if chain.map({ session.markedOwner(of: contact.address, on: $0) == nil }) ?? true {
                    Button {
                        Pasteboard.copyAddress(contact.address)
                        toasts.show(String(localized: "Endereço copiado."))
                    } label: { Label("Copiar endereço", systemImage: "doc.on.doc") }
                }
                Button(role: .destructive) { removing = contact } label: { Label("Apagar", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: Height.touch, height: Height.touch)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Opções de \(contact.name)")
        }
        .padding(.leading, Space.md)
        .padding(.vertical, Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.body))
    }
}

struct AddContactSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(AuthCoordinator.self) private var auth
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var tag = ""
    @State private var tagNotice: String?
    @State private var chain: Chain = .bitcoin
    @State private var scanning = false
    /// O trecho do endereco digitado pelo dono olhando a fonte (auditoria 4, C7-07).
    @State private var check = ""
    /// Nome da NEAR: o texto cujo desafio ja nasceu, no toque do Salvar ou na entrada inteira, como no Continuar do envio
    /// (revisao de seguranca, 09/11/2026).
    @State private var nearArmedFor: String?
    @State private var wholeNameMiss = false
    @State private var qrProblem: String?
    /// A rede que o QR lido disse: trocar a rede depois nao leva o endereco junto, nem a
    /// sugestao de outra rede aparece para ele (revisao dos baixos, B1).
    @State private var linkReading: PaymentURI.Reading?
    /// Contato G com um memo que e numero e bate com outra conta conhecida (a mesma conta,
    /// outro ID): aparece ao tocar em Salvar, e o dono digita o memo lido na fonte (segunda
    /// revisao do B-6). Ao vivo, ele esconderia o campo do memo no primeiro algarismo.
    @State private var memoConflict: AddressPoisoning.SameAccount?
    @State private var memoCheck = ""
    @State private var memoFocused = false

    private var trimmed: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validation: Result<Address.Destination, Address.Problem> { Address.validate(trimmed, for: chain) }
    private var isValid: Bool { (try? validation.get()) != nil }
    /// O endereco colado parece de outra rede: o app sugere, nao troca sozinho.
    private var suggestion: Chain? {
        guard linkReading?.chainID == nil, !trimmed.isEmpty, !isValid, let guess = Address.guessChain(trimmed), guess.id != chain.id,
              case .success = Address.validate(trimmed, for: guess) else { return nil }
        return guess
    }

    /// Um endereco salvo vira de confianca, e antes ele nascia sem conferencia nenhuma: um
    /// programa no computador trocava o endereco no Universal Clipboard na hora de salvar,
    /// e o contato envenenado passava a ser o "conhecido" (auditoria 4, C7-07). Agora ele e
    /// comparado com tudo que o dono ja usou nesta rede, e o dono digita um trecho do meio
    /// olhando a fonte.
    private var destination: Address.Destination? { try? validation.get() }

    /// Os ultimos enderecos para onde esta carteira enviou, os mais recentes primeiro e fora
    /// os ja salvos (pedido do dono, 17/10/2026): da Atividade, com a data, e dos enviados
    /// guardados, sem data. Tocar preenche a rede e o endereco; a conferencia do meio continua.
    private var recentSent: [(chain: Chain, address: String)] {
        let saved = Set(session.metadata.contacts.map { "\($0.chainID)|\($0.address.lowercased())" })
        var seen = Set<String>()
        var out: [(chain: Chain, address: String)] = []
        func add(_ chainID: String, _ address: String) {
            let key = "\(chainID)|\(address.lowercased())"
            guard !saved.contains(key), seen.insert(key).inserted, let chain = Chain.find(chainID) else { return }
            out.append((chain, address))
        }
        // So o historico da carteira selecionada, e nunca o de uma de observacao: os envios de quem e observado nao sao
        // do dono (como no Android, que usa so os enviados guardados; revisao de seguranca de 06/11/2026).
        if let selected = session.selectedWallet, !selected.isWatchOnly, ActivityFeed.shared.shownWalletID == selected.id {
            for entry in ActivityFeed.shared.entries.sorted(by: { $0.date > $1.date }) where entry.direction == .sent && !entry.suspicious {
                if let to = entry.counterparty { add(entry.chainID, to) }
            }
        }
        for (chainID, list) in session.metadata.sentTo.sorted(by: { $0.key < $1.key }) {
            for address in list.reversed() { add(chainID, address) }
        }
        return Array(out.prefix(6))
    }

    private var known: [String] {
        let sent = session.metadata.sentTo[chain.id] ?? []
        let contacts = session.metadata.contacts.filter { $0.chainID == chain.id }.map(\.address)
        let wallets = session.metadata.wallets.filter { !$0.isWatchOnly }.compactMap { $0.account(chain)?.address }
        return sent + contacts + wallets
    }

    private var lookalike: String? {
        destination.flatMap { AddressPoisoning.lookalike($0.address, among: known, chain: chain) }
    }

    /// Um M da mesma conta de um conhecido, com outro ID: salvo, ele virava conhecido para
    /// sempre, e o desafio do meio nao pegava a troca, porque o meio de um M e a chave
    /// (revisao do B-6). O mesmo aviso do envio; o parecido, se houver, vem antes.
    private var otherID: AddressPoisoning.SameAccount? {
        guard lookalike == nil, let destination else { return nil }
        return AddressPoisoning.sameAccountOtherID(destination.address, among: known,
                                                   tagged: SendStages.taggedContacts(chain, session: session), chain: chain)
    }

    /// O memo do contato contra os conhecidos: so de um G, com memo que e numero, e o par
    /// (conta, memo) com a conta de um conhecido e outro ID.
    private var memoOtherID: AddressPoisoning.SameAccount? {
        guard lookalike == nil, otherID == nil, let destination, chain.family == .stellar, !tag.isEmpty,
              StellarMuxedAccount(address: destination.address)?.isMuxed == false else { return nil }
        return AddressPoisoning.sameAccountOtherID(destination.address, tag: tag, among: known,
                                                   tagged: SendStages.taggedContacts(chain, session: session), chain: chain)
    }

    private var memoConfirmed: Bool {
        guard memoConflict != nil else { return true }
        guard let id = UInt64(tag.trimmingCharacters(in: .whitespaces)) else { return false }
        return AddressPoisoning.idConfirmed(memoCheck, id: id)
    }

    /// Com um desafio na tela, o campo do endereco some: a resposta (o trecho escondido, o
    /// fim do ID) se leria nele (segunda revisao dos enderecos parecidos).
    private var challengeOnScreen: Bool { destination != nil && (otherID != nil || segment != nil) }

    /// O trecho que o dono digita: onde difere do parecido, ou um trecho escondido do
    /// endereco como foi colado (a forma que esta na fonte, nao a normalizada): o meio, ou
    /// o fim do ID num M.
    private var segment: AddressPoisoning.Segment? {
        guard let destination, !nearPending else { return nil }
        if let lookalike { return AddressPoisoning.differingSegment(destination.address, from: lookalike, chain: chain) }
        return AddressPoisoning.blindSegment(trimmed, chain: chain)
    }

    /// Onde o trecho e lido: o endereco normalizado quando ha parecido (os dois lado a lado),
    /// o colado quando nao ha.
    private var checkedText: String { lookalike == nil ? trimmed : (destination?.address ?? trimmed) }

    /// Nome da NEAR valido no campo, com o desafio ainda por nascer: digitando, cada comeco ja e conta valida, e o desafio nascia
    /// no segundo caractere. O Salvar o faz nascer.
    private var nearPending: Bool {
        destination != nil && AddressPoisoning.wholeNEARName(trimmed, chain: chain) != nil && nearArmedFor != trimmed
    }

    /// O nome da NEAR que entrou inteiro na rede errada (a sugestao da NEAR na tela): o campo fica escondido ate a troca, como com
    /// o desafio na tela. A vista, o dono lia o nome trocado pelo tempo que quisesse e o digitava de memoria (revisao de
    /// seguranca, 09/11/2026).
    private var wholeEntryHidden: Bool {
        // Tambem o endereco que vale noutra rede, com ou sem sugestao (a Sui, a Aptos, a implicita da NEAR): a rede do contato e
        // livre, e depois da troca o desafio pede um trecho que estava a vista.
        !trimmed.isEmpty && nearArmedFor == trimmed && destination == nil
            && (suggestion != nil || AddressPoisoning.looksLikeNEARName(trimmed) || AddressPoisoning.validElsewhere(trimmed, than: chain))
    }

    /// O desafio e o nome inteiro: conferido no toque do Salvar, e nao ao vivo.
    private var wholeNameOnScreen: Bool { segment.map { AddressPoisoning.coversAll($0, of: checkedText) } ?? false }

    private var checked: Bool {
        guard let destination, !nearPending else { return false }
        if otherID != nil { return AddressPoisoning.muxedIDConfirmed(check, address: destination.address) }
        guard let segment else { return lookalike == nil }
        return AddressPoisoning.answers(check, segment: segment, of: checkedText, chain: chain)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if address.isEmpty, !recentSent.isEmpty {
                        labeled(String(localized: "Enviados recentemente")) {
                            VStack(spacing: 0) {
                                ForEach(Array(recentSent.enumerated()), id: \.offset) { _, item in
                                    Button {
                                        chain = item.chain
                                        armNEAR(item.address, chain: item.chain)
                                        address = item.address
                                    } label: {
                                        HStack(spacing: Space.sm) {
                                            NetworkBadge(chain: item.chain, size: 28, ring: Palette.rail)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(verbatim: KnownExchanges.name(for: item.address) ?? item.chain.name)
                                                    .typeStyle(.note).foregroundStyle(Palette.inkSoft)
                                                Text(verbatim: Fmt.address(item.address, chain: item.chain))
                                                    .font(TypeStyle.mono.font).foregroundStyle(Palette.ink).lineLimit(1)
                                            }
                                            Spacer(minLength: Space.xs)
                                            Image(systemName: "plus.circle").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                                        }
                                        .padding(.horizontal, Space.md).frame(minHeight: Height.rowCompact)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(RowStyle())
                                    .accessibilityIdentifier("contato-recente")
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.rail))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        }
                    }
                    labeled(String(localized: "Nome")) {
                        TextField("", text: $name, prompt: Text("Ex.: Minha conta na corretora").foregroundColor(Palette.inkDead))
                            .typeStyle(.row).foregroundStyle(Palette.ink)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, Space.md).frame(height: Height.field)
                            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.rail))
                    }
                    labeled(String(localized: "Rede")) {
                        HStack {
                            NetworkMenu(chains: Chain.all, selected: chain) { chain = $0 }
                            Spacer()
                        }
                    }
                    labeled(String(localized: "Endereço")) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            if challengeOnScreen || wholeEntryHidden {
                                HiddenAddressField(fill: Palette.rail, buttonFill: Palette.control, identifier: "contato-editar-endereco") {
                                    nearArmedFor = nil
                                    address = ""
                                    tag = ""
                                }
                            } else {
                                HStack(spacing: Space.xs) {
                                    TextField("", text: $address, prompt: Text("Cole ou escaneie").foregroundColor(Palette.inkDead), axis: .vertical)
                                        .font(TypeStyle.mono.font).foregroundStyle(Palette.ink)
                                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                                        .lineLimit(1...3)
                                    AppPasteButton { pasted in
                                        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                                        // A mesma regra do Android para a area de transferencia.
                                        if PrivateKeyGuard.clipboardHasSecret(text, on: chain) { Pasteboard.clearSecret() }
                                        if let message = PhraseGuard.secretMessage(text, on: chain) {
                                            nearArmedFor = nil
                                            linkReading = nil
                                            address = ""
                                            qrProblem = message
                                        } else {
                                            armNEAR(text, chain: chain)
                                            address = text
                                        }
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonBorderShape(.circle)
                                    .tint(Palette.control)
                                    Button { scanning = true } label: {
                                        Image(systemName: "qrcode.viewfinder").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                                            .frame(width: 36, height: 36).background(Circle().fill(Palette.control))
                                    }
                                    .accessibilityLabel("Escanear QR")
                                }
                                .padding(.leading, Space.md).padding(.trailing, Space.xs).padding(.vertical, Space.xs)
                                .frame(minHeight: Height.field)
                                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.rail)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                        .stroke(isValid ? Palette.up.opacity(0.6) : Color.clear, lineWidth: 1)))
                            }
                            if let suggestion {
                                Button { chain = suggestion } label: {
                                    HStack(spacing: Space.xs) {
                                        NetworkBadge(chain: suggestion, size: 18, ring: Palette.body)
                                        Text("Parece um endereço da \(suggestion.name). Usar a \(suggestion.name)?")
                                            .typeStyle(.note).fontWeight(.semibold).foregroundStyle(Palette.ink)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else if !trimmed.isEmpty, case .failure(let problem) = validation {
                                Text(problemMessage(problem)).typeStyle(.note).foregroundStyle(Palette.down)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if isValid {
                                Label("Endereço válido na \(chain.name)", systemImage: "checkmark.circle.fill")
                                    .typeStyle(.note).foregroundStyle(Palette.up)
                            }
                        }
                    }
                    if let qrProblem {
                        Banner(kind: .failure, title: qrProblem)
                    }
                    if let destination, let otherID {
                        OtherIDCheck(pasted: destination.address, known: otherID, knownLabel: KnownAddress.label(otherID.known, chain: chain, session: session),
                                     check: $check, field: Palette.rail, identifier: "contato-conferir-id")
                    } else if let destination, let segment {
                        sourceCheck(destination, segment)
                    }
                    if chain.destinationTag != .none {
                        labeled(chain.destinationTag == .stellarMemo ? String(localized: "Memo, se houver") : String(localized: "Tag de destino, se houver")) {
                            if memoConflict != nil {
                                HiddenAddressField(fill: Palette.rail, buttonFill: Palette.control, identifier: "contato-editar-memo") {
                                    tag = ""
                                    memoConflict = nil
                                    memoCheck = ""
                                }
                            } else {
                                TextField("", text: $tag)
                                    .font(TypeStyle.mono.font).foregroundStyle(Palette.ink)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .padding(.horizontal, Space.md).frame(height: Height.field)
                                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.rail))
                                    // A frase ou a chave na tag sai na hora: salva, ela iria a rede em cada envio (revisao de
                                    // seguranca, 09/11/2026).
                                    .onChange(of: tag) { _, new in
                                        if PhraseGuard.tagHasSecret(new) {
                                            tag = ""
                                            tagNotice = PhraseGuard.tagMessage
                                        } else if !new.isEmpty {
                                            tagNotice = nil
                                        }
                                    }
                                if let tagNotice {
                                    Text(tagNotice).typeStyle(.note).foregroundStyle(Palette.down).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if let memoConflict {
                            memoSourceCheck(memoConflict)
                        }
                    }
                }
                .padding(Space.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                ActionFooter {
                    PrimaryButton(title: String(localized: "Salvar"),
                                  enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && isValid
                                  && (checked || nearPending || (wholeNameOnScreen && !check.isEmpty)) && memoConfirmed) {
                        Task { await saveTapped() }
                    }
                }
            }
            .background(Palette.body.ignoresSafeArea())
            .navigationTitle("Salvar endereço")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: check) { _, _ in wholeNameMiss = false }
            .onChange(of: trimmed) { old, new in
                // Colado pelo menu do sistema: com um segredo, a area de transferencia esvazia tambem.
                if new.count > old.count + 1, PrivateKeyGuard.clipboardHasSecret(new, on: chain) { Pasteboard.clearSecret() }
                // A frase colada ou digitada no campo sai dele na hora, como no envio (revisao de seguranca, 09/11/2026).
                if let message = PhraseGuard.secretMessage(new, on: chain) {
                    // A frase tambem nao fica na marca do nome da NEAR (digitada palavra a palavra, ela arma), nem na leitura do QR.
                    nearArmedFor = nil
                    linkReading = nil
                    address = ""
                    qrProblem = message
                    return
                }
                // O endereco que entra inteiro (o Colar do menu do campo): o desafio do nome nasce na hora. So a digitacao, letra
                // a letra, espera o Salvar.
                if AddressPoisoning.enteredWhole(from: old, to: new) { armNEAR(new, chain: chain) }
                check = ""
                memoConflict = nil
                if !new.isEmpty { qrProblem = nil }
                if new != linkReading?.address { linkReading = nil }
            }
            .onChange(of: chain) { _, new in
                check = ""
                memoConflict = nil
                // O que era endereco na rede de antes (0x mais 64 hexadecimais na Sui) e chave na nova (a EVM): sai do campo, como
                // no Android.
                if let message = PhraseGuard.secretMessage(trimmed, on: new) {
                    nearArmedFor = nil
                    linkReading = nil
                    address = ""
                    qrProblem = message
                    return
                }
                // O endereco que veio de um QR de outra rede nao fica para a rede nova.
                if let reading = linkReading, let problem = PaymentURI.networkProblem(reading, chain: new) {
                    address = ""
                    qrProblem = problem
                    linkReading = nil
                }
            }
            .sheet(isPresented: $scanning) {
                QRScannerSheet { text in
                    // O mesmo leitor do envio: um QR com as palavras de uma carteira nunca
                    // vai para o campo (auditoria 4, C7-13), e a tag do link vem junto.
                    let reading = PaymentURI.read(text)
                    // O QR de outra rede que a escolhida nao entra (auditoria 4, B-4).
                    if let problem = reading.problem ?? PaymentURI.networkProblem(reading, chain: chain) {
                        address = ""
                        qrProblem = problem
                        linkReading = nil
                    } else {
                        armNEAR(reading.address, chain: chain)
                        address = reading.address
                        if let linkTag = reading.tag, !linkTag.isEmpty { tag = linkTag }
                        qrProblem = nil
                        linkReading = reading
                    }
                    scanning = false
                }
            }
        }
        .presentationBackground(Palette.body)
        .presentationCornerRadius(Radius.sheet)
    }

    @ViewBuilder
    private func sourceCheck(_ destination: Address.Destination, _ segment: AddressPoisoning.Segment) -> some View {
        // Na NEAR com nome, o nome inteiro, com o registro, como no envio (revisao de seguranca, 08/11/2026).
        let wholeName = AddressPoisoning.coversAll(segment, of: lookalike == nil ? trimmed : destination.address)
        VStack(alignment: .leading, spacing: Space.sm) {
            if let lookalike {
                Banner(kind: .caution,
                       title: wholeName ? String(localized: "Nome parecido com um que você já usou") : String(localized: "Endereço parecido com um que você já usou"),
                       message: wholeName ? String(localized: "Golpistas registram por centavos nomes assim. Confira na fonte antes de salvar.")
                                          : String(localized: "As pontas são iguais, o meio é diferente. Confira na fonte antes de salvar."))
                // O nome colado escondido, como no desafio escondido: a vista, quem copiasse da tela passava (revisao de seguranca,
                // 09/11/2026). O conhecido fica a vista.
                MarkedAddress(label: String(localized: "Você colou"), address: destination.address, segment: segment, masked: wholeName)
                MarkedAddress(label: KnownAddress.label(lookalike, chain: chain, session: session), address: lookalike,
                              segment: AddressPoisoning.differingSegment(lookalike, from: destination.address, chain: chain))
            } else {
                MarkedAddress(label: String(localized: "Confira com a fonte"), address: trimmed, segment: segment, masked: true)
            }
            Text(wholeName
                 ? String(localized: "Olhando onde você copiou o endereço, digite o nome inteiro da conta, com o final (como .near). Um programa no computador pode trocar o endereço na hora de copiar.")
                 : lookalike == nil
                 ? String(localized: "Olhando onde você copiou o endereço, digite os 6 caracteres escondidos. Um programa no computador pode trocar o endereço na hora de copiar.")
                 : String(localized: "Olhando onde você copiou o endereço, digite os 6 caracteres marcados. Um programa no computador pode trocar o endereço na hora de copiar."))
                .typeStyle(.note).foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if AddressPoisoning.caseMatters(checkedText, chain: chain) { CaseNote() }
            // Acima do campo: abaixo, o teclado e o Salvar o cobriam.
            if wholeNameMiss { WholeNameMiss() }
            // As caixas do envio, que so aceitam um caractere por vez: colar a area de transferencia nao responde o desafio.
            CharacterBoxes(text: $check, count: segment.length, limit: wholeName ? AddressPoisoning.wholeNameLimit : nil,
                           identifier: "contato-conferir-trecho")
        }
    }

    /// O memo que bate com outra conta conhecida: o conhecido a vista, com o ID dele, e o
    /// memo do contato escondido, para o dono digitar o que le na fonte.
    private func memoSourceCheck(_ conflict: AddressPoisoning.SameAccount) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Banner(kind: .caution, title: String(localized: "Mesma conta de um endereço que você já usou, com outro ID"),
                   message: String(localized: "Confira o ID com quem vai receber."))
            MarkedAddress(label: String(localized: "\(KnownAddress.label(conflict.known, chain: chain, session: session)) · ID \(String(conflict.knownID))"),
                          address: conflict.known, segment: AddressPoisoning.muxedIDSegment(conflict.known))
            Text(String(localized: "Para seguir, digite o memo que quem vai receber mostra, lendo onde você o copiou."))
                .typeStyle(.note).foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            // Um caractere por vez e sem Colar: o memo colado pode ter sido trocado, e colar de novo respondia (revisao de seguranca,
            // 08/11/2026). Ate 20, o maior ID.
            ChallengeTextField(text: $memoCheck, isFocused: $memoFocused, limit: 20, identifier: "contato-conferir-memo",
                               placeholder: String(localized: "Memo"), fontSize: 16, weight: .medium)
                .padding(Space.sm)
                .background(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).fill(Palette.rail))
                .frame(maxWidth: 220, alignment: .leading)
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).typeStyle(.note).foregroundStyle(Palette.inkSoft)
            content()
        }
    }

    /// Um endereco salvo vira endereco de confianca: aparece como atalho no envio e entra
    /// na conferencia de endereco parecido. Por isso gravar pede Face ID ou PIN, como
    /// qualquer operacao que muda para onde o dinheiro pode ir.
    /// O endereco entrou inteiro (colar, QR, recentes): o desafio do nome da NEAR nasce na hora. Adiar ate o Salvar deixava o nome
    /// trocado a vista no campo (revisao de seguranca, 09/11/2026).
    private func armNEAR(_ text: String, chain: Chain) {
        // So o texto, sem a rede: colado na Bitcoin e trocado para a NEAR pela sugestao, o nome voltava a vista.
        nearArmedFor = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Um nome (com ponto) noutra rede: o aviso diz que e um nome, e nao manda copiar de novo (revisao de seguranca, 09/11/2026).
    private func problemMessage(_ problem: Address.Problem) -> String {
        if case .malformed = problem, AddressPoisoning.nameNotAddress(trimmed, on: chain) {
            return String(localized: "Este é um nome, não um endereço. Cole o endereço da rede \(chain.name).")
        }
        return SendStages.message(problem, chain: chain)
    }

    /// O Salvar. Nome da NEAR: o desafio nasce aqui, e o nome inteiro e conferido aqui. O `save` confere tudo de novo.
    private func saveTapped() async {
        if nearPending {
            nearArmedFor = trimmed
            return
        }
        if wholeNameOnScreen, !checked {
            // Sem nada digitado, nada a dizer: alarme falso ensina a ignorar o verdadeiro.
            wholeNameMiss = !check.isEmpty
            return
        }
        await save()
    }

    private func save() async {
        guard case .success(let destination) = validation, checked, memoConfirmed else { return }
        // A tag com uma frase ou uma chave nunca e salva: iria a rede em cada envio (como no Android, revisao de seguranca).
        guard !PhraseGuard.tagHasSecret(tag) else {
            tag = ""
            tagNotice = PhraseGuard.tagMessage
            return
        }
        // O memo que bate com outra conta conhecida: antes de salvar, o dono o confere na
        // fonte, com o campo do memo escondido.
        if memoConflict == nil, let conflict = memoOtherID {
            memoConflict = conflict
            memoCheck = ""
            return
        }
        // So rede que tem tag guarda tag (revisao da auditoria 4, B-1).
        let finalTag = chain.destinationTag == .none ? nil : (destination.tag.map(String.init) ?? (tag.isEmpty ? nil : tag))
        let title = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        do {
            guard try await auth.perform(session, reason: String(localized: "Salvar o endereço de \(title)"), { _ in true }) == true else { return }
        } catch {
            // Na espera do modo reforcado, o motivo; o resto, como antes, so nao salva.
            if let message = AuthCoordinator.refusalMessage(error) { toasts.show(message, kind: .failure) }
            return
        }
        session.metadata.contacts.append(Contact(id: UUID(), name: title, chainID: chain.id, address: destination.address, tag: finalTag))
        do {
            try session.persist()
            dismiss()
        } catch {
            session.metadata.contacts.removeAll { $0.address == destination.address && $0.chainID == chain.id && $0.name == title }
        }
    }
}

/// P4: gerenciar ativos: o que aparece na Carteira e as moedas custom.
struct ManageAssetsView: View {
    @Environment(AppSession.self) private var session
    @Environment(Portfolio.self) private var portfolio
    @State private var adding = false
    @State private var removing: Asset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let wallet = session.selectedWallet, !portfolio.allRows.isEmpty {
                    SettingsGroup {
                        ForEach(portfolio.allRows) { row in
                            Toggle(isOn: Binding(
                                get: { !wallet.hiddenAssetIDs.contains(row.id) },
                                set: { visible in
                                    let updated = session.update(wallet.id) { if visible { _ = $0.hiddenAssetIDs.remove(row.id) } else { _ = $0.hiddenAssetIDs.insert(row.id) } }
                                    portfolio.show(updated ?? wallet, session: session, force: true)
                                }
                            )) {
                                HStack(spacing: Space.sm) {
                                    CoinLogo(coingeckoID: row.logoID, symbol: row.symbol, size: 28, ringColor: Palette.body, unverified: row.origin != nil,
                                             logoAsset: row.contractLogoAsset)
                                    Text(verbatim: row.symbol).typeStyle(.body).foregroundStyle(Palette.ink)
                                    if row.isCustom { TokenBadge(.custom) }
                                }
                            }
                            .tint(Palette.accent)
                            .padding(.horizontal, Space.md).frame(minHeight: Height.rowCompact)
                        }
                    }
                    .padding(.top, Space.md)
                }
                if let wallet = session.selectedWallet, !portfolio.allOthers.isEmpty {
                    // Outros tokens: fora da lista verificada, sem suspeita. Esconder tira da
                    // Carteira e do total; o saldo continua na rede.
                    Text("Outros tokens").typeStyle(.heading).foregroundStyle(Palette.ink)
                        .padding(.horizontal, Space.gutter).padding(.top, Space.xl)
                    Text("Fora da lista verificada. Os suspeitos não aparecem aqui: ficam sempre escondidos.")
                        .typeStyle(.note).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Space.gutter).padding(.top, Space.xxs)
                    SettingsGroup {
                        ForEach(portfolio.allOthers) { token in
                            Toggle(isOn: Binding(
                                get: { !wallet.hiddenAssetIDs.contains(token.id) },
                                set: { visible in
                                    let updated = session.update(wallet.id) { if visible { _ = $0.hiddenAssetIDs.remove(token.id) } else { _ = $0.hiddenAssetIDs.insert(token.id) } }
                                    portfolio.show(updated ?? wallet, session: session, force: true)
                                }
                            )) {
                                HStack(spacing: Space.sm) {
                                    CoinLogo(coingeckoID: nil, symbol: token.asset.symbol, size: 28, network: token.asset.chain, ringColor: Palette.body,
                                             unverified: true, logoAsset: token.asset)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: token.asset.symbol).typeStyle(.body).foregroundStyle(Palette.ink).lineLimit(1)
                                        Text("na \(token.asset.chain?.name ?? token.asset.chainID)").typeStyle(.note).foregroundStyle(Palette.inkSoft).lineLimit(1)
                                    }
                                }
                            }
                            .tint(Palette.accent)
                            .padding(.horizontal, Space.md).frame(minHeight: Height.row)
                        }
                    }
                    .padding(.top, Space.sm)
                }

                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Moedas custom").typeStyle(.heading).foregroundStyle(Palette.ink)
                    Text("Um token que não está na lista verificada e que você quer ver, receber e enviar. A carteira lê nome, símbolo e casas decimais na própria rede antes de salvar.")
                        .typeStyle(.note).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.gutter).padding(.top, Space.xl)

                if !session.metadata.customTokens.isEmpty {
                    SettingsGroup {
                        ForEach(session.metadata.customTokens, id: \.id) { asset in
                            HStack(spacing: Space.sm) {
                                CoinLogo(coingeckoID: nil, symbol: asset.symbol, size: 28, network: asset.chain, ringColor: Palette.body, unverified: true,
                                         logoAsset: asset)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: asset.symbol).typeStyle(.body).foregroundStyle(Palette.ink).lineLimit(1)
                                    Text(verbatim: "\(asset.chain?.name ?? asset.chainID) · \(Fmt.address(CustomToken.reference(asset.kind) ?? "", chain: asset.chain))")
                                        .typeStyle(.note).foregroundStyle(Palette.inkSoft).lineLimit(1)
                                }
                                Spacer()
                                Button { removing = asset } label: {
                                    Text("Remover").typeStyle(.note).foregroundStyle(Palette.inkSoft).frame(minHeight: Height.touch)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remover \(asset.symbol)")
                            }
                            .padding(.horizontal, Space.md).frame(minHeight: Height.rowCompact)
                        }
                    }
                    .padding(.top, Space.sm)
                }

                SecondaryButton(title: String(localized: "Adicionar moeda"), systemImage: "plus") { adding = true }
                    .padding(.horizontal, Space.gutter).padding(.top, Space.md)
                    .accessibilityIdentifier("adicionar-moeda")

                if portfolio.unknownTokens > 0 {
                    Text(portfolio.unknownTokens == 1
                         ? "1 token chegou numa rede em que a carteira ainda só conta quantos são, sem ler nome e contrato. Ele fica escondido."
                         : "\(portfolio.unknownTokens) tokens chegaram numa rede em que a carteira ainda só conta quantos são, sem ler nome e contrato. Eles ficam escondidos.")
                        .typeStyle(.note).foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, Space.gutter).padding(.top, Space.lg)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, Space.xl)
        }
        .background(Palette.void.ignoresSafeArea())
        .navigationTitle("Gerenciar ativos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            NavigationStack { AddCustomTokenView { adding = false } }
                .presentationBackground(Palette.void)
        }
        .whiteAlert("Remover \(removing?.symbol ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Cancelar", role: .cancel) { removing = nil }
            Button("Remover", role: .destructive) { remove() }
        } message: {
            Text("A moeda some da Carteira, de Receber e de Enviar. O saldo continua na rede, e você pode adicionar de novo.")
        }
    }

    private func remove() {
        guard let asset = removing else { return }
        removing = nil
        session.metadata.customAssets = session.metadata.customTokens.filter { $0.id != asset.id }
        try? session.persist()
        portfolio.customChanged(session.selectedWallet, session: session)
        Task { await portfolio.refresh(session.selectedWallet, session: session) }
    }
}

/// A lista vazia de enderecos salvos (pedido do dono, 15/10/2026): tres cartoes de endereco,
/// de redes diferentes, que chegam empilhados e se abrem um embaixo do outro, e flutuam de
/// leve. Com Reduzir Movimento, ja abertos e parados.
private struct SavedAddressesIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false

    private static let chains = ["bitcoin", "ethereum", "xrpl"].compactMap { Chain.find($0) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(Self.chains.enumerated()), id: \.offset) { index, chain in
                    let place = CGFloat(index) - 1
                    card(chain, index: index)
                        .offset(y: (open ? place * 58 : place * 6) + (reduceMotion ? 0 : CGFloat(sin(time * 1.3 + Double(index) * 1.1)) * 2))
                        .rotationEffect(.degrees(open ? 0 : Double(place) * -5))
                        .scaleEffect(open ? 1 : 0.94 - 0.02 * abs(place))
                        .zIndex(Double(3 - index))
                }
            }
            .frame(height: 190)
        }
        .onAppear {
            if reduceMotion {
                open = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.25)) { open = true }
            }
        }
        .accessibilityHidden(true)
    }

    private func card(_ chain: Chain, index: Int) -> some View {
        HStack(spacing: Space.sm) {
            NetworkBadge(chain: chain, size: 30, ring: Palette.body)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Palette.ink.opacity(0.85)).frame(width: [92, 74, 104][index % 3], height: 7)
                Capsule().fill(Palette.inkMuted.opacity(0.6)).frame(width: [132, 150, 118][index % 3], height: 6)
            }
            Spacer(minLength: 0)
            Image(systemName: "bookmark.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkMuted)
        }
        .padding(.horizontal, Space.md)
        .frame(width: 250, height: 52)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.body)
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Palette.edge, lineWidth: 1)))
    }
}
