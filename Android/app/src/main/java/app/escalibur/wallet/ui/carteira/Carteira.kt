package app.escalibur.wallet.ui.carteira

import app.escalibur.wallet.ui.comp.LocalEspacoDaBarra
import androidx.compose.animation.core.animateDpAsState
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.AcaoRapida
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.Esqueleto
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.comp.toqueDeSelecao
import app.escalibur.wallet.ui.principal.Aba
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.receber.FluxoDeReceber
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.launch
import org.json.JSONObject

/** As redes de cada carteira: nome e o id do CoinGecko da moeda nativa (para o logo da rede). */
object Redes {
    data class Rede(val id: String, val nome: String, val familia: String, val simbolo: String, val coingecko: String, val casas: Int)

    var todas by mutableStateOf<List<Rede>>(emptyList())
        private set

    suspend fun carregar() {
        if (todas.isNotEmpty()) return
        todas = runCatching {
            Api.lista("redes").objetos().map {
                Rede(it.getString("id"), it.getString("nome"), it.getString("familia"), it.getString("simbolo"), it.getString("coingecko"), it.getInt("casas"))
            }
        }.getOrDefault(emptyList())
    }

    fun rede(id: String): Rede? = todas.firstOrNull { it.id == id }
}

/** Quanto eu tenho e em que. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TelaDaCarteira() {
    val estado = App.estado
    val carteira = estado.carteira ?: return
    val retrato = Saldos.retrato
    val ocultar = estado.ocultarSaldos
    val escopo = rememberCoroutineScope()
    var trocando by remember { mutableStateOf(false) }

    LaunchedEffect(carteira.id) {
        Redes.carregar()
        Saldos.mostrar()
        Saldos.atualizar(forcar = false)
        // O historico comeca a ser lido logo depois do saldo: a Atividade so mostra o que ja chegou.
        runCatching { Api.objeto("atividade.atualizar", JSONObject().put("forcar", false)) }
    }

    // A unidade escolhida, se ha cotacao para ela agora; senao a moeda do app.
    val unidades = listOf("usd", "brl", "eur", "btc").filter { retrato.converter(1.0, it) != null }
    val unidade = estado.unidade.takeIf { it in unidades } ?: estado.moeda
    val total = retrato.converter(retrato.total, unidade) ?: retrato.total
    val variacao = retrato.converter(retrato.variacao24h, unidade) ?: retrato.variacao24h
    val taxa = retrato.converter(1.0, unidade)

    // O indicador de cima so quando o dono puxa; a leitura automatica fica no circulo de Ativos.
    var puxando by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = puxando,
        onRefresh = {
            puxando = true
            escopo.launch {
                try { Saldos.atualizar(forcar = true) } finally { puxando = false }
            }
        },
        modifier = Modifier.fillMaxSize(),
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(bottom = Espaco.xl + LocalEspacoDaBarra.current)) {
            // Cabecalho: a carteira (abre a lista) e o olho.
            Row(Modifier.fillMaxWidth().padding(horizontal = Espaco.margem), verticalAlignment = Alignment.CenterVertically) {
                Row(
                    Modifier.heightIn(min = Altura.toque).clickable { trocando = true },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs),
                ) {
                    if (carteira.temPassphrase) Icone(Icones.cadeadoCheio, Paleta.tintaSuave, tamanho = 14.dp, descricao = t("Carteira com passphrase"))
                    Text(carteira.nome, style = estilo(Tipo.acao), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (carteira.observacao) {
                        Text(t("Só observar"), style = estilo(Tipo.rotulo), color = Paleta.tintaSuave,
                             modifier = Modifier.clip(RoundedCornerShape(Raio.selo)).background(Paleta.trilho).padding(horizontal = 6.dp, vertical = 3.dp))
                    }
                    Icone(Icones.abaixo, Paleta.tintaApagada, tamanho = 13.dp)
                }
                Spacer(Modifier.weight(1f))
                Box(
                    Modifier.size(Altura.toque).clickable {
                        escopo.launch { App.aplicar(Api.objeto("ajustes.ocultarSaldos", JSONObject().put("ocultar", !ocultar))) }
                    },
                    contentAlignment = Alignment.CenterEnd,
                ) {
                    Icone(if (ocultar) Icones.olhoRiscado else Icones.olho, Paleta.tintaSuave, tamanho = 20.dp,
                          descricao = if (ocultar) t("Mostrar valores") else t("Ocultar valores"))
                }
            }

            Row(Modifier.fillMaxWidth().padding(horizontal = Espaco.margem).padding(top = Espaco.md), verticalAlignment = Alignment.CenterVertically) {
                Text(t("Saldo total"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.weight(1f))
                SeletorDeUnidade(unidade, unidades) { nova ->
                    escopo.launch {
                        App.aplicar(Api.objeto("ajustes.unidade", JSONObject().put("unidade", nova)))
                        Saldos.atualizar(forcar = true)
                    }
                }
            }
            NumeroDoSaldo(total, unidade, ocultar, Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xxs))
            LinhaDaVariacao(variacao, retrato, unidade, ocultar, Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xxs))

            Row(Modifier.fillMaxWidth().padding(horizontal = Espaco.xs).padding(top = Espaco.lg)) {
                if (!carteira.observacao) {
                    AcaoRapida(t("Enviar"), Icones.enviar, Modifier.weight(1f)) { Navegacao.cobrir { app.escalibur.wallet.ui.enviar.FluxoDeEnviar(null) } }
                }
                AcaoRapida(t("Receber"), Icones.receber, Modifier.weight(1f)) { Navegacao.folha { FluxoDeReceber() } }
                if (!carteira.observacao) {
                    AcaoRapida(t("Trocar"), Icones.trocar, Modifier.weight(1f)) { Navegacao.aba = Aba.trocar }
                }
            }

            if (!carteira.temCopia && !carteira.observacao) {
                val titulo = if (carteira.palavrasConfirmadas) t("Falta conferir a passphrase") else t("Falta confirmar que você anotou as palavras")
                val mensagem = if (carteira.palavrasConfirmadas) t("Digite a passphrase de novo, de onde você anotou, antes de receber.")
                else t("Grave as %lld palavras antes de receber. Leva 2 minutos.", carteira.palavras ?: 12)
                Faixa(
                    TipoDeFaixa.cautela, titulo, Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg), mensagem = mensagem,
                    tituloDaAcao = if (carteira.palavrasConfirmadas) t("Conferir agora") else t("Gravar agora"),
                    acao = { Navegacao.cobrir { CopiaAgora(carteira) } },
                )
            }
            AvisosDeEstado(retrato)

            Ativos(retrato, ocultar, unidade, taxa)
        }
    }
    if (trocando) SeletorDeCarteiras { trocando = false }
}

@Composable
private fun AvisosDeEstado(retrato: Retrato) {
    val escopo = rememberCoroutineScope()
    val modificador = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg)
    val atualizado = retrato.atualizado
    when {
        retrato.semRede && atualizado != null ->
            Faixa(TipoDeFaixa.neutra, t("Sem internet. Valores de %@.", Formato.relativo(atualizado, naFrase = true)), modificador)
        retrato.semRede ->
            Faixa(TipoDeFaixa.neutra, t("Sem internet. Os saldos aparecem quando a conexão voltar."), modificador,
                  tituloDaAcao = t("Tentar de novo"), acao = { escopo.launch { Saldos.atualizar(true) } })
        retrato.falhas.isNotEmpty() ->
            Faixa(TipoDeFaixa.neutra, t("Não foi possível ler o saldo na %@. Os outros estão em dia.", retrato.falhas.first()), modificador,
                  tituloDaAcao = t("Tentar de novo"), acao = { escopo.launch { Saldos.atualizar(true) } })
    }
}

/** O saldo grande: o simbolo menor e mais claro, o inteiro em peso, as casas menores. */
@Composable
fun NumeroDoSaldo(valor: Double, unidade: String, oculto: Boolean, modifier: Modifier = Modifier) {
    val casas = if (unidade == "btc") 8 else 2
    val simbolo = Formato.simboloDaMoeda(unidade)
    val texto = buildAnnotatedString {
        val estiloDoSimbolo = SpanStyle(fontSize = 24.sp, fontWeight = FontWeight.SemiBold, color = Paleta.tintaSuave)
        val antes = Formato.dinheiro("X", simbolo).startsWith(simbolo)
        if (antes) withStyle(estiloDoSimbolo) { append(simbolo + " ") }
        if (oculto) {
            append("••••••")
        } else {
            val numero = Formato.agrupado(valor, casas, aparar = unidade == "btc")
            val partes = numero.split(Formato.decimal)
            append(partes[0])
            withStyle(SpanStyle(fontSize = if (casas > 2) 22.sp else 28.sp, color = Paleta.tintaSuave)) {
                append(Formato.decimal + (partes.getOrNull(1) ?: "0".repeat(casas)))
            }
        }
        if (!antes) withStyle(estiloDoSimbolo) { append(" $simbolo") }
    }
    Text(texto, style = estilo(Tipo.vitrine), color = Paleta.tinta, maxLines = 1, modifier = modifier)
}

