package app.escalibur.wallet.ui.mercado

import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.draw.alpha
import app.escalibur.wallet.ui.comp.GraficoCarregando
import app.escalibur.wallet.ui.comp.PuxarParaAtualizar
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import app.escalibur.wallet.ui.comp.TelaComBarra
import kotlin.math.abs
import app.escalibur.wallet.ui.comp.LocalEspacoDaBarra
import app.escalibur.wallet.ui.avisos.SinoDoAlerta
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Chip
import app.escalibur.wallet.ui.comp.Esqueleto
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.PilulaDeVariacao
import app.escalibur.wallet.ui.comp.SecaoDoGrafico
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.comp.TituloDeAba
import app.escalibur.wallet.ui.data
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.receber.opcional
import app.escalibur.wallet.ui.trocar.ControleDaTroca
import app.escalibur.wallet.ui.principal.Aba
import app.escalibur.wallet.ui.receber.CampoDeBusca
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.textos
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.Date

class MoedaDeMercado(j: JSONObject) {
    val id: String = j.getString("id")
    val simbolo: String = j.getString("simbolo").uppercase()
    val nome: String = j.getString("nome")
    val preco: Double = j.getDouble("preco")
    val variacao: Double? = if (j.has("variacao24h") && !j.isNull("variacao24h")) j.getDouble("variacao24h") else null
    val capitalizacao: Double? = if (j.has("capitalizacao")) j.optDouble("capitalizacao") else null
    val volume: Double? = if (j.has("volume")) j.optDouble("volume") else null
    val posicao: Int? = if (j.has("posicao")) j.optInt("posicao") else null
}

private enum class Ordem { relevancia, alta, queda, preco;
    val titulo: String get() = when (this) {
        relevancia -> t("Relevância")
        alta -> t("Maior alta")
        queda -> t("Maior queda")
        preco -> t("Maior preço")
    }
    fun ordenar(lista: List<MoedaDeMercado>): List<MoedaDeMercado> = when (this) {
        relevancia -> lista
        alta -> lista.sortedByDescending { it.variacao ?: Double.NEGATIVE_INFINITY }
        queda -> lista.sortedBy { it.variacao ?: Double.POSITIVE_INFINITY }
        preco -> lista.sortedByDescending { it.preco }
    }
}

