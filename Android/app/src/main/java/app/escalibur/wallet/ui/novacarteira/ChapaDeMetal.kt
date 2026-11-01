package app.escalibur.wallet.ui.novacarteira

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Text
import androidx.compose.ui.text.style.TextOverflow

/**
 * A inclinacao do celular pela gravidade (o TiltReader do iOS): de -1 a 1 para os lados (`roll`)
 * e para frente e para tras (`pitch`), a partir de como o celular estava quando a tela abriu,
 * suavizada para um tremor da mao nao tremer a chapa.
 */
@Stable
class Inclinacao {
    var roll by mutableFloatStateOf(0f)
        internal set
    var pitch by mutableFloatStateOf(0f)
        internal set
}

@Composable
fun rememberInclinacao(ligada: Boolean = true): Inclinacao {
    val inclinacao = remember { Inclinacao() }
    val contexto = LocalContext.current
    DisposableEffect(ligada) {
        val sensores = contexto.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val gravidade = sensores?.getDefaultSensor(Sensor.TYPE_GRAVITY)
        if (!ligada || sensores == null || gravidade == null) return@DisposableEffect onDispose {}
        var base: Pair<Float, Float>? = null
        val ouvinte = object : SensorEventListener {
            override fun onSensorChanged(evento: SensorEvent) {
                // No Android a gravidade vem "para cima" e em m/s²; no iOS, para baixo e em g.
                val x = -evento.values[0] / SensorManager.GRAVITY_EARTH
                val y = -evento.values[1] / SensorManager.GRAVITY_EARTH
                val referencia = base ?: (x to y).also { base = it }
                fun limite(valor: Float) = (valor / 0.35f).coerceIn(-1f, 1f)
                inclinacao.roll += (limite(x - referencia.first) - inclinacao.roll) * 0.2f
                inclinacao.pitch += (limite(y - referencia.second) - inclinacao.pitch) * 0.2f
            }
            override fun onAccuracyChanged(sensor: Sensor?, precisao: Int) {}
        }
        sensores.registerListener(ouvinte, gravidade, SensorManager.SENSOR_DELAY_GAME)
        onDispose {
            sensores.unregisterListener(ouvinte)
            inclinacao.roll = 0f
            inclinacao.pitch = 0f
        }
    }
    return inclinacao
}

/** As cores da chapa de aco (as do MetalPlate do iOS). */
object Aco {
    val tinta = Color(0xFF2E2F35)
    val sulco = Color(0xFF8E9098)
    val bordaClara = Color(0xFF8B8D95)
    val bordaEscura = Color(0xFF55575E)
}

/**
 * O aco escovado da chapa das palavras (o MetalPlate do iOS): o fundo, riscos irregulares de
 * comprimento, altura e tom sorteados (sempre os mesmos), parafusos de fenda cruzada nos
 * cantos, o reflexo que corre conforme a chapa inclina para os lados, a luz de cima e o
 * chanfro. `inclinacaoX` e `inclinacaoY` de -1 a 1.
 */
