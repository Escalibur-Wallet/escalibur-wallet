package app.escalibur.wallet.ui.receber

import app.escalibur.wallet.ui.comp.OpcaoDoMenu
import app.escalibur.wallet.ui.comp.PilulaComMenu
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.ui.unit.IntOffset
import app.escalibur.wallet.ui.comp.BotaoDeCopiar
import app.escalibur.wallet.ui.comp.Girando
import app.escalibur.wallet.ui.comp.Esqueleto
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.BotaoDoGrupo
import app.escalibur.wallet.ui.comp.CabecalhoDaFolha
import app.escalibur.wallet.ui.comp.PlacaLaqueada
import app.escalibur.wallet.ui.comp.TelaComBarra
import app.escalibur.wallet.ui.carteira.TipoDeSelo
import android.content.Intent
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.carteira.CopiaAgora
import app.escalibur.wallet.ui.carteira.SeloDeToken
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.EnderecoEmBlocos
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.ImagemDoQR
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.comp.Transferencia
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import org.json.JSONObject
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.offset

/** Um ativo que a carteira recebe numa rede (o `Receber.Ativo` do nucleo). */
data class AtivoRecebivel(
    val id: String, val rede: String, val redeNome: String, val redeCoingecko: String, val familia: String, val simbolo: String,
    val nome: String, val coingecko: String?, val nativo: Boolean, val contrato: String?, val usaEmissor: Boolean, val emitido: Boolean,
    val padrao: String, val custom: Boolean, val formaDe: String?, val formaDeRedeNome: String?, val formaDeSimbolo: String?,
) {
    companion object {
        fun de(j: JSONObject) = AtivoRecebivel(
            j.getString("id"), j.getString("rede"), j.getString("redeNome"), j.getString("redeCoingecko"), j.getString("familia"),
            j.getString("simbolo"), j.getString("nome"), j.opcional("coingecko"), j.getBoolean("nativo"),
            j.opcional("contrato"), j.getBoolean("usaEmissor"), j.getBoolean("emitido"), j.getString("padrao"), j.getBoolean("custom"),
            j.opcional("formaDe"), j.opcional("formaDeRedeNome"), j.opcional("formaDeSimbolo"),
        )
    }
}

data class MoedaRecebivel(
    val id: String, val simbolo: String, val nome: String, val coingecko: String?, val custom: Boolean,
    val ativos: List<AtivoRecebivel>, val outrasFormas: List<AtivoRecebivel>, val naCarteira: Boolean,
) {
    val redes: Int get() = ativos.size + outrasFormas.size
    val todas: List<AtivoRecebivel> get() = ativos + outrasFormas
}

/** Uma moeda achada na busca, fora da lista verificada (o `Receber.Resultado` do nucleo). */
data class ResultadoDaBusca(val id: String, val simbolo: String, val nome: String)

/**
 * As redes de uma moeda da busca em que a carteira recebe ela (o `Receber.Redes` do nucleo): cada
 * uma com o contrato, e se a moeda ja esta entre as custom da carteira.
 */
data class MoedaDoCatalogo(
    val id: String, val simbolo: String, val nome: String, val aviso: Boolean,
    val ativos: List<AtivoRecebivel>, val adicionadas: Set<String>, val desligadas: List<String>,
) {
    companion object {
        fun de(j: JSONObject): MoedaDoCatalogo {
            val itens = j.getJSONArray("ativos").objetos()
            return MoedaDoCatalogo(
                j.getString("id"), j.getString("simbolo"), j.getString("nome"), j.getBoolean("aviso"),
                itens.map { AtivoRecebivel.de(it.getJSONObject("ativo")) },
                itens.filter { it.getBoolean("jaAdicionada") }.map { it.getJSONObject("ativo").getString("id") }.toSet(),
                (0 until j.getJSONArray("desligadas").length()).map { j.getJSONArray("desligadas").getString(it) },
            )
        }
    }
}

/** O texto de uma chave que pode faltar (o JSON do Swift omite o nulo). */
fun JSONObject.opcional(chave: String): String? = if (has(chave) && !isNull(chave)) getString(chave) else null