/** Mercado: as maiores moedas por capitalizacao. So dado publico, igual para todo mundo. */
@Composable
fun TelaDoMercado() {
    val escopo = rememberCoroutineScope()
    val dono = LocalLifecycleOwner.current
    val moeda = App.estado.moeda
    var moedas by remember { mutableStateOf<List<MoedaDeMercado>>(emptyList()) }
    var favoritas by remember { mutableStateOf<List<String>>(emptyList()) }
    var busca by remember { mutableStateOf("") }
    var ordem by remember { mutableStateOf(Ordem.relevancia) }
    var carregando by remember { mutableStateOf(false) }
    var falhou by remember { mutableStateOf(false) }
    var velho by remember { mutableStateOf<Date?>(null) }
    var rodape by remember { mutableStateOf<String?>(null) }

    suspend fun carregar() {
        carregando = true
        val resposta = runCatching { Api.objeto("mercado.lista", JSONObject().put("moeda", moeda)) }.getOrNull()
        carregando = false
        if (resposta == null) { falhou = true; return }
        falhou = false
        moedas = resposta.optJSONArray("moedas").objetos().map(::MoedaDeMercado)
        favoritas = resposta.optJSONArray("favoritas").textos()
        Favoritas.ids = favoritas.toSet()
        val quando = resposta.data("atualizado")
        velho = if (resposta.optBoolean("velho")) quando else null
        rodape = quando?.let { t("Dados de mercado: %@, às %@", resposta.optString("fonte"), Formato.carimbo(it)) }
    }
    // Lista viva: atualiza a cada 30 s so enquanto a aba esta na tela e o app na frente.
    LaunchedEffect(moeda) {
        dono.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                carregar()
                delay(30_000)
            }
        }
    }

    val termo = busca.trim()
    val filtradas = if (termo.isEmpty()) moedas else moedas.filter { it.simbolo.contains(termo, true) || it.nome.contains(termo, true) }
    val marcadas = (favoritas.filter { it in Favoritas.ids } + (Favoritas.ids - favoritas.toSet())).mapNotNull { id -> filtradas.firstOrNull { it.id == id } }.let { if (ordem == Ordem.relevancia) it else ordem.ordenar(it) }
    val outras = ordem.ordenar(filtradas.filter { it.id !in Favoritas.ids })

    var puxando by remember { mutableStateOf(false) }
    PuxarParaAtualizar(puxando, { puxando = true; escopo.launch { try { carregar() } finally { puxando = false } } }, Modifier.fillMaxSize().background(Paleta.vazio)) {
    LazyColumn(Modifier.fillMaxSize().statusBarsPadding(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = LocalEspacoDaBarra.current + Espaco.xl)) {
        item { TituloDeAba(t("Mercado")) }
        item { CampoDeBusca(busca, t("Buscar moeda"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm)) { busca = it } }
        item {
            // Sem lista, nao ha o que ordenar: os filtros apagam e nao respondem.
            val apagado by animateFloatAsState(if (moedas.isEmpty()) 0.35f else 1f, tween(150), label = "filtros")
            Row(Modifier.padding(top = Espaco.sm).alpha(apagado).horizontalScroll(rememberScrollState()).padding(horizontal = Espaco.margem),
                horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                for (opcao in Ordem.entries) Chip(opcao.titulo, ordem == opcao) { if (moedas.isNotEmpty()) ordem = opcao }
            }
        }
        when {
            moedas.isEmpty() && (carregando || !falhou) -> items(8) {
                Row(Modifier.fillMaxWidth().heightIn(min = Altura.linha).padding(horizontal = Espaco.margem).padding(top = if (it == 0) Espaco.sm else 0.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    Box(Modifier.size(40.dp).clip(CircleShape).background(Paleta.corpo))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) { Esqueleto(48.dp); Esqueleto(88.dp) }
                    Esqueleto(72.dp, 16.dp)
                    Esqueleto(72.dp, 28.dp)
                }
            }
            moedas.isEmpty() && falhou -> item {
                // O Mercado sem nenhuma fonte de preco: a linha do grafico carregando, o que aconteceu,
                // de onde os precos vem e o tentar de novo. Centrado e sem cartao: e a tela inteira.
                Column(Modifier.fillMaxWidth().padding(horizontal = Espaco.margem).padding(top = 72.dp), horizontalAlignment = Alignment.CenterHorizontally,
                       verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    Box(Modifier.widthIn(max = 280.dp).fillMaxWidth().height(104.dp).padding(bottom = Espaco.sm)) { GraficoCarregando(folga = 10.dp) }
                    Text(t("Não foi possível carregar o mercado agora"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center)
                    Text(t("Os preços vêm do CoinGecko e, quando ele não responde, do CoinPaprika. Nenhum dos dois respondeu. Confira a internet e tente de novo."),
                         style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
                    BotaoSecundario(t("Tentar de novo"), Modifier.widthIn(max = 220.dp).padding(top = Espaco.md)) { escopo.launch { carregar() } }
                }
            }
            else -> {
                velho?.let { quando ->
                    item {
                        Faixa(TipoDeFaixa.neutra, t("Sem conexão com os dados de mercado agora."), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md),
                              mensagem = t("Mostrando os preços de %@.", Formato.carimbo(quando)), tituloDaAcao = t("Tentar de novo")) { escopo.launch { carregar() } }
                    }
                }
                item { Spacer(Modifier.height(Espaco.sm)) }
                if (marcadas.isNotEmpty()) {
                    item { TituloDeSecao(t("Favoritas")) }
                    items(marcadas, key = { "f" + it.id }) { LinhaDoMercado(it, moeda, Modifier.animateItem()) { abrir(it) } }
                    item { TituloDeSecao(t("Todas")) }
                }
                items(outras, key = { it.id }) { LinhaDoMercado(it, moeda, Modifier.animateItem()) { abrir(it) } }
                rodape?.let { item { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada, textAlign = TextAlign.Center,
                                          modifier = Modifier.fillMaxWidth().padding(top = Espaco.lg)) } }
            }
        }
    }
    }
}

