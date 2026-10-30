package app.escalibur.wallet.ui.trocar

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import app.escalibur.wallet.ui.comp.Interruptor
import app.escalibur.wallet.ui.comp.Girando
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.rememberCoroutineScope
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.Ciclo
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.receber.opcional
import kotlinx.coroutines.launch
import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.Confirmacao
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.delay
import org.json.JSONObject
import java.text.DateFormat
import java.util.Date

/**
 * As ordens limite abertas desta carteira em todas as redes com ordem limite, lidas da rede, ali
 * mesmo na tela da troca (auditoria 2, A3). A lista rele a cada 6 s enquanto esta na tela. Na troca
 * imediata (`soComOrdens`), a secao so aparece quando ha ordem.
 */
@Composable
fun OrdensAbertas(soComOrdens: Boolean, modifier: Modifier = Modifier) {
    val dono = LocalLifecycleOwner.current
    val carteira = App.estado.carteira?.id
    var visiveis by remember(carteira) { mutableIntStateOf(10) }
    var detalhe by remember { mutableStateOf<LinhaDaOrdem?>(null) }
    var cancelando by remember { mutableStateOf<LinhaDaOrdem?>(null) }
    LaunchedEffect(carteira, ControleDasOrdens.pedido) {
        ControleDasOrdens.mostrar()
        dono.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            var inicial = true
            while (true) {
                ControleDasOrdens.ler(inicial)
                inicial = false
                delay(6_000)
            }
        }
    }
    val o = ControleDasOrdens.retrato
    val temLinhas = o != null && (o.ordens.isNotEmpty() || o.terminadas.isNotEmpty())
    if (soComOrdens && !temLinhas) return
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Text(if (o != null && o.ordens.isNotEmpty()) t("Ordens abertas (%lld)", o.ordens.size) else t("Ordens abertas"),
             style = estilo(Tipo.cabecalho), color = Paleta.tinta)
        when {
            o == null || o.carregando -> Row(Modifier.heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically,
                                             horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                Girando(Paleta.tintaSuave, 16.dp)
                Text(t("Lendo as ordens na rede."), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            }
            o.falha != null && o.ordens.isEmpty() -> Column {
                Text(o.falha, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                BotaoTerciario(t("Tentar de novo")) { ControleDasOrdens.reler() }
            }
            !temLinhas -> {
                Text(t("Nenhuma ordem aberta. A que você criar, em qualquer rede, aparece aqui até executar, vencer ou você cancelar."),
                     style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                o.semResposta?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada) }
            }
            else -> {
                Column {
                    for (ordem in o.ordens.take(visiveis)) LinhaDaOrdemAberta(ordem) { detalhe = ordem }
                    for (terminada in o.terminadas) LinhaDaTerminada(terminada)
                }
                // De 10 em 10.
                if (o.ordens.size > visiveis) {
                    BotaoSecundario(t("Carregar mais (%lld)", minOf(10, o.ordens.size - visiveis)), Modifier.padding(top = Espaco.xs)) { visiveis += 10 }
                }
                o.semResposta?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada) }
                if (o.ordens.isNotEmpty()) {
                    Text(if (o.podeAssinar) t("Toque numa ordem para ver os detalhes, mudar ou cancelar.")
                         else t("Esta carteira só acompanha: para cancelar, abra a carteira que assina."),
                         style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                }
            }
        }
    }
    detalhe?.let { ordem ->
        FolhaDaOrdem(ordem, o?.podeAssinar == true, aoFechar = { detalhe = null }, aoEditar = {
            Navegacao.cobrir { TelaDeEditarOrdem(ordem.id) }
        }, aoCancelar = { cancelando = ordem })
    }
    // O cancelamento pergunta num popup, no meio da tela.
    cancelando?.let { ordem ->
        Confirmacao(
            t("Cancelar esta ordem?"), ordem.explicacao, t("Cancelar a ordem"),
            aoConfirmar = {
                cancelando = null
                Navegacao.cobrir { RevisaoDoCancelamento(ordem.id) }
            },
            aoCancelar = { cancelando = null }, tituloDoCancelar = t("Manter a ordem"),
        )
    }
}

