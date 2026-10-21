package app.escalibur.wallet.ui.atividade

import androidx.compose.ui.graphics.Color
import app.escalibur.wallet.ui.comp.TelaComBarra
import app.escalibur.wallet.ui.comp.moedaGirando
import app.escalibur.wallet.ui.carteira.TipoDeSelo
import app.escalibur.wallet.ui.comp.PuxarParaAtualizar
import app.escalibur.wallet.ui.comp.LocalEspacoDaBarra
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.width
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.zIndex
import app.escalibur.wallet.ui.carteira.Redes
import app.escalibur.wallet.ui.comp.Girando
import app.escalibur.wallet.ui.comp.movimentoReduzido
import app.escalibur.wallet.ui.comp.relogio
import app.escalibur.wallet.ui.comp.saltoDeSaida
import kotlin.math.PI
import kotlin.math.sin
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.Eventos
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.Textos
import app.escalibur.wallet.ui.carteira.Saldos
import app.escalibur.wallet.ui.carteira.SeloDeToken
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.EnderecoEmBlocos
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.comp.TituloDeAba
import app.escalibur.wallet.ui.comp.Transferencia
import app.escalibur.wallet.ui.data
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.receber.FluxoDeReceber
import app.escalibur.wallet.ui.receber.opcional
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.textos
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.Calendar
import java.util.Date

/** Uma movimentacao, como o nucleo devolve (Atividade.Item). */
class Movimento(j: JSONObject) {
    val id: String = j.getString("id")
    val rede: String = j.getString("rede")
    val redeNome: String = j.getString("redeNome")
    val redeCoingecko: String = j.getString("redeCoingecko")
    val direcao: String = j.getString("direcao")
    val simbolo: String = j.getString("simbolo")
    val coingecko: String? = j.opcional("coingecko")
    val casas: Int = j.getInt("casas")
    val custom: Boolean = j.getBoolean("custom")
    val quantidade: String = j.getString("quantidade")
    val contraparte: String? = j.opcional("contraparte")
    val data: Date = j.data("data") ?: Date()
    val situacao: String = j.getString("situacao")
    val nota: String? = j.opcional("nota")
    val taxa: String? = j.opcional("taxa")
    val simboloNativo: String = j.getString("simboloNativo")
    val casasNativas: Int = j.getInt("casasNativas")
    val hash: String = j.getString("hash")
    val recebidoSimbolo: String? = j.opcional("recebidoSimbolo")
    val recebidoCoingecko: String? = j.opcional("recebidoCoingecko")
    val recebidoCasas: Int? = if (j.has("recebidoCasas")) j.getInt("recebidoCasas") else null
    val recebidoQuantidade: String? = j.opcional("recebidoQuantidade")
    val explorador: String = j.getString("explorador")
    val urlDoExplorador: String? = j.opcional("urlDoExplorador")
    val conferivel: Boolean = j.optBoolean("conferivel")

    val falhou: Boolean get() = situacao == "falhou"
    val zero: Boolean get() = quantidade.trimStart('0').isEmpty()
    /** Aprovacao e afins: nenhum valor saiu, so a taxa. */
    val soTaxa: String? get() = if (zero && direcao != "swap" && direcao != "received" && taxa != null && taxa.trimStart('0').isNotEmpty()) taxa else null
    val sinal: String get() = if (zero || falhou) "" else if (direcao == "received") "+" else if (direcao == "sent") Formato.menos else ""
}

private class RetratoDaAtividade(j: JSONObject) {
    val carregando = j.optBoolean("carregando")
    val lidaUmaVez = j.optBoolean("lidaUmaVez")
    val falhas = j.optJSONArray("falhas").textos()
    val semHistorico = j.optJSONArray("semHistorico").objetos()
    val suspeitas = j.optInt("suspeitas")
    val itens = j.optJSONArray("itens").objetos().map(::Movimento)
    val redes = j.optInt("redes")
    val restantes = j.optInt("restantes")
}

