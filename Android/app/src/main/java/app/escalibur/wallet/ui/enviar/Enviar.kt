package app.escalibur.wallet.ui.enviar

import app.escalibur.wallet.ui.comp.PlacaLaqueada
import app.escalibur.wallet.ui.carteira.TipoDeSelo
import app.escalibur.wallet.ui.comp.Girando
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.Eventos
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.carteira.SeloDeToken
import app.escalibur.wallet.ui.comp.Aceite
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Confirmacao
import app.escalibur.wallet.ui.comp.EnderecoEmBlocos
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.receber.CampoDeBusca
import app.escalibur.wallet.ui.receber.FluxoDeReceber
import app.escalibur.wallet.ui.receber.opcional
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
import java.math.BigInteger
import java.util.Date

/** Uma linha da escolha: um ativo numa rede, porque todo envio acontece numa rede. */
private class AtivoParaEnviar(j: JSONObject) {
    val id: String = j.getString("id")
    val simbolo: String = j.getString("simbolo")
    val rede: String = j.getString("rede")
    val redeNome: String = j.getString("redeNome")
    val redeCoingecko: String = j.getString("redeCoingecko")
    val coingecko: String? = j.opcional("coingecko")
    val casas: Int = j.getInt("casas")
    val custom: Boolean = j.getBoolean("custom")
    val conferido: Boolean = j.getBoolean("conferido")
    val disponivel: String = j.getString("disponivel")
    val valor: Double? = if (j.has("valor")) j.getDouble("valor") else null
    val indisponivel: String? = j.opcional("indisponivel")
}

/** Enviar, em tela cheia: a escolha do ativo e as etapas. Transmitindo, nao fecha. */
@Composable
fun FluxoDeEnviar(ativo: String?) {
    val controle = remember { ControleDoEnvio() }
    var escolhido by remember { mutableStateOf(ativo) }
    var recusa by remember { mutableStateOf<Pair<String, String>?>(null) }
    DisposableEffect(Unit) { onDispose { controle.encerrar() } }
    LaunchedEffect(Unit) {
        Eventos.eventos.filter { it.nome == "envio" }.collect { evento -> runCatching { controle.aplicar(JSONObject(evento.json)) } }
    }
    LaunchedEffect(escolhido) {
        val id = escolhido ?: return@LaunchedEffect
        val falha = controle.iniciar(id) ?: return@LaunchedEffect
        val motivo = falha.codigo.removePrefix("envio.indisponivel:")
        recusa = t("Envio indisponível") to
            if (motivo != falha.codigo) motivo else t("O saldo deste ativo ainda não foi lido. Atualize a carteira e tente de novo.")
        if (ativo != null) Navegacao.fechar() else escolhido = null
    }
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().imePadding()) {
        val retrato = controle.retrato
        when {
            escolhido == null -> EscolhaDoAtivo(aoBloquear = { simbolo, motivo -> recusa = t("Envio de %@ indisponível", simbolo) to motivo }) { escolhido = it }
            retrato == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Girando(Paleta.tintaSuave, 20.dp)
            }
            else -> Etapas(controle, retrato, voltarParaEscolha = if (ativo == null) ({ controle.encerrar(); escolhido = null }) else null)
        }
    }
    recusa?.let { (titulo, mensagem) ->
        Confirmacao(titulo, mensagem, t("Entendi"), aoConfirmar = { recusa = null }, aoCancelar = { recusa = null }, destrutiva = false, soUmBotao = true)
    }
}

// MARK: E1 Escolha

@Composable
private fun ColumnScope.EscolhaDoAtivo(aoBloquear: (String, String) -> Unit, aoEscolher: (String) -> Unit) {
    var ativos by remember { mutableStateOf<List<AtivoParaEnviar>?>(null) }
    var busca by remember { mutableStateOf("") }
    val unidade = App.estado.moeda
    LaunchedEffect(Unit) {
        ativos = runCatching { Api.lista("envio.ativos").objetos().map(::AtivoParaEnviar) }.getOrDefault(emptyList())
    }
    CabecalhoDeFolha("", { Navegacao.fechar() })
    val lista = ativos ?: return
    if (lista.isEmpty()) {
        Column(Modifier.weight(1f).fillMaxWidth().padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            Box(Modifier.size(96.dp).clip(CircleShape).background(Paleta.corpo), contentAlignment = Alignment.Center) {
                Icone(Icones.enviar, Paleta.tintaApagada, tamanho = 36.dp)
            }
            Text(t("Ainda não há ativos para enviar"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                 modifier = Modifier.padding(top = Espaco.lg))
            Text(t("Quando chegar saldo nesta carteira, ele aparece aqui para você escolher o que enviar."), style = estilo(Tipo.corpo),
                 color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm))
            Spacer(Modifier.weight(1f))
            BotaoPrimario(t("Receber")) {
                Navegacao.fechar()
                Navegacao.folha { FluxoDeReceber() }
            }
        }
        return
    }
    val termo = busca.trim()
    val filtrados = if (termo.isEmpty()) lista else lista.filter { it.simbolo.contains(termo, true) }
    Text(t("Escolha o que enviar"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(horizontal = Espaco.margem))
    CampoDeBusca(busca, t("Buscar"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md)) { busca = it }
    LazyColumn(Modifier.weight(1f).fillMaxWidth().padding(top = Espaco.xs)) {
        items(filtrados, key = { it.id }) { item ->
            Row(
                Modifier.fillMaxWidth().clickable { item.indisponivel?.let { aoBloquear(item.simbolo, it) } ?: aoEscolher(item.id) }
                    .heightIn(min = Altura.linha).padding(horizontal = Espaco.margem),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
            ) {
                LogoDaMoeda(item.coingecko, item.simbolo, 40.dp, rede = item.rede, redeCoingecko = item.redeCoingecko, naoConferido = !item.conferido)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(item.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta)
                        if (item.custom) SeloDeToken(TipoDeSelo.custom)
                    }
                    Text(
                        if (item.indisponivel == null) t("na %@ · %@", item.redeNome, Formato.cripto(item.disponivel, item.casas))
                        else t("na %@ · envio indisponível", item.redeNome),
                        style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1,
                    )
                }
                item.valor?.let { Text(Formato.valor(it, unidade), style = estilo(Tipo.nota), color = Paleta.tintaSuave) }
            }
        }
    }
}

