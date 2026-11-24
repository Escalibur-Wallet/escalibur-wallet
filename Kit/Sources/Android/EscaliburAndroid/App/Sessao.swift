import EscaliburChains
import EscaliburCore
import EscaliburEngines
import EscaliburKeys
import EscaliburNetwork
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Como o dono prova presenca para uma operacao que precisa da chave raiz (o `Credential` do iOS).
enum Credencial {
    case pin(SecureBytes)
    case biometria(motivo: String)
    /// O PIN e, com a biometria ligada, ela tambem: ver as palavras, remover carteira, desligar
    /// a biometria.
    case pinEBiometria(SecureBytes, motivo: String)
    /// Modo reforcado: o PIN e a biometria pela criptografia, em tudo.
    case reforcado(SecureBytes, motivo: String)

    func zerar() {
        switch self {
        case .pin(let pin), .pinEBiometria(let pin, _), .reforcado(let pin, _): pin.wipe()
        case .biometria: break
        }
    }
}

/// O estado de alto nivel do app Android: a mesma sessao do iOS (App/AppSession.swift), sem a
/// interface. A interface (Kotlin) pergunta o estado e chama as operacoes; nada aqui depende da
/// thread principal: o estado fica sob uma trava e o trabalho pesado (Argon2, rede) roda fora
/// dela.
final class Sessao: @unchecked Sendable {
    static let shared = Sessao()

    enum Fase: String, Codable { case onboarding, locked, unlocked }

    enum Falha: Error {
        case semPasta
        case travada
        case jaImportada(String)
        case naoEFrase
        case remocaoFalhou
        case semRascunho
        case carteiraNaoEncontrada
        /// Alguma carteira ainda sem a copia conferida (o Super Security espera por ela).
        case copiaPendente
        /// A passphrase tem um caractere que nao da para anotar no papel.
        case passphraseInvisivel
        /// Passou dos 256 bytes do cofre, contados depois do NFKD (revisao de seguranca de 24/10/2026).
        case passphraseLonga
        /// Passphrase vazia ao abrir uma carteira com passphrase.
        case passphraseVazia
        /// Abrir com passphrase a partir de uma carteira que ja tem passphrase.
        /// Super Security em "Bloquear as carteiras": nenhuma carteira com palavras entra.
        case bloqueioLigado
        case baseComPassphrase
        /// A carteira que ja estava aqui quando o cofre abriu saiu no meio: nada foi gravado.
        case listaMudou
    }

    private let trava = NSLock()
    private var faseAtual: Fase
    private var metadados = Metadata()
    /// A chave dos metadados. So existe enquanto o app esta destrancado.
    private var chaveDeIndice: SymmetricKey?
    /// A ida para o segundo plano no relogio monotono (conta o tempo dormindo, nao anda com o
    /// relogio de parede).
    private var segundoPlanoDesde: TimeInterval?
    /// As palavras de uma carteira recem-criada, enquanto o dono anota e confere.
    private var rascunho: Rascunho?

    private init() {
        faseAtual = Chaves.root.isSetUp ? .locked : .onboarding
    }

    var fase: Fase { trava.withLock { faseAtual } }
    var metadata: Metadata { trava.withLock { metadados } }

    /// O que terminou depois de o app travar e precisa ir para os metadados (o `whenUnlocked` do
    /// iOS): a ponte ou a ordem que saiu enquanto o app travava (caca de bugs de 25/10/2026). Espera
    /// o proximo destravar e vale por cima dos metadados de verdade. Se o processo morrer antes, se
    /// perde, como antes.
    private var depoisDeDestravar: [(inout Metadata) -> Void] = []
    /// A ultima carteira foi removida com o app travado no meio: no destravar, o app volta a ser como recem-instalado (rodada 14).
    private var apagarAoDestravar = false

    func alterarOuDepois(_ corpo: @escaping (inout Metadata) -> Void) {
        let gravou = trava.withLock { () -> Bool in
            guard let chaveDeIndice else {
                depoisDeDestravar.append(corpo)
                return false
            }
            var copia = metadados
            corpo(&copia)
            guard (try? MetadataStore.save(copia, key: chaveDeIndice)) != nil else { return false }
            metadados = copia
            return true
        }
        // A interface so le o estado quando pede: a marca de outra chave gravada aqui, com o Copiar endereco ja aberto, nao
        // chegava a tela, e o endereco marcado copiava (rodada 8 da auditoria 8). Fora da trava.
        if gravou { Eventos.emitir("estado", Data("{}".utf8)) }
    }

    /// Muda os metadados e grava. Travado no meio de uma operacao: nada e gravado em silencio.
    @discardableResult
    func alterar<T>(_ corpo: (inout Metadata) throws -> T) throws -> T {
        try trava.withLock {
            guard let chaveDeIndice else { throw Falha.travada }
            var copia = metadados
            let resultado = try corpo(&copia)
            try MetadataStore.save(copia, key: chaveDeIndice)
            metadados = copia
            return resultado
        }
    }

    // MARK: Abertura

    /// Na abertura do processo: a contagem de tentativas que veio de outro boot, e a fase de novo
    /// (o cofre pode ter sido apagado por fora).
    func abrirProcesso() {
        Chaves.root.rebaseAttempts()
        trava.withLock {
            if faseAtual == .locked, !Chaves.root.isSetUp { faseAtual = .onboarding }
        }
        // Sem cofre, nenhuma carteira: nenhum arquivo de aviso fica.
        if !Chaves.root.isSetUp { Vigias.apagarTudo() }
    }

    // MARK: PIN e desbloqueio

    func cadastrarPIN(_ pin: SecureBytes) throws {
        defer { pin.wipe() }
        let rk = try Chaves.root.setUp(pin: pin)
        defer { rk.wipe() }
        let chave = IndexCipher.key(from: rk)
        try trava.withLock {
            chaveDeIndice = chave
            metadados = Metadata()
            // Nada de uma instalacao anterior espera o destravar desta (revisao de seguranca, 08/11/2026).
            depoisDeDestravar = []
            // A ultima removida com o app travado no meio nao vale para a instalacao seguinte (rodada 15).
            apagarAoDestravar = false
            try MetadataStore.save(metadados, key: chave)
            faseAtual = .unlocked
        }
    }

    // MARK: Super Security: a biometria antes do PIN

    /// A biometria do Super Security ja confirmada, a espera do PIN (pedido do dono, 01/11/2026: o
    /// rosto antes do PIN ao abrir o app, enviar e ver as palavras). So o identificador fica aqui; o
    /// cofre guarda o resto, vale um PIN e vence em 2 minutos.
    private var rostoConfirmado: RootKeyVault.HardenedFacePass?

    func confirmarRosto(motivo: String, abrir: Bool) throws {
        let passe = try Chaves.root.hardenedFace(reason: motivo, use: abrir ? .openApp : .operation)
        trava.withLock { rostoConfirmado = passe }
    }

    func descartarRosto() {
        trava.withLock { rostoConfirmado = nil }
        Chaves.root.discardHardenedFace()
    }

    /// O PIN do Super Security com a biometria ja confirmada, ou, sem ela, as duas numa chamada so.
    private func abrirReforcado(pin: SecureBytes, motivo: String, uso: RootKeyVault.HardenedUse) throws -> SecureBytes {
        let passe = trava.withLock { () -> RootKeyVault.HardenedFacePass? in
            defer { rostoConfirmado = nil }
            return rostoConfirmado
        }
        if let passe { return try Chaves.root.unlockHardened(pin: pin, face: passe, use: uso) }
        return try Chaves.root.unlockHardened(pin: pin, reason: motivo, use: uso)
    }

    func destrancar(pin: SecureBytes) throws {
        defer { pin.wipe() }
        let epoca = trava.withLock { epocaDeTravar }
        let rk: SecureBytes
        do {
            rk = Chaves.root.securityMode == .hardened
                ? try abrirReforcado(pin: pin, motivo: Textos.destravar, uso: .openApp)
                : try Chaves.root.unlock(pin: pin)
        } catch RootKeyVault.Failure.wiped {
            // O ultimo PIN errado no bloqueio: os metadados vao junto aqui mesmo, como nas operacoes, e a tela segue o
            // apagar sem depender de a dela ainda estar aberta (06/11/2026). O "sessao.apagarTudo" da tela fica de reforco.
            apagarTudo()
            throw RootKeyVault.Failure.wiped
        }
        defer { rk.wipe() }
        try abrir(com: IndexCipher.key(from: rk), novasContas: Self.contasQueFaltam(rk: rk), epoca: epoca)
    }

    func destrancarComBiometria() throws {
        let epoca = trava.withLock { epocaDeTravar }
        let rk = try Chaves.root.unlockWithBiometry(reason: Textos.destravar)
        defer { rk.wipe() }
        try abrir(com: IndexCipher.key(from: rk), novasContas: Self.contasQueFaltam(rk: rk), epoca: epoca)
    }

    /// Cada travar() soma um. O destravar que comecou antes de um travar (o dono apertou o botao de
    /// energia durante o Argon2) nao termina abrindo o app com a tela apagada (revisao de seguranca do
    /// Android de 26/10/2026).
    private var epocaDeTravar = 0
    /// A vez do travar agora: quem le a rede e grava depois confere que o app nao travou no meio (rodada 5 da auditoria 8).
    var epocaAtual: Int { trava.withLock { epocaDeTravar } }

    /// Redes que entraram numa versao nova ainda nao tem endereco nas carteiras antigas: com a RK
    /// aberta neste desbloqueio, os enderecos que faltam sao derivados agora. A carteira com
    /// passphrase fica para a proxima assinatura, quando a passphrase e digitada
    /// (`PortaDaPassphrase.assinar`): o cofre nao a tem.
    ///
    /// E a passphrase que uma versao anterior gravou sai do cofre, no primeiro destravar depois de
    /// atualizar (pedido do dono, 05/11/2026). A que estava fora de NFKD deixa so a marca
    /// `legacyCardanoPassphrase`, gravada antes de ela sair: sem a marca gravada, ela espera o
    /// proximo destravar. Se o cofre recusar, tambem; o registro aberto ja nao a devolve a ninguem.
    private static func contasQueFaltam(rk: SecureBytes) -> [UUID: [DerivedAccount]] {
        let chave = IndexCipher.key(from: rk)
        guard var metadata = try? MetadataStore.load(key: chave) else { return [:] }
        // Os fatos sobre a antiga (fora de NFKD; nao da a raiz da criacao) viram marcas, gravadas antes de ela sair: sem as
        // marcas gravadas, ela espera o proximo destravar.
        var achadas: [(id: UUID, antiga: Bool, conferida: Bool)] = []
        for wallet in metadata.wallets where wallet.hasPassphrase && !wallet.isWatchOnly {
            let digital = wallet.fingerprint.flatMap(Hex.decode)
            if case .present(let antiga, let conferida) = try? Chaves.wallets.storedPassphrase(walletID: wallet.id, rk: rk, fingerprint: digital) {
                achadas.append((wallet.id, antiga, conferida))
            }
        }
        let marcas = achadas.filter { $0.antiga || !$0.conferida }
        var marcada = true
        if !marcas.isEmpty {
            for indice in metadata.wallets.indices {
                guard let marca = marcas.first(where: { $0.id == metadata.wallets[indice].id }) else { continue }
                if marca.antiga { metadata.wallets[indice].legacyCardanoPassphrase = true }
                if !marca.conferida { metadata.wallets[indice].passphraseUnverified = true }
            }
            marcada = (try? MetadataStore.save(metadata, key: chave)) != nil
        }
        for item in achadas where marcada || !(item.antiga || !item.conferida) {
            _ = try? Chaves.wallets.purgePassphrase(walletID: item.id, rk: rk)
        }
        var novas: [UUID: [DerivedAccount]] = [:]
        for wallet in metadata.wallets where wallet.isWatchOnly {
            guard let evm = wallet.accounts.first(where: { Chain.find($0.chainID)?.family == .evm }) else { continue }
            let tem = Set(wallet.accounts.map(\.chainID))
            let faltam = Chain.evmChains.filter { !tem.contains($0.id) }
            guard !faltam.isEmpty else { continue }
            novas[wallet.id] = faltam.map {
                DerivedAccount(chainID: $0.id, path: evm.path, address: evm.address, publicKey: evm.publicKey, accountXPub: nil)
            }
        }
        for wallet in metadata.wallets where !wallet.isWatchOnly && !wallet.hasPassphrase {
            let tem = Set(wallet.accounts.map(\.chainID))
            let faltam = Chain.all.filter { !tem.contains($0.id) }
            guard !faltam.isEmpty, let secret = try? Chaves.wallets.open(walletID: wallet.id, rk: rk) else { continue }
            defer { secret.wipe() }
            if let (contas, _) = try? AccountDeriver.derive(secret, chains: faltam), !contas.isEmpty {
                novas[wallet.id] = contas
            }
        }
        return novas
    }

