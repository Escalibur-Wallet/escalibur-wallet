package app.escalibur.wallet.nucleo

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * A ponte com o nucleo em Swift (o mesmo do iOS), carregado de libEscaliburAndroid.so.
 *
 * `chamar` recebe o nome de um metodo e os dados em JSON, e devolve JSON. Segredo (PIN, palavras,
 * passphrase) vai por `chamarComSegredo`, num byte[] que o nucleo copia para a memoria protegida
 * dele e zera no lugar. Chame sempre fora da thread da interface (o nucleo pode ir a rede, e o
 * PIN custa um Argon2 de 256 MiB).
 */
object Nucleo {
    init {
        System.loadLibrary("c++_shared")
        System.loadLibrary("EscaliburAndroid")
    }

    @JvmStatic
    external fun chamar(metodo: String, corpo: String): String

    @JvmStatic
    external fun chamarComSegredo(metodo: String, corpo: String, segredo: ByteArray): String
}

/** A recusa do nucleo: o codigo estavel ("cofre.pinErrado") e o resto do JSON (restantes, segundos). */
class FalhaDoNucleo(val codigo: String, val dados: JSONObject) : Exception(codigo) {
    val restantes: Int? get() = if (dados.has("restantes")) dados.getInt("restantes") else null
    val segundos: Double get() = dados.optDouble("segundos", 0.0)
    val erros: Int get() = dados.optInt("erros", 0)
}

/** As chamadas, na thread de fundo, com a resposta ja conferida. */
object Api {
    suspend fun objeto(metodo: String, corpo: JSONObject = JSONObject()): JSONObject = withContext(Dispatchers.IO) {
        conferir(Nucleo.chamar(metodo, corpo.toString()))
    }

    suspend fun lista(metodo: String, corpo: JSONObject = JSONObject()): JSONArray = withContext(Dispatchers.IO) {
        val resposta = Nucleo.chamar(metodo, corpo.toString())
        if (resposta.trimStart().startsWith("[")) JSONArray(resposta) else throw falha(JSONObject(resposta))
    }

    /**
     * Com segredo. `partes`: o PIN da credencial primeiro (quando ela e por PIN) e o que a operacao
     * pede, cada um zerado aqui depois do envio. Nada disto vira String.
     */
    suspend fun comSegredo(metodo: String, corpo: JSONObject, vararg partes: ByteArray): JSONObject = withContext(Dispatchers.IO) {
        // Cada parte com o tamanho na frente (4 bytes): uma passphrase colada com quebra de linha
        // chega inteira, em vez de virar duas partes.
        val junto = ByteArray(partes.sumOf { 4 + it.size })
        var posicao = 0
        for (parte in partes) {
            for (deslocamento in 0 until 4) junto[posicao++] = (parte.size ushr (24 - 8 * deslocamento)).toByte()
            parte.copyInto(junto, posicao)
            posicao += parte.size
        }
        try {
            conferir(Nucleo.chamarComSegredo(metodo, corpo.toString(), junto))
        } finally {
            junto.fill(0)
            partes.forEach { it.fill(0) }
        }
    }

    /** Resposta de erro do nucleo: `{"erro": "..."}` e, as vezes, os numeros da mensagem. */
    private fun conferir(resposta: String): JSONObject {
        val json = JSONObject(resposta)
        if (json.opt("erro") is String) throw falha(json)
        return json
    }

    private fun falha(json: JSONObject) = FalhaDoNucleo(json.optString("erro", "falha"), json)
}
