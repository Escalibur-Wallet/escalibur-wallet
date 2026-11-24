package app.escalibur.wallet.ui.comp

import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * As animacoes do sistema desligadas (o "Reduzir movimento" do iOS): nas opcoes do desenvolvedor ou
 * em Acessibilidade, "Remover animacoes".
 */
@Composable
fun movimentoReduzido(): Boolean {
    val contexto = LocalContext.current
    return remember { Settings.Global.getFloat(contexto.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}

/**
 * O relogio das animacoes continuas (o `TimelineView` do iOS): os segundos desde que a tela abriu,
 * a cada quadro. Com o movimento reduzido, fica no zero.
 */
@Composable
fun relogio(parado: Boolean = movimentoReduzido()): State<Float> {
    val tempo = remember { mutableFloatStateOf(0f) }
    if (!parado) LaunchedEffect(Unit) {
        val inicio = withFrameNanos { it }
        while (true) withFrameNanos { tempo.floatValue = (it - inicio) / 1e9f }
    }
    return tempo
}

/** O 0 a 1 suave entre as pontas (o smoothstep). */
fun suave(x: Float): Float { val t = x.coerceIn(0f, 1f); return t * t * (3 - 2 * t) }

/** O 0 a 1 que passa do ponto e volta (o easeOutBack), para um visto que salta ao aparecer. */
fun saltoDeSaida(x: Float): Float {
    val t = x.coerceIn(0f, 1f)
    val c1 = 1.70158f
    val c3 = c1 + 1
    return 1 + c3 * (t - 1) * (t - 1) * (t - 1) + c1 * (t - 1) * (t - 1)
}

/**
 * O carregando do iOS (o `ProgressView` pequeno): oito raios arredondados, o mais claro girando em
 * passos, uma volta por segundo. No lugar do circulo do Android.
 */
@Composable
fun Girando(cor: Color, tamanho: Dp = 20.dp, modifier: Modifier = Modifier) {
    val tempo by relogio()
    Canvas(modifier.size(tamanho)) {
        val raios = 8
        val passo = (tempo * raios).toInt() % raios
        val raio = size.minDimension / 2
        val largura = raio * 0.24f
        for (i in 0 until raios) {
            // O raio da vez e o mais claro; os de tras vao apagando.
            val atras = (passo - i + raios) % raios
            val alfa = 1f - atras * 0.11f
            rotate(i * 360f / raios) {
                drawLine(cor.copy(alpha = cor.alpha * alfa), center.copy(y = center.y - raio * 0.48f), center.copy(y = center.y - raio + largura / 2),
                         strokeWidth = largura, cap = StrokeCap.Round)
            }
        }
    }
}