// MARK: As etapas

@Composable
private fun ColumnScope.Etapas(controle: ControleDoEnvio, r: RetratoDoEnvio, voltarParaEscolha: (() -> Unit)?) {
    val escopo = rememberCoroutineScope()
    val enviando = r.etapa == "enviando"
    fun para(etapa: String) { escopo.launch { controle.chamar("envio.voltar", JSONObject().put("etapa", etapa)) } }
    val voltar: (() -> Unit)? = when (r.etapa) {
        "tag" -> ({ para("destino") })
        "valor" -> ({ para(if (r.precisaEtapaDaTag && r.tagDoEndereco == null) "tag" else "destino") })
        "revisao" -> ({ para("valor") })
        "destino" -> voltarParaEscolha
        else -> null
    }
    BackHandler(enabled = !enviando) { voltar?.invoke() ?: Navegacao.fechar() }
    // Como no iOS, so o fechar no alto; o voltar do sistema volta uma etapa.
    CabecalhoDeFolha("", if (enviando) null else ({ Navegacao.fechar() }))
    Column(Modifier.weight(1f).fillMaxWidth().padding(horizontal = Espaco.margem).padding(top = Espaco.md, bottom = Espaco.xs)) {
        when (r.etapa) {
            "destino" -> EtapaDoDestino(controle, r)
            "tag" -> EtapaDaTag(controle, r)
            "valor" -> EtapaDoValor(controle, r)
            "revisao" -> EtapaDaRevisao(controle, r)
            "enviando", "enviado" -> EtapaDoStatus(controle, r)
            "incerto" -> EtapaIncerta(controle, r)
        }
    }
}

@Composable
private fun Cabecalho(r: RetratoDoEnvio) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        LogoDaMoeda(r.coingecko, r.simbolo, 32.dp, rede = r.rede, redeCoingecko = r.redeCoingecko, naoConferido = !r.conferido)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(t("Enviar %@", r.simbolo), style = estilo(Tipo.titulo), color = Paleta.tinta)
                if (r.custom) SeloDeToken(TipoDeSelo.custom)
            }
            Text(t("pela rede %@", r.redeNome), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
    }
}

// MARK: E2 Para