/** Escolher o que receber e mostrar o endereco. */
@Composable
fun FluxoDeReceber(preescolhido: String? = null) {
    val carteira = App.estado.carteira ?: return
    var moedas by remember { mutableStateOf<List<MoedaRecebivel>>(emptyList()) }
    var moeda by remember { mutableStateOf<MoedaRecebivel?>(null) }
    var ativo by remember { mutableStateOf<AtivoRecebivel?>(null) }
    // A moeda tocada na busca, fora da lista, e as redes dela depois de lidas.
    var resultado by remember { mutableStateOf<ResultadoDaBusca?>(null) }
    var catalogo by remember { mutableStateOf<MoedaDoCatalogo?>(null) }
    LaunchedEffect(Unit) {
        moedas = runCatching {
            Api.lista("receber.moedas").objetos().map { j ->
                MoedaRecebivel(
                    j.getString("id"), j.getString("simbolo"), j.getString("nome"), j.opcional("coingecko"), j.getBoolean("custom"),
                    j.getJSONArray("ativos").objetos().map(AtivoRecebivel::de), j.getJSONArray("outrasFormas").objetos().map(AtivoRecebivel::de),
                    j.getBoolean("naCarteira"),
                )
            }
        }.getOrDefault(emptyList())
        if (preescolhido != null) ativo = moedas.flatMap { it.todas }.firstOrNull { it.id == preescolhido }
    }
    // As etapas empurram dentro da folha, como a pilha do iOS: a seguinte entra da direita.
    val etapa = when {
        !carteira.temCopia && !carteira.observacao -> 0
        ativo != null -> 3
        moeda != null || resultado != null -> 2
        else -> 1
    }
    AnimatedContent(
        etapa,
        transitionSpec = {
            val frente = targetState > initialState
            val curva = tween<IntOffset>(380, easing = androidx.compose.animation.core.CubicBezierEasing(0.2f, 0.9f, 0.25f, 1f))
            (slideInHorizontally(curva) { if (frente) it else -it / 3 } togetherWith slideOutHorizontally(curva) { if (frente) -it / 3 else it })
                .using(SizeTransform(clip = false))
        },
        modifier = Modifier.fillMaxSize().background(Paleta.corpo).navigationBarsPadding(),
        label = "receber",
    ) { qual ->
        Box(Modifier.fillMaxSize().background(Paleta.corpo)) {
            val atual = ativo
            val escolhida = moeda
            when {
                qual == 0 -> AntesDaCopia(carteira)
                qual == 3 && atual != null -> {
                    // Da busca com uma rede so, voltar leva a lista, e nao a leitura das redes de novo.
                    val doCatalogo = catalogo?.takeIf { c -> c.ativos.any { it.id == atual.id } }
                    fun voltar() {
                        if (preescolhido != null) return Navegacao.fechar()
                        ativo = null
                        if (doCatalogo != null && doCatalogo.ativos.size == 1) { resultado = null; catalogo = null }
                    }
                    BackHandler { voltar() }
                    val formas = moedas.firstOrNull { m -> m.todas.any { it.id == atual.id } }?.todas ?: listOf(atual)
                    TelaDoEndereco(atual, formas, direto = preescolhido != null, catalogo = doCatalogo, aoTrocar = { ativo = it }) { voltar() }
                }
                qual == 2 && resultado != null -> {
                    val achado = resultado!!
                    BackHandler { resultado = null; catalogo = null }
                    RedesDoCatalogo(achado, catalogo, aoLer = { catalogo = it }, aoVoltar = { resultado = null; catalogo = null }) { ativo = it }
                }
                qual == 2 && escolhida != null -> {
                    BackHandler { moeda = null }
                    EscolhaDaRede(escolhida, aoVoltar = { moeda = null }) { ativo = it }
                }
                else -> Escolha(moedas, aoEscolherResultado = { resultado = it; catalogo = null }) { if (it.redes == 1) ativo = it.ativos.first() else moeda = it }
            }
        }
    }
}

@Composable
internal fun AntesDaCopia(carteira: Carteira) {
    Column(Modifier.fillMaxSize().padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs), horizontalAlignment = Alignment.CenterHorizontally) {
        CabecalhoDeFolha("", { Navegacao.fechar() })
        ArteDaCopiaPrimeiro(280.dp, Modifier.padding(top = Espaco.sm))
        val passphrase = carteira.palavrasConfirmadas
        Text(
            if (passphrase) t("Confira a passphrase antes de receber") else t("Grave a senha da carteira antes de receber"),
            style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.lg),
        )
        Text(
            if (passphrase) t("Você ainda não conferiu a passphrase desta carteira. Se ela estiver anotada errado, o que chegar aqui se perde.")
            else t("Você ainda não confirmou que anotou as palavras desta carteira. Se o celular sumir antes disso, o que chegar aqui se perde."),
            style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm),
        )
        Row(Modifier.padding(top = Espaco.sm), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icone(Icones.relogio, Paleta.tintaApagada, tamanho = 13.dp)
            Text(t("Leva 2 minutos"), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
        Spacer(Modifier.weight(1f))
        BotaoPrimario(if (passphrase) t("Conferir agora") else t("Gravar agora")) {
            Navegacao.fechar()
            Navegacao.cobrir { CopiaAgora(carteira) }
        }
        BotaoSecundario(t("Agora não"), Modifier.padding(top = Espaco.sm)) { Navegacao.fechar() }
    }
}

