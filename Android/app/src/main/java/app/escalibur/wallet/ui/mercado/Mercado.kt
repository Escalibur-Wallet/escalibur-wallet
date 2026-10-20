package app.escalibur.wallet.ui.mercado

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
        val quando = resposta.data("atualizado")
        velho = if (resposta.optBoolean("velho")) quando else null
        rodape = quando?.let { t("Dados de mercado: %@, às %@", resposta.optString("fonte"), Formato.relogio(it)) }
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
    val marcadas = favoritas.mapNotNull { id -> filtradas.firstOrNull { it.id == id } }.let { if (ordem == Ordem.relevancia) it else ordem.ordenar(it) }
    val outras = ordem.ordenar(filtradas.filter { it.id !in favoritas })

    LazyColumn(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding()) {
        item { TituloDeAba(t("Mercado")) }
        item { CampoDeBusca(busca, t("Buscar moeda"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm)) { busca = it } }
        item {
            Row(Modifier.padding(top = Espaco.sm).horizontalScroll(rememberScrollState()).padding(horizontal = Espaco.margem), horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                for (opcao in Ordem.entries) Chip(opcao.titulo, ordem == opcao) { if (moedas.isNotEmpty()) ordem = opcao }
            }
        }
        when {
            moedas.isEmpty() && (carregando || !falhou) -> items(8) {
                Row(Modifier.fillMaxWidth().heightIn(min = Altura.linha).padding(horizontal = Espaco.margem), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    Box(Modifier.size(40.dp).clip(RoundedCornerShape(20.dp)).background(Paleta.corpo))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) { Esqueleto(48.dp); Esqueleto(88.dp) }
                    Esqueleto(72.dp, 16.dp)
                }
            }
            moedas.isEmpty() && falhou -> item {
                Column(Modifier.fillMaxWidth().padding(horizontal = Espaco.margem).padding(top = 72.dp), horizontalAlignment = Alignment.CenterHorizontally,
                       verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    Icone(Icones.mercado, Paleta.tintaApagada, tamanho = 36.dp)
                    Text(t("Não foi possível carregar o mercado agora."), style = estilo(Tipo.linha), color = Paleta.tinta, textAlign = TextAlign.Center)
                    BotaoSecundario(t("Tentar de novo")) { escopo.launch { carregar() } }
                }
            }
            else -> {
                velho?.let { quando ->
                    item {
                        Faixa(TipoDeFaixa.neutra, t("Sem conexão com os dados de mercado agora."), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md),
                              mensagem = t("Mostrando os preços de %@.", Formato.relogio(quando)), tituloDaAcao = t("Tentar de novo")) { escopo.launch { carregar() } }
                    }
                }
                if (marcadas.isNotEmpty()) {
                    item { TituloDeSecao(t("Favoritas")) }
                    items(marcadas, key = { "f" + it.id }) { LinhaDoMercado(it, moeda) { abrir(it) } }
                    item { TituloDeSecao(t("Todas")) }
                }
                items(outras, key = { it.id }) { LinhaDoMercado(it, moeda) { abrir(it) } }
                rodape?.let { item { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada, textAlign = TextAlign.Center,
                                          modifier = Modifier.fillMaxWidth().padding(top = Espaco.lg, bottom = Espaco.xl)) } }
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
private fun LinhaDoMercado(m: MoedaDeMercado, moeda: String, aoTocar: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Altura.linha).clickable(onClick = aoTocar).padding(horizontal = Espaco.margem),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        LogoDaMoeda(m.id, m.simbolo, 40.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(m.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
            Text(m.nome, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
        }
        Text(Formato.preco(m.preco, moeda), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, textAlign = TextAlign.End, modifier = Modifier.width(120.dp))
        PilulaDeVariacao(m.variacao, Modifier.width(84.dp))
    }
}

