package app.escalibur.wallet.ui.trocar

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.EnderecoEmBlocos
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.enviar.PedidoDePassphrase
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
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

/**
 * T3 a T5: a revisao da troca, a assinatura e o acompanhamento. A tela mostra o plano que o motor
 * montou e validou, nunca a intencao. O plano que nao sai volta para o formulario com o erro.
 */
@Composable
fun RevisaoDaTroca() {
    val controle = ControleDaTroca
    val escopo = rememberCoroutineScope()
    // So depois de o pedido de revisar voltar: antes disso, o retrato ainda e o do formulario.
    var pediu by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        controle.trabalhar("troca.revisar")
        pediu = true
    }
    val r = controle.retrato
    val etapa = r?.etapa ?: "formulario"
    LaunchedEffect(pediu, etapa) { if (pediu && etapa == "formulario") Navegacao.fechar() }
    val transmitindo = etapa == "enviando"
    fun fechar() {
        escopo.launch {
            controle.chamar("troca.fechar")
            Navegacao.fechar()
        }
    }
    BackHandler(enabled = !transmitindo) { fechar() }
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
        CabecalhoDeFolha("", if (transmitindo) null else ({ fechar() }))
        Column(Modifier.weight(1f).fillMaxWidth().padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs)) {
            if (r == null) return@Column
            when (etapa) {
                "formulario", "montando" -> Espera(r, t("Recotando e simulando a troca antes de mostrar."), null)
                "revisao" -> Revisao(r)
                "enviando" -> Espera(r, r.revisao?.nota ?: t("Não feche o app até terminar."), t("Enviando a troca"))
                "enviada" -> Enviada(r) { fechar() }
                "incerta" -> Incerta(r) { fechar() }
            }
        }
    }
}

/** Montando ou enviando: as duas moedas e o texto, no meio da tela. */
@Composable
private fun ColumnScope.Espera(r: RetratoDaTroca, texto: String, titulo: String?) {
    Spacer(Modifier.weight(1f))
    Direcao(r, null, null)
    if (titulo != null) Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                             modifier = Modifier.fillMaxWidth().padding(top = Espaco.lg))
    Text(texto, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center,
         modifier = Modifier.fillMaxWidth().padding(top = if (titulo == null) Espaco.lg else Espaco.xs))
    Spacer(Modifier.weight(1f))
}

/** O que sai e o que entra, com as moedas. Sem os valores, a espera gira entre elas. */
@Composable
private fun Direcao(r: RetratoDaTroca, sai: String?, entra: String?) {
    val esperando = sai == null && entra == null
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        LadoDaDirecao(r.vende, sai, Modifier.weight(1f))
        Box(Modifier.width(36.dp).heightIn(min = 52.dp), contentAlignment = Alignment.Center) {
            if (esperando) CircularProgressIndicator(color = Paleta.tintaSuave, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
            else Icone(Icones.avancar, Paleta.tintaSuave, tamanho = 18.dp)
        }
        LadoDaDirecao(r.compra, entra, Modifier.weight(1f))
    }
}

@Composable
private fun LadoDaDirecao(ativo: AtivoDaTroca?, quantia: String?, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        LogoDaMoeda(ativo?.coingecko, ativo?.simbolo ?: "", 52.dp, rede = ativo?.rede, redeCoingecko = ativo?.redeCoingecko,
                    naoConferido = ativo?.conferido == false)
        if (quantia != null) Text(quantia, style = estilo(Tipo.nota), color = Paleta.tinta, textAlign = TextAlign.Center, maxLines = 2)
    }
}

@Composable
private fun ColumnScope.Revisao(r: RetratoDaTroca) {
    val controle = ControleDaTroca
    val escopo = rememberCoroutineScope()
    val revisao = r.revisao ?: return
    var erro by remember { mutableStateOf<String?>(null) }
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = Espaco.md, bottom = Espaco.lg)) {
        Direcao(r, revisao.sai, revisao.entra)
        Text(revisao.titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
        r.valorEmMoeda?.let {
            Text(t("cerca de %@", Formato.valor(it, r.moeda)), style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = 2.dp))
        }
        if (revisao.enderecos.isNotEmpty()) Enderecos(revisao.enderecos, Modifier.padding(top = Espaco.lg))
        Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            for ((rotulo, valor) in revisao.linhas) {
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    Text(rotulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    Text(valor, style = estilo(Tipo.nota), color = Paleta.tinta, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
                }
            }
        }
        if (revisao.transacoes > 1) {
            Faixa(TipoDeFaixa.neutra, t("Você vai assinar %lld transações de uma vez", revisao.transacoes), Modifier.padding(top = Espaco.md),
                  mensagem = t("A autorização do token vai antes e a troca logo depois, em transações separadas. Se a troca não sair, a autorização continua valendo, só para este valor e só para o contrato desta troca."))
        }
        for (aviso in revisao.avisos) Faixa(TipoDeFaixa.cautela, aviso, Modifier.padding(top = Espaco.sm))
        (erro ?: revisao.erro)?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
    }
    BotaoPrimario(t("Confirmar troca"), Modifier.padding(top = Espaco.sm), carregando = controle.trabalhando) {
        escopo.launch {
            erro = null
            erro = assinar(r, revisao.titulo)
        }
    }
}