/** So as moedas: a mesma moeda em redes diferentes e uma linha so; a rede vem depois. */
@Composable
private fun Escolha(moedas: List<MoedaRecebivel>, aoEscolherResultado: (ResultadoDaBusca) -> Unit, aoEscolher: (MoedaRecebivel) -> Unit) {
    var busca by remember { mutableStateOf("") }
    val termo = busca.trim()
    val buscando = termo.length >= 2
    val filtradas = if (termo.isEmpty()) moedas else moedas.filter { it.simbolo.contains(termo, true) || it.nome.contains(termo, true) }
    val naCarteira = filtradas.filter { it.naCarteira }
    val outras = filtradas.filter { !it.naCarteira }
    // Qualquer moeda, fora da lista verificada: a mesma busca do iOS (pedido do dono, 30/10/2026).
    // Uma pergunta por texto, depois de uma pausa curta na digitacao.
    var tentativa by remember { mutableStateOf(0) }
    var resposta by remember { mutableStateOf<Pair<String, JSONObject?>?>(null) }
    LaunchedEffect(termo.lowercase(), tentativa) {
        if (!buscando) return@LaunchedEffect
        resposta = null
        kotlinx.coroutines.delay(350)
        resposta = termo.lowercase() to runCatching { Api.objeto("receber.buscar", JSONObject().put("texto", termo)) }.getOrNull()
    }
    val listadas = moedas.mapNotNull { it.coingecko }.toSet()
    Column(Modifier.fillMaxSize()) {
        // A moeda que nao esta na lista, pelo contrato colado (o "+" do iOS).
        CabecalhoDaFolha(t("Receber"), { Navegacao.fechar() },
                         extra = Triple(Icones.mais, t("Adicionar moeda pelo contrato")) {
                             Navegacao.folha { app.escalibur.wallet.ui.carteira.AdicionarMoedaCustom { Navegacao.fechar() } }
                         })
        CampoDeBusca(busca, t("Buscar qualquer moeda"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md), superficie = Paleta.trilho) { busca = it }
        LazyColumn(Modifier.fillMaxSize().padding(top = Espaco.xs)) {
            if (naCarteira.isNotEmpty()) {
                item { TituloDeSecao(t("Na carteira")) }
                items(naCarteira, key = { "c" + it.id }) { LinhaDeMoeda(it) { aoEscolher(it) } }
            }
            if (outras.isNotEmpty()) {
                if (naCarteira.isNotEmpty() || buscando) item { TituloDeSecao(if (buscando) t("Verificadas") else t("Todas")) }
                items(outras, key = { "o" + it.id }) { LinhaDeMoeda(it) { aoEscolher(it) } }
            }
            if (buscando) {
                val atual = resposta?.takeIf { it.first == termo.lowercase() }
                val r = atual?.second
                when {
                    atual == null -> {
                        item { TituloDeSecao(t("Mais moedas, fora da lista verificada")) }
                        items(3) { LinhaEsperando() }
                    }
                    r == null || r.optString("estado") == "falhou" -> item {
                        Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md)) {
                            NotaDaBusca(t("O CoinGecko não respondeu agora. Aparecem só as moedas verificadas."))
                            BotaoTerciario(t("Buscar de novo")) { tentativa++ }
                        }
                    }
                    r.optString("estado") == "frase" -> item {
                        Box(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md)) {
                            NotaDaBusca(t("Isto parece o começo das palavras de uma carteira, e a busca não saiu do celular. As palavras só se digitam ao importar uma carteira."))
                        }
                    }
                    else -> {
                        val achados = r.getJSONArray("resultados").objetos()
                            .map { ResultadoDaBusca(it.getString("id"), it.getString("simbolo"), it.getString("nome")) }
                            .filter { it.id !in listadas }
                        if (achados.isNotEmpty()) {
                            item { TituloDeSecao(t("Mais moedas, fora da lista verificada")) }
                            items(achados, key = { "b" + it.id }) { achado -> LinhaDoResultado(achado) { aoEscolherResultado(achado) } }
                        } else if (filtradas.isEmpty()) {
                            item { Box(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md)) { NotaDaBusca(t("Nenhuma moeda com esse nome ou símbolo.")) } }
                        }
                    }
                }
            }
            item { Spacer(Modifier.height(Espaco.lg)) }
        }
    }
}

@Composable
fun CampoDeBusca(texto: String, dica: String, modifier: Modifier = Modifier, superficie: androidx.compose.ui.graphics.Color = Paleta.corpo, aoMudar: (String) -> Unit) {
    Row(
        modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(Raio.cartao)).background(superficie)
            .padding(start = Espaco.md, end = if (texto.isEmpty()) Espaco.md else Espaco.xxs),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs),
    ) {
        Icone(Icones.busca, Paleta.tintaApagada, tamanho = 17.dp)
        Box(Modifier.weight(1f)) {
            if (texto.isEmpty()) Text(dica, style = estilo(Tipo.corpo), color = Paleta.tintaApagada)
            BasicTextField(
                texto, aoMudar, singleLine = true, textStyle = estilo(Tipo.corpo).copy(color = Paleta.tinta),
                cursorBrush = SolidColor(Paleta.acento),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (texto.isNotEmpty()) Box(Modifier.size(width = 32.dp, height = 44.dp).clickable { aoMudar("") }, contentAlignment = Alignment.Center) {
            Icone(Icones.fecharCheio, Paleta.tintaApagada, tamanho = 17.dp, descricao = t("Limpar busca"))
        }
    }
}

@Composable
private fun TituloDeSecao(texto: String) {
    Text(texto, style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md, bottom = Espaco.xxs))
}

