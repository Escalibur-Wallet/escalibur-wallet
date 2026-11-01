package app.escalibur.wallet.ui.envelope

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.comp.PixelsCifrando
import app.escalibur.wallet.ui.comp.movimentoReduzido
import app.escalibur.wallet.ui.comp.relogio
import app.escalibur.wallet.ui.tema.Letra
import app.escalibur.wallet.ui.tema.Paleta
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

/** Onde o lacre de verdade esta: fazendo a conta da senha, gravando, lacrado. */
enum class EtapaDoLacre { trabalhando, gravando, lacrado }

/**
 * "A senha da carteira entra no envelope", em pixels (o `EnvelopePixelScene` do iOS): tres palavras ja
 * cifradas se desfazem em pixels cinza que cifram e caem pela boca do envelope. O envelope inteiro e de
 * pixels que cifram ao vivo: a aba fecha dobrando como papel, um cadeado de pixels se monta no meio e
 * um anel de pixels acende em verde em volta dele, em ordem. Em laco.
 *
 * Com `etapa`, a historia anda com o lacre de verdade e para no lacrado. Abrir um envelope tem a cena
 * propria (`CenaDeAbrirEnvelope`, 24/10/2026). Com o movimento reduzido, parado.
 */
@Composable
fun CenaDoEnvelope(modifier: Modifier = Modifier, altura: Dp = 236.dp, etapa: EtapaDoLacre? = null) {
    val parado = movimentoReduzido()
    val relogio = relogio(parado)
    // Onde a historia estava quando a etapa mudou, e quando: a cena segue dali.
    var ancora by remember { mutableStateOf(0.0 to 0.0) }
    var etapaDeAntes by remember { mutableStateOf(etapa) }
    LaunchedEffect(etapa) {
        if (etapa == etapaDeAntes) return@LaunchedEffect
        val agora = relogio.value.toDouble()
        ancora = tempoDaHistoria(agora, etapaDeAntes, ancora) to agora
        etapaDeAntes = etapa
    }
    val medidor = rememberTextMeasurer()
    Canvas(modifier.fillMaxWidth().height(altura)) {
        val agora = relogio.value.toDouble()
        val escala = min(size.width / G.largura, size.height / G.altura)
        translate((size.width - G.largura * escala) / 2, (size.height - G.altura * escala) / 2) {
            withTransform({ scale(escala, escala, Offset.Zero) }) {
                val cena = Cena(this, medidor, agora, etapa, parado)
                val t = if (parado) T.esmaeceDe - 0.3 else tempoDaHistoria(agora, etapa, ancora)
                cena.desenhar(t)
            }
        }
    }
}

/** O alto vazio da cena depois que as palavras caem (acima da aba aberta): quem centraliza a cena no lacre desconta a metade dele. */
val AltoVazioDaCena = 116.dp

/** O tempo da historia: em laco nas telas de explicar; no lacre, andando de onde parou ate o teto da etapa. */
private fun tempoDaHistoria(agora: Double, etapa: EtapaDoLacre?, ancora: Pair<Double, Double>): Double {
    if (etapa == null) return agora % T.periodo
    // As palavras voam para o envelope enquanto o app faz a conta da senha; gravando, a aba fecha;
    // lacrado, o cadeado e o anel, um pouco mais rapido se a historia ficou para tras.
    val (teto, ritmo) = when (etapa) {
        EtapaDoLacre.trabalhando -> (T.abaDe - 0.05) to 1.0
        EtapaDoLacre.gravando -> (T.lacreDe - 0.05) to 1.4
        EtapaDoLacre.lacrado -> (T.esmaeceDe - 0.05) to (if (ancora.first < T.anelDe) 1.8 else 1.0)
    }
    return min(teto, ancora.first + (agora - ancora.second) * ritmo)
}

/** O desenho num quadro fixo, escalado para caber. */
private object G {
    const val largura = 300f
    const val altura = 236f
    val envelope = Rect(60f, 120f, 240f, 224f)
    const val alturaDaAba = 104f * 0.58f
    val boca = Offset(150f, 166f)
    val lacre = Offset(150f, 178f)
    val chip = Size(82f, 30f)
    val chips = floatArrayOf(21f, 109f, 197f)
    const val chipY = 16f
    const val celula = 5f
    const val passo = 6.6f
    const val anel = 28
    /** A grade do envelope: um pixel a cada 6 pontos. */
    const val grade = 6f
    const val celulaDaGrade = 4.6f
    val colunas = (180f / grade).toInt()
    val linhas = (104f / grade).toInt()
    /** Quantas linhas a aba tem, da borda de cima ate a ponta. */
    val linhasDaAba = (alturaDaAba / grade).roundToInt()
    /** O cadeado em pixels: arco em cima, corpo embaixo, o buraco da chave no meio. */
    val cadeado = listOf("..#####..", ".##...##.", ".#.....#.", ".#.....#.", "#########",
                         "#########", "####.####", "####.####", "#########", "#########")
}

