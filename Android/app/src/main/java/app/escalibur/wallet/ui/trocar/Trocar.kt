package app.escalibur.wallet.ui.trocar

import app.escalibur.wallet.ui.comp.OpcaoDoMenu
import app.escalibur.wallet.ui.comp.PilulaComMenu
import app.escalibur.wallet.ui.comp.Interruptor
import app.escalibur.wallet.ui.comp.Girando
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.avisos.rememberPermissaoDeNotificar
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import app.escalibur.wallet.nucleo.Eventos
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.carteira.SeloDeToken
import app.escalibur.wallet.ui.comp.Aceite
import app.escalibur.wallet.ui.comp.BotaoDeDestaque
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Chip
import app.escalibur.wallet.ui.comp.Esqueleto
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.Logos
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.Segmentado
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.comp.TituloDeAba
import app.escalibur.wallet.ui.comp.toqueDeSelecao
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.receber.CampoDeBusca
import app.escalibur.wallet.ui.receber.FluxoDeReceber
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import org.json.JSONObject

/** Os retratos que chegam por evento (montando, transmitindo) vao para o controle da tela certa. */
@Composable
private fun OuvirEventos(controle: ControleDaTroca) {
    LaunchedEffect(controle) {
        Eventos.eventos.filter { it.nome == "troca" }.collect { evento -> runCatching { controle.aplicar(JSONObject(evento.json)) } }
    }
}

/** T1 e L1: trocar agora ou por ordem limite, dentro de uma rede. A cotacao, o plano e as conferencias ficam no nucleo. */
@Composable
fun TelaDeTrocar() {
    val controle = ControleDaTroca.aba
    val dono = LocalLifecycleOwner.current
    val carteira = App.estado.carteira?.id
    var escolhendoToken by remember { mutableStateOf<Boolean?>(null) }
    var vendoRota by remember { mutableStateOf(false) }
    LaunchedEffect(carteira) { controle.chamar("troca.estado") }
    OuvirEventos(controle)
    val r = controle.retrato
    // A cotacao viva: a cada pedido novo (par, valor, tolerancia), depois de 400 ms, e de 15 em 15
    // s enquanto ele nao muda. So com a aba na tela e o app na frente; na revisao, para.
    val cotavel = r != null && r.podeCotar && r.etapa == "formulario" && !controle.naPonte
    LaunchedEffect(r?.chave, cotavel) {
        val chave = r?.chave ?: return@LaunchedEffect
        if (!cotavel) return@LaunchedEffect
        dono.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            delay(400)
            while (true) {
                controle.buscando = true
                try {
                    controle.chamar("troca.cotar", JSONObject().put("chave", chave))
                } finally {
                    controle.buscando = false
                }
                for (segundo in 15 downTo 1) {
                    controle.proxima = segundo
                    delay(1000)
                }
            }
        }
    }

    fun mudar(mudanca: JSONObject) = controle.definir(mudanca)

    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding()) {
        TituloDeAba(t("Trocar")) {
            val rede = r?.rede
            // A rede num menu preso a capsula, como o NetworkMenu do iOS.
            if (rede != null && r.redes.isNotEmpty() && !controle.naPonte) {
                PilulaComMenu(rede.nome, { SeloDaRede(rede.id, rede.coingecko, 20.dp, Color.Transparent) },
                              r.redes.map { x -> OpcaoDoMenu(x.id, x.nome) { SeloDaRede(x.id, x.coingecko, 28.dp, Color.Transparent) } },
                              rede.id, descricao = t("Rede: %@", rede.nome)) { mudar(JSONObject().put("rede", it)) }
            }
        }
        if (r == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Girando(Paleta.tintaSuave, 20.dp) }
            return
        }
        if (r.redes.isEmpty()) {
            Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Text(t("Trocas chegam numa atualização"), style = estilo(Tipo.linha), color = Paleta.tinta)
                Text(t("Enviar e receber já funcionam em todas as redes. A troca entra rede por rede, cada uma depois de passar pela validação de segurança."),
                     style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
            }
            return
        }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.lg)) {
            Segmentado(listOf("agora" to t("Imediata"), "limite" to t("Limite"), "ponte" to t("Ponte")), if (controle.naPonte) "ponte" else r.modo,
                       Modifier.fillMaxWidth().padding(top = Espaco.sm)) {
                controle.naPonte = it == "ponte"
                if (it != "ponte") mudar(JSONObject().put("modo", it))
            }
            if (r.observa) Faixa(TipoDeFaixa.neutra, t("Esta carteira só observa. Escolha outra carteira para trocar."), Modifier.padding(top = Espaco.md))
            if (controle.naPonte) {
                FormularioDaPonte()
            } else if (r.modo == "limite") {
                FormularioLimite(r, ::mudar, aoEscolherToken = { escolhendoToken = it })
                OrdensAbertas(soComOrdens = false, Modifier.padding(top = Espaco.lg))
            } else {
                FormularioAgora(controle, r, ::mudar, aoEscolherToken = { escolhendoToken = it }, aoVerRota = { vendoRota = true })
                OrdensAbertas(soComOrdens = true, Modifier.padding(top = Espaco.lg))
            }
        }
        if (controle.naPonte) RodapeDaPonte() else RodapeDaTroca(controle, r)
    }
    if (r == null) return
    escolhendoToken?.let { vende ->
        FolhaDeTokens(controle, vende, r, aoFechar = { escolhendoToken = null }) { mudar(JSONObject().put(if (vende) "vende" else "compra", it)) }
    }
    val cotacao = r.cotacao
    if (vendoRota && cotacao != null) FolhaDaRota(cotacao, aoFechar = { vendoRota = false }) { provedor ->
        mudar(JSONObject().put("rota", provedor))
        vendoRota = false
    }
}