    private func abrir(com chave: SymmetricKey, novasContas: [UUID: [DerivedAccount]], epoca: Int) throws {
        var lidos = try MetadataStore.load(key: chave)
        if !novasContas.isEmpty {
            for (id, contas) in novasContas {
                guard let indice = lidos.wallets.firstIndex(where: { $0.id == id }) else { continue }
                lidos.wallets[indice].accounts += contas
            }
            try? MetadataStore.save(lidos, key: chave)
        }
        let abriu = trava.withLock { () -> Bool in
            guard epocaDeTravar == epoca else { return false }
            metadados = lidos
            chaveDeIndice = chave
            faseAtual = .unlocked
            return true
        }
        guard abriu else { throw Falha.travada }
        PortaDaPassphrase.aplicarPendentes()
        let pendentes = trava.withLock { () -> [(inout Metadata) -> Void] in
            defer { depoisDeDestravar = [] }
            return depoisDeDestravar
        }
        // Pelo `alterarOuDepois`: travado de novo no meio, as gravacoes voltam para a fila em vez de se perder (rodada 12); gravadas,
        // ele avisa a tela, e a copia de uma conta que deixou de receber sai (rodada 11 da auditoria 8).
        if !pendentes.isEmpty { alterarOuDepois { metadata in for corpo in pendentes { corpo(&metadata) } } }
        // A ultima carteira saiu com o app travado no meio da remocao: o apagar tudo que ficou para agora (rodada 14), so se a lista
        // ficou mesmo vazia (outra carteira gravada no meio, ou a gravacao que falhou, nao apagam nada), e o destravar para ai: o
        // resto dele recriaria os arquivos dos avisos (rodada 15).
        let apagar = trava.withLock { () -> Bool in
            guard apagarAoDestravar, chaveDeIndice != nil else { return false }
            apagarAoDestravar = false
            return metadados.wallets.isEmpty
        }
        if apagar {
            apagarTudo()
            return
        }
        // Uma vez, depois de atualizar: os avisos de fim do prazo da versao anterior saem do formato antigo (setima
        // passada da auditoria de 03/11/2026).
        let renovadas = (lidos.limitRenewals ?? []).filter { renovacao in
            lidos.wallets.first { $0.id == renovacao.walletID }?.hasPassphrase == false
        }.map(\.orderID)
        VigiaDeOrdens.migrarAvisos(renovadas: renovadas)
        // O cache de saldo e o historico de carteira que nao existe mais saem, como no iOS (decima terceira passada e a
        // revisao dela): uma leitura que terminou depois de remover a carteira nao deixa o rastro dela.
        let carteiras = Set(lidos.wallets.map(\.id))
        let prefixos = carteiras.map { $0.uuidString + "|" }
        if lidos.balanceCache.keys.contains(where: { !carteiras.contains($0) })
            || (lidos.activityCache ?? [:]).keys.contains(where: { !carteiras.contains($0) })
            || (lidos.activityFetched ?? [:]).keys.contains(where: { !carteiras.contains($0) })
            || (lidos.pendingEVM ?? [:]).keys.contains(where: { chave in !prefixos.contains { chave.hasPrefix($0) } })
            || (lidos.unsureSends ?? []).contains(where: { !carteiras.contains($0.wallet) }) {
            try? alterar { metadata in
                metadata.balanceCache = metadata.balanceCache.filter { carteiras.contains($0.key) }
                metadata.activityCache = metadata.activityCache?.filter { carteiras.contains($0.key) }
                metadata.activityFetched = metadata.activityFetched?.filter { carteiras.contains($0.key) }
                metadata.pendingEVM = metadata.pendingEVM?.filter { item in prefixos.contains { item.key.hasPrefix($0) } }
                metadata.unsureSends = metadata.unsureSends?.filter { carteiras.contains($0.wallet) }
            }
        }
        // E os mapas por ativo com o que nenhuma carteira tem mais.
        var podado = lidos
        Saldos.podarPorAtivo(&podado)
        if podado.quoteCache != lidos.quoteCache || podado.recognizedTokens != lidos.recognizedTokens || podado.unrecognizedChecks != lidos.unrecognizedChecks {
            try? alterar { Saldos.podarPorAtivo(&$0) }
        }
        agendarConferencias()
    }

    func travar() {
        // A biometria confirmada e ainda sem PIN nao vale depois de travar.
        descartarRosto()
        trava.withLock {
            epocaDeTravar &+= 1
            Importacao.esquecerPreviasEVM()
            // As conferencias das carteiras com passphrase param: a tarefa guardava as contas dela na memoria com o app travado
            // (rodada 3 da auditoria 8), como no iOS. A que nao terminou a primeira e conferida de novo quando escolhida (rodada 4).
            for carteira in metadados.wallets where carteira.hasPassphrase { cancelarConferencias(de: carteira.id) }
            // Travado, a tela da previa sai: a marca dela nao segura a rodada do dia depois de destravar (rodada 6).
            previaAberta = false
            tronLidaEm = [:]
            rascunho?.zerar()
            rascunho = nil
            chaveDeIndice = nil
            metadados = Metadata()
            if faseAtual == .unlocked { faseAtual = .locked }
        }
        Saldos.shared.esquecer()
        Atividade.shared.esquecer()
        Renovacoes.esquecer(carteira: nil)
        PortaDaPassphrase.encerrarFolgas()
        Envio.encerrar()
        Silencio.ligar(false)
        esquecerSegredosDasTelas()
    }

    /// Os segredos que as telas guardam entre um passo e outro (lacre e abertura de envelope, frases do
    /// Super Security) saem ao travar e ao apagar tudo: antes so a tela, ao fechar, os zerava, e com o
    /// app no fundo isso esperava a volta (revisao de seguranca do Android de 26/10/2026).
    private func esquecerSegredosDasTelas() {
        Envelopes.encerrar()
        Envelopes.fecharAbertura()
        Reforco.esquecerFrases()
    }

    /// O app foi para o segundo plano (a tela ja fica coberta pelo FLAG_SECURE).
    func foiParaSegundoPlano() {
        trava.withLock { segundoPlanoDesde = PINPolicy.uptime }
        // A biometria confirmada e ainda sem PIN nao fica para a volta, nem a copia da passphrase da folga
        // (pedido do dono, 05/11/2026).
        descartarRosto()
        PortaDaPassphrase.encerrarFolgas()
        // E o que as telas guardavam com a passphrase: o envelope aberto (o arquivo cifrado fica) e as frases do Super Security.
        // O lacre nao leva a passphrase e fica, como no iPhone. A ida ao seletor de arquivos do app nao passa por aqui.
        Envelopes.esquecerAberto()
        Reforco.esquecerFrases()
    }

    /// Voltou: trava se passou do tempo escolhido (padrao 1 minuto). Devolve se travou.
    @discardableResult
    func voltouAoPrimeiroPlano() -> Bool {
        Chaves.root.rebaseAttempts()
        let deveTravar = trava.withLock { () -> Bool in
            defer { segundoPlanoDesde = nil }
            guard faseAtual == .unlocked, let desde = segundoPlanoDesde else { return false }
            return PINPolicy.uptime - desde >= Double(max(0, metadados.settings.autoLockSeconds))
        }
        if deveTravar { travar() }
        return deveTravar
    }

    // MARK: Operacoes com a chave raiz

    /// Destranca a RK com presenca nova e executa `corpo` com ela. A RK nasce, e usada e e zerada
    /// dentro desta chamada.
    /// As redes que nasceram numa assinatura da carteira com passphrase. So as que ainda faltam.
    func acrescentarContas(_ contas: [DerivedAccount], em id: UUID) {
        try? alterar { metadata in
            guard let indice = metadata.wallets.firstIndex(where: { $0.id == id }) else { return }
            let tem = Set(metadata.wallets[indice].accounts.map(\.chainID))
            let novas = contas.filter { !tem.contains($0.chainID) }
            guard !novas.isEmpty else { return }
            metadata.wallets[indice].accounts += novas
        }
    }

    func comChaveRaiz<T>(_ credencial: Credencial, _ corpo: (SecureBytes) throws -> T) throws -> T {
        do {
            let rk: SecureBytes
            switch credencial {
            case .pin(let pin):
                defer { pin.wipe() }
                rk = try Chaves.root.unlock(pin: pin)
            case .biometria(let motivo):
                rk = try Chaves.root.unlockWithBiometry(reason: motivo)
            case .pinEBiometria(let pin, let motivo):
                defer { pin.wipe() }
                rk = try Chaves.root.unlockWithPINAndBiometry(pin: pin, reason: motivo)
            case .reforcado(let pin, let motivo):
                defer { pin.wipe() }
                rk = try abrirReforcado(pin: pin, motivo: motivo, uso: .operation)
            }
            defer { rk.wipe() }
            return try corpo(rk)
        } catch RootKeyVault.Failure.wiped {
            // O erro que disparou o apagar apos erros veio de uma operacao: os metadados vao junto.
            apagarTudo()
            throw RootKeyVault.Failure.wiped
        }
    }

    /// Liga a biometria: o cofre confere na hora que o slot novo abre e devolve a mesma RK.
    func ligarBiometria(pin: SecureBytes, motivo: String) throws {
        do {
            defer { pin.wipe() }
            let rk = try Chaves.root.unlock(pin: pin)
            defer { rk.wipe() }
            try Chaves.root.enableBiometry(rk: rk, reason: motivo)
        } catch RootKeyVault.Failure.wiped {
            apagarTudo()
            throw RootKeyVault.Failure.wiped
        }
        try alterar { $0.settings.biometryEnabled = true }
    }

    func desligarBiometria(_ credencial: Credencial) throws {
        guard case .pinEBiometria(let pin, let motivo) = credencial else {
            credencial.zerar()
            throw RootKeyVault.Failure.biometryRequired
        }
        do {
            defer { pin.wipe() }
            try Chaves.root.disableBiometry(pin: pin, reason: motivo)
        } catch RootKeyVault.Failure.wiped {
            apagarTudo()
            throw RootKeyVault.Failure.wiped
        }
        try? alterar { $0.settings.biometryEnabled = false }
    }

