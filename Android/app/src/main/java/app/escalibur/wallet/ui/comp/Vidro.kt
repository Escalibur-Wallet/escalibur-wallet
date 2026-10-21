package app.escalibur.wallet.ui.comp

import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.RenderEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.addOutline
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/**
 * O vidro do iOS 26 (Liquid Glass), desenhado aqui. O que fica atras e gravado numa camada (a
 * fonte); cada peca de vidro desenha essa camada desfocada, com a beirada curvando o fundo como
 * uma lente (a cor se separa um pouco na curva), um tom por cima e o brilho da borda. O desfoque
 * vale do Android 12 em diante e a lente, do 13; no Android 11, um tom quase solido no lugar.
 *
 * O vidro que fica dentro do conteudo (a selecao de um segmento, um chip) nao amostra fundo: atras
 * dele so ha o fundo liso da tela, e amostrar a propria fonte faria a camada se desenhar dentro
 * dela mesma. So o que flutua por cima (a barra de abas, os botoes do topo, as folhas) amostra.
 */
class FundoDoVidro internal constructor(internal val camada: GraphicsLayer) {
    internal var posicao by mutableStateOf(Offset.Zero)
}

/** A fonte que o vidro por cima amostra. Nulo dentro da propria fonte. */
val LocalFundoDoVidro = staticCompositionLocalOf<FundoDoVidro?> { null }

@Composable
fun rememberFundoDoVidro(): FundoDoVidro {
    val camada = rememberGraphicsLayer()
    return remember(camada) { FundoDoVidro(camada) }
}

/** O que fica atras do vidro: grava o que desenha, para as pecas de vidro por cima. */
fun Modifier.fonteDoVidro(fundo: FundoDoVidro): Modifier = this
    .onGloballyPositioned { fundo.posicao = it.positionInRoot() }
    .drawWithContent {
        // A camada e um RenderNode: o vidro que a desenha acompanha cada gravacao nova sem
        // precisar se redesenhar.
        fundo.camada.record { this@drawWithContent.drawContent() }
        drawLayer(fundo.camada)
    }

/**
 * A fonte e o que flutua por cima dela. O conteudo nao enxerga o fundo (vidro dentro dele nao
 * amostra); a frente enxerga.
 */
@Composable
fun ComVidro(modifier: Modifier = Modifier, frente: @Composable BoxScope.() -> Unit, conteudo: @Composable () -> Unit) {
    val fundo = rememberFundoDoVidro()
    Box(modifier) {
        Box(Modifier.matchParentSize().fonteDoVidro(fundo)) {
            CompositionLocalProvider(LocalFundoDoVidro provides null, content = conteudo)
        }
        CompositionLocalProvider(LocalFundoDoVidro provides fundo) { frente() }
    }
}

/**
 * Como cada vidro aparece. `tom` vai por cima do fundo desfocado; `semFundo` e o tom quando nao ha
 * o que amostrar (Android 11, ou vidro dentro do conteudo).
 */
@Immutable
data class EstiloDoVidro(
    val tom: Color,
    val semFundo: Color,
    val desfoque: Dp = 0.dp,
    val lente: Dp = 0.dp,
    val forca: Dp = 0.dp,
    val brilho: Float = 1f,
)

object Vidros {
    /** A barra de abas e os botoes do topo: vidro escuro, com o conteudo passando por baixo. */
    val barra = EstiloDoVidro(
        tom = Color(0xFF16161A).copy(alpha = 0.66f), semFundo = Color(0xFF1C1C20).copy(alpha = 0.96f),
        desfoque = 9.dp, lente = 20.dp, forca = 12.dp,
    )

    /** A escolha dentro do vidro (a aba escolhida, o segmento escolhido): um vidro mais claro. */
    val selecao = EstiloDoVidro(tom = Color.White.copy(alpha = 0.15f), semFundo = Color.White.copy(alpha = 0.15f), brilho = 0.75f)

    /** A pilula de variacao: vidro sem cor e sem toque (ela nao e botao). */
    val pilula = EstiloDoVidro(tom = Color.White.copy(alpha = 0.06f), semFundo = Color.White.copy(alpha = 0.06f), brilho = 0.7f)

    /** A gota que o dedo arrasta na barra de abas: quase transparente, so a lente. */
    val gota = EstiloDoVidro(
        tom = Color.White.copy(alpha = 0.06f), semFundo = Color.White.copy(alpha = 0.16f),
        desfoque = 1.dp, lente = 26.dp, forca = 16.dp, brilho = 1.3f,
    )

    /** As folhas: o vidro da barra, mais fechado, para o texto por cima ler bem. */
    val folha = EstiloDoVidro(
        tom = Color(0xFF141417).copy(alpha = 0.82f), semFundo = Color(0xFF17171A),
        desfoque = 22.dp, lente = 24.dp, forca = 10.dp, brilho = 0.9f,
    )
}

