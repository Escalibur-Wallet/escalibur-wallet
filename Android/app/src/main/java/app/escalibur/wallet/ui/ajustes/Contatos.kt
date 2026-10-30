package app.escalibur.wallet.ui.ajustes

import android.content.ClipboardManager
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import app.escalibur.wallet.ui.comp.acimaDoTeclado
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.carteira.Redes
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Chip
import app.escalibur.wallet.ui.comp.Confirmacao
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.comp.Transferencia
import app.escalibur.wallet.ui.enviar.CampoCurto
import app.escalibur.wallet.ui.enviar.EnderecoMarcado
import app.escalibur.wallet.ui.enviar.LeitorDeQR
import app.escalibur.wallet.ui.enviar.Trecho
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.receber.opcional
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.launch
import org.json.JSONObject
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.layout.width
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.style.TextOverflow
import app.escalibur.wallet.ui.comp.TelaComBarra
import app.escalibur.wallet.ui.comp.MenuFlutuante
import app.escalibur.wallet.ui.comp.OpcaoDoMenu
import app.escalibur.wallet.ui.comp.movimentoReduzido
import app.escalibur.wallet.ui.comp.relogio
import kotlinx.coroutines.delay
import kotlin.math.sin

private class Contato(j: JSONObject) {
    val id: String = j.getString("id")
    val nome: String = j.getString("nome")
    val rede: String = j.getString("rede")
    val redeNome: String = j.getString("redeNome")
    val redeCoingecko: String = j.getString("redeCoingecko")
    val endereco: String = j.getString("endereco")
    val tag: String? = j.opcional("tag")
}

/** Os enderecos salvos: atalho no envio e conhecidos na conferencia de endereco parecido. */
@Composable
fun TelaDeContatos() {
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    var contatos by remember { mutableStateOf<List<Contato>?>(null) }
    var removendo by remember { mutableStateOf<Contato?>(null) }
    var menuDe by remember { mutableStateOf<String?>(null) }
    val versao = App.estado.contatos
    LaunchedEffect(versao) { contatos = runCatching { Api.lista("contatos.lista").objetos().map(::Contato) }.getOrDefault(emptyList()) }
    // Como no iOS: a lista rola por baixo da barra, e o botao fica preso embaixo.
    TelaComBarra({ Navegacao.fechar() }, titulo = t("Endereços salvos"),
                 rodape = { BotaoPrimario(t("Salvar um endereço")) { Navegacao.folha { NovoContato() } } }) { espaco ->
        val lista = contatos ?: return@TelaComBarra
        if (lista.isEmpty()) {
            // O vazio no meio da tela, um pouco acima do centro.
            Column(
                Modifier.fillMaxSize().padding(espaco).padding(horizontal = Espaco.margem).padding(bottom = Espaco.xl),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
            ) {
                IlustracaoDeEnderecos(Modifier.padding(bottom = Espaco.md))
                Text(t("Nenhum endereço salvo"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                     modifier = Modifier.padding(top = Espaco.xs))
                Text(t("Salve os endereços para onde você envia sempre, com a tag de destino junto quando houver. No envio, é só escolher."),
                     style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm))
            }
            return@TelaComBarra
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(horizontal = Espaco.margem)
                .padding(top = Espaco.md, bottom = Espaco.lg),
            verticalArrangement = Arrangement.spacedBy(Espaco.xs),
        ) {
            for (contato in lista) {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(start = Espaco.md).padding(vertical = Espaco.sm),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    SeloDaRede(contato.rede, contato.redeCoingecko, 36.dp, Paleta.corpo)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(contato.nome, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(contato.redeNome + (contato.tag?.let { " · tag $it" } ?: ""), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
                             maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(Formato.endereco(contato.endereco, 8, 6), style = estilo(Tipo.monoPequeno), color = Paleta.tintaApagada, maxLines = 1)
                    }
                    Box {
                        Box(Modifier.size(Altura.toque).clickable { menuDe = contato.id }, contentAlignment = Alignment.Center) {
                            Icone(Icones.reticencias, Paleta.tintaSuave, tamanho = 15.dp, descricao = t("Opções de %@", contato.nome))
                        }
                        MenuFlutuante(
                            menuDe == contato.id,
                            listOf(
                                OpcaoDoMenu("copiar", t("Copiar endereço")) { Icone(Icones.copiar, Paleta.tinta, tamanho = 17.dp) },
                                OpcaoDoMenu("apagar", t("Apagar")) { Icone(Icones.lixeira, Paleta.baixa, tamanho = 17.dp) },
                            ),
                            escolhida = null, aoFechar = { menuDe = null },
                        ) { opcao ->
                            when (opcao) {
                                "copiar" -> {
                                    Transferencia.copiar(contexto, contato.endereco)
                                    Avisos.mostrar(t("Endereço copiado."))
                                }
                                "apagar" -> removendo = contato
                            }
                        }
                    }
                }
            }
            Text(t("Endereço salvo vira atalho no envio e entra na conferência de endereço parecido. Salvar pede a biometria ou o PIN."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.sm))
        }
    }
    removendo?.let { contato ->
        Confirmacao(
            t("Apagar %@?", contato.nome), t("O endereço sai da lista. Nada muda na rede."), t("Apagar"),
            aoConfirmar = {
                removendo = null
                escopo.launch { runCatching { App.aplicar(Api.objeto("contatos.remover", JSONObject().put("id", contato.id))) } }
            },
            aoCancelar = { removendo = null },
        )
    }
}

