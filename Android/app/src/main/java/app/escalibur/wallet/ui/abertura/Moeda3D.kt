package app.escalibur.wallet.ui.abertura

import android.content.Context
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * A moeda de Bitcoin em 3D do iOS (`BitcoinCoin3D`): as mesmas texturas, o metal, a luz e a camera,
 * renderizados pelo SceneKit do Mac em 120 quadros por volta (`tools/android/moeda3d.swift`). Cada
 * quadro e lido do APK quando o giro chega nele; os ultimos ficam guardados.
 */
internal object QuadrosDaMoeda {
    const val TOTAL = 120
    private val guardados = LruCache<Int, ImageBitmap>(12)

    fun indice(angulo: Double): Int {
        val volta = 2 * PI
        val fracao = ((angulo % volta) + volta) % volta / volta
        return (fracao * TOTAL).roundToInt() % TOTAL
    }

    fun quadro(contexto: Context, indice: Int): ImageBitmap? {
        guardados.get(indice)?.let { return it }
        val imagem = runCatching {
            contexto.assets.open(String.format(Locale.ROOT, "moeda3d/%03d.webp", indice)).use { BitmapFactory.decodeStream(it) }
        }.getOrNull()?.asImageBitmap() ?: return null
        guardados.put(indice, imagem)
        return imagem
    }

    /** Adianta os quadros de frente, fora da linha da tela: chamado pela pagina de antes, como no iOS. */
    suspend fun adiantar(contexto: Context) = withContext(Dispatchers.IO) {
        for (indice in listOf(0, 1, 2, TOTAL - 1)) quadro(contexto, indice)
    }
}

/** O embalo depois de soltar: de onde a moeda estava ate a volta inteira em que ela para (o `CoinMotion` do iOS). */
internal class SoltaDaMoeda(val de: Double, val ate: Double, val em: Long)

internal object GiroDaMoeda {
    /** Quanto o dedo anda, em dp, para a moeda girar um radiano. */
    const val DP_POR_RADIANO = 55f

    /** O giro do dedo num instante (`System.nanoTime`): o embalo desacelera e para numa volta inteira. */
    fun daMao(solta: SoltaDaMoeda?, agora: Long): Double {
        solta ?: return 0.0
        val p = ((agora - solta.em) / 1e9 / 1.2).coerceIn(0.0, 1.0)
        return solta.de + (solta.ate - solta.de) * (1 - (1 - p).pow(3))
    }

    /** Solta a moeda em `de` com `extra` de embalo: ela para de frente, na volta inteira mais perto. */
    fun soltar(de: Double, extra: Double, agora: Long): SoltaDaMoeda {
        val volta = 2 * PI
        val voltas = (de + extra) / volta
        // O arredondamento do Swift: metade para longe do zero.
        val inteiras = if (voltas < 0) -floor(-voltas + 0.5) else floor(voltas + 0.5)
        return SoltaDaMoeda(de, inteiras * volta, agora)
    }
}

/**
 * A moeda no angulo dado (0 e a frente), com a sombra no chao. Ocupa a largura toda e a altura que
 * receber (200 no tour, como no iOS); `entrada` vai de 0 a 1 quando a cena abre e `balanco` e o sobe e
 * desce, em dp.
 */
@Composable
internal fun MoedaEmTresD(angulo: Double, entrada: Float, balanco: Float, modifier: Modifier) {
    val quadro = QuadrosDaMoeda.quadro(LocalContext.current, QuadrosDaMoeda.indice(angulo))
    Canvas(modifier) {
        val centro = size.width / 2
        // A sombra, que encolhe quando a moeda sobe e quando ela esta de lado.
        val diametro = size.height * 0.7f
        val chao = size.height / 2 + diametro * 0.56f
        val largura = diametro * (0.7f - balanco * 0.01f) * max(abs(cos(angulo)).toFloat(), 0.35f)
        if (largura > 0f && entrada > 0f) {
            drawOval(
                Brush.radialGradient(listOf(Color.Black.copy(alpha = 0.45f * entrada), Color.Transparent), Offset(centro, chao), largura / 2),
                Offset(centro - largura / 2, chao - 6.dp.toPx()), Size(largura, 12.dp.toPx()),
            )
        }
        if (quadro == null || entrada <= 0f) return@Canvas
        // O quadro e quadrado, da altura toda: a camera do iOS enquadra pela altura.
        val lado = size.height.roundToInt()
        translate(top = (balanco - 8f).dp.toPx()) {
            scale(0.8f + 0.2f * entrada, pivot = Offset(centro, size.height / 2)) {
                drawImage(
                    quadro, srcOffset = IntOffset.Zero, srcSize = IntSize(quadro.width, quadro.height),
                    dstOffset = IntOffset((centro - lado / 2f).roundToInt(), 0), dstSize = IntSize(lado, lado),
                    alpha = entrada, filterQuality = FilterQuality.High,
                )
            }
        }
    }
}
