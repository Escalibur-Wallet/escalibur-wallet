package app.escalibur.wallet.ui.avisos

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Ciclo
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.ajustes.GrupoDeAjustes
import app.escalibur.wallet.ui.ajustes.LinhaComInterruptor
import app.escalibur.wallet.ui.ajustes.LinhaDeAjuste
import app.escalibur.wallet.ui.ajustes.NotaDeAjuste
import app.escalibur.wallet.ui.ajustes.SecaoDeAjustes
import app.escalibur.wallet.ui.ajustes.Subtela
import app.escalibur.wallet.ui.comp.Avisos as Toques
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.Segmentado
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.mercado.DetalheDaMoeda
import app.escalibur.wallet.ui.mercado.MoedaDeMercado
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.principal.Aba
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.receber.CampoDeBusca
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import app.escalibur.wallet.ui.trocar.ControleDaTroca
import app.escalibur.wallet.vigias.Vigia
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Pede a permissao de notificar (do Android 13 em diante) e devolve se ficou permitido. Recusada de
 * vez, o Android nem mostra o pedido: a tela oferece abrir os ajustes do sistema.
 */
@Composable
fun rememberPermissaoDeNotificar(): suspend () -> Boolean {
    val contexto = LocalContext.current
    val espera = remember { arrayOfNulls<CompletableDeferred<Boolean>>(1) }
    val lancador = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> espera[0]?.complete(ok) }
    return remember {
        suspend {
            when {
                Vigia.permitido(contexto) -> true
                Build.VERSION.SDK_INT < 33 -> false
                else -> {
                    val resposta = CompletableDeferred<Boolean>()
                    espera[0] = resposta
                    lancador.launch(Manifest.permission.POST_NOTIFICATIONS)
                    resposta.await() && Vigia.permitido(contexto)
                }
            }
        }
    }
}

/**
 * Com o app destravado: os avisos ligados de fabrica na primeira vez que a carteira abre, e o toque
 * numa notificacao levando ao lugar dela (a moeda no Mercado, a ordem em Trocar, o recebido em
 * Atividade).
 */
@Composable
fun VigiasDaSessao() {
    val contexto = LocalContext.current
    val pedir = rememberPermissaoDeNotificar()
    val temCarteira = App.estado.carteiras.isNotEmpty()
    LaunchedEffect(temCarteira) {
        if (!temCarteira) return@LaunchedEffect
        val oferecer = runCatching { Api.objeto("vigias.padrao").optBoolean("oferecer") }.getOrDefault(false)
        if (!oferecer) return@LaunchedEffect
        // Depois de a carteira aparecer: o pedido do sistema por cima da tela que ainda carrega
        // assustava.
        delay(1500)
        val permitido = pedir()
        runCatching { Api.objeto("vigias.ligarDeFabrica", JSONObject().put("permitido", permitido)) }
        Vigia.conferir(contexto, forcar = true)
    }
    // Coletado, e nao como chave do efeito: zerar o pedido cancelaria a rota no meio.
    LaunchedEffect(Unit) {
        snapshotFlow { Vigia.pedido }.filterNotNull().collect { pedido ->
            Vigia.pedido = null
            Navegacao.fecharTudo()
            when {
                pedido.moeda != null -> {
                    Navegacao.aba = Aba.mercado
                    val lista = runCatching { Api.objeto("mercado.lista", JSONObject().put("moeda", App.estado.moeda)) }.getOrNull()
                    val moeda = lista?.optJSONArray("moedas").objetos().firstOrNull { it.optString("id") == pedido.moeda }?.let(::MoedaDeMercado)
                    if (moeda != null) Navegacao.abrir { DetalheDaMoeda(moeda) }
                }
                pedido.ordem != null -> {
                    ControleDaTroca.aba.definir(JSONObject().put("modo", "limite"))
                    Navegacao.aba = Aba.trocar
                }
                pedido.recebimento -> Navegacao.aba = Aba.atividade
            }
        }
    }
}

/**
 * Com o app aberto, a conferencia de tempos em tempos (o nucleo segura os intervalos: 2 minutos
 * para o recebimento, 10 para os precos). Destravado, as contas e a moeda de agora vao antes.
 */