@Composable
private fun ColumnScope.EtapaDoDestino(controle: ControleDoEnvio, r: RetratoDoEnvio) {
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    var texto by remember { mutableStateOf(r.textoDoDestino) }
    var envios by remember { mutableIntStateOf(0) }
    var carteiras by remember { mutableStateOf(false) }
    var tag by remember { mutableStateOf(r.tag) }
    var conferenciaDoParecido by remember(r.destino) { mutableStateOf("") }
    var conferenciaDoOutroID by remember(r.destino) { mutableStateOf("") }
    var conferenciaCega by remember(r.destino) { mutableStateOf("") }

    // A ultima mudanca do destino manda: o campo segue o nucleo quando ele apaga o texto (a frase
    // colada por engano sai na hora) ou quando o link trouxe outro endereco.
    fun mudar(metodo: String, corpo: JSONObject, novo: String? = null) {
        if (novo != null) texto = novo
        val n = ++envios
        escopo.launch {
            controle.chamar(metodo, corpo)
            if (n == envios) controle.retrato?.let { atual ->
                if (atual.textoDoDestino != texto) texto = atual.textoDoDestino
                tag = atual.tag
            }
        }
    }
    fun conferir(campo: String, valor: Any) { escopo.launch { controle.chamar("envio.conferir", JSONObject().put(campo, valor)) } }

    // Para quem a carteira ja pagou nesta rede: sem a leitura, o Continuar espera.
    LaunchedEffect(r.rede) { controle.chamar("envio.historico") }

    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = Espaco.lg)) {
        Cabecalho(r)
        Text(t("Para"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.lg))
        if (r.desafio) {
            CampoEscondido(Modifier.padding(top = Espaco.xs)) {
                conferenciaDoParecido = ""
                conferenciaDoOutroID = ""
                conferenciaCega = ""
                mudar("envio.editarDestino", JSONObject(), "")
            }
        } else {
            Box(
                Modifier.padding(top = Espaco.xs).fillMaxWidth().heightIn(min = Altura.campo)
                    .background(Paleta.corpo, RoundedCornerShape(Raio.cartao)).border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao))
                    .padding(Espaco.md),
            ) {
                if (texto.isEmpty()) Text(t("Endereço"), style = estilo(Tipo.mono), color = Paleta.tintaMorta)
                BasicTextField(
                    texto, { novo -> mudar("envio.destino", JSONObject().put("texto", novo), novo) },
                    textStyle = estilo(Tipo.mono).copy(color = Paleta.tinta), cursorBrush = SolidColor(Paleta.acento), maxLines = 3,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = KeyboardType.Ascii),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Row(Modifier.padding(top = Espaco.xs), horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                // O colar do iOS: so o texto, apagado quando nao ha nada para colar.
                val temTexto = remember { contexto.getSystemService(ClipboardManager::class.java).hasPrimaryClip() }
                Pilula(t("Colar"), null, ligado = temTexto) {
                    val gerente = contexto.getSystemService(ClipboardManager::class.java)
                    val colado = runCatching { gerente.primaryClip?.getItemAt(0)?.coerceToText(contexto)?.toString() }.getOrNull().orEmpty()
                    if (colado.isNotEmpty()) mudar("envio.link", JSONObject().put("texto", colado))
                }
                Pilula(t("Ler QR"), Icones.qr) {
                    Navegacao.folha {
                        LeitorDeQR(aoFechar = { Navegacao.fechar() }) { lido ->
                            Navegacao.fechar()
                            mudar("envio.link", JSONObject().put("texto", lido))
                        }
                    }
                }
                if (r.variasCarteiras) Pilula(t("Minhas carteiras"), Icones.carteira) { carteiras = true }
            }
        }

        LinhaDaValidacao(r) { sugestao -> mudar("envio.trocarRede", JSONObject().put("ativo", sugestao)) }
        TagOpcional(r, tag) { novo ->
            tag = novo
            conferir("tag", novo)
        }

        val destino = r.destino
        val parecido = r.parecido
        if (parecido != null && destino != null) {
            Faixa(TipoDeFaixa.cautela, t("Endereço parecido com um que você já usou"), Modifier.padding(top = Espaco.md),
                  mensagem = t("As pontas são iguais, o meio é diferente. Golpistas mandam centavos de um endereço assim para ele aparecer no seu histórico."))
            Column(Modifier.padding(top = Espaco.sm), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                EnderecoMarcado(t("Você colou"), destino, parecido.trechoColado)
                EnderecoMarcado(parecido.rotulo, parecido.conhecido, parecido.trechoConhecido)
            }
            Text(t("Para seguir, digite os 6 caracteres marcados do endereço que você colou."), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
                 modifier = Modifier.padding(top = Espaco.sm))
            CampoCurto(conferenciaDoParecido, t("6 marcados"), Modifier.padding(top = Espaco.xs)) {
                conferenciaDoParecido = it
                conferir("parecido", it)
            }
        }

        val outro = r.outroID
        if (outro != null && destino != null) {
            Faixa(TipoDeFaixa.cautela, t("Mesma conta de um endereço que você já usou, com outro ID"), Modifier.padding(top = Espaco.md),
                  mensagem = t("Confira o ID com quem vai receber."))
            Column(Modifier.padding(top = Espaco.sm), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                EnderecoMarcado(t("Você colou"), destino, outro.trechoColado, escondido = true)
                EnderecoMarcado(t("%@ · ID %@", outro.rotulo, outro.idConhecido), outro.conhecido, outro.trechoConhecido)
            }
            Text(t("Para seguir, digite o número do ID que quem vai receber mostra, ou os 6 últimos caracteres do endereço, lendo onde você o copiou."),
                 style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
            CampoCurto(conferenciaDoOutroID, t("Número do ID"), Modifier.padding(top = Espaco.xs), largura = 220.dp) {
                conferenciaDoOutroID = it
                conferir("outroID", it)
            }
        }

        val cego = r.cego
        if (cego != null) {
            Faixa(TipoDeFaixa.neutra, t("Primeiro envio para este endereço"), Modifier.padding(top = Espaco.md),
                  mensagem = t("O histórico desta rede não pôde ser lido agora, então o app não consegue comparar com os endereços que você já usou. Confira o endereço com quem vai receber."))
            EnderecoMarcado(t("Você colou"), cego.fonte, cego.trecho, escondido = true, modifier = Modifier.padding(top = Espaco.sm))
            Text(t("Para seguir, digite os 6 caracteres escondidos, lendo no lugar de onde você copiou o endereço."), style = estilo(Tipo.nota),
                 color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
            CampoCurto(conferenciaCega, t("6 escondidos"), Modifier.padding(top = Espaco.xs)) {
                conferenciaCega = it
                conferir("cego", it)
            }
        }

        if (r.precisaConfirmarRede) {
            var confirmada by remember(r.destino) { mutableStateOf(false) }
            Column(
                Modifier.padding(top = Espaco.md).fillMaxWidth().background(Paleta.corpo, RoundedCornerShape(Raio.cartao))
                    .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(Espaco.md),
                verticalArrangement = Arrangement.spacedBy(Espaco.sm),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    SeloDaRede(r.rede, r.redeCoingecko, 28.dp, Paleta.corpo)
                    Text(t("Envio pela rede %@", r.redeNome), style = estilo(Tipo.linha), color = Paleta.tinta)
                }
                r.notaDaRede?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaSuave) }
                Aceite(confirmada, r.textoDaConfirmacaoDeRede ?: "", solto = true) {
                    confirmada = it
                    conferir("rede", it)
                }
            }
        }

        if (r.contatos.isNotEmpty()) {
            Text(t("Endereços salvos"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.lg))
            for (contato in r.contatos) {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).clickable {
                        mudar("envio.escolher", JSONObject().put("endereco", contato.endereco).put("tag", contato.tag ?: ""), contato.endereco)
                    },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(contato.nome, style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.weight(1f))
                    Text(Formato.endereco(contato.endereco), style = estilo(Tipo.monoPequeno), color = Paleta.tintaSuave)
                }
            }
        }
    }
    BotaoPrimario(
        t("Continuar"), ligado = r.podeContinuar,
        carregando = controle.trabalhando || (r.destino != null && !r.historicoLido),
    ) { escopo.launch { controle.trabalhar("envio.continuar") } }

    if (carteiras) {
        FolhaDeCarteiras(r, aoFechar = { carteiras = false }) { carteira ->
            carteiras = false
            mudar("envio.escolher", JSONObject().put("endereco", carteira.endereco).put("tag", ""), carteira.endereco)
        }
    }
}