/** "Stellar", "Stellar e Dogecoin", "Stellar, Dogecoin e mais 2 redes". */
private fun nomes(lista: List<String>): String = when (lista.size) {
    0 -> ""
    1 -> lista[0]
    2, 3 -> android.icu.text.ListFormatter.getInstance(Textos.locale).format(lista)
    else -> t("%@, %@ e mais %lld redes", lista[0], lista[1], lista.size - 2)
}

/** H1: Atividade. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TelaDeAtividade() {
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    val estado = App.estado
    val oculto = estado.ocultarSaldos
    var retrato by remember { mutableStateOf<RetratoDaAtividade?>(null) }
    var visiveis by remember(estado.selecionada) { mutableIntStateOf(20) }
    var puxando by remember { mutableStateOf(false) }

    fun atualizar(forcar: Boolean) {
        escopo.launch {
            runCatching { retrato = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { RetratoDaAtividade(Api.objeto("atividade.atualizar", JSONObject().put("forcar", forcar))) } }
        }
    }
    LaunchedEffect(estado.selecionada) {
        runCatching { retrato = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { RetratoDaAtividade(Api.objeto("atividade.mostrar")) } }
        atualizar(false)
    }
    LaunchedEffect(Unit) {
        // Lido fora da linha principal, e so o mais novo (como o retrato dos saldos).
        Eventos.eventos.filter { it.nome == "atividade" }
            .map { evento -> runCatching { RetratoDaAtividade(JSONObject(evento.json)) }.getOrNull() }
            .flowOn(kotlinx.coroutines.Dispatchers.Default)
            .conflate()
            .collect { novo -> if (novo != null) retrato = novo }
    }

    val r = retrato
    val pendentes = r?.itens?.filter { it.situacao == "pendente" }.orEmpty()
    val feitos = r?.itens?.filter { it.situacao != "pendente" }.orEmpty()
    val carregandoPrimeiraVez = r == null || (r.itens.isEmpty() && (r.carregando || !r.lidaUmaVez))
    val alturaDaTela = LocalConfiguration.current.screenHeightDp.dp

    PuxarParaAtualizar(
        atualizando = puxando,
        aoAtualizar = {
            puxando = true
            escopo.launch {
                try { runCatching { retrato = RetratoDaAtividade(Api.objeto("atividade.atualizar", JSONObject().put("forcar", true))) } } finally { puxando = false }
            }
        },
        modifier = Modifier.fillMaxSize().background(Paleta.vazio),
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(bottom = Espaco.xl + LocalEspacoDaBarra.current)) {
            TituloDeAba(t("Atividade"))
            if (r != null && r.falhas.isNotEmpty()) {
                AvisoDeAtualizacao(nomes(r.falhas), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm)) { atualizar(true) }
            }
            when {
                // Lendo pela primeira vez: o carregando no espaco livre, abaixo do que ja aparece.
                carregandoPrimeiraVez -> Box(Modifier.fillMaxWidth().heightIn(min = alturaDaTela * 0.55f), contentAlignment = Alignment.Center) {
                    val ligadas = Redes.todas.filter { it.id !in App.estado.redesDesligadas }
                    CarregandoAtividade(ligadas.take(7).map { it.id to it.coingecko }, r?.redes ?: ligadas.size)
                }
                r != null && r.itens.isEmpty() -> Column(Modifier.fillMaxWidth().heightIn(min = alturaDaTela * 0.8f).padding(horizontal = Espaco.margem),
                                                         horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    ArteDaAtividadeVazia(230.dp)
                    Text(t("Sua atividade aparece aqui"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.md))
                    Text(t("Envios, recebimentos, trocas e ordens, cada um com o seu status."), style = estilo(Tipo.corpo), color = Paleta.tintaSuave,
                         textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm))
                    BotaoPrimario(t("Receber"), Modifier.padding(top = Espaco.lg)) { Navegacao.folha { FluxoDeReceber() } }
                }
                else -> {
                    if (pendentes.isNotEmpty()) Secao(t("Pendentes"), pendentes, oculto)
                    if (r != null && r.carregando && r.restantes > 0) {
                        Row(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                            Girando(Paleta.tintaSuave, 14.dp)
                            Text(if (r.restantes == 1) t("Lendo mais 1 rede") else t("Lendo mais %lld redes", r.restantes), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                        }
                    }
                    for ((titulo, itens) in porDia(feitos.take(visiveis))) Secao(titulo, itens, oculto)
                    if (feitos.size > visiveis) {
                        // Chegar ao fim da lista ja traz as proximas 20; o botao fica para quem navega pelo leitor de tela.
                        BotaoSecundario(t("Mostrar mais"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md)
                            .onGloballyPositioned { visiveis += 20 }) { visiveis += 20 }
                    }
                }
            }
            if (r != null && r.semHistorico.isNotEmpty() && !carregandoPrimeiraVez) {
                Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    Text(t("O histórico de %@ não aparece aqui: nenhum serviço gratuito publica o histórico dessas redes sem cadastro. O saldo aparece na Carteira, e o histórico completo, no explorador da rede.",
                           nomes(r.semHistorico.map { it.getString("nome") })), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                    for (rede in r.semHistorico) {
                        val url = rede.opcional("url") ?: continue
                        Row(
                            Modifier.height(36.dp).clip(CircleShape).background(Paleta.trilho)
                                .clickable { runCatching { contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } }.padding(horizontal = Espaco.sm),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs),
                        ) {
                            SeloDaRede(rede.getString("rede"), rede.getString("coingecko"), 20.dp, Paleta.trilho)
                            Text(t("Ver o histórico no %@", rede.getString("explorador")), style = estilo(Tipo.rotulo), color = Paleta.tinta)
                            Icone(Icones.setaDiagonal, Paleta.tintaSuave, tamanho = 11.dp)
                        }
                    }
                }
            }
            if (r != null && r.suspeitas > 0) {
                Text(
                    if (r.suspeitas == 1) t("1 recebimento suspeito escondido. São envios de valor zero ou de tokens fora da lista, muitas vezes de endereços parecidos com os seus.")
                    else t("%lld recebimentos suspeitos escondidos. São envios de valor zero ou de tokens fora da lista, muitas vezes de endereços parecidos com os seus.", r.suspeitas),
                    style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg),
                )
            }
        }
    }
}

/**
 * Rede que nao respondeu agora: uma linha, sem cartao (o `RefreshNotice` do iOS). O que estava
 * guardado dela continua na lista.
 */
