package app.escalibur.wallet.ui

import android.icu.number.Notation
import android.icu.number.NumberFormatter
import android.icu.number.Precision
import android.icu.text.DecimalFormat
import android.icu.text.DecimalFormatSymbols
import android.icu.text.NumberFormat
import android.icu.util.Currency
import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Toda formatacao de numero, valor e data que o usuario le, num lugar so: o `Fmt` do iOS. O formato
 * da regiao do aparelho (no Brasil, "R$ 1.234,56"), sempre com algarismos latinos, espaco que nao
 * quebra entre simbolo e numero, sinal de menos U+2212 e nunca hifen, cripto truncado para baixo.
 */
object Formato {
    const val menos = "−"
    const val nbsp = " "

    /** A regiao do aparelho com algarismos latinos. */
    val locale: Locale by lazy {
        Locale.Builder().setLocale(Locale.getDefault()).setUnicodeLocaleKeyword("nu", "latn").build()
    }
    private val simbolos by lazy { DecimalFormatSymbols.getInstance(locale) }
    val decimal: String get() = simbolos.decimalSeparator.toString()
    private val grupo: String get() = simbolos.groupingSeparator.toString()
    /** O separador de milhar da regiao ("." no Brasil, "," em ingles), para o campo que agrupa enquanto digita. */
    val milhar: String get() = grupo

    /** Onde a regiao poe o simbolo da moeda: antes ("R$ 10,00") ou depois ("10,00 €"). */
    private val simboloAntes: Boolean by lazy {
        val padrao = (NumberFormat.getCurrencyInstance(locale) as? DecimalFormat)?.toPattern() ?: "¤#"
        padrao.trim().startsWith("¤")
    }

    fun dinheiro(corpo: String, simbolo: String, sinal: String = ""): String =
        if (simboloAntes) "$sinal$simbolo$nbsp$corpo" else "$sinal$corpo$nbsp$simbolo"

    /** O simbolo de cada moeda como a regiao escreve: "US$" no Brasil, "$" nos EUA. */
    fun simboloDaMoeda(codigo: String): String = when (codigo.uppercase()) {
        "BTC" -> "₿"
        else -> runCatching { Currency.getInstance(codigo.uppercase()).getSymbol(locale) }.getOrDefault(codigo.uppercase())
    }

    /** Valor numa unidade ("brl", "usd", "eur", "btc"): centavos e "< R$ 0,01"; ₿ com ate 8 casas. */
    fun valor(valor: Double, unidade: String, comSinal: Boolean = false): String {
        val simbolo = simboloDaMoeda(unidade)
        if (!valor.isFinite()) return dinheiro("0", simbolo)
        val magnitude = kotlin.math.abs(valor)
        val sinal = if (valor < 0) menos else if (comSinal && valor > 0) "+" else ""
        if (unidade == "btc") {
            if (magnitude > 0 && magnitude < 0.00000001) return "< " + dinheiro("0${decimal}00000001", simbolo)
            return dinheiro(agrupado(magnitude, 8, aparar = true), simbolo, sinal)
        }
        if (magnitude > 0 && magnitude < 0.01) return "< " + dinheiro("0${decimal}01", simbolo)
        return dinheiro(agrupado(magnitude, 2), simbolo, sinal)
    }

    /** Preco unitario com casas pela faixa, e zeros em subscrito abaixo de 0,0001. */
    fun preco(valor: Double, unidade: String): String {
        val simbolo = simboloDaMoeda(unidade)
        if (!valor.isFinite() || valor <= 0) return dinheiro("0${decimal}00", simbolo)
        if (unidade == "btc") return dinheiro(if (valor >= 0.00000001) agrupado(valor, 8, aparar = true) else zerosEmSubscrito(valor), simbolo)
        val corpo = when {
            valor >= 1 -> agrupado(valor, 2)
            valor >= 0.01 -> agrupado(valor, 4)
            valor >= 0.0001 -> agrupado(valor, 6)
            else -> zerosEmSubscrito(valor)
        }
        return dinheiro(corpo, simbolo)
    }

    /** "+2,31%". Zero sai sem sinal. A partir de 1.000%, sem casas. */
    fun percentual(valor: Double): String {
        if (!valor.isFinite()) return "0${decimal}00%"
        val arredondado = Math.round(valor * 100) / 100.0
        if (arredondado == 0.0) return "0${decimal}00%"
        val sinal = if (arredondado > 0) "+" else menos
        val casas = if (kotlin.math.abs(arredondado) >= 1000) 0 else 2
        return "$sinal${agrupado(kotlin.math.abs(arredondado), casas)}%"
    }