@Composable
private fun LinhaDeMoeda(moeda: MoedaRecebivel, aoTocar: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = aoTocar).heightIn(min = Altura.linha).padding(horizontal = Espaco.margem),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        val unica = moeda.ativos.singleOrNull()
        LogoDaMoeda(moeda.coingecko, moeda.simbolo, 36.dp, anel = Paleta.corpo, naoConferido = moeda.custom,
                    rede = if (moeda.custom) unica?.rede else null, redeCoingecko = if (moeda.custom) unica?.redeCoingecko else null)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(moeda.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta)
                if (moeda.custom) SeloDeToken(TipoDeSelo.custom)
            }
            Text(if (moeda.custom) t("%@ na %@", moeda.nome, unica?.redeNome ?: "") else moeda.nome,
                 style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
        }
        if (moeda.redes > 1) Text(t("%lld redes", moeda.redes), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 14.dp)
    }
}

@Composable
private fun NotaDaBusca(texto: String) {
    Text(texto, style = estilo(Tipo.nota), color = Paleta.tintaApagada)
}

/** O lugar de uma moeda enquanto a busca responde. */
@Composable
private fun LinhaEsperando() {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Altura.linha).padding(horizontal = Espaco.margem),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(Paleta.trilho))
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Esqueleto(72.dp, 14.dp)
            Esqueleto(140.dp, 12.dp)
        }
    }
}

@Composable
private fun LinhaDoResultado(achado: ResultadoDaBusca, aoTocar: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = aoTocar).heightIn(min = Altura.linha).padding(horizontal = Espaco.margem),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        LogoDaMoeda(achado.id.takeUnless { it.startsWith("paprika:") }, achado.simbolo, 36.dp, anel = Paleta.corpo)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(achado.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
            Text(achado.nome, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
        }
        Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 14.dp)
    }
}

/**
 * Tocou numa moeda da busca: le as redes dela e segue para o endereco (uma rede), a escolha da rede
 * (mais de uma) ou o aviso de que ainda nao recebe aqui. O mesmo `catalogLookup` do iOS.
 */
@Composable
private fun RedesDoCatalogo(
    achado: ResultadoDaBusca, lida: MoedaDoCatalogo?, aoLer: (MoedaDoCatalogo) -> Unit, aoVoltar: () -> Unit, aoEscolher: (AtivoRecebivel) -> Unit,
) {
    var falhou by remember(achado.id) { mutableStateOf(false) }
    var tentativa by remember(achado.id) { mutableStateOf(0) }
    LaunchedEffect(achado.id, tentativa) {
        if (lida != null) return@LaunchedEffect
        falhou = false
        val r = runCatching {
            Api.objeto("receber.redes", JSONObject().put("id", achado.id).put("simbolo", achado.simbolo).put("nome", achado.nome))
        }.getOrNull()
        if (r == null) { falhou = true; return@LaunchedEffect }
        val moeda = MoedaDoCatalogo.de(r)
        aoLer(moeda)
        moeda.ativos.singleOrNull()?.let(aoEscolher)
    }
    TelaComBarra(aoVoltar = aoVoltar, fundo = Paleta.corpo) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(horizontal = Espaco.margem).padding(top = Espaco.xs, bottom = Espaco.lg)) {
            when {
                falhou -> {
                    Text(t("Receber %@", achado.simbolo), style = estilo(Tipo.titulo), color = Paleta.tinta)
                    Text(t("O CoinGecko não respondeu agora, e sem ele a carteira não sabe em que rede esta moeda existe."),
                         style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
                    BotaoSecundario(t("Tentar de novo"), Modifier.padding(top = Espaco.md)) { tentativa++ }
                }
                lida == null || lida.ativos.size == 1 -> Column(Modifier.fillMaxWidth().padding(top = Espaco.xl), horizontalAlignment = Alignment.CenterHorizontally) {
                    Girando(Paleta.tintaSuave)
                    Text(t("Buscando as redes de %@", achado.simbolo), style = estilo(Tipo.nota), color = Paleta.tintaSuave, textAlign = TextAlign.Center,
                         modifier = Modifier.padding(top = Espaco.md))
                }
                lida.ativos.isEmpty() -> {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                        LogoDaMoeda(achado.id.takeUnless { it.startsWith("paprika:") }, lida.simbolo, 32.dp, anel = Paleta.corpo)
                        Text(t("Receber %@", lida.simbolo), style = estilo(Tipo.titulo), color = Paleta.tinta)
                    }
                    // Mandar para um endereco de outra rede perderia o valor.
                    Text(
                        if (lida.desligadas.isEmpty()) t("A Escalibur ainda não recebe %@: ela existe só em redes que a carteira não tem, ou em que a carteira ainda não mostra token fora da lista. Não envie %@ para nenhum endereço desta carteira.", lida.simbolo, lida.simbolo)
                        else t("%@ existe na %@, que está desligada nesta carteira. Ligue a rede em Ajustes para receber.", lida.simbolo, lida.desligadas.joinToString(", ")),
                        style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm),
                    )
                }
                else -> {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                        LogoDaMoeda(achado.id.takeUnless { it.startsWith("paprika:") }, lida.simbolo, 32.dp, anel = Paleta.corpo)
                        Text(t("Receber %@", lida.simbolo), style = estilo(Tipo.titulo), color = Paleta.tinta)
                    }
                    Text(t("Escolha a rede. Tem de ser a mesma que quem envia escolher: %@ enviado por outra rede não chega a este endereço.", lida.simbolo),
                         style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
                    Column(Modifier.padding(top = Espaco.md)) {
                        for (ativo in lida.ativos) LinhaDeRede(ativo, ativo.redeNome, t("%@ · não verificado", ativo.padrao)) { aoEscolher(ativo) }
                    }
                }
            }
        }
    }
}

