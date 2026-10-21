package app.escalibur.wallet.ui.atividade

import app.escalibur.wallet.ui.comp.LocalEspacoDaBarra
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
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
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
            runCatching { retrato = RetratoDaAtividade(Api.objeto("atividade.atualizar", JSONObject().put("forcar", forcar))) }
        }
    }
    LaunchedEffect(estado.selecionada) {
        runCatching { retrato = RetratoDaAtividade(Api.objeto("atividade.mostrar")) }
        atualizar(false)
    }
    LaunchedEffect(Unit) {
        Eventos.eventos.filter { it.nome == "atividade" }.collect { evento -> runCatching { retrato = RetratoDaAtividade(JSONObject(evento.json)) } }
    }

    val r = retrato
    val pendentes = r?.itens?.filter { it.situacao == "pendente" }.orEmpty()
    val feitos = r?.itens?.filter { it.situacao != "pendente" }.orEmpty()
    val carregandoPrimeiraVez = r == null || (r.itens.isEmpty() && (r.carregando || !r.lidaUmaVez))

    PullToRefreshBox(
        isRefreshing = puxando,
        onRefresh = {
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
                Faixa(TipoDeFaixa.neutra, t("%@ não atualizou agora. Mostrando o que já estava salvo.", nomes(r.falhas)),
                      Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm), tituloDaAcao = t("Tentar de novo")) { atualizar(true) }
            }
            when {
                carregandoPrimeiraVez -> Column(Modifier.fillMaxWidth().padding(top = Espaco.xxl), horizontalAlignment = Alignment.CenterHorizontally,
                                               verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    CircularProgressIndicator(color = Paleta.tintaSuave, strokeWidth = 2.dp, modifier = Modifier.size(28.dp))
                    Text(t("Lendo o histórico"), style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.sm))
                    Text(if ((r?.redes ?: 0) > 1) t("%lld redes, cada uma direto dos provedores públicos.", r?.redes ?: 0) else t("Direto dos provedores públicos da rede."),
                         style = estilo(Tipo.nota), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
                }
                r != null && r.itens.isEmpty() -> Column(Modifier.fillMaxWidth().padding(horizontal = Espaco.margem).padding(top = Espaco.xl),
                                                         horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    Box(Modifier.size(96.dp).clip(CircleShape).background(Paleta.corpo), contentAlignment = Alignment.Center) {
                        Icone(Icones.atividade, Paleta.tintaApagada, tamanho = 36.dp)
                    }
                    Text(t("Sua atividade aparece aqui"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.md))
                    Text(t("Envios, recebimentos, trocas e ordens, cada um com o seu status."), style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
                    BotaoPrimario(t("Receber"), Modifier.padding(top = Espaco.md)) { Navegacao.folha { FluxoDeReceber() } }
                }
                else -> {
                    if (pendentes.isNotEmpty()) Secao(t("Pendentes"), pendentes, oculto)
                    for ((titulo, itens) in porDia(feitos.take(visiveis))) Secao(titulo, itens, oculto)
                    if (feitos.size > visiveis) {
                        BotaoSecundario(t("Mostrar mais"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md)) { visiveis += 20 }
                    }
                }
            }
            if (r != null && r.semHistorico.isNotEmpty()) {
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
    val preco = if (m.custom || m.zero || m.falhou) null else Saldos.retrato.todasAsLinhas.firstOrNull { it.coingecko != null && it.coingecko == m.coingecko }?.preco
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding()) {
        CabecalhoDeFolha("", null, aoVoltar = { Navegacao.fechar() })
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.xl),
               verticalArrangement = Arrangement.spacedBy(Espaco.lg)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                if (m.direcao == "swap" && m.recebidoSimbolo != null) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                        LogoDaMoeda(m.coingecko, m.simbolo, 56.dp, rede = m.rede, redeCoingecko = m.redeCoingecko, naoConferido = m.custom)
                        Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 15.dp)
                        LogoDaMoeda(m.recebidoCoingecko, m.recebidoSimbolo, 56.dp, rede = m.rede, redeCoingecko = m.redeCoingecko)
                    }
                } else {
                    Box(Modifier.size(96.dp).clip(CircleShape).background(Paleta.corpo), contentAlignment = Alignment.Center) {
                        LogoDaMoeda(m.coingecko, m.simbolo, 72.dp, rede = m.rede, redeCoingecko = m.redeCoingecko, anel = Paleta.corpo, naoConferido = m.custom)
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Text(tipo, style = estilo(Tipo.linha), color = Paleta.tintaSuave)
                    if (m.custom && m.direcao == "received") SeloDeToken(t("Suspeito"), Paleta.cautela)
                }
                when {
                    m.direcao == "swap" && m.recebidoQuantidade != null && m.recebidoSimbolo != null -> {
                        Text("+" + Formato.cripto(m.recebidoQuantidade, m.recebidoCasas ?: 0, m.recebidoSimbolo, Formato.EstiloCripto.cheio),
                             style = estilo(Tipo.numero), color = if (m.falhou) Paleta.tintaApagada else Paleta.alta)
                        Text(t("por %@", Formato.cripto(m.quantidade, m.casas, m.simbolo, Formato.EstiloCripto.cheio)), style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                    }
                    m.soTaxa != null -> {
                        Text(Formato.menos + Formato.cripto(m.soTaxa!!, m.casasNativas, m.simboloNativo, Formato.EstiloCripto.cheio), style = estilo(Tipo.numero), color = Paleta.tinta)
                        Text(t("Só a taxa da rede: nenhum valor saiu da conta"), style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                    }
                    else -> {
                        Text(m.sinal + Formato.cripto(m.quantidade, m.casas, m.simbolo, Formato.EstiloCripto.cheio), style = estilo(Tipo.numero),
                             color = if (m.falhou) Paleta.tintaApagada else if (m.direcao == "received") Paleta.alta else Paleta.tinta,
                             textDecoration = if (m.falhou) TextDecoration.LineThrough else null)
                        preco?.let {
                            Text(t("≈ %@ hoje", Formato.valor(Formato.numero(m.quantidade, m.casas) * it, App.estado.moeda)), style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                        }
                    }
                }
                Situacao(m, conferencia)
            }
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(horizontal = Espaco.base, vertical = Espaco.xs)) {
                if (m.direcao != "swap") Fato(t("Moeda")) {
                    LogoDaMoeda(m.coingecko, m.simbolo, 22.dp, naoConferido = m.custom)
                    Text(m.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta)
                }
                Fato(t("Rede")) {
                    SeloDaRede(m.rede, m.redeCoingecko, 22.dp, Paleta.corpo)
                    Text(m.redeNome, style = estilo(Tipo.linha), color = Paleta.tinta)
                }
                Fato(t("Data")) {
                    val formato = java.text.SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(Formato.locale, "dMMMyyyyHHmm"), Formato.locale)
                    Text(formato.format(m.data), style = estilo(Tipo.linha), color = Paleta.tinta)
                }
                m.taxa?.let { taxa ->
                    Fato(t("Taxa da rede")) { Text(Formato.cripto(taxa, m.casasNativas, m.simboloNativo, Formato.EstiloCripto.cheio), style = estilo(Tipo.linha), color = Paleta.tinta) }
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
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(horizontal = Espaco.base)) {
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

@Composable
private fun Situacao(m: Movimento, conferencia: JSONObject?) {
    val (texto, cor) = if (m.conferivel) {
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
    Row(Modifier.padding(top = Espaco.xs).clip(CircleShape).background(Paleta.corpo).padding(horizontal = Espaco.sm, vertical = 6.dp),
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
