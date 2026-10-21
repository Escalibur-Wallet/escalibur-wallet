package app.escalibur.wallet.ui.trocar

import androidx.compose.ui.graphics.Color
import app.escalibur.wallet.ui.comp.OpcaoDoMenu
import app.escalibur.wallet.ui.comp.PilulaComMenu
import app.escalibur.wallet.ui.comp.Girando
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.Eventos
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.Segmentado
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.enviar.PedidoDePassphrase
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
import app.escalibur.wallet.ui.textos
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.util.Date

// MARK: O modelo

class RetratoDaPonte(json: JSONObject) {
    val numero = json.getInt("numero")
    val moeda: String = json.getString("moeda")
    val pedePassphrase = json.getBoolean("pedePassphrase")
    val nomeDaCarteira: String = json.getString("nomeDaCarteira")
    private val e = json.getJSONObject("ponte")

    class Moeda(val moeda: String, val simbolo: String, val coingecko: String?, val motivo: String?, val caminho: String, val saldo: String?)
    class Rota(val rota: String, val titulo: String)
    class LinhaDaPonte(j: JSONObject) {
        val id: String = j.getString("id")
        val valor: String = j.getString("valor")
        val titulo: String = j.getString("titulo")
        val detalhe: String = j.getString("detalhe")
        val feito: Boolean = j.getBoolean("feito")
        val chegou: Boolean = j.getBoolean("chegou")
        val de: RetratoDaTroca.Rede? = j.optJSONObject("de")?.let { RetratoDaTroca.Rede(it.getString("id"), it.getString("nome"), it.getString("coingecko")) }
        val para: RetratoDaTroca.Rede? = j.optJSONObject("para")?.let { RetratoDaTroca.Rede(it.getString("id"), it.getString("nome"), it.getString("coingecko")) }
        val deposito: String? = j.opcional("deposito")
        val nomeDoDeposito: String? = j.opcional("nomeDoDeposito")
        val entrega: String? = j.opcional("entrega")
        val nomeDaEntrega: String? = j.opcional("nomeDaEntrega")
    }

    private fun rede(j: JSONObject) = RetratoDaTroca.Rede(j.getString("id"), j.getString("nome"), j.getString("coingecko"))

    val observa: Boolean = e.getBoolean("observa")
    val redesDe: List<RetratoDaTroca.Rede> = e.getJSONArray("redesDe").objetos().map(::rede)
    val redesPara: List<RetratoDaTroca.Rede> = e.getJSONArray("redesPara").objetos().map(::rede)
    val de: RetratoDaTroca.Rede = rede(e.getJSONObject("de"))
    val para: RetratoDaTroca.Rede = rede(e.getJSONObject("para"))
    val podeInverter: Boolean = e.getBoolean("podeInverter")
    val vende: AtivoDaTroca? = e.optJSONObject("vende")?.let(::AtivoDaTroca)
    val chega: AtivoDaTroca? = e.optJSONObject("chega")?.let(::AtivoDaTroca)
    val moedas: List<Moeda> = e.getJSONArray("moedas").objetos().map {
        Moeda(it.getString("moeda"), it.getString("simbolo"), it.opcional("coingecko"), it.opcional("motivo"), it.getString("caminho"), it.opcional("saldo"))
    }
    val valor: String = e.getString("valor")
    val versaoDoValor: Int = e.getInt("versaoDoValor")
    val emMoedaQueSai: Double? = e.duplo("emMoedaQueSai")
    val emMoedaQueChega: Double? = e.duplo("emMoedaQueChega")
    val chegaTexto: String = e.getString("chegaTexto")
    val saldo: String? = e.opcional("saldo")
    val temSaldo: Boolean = e.getBoolean("temSaldo")
    val passou: Boolean = e.getBoolean("passou")
    val chave: String = e.getString("chave")
    val podeCotar: Boolean = e.getBoolean("podeCotar")
    val cotando: Boolean = e.getBoolean("cotando")
    val rotas: List<Rota> = e.getJSONArray("rotas").objetos().map { Rota(it.getString("rota"), it.getString("titulo")) }
    val rota: String? = e.opcional("rota")
    val detalhes: List<String> = e.getJSONArray("detalhes").textos()
    val nota: String? = e.opcional("nota")
    val erro: String? = e.opcional("erro")
    val botao: String = e.getString("botao")
    val botaoLigado: Boolean = e.getBoolean("botaoLigado")
    val etapa: String = e.getString("etapa")
    val revisao: RetratoDaTroca.Revisao? = e.optJSONObject("revisao")?.let { RetratoDaTroca.Revisao(it) }
    val falhaDaMontagem: String? = e.opcional("falhaDaMontagem")
    val valorEmMoeda: Double? = e.duplo("valorEmMoeda")
    val detalheIncerto: String? = e.opcional("detalheIncerto")
    val registro: LinhaDaPonte? = e.optJSONObject("registro")?.let(::LinhaDaPonte)
    val pontes: List<LinhaDaPonte> = e.getJSONArray("pontes").objetos().map(::LinhaDaPonte)
    val emCurso: Boolean = e.getBoolean("emCurso")
}