@Composable
private fun AvisoDeAtualizacao(redes: String, modifier: Modifier = Modifier, tentar: () -> Unit) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Icone(Icones.atualizar, Paleta.tintaApagada, tamanho = 13.dp, modifier = Modifier.padding(top = 2.dp))
        Text(t("%@ não atualizou agora. Mostrando o que já estava salvo.", redes), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
             modifier = Modifier.weight(1f))
        Text(t("Tentar de novo"), style = estilo(Tipo.nota).copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = Paleta.tinta,
             modifier = Modifier.padding(start = Espaco.xs).clickable(onClick = tentar))
    }
}

/**
 * Enquanto o historico chega: as redes da carteira acendendo uma de cada vez, no meio da tela. Com
 * o movimento reduzido, parado.
 */
@Composable
private fun CarregandoAtividade(redes: List<Pair<String, String>>, total: Int, modifier: Modifier = Modifier) {
    val tempo by relogio()
    Column(modifier.fillMaxWidth().padding(horizontal = Espaco.margem), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(horizontalArrangement = Arrangement.spacedBy((-8).dp)) {
            redes.forEachIndexed { indice, (rede, coingecko) ->
                val fase = tempo / 1.6f - indice / maxOf(redes.size, 1).toFloat()
                val onda = (sin(fase * 2 * PI.toFloat()) + 1) / 2
                SeloDaRede(rede, coingecko, 36.dp, Paleta.vazio, Modifier.zIndex(onda).graphicsLayer {
                    val escala = 0.9f + 0.12f * onda
                    scaleX = escala
                    scaleY = escala
                    alpha = 0.45f + 0.55f * onda
                })
            }
        }
        Text(t("Lendo o histórico"), style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.md))
        Text(if (total > 1) t("%lld redes, cada uma direto dos provedores públicos.", total) else t("Direto dos provedores públicos da rede."),
             style = estilo(Tipo.nota), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xxs))
    }
}

