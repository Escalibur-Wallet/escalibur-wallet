package app.escalibur.wallet.ui.novacarteira

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.PixelsCifrando
import app.escalibur.wallet.ui.comp.movimentoReduzido
import app.escalibur.wallet.ui.comp.relogio
import app.escalibur.wallet.ui.comp.toqueDeSelecao
import app.escalibur.wallet.ui.principal.FolhaDoIos
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.pow

/**
 * A lista do "Estou ciente que:": cada frase marca e desmarca num toque, com o circulo verde do iOS. O botao da tela so liga com
 * todas marcadas.
 */
@Composable
fun DeclaracoesDeCiente(declaracoes: List<String>, cientes: SnapshotStateList<Int>, modifier: Modifier = Modifier) {
    val toque = toqueDeSelecao()
    Column(modifier) {
        declaracoes.forEachIndexed { indice, declaracao ->
            val marcada = indice in cientes
            Row(
                Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).clickable {
                    if (marcada) cientes.remove(indice) else cientes.add(indice)
                    toque()
                },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
            ) {
                Box(
                    Modifier.size(22.dp).clip(CircleShape).background(if (marcada) Paleta.sucesso else Paleta.vazio)
                        .border(1.5.dp, if (marcada) Paleta.sucesso else Paleta.tintaApagada, CircleShape),
                    contentAlignment = Alignment.Center,
                ) { if (marcada) Icone(Icones.visto, Paleta.vazio, tamanho = 12.dp) }
                Text(declaracao, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
            }
        }
    }
}

/**
 * Antes de copiar a frase (o `CopyPhraseSheet` do iOS): o que pode dar errado, tres "estou ciente" e so entao o botao. A copia
 * sai marcada como sensivel e some em 1 minuto.
 */
@Composable
fun FolhaDaCopia(aoCopiar: () -> Unit, aoFechar: () -> Unit) {
    val declaracoes = listOf(
        t("Qualquer app que eu abrir pode ler o que está copiado"),
        t("Colar as palavras num site, chat ou nota pode custar o saldo"),
        t("A Escalibur nunca pede as palavras"),
    )
    val cientes = remember { mutableStateListOf<Int>() }
    FolhaDoIos(aoFechar) { fechar ->
        Column(Modifier.fillMaxSize().background(Paleta.vazio).navigationBarsPadding().padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs)) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                Box(Modifier.fillMaxWidth().padding(top = Espaco.xl), contentAlignment = Alignment.Center) { ContagemDaCopia() }
                Text(t("Copiar a senha da carteira?"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.md))
                Text(t("A cópia some sozinha em 1 minuto, e o Android não mostra o que ela tem na prévia. Anotar no papel continua sendo o mais seguro."),
                     style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
                Text(t("Estou ciente que:"), style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
                DeclaracoesDeCiente(declaracoes, cientes)
                Spacer(Modifier.padding(top = Espaco.lg))
            }
            BotaoPrimario(t("Copiar as palavras"), ligado = cientes.size == declaracoes.size, claro = true) { aoCopiar(); fechar() }
            BotaoTerciario(t("Agora não"), Modifier.fillMaxWidth()) { fechar() }
        }
    }
}

/**
 * A cena da copia, em pixels (a `ClipboardCountdown` do iOS): tres palavras, so em pixels cinza que cifram, entram na prancheta;
 * um anel verde liso em volta do relogio conta o minuto no tempo de verdade; no zero, os pixels das palavras se desfazem para
 * cima e somem. Em ciclo. Com o movimento reduzido, a prancheta cheia e o anel inteiro, parados.
 */