private fun abrir(moeda: MoedaDeMercado) { Navegacao.abrir { DetalheDaMoeda(moeda) } }

@Composable
private fun TituloDeSecao(texto: String) {
    Text(texto, style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md, bottom = Espaco.xxs))
}

@Composable
private fun LinhaDoMercado(m: MoedaDeMercado, moeda: String, modifier: Modifier = Modifier, aoTocar: () -> Unit) {
    Row(
        modifier.fillMaxWidth().heightIn(min = Altura.linha).clickable(onClick = aoTocar).padding(horizontal = Espaco.margem),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        LogoDaMoeda(m.id, m.simbolo, 40.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(m.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
            Text(m.nome, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
        }
        Text(Formato.preco(m.preco, moeda), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, textAlign = TextAlign.End, modifier = Modifier.width(120.dp))
        PilulaDeVariacao(m.variacao)
    }
}

/** As moedas fixadas no topo do Mercado, as mesmas em toda tela. */
object Favoritas {
    var ids by mutableStateOf<Set<String>>(emptySet())

    fun alternar(escopo: kotlinx.coroutines.CoroutineScope, id: String) {
        val nova = id !in ids
        ids = if (nova) ids + id else ids - id
        escopo.launch { runCatching { Api.objeto("mercado.favorita", JSONObject().put("id", id).put("favorita", nova)) } }
    }
}

/** O coracao da barra: fixa a moeda no topo do Mercado (o `FavoriteButton` do iOS). */
@Composable
fun BotaoFavorito(id: String?) {
    id ?: return
    val escopo = rememberCoroutineScope()
    val haptico = LocalHapticFeedback.current
    val favorita = id in Favoritas.ids
    LaunchedEffect(Unit) {
        if (Favoritas.ids.isEmpty()) {
            runCatching { Api.objeto("mercado.lista", JSONObject().put("moeda", App.estado.moeda)).optJSONArray("favoritas").textos().toSet() }
                .getOrNull()?.let { Favoritas.ids = it }
        }
    }
    val escala by animateFloatAsState(if (favorita) 1.08f else 1f, spring(dampingRatio = 0.5f, stiffness = 440f), label = "coracao")
    Box(
        Modifier.size(width = 42.dp, height = Altura.toque).clip(CircleShape).clickable {
            haptico.performHapticFeedback(HapticFeedbackType.ContextClick)
            Favoritas.alternar(escopo, id)
        }.semantics { contentDescription = if (favorita) t("Tirar dos favoritos") else t("Fixar no topo do Mercado") },
        contentAlignment = Alignment.Center,
    ) {
        AnimatedContent(favorita, transitionSpec = { (scaleIn(initialScale = 0.6f) + fadeIn()) togetherWith (scaleOut(targetScale = 0.6f) + fadeOut()) }, label = "favorita") { f ->
            Icone(if (f) Icones.coracaoCheio else Icones.coracao, if (f) Paleta.baixa else Paleta.tintaSuave, tamanho = 21.dp,
                  modifier = Modifier.graphicsLayer { scaleX = escala; scaleY = escala })
        }
    }
}

/** A pagina de uma moeda: o grafico, o mercado e, se a carteira tem, vender e comprar. */
@Composable
fun DetalheDaMoeda(m: MoedaDeMercado) {
    val escopo = rememberCoroutineScope()
    val moeda = App.estado.moeda
    var detalhes by remember { mutableStateOf<JSONObject?>(null) }
    var carregando by remember { mutableStateOf(true) }
    LaunchedEffect(m.id, moeda) {
        carregando = true
        detalhes = runCatching { Api.objeto("mercado.detalhes", JSONObject().put("id", m.id).put("moeda", moeda)) }.getOrNull()
        carregando = false
    }
    // O que comprar e o que vender desta moeda, pelo nucleo: (comprar, vender).
    var troca by remember { mutableStateOf<Pair<String?, String?>>(null to null) }
    LaunchedEffect(m.id, App.estado.carteira?.id) {
        troca = runCatching {
            Api.objeto("troca.daMoeda", JSONObject().put("coingecko", m.id)).let { it.opcional("comprar") to it.opcional("vender") }
        }.getOrDefault(null to null)
    }
    val observacao = App.estado.carteira?.observacao == true
    fun abrirTroca(ativo: String, vende: Boolean) {
        escopo.launch {
            if (!ControleDaTroca.preparar(ativo, vende)) return@launch
            Navegacao.fecharTudo()
            Navegacao.aba = Aba.trocar
        }
    }
    TelaComBarra(
        aoVoltar = { Navegacao.fechar() },
        centro = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                LogoDaMoeda(m.id, m.simbolo, 20.dp)
                Text(m.nome, style = estilo(Tipo.acao), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        },
        acoes = {
            SinoDoAlerta(m.id, m.simbolo, m.nome)
            BotaoFavorito(m.id)
        },
        // Vender o que a carteira tem da moeda, na rede onde ha mais; comprar pela primeira rede com
        // troca que tem a moeda.
        rodape = if (!observacao && (troca.first != null || troca.second != null)) ({
            Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                troca.second?.let { vender -> BotaoSecundario(t("Vender"), Modifier.weight(1f), altura = Altura.primaria) { abrirTroca(vender, true) } }
                troca.first?.let { comprar -> BotaoPrimario(t("Comprar %@", m.simbolo.uppercase()), Modifier.weight(1f)) { abrirTroca(comprar, false) } }
            }
        }) else null,
    ) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(bottom = Espaco.xl)) {
            SecaoDoGrafico(m.id, m.preco, m.variacao, moeda, estavel = m.id in listOf("tether", "usd-coin", "dai"))
            FatosDoMercado(m, detalhes, carregando, moeda, Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xl))
        }
    }
}