@Composable
private fun LinhaDaVariacao(variacao: Double, retrato: Retrato, unidade: String, oculto: Boolean, modifier: Modifier) {
    if (oculto || retrato.total == 0.0) {
        Text(" ", style = estilo(Tipo.linha), modifier = modifier)
        return
    }
    val cor = when {
        retrato.variacao24h > 0 -> Paleta.alta
        retrato.variacao24h < 0 -> Paleta.baixa
        else -> Paleta.tintaSuave
    }
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Bottom) {
        Text("${Formato.valor(variacao, unidade, comSinal = true)} (${Formato.percentual(retrato.variacao24hPct)})", style = estilo(Tipo.linha), color = cor)
        Text(if (retrato.falhas.isEmpty()) "24h" else t("24h, sem %@", retrato.falhas.joinToString(", ")), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
    }
}

/** R$, US$, €, ₿: em que unidade o total aparece. */
@Composable
private fun SeletorDeUnidade(escolhida: String, unidades: List<String>, aoEscolher: (String) -> Unit) {
    val toque = toqueDeSelecao()
    Row(Modifier.clip(CircleShape).background(Paleta.corpo).padding(2.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        for (unidade in unidades) {
            val selecionada = unidade == escolhida
            Box(
                Modifier.heightIn(min = 28.dp).clip(CircleShape)
                    .background(if (selecionada) Paleta.controle else Paleta.corpo)
                    .clickable { if (!selecionada) { toque(); aoEscolher(unidade) } }
                    .padding(horizontal = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(Formato.simboloDaMoeda(unidade), style = estilo(Tipo.rotulo), color = if (selecionada) Paleta.tinta else Paleta.tintaApagada)
            }
        }
    }
}

@Composable
private fun Ativos(retrato: Retrato, oculto: Boolean, unidade: String, taxa: Double?) {
    Column(Modifier.padding(top = Espaco.xl)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = Espaco.margem), verticalAlignment = Alignment.CenterVertically) {
            Text(t("Ativos"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
            if (retrato.carregando) {
                CircularProgressIndicator(color = Paleta.tintaApagada, strokeWidth = 1.5.dp, modifier = Modifier.padding(start = Espaco.xs).size(14.dp))
            }
        }
        when {
            retrato.linhas.isEmpty() && retrato.carregando && retrato.atualizado == null -> EsqueletoDosAtivos()
            retrato.linhas.isEmpty() && retrato.atualizado == null && (retrato.semRede || retrato.falhas.isNotEmpty()) -> NaoLidos()
            retrato.linhas.isEmpty() -> CarteiraVazia()
            else -> Column(Modifier.padding(top = Espaco.xs)) {
                for (linha in retrato.linhas) LinhaDeAtivo(linha, oculto, unidade, taxa, retrato.moeda) {
                    Navegacao.abrir { DetalheDoAtivo(linha.id) }
                }
            }
        }
        if (retrato.outros.isNotEmpty()) OutrosTokens(retrato.outros, oculto, unidade, taxa, retrato.moeda)
    }
}

@Composable
private fun EsqueletoDosAtivos() {
    Column(Modifier.padding(top = Espaco.xs)) {
        repeat(4) {
            Row(Modifier.fillMaxWidth().heightIn(min = Altura.linha).padding(horizontal = Espaco.margem), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                Box(Modifier.size(40.dp).clip(CircleShape).background(Paleta.corpo))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { Esqueleto(56.dp); Esqueleto(88.dp) }
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) { Esqueleto(72.dp); Esqueleto(48.dp) }
            }
        }
    }
}

@Composable
private fun NaoLidos() {
    val escopo = rememberCoroutineScope()
    Column(
        Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md).fillMaxWidth()
            .clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(Espaco.md),
    ) {
        Text(t("Os saldos ainda não foram lidos"), style = estilo(Tipo.linha), color = Paleta.tinta)
        Text(t("As redes não responderam agora. Isso não quer dizer que a carteira está vazia: os valores aparecem quando a leitura der certo."),
             style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xxs))
        BotaoSecundario(t("Tentar de novo"), Modifier.padding(top = Espaco.md)) { escopo.launch { Saldos.atualizar(true) } }
    }
}