/** Os enderecos e contratos (a propria conta, o contrato da troca, quem fica autorizado), atras de um toque. */
@Composable
private fun Enderecos(linhas: List<Pair<String, String>>, modifier: Modifier = Modifier) {
    var aberto by remember { mutableStateOf(false) }
    val forma = RoundedCornerShape(Raio.cartao)
    Column(modifier.fillMaxWidth().clip(forma).background(Paleta.corpo).border(1.dp, Paleta.borda, forma).animateContentSize()) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).clickable { aberto = !aberto }.padding(horizontal = Espaco.md),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
        ) {
            Icone(Icones.documento, Paleta.tintaSuave, tamanho = 16.dp)
            Text(if (linhas.size == 1) t("Ver o endereço") else t("Ver endereços e contratos (%lld)", linhas.size), style = estilo(Tipo.linha),
                 color = Paleta.tinta, modifier = Modifier.weight(1f))
            Icone(if (aberto) Icones.acima else Icones.abaixo, Paleta.tintaApagada, tamanho = 12.dp)
        }
        if (aberto) {
            Column(Modifier.padding(start = Espaco.md, end = Espaco.md, bottom = Espaco.md), verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
                for ((rotulo, valor) in linhas) {
                    Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                        Text(rotulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                        if (valor.length >= 26 && !valor.contains(" ")) EnderecoEmBlocos(valor)
                        else Text(valor, style = estilo(Tipo.mono), fontWeight = FontWeight.Bold, color = Paleta.tinta)
                    }
                }
            }
        }
    }
}

/**
 * Assina e transmite. A carteira com passphrase pede ela antes da biometria ou do PIN; o nucleo
 * confere dentro do assinador. Devolve o texto do erro, ou nil.
 */
private suspend fun assinar(r: RetratoDaTroca, motivo: String): String? {
    val controle = ControleDaTroca
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
            controle.aplicar(Api.comSegredo("troca.assinar", corpo, *partes))
        }
        return null
    } catch (falha: FalhaDoNucleo) {
        controle.chamar("troca.estado")
        return when (falha.codigo) {
            "passphrase.errada" -> t("A passphrase não confere. Nada foi assinado. Escreva igual ao que você anotou: maiúscula, acento e espaço contam.")
            "passphrase.espera" -> t("Muitas passphrases erradas. Tente de novo às %@.", Formato.relogio(Date(falha.dados.optDouble("ate", 0.0).toLong())))
            "envio.pedePassphrase" -> t("A folga da passphrase acabou. Toque de novo para enviar.")
            "envio.motor" -> falha.dados.optString("mensagem", "").ifEmpty { null } ?: t("A troca não saiu. Nada foi debitado.")
            else -> Autorizacao.mensagemDeRecusa(falha) ?: t("A troca não saiu. Nada foi debitado.")
        }
    } finally {
        passphrase?.bytes?.fill(0)
        controle.trabalhando = false
    }
}

// MARK: Depois de enviar

