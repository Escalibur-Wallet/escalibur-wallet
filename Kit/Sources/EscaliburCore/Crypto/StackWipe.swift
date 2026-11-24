#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif

/// Zera a pilha abaixo de quem chama, depois de uma operacao com segredo: os quadros que o HMAC e o PBKDF2 da frase, o
/// Ed25519 e a Cardano deixaram ao voltar (a frase em XOR com o pad, o escalar, o digesto do nonce), que o `defer` de cada
/// funcao nao alcanca (auditoria das chaves de 06/11/2026). Chamar num `defer` posto como primeira linha da funcao que
/// fez as contas, para rodar por ultimo, na mesma thread: a recursao desce pela regiao que as contas usaram.
public enum StackWipe {
    /// 4 KiB numa variavel local: um quadro da recursao.
    private struct Block {
        var a = SIMD64<UInt64>(), b = SIMD64<UInt64>(), c = SIMD64<UInt64>(), d = SIMD64<UInt64>()
        var e = SIMD64<UInt64>(), f = SIMD64<UInt64>(), g = SIMD64<UInt64>(), h = SIMD64<UInt64>()
    }

    /// 64 KiB, em 16 quadros de 4 KiB, cada um zerado com `memset_s` (que o compilador nao tira). O
    /// `withExtendedLifetime` depois da chamada impede a recursao de reaproveitar o quadro.
    @inline(never)
    public static func below(depth: Int = 16) {
        var block = Block()
        withUnsafeMutableBytes(of: &block) { raw in
            if let base = raw.baseAddress { _ = memset_s(base, raw.count, 0, raw.count) }
        }
        if depth > 1 { below(depth: depth - 1) }
        withExtendedLifetime(block) {}
    }
}