/** A ponte da aba Trocar: o estado fica no nucleo; a aba que sai e volta pega o mesmo retrato. */
object ControleDaPonte {
    var retrato by mutableStateOf<RetratoDaPonte?>(null)
        private set
    var trabalhando by mutableStateOf(false)

    fun aplicar(json: JSONObject) {
        val novo = runCatching { RetratoDaPonte(json) }.getOrNull() ?: return
        val atual = retrato
        if (atual != null && novo.numero <= atual.numero) return
        retrato = novo
    }

    private val fila = Mutex()
    private val longas = setOf("ponte.cotar", "ponte.revisar", "ponte.remontar", "ponte.retransmitir", "ponte.atualizar")
    private val escopo = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    suspend fun chamar(metodo: String, corpo: JSONObject = JSONObject()): Boolean = try {
        val resposta = if (metodo in longas) Api.objeto(metodo, corpo) else fila.withLock { Api.objeto(metodo, corpo) }
        aplicar(resposta)
        true
    } catch (erro: FalhaDoNucleo) {
        false
    }

    fun definir(mudanca: JSONObject) {
        escopo.launch { chamar("ponte.definir", mudanca) }
    }

    suspend fun trabalhar(metodo: String, corpo: JSONObject = JSONObject()): Boolean {
        trabalhando = true
        try {
            return chamar(metodo, corpo)
        } finally {
            trabalhando = false
        }
    }
}

// MARK: O formulario