/** A revisao do cancelamento de uma ordem: a mesma revisao, PIN e assinatura de qualquer plano. */
@Composable
fun RevisaoDoCancelamento(ordem: String) {
    val controle = remember { ControleDaTroca("cancelamento") }
    RevisaoDaTroca(controle, encerra = true) { it.trabalhar("troca.cancelar", JSONObject().put("ordem", ordem)) }
}

@Composable
private fun LinhaDaOrdemAberta(ordem: LinhaDaOrdem, acao: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Altura.linha).clickable(onClick = acao).padding(vertical = Espaco.xxs),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        LogoDaOrdem(ordem.vende, ordem.rede, ordem.redeCoingecko)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(ordem.titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            Text(ordem.detalhe, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            ordem.preco?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1) }
            if (ordem.fracao != null) Text(vencimento(ordem.vence), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
        val fracao = ordem.fracao
        if (fracao != null) AnelDoPreenchimento(fracao, 44.dp)
        else Text(vencimento(ordem.vence), style = estilo(Tipo.nota), color = Paleta.tintaSuave, textAlign = TextAlign.End)
    }
}

/**
 * A linha da ordem dentro do Enviar (o `LockedOrdersSheet` do iOS): como em Ordens abertas, com o cancelar na ponta. Com o
 * cancelamento enviado, o aviso de que a rede ainda confirma: ate la a ordem ainda pode executar.
 */
@Composable
fun LinhaDaOrdemQueCancela(ordem: LinhaDaOrdem, cancelando: Boolean, aoCancelar: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Altura.linha).padding(vertical = Espaco.xxs),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        LogoDaOrdem(ordem.vende, ordem.rede, ordem.redeCoingecko)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(ordem.titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            Text(ordem.detalhe, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            ordem.preco?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1) }
            if (cancelando) Text(t("Cancelamento enviado. Esperando a rede confirmar."), style = estilo(Tipo.nota), color = Paleta.cautela)
            else Text(vencimento(ordem.vence), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
        when {
            cancelando -> Girando(Paleta.tintaSuave, 18.dp)
            ordem.podeCancelar -> Box(
                Modifier.height(34.dp).clip(CircleShape).background(Paleta.trilho).clickable(onClick = aoCancelar).padding(horizontal = Espaco.sm),
                contentAlignment = Alignment.Center,
            ) { Text(t("Cancelar"), style = estilo(Tipo.rotulo), color = Paleta.baixa) }
        }
    }
}

@Composable
private fun LinhaDaTerminada(item: OrdemTerminada) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Altura.linha).padding(vertical = Espaco.xxs),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        LogoDaOrdem(item.vende, item.vende?.rede, item.vende?.redeCoingecko)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(item.titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            Text(item.resultado, style = estilo(Tipo.nota), color = if (item.executada) Paleta.alta else Paleta.tintaSuave)
        }
        AnelDoPreenchimento(item.fracao, 44.dp)
    }
}

@Composable
private fun LogoDaOrdem(ativo: AtivoDaTroca?, rede: String?, redeCoingecko: String?) {
    LogoDaMoeda(ativo?.coingecko, ativo?.simbolo ?: "?", 36.dp, rede = rede, redeCoingecko = redeCoingecko, naoConferido = ativo?.conferido != true)
}