@Composable
private fun LinhaDaValidacao(r: RetratoDoEnvio, aoTrocarRede: (String) -> Unit) {
    val problema = r.problema
    val destino = r.destino
    if (problema != null) {
        Column(Modifier.padding(top = Espaco.sm), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            if (problema.isNotEmpty()) Text(problema, style = estilo(Tipo.nota), color = Paleta.baixa)
            r.sugestao?.let { (ativo, simbolo, rede) -> BotaoSecundario(t("Enviar %@ pela %@", simbolo, rede)) { aoTrocarRede(ativo) } }
        }
    } else if (destino != null) {
        Column(Modifier.padding(top = Espaco.sm), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            // O endereco como vai para a transacao, com as pontas marcadas para conferir contra a
            // origem. Com um desafio na tela, ele some com o campo: o trecho se leria aqui.
            if (!r.desafio) EnderecoEmBlocos(destino, Modifier.padding(bottom = Espaco.xxs))
            r.rotuloDoDestino?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.alta) }
            r.tagDoEndereco?.let { Text(t("A tag de destino %@ veio junto no endereço.", it), style = estilo(Tipo.nota), color = Paleta.tintaSuave) }
            if (r.primeiroEnvio) Text(t("Primeira vez que você envia para este endereço."), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
    }
}

/** Tag, memo ou comentario quando a rede tem e o destino nao exige: o campo ja vem aberto. */
@Composable
private fun TagOpcional(r: RetratoDoEnvio, tag: String, aoMudar: (String) -> Unit) {
    if (r.muxed) {
        Text(t("Endereço M: o ID de quem recebe já vai dentro dele, sem memo."), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
             modifier = Modifier.padding(top = Espaco.md))
        return
    }
    if (r.tipoDeTag == "none" || r.precisaEtapaDaTag) return
    val exchange = t("Exchanges pedem para saber de quem é o depósito. Se quem pediu o envio deu")
    val (titulo, explicacao) = when (r.tipoDeTag) {
        "stellarMemo" -> t("Memo (MEMO)") to t("%@ um memo, cole aqui exatamente igual. Para uma carteira pessoal, deixe vazio.", exchange)
        "tonComment" -> t("Comentário (Memo)") to t("%@ um comentário ou memo, cole aqui exatamente igual. Para uma carteira pessoal, deixe vazio.", exchange)
        else -> t("Tag de destino (Destination Tag)") to
            t("%@ uma tag (um número), cole aqui. Sem ela, a exchange pode não achar o depósito. Para uma carteira pessoal, deixe vazio.", exchange)
    }
    Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            Text(t("opcional"), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
        Text(explicacao, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        CampoDaTag(tag, if (r.tipoDeTag == "xrplTag") "Ex.: 123456789" else t("Cole aqui, se tiver"), r.tipoDeTag == "xrplTag", Altura.campo, aoMudar)
        r.problemaDaTag?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.baixa) }
        if (r.tagDoLink) Text(t("Veio do código que você leu. Confira com quem pediu."), style = estilo(Tipo.nota), color = Paleta.cautela)
    }
}