@Composable
private fun CarteiraVazia() {
    Column(
        Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md).fillMaxWidth()
            .clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(Espaco.md),
    ) {
        Text(t("Um endereço em cada rede"), style = estilo(Tipo.linha), color = Paleta.tinta)
        Text(t("Esta carteira já tem endereço em Bitcoin, Ethereum, Base, Solana, XRP Ledger, Stellar e outras. Receba em qualquer um para começar."),
             style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xxs))
        Row(Modifier.padding(top = Espaco.md)) {
            listOf("bitcoin" to "bitcoin", "ethereum" to "ethereum", "solana" to "solana", "xrpl" to "ripple", "stellar" to "stellar", "tron" to "tron", "base" to "ethereum")
                .forEachIndexed { indice, (rede, moeda) ->
                    SeloDaRede(rede, moeda, 28.dp, Paleta.corpo, Modifier.offset(x = (-6 * indice).dp))
                }
        }
        Text(t("No XRP Ledger e na Stellar, a conta passa a existir no primeiro recebimento de 1 XRP ou 1 XLM, que ficam reservados pela rede."),
             style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.md))
        BotaoSecundario(t("Receber"), Modifier.padding(top = Espaco.md)) { Navegacao.folha { FluxoDeReceber() } }
    }
}

/** Uma linha de ativo, 64, sem filete. */
@Composable
fun LinhaDeAtivo(linha: Linha, oculto: Boolean, unidade: String, taxa: Double?, moeda: String, aoTocar: () -> Unit) {
    val unidadeMostrada = if (taxa != null) unidade else moeda
    fun mostrado(valor: Double) = valor * (taxa ?: 1.0)
    val umaRede = linha.posicoes.singleOrNull()
    Row(
        Modifier.fillMaxWidth().clickable(onClick = aoTocar).heightIn(min = Altura.linha).padding(horizontal = Espaco.margem),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        LogoDaMoeda(
            linha.coingecko, linha.simbolo, 40.dp, rede = umaRede?.rede, redeCoingecko = umaRede?.let { Redes.rede(it.rede)?.coingecko },
            quantasRedes = linha.posicoes.size, naoConferido = !linha.conferido && !linha.reconhecido,
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(linha.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (linha.custom) SeloDeToken(t("Custom"))
                val preco = linha.preco
                if (preco != null) {
                    Text(Formato.preco(mostrado(preco), unidadeMostrada), style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
                } else if (Saldos.esperandoPreco(linha)) {
                    Esqueleto(58.dp, 10.dp)
                }
                linha.variacao24h?.let { variacao ->
                    Text(Formato.percentual(variacao), style = estilo(Tipo.nota), maxLines = 1,
                         color = if (variacao > 0.004) Paleta.alta else if (variacao < -0.004) Paleta.baixa else Paleta.tintaSuave)
                }
            }
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            val valor = linha.valor
            if (!oculto && valor == null && Saldos.esperandoPreco(linha)) {
                Esqueleto(72.dp, 14.dp, Modifier.padding(vertical = 3.dp))
            } else {
                Text(if (oculto) "••••" else valor?.let { Formato.valor(mostrado(it), unidadeMostrada) } ?: t("sem preço"),
                     style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
            }
            Text(
                if (oculto) "••••" else Formato.cripto(linha.total, linha.casas, linha.simbolo, if (linha.estavel) Formato.EstiloCripto.estavel else Formato.EstiloCripto.lista),
                style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1,
            )
        }
    }
}

@Composable
fun SeloDeToken(texto: String, cor: androidx.compose.ui.graphics.Color = Paleta.tintaSuave) {
    Text(texto, style = estilo(Tipo.rotulo), color = cor,
         modifier = Modifier.clip(RoundedCornerShape(Raio.selo)).background(Paleta.trilho).padding(horizontal = 5.dp, vertical = 1.dp))
}

/** Tokens fora da lista e das moedas custom, sem suspeita: so com o selo de nao conferido. */
@Composable
private fun OutrosTokens(outros: List<Outro>, oculto: Boolean, unidade: String, taxa: Double?, moeda: String) {
    var aberto by remember { mutableStateOf(false) }
    val giro by animateDpAsState(if (aberto) 1.dp else 0.dp, label = "seta")
    Column(Modifier.padding(top = Espaco.lg)) {
        Row(
            Modifier.fillMaxWidth().clickable { aberto = !aberto }.heightIn(min = Altura.toque).padding(horizontal = Espaco.margem),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(t("Outros tokens"), style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.weight(1f))
            Text("${outros.size}", style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            Icone(if (giro > 0.dp) Icones.acima else Icones.abaixo, Paleta.tintaApagada, tamanho = 14.dp, modifier = Modifier.padding(start = Espaco.xs))
        }
        if (aberto) {
            Text(t("Fora da lista conferida da Escalibur. Qualquer um cria um token com qualquer nome: confira o contrato antes de confiar."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs))
            for (outro in outros) {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = Altura.linha).padding(horizontal = Espaco.margem),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    LogoDaMoeda(null, outro.simbolo, 40.dp, naoConferido = true, rede = outro.rede, redeCoingecko = Redes.rede(outro.rede)?.coingecko)
                    Column(Modifier.weight(1f)) {
                        Text(outro.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(Redes.rede(outro.rede)?.nome ?: outro.rede, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        val valor = outro.valor
                        if (valor != null) Text(if (oculto) "••••" else Formato.valor(valor * (taxa ?: 1.0), if (taxa != null) unidade else moeda),
                                                style = estilo(Tipo.linha), color = Paleta.tinta)
                        Text(if (oculto) "••••" else Formato.cripto(outro.quantidade, outro.casas, outro.simbolo), style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
                    }
                }
            }
        }
    }
}
