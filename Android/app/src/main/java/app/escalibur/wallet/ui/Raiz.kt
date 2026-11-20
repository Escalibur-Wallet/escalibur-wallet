package app.escalibur.wallet.ui

import android.app.KeyguardManager
import android.content.Context
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.Text
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.BuildConfig
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.Eventos
import app.escalibur.wallet.ui.comp.Transferencia
import kotlinx.coroutines.flow.filter
import app.escalibur.wallet.nucleo.Nucleo
import app.escalibur.wallet.ui.abertura.FluxoDeAbertura
import app.escalibur.wallet.ui.bloqueio.TelaDeBloqueio
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.pin.TelaDoPin
import app.escalibur.wallet.ui.principal.Principal
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

/** O que muda a cada volta do app para a frente: a tela de bloqueio tenta a biometria de novo. */
object Ciclo {
    var vinda by mutableIntStateOf(0)
        private set
    var primeiroPlano by mutableStateOf(true)
        private set
    /** Sobe a cada ida ao fundo: a volta que esperou o nucleo enquanto o app saiu de novo nao vale (revisao final de
     * 07/11/2026). As duas pontas rodam na thread principal. */
    private var saidas = 0

    /**
     * Na hora, sem corrotina: a da Activity era cancelada quando ela morria logo depois, e a volta nao
     * travava (revisao de seguranca do Android de 26/10/2026). A chamada e curta: so anota o instante.
     */
    fun foiParaSegundoPlano() {
        primeiroPlano = false
        saidas++
        // A copia da passphrase da folga sai ja, ate na ida ao seletor, que nao trava; e a folha da passphrase e a do PIN
        // fecham, com o que estava digitado zerado: a operacao que esperava por elas para (05/11/2026).
        app.escalibur.wallet.ui.enviar.PedidoDePassphrase.cancelar()
        Autorizacao.cancelar()
        app.escalibur.wallet.ui.comp.Segredo.limparTodos()
        app.escalibur.wallet.ui.pin.EntradaDoPin.limparTodas()
        app.escalibur.wallet.ui.importar.EntradaDaFrase.limparTodas()
        app.escalibur.wallet.nucleo.PalavrasNaTela.zerarTodas()
        runCatching { Nucleo.chamar("passphrase.encerrarFolgas", "{}") }
        // A biometria que estava na tela cai antes de o nucleo descartar o rosto (auditoria de 03/11/2026).
        app.escalibur.wallet.nucleo.Cofre.cancelarBiometria()
        // O seletor de arquivos do proprio app (salvar ou abrir envelope) e outra Activity: sair para ele
        // nao e sair do app. Com "Ao sair do app", o app travava na volta, e salvar ou abrir envelope
        // nunca terminava (caca de bugs de 27/10/2026). Ate 2 minutos no seletor, nao conta (eram 10: o dono que
        // saia do seletor para outro app deixava a carteira aberta por todo esse tempo; auditoria 8, 14/11/2026).
        if (seletorDesde != null) return
        runCatching { Nucleo.chamar("sessao.segundoPlano", "{}") }
    }

    /** O seletor de arquivos do app vai abrir: a ida a ele nao conta como sair do app (ver acima). */
    fun abrindoSeletor() {
        seletorDesde = android.os.SystemClock.elapsedRealtime()
    }

    private var seletorDesde: Long? = null
    private const val TEMPO_NO_SELETOR = 2 * 60 * 1000L

    /** O nucleo decide se trava antes de a tela voltar: ate a resposta, a capa cobre tudo. */
    suspend fun voltou() {
        val ida = saidas
        val seletor = seletorDesde
        seletorDesde = null
        // Mais que 2 minutos fora pelo seletor: trava como qualquer saida.
        if (seletor != null && android.os.SystemClock.elapsedRealtime() - seletor > TEMPO_NO_SELETOR) {
            runCatching { App.aplicar(Api.objeto("sessao.travar")) }
        }
        runCatching { App.aplicar(Api.objeto("sessao.primeiroPlano")) }
        // O app saiu de novo enquanto o nucleo respondia: a volta nao vale, e a proxima (onStart) refaz. Senao, a leitura das
        // palavras volta a valer aqui tambem (um aviso de tela apagada atrasado pode ter travado depois do onStart): a
        // conferencia e a liberacao rodam juntas na thread principal, sem espera entre elas (revisao final de 07/11/2026).
        if (saidas != ida) {
            // O "segundo plano" do onStop vai na hora e este "primeiro plano" vai pela thread de IO: o nucleo pode ter
            // recebido os dois fora de ordem e apagado a hora da saida, e a proxima volta nao travaria. De novo, com o app no
            // fundo (fora a ida ao seletor, que nao conta como saida). Repetir e seguro.
            if (seletorDesde == null) runCatching { Nucleo.chamar("sessao.segundoPlano", "{}") }
            return
        }
        app.escalibur.wallet.nucleo.PalavrasNaTela.liberar()
        primeiroPlano = true
        vinda++
    }