/** A ponte: levar a mesma moeda da sua conta numa rede para a sua conta em outra. */
@Composable
fun ColumnScope.FormularioDaPonte() {
    val controle = ControleDaPonte
    val dono = LocalLifecycleOwner.current
    val carteira = App.estado.carteira?.id
    var escolhendo by remember { mutableStateOf<String?>(null) }
    var aberta by remember { mutableStateOf<RetratoDaPonte.LinhaDaPonte?>(null) }
    LaunchedEffect(carteira) { controle.chamar("ponte.estado") }
    LaunchedEffect(Unit) {
        Eventos.eventos.filter { it.nome == "ponte" }.collect { evento -> runCatching { controle.aplicar(JSONObject(evento.json)) } }
    }
    val r = controle.retrato ?: return
    // A cotacao de cada pedido novo, depois de 400 ms. Vale 60 s: a revisao cota de novo.
    LaunchedEffect(r.chave, r.podeCotar, r.etapa) {
        if (!r.podeCotar || r.etapa != "formulario") return@LaunchedEffect
        delay(400)
        controle.chamar("ponte.cotar", JSONObject().put("chave", r.chave))
    }
    // As pontes em curso: o andamento a cada 6 s, so com a aba na tela e o app na frente.
    LaunchedEffect(r.emCurso, carteira) {
        if (!r.emCurso) return@LaunchedEffect
        dono.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                controle.chamar("ponte.atualizar")
                delay(6_000)
            }
        }
    }
    var valor by remember { mutableStateOf(r.valor) }
    LaunchedEffect(r.versaoDoValor) { valor = r.valor }
    fun mudar(mudanca: JSONObject) = controle.definir(mudanca)

    // De e Para em colunas de largura igual: o botao de inverter fica parado no meio.
    Row(Modifier.fillMaxWidth().padding(top = Espaco.md), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(t("De"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            PilulaComMenu(r.de.nome, { SeloDaRede(r.de.id, r.de.coingecko, 20.dp, Color.Transparent) },
                          r.redesDe.map { x -> OpcaoDoMenu(x.id, x.nome) { SeloDaRede(x.id, x.coingecko, 28.dp, Color.Transparent) } },
                          r.de.id, descricao = t("Rede: %@", r.de.nome)) { mudar(JSONObject().put("de", it)) }
        }
        Box(Modifier.size(36.dp).clip(CircleShape).background(Paleta.trilho).clickable(enabled = r.podeInverter) { mudar(JSONObject().put("inverter", true)) },
            contentAlignment = Alignment.Center) {
            Icone(Icones.trocar, if (r.podeInverter) Paleta.tinta else Paleta.tintaMorta, tamanho = 15.dp, descricao = t("Inverter redes"))
        }
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(t("Para"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            PilulaComMenu(r.para.nome, { SeloDaRede(r.para.id, r.para.coingecko, 20.dp, Color.Transparent) },
                          r.redesPara.map { x -> OpcaoDoMenu(x.id, x.nome) { SeloDaRede(x.id, x.coingecko, 28.dp, Color.Transparent) } },
                          r.para.id, descricao = t("Rede: %@", r.para.nome)) { mudar(JSONObject().put("para", it)) }
        }
    }
    Column(Modifier.padding(top = Espaco.md), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        CaixaDeValor(
            t("Você envia"), r.vende, valor, "0", r.saldo, r.emMoedaQueSai?.let { t("≈ %@", Formato.valor(it, r.moeda)) }, r.passou,
            carregando = false, calculado = false,
            aoDigitar = {
                valor = it
                mudar(JSONObject().put("valor", it))
            },
            aoEscolher = { escolhendo = "moeda" },
            aoFracao = if (r.temSaldo) ({ mudar(JSONObject().put("fracao", it)) }) else null,
        )
        CaixaDeValor(
            t("Chega na %@", r.para.nome), r.chega, r.chegaTexto, "0", null, r.emMoedaQueChega?.let { t("≈ %@", Formato.valor(it, r.moeda)) }, false,
            carregando = r.cotando && r.chegaTexto.isEmpty(), calculado = true, aoDigitar = {}, aoEscolher = { escolhendo = "moeda" }, aoFracao = null,
            editavel = false,
        )
    }
    if (r.rotas.size > 1) {
        Segmentado(r.rotas.map { it.rota to it.titulo }, r.rota ?: r.rotas.first().rota, Modifier.fillMaxWidth().padding(top = Espaco.md)) {
            mudar(JSONObject().put("rota", it))
        }
    }
    Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        when {
            r.detalhes.isNotEmpty() -> for (linha in r.detalhes) Text(linha, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            r.erro != null -> Faixa(TipoDeFaixa.neutra, r.erro)
            r.nota != null -> Text(r.nota, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
    }
    if (r.pontes.isNotEmpty()) {
        Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            Text(t("Suas pontes"), style = estilo(Tipo.linha), color = Paleta.tinta)
            for (ponte in r.pontes) LinhaDaPonte(ponte) { aberta = ponte }
        }
    }

    when (escolhendo) {
        "moeda" -> FolhaDeMoedas(r, aoFechar = { escolhendo = null }) { mudar(JSONObject().put("moeda", it)) }
    }
    aberta?.let { linha ->
        Folha("", { aberta = null }) { _ ->
            val atual = r.pontes.firstOrNull { it.id == linha.id } ?: linha
            Column(Modifier.padding(horizontal = Espaco.margem).padding(bottom = Espaco.lg)) { PainelDaPonte(atual) }
        }
    }
}

/** O botao da ponte: revisar, ou receber quando nao ha saldo do que se envia. */
@Composable
fun RodapeDaPonte() {
    val r = ControleDaPonte.retrato ?: return
    Rodape {
        BotaoPrimario(r.botao, ligado = r.botaoLigado && !r.observa, carregando = r.cotando && r.chegaTexto.isEmpty() && r.podeCotar) {
            Navegacao.cobrir { RevisaoDaPonte() }
        }
    }
}

@Composable
private fun LinhaDaPonte(ponte: RetratoDaPonte.LinhaDaPonte, acao: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).clickable(onClick = acao).padding(Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        Box(Modifier.width(42.dp)) {
            ponte.de?.let { SeloDaRede(it.id, it.coingecko, 24.dp, Paleta.corpo) }
            ponte.para?.let { SeloDaRede(it.id, it.coingecko, 24.dp, Paleta.corpo, Modifier.offset(x = 18.dp)) }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(ponte.valor, style = estilo(Tipo.linha), color = Paleta.tinta)
            Text(ponte.titulo, style = estilo(Tipo.nota), color = if (ponte.chegou) Paleta.alta else Paleta.tintaSuave)
        }
        if (!ponte.feito) Girando(Paleta.acento, 18.dp)
    }
}

/** O andamento de uma ponte: o titulo, o que esta acontecendo e os links do deposito e da entrega. */
@Composable
private fun PainelDaPonte(ponte: RetratoDaPonte.LinhaDaPonte) {
    val contexto = LocalContext.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        if (ponte.feito) Icone(if (ponte.chegou) Icones.vistoCheio else Icones.atualizar, if (ponte.chegou) Paleta.alta else Paleta.tintaSuave, tamanho = 40.dp)
        else Girando(Paleta.acento, 36.dp)
        Text(ponte.titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.xs))
        Text(ponte.detalhe, style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
        ponte.deposito?.let { url ->
            Text(t("Depósito no %@", ponte.nomeDoDeposito ?: ""), style = estilo(Tipo.nota), color = Paleta.tinta,
                 modifier = Modifier.padding(top = Espaco.xs).clickable { runCatching { contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } })
        }
        ponte.entrega?.let { url ->
            Text(t("Entrega no %@", ponte.nomeDaEntrega ?: ""), style = estilo(Tipo.nota), color = Paleta.tinta,
                 modifier = Modifier.clickable { runCatching { contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } })
        }
    }
}