/**
 * O vazio dos enderecos salvos (o SavedAddressesIllustration do iOS): tres fichas de endereco, de
 * Bitcoin, Ethereum e XRP, empilhadas e inclinadas, que se abrem em lista ao entrar e respiram de
 * leve. Com o movimento reduzido, ja abertas e paradas.
 */
@Composable
private fun IlustracaoDeEnderecos(modifier: Modifier = Modifier) {
    val parado = movimentoReduzido()
    val agora = relogio(parado)
    val abertura = remember { Animatable(if (parado) 1f else 0f) }
    LaunchedEffect(Unit) {
        if (!parado) {
            delay(250)
            abertura.animateTo(1f, spring(dampingRatio = 0.72f, stiffness = 90f))
        }
    }
    val fichas = listOf(Triple("bitcoin", "bitcoin", 0), Triple("ethereum", "ethereum", 1), Triple("xrpl", "ripple", 2))
    Box(modifier.fillMaxWidth().height(190.dp), contentAlignment = Alignment.Center) {
        // A de cima por ultimo: a primeira fica na frente.
        for ((rede, coingecko, indice) in fichas.reversed()) {
            val lugar = indice - 1f
            val a = abertura.value
            val respiro = if (parado) 0f else sin(agora.value * 1.3 + indice * 1.1).toFloat() * 2f
            Row(
                Modifier.graphicsLayer {
                    translationY = ((lugar * 6f) + (lugar * 58f - lugar * 6f) * a + respiro) * density
                    rotationZ = lugar * -5f * (1f - a)
                    val escala = (0.94f - 0.02f * kotlin.math.abs(lugar)) + (1f - (0.94f - 0.02f * kotlin.math.abs(lugar))) * a
                    scaleX = escala; scaleY = escala
                }.width(250.dp).height(52.dp).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
                    .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(horizontal = Espaco.md),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
            ) {
                SeloDaRede(rede, coingecko, 30.dp, Paleta.corpo)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.width(listOf(92, 74, 104)[indice].dp).height(7.dp).clip(CircleShape).background(Paleta.tinta.copy(alpha = 0.85f)))
                    Box(Modifier.width(listOf(132, 150, 118)[indice].dp).height(6.dp).clip(CircleShape).background(Paleta.tintaApagada.copy(alpha = 0.6f)))
                }
                Icone(Icones.marcadorCheio, Paleta.tintaApagada, tamanho = 13.dp)
            }
        }
    }
}

