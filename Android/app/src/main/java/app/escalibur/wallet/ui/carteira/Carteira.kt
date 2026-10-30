package app.escalibur.wallet.ui.carteira

import app.escalibur.wallet.ui.comp.veuDePixels
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.blur
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.em
import app.escalibur.wallet.ui.comp.CorDoLogo
import app.escalibur.wallet.ui.comp.TextoNumerico
import app.escalibur.wallet.ui.tema.Letra
import kotlin.math.roundToInt
import app.escalibur.wallet.ui.comp.PuxarParaAtualizar
import app.escalibur.wallet.ui.comp.Girando
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
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.App
import kotlinx.coroutines.delay
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
    val contextoDoRoot = LocalContext.current
    val comRoot = remember { app.escalibur.wallet.ui.novacarteira.Checagem.pareceTerRoot(contextoDoRoot) }
    val carteira = estado.carteira ?: return
    val retrato = Saldos.retrato
    val ocultar = App.ocultarSaldos
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
    PuxarParaAtualizar(
        atualizando = puxando,
        aoAtualizar = {
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
                        // A tela anima ja; o nucleo grava depois da animacao (como o iOS).
                        val novo = !ocultar
                        App.ocultarJa = novo
                        escopo.launch {
                            delay(600)
                            runCatching { App.aplicar(Api.objeto("ajustes.ocultarSaldos", JSONObject().put("ocultar", novo))) }
                            if (App.ocultarJa == novo) App.ocultarJa = null
                        }
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
                // A de so observar nao recebe por aqui: sem a chave, o que chega nao sai pelo app.
                if (!carteira.observacao) {
                    AcaoRapida(t("Receber"), Icones.receber, Modifier.weight(1f)) { Navegacao.folha { FluxoDeReceber() } }
                    AcaoRapida(t("Trocar"), Icones.trocar, Modifier.weight(1f)) { Navegacao.aba = Aba.trocar }
                }
            }

            // Super Security com "Esperar 24 horas": a biometria mudou, e so o saldo vale ate a espera acabar.
            if (estado.espera > 0) {
                Faixa(TipoDeFaixa.cautela, app.escalibur.wallet.ui.ajustes.mensagemDaEspera(estado.espera),
                      Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg))
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
            if (comRoot) {
                Faixa(TipoDeFaixa.cautela, t("Este celular parece ter root"),
                      Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg),
                      mensagem = t("Com root, outros apps podem ler o que este app guarda. Para valor alto, prefira uma carteira de hardware."))
            }

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

/**
 * O saldo grande: o simbolo menor e mais claro, o inteiro em peso, as casas menores e mais claras, na
 * mesma linha de base. Os digitos rolam quando o valor muda, como no iOS.
 */
@Composable
fun NumeroDoSaldo(valor: Double, unidade: String, oculto: Boolean, modifier: Modifier = Modifier) {
    val casas = if (unidade == "btc") 8 else 2
    val simbolo = Formato.simboloDaMoeda(unidade)
    val antes = Formato.dinheiro("X", simbolo).startsWith(simbolo)
    val doSimbolo = TextStyle(fontFamily = Letra.familia(FontWeight.SemiBold, 24f), fontWeight = FontWeight.SemiBold, fontSize = 24.sp,
                              letterSpacing = Letra.espacoNatural(24f).em)
    val dasCasas = estilo(Tipo.vitrine).copy(fontSize = if (casas > 2) 22.sp else 28.sp, fontFamily = Letra.familia(FontWeight.Bold, if (casas > 2) 22f else 28f),
                                            letterSpacing = Letra.espacoNatural(28f).em)
    @Composable fun Simbolo(alinhado: Modifier) {
        AnimatedContent(simbolo, transitionSpec = { fadeIn(tween(150)) togetherWith fadeOut(tween(150)) }, modifier = alinhado, label = "simbolo") {
            Text(it, style = doSimbolo, color = Paleta.tintaSuave, maxLines = 1)
        }
    }
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (antes) Simbolo(Modifier.alignByBaseline())
        // Ocultar e mostrar em pixels (como o iOS, 24/10/2026): o numero se cifra numa frente de pixels e
        // os pontos entram um a um; ao mostrar, os pontos saem, os pixels cobrem o lugar e a frente os
        // leva da esquerda para a direita, descobrindo o numero. Com o movimento reduzido, na hora.
        val parado = app.escalibur.wallet.ui.comp.movimentoReduzido()
        val progresso by animateFloatAsState(if (oculto) 1f else 0f, if (parado) snap() else tween(700, easing = LinearEasing), label = "ocultar")
        Box(Modifier.alignByBaseline()) {
            if (progresso < 1f) {
                val partes = Formato.agrupado(valor, casas, aparar = unidade == "btc").split(Formato.decimal)
                Row(Modifier.veuDePixels(progresso, revelando = !oculto)) {
                    TextoNumerico(partes[0], estilo(Tipo.vitrine), Paleta.tinta, Modifier.alignByBaseline(), valor)
                    TextoNumerico(Formato.decimal + (partes.getOrNull(1) ?: "0".repeat(casas)), dasCasas, Paleta.tintaSuave, Modifier.alignByBaseline(), valor)
                }
            }
            if (progresso > 0f) Row {
                repeat(6) { i ->
                    // Ocultando, os pontos entram quando os pixels se apagam; mostrando, saem logo.
                    val ponto = if (oculto) ((progresso - 0.62f - i * 0.05f) / 0.2f).coerceIn(0f, 1f)
                                else ((progresso - 0.8f) / 0.2f).coerceIn(0f, 1f)
                    val salto = app.escalibur.wallet.ui.comp.saltoDeSaida(ponto)
                    Text("•", style = estilo(Tipo.vitrine), color = Paleta.tinta,
                         modifier = Modifier.graphicsLayer { alpha = ponto; scaleX = 0.3f + 0.7f * salto; scaleY = scaleX })
                }
            }
        }
        if (!antes) Simbolo(Modifier.alignByBaseline())
    }
}