@Composable
private fun CampoDaTag(texto: String, dica: String, numerico: Boolean, altura: Dp, aoMudar: (String) -> Unit) {
    Box(
        Modifier.fillMaxWidth().height(altura).background(Paleta.corpo, RoundedCornerShape(Raio.cartao))
            .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(horizontal = Espaco.md),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (texto.isEmpty()) Text(dica, style = estilo(Tipo.mono), color = Paleta.tintaMorta)
        BasicTextField(
            texto, { aoMudar(it.take(120)) }, singleLine = true,
            textStyle = estilo(Tipo.mono).copy(color = Paleta.tinta), cursorBrush = SolidColor(Paleta.acento),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false,
                                              keyboardType = if (numerico) KeyboardType.Number else KeyboardType.Ascii),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun Pilula(titulo: String, icone: ImageVector?, ligado: Boolean = true, acao: () -> Unit) {
    Row(
        Modifier.height(34.dp).clip(CircleShape).background(Paleta.trilho).clickable(enabled = ligado, onClick = acao).padding(horizontal = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (icone != null) Icone(icone, Paleta.tinta, tamanho = 15.dp)
        Text(titulo, style = estilo(Tipo.rotulo), color = if (ligado) Paleta.tinta else Paleta.tintaApagada)
    }
}

/** O campo do endereco enquanto um desafio esta na tela: escondido, porque a resposta se leria nele. */
@Composable
fun CampoEscondido(modifier: Modifier = Modifier, aoEditar: () -> Unit) {
    Row(
        modifier.fillMaxWidth().heightIn(min = Altura.campo).background(Paleta.corpo, RoundedCornerShape(Raio.cartao))
            .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(start = Espaco.md, end = Espaco.xs, top = Espaco.xs, bottom = Espaco.xs),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        Icone(Icones.olhoRiscado, Paleta.tintaSuave, tamanho = 16.dp)
        Text(t("Escondido enquanto você confere"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.weight(1f))
        Box(Modifier.height(34.dp).clip(CircleShape).background(Paleta.trilho).clickable(onClick = aoEditar).padding(horizontal = Espaco.sm),
            contentAlignment = Alignment.Center) {
            Text(t("Editar"), style = estilo(Tipo.rotulo), color = Paleta.tinta)
        }
    }
}

/** Um endereco com o trecho que o dono le e digita destacado; escondido, ele le na fonte. */
@Composable
fun EnderecoMarcado(rotulo: String, endereco: String, trecho: Trecho?, escondido: Boolean = false, modifier: Modifier = Modifier) {
    val texto = buildAnnotatedString {
        if (trecho == null || trecho.inicio < 0 || trecho.inicio + trecho.tamanho > endereco.length) {
            append(endereco)
        } else {
            append(endereco.substring(0, trecho.inicio))
            withStyle(SpanStyle(color = Paleta.cautela, textDecoration = TextDecoration.Underline)) {
                append(if (escondido) "•".repeat(trecho.tamanho) else endereco.substring(trecho.inicio, trecho.inicio + trecho.tamanho))
            }
            append(endereco.substring(trecho.inicio + trecho.tamanho))
        }
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(rotulo, style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        Text(texto, style = estilo(Tipo.mono), color = Paleta.tinta)
    }
}

@Composable
fun CampoCurto(texto: String, dica: String, modifier: Modifier = Modifier, largura: Dp = 180.dp, aoMudar: (String) -> Unit) {
    Box(
        modifier.widthIn(max = largura).fillMaxWidth().height(Altura.campo).background(Paleta.corpo, RoundedCornerShape(Raio.chip))
            .padding(horizontal = Espaco.sm),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (texto.isEmpty()) Text(dica, style = estilo(Tipo.mono), color = Paleta.tintaMorta)
        BasicTextField(
            texto, { aoMudar(it.take(32)) }, singleLine = true, textStyle = estilo(Tipo.mono).copy(color = Paleta.tinta),
            cursorBrush = SolidColor(Paleta.acento),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = KeyboardType.Ascii),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** As outras carteiras deste app com conta nesta rede: o endereco vem da propria carteira. */
@Composable
private fun FolhaDeCarteiras(r: RetratoDoEnvio, aoFechar: () -> Unit, aoEscolher: (RetratoDoEnvio.MinhaCarteira) -> Unit) {
    Dialog(onDismissRequest = aoFechar, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
            CabecalhoDeFolha(t("Minhas carteiras"), aoFechar)
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(top = Espaco.md),
                   verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                if (r.minhasCarteiras.isEmpty()) {
                    Text(if (r.rede == "xrpl") t("Nenhuma outra carteira deste app tem conta no %@.", r.redeNome)
                         else t("Nenhuma outra carteira deste app tem conta na %@.", r.redeNome),
                         style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                }
                for (carteira in r.minhasCarteiras) {
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).clickable { aoEscolher(carteira) }.padding(Espaco.sm),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                    ) {
                        Box(Modifier.size(36.dp).clip(CircleShape).background(Paleta.trilho), contentAlignment = Alignment.Center) {
                            Icone(Icones.carteira, Paleta.tintaSuave, tamanho = 17.dp)
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(carteira.nome, style = estilo(Tipo.linha), color = Paleta.tinta)
                            Text(Formato.endereco(carteira.endereco), style = estilo(Tipo.monoPequeno), color = Paleta.tintaSuave)
                        }
                        Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 13.dp)
                    }
                }
            }
        }
    }
}

// MARK: E3 Tag

@Composable
private fun ColumnScope.EtapaDaTag(controle: ControleDoEnvio, r: RetratoDoEnvio) {
    val escopo = rememberCoroutineScope()
    var tag by remember { mutableStateOf(r.tag) }
    val exige = r.exigeTag
    // As frases inteiras para cada tipo: o nome muda o genero e a ordem da frase em cada idioma.
    val (titulo, corpo, dica, pular) = when (r.tipoDeTag) {
        "stellarMemo" -> listOf(
            if (exige) t("Esta conta exige memo") else t("Este endereço é de uma exchange"),
            if (exige) t("A exchange usa o memo para saber que este envio é seu. Copie da tela de depósito da exchange, a mesma onde está o endereço.")
            else t("Exchanges quase sempre pedem memo. Sem ele, o valor chega na exchange mas não na sua conta, e recuperar leva semanas de suporte."),
            t("Memo"), t("A exchange não pediu memo"),
        )
        "tonComment" -> listOf(
            if (exige) t("Esta conta exige comentário") else t("Este endereço é de uma exchange"),
            if (exige) t("A exchange usa o comentário para saber que este envio é seu. Copie da tela de depósito da exchange, a mesma onde está o endereço.")
            else t("Exchanges quase sempre pedem comentário. Sem ele, o valor chega na exchange mas não na sua conta, e recuperar leva semanas de suporte."),
            t("Comentário"), t("A exchange não pediu comentário"),
        )
        else -> listOf(
            if (exige) t("Esta conta exige tag de destino") else t("Este endereço é de uma exchange"),
            if (exige) t("A exchange usa a tag de destino para saber que este envio é seu. Copie da tela de depósito da exchange, a mesma onde está o endereço.")
            else t("Exchanges quase sempre pedem tag de destino. Sem ela, o valor chega na exchange mas não na sua conta, e recuperar leva semanas de suporte."),
            t("Tag de destino"), t("A exchange não pediu tag de destino"),
        )
    }
    Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta)
    Text(corpo, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
    Box(Modifier.padding(top = Espaco.lg)) {
        CampoDaTag(tag, dica, r.tipoDeTag == "xrplTag", 56.dp) { novo ->
            tag = novo
            escopo.launch { controle.chamar("envio.conferir", JSONObject().put("tag", novo)) }
        }
    }
    r.problemaDaTag?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.baixa, modifier = Modifier.padding(top = Espaco.xs)) }
    Spacer(Modifier.weight(1f))
    BotaoPrimario(t("Continuar"), ligado = tag.isNotEmpty() && r.problemaDaTag == null) {
        escopo.launch { controle.chamar("envio.tag", JSONObject().put("texto", tag).put("pular", false)) }
    }
    if (!exige) {
        BotaoSecundario(pular, Modifier.padding(top = Espaco.sm)) {
            escopo.launch { controle.chamar("envio.tag", JSONObject().put("texto", "").put("pular", true)) }
        }
    }
}

// MARK: E4 Valor

@Composable
private fun ColumnScope.EtapaDoValor(controle: ControleDoEnvio, r: RetratoDoEnvio) {
    val escopo = rememberCoroutineScope()
    var valor by remember { mutableStateOf(r.valor) }
    val limite = runCatching { BigInteger(r.disponivel) }.getOrDefault(BigInteger.ZERO)
    val pedido: BigInteger? = if (r.tudo) limite else Formato.lerQuantidade(valor, r.casas)
    val passou = !r.tudo && pedido != null && pedido > limite
    val foco = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        runCatching { foco.requestFocus() }
        controle.chamar("envio.disponivel")
    }

    fun mudar(texto: String, tudo: Boolean) {
        valor = texto
        escopo.launch { controle.chamar("envio.valor", JSONObject().put("texto", texto).put("tudo", tudo)) }
    }

    Cabecalho(r)
    val mostrado = if (r.tudo) Formato.decimalSimples(r.disponivel, r.casas) else valor
    val tamanho = if (mostrado.length <= 11) 40f else maxOf(18f, 40f * 11 / mostrado.length)
    val densidade = LocalDensity.current
    val fonte = with(densidade) { (tamanho / fontScale).sp }
    val estiloDoValor = TextStyle(fontSize = fonte, fontWeight = FontWeight.Bold, color = if (passou) Paleta.baixa else Paleta.tinta, fontFeatureSettings = "tnum")
    // O campo do tamanho do numero: o simbolo vem logo depois, como no iOS.
    val medidor = rememberTextMeasurer()
    val largura = with(densidade) { medidor.measure(mostrado.ifEmpty { "0" }, estiloDoValor).size.width.toDp() } + 4.dp
    Row(Modifier.padding(top = Espaco.xl), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Box(Modifier.weight(1f, fill = false)) {
            if (mostrado.isEmpty()) Text("0", style = estiloDoValor.copy(color = Paleta.tintaMorta))
            BasicTextField(
                mostrado, { novo -> mudar(novo.filter { it.isDigit() || it == ',' || it == '.' }.take(40), false) },
                singleLine = true, textStyle = estiloDoValor, cursorBrush = SolidColor(Paleta.acento),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, autoCorrectEnabled = false),
                modifier = Modifier.width(largura).focusRequester(foco),
            )
        }
        Text(r.simbolo, style = estilo(Tipo.cabecalho), color = Paleta.tintaSuave, maxLines = 1, modifier = Modifier.padding(bottom = 6.dp))
    }
    val preco = r.preco
    if (preco != null && pedido != null) {
        Text(t("≈ %@", Formato.valor(Formato.numero(pedido.toString(), r.casas) * preco, r.moeda)), style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
    }
    Row(Modifier.fillMaxWidth().padding(top = Espaco.lg), verticalAlignment = Alignment.CenterVertically) {
        Text(t("Disponível %@", Formato.cripto(r.disponivel, r.casas, r.simbolo, Formato.EstiloCripto.cheio)), style = estilo(Tipo.nota),
             color = if (passou) Paleta.baixa else Paleta.tintaSuave, modifier = Modifier.weight(1f))
        Box(Modifier.height(28.dp).clip(CircleShape).background(Paleta.trilho).clickable {
            mudar(valor, true)
            if (!r.motorRespondeu) escopo.launch { controle.chamar("envio.disponivel") }
        }.padding(horizontal = Espaco.sm), contentAlignment = Alignment.Center) {
            Text(t("Máx"), style = estilo(Tipo.rotulo), color = Paleta.tinta)
        }
    }
    Deslizante(limite, pedido, r.tudo, r.casas) { fracao, parte ->
        if (fracao >= 0.995f) mudar(valor, true) else mudar(if (parte.signum() == 0) "" else Formato.decimalSimples(parte.toString(), r.casas), false)
    }
    r.notaDeReserva?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.xs)) }
    r.notaDeTaxa?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.xxs)) }
    r.ativacao?.let { minimo ->
        Text(if (r.rede == "xrpl") t("Esta conta ainda não existe no %@. Para ativá-la, o primeiro envio precisa ser de %@ ou mais.", r.redeNome, minimo)
             else t("Esta conta ainda não existe na %@. Para ativá-la, o primeiro envio precisa ser de %@ ou mais.", r.redeNome, minimo),
             style = estilo(Tipo.nota), color = Paleta.cautela, modifier = Modifier.padding(top = Espaco.sm))
    }
    r.erro?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
    Spacer(Modifier.weight(1f))
    BotaoPrimario(
        if (passou) t("Saldo insuficiente") else t("Revisar"),
        ligado = pedido != null && pedido.signum() > 0 && !passou, carregando = controle.trabalhando,
    ) { escopo.launch { controle.trabalhar("envio.revisar") } }
}