/** A rede. Quem envia escolhe a rede do lado de la; as duas tem de ser a mesma. */
@Composable
private fun EscolhaDaRede(moeda: MoedaRecebivel, aoVoltar: () -> Unit, aoEscolher: (AtivoRecebivel) -> Unit) {
    TelaComBarra(aoVoltar = aoVoltar, fundo = Paleta.corpo) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(horizontal = Espaco.margem).padding(top = Espaco.xs, bottom = Espaco.lg)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                LogoDaMoeda(moeda.coingecko, moeda.simbolo, 32.dp, anel = Paleta.corpo)
                Text(t("Receber %@", moeda.simbolo), style = estilo(Tipo.titulo), color = Paleta.tinta)
            }
            Text(t("Escolha a rede. Tem de ser a mesma que quem envia escolher: %@ enviado por outra rede não chega a este endereço.", moeda.simbolo),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
            Column(Modifier.padding(top = Espaco.md)) {
                for (ativo in moeda.ativos) LinhaDeRede(ativo, ativo.redeNome, if (ativo.nativo) null else ativo.padrao.ifEmpty { null }) { aoEscolher(ativo) }
                for (ativo in moeda.outrasFormas) {
                    LinhaDeRede(ativo, ativo.redeNome, listOf(ativo.padrao, "${ativo.simbolo} · ${ativo.nome}").filter { it.isNotEmpty() }.joinToString(" · ")) { aoEscolher(ativo) }
                }
            }
            if (moeda.outrasFormas.isNotEmpty()) {
                Text(t("As redes com o nome de um token recebem a versão de %@ emitida naquela rede, que vale o mesmo enquanto o emissor mantiver o lastro. Quem envia tem de escolher exatamente a mesma rede.", moeda.simbolo),
                     style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.sm))
            }
        }
    }
}

@Composable
private fun LinhaDeRede(ativo: AtivoRecebivel, titulo: String, detalhe: String?, aoTocar: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = aoTocar).heightIn(min = Altura.linha),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        SeloDaRede(ativo.rede, ativo.redeCoingecko, 32.dp, Paleta.corpo)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            if (detalhe != null) Text(detalhe, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
        Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 14.dp)
    }
}