@Composable
fun ConferenciaAberta() {
    val contexto = LocalContext.current
    LaunchedEffect(Ciclo.primeiroPlano) {
        if (!Ciclo.primeiroPlano) return@LaunchedEffect
        while (true) {
            if (App.estado.fase == "unlocked") runCatching { Api.objeto("vigias.acompanhar") }
            Vigia.conferir(contexto)
            delay(2 * 60 * 1000L)
        }
    }
}

// MARK: Alertas de preco

private class EstadoDosAlertas(j: JSONObject) {
    val ligado = j.optBoolean("ligado")
    val redondos = j.optBoolean("redondos", true)
    val variacao: Double? = if (j.isNull("variacao")) null else j.optDouble("variacao")
    val detalhes = j.optBoolean("detalhes", true)
    val moedas = j.optJSONArray("moedas").objetos()
    val maximo = j.optInt("maximo", 7)
    val limites = j.optJSONArray("limites")?.let { lista -> (0 until lista.length()).map { lista.getDouble(it) } } ?: listOf(5.0, 10.0, 15.0, 20.0)
    val unidade = j.optString("unidade", "usd")
}

/** O valor da linha em Ajustes: "Desligados" ou quantas moedas. */
suspend fun resumoDosAlertas(): String? = runCatching {
    val estado = EstadoDosAlertas(Api.objeto("alertas.estado"))
    when {
        !estado.ligado || estado.moedas.isEmpty() -> t("Desligados")
        estado.moedas.size == 1 -> t("1 moeda")
        else -> t("%lld moedas", estado.moedas.size)
    }
}.getOrNull()

suspend fun resumoDoRecebimento(): String? = runCatching {
    if (Api.objeto("recebimentos.estado").optBoolean("ligado")) t("Ligado") else t("Desligado")
}.getOrNull()

/**
 * Ajustes, Alertas de preco: liga, escolhe quando avisar, o que aparece na tela bloqueada e quais
 * moedas. As moedas da carteira e as favoritas aparecem como sugestao, e o dono marca uma a uma.
 */