/** O valor pelo deslizante, de 0 ao disponivel. No fim, vira "enviar tudo" (o motor desconta a taxa). */
@Composable
private fun Deslizante(limite: BigInteger, pedido: BigInteger?, tudo: Boolean, casas: Int, aoMudar: (Float, BigInteger) -> Unit) {
    val total = Formato.numero(limite.toString(), casas)
    val fracao = when {
        tudo -> 1f
        pedido == null || total <= 0 -> 0f
        else -> minOf(Formato.numero(pedido.toString(), casas) / total, 1.0).toFloat()
    }
    Column(Modifier.padding(top = Espaco.md)) {
        val ligado = limite.signum() > 0
        fun escolher(nova: Float) {
            val milesimos = BigInteger.valueOf(Math.round(nova.coerceIn(0f, 1f) * 1000.0))
            aoMudar(nova.coerceIn(0f, 1f), paraBaixo(limite * milesimos / BigInteger.valueOf(1000)))
        }
        // Trilho e bolinha proprios: o deslizante do Material tem outro desenho a cada versao.
        BoxWithConstraints(
            Modifier.fillMaxWidth().height(Altura.toque)
                .pointerInput(ligado) {
                    if (!ligado) return@pointerInput
                    detectTapGestures { escolher(it.x / size.width) }
                }
                .pointerInput(ligado) {
                    if (!ligado) return@pointerInput
                    detectHorizontalDragGestures { mudanca, _ -> escolher(mudanca.position.x / size.width) }
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            val bolinha = 26.dp
            Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(Paleta.trilho))
            Box(Modifier.fillMaxWidth(fracao).height(6.dp).clip(CircleShape).background(if (ligado) Paleta.acento else Paleta.trilho))
            Box(Modifier.offset(x = (maxWidth - bolinha) * fracao).size(bolinha).clip(CircleShape).background(if (ligado) Paleta.tinta else Paleta.controle))
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            for (rotulo in listOf("0%", "25%", "50%", "75%", t("Máx"))) Text(rotulo, style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
    }
}

/** Para baixo, com 6 algarismos que contam: o deslizante nao enche o campo de casas. */
private fun paraBaixo(valor: BigInteger, significativos: Int = 6): BigInteger {
    val digitos = valor.toString().length
    if (digitos <= significativos) return valor
    val fator = BigInteger.TEN.pow(digitos - significativos)
    return valor / fator * fator
}

// MARK: E6 Revisao


@Composable
private fun ColumnScope.EtapaDaRevisao(controle: ControleDoEnvio, r: RetratoDoEnvio) {
    val escopo = rememberCoroutineScope()
    val plano = r.plano ?: return
    var irreversivel by remember { mutableStateOf(false) }
    var erro by remember { mutableStateOf<String?>(null) }
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = Espaco.lg)) {
        Text(plano.titulo, style = estilo(Tipo.titulo), color = Paleta.tinta)
        r.preco?.let { preco ->
            Text(t("cerca de %@", Formato.valor(Formato.numero(plano.saida, r.casas) * preco, r.moeda)), style = estilo(Tipo.corpo),
                 color = Paleta.tintaSuave, modifier = Modifier.padding(top = 2.dp))
        }
        // So o destino (e a tag ou o memo dele), como a rede vai ver.
        if (plano.placa.isNotEmpty()) {
            Column(
                Modifier.padding(top = Espaco.lg).fillMaxWidth().background(Paleta.viva, PlacaLaqueada()).padding(Espaco.base),
                verticalArrangement = Arrangement.spacedBy(Espaco.sm),
            ) {
                for (linha in plano.placa) {
                    Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                        Text(linha.rotulo, style = estilo(Tipo.nota), color = Paleta.placaApagada)
                        if (linha.endereco) EnderecoEmBlocos(linha.valor, naPlaca = true)
                        else Text(linha.valor, style = estilo(Tipo.mono), fontWeight = FontWeight.Bold, color = Paleta.placaTinta)
                    }
                }
            }
        }
        Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            for ((rotulo, valor) in plano.linhas) {
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    Text(rotulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    Text(valor, style = estilo(Tipo.nota), color = Paleta.tinta, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
                }
            }
        }
        for (aviso in plano.avisos) Faixa(TipoDeFaixa.cautela, aviso, Modifier.padding(top = Espaco.sm))
        (erro ?: r.erro)?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
    }
    Aceite(irreversivel, t("Sei que este envio não pode ser desfeito. Depois de confirmado na rede, ninguém consegue devolver, nem a Escalibur.")) { irreversivel = it }
    BotaoPrimario(plano.titulo, Modifier.padding(top = Espaco.sm), ligado = irreversivel, carregando = controle.trabalhando) {
        escopo.launch {
            erro = null
            erro = assinar(controle, r, plano.titulo)
        }
    }
    if (r.primeiroEnvio) {
        Text(t("Primeiro envio para este endereço? Mandar um valor pequeno antes é a forma mais barata de conferir."), style = estilo(Tipo.nota),
             color = Paleta.tintaApagada, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = Espaco.sm))
    }
}