/** O vidro na forma dada. Os filhos vem por cima dele. */
fun Modifier.vidro(forma: Shape, estilo: EstiloDoVidro = Vidros.barra): Modifier = composed {
    val fundo = LocalFundoDoVidro.current
    val amostra = fundo != null && estilo.desfoque > 0.dp && Build.VERSION.SDK_INT >= 31
    val camada = rememberGraphicsLayer()
    var posicao by remember { mutableStateOf(Offset.Zero) }
    val lente = remember { if (Build.VERSION.SDK_INT >= 33) Lente() else null }
    val efeitoAtual = remember { EfeitoGuardado() }
    this
        // Camada propria: o vidro se redesenha sem redesenhar a tela.
        .graphicsLayer()
        .onGloballyPositioned { posicao = it.positionInRoot() }
        .drawBehind {
            val contorno = forma.createOutline(size, layoutDirection, this)
            val caminho = Path().apply { addOutline(contorno) }
            if (amostra && fundo != null) {
                val margem = (estilo.lente + estilo.desfoque * 2).toPx()
                // O efeito so muda com o tamanho: trocar a cada quadro redesenharia sem fim.
                val chave = Triple(size, margem, raioDe(contorno))
                if (efeitoAtual.chave != chave) {
                    efeitoAtual.chave = chave
                    camada.renderEffect = efeito(estilo, margem, chave.third, lente)
                }
                camada.record(IntSize((size.width + margem * 2).roundToInt(), (size.height + margem * 2).roundToInt())) {
                    translate(fundo.posicao.x - posicao.x + margem, fundo.posicao.y - posicao.y + margem) { drawLayer(fundo.camada) }
                }
                clipPath(caminho) { translate(-margem, -margem) { drawLayer(camada) } }
                drawPath(caminho, estilo.tom)
            } else {
                drawPath(caminho, estilo.semFundo)
            }
            bordaDoVidro(caminho, estilo.brilho)
        }
}

/** Fora do estado do Compose: guardar aqui nao pede outro desenho. */
private class EfeitoGuardado { var chave: Any? = null }

/**
 * O brilho da borda: a luz vem de cima a esquerda, entao a borda e mais clara ali e no canto
 * oposto, e quase some nos lados.
 */
private fun DrawScope.bordaDoVidro(caminho: Path, brilho: Float) {
    if (brilho <= 0f) return
    val luz = Brush.linearGradient(
        0f to Color.White.copy(alpha = 0.30f * brilho),
        0.32f to Color.White.copy(alpha = 0.07f * brilho),
        0.68f to Color.White.copy(alpha = 0.035f * brilho),
        1f to Color.White.copy(alpha = 0.16f * brilho),
        start = Offset.Zero, end = Offset(size.width, size.height),
    )
    clipPath(caminho) {
        drawPath(caminho, luz, style = Stroke(width = 1.6.dp.toPx()))
        // Um halo fino por dentro da borda, para o vidro ter espessura.
        drawPath(caminho, Color.White.copy(alpha = 0.025f * brilho), style = Stroke(width = 5.dp.toPx()))
    }
}

private fun raioDe(contorno: Outline): Float = when (contorno) {
    is Outline.Rounded -> contorno.roundRect.topLeftCornerRadius.x
    is Outline.Rectangle -> 0f
    is Outline.Generic -> contorno.bounds.minDimension / 2
}

private fun DrawScope.efeito(estilo: EstiloDoVidro, margem: Float, raio: Float, lente: Lente?): RenderEffect {
    val r = estilo.desfoque.toPx()
    val desfoque = android.graphics.RenderEffect.createBlurEffect(r, r, Shader.TileMode.CLAMP)
    if (lente == null || estilo.lente <= 0.dp || Build.VERSION.SDK_INT < 33) return desfoque.asComposeRenderEffect()
    return lente.efeito(size.width, size.height, margem, raio, estilo.lente.toPx(), estilo.forca.toPx(), desfoque).asComposeRenderEffect()
}

/**
 * A lente da beirada: perto da borda, o fundo e puxado de fora para dentro, como no vidro grosso
 * de verdade, e o vermelho e o azul se afastam um pouco (a dispersao). No meio, o fundo passa reto.
 */
@RequiresApi(33)
private class Lente {
    private val shader = RuntimeShader(AGSL)

    fun efeito(largura: Float, altura: Float, margem: Float, raio: Float, beirada: Float, forca: Float, desfoque: android.graphics.RenderEffect): android.graphics.RenderEffect {
        shader.setFloatUniform("tamanho", largura, altura)
        shader.setFloatUniform("margem", margem, margem)
        shader.setFloatUniform("raio", minOf(raio, minOf(largura, altura) / 2))
        shader.setFloatUniform("beirada", maxOf(beirada, 1f))
        shader.setFloatUniform("forca", forca)
        val curva = android.graphics.RenderEffect.createRuntimeShaderEffect(shader, "conteudo")
        // O desfoque primeiro, a lente sobre o fundo ja desfocado.
        return android.graphics.RenderEffect.createChainEffect(curva, desfoque)
    }

    companion object {
        const val AGSL = """
uniform shader conteudo;
uniform float2 tamanho;
uniform float2 margem;
uniform float raio;
uniform float beirada;
uniform float forca;

float caixa(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + float2(r);
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

half4 main(float2 ponto) {
    float2 meio = tamanho * 0.5;
    float2 p = ponto - margem - meio;
    float d = caixa(p, meio, raio);
    float dentro = -d;
    if (dentro <= 0.0 || dentro >= beirada) { return conteudo.eval(ponto); }
    float2 e = float2(0.75, 0.0);
    float2 n = float2(caixa(p + e.xy, meio, raio) - caixa(p - e.xy, meio, raio),
                      caixa(p + e.yx, meio, raio) - caixa(p - e.yx, meio, raio));
    float tamanhoDoN = length(n);
    if (tamanhoDoN < 0.0001) { return conteudo.eval(ponto); }
    n = n / tamanhoDoN;
    // O perfil de uma lente convexa: reto no meio, curvando cada vez mais perto da borda.
    float t = 1.0 - dentro / beirada;
    float curva = 1.0 - sqrt(max(1.0 - t * t, 0.0));
    float2 desvio = n * forca * curva;
    half4 verde = conteudo.eval(ponto + desvio);
    half vermelho = conteudo.eval(ponto + desvio * 1.08).r;
    half azul = conteudo.eval(ponto + desvio * 0.92).b;
    return half4(vermelho, verde.g, azul, verde.a);
}
"""
    }
}