/**
 * Editar uma ordem aberta (pedido do dono no iOS, 17/10/2026): so a ordem limite, com os valores
 * dela. Uma ordem assinada nao muda: na revisao, a atual e cancelada e a nova e criada, nesta ordem.
 */
@Composable
fun TelaDeEditarOrdem(ordem: String) {
    TelaDaOrdemPronta("edicao", t("Editar ordem"), t("Mude o que quiser. Na revisão, a ordem atual é cancelada primeiro e a nova é criada em seguida.")) {
        it.chamar("troca.editar", JSONObject().put("ordem", ordem))
    }
}

/**
 * Refazer uma ordem limite vencida: o que falta vender, no mesmo preco e no mesmo prazo. O dono
 * confere e revisa como qualquer ordem; fechar sem refazer deixa a pergunta para a proxima abertura.
 */
@Composable
fun TelaDeRefazerOrdem(ordem: String, continuar: Boolean) {
    TelaDaOrdemPronta("refazer", t("Refazer a ordem"), t("O que falta vender, no mesmo preço. Confira e siga para a revisão, como qualquer ordem."),
                      aoDesistir = { runCatching { Api.objeto("ordens.adiar", JSONObject().put("ordem", ordem)) } }) {
        it.chamar("troca.refazer", JSONObject().put("ordem", ordem).put("continuar", continuar))
    }
}

/** A ordem limite montada pelo nucleo (a editada ou a refeita), na tela propria. */
@Composable
private fun TelaDaOrdemPronta(alvo: String, titulo: String, nota: String, aoDesistir: suspend () -> Unit = {}, iniciar: suspend (ControleDaTroca) -> Boolean) {
    val controle = remember { ControleDaTroca(alvo) }
    var escolhendoToken by remember { mutableStateOf<Boolean?>(null) }
    var saiu by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        onDispose {
            controle.encerrar()
            if (!saiu) CoroutineScope(Dispatchers.IO).launch { aoDesistir() }
        }
    }
    LaunchedEffect(Unit) { if (!iniciar(controle)) Navegacao.fechar() }
    OuvirEventos(controle)
    val r = controle.retrato
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().imePadding()) {
        CabecalhoDeFolha(titulo, { Navegacao.fechar() })
        if (r == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Girando(Paleta.tintaSuave, 20.dp) }
            return
        }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.lg)) {
            Column(verticalArrangement = Arrangement.spacedBy(Espaco.xxs)) {
                r.limite?.editando?.let { Text(it, style = estilo(Tipo.linha), color = Paleta.tinta) }
                Text(nota, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            }
            FormularioLimite(r, controle::definir, aoEscolherToken = { escolhendoToken = it })
        }
        RodapeDaTroca(controle, r) {
            saiu = true
            Navegacao.fechar()
        }
    }
    if (r == null) return
    escolhendoToken?.let { vende ->
        FolhaDeTokens(controle, vende, r, aoFechar = { escolhendoToken = null }) { controle.definir(JSONObject().put(if (vende) "vende" else "compra", it)) }
    }
}