/**
 * Assina e transmite. A carteira com passphrase pede ela antes da biometria ou do PIN; o nucleo
 * confere dentro do assinador. Devolve o texto do erro, ou nil.
 */
private suspend fun assinar(controle: ControleDoEnvio, r: RetratoDoEnvio, motivo: String): String? {
    var passphrase: PedidoDePassphrase.Resposta? = null
    if (r.pedePassphrase) passphrase = PedidoDePassphrase.pedir(r.nomeDaCarteira) ?: return null
    controle.trabalhando = true
    try {
        val segredo = passphrase?.bytes
        Autorizacao.tentando(motivo) { credencial ->
            val corpo = JSONObject().put("credencial", credencial.json())
            passphrase?.folga?.let { corpo.put("folga", it) }
            // Cada tentativa leva a sua copia: a chamada zera o que recebe.
            val partes = if (segredo != null) credencial.partes(segredo.copyOf()) else credencial.partes()
            controle.aplicar(Api.comSegredo("envio.assinar", corpo, *partes))
        }
        return null
    } catch (falha: FalhaDoNucleo) {
        controle.chamar("envio.estado")
        return when (falha.codigo) {
            "passphrase.errada" -> t("A passphrase não confere. Nada foi assinado. Escreva igual ao que você anotou: maiúscula, acento e espaço contam.")
            "passphrase.espera" -> t("Muitas passphrases erradas. Tente de novo às %@.", Formato.relogio(Date(falha.dados.optDouble("ate", 0.0).toLong())))
            "envio.pedePassphrase" -> t("A folga da passphrase acabou. Toque de novo para enviar.")
            "envio.motor" -> falha.dados.optString("mensagem", "").ifEmpty { null } ?: t("O envio não saiu. Nada foi debitado.")
            else -> Autorizacao.mensagemDeRecusa(falha) ?: t("O envio não saiu. Nada foi debitado.")
        }
    } finally {
        passphrase?.bytes?.fill(0)
        controle.trabalhando = false
    }
}

