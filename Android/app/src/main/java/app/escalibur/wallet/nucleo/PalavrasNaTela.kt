package app.escalibur.wallet.nucleo

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer

/**
 * As palavras secretas que estao na tela (as da carteira, e as sorteadas para a senha do envelope), sem passar por String
 * nem JSON (auditoria das chaves de 06/11/2026). O nucleo escreve os bytes num ByteBuffer direto (no ART, um byte[] que o
 * GC nao move nem copia), que vira um CharArray por palavra e e zerado na hora. Os CharArray sao desenhados pelo
 * `TextoSecreto` e zerados em [zerar], quando a tela sai ou as palavras escondem; o CharArray e um objeto comum do heap, e
 * o GC pode ter deixado uma copia dele antes de zerar. Na ida do app para o segundo plano, [zerarTodas] zera as de todas as
 * telas na hora: o efeito da tela so rodaria na volta, e no fundo o sistema manda paginas para o swap (revisao final de
 * 07/11/2026). A tela que estava aberta le de novo na volta.
 */
class PalavrasNaTela {
    private val vivas = mutableListOf<CharArray>()
    /** Sobe a cada [zerar]: uma leitura que estava no nucleo quando a tela zerou nao entra em [vivas], e sai zerada. */
    private var geracao = 0

    init {
        synchronized(todas) {
            todas.removeAll { it.get() == null }
            todas.add(java.lang.ref.WeakReference(this))
        }
    }

    /** As palavras de `de` ate `ate` (sem incluir), ou null se o rascunho nao esta aberto. */
    suspend fun ler(de: Int, ate: Int): List<CharArray>? = ler(0, de, ate)

    /** As seis palavras sorteadas para a senha do envelope, ou null sem sorteio. */
    suspend fun lerSugestao(): List<CharArray>? = ler(1, 0, 0)

    private suspend fun ler(fonte: Int, de: Int, ate: Int): List<CharArray>? = withContext(Dispatchers.IO) {
        val minha = synchronized(vivas) { geracao }
        // A maior palavra das listas tem 33 bytes: 24 delas e os espacos cabem com folga.
        val bytes = ByteBuffer.allocateDirect(1024)
        try {
            val escritos = Nucleo.palavras(fonte, de, ate, bytes)
            if (escritos < 0) return@withContext null
            val palavras = mutableListOf<CharArray>()
            var inicio = 0
            for (posicao in 0..escritos) {
                if (posicao == escritos || bytes.get(posicao) == 0x20.toByte()) {
                    if (posicao > inicio) palavras.add(utf8(bytes, inicio, posicao))
                    inicio = posicao + 1
                }
            }
            synchronized(vivas) {
                // Zerada no meio da leitura, ou o app no fundo: a leitura que comeca com a composicao parada nao fica no heap
                // ate a volta (revisao final de 07/11/2026).
                if (geracao != minha || noFundo) {
                    palavras.forEach { it.fill('\u0000') }
                    return@withContext null
                }
                vivas.addAll(palavras)
            }
            palavras
        } finally {
            for (posicao in 0 until bytes.capacity()) bytes.put(posicao, 0)
        }
    }

    /** Zera todas as palavras que esta tela leu. */
    fun zerar() {
        synchronized(vivas) {
            geracao++
            vivas.forEach { it.fill('\u0000') }
            vivas.clear()
        }
    }

    companion object {
        private val todas = mutableListOf<java.lang.ref.WeakReference<PalavrasNaTela>>()
        @Volatile private var noFundo = false

        /** Zera as palavras de todas as telas, na hora (a ida para o segundo plano e o travar). Ate [liberar], nenhuma
         * leitura fica. */
        fun zerarTodas() {
            noFundo = true
            synchronized(todas) {
                todas.removeAll { it.get() == null }
                todas.forEach { it.get()?.zerar() }
            }
        }

        /** A volta para a frente: as telas leem de novo. */
        fun liberar() {
            noFundo = false
        }
    }

    /** UTF-8 para UTF-16 direto num CharArray, sem String (as listas do BIP-39 cabem no plano basico). */
    private fun utf8(bytes: ByteBuffer, inicio: Int, fim: Int): CharArray {
        val saida = CharArray(fim - inicio)
        var escritos = 0
        var posicao = inicio
        fun continuacao(deslocamento: Int): Int = bytes.get(posicao + deslocamento).toInt() and 0x3F
        while (posicao < fim) {
            val primeiro = bytes.get(posicao).toInt() and 0xFF
            val tamanho = when {
                primeiro < 0x80 -> 1
                primeiro shr 5 == 0x6 -> 2
                primeiro shr 4 == 0xE -> 3
                else -> 4
            }
            if (posicao + tamanho > fim) break
            val ponto = when (tamanho) {
                1 -> primeiro
                2 -> (primeiro and 0x1F shl 6) or continuacao(1)
                3 -> (primeiro and 0x0F shl 12) or (continuacao(1) shl 6) or continuacao(2)
                else -> (primeiro and 0x07 shl 18) or (continuacao(1) shl 12) or (continuacao(2) shl 6) or continuacao(3)
            }
            escritos += Character.toChars(ponto, saida, escritos)
            posicao += tamanho
        }
        return if (escritos == saida.size) saida else saida.copyOf(escritos).also { saida.fill('\u0000') }
    }
}