/**
 * Atividade vazia: tres cartoes de atividade entram um a um (receber, enviar, trocar, cada um com a
 * sua rede), com o status girando como pendente ate virar o visto verde de confirmado. E o que a tela
 * vai mostrar quando houver movimento. Ciclo de 6 s; com o movimento reduzido, os tres aparecem
 * confirmados e parados.
 */
@Composable
private fun ArteDaAtividadeVazia(altura: Dp) {
    val parado = movimentoReduzido()
    val agora by relogio(parado)
    val t = if (parado) 4.5f else agora % 6f
    val some = if (parado) 1f else 1f - ((t - 5.3f) / 0.6f).coerceIn(0f, 1f)
    val itens = listOf(Triple(Icones.receber, "bitcoin" to "bitcoin", 0.62f), Triple(Icones.enviar, "ethereum" to "ethereum", 0.48f),
                       Triple(Icones.trocar, "solana" to "solana", 0.7f))
    Box(Modifier.fillMaxWidth().height(altura), contentAlignment = Alignment.Center) {
        Column(Modifier.width(290.dp), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            itens.forEachIndexed { indice, (icone, rede, largura) ->
                val aparece = ((t - (0.3f + indice * 0.45f)) / 0.4f).coerceIn(0f, 1f) * some
                val confirmado = ((t - (2.0f + indice * 0.55f)) / 0.3f).coerceIn(0f, 1f)
                Row(
                    Modifier.fillMaxWidth().height(62.dp)
                        .graphicsLayer { alpha = aparece; translationY = (1 - aparece) * 16.dp.toPx() }
                        .clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(horizontal = Espaco.sm),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    Box(Modifier.size(43.dp)) {
                        Box(Modifier.size(40.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) { Icone(icone, Paleta.tinta, tamanho = 17.dp) }
                        SeloDaRede(rede.first, rede.second, 16.dp, Paleta.corpo, Modifier.align(Alignment.BottomEnd))
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        Box(Modifier.width(150.dp * largura).height(9.dp).clip(CircleShape).background(Paleta.bordaForte))
                        Box(Modifier.width(90.dp * largura).height(7.dp).clip(CircleShape).background(Paleta.controle))
                    }
                    Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                        Canvas(Modifier.size(18.dp).graphicsLayer { alpha = 1 - confirmado; rotationZ = if (parado) 0f else agora * 360f }) {
                            drawArc(Paleta.tintaApagada, -90f, 252f, false, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round))
                        }
                        Box(Modifier.size(22.dp).graphicsLayer { val e = saltoDeSaida(confirmado); scaleX = e; scaleY = e }
                            .clip(CircleShape).background(Paleta.sucesso), contentAlignment = Alignment.Center) {
                            Icone(Icones.visto, Paleta.vazio, tamanho = 11.dp)
                        }
                    }
                }
            }
        }
    }
}

/** Hoje, Ontem, ou o dia e o mes. */
private fun porDia(itens: List<Movimento>): List<Pair<String, List<Movimento>>> {
    val hoje = Calendar.getInstance()
    val ontem = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -1) }
    fun mesmo(a: Calendar, b: Date) = Calendar.getInstance().apply { time = b }.let { it.get(Calendar.YEAR) == a.get(Calendar.YEAR) && it.get(Calendar.DAY_OF_YEAR) == a.get(Calendar.DAY_OF_YEAR) }
    val formato = java.text.SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(Formato.locale, "dMMMM"), Formato.locale)
    val grupos = LinkedHashMap<String, MutableList<Movimento>>()
    for (item in itens) {
        val titulo = when {
            mesmo(hoje, item.data) -> t("Hoje")
            mesmo(ontem, item.data) -> t("Ontem")
            else -> formato.format(item.data)
        }
        grupos.getOrPut(titulo) { mutableListOf() }.add(item)
    }
    return grupos.map { it.key to it.value }
}