@Composable
private fun FolhaDeMoedas(r: RetratoDaPonte, aoFechar: () -> Unit, aoEscolher: (String) -> Unit) {
    Folha(t("Moeda"), aoFechar) { fechar ->
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md),
               verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            Text(t("Da %@ para a %@", r.de.nome, r.para.nome), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(bottom = Espaco.xs))
            for (moeda in r.moedas) {
                val livre = moeda.motivo == null
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.trilho)
                        .clickable(enabled = livre) { fechar { aoEscolher(moeda.moeda) } }.padding(Espaco.sm).alpha(if (livre) 1f else 0.5f),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    LogoDaMoeda(moeda.coingecko, moeda.simbolo, 40.dp, rede = r.de.id, redeCoingecko = r.de.coingecko, anel = Paleta.trilho)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(moeda.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta)
                        Text(moeda.motivo ?: moeda.caminho, style = estilo(Tipo.nota), color = if (livre) Paleta.tintaSuave else Paleta.tintaApagada)
                    }
                    moeda.saldo?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaSuave) }
                    if (moeda.simbolo == r.vende?.simbolo) Icone(Icones.visto, Paleta.acento, tamanho = 15.dp)
                }
            }
        }
    }
}

// MARK: A revisao

/** Revisar a ponte, assinar e acompanhar ate chegar. A tela mostra o plano conferido, nunca a cotacao da API. */
@Composable
fun RevisaoDaPonte() {
    val controle = ControleDaPonte
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    var pediu by remember { mutableStateOf(false) }
    var erro by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        controle.trabalhar("ponte.revisar")
        pediu = true
    }
    val r = controle.retrato
    val etapa = r?.etapa ?: "formulario"
    LaunchedEffect(pediu, etapa) { if (pediu && etapa == "formulario") Navegacao.fechar() }
    // Enviada: o andamento a cada 6 s ate chegar.
    LaunchedEffect(etapa) {
        if (etapa != "enviada" && etapa != "incerta") return@LaunchedEffect
        runCatching { Api.objeto("saldos.atualizar", JSONObject().put("forcar", true)) }
        while (controle.retrato?.registro?.feito == false) {
            controle.chamar("ponte.atualizar")
            delay(6_000)
        }
    }
    val transmitindo = etapa == "enviando"
    fun fechar() {
        escopo.launch {
            controle.chamar("ponte.fechar")
            Navegacao.fechar()
        }
    }
    BackHandler(enabled = !transmitindo) { fechar() }
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
        CabecalhoDeFolha("", if (transmitindo) null else ({ fechar() }))
        Column(Modifier.weight(1f).fillMaxWidth().padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs)) {
            if (r == null) return@Column
            when (etapa) {
                "formulario", "montando" -> {
                    val falha = r.falhaDaMontagem
                    if (falha != null) {
                        Text(t("A ponte não foi montada"), style = estilo(Tipo.titulo), color = Paleta.tinta)
                        Faixa(TipoDeFaixa.falha, falha, Modifier.padding(top = Espaco.md))
                        Spacer(Modifier.weight(1f))
                        BotaoPrimario(t("Tentar de novo"), carregando = controle.trabalhando) { escopo.launch { controle.trabalhar("ponte.remontar") } }
                    } else {
                        EsperaDaPonte(r, null, t("Cotando de novo, conferindo os contratos nas duas redes e simulando antes de mostrar."))
                    }
                }
                "revisao" -> {
                    val revisao = r.revisao ?: return@Column
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = Espaco.md, bottom = Espaco.lg)) {
                        DirecaoDaPonte(r, revisao.sai, revisao.entra)
                        Text(revisao.titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
                        r.valorEmMoeda?.let {
                            Text(t("cerca de %@", Formato.valor(it, r.moeda)), style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = 2.dp))
                        }
                        if (revisao.enderecos.isNotEmpty()) Enderecos(revisao.enderecos, Modifier.padding(top = Espaco.lg))
                        Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                            for ((rotulo, valor) in revisao.linhas) {
                                Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                                    Text(rotulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                                    Text(valor, style = estilo(Tipo.nota), color = Paleta.tinta, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
                                }
                            }
                        }
                        if (revisao.transacoes > 1) {
                            Faixa(TipoDeFaixa.neutra, t("Você vai assinar %lld transações de uma vez", revisao.transacoes), Modifier.padding(top = Espaco.md),
                                  mensagem = t("A autorização vai antes e o depósito logo depois. Se o depósito não sair, a autorização continua valendo, só para este valor e só para o contrato da ponte."))
                        }
                        for (aviso in revisao.avisos) Faixa(TipoDeFaixa.cautela, aviso, Modifier.padding(top = Espaco.sm))
                        (erro ?: revisao.erro)?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
                    }
                    BotaoPrimario(t("Confirmar ponte"), Modifier.padding(top = Espaco.sm), carregando = controle.trabalhando) {
                        escopo.launch {
                            erro = null
                            erro = assinarPonte(r, revisao.titulo)
                        }
                    }
                }
                "enviando" -> EsperaDaPonte(r, t("Enviando para a ponte"), t("Não feche o app até terminar."))
                "enviada" -> {
                    Spacer(Modifier.weight(1f))
                    r.registro?.let { PainelDaPonte(it) }
                    Spacer(Modifier.weight(1f))
                    BotaoPrimario(t("Concluir"), Modifier.padding(top = Espaco.sm)) { fechar() }
                }
                "incerta" -> {
                    Spacer(Modifier.weight(1f))
                    Icone(Icones.pergunta, Paleta.cautela, tamanho = 44.dp)
                    Text(t("Não deu para confirmar o depósito"), style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.md))
                    Text(t("A resposta não veio com certeza, e o que foi assinado pode já estar a caminho. Não monte de novo: enviar de novo usa os mesmos dados e não paga duas vezes. Confira na Atividade antes de qualquer outra operação."),
                         style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs))
                    r.detalheIncerto?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.sm)) }
                    Spacer(Modifier.weight(1f))
                    r.registro?.deposito?.let { url ->
                        BotaoSecundario(t("Procurar no %@", r.registro.nomeDoDeposito ?: "")) {
                            runCatching { contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                        }
                    }
                    BotaoPrimario(t("Enviar de novo"), Modifier.padding(top = Espaco.sm), carregando = controle.trabalhando) {
                        escopo.launch { controle.trabalhar("ponte.retransmitir") }
                    }
                    BotaoTerciario(t("Fechar e acompanhar na Atividade"), Modifier.fillMaxWidth()) { fechar() }
                }
            }
        }
    }
}

