package app.escalibur.wallet.ui.comp

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.tema.Paleta
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.sin

/**
 * Enquanto a troca, o envio ou a ponte sao montados ou enviados (o `SwapProcessingIndicator` do iOS): as duas moedas nas pontas
 * de um arco, e um cometa lima com rastro correndo de uma para a outra. Quando ele chega, uma onda sai da moeda de destino. No
 * cancelamento, o cometa volta para a moeda vendida (o valor fica na carteira) e a outra fica apagada. `parado`: so o arco e as
 * moedas, como a ponte que terminou sem entrega. Tudo sai de um relogio de quadros, sem animacao implicita; cores chapadas.
 */
@Composable
fun IndicadorDaTroca(
    origem: @Composable () -> Unit, destino: @Composable () -> Unit, modifier: Modifier = Modifier,
    cancelando: Boolean = false, parado: Boolean = false,
) {
    val tempo = relogio(parado || movimentoReduzido())
    val logo = 56.dp
    val largura = 280.dp
    val subida = 68.dp
    val folga = 8.dp
    Box(modifier.size(largura, folga + subida + logo / 2)) {
        Canvas(Modifier.fillMaxSize()) {
            val base = (folga + subida).toPx()
            val inicio = Offset(logo.toPx() / 2, base)
            val fim = Offset(size.width - logo.toPx() / 2, base)
            // O topo de uma curva quadratica simetrica fica na metade do caminho ate o controle.
            val controle = Offset(size.width / 2, base - 2 * subida.toPx())
            val arco = Path().apply {
                moveTo(inicio.x, inicio.y)
                quadraticTo(controle.x, controle.y, fim.x, fim.y)
            }
            drawPath(arco, Paleta.bordaForte, style = Stroke(1.5.dp.toPx(), cap = StrokeCap.Round,
                                                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 6.dp.toPx()))))
            if (parado) return@Canvas
            val ciclo = (tempo.value % 1.6f) / 1.6f
            fun ponto(t: Float): Offset {
                val u = 1 - t
                return Offset(u * u * inicio.x + 2 * u * t * controle.x + t * t * fim.x, u * u * inicio.y + 2 * u * t * controle.y + t * t * fim.y)
            }
            fun suaveDoCometa(x: Float) = x * x * (3 - 2 * x)
            // O cometa corre nos primeiros 80% do ciclo; a onda ocupa o resto.
            if (ciclo < 0.8f) {
                val viagem = minOf(1f, ciclo / 0.8f)
                // Na troca, da moeda vendida para a comprada; no cancelamento, do meio do caminho de volta para a vendida.
                val cabeca = if (cancelando) 0.7f * (1 - suaveDoCometa(viagem)) else suaveDoCometa(viagem)
                val sentido = if (cancelando) 1f else -1f
                for (k in 0 until 14) {
                    val t = cabeca + sentido * k * 0.022f
                    if (t < 0f || t > 1f) continue
                    val raio = maxOf(1f, 5.5f - k * 0.35f).dp.toPx()
                    drawCircle(Paleta.acento.copy(alpha = 1 - k / 14f), raio, ponto(t))
                }
            } else {
                val onda = (ciclo - 0.8f) / 0.2f
                val alvo = if (cancelando) inicio else fim
                drawCircle(Paleta.acento.copy(alpha = 1 - onda), (logo / 2 + 2.dp).toPx() + onda * 16.dp.toPx(), alvo, style = Stroke(2.dp.toPx()))
            }
        }
        val pulso = { fase: Float -> 1 + 0.03f * sin(tempo.value * 2 * PI.toFloat() / 2.2f + fase) }
        Box(Modifier.align(Alignment.BottomStart).size(logo).graphicsLayer { val e = pulso(0f); scaleX = e; scaleY = e }, contentAlignment = Alignment.Center) {
            origem()
        }
        Box(Modifier.align(Alignment.BottomEnd).size(logo).graphicsLayer {
            val e = pulso(PI.toFloat()); scaleX = e; scaleY = e
            alpha = if (cancelando) 0.35f else 1f
        }, contentAlignment = Alignment.Center) { destino() }
    }
}

/** O destino do envio, que nao tem moeda do outro lado: a carteira num circulo. */
@Composable
fun DestinoDoEnvio() {
    Box(Modifier.size(56.dp).clip(CircleShape).background(Paleta.trilho).border(1.dp, Paleta.bordaForte, CircleShape), contentAlignment = Alignment.Center) {
        Icone(Icones.carteira, Paleta.tinta, tamanho = 22.dp)
    }
}

/**
 * O selo de concluido (o `CoinFlipBadge` do iOS): um circulo que gira no eixo vertical como uma moeda jogada, com a moeda de um
 * lado e o visto em lima do outro. Gira rapido tres vezes ao aparecer e depois vira devagar de tempos em tempos. Com o movimento
 * reduzido, fica parado no visto.
 */
@Composable
fun MoedaQueVira(moeda: @Composable () -> Unit, modifier: Modifier = Modifier, tamanho: Dp = 112.dp) {
    val angulo = remember { Animatable(0f) }
    val parado = movimentoReduzido()
    LaunchedEffect(Unit) {
        if (parado) {
            angulo.snapTo(180f)
            return@LaunchedEffect
        }
        // Jogada: tres voltas e meia, terminando no visto.
        angulo.animateTo(1080f + 180f, tween(1600, easing = CubicBezierEasing(0.2f, 0.8f, 0.25f, 1f)))
        delay(1_000)
        // Depois, vira devagar: mostra a moeda, volta ao visto.
        while (true) {
            angulo.animateTo(angulo.value + 180f, tween(700, easing = EaseInOut))
            delay(900)
            angulo.animateTo(angulo.value + 180f, tween(700, easing = EaseInOut))
            delay(2_500)
        }
    }
    val volta = angulo.value % 360f
    val mostraMoeda = volta < 90f || volta > 270f
    Box(
        modifier.size(tamanho).graphicsLayer { rotationY = angulo.value; cameraDistance = 8 * density },
        contentAlignment = Alignment.Center,
    ) {
        if (mostraMoeda) {
            Box(Modifier.fillMaxSize().clip(CircleShape).background(Paleta.corpo).border(1.dp, Paleta.bordaForte, CircleShape), contentAlignment = Alignment.Center) {
                moeda()
            }
        } else {
            // O verso de um giro em Y aparece espelhado: desfaz o espelho.
            Box(Modifier.fillMaxSize().graphicsLayer { rotationY = 180f }.clip(CircleShape).background(Paleta.alta), contentAlignment = Alignment.Center) {
                Icone(Icones.visto, Paleta.sobreLima, tamanho = tamanho * 0.42f)
            }
        }
    }
}