/** A historia, em segundos dentro do laco. */
private object T {
    const val periodo = 6.6
    const val quebraDe = 0.7
    const val quebraPasso = 0.32
    const val voo = 0.75
    const val abaDe = 2.45
    const val abaTempo = 0.45
    const val lacreDe = 2.95
    const val anelDe = 3.15
    const val anelTempo = 0.45
    const val esmaeceDe = 6.0
}

/** A abertura, em segundos dentro do laco dela. */
private class Cena(val d: DrawScope, val medidor: TextMeasurer, val relogio: Double, val etapa: EtapaDoLacre?, val parado: Boolean) {
    private var alfa = 1f

    fun desenhar(t: Double) {
        // Tudo some junto no fim do laco e nasce de novo no comeco.
        alfa = min(suave(t / 0.35), 1 - suave((t - T.esmaeceDe) / (T.periodo - T.esmaeceDe))).toFloat().coerceIn(0f, 1f)
        // O envelope fica no lugar ao fechar. Lacrado, sem a passada de luz: so cifrando.
        val fechando = if (parado) 1.0 else entraESai((t - T.abaDe) / T.abaTempo)
        envelope(fechando, varrendo = etapa != EtapaDoLacre.lacrado)
        pixels(t)
        chips(t)
        cadeado(t)
        anel(t)
    }

    private fun quadrado(cor: Color, x: Float, y: Float, w: Float, h: Float, raio: Float, a: Float = alfa) =
        d.drawRoundRect(cor, Offset(x, y), Size(w, h), CornerRadius(raio), alpha = a.coerceIn(0f, 1f))

    /** Um pixel da grade do envelope (linha negativa: acima da borda de cima, onde fica a aba aberta). */
    private fun celula(coluna: Int, linha: Int): Rect {
        val recuo = (G.grade - G.celulaDaGrade) / 2
        val x = G.envelope.left + coluna * G.grade + recuo
        val y = G.envelope.top + linha * G.grade + recuo
        return Rect(x, y, x + G.celulaDaGrade, y + G.celulaDaGrade)
    }

    /**
     * O envelope de pixels, cifrando ao vivo: o corpo, a borda e as dobras mais claras, e uma passada
     * de luz que corre devagar. A aba dobra na borda de cima como papel: aberta para cima, achata na
     * dobra e desce sobre o envelope (`fechando`, de 0 a 1).
     */
    private fun envelope(fechando: Double, varrendo: Boolean) {
        val e = G.envelope
        val dobra = Offset(e.center.x, e.top + e.height * 0.5f)
        val passada = ((relogio / 2.2) % 1.0).toFloat() * (e.width + 80) + e.left - 40
        fun luz(centro: Offset): Double {
            if (!varrendo) return 0.0
            val x = ((centro.x - passada + (centro.y - e.top) * 0.5f) / 18).toDouble()
            return 0.08 * exp(-x * x)
        }
        for (coluna in 0 until G.colunas) for (linha in 0 until G.linhas) {
            val r = celula(coluna, linha)
            val id = 5000 + coluna * G.linhas + linha
            val borda = coluna == 0 || coluna == G.colunas - 1 || linha == 0 || linha == G.linhas - 1
            val naDobra = distancia(r.center, Offset(e.left, e.top), dobra) < G.grade * 0.6f ||
                distancia(r.center, Offset(e.right, e.top), dobra) < G.grade * 0.6f
            val bit = tom(id, relogio)
            // Cinza escuro, quase preto; a borda e as dobras um pouco mais claras.
            var tom = 0.06 + 0.07 * bit
            if (borda) tom = 0.22 + 0.1 * bit else if (naDobra) tom = 0.15 + 0.06 * bit
            tom += luz(r.center)
            quadrado(PixelsCifrando.cinza(tom), r.left, r.top, r.width, r.height, 1.1f)
        }
        // A aba: cada pixel na sua distancia da dobra, multiplicada pela abertura (-1 aberta para
        // cima, 0 achatada na dobra, 1 fechada), e achatado junto, como papel virando.
        val vira = (-1 + 2 * fechando).toFloat()
        val achata = max(abs(vira), 0.08f)
        for (linha in 0 until G.linhasDaAba) {
            val metade = (1 - (linha + 0.5f) / G.linhasDaAba) * e.width / 2 + G.grade * 0.5f
            for (coluna in 0 until G.colunas) {
                val casa = celula(coluna, linha)
                val foraDoMeio = abs(casa.center.x - e.center.x)
                if (foraDoMeio > metade) continue
                val h = casa.height * achata
                val y = e.top + (casa.center.y - e.top) * vira - h / 2
                val aro = foraDoMeio > metade - G.grade * 1.2f
                val bit = tom(7000 + coluna * 40 + linha, relogio)
                val tom = (if (aro) 0.22 + 0.1 * bit else 0.09 + 0.07 * bit) + luz(Offset(casa.center.x, y + h / 2))
                quadrado(PixelsCifrando.cinza(tom), casa.left, y, casa.width, h, min(1.1f, h / 2))
            }
        }
    }