/** A folha da ordem: o que ela vende e recebe, o preco, o andamento, quando foi criada e quando vence, onde esta, mudar e cancelar. */
@Composable
private fun FolhaDaOrdem(ordem: LinhaDaOrdem, podeAssinar: Boolean, aoFechar: () -> Unit, aoEditar: () -> Unit, aoCancelar: () -> Unit) {
    Folha(t("Ordem limite"), aoFechar) { fechar ->
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                LogoDaOrdem(ordem.vende, ordem.rede, ordem.redeCoingecko)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(ordem.tituloCurto, style = estilo(Tipo.linha), color = Paleta.tinta)
                    Text(ordem.porNoMinimo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                }
                ordem.fracao?.let { AnelDoPreenchimento(it, 44.dp) }
            }
            Column(Modifier.padding(top = Espaco.md).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.trilho)
                       .padding(horizontal = Espaco.md, vertical = Espaco.xs)) {
                ordem.precoCurto?.let { LinhaDoDetalhe(t("Preço"), it) }
                if (ordem.recebido != null) {
                    LinhaDoDetalhe(t("Já recebido"), ordem.recebido)
                    ordem.falta?.let { LinhaDoDetalhe(t("Falta vender"), it) }
                }
                ordem.criada?.let {
                    LinhaDoDetalhe(t("Criada em"), DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, Formato.locale).format(Date(it)))
                }
                LinhaDoDetalhe(t("Vence"), vencimento(ordem.vence))
                LinhaDoDetalhe(t("Rede"), ordem.redeNome)
                LinhaDoDetalhe(t("Onde"), ordem.onde)
            }
            Text(
                when {
                    !podeAssinar -> t("Esta carteira só acompanha: para mudar ou cancelar, abra a carteira que assina.")
                    ordem.podeCancelar -> t("Uma ordem assinada não muda. Editar abre esta ordem com os valores dela; na revisão, ela é cancelada e a nova é criada, nesta ordem.")
                    else -> ordem.explicacao
                },
                style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.sm),
            )
            if (ordem.podeCancelar) {
                BotaoSecundario(t("Editar a ordem"), Modifier.padding(top = Espaco.md)) { fechar(aoEditar) }
                BotaoTerciario(t("Cancelar a ordem"), Modifier.fillMaxWidth(), cor = Paleta.baixa) { fechar(aoCancelar) }
            }
        }
    }
}

@Composable
private fun LinhaDoDetalhe(rotulo: String, valor: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Text(rotulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        Spacer(Modifier.weight(1f))
        Text(valor, style = estilo(Tipo.nota), color = Paleta.tinta, textAlign = TextAlign.End)
    }
}

/** O anel do quanto ja foi preenchido, com o percentual no meio. */
@Composable
fun AnelDoPreenchimento(fracao: Double, tamanho: Dp) {
    Box(Modifier.size(tamanho), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(tamanho)) {
            val traco = 3.dp.toPx()
            drawCircle(Paleta.trilho, style = Stroke(traco), radius = size.minDimension / 2 - traco / 2)
            drawArc(if (fracao >= 1) Paleta.alta else Paleta.tinta, -90f, (360 * fracao.coerceIn(0.0, 1.0)).toFloat(), false,
                    topLeft = Offset(traco / 2, traco / 2), size = Size(size.width - traco, size.height - traco), style = Stroke(traco, cap = StrokeCap.Round))
        }
        Text(percentual(fracao), color = Paleta.tinta, fontSize = maxOf(10f, tamanho.value * 0.26f).sp, fontWeight = FontWeight.SemiBold)
    }
}

/** "37%": para baixo, nunca 0% com algo preenchido nem 100% sem estar inteira. */
fun percentual(fracao: Double): String = when {
    fracao <= 0 -> "0%"
    fracao >= 1 -> "100%"
    else -> (fracao * 100).toInt().let { if (it == 0) "<1%" else "${minOf(it, 99)}%" }
}

/**
 * "Vence em 6 d 23 h": o tempo que falta de verdade, nas duas maiores unidades, contando a cada
 * segundo. Sem prazo, "Até cancelar".
 */