/** O endereco: o QR com o logo da moeda, a rede, o endereco em blocos, o aviso da rede, copiar e compartilhar. */
@Composable
private fun TelaDoEndereco(
    ativo: AtivoRecebivel, formas: List<AtivoRecebivel>, direto: Boolean, catalogo: MoedaDoCatalogo? = null,
    aoTrocar: (AtivoRecebivel) -> Unit, aoVoltar: () -> Unit,
) {
    val contexto = LocalContext.current
    var dados by remember(ativo.id) { mutableStateOf<JSONObject?>(null) }
    LaunchedEffect(ativo.id) {
        val pedido = JSONObject().put("ativo", ativo.id)
        // A moeda da busca nao esta na lista da carteira: o endereco e o da conta na rede dela.
        if (catalogo != null) pedido.put("rede", ativo.rede)
        dados = runCatching { Api.objeto("receber.endereco", pedido) }.getOrNull()
    }
    val info = dados ?: return
    val endereco = info.getString("endereco")
    val existe = info.getBoolean("existe")
    // Aberta direto (sem a lista antes): so o fechar no alto, como no iOS; senao, o voltar de vidro.
    TelaComBarra(aoVoltar = if (direto) null else aoVoltar, fundo = Paleta.corpo,
                 acoes = if (direto) ({ BotaoDoGrupo(Icones.fechar, t("Fechar"), Paleta.tintaSuave) { Navegacao.fechar() } }) else null) { espaco ->
    Column(Modifier.fillMaxSize().padding(espaco)) {
        if (info.getBoolean("tronOutraChave")) {
            Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                Text(t("Esta conta na Tron é controlada por outra chave"), style = estilo(Tipo.titulo), color = Paleta.tinta)
                Text(t("Quando esta carteira foi importada, a rede mostrou outra chave no controle da conta na Tron. É o golpe da frase com saldo: o que entrar nela, quem controla essa chave leva. Por isso o app não mostra este endereço."),
                     style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
            }
            return@Column
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(top = Espaco.xs, bottom = Espaco.lg)) {
            // A rede e o token ao lado do titulo; sem espaco (nome longo, texto grande), embaixo.
            TituloDoEndereco(ativo)
            if (info.getBoolean("observacao")) {
                Faixa(TipoDeFaixa.cautela, t("Carteira só de observação"), Modifier.padding(top = Espaco.md),
                      mensagem = t("Este app não tem a chave deste endereço: o que chegar aqui não sai por este app. Se alguém pediu para você observar um endereço e depositar nele, é golpe."))
            }
            // O QR numa placa clara, com o logo da moeda no meio e a rede no selo.
            Box(Modifier.fillMaxWidth().padding(top = Espaco.lg), contentAlignment = Alignment.Center) {
                Box(Modifier.size(280.dp).background(Paleta.viva, PlacaLaqueada(corte = 24.dp)), contentAlignment = Alignment.Center) {
                    ImagemDoQR(endereco, 232.dp)
                    // O fundo redondo sem recortar: o selo da rede passa da borda, como no iOS.
                    Box(Modifier.background(Paleta.viva, CircleShape).padding(5.dp)) {
                        LogoDaMoeda(ativo.formaDe ?: ativo.coingecko, ativo.formaDeSimbolo ?: ativo.simbolo, 48.dp, anel = Paleta.viva,
                                    rede = ativo.rede, redeCoingecko = ativo.redeCoingecko, naoConferido = ativo.custom)
                    }
                }
            }
            if (formas.size > 1) {
                Box(Modifier.fillMaxWidth().padding(top = Espaco.md), contentAlignment = Alignment.Center) { SeletorDeForma(formas, ativo, aoTrocar) }
            }
            EnderecoEmBlocos(endereco, Modifier.padding(top = Espaco.base))
            Text(avisoDaRede(ativo, existe), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.md))
            if (catalogo?.aviso == true) {
                // O texto do aviso e de quem escreveu, com link: a tela so diz que existe.
                Text(t("O CoinGecko publicou um aviso sobre %@ (ataque, migração ou golpe). Confira as notícias da moeda antes de receber.", ativo.simbolo),
                     style = estilo(Tipo.nota), color = Paleta.cautela, modifier = Modifier.padding(top = Espaco.sm))
            }
            ativo.contrato?.let { contrato -> CartaoDoContrato(contrato, ativo, Modifier.padding(top = Espaco.sm), naoVerificado = catalogo != null) }
            if (catalogo != null) {
                Text(t("Contrato listado pelo CoinGecko ou pelo CoinPaprika, fora da lista verificada da Escalibur. Para o saldo aparecer na carteira, adicione a moeda: a carteira lê nome, símbolo e casas na própria rede antes de salvar."),
                     style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.xs))
                if (ativo.id !in catalogo.adicionadas) {
                    BotaoSecundario(t("Adicionar %@ à carteira", ativo.simbolo), Modifier.padding(top = Espaco.xs)) {
                        val contrato = ativo.contrato ?: return@BotaoSecundario
                        Navegacao.folha { app.escalibur.wallet.ui.carteira.AdicionarMoedaCustom(inicial = contrato) { Navegacao.fechar() } }
                    }
                }
            }
            if (ativo.emitido && !info.getBoolean("temLinha")) {
                Text(
                    if (ativo.custom) t("Para receber %@, esta conta precisa antes de uma linha de confiança com o emissor. A Escalibur ainda não abre linha de confiança para moeda custom: sem ela, o envio de quem manda não passa e o valor fica com quem enviou.", ativo.simbolo)
                    else t("Para receber %@, esta conta precisa antes de uma linha de confiança com o emissor do %@. Sem ela, o envio de quem manda não passa e o valor fica com quem enviou. A linha é criada na primeira troca por %@ aqui na carteira.", ativo.simbolo, ativo.simbolo, ativo.simbolo),
                    style = estilo(Tipo.nota), color = Paleta.cautela, modifier = Modifier.padding(top = Espaco.sm),
                )
            }
            BotaoDeCopiar(t("Copiar endereço"), t("Endereço copiado"), Modifier.padding(top = Espaco.lg)) {
                Transferencia.copiar(contexto, endereco)
                Avisos.mostrar(t("Endereço copiado. Depois de colar, confira o endereço inteiro, inclusive o meio."))
            }
            BotaoSecundario(t("Compartilhar"), Modifier.padding(top = Espaco.sm)) {
                val envio = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, endereco)
                contexto.startActivity(Intent.createChooser(envio, null))
            }
        }
    }
}
}

/** "Receber USDT", e ao lado "pela rede Tron" e "Tether · TRC-20"; sem espaco, um embaixo do outro. */
@Composable
private fun TituloDoEndereco(ativo: AtivoRecebivel) {
    val titulo = t("Receber %@", ativo.simbolo)
    val rede = t("pela rede %@", ativo.redeNome)
    val token = if (ativo.nativo) null else listOf(ativo.nome, ativo.padrao).filter { it.isNotEmpty() }.joinToString(" · ")
    val medidor = androidx.compose.ui.text.rememberTextMeasurer()
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val larguraDoTitulo = medidor.measure(titulo, estilo(Tipo.titulo)).size.width
        val larguraDaRede = maxOf(medidor.measure(rede, estilo(Tipo.corpo)).size.width, token?.let { medidor.measure(it, estilo(Tipo.nota)).size.width } ?: 0)
        val cabe = larguraDoTitulo + larguraDaRede + with(androidx.compose.ui.platform.LocalDensity.current) { Espaco.md.roundToPx() } <= constraints.maxWidth
        if (cabe) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, maxLines = 1)
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(rede, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, maxLines = 1)
                    token?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1) }
                }
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(rede, style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                    token?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaSuave) }
                }
            }
        }
    }
}