@Composable
private fun LinhaDaVariacao(variacao: Double, retrato: Retrato, unidade: String, oculto: Boolean, modifier: Modifier) {
    AoOcultar(oculto, modifier, alinhamento = Alignment.TopStart) { LinhaDaVariacaoAgora(variacao, retrato, unidade, it, Modifier) }
}

@Composable
private fun LinhaDaVariacaoAgora(variacao: Double, retrato: Retrato, unidade: String, oculto: Boolean, modifier: Modifier) {
    if (oculto || retrato.total == 0.0) {
        Text(" ", style = estilo(Tipo.linha), modifier = modifier)
        return
    }
    val cor = when {
        retrato.variacao24h > 0 -> Paleta.alta
        retrato.variacao24h < 0 -> Paleta.baixa
        else -> Paleta.tintaSuave
    }
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        TextoNumerico("${Formato.valor(variacao, unidade, comSinal = true)} (${Formato.percentual(retrato.variacao24hPct)})", estilo(Tipo.linha), cor,
                      Modifier.alignByBaseline(), variacao)
        Text(if (retrato.falhas.isEmpty()) "24h" else t("24h, sem %@", retrato.falhas.joinToString(", ")), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
             modifier = Modifier.alignByBaseline())
    }
}

/** R$, US$, €, ₿: em que unidade o total aparece. Capsulas pequenas, a escolhida preenchida, e a marca desliza ate ela. */
@Composable
private fun SeletorDeUnidade(escolhida: String, unidades: List<String>, aoEscolher: (String) -> Unit) {
    val toque = toqueDeSelecao()
    val lugares = remember { mutableStateMapOf<String, Pair<Float, Float>>() }
    val x = remember { Animatable(0f) }
    val largura = remember { Animatable(0f) }
    var primeira by remember { mutableStateOf(true) }
    LaunchedEffect(escolhida, lugares[escolhida]) {
        val (alvoX, alvoL) = lugares[escolhida] ?: return@LaunchedEffect
        // O snappy do iOS: rapido, com um balanco pequeno.
        val mola = spring<Float>(dampingRatio = 0.85f, stiffness = 815f)
        if (primeira) { x.snapTo(alvoX); largura.snapTo(alvoL); primeira = false }
        else { launch { x.animateTo(alvoX, mola) }; largura.animateTo(alvoL, mola) }
    }
    Box(Modifier.clip(CircleShape).background(Paleta.corpo).padding(2.dp)) {
        if (lugares[escolhida] != null) {
            Box(Modifier.offset { IntOffset(x.value.roundToInt(), 0) }.width(with(LocalDensity.current) { largura.value.toDp() }).height(28.dp)
                    .clip(CircleShape).background(Paleta.controle))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            for (unidade in unidades) {
                val selecionada = unidade == escolhida
                Box(
                    Modifier.heightIn(min = 28.dp).clip(CircleShape)
                        .onGloballyPositioned { lugares[unidade] = it.positionInParent().x to it.size.width.toFloat() }
                        .clickable { if (!selecionada) { toque(); aoEscolher(unidade) } }
                        .padding(horizontal = 10.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    val cor by animateColorAsState(if (selecionada) Paleta.tinta else Paleta.tintaApagada, tween(220), label = "unidade")
                    Text(Formato.simboloDaMoeda(unidade), style = estilo(Tipo.rotulo), color = cor)
                }
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
                Girando(Paleta.tintaApagada, 16.dp, Modifier.padding(start = Espaco.xs))
            }
            Spacer(Modifier.weight(1f))
            Box(Modifier.heightIn(min = Altura.toque).clickable { Navegacao.abrir { TelaDeGerenciarAtivos() } }, contentAlignment = Alignment.Center) {
                Text(t("Gerenciar"), style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
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
        if (retrato.outros.isNotEmpty() || retrato.suspeitos.isNotEmpty()) {
            OutrosTokens(retrato.outros, retrato.suspeitos, oculto, retrato.moeda, Modifier.padding(top = if (retrato.linhas.isEmpty()) Espaco.md else Espaco.lg))
        }
    }
    // A distribuicao vem depois da lista: primeiro o que a carteira tem, depois como isso se divide.
    if (retrato.linhas.size >= 2) {
        Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xl), verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
            Text(t("Distribuição"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
            Distribuicao(retrato.linhas, oculto)
        }
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
        if (App.estado.carteira?.observacao != true) {
            BotaoSecundario(t("Receber"), Modifier.padding(top = Espaco.md)) { Navegacao.folha { FluxoDeReceber() } }
        }
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
                if (linha.custom) SeloDeToken(TipoDeSelo.custom)
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
        AoOcultar(oculto) { oculto ->
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
}

/** O selo de um token que nao e da lista conferida, com a cor so no suspeito (o `TokenBadge` do iOS). */
enum class TipoDeSelo { custom, naoVerificado, suspeito }

@Composable
fun SeloDeToken(tipo: TipoDeSelo) {
    val (titulo, cor, fundo) = when (tipo) {
        TipoDeSelo.custom -> Triple(t("Custom"), Paleta.tinta, Paleta.controle)
        TipoDeSelo.naoVerificado -> Triple(t("Não verificado"), Paleta.tintaSuave, Paleta.trilho)
        TipoDeSelo.suspeito -> Triple(t("Suspeito"), Paleta.cautela, Paleta.cautelaFundo)
    }
    Box(Modifier.height(Altura.selo).clip(RoundedCornerShape(Raio.selo)).background(fundo).padding(horizontal = 6.dp), contentAlignment = Alignment.Center) {
        Text(titulo, style = estilo(Tipo.rotulo), color = cor, maxLines = 1, softWrap = false)
    }
}

/**
 * "Outros tokens" na Carteira: o que a conta tem e nao esta na lista conferida nem nas moedas custom.
 * Aparece, marcado, sem preco inventado, fechado de inicio, com a contagem; os de cara de golpe ficam
 * atras de "Mostrar suspeitos".
 */
@Composable
private fun OutrosTokens(outros: List<Outro>, suspeitos: List<Outro>, oculto: Boolean, moeda: String, modifier: Modifier = Modifier) {
    var abertos by remember { mutableStateOf(false) }
    var mostrandoSuspeitos by remember { mutableStateOf(false) }
    Column(modifier.animateContentSize(spring(dampingRatio = 1f, stiffness = 800f))) {
        if (outros.isNotEmpty()) {
            Row(
                Modifier.fillMaxWidth().clickable { abertos = !abertos }.heightIn(min = Altura.toque).padding(horizontal = Espaco.margem),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs),
            ) {
                Text(t("Outros tokens"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
                Box(Modifier.heightIn(min = 22.dp).clip(CircleShape).background(Paleta.controle).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
                    Text("${outros.size}", style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                }
                Spacer(Modifier.weight(1f))
                Icone(if (abertos) Icones.acima else Icones.abaixo, Paleta.tintaApagada, tamanho = 13.dp)
            }
            if (abertos) {
                Text(t("Fora da lista verificada. Sem preço confiável, ficam fora do saldo total."), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
                     modifier = Modifier.padding(horizontal = Espaco.margem))
                Column(Modifier.padding(top = Espaco.xs)) { for (outro in outros) LinhaDeOutroToken(outro, oculto, moeda) }
            }
        }
        if (suspeitos.isNotEmpty()) {
            Row(
                Modifier.padding(top = if (outros.isEmpty()) 0.dp else Espaco.sm).fillMaxWidth().clickable { mostrandoSuspeitos = !mostrandoSuspeitos }
                    .heightIn(min = Altura.toque).padding(horizontal = Espaco.margem),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs),
            ) {
                Box(Modifier.size(28.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                    Icone(if (mostrandoSuspeitos) Icones.olhoRiscado else Icones.alertaContorno, Paleta.tinta, tamanho = 15.dp)
                }
                Text(if (mostrandoSuspeitos) t("Esconder suspeitos") else t("Mostrar suspeitos (%lld)", suspeitos.size), style = estilo(Tipo.corpo),
                     color = Paleta.tintaSuave, modifier = Modifier.weight(1f))
                Icone(if (mostrandoSuspeitos) Icones.acima else Icones.abaixo, Paleta.tintaApagada, tamanho = 13.dp)
            }
            if (mostrandoSuspeitos) {
                Text(t("Chegaram sem você pedir e têm cara de golpe. Não abra os sites dos nomes."), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
                     modifier = Modifier.padding(horizontal = Espaco.margem).padding(bottom = Espaco.xxs))
                for (outro in suspeitos) LinhaDeOutroToken(outro, oculto, moeda)
            }
        }
    }
}

/** Uma linha de token fora da lista: logo neutro, simbolo limpo, selo, rede e valor so com preco por contrato. O toque abre a pagina dele. */
@Composable
private fun LinhaDeOutroToken(outro: Outro, oculto: Boolean, moeda: String) {
    Row(
        Modifier.fillMaxWidth().clickable { Navegacao.abrir { DetalheDoOutroToken(outro.id) } }.heightIn(min = Altura.linha).padding(horizontal = Espaco.margem),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        LogoDaMoeda(null, outro.simbolo, 40.dp, naoConferido = true, rede = outro.rede, redeCoingecko = Redes.rede(outro.rede)?.coingecko)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(outro.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                SeloDeToken(if (outro.suspeito) TipoDeSelo.suspeito else TipoDeSelo.naoVerificado)
                Text(t("na %@", Redes.rede(outro.rede)?.nome ?: outro.rede), style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
            }
        }
        AoOcultar(oculto) { oculto ->
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            val valor = outro.valor
            when {
                oculto -> Text("R$ ••••••", style = estilo(Tipo.linha), color = Paleta.tinta)
                valor != null -> Text(Formato.valor(valor, moeda), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                else -> Text(t("sem preço"), style = estilo(Tipo.nota), color = Paleta.tintaApagada, maxLines = 1)
            }
            Text(if (oculto) "••••" else Formato.cripto(outro.quantidade, outro.casas, null), style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
        }
        }
    }
}

/**
 * Onde esta o saldo: uma rosca com a fatia de cada ativo na cor do proprio logo, e a legenda ao lado
 * com a porcentagem. Os cinco maiores aparecem por nome; o resto vira "Outros". Tocar numa fatia
 * destaca o ativo no centro.
 */
@Composable
private fun Distribuicao(linhas: List<Linha>, oculto: Boolean) {
    val contexto = LocalContext.current
    data class Fatia(val id: String, val simbolo: String, val valor: Double, val cor: Color)
    // A fatia menor que 1% do total entra em "Outros", e cada fatia desenhada ocupa pelo menos 2% da
    // volta (a legenda mostra a porcentagem real), como no iOS: la uma fatia de bilionesimos (a BNB
    // Frog Inu) derrubava o grafico na troca de moeda.
    val fatias = remember(linhas) {
        val comValor = linhas.mapNotNull { l -> l.valor?.takeIf { it.isFinite() && it > 0 }?.let { Fatia(l.id, l.simbolo, it, CorDoLogo.de(contexto, l.coingecko)) } }
            .sortedByDescending { it.valor }
        val soma = comValor.sumOf { it.valor }
        if (!soma.isFinite() || soma <= 0) return@remember emptyList()
        val grandes = comValor.filter { it.valor / soma >= 0.01 }
        val nomeadas = grandes.take(if (comValor.size > grandes.size || grandes.size > 6) 5 else 6)
        val resto = comValor.drop(nomeadas.size).sumOf { it.valor }
        if (resto > 0) nomeadas + Fatia("outros", t("Outros"), resto, Paleta.tintaMorta) else nomeadas
    }
    val total = fatias.sumOf { it.valor }
    if (fatias.size < 2 || total <= 0) return
    fun desenhado(f: Fatia) = maxOf(f.valor, total * 0.02)
    val totalDesenhado = fatias.sumOf { desenhado(it) }
    var escolhida by remember { mutableStateOf<String?>(null) }
    val toque = toqueDeSelecao()
    fun porcento(parte: Double): String {
        val v = parte * 100
        return if (v < 0.1) "< 0,1%" else Formato.agrupado(v, if (v < 10) 1 else 0, aparar = true) + "%"
    }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.lg)) {
        Box(Modifier.size(132.dp).pointerInput(fatias) {
            detectTapGestures { p ->
                val c = Offset(size.width / 2f, size.height / 2f)
                val d = (p - c).getDistance()
                if (d < size.width / 2f * 0.6f || d > size.width / 2f) { escolhida = null; return@detectTapGestures }
                var angulo = Math.toDegrees(kotlin.math.atan2((p.y - c.y).toDouble(), (p.x - c.x).toDouble())) + 90
                if (angulo < 0) angulo += 360
                var corrido = 0.0
                val alvo = fatias.firstOrNull { corrido += desenhado(it) / totalDesenhado * 360; angulo <= corrido }?.id
                escolhida = if (escolhida == alvo) null else alvo
                toque()
            }
        }, contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                var inicio = -90f
                val raio = size.minDimension / 2
                for (f in fatias) {
                    val varre = (desenhado(f) / totalDesenhado * 360).toFloat()
                    val fora = raio * (if (escolhida == f.id) 1f else 0.94f)
                    val dentro = raio * 0.64f
                    val espessura = fora - dentro
                    val meio = dentro + espessura / 2
                    drawArc(
                        f.cor.copy(alpha = if (escolhida == null || escolhida == f.id) 1f else 0.35f),
                        inicio + 0.75f, (varre - 1.5f).coerceAtLeast(0.5f), false,
                        topLeft = Offset(center.x - meio, center.y - meio), size = Size(meio * 2, meio * 2), style = Stroke(espessura),
                    )
                    inicio += varre
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                val f = fatias.firstOrNull { it.id == escolhida }
                if (f != null) {
                    Text(f.simbolo, style = estilo(Tipo.rotulo), color = Paleta.tintaSuave)
                    AoOcultar(oculto, alinhamento = Alignment.Center) { Text(if (it) "••" else porcento(f.valor / total), style = estilo(Tipo.linha), color = Paleta.tinta) }
                } else {
                    Text("${linhas.size}", style = estilo(Tipo.linha), color = Paleta.tinta)
                    Text(if (linhas.size == 1) t("ativo") else t("ativos"), style = estilo(Tipo.rotulo), color = Paleta.tintaSuave)
                }
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            for (f in fatias) {
                Row(Modifier.alpha(if (escolhida == null || escolhida == f.id) 1f else 0.4f), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Box(Modifier.size(8.dp).clip(CircleShape).background(f.cor))
                    Text(f.simbolo, style = estilo(Tipo.nota), color = Paleta.tinta, maxLines = 1, modifier = Modifier.weight(1f))
                    AoOcultar(oculto) { Text(if (it) "••" else porcento(f.valor / total), style = estilo(Tipo.nota).copy(fontFeatureSettings = "tnum"), color = Paleta.tintaSuave) }
                }
            }
        }
    }
}

/** O valor que se esconde e volta: o texto sai e os pontos entram (e o contrario), sem corte seco. */
@Composable
private fun AoOcultar(oculto: Boolean, modifier: Modifier = Modifier, alinhamento: Alignment = Alignment.TopEnd, conteudo: @Composable (Boolean) -> Unit) {
    androidx.compose.animation.AnimatedContent(
        oculto, modifier, contentAlignment = alinhamento, label = "ocultar",
        transitionSpec = {
            (fadeIn(tween(260, delayMillis = 120)) + androidx.compose.animation.scaleIn(tween(260, delayMillis = 120), initialScale = 0.85f)) togetherWith
                (fadeOut(tween(180)) + androidx.compose.animation.scaleOut(tween(180), targetScale = 1.04f)) using
                androidx.compose.animation.SizeTransform(clip = false)
        },
    ) { conteudo(it) }
}