@Composable
private fun ColumnScope.Enviada(r: RetratoDaTroca, aoConcluir: () -> Unit) {
    val controle = ControleDaTroca
    val contexto = LocalContext.current
    val resultado = r.resultado
    // O saldo novo: a carteira rele as redes, e a troca pergunta pela confirmacao (ou, na CoW,
    // pelo preenchimento da ordem) ate terminar.
    LaunchedEffect(Unit) { runCatching { Api.objeto("saldos.atualizar", JSONObject().put("forcar", true)) } }
    LaunchedEffect(resultado?.id) {
        if (resultado == null) return@LaunchedEffect
        repeat(120) {
            controle.chamar("troca.acompanhar")
            val agora = controle.retrato
            val fim = if (agora?.resultado?.ordem == true) agora.andamento?.estado.let { it != null && it != "aberta" }
                      else agora?.resultado?.situacao != "pendente"
            if (fim) {
                runCatching { Api.objeto("saldos.atualizar", JSONObject().put("forcar", true)) }
                return@LaunchedEffect
            }
            delay(5_000)
        }
    }
    Spacer(Modifier.weight(1f))
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        if (resultado?.ordem == true) {
            AndamentoDaOrdem(r)
        } else if (resultado?.situacao == "falhou") {
            Icone(Icones.falha, Paleta.baixa, tamanho = 44.dp)
            Text(t("A rede recusou o envio"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.md))
            Text(resultado.detalhe ?: "", style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs))
        } else {
            Box(contentAlignment = Alignment.BottomEnd) {
                LogoDaMoeda(r.compra?.coingecko, r.compra?.simbolo ?: "", 72.dp, rede = r.compra?.rede, redeCoingecko = r.compra?.redeCoingecko,
                            naoConferido = r.compra?.conferido == false)
            }
            Text(t("Troca enviada"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
            Text(t("O saldo novo aparece quando a rede confirmar."), style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center,
                 modifier = Modifier.padding(top = Espaco.xs))
            if (resultado?.situacao == "confirmado") {
                Row(Modifier.padding(top = Espaco.md), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Icone(Icones.vistoCheio, Paleta.alta, tamanho = 15.dp)
                    Text(resultado.detalhe ?: t("Confirmado na rede."), style = estilo(Tipo.nota), color = Paleta.tinta)
                }
            }
        }
    }
    Spacer(Modifier.weight(1f))
    val url = resultado?.url
    if (url != null) {
        BotaoSecundario(t("Ver no %@", resultado.explorador)) {
            runCatching { contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        }
    }
    BotaoPrimario(t("Concluir"), Modifier.padding(top = Espaco.sm), acao = aoConcluir)
}

/** A troca pela CoW: o anel do preenchimento e o que ja chegou. */
@Composable
private fun AndamentoDaOrdem(r: RetratoDaTroca) {
    val andamento = r.andamento
    val fracao = andamento?.fracao ?: 0.0
    Box(Modifier.size(96.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(96.dp)) {
            val traco = 6.dp.toPx()
            drawCircle(Paleta.trilho, style = Stroke(traco), radius = size.minDimension / 2 - traco / 2)
            drawArc(if (andamento?.estado == "preenchida") Paleta.alta else Paleta.tinta, -90f, (360 * fracao).toFloat(), false,
                    topLeft = Offset(traco / 2, traco / 2), size = Size(size.width - traco, size.height - traco), style = Stroke(traco, cap = StrokeCap.Round))
        }
        Text(Formato.agrupado(fracao * 100, 0) + "%", style = estilo(Tipo.cabecalho), color = Paleta.tinta)
    }
    val titulo = when (andamento?.estado) {
        null -> t("Troca enviada")
        "preenchida" -> t("Troca concluída")
        "vencida" -> t("Prazo encerrado")
        "cancelada" -> t("Ordem cancelada")
        else -> if (fracao > 0) t("Preenchendo") else t("No leilão da CoW")
    }
    Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
    val texto = when {
        andamento == null -> if (r.semAndamento) t("Sem resposta da CoW agora. O andamento volta a aparecer sozinho, e as ordens abertas mostram o mesmo.")
                             else t("Lendo o andamento na CoW.")
        andamento.estado == "preenchida" -> t("Saiu inteira, pelo mínimo garantido de %@ ou mais. O saldo novo aparece em instantes.", andamento.garantido)
        andamento.estado == "vencida" || andamento.estado == "cancelada" ->
            if (fracao > 0) t("%@ foi preenchido. O restante continua na sua carteira.", Formato.agrupado(fracao * 100, 0) + "%")
            else t("Nada foi preenchido. O valor continua na sua carteira.")
        else -> t("Cada parte sai pelo preço garantido ou melhor. %@", t("Pode fechar esta tela: o andamento fica em Ordens abertas."))
    }
    Text(texto, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs))
    if (andamento != null && andamento.fracao > 0) {
        Text(t("Recebido %@", andamento.recebido), style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.md))
        Text(t("Garantido no total: %@ ou mais", andamento.garantido), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
    }
}

/** Assinada e enviada sem resposta certa: so os mesmos bytes podem ir de novo, nunca outra troca. */
@Composable
private fun ColumnScope.Incerta(r: RetratoDaTroca, aoFechar: () -> Unit) {
    val controle = ControleDaTroca
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    LaunchedEffect(r.resultado?.id) {
        repeat(40) {
            delay(5_000)
            if (controle.retrato?.etapa != "incerta") return@LaunchedEffect
            controle.chamar("troca.acompanhar")
        }
    }
    Spacer(Modifier.weight(1f))
    Icone(Icones.pergunta, Paleta.cautela, tamanho = 44.dp)
    Text(t("Não deu para confirmar a troca"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.md))
    Text(t("A resposta não veio com certeza, e o que foi assinado pode já estar a caminho. Não monte de novo: enviar de novo usa os mesmos dados e não paga duas vezes. Confira na Atividade antes de qualquer outra operação."),
         style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs))
    r.detalheIncerto?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.sm)) }
    Spacer(Modifier.weight(1f))
    val resultado = r.resultado
    val url = resultado?.url
    if (url != null) {
        BotaoSecundario(t("Procurar no %@", resultado.explorador)) {
            runCatching { contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        }
    }
    BotaoPrimario(t("Enviar de novo"), Modifier.padding(top = Espaco.sm), carregando = controle.trabalhando) {
        escopo.launch { controle.trabalhar("troca.retransmitir") }
    }
    BotaoTerciario(t("Fechar e acompanhar na Atividade"), Modifier.fillMaxWidth(), acao = aoFechar)
}