/** O botao principal: revisar, ou receber quando nao ha saldo do que se vende. */
@Composable
private fun RodapeDaTroca(controle: ControleDaTroca, r: RetratoDaTroca, aoSair: () -> Unit = {}) {
    Rodape {
        val vende = r.vende
        if (!r.temSaldo && vende != null && !r.observa) {
            BotaoDeDestaque(t("Receber %@", vende.simbolo), icone = Icones.receber) { Navegacao.folha { FluxoDeReceber(vende.id) } }
        } else {
            BotaoPrimario(r.botao, ligado = r.botaoLigado && !r.observa, carregando = controle.buscando && r.cotacao == null && r.podeCotar) {
                Navegacao.cobrir { RevisaoDaTroca(controle, aoSair = aoSair) { it.trabalhar("troca.revisar") } }
            }
        }
    }
}

// MARK: Agora

@Composable
private fun FormularioAgora(controle: ControleDaTroca, r: RetratoDaTroca, mudar: (JSONObject) -> Unit, aoEscolherToken: (Boolean) -> Unit, aoVerRota: () -> Unit) {
    val foco = LocalFocusManager.current
    // O campo guarda o que se digita; ele so copia o nucleo quando o nucleo mudou o texto por conta
    // propria (a fracao do saldo, inverter, outra rede, a troca que terminou).
    var valor by remember { mutableStateOf(r.valor) }
    var recebido by remember { mutableStateOf(r.recebido) }
    var editandoRecebido by remember { mutableStateOf(false) }
    // Qual dos dois campos o dono digitou por ultimo: decidido na hora da letra, sem esperar o
    // nucleo (senao o campo mostra o calculado por um instante e o cursor volta para o comeco).
    var exato by remember { mutableStateOf(r.recebeExato) }
    LaunchedEffect(r.versaoDoValor) { valor = r.valor }
    LaunchedEffect(r.versaoDoRecebido) { recebido = r.recebido }
    LaunchedEffect(r.versaoDoValor, r.versaoDoRecebido) { exato = r.recebeExato }
    var giros by remember { mutableIntStateOf(0) }
    val giro by animateFloatAsState(giros * 180f, tween(260), label = "inverter")

    val vende = r.vende
    val compra = r.compra
    val cotacao = r.cotacao
    // "Voce paga": o digitado, ou o que a busca achou para o recebido digitado.
    val pago = if (exato) r.entrada?.takeIf { r.recebeExato }?.let { e -> vende?.let { Formato.decimalSimples(e, it.casas) } } ?: "" else valor
    val calculado = cotacao?.garantido?.let { g -> compra?.let { Formato.decimalSimples(g, it.casas) } } ?: ""
    val recebe = when {
        exato -> recebido
        editandoRecebido -> ""
        else -> calculado
    }

    Column(Modifier.padding(top = Espaco.md), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        CaixaDeValor(
            t("Você paga"), vende, pago, "0", r.saldo, emMoeda(r, r.entrada, vende), r.passou,
            carregando = exato && (r.resolvendo || !r.recebeExato) && pago.isEmpty(), calculado = exato,
            aoDigitar = {
                valor = it
                exato = false
                mudar(JSONObject().put("valor", it))
            },
            aoEscolher = { aoEscolherToken(true) },
            aoFracao = if (r.temSaldo) ({ mudar(JSONObject().put("fracao", it)) }) else null,
        )
        Box {
            CaixaDeValor(
                t("Você recebe"), compra, recebe, if (editandoRecebido && !exato && calculado.isNotEmpty()) calculado else "0", r.saldoDaCompra,
                emMoeda(r, if (exato) compra?.let { Formato.lerQuantidade(recebido, it.casas)?.toString() } else cotacao?.garantido, compra), false,
                carregando = !exato && controle.buscando && cotacao == null && r.podeCotar, calculado = !exato,
                aoDigitar = {
                    recebido = it
                    exato = true
                    mudar(JSONObject().put("recebe", it))
                },
                aoEscolher = { aoEscolherToken(false) }, aoFracao = null,
                aoFoco = { focado ->
                    editandoRecebido = focado
                    if (!focado) mudar(JSONObject().put("saiuDoRecebe", true))
                },
            )
            Box(
                Modifier.align(Alignment.TopCenter).offset(y = (-22).dp).size(40.dp).clip(CircleShape).background(Paleta.vazio).padding(4.dp)
                    .clip(CircleShape).background(Paleta.trilho).clickable {
                        foco.clearFocus()
                        giros++
                        mudar(JSONObject().put("inverter", true))
                    },
                contentAlignment = Alignment.Center,
            ) { Icone(Icones.trocarVertical, Paleta.tinta, tamanho = 16.dp, descricao = t("Inverter"), modifier = Modifier.rotate(giro)) }
        }
    }
    r.erroDoPlano?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
    val partes = cotacao?.partes
    if (partes != null && compra != null) EscolhaDeExecucao(partes, r.emPartes) { mudar(JSONObject().put("partes", it)) }
    Tolerancia(r.tolerancia, r.automatica, r.toleranciaAuto, Modifier.padding(top = Espaco.lg)) { bps ->
        mudar(if (bps == null) JSONObject().put("automatica", true) else JSONObject().put("tolerancia", bps))
    }
    if (cotacao != null && vende != null && compra != null) {
        LinhasDaCotacao(controle, r, cotacao, mudar, aoVerRota)
    } else {
        r.erro?.let { Faixa(TipoDeFaixa.neutra, it, Modifier.padding(top = Espaco.lg)) }
    }
}

