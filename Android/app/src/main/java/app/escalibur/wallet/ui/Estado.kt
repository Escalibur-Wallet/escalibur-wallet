package app.escalibur.wallet.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.escalibur.wallet.nucleo.Api
import org.json.JSONArray
import org.json.JSONObject

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
    val selecionada: Boolean,
    val digital: String?,
    val contas: List<Pair<String, String>>,
) {
    fun endereco(rede: String): String? = contas.firstOrNull { it.first == rede }?.second

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
            selecionada = json.optBoolean("selecionada"),
            digital = json.optString("digital").takeIf { it.isNotEmpty() && it != "null" },
            contas = json.optJSONArray("contas").objetos().map { it.getString("rede") to it.getString("endereco") },
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