/** O seletor de rede embaixo do QR, por forma da moeda: a rede, e o token quando nao e a moeda nativa da rede. */
@Composable
private fun SeletorDeForma(formas: List<AtivoRecebivel>, escolhida: AtivoRecebivel, aoEscolher: (AtivoRecebivel) -> Unit) {
    fun titulo(a: AtivoRecebivel) = if (a.nativo) a.redeNome else "${a.redeNome} · ${a.simbolo}"
    PilulaComMenu(titulo(escolhida), { SeloDaRede(escolhida.rede, escolhida.redeCoingecko, 20.dp, androidx.compose.ui.graphics.Color.Transparent) },
                  formas.map { f -> OpcaoDoMenu(f.id, titulo(f)) { SeloDaRede(f.rede, f.redeCoingecko, 28.dp, androidx.compose.ui.graphics.Color.Transparent) } },
                  escolhida.id, descricao = t("Rede: %@", titulo(escolhida))) { id -> formas.firstOrNull { it.id == id }?.let(aoEscolher) }
}

/** O contrato do token, num desenho que nao se confunde com o endereco de deposito. */
@Composable
private fun CartaoDoContrato(contrato: String, ativo: AtivoRecebivel, modifier: Modifier, naoVerificado: Boolean = false) {
    val contexto = LocalContext.current
    Row(
        // Um cartao liso, da cor da folha, como no iOS: o contrato nao se confunde com o endereco.
        modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(start = Espaco.md, end = Espaco.xs, top = Espaco.sm, bottom = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (ativo.custom) SeloDeToken(TipoDeSelo.custom)
                if (naoVerificado) SeloDeToken(TipoDeSelo.naoVerificado)
                Text(if (ativo.usaEmissor) t("Emissor da moeda %@", ativo.simbolo) else t("Contrato da moeda %@", ativo.simbolo), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            }
            Text(contrato, fontFamily = FontFamily.Monospace, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = Paleta.tintaSuave)
        }
        Box(
            Modifier.size(Altura.toque).clickable {
                Transferencia.copiar(contexto, contrato)
                Avisos.mostrar(if (ativo.usaEmissor) t("Emissor do token copiado.") else t("Contrato do token copiado."))
            },
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(36.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) { Icone(Icones.copiar, Paleta.tinta, tamanho = 16.dp) }
        }
    }
}

/** O aviso de cada rede, os mesmos textos do iOS. */
fun avisoDaRede(ativo: AtivoRecebivel, existe: Boolean): String = when (ativo.familia) {
    "evm" -> if (ativo.formaDe != null && ativo.formaDeRedeNome != null && ativo.formaDeSimbolo != null)
        t("Envie só pela rede %@ (%@). Não é %@ da rede %@: por outra rede, não chega como este token.", ativo.redeNome, ativo.padrao, ativo.formaDeSimbolo, ativo.formaDeRedeNome)
    else t("Na exchange, escolha a rede %@. Se vier por outra rede EVM, o saldo aparece naquela rede, desde que ela esteja ligada em Ajustes.", ativo.redeNome)
    "utxo" -> t("Envie só %@, pela rede %@. Outra moeda enviada para este endereço se perde.", ativo.nome, ativo.redeNome)
    "xrpl" -> if (existe) t("Não precisa de tag de destino. Se a exchange pedir, marque que o endereço não tem tag.")
    else t("Esta conta ainda não existe no XRP Ledger. O primeiro recebimento precisa ser de 1 XRP ou mais, e 1 XRP fica reservado pela rede.")
    "stellar" -> if (existe) t("Não precisa de memo. Se a exchange pedir, marque que o endereço não tem memo.")
    else t("Esta conta ainda não existe na Stellar. O primeiro recebimento precisa ser de 1 XLM ou mais, e parte fica reservada pela rede.")
    "solana" -> t("Envie só pela rede Solana. Tokens de outras redes enviados para este endereço se perdem.")
    "tron" -> if (existe) t("Envie só pela rede Tron (TRC-20). USDT de outra rede enviado para este endereço se perde.")
    else t("Esta conta Tron ainda não está ativa. Ela ativa no primeiro recebimento de TRX ou de token.")
    "ton" -> t("Envie só pela rede TON. Não precisa de comentário.")
    "sui" -> t("Na exchange, escolha a rede Sui. O endereço tem o mesmo formato dos endereços Aptos, e um envio pela Aptos não chega aqui.")
    "cardano" -> t("Na exchange, escolha a rede Cardano. Envie só ADA: tokens nativos que chegarem aqui ainda não podem ser movidos pela Escalibur.")
    "polkadot" -> if (existe) t("Na exchange, escolha a rede Polkadot Asset Hub e envie só DOT. DOT enviado pela relay chain antiga não aparece aqui.")
    else t("Na exchange, escolha a rede Polkadot Asset Hub. O primeiro recebimento precisa ser de 0,01 DOT ou mais, o mínimo da rede para a conta existir.")
    "near" -> if (existe) t("Na exchange, escolha a rede NEAR e envie só NEAR. Esta é a conta implícita da carteira, com 64 caracteres, e não precisa de memo.")
    else t("Na exchange, escolha a rede NEAR. Esta é a conta implícita da carteira: ela passa a existir no primeiro recebimento, de qualquer valor, e não precisa de memo.")
    "aptos" -> t("Na exchange, escolha a rede Aptos e envie só APT. O endereço tem o mesmo formato dos endereços Sui, e um envio pela Sui não chega aqui. A conta passa a existir no primeiro recebimento, de qualquer valor.")
    else -> ""
}

