package app.escalibur.wallet.ui.carteira

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.ajustes.GrupoDeAjustes
import app.escalibur.wallet.ui.ajustes.LinhaComInterruptor
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.Confirmacao
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.TelaComBarra
import app.escalibur.wallet.ui.comp.acimaDoTeclado
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.comp.movimentoReduzido
import app.escalibur.wallet.ui.comp.relogio
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import app.escalibur.wallet.ui.textos
import kotlinx.coroutines.launch
import org.json.JSONObject
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Gerenciar ativos (o `ManageAssetsView` do iOS): ligar e desligar cada ativo na Carteira, os outros
 * tokens sem suspeita, e as moedas custom, com o remover e o adicionar. Esconder tira da Carteira e
 * do total; o saldo continua na rede.
 */
@Composable
fun TelaDeGerenciarAtivos() {
    val escopo = rememberCoroutineScope()
    val retrato = Saldos.retrato
    var ocultos by remember { mutableStateOf<Set<String>>(emptySet()) }
    var custom by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var removendo by remember { mutableStateOf<JSONObject?>(null) }

    fun aplicar(lista: JSONObject) {
        ocultos = lista.optJSONArray("ocultos").textos().toSet()
        custom = lista.optJSONArray("custom").objetos()
    }
    LaunchedEffect(Unit) { runCatching { aplicar(Api.objeto("ativos.lista")) } }
    // Uma moeda custom nova volta para ca: a lista e lida de novo a cada retrato.
    LaunchedEffect(retrato) { runCatching { aplicar(Api.objeto("ativos.lista")) } }

    fun mostrar(id: String, visivel: Boolean) {
        ocultos = if (visivel) ocultos - id else ocultos + id
        escopo.launch { runCatching { Api.objeto("ativos.visivel", JSONObject().put("id", id).put("visivel", visivel)) } }
    }

    TelaComBarra({ Navegacao.fechar() }, titulo = t("Gerenciar ativos")) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(bottom = Espaco.xl)) {
            if (retrato.todasAsLinhas.isNotEmpty()) {
                GrupoDeAjustes(Modifier.padding(top = Espaco.md)) {
                    for (linha in retrato.todasAsLinhas) {
                        LinhaComInterruptor(null, linha.simbolo, linha.id !in ocultos, cor = Paleta.acento, inicio = {
                            LogoDaMoeda(linha.coingecko, linha.simbolo, 28.dp, anel = Paleta.corpo, naoConferido = linha.reconhecido || !linha.conferido)
                        }) { mostrar(linha.id, it) }
                    }
                }
            }
            if (retrato.todosOsOutros.isNotEmpty()) {
                // Outros tokens: fora da lista verificada, sem suspeita.
                Text(t("Outros tokens"), style = estilo(Tipo.cabecalho), color = Paleta.tinta,
                     modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xl))
                Text(t("Fora da lista verificada. Os suspeitos não aparecem aqui: ficam sempre escondidos."), style = estilo(Tipo.nota),
                     color = Paleta.tintaSuave, modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xxs))
                GrupoDeAjustes(Modifier.padding(top = Espaco.sm)) {
                    for (outro in retrato.todosOsOutros) {
                        LinhaComInterruptor(null, outro.simbolo, outro.id !in ocultos, detalhe = t("na %@", Redes.rede(outro.rede)?.nome ?: outro.rede),
                                            cor = Paleta.acento, inicio = {
                            LogoDaMoeda(null, outro.simbolo, 28.dp, anel = Paleta.corpo, naoConferido = true, rede = outro.rede,
                                        redeCoingecko = Redes.rede(outro.rede)?.coingecko)
                        }) { mostrar(outro.id, it) }
                    }
                }
            }

            Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xl), verticalArrangement = Arrangement.spacedBy(Espaco.xxs)) {
                Text(t("Moedas custom"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
                Text(t("Um token que não está na lista verificada e que você quer ver, receber e enviar. A carteira lê nome, símbolo e casas decimais na própria rede antes de salvar."),
                     style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            }
            if (custom.isNotEmpty()) {
                GrupoDeAjustes(Modifier.padding(top = Espaco.sm)) {
                    for (moeda in custom) {
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).padding(start = Espaco.md, end = Espaco.xs),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                        ) {
                            val rede = moeda.optString("rede")
                            LogoDaMoeda(null, moeda.optString("simbolo"), 28.dp, anel = Paleta.corpo, naoConferido = true, rede = rede,
                                        redeCoingecko = Redes.rede(rede)?.coingecko)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(moeda.optString("simbolo"), style = estilo(Tipo.corpo), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text("${moeda.optString("redeNome")} · ${Formato.endereco(moeda.optString("referencia"))}", style = estilo(Tipo.nota),
                                     color = Paleta.tintaSuave, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            Box(Modifier.heightIn(min = Altura.toque).clickable { removendo = moeda }.padding(horizontal = Espaco.xs), contentAlignment = Alignment.Center) {
                                Text(t("Remover"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                            }
                        }
                    }
                }
            }
            BotaoSecundario(t("Adicionar moeda"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md), icone = Icones.mais) {
                Navegacao.folha { AdicionarMoedaCustom { Navegacao.fechar() } }
            }
            val desconhecidos = retrato.tokensDesconhecidos
            if (desconhecidos > 0) {
                Text(
                    if (desconhecidos == 1) t("1 token chegou numa rede em que a carteira ainda só conta quantos são, sem ler nome e contrato. Ele fica escondido.")
                    else t("%lld tokens chegaram numa rede em que a carteira ainda só conta quantos são, sem ler nome e contrato. Eles ficam escondidos.", desconhecidos),
                    style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg),
                )
            }
        }
    }

    removendo?.let { moeda ->
        Confirmacao(
            t("Remover %@?", moeda.optString("simbolo")),
            t("A moeda some da Carteira, de Receber e de Enviar. O saldo continua na rede, e você pode adicionar de novo."),
            t("Remover"),
            aoConfirmar = {
                removendo = null
                escopo.launch { runCatching { aplicar(Api.objeto("tokens.remover", JSONObject().put("id", moeda.optString("id")))) } }
            },
            aoCancelar = { removendo = null },
        )
    }
}

/**
 * Adicionar moeda (o `AddCustomTokenView` do iOS): colar o contrato, e a rede vem dele (ou o codigo e
 * o emissor, no XRP Ledger e na Stellar); ler nome, simbolo e casas na propria rede com dois
 * provedores concordando; conferir a previa com o contrato inteiro e o aviso de nao verificado, e
 * so entao guardar.
 */
@Composable
fun AdicionarMoedaCustom(inicial: String? = null, rede: String? = null, codigoInicial: String? = null, aoTerminar: () -> Unit) {
    val escopo = rememberCoroutineScope()
    // `inicial`: o contrato de uma moeda achada na busca do Receber, ja lido na rede ao abrir. Com a `rede` (um token de "Outros
    // tokens", a escolha do token da troca), le direto nela; com o `codigoInicial`, `inicial` e o emissor da moeda emitida.
    var endereco by remember { mutableStateOf(if (codigoInicial == null) inicial ?: "" else "") }
    var codigo by remember { mutableStateOf(codigoInicial ?: "") }
    var emissor by remember { mutableStateOf(if (codigoInicial != null) inicial ?: "" else "") }
    var emitida by remember { mutableStateOf(codigoInicial != null) }
    var lendo by remember { mutableStateOf(false) }
    var erro by remember { mutableStateOf<String?>(null) }
    var token by remember { mutableStateOf<JSONObject?>(null) }
    var opcoes by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    val rolagem = rememberScrollState()

    fun resposta(r: JSONObject) {
        r.optJSONObject("token")?.let { token = it; return }
        opcoes = r.optJSONArray("opcoes").objetos()
        if (opcoes.isNotEmpty()) return
        val rede = r.optString("redeNome")
        erro = when (r.optString("problema")) {
            "redeSemCustom" -> t("A rede %@ ainda não aceita moeda custom.", rede)
            "vazio" -> t("Cole o endereço do token.")
            "enderecoInvalido" -> t("Este não é um endereço válido na rede %@. Confira se copiou inteiro e se a rede é essa.", rede)
            "codigoInvalido" -> t("Este código de moeda não vale na rede %@.", rede)
            "listada" -> t("%@ com este contrato já está na lista verificada. Ele aparece sozinho na Carteira quando houver saldo.", r.optString("simboloListado"))
            "naoToken" -> t("Este endereço é de um programa da rede, não de um token.")
            "jaNaCarteira" -> t("Esta moeda já está na carteira.")
            "enderecoNenhumaRede" -> t("Este endereço não parece o contrato de uma moeda em nenhuma rede da carteira. Confira se copiou inteiro.")
            "naoAchado" -> t("Não achamos este contrato nas redes da carteira. Confira se copiou inteiro e se a rede é uma das que a carteira usa.")
            "emissor" -> t("O emissor começa com r (XRP Ledger) ou G (Stellar).")
            else -> r.optString("mensagem").ifEmpty { t("Não foi possível ler a moeda na rede agora.") }
        }
    }

    fun ler() {
        erro = null
        opcoes = emptyList()
        lendo = true
        escopo.launch {
            runCatching {
                if (emitida) Api.objeto("tokens.ler", JSONObject().put("codigo", codigo.trim()).put("emissor", emissor.trim()))
                else if (rede != null && (inicial == null || endereco.trim() == inicial)) Api.objeto("tokens.ler", JSONObject().put("rede", rede).put("endereco", endereco.trim()))
                else Api.objeto("tokens.encontrar", JSONObject().put("texto", endereco.trim()))
            }.onSuccess { resposta(it) }.onFailure { erro = t("Não foi possível ler a moeda na rede agora.") }
            lendo = false
            rolagem.scrollTo(0)
        }
    }

    LaunchedEffect(Unit) { if (inicial != null) ler() }
    val conferindo = token
    TelaComBarra(null, titulo = if (conferindo == null) t("Adicionar moeda") else t("Conferir moeda"), fundo = Paleta.vazio) { espaco ->
        Column(Modifier.fillMaxSize().acimaDoTeclado().verticalScroll(rolagem).padding(espaco).padding(horizontal = Espaco.margem).padding(top = Espaco.sm, bottom = Espaco.xl)) {
            if (conferindo != null) {
                PreviaDaMoeda(conferindo, aoAdicionar = {
                    escopo.launch {
                        runCatching { Api.objeto("tokens.adicionar", JSONObject().put("id", conferindo.optString("id"))) }
                            .onSuccess {
                                Avisos.mostrar(t("%@ adicionada. Ela aparece na Carteira, em Receber e em Enviar.", it.optString("simbolo")))
                                aoTerminar()
                            }
                            .onFailure { erro = t("Não foi possível salvar agora. Tente de novo."); token = null }
                    }
                }) { token = null }
                return@Column
            }
            OrbitaDeMoedas(Modifier.padding(bottom = Espaco.md))
            if (emitida) {
                Text(t("Moeda emitida"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
                Text(t("No XRP Ledger e na Stellar, a moeda é o código mais o emissor. A rede sai do emissor: r... é XRP Ledger, G... é Stellar."),
                     style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xxs))
                CampoDaMoeda(t("Código da moeda"), codigo, "USD, SOLO, AQUA...", Modifier.padding(top = Espaco.md)) { codigo = it; erro = null }
                CampoDaMoeda(t("Emissor"), emissor, t("Endereço r... ou G..."), Modifier.padding(top = Espaco.md)) { emissor = it; erro = null }
                BotaoTerciario(t("Voltar para o contrato"), Modifier.padding(top = Espaco.xs)) { emitida = false; erro = null }
            } else {
                Text(t("Contrato do token"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
                Text(t("Cole o endereço do contrato. A Escalibur acha a rede da moeda sozinha."), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
                     modifier = Modifier.padding(top = Espaco.xxs))
                CampoDaMoeda(t("Contrato"), endereco, "0x..., T..., EQ...", Modifier.padding(top = Espaco.md)) { endereco = it; erro = null }
                BotaoTerciario(t("É uma moeda do XRP Ledger ou da Stellar?"), Modifier.padding(top = Espaco.xs)) { emitida = true; erro = null; opcoes = emptyList() }
                if (opcoes.size > 1) {
                    Text(t("Este contrato existe em mais de uma rede. Escolha a da moeda:"), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
                         modifier = Modifier.padding(top = Espaco.md))
                    @OptIn(ExperimentalLayoutApi::class)
                    FlowRow(Modifier.padding(top = Espaco.sm), horizontalArrangement = Arrangement.spacedBy(Espaco.xs), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                        for (opcao in opcoes) EscolhaDeRede(opcao.optString("rede"), opcao.optString("redeNome")) { token = opcao.optJSONObject("token") }
                    }
                }
            }
            Text(t("Copie o endereço da fonte oficial do token, não de um site que apareceu num anúncio ou no nome de outro token."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.sm))
            erro?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
            val podeLer = if (emitida) codigo.isNotBlank() && emissor.isNotBlank() else endereco.isNotBlank()
            BotaoPrimario(if (emitida) t("Ler na rede") else t("Encontrar a moeda"), Modifier.padding(top = Espaco.lg), ligado = podeLer, carregando = lendo) { ler() }
        }
    }
}

/** Um campo da moeda: o rotulo em cima, o texto em letra de endereco e o colar dentro enquanto vazio. */
@Composable
private fun CampoDaMoeda(rotulo: String, texto: String, dica: String, modifier: Modifier = Modifier, aoMudar: (String) -> Unit) {
    val contexto = LocalContext.current
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Text(rotulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
                .padding(start = Espaco.md, end = Espaco.xs, top = Espaco.sm, bottom = Espaco.sm),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs),
        ) {
            Box(Modifier.weight(1f)) {
                if (texto.isEmpty()) Text(dica, style = estilo(Tipo.mono), color = Paleta.tintaMorta, maxLines = 1, overflow = TextOverflow.Ellipsis)
                BasicTextField(texto, aoMudar, textStyle = estilo(Tipo.mono).copy(color = Paleta.tinta), cursorBrush = SolidColor(Paleta.acento), maxLines = 3,
                               keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = KeyboardType.Ascii),
                               modifier = Modifier.fillMaxWidth())
            }
            // Colar dentro do campo, como no iOS.
            if (texto.isEmpty()) {
                Row(
                    Modifier.height(30.dp).clip(CircleShape).background(Paleta.controle).clickable {
                        val gerente = contexto.getSystemService(android.content.ClipboardManager::class.java)
                        runCatching { gerente.primaryClip?.getItemAt(0)?.coerceToText(contexto)?.toString() }.getOrNull()
                            ?.trim()?.takeIf { it.isNotEmpty() }?.let(aoMudar)
                    }.padding(horizontal = 10.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icone(Icones.colar, Paleta.tinta, tamanho = 13.dp)
                    Text(t("Colar"), style = estilo(Tipo.nota), color = Paleta.tinta)
                }
            }
        }
    }
}

/** Uma rede para escolher (o `NetworkChoice` do iOS): o selo da rede e o nome, numa capsula com borda. */
@Composable
private fun EscolhaDeRede(rede: String, nome: String, acao: () -> Unit) {
    Row(
        Modifier.widthIn(min = 132.dp).height(40.dp).clip(CircleShape).border(1.dp, Paleta.borda, CircleShape).clickable(onClick = acao).padding(horizontal = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs),
    ) {
        LogoDaMoeda(Redes.rede(rede)?.coingecko, nome, 22.dp)
        Text(nome, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
    }
}

/** A previa da moeda lida: o nome e os selos, a rede, as casas, o contrato inteiro e os avisos. */
@Composable
private fun PreviaDaMoeda(token: JSONObject, aoAdicionar: () -> Unit, aoVoltar: () -> Unit) {
    val rede = token.optString("rede")
    val redeNome = token.optString("redeNome")
    val motivos = token.optJSONArray("motivos").textos()
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        LogoDaMoeda(null, token.optString("simbolo"), 48.dp, anel = Paleta.vazio, naoConferido = true, rede = rede, redeCoingecko = Redes.rede(rede)?.coingecko)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(token.optString("simbolo"), style = estilo(Tipo.titulo), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis,
                     modifier = Modifier.weight(1f, fill = false))
                SeloDeToken(TipoDeSelo.custom)
                SeloDeToken(if (motivos.isEmpty()) TipoDeSelo.naoVerificado else TipoDeSelo.suspeito)
            }
            Text(token.optString("nome"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 2)
        }
    }
    Column(Modifier.padding(top = Espaco.md)) {
        LinhaDeInformacao(t("Rede"), redeNome)
        LinhaDeInformacao(t("Casas decimais"), token.optInt("casas").toString())
        LinhaDeInformacao(t("Conferido em"), lista(token.optJSONArray("fontes").textos()))
    }
    Text(token.optString("notaDasCasas").takeIf { it.isNotEmpty() && it != "null" }
             ?: t("As duas fontes leram as mesmas casas decimais no contrato. É nessa escala que o valor de um envio é lido."),
         style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.xs))

    // O contrato inteiro, como o dono confere com a fonte.
    PainelDoContrato(token, Modifier.padding(top = Espaco.md))

    Faixa(TipoDeFaixa.cautela, t("Não verificado pela Escalibur"), Modifier.padding(top = Espaco.md),
          mensagem = qualquerUmCriaToken)
    if (motivos.isNotEmpty()) {
        Column(Modifier.padding(top = Espaco.md), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            Text(t("Sinais de golpe neste token"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
            for (motivo in motivos) PontoDoToken(textoDoMotivo(motivo), Icones.alertaContorno, Paleta.cautela)
        }
    }
    val notas = token.optJSONArray("notas").textos()
    if (notas.isNotEmpty()) {
        Column(Modifier.padding(top = Espaco.md), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            for (nota in notas) PontoDoToken(nota, Icones.info, Paleta.tinta)
        }
    }
    token.optString("envioIndisponivel").takeIf { it.isNotEmpty() && it != "null" }?.let {
        PontoDoToken(it, Icones.enviar, Paleta.tinta, Modifier.padding(top = Espaco.md))
    }
    BotaoPrimario(t("Adicionar à carteira"), Modifier.padding(top = Espaco.lg), acao = aoAdicionar)
    BotaoTerciario(t("Voltar e corrigir"), Modifier.fillMaxWidth().padding(top = Espaco.xs), acao = aoVoltar)
}

/** "Uniswap e CoinGecko": a lista com o "e" do idioma. */
private fun lista(itens: List<String>): String = when (itens.size) {
    0 -> ""
    1 -> itens[0]
    else -> t("%@ e %@", itens.dropLast(1).joinToString(", "), itens.last())
}

@Composable
private fun LinhaDeInformacao(rotulo: String, valor: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 36.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(rotulo, style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
        Spacer(Modifier.weight(1f).widthIn(min = Espaco.sm))
        Text(valor, style = estilo(Tipo.corpo), color = Paleta.tinta, textAlign = TextAlign.End)
    }
}

/**
 * O alto de "Adicionar moeda" (o `CoinOrbit` do iOS): logos de moedas girando numa orbita em volta do
 * "+", maiores e acesos quando passam na frente, menores e apagados atras. Com o movimento reduzido, parada.
 * "Observar um endereço" usa a mesma, com o olho no lugar do "+".
 */
@Composable
fun OrbitaDeMoedas(modifier: Modifier = Modifier, icone: ImageVector = Icones.mais) {
    val moedas = listOf("tether" to "USDT", "chainlink" to "LINK", "pepe" to "PEPE", "usd-coin" to "USDC",
                        "uniswap" to "UNI", "shiba-inu" to "SHIB", "aave" to "AAVE", "bonk" to "BONK")
    val parado = movimentoReduzido()
    val agora = relogio(parado)
    Layout(
        content = {
            moedas.forEachIndexed { i, (id, simbolo) ->
                Box(Modifier.graphicsLayer {
                    val angulo = agora.value * 0.32 + i.toDouble() / moedas.size * 2 * Math.PI
                    val fundo = ((sin(angulo) + 1) / 2).toFloat()
                    val e = 0.58f + 0.42f * fundo
                    scaleX = e; scaleY = e
                    alpha = 0.3f + 0.7f * fundo
                }) { LogoDaMoeda(id, simbolo, 40.dp) }
            }
            Box(Modifier.size(60.dp).clip(CircleShape).background(Paleta.controle).border(1.dp, Paleta.borda, CircleShape), contentAlignment = Alignment.Center) {
                Icone(icone, Paleta.tinta, tamanho = 24.dp)
            }
        },
        modifier = modifier.fillMaxWidth().height(132.dp),
    ) { medidos, limites ->
        val pecas = medidos.map { it.measure(limites.copy(minWidth = 0, minHeight = 0)) }
        val largura = limites.maxWidth
        val altura = limites.maxHeight
        layout(largura, altura) {
            val cx = largura / 2f
            val cy = altura / 2f
            val ao = minOf(largura / 2f - 28.dp.toPx(), 150.dp.toPx())
            // As de tras primeiro, o "+" no meio da profundidade, as da frente por cima.
            val ordem = moedas.indices.map { i ->
                val angulo = agora.value * 0.32 + i.toDouble() / moedas.size * 2 * Math.PI
                Triple(i, angulo, (sin(angulo) + 1) / 2)
            }
            for ((i, angulo, fundo) in ordem.filter { it.third < 0.5 }) {
                val p = pecas[i]
                p.place((cx + cos(angulo).toFloat() * ao - p.width / 2f).roundToInt(), (cy + sin(angulo).toFloat() * 30.dp.toPx() - p.height / 2f).roundToInt(), fundo.toFloat())
            }
            val mais = pecas.last()
            mais.place((cx - mais.width / 2f).roundToInt(), (cy - mais.height / 2f).roundToInt(), 0.5f)
            for ((i, angulo, fundo) in ordem.filter { it.third >= 0.5 }) {
                val p = pecas[i]
                p.place((cx + cos(angulo).toFloat() * ao - p.width / 2f).roundToInt(), (cy + sin(angulo).toFloat() * 30.dp.toPx() - p.height / 2f).roundToInt(), fundo.toFloat())
            }
        }
    }
}