@Composable
fun ChapaDeMetal(inclinacaoX: Float, inclinacaoY: Float, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val raio = CornerRadius(16.dp.toPx())
        val largura = size.width
        val altura = size.height
        clipPath(androidx.compose.ui.graphics.Path().apply {
            addRoundRect(androidx.compose.ui.geometry.RoundRect(0f, 0f, largura, altura, raio))
        }) {
            drawRect(Brush.linearGradient(
                0f to Color(0xFFE6E7EB), 0.45f to Color(0xFFCFD1D6), 1f to Color(0xFFBABCC2),
                start = Offset.Zero, end = Offset(largura * 0.3f, altura),
            ))
            // O escovado de verdade: os mesmos riscos do iOS, pela mesma semente.
            var semente = 0x9E37_79B9_7F4A_7C15uL
            fun proximo(): Double {
                semente = semente * 6364136223846793005uL + 1442695040888963407uL
                return (semente shr 11).toDouble() / (1uL shl 53).toDouble()
            }
            val ponto = 1.dp.toPx()
            val riscos = (altura / ponto * 5).toInt()
            repeat(riscos) {
                val y = proximo().toFloat() * altura
                val comprimento = largura * (0.25f + 0.75f * proximo().toFloat())
                val x = proximo().toFloat() * (largura - comprimento * 0.5f) - comprimento * 0.25f
                val claro = proximo() < 0.55
                val alfa = if (claro) 0.06f + 0.14f * proximo().toFloat() else 0.02f + 0.06f * proximo().toFloat()
                val espessura = (0.35f + 0.5f * proximo().toFloat()) * ponto
                drawRect(if (claro) Color.White.copy(alpha = alfa) else Color.Black.copy(alpha = alfa), Offset(x, y), Size(comprimento, espessura))
            }
            // Parafusos de fenda cruzada nos quatro cantos, cada um num angulo.
            val margem = 15.dp.toPx()
            val cantos = listOf(Offset(margem, margem), Offset(largura - margem, margem), Offset(margem, altura - margem), Offset(largura - margem, altura - margem))
            val r = 5.5f * ponto
            cantos.forEachIndexed { indice, canto ->
                drawCircle(Color.Black.copy(alpha = 0.14f), r + 1.5f * ponto, canto)
                drawCircle(Color.Black.copy(alpha = 0.28f), r, canto + Offset(0f, ponto))
                drawCircle(Brush.radialGradient(listOf(Color(0xFFF8F8FA), Color(0xFFA6A8B0), Color(0xFF7C7E86)),
                                                center = canto - Offset(2 * ponto, 2 * ponto), radius = 8 * ponto), r, canto)
                rotate(listOf(18f, 63f, 141f, 102f)[indice], canto) {
                    for (angulo in listOf(0f, 90f)) {
                        rotate(angulo, canto) {
                            drawRoundRect(Color(0xFF4A4C53), canto - Offset(3.6f * ponto, 0.7f * ponto), Size(7.2f * ponto, 1.4f * ponto), CornerRadius(0.7f * ponto))
                        }
                    }
                }
            }
            // O reflexo do escovado: uma faixa larga que corre a chapa com a inclinacao, e uma
            // segunda, mais fina, um pouco atras.
            fun faixa(centro: Float, larguraDaFaixa: Float, alfa: Float) {
                val inicio = centro - larguraDaFaixa / 2
                drawRect(Brush.horizontalGradient(listOf(Color.White.copy(alpha = 0f), Color.White.copy(alpha = alfa), Color.White.copy(alpha = 0f)),
                                                  startX = inicio, endX = inicio + larguraDaFaixa),
                         Offset(inicio, 0f), Size(larguraDaFaixa, altura), blendMode = BlendMode.Screen)
            }
            faixa(largura * (0.5f - inclinacaoX * 0.9f), largura * 0.42f, 0.4f)
            faixa(largura * (0.82f - inclinacaoX * 1.3f), largura * 0.12f, 0.22f)
            // A luz de cima: mais clara quando a chapa vira para cima, mais escura para baixo.
            drawRect(Brush.verticalGradient(listOf(Color.White.copy(alpha = maxOf(0.05f, 0.16f - inclinacaoY * 0.12f)), Color.Transparent,
                                                   Color.Black.copy(alpha = maxOf(0f, 0.1f + inclinacaoY * 0.08f)))))
            // As bordas um pouco mais escuras, como metal de verdade sob uma luz so.
            drawRect(Brush.radialGradient(0f to Color.Transparent, (120f / 360f) to Color.Transparent, 1f to Color.Black.copy(alpha = 0.1f),
                                          center = Offset(largura / 2, altura / 2), radius = 360.dp.toPx()))
        }
        // O chanfro: a borda de cima pega a luz, a de baixo fica na sombra.
        val linha = 2.dp.toPx()
        drawRoundRect(Brush.verticalGradient(listOf(Color.White.copy(alpha = minOf(1f, 0.85f + maxOf(-inclinacaoY, 0f) * 0.15f)), Color(0xFF82848C))),
                      Offset(linha / 2, linha / 2), Size(largura - linha, altura - linha), CornerRadius(raio.x - linha / 2), style = Stroke(linha))
        val dentro = 5.dp.toPx()
        drawRoundRect(Color.Black.copy(alpha = 0.08f), Offset(dentro, dentro), Size(largura - 2 * dentro, altura - 2 * dentro),
                      CornerRadius(raio.x - dentro), style = Stroke(1.dp.toPx()))
    }
}

/**
 * Texto gravado no metal (o `engraved` do iOS): o sulco escuro, um fio escuro na borda de
 * cima e a luz batendo na borda de baixo.
 */
@Composable
fun TextoGravado(texto: String, estilo: TextStyle, profundidade: Dp, modifier: Modifier = Modifier, linhas: Int = 1) {
    Box(modifier) {
        Text(texto, style = estilo, color = Color.White.copy(alpha = 0.9f), maxLines = linhas, overflow = TextOverflow.Clip,
             modifier = Modifier.offset(y = profundidade * 1.3f))
        Text(texto, style = estilo, color = Color.Black.copy(alpha = 0.28f), maxLines = linhas, overflow = TextOverflow.Clip,
             modifier = Modifier.offset(y = -profundidade * 0.8f))
        Text(texto, style = estilo, color = Aco.tinta.copy(alpha = 0.94f), maxLines = linhas, overflow = TextOverflow.Clip)
    }
}