    /** As tres palavras cifradas no alto, que somem quando viram pixels. */
    private fun chips(t: Double) {
        val tique = max(relogio * 12, 0.0).toLong()
        G.chips.forEachIndexed { indice, x ->
            val quebra = T.quebraDe + indice * T.quebraPasso
            val a = alfa * (1 - suave((t - quebra) / 0.22)).toFloat()
            if (a <= 0.01f) return@forEachIndexed
            val r = Rect(Offset(x, G.chipY), G.chip)
            d.drawRoundRect(Paleta.vazio, r.topLeft, r.size, CornerRadius(9f), alpha = a)
            d.drawRoundRect(Paleta.bordaForte, r.topLeft, r.size, CornerRadius(9f), style = Stroke(1f), alpha = a)
            texto("${indice + 1}", numero, Paleta.tintaApagada, r.left + 12, r.center.y, a, centro = true)
            texto(CifraDoEnvelope.glifos(indice, tique), glifo, Paleta.tintaSuave, r.left + 24, r.center.y, a)
        }
    }

    private fun texto(texto: String, estilo: TextStyle, cor: Color, x: Float, yDoMeio: Float, a: Float, centro: Boolean = false) {
        if (a <= 0.01f) return
        val medida = medidor.measure(texto, estilo)
        val esquerda = if (centro) x - medida.size.width / 2f else x
        d.drawText(medida, cor, Offset(esquerda, yDoMeio - medida.size.height / 2f), alpha = a.coerceIn(0f, 1f))
    }

    /** Cada palavra vira uma grade de pixels que cifram e voam ate a boca do envelope. */
    private fun pixels(t: Double) {
        val colunas = (G.chip.width / G.passo).toInt()
        val linhas = (G.chip.height / G.passo).toInt()
        G.chips.forEachIndexed { indice, x ->
            val quebra = T.quebraDe + indice * T.quebraPasso
            if (t <= quebra - 0.05) return@forEachIndexed
            for (coluna in 0 until colunas) for (linha in 0 until linhas) {
                val id = indice * 100 + coluna * linhas + linha
                val atraso = PixelsCifrando.ruido(id, 7, 0x3C1) * 0.35
                val p = suave((t - quebra - atraso) / T.voo)
                if (p >= 0.999 || p < 0.02) continue
                val de = Offset(x + 4 + coluna * G.passo, G.chipY + 2 + linha * G.passo)
                val espalha = (PixelsCifrando.ruido(id, 11, 0x5A) - 0.5).toFloat() * 36
                val para = Offset(G.boca.x + espalha, G.boca.y)
                // Uma curva: sobe um pouco, depois cai para dentro.
                val controle = Offset((de.x + para.x) / 2, min(de.y, para.y) - 10)
                val u = p.toFloat()
                val px = (1 - u) * (1 - u) * de.x + 2 * (1 - u) * u * controle.x + u * u * para.x
                val py = (1 - u) * (1 - u) * de.y + 2 * (1 - u) * u * controle.y + u * u * para.y
                val lado = G.celula * (1 - 0.35f * u)
                val tom = 0.22 + 0.32 * tom(id, relogio) + 0.2 * (1 - u)
                quadrado(PixelsCifrando.cinza(tom), px - lado / 2, py - lado / 2, lado, lado, 1.2f)
            }
        }
    }

    /** O cadeado de pixels, que se monta no meio depois que a aba fecha, sobre um disco preto. */
    private fun cadeado(t: Double) {
        val p = saida((t - T.lacreDe) / 0.25)
        if (p <= 0) return
        val a = alfa * p.toFloat()
        d.drawCircle(Color.Black, 23f, G.lacre, alpha = a)
        val passo = 3.6f
        val lado = 3.0f
        val linhas = G.cadeado.size
        val colunas = G.cadeado[0].length
        val origem = Offset(G.lacre.x - colunas * passo / 2, G.lacre.y - linhas * passo / 2)
        G.cadeado.forEachIndexed { linha, desenho ->
            desenho.forEachIndexed { coluna, marca ->
                if (marca != '#') return@forEachIndexed
                // Cada pixel chega no seu instante: o cadeado se monta, nao aparece pronto.
                val chega = T.lacreDe + PixelsCifrando.ruido(coluna, linha, 0x10C) * 0.3
                if (t < chega && !parado) return@forEachIndexed
                quadrado(Paleta.tinta, origem.x + coluna * passo, origem.y + linha * passo, lado, lado, 0.6f, a)
            }
        }
    }

