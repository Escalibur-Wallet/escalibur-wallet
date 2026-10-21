package app.escalibur.wallet.ui.comp

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.rotate
import app.escalibur.wallet.ui.tema.Paleta
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Um numero que muda rolando, como o `contentTransition(.numericText())` do iOS: so os caracteres
 * que mudaram se mexem, cada digito sobe (o valor cresceu) ou desce (diminuiu) no lugar do antigo,
 * os outros ficam parados. Alinhado pela direita, para os digitos de mesma casa se encontrarem.
 */
@Composable
fun TextoNumerico(texto: String, estilo: TextStyle, cor: Color, modifier: Modifier = Modifier, valor: Double? = null) {
    val parado = movimentoReduzido()
    var anterior by remember { mutableStateOf(valor) }
    val sobe = valor == null || anterior == null || valor >= anterior!!
    if (valor != anterior) anterior = valor
    // A linha de base do texto inteiro: a mesma de cada caractere, e quem alinha pela base (o simbolo
    // e as casas do saldo) encontra o numero no lugar.
    val base = rememberTextMeasurer().measure(texto.ifEmpty { " " }, estilo, maxLines = 1).firstBaseline.roundToInt()
    Layout(
        content = {
            texto.forEachIndexed { indice, caractere ->
                key(texto.length - indice) {
                    AnimatedContent(
                        caractere,
                        transitionSpec = {
                            if (parado || !caractere.isDigit()) {
                                fadeIn(tween(150)) togetherWith fadeOut(tween(150))
                            } else {
                                val mola = spring<IntOffset>(dampingRatio = 0.86f, stiffness = 520f)
                                (slideInVertically(mola) { if (sobe) it else -it } + fadeIn(tween(220))) togetherWith
                                    (slideOutVertically(mola) { if (sobe) -it else it } + fadeOut(tween(160)))
                            }.using(SizeTransform(clip = false))
                        },
                        label = "digito",
                    ) { c -> Text(c.toString(), style = estilo, color = cor, maxLines = 1, softWrap = false) }
                }
            }
        },
        modifier = modifier.clearAndSetSemantics { contentDescription = texto },
    ) { medidos, limites ->
        val pecas = medidos.map { it.measure(limites.copy(minWidth = 0, minHeight = 0)) }
        val largura = pecas.sumOf { it.width }
        val altura = pecas.maxOfOrNull { it.height } ?: 0
        layout(largura, altura, mapOf(FirstBaseline to base, LastBaseline to base)) {
            var x = 0
            for (p in pecas) { p.placeRelative(x, 0); x += p.width }
        }
    }
}

/**
 * O puxar para atualizar do iOS: o conteudo desce junto com o dedo, e no espaco que abre os raios
 * do carregando aparecem um a um; passou do ponto, solta e gira, com o conteudo esperando ali ate
 * terminar. No lugar do circulo do Android.
 */
@Composable
fun PuxarParaAtualizar(atualizando: Boolean, aoAtualizar: () -> Unit, modifier: Modifier = Modifier, conteudo: @Composable BoxScope.() -> Unit) {
    val densidade = LocalDensity.current
    val haptico = LocalHapticFeedback.current
    val escopo = rememberCoroutineScope()
    val ponto = with(densidade) { 86.dp.toPx() }
    val parada = with(densidade) { 58.dp.toPx() }
    val puxado = remember { Animatable(0f) }
    var armado by remember { mutableStateOf(false) }
    val atualizandoAgora by rememberUpdatedState(atualizando)
    val aoAtualizarAgora by rememberUpdatedState(aoAtualizar)
    // Terminou: o conteudo sobe de volta.
    if (!atualizando && puxado.value > 0f && !armado) {
        LaunchedEffect(Unit) { puxado.animateTo(0f, spring(dampingRatio = 0.9f, stiffness = 380f)) }
    }
    if (atualizando) LaunchedEffect(Unit) {
        if (puxado.value < parada) puxado.animateTo(parada, spring(dampingRatio = 0.9f, stiffness = 380f))
    }
    val conexao = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                // Puxado e o dedo subindo: primeiro o conteudo volta.
                if (available.y < 0 && puxado.value > 0f && source == NestedScrollSource.UserInput && !atualizandoAgora) {
                    val antes = puxado.value
                    val depois = (antes + available.y).coerceAtLeast(0f)
                    escopo.launch { puxado.snapTo(depois) }
                    if (depois < ponto) armado = false
                    return Offset(0f, depois - antes)
                }
                return Offset.Zero
            }

            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (available.y > 0 && source == NestedScrollSource.UserInput && !atualizandoAgora) {
                    // Resistencia: quanto mais puxado, menos anda.
                    val novo = puxado.value + available.y * (1f - (puxado.value / (ponto * 2.4f)).coerceIn(0f, 0.8f))
                    escopo.launch { puxado.snapTo(novo) }
                    if (!armado && novo >= ponto) {
                        armado = true
                        haptico.performHapticFeedback(HapticFeedbackType.SegmentTick)
                    }
                    return Offset(0f, available.y)
                }
                return Offset.Zero
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                if (puxado.value <= 0f) return Velocity.Zero
                if (armado && !atualizandoAgora) {
                    armado = false
                    aoAtualizarAgora()
                    puxado.animateTo(parada, spring(dampingRatio = 0.9f, stiffness = 380f))
                } else if (!atualizandoAgora) {
                    puxado.animateTo(0f, spring(dampingRatio = 0.9f, stiffness = 380f))
                }
                return available
            }
        }
    }
    Box(modifier.nestedScroll(conexao)) {
        if (puxado.value > 0f) {
            val fracao = (puxado.value / ponto).coerceIn(0f, 1f)
            Box(Modifier.fillMaxWidth().height(with(densidade) { puxado.value.toDp() }).padding(top = 8.dp), contentAlignment = Alignment.Center) {
                if (atualizando || armado) Girando(Paleta.tintaSuave, 24.dp)
                else RaiosAparecendo(fracao)
            }
        }
        Box(Modifier.offset { IntOffset(0, puxado.value.roundToInt()) }, content = conteudo)
    }
}

/** Os raios do carregando aparecendo um a um enquanto o dedo puxa. */
@Composable
private fun RaiosAparecendo(fracao: Float) {
    Canvas(Modifier.size(24.dp).graphicsLayer { alpha = (fracao * 1.6f).coerceAtMost(1f) }) {
        val raios = 8
        val visiveis = (fracao * raios).toInt()
        val raio = size.minDimension / 2
        val largura = raio * 0.24f
        for (i in 0 until visiveis) {
            rotate(i * 360f / raios) {
                drawLine(Paleta.tintaSuave, center.copy(y = center.y - raio * 0.48f), center.copy(y = center.y - raio + largura / 2),
                         strokeWidth = largura, cap = StrokeCap.Round)
            }
        }
    }
}