@Composable
private fun Secao(titulo: String, itens: List<Movimento>, oculto: Boolean) {
    Column {
        Text(titulo, style = estilo(Tipo.cabecalho), color = Paleta.tinta,
             modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg, bottom = Espaco.xs))
        for (item in itens) LinhaDaAtividade(item, oculto) { Navegacao.abrir { DetalheDaAtividade(item) } }
    }
}

private fun tituloDaLinha(m: Movimento): String = when (m.direcao) {
    "sent" -> t("Enviado · %@", m.simbolo)
    "received" -> t("Recebido · %@", m.simbolo)
    "swap" -> m.recebidoSimbolo?.let { t("Troca · %@ por %@", m.simbolo, it) } ?: t("Troca · %@", m.simbolo)
    "approval" -> t("Autorização · %@", m.simbolo)
    "order" -> t("Ordem · %@", m.simbolo)
    else -> m.redeNome
}

private const val OCULTO = "•••"

@Composable
fun LinhaDaAtividade(m: Movimento, oculto: Boolean, aoTocar: () -> Unit) {
    val hora = Formato.relogio(m.data)
    val subtitulo = when (m.situacao) {
        "pendente" -> m.nota ?: t("Aguardando confirmação")
        "falhou" -> t("Falhou")
        else -> when {
            m.direcao == "swap" && m.recebidoSimbolo != null && !oculto -> "${Formato.menos}${Formato.cripto(m.quantidade, m.casas, m.simbolo)} · $hora"
            m.contraparte != null -> (if (m.direcao == "received") t("De") else t("Para")) + " " + Formato.endereco(m.contraparte) + " · " + hora
            else -> hora
        }
    }
    Row(
        Modifier.fillMaxWidth().heightIn(min = Altura.linha).clickable(onClick = aoTocar).padding(horizontal = Espaco.margem),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        LogoDaMoeda(m.coingecko, m.simbolo, 40.dp, rede = m.rede, redeCoingecko = m.redeCoingecko, naoConferido = m.custom)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(tituloDaLinha(m), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
            Text(subtitulo, style = estilo(Tipo.nota), color = if (m.falhou) Paleta.baixa else Paleta.tintaSuave, maxLines = 1)
        }
        val (valor, cor) = when {
            m.direcao == "swap" && m.recebidoQuantidade != null && m.recebidoSimbolo != null ->
                (if (oculto) OCULTO else (if (m.falhou) "" else "+") + Formato.cripto(m.recebidoQuantidade, m.recebidoCasas ?: 0, m.recebidoSimbolo)) to
                    (if (m.falhou) Paleta.tintaApagada else Paleta.alta)
            m.soTaxa != null -> (if (oculto) OCULTO else Formato.menos + Formato.cripto(m.soTaxa!!, m.casasNativas, m.simboloNativo)) to Paleta.tinta
            !m.zero -> (if (oculto) OCULTO else m.sinal + Formato.cripto(m.quantidade, m.casas, m.simbolo)) to
                (if (m.falhou) Paleta.tintaApagada else if (m.direcao == "received") Paleta.alta else Paleta.tinta)
            else -> "" to Paleta.tinta
        }
        if (valor.isNotEmpty()) {
            Text(valor, style = estilo(Tipo.linha), color = cor, maxLines = 1,
                 textDecoration = if (m.falhou && !oculto) TextDecoration.LineThrough else null)
        }
    }
}

