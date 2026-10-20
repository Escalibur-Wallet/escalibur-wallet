package app.escalibur.wallet.ui

import android.content.Context
import android.icu.text.PluralRules
import org.json.JSONObject
import java.util.Locale

/**
 * Os textos do app. A chave e a frase em portugues, a mesma do iOS: a traducao vem da tabela do
 * idioma do aparelho (gerada no build do catalogo do iOS, assets/textos). Os argumentos seguem o
 * formato do iOS: %@ (texto), %lld (inteiro), %lf (fracionario) e as posicoes %1$@.
 */
object Textos {
    /** Os idiomas que o app tem, alem do portugues (o original). */
    private val idiomas = listOf("en", "es", "fr", "de", "hi", "id", "ja", "ko", "tr", "zh-Hans", "vi", "ar")

    @Volatile private var tabela: JSONObject = JSONObject()
    @Volatile var locale: Locale = Locale.forLanguageTag("pt-BR")
        private set
    private var plurais: PluralRules = PluralRules.forLocale(locale)

    /** O codigo do idioma escolhido ("pt-BR", "en"...). */
    @Volatile var idioma: String = "pt-BR"
        private set

    fun carregar(contexto: Context) {
        val local = contexto.resources.configuration.locales[0]
        val escolhido = escolher(local)
        idioma = escolhido ?: "pt-BR"
        locale = if (escolhido == null) Locale.forLanguageTag("pt-BR") else local
        plurais = PluralRules.forLocale(locale)
        tabela = runCatching {
            contexto.assets.open("textos/$idioma.json").use { JSONObject(it.readBytes().decodeToString()) }
        }.getOrElse { JSONObject() }
    }

    private fun escolher(local: Locale): String? {
        val lingua = local.language
        if (lingua == "pt") return null
        if (lingua == "zh") return "zh-Hans"
        if (lingua == "in") return "id"
        return idiomas.firstOrNull { it == lingua }
    }

    /** A tabela inteira, para o nucleo traduzir o que ele grava (nome de carteira, motivo). */
    fun tabela(chaves: List<String>): Map<String, String> = chaves.associateWith { t(it) }

    fun t(chave: String, vararg argumentos: Any?): String {
        val valor = tabela.opt(chave)
        val modelo = when (valor) {
            is String -> valor
            is JSONObject -> forma(valor, argumentos) ?: chave
            else -> chave
        }
        return if (argumentos.isEmpty()) modelo else preencher(modelo, argumentos)
    }

    /** O plural pelo primeiro argumento numerico. */
    private fun forma(formas: JSONObject, argumentos: Array<out Any?>): String? {
        val numero = argumentos.firstOrNull { it is Number } as? Number ?: return formas.optString("other", null)
        val categoria = plurais.select(numero.toDouble())
        return formas.optString(categoria, null) ?: formas.optString("other", null)
    }

    private val especificador = Regex("%(\\d+\\$)?(@|lld|llu|ld|lu|d|lf|f|\\.\\d+f|%)")

    fun preencher(modelo: String, argumentos: Array<out Any?>): String {
        var proximo = 0
        return especificador.replace(modelo) { achado ->
            val tipo = achado.groupValues[2]
            if (tipo == "%") return@replace "%"
            val posicao = achado.groupValues[1].dropLast(1).toIntOrNull()?.minus(1) ?: proximo++
            val valor = argumentos.getOrNull(posicao)
            when {
                tipo.startsWith(".") && valor is Number -> String.format(locale, "%${tipo}", valor.toDouble())
                else -> valor?.toString() ?: ""
            }
        }
    }
}

/** Atalho: `t("Escolha um PIN")`. */
fun t(chave: String, vararg argumentos: Any?): String = Textos.t(chave, *argumentos)
