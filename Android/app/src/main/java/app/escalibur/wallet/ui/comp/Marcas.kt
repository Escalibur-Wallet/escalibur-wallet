package app.escalibur.wallet.ui.comp

import app.escalibur.wallet.ui.tema.Raio
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.Density
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.geometry.Rect
import android.content.Context
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.ui.tema.Paleta

/** A marca do app: a espada do Escalibur, quase preta, no lima (24/10/2026, antes rosa), em proporcao com o icone de 1024 pontos. */
@Composable
fun SeloDaCarteira(tamanho: Dp = 44.dp, fundo: Color = Paleta.acento, modifier: Modifier = Modifier) {
    Canvas(modifier.size(tamanho).clip(RoundedCornerShape(tamanho * 0.2237f))) {
        val w = size.width
        val h = size.height
        drawRect(fundo)
        val aco = Color(0xFF0B0B0C)
        fun retangulo(x: Float, y: Float, largura: Float, altura: Float) =
            drawRect(aco, Offset(x * w, y * h), Size(largura * w, altura * h))
        retangulo(0.4297f, 0.2900f, 0.1406f, 0.0615f) // pomo
        retangulo(0.4639f, 0.3516f, 0.0723f, 0.1436f) // punho
        retangulo(0.2041f, 0.4951f, 0.5918f, 0.0498f) // guarda
        retangulo(0.4375f, 0.5449f, 0.1250f, 0.4551f) // lamina
    }
}

/** Os logos embarcados (assets/logos, os mesmos do iOS), lidos uma vez cada. */
object Logos {
    private val cache = LruCache<String, ImageBitmap>(160)
    private val ausentes = mutableSetOf<String>()

    fun imagem(contexto: Context, nome: String): ImageBitmap? {
        cache.get(nome)?.let { return it }
        if (nome in ausentes) return null
        val imagem = listOf("png", "jpg").firstNotNullOfOrNull { extensao ->
            runCatching { contexto.assets.open("logos/$nome.$extensao").use { BitmapFactory.decodeStream(it)?.asImageBitmap() } }.getOrNull()
        }
        if (imagem == null) ausentes += nome else cache.put(nome, imagem)
        return imagem
    }

    /** Logos escuros que somem no preto ganham um disco claro atras. */
    val escuros = setOf("ripple", "stellar")
    /** Logos sem circulo proprio (o losango do ETH): vao num disco, com o glifo a 62%. */
    val soltos = setOf("ethereum", "solana", "tether", "weth")
}

/**
 * O logo de uma moeda, com o selo da rede quando o ativo nao esta na rede nativa dele (USDC na Base
 * leva selo; ETH na Ethereum nao), ou a contagem de redes. Token fora da lista nunca usa o logo que
 * ele mesmo declara: so as letras.
 */
