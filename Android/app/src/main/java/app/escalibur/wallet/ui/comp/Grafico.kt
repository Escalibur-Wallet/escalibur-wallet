package app.escalibur.wallet.ui.comp

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.data
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.delay
import org.json.JSONObject
import java.util.Date
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

data class PontoDePreco(val tempo: Date, val preco: Double)

enum class Periodo(val chave: String) {
    dia("day"), semana("week"), mes("month"), ano("year"), tudo("all");

    val rotulo: String get() = when (this) {
        dia -> "24h"
        semana -> t("7 dias")
        mes -> t("30 dias")
        ano -> t("1 ano")
        tudo -> t("Tudo")
    }

    val legenda: String get() = when (this) {
        dia -> t("em 24h")
        semana -> t("em 7 dias")
        mes -> t("em 30 dias")
        ano -> t("em 1 ano")
        tudo -> t("desde o início")
    }
}

/**
 * Preco com grafico e periodos, no detalhe do ativo e no Mercado. O dedo segurado no grafico
 * troca o preco pelo do ponto tocado. Linha em lima na alta e vermelho na queda.
 */
@Composable
fun SecaoDoGrafico(coingecko: String, precoAoVivo: Double?, variacaoAoVivo: Double?, moeda: String, estavel: Boolean = false, precoGrande: Boolean = true) {
    var periodo by remember { mutableStateOf(Periodo.dia) }
    var pontos by remember(coingecko) { mutableStateOf<List<PontoDePreco>>(emptyList()) }
    var carregando by remember { mutableStateOf(false) }
    var falhou by remember { mutableStateOf(false) }
    var velhoDesde by remember { mutableStateOf<Date?>(null) }
    var escolhido by remember { mutableStateOf<PontoDePreco?>(null) }
    LaunchedEffect(coingecko, periodo, moeda) {
        carregando = true
        val resposta = runCatching { Api.objeto("mercado.grafico", JSONObject().put("id", coingecko).put("moeda", moeda).put("intervalo", periodo.chave)) }.getOrNull()
        carregando = false
        if (resposta == null) {
            falhou = true
            return@LaunchedEffect
        }
        falhou = false
        pontos = resposta.optJSONArray("pontos").objetos().map { PontoDePreco(it.data("t") ?: Date(), it.getDouble("p")) }
        velhoDesde = if (resposta.optBoolean("velho")) resposta.data("atualizado") else null
    }
    // Sem a lista do Mercado aberta, o 24h se atualiza sozinho de tempos em tempos.
    LaunchedEffect(coingecko, periodo) {
        while (periodo == Periodo.dia) {
            delay(60_000)
            runCatching { Api.objeto("mercado.grafico", JSONObject().put("id", coingecko).put("moeda", moeda).put("intervalo", "day")) }.getOrNull()?.let { r ->
                pontos = r.optJSONArray("pontos").objetos().map { PontoDePreco(it.data("t") ?: Date(), it.getDouble("p")) }
            }
        }
    }
    val preco = escolhido?.preco ?: precoAoVivo ?: pontos.lastOrNull()?.preco
    val primeiro = pontos.firstOrNull()?.preco
    val variacao = when {
        escolhido != null && primeiro != null && primeiro > 0 -> (escolhido!!.preco - primeiro) / primeiro * 100
        periodo == Periodo.dia && variacaoAoVivo != null -> variacaoAoVivo
        primeiro != null && primeiro > 0 && pontos.size > 1 -> (pontos.last().preco - primeiro) / primeiro * 100
        else -> variacaoAoVivo
    }
    Column {
        Text(preco?.let { Formato.preco(it, moeda) } ?: " ", style = estilo(if (precoGrande) Tipo.numero else Tipo.linha), color = Paleta.tinta,
             modifier = Modifier.padding(horizontal = Espaco.margem))
        Row(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xxs), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            variacao?.let {
                Text(Formato.percentual(it), style = estilo(Tipo.nota), color = if (it > 0.004) Paleta.alta else if (it < -0.004) Paleta.baixa else Paleta.tintaSuave)
            }
            Text(escolhido?.let { Formato.relativo(it.tempo) } ?: if (periodo == Periodo.tudo && pontos.isNotEmpty()) {
                t("desde %@", java.text.SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(Formato.locale, "MMMyyyy"), Formato.locale).format(pontos.first().tempo))
            } else periodo.legenda, style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
        GraficoDePreco(pontos, carregando && pontos.isEmpty(), estavel, moeda, Modifier.padding(top = Espaco.sm), falhou = falhou) { escolhido = it }
        when {
            falhou && pontos.isEmpty() -> Text(t("Não foi possível carregar o gráfico agora."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                                               modifier = Modifier.padding(horizontal = Espaco.margem))
            velhoDesde != null -> Text(t("Gráfico de %@. As fontes de preço não responderam agora; o app tenta de novo sozinho.", Formato.relogio(velhoDesde!!)),
                                       style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(horizontal = Espaco.margem))
        }
        Segmentado(Periodo.entries.map { it to it.rotulo }, periodo, Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm)) {
            escolhido = null
            periodo = it
        }
    }
}

