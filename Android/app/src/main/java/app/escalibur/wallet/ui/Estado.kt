package app.escalibur.wallet.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.escalibur.wallet.nucleo.Api
import org.json.JSONArray
import org.json.JSONObject
import java.util.Date

/** Uma carteira como a interface ve: o que o nucleo devolve em `CarteiraResumo`. */
data class Carteira(
    val id: String,
    val nome: String,
    val observacao: Boolean,
    val palavras: Int?,
    val origem: String,
    val palavrasConfirmadas: Boolean,
    val temCopia: Boolean,
    val temPassphrase: Boolean,
    val passphraseConfirmada: Boolean,
    val tronOutraChave: Boolean,
    /** Pede a passphrase para mover saldo e para ver as palavras. */
    val pedePassphrase: Boolean,
    val selecionada: Boolean,
    val digital: String?,
    val contas: List<Pair<String, String>>,
    /** O comeco e o fim de cada endereco, por rede, como o iOS mostra (vem do nucleo). */
    val curtos: Map<String, String> = emptyMap(),
    val copiaConfirmadaEm: Date? = null,
    val passphraseConferidaEm: Date? = null,
    val envelopeLacradoEm: Date? = null,
    val vistaEm: Date? = null,
) {
    fun endereco(rede: String): String? = contas.firstOrNull { it.first == rede }?.second

    /** "bc1qcr8te4…6fyu": o endereco curto da rede, como no iOS. */
    fun curto(rede: String): String? = curtos[rede] ?: endereco(rede)?.let { Formato.endereco(it) }

    companion object {
        fun de(json: JSONObject) = Carteira(
            id = json.getString("id"),
            nome = json.getString("nome"),
            observacao = json.optBoolean("observacao"),
            palavras = if (json.isNull("palavras")) null else json.optInt("palavras"),
            origem = json.optString("origem"),
            palavrasConfirmadas = json.optBoolean("palavrasConfirmadas"),
            temCopia = json.optBoolean("temCopia"),
            temPassphrase = json.optBoolean("temPassphrase"),
            passphraseConfirmada = json.optBoolean("passphraseConfirmada"),
            tronOutraChave = json.optBoolean("tronOutraChave"),
            pedePassphrase = json.optBoolean("pedePassphrase"),
            selecionada = json.optBoolean("selecionada"),
            digital = json.optString("digital").takeIf { it.isNotEmpty() && it != "null" },
            contas = json.optJSONArray("contas").objetos().map { it.getString("rede") to it.getString("endereco") },
            curtos = json.optJSONArray("contas").objetos().filter { it.has("curto") }.associate { it.getString("rede") to it.getString("curto") },
            copiaConfirmadaEm = json.data("copiaConfirmadaEm"),
            passphraseConferidaEm = json.data("passphraseConferidaEm"),
            envelopeLacradoEm = json.data("envelopeLacradoEm"),
            vistaEm = json.data("vistaEm"),
        )
    }
}

/** O estado que decide a tela: o `Estado` do nucleo. */
data class EstadoDoApp(
    val fase: String,
    val pinDigitos: Set<Int>,
    val biometriaLigada: Boolean,
    val biometriaDoSistema: String,
    val pedePINDepoisDeReiniciar: Boolean,
    val atraso: Double,
    val erros: Int,
    val reforcado: Boolean,
    val carteiras: List<Carteira>,
    val selecionada: String?,
    val moeda: String,
    val unidade: String,
    val ocultarSaldos: Boolean,
    val autoTravar: Int,
    val tecladoProprio: Boolean,
    val responsabilidade: Int?,
    val redesDesligadas: Set<String> = emptySet(),
    /** Apagar as carteiras depois de tantos PINs errados seguidos; nulo, nunca. */
    val apagarDepois: Int? = null,
    val opcoesDeApagar: List<Int> = listOf(5, 10, 15, 20),
    val contatos: Int = 0,
    /** O alerta de seguranca por cima de tudo, quando o nucleo manda. */
    val aviso: JSONObject? = null,
) {
    val carteira: Carteira? get() = carteiras.firstOrNull { it.id == selecionada } ?: carteiras.firstOrNull()
    val biometriaPronta: Boolean get() = biometriaDoSistema == "pronta"

    companion object {
        val inicial = EstadoDoApp("carregando", setOf(6), false, "indisponivel", false, 0.0, 0, false, emptyList(), null, "usd", "usd", false, 60, true, null)

        fun de(json: JSONObject): EstadoDoApp {
            val biometria = json.getJSONObject("biometria")
            val ajustes = json.getJSONObject("ajustes")
            return EstadoDoApp(
                fase = json.getString("fase"),
                pinDigitos = json.getJSONArray("pinDigitos").let { lista -> (0 until lista.length()).map { lista.getInt(it) }.toSet() }.ifEmpty { setOf(6) },
                biometriaLigada = biometria.getBoolean("ligada"),
                biometriaDoSistema = biometria.getString("sistema"),
                pedePINDepoisDeReiniciar = biometria.getBoolean("pedePINDepoisDeReiniciar"),
                atraso = json.optDouble("atraso", 0.0),
                erros = json.optInt("erros"),
                reforcado = json.optBoolean("reforcado"),
                carteiras = json.getJSONArray("carteiras").objetos().map(Carteira::de),
                selecionada = json.optString("selecionada").takeIf { it.isNotEmpty() && it != "null" },
                moeda = ajustes.getString("moeda"),
                unidade = ajustes.getString("unidade"),
                ocultarSaldos = ajustes.getBoolean("ocultarSaldos"),
                autoTravar = ajustes.getInt("autoTravar"),
                tecladoProprio = ajustes.optBoolean("tecladoProprio", true),
                responsabilidade = if (json.isNull("responsabilidade")) null else json.optInt("responsabilidade"),
                redesDesligadas = ajustes.optJSONArray("redesDesligadas").textos().toSet(),
                apagarDepois = if (ajustes.has("apagarDepois") && !ajustes.isNull("apagarDepois")) ajustes.getInt("apagarDepois") else null,
                opcoesDeApagar = ajustes.optJSONArray("opcoesDeApagar")?.let { lista -> (0 until lista.length()).map { lista.getInt(it) } } ?: listOf(5, 10, 15, 20),
                contatos = json.optInt("contatos"),
                aviso = json.optJSONObject("aviso"),
            )
        }
    }
}

fun JSONArray?.objetos(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).map { getJSONObject(it) }

fun JSONArray?.textos(): List<String> = if (this == null) emptyList() else (0 until length()).map { getString(it) }

/** O estado do app, observado pela interface. Toda resposta do nucleo que traz o estado passa por aqui. */
object App {
    var estado by mutableStateOf(EstadoDoApp.inicial)
        private set

    fun aplicar(json: JSONObject): JSONObject {
        if (json.has("fase") && json.has("biometria")) estado = EstadoDoApp.de(json)
        return json
    }

    suspend fun recarregar() {
        aplicar(Api.objeto("estado"))
    }
}

/** Uma data do nucleo (milissegundos desde 1970), quando vem. */
fun JSONObject.data(chave: String): Date? = if (has(chave) && !isNull(chave)) Date(getDouble(chave).toLong()) else null