@Composable
fun LogoDaMoeda(
    coingecko: String?, simbolo: String = "", tamanho: Dp = 40.dp, modifier: Modifier = Modifier,
    rede: String? = null, redeCoingecko: String? = null, quantasRedes: Int = 1, anel: Color = Paleta.vazio,
    naoConferido: Boolean = false,
) {
    val contexto = LocalContext.current
    val imagem = remember(coingecko) { if (naoConferido || coingecko == null) null else Logos.imagem(contexto, "logo-$coingecko") }
    Box(modifier.size(tamanho)) {
        when {
            imagem != null && coingecko in Logos.soltos -> Box(
                Modifier.size(tamanho).clip(CircleShape).background(Paleta.controle).padding(tamanho * 0.19f),
            ) { Image(imagem, null, Modifier.size(tamanho), contentScale = ContentScale.Fit, filterQuality = FilterQuality.High) }
            imagem != null -> Image(
                imagem, null,
                Modifier.size(tamanho).clip(CircleShape).background(if (coingecko in Logos.escuros) Paleta.discoDeLogo else Color.Transparent),
                contentScale = ContentScale.Fit, filterQuality = FilterQuality.High,
            )
            else -> Box(Modifier.size(tamanho).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                val letras = simbolo.filter { it.code in 0x30..0x7A && it.isLetterOrDigit() }.take(2).uppercase()
                Text(letras.ifEmpty { "?" }, color = if (naoConferido) Paleta.tinta else Paleta.tintaSuave, fontWeight = FontWeight.SemiBold,
                     fontSize = (tamanho.value * 0.34f).sp)
            }
        }
        if (rede != null && redeCoingecko != null && redeCoingecko != coingecko) {
            SeloDaRede(rede, redeCoingecko, tamanho * 0.4f, anel, Modifier.align(Alignment.BottomEnd).offset(tamanho * 0.08f, tamanho * 0.08f))
        } else if (quantasRedes > 1) {
            Box(
                Modifier.align(Alignment.BottomEnd).offset(tamanho * 0.08f, tamanho * 0.08f).size(tamanho * 0.42f)
                    .clip(CircleShape).background(Paleta.controle).border(2.dp, anel, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text("$quantasRedes", color = Paleta.tinta, fontWeight = FontWeight.Bold, fontSize = (tamanho.value * 0.24f).sp)
            }
        }
    }
}

@Composable
fun SeloDaRede(rede: String, coingecko: String, tamanho: Dp = 16.dp, anel: Color = Paleta.vazio, modifier: Modifier = Modifier) {
    val contexto = LocalContext.current
    val imagem = remember(rede) { Logos.imagem(contexto, "rede-$rede") ?: Logos.imagem(contexto, "logo-$coingecko") }
    Box(modifier.size(tamanho).clip(CircleShape).border(2.dp, anel, CircleShape), contentAlignment = Alignment.Center) {
        when {
            rede == "base" -> Box(Modifier.size(tamanho).background(Color(0xFF0052FF)), contentAlignment = Alignment.Center) {
                Box(Modifier.size(tamanho * 0.38f).clip(RoundedCornerShape(tamanho * 0.06f)).background(Color.White))
            }
            imagem != null -> Image(
                imagem, null,
                Modifier.size(tamanho).background(if (rede == "xrpl" || rede == "stellar") Paleta.discoDeLogo else Paleta.controle),
                contentScale = ContentScale.Fit, filterQuality = FilterQuality.High,
            )
            else -> Box(Modifier.size(tamanho).background(Paleta.controle))
        }
    }
}

/**
 * A cor de um logo, para a fatia dele na distribuicao (o `LogoColor` do iOS): a cor saturada que
 * mais aparece num logo reduzido a 32 px; sem cor, um cinza visivel no fundo escuro.
 */
object CorDoLogo {
    private val guardadas = HashMap<String, Color>()

    fun de(contexto: Context, coingecko: String?): Color {
        val id = coingecko ?: return Paleta.tintaApagada
        guardadas[id]?.let { return it }
        val cor = Logos.imagem(contexto, "logo-$id")?.let(::calcular) ?: Paleta.tintaApagada
        guardadas[id] = cor
        return cor
    }

    private fun calcular(imagem: ImageBitmap): Color? {
        val lado = 32
        val reduzida = android.graphics.Bitmap.createScaledBitmap(imagem.asAndroidBitmap(), lado, lado, true)
        val saturadas = HashMap<Int, IntArray>()
        val neutras = HashMap<Int, IntArray>()
        for (y in 0 until lado) for (x in 0 until lado) {
            val p = reduzida.getPixel(x, y)
            if ((p ushr 24) <= 200) continue
            val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF
            val alto = maxOf(r, g, b); val baixo = minOf(r, g, b)
            val chave = (r shr 4) shl 8 or ((g shr 4) shl 4) or (b shr 4)
            val mapa = if (alto > 40 && alto - baixo > 48) saturadas else neutras
            val e = mapa.getOrPut(chave) { IntArray(4) }
            e[0]++; e[1] += r; e[2] += g; e[3] += b
        }
        saturadas.values.maxByOrNull { it[0] }?.takeIf { it[0] >= 12 }?.let { return Color(it[1] / it[0] / 255f, it[2] / it[0] / 255f, it[3] / it[0] / 255f) }
        val cinza = neutras.values.maxByOrNull { it[0] } ?: return null
        // Preto some no fundo escuro; branco puro brilha demais. Cinza visivel.
        val nivel = ((cinza[1] + cinza[2] + cinza[3]).toFloat() / (cinza[0] * 3) / 255f).coerceIn(0.55f, 0.85f)
        return Color(nivel, nivel, nivel)
    }
}

/** A placa clara de metal (o destino do envio, o QR do Receber), com o canto de cima cortado (o LacquerPlate do iOS). */
class PlacaLaqueada(private val corte: Dp = 24.dp, private val raio: Dp = Raio.botao) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val c = with(density) { corte.toPx() }
        val r = with(density) { raio.toPx() }
        val w = size.width
        val h = size.height
        return Outline.Generic(Path().apply {
            moveTo(r, 0f)
            lineTo(w - c, 0f)
            lineTo(w, c)
            lineTo(w, h - r)
            arcTo(Rect(w - 2 * r, h - 2 * r, w, h), 0f, 90f, false)
            lineTo(r, h)
            arcTo(Rect(0f, h - 2 * r, 2 * r, h), 90f, 90f, false)
            lineTo(0f, r)
            arcTo(Rect(0f, 0f, 2 * r, 2 * r), 180f, 90f, false)
            close()
        })
    }
}
