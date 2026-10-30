package app.escalibur.wallet.ui.comp

import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.animation.core.spring
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
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
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.carteira.Saldos
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

/** Pelo contrato, CoinGecko e GeckoTerminal limitam por IP: de novo enquanto a tela esta aberta, como no iOS. */
val esperasDoContrato = listOf(0L, 6_000L, 15_000L, 30_000L, 60_000L)

/**
 * Preco com grafico e periodos, no detalhe do ativo e no Mercado. O dedo segurado no grafico
 * troca o preco pelo do ponto tocado. Linha em lima na alta e vermelho na queda. Tocar no preco
 * mostra a outra moeda (real e dolar), com o grafico junto.
 *
 * Sem `coingecko`, o grafico vem pelo `contrato` (o id do ativo: token fora da lista ou moeda
 * custom), do CoinGecko ou da pool de DEX com mais liquidez, e a nota embaixo diz de onde.
 * `reserva`: o token da lista com contrato, para a pool de DEX quando o CoinGecko e a OKX nao respondem.
 */
@Composable
fun SecaoDoGrafico(
    coingecko: String?, precoAoVivo: Double?, variacaoAoVivo: Double?, moeda: String, estavel: Boolean = false, precoGrande: Boolean = true,
    contrato: String? = null, reserva: String? = null,
) {
    var periodo by remember { mutableStateOf(Periodo.dia) }
    var pontos by remember(coingecko, contrato) { mutableStateOf<List<PontoDePreco>>(emptyList()) }
    var carregando by remember { mutableStateOf(false) }
    var falhou by remember { mutableStateOf(false) }
    var velhoDesde by remember { mutableStateOf<Date?>(null) }
    var escolhido by remember { mutableStateOf<PontoDePreco?>(null) }
    // Pelo contrato: "coingecko", "dex" (com a pool) ou "nenhuma" (nenhuma das duas fontes tem o token).
    var origem by remember(contrato) { mutableStateOf<String?>(null) }
    var pool by remember(contrato) { mutableStateOf<JSONObject?>(null) }
    fun lidos(r: JSONObject) = r.optJSONArray("pontos").objetos().map { PontoDePreco(it.data("t") ?: Date(), it.getDouble("p")) }
    LaunchedEffect(coingecko, contrato, periodo, moeda) {
        if (coingecko == null) {
            if (contrato == null) return@LaunchedEffect
            carregando = true
            for (espera in esperasDoContrato) {
                if (espera > 0) delay(espera)
                val r = runCatching {
                    Api.objeto("mercado.graficoDoContrato", JSONObject().put("id", contrato).put("moeda", moeda).put("intervalo", periodo.chave))
                }.getOrNull()
                if (r == null) { falhou = true; continue }
                falhou = false
                pontos = lidos(r)
                velhoDesde = if (r.optBoolean("velho")) r.data("atualizado") else null
                origem = r.optString("fonte")
                pool = r.optJSONObject("pool")
                break
            }
            carregando = false
            return@LaunchedEffect
        }
        carregando = true
        val pedido = JSONObject().put("id", coingecko).put("moeda", moeda).put("intervalo", periodo.chave)
        reserva?.let { pedido.put("reserva", it) }
        val resposta = runCatching { Api.objeto("mercado.grafico", pedido) }.getOrNull()
        carregando = false
        if (resposta == null) {
            falhou = true
            return@LaunchedEffect
        }
        falhou = false
        pontos = lidos(resposta)
        velhoDesde = if (resposta.optBoolean("velho")) resposta.data("atualizado") else null
    }
    // Sem a lista do Mercado aberta, o 24h se atualiza sozinho de tempos em tempos.
    LaunchedEffect(coingecko, periodo) {
        while (coingecko != null && periodo == Periodo.dia) {
            delay(60_000)
            runCatching { Api.objeto("mercado.grafico", JSONObject().put("id", coingecko).put("moeda", moeda).put("intervalo", "day")) }.getOrNull()?.let { r ->
                pontos = lidos(r)
            }
        }
    }
    // A unidade mostrada: a escolhida em Ativos (real, dolar, euro ou bitcoin), ou, ao tocar no preco, a outra (o dolar, ou o
    // real para quem nao usa real). Sem cotacao para a unidade, a moeda dos precos.
    var outra by remember { mutableStateOf(false) }
    val retrato = Saldos.retrato
    val escolhida = App.estado.unidade.takeIf { retrato.converter(1.0, it) != null } ?: moeda
    val alternativa = if (escolhida == "brl") "usd" else "brl"
    val unidade = if (outra) alternativa else escolhida
    val fator = if (unidade == moeda) 1.0 else retrato.converter(1.0, unidade) ?: 1.0
    val mostrados = remember(pontos, fator) { if (fator == 1.0) pontos else pontos.map { PontoDePreco(it.tempo, it.preco * fator) } }
    val toque = toqueDeSelecao()
    // O ponto escolhido no grafico ja vem na unidade mostrada; o preco vivo, nao.
    val preco = escolhido?.preco ?: (precoAoVivo ?: pontos.lastOrNull()?.preco)?.let { it * fator }
    val primeiro = mostrados.firstOrNull()?.preco
    val variacao = when {
        escolhido != null && primeiro != null && primeiro > 0 -> (escolhido!!.preco - primeiro) / primeiro * 100
        periodo == Periodo.dia && variacaoAoVivo != null -> variacaoAoVivo
        primeiro != null && primeiro > 0 && mostrados.size > 1 -> (mostrados.last().preco - primeiro) / primeiro * 100
        else -> variacaoAoVivo
    }
    Column {
        Text(preco?.let { Formato.preco(it, unidade) } ?: " ", style = estilo(if (precoGrande) Tipo.numero else Tipo.linha), color = Paleta.tinta,
             modifier = Modifier.padding(horizontal = Espaco.margem).clickable(
                 interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null,
                 onClickLabel = if (alternativa == "brl") t("Toque para ver em reais") else t("Toque para ver em dólar"),
             ) {
                 if (outra || retrato.converter(1.0, alternativa) != null) { outra = !outra; toque() }
             })
        Row(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xxs), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            variacao?.let {
                Text(Formato.percentual(it), style = estilo(Tipo.nota), color = if (it > 0.004) Paleta.alta else if (it < -0.004) Paleta.baixa else Paleta.tintaSuave)
            }
            Text(escolhido?.let { Formato.relativo(it.tempo) } ?: if (periodo == Periodo.tudo && pontos.isNotEmpty()) {
                t("desde %@", java.text.SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(Formato.locale, "MMMyyyy"), Formato.locale).format(pontos.first().tempo))
            } else periodo.legenda, style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
        GraficoDePreco(mostrados, carregando && pontos.isEmpty(), estavel, unidade, Modifier.padding(top = Espaco.sm), falhou = falhou) { escolhido = it }
        when {
            origem == "nenhuma" -> Text(t("Sem gráfico: o CoinGecko não lista este contrato e o GeckoTerminal não tem pool com liquidez para ele."),
                                        style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(horizontal = Espaco.margem))
            falhou && pontos.isEmpty() -> Text(t("Não foi possível carregar o gráfico agora."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                                               modifier = Modifier.padding(horizontal = Espaco.margem))
            velhoDesde != null -> Text(t("Gráfico de %@. As fontes de preço não responderam agora; o app tenta de novo sozinho.", Formato.carimbo(velhoDesde!!)),
                                       style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(horizontal = Espaco.margem))
        }
        SeletorDePeriodo(periodo, Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm)) {
            escolhido = null
            periodo = it
        }
        // De onde vem o grafico de um token fora da lista, dito embaixo dele.
        val nota = when {
            contrato == null || coingecko != null -> null
            origem == "coingecko" -> t("Gráfico do CoinGecko, pelo contrato. O token não está na lista conferida da Escalibur.")
            origem == "dex" && pool != null -> t(
                "Preço da pool %@ na %@, com %@ de liquidez, pelo GeckoTerminal. É preço de DEX: qualquer um cria uma pool, e por isso ele não entra no saldo total.",
                pool!!.optString("nome"), pool!!.optString("dex"), "US$\u00A0" + Formato.compacto(pool!!.optDouble("liquidez")),
            )
            else -> null
        }
        nota?.let {
            Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm))
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
    // O ultimo ponto escolhido: o corte fica nele enquanto a cor volta, depois de soltar.
    var corte by remember(mostrados) { mutableStateOf<Int?>(null) }
    // Quanto o que vem depois do ponto esta apagado: entra e sai animado, sem corte seco (pedido do
    // dono, 23/10/2026), como no iOS.
    val apagado by animateFloatAsState(
        if (indice != null) 1f else 0f,
        if (indice != null) tween(280, easing = LinearOutSlowInEasing) else tween(400, easing = FastOutSlowInEasing), label = "apagado",
    )
    // O toque que vem logo depois de um arrasto (soltar sem mexer) nao conta como toque.
    var arrastou by remember { mutableStateOf(false) }
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
                    // O corte no pixel, no ponto escolhido (ou no ultimo, enquanto a cor volta).
                    fun xDoCorte(): Float? = (indice ?: corte)?.takeIf { apagado > 0.001f && it in mostrados.indices }?.let { kotlin.math.round(lugar(it).x) }
                    // O brilho desfocado embaixo da linha (o desfoque vale do Android 12 em diante).
                    // Com o dedo no grafico, o de depois do ponto escolhido se apaga.
                    Canvas(Modifier.fillMaxSize().blur(14.dp)) {
                        val brilho = Path()
                        mostrados.indices.forEach { i -> val p = lugar(i); if (i == 0) brilho.moveTo(p.x, p.y) else brilho.lineTo(p.x, p.y) }
                        val estilo = Stroke(width = 10.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
                        val x = xDoCorte()
                        if (x == null) drawPath(brilho, cor.copy(alpha = 0.34f), style = estilo) else {
                            clipRect(right = x) { drawPath(brilho, cor.copy(alpha = 0.34f), style = estilo) }
                            clipRect(left = x) { drawPath(brilho, cor.copy(alpha = 0.34f * (1f - apagado)), style = estilo) }
                        }
                    }
                    fun indiceEm(x: Float): Int {
                        val fracao = ((x - margem) / maxOf(largura - margem * 2, 1f)).coerceIn(0f, 1f)
                        return (fracao * (mostrados.size - 1)).roundToInt()
                    }
                    fun escolher(x: Float) {
                        val novo = indiceEm(x)
                        if (novo != indice) {
                            indice = novo
                            corte = novo
                            haptico.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            aoEscolher(mostrados[novo])
                        }
                    }
                    Canvas(
                        Modifier.fillMaxSize().pointerInput(mostrados) {
                            // Um toque simples tambem escolhe o ponto, e ele fica ate outro toque: no
                            // mesmo ponto, o grafico volta ao presente; em outro, o ponto muda.
                            detectTapGestures(onPress = { arrastou = false }) { toque ->
                                if (arrastou) return@detectTapGestures
                                val atual = indice
                                if (atual != null && kotlin.math.abs(lugar(atual).x - lugar(indiceEm(toque.x)).x) < 22.dp.toPx()) {
                                    indice = null
                                    aoEscolher(null)
                                } else escolher(toque.x)
                            }
                        }.pointerInput(mostrados) {
                            detectDragGesturesAfterLongPress(
                                onDragStart = { arrastou = true; escolher(it.x) },
                                onDrag = { mudanca, _ -> escolher(mudanca.position.x) },
                                onDragEnd = { indice = null; aoEscolher(null) },
                                onDragCancel = { indice = null; aoEscolher(null) },
                            )
                        }.pointerInput(mostrados) {
                            // Arrastar de lado mexe o ponto na hora, sem segurar antes (pedido do dono,
                            // 27/10/2026); na vertical, quem leva e a rolagem da tela.
                            detectHorizontalDragGestures(
                                onDragStart = { arrastou = true; escolher(it.x) },
                                onDragEnd = { indice = null; aoEscolher(null) },
                                onDragCancel = { indice = null; aoEscolher(null) },
                            ) { mudanca, _ -> mudanca.consume(); escolher(mudanca.position.x) }
                        },
                    ) {
                        val linha = Path()
                        mostrados.indices.forEach { i -> val p = lugar(i); if (i == 0) linha.moveTo(p.x, p.y) else linha.lineTo(p.x, p.y) }
                        val traco = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
                        // Com o dedo no grafico, o que vem depois do ponto escolhido fica cinza
                        // apagado: o grafico "volta no tempo" ate ali (pedido do dono, 22/10/2026). O
                        // cinza entra e sai aos poucos, com a regua e o ponto.
                        val x = xDoCorte()
                        val i = indice ?: corte
                        if (x == null || i == null) drawPath(linha, cor, style = traco) else {
                            clipRect(right = x) { drawPath(linha, cor, style = traco) }
                            clipRect(left = x) {
                                drawPath(linha, Paleta.bordaForte, style = traco)
                                drawPath(linha, cor, alpha = 1f - apagado, style = traco)
                            }
                            val p = lugar(i)
                            drawLine(Paleta.tintaApagada, Offset(x, espacoDoRotulo), Offset(x, size.height - espacoDoRotulo), 1.dp.toPx(), alpha = apagado)
                            drawCircle(Paleta.vazio, 6.dp.toPx(), p, alpha = apagado)
                            drawCircle(cor, 4.5.dp.toPx(), p, alpha = apagado)
                        }
                    }
                    // A maxima e a minima do periodo, junto do ponto delas.
                    for (topo in listOf(true, false)) {
                        val alvo = if (topo) precos.max() else precos.min()
                        val i = precos.indexOf(alvo).coerceAtLeast(0)
                        val p = lugar(i)
                        Text(
                            Formato.preco(alvo, moeda), style = estilo(Tipo.eixo), color = Paleta.tintaSuave, maxLines = 1, softWrap = false,
                            modifier = Modifier.layout { medida, limites ->
                                val peca = medida.measure(limites.copy(minWidth = 0, maxWidth = Int.MAX_VALUE))
                                layout(peca.width, peca.height) {
                                    val borda = 48.dp.toPx()
                                    val cx = p.x.coerceIn(borda, largura - borda)
                                    val cy = if (topo) p.y - 16.dp.toPx() else p.y + 16.dp.toPx()
                                    peca.place((cx - peca.width / 2).roundToInt(), (cy - peca.height / 2).roundToInt())
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

/** Os periodos, por extenso ("1M" e ambiguo entre minuto e mes), sem trilho: so a escolha em vidro, que desliza. */
@Composable
private fun SeletorDePeriodo(periodo: Periodo, modifier: Modifier = Modifier, aoEscolher: (Periodo) -> Unit) {
    val toque = toqueDeSelecao()
    val indice = Periodo.entries.indexOf(periodo)
    BoxWithConstraints(modifier.fillMaxWidth().height(38.dp)) {
        val largura = (maxWidth - 2.dp * (Periodo.entries.size - 1)) / Periodo.entries.size
        val x by animateDpAsState((largura + 2.dp) * indice, spring(dampingRatio = 0.82f, stiffness = 380f), label = "periodo")
        Box(Modifier.offset(x = x).width(largura).fillMaxHeight().vidro(CircleShape, Vidros.selecao))
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            for (opcao in Periodo.entries) {
                val escolhida = opcao == periodo
                Box(
                    Modifier.weight(1f).fillMaxHeight().clip(CircleShape).clickable {
                        if (!escolhida) toque()
                        aoEscolher(opcao)
                    },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(opcao.rotulo, style = estilo(Tipo.rotulo).copy(fontWeight = if (escolhida) FontWeight.SemiBold else FontWeight.Normal),
                         color = if (escolhida) Paleta.tinta else Paleta.tintaApagada, maxLines = 1)
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
fun GraficoCarregando(modifier: Modifier = Modifier, folga: androidx.compose.ui.unit.Dp = 26.dp) {
    val parado = LocalContext.current.let { android.provider.Settings.Global.getFloat(it.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
    var tempo by remember { mutableFloatStateOf(0f) }
    if (!parado) LaunchedEffect(Unit) {
        val inicio = withFrameNanos { it }
        while (true) withFrameNanos { tempo = (it - inicio) / 1e9f }
    }
    Canvas(modifier.fillMaxSize()) {
        val margem = Espaco.margem.toPx()
        val espacoDoRotulo = folga.toPx()
        val largura = size.width - margem * 2
        val altura = size.height - espacoDoRotulo * 2
        val linha = Path()
        val passos = 90
        for (passo in 0..passos) {
            val x = passo / passos.toFloat()
            val onda = 0.5f + 0.16f * sin(x * 2 * PI.toFloat() * 1.2f + tempo * 0.9f) + 0.08f * sin(x * 2 * PI.toFloat() * 2.9f - tempo * 1.3f)
            val px = margem + largura * x
            val py = espacoDoRotulo + altura - altura * onda
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

/**
 * A pilula da variacao do dia, em vidro (o `ChangePill` do iOS): so o triangulo tem cor, lima na alta
 * e vermelho na queda; o numero, sem sinal (o triangulo ja diz a direcao), fica na tinta do app.
 * Abaixo de 0,01% e neutra, sem triangulo.
 */
@Composable
fun PilulaDeVariacao(variacao: Double?, modifier: Modifier = Modifier) {
    val valor = variacao ?: 0.0
    val sobe = valor > 0.004
    val desce = valor < -0.004
    Row(
        modifier.defaultMinSize(minWidth = 80.dp, minHeight = 28.dp).vidro(CircleShape, Vidros.pilula).padding(horizontal = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterHorizontally),
    ) {
        if (sobe || desce) Icone(if (sobe) Icones.trianguloAcima else Icones.trianguloAbaixo, if (sobe) Paleta.alta else Paleta.baixa, tamanho = 9.dp)
        Text(Formato.percentual(kotlin.math.abs(valor)).removePrefix("+"), style = estilo(Tipo.rotulo).copy(fontFeatureSettings = "tnum"),
             color = if (sobe || desce) Paleta.tinta else Paleta.tintaSuave, maxLines = 1)
    }
}