@Composable
private fun ColumnScope.EsperaDaPonte(r: RetratoDaPonte, titulo: String?, texto: String) {
    Spacer(Modifier.weight(1f))
    DirecaoDaPonte(r, null, null)
    if (titulo != null) Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = Espaco.lg))
    Text(texto, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center,
         modifier = Modifier.fillMaxWidth().padding(top = if (titulo == null) Espaco.lg else Espaco.xs))
    Spacer(Modifier.weight(1f))
}

@Composable
private fun DirecaoDaPonte(r: RetratoDaPonte, sai: String?, entra: String?) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        for ((indice, par) in listOf(r.vende to sai, r.chega to entra).withIndex()) {
            val (ativo, quantia) = par
            if (indice == 1) {
                Box(Modifier.width(36.dp).heightIn(min = 52.dp), contentAlignment = Alignment.Center) {
                    if (sai == null && entra == null) Girando(Paleta.tintaSuave, 20.dp)
                    else Icone(Icones.avancar, Paleta.tintaSuave, tamanho = 18.dp)
                }
            }
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                LogoDaMoeda(ativo?.coingecko, ativo?.simbolo ?: "", 52.dp, rede = ativo?.rede, redeCoingecko = ativo?.redeCoingecko)
                if (quantia != null) Text(quantia, style = estilo(Tipo.nota), color = Paleta.tinta, textAlign = TextAlign.Center, maxLines = 2)
            }
        }
    }
}