    /** "12,3 mil", "812 mi" no Brasil; "12.3K", "812M" nos EUA. So para dado de mercado. */
    fun compacto(valor: Double, unidade: String? = null): String {
        val texto = if (valor >= 1000) {
            NumberFormatter.withLocale(locale).notation(Notation.compactShort()).precision(Precision.maxSignificantDigits(3)).format(valor).toString()
        } else agrupado(valor, 0)
        return if (unidade != null) dinheiro(texto, simboloDaMoeda(unidade)) else texto
    }

    enum class EstiloCripto { lista, cheio, estavel }

    /** Valor de token a partir do inteiro da rede (texto decimal), truncado para baixo. */
    fun cripto(quantidade: String, casas: Int, simbolo: String? = null, estilo: EstiloCripto = EstiloCripto.lista): String {
        val (inteiro, fracao) = dividir(quantidade, casas)
        val casasMostradas = when (estilo) {
            EstiloCripto.estavel -> 2
            EstiloCripto.cheio -> minOf(casas, 8)
            EstiloCripto.lista -> {
                val digitosInteiros = if (inteiro == "0") 0 else inteiro.length
                when {
                    digitosInteiros >= 6 -> 0
                    digitosInteiros > 0 -> minOf(6 - digitosInteiros, 8)
                    else -> minOf(fracao.takeWhile { it == '0' }.length + 6, 8)
                }
            }
        }
        var textoDaFracao = fracao.take(casasMostradas)
        if (estilo != EstiloCripto.estavel) textoDaFracao = textoDaFracao.trimEnd('0')
        val zeroMostrado = inteiro == "0" && textoDaFracao.all { it == '0' }
        val naoZero = quantidade.trimStart('0').isNotEmpty()
        var texto = if (zeroMostrado && naoZero) {
            "< 0" + decimal + "0".repeat(maxOf(casasMostradas - 1, 0)) + "1"
        } else {
            agruparInteiro(inteiro) + if (textoDaFracao.isEmpty()) "" else decimal + textoDaFracao
        }
        if (simbolo != null) texto += " $simbolo"
        return texto
    }

    /** O inteiro da rede como numero, so para multiplicar por preco e mostrar. */
    fun numero(quantidade: String, casas: Int): Double = runCatching { BigDecimal(BigInteger(quantidade), casas).toDouble() }.getOrDefault(0.0)

    /**
     * Le o valor digitado ("1,5" ou "1.5") para o inteiro da rede, sem ponto flutuante. Casas demais
     * sao recusadas, nao arredondadas. Onde a virgula separa milhar, ela nao vale como decimal.
     */
    fun lerQuantidade(texto: String, casas: Int): BigInteger? {
        val cru = texto.replace(" ", "").replace(nbsp, "")
        if (decimal == "." && cru.contains(",")) return null
        val limpo = cru.replace(".", ",")
        val partes = limpo.split(",")
        if (partes.size > 2 || cru.isEmpty()) return null
        val inteiro = partes[0].ifEmpty { "0" }
        val fracao = if (partes.size == 2) partes[1] else ""
        if (fracao.length > casas || !inteiro.all(Char::isDigit) || !fracao.all(Char::isDigit)) return null
        return BigInteger(inteiro + fracao + "0".repeat(casas - fracao.length))
    }

    /** O inteiro da rede em texto decimal simples, para os campos editaveis. */
    fun decimalSimples(quantidade: String, casas: Int): String {
        val (inteiro, fracao) = dividir(quantidade, casas)
        val aparada = fracao.trimEnd('0')
        return if (aparada.isEmpty()) inteiro else inteiro + decimal + aparada
    }

    /** "0x71C7A3…976F": 6 e 4 do texto. */
    fun endereco(texto: String, inicio: Int = 6, fim: Int = 4): String =
        if (texto.length <= inicio + fim + 1) texto else texto.take(inicio) + "…" + texto.takeLast(fim)

