package app.escalibur.wallet.ui.carteira

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.Eventos
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.textos
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.Date

/** Uma rede onde a carteira tem o ativo da linha. */
data class Posicao(
    val rede: String, val redeNome: String, val ativo: String, val quantidade: String, val disponivel: String,
    val casas: Int, val contrato: String?,
)

/** Um ativo na lista: o mesmo ativo em varias redes vira uma linha so. */
data class Linha(
    val id: String, val simbolo: String, val nome: String, val coingecko: String?, val estavel: Boolean,
    val posicoes: List<Posicao>, val preco: Double?, val variacao24h: Double?, val valor: Double?, val casas: Int,
    val total: String, val reconhecido: Boolean, val custom: Boolean, val conferido: Boolean,
)

/** Um token fora da lista conferida. */
data class Outro(
    val id: String, val simbolo: String, val nome: String, val rede: String, val quantidade: String, val casas: Int,
    val preco: Double?, val valor: Double?, val suspeito: Boolean,
)

data class Retrato(
    val carteira: String?, val linhas: List<Linha>, val todasAsLinhas: List<Linha>, val outros: List<Outro>, val suspeitos: List<Outro>,
    val total: Double, val variacao24h: Double, val variacao24hPct: Double, val carregando: Boolean, val falhas: List<String>,
    val atualizado: Date?, val semRede: Boolean, val tokensDesconhecidos: Int, val moeda: String, val bitcoin: Map<String, Double>,
) {
    /** Um valor na moeda do app levado para outra unidade, pela cotacao do bitcoin. */
    fun converter(valor: Double, unidade: String): Double? {
        val btcNaMoeda = bitcoin[moeda] ?: return if (unidade == moeda) valor else null
        if (btcNaMoeda <= 0) return if (unidade == moeda) valor else null
        if (unidade == "btc") return valor / btcNaMoeda
        val btcNaUnidade = bitcoin[unidade] ?: return null
        return valor * btcNaUnidade / btcNaMoeda
    }

    companion object {
        // Antes do primeiro retrato do nucleo: carregando, para a carteira mostrar o esqueleto e nao "vazia".
        val vazio = Retrato(null, emptyList(), emptyList(), emptyList(), emptyList(), 0.0, 0.0, 0.0, true, emptyList(), null, false, 0, "usd", emptyMap())

        private fun linha(json: JSONObject) = Linha(
            id = json.getString("id"), simbolo = json.getString("simbolo"), nome = json.getString("nome"),
            coingecko = json.optString("coingecko").takeIf { it.isNotEmpty() && it != "null" }, estavel = json.optBoolean("estavel"),
            posicoes = json.getJSONArray("posicoes").objetos().map {
                Posicao(it.getString("rede"), it.getString("redeNome"), it.getString("ativo"), it.getString("quantidade"),
                        it.getString("disponivel"), it.getInt("casas"), it.optString("contrato").takeIf { c -> c.isNotEmpty() && c != "null" })
            },
            preco = if (json.has("preco")) json.getDouble("preco") else null,
            variacao24h = if (json.has("variacao24h")) json.getDouble("variacao24h") else null,
            valor = if (json.has("valor")) json.getDouble("valor") else null,
            casas = json.getInt("casas"), total = json.getString("total"), reconhecido = json.optBoolean("reconhecido"),
            custom = json.optBoolean("custom"), conferido = json.optBoolean("conferido", true),
        )

        private fun outro(json: JSONObject) = Outro(
            id = json.getString("id"), simbolo = json.getString("simbolo"), nome = json.getString("nome"), rede = json.getString("rede"),
            quantidade = json.getString("quantidade"), casas = json.getInt("casas"),
            preco = if (json.has("preco")) json.getDouble("preco") else null, valor = if (json.has("valor")) json.getDouble("valor") else null,
            suspeito = json.optBoolean("suspeito"),
        )

        fun de(json: JSONObject): Retrato {
            val bitcoin = json.optJSONObject("bitcoin")
            return Retrato(
                carteira = json.optString("carteira").takeIf { it.isNotEmpty() && it != "null" },
                linhas = json.getJSONArray("linhas").objetos().map(::linha),
                todasAsLinhas = json.getJSONArray("todasAsLinhas").objetos().map(::linha),
                outros = json.getJSONArray("outros").objetos().map(::outro),
                suspeitos = json.getJSONArray("suspeitos").objetos().map(::outro),
                total = json.optDouble("total", 0.0), variacao24h = json.optDouble("variacao24h", 0.0),
                variacao24hPct = json.optDouble("variacao24hPct", 0.0), carregando = json.optBoolean("carregando"),
                falhas = json.optJSONArray("falhas").textos(),
                atualizado = if (json.has("atualizado")) Date(json.getLong("atualizado")) else null,
                semRede = json.optBoolean("semRede"), tokensDesconhecidos = json.optInt("tokensDesconhecidos"),
                moeda = json.optString("moeda", "usd"),
                bitcoin = bitcoin?.keys()?.asSequence()?.associateWith { bitcoin.getDouble(it) } ?: emptyMap(),
            )
        }
    }
}

/** Os saldos da carteira em uso, como a interface ve. Cada rede que chega atualiza o retrato. */
object Saldos {
    var retrato by mutableStateOf(Retrato.vazio)
        private set
    private val escopo = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    init {
        escopo.launch {
            // Ler o retrato fora da linha principal, e so o mais novo: com muitas redes chegando juntas,
            // ler cada um na linha principal travava o toque (ANR digitando o PIN).
            Eventos.eventos.filter { it.nome == "saldos" }
                .map { evento -> runCatching { Retrato.de(JSONObject(evento.json)) }.getOrNull() }
                .flowOn(Dispatchers.Default)
                .conflate()
                .collect { novo -> if (novo != null) retrato = novo }
        }
    }

    suspend fun mostrar() {
        runCatching { retrato = lido(Api.objeto("saldos.mostrar")) }
    }

    suspend fun atualizar(forcar: Boolean) {
        runCatching { retrato = lido(Api.objeto("saldos.atualizar", JSONObject().put("forcar", forcar))) }
    }

    private suspend fun lido(json: JSONObject): Retrato = withContext(Dispatchers.Default) { Retrato.de(json) }

    /** A linha ainda espera a cotacao: no lugar do valor, a barra que brilha. */
    fun esperandoPreco(linha: Linha): Boolean = linha.preco == null && (retrato.carregando || (linha.coingecko != null && !retrato.semRede))
}
