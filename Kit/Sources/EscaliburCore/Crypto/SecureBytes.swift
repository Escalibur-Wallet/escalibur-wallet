#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// Um buffer para segredo: senha, chave derivada, frase em claro.
///
/// Nada disso pode morar em `String` nem em `Data`. Os dois crescem realocando, e a
/// alocacao antiga fica no heap com o segredo dentro, sem endereco para apagar. Uma
/// senha digitada em `@State private var senha = ""` deixa para tras `"c"`, `"co"`,
/// `"cor"`, `"corr"`, e um dump de memoria do processo remonta a senha inteira. Isso
/// e um achado conhecido, nao uma preocupacao teorica.
///
/// Este tipo evita as tres armadilhas:
///
/// 1. **Capacidade fixa.** Nunca realoca, entao nunca deixa copia para tras. Estourar
///    a capacidade e erro de programacao e mata o processo, em vez de crescer em
///    silencio.
/// 2. **Paginas de guarda.** A regiao e mapeada com uma pagina inacessivel de cada
///    lado, entao leitura ou escrita fora do buffer estoura na hora, em vez de
///    alcancar o segredo do vizinho.
/// 3. **Zeragem que sobrevive ao otimizador.** `memset_s` do C11 nao pode ser
///    eliminado como escrita morta; `memset` pode, e e removido em `-O` justamente
///    quando ninguem le o resultado, que e sempre o caso aqui.
///
/// O que este tipo **nao** garante, e esta escrito em docs/criptografia.md para nao
/// virar promessa: o compilador ainda pode ter copiado bytes para a pilha ao passar
/// registradores, e o compressor de memoria do iOS pode ter guardado a pagina em
/// forma comprimida. A defesa real contra isso e a janela curta de vida, nao a
/// chamada de sistema.
public final class SecureBytes: @unchecked Sendable {

    /// A sincronizacao e de quem usa: um `SecureBytes` atravessa a fronteira de
    /// tarefa durante a derivacao de chave, e serializar aqui dentro esconderia esse
    /// contrato em vez de cumpri-lo. Cada instancia pertence a um fluxo de cada vez.

    private let region: UnsafeMutableRawPointer
    private let regionSize: Int
    private let base: UnsafeMutableRawPointer
    /// No Android, as fatias da arena travada que este buffer usa (nil: regiao propria, com `mmap`).
    private let arenaSlices: (first: Int, count: Int)?

    public let capacity: Int
    public private(set) var count: Int = 0

    private var wiped = false

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity

        #if !canImport(Darwin)
        // Android: o segredo pequeno vai para a arena travada na RAM (LockedArena), que nao gasta uma pagina da cota de
        // memoria travada por buffer (auditoria das chaves de 06/11/2026).
        if let slot = LockedArena.take(capacity) {
            memset_s(slot.pointer, slot.count * LockedArena.sliceSize, 0, slot.count * LockedArena.sliceSize)
            self.region = slot.pointer
            self.regionSize = 0
            self.base = slot.pointer
            self.arenaSlices = (slot.first, slot.count)
            return
        }
        #endif

        let pageSize = Int(getpagesize())
        let payloadPages = (capacity + pageSize - 1) / pageSize
        // Uma pagina de guarda antes, uma depois.
        let regionSize = (payloadPages + 2) * pageSize

        #if canImport(Darwin)
        guard
            let region = mmap(
                nil, regionSize,
                PROT_READ | PROT_WRITE,
                MAP_PRIVATE | MAP_ANON, -1, 0
            ),
            region != MAP_FAILED
        else {
            fatalError("SecureBytes: mmap falhou")
        }
        #else
        // Android: o mmap devolve o ponteiro sem opcional, e o MAP_FAILED do C, (void *)-1,
        // nao vem para o Swift.
        let region: UnsafeMutableRawPointer = mmap(nil, regionSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
        guard region != UnsafeMutableRawPointer(bitPattern: -1) else {
            fatalError("SecureBytes: mmap falhou")
        }
        #endif

        // As guardas ficam sem permissao nenhuma: encostar nelas e sinal, nao
        // corrupcao silenciosa. E o retorno e conferido: um mprotect que falha em
        // silencio deixaria as guardas legiveis e gravaveis sem nenhum sinal, que e o
        // oposto do que elas existem para ser.
        guard mprotect(region, pageSize, PROT_NONE) == 0,
              mprotect(region.advanced(by: regionSize - pageSize), pageSize, PROT_NONE) == 0
        else {
            fatalError("SecureBytes: mprotect recusou as paginas de guarda")
        }

        #if !canImport(Darwin)
        // Android: o segredo nao vai para o swap nem para um core dump. Em aparelho com RAM Plus,
        // Extensao de memoria e afins, o swap e um arquivo no flash, e a pagina fica la depois de
        // zerada na RAM. Melhor esforco: sem cota (RLIMIT_MEMLOCK) ou sem permissao, o buffer segue
        // como antes; o munmap solta a trava (auditoria Android de 31/10/2026, AA-01). O bloco do
        // Argon2 (256 MiB, malloc) nao cabe na cota e continua exposto durante a derivacao do PIN.
        // A falha do mlock e contada, e nao engolida (`LockedArena.lockFailures`).
        if mlock(region.advanced(by: pageSize), payloadPages * pageSize) != 0 { LockedArena.noteLockFailure() }
        _ = madvise(region, regionSize, MADV_DONTDUMP)
        #endif

        self.region = region
        self.regionSize = regionSize
        self.base = region.advanced(by: pageSize)
        self.arenaSlices = nil
    }