/** Assina e transmite a ponte. A carteira com passphrase pede ela antes da biometria ou do PIN. */
private suspend fun assinarPonte(r: RetratoDaPonte, motivo: String): String? {
    val controle = ControleDaPonte
    var passphrase: PedidoDePassphrase.Resposta? = null
    if (r.pedePassphrase) passphrase = PedidoDePassphrase.pedir(r.nomeDaCarteira) ?: return null
    controle.trabalhando = true
    try {
        val segredo = passphrase?.bytes
        Autorizacao.tentando(motivo) { credencial ->
            val corpo = JSONObject().put("credencial", credencial.json())
            passphrase?.folga?.let { corpo.put("folga", it) }
            val partes = if (segredo != null) credencial.partes(segredo.copyOf()) else credencial.partes()
            controle.aplicar(Api.comSegredo("ponte.assinar", corpo, *partes))
        }
        return null
    } catch (falha: FalhaDoNucleo) {
        controle.chamar("ponte.estado")
        return when (falha.codigo) {
            "passphrase.errada" -> t("A passphrase não confere. Nada foi assinado. Escreva igual ao que você anotou: maiúscula, acento e espaço contam.")
            "passphrase.espera" -> t("Muitas passphrases erradas. Tente de novo às %@.", Formato.relogio(Date(falha.dados.optDouble("ate", 0.0).toLong())))
            "envio.pedePassphrase" -> t("A folga da passphrase acabou. Toque de novo para enviar.")
            "envio.motor" -> falha.dados.optString("mensagem", "").ifEmpty { null } ?: t("A ponte não saiu. Nada foi debitado.")
            else -> Autorizacao.mensagemDeRecusa(falha) ?: t("A ponte não saiu. Nada foi debitado.")
        }
    } finally {
        passphrase?.bytes?.fill(0)
        controle.trabalhando = false
    }
}