@Composable
fun vencimento(vence: Long?): String {
    var agora by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(vence) {
        while (vence != null) {
            delay(1_000)
            agora = System.currentTimeMillis()
        }
    }
    if (vence == null) return t("Até cancelar")
    val resta = (vence - agora) / 1000
    if (resta < 1) return t("Vencendo agora")
    val (grande, pequena) = when {
        resta >= 86_400 -> Measure(resta / 86_400, MeasureUnit.DAY) to Measure(resta % 86_400 / 3_600, MeasureUnit.HOUR)
        resta >= 3_600 -> Measure(resta / 3_600, MeasureUnit.HOUR) to Measure(resta % 3_600 / 60, MeasureUnit.MINUTE)
        else -> Measure(resta / 60, MeasureUnit.MINUTE) to Measure(resta % 60, MeasureUnit.SECOND)
    }
    val formato = MeasureFormat.getInstance(Formato.locale, MeasureFormat.FormatWidth.NARROW)
    val partes = listOf(grande, pequena).filter { it.number.toLong() > 0 }
    return t("Vence em %@", formato.formatMeasures(*partes.ifEmpty { listOf(pequena) }.toTypedArray()))
}

/**
 * A pergunta de refazer uma ordem limite vencida, por cima de qualquer aba, quando o app abre
 * destravado. Refazer abre a ordem pronta e a revisao de sempre; nada e assinado sem o dono.
 */
@Composable
fun PerguntaDasVencidas() {
    val escopo = rememberCoroutineScope()
    var pergunta by remember { mutableStateOf<JSONObject?>(null) }
    var continuar by remember { mutableStateOf(true) }
    var decidiu by remember { mutableStateOf(false) }
    LaunchedEffect(App.estado.carteira?.id, Ciclo.vinda) {
        // Depois da carteira aparecer: a folha por cima da tela que ainda carrega assustava.
        delay(900)
        pergunta = runCatching { Api.objeto("ordens.vencidas").optJSONObject("pergunta") }.getOrNull()
    }
    val p = pergunta ?: return
    val id = p.getString("id")
    fun seguir(metodo: String) {
        escopo.launch { pergunta = runCatching { Api.objeto(metodo, JSONObject().put("ordem", id)).optJSONObject("pergunta") }.getOrNull() }
    }
    Folha(t("Uma ordem limite venceu"), aoFechar = {
        // O X e o deslizar: pergunta de novo so na proxima abertura.
        if (decidiu) decidiu = false else seguir("ordens.adiar")
    }) { fechar ->
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md)) {
            val vende = p.optJSONObject("vende")?.let(::AtivoDaTroca)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                LogoDaOrdem(vende, vende?.rede, vende?.redeCoingecko)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(p.optString("titulo"), style = estilo(Tipo.linha), color = Paleta.tinta)
                    Text(p.optString("minimo"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                }
            }
            Text(p.optString("texto"), style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.md))
            p.opcional("parcial")?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm)) }
            p.opcional("abaixoDoMercado")?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.cautela, modifier = Modifier.padding(top = Espaco.sm)) }
            Row(Modifier.padding(top = Espaco.lg).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(t("Perguntar de novo quando vencer"), style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.weight(1f))
                Interruptor(continuar, { continuar = it }, cor = Paleta.acento)
            }
            Text(t("Refazer pede a sua biometria ou o PIN: sem você, ninguém assina uma ordem nova com a sua chave."), style = estilo(Tipo.nota),
                 color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.xs))
            BotaoPrimario(t("Refazer a ordem"), Modifier.padding(top = Espaco.lg)) {
                decidiu = true
                val manter = continuar
                fechar {
                    pergunta = null
                    Navegacao.cobrir { TelaDeRefazerOrdem(id, manter) }
                }
            }
            BotaoTerciario(t("Não refazer"), Modifier.fillMaxWidth()) {
                decidiu = true
                fechar { seguir("ordens.naoRefazer") }
            }
            p.opcional("mais")?.let {
                Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            }
        }
    }
}