    deinit {
        wipeRegion()
        #if !canImport(Darwin)
        if let slices = arenaSlices {
            LockedArena.give(first: slices.first, count: slices.count)
            return
        }
        #endif
        munmap(region, regionSize)
    }

    // MARK: Escrita

    public func append(_ byte: UInt8) {
        rearm()
        precondition(count + 1 <= capacity, "SecureBytes: capacidade estourada")
        base.advanced(by: count).storeBytes(of: byte, as: UInt8.self)
        count += 1
    }

    public func append(contentsOf buffer: UnsafeBufferPointer<UInt8>) {
        guard let source = buffer.baseAddress, !buffer.isEmpty else { return }
        rearm()
        precondition(count + buffer.count <= capacity, "SecureBytes: capacidade estourada")
        base.advanced(by: count).copyMemory(from: source, byteCount: buffer.count)
        count += buffer.count
    }

    /// Remove os ultimos `n` bytes, apagando o que sai. E o backspace do campo de
    /// senha: o byte removido nao pode continuar legivel no fim do buffer.
    public func removeLast(_ n: Int) {
        guard !wiped, n > 0, count > 0 else { return }
        let removing = min(n, count)
        let start = count - removing
        memset_s(base.advanced(by: start), removing, 0, removing)
        count = start
    }

    public func replaceAll(with bytes: [UInt8]) {
        rearm()
        precondition(bytes.count <= capacity, "SecureBytes: capacidade estourada")
        memset_s(base, capacity, 0, capacity)
        count = 0
        bytes.withUnsafeBufferPointer { append(contentsOf: $0) }
    }

    /// Deixa uma funcao C escrever `count` bytes direto na regiao, sem copia
    /// intermediaria. O conteudo anterior e apagado antes.
    public func fill(count: Int, _ body: (UnsafeMutableRawPointer) -> Void) {
        rearm()
        precondition(count <= capacity, "SecureBytes: capacidade estourada")
        memset_s(base, capacity, 0, capacity)
        body(base)
        self.count = count
    }

    // MARK: Leitura

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try body(UnsafeRawBufferPointer(start: base, count: count))
    }

    /// Copia para um `Data` de vida curta. Usar so na fronteira com APIs que exigem
    /// `Data`, e nunca guardar o resultado.
    public func withUnsafeData<R>(_ body: (Data) throws -> R) rethrows -> R {
        try withUnsafeBytes { raw in
            var data = Data(raw)
            defer {
                data.withUnsafeMutableBytes { buffer in
                    guard let address = buffer.baseAddress else { return }
                    memset_s(address, buffer.count, 0, buffer.count)
                }
            }
            return try body(data)
        }
    }

    // MARK: Zeragem

    /// Apaga o conteudo. Idempotente, e o buffer continua utilizavel depois de um
    /// `reset()`.
    public func wipe() {
        wipeRegion()
        count = 0
        wiped = true
    }

    /// Escrever depois de uma zeragem **nao pode derrubar o processo**.
    ///
    /// Antes isto era um `precondition`, e ele disparava num caminho banal: uma
    /// notificacao chegando enquanto a senha era digitada fechava o cofre, zerava o
    /// buffer, e a tecla seguinte matava o app. Num aplicativo de custodia, morrer na
    /// hora de abrir o cofre faz o dono achar que perdeu o dinheiro.
    ///
    /// A regiao ja foi zerada quando `wiped` virou verdadeiro, entao rearmar nao
    /// desfaz nenhuma garantia: o segredo antigo nao esta mais la.
    private func rearm() {
        guard wiped else { return }
        wipeRegion()
        count = 0
        wiped = false
    }

    public func reset() {
        wipeRegion()
        count = 0
        wiped = false
    }

    private func wipeRegion() {
        memset_s(base, capacity, 0, capacity)
    }

    // MARK: Construcao

    /// Preenche com bytes do gerador do sistema. Nunca de `Int.random`, nunca de
    /// `arc4random`: chave de cofre so nasce do CSPRNG do sistema.
    public static func random(count: Int) throws -> SecureBytes {
        let bytes = SecureBytes(capacity: count)
        let status = bytes.base.withMemoryRebound(to: UInt8.self, capacity: count) {
            SecRandomCopyBytes(kSecRandomDefault, count, $0)
        }
        guard status == errSecSuccess else {
            bytes.wipe()
            throw CryptoError.randomnessUnavailable
        }
        bytes.count = count
        return bytes
    }
}