    /** O anel de pixels em volta do cadeado, acendendo em verde em ordem: trancado e conferido. */
    private fun anel(t: Double) {
        if (t <= T.lacreDe) return
        for (indice in 0 until G.anel) {
            val angulo = indice.toDouble() / G.anel * 2 * Math.PI - Math.PI / 2
            val x = G.lacre.x + 34 * cos(angulo).toFloat()
            val y = G.lacre.y + 34 * sin(angulo).toFloat()
            val acendeEm = T.anelDe + indice.toDouble() / G.anel * T.anelTempo
            val aceso = t >= acendeEm
            val clarao = if (aceso) exp(-max(t - acendeEm, 0.0) * 6) else 0.0
            val lado = 4.6f + 1.6f * clarao.toFloat()
            quadrado(if (aceso) Paleta.sucesso else PixelsCifrando.cinza(0.2), x - lado / 2, y - lado / 2, lado, lado, 1.2f)
            if (clarao > 0.02) quadrado(Color.White, x - lado / 2, y - lado / 2, lado, lado, 1.2f, alfa * 0.5f * clarao.toFloat())
        }
    }

    // Os textos medem em unidades da cena (o desenho ja esta escalado): o tamanho vai em "px" da cena.
    private val numero = TextStyle(fontFamily = Letra.familia(FontWeight.Medium, 11f), fontWeight = FontWeight.Medium,
                                   fontSize = emUnidades(11f), fontFeatureSettings = "tnum")
    private val glifo = TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium, fontSize = emUnidades(13f))

    private fun emUnidades(valor: Float): TextUnit = TextUnit(valor / (d.density * d.fontScale), TextUnitType.Sp)
}

/** Distancia, em pontos, do centro de um pixel ate a reta de a ate b. */
private fun distancia(p: Offset, a: Offset, b: Offset): Float {
    val dx = b.x - a.x
    val dy = b.y - a.y
    val u = (((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)).coerceIn(0f, 1f)
    return hypot(p.x - (a.x + u * dx), p.y - (a.y + u * dy))
}

/** O tom cifrado de um pixel agora, de 0 a 1, trocando no compasso dele. */
private fun tom(id: Int, relogio: Double): Double {
    val fase = PixelsCifrando.ruido(id, 3, 0x77)
    val batida = relogio * 7 * (0.6 + 0.8 * fase) + fase * 8
    val degrau = floor(batida)
    val mistura = suave(batida - degrau)
    val a = PixelsCifrando.ruido(id, 3, degrau.toLong())
    val b = PixelsCifrando.ruido(id, 3, degrau.toLong() + 1)
    return a + (b - a) * mistura
}

internal fun suave(x: Double): Double { val t = x.coerceIn(0.0, 1.0); return t * t * (3 - 2 * t) }
private fun saida(x: Double): Double { val t = x.coerceIn(0.0, 1.0); return 1 - (1 - t) * (1 - t) * (1 - t) }
private fun entraESai(x: Double): Double { val t = x.coerceIn(0.0, 1.0); return if (t < 0.5) 4 * t * t * t else 1 - (-2 * t + 2).pow(3) / 2 }

/** Os glifos do cifrado e as palavras de exemplo, os mesmos do iOS. Nenhuma palavra de verdade. */
internal object CifraDoEnvelope {
    val exemplo = listOf("ocean", "figure", "velvet", "canyon", "ripple", "lamp", "orbit", "meadow", "silver", "tiger", "harbor", "puzzle")
    private const val alfabeto = "0123456789ABCDEF"

    /** Quatro glifos por palavra, como a cifra viva mostra a palavra (sem contar o tamanho dela). So desenho: sai de um contador (SplitMix64). */
    fun glifos(indice: Int, tique: Long): String {
        // Palavra e quadro misturados antes de andar: sem isso, cada palavra repetia os glifos da vizinha.
        var x = mistura(mistura((indice + 1).toULong() * 0xD6E8FEB86659FD93uL) xor tique.toULong())
        return buildString {
            repeat(4) {
                x += 0x9E3779B97F4A7C15uL
                append(alfabeto[(mistura(x) % 16uL).toInt()])
            }
        }
    }

    private fun mistura(valor: ULong): ULong {
        var z = valor
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }
}