/** Salvar um endereco: a rede, o endereco conferido na fonte, a tag quando a rede tem, e o nome. */
@Composable
private fun NovoContato() {
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    var rede by remember { mutableStateOf("bitcoin") }
    var endereco by remember { mutableStateOf("") }
    var nome by remember { mutableStateOf("") }
    var tag by remember { mutableStateOf("") }
    var conferencia by remember { mutableStateOf("") }
    var conferenciaDoMemo by remember { mutableStateOf("") }
    var comMemo by remember { mutableStateOf(false) }
    var resposta by remember { mutableStateOf<JSONObject?>(null) }
    var recentes by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var mensagem by remember { mutableStateOf<String?>(null) }
    var salvando by remember { mutableStateOf(false) }
    var escolhendoRede by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { recentes = runCatching { Api.lista("contatos.recentes").objetos() }.getOrDefault(emptyList()) }
    LaunchedEffect(rede, endereco, tag, conferencia, conferenciaDoMemo, comMemo) {
        resposta = runCatching {
            Api.objeto("contatos.conferir", JSONObject().put("rede", rede).put("endereco", endereco).put("tag", tag).put("conferencia", conferencia)
                .put("conferenciaDoMemo", conferenciaDoMemo).put("comMemo", comMemo))
        }.getOrNull()
    }
    // Endereco ou rede novos: a conferencia comeca de novo.
    LaunchedEffect(rede, endereco) {
        conferencia = ""
        comMemo = false
        conferenciaDoMemo = ""
    }

    val r = resposta
    val valido = r?.optBoolean("valido") == true
    val conferido = r?.optBoolean("conferido") == true
    val memoConferido = r?.optBoolean("memoConferido", true) != false
    val tipoDeTag = r?.optString("tipoDeTag") ?: "none"
    val desafio = valido && (r?.has("outroID") == true || r?.has("trecho") == true)
    val redeAtual = Redes.rede(rede)

    fun salvar() {
        mensagem = null
        salvando = true
        escopo.launch {
            try {
                val salvo = Autorizacao.tentando(t("Salvar o endereço de %@", nome.trim().take(40))) { credencial ->
                    val corpo = JSONObject().put("rede", rede).put("endereco", endereco).put("nome", nome).put("tag", tag).put("conferencia", conferencia)
                        .put("credencial", credencial.json())
                    if (comMemo) corpo.put("conferenciaDoMemo", conferenciaDoMemo)
                    Api.comSegredo("contatos.salvar", corpo, *credencial.partes())
                }
                if (salvo != null) {
                    App.recarregar()
                    Navegacao.fechar()
                }
            } catch (falha: FalhaDoNucleo) {
                when (falha.codigo) {
                    "contato.conferirMemo" -> comMemo = true
                    "contato.naoConferido" -> mensagem = t("Confira o endereço antes de salvar.")
                    "contato.tagInvalida" -> mensagem = t("A tag é um número de 0 a 4.294.967.295. Confira na exchange.")
                    "contato.memoInvalido" -> mensagem = t("O memo cabe até 28 caracteres.")
                    else -> mensagem = Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível salvar. Tente de novo.")
                }
            } finally {
                salvando = false
            }
        }
    }

    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().acimaDoTeclado()) {
        CabecalhoDeFolha(t("Salvar endereço"), null, aoVoltar = { Navegacao.fechar() })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.lg),
               verticalArrangement = Arrangement.spacedBy(Espaco.lg)) {
            if (endereco.isEmpty() && recentes.isNotEmpty()) {
                Rotulado(t("Enviados recentemente")) {
                    Column(Modifier.clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)) {
                        for (item in recentes) {
                            Row(
                                Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).clickable {
                                    rede = item.getString("rede")
                                    endereco = item.getString("endereco")
                                }.padding(horizontal = Espaco.sm),
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                            ) {
                                SeloDaRede(item.getString("rede"), item.getString("redeCoingecko"), 22.dp, Paleta.corpo)
                                Text(Formato.endereco(item.getString("endereco")), style = estilo(Tipo.monoPequeno), color = Paleta.tinta, modifier = Modifier.weight(1f))
                            }
                        }
                    }
                }
            }
            Rotulado(t("Nome")) {
                Campo(nome, t("Ex.: Minha conta na corretora")) { nome = it.take(40) }
            }
            Rotulado(t("Rede")) {
                Row(
                    Modifier.fillMaxWidth().height(Altura.campo).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
                        .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).clickable { escolhendoRede = !escolhendoRede }.padding(horizontal = Espaco.md),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    redeAtual?.let { SeloDaRede(it.id, it.coingecko, 22.dp, Paleta.corpo) }
                    Text(redeAtual?.nome ?: rede, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
                    Icone(if (escolhendoRede) Icones.acima else Icones.abaixo, Paleta.tintaApagada, tamanho = 13.dp)
                }
                if (escolhendoRede) {
                    Row(Modifier.padding(top = Espaco.xs).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                        for (opcao in Redes.todas) Chip(opcao.nome, opcao.id == rede) { rede = opcao.id; escolhendoRede = false }
                    }
                }
            }
            Rotulado(t("Endereço")) {
                if (desafio) {
                    app.escalibur.wallet.ui.enviar.CampoEscondido { endereco = "" }
                } else {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = Altura.campo).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
                            .border(1.dp, if (valido) Paleta.alta.copy(alpha = 0.6f) else Paleta.borda, RoundedCornerShape(Raio.cartao))
                            .padding(start = Espaco.md, end = Espaco.xs, top = Espaco.xs, bottom = Espaco.xs),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.weight(1f)) {
                            if (endereco.isEmpty()) Text(t("Cole ou escaneie"), style = estilo(Tipo.corpo), color = Paleta.tintaMorta)
                            BasicTextField(
                                endereco, { endereco = it.take(512) }, maxLines = 3, textStyle = estilo(Tipo.mono).copy(color = Paleta.tinta),
                                cursorBrush = SolidColor(Paleta.acento),
                                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = KeyboardType.Ascii),
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                        if (endereco.isEmpty()) {
                            Box(Modifier.size(Altura.toque).clickable {
                                val gerente = contexto.getSystemService(ClipboardManager::class.java)
                                endereco = runCatching { gerente.primaryClip?.getItemAt(0)?.coerceToText(contexto)?.toString() }.getOrNull().orEmpty().trim().take(512)
                            }, contentAlignment = Alignment.Center) { Icone(Icones.colar, Paleta.tintaSuave, tamanho = 16.dp, descricao = t("Colar")) }
                            Box(Modifier.size(Altura.toque).clickable {
                                Navegacao.folha {
                                    LeitorDeQR(aoFechar = { Navegacao.fechar() }) { lido ->
                                        Navegacao.fechar()
                                        // O mesmo leitor do envio: frase nunca entra, link de outra rede tambem nao, e a tag vem junto.
                                        escopo.launch {
                                            val link = runCatching { Api.objeto("contatos.link", JSONObject().put("texto", lido).put("rede", rede)) }.getOrNull() ?: return@launch
                                            endereco = link.optString("endereco")
                                            link.opcional("tag")?.let { tag = it }
                                            mensagem = link.opcional("problema")
                                        }
                                    }
                                }
                            }, contentAlignment = Alignment.Center) { Icone(Icones.qr, Paleta.tintaSuave, tamanho = 16.dp, descricao = t("Ler QR")) }
                        }
                    }
                }
                r?.opcional("problema")?.takeIf { it.isNotEmpty() }?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.baixa, modifier = Modifier.padding(top = Espaco.xs)) }
                r?.optJSONObject("sugestao")?.let { sugestao ->
                    BotaoSecundario(t("Parece um endereço da %@. Usar a %@?", sugestao.getString("nome"), sugestao.getString("nome")), Modifier.padding(top = Espaco.xs)) {
                        rede = sugestao.getString("id")
                    }
                }
                // O endereco confere com a rede escolhida: o verde de que pode seguir, como no iOS.
                if (valido && r?.has("sugestao") != true) {
                    Row(Modifier.padding(top = Espaco.xs), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icone(Icones.vistoCheio, Paleta.alta, tamanho = 14.dp)
                        Text(t("Endereço válido na %@", redeAtual?.nome ?: rede), style = estilo(Tipo.nota), color = Paleta.alta)
                    }
                }
            }
            if (valido) ConferenciaDoContato(r!!, conferencia) { conferencia = it }
            if (valido && tipoDeTag != "none") {
                Rotulado(if (tipoDeTag == "stellarMemo") t("Memo, se houver") else t("Tag de destino, se houver")) {
                    Campo(tag, if (tipoDeTag == "xrplTag") "Ex.: 123456789" else t("Cole aqui, se tiver"), numerico = tipoDeTag == "xrplTag") { tag = it.take(120) }
                }
            }
            r?.optJSONObject("conflitoDoMemo")?.let { conflito ->
                Column(verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    Faixa(TipoDeFaixa.cautela, t("Mesma conta de um endereço que você já usou, com outro ID"), mensagem = t("Confira o ID com quem vai receber."))
                    EnderecoMarcado(t("%@ · ID %@", conflito.getString("rotulo"), conflito.getString("idConhecido")), conflito.getString("conhecido"),
                                    conflito.optJSONObject("trechoConhecido")?.let { Trecho.de(it) })
                    Text(t("Para seguir, digite o memo que quem vai receber mostra, lendo onde você o copiou."), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    CampoCurto(conferenciaDoMemo, t("Memo"), largura = 220.dp) { conferenciaDoMemo = it }
                }
            }
            mensagem?.let { Faixa(TipoDeFaixa.falha, it) }
        }
        Rodape {
            BotaoPrimario(t("Salvar"), ligado = nome.isNotBlank() && valido && conferido && memoConferido, carregando = salvando) { salvar() }
        }
    }
}