/**
 * "Grave a senha antes de receber" (o BackupFirstArt do iOS): o papel da senha sendo escrito, posicao
 * por posicao, ate o selo de conferido; em volta, as redes esperando em orbita. O ciclo recomeca a
 * cada 7 segundos. Com o movimento reduzido, o papel aparece escrito e conferido, parado.
 */
@Composable
private fun ArteDaCopiaPrimeiro(altura: androidx.compose.ui.unit.Dp, modifier: Modifier = Modifier) {
    val parado = app.escalibur.wallet.ui.comp.movimentoReduzido()
    val agora by app.escalibur.wallet.ui.comp.relogio(parado)
    val redes = listOf("bitcoin" to "bitcoin", "ethereum" to "ethereum", "solana" to "solana", "xrpl" to "ripple",
                       "stellar" to "stellar", "tron" to "tron", "ton" to "the-open-network", "base" to "ethereum")
    // Larguras do traco de cada palavra, em fracao da linha: parece letra de mao.
    val tracos = listOf(0.72f, 0.55f, 0.86f, 0.64f, 0.5f, 0.78f, 0.6f, 0.9f, 0.58f, 0.7f, 0.82f, 0.52f)
    val t = if (parado) 5.0 else agora.toDouble() % 7.0
    val some = if (parado) 1f else 1f - ((t - 6.4) / 0.6).toFloat().coerceIn(0f, 1f)
    androidx.compose.foundation.layout.BoxWithConstraints(modifier.fillMaxWidth().height(altura), contentAlignment = Alignment.Center) {
        val raio = minOf(maxWidth, maxHeight) / 2 - 18.dp
        androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) {
            drawCircle(Paleta.borda, raio.toPx(), center, style = androidx.compose.ui.graphics.drawscope.Stroke(1.dp.toPx()))
        }
        redes.forEachIndexed { i, (rede, coingecko) ->
            val angulo = (if (parado) 0.0 else agora / 50.0 * 2 * Math.PI) + i.toDouble() / redes.size * 2 * Math.PI
            SeloDaRede(rede, coingecko, 30.dp, Paleta.corpo,
                       Modifier.offset(raio * kotlin.math.cos(angulo).toFloat(), raio * kotlin.math.sin(angulo).toFloat()))
        }
        // O papel, levemente torto, com as 12 posicoes sendo escritas em ordem.
        Box(Modifier.width(186.dp).graphicsLayer { rotationZ = -3f }) {
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Paleta.viva).padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                for (linha in 0 until 6) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        for (coluna in 0..1) {
                            val indice = linha * 2 + coluna
                            val progresso = (((t - (0.4 + indice * 0.32)) / 0.28).toFloat().coerceIn(0f, 1f)) * some
                            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                Text("${indice + 1}", fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = Paleta.placaApagada,
                                     textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.width(14.dp))
                                Box(Modifier.weight(1f).height(10.dp), contentAlignment = Alignment.CenterStart) {
                                    Box(Modifier.fillMaxWidth().height(2.dp).offset(y = 3.dp).clip(CircleShape).background(Paleta.placaLinha))
                                    Box(Modifier.fillMaxWidth(tracos[indice] * progresso).height(4.dp).clip(CircleShape).background(Paleta.placaTinta))
                                }
                            }
                        }
                    }
                }
            }
            // O selo carimba: passa um pouco do tamanho e volta.
            val selo = app.escalibur.wallet.ui.comp.saltoDeSaida(((t - 4.3) / 0.35).toFloat().coerceIn(0f, 1f))
            if (selo > 0f) Box(
                Modifier.align(Alignment.TopEnd).offset(14.dp, (-14).dp).size(34.dp).graphicsLayer { scaleX = selo * some; scaleY = selo * some; alpha = some }
                    .clip(CircleShape).background(Paleta.acento).border(3.dp, Paleta.corpo, CircleShape),
                contentAlignment = Alignment.Center,
            ) { Icone(Icones.visto, Paleta.sobreAcento, tamanho = 16.dp) }
        }
    }
}