    func trocarPIN(_ credencial: Credencial, novo: SecureBytes) throws {
        defer { novo.wipe() }
        // No Super Security o PIN troca dentro do registro do modo, com a biometria de novo para
        // conferir antes de valer.
        if case .reforcado(let pin, let motivo) = credencial {
            defer { pin.wipe() }
            // Trocar o PIN pede a biometria la dentro, para conferir antes de valer.
            descartarRosto()
            do {
                try Chaves.root.changeHardenedPIN(currentPIN: pin, newPIN: novo, reason: motivo,
                                                  confirmReason: Textos.t("Confirme a biometria para conferir o Super Security"))
            } catch RootKeyVault.Failure.wiped {
                apagarTudo()
                throw RootKeyVault.Failure.wiped
            }
            return
        }
        try comChaveRaiz(credencial) { rk in try Chaves.root.changePIN(rk: rk, newPIN: novo) }
    }

    // MARK: Carteiras

    /// Guarda uma carteira nova ou importada. A RK so existe durante esta chamada.
    func adicionarCarteira(
        _ secret: WalletSecret, nome: String, origem: WalletMeta.Origin, palavras: Int,
        copiaConfirmada: Bool, selecionar: Bool = true, tronComOutraChave: Bool = false,
        passphraseConfirmada: Bool = false, cardanoAntiga: Bool = false, digitalEsperada: String? = nil, palavrasEscolhidas: Bool = false,
        credencial: Credencial
    ) throws -> WalletMeta {
        guard !adicionarBloqueado else {
            secret.wipe()
            credencial.zerar()
            throw Falha.bloqueioLigado
        }
        let id = UUID()
        let temPassphrase = secret.passphrase.count > 0
        // O autoteste antes de abrir a RK, e a derivacao antes de gravar: se ela falha, nada fica no cofre (a frase ficava
        // guardada sem carteira, longe do "Remover"; revisao da decima terceira passada).
        do { try DerivationSelfTest.require() } catch { secret.wipe(); credencial.zerar(); throw error }
        // A carteira que ja esta aqui nao e gravada de novo: gravar e depois apagar deixava um registro se o apagar falhasse
        // (revisao da decima terceira passada).
        let conhecidas = Set(metadata.wallets.filter { !$0.isWatchOnly }.map(\.fingerprint))
        let (contas, digital, gravada): ([DerivedAccount], [UInt8], Bool) = try comChaveRaiz(credencial) { rk in
            defer { secret.wipe() }
            let derivadas = try AccountDeriver.derive(secret)
            // A importacao so grava a carteira da digital que o dono conferiu na previa, na mesma derivacao que vai ao cofre
            // (revisao de blockchain de 05/11/2026).
            if let digitalEsperada, derivadas.fingerprint.hex.uppercased() != digitalEsperada.uppercased() {
                throw Nucleo.Falha(erro: "importacao.mudou")
            }
            guard !conhecidas.contains(derivadas.fingerprint.hex) else { return (derivadas.accounts, derivadas.fingerprint, false) }
            // De novo com o cofre aberto, logo antes de gravar: a politica pode ter mudado no meio.
            guard !Self.palavrasBloqueadas(Chaves.root) else { throw Falha.bloqueioLigado }
            try Chaves.wallets.save(secret, walletID: id, rk: rk)
            return (derivadas.accounts, derivadas.fingerprint, true)
        }
        // A frase ja foi guardada: se a lista nao grava (o app travou no meio), ela sai, ou ficaria no
        // cofre sem carteira nenhuma, longe do "Remover" (caca de bugs de 27/10/2026).
        do { let salva = try alterar { metadata in
            if let existente = metadata.wallets.first(where: { $0.fingerprint == digital.hex && !$0.isWatchOnly }) {
                if gravada { try? Chaves.wallets.delete(id) }
                throw Falha.jaImportada(existente.name)
            }
            // Estava aqui quando o cofre abriu e saiu no meio: nada foi gravado, e nada e criado.
            guard gravada else { throw Falha.listaMudou }
            var wallet = WalletMeta(
                id: id, name: Self.nomeUnico(nome, origem: origem, em: metadata), kind: .phrase(wordCount: palavras), origin: origem,
                createdAt: .now, accounts: contas, fingerprint: digital.hex, hasPassphrase: temPassphrase,
                backupConfirmedAt: copiaConfirmada ? .now : nil
            )
            if tronComOutraChave { wallet.tronForeignControl = true }
            // A delegacao EVM que a previa viu, com dois de acordo, nasce como marca, como a da Tron (rodada 4 da auditoria 8).
            if let achado = Importacao.consumirPreviaEVM(contas) { wallet.foreignControl = [achado.chain.id: achado.control] }
            if palavrasEscolhidas { wallet.chosenWords = true }
            // As marcas do envelope de antes nascem com a carteira, e nao numa gravacao depois (revisao de blockchain de 05/11/2026).
            if wallet.hasPassphrase, passphraseConfirmada { wallet.passphraseConfirmedAt = .now }
            if wallet.hasPassphrase, cardanoAntiga { wallet.legacyCardanoPassphrase = true }
            metadata.wallets.append(wallet)
            // A mesma conta de volta (removida e importada de novo nesta sessao) volta a ter os avisos de ordem.
            VigiaDeOrdens.lembrar(donos: Self.donosEVM(wallet))
            if selecionar || metadata.selectedWalletID == nil { metadata.selectedWalletID = id }
            return wallet
        }
            // A Tron e as outras redes dela ja, logo depois de gravar, como o iOS: travar entre aqui e a tela nao a deixa sem
            // conferencia, e a marca de uma previa com um operador so sai com todos os que respondem vendo a conta limpa (auditoria 8).
            // A carteira criada aqui nao tem o que ler, e a consulta so entregaria os enderecos novos aos operadores; so a
            // escolhida, como na rodada do dia (rodada 3).
            // O envelope tambem quando nao fica escolhido: a previa ja consultou a EVM e a Tron dele, deste IP, segundos antes
            // (rodada 4 da auditoria 8), como no iOS.
            // A que passa a ser escolhida: o que ainda consultava a de antes para (rodada 4 da auditoria 8). O envelope que nao
            // fica escolhido tambem: conferido agora, ele nao sai junto com a rodada da escolhida.
            if metadata.selectedWalletID == salva.id || origem == .importedEnvelope { pararConferencias(mantendo: salva.id) }
            // A criada com as palavras escolhidas tambem: a frase pode ser a de outra pessoa (rodada 6 da auditoria 8).
            if origem != .created || palavrasEscolhidas, metadata.selectedWalletID == salva.id || origem == .importedEnvelope {
                // So a sem passphrase entra na excecao da pausa: a com passphrase nunca sai junto com outra (rodada 5).
                if !salva.hasPassphrase { trava.withLock { _ = primeirasConferencias.insert(salva.id) } }
                _ = conferirTron(salva.id)
                conferirControle(salva.id)
                conferirVersaoTON(salva.id)
            }
            return salva
        } catch Falha.jaImportada(let nome) {
            if gravada { try? Chaves.wallets.delete(id) }
            // A delegacao que a previa viu vale para a carteira que ja estava, e ela e conferida (rodada 5 da auditoria 8), como no iOS.
            // So se for a mesma conta EVM: a digital tem 4 bytes, e uma frase moida com a digital da vitima marcava a carteira dela.
            let evmNova = Set(contas.filter { Chain.find($0.chainID)?.family == .evm }.map { $0.address.lowercased() })
            if let existente = metadata.wallets.first(where: { $0.fingerprint == digital.hex && !$0.isWatchOnly }),
               evmNova.isSubset(of: Set(existente.accounts.map { $0.address.lowercased() })) {
                let achado = Importacao.consumirPreviaEVM(contas)
                // A Tron que a previa viu tambem: a conferencia dela, e a marca so com dois de acordo (rodada 6), como no iOS.
                if tronComOutraChave || achado != nil {
                    if let achado {
                        try? alterar { metadata in
                            guard let indice = metadata.wallets.firstIndex(where: { $0.id == existente.id }) else { return }
                            metadata.wallets[indice].foreignControl = ForeignControlCheck.apply([achado.chain.id: .foreign(achado.control)],
                                                                                                to: metadata.wallets[indice].foreignControl, startingFrom: nil)
                        }
                        // A importacao e recusada, e a tela nao recarrega sozinha: o aviso tira o endereco marcado dela (rodada 9).
                        Eventos.emitir("estado", Data("{}".utf8))
                    }
                    _ = conferirTron(existente.id)
                    conferirControle(existente.id)
                }
            }
            throw Falha.jaImportada(nome)
        } catch {
            if gravada { try? Chaves.wallets.delete(id) }
            throw error
        }
    }

