package app.escalibur.wallet.ui.comp

import android.graphics.Paint
import android.graphics.Typeface
import android.text.TextPaint
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFontFamilyResolver
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import app.escalibur.wallet.ui.tema.Letra
import kotlin.math.ceil

/** O que a medida decidiu: o pincel (encolhido, se a palavra nao cabia) e, por grafema, onde comeca, quantos chars e a largura. */
private class Medida(val tinta: TextPaint, val inicios: IntArray, val tamanhos: IntArray, val larguras: FloatArray, val base: Float)

/** Continua o grafema de antes: marca (acento solto do NFKD, o dakuten do japones), vogal ou final do Hangul em jamo,
 * seletor de variacao. */
private fun continuaGrafema(ponto: Int): Boolean = when (Character.getType(ponto).toByte()) {
    Character.NON_SPACING_MARK, Character.ENCLOSING_MARK, Character.COMBINING_SPACING_MARK -> true
    else -> ponto in 0x1160..0x11FF || ponto in 0xD7B0..0xD7FF || ponto in 0xFE00..0xFE0F
}

/**
 * Uma palavra da frase desenhada direto do CharArray, sem virar String. O `Text` guarda a String no layout e no no de
 * semantica, que ficam no heap do Java sem ter como zerar (auditoria das chaves de 06/11/2026). O CharArray e do
 * [app.escalibur.wallet.nucleo.PalavrasNaTela] que o leu do nucleo, e ele zera quando a tela sai. Sem semantica de texto:
 * nenhum servico de acessibilidade le a palavra (a janela ja e marcada como dado sensivel).
 *
 * Grafema a grafema (a letra com os acentos dela; as partes de uma silaba do Hangul juntas): o texto do Android guarda
 * copias do que mede e desenha (o cache de layout do Minikin, o buffer do MeasuredParagraph, o temporario do Canvas), e
 * assim nenhuma delas tem a palavra inteira, so pedacos de uma letra (revisao dos pendentes de 07/11/2026). O desenho
 * vai de um rascunho do tamanho de um grafema (`drawText(char[], ...)`, sem CharSequence), zerado depois. As listas do BIP-39 nao tem escrita que se liga
 * letra a letra (como o arabe), entao nada muda na forma.
 *
 * Nunca corta: a palavra que nao cabe na largura encolhe ate caber. Uma letra cortada na chapa ("abstrac") vira um
 * backup com a palavra errada (8 letras em 20 sp nao cabiam numa tela de 360 dp).
 *
 * `camadas`: copias por baixo, deslocadas na vertical (o baixo-relevo da chapa de aco).
 */
@Composable
fun TextoSecreto(
    letras: CharArray,
    tamanho: TextUnit,
    peso: FontWeight,
    cor: Color,
    modifier: Modifier = Modifier,
    familia: FontFamily = FontFamily.Monospace,
    camadas: List<Pair<Color, Dp>> = emptyList(),
) {
    val densidade = LocalDensity.current
    val resolvedor = LocalFontFamilyResolver.current
    val pincel = remember(tamanho, peso, familia, densidade) {
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = with(densidade) { tamanho.toPx() }
            typeface = resolvedor.resolve(familia, peso).value as? Typeface ?: Typeface.create(Typeface.DEFAULT, peso.weight, false)
            letterSpacing = Letra.espacoNatural(15f)
        }
    }
    // Onde cada grafema comeca e quantos chars tem: posicoes, nada da palavra.
    val grafemas = remember(letras) {
        val inicios = mutableListOf<Int>()
        val tamanhos = mutableListOf<Int>()
        var indice = 0
        while (indice < letras.size) {
            val inicio = indice
            indice += Character.charCount(Character.codePointAt(letras, indice))
            while (indice < letras.size) {
                val ponto = Character.codePointAt(letras, indice)
                if (!continuaGrafema(ponto)) break
                indice += Character.charCount(ponto)
            }
            inicios.add(inicio)
            tamanhos.add(indice - inicio)
        }
        inicios.toIntArray() to tamanhos.toIntArray()
    }
    val medida = remember { arrayOfNulls<Medida>(1) }
    // Cada grafema vai para a ponte nativa a partir deste rascunho, zerado depois: o `drawText`/`measureText` de um
    // `char[]` copia o array inteiro na JNI, e assim ela so ve o grafema (revisao dos pendentes de 07/11/2026).
    val rascunho = remember(grafemas) { CharArray(maxOf(2, grafemas.second.maxOrNull() ?: 0)) }
    fun copiar(indice: Int): Int {
        val (inicios, tamanhos) = grafemas
        val tamanho = tamanhos[indice]
        if (inicios[indice] + tamanho > letras.size) return 0
        letras.copyInto(rascunho, 0, inicios[indice], inicios[indice] + tamanho)
        return tamanho
    }
    Layout(
        modifier = modifier.drawWithContent {
            val atual = medida[0] ?: return@drawWithContent
            drawIntoCanvas { canvas ->
                val nativo = canvas.nativeCanvas
                fun desenhar() {
                    var x = 0f
                    for (indice in atual.inicios.indices) {
                        val tamanho = copiar(indice)
                        if (tamanho > 0) nativo.drawText(rascunho, 0, tamanho, x, atual.base, atual.tinta)
                        x += atual.larguras[indice]
                    }
                    rascunho.fill('\u0000')
                }
                for ((tom, deslocamento) in camadas) {
                    nativo.save()
                    nativo.translate(0f, deslocamento.toPx())
                    atual.tinta.color = tom.toArgb()
                    desenhar()
                    nativo.restore()
                }
                atual.tinta.color = cor.toArgb()
                desenhar()
            }
        },
    ) { _, restricoes ->
        val (inicios, tamanhos) = grafemas
        fun larguras(tinta: TextPaint) = FloatArray(inicios.size) { tinta.measureText(rascunho, 0, copiar(it)) }
            .also { rascunho.fill('\u0000') }
        val limite = if (restricoes.hasBoundedWidth) restricoes.maxWidth else Int.MAX_VALUE
        val natural = larguras(pincel).sum()
        val tinta = if (natural <= limite) TextPaint(pincel) else TextPaint(pincel).apply { textSize *= limite / natural * 0.98f }
        val metricas = tinta.fontMetrics
        val atual = Medida(tinta, inicios, tamanhos, larguras(tinta), -metricas.ascent).also { medida[0] = it }
        val largura = ceil(atual.larguras.sum()).toInt().coerceAtMost(limite).coerceAtLeast(maxOf(1, restricoes.minWidth))
        val altura = ceil(metricas.descent - metricas.ascent).toInt()
        layout(largura, altura.coerceIn(restricoes.minHeight, restricoes.maxHeight)) {}
    }
}