@Composable
fun GraficoDePreco(
    pontos: List<PontoDePreco>, carregando: Boolean, estavel: Boolean, moeda: String, modifier: Modifier = Modifier, falhou: Boolean = false,
    aoEscolher: (PontoDePreco?) -> Unit,
) {
    val haptico = LocalHapticFeedback.current
    // Muitos pontos viram 160 medias: a linha fica limpa e o toque, leve.
    val mostrados = remember(pontos) {
        if (pontos.size <= 160) pontos else {
            val tamanho = pontos.size / 160.0
            (0 until 160).mapNotNull { balde ->
                val inicio = (balde * tamanho).toInt()
                val fim = minOf(pontos.size, ((balde + 1) * tamanho).toInt())
                if (inicio >= fim) null else {
                    val fatia = pontos.subList(inicio, fim)
                    PontoDePreco(fatia.last().tempo, if (balde == 159) pontos.last().preco else fatia.sumOf { it.preco } / fatia.size)
                }
            }
        }
    }
    var indice by remember(mostrados) { mutableStateOf<Int?>(null) }
    Box(modifier.fillMaxWidth().height(248.dp), contentAlignment = Alignment.Center) {
        when {
            carregando -> GraficoCarregando()
            mostrados.size < 2 -> if (!falhou) Text(t("Sem histórico de preço neste período"), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            else -> {
                val precos = mostrados.map { it.preco }
                var baixo = precos.min()
                var alto = precos.max()
                if (estavel) {
                    val media = precos.average()
                    baixo = minOf(baixo, media * 0.99)
                    alto = maxOf(alto, media * 1.01)
                }
                if (alto <= baixo) alto = baixo + maxOf(kotlin.math.abs(baixo) * 0.01, 1e-12)
                val cor = when {
                    mostrados.last().preco > mostrados.first().preco -> Paleta.alta
                    mostrados.last().preco < mostrados.first().preco -> Paleta.baixa
                    else -> Paleta.tintaSuave
                }
                val margem = with(LocalDensity.current) { Espaco.margem.toPx() }
                val espacoDoRotulo = with(LocalDensity.current) { 26.dp.toPx() }
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    val largura = constraints.maxWidth.toFloat()
                    val altura = constraints.maxHeight.toFloat()
                    fun lugar(i: Int): Offset {
                        val x = margem + (largura - margem * 2) * i / (mostrados.size - 1)
                        val fracao = ((mostrados[i].preco - baixo) / (alto - baixo)).toFloat()
                        return Offset(x, altura - espacoDoRotulo - (altura - espacoDoRotulo * 2) * fracao)
                    }
                    // O brilho desfocado embaixo da linha (o desfoque vale do Android 12 em diante).
                    Canvas(Modifier.fillMaxSize().blur(14.dp)) {
                        val brilho = Path()
                        mostrados.indices.forEach { i -> val p = lugar(i); if (i == 0) brilho.moveTo(p.x, p.y) else brilho.lineTo(p.x, p.y) }
                        drawPath(brilho, cor.copy(alpha = 0.34f), style = Stroke(width = 10.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
                    }
                    Canvas(
                        Modifier.fillMaxSize().pointerInput(mostrados) {
                            fun escolher(x: Float) {
                                val fracao = ((x - margem) / maxOf(largura - margem * 2, 1f)).coerceIn(0f, 1f)
                                val novo = (fracao * (mostrados.size - 1)).roundToInt()
                                if (novo != indice) {
                                    indice = novo
                                    haptico.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                    aoEscolher(mostrados[novo])
                                }
                            }
                            detectDragGesturesAfterLongPress(
                                onDragStart = { escolher(it.x) },
                                onDrag = { mudanca, _ -> escolher(mudanca.position.x) },
                                onDragEnd = { indice = null; aoEscolher(null) },
                                onDragCancel = { indice = null; aoEscolher(null) },
                            )
                        },
                    ) {
                        val linha = Path()
                        mostrados.indices.forEach { i -> val p = lugar(i); if (i == 0) linha.moveTo(p.x, p.y) else linha.lineTo(p.x, p.y) }
                        drawPath(linha, cor, style = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
                        indice?.let { i ->
                            val p = lugar(i)
                            drawLine(Paleta.tintaApagada, Offset(p.x, espacoDoRotulo), Offset(p.x, size.height - espacoDoRotulo), 1.dp.toPx())
                            drawCircle(Paleta.vazio, 6.dp.toPx(), p)
                            drawCircle(cor, 4.5.dp.toPx(), p)
                        }
                    }
                    // A maxima e a minima do periodo, junto do ponto delas.
                    for (topo in listOf(true, false)) {
                        val alvo = if (topo) precos.max() else precos.min()
                        val i = precos.indexOf(alvo).coerceAtLeast(0)
                        val p = lugar(i)
                        val densidade = LocalDensity.current
                        Text(
                            Formato.preco(alvo, moeda), style = estilo(Tipo.eixo), color = Paleta.tintaSuave,
                            modifier = Modifier.offset {
                                IntOffset((p.x - with(densidade) { 40.dp.toPx() }).coerceIn(0f, largura - with(densidade) { 90.dp.toPx() }).roundToInt(),
                                          (if (topo) p.y - with(densidade) { 22.dp.toPx() } else p.y + with(densidade) { 6.dp.toPx() }).roundToInt())
                            },
                        )
                    }
                }
            }
        }
    }
}

/**
 * O grafico carregando, como no iOS: uma linha fantasma cinza que ondula devagar, com um brilho que
 * corre da esquerda para a direita. Cinza e sem rotulos, para nunca passar por dado. Com as animacoes
 * do sistema desligadas, fica parada. O Mercado sem fonte usa a mesma linha.
 */
@Composable
fun GraficoCarregando(modifier: Modifier = Modifier) {
    val parado = LocalContext.current.let { android.provider.Settings.Global.getFloat(it.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
    var tempo by remember { mutableFloatStateOf(0f) }
    if (!parado) LaunchedEffect(Unit) {
        val inicio = withFrameNanos { it }
        while (true) withFrameNanos { tempo = (it - inicio) / 1e9f }
    }
    Canvas(modifier.fillMaxSize()) {
        val margem = Espaco.margem.toPx()
        val folga = 26.dp.toPx()
        val largura = size.width - margem * 2
        val altura = size.height - folga * 2
        val linha = Path()
        val passos = 90
        for (passo in 0..passos) {
            val x = passo / passos.toFloat()
            val onda = 0.5f + 0.16f * sin(x * 2 * PI.toFloat() * 1.2f + tempo * 0.9f) + 0.08f * sin(x * 2 * PI.toFloat() * 2.9f - tempo * 1.3f)
            val px = margem + largura * x
            val py = folga + altura - altura * onda
            if (passo == 0) linha.moveTo(px, py) else linha.lineTo(px, py)
        }
        val traco = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
        drawPath(linha, Paleta.bordaForte, style = traco)
        if (parado) return@Canvas
        // O brilho: uma janela que atravessa a linha, mais clara no meio.
        val fase = (tempo % 1.8f) / 1.8f
        val janela = largura * 0.28f
        val centro = margem - janela / 2 + (largura + janela) * fase
        clipRect(left = centro - janela / 2, right = centro + janela / 2) {
            drawPath(linha, Brush.horizontalGradient(
                0f to Paleta.tintaSuave.copy(alpha = 0f), 0.5f to Paleta.tintaSuave, 1f to Paleta.tintaSuave.copy(alpha = 0f),
                startX = centro - janela / 2, endX = centro + janela / 2,
            ), style = traco)
        }
    }
}

/** A pilula da variacao do dia: so a seta tem cor, lima na alta e vermelho na queda. */
@Composable
fun PilulaDeVariacao(variacao: Double?, modifier: Modifier = Modifier) {
    val valor = variacao ?: 0.0
    val sobe = valor > 0.004
    val desce = valor < -0.004
    Row(
        modifier.height(28.dp).background(Paleta.corpo, androidx.compose.foundation.shape.CircleShape)
            .padding(horizontal = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        if (sobe || desce) Icone(if (sobe) Icones.acima else Icones.abaixo, if (sobe) Paleta.alta else Paleta.baixa, tamanho = 9.dp)
        Text(Formato.percentual(kotlin.math.abs(valor)).removePrefix("+"), style = estilo(Tipo.rotulo), color = if (sobe || desce) Paleta.tinta else Paleta.tintaSuave)
    }
}