private fun emMoeda(r: RetratoDaTroca, quantidade: String?, ativo: AtivoDaTroca?): String? {
    val preco = ativo?.preco ?: return null
    return t("≈ %@", Formato.valor(Formato.numero(quantidade ?: "0", ativo.casas) * preco, r.moeda))
}

// MARK: Limite

/** L1: vender por um preco. O minimo da ordem sai do preco digitado; o recebido pode puxar o preco ou o valor. */
@Composable
private fun ColumnScope.FormularioLimite(r: RetratoDaTroca, mudar: (JSONObject) -> Unit, aoEscolherToken: (Boolean) -> Unit) {
    val limite = r.limite ?: return
    var valor by remember { mutableStateOf(r.valor) }
    var recebido by remember { mutableStateOf(r.recebido) }
    var preco by remember { mutableStateOf(limite.preco) }
    var editandoRecebido by remember { mutableStateOf(false) }
    var exato by remember { mutableStateOf(r.recebeExato) }
    LaunchedEffect(r.versaoDoValor) { valor = r.valor }
    LaunchedEffect(r.versaoDoRecebido) { recebido = r.recebido }
    LaunchedEffect(limite.versaoDoPreco) { preco = limite.preco }
    LaunchedEffect(r.versaoDoValor, r.versaoDoRecebido, limite.versaoDoPreco) { exato = r.recebeExato }
    val vende = r.vende
    val compra = r.compra
    val recebe = when {
        exato -> recebido
        editandoRecebido -> ""
        else -> limite.recebido
    }

    Column(Modifier.padding(top = Espaco.md), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        CaixaDeValor(
            t("Você vende"), vende, valor, "0", r.saldo, emMoeda(r, r.entrada, vende), r.passou, carregando = false, calculado = limite.calculado,
            aoDigitar = {
                valor = it
                exato = false
                mudar(JSONObject().put("valor", it))
            },
            aoEscolher = { aoEscolherToken(true) },
            aoFracao = if (r.temSaldo) ({ mudar(JSONObject().put("fracao", it)) }) else null,
        )
        CaixaDoPreco(limite, preco, compra?.simbolo ?: "", aoAlvo = { mudar(JSONObject().put("percentual", it)) }) {
            preco = it
            mudar(JSONObject().put("preco", it))
        }
        limite.conferencia?.let { c ->
            Column(Modifier.padding(vertical = Espaco.xs), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Text(c.texto, style = estilo(Tipo.nota), color = if (c.forte) Paleta.baixa else Paleta.tintaSuave)
                c.confirmacao?.let { rotulo -> Aceite(c.confirmado, rotulo, solto = true) { mudar(JSONObject().put("aceitarPreco", it)) } }
            }
        }
        r.erroDoPlano?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(vertical = Espaco.xs)) }
        CaixaDeValor(
            t("Você recebe"), compra, recebe, if (editandoRecebido && !exato && limite.recebido.isNotEmpty()) limite.recebido else "0", r.saldoDaCompra,
            null, false, carregando = false, calculado = !exato,
            aoDigitar = {
                recebido = it
                exato = true
                mudar(JSONObject().put("recebe", it))
            },
            aoEscolher = { aoEscolherToken(false) }, aoFracao = null,
            aoFoco = { focado ->
                editandoRecebido = focado
                if (!focado) mudar(JSONObject().put("saiuDoRecebe", true))
            },
        )
    }
    Column(Modifier.padding(top = Espaco.sm), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        if (limite.validades.isEmpty()) {
            limite.semPrazo?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaSuave) }
        } else {
            Text(t("Vale por"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                for (opcao in limite.validades) {
                    Chip(opcao.titulo, opcao.segundos == limite.validade) {
                        mudar(opcao.segundos?.let { JSONObject().put("validade", it) } ?: JSONObject().put("ateCancelar", true))
                    }
                }
            }
        }
    }
    if (limite.podeRefazer) {
        // Sem servidor e com a chave so no celular, nada assina sozinho: o app avisa e pergunta.
        val pedir = rememberPermissaoDeNotificar()
        val escopo = rememberCoroutineScope()
        Column(Modifier.padding(top = Espaco.md), verticalArrangement = Arrangement.spacedBy(Espaco.xxs)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(t("Refazer quando vencer"), style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.weight(1f))
                Interruptor(limite.refazer, { novo ->
                    mudar(JSONObject().put("refazer", novo))
                    if (novo) escopo.launch { pedir() }
                }, cor = Paleta.acento)
            }
            Text(t("Quando o prazo acabar, o celular avisa e o app pergunta se refaz com o mesmo preço. Refazer pede a sua biometria ou o PIN: sem você, ninguém assina uma ordem nova com a sua chave."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
    }
    limite.custodia?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.sm)) }
}