@Composable
fun TelaDosAlertas() {
    val contexto = LocalContext.current
    val escopo = rememberCoroutineScope()
    val pedir = rememberPermissaoDeNotificar()
    var estado by remember { mutableStateOf<EstadoDosAlertas?>(null) }
    var negado by remember { mutableStateOf(false) }
    var mercado by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var favoritas by remember { mutableStateOf<List<String>>(emptyList()) }
    var daCarteira by remember { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(Ciclo.vinda) {
        daCarteira = runCatching { Api.objeto("saldos.mostrar").optJSONArray("linhas").objetos().mapNotNull { it.optString("coingecko").takeIf(String::isNotEmpty) } }
            .getOrDefault(emptyList())
        estado = runCatching { EstadoDosAlertas(Api.objeto("alertas.estado")) }.getOrNull()
        negado = estado?.ligado == true && !Vigia.permitido(contexto)
        runCatching { Api.objeto("mercado.lista", JSONObject().put("moeda", App.estado.moeda)) }.getOrNull()?.let { lista ->
            mercado = lista.optJSONArray("moedas").objetos()
            favoritas = lista.optJSONArray("favoritas")?.let { f -> (0 until f.length()).map { f.getString(it) } } ?: emptyList()
        }
    }

    fun mudar(corpo: JSONObject, conferir: Boolean = false) {
        escopo.launch {
            runCatching { Api.objeto("alertas.mudar", corpo) }.getOrNull()?.let { estado = EstadoDosAlertas(it) }
            Vigia.atualizarAgenda(contexto)
            // A moeda nova ganha a base de preco agora: o primeiro aviso dela ja compara.
            if (conferir) Vigia.conferir(contexto, forcar = true)
        }
    }

    fun ligar(ligado: Boolean) {
        if (!ligado) {
            negado = false
            mudar(JSONObject().put("ligado", false))
            return
        }
        escopo.launch {
            if (!pedir()) {
                negado = true
                return@launch
            }
            negado = false
            mudar(JSONObject().put("ligado", true), conferir = true)
        }
    }

    fun alternar(moeda: JSONObject) {
        val id = moeda.optString("id")
        val atual = estado ?: return
        if (atual.moedas.any { it.optString("id") == id }) mudar(JSONObject().put("tirar", id))
        else mudar(JSONObject().put("por", moeda), conferir = true)
    }

    Subtela("") {
        Column(Modifier.fillMaxWidth().padding(horizontal = Espaco.margem).padding(top = Espaco.sm), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(64.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                Icone(Icones.sino, Paleta.tinta, tamanho = 26.dp)
            }
            Text(t("Alertas de preço"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.sm))
            Text(t("O próprio celular confere os preços e avisa quando uma moeda passa de um número redondo ou se mexe forte em 24 h. Sem servidor da Escalibur no caminho."),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs))
        }
        val e = estado ?: return@Subtela
        GrupoDeAjustes(Modifier.padding(top = Espaco.lg)) {
            LinhaComInterruptor(Icones.sino, t("Avisar sobre preços"), e.ligado) { ligar(it) }
        }
        if (negado) {
            Faixa(TipoDeFaixa.cautela, t("As notificações da Escalibur estão desligadas no celular."),
                  Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm), mensagem = t("Ligue nos ajustes do Android, em Notificações."),
                  tituloDaAcao = t("Abrir ajustes do Android")) { Vigia.abrirAjustesDoSistema(contexto) }
        }
        if (e.ligado) {
            SecaoDeAjustes(t("Quando avisar")) {
                LinhaComInterruptor(Icones.alvo, t("Números redondos"), e.redondos, detalhe = t("Ex.: Bitcoin passou de %@", exemplo(mercado, App.estado.moeda))) {
                    mudar(JSONObject().put("redondos", it))
                }
                LinhaComInterruptor(Icones.altaEQueda, t("Alta ou queda forte"), e.variacao != null, detalhe = t("Variação em 24 h acima do limite")) {
                    mudar(if (it) JSONObject().put("variacao", 10.0) else JSONObject().put("semVariacao", true))
                }
                e.variacao?.let { limite ->
                    Segmentado(e.limites.map { it to "${it.toInt()}%" }, limite, Modifier.padding(horizontal = Espaco.md).padding(bottom = Espaco.md)) {
                        mudar(JSONObject().put("variacao", it))
                    }
                }
            }
            Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Text(t("Na tela bloqueada"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                Segmentado(listOf(true to t("Moeda e preço"), false to t("Só o aviso")), e.detalhes) { mudar(JSONObject().put("detalhes", it)) }
                Text(if (e.detalhes) t("Quem pegar o celular bloqueado pode ver a moeda e o preço. Nunca o seu saldo.")
                     else t("A tela bloqueada mostra só \"Alerta de preço\". Moeda e preço aparecem no app, depois do PIN."),
                     style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            }
            SecaoDeAjustes(if (e.moedas.isEmpty()) t("Moedas") else t("Moedas, %@", if (e.moedas.size == 1) t("1 moeda") else t("%lld moedas", e.moedas.size))) {
                for (moeda in e.moedas) {
                    Row(Modifier.fillMaxWidth().heightIn(min = Altura.linha).padding(start = Espaco.md, end = Espaco.xs),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                        LogoDaMoeda(moeda.optString("id"), moeda.optString("symbol"), 32.dp, anel = Paleta.corpo)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(moeda.optString("name"), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(moeda.optString("symbol").uppercase(), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                        }
                        Box(Modifier.size(Altura.toque).clickable { alternar(moeda) }, contentAlignment = Alignment.Center) {
                            Icone(Icones.menos, Paleta.tintaApagada, tamanho = 18.dp, descricao = t("Tirar %@ dos alertas", moeda.optString("name")))
                        }
                    }
                }
                val cheia = e.moedas.size >= e.maximo
                Box(Modifier.alpha(if (cheia) 0.4f else 1f)) {
                    LinhaDeAjuste(Icones.mais, t("Adicionar moeda"), t("%lld de %lld", e.moedas.size, e.maximo)) {
                        if (!cheia) Navegacao.folha { EscolherMoedas(mercado) { escopo.launch { estado = runCatching { EstadoDosAlertas(Api.objeto("alertas.estado")) }.getOrNull() } } }
                    }
                }
            }
            val sugestoes = sugestoes(e, mercado, daCarteira + favoritas)
            if (sugestoes.isNotEmpty() && e.moedas.size < e.maximo) {
                Text(t("Da sua carteira e das favoritas"), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
                     modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg))
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(top = Espaco.xs),
                    horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    for (moeda in sugestoes) {
                        val forma = CircleShape
                        Row(Modifier.height(Altura.chip).clip(forma).background(Paleta.corpo).border(1.dp, Paleta.borda, forma).clickable { alternar(moeda) }
                                .padding(start = 6.dp, end = Espaco.sm),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            LogoDaMoeda(moeda.optString("id"), moeda.optString("simbolo"), 20.dp, anel = Paleta.corpo)
                            Text(moeda.optString("simbolo").uppercase(), style = estilo(Tipo.rotulo), color = Paleta.tinta)
                            Icone(Icones.mais, Paleta.tintaSuave, tamanho = 11.dp)
                        }
                    }
                }
            }
        }
        Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            NotaDeAjuste(t("Sem servidor, quem decide a hora de conferir é o Android: algumas vezes por hora com o celular em uso, menos quando ele está parado ou com pouca bateria. O aviso pode chegar alguns minutos depois do preço passar."))
            NotaDeAjuste(t("Um alerta só sai quando o CoinGecko e o CoinPaprika concordam no preço."))
            NotaDeAjuste(t("A lista de moedas fica neste celular fora do cofre, para o alerta funcionar com o app travado. Nela não entra saldo nem endereço."))
        }
    }
}