public enum CryptoError: Error, Equatable {
    /// `SecRandomCopyBytes` falhou. Nao existe plano B: a operacao aborta.
    case randomnessUnavailable

    /// Argon2 recusou os parametros ou nao conseguiu a memoria pedida.
    case keyDerivationFailed(code: Int32)

    /// A tag de autenticacao nao fecha.
    ///
    /// Deliberadamente um erro so, sem distinguir senha errada de arquivo adulterado.
    /// Separar os dois entregaria ao atacante um verificador barato, e e por isso que
    /// a interface tambem mostra uma unica mensagem.
    case cannotOpen

    /// O arquivo nao e um cofre, ou e de uma versao que este app nao conhece.
    case malformedVault(String)
}

#if !canImport(Darwin)
/// Uma regiao so, travada na RAM (`mlock`) e fora do core dump, com uma pagina de guarda em cada ponta, dividida em fatias de
/// 256 bytes. A cota de memoria travada do Android e de 64 KiB (RLIMIT_MEMLOCK), e cada SecureBytes com regiao propria trava
/// pelo menos uma pagina: do 17o buffer em diante (do 5o, em kernel de paginas de 16 KiB) o `mlock` falhava em silencio e a
/// seed podia ir para o swap no flash (auditoria das chaves de 06/11/2026). Aqui cabem as chaves, a entropia, a seed, o PIN,
/// a passphrase e a frase. O que nao cabe segue com a regiao propria. Entre as fatias nao ha pagina de guarda: a capacidade
/// fixa do SecureBytes ja impede escrever fora, e as guardas da arena pegam o ponteiro cru que passa da ponta.
enum LockedArena {
    static let sliceSize = 256
    /// Acima disto (texto de envelope, por exemplo) vai para a regiao propria, para nao ocupar a arena das chaves.
    static let largestCapacity = 2048

    private struct State {
        let base: UnsafeMutableRawPointer
        var used: [Bool]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var state: State? = setup()
    nonisolated(unsafe) private static var failures = 0

    /// Quantos `mlock` de regiao propria falharam neste processo (o que nao coube na arena).
    static var lockFailures: Int { lock.withLock { failures } }

    /// A arena nasceu (mmap, guardas e mlock aceitos)?
    static var isActive: Bool { lock.withLock { state != nil } }

    static func noteLockFailure() { lock.withLock { failures += 1 } }

    private static func setup() -> State? {
        let pageSize = Int(getpagesize())
        var limit = rlimit()
        guard getrlimit(RLIMIT_MEMLOCK, &limit) == 0 else { return nil }
        // Sem limite (RLIM_INFINITY) conta como a cota padrao do Android.
        let quota = limit.rlim_cur > rlim_t(Int32.max) ? 64 * 1024 : Int(limit.rlim_cur)
        // Metade da cota, ate 32 KiB: a outra metade fica para quem nao cabe aqui.
        let payload = (min(32 * 1024, quota / 2) / pageSize) * pageSize
        guard payload >= pageSize else { return nil }
        let regionSize = payload + 2 * pageSize
        let region: UnsafeMutableRawPointer = mmap(nil, regionSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
        guard region != UnsafeMutableRawPointer(bitPattern: -1) else { return nil }
        let base = region.advanced(by: pageSize)
        guard mprotect(region, pageSize, PROT_NONE) == 0,
              mprotect(base.advanced(by: payload), pageSize, PROT_NONE) == 0,
              mlock(base, payload) == 0
        else {
            munmap(region, regionSize)
            return nil
        }
        _ = madvise(region, regionSize, MADV_DONTDUMP)
        return State(base: base, used: [Bool](repeating: false, count: payload / sliceSize))
    }

    /// As primeiras fatias seguidas e livres que cabem `capacity`, ou nil (arena cheia, ou sem arena).
    static func take(_ capacity: Int) -> (pointer: UnsafeMutableRawPointer, first: Int, count: Int)? {
        let needed = (capacity + sliceSize - 1) / sliceSize
        return lock.withLock {
            // O `state` primeiro: a arena nasce no primeiro SecureBytes do processo, de qualquer tamanho. Se os grandes
            // viessem antes e gastassem a cota, o mlock dela falhava e ela nunca existia (revisao de 07/11/2026).
            guard var current = state, capacity <= largestCapacity, needed <= current.used.count else { return nil }
            var run = 0
            for index in current.used.indices {
                run = current.used[index] ? 0 : run + 1
                guard run == needed else { continue }
                let first = index - needed + 1
                for slice in first...index { current.used[slice] = true }
                state = current
                return (current.base.advanced(by: first * sliceSize), first, needed)
            }
            return nil
        }
    }

    /// Devolve as fatias (ja zeradas por quem as usou).
    static func give(first: Int, count: Int) {
        lock.withLock {
            guard var current = state else { return }
            for slice in first..<(first + count) { current.used[slice] = false }
            state = current
        }
    }
}
#endif