/** O trecho do meio digitado olhando a fonte: onde o colado difere do parecido, ou um trecho escondido. */
@Composable
private fun ConferenciaDoContato(r: JSONObject, conferencia: String, aoMudar: (String) -> Unit) {
    val destino = r.opcional("destino") ?: return
    val parecido = r.optJSONObject("parecido")
    val outro = r.optJSONObject("outroID")
    val trecho = r.optJSONObject("trecho")?.let { Trecho.de(it) }
    when {
        outro != null -> Column(verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            Faixa(TipoDeFaixa.cautela, t("Mesma conta de um endereço que você já usou, com outro ID"), mensagem = t("Confira o ID com quem vai receber."))
            EnderecoMarcado(t("Você colou"), destino, outro.optJSONObject("trechoColado")?.let { Trecho.de(it) }, escondido = true)
            EnderecoMarcado(t("%@ · ID %@", outro.getString("rotulo"), outro.getString("idConhecido")), outro.getString("conhecido"),
                            outro.optJSONObject("trechoConhecido")?.let { Trecho.de(it) })
            Text(t("Para seguir, digite o número do ID que quem vai receber mostra, ou os 6 últimos caracteres do endereço, lendo onde você o copiou."),
                 style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            CampoCurto(conferencia, t("Número do ID"), largura = 220.dp, aoMudar = aoMudar)
        }
        trecho != null -> Column(verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            if (parecido != null) {
                Faixa(TipoDeFaixa.cautela, t("Endereço parecido com um que você já usou"), mensagem = t("As pontas são iguais, o meio é diferente. Confira na fonte antes de salvar."))
                EnderecoMarcado(t("Você colou"), destino, trecho)
                EnderecoMarcado(parecido.getString("rotulo"), parecido.getString("conhecido"), parecido.optJSONObject("trechoConhecido")?.let { Trecho.de(it) })
            } else {
                EnderecoMarcado(t("Confira com a fonte"), r.getString("fonte"), trecho, escondido = true)
            }
            Text(
                if (parecido == null) t("Olhando onde você copiou o endereço, digite os 6 caracteres escondidos. Um programa no computador pode trocar o endereço na hora de copiar.")
                else t("Olhando onde você copiou o endereço, digite os 6 caracteres marcados. Um programa no computador pode trocar o endereço na hora de copiar."),
                style = estilo(Tipo.nota), color = Paleta.tintaSuave,
            )
            CampoCurto(conferencia, if (parecido == null) t("6 escondidos") else t("6 marcados"), aoMudar = aoMudar)
        }
    }
}

@Composable
private fun Rotulado(rotulo: String, conteudo: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Text(rotulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        conteudo()
    }
}

@Composable
private fun Campo(texto: String, dica: String, numerico: Boolean = false, aoMudar: (String) -> Unit) {
    Box(
        Modifier.fillMaxWidth().height(Altura.campo).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
            .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(horizontal = Espaco.md),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (texto.isEmpty()) Text(dica, style = estilo(Tipo.corpo), color = Paleta.tintaMorta)
        BasicTextField(
            texto, aoMudar, singleLine = true, textStyle = estilo(Tipo.corpo).copy(color = Paleta.tinta), cursorBrush = SolidColor(Paleta.acento),
            keyboardOptions = KeyboardOptions(capitalization = if (numerico) KeyboardCapitalization.None else KeyboardCapitalization.Sentences,
                                              keyboardType = if (numerico) KeyboardType.Number else KeyboardType.Text),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