// MARK: E8 Status

@Composable
private fun ColumnScope.EtapaDoStatus(controle: ControleDoEnvio, r: RetratoDoEnvio) {
    val contexto = LocalContext.current
    val resultado = r.resultado
    // Enviado: pergunta a rede pela confirmacao, ate ela responder.
    LaunchedEffect(r.etapa, resultado?.id) {
        if (r.etapa != "enviado" || resultado == null) return@LaunchedEffect
        repeat(40) {
            controle.chamar("envio.acompanhar")
            if (controle.retrato?.resultado?.situacao != "pendente") return@LaunchedEffect
            delay(if (r.tempoDeConfirmacao > 60) 15_000L else 3_000L)
        }
    }
    Spacer(Modifier.weight(1f))
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        if (r.etapa == "enviando") {
            Girando(Paleta.acento, 56.dp)
            Text(t("Enviando"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
            Text(r.linhaDoEnvio, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs))
        } else if (resultado?.situacao == "falhou") {
            Icone(Icones.falha, Paleta.baixa, tamanho = 44.dp)
            Text(t("A rede recusou o envio"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.md))
            Text(resultado.detalhe ?: "", style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs))
        } else {
            LogoDaMoeda(r.coingecko, r.simbolo, 72.dp, rede = r.rede, redeCoingecko = r.redeCoingecko, naoConferido = !r.conferido)
            Text(t("Enviado"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
            Text(r.linhaDoEnvio, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs))
            Row(Modifier.padding(top = Espaco.md), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                if (resultado?.situacao == "confirmado") {
                    Icone(Icones.vistoCheio, Paleta.alta, tamanho = 15.dp)
                    Text(resultado.detalhe ?: t("Confirmado na rede."), style = estilo(Tipo.nota), color = Paleta.tinta)
                } else {
                    Girando(Paleta.tintaSuave, 14.dp)
                    Text(
                        when {
                            r.familia == "utxo" -> t("A primeira confirmação leva cerca de %lld minutos. Pode fechar o app.", r.tempoDeConfirmacao / 60)
                            r.rede == "xrpl" -> t("Confirmando no %@, cerca de %lld segundos.", r.redeNome, r.tempoDeConfirmacao)
                            else -> t("Confirmando na %@, cerca de %lld segundos.", r.redeNome, r.tempoDeConfirmacao)
                        },
                        style = estilo(Tipo.nota), color = Paleta.tintaSuave,
                    )
                }
            }
        }
    }
    Spacer(Modifier.weight(1f))
    val url = resultado?.urlDoExplorador
    if (url != null) {
        BotaoSecundario(t("Ver no %@", resultado.explorador ?: t("explorador"))) {
            runCatching { contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        }
    }
    if (r.etapa != "enviando") BotaoPrimario(t("Concluir"), Modifier.padding(top = Espaco.sm)) { Navegacao.fechar() }
}

/** Transmitido sem resposta certa: so os mesmos bytes podem ir de novo, nunca outro envio. */
@Composable
private fun ColumnScope.EtapaIncerta(controle: ControleDoEnvio, r: RetratoDoEnvio) {
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    LaunchedEffect(r.resultado?.id) {
        repeat(40) {
            delay(if (r.tempoDeConfirmacao > 60) 15_000L else 4_000L)
            if (controle.retrato?.etapa != "incerto") return@LaunchedEffect
            controle.chamar("envio.acompanhar")
        }
    }
    Spacer(Modifier.weight(1f))
    Icone(Icones.pergunta, Paleta.cautela, tamanho = 44.dp)
    Text(t("Não deu para confirmar o envio"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.md))
    Text(t("A rede não respondeu com certeza, e a transação assinada pode já estar a caminho. Não monte outro envio: transmitir de novo usa os mesmos dados e não paga duas vezes. O app continua perguntando à rede por esta transação."),
         style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs))
    r.detalheIncerto?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.sm)) }
    Spacer(Modifier.weight(1f))
    val resultado = r.resultado
    val url = resultado?.urlDoExplorador
    if (url != null) {
        BotaoSecundario(t("Procurar no %@", resultado.explorador ?: t("explorador"))) {
            runCatching { contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        }
    }
    BotaoPrimario(t("Transmitir de novo"), Modifier.padding(top = Espaco.sm), carregando = controle.trabalhando) {
        escopo.launch { controle.trabalhar("envio.retransmitir") }
    }
    BotaoTerciario(t("Fechar e acompanhar na Atividade"), Modifier.fillMaxWidth()) { Navegacao.fechar() }
}