/**
 * O que a pagina da moeda mostra abaixo do grafico, como as boas corretoras: mercado, faixa de 24
 * horas, maxima historica, oferta e um "Sobre" curto. Os tres numeros da lista aparecem na hora; o
 * resto chega quando a pagina abre, e so o que a fonte entregou aparece.
 */
@Composable
private fun FatosDoMercado(m: MoedaDeMercado, d: JSONObject?, carregando: Boolean, moeda: String, modifier: Modifier = Modifier) {
    fun numero(chave: String): Double? = d?.takeIf { it.has(chave) && !it.isNull(chave) }?.getDouble(chave)
    val preco = numero("price") ?: m.preco
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espaco.lg)) {
        Column(verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
            Text(t("Sobre o mercado"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
            GradeDeFatos(buildList {
                add(t("Capitalização") to (numero("marketCap") ?: m.capitalizacao)?.let { Formato.compacto(it, moeda) })
                add(t("Volume em 24h") to (numero("volume24h") ?: m.volume)?.let { Formato.compacto(it, moeda) })
                add(t("Posição no mercado") to (d?.optInt("rank")?.takeIf { it > 0 } ?: m.posicao)?.let { "${it}º" })
                numero("fullyDilutedValuation")?.let { add(t("Valor totalmente diluído") to Formato.compacto(it, moeda)) }
            })
        }
        if (d != null) {
            val baixa = numero("low24h")
            val alta = numero("high24h")
            if (baixa != null && alta != null && alta > baixa) FaixaDoDia(baixa, alta, preco, moeda)
            numero("allTimeHigh")?.let { maxima ->
                Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Text(t("Máxima histórica"), style = estilo(Tipo.acao), color = Paleta.tinta)
                    Row(verticalAlignment = Alignment.Top) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(Formato.preco(maxima, moeda), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                            d.data("allTimeHighDate")?.let { Text(t("Em %@", Formato.diaLongo(it)), style = estilo(Tipo.nota), color = Paleta.tintaApagada) }
                        }
                        numero("fromAllTimeHigh")?.let { distancia ->
                            Text(if (distancia >= -0.5) t("Na máxima") else t("%@%% abaixo da máxima", Formato.agrupado(abs(distancia), if (abs(distancia) < 10) 1 else 0, aparar = true)),
                                 style = estilo(Tipo.nota), color = Paleta.tintaSuave, textAlign = TextAlign.End, modifier = Modifier.padding(start = Espaco.sm))
                        }
                    }
                }
            }
            val simbolo = m.simbolo.uppercase()
            val oferta = buildList {
                numero("circulatingSupply")?.let { add(t("Em circulação") to "${Formato.compacto(it)} $simbolo") }
                numero("totalSupply")?.let { add(t("Oferta total") to "${Formato.compacto(it)} $simbolo") }
                val maximo = numero("maxSupply")
                if (maximo != null) add(t("Oferta máxima") to "${Formato.compacto(maximo)} $simbolo")
                else if (d.optBoolean("unlimitedSupply")) add(t("Oferta máxima") to t("Sem teto"))
            }
            if (oferta.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
                    Text(t("Oferta de moedas"), style = estilo(Tipo.acao), color = Paleta.tinta)
                    GradeDeFatos(oferta)
                }
            }
            d.optString("about").takeIf { it.isNotBlank() && it != "null" }?.let { sobre ->
                Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Text(t("Sobre o projeto"), style = estilo(Tipo.acao), color = Paleta.tinta)
                    androidx.compose.foundation.text.selection.SelectionContainer {
                        Text(sobre, style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                    }
                    if (!d.optBoolean("aboutInPortuguese")) Text(t("Texto em inglês, como a fonte publica."), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                }
            }
        } else if (carregando) {
            Column(verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                Esqueleto(140.dp, 16.dp)
                Esqueleto(220.dp)
                Esqueleto(180.dp)
            }
        }
        if (d != null) {
            val fonte = d.optString("source")
            val quando = d.data("fetchedAt")?.let { Formato.carimbo(it) } ?: ""
            Text(if (d.optBoolean("isStale")) t("Sem conexão com as fontes agora. Dados de %@, do %@.", quando, fonte) else t("Dados do %@, às %@.", fonte, quando),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        } else if (!carregando) {
            Text(t("Não foi possível carregar mais dados desta moeda agora."), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
    }
}

/** Numeros em duas colunas: valor em cima, rotulo embaixo. Sem valor, "sem dado". */
@Composable
private fun GradeDeFatos(itens: List<Pair<String, String?>>) {
    Column(verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
        for (par in itens.chunked(2)) {
            Row(horizontalArrangement = Arrangement.spacedBy(Espaco.md)) {
                for ((rotulo, valor) in par) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(valor ?: t("sem dado"), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                        Text(rotulo, style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                    }
                }
                if (par.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** Faixa de 24 horas: minima e maxima, com o preco de agora marcado entre elas. */
@Composable
private fun FaixaDoDia(baixa: Double, alta: Double, preco: Double, moeda: String) {
    // A maxima e a minima da fonte podem estar um pouco atras do preco vivo: o marcador fica na ponta.
    val posicao = ((preco - baixa) / (alta - baixa)).coerceIn(0.0, 1.0).toFloat()
    Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Text(t("Faixa de 24 horas"), style = estilo(Tipo.acao), color = Paleta.tinta)
        Canvas(Modifier.fillMaxWidth().height(12.dp)) {
            val meio = size.height / 2
            val traco = 4.dp.toPx()
            drawLine(Paleta.trilho, Offset(traco / 2, meio), Offset(size.width - traco / 2, meio), traco, StrokeCap.Round)
            drawLine(Paleta.bordaForte, Offset(traco / 2, meio), Offset(maxOf(traco, size.width * posicao) - traco / 2, meio), traco, StrokeCap.Round)
            val x = (size.width * posicao).coerceIn(6.dp.toPx(), size.width - 6.dp.toPx())
            drawCircle(Paleta.tinta, 6.dp.toPx(), Offset(x, meio))
        }
        Row {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(Formato.preco(baixa, moeda), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                Text(t("Mínima"), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(Formato.preco(alta, moeda), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                Text(t("Máxima"), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            }
        }
    }
}