@Composable
private fun ContagemDaCopia() {
    val parado = movimentoReduzido()
    val tempo = relogio(parado)
    val minuto = 60f
    val contarDe = 1.4f
    val periodo = contarDe + minuto + 1.8f
    fun limitar(x: Float) = x.coerceIn(0f, 1f)
    fun t() = if (parado) 1.4f else tempo.value % periodo
    val restante by remember { derivedStateOf { if (parado) 1f else 1 - limitar((t() - contarDe) / minuto) } }
    val desfeito by remember { derivedStateOf { if (parado) 0f else limitar((t() - contarDe - minuto) / 1.2f) } }
    val segundos by remember { derivedStateOf { ceil(restante * minuto).toInt() } }
    val tamanhos = listOf(9, 7, 8)
    Box(Modifier.size(140.dp, 112.dp)) {
        // A prancheta, com o prendedor no alto.
        Box(Modifier.offset(x = 24.dp).size(116.dp, 100.dp)) {
            val forma = RoundedCornerShape(14.dp)
            Box(Modifier.fillMaxSize().clip(forma).background(Paleta.corpo).border(1.dp, Paleta.bordaForte, forma))
            Box(Modifier.align(Alignment.TopCenter).offset(y = (-6).dp).size(46.dp, 12.dp).clip(CircleShape).background(Paleta.controle)
                    .border(1.dp, Paleta.bordaForte, CircleShape))
            Canvas(Modifier.fillMaxSize()) {
                val agora = t()
                val relogioDoTom = if (parado) 0.0 else tempo.value.toDouble()
                val dissolve = if (parado) 0f else limitar((agora - contarDe - minuto) / 1.2f)
                for ((linha, quantos) in tamanhos.withIndex()) {
                    val entra = 1 - (1 - limitar((agora - 0.15f - linha * 0.22f) / 0.45f)).pow(3)
                    val y = (28 + linha * 17).dp.toPx()
                    // O numero da palavra, como na chapa.
                    drawRoundRect(Paleta.tintaApagada.copy(alpha = entra * (1 - dissolve)), Offset(16.dp.toPx(), y + 1.dp.toPx()),
                                  Size(8.dp.toPx(), 5.dp.toPx()), CornerRadius(1.5.dp.toPx()))
                    for (indice in 0 until quantos) {
                        val id = linha * 16 + indice
                        val sobe = dissolve * (14 + 24 * PixelsCifrando.ruido(id, 5, 0x91).toFloat())
                        val desvio = dissolve * (PixelsCifrando.ruido(id, 6, 0x92).toFloat() - 0.5f) * 16
                        val alfa = entra * (1 - limitar(dissolve * 1.3f - PixelsCifrando.ruido(id, 7, 0x93).toFloat() * 0.3f))
                        if (alfa <= 0.01f) continue
                        val x = 30 + indice * 7 - (1 - entra) * 24 + desvio
                        val lado = 5.4f * (1 - 0.4f * dissolve)
                        drawRoundRect(PixelsCifrando.cinza(tom(id, relogioDoTom)).copy(alpha = alfa), Offset(x.dp.toPx(), (y - sobe.dp.toPx())),
                                      Size(lado.dp.toPx(), lado.dp.toPx()), CornerRadius(1.2.dp.toPx()))
                    }
                }
            }
        }
        // O relogio de 1 minuto: um anel verde liso que esvazia continuo, com os segundos no meio.
        Box(Modifier.offset(x = 114.dp, y = (-20).dp).size(48.dp).alpha(1 - desfeito * 0.6f), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                drawCircle(Paleta.vazio)
                val traco = 3.dp.toPx()
                val recuo = 5.dp.toPx() + traco / 2
                val lado = size.width - 2 * recuo
                drawCircle(Paleta.sucesso.copy(alpha = 0.18f), radius = lado / 2, style = Stroke(traco))
                drawArc(Paleta.sucesso, -90f, 360f * restante, false, Offset(recuo, recuo), Size(lado, lado), style = Stroke(traco, cap = StrokeCap.Round))
            }
            Text(if (segundos >= 60) "1:00" else "0:%02d".format(segundos), color = Paleta.tinta,
                 style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"))
        }
    }
}

/** O cinza de cada pixel, que muda devagar e cada um no seu passo. */
private fun tom(id: Int, relogio: Double): Double {
    val fase = PixelsCifrando.ruido(id, 4, 0x55)
    val batida = relogio * 6 * (0.6 + 0.8 * fase) + fase * 8
    val degrau = floor(batida)
    val f = batida - degrau
    val mistura = f * f * (3 - 2 * f)
    val a = PixelsCifrando.ruido(id, 4, degrau.toLong())
    val b = PixelsCifrando.ruido(id, 4, degrau.toLong() + 1)
    return 0.38 + 0.4 * (a + (b - a) * mistura)
}