/** "R$ 600.000": o numero redondo logo abaixo do preco do Bitcoin de agora, na moeda da lista do Mercado. */
private fun exemplo(mercado: List<JSONObject>, unidade: String): String {
    val preco = mercado.firstOrNull { it.optString("id") == "bitcoin" }?.optDouble("preco") ?: if (unidade == "brl") 600_000.0 else 110_000.0
    val expoente = kotlin.math.floor(kotlin.math.log10(preco)).toInt() - 1
    val passo = Math.pow(10.0, expoente.toDouble())
    val nivel = kotlin.math.floor(preco / passo) * passo
    return Formato.dinheiro(Formato.agrupado(nivel, 0), Formato.simboloDaMoeda(unidade))
}

/**
 * As moedas da carteira e as favoritas que ainda nao estao na lista. Montadas na tela, destravada;
 * nunca gravadas sozinhas.
 */
private fun sugestoes(e: EstadoDosAlertas, mercado: List<JSONObject>, candidatas: List<String>): List<JSONObject> {
    val vigiadas = e.moedas.map { it.optString("id") }.toSet()
    val ids = candidatas.filter { it !in vigiadas }.distinct()
    return ids.mapNotNull { id -> mercado.firstOrNull { it.optString("id") == id } }.take(10).map { moeda ->
        JSONObject().put("id", moeda.optString("id")).put("simbolo", moeda.optString("simbolo")).put("nome", moeda.optString("nome"))
            .apply { moeda.optString("imagem").takeIf { it.isNotEmpty() }?.let { put("imagem", it) } }
    }
}