/** "Quando 1 XRP valer": o preco-alvo, com o de agora e os degraus acima dele. */
@Composable
private fun CaixaDoPreco(limite: RetratoDaTroca.Limite, preco: String, simbolo: String, aoAlvo: (Int) -> Unit, aoDigitar: (String) -> Unit) {
    val forma = RoundedCornerShape(Raio.cartao)
    Column(
        Modifier.fillMaxWidth().clip(forma).background(Paleta.corpo).border(1.dp, Paleta.borda, forma).padding(Espaco.md),
        verticalArrangement = Arrangement.spacedBy(Espaco.xs),
    ) {
        Text(limite.rotuloDoPreco, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            val estiloDoPreco = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum", color = Paleta.tinta)
            Box(Modifier.weight(1f)) {
                if (preco.isEmpty()) Text("0", style = estiloDoPreco.copy(color = Paleta.tintaMorta))
                CampoDeNumero(preco, estiloDoPreco, Modifier.fillMaxWidth(), aoDigitar)
            }
            Text(simbolo, style = estilo(Tipo.acao), color = Paleta.tintaSuave)
        }
        limite.precoCompacto?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaSuave) }
        Row(horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            for (percentual in listOf(0, 5, 10, 20)) {
                Chip(if (percentual == 0) t("Atual") else "+$percentual%", false) { aoAlvo(percentual) }
            }
        }
    }
}