    /** O celular travou (a tela apagou). Nada a fazer se o nucleo ainda nao abriu. */
    suspend fun travarAgora() {
        app.escalibur.wallet.ui.enviar.PedidoDePassphrase.cancelar()
        Autorizacao.cancelar()
        app.escalibur.wallet.ui.comp.Segredo.limparTodos()
        app.escalibur.wallet.ui.comp.Segredo.zerarAoTravar()
        app.escalibur.wallet.ui.pin.EntradaDoPin.limparTodas()
        app.escalibur.wallet.ui.importar.EntradaDaFrase.limparTodas()
        app.escalibur.wallet.ui.importar.EntradaDaFrase.zerarAoTravar()
        app.escalibur.wallet.ui.comp.PalavraEmDigitacao.zerarAoTravar()
        app.escalibur.wallet.nucleo.PalavrasNaTela.zerarTodas()
        // O aviso de tela apagada que chega atrasado, com o app ja de volta na frente, nao deixa a leitura travada.
        if (primeiroPlano) app.escalibur.wallet.nucleo.PalavrasNaTela.liberar()
        // Sempre: um destravar em andamento (o Kotlin ainda nao sabe que abriu) para pela epoca do nucleo.
        runCatching { App.aplicar(Api.objeto("sessao.travar")) }
    }
}

/**
 * Prepara o nucleo uma vez por processo: as listas de palavras (do APK para a pasta do app, onde o
 * nucleo as confere por digesto), a pasta sem backup dos metadados e os textos traduzidos.
 */
suspend fun iniciarNucleo(contexto: Context) = withContext(Dispatchers.IO) {
    val recursos = File(contexto.filesDir, "nucleo")
    val marca = File(recursos, ".versao")
    val versao = "${BuildConfig.VERSION_CODE}-${contexto.packageManager.getPackageInfo(contexto.packageName, 0).lastUpdateTime}"
    if (!marca.exists() || marca.readText() != versao) {
        recursos.deleteRecursively()
        for (pasta in listOf("Wordlists", "Forca", "Versoes")) {
            val destino = File(recursos, pasta).apply { mkdirs() }
            for (nome in contexto.assets.list("nucleo/$pasta").orEmpty()) {
                contexto.assets.open("nucleo/$pasta/$nome").use { entrada -> File(destino, nome).outputStream().use { entrada.copyTo(it) } }
            }
        }
        // A lista de moedas da busca do Receber (2,7 MB), lida pelo nucleo na primeira busca.
        runCatching {
            contexto.assets.open("nucleo/catalogo-moedas.json").use { entrada -> File(recursos, "catalogo-moedas.json").outputStream().use { entrada.copyTo(it) } }
        }
        marca.writeText(versao)
    }
    val pasta = File(contexto.noBackupFilesDir, "carteira").apply { mkdirs() }
    // Os separadores da regiao, os mesmos que a interface usa (Formato): a revisao que o nucleo
    // monta e a conferencia antes de assinar comparam o mesmo texto.
    val simbolos = android.icu.text.DecimalFormatSymbols.getInstance(Formato.locale)
    val padrao = android.text.format.DateFormat.getBestDateTimePattern(Formato.locale, "ddMMyyyyHHmm")
    val numeros = JSONObject().put("decimal", simbolos.decimalSeparator.toString()).put("grupo", simbolos.groupingSeparator.toString())
        .put("grupoPrimario", 3).put("grupoSecundario", 3).put("data", padrao)
    val iniciado = Api.objeto("iniciar", JSONObject().put("pasta", pasta.absolutePath).put("recursos", recursos.absolutePath)
        .put("vigias", app.escalibur.wallet.vigias.Vigia.pasta(contexto).absolutePath)
        .put("pacote", JSONObject().put("nome", contexto.packageName).put("versao", BuildConfig.VERSION_NAME).put("build", BuildConfig.VERSION_CODE.toString()))
        .put("idioma", Textos.idioma)
        .put("textos", Textos.tabelaPlana()).put("numeros", numeros))
    // Na principal, como todo `App.aplicar`: o contador da geracao do estado so muda numa thread (rodada 14).
    withContext(Dispatchers.Main) { App.aplicar(iniciado) }
}