/** Escolher moedas para os alertas, na lista do Mercado. */
@Composable
private fun EscolherMoedas(mercado: List<JSONObject>, aoMudar: () -> Unit) {
    val contexto = LocalContext.current
    val escopo = rememberCoroutineScope()
    var busca by remember { mutableStateOf("") }
    var vigiadas by remember { mutableStateOf<Set<String>>(emptySet()) }
    var maximo by remember { mutableStateOf(7) }
    LaunchedEffect(Unit) {
        runCatching { EstadoDosAlertas(Api.objeto("alertas.estado")) }.getOrNull()?.let { e ->
            vigiadas = e.moedas.map { it.optString("id") }.toSet()
            maximo = e.maximo
        }
    }
    val filtradas = if (busca.isBlank()) mercado else mercado.filter {
        it.optString("simbolo").contains(busca, ignoreCase = true) || it.optString("nome").contains(busca, ignoreCase = true)
    }
    val cheia = vigiadas.size >= maximo
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().imePadding()) {
        CabecalhoDeFolha(t("Adicionar moeda"), { Navegacao.fechar() })
        CampoDeBusca(busca, t("Buscar moeda"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm)) { busca = it }
        Text(if (cheia) t("Você escolheu %lld moedas, o máximo. Tire uma para escolher outra.", maximo)
             else t("Escolha até %lld moedas: %lld de %lld.", maximo, vigiadas.size, maximo),
             style = estilo(Tipo.nota), color = if (cheia) Paleta.cautela else Paleta.tintaSuave,
             modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm))
        if (mercado.isEmpty()) {
            Faixa(TipoDeFaixa.neutra, t("Não foi possível carregar a lista de moedas agora."), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md))
        }
        LazyColumn(Modifier.weight(1f).padding(top = Espaco.sm), contentPadding = PaddingValues(bottom = Espaco.xl)) {
            items(filtradas, key = { it.optString("id") }) { moeda ->
                val id = moeda.optString("id")
                val marcada = id in vigiadas
                Row(
                    Modifier.fillMaxWidth().heightIn(min = Altura.linha).alpha(if (!marcada && cheia) 0.4f else 1f).clickable {
                        if (!marcada && cheia) return@clickable
                        vigiadas = if (marcada) vigiadas - id else vigiadas + id
                        escopo.launch {
                            val corpo = if (marcada) JSONObject().put("tirar", id)
                            else JSONObject().put("por", JSONObject().put("id", id).put("simbolo", moeda.optString("simbolo")).put("nome", moeda.optString("nome"))
                                .apply { moeda.optString("imagem").takeIf { it.isNotEmpty() }?.let { put("imagem", it) } })
                            runCatching { Api.objeto("alertas.mudar", corpo) }
                            aoMudar()
                            if (!marcada) Vigia.conferir(contexto, forcar = true)
                        }
                    }.padding(horizontal = Espaco.margem),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    LogoDaMoeda(id, moeda.optString("simbolo"), 36.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(moeda.optString("nome"), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(moeda.optString("simbolo").uppercase(), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    }
                    if (marcada) Icone(Icones.vistoCheio, Paleta.sucesso, tamanho = 22.dp)
                    else Box(Modifier.size(22.dp).border(1.5.dp, Paleta.bordaForte, CircleShape))
                }
            }
        }
    }
}

/** O sino no topo da pagina da moeda: liga ou desliga os alertas desta moeda. */
@Composable
fun SinoDoAlerta(id: String, simbolo: String, nome: String, modifier: Modifier = Modifier) {
    val contexto = LocalContext.current
    val escopo = rememberCoroutineScope()
    val pedir = rememberPermissaoDeNotificar()
    var vigiando by remember { mutableStateOf(false) }
    LaunchedEffect(id) {
        vigiando = runCatching { EstadoDosAlertas(Api.objeto("alertas.estado")) }.getOrNull()?.let { e -> e.ligado && e.moedas.any { it.optString("id") == id } } ?: false
    }
    Box(modifier.size(Altura.toque).clickable {
        escopo.launch {
            if (vigiando) {
                runCatching { Api.objeto("alertas.mudar", JSONObject().put("tirar", id)) }
                vigiando = false
                Vigia.atualizarAgenda(contexto)
                Toques.mostrar(t("Alertas de %@ desligados", simbolo.uppercase()))
                return@launch
            }
            if (!pedir()) {
                Toques.mostrar(t("Para receber alertas de preço, ligue as notificações da Escalibur nos ajustes do Android."))
                return@launch
            }
            val e = runCatching {
                EstadoDosAlertas(Api.objeto("alertas.mudar", JSONObject().put("ligado", true).put("por", JSONObject().put("id", id).put("simbolo", simbolo).put("nome", nome))))
            }.getOrNull() ?: return@launch
            if (e.moedas.none { it.optString("id") == id }) {
                Toques.mostrar(t("A lista de alertas já tem %lld moedas", e.maximo))
                return@launch
            }
            vigiando = true
            Toques.mostrar(t("Alertas de %@ ligados", simbolo.uppercase()))
            Vigia.conferir(contexto, forcar = true)
        }
    }, contentAlignment = Alignment.Center) {
        Icone(if (vigiando) Icones.sinoCheio else Icones.sino, if (vigiando) Paleta.tinta else Paleta.tintaSuave, tamanho = 20.dp,
              descricao = if (vigiando) t("Desligar alertas desta moeda") else t("Avisar sobre o preço desta moeda"))
    }
}