/** O detalhe de uma movimentacao: o que se moveu, a situacao, a rede, a data, a taxa e o identificador. */
@Composable
fun DetalheDaAtividade(m: Movimento) {
    val contexto = LocalContext.current
    var conferencia by remember { mutableStateOf<JSONObject?>(null) }
    LaunchedEffect(m.id) {
        if (m.conferivel) conferencia = runCatching { Api.objeto("atividade.conferir", JSONObject().put("id", m.id)) }.getOrNull() ?: JSONObject().put("resultado", "falhou")
    }
    val tipo = when (m.direcao) {
        "sent" -> t("Enviado")
        "received" -> t("Recebido")
        "swap" -> t("Troca")
        "approval" -> t("Autorização")
        "order" -> t("Ordem")
        else -> t("Transação")
    }
    val suspeito = m.custom && m.direcao == "received"
    val linha = Saldos.retrato.todasAsLinhas.firstOrNull { it.coingecko != null && it.coingecko == m.coingecko }
    val preco = if (m.custom || m.zero || m.falhou) null else linha?.preco
    TelaComBarra(aoVoltar = { Navegacao.fechar() }) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(horizontal = Espaco.margem).padding(top = Espaco.sm, bottom = Espaco.xl),
               verticalArrangement = Arrangement.spacedBy(Espaco.lg)) {
            // O que se moveu: o logo grande (na troca, o que saiu e o que entrou), o tipo, o valor e a situacao.
            Column(Modifier.fillMaxWidth().padding(top = Espaco.sm), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                if (m.direcao == "swap" && m.recebidoSimbolo != null) {
                    Row(Modifier.padding(bottom = Espaco.xs), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                        LogoDaMoeda(m.coingecko, m.simbolo, 56.dp, Modifier.moedaGirando(), rede = m.rede, redeCoingecko = m.redeCoingecko, anel = Paleta.corpo, naoConferido = m.custom)
                        Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 15.dp)
                        LogoDaMoeda(m.recebidoCoingecko, m.recebidoSimbolo, 56.dp, Modifier.moedaGirando(250), rede = m.rede, redeCoingecko = m.redeCoingecko, anel = Paleta.corpo)
                    }
                } else {
                    Box(Modifier.padding(bottom = Espaco.xxs).size(96.dp).clip(CircleShape).background(Paleta.corpo), contentAlignment = Alignment.Center) {
                        LogoDaMoeda(m.coingecko, m.simbolo, 72.dp, Modifier.moedaGirando(), rede = m.rede, redeCoingecko = m.redeCoingecko, anel = Paleta.corpo, naoConferido = m.custom)
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Text(tipo, style = estilo(Tipo.linha), color = Paleta.tintaSuave)
                    if (suspeito) SeloDeToken(TipoDeSelo.suspeito)
                }
                when {
                    m.direcao == "swap" && m.recebidoQuantidade != null && m.recebidoSimbolo != null -> {
                        Text("+" + Formato.cripto(m.recebidoQuantidade, m.recebidoCasas ?: 0, m.recebidoSimbolo, Formato.EstiloCripto.cheio),
                             style = estilo(Tipo.numero), color = if (m.falhou) Paleta.tintaApagada else Paleta.alta, maxLines = 1,
                             textDecoration = if (m.falhou) TextDecoration.LineThrough else null)
                        Text(t("por %@", Formato.cripto(m.quantidade, m.casas, m.simbolo, Formato.EstiloCripto.cheio)), style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                    }
                    m.soTaxa != null -> {
                        Text(Formato.menos + Formato.cripto(m.soTaxa!!, m.casasNativas, m.simboloNativo, Formato.EstiloCripto.cheio), style = estilo(Tipo.numero), color = Paleta.tinta, maxLines = 1)
                        Text(t("Só a taxa da rede: nenhum valor saiu da conta"), style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                    }
                    else -> {
                        Text(m.sinal + Formato.cripto(m.quantidade, m.casas, m.simbolo, Formato.EstiloCripto.cheio), style = estilo(Tipo.numero), maxLines = 1,
                             color = if (m.falhou) Paleta.tintaApagada else if (m.direcao == "received") Paleta.alta else Paleta.tinta,
                             textDecoration = if (m.falhou) TextDecoration.LineThrough else null)
                        preco?.let {
                            Text(t("≈ %@ hoje", Formato.valor(Formato.numero(m.quantidade, m.casas) * it, App.estado.moeda)), style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                        }
                    }
                }
                Situacao(m, conferencia, Modifier.padding(top = Espaco.xs))
            }
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(horizontal = Espaco.base, vertical = Espaco.xs)) {
                if (m.direcao != "swap") Fato(t("Moeda")) {
                    LogoDaMoeda(m.coingecko, m.simbolo, 22.dp, anel = Paleta.corpo, naoConferido = m.custom)
                    Text(linha?.nome ?: m.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                }
                Fato(t("Rede")) {
                    SeloDaRede(m.rede, m.redeCoingecko, 22.dp, Color.Transparent)
                    Text(m.redeNome, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                }
                Fato(t("Data")) {
                    val formato = java.text.SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(Formato.locale, "dMMMyyyyjjmm"), Formato.locale)
                    Text(formato.format(m.data), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                }
                m.taxa?.let { taxa ->
                    Fato(t("Taxa da rede")) { Text(Formato.cripto(taxa, m.casasNativas, m.simboloNativo, Formato.EstiloCripto.cheio), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1) }
                }
            }
            // Sem copiar: o endereco de quem mandou pode ser isca.
            m.contraparte?.let { contraparte ->
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(Espaco.base),
                       verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Text(if (m.direcao == "received") t("De") else t("Para"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    EnderecoEmBlocos(contraparte)
                }
            }
            // O identificador da transacao, para copiar ou abrir no explorador da rede.
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(horizontal = Espaco.base).padding(bottom = Espaco.xxs)) {
                Text(t("Identificador"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.base))
                Text(m.hash, style = estilo(Tipo.monoPequeno), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.xxs, bottom = Espaco.xs))
                Acao(t("Copiar"), Icones.copiar) {
                    Transferencia.copiar(contexto, m.hash)
                    Avisos.mostrar(t("Identificador copiado."))
                }
                m.urlDoExplorador?.let { url ->
                    Acao(t("Ver no %@", m.explorador), Icones.setaDiagonal) { runCatching { contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } }
                }
            }
        }
    }
}

/**
 * A situacao no detalhe: a capsula com o ponto da cor do estado e o texto claro (a do Android, que o
 * dono preferiu a do iOS, 21/10/2026).
 */
@Composable
private fun Situacao(m: Movimento, conferencia: JSONObject?, modifier: Modifier = Modifier) {
    val (texto, cor) = if (m.conferivel) {
        // O indexador e um so: "Conferida" so depois de dois nos da rede mostrarem o valor chegando.
        when (conferencia?.optString("resultado")) {
            "conferida" -> {
                val confirmacoes = conferencia.optLong("confirmacoes", 0)
                (if (confirmacoes > 1) t("Conferida na rede, %@ confirmações", Formato.agrupado(confirmacoes.toDouble(), 0)) else t("Conferida na rede")) to Paleta.tintaSuave
            }
            "naoEncontrada" -> t("Segundo o indexador. A rede ainda não mostra esta transação") to Paleta.cautela
            "naoConfere" -> t("A rede não confirma este recebimento") to Paleta.baixa
            "interna" -> t("Segundo o indexador. Chegou por transação interna, que o recibo não mostra") to Paleta.cautela
            "falhou" -> t("Segundo o indexador. Não deu para conferir na rede agora") to Paleta.cautela
            else -> t("Segundo o indexador. Conferindo na rede") to Paleta.cautela
        }
    } else when (m.situacao) {
        "pendente" -> (m.nota ?: t("Pendente")) to Paleta.cautela
        "falhou" -> (m.nota ?: t("Falhou")) to Paleta.baixa
        else -> t("Confirmada") to Paleta.alta
    }
    Row(modifier.clip(CircleShape).background(Paleta.corpo).padding(horizontal = Espaco.sm, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(cor))
        Text(texto, style = estilo(Tipo.nota), color = Paleta.tinta, textAlign = TextAlign.Center)
    }
}

@Composable
private fun Fato(rotulo: String, valor: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Text(rotulo, style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
        Spacer(Modifier.weight(1f))
        valor()
    }
}

@Composable
private fun Acao(titulo: String, icone: androidx.compose.ui.graphics.vector.ImageVector, acao: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).clickable(onClick = acao), verticalAlignment = Alignment.CenterVertically) {
        Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.weight(1f))
        Icone(icone, Paleta.tintaSuave, tamanho = 14.dp)
    }
}