@Composable
fun Raiz() {
    val contexto = LocalContext.current
    var pronto by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        iniciarNucleo(contexto)
        pronto = true
    }
    val aparelhoComBloqueio = remember(Ciclo.vinda) { contexto.getSystemService(KeyguardManager::class.java).isDeviceSecure }
    // Um app de fora com acesso de acessibilidade, leia a tela ou so possa cobri-la: so esta tela, e nada da carteira montado por
    // baixo. Fechou, travou: o pedido de biometria do sistema que estiver na tela cai (e janela do sistema, fora desta arvore), o
    // PIN e a passphrase em digitacao saem e a sessao trava, como na tela apagada. Desligado o servico, a volta e pelo PIN.
    // O travar so depois de o nucleo responder (`pronto`): antes disso a chamada correria junto com o `iniciar`. Na Activity
    // recriada o `pronto` volta a falso por um instante, sem nada da carteira montado, e o efeito roda de novo quando o nucleo
    // responde. E vai ate o fim, mesmo que o servico desligue no meio (revisao dos 3 agentes, 17/11/2026).
    Acessibilidade.suspeitos.takeIf { it.isNotEmpty() }?.let {
        LaunchedEffect(pronto) {
            app.escalibur.wallet.nucleo.Cofre.cancelarBiometria()
            if (pronto) withContext(kotlinx.coroutines.NonCancellable) { Ciclo.travarAgora() }
        }
        TelaDeAcessibilidade(it, Acessibilidade.leemATela)
        return
    }
    if (pronto) app.escalibur.wallet.ui.avisos.ConferenciaAberta()
    // A versao desatualizada: ao abrir e a cada volta para a frente (no maximo a cada 6 horas).
    LaunchedEffect(pronto, Ciclo.vinda) { if (pronto) app.escalibur.wallet.ui.atualizar.Atualizacao.conferir(contexto) }
    // O nucleo gravou na carteira com a tela aberta (a marca de outra chave, a troca da TON para a W5): o estado e lido de novo, e
    // o Copiar endereco e os Ajustes tiram o endereco na hora (rodada 8 da auditoria 8), como o iOS observa a sessao.
    // Destravado sem nada pendente, nenhum "estado" chega: a copia marcada sai aqui (rodada 11 da auditoria 8). Tambem a cada
    // mudanca da lista (a carteira removida, o app apagado), sem depender de um aviso do nucleo (rodada 13); travado, a lista vem
    // vazia e nada conta como mudado.
    LaunchedEffect(App.estado.fase, App.estado.carteiras) {
        Transferencia.retirarSeBloqueado(contexto, App.estado.carteiras, App.estado.fase)
        // A lista do aviso de recebimento se acerta ja, e nao so no laco de 2 minutos: a removida deixa de ser vigiada pelo
        // trabalho de hora em hora (rodada 16), como o iPhone. Sem mudanca, nao faz nada.
        if (App.estado.fase == "unlocked") runCatching { Api.objeto("vigias.acompanhar") }
    }
    // O aviso do nucleo na hora da marca (rodada 12): a copia sai mesmo com o app travado na frente.
    LaunchedEffect(pronto) {
        if (pronto) Eventos.eventos.filter { it.nome == "copia.retirar" }.collect { evento ->
            val lista = runCatching { org.json.JSONObject(evento.json).getJSONArray("enderecos") }.getOrNull() ?: return@collect
            Transferencia.retirarEnderecos(contexto, (0 until lista.length()).map { lista.getString(it) }.toSet())
        }
    }
    LaunchedEffect(pronto) {
        // Pelo StateFlow, que nao perde o ultimo aviso com a rajada de saldos (rodada 15).
        // Sem o drop: a Activity recriada (tema, idioma, letra) se inscreve de novo, e o aviso que chegou no meio nao se perde
        // (rodada 16). Custa uma leitura a mais por inscricao.
        if (pronto) Eventos.estadoMudou.collect {
            runCatching { App.recarregar() }
            // O endereco copiado de uma conta que acabou de deixar de receber, ou de trocar de endereco, sai da area de
            // transferencia (rodadas 10 e 11).
            Transferencia.retirarSeBloqueado(contexto, App.estado.carteiras, App.estado.fase)
        }
    }
    Box(Modifier.fillMaxSize().background(Paleta.vazio)) {
        if (pronto) {
            // Com a tela de atualizar na frente, a carteira por baixo sai da arvore do leitor de tela: o TalkBack nao navega
            // nem ativa o que a tela cobre.
            val coberta = app.escalibur.wallet.ui.atualizar.Atualizacao.naTela
            Crossfade(App.estado.fase, Modifier.then(if (coberta) Modifier.clearAndSetSemantics {} else Modifier),
                      animationSpec = tween(150), label = "fase") { fase ->
                when (fase) {
                    "onboarding" -> FluxoDeAbertura(aparelhoComBloqueio)
                    "locked" -> {
                        LaunchedEffect(Unit) { app.escalibur.wallet.ui.enviar.PedidoDePassphrase.cancelar(); Autorizacao.cancelar() }
                        if (aparelhoComBloqueio) TelaDeBloqueio(Ciclo.vinda) else TelaSemBloqueio()
                    }
                    "unlocked" -> Principal()
                    else -> Box(Modifier.fillMaxSize().background(Paleta.vazio))
                }
            }
        }
        // Entre a volta ao primeiro plano e a resposta do nucleo (que pode travar), nada da carteira
        // aparece, nem por um quadro.
        if (!Ciclo.primeiroPlano && App.estado.fase == "unlocked") Box(Modifier.fillMaxSize().background(Paleta.vazio))
        // Acima da carteira e abaixo do pedido de PIN e de passphrase: um pedido aberto quando a tela chega termina por cima.
        if (pronto) app.escalibur.wallet.ui.atualizar.TelaDeAtualizar()
        CapaDaAbertura(pronto)
        app.escalibur.wallet.ui.enviar.PedidoDePassphrase.pedido?.let { app.escalibur.wallet.ui.enviar.FolhaDaPassphrase(it) }
        Autorizacao.pedido?.let { FolhaDePin(it) }
        Avisos.Camada(Modifier.align(Alignment.TopCenter))
        App.estado.aviso?.let { app.escalibur.wallet.ui.comp.AlertaDeSeguranca(it) }
    }
}