// MARK: Aviso de recebimento

/** Ajustes: avisar quando receber moeda, sem servidor. */
@Composable
fun TelaDoRecebimento() {
    val contexto = LocalContext.current
    val escopo = rememberCoroutineScope()
    val pedir = rememberPermissaoDeNotificar()
    var ligado by remember { mutableStateOf<Boolean?>(null) }
    var detalhes by remember { mutableStateOf(false) }
    var negado by remember { mutableStateOf(false) }
    LaunchedEffect(Ciclo.vinda) {
        runCatching { Api.objeto("recebimentos.estado") }.getOrNull()?.let {
            ligado = it.optBoolean("ligado")
            detalhes = it.optBoolean("detalhes")
        }
        negado = ligado == true && !Vigia.permitido(contexto)
    }

    fun aplicar(resposta: JSONObject?) {
        resposta ?: return
        ligado = resposta.optBoolean("ligado")
        detalhes = resposta.optBoolean("detalhes")
    }

    Subtela("") {
        Column(Modifier.fillMaxWidth().padding(horizontal = Espaco.margem).padding(top = Espaco.sm), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(64.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                Icone(Icones.receber, Paleta.tinta, tamanho = 26.dp)
            }
            Text(t("Aviso de recebimento"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.sm))
            Text(t("O próprio celular confere o saldo das suas contas e avisa quando entra moeda. Sem servidor da Escalibur no caminho."),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs))
        }
        val atual = ligado ?: return@Subtela
        GrupoDeAjustes(Modifier.padding(top = Espaco.lg)) {
            LinhaComInterruptor(Icones.sino, t("Avisar quando receber moeda"), atual) { novo ->
                escopo.launch {
                    if (!novo) {
                        negado = false
                        aplicar(runCatching { Api.objeto("recebimentos.desligar") }.getOrNull())
                        Vigia.atualizarAgenda(contexto)
                        return@launch
                    }
                    if (!pedir()) {
                        negado = true
                        return@launch
                    }
                    negado = false
                    aplicar(runCatching { Api.objeto("recebimentos.ligar") }.getOrNull())
                    // A primeira leitura so marca o saldo de partida.
                    Vigia.conferir(contexto, forcar = true)
                }
            }
            if (atual) {
                LinhaComInterruptor(Icones.olho, t("Valor e moeda no aviso"), detalhes,
                                    detalhe = if (detalhes) t("Ex.: Recebeu 100 USDT, na Tron") else t("A tela bloqueada só diz que entrou moeda")) { novo ->
                    detalhes = novo
                    escopo.launch { aplicar(runCatching { Api.objeto("recebimentos.detalhes", JSONObject().put("ligado", novo)) }.getOrNull()) }
                }
            }
        }
        if (negado) {
            Faixa(TipoDeFaixa.cautela, t("As notificações da Escalibur estão desligadas no celular."),
                  Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm), mensagem = t("Ligue nos ajustes do Android, em Notificações."),
                  tituloDaAcao = t("Abrir ajustes do Android")) { Vigia.abrirAjustesDoSistema(contexto) }
        }
        Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            NotaDeAjuste(t("Por segurança, a Escalibur não tem servidor: não existe ninguém para avisar o celular na hora em que a moeda chega. Quem confere é o próprio celular, quando o Android deixa: algumas vezes por hora em uso, menos parado ou com pouca bateria. Por isso o aviso pode chegar alguns minutos depois. Com o app aberto, a conferência é a cada 2 minutos."))
            NotaDeAjuste(t("Para conferir com o app travado, os endereços públicos das suas carteiras e o último saldo visto de cada moeda ficam num arquivo à parte, que abre depois do primeiro desbloqueio do celular, fora dos dados cifrados da carteira. Quem extrair os dados de um celular nesse estado lê esses endereços. Nenhuma chave, frase ou nome de carteira entra nele."))
            NotaDeAjuste(t("Carteiras com passphrase e carteiras com as palavras ainda não confirmadas ficam de fora. Desligar apaga o arquivo."))
            NotaDeAjuste(t("Contam a moeda de cada rede e os tokens da lista conferida. Token fora da lista não avisa: é por ele que chega o spam."))
        }
        Spacer(Modifier.height(Espaco.md))
    }
}