    /// A carteira da 25a palavra a partir de outra (o `addPassphraseWallet` do iOS): o cofre abre a
    /// frase da base, junta a passphrase e guarda a carteira nova, sem a frase aparecer. A mesma frase
    /// com a mesma passphrase e a mesma carteira: se ela ja esta aqui, so passa a ser a escolhida.
    /// Criar e uma porta de chute (a passphrase certa reabre a que existe): toda tentativa conta, numa
    /// espera mais curta que zera depois de um dia sem tentar. E por aqui que o dono que esqueceu a
    /// passphrase tenta lembrar (pedido do dono, 25/10/2026).
    func abrirComPassphrase(base id: UUID, passphrase: SecureBytes, nome: String, credencial: Credencial) throws -> (WalletMeta, jaAberta: Bool) {
        defer { passphrase.wipe() }
        guard !adicionarBloqueado else {
            credencial.zerar()
            throw Falha.bloqueioLigado
        }
        guard let base = metadata.wallets.first(where: { $0.id == id }), case .phrase(let palavras) = base.kind else {
            credencial.zerar()
            throw Falha.carteiraNaoEncontrada
        }
        // A base e sempre a carteira sem passphrase: a conta de tentativas da porta de criar fica por
        // frase, e trocar de base nao a zera (revisao de seguranca do Android de 26/10/2026).
        guard !base.hasPassphrase else {
            credencial.zerar()
            throw Falha.baseComPassphrase
        }
        // Passphrase vazia seria a carteira de sempre marcada como "com passphrase": o assinador recusa
        // passphrase vazia (revisao de blockchain de 26/10/2026).
        guard passphrase.count > 0 else {
            credencial.zerar()
            throw Falha.passphraseVazia
        }
        guard PortaDaPassphrase.escrevivel(passphrase) else {
            credencial.zerar()
            throw Falha.passphraseInvisivel
        }
        guard PortaDaPassphrase.cabe(passphrase) else {
            credencial.zerar()
            throw Falha.passphraseLonga
        }
        // O autoteste antes da porta (que conta a tentativa) e da RK; a derivacao, antes de gravar (revisao da decima
        // terceira passada).
        do { try DerivationSelfTest.require() } catch { credencial.zerar(); throw error }
        do { try PortaDaPassphrase.comecar(id, criacao: true) } catch { credencial.zerar(); throw error }
        let novo = UUID()
        let contas: [DerivedAccount]
        let digital: [UInt8]
        let gravada: Bool
        let conhecidas = Set(metadata.wallets.filter { !$0.isWatchOnly }.map(\.fingerprint))
        do {
            (contas, digital, gravada) = try comChaveRaiz(credencial) { rk in
                let original = try Chaves.wallets.open(walletID: id, rk: rk)
                defer { original.wipe() }
                let entropia = SecureBytes(capacity: original.entropy.count)
                original.entropy.withUnsafeBytes { entropia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
                // A 25a palavra em NFKD, como a importacao grava: a chave da Cardano (Icarus) usa os
                // bytes como estao, e "ação" do teclado (NFC) daria outra conta.
                let normalizada: SecureBytes
                if passphrase.withUnsafeBytes({ raw in raw.contains { $0 >= 0x80 } }) {
                    normalizada = BIP39.nfkd(passphrase)
                } else {
                    normalizada = SecureBytes(capacity: passphrase.count)
                    passphrase.withUnsafeBytes { normalizada.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
                }
                let secret = WalletSecret(entropy: entropia, language: original.language, passphrase: normalizada)
                defer { secret.wipe() }
                let derivadas = try AccountDeriver.derive(secret)
                // A mesma frase com a mesma passphrase ja aberta: nada e gravado de novo.
                guard !conhecidas.contains(derivadas.fingerprint.hex) else { return (derivadas.accounts, derivadas.fingerprint, false) }
                // De novo com o cofre aberto, logo antes de gravar: a politica pode ter mudado no meio.
                guard !Self.palavrasBloqueadas(Chaves.root) else { throw Falha.bloqueioLigado }
                try Chaves.wallets.save(secret, walletID: novo, rk: rk)
                return (derivadas.accounts, derivadas.fingerprint, true)
            }
        } catch {
            PortaDaPassphrase.devolver(id, criacao: true)
            throw error
        }
        // Conta na espera, sem o aviso de passphrase errada: aqui nada errou.
        PortaDaPassphrase.errou(id, criacao: true)
        let resultado: (WalletMeta, jaAberta: Bool)
        do { resultado = try alterar { metadata -> (WalletMeta, jaAberta: Bool) in
            if let existente = metadata.wallets.first(where: { $0.fingerprint == digital.hex && !$0.isWatchOnly }) {
                if gravada { try? Chaves.wallets.delete(novo) }
                // A digital tem 4 bytes: o endereco da Bitcoin confirma que e a mesma, e uma carteira de outra frase com a
                // mesma digital nunca e escolhida no lugar (revisao dos 3 agentes, 08/11/2026).
                guard existente.account(.bitcoin)?.address == contas.first(where: { $0.chainID == Chain.bitcoin.id })?.address else {
                    throw Falha.jaImportada(existente.name)
                }
                metadata.selectedWalletID = existente.id
                return (existente, true)
            }
            guard gravada else { throw Falha.listaMudou }
            var wallet = WalletMeta(
                id: novo, name: Self.nomeUnico(nome, origem: base.origin, em: metadata), kind: .phrase(wordCount: palavras), origin: base.origin,
                createdAt: .now, accounts: contas, fingerprint: digital.hex, hasPassphrase: true, backupConfirmedAt: base.backupConfirmedAt
            )
            // As palavras escolhidas da base valem para a com passphrase, como no iOS (rodada 6 da auditoria 8).
            wallet.chosenWords = base.chosenWords
            metadata.wallets.append(wallet)
            // A mesma conta de volta (removida e importada de novo nesta sessao) volta a ter os avisos de ordem.
            VigiaDeOrdens.lembrar(donos: Self.donosEVM(wallet))
            metadata.selectedWalletID = novo
            return (wallet, false)
        } } catch {
            // A carteira guardada sai se a lista nao gravou, como em `adicionarCarteira`.
            if gravada { try? Chaves.wallets.delete(novo) }
            throw error
        }
        if !resultado.jaAberta { trava.withLock { recemAbertas[resultado.0.id] = PINPolicy.uptime } }
        return resultado
    }

    /// As carteiras com passphrase abertas por este processo, com o instante no relogio monotono:
    /// so elas podem sair sem PIN pela busca de movimento. O id que o Kotlin manda e o `createdAt`
    /// (relogio de parede, que se atrasa a mao) nao bastam (revisao de seguranca do Android de 26/10/2026).
    private var recemAbertas: [UUID: TimeInterval] = [:]

    /// Nome repetido ganha a origem junto.
    private static func nomeUnico(_ nome: String, origem: WalletMeta.Origin, em metadata: Metadata) -> String {
        let usados = Set(metadata.wallets.map { esqueleto($0.name) })
        guard usados.contains(esqueleto(nome)) else { return nome }
        let marca = origem == .importedEnvelope ? Textos.envelope : Textos.importada
        var candidato = "\(nome) (\(marca))"
        var numero = 2
        while usados.contains(esqueleto(candidato)) {
            candidato = "\(nome) (\(marca) \(numero))"
            numero += 1
        }
        return String(candidato.prefix(48))
    }

    /// O nome como o olho le: sem acento, em minusculas e sem espacos nas pontas. "principаl" com
    /// um "а" cirilico e "principal" dao o mesmo.
    static func esqueleto(_ nome: String) -> String {
        let latino = nome.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? nome
        return latino.trimmingCharacters(in: .whitespaces).lowercased()
    }

    func adicionarObservacao(rede: Chain, endereco: String, nome: String) throws -> WalletMeta {
        let redes = rede.family == .evm ? Chain.evmChains : [rede]
        let contas = redes.map {
            DerivedAccount(chainID: $0.id, path: DerivationPath(components: []), address: endereco, publicKey: [], accountXPub: nil)
        }
        let wallet = WalletMeta(
            id: UUID(), name: nome, kind: .watch(chainID: rede.id), origin: .watch, createdAt: .now,
            accounts: contas, fingerprint: nil, hasPassphrase: false, backupConfirmedAt: nil
        )
        try alterar { metadata in
            metadata.wallets.append(wallet)
            // A mesma conta de volta (removida e importada de novo nesta sessao) volta a ter os avisos de ordem.
            VigiaDeOrdens.lembrar(donos: Self.donosEVM(wallet))
            metadata.selectedWalletID = wallet.id
        }
        return wallet
    }

    func selecionar(_ id: UUID) throws {
        // A rodada de outra carteira para: a que passa a ser escolhida nao e consultada junto com ela (rodada 2 da auditoria 8).
        if metadata.selectedWalletID != id { pararConferencias(mantendo: id) }
        try alterar { metadata in
            guard metadata.wallets.contains(where: { $0.id == id }) else { throw Falha.carteiraNaoEncontrada }
            metadata.selectedWalletID = id
        }
        // A conferencia do dia e so da carteira em uso: a que passa a ser escolhida e conferida agora, se ja for a hora dela.
        agendarConferencias()
    }

    func atualizar(_ id: UUID, _ corpo: (inout WalletMeta) -> Void) throws {
        try alterar { metadata in
            guard let indice = metadata.wallets.firstIndex(where: { $0.id == id }) else { throw Falha.carteiraNaoEncontrada }
            corpo(&metadata.wallets[indice])
        }
    }

    func aceitarResponsabilidade(versao: Int) throws {
        try alterar {
            $0.responsibilityAccepted = .now
            $0.responsibilityVersion = versao
        }
    }

    /// A carteira so sai da lista depois de o armazenamento confirmar que a frase saiu.
    /// Os enderecos EVM da carteira, em hex minusculo sem `0x`: o dono que o UID da CoW traz.
    static func donosEVM(_ meta: WalletMeta) -> Set<String> {
        Set(Chain.all.filter { $0.family == .evm }.compactMap { rede in
            meta.account(rede).map { $0.address.lowercased().replacingOccurrences(of: "0x", with: "") }
        })
    }

    /// Remove uma carteira. A com as palavras so com a presenca inteira (PIN e rosto, ou o Super Security), conferida aqui, na
    /// propria remocao, e a credencial abrindo a chave raiz antes, como o `remove(_:credential:)` do iOS; antes, so o
    /// despachante conferia, e um metodo novo que chamasse a remocao pulava (rodada 3 da auditoria 8). Quem decide se e so de
    /// olhar e a lista, e nao quem chama.
    func remover(_ id: UUID, credencial: Credencial?) throws {
        let antes = metadata
        guard let wallet = antes.wallets.first(where: { $0.id == id }) else {
            credencial?.zerar()
            throw Falha.carteiraNaoEncontrada
        }
        if !wallet.isWatchOnly {
            guard let credencial else { throw Falha.remocaoFalhou }
            switch credencial {
            case .pinEBiometria, .reforcado: try comChaveRaiz(credencial) { _ in }
            case .pin, .biometria:
                credencial.zerar()
                throw RootKeyVault.Failure.biometryRequired
            }
            // Travado depois da biometria (o botao de ligar logo em seguida), a chave nao sai (rodada 14).
            guard fase == .unlocked else { throw Falha.travada }
            try? Chaves.wallets.delete(id)
            guard Chaves.wallets.probe(id) == .absent else { throw Falha.remocaoFalhou }
        } else {
            credencial?.zerar()
        }
        // A copia de um endereco da carteira que sai do aparelho sai ja, com a chave fora: uma gravacao que falhe ou um travar no
        // meio nao a deixam para tras (rodadas 13 e 14), como o iPhone.
        Sessao.retirarCopia(Set(wallet.accounts.map(\.address)))
        // O aviso de recebimento deixa de vigiar os enderecos dela ja, sem a chave dos metadados: com o app travado no meio, o
        // trabalho de hora em hora seguia consultando a removida (rodada 16), como o iPhone, que regrava a lista na hora.
        // So a carteira com frase: a de observacao nunca entra no arquivo, e esquecer a dela tirava a conta da carteira de verdade
        // com o mesmo endereco, que ficava sem base de saldo (rodada 17, regressao da 16).
        if !wallet.isWatchOnly { AvisoDeRecebimento.esquecer(wallet) }
        var ficouSemCarteira = false
        // As ordens assinadas guardadas e os avisos de ordem limite dela: o UID traz o endereco, e o arquivo dos
        // avisos abre com o app travado (quarta passada da auditoria de 03/11/2026).
        // So os enderecos que nenhuma carteira que fica usa (uma carteira so para ver o mesmo endereco segue com os
        // avisos dela).
        // A lista lida no comeco: travado no meio, a de agora vem vazia (rodada 15).
        let donos = Self.donosEVM(wallet).subtracting(antes.wallets.filter { $0.id != id }.flatMap(Self.donosEVM))
        let guardadas = Set((antes.signedOrders ?? []).filter { $0.walletID == id }.map(\.id))
        // Os donos esquecidos antes de gravar, e as renovacoes lidas dentro da gravacao: um registro que caisse entre a
        // leitura e a marca deixava um aviso de fim do prazo que ninguem tirava (revisao da decima terceira passada).
        VigiaDeOrdens.esquecer(donos: donos, ids: guardadas)
        var renovadas: [String] = []
        // Tudo o que leva enderecos ou o rastro desta carteira sai junto (revisao de seguranca de
        // 24/10/2026): o historico, as transacoes em transito, as ordens a refazer e a conta de
        // passphrases erradas dela. Numa funcao so: na gravacao de agora e, se o app travar no meio, na do destravar (rodada 14).
        // A edicao de ordem guardada pode ser desta carteira (revisao dos 3 agentes, 17/11/2026).
        Troca.esquecerEdicaoSuspensa()
        let tirar: (inout Metadata) -> Void = { metadata in
            metadata.wallets.removeAll { $0.id == id }
            metadata.balanceCache[id] = nil
            metadata.activityCache?[id] = nil
            metadata.activityFetched?[id] = nil
            let prefixo = id.uuidString + "|"
            metadata.pendingEVM = metadata.pendingEVM?.filter { !$0.key.hasPrefix(prefixo) }
            metadata.unsureSends?.removeAll { $0.wallet == id }
            metadata.limitRenewals?.removeAll { $0.walletID == id }
            metadata.signedOrders?.removeAll { $0.walletID == id }
            Saldos.podarPorAtivo(&metadata)
            PortaDaPassphrase.esquecer(&metadata, id)
            if metadata.selectedWalletID == id { metadata.selectedWalletID = metadata.wallets.first?.id }
        }
        do {
            try alterar { metadata in
                guard metadata.wallets.contains(where: { $0.id == id }) else { throw Falha.carteiraNaoEncontrada }
                renovadas = (metadata.limitRenewals ?? []).filter { $0.walletID == id }.map(\.orderID)
                tirar(&metadata)
                ficouSemCarteira = metadata.wallets.isEmpty
            }
        } catch Falha.travada {
            // O app travou entre apagar a chave e gravar a lista: a lista se acerta no proximo destravar, em vez de mostrar uma
            // carteira sem chave, como o descartar (rodada 14 da auditoria 8). Era a ultima: o app apaga tudo no destravar.
            // A decisao vem da lista depois dos pendentes, no destravar (rodada 15): a marca liga sempre.
            trava.withLock { apagarAoDestravar = true }
            alterarOuDepois(tirar)
            // O que o caminho normal faz depois de gravar, ja aqui: os avisos de fim do prazo dela e as consultas em voo com os
            // enderecos dela (rodada 15).
            for ordem in (antes.limitRenewals ?? []).filter({ $0.walletID == id }).map(\.orderID) { VigiaDeOrdens.desmarcarFimDoPrazo(ordem) }
            trava.withLock {
                cancelarConferencias(de: id)
                if carteiraDaRodada == id {
                    rodadaDeControle?.cancel()
                    rodadaDeControle = nil
                    carteiraDaRodada = nil
                }
            }
            Saldos.shared.esquecer()
            Atividade.shared.esquecer(carteira: id)
            Renovacoes.esquecer(carteira: id)
            throw Falha.travada
        }
        // A ultima carteira saiu: o app volta a ser como recem-instalado, PIN e ajustes inclusive
        // (pedido do dono, 24/10/2026). Nada da carteira de antes fica para a proxima. A decisao vem
        // de dentro da gravacao: relida depois, a lista podia ser a vazia de um travar() no meio
        // (caca de bugs de 25/10/2026, B5).
        // Os avisos de refazer quando vencer dela tambem saem (quinta passada de 03/11/2026).
        for ordem in renovadas { VigiaDeOrdens.desmarcarFimDoPrazo(ordem) }
        // O que esta na memoria sai tambem: uma leitura em curso dela nao grava mais nada.
        Saldos.shared.esquecer()
        Atividade.shared.esquecer(carteira: id)
        Renovacoes.esquecer(carteira: id)
        // As consultas da removida param, e a rodada do dia, se for dela (rodada 4 da auditoria 8), como no iOS.
        trava.withLock {
            cancelarConferencias(de: id)
            if carteiraDaRodada == id {
                rodadaDeControle?.cancel()
                rodadaDeControle = nil
                carteiraDaRodada = nil
            }
        }
        if ficouSemCarteira { apagarTudo() }
        // O que ainda consultava a de antes para, mantendo a escolhida (rodada 4 da auditoria 8), como no iOS.
        else { pararConferencias(mantendo: metadata.selectedWalletID) }
    }

    /// A carteira com passphrase recem-aberta em que a busca nao achou movimento nenhum, quando o dono
    /// prefere tentar outra passphrase (o discardFreshPassphraseWallet do iOS, pedido do dono,
    /// 25/10/2026): sai sem pedir o PIN de novo, e a carteira de antes volta a ser a escolhida. Nao ha o
    /// que perder: nunca recebeu nada, e a mesma frase com a mesma passphrase a abre de novo, igual. So
    /// vale para uma carteira com passphrase criada agora, e nunca para a ultima.
    func descartarCarteiraComPassphrase(_ id: UUID, anterior: UUID?) throws {
        guard fase == .unlocked else { throw Falha.travada }
        guard let aberta = trava.withLock({ recemAbertas[id] }), PINPolicy.uptime - aberta < 3600,
              let wallet = metadata.wallets.first(where: { $0.id == id }), wallet.hasPassphrase, !wallet.isWatchOnly,
              metadata.wallets.count > 1 || trava.withLock({ recemImportadas.contains(id) })
        else { throw Falha.carteiraNaoEncontrada }
        try? Chaves.wallets.delete(id)
        guard Chaves.wallets.probe(id) == .absent else { throw Falha.remocaoFalhou }
        // A copia de um endereco da descartada sai ja, com a chave fora (rodadas 13 e 14), como no iOS.
        Sessao.retirarCopia(Set(wallet.accounts.map(\.address)))
        // A edicao de ordem guardada pode ser desta carteira (revisao dos 3 agentes, 17/11/2026).
        Troca.esquecerEdicaoSuspensa()
        let tirar: (inout Metadata) -> Void = { metadata in
            metadata.wallets.removeAll { $0.id == id }
            metadata.balanceCache[id] = nil
            metadata.activityCache?[id] = nil
            metadata.activityFetched?[id] = nil
            // O que leva o endereco dela: as transacoes em transito e as ordens guardadas (quarta passada de 03/11/2026).
            metadata.pendingEVM = metadata.pendingEVM?.filter { !$0.key.hasPrefix(id.uuidString + "|") }
            metadata.unsureSends?.removeAll { $0.wallet == id }
            metadata.signedOrders?.removeAll { $0.walletID == id }
            Saldos.podarPorAtivo(&metadata)
            PortaDaPassphrase.esquecer(&metadata, id)
            let volta = anterior.flatMap { anterior in metadata.wallets.contains { $0.id == anterior } ? anterior : nil }
            metadata.selectedWalletID = volta ?? metadata.wallets.first?.id
        }
        // O app travou entre apagar o registro e gravar a lista: a lista se acerta no proximo destravar, em vez de mostrar
        // uma carteira sem chave (revisao de seguranca, 08/11/2026).
        do { try alterar { tirar(&$0) } } catch Falha.travada {
            alterarOuDepois(tirar)
            throw Falha.travada
        }
        // O que ainda consultava a carteira descartada para, antes de a de volta ser consultada (rodada 3 da auditoria 8), e a
        // rodada do dia da de volta e agendada de novo (rodada 4). As da descartada antes, ja fora da lista (rodada 5).
        trava.withLock { cancelarConferencias(de: id) }
        pararConferencias(mantendo: metadata.selectedWalletID)
        agendarConferencias()
        trava.withLock {
            recemAbertas[id] = nil
            recemImportadas.remove(id)
        }
        Saldos.shared.esquecer()
        Atividade.shared.esquecer(carteira: id)
        Renovacoes.esquecer(carteira: id)
    }

    /// A carteira com passphrase importada agora (`Importacao.importarComPassphrase`): a busca de movimento pode tira-la sem
    /// PIN, como a aberta pelos Ajustes.
    func marcarRecemAberta(_ id: UUID) {
        trava.withLock {
            recemAbertas[id] = PINPolicy.uptime
            recemImportadas.insert(id)
        }
    }

    /// As carteiras com passphrase gravadas pela importacao neste processo: podem sair pela busca de movimento mesmo sendo a
    /// unica, a primeira do aparelho, com as palavras ainda na tela de importar (revisao dos 3 agentes, 08/11/2026).
    private var recemImportadas: Set<UUID> = []

    /// A tarefa que terminou sai da lista so se nao foi cancelada: a pausa cancela e tira sob a mesma trava, e a tarefa velha
    /// que passava do `guard` antes da pausa tirava a nova (rodada 3 da auditoria 8).
    private func esquecerTron(_ id: UUID) {
        trava.withLock { if !Task.isCancelled { verificacoesTron[id] = nil } }
    }

    private var verificacoesTron: [UUID: Task<Bool?, Never>] = [:]

    /// Quem controla a conta da Tron de uma carteira que acabou de abrir por aqui (o golpe da "frase com saldo", como a
    /// previa da importacao faz): outra chave no controle marca a carteira, e o Receber da Tron fecha. Uma conferencia por
    /// carteira, que segue mesmo se a tela fechar; sem rede, nada a dizer, e o envio confere de novo (o checkTronControl do iOS).
    /// Devolve o aviso na hora (outra chave vista), ou nil quando a conferencia foi cancelada (rodada 4 da auditoria 8), como no iOS.
    func conferirTron(_ id: UUID) -> Task<Bool?, Never> {
        // Lido antes: `metadata` pega a trava, que nao entra duas vezes. Sem a carteira (o app travou e a lista esta vazia),
        // nada fica guardado: a proxima chamada confere.
        // A Tron desligada nos Ajustes nao e perguntada (rodada 1 da auditoria 8).
        guard !metadata.settings.disabledChainIDs.contains(Chain.tron.id),
              let endereco = metadata.wallets.first(where: { $0.id == id })?.account(.tron)?.address, let tron = TronAddress(endereco) else {
            return Task { false }
        }
        return trava.withLock {
            if let andando = verificacoesTron[id] { return andando }
            // Ja marcada, "limpa" so com todos os operadores de acordo (rodada 1 da auditoria 8).
            let marcada = metadados.wallets.first(where: { $0.id == id })?.tronForeignControl == true
            let tarefa = Task<Bool?, Never> {
                // A tela das palavras deixa a rede em silencio: a conferencia espera ela fechar (rodada 7), como no iOS.
                await HTTPClient.shared.whenAudible()
                guard !Task.isCancelled else { return nil }
                let leitura = try? await TronReader.shared.ownerControlCheck(owner: tron, everyone: marcada)
                // Parada (a carteira com passphrase abriu), sai sem gravar e sem mexer na lista, que ja pode ter a nova.
                guard !Task.isCancelled else { return nil }
                // Terminada, a proxima chamada pergunta de novo (a do destravar, um dia depois). Sem resposta, nada fica
                // guardado (revisao, 08/11/2026).
                Sessao.shared.esquecerTron(id)
                Sessao.shared.fimDaConferencia(id)
                guard let leitura else { return false }
                // O aviso na hora basta um operador ver; a marca guardada so entra com os dois de acordo, e sai com todos os
                // que respondem vendo a conta limpa, e pelo menos tres (auditoria 8 e rodadas 1 e 2). "Limpa" so tira a marca
                // que ja estava quando a conferencia comecou. Travado no meio, a marca espera o proximo destravar.
                if let acordo = leitura.agreed {
                    // A copia do endereco da Tron com outra chave sai ja, mesmo travado (rodada 12), como no iOS.
                    if acordo.isCompromised { Sessao.retirarCopia(Sessao.shared.metadata.wallets.formas(de: endereco, on: .tron)) }
                    // Lida com dois de acordo: a data do dia da conferencia das outras redes pode contar com ela (rodada 7).
                    Sessao.shared.trava.withLock { Sessao.shared.tronLidaEm[id] = Date() }
                    let marca: Bool? = acordo.isCompromised ? true : nil
                    Sessao.shared.alterarOuDepois { metadata in
                        guard let indice = metadata.wallets.firstIndex(where: { $0.id == id }) else { return }
                        if acordo.isCompromised || marcada { metadata.wallets[indice].tronForeignControl = marca }
                        // Lida de verdade, com dois de acordo: a Tron conta como lida (rodada 6 da auditoria 8), como no iOS.
                        metadata.wallets[indice].foreignControlRead = (metadata.wallets[indice].foreignControlRead ?? []).union([Chain.tron.id])
                    }
                }
                return leitura.shown.isCompromised
            }
            verificacoesTron[id] = tarefa
            return tarefa
        }
    }

    private var verificacoesDeControle: [UUID: Task<Bool, Never>] = [:]
    private var rodadaDeControle: Task<Void, Never>?

    /// Outra chave, conta ou contrato no controle das outras contas de uma carteira (`ForeignControlCheck`; o
    /// `checkForeignControl` do iOS, auditoria 8, 14/11/2026): rede por rede, a marca entra com dois operadores de acordo e
    /// so sai com todos os que respondem vendo a conta limpa, e pelo menos tres. A Tron fica com `conferirTron`. `redes`: so
    /// estas, como o Receber confere a dele.
    @discardableResult
    /// Devolve se a conferencia foi ate o fim: a cancelada pela pausa nao conta como feita (rodada 4 da auditoria 8), como no iOS.
    func conferirControle(_ id: UUID, redes: Set<String>? = nil) -> Task<Bool, Never> {
        guard let carteira = metadata.wallets.first(where: { $0.id == id }), !carteira.isWatchOnly else {
            trava.withLock { _ = primeirasConferencias.remove(id) }
            return Task { true }
        }
        // So as redes ligadas nos Ajustes (rodada 1 da auditoria 8).
        let desligadas = metadata.settings.disabledChainIDs
        let contas = carteira.accounts.filter {
            $0.chainID != Chain.tron.id && !desligadas.contains($0.chainID) && (redes?.contains($0.chainID) ?? true)
        }
        // Sem conta para ler, a completa segue mesmo assim: a data do dia entra com a Tron lida (rodada 8), como no iOS.
        guard !contas.isEmpty || redes == nil else { return Task { true } }
        // A de algumas redes (o Receber, a ponte) tambem uma por vez (rodada 3 da auditoria 8), como no iOS. Com o endereco na
        // chave: a releitura da W5 nao reaproveita a do Receber da TON aberto com a V4R2 (rodada 8).
        let chaveDasRedes = redes.map { _ in "\(id.uuidString)|" + contas.map { "\($0.chainID):\($0.address)" }.sorted().joined(separator: ",") }
        return trava.withLock {
            if redes == nil, let andando = verificacoesDeControle[id] { return andando }
            if let chaveDasRedes, let andando = verificacoesDeRedes[chaveDasRedes] { return andando }
            let inicio = carteira.foreignControl
            let marcadas = Set((inicio ?? [:]).keys)
            let tarefa = Task<Bool, Never> {
                // A tela das palavras deixa a rede em silencio: a conferencia espera ela fechar (rodada 7), como no iOS.
                await HTTPClient.shared.whenAudible()
                guard !Task.isCancelled else { return false }
                let vereditos = await ForeignControlCheck.check(contas, marked: marcadas)
                guard !Task.isCancelled else { return false }
                // A copia de um endereco com outra chave sai ja, mesmo com o app travado na frente (rodada 12), como no iOS.
                // Tambem a mesma conta escrita de outra forma em outra carteira (a TON so de observacao; revisao dos tres agentes).
                let todas = Sessao.shared.metadata.wallets
                Sessao.retirarCopia(contas.reduce(into: Set<String>()) { saida, conta in
                    guard case .foreign = vereditos[conta.chainID], let rede = Chain.find(conta.chainID) else { return }
                    saida.formUnion(todas.formas(de: conta.address, on: rede))
                })
                // A marca e as redes lidas entram ja; so a data do dia espera a Tron, embaixo (rodada 8), como no iOS.
                Sessao.shared.alterarOuDepois { metadata in
                    guard let indice = metadata.wallets.firstIndex(where: { $0.id == id }) else { return }
                    metadata.wallets[indice].foreignControl = ForeignControlCheck.apply(vereditos, to: metadata.wallets[indice].foreignControl,
                                                                                        startingFrom: inicio)
                    // As redes que responderam de verdade contam como lidas, uma por uma (rodada 6 da auditoria 8), e so pelo
                    // endereco que a carteira ainda tem: a TON trocada para a W5 no meio nao conta pela leitura da V4R2 (rodada 7).
                    let agora = metadata.wallets[indice]
                    let lidas = Set(vereditos.compactMap { rede, veredito -> String? in
                        guard veredito != .unknown,
                              contas.first(where: { $0.chainID == rede })?.address == agora.accounts.first(where: { $0.chainID == rede })?.address
                        else { return nil }
                        return rede
                    })
                    if !lidas.isEmpty { metadata.wallets[indice].foreignControlRead = (metadata.wallets[indice].foreignControlRead ?? []).union(lidas) }
                }
                // A data do dia tambem espera a Tron, quando ela tem o que ler: lida com dois de acordo nesta rodada (rodada 7),
                // como no iOS. A Tron que corre junto (a do `adicionarCarteira`) e esperada, com esta ainda na lista: travar,
                // pausar e apagar tudo a cancelam tambem na espera (rodada 8).
                if redes == nil, let tron = Sessao.shared.trava.withLock({ Sessao.shared.verificacoesTron[id] }) { _ = await tron.value }
                guard !Task.isCancelled else { return false }
                if redes == nil {
                    Sessao.shared.esquecerControle(id)
                    Sessao.shared.trava.withLock { _ = Sessao.shared.primeirasConferencias.remove(id) }
                }
                if let chaveDasRedes { Sessao.shared.trava.withLock { if !Task.isCancelled { Sessao.shared.verificacoesDeRedes[chaveDasRedes] = nil } } }
                // Terminada a primeira (a do envelope, que pausou a escolhida), a rodada do dia da escolhida volta (rodada 5), e
                // tambem depois de qualquer outra de outra carteira (rodada 7), como no iOS.
                Sessao.shared.fimDaConferencia(id)
                let tronDevida = !desligadas.contains(Chain.tron.id) && carteira.account(.tron) != nil
                let tronLida = Sessao.shared.trava.withLock { Sessao.shared.tronLidaEm[id] }.map { Date().timeIntervalSince($0) < 600 } ?? false
                // Sem resposta nenhuma (sem rede), a conferencia do dia fica para o proximo destravar. Sem conta com leitura (so
                // o Bitcoin, a Sui ou a Cardano ligadas), conta como feita, e a rodada nao volta a cada destravar (rodada 6).
                let responderam = (vereditos.values.contains { $0 != .unknown }
                    || !contas.contains { Chain.find($0.chainID).map(ForeignControlCheck.reads) ?? false })
                    && (!tronDevida || tronLida)
                if redes == nil, responderam {
                    // So com as mesmas contas lidas: a TON trocada para a W5 no meio tirou a data, e esta conferencia leu a V4R2
                    // (rodada 9 da auditoria 8), como no iOS.
                    let lidas = Set(contas.map { "\($0.chainID):\($0.address)" })
                    Sessao.shared.alterarOuDepois { metadata in
                        guard let indice = metadata.wallets.firstIndex(where: { $0.id == id }) else { return }
                        let agora = Set(metadata.wallets[indice].accounts
                            .filter { $0.chainID != Chain.tron.id && !desligadas.contains($0.chainID) }
                            .map { "\($0.chainID):\($0.address)" })
                        guard agora == lidas else { return }
                        metadata.wallets[indice].foreignControlCheckedAt = Date()
                    }
                }
                return true
            }
            if redes == nil { verificacoesDeControle[id] = tarefa }
            if let chaveDasRedes { verificacoesDeRedes[chaveDasRedes] = tarefa }
            return tarefa
        }
    }

    private var verificacoesDeRedes: [String: Task<Bool, Never>] = [:]

    private func esquecerControle(_ id: UUID) {
        trava.withLock { if !Task.isCancelled { verificacoesDeControle[id] = nil } }
    }

    /// A carteira TON na W5 (`TONDiscovery`; o `checkTONVersion` do iOS, auditoria 8, 14/11/2026): uma vez por carteira, depois
    /// de gravar ou abrir, e no destravar para a que ja estava aqui. A conta da V4R2 sem movimento troca pela W5 da mesma chave
    /// que teve, e o saldo guardado da TON sai. Sem resposta, a proxima vez pergunta de novo.
    @discardableResult
    func conferirVersaoTON(_ id: UUID) -> Task<Void, Never> {
        guard let carteira = metadata.wallets.first(where: { $0.id == id }), !carteira.isWatchOnly, carteira.tonVersionChecked != true,
              !metadata.settings.disabledChainIDs.contains(Chain.ton.id), let ton = carteira.account(.ton) else { return Task {} }
        // Uma por carteira: abrir, gravar e o destravar chamavam juntas, e a TON era perguntada duas ou tres vezes (rodada 2).
        return trava.withLock {
            if let andando = verificacoesTON[id] { return andando }
            let tarefa = Task<Void, Never> { await Sessao.shared.versaoTON(id, ton) }
            verificacoesTON[id] = tarefa
            return tarefa
        }
    }

    private var verificacoesTON: [UUID: Task<Void, Never>] = [:]
    /// Quando a Tron de cada carteira foi lida com dois de acordo, so na memoria. Com a trava (rodada 7 da auditoria 8).
    private var tronLidaEm: [UUID: Date] = [:]

    /// Terminada uma conferencia de outra carteira (a primeira do envelope, a Tron, a TON, a releitura de uma rede), a rodada do
    /// dia da escolhida volta: ela desiste com outra conferencia no ar, e nada mais a armava (rodada 7), como no iOS.
    private func fimDaConferencia(_ id: UUID) {
        if metadata.selectedWalletID != id { agendarConferencias() }
    }

    private func versaoTON(_ id: UUID, _ ton: DerivedAccount) async {
        // A tela das palavras deixa a rede em silencio: a conferencia espera ela fechar (rodada 7), como no iOS.
        await HTTPClient.shared.whenAudible()
        guard !Task.isCancelled else { return }
        let resposta = await TONDiscovery.check(ton)
        guard !Task.isCancelled else { return }
        trava.withLock { if !Task.isCancelled { verificacoesTON[id] = nil } }
        fimDaConferencia(id)
        guard resposta != .unknown else { return }
        // A conta TON que muda de endereco e conferida de novo: a marca era a do endereco da V4R2 (rodada 1 da auditoria 8).
        defer { if case .switchTo = resposta { Sessao.shared.conferirControle(id, redes: [Chain.ton.id]) } }
        // A copia da V4R2 sai ja, mesmo travado (rodada 12), como no iOS.
        if case .switchTo = resposta { Sessao.retirarCopia([ton.address]) }
        Sessao.shared.alterarOuDepois { metadata in
            guard let indice = metadata.wallets.firstIndex(where: { $0.id == id }) else { return }
            if case .switchTo(let melhor) = resposta,
               let conta = metadata.wallets[indice].accounts.firstIndex(where: { $0.chainID == Chain.ton.id && $0.address == ton.address }) {
                metadata.wallets[indice].accounts[conta] = melhor
                metadata.balanceCache[id]?[Chain.ton.id] = nil
                // A W5 ainda nao foi lida: a TON volta a contar so depois da releitura dela (rodada 7), como no iOS. E a data do
                // dia sai: se a releitura nao ler (travada, ou sem resposta), a proxima rodada le tudo (rodada 8).
                metadata.wallets[indice].foreignControlRead?.remove(Chain.ton.id)
                metadata.wallets[indice].foreignControlCheckedAt = nil
            }
            metadata.wallets[indice].tonVersionChecked = true
        }
    }

    /// Uma vez por dia, ao destravar ou ao escolher a carteira: so a carteira em uso, e so as redes ligadas, como o saldo e a
    /// atividade (o `scheduleControlChecks` do iOS). Antes, todas as carteiras, uma atras da outra, do mesmo IP: o operador
    /// ligava uma a outra numa rodada so (rodada 1 da auditoria 8). Comeca depois de um tempo sorteado, de 30 s a 5 min. A
    /// carteira com passphrase so e conferida quando abre.
    /// A interface tira da area de transferencia a copia de um destes enderecos, se ainda e a dela (rodada 12 da auditoria 8): nao
    /// espera os metadados, que com o app travado so entram depois de destravar.
    static func retirarCopia(_ enderecos: Set<String>) {
        guard !enderecos.isEmpty, let json = try? JSONEncoder().encode(["enderecos": enderecos.sorted()]) else { return }
        Eventos.emitir("copia.retirar", json)
    }

    func agendarConferencias() {
        // Com a previa da importacao aberta, nao (rodada 6 da auditoria 8): ela agenda ao fechar.
        guard !trava.withLock({ previaAberta }) else { return }
        let metadata = self.metadata
        // A com passphrase so quando ainda nao terminou a primeira (travou no meio dela; rodada 4 da auditoria 8).
        guard let id = metadata.selectedWalletID, let carteira = metadata.wallets.first(where: { $0.id == id }),
              !carteira.isWatchOnly, !carteira.hasPassphrase || carteira.foreignControlCheckedAt == nil,
              carteira.foreignControlCheckedAt.map({ Date().timeIntervalSince($0) > ForeignControlCheck.interval }) ?? true
        else { return }
        let espera = ForeignControlCheck.checkDelay()
        trava.withLock {
            guard rodadaDeControle == nil else { return }
            vezDaRodada &+= 1
            let vez = vezDaRodada
            carteiraDaRodada = id
            rodadaDeControle = Task<Void, Never> {
                // A rodada parada nao apaga a nova (rodada 2 da auditoria 8).
                defer {
                    Sessao.shared.trava.withLock {
                        if Sessao.shared.vezDaRodada == vez {
                            Sessao.shared.rodadaDeControle = nil
                            Sessao.shared.carteiraDaRodada = nil
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(espera * 1_000_000_000))
                // Antes de cada passo: parada, travada ou com outra carteira escolhida, para.
                // Com a rede em silencio (a tela das palavras aberta), a rodada desiste em vez de esperar (rodada 8), como no iOS.
                let atual = { !Task.isCancelled && Sessao.shared.fase == .unlocked && Sessao.shared.metadata.selectedWalletID == id && !HTTPClient.shared.isQuiet }
                // Na saida, tambem com a conferencia de outra carteira no ar, e so se ainda for a hora (rodada 6), como no iOS.
                let devida = { Sessao.shared.metadata.wallets.first { $0.id == id }?.foreignControlCheckedAt.map { Date().timeIntervalSince($0) > ForeignControlCheck.interval } ?? true }
                guard atual(), devida(), !Sessao.shared.outrasConferindo(id) else { return }
                _ = await Sessao.shared.conferirTron(id).value
                guard atual() else { return }
                _ = await Sessao.shared.conferirControle(id).value
                guard atual() else { return }
                await Sessao.shared.conferirVersaoTON(id).value
            }
        }
    }

    /// A carteira da rodada do dia em andamento, e a vez dela: so a rodada que ainda e a atual se apaga no fim.
    private var carteiraDaRodada: UUID?
    private var vezDaRodada = 0

    /// A carteira com passphrase vai abrir: a rodada do dia para, para as duas nao serem consultadas juntas, do mesmo IP.
    /// `oculta`: quem abre e uma carteira com passphrase (ou a previa de uma), e entao nada e poupado. Sem dizer, vale a de
    /// `mantendo`; sem `mantendo`, nada e poupado (rodada 5 da auditoria 8), como no iOS.
    func pararConferencias(mantendo: UUID? = nil, oculta: Bool? = nil) {
        let escondendo = oculta ?? mantendo.flatMap { id in metadata.wallets.first { $0.id == id }?.hasPassphrase } ?? true
        trava.withLock {
            rodadaDeControle?.cancel()
            rodadaDeControle = nil
            carteiraDaRodada = nil
            // E toda consulta de outra carteira no ar, e nao so a da rodada: a importacao, o Receber e a ponte disparam as suas,
            // e seguiam junto com a da carteira que abriu, do mesmo IP (rodadas 2 e 3 da auditoria 8), como no iOS.
            let andando = Set(verificacoesTron.keys).union(verificacoesDeControle.keys).union(verificacoesTON.keys)
                .union(verificacoesDeRedes.keys.compactMap { UUID(uuidString: String($0.prefix { $0 != "|" })) })
            for id in andando where id != mantendo {
                // A primeira conferencia da recem-importada (a disparada ao gravar) segue, salvo quando quem abre tem passphrase:
                // a de base nao sai junto com ela (rodadas 4 e 5 da auditoria 8), como no iOS.
                if !escondendo, primeirasConferencias.contains(id), metadados.wallets.first(where: { $0.id == id })?.hasPassphrase == false { continue }
                cancelarConferencias(de: id)
            }
        }
    }

    /// Alguma conferencia de outra carteira no ar, ou a previa da importacao aberta (rodada 6 da auditoria 8).
    func outrasConferindo(_ id: UUID) -> Bool {
        let prefixo = id.uuidString + "|"
        return trava.withLock {
            previaAberta || verificacoesTron.keys.contains { $0 != id } || verificacoesDeControle.keys.contains { $0 != id }
                || verificacoesTON.keys.contains { $0 != id } || verificacoesDeRedes.keys.contains { !$0.hasPrefix(prefixo) }
        }
    }

    /// A previa da importacao aberta, consultando a importada: a rodada do dia nao sai junto (rodada 6), como no iOS.
    private var previaAberta = false

    func abrirPrevia(oculta: Bool) {
        // So destravada: a consulta que chega depois de o app travar nao liga a marca, que ficaria ate o proximo travar (rodada 7).
        trava.withLock { if faseAtual == .unlocked { previaAberta = true } }
        pararConferencias(oculta: oculta)
    }

    func fecharPrevia() {
        trava.withLock { previaAberta = false }
        agendarConferencias()
    }

    /// Faz `corpo` so com o app destravado e na mesma vez do travar, sob a mesma trava do `travar()` (rodada 6).
    func seDestravada(desde epoca: Int, _ corpo: () -> Void) {
        trava.withLock {
            guard faseAtual == .unlocked, epocaDeTravar == epoca else { return }
            corpo()
        }
    }

    /// As carteiras cuja primeira conferencia, disparada ao gravar, ainda esta no ar (so na memoria). Com a trava.
    private var primeirasConferencias: Set<UUID> = []

    /// As consultas de outra chave e da TON de uma carteira, canceladas e fora das listas. Chamar com a trava.
    private func cancelarConferencias(de id: UUID) {
        primeirasConferencias.remove(id)
        verificacoesTron.removeValue(forKey: id)?.cancel()
        verificacoesDeControle.removeValue(forKey: id)?.cancel()
        verificacoesTON.removeValue(forKey: id)?.cancel()
        for chave in verificacoesDeRedes.keys where chave.hasPrefix(id.uuidString + "|") { verificacoesDeRedes.removeValue(forKey: chave)?.cancel() }
    }

    /// Apaga tudo deste aparelho: as chaves do Keystore e os itens do cofre primeiro.
    func apagarTudo() {
        // O achado da previa EVM sai junto: a carteira da mesma frase nascia com ele depois (rodada 5 da auditoria 8).
        Importacao.esquecerPreviasEVM()
        // A conferencia da Tron em voo para, e nada dela grava depois (revisao, 08/11/2026); a das outras redes tambem.
        trava.withLock {
            verificacoesTron.values.forEach { $0.cancel() }
            verificacoesTron = [:]
            verificacoesDeControle.values.forEach { $0.cancel() }
            verificacoesDeControle = [:]
            verificacoesTON.values.forEach { $0.cancel() }
            verificacoesTON = [:]
            verificacoesDeRedes.values.forEach { $0.cancel() }
            verificacoesDeRedes = [:]
            primeirasConferencias = []
            tronLidaEm = [:]
            previaAberta = false
            rodadaDeControle?.cancel()
            rodadaDeControle = nil
            carteiraDaRodada = nil
            recemImportadas = []
        }
        Chaves.root.wipeAll()
        MetadataStore.deleteFile()
        Vigias.apagarTudo()
        trava.withLock {
            rascunho?.zerar()
            rascunho = nil
            chaveDeIndice = nil
            metadados = Metadata()
            depoisDeDestravar = []
            // A ultima removida com o app travado no meio nao vale para a instalacao seguinte (rodada 15).
            apagarAoDestravar = false
            faseAtual = .onboarding
        }
        Saldos.shared.esquecer()
        Atividade.shared.esquecer()
        Renovacoes.esquecer(carteira: nil)
        PortaDaPassphrase.encerrarFolgas()
        Envio.encerrar()
        Troca.esquecerEdicaoSuspensa()
        Silencio.ligar(false)
        esquecerSegredosDasTelas()
    }

    // MARK: Carteira nova

    /// A frase nasce e a carteira e guardada **antes** de mostrar as palavras: se o dono sair no
    /// meio, ela existe marcada "palavras nao confirmadas" e nao recebe.
    /// Super Security em "Bloquear as carteiras": nenhuma carteira com palavras entra (pedido do dono, 06/11/2026; o
    /// `addingWordsBlocked` do iOS). As palavras inteiras de cada carteira sao conferidas ao escolher "Bloquear"; uma
    /// adicionada depois ficaria presa a um papel nunca conferido inteiro. So observar continua.
    var adicionarBloqueado: Bool { Self.palavrasBloqueadas(Chaves.root) }

    /// Na duvida, recusa: o cofre mudo, ou o cabecalho do Super Security ilegivel, contam como "Bloquear" (revisao de
    /// seguranca de 06/11/2026; o `wordsBlocked` do iOS). Sem trava propria do cofre: vale tambem com a RK aberta.
    static func palavrasBloqueadas(_ root: RootKeyVault) -> Bool {
        switch root.securityMode {
        case .normal: return false
        case .unknown: return true
        case .hardened: return root.hardenedFaceChange.map { $0 == .lock } ?? true
        }
    }

    func criarCarteira(palavras: Int, credencial: Credencial) throws -> WalletMeta {
        guard !adicionarBloqueado else {
            credencial.zerar()
            throw Falha.bloqueioLigado
        }
        let frase = try BIP39.generate(wordCount: palavras)
        return try guardarRascunho(Rascunho(frase: frase, palavras: palavras), escolhidas: false, credencial: credencial)
    }

    /// O dono escolheu as primeiras palavras; o app sorteia a ultima, que fecha a conta.
    func criarComPalavras(_ primeiras: SecureBytes, palavras: Int, credencial: Credencial) throws -> WalletMeta {
        defer { primeiras.wipe() }
        guard !adicionarBloqueado else {
            credencial.zerar()
            throw Falha.bloqueioLigado
        }
        let frase: SecureBytes
        do {
            frase = try BIP39.completing(primeiras)
        } catch {
            credencial.zerar()
            throw error
        }
        return try guardarRascunho(Rascunho(frase: frase, palavras: palavras), escolhidas: true, credencial: credencial)
    }

    /// `escolhidas`: as palavras vieram do dono (a sorteada inteira nao e conferida nem marcada; rodada 7 da auditoria 8).
    private func guardarRascunho(_ novo: Rascunho, escolhidas: Bool, credencial: Credencial) throws -> WalletMeta {
        do {
            let copia = SecureBytes(capacity: novo.frase.capacity)
            novo.frase.withUnsafeBytes { copia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
            let secret = try WalletSecret.from(phrase: copia, language: .english)
            copia.wipe()
            let quantas = metadata.wallets.count
            let nome = quantas == 0 ? Textos.carteiraPrincipal : Textos.carteira(quantas + 1)
            let wallet = try adicionarCarteira(secret, nome: nome, origem: .created, palavras: novo.palavras, copiaConfirmada: false,
                                               palavrasEscolhidas: escolhidas, credencial: credencial)
            trava.withLock {
                rascunho?.zerar()
                rascunho = novo
            }
            return wallet
        } catch {
            novo.zerar()
            throw error
        }
    }

    func comRascunho<T>(_ corpo: (Rascunho) throws -> T) throws -> T {
        try trava.withLock {
            guard let rascunho else { throw Falha.semRascunho }
            return try corpo(rascunho)
        }
    }

    /// As palavras conferidas: a carteira ganha a copia e o rascunho e zerado. Revelado de uma
    /// carteira com passphrase ainda nao conferida, ele fica para a conferencia dela, logo depois.
    func confirmarCopia(_ id: UUID) throws {
        try atualizar(id) { $0.backupConfirmedAt = .now }
        let carteira = metadata.wallets.first { $0.id == id }
        let ficaParaAPassphrase = carteira?.hasPassphrase == true && carteira?.passphraseConfirmedAt == nil
            && trava.withLock { rascunho?.carteira == id }
        if !ficaParaAPassphrase { descartarRascunho() }
    }

    // MARK: Ver as palavras de uma carteira guardada

    /// Abre a frase de uma carteira guardada, para ver ou para a copia que faltou (o RevealFlow
    /// do iOS). Na carteira com passphrase, ela vem digitada e confere pelo fingerprint da raiz antes
    /// de qualquer palavra sair: sem a carteira de base neste celular, quem tem o PIN e o rosto
    /// levaria as palavras daqui e testaria passphrases fora do aparelho. Ela sai zerada no fim.
    func revelar(_ id: UUID, credencial: Credencial, passphraseDigitada: SecureBytes?) throws -> (palavras: Int, passphrase: Bool) {
        defer { passphraseDigitada?.wipe() }
        // A presenca inteira conferida aqui, na operacao, e nao so no despachante: um metodo novo que chamasse esta funcao com
        // o PIN ou a biometria sozinhos lia as palavras (rodada 4 da auditoria 8), como o `walletPhrase` do iOS.
        switch credencial {
        case .pinEBiometria, .reforcado: break
        case .pin, .biometria:
            credencial.zerar()
            throw RootKeyVault.Failure.biometryRequired
        }
        guard let wallet = metadata.wallets.first(where: { $0.id == id }), !wallet.isWatchOnly else {
            credencial.zerar()
            throw Falha.carteiraNaoEncontrada
        }
        if PortaDaPassphrase.semConferencia(wallet) {
            credencial.zerar()
            throw PortaDaPassphrase.SemConferencia()
        }
        // A digitada vem na chamada, ou entregue pela folha antes do PIN (o Kotlin zera a dele na hora).
        let conferir = PortaDaPassphrase.pede(wallet) ? (passphraseDigitada ?? PortaDaPassphrase.copiaEntregue()) : nil
        defer { conferir?.wipe() }
        if PortaDaPassphrase.pede(wallet), conferir == nil {
            credencial.zerar()
            throw Nucleo.Falha(erro: "envio.pedePassphrase")
        }
        if conferir != nil {
            do { try PortaDaPassphrase.comecar(id) } catch { credencial.zerar(); throw error }
        }
        let frase: SecureBytes
        do {
            frase = try comChaveRaiz(credencial) { rk in
                let secret = try Chaves.wallets.open(walletID: id, rk: rk)
                defer { secret.wipe() }
                if let conferir, try PortaDaPassphrase.confere(secret, conferir, wallet) == .mismatch { throw Signer.Failure.passphraseMismatch }
                return try secret.phrase()
            }
        } catch {
            if conferir != nil {
                if (error as? Signer.Failure) == .passphraseMismatch {
                    PortaDaPassphrase.descartarEntregue()
                    PortaDaPassphrase.errou(id)
                } else {
                    PortaDaPassphrase.devolver(id)
                }
            }
            throw error
        }
        PortaDaPassphrase.descartarEntregue()
        if conferir != nil { PortaDaPassphrase.passou(id) }
        let palavras = frase.withUnsafeBytes { raw in raw.filter { $0 == 0x20 }.count + 1 }
        // So guarda com a sessao aberta, sob a mesma trava do travar(): o app que travou durante a
        // abertura do cofre nao fica com as palavras na memoria (revisao de seguranca do Android de
        // 26/10/2026).
        guard mostrar(Rascunho(frase: frase, palavras: palavras, carteira: id)) else { throw Falha.travada }
        return (palavras, wallet.hasPassphrase)
    }

    /// Fechou a tela das palavras: a carteira anota quando elas foram vistas e o rascunho sai.
    func terminarRevelacao(_ id: UUID) {
        let eraDela = trava.withLock { rascunho?.carteira == id }
        if eraDela { try? atualizar(id) { $0.lastRevealedAt = .now } }
        descartarRascunho()
    }

    enum ConferenciaDaPassphrase: String, Encodable { case confere, naoConfere, antiga }

    /// A passphrase digitada de onde o dono anotou. Ela nao fica no cofre (05/11/2026): confere pelo
    /// fingerprint da raiz que a criacao gravou. Logo depois das palavras, a seed sai do rascunho;
    /// sozinha (palavras ja conferidas), pelo cofre com o PIN. Nos dois casos a tentativa conta.
    func conferirPassphrase(_ id: UUID, digitada: SecureBytes, credencial: Credencial?) throws -> ConferenciaDaPassphrase {
        defer { digitada.wipe() }
        let carteira = metadata.wallets.first { $0.id == id }
        if PortaDaPassphrase.semConferencia(carteira) {
            credencial?.zerar()
            throw PortaDaPassphrase.SemConferencia()
        }
        let digital = carteira?.fingerprint.flatMap(Hex.decode)
        let cardano = carteira?.accounts.first { $0.chainID == Chain.cardano.id }?.publicKey
        do { try PortaDaPassphrase.comecar(id) } catch { credencial?.zerar(); throw error }
        let resultado: PassphraseProof.Result
        do {
            // A frase sai do rascunho numa copia, e a conta (PBKDF2) corre fora da trava.
            let frase = trava.withLock { () -> SecureBytes? in
                guard let rascunho, rascunho.carteira == id else { return nil }
                let copia = SecureBytes(capacity: max(rascunho.frase.count, 1))
                rascunho.frase.withUnsafeBytes { copia.append(contentsOf: $0.bindMemory(to: UInt8.self)) }
                return copia
            }
            defer { frase?.wipe() }
            if let frase, case .valid(let idioma) = BIP39.validate(frase) {
                credencial?.zerar()
                resultado = try PassphraseProof.check(phrase: frase, language: idioma, typed: digitada, fingerprint: digital, cardanoPublicKey: cardano)
            } else {
                guard let credencial else { throw Nucleo.Falha(erro: "credencial desconhecida") }
                resultado = try comChaveRaiz(credencial) { rk in
                    try PassphraseProof.check(walletID: id, rootKey: rk, vault: Chaves.wallets, typed: digitada,
                                              fingerprint: digital, cardanoPublicKey: cardano)
                }
            }
        } catch {
            PortaDaPassphrase.devolver(id)
            throw error
        }
        if resultado == .mismatch { PortaDaPassphrase.errou(id) } else { PortaDaPassphrase.passou(id) }
        switch resultado {
        case .match:
            try atualizar(id) { $0.passphraseConfirmedAt = .now }
            descartarRascunho()
            return .confere
        case .legacy:
            try? atualizar(id) { $0.legacyCardanoPassphrase = true }
            return .antiga
        case .mismatch:
            return .naoConfere
        }
    }

    func descartarRascunho() {
        trava.withLock {
            rascunho?.zerar()
            rascunho = nil
        }
    }

    /// As palavras de um envelope aberto, so para ver: o rascunho que a tela de gravar mostra de
    /// tres em tres, sem carteira guardada.
    /// Guarda o rascunho so com a sessao aberta, sob a trava do travar(); travada, zera o novo.
    @discardableResult
    func mostrar(_ novo: Rascunho) -> Bool {
        let guardou = trava.withLock { () -> Bool in
            guard chaveDeIndice != nil else { return false }
            rascunho?.zerar()
            rascunho = novo
            return true
        }
        if !guardou { novo.zerar() }
        return guardou
    }
}

/// A frase de uma carteira recem-criada, enquanto o dono anota e confere. As palavras nunca viram `String`: saem em bytes
/// direto num ByteBuffer do Kotlin (`escrever`), e a conferida chega como segredo (auditoria das chaves de 06/11/2026).
final class Rascunho: @unchecked Sendable {
    let frase: SecureBytes
    let palavras: Int
    /// Revelado de uma carteira guardada: a passphrase dela, quando tem, e de qual carteira e.
    let passphrase: SecureBytes?
    let carteira: UUID?

    init(frase: SecureBytes, palavras: Int, passphrase: SecureBytes? = nil, carteira: UUID? = nil) {
        self.frase = frase
        self.palavras = palavras
        self.passphrase = passphrase
        self.carteira = carteira
    }

    /// As palavras da faixa, em UTF-8 e separadas por um espaco, direto no destino (o ByteBuffer direto do Kotlin, fora do
    /// heap do Java). Devolve quantos bytes escreveu, ou -1 se a faixa ou o destino nao servem.
    func escrever(_ faixa: Range<Int>, em destino: UnsafeMutableRawBufferPointer) -> Int {
        frase.withUnsafeBytes { raw in
            let trechos = Self.trechos(raw)
            guard !faixa.isEmpty, faixa.lowerBound >= 0, faixa.upperBound <= trechos.count,
                  let origem = raw.baseAddress, let saida = destino.baseAddress
            else { return -1 }
            let total = faixa.reduce(faixa.count - 1) { $0 + trechos[$1].count }
            guard total <= destino.count else { return -1 }
            var posicao = 0
            for indice in faixa {
                if posicao > 0 {
                    saida.storeBytes(of: UInt8(0x20), toByteOffset: posicao, as: UInt8.self)
                    posicao += 1
                }
                let trecho = trechos[indice]
                saida.advanced(by: posicao).copyMemory(from: origem.advanced(by: trecho.lowerBound), byteCount: trecho.count)
                posicao += trecho.count
            }
            return posicao
        }
    }

    /// A palavra digitada confere com a da posicao? Na forma canonica, pelos bytes, em tempo constante.
    func confere(_ digitada: SecureBytes, em indice: Int) -> Bool {
        let (candidata, palavrasDigitadas) = BIP39.canonicalWords(digitada)
        defer { candidata.wipe() }
        guard palavrasDigitadas.count == 1 else { return false }
        return candidata.withUnsafeBytes { digitadaRaw in
            frase.withUnsafeBytes { raw in
                let trechos = Self.trechos(raw)
                guard trechos.indices.contains(indice) else { return false }
                var palavra = Array(raw[trechos[indice]])
                var tentativa = Array(digitadaRaw[palavrasDigitadas[0]])
                defer { palavra.resetBytes(); tentativa.resetBytes() }
                return Hash.constantTimeEqual(palavra, tentativa)
            }
        }
    }

    private static func trechos(_ raw: UnsafeRawBufferPointer) -> [Range<Int>] {
        var saida: [Range<Int>] = []
        var inicio = 0
        for indice in 0...raw.count where indice == raw.count || raw[indice] == 0x20 {
            if indice > inicio { saida.append(inicio..<indice) }
            inicio = indice + 1
        }
        return saida
    }

    func zerar() {
        frase.wipe()
        passphrase?.wipe()
    }
}

/// Os textos que o nucleo grava ou mostra no sistema (nome de carteira, motivo da biometria). O
/// app instala a traducao ao abrir (`Textos.instalar`).
enum Textos {
    nonisolated(unsafe) private static var tabela: [String: String] = [:]

    static func instalar(_ nova: [String: String]) { tabela = nova }

    static func t(_ chave: String) -> String { tabela[chave] ?? chave }

    static var destravar: String { t("Destravar a Escalibur") }
    static var carteiraPrincipal: String { t("Carteira principal") }
    static func carteira(_ numero: Int) -> String { t("Carteira %lld").replacingOccurrences(of: "%lld", with: "\(numero)") }
    static var envelope: String { t("envelope") }
    static var importada: String { t("importada") }
}