/** A pagina de uma moeda: o grafico, o mercado e, se a carteira tem, enviar e receber. */
@Composable
fun DetalheDaMoeda(m: MoedaDeMercado) {
    val escopo = rememberCoroutineScope()
    val moeda = App.estado.moeda
    var favorita by remember { mutableStateOf(false) }
    var detalhes by remember { mutableStateOf<JSONObject?>(null) }
    var semDetalhes by remember { mutableStateOf(false) }
    LaunchedEffect(m.id) {
        favorita = runCatching { Api.objeto("mercado.lista", JSONObject().put("moeda", moeda)).optJSONArray("favoritas").textos().contains(m.id) }.getOrDefault(false)
        detalhes = runCatching { Api.objeto("mercado.detalhes", JSONObject().put("id", m.id).put("moeda", moeda)) }.getOrNull()
        semDetalhes = detalhes == null
    }
    // O que comprar e o que vender desta moeda, pelo nucleo: (comprar, vender).
    var troca by remember { mutableStateOf<Pair<String?, String?>>(null to null) }
    LaunchedEffect(m.id, App.estado.carteira?.id) {
        troca = runCatching {
            Api.objeto("troca.daMoeda", JSONObject().put("coingecko", m.id)).let { it.opcional("comprar") to it.opcional("vender") }
        }.getOrDefault(null to null)
    }
    val observacao = App.estado.carteira?.observacao == true
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding()) {
        Box(Modifier.fillMaxWidth()) {
            CabecalhoDeFolha(m.nome, null, aoVoltar = { Navegacao.fechar() })
            SinoDoAlerta(m.id, m.simbolo, m.nome, Modifier.align(Alignment.CenterEnd).padding(end = Espaco.xs + Altura.toque))
            Box(Modifier.align(Alignment.CenterEnd).padding(end = Espaco.xs).size(Altura.toque).clickable {
                val nova = !favorita
                favorita = nova
                escopo.launch { runCatching { Api.objeto("mercado.favorita", JSONObject().put("id", m.id).put("favorita", nova)) } }
            }, contentAlignment = Alignment.Center) {
                Icone(Icones.estrela, if (favorita) Paleta.realce else Paleta.tintaSuave, tamanho = 20.dp,
                      descricao = if (favorita) t("Tirar das favoritas") else t("Marcar como favorita"))
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = Espaco.xl)) {
            Row(Modifier.padding(horizontal = Espaco.margem).padding(bottom = Espaco.sm), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                LogoDaMoeda(m.id, m.simbolo, 24.dp)
                Text(m.simbolo, style = estilo(Tipo.linha), color = Paleta.tintaSuave)
            }
            SecaoDoGrafico(m.id, m.preco, m.variacao, moeda, estavel = m.id in listOf("tether", "usd-coin", "dai"))
            FatosDoMercado(m, detalhes, semDetalhes, moeda)
        }
        // Vender o que a carteira tem da moeda, na rede onde ha mais; comprar pela primeira rede com
        // troca que tem a moeda (o MarketCoinDetail do iOS).
        if (!observacao && (troca.first != null || troca.second != null)) {
            fun abrir(ativo: String, vende: Boolean) {
                escopo.launch {
                    if (!ControleDaTroca.preparar(ativo, vende)) return@launch
                    Navegacao.fecharTudo()
                    Navegacao.aba = Aba.trocar
                }
            }
            Row(Modifier.padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs), horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                troca.second?.let { vender -> BotaoSecundario(t("Vender"), Modifier.weight(1f), altura = Altura.primaria) { abrir(vender, true) } }
                troca.first?.let { comprar -> BotaoPrimario(t("Comprar %@", m.simbolo.uppercase()), Modifier.weight(1f)) { abrir(comprar, false) } }
            }
        }
    }
}

@Composable
private fun FatosDoMercado(m: MoedaDeMercado, d: JSONObject?, semDetalhes: Boolean, moeda: String) {
    fun numero(chave: String): Double? = d?.takeIf { it.has(chave) && !it.isNull(chave) }?.getDouble(chave)
    Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xl), verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
        Text(t("Sobre o mercado"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
        Cartao {
            Fato(t("Capitalização"), (numero("marketCap") ?: m.capitalizacao)?.let { Formato.compacto(it, moeda) })
            Fato(t("Volume em 24h"), (numero("volume24h") ?: m.volume)?.let { Formato.compacto(it, moeda) })
            Fato(t("Posição no mercado"), (d?.optInt("rank")?.takeIf { it > 0 } ?: m.posicao)?.let { "${it}º" })
            numero("fullyDilutedValuation")?.let { Fato(t("Valor totalmente diluído"), Formato.compacto(it, moeda)) }
        }
        val baixa = numero("low24h")
        val alta = numero("high24h")
        if (baixa != null && alta != null) {
            Text(t("Faixa de 24 horas"), style = estilo(Tipo.acao), color = Paleta.tinta)
            Cartao {
                Fato(t("Mínima"), Formato.preco(baixa, moeda))
                Fato(t("Máxima"), Formato.preco(alta, moeda))
            }
        }
        numero("allTimeHigh")?.let { maxima ->
            Text(t("Máxima histórica"), style = estilo(Tipo.acao), color = Paleta.tinta)
            Cartao {
                Fato(t("Preço"), Formato.preco(maxima, moeda))
                numero("fromAllTimeHigh")?.let { distancia ->
                    Fato(t("Distância"), if (distancia >= -0.5) t("Na máxima") else t("%@%% abaixo da máxima", Formato.agrupado(kotlin.math.abs(distancia), if (kotlin.math.abs(distancia) < 10) 1 else 0, aparar = true)))
                }
            }
        }
        val circulando = numero("circulatingSupply")
        val total = numero("totalSupply")
        val maximo = numero("maxSupply")
        if (circulando != null || total != null || maximo != null || d?.optBoolean("unlimitedSupply") == true) {
            Text(t("Oferta de moedas"), style = estilo(Tipo.acao), color = Paleta.tinta)
            Cartao {
                circulando?.let { Fato(t("Em circulação"), Formato.compacto(it)) }
                total?.let { Fato(t("Oferta total"), Formato.compacto(it)) }
                if (maximo != null) Fato(t("Oferta máxima"), Formato.compacto(maximo)) else if (d?.optBoolean("unlimitedSupply") == true) Fato(t("Oferta máxima"), t("Sem teto"))
            }
        }
        d?.optString("about")?.takeIf { it.isNotBlank() && it != "null" }?.let { sobre ->
            Text(t("Sobre o projeto"), style = estilo(Tipo.acao), color = Paleta.tinta)
            Text(sobre, style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
            if (d.optBoolean("aboutInPortuguese") == false) Text(t("Texto em inglês, como a fonte publica."), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
        if (semDetalhes) Text(t("Não foi possível carregar mais dados desta moeda agora."), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
    }
}

@Composable
private fun Cartao(conteudo: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(horizontal = Espaco.md, vertical = Espaco.xs)) { conteudo() }
}

@Composable
private fun Fato(rotulo: String, valor: String?) {
    Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(rotulo, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.weight(1f))
        Text(valor ?: t("sem dado"), style = estilo(Tipo.linha), color = Paleta.tinta)
    }
}