    /** "1 segundo", "5 minutos", "3 horas", "2 dias", arredondado para cima. */
    fun duracao(segundos: Double): String {
        val s = kotlin.math.ceil(segundos).toInt()
        if (s < 60) return if (s == 1) t("1 segundo") else t("%lld segundos", s)
        val m = kotlin.math.ceil(s / 60.0).toInt()
        if (m < 60) return if (m == 1) t("1 minuto") else t("%lld minutos", m)
        val h = kotlin.math.ceil(m / 60.0).toInt()
        if (h < 48) return if (h == 1) t("1 hora") else t("%lld horas", h)
        return t("%lld dias", kotlin.math.ceil(h / 24.0).toInt())
    }

    /** "14:32" no Brasil, "2:32 PM" nos EUA. */
    fun relogio(data: Date): String = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT, locale).format(data)

    /** "agora", "há 5 min", "Hoje, 14:32", "Ontem, 14:32", "3 out, 14:32". */
    fun relativo(data: Date, agora: Date = Date(), naFrase: Boolean = false): String {
        val segundos = (agora.time - data.time) / 1000
        if (segundos < 60) return t("agora")
        if (segundos < 3600) return t("há %lld min", (segundos / 60).toInt())
        val hora = relogio(data)
        if (mesmoDia(data, agora)) return if (naFrase) t("hoje, %@", hora) else t("Hoje, %@", hora)
        if (mesmoDia(data, Date(agora.time - 86_400_000))) return if (naFrase) t("ontem, %@", hora) else t("Ontem, %@", hora)
        return t("%@, %@", diaCurto(data), hora)
    }

    /** "14:32", "ontem, 14:32" ou "3 out, 14:32": quando um dado foi lido (o `stamp` do iOS). */
    fun carimbo(data: Date, agora: Date = Date()): String {
        val hora = relogio(data)
        if (mesmoDia(data, agora)) return hora
        if (mesmoDia(data, Date(agora.time - 86_400_000))) return t("ontem, %@", hora)
        return t("%@, %@", diaCurto(data), hora)
    }

    /** "7 de mai de 2021". */
    fun diaLongo(data: Date): String {
        val texto = SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(locale, "dMMMyyyy"), locale).format(data)
        return if (locale.language == "pt") texto.replace(".", "") else texto
    }

    private fun mesmoDia(a: Date, b: Date): Boolean {
        val x = Calendar.getInstance().apply { time = a }
        val y = Calendar.getInstance().apply { time = b }
        return x.get(Calendar.YEAR) == y.get(Calendar.YEAR) && x.get(Calendar.DAY_OF_YEAR) == y.get(Calendar.DAY_OF_YEAR)
    }

    private fun diaCurto(data: Date): String {
        val padrao = android.text.format.DateFormat.getBestDateTimePattern(locale, "dMMM")
        val texto = SimpleDateFormat(padrao, locale).format(data)
        return if (locale.language == "pt") texto.replace(".", "") else texto
    }

    fun agrupado(valor: Double, casas: Int, aparar: Boolean = false): String {
        val formato = NumberFormat.getNumberInstance(locale) as DecimalFormat
        formato.isGroupingUsed = true
        formato.maximumFractionDigits = casas
        formato.minimumFractionDigits = if (aparar) 0 else casas
        formato.roundingMode = BigDecimal.ROUND_HALF_UP
        return formato.format(valor)
    }

    private fun agruparInteiro(digitos: String): String {
        val reverso = digitos.reversed().chunked(3).joinToString(grupo)
        return reverso.reversed()
    }

    private fun dividir(quantidade: String, casas: Int): Pair<String, String> {
        val digitos = quantidade.trimStart('0').ifEmpty { "0" }
        if (casas <= 0) return digitos to ""
        if (digitos.length <= casas) return "0" to "0".repeat(casas - digitos.length) + digitos
        return digitos.dropLast(casas) to digitos.takeLast(casas)
    }

    fun zerosEmSubscrito(valor: Double): String {
        if (!valor.isFinite() || valor <= 0) return "0"
        val cientifico = String.format(Locale.US, "%.3e", valor).split("e")
        val expoente = cientifico.getOrNull(1)?.toIntOrNull() ?: return agrupado(valor, 4)
        if (expoente >= 0) return agrupado(valor, 4)
        val significativos = cientifico[0].filter(Char::isDigit)
        val zeros = -expoente - 1
        val subscritos = "₀₁₂₃₄₅₆₇₈₉"
        return "0${decimal}0" + zeros.toString().map { subscritos[it - '0'] }.joinToString("") + significativos
    }

    @Suppress("unused")
    private val arredondamento = RoundingMode.DOWN
}