/**
 * A continuacao da abertura do sistema (o LaunchCover do iOS): o mesmo selo, no mesmo lugar (o centro
 * da tela inteira), agora cifrando, e some num esmaecer quando o app ja carregou. Nao segura toques.
 */
@Composable
private fun CapaDaAbertura(pronto: Boolean) {
    val inicio = remember { System.nanoTime() }
    var abrindo by remember { mutableStateOf(true) }
    LaunchedEffect(pronto) {
        if (!pronto) return@LaunchedEffect
        kotlinx.coroutines.delay((650 - (System.nanoTime() - inicio) / 1_000_000).coerceAtLeast(0))
        abrindo = false
    }
    androidx.compose.animation.AnimatedVisibility(abrindo, enter = androidx.compose.animation.EnterTransition.None,
                                                  exit = androidx.compose.animation.fadeOut(tween(300, easing = androidx.compose.animation.core.LinearOutSlowInEasing))) {
        Box(Modifier.fillMaxSize().background(Paleta.vazio), contentAlignment = Alignment.Center) { app.escalibur.wallet.ui.comp.EmblemaCifrado(88.dp) }
    }
}

/**
 * O bloqueio de tela do celular saiu: sem ele, o Keystore fica destravado para sempre, e o cofre
 * recusa abrir. As carteiras continuam guardadas e voltam quando o bloqueio voltar.
 */
@Composable
private fun TelaSemBloqueio() {
    val contexto = LocalContext.current
    Column(
        Modifier.fillMaxSize().background(Paleta.vazio).systemBarsPadding().padding(horizontal = Espaco.margem),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        app.escalibur.wallet.ui.comp.EmblemaCifrado(72.dp)
        Text(t("Este celular não tem bloqueio de tela"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
             modifier = Modifier.padding(top = Espaco.lg))
        Text(t("Sem bloqueio de tela, o Android não protege as chaves da carteira. Configure um PIN, padrão ou senha nas configurações do celular."),
             style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm))
        app.escalibur.wallet.ui.comp.BotaoPrimario(t("Abrir configurações"), Modifier.padding(top = Espaco.lg)) {
            runCatching { contexto.startActivity(android.content.Intent(android.provider.Settings.ACTION_SECURITY_SETTINGS)) }
        }
    }
}

/** A folha do PIN para confirmar uma operacao, por cima de qualquer tela. */
@Composable
private fun FolhaDePin(pedido: Autorizacao.PedidoDePin) {
    val entrada = pedido.entrada
    LaunchedEffect(pedido) { pedido.erro?.let { entrada.falhar(it) } }
    androidx.activity.compose.BackHandler { entrada.limpar(); pedido.responder(null) }
    TelaDoPin(
        titulo = t("Confirme com o PIN"),
        subtitulo = pedido.aviso?.let { "${pedido.motivo}\n$it" } ?: pedido.motivo,
        entrada = entrada,
        aoCompletar = { pedido.responder(entrada.tirar()) },
    ) {
        BotaoTerciario(t("Cancelar")) { entrada.limpar(); pedido.responder(null) }
    }
}
