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
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.BuildConfig
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.abertura.FluxoDeAbertura
import app.escalibur.wallet.ui.bloqueio.TelaDeBloqueio
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.pin.EntradaDoPin
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

    suspend fun foiParaSegundoPlano() {
        primeiroPlano = false
        runCatching { Api.objeto("sessao.segundoPlano") }
    }

    /** O nucleo decide se trava antes de a tela voltar: ate a resposta, a capa cobre tudo. */
    suspend fun voltou() {
        runCatching { App.aplicar(Api.objeto("sessao.primeiroPlano")) }
        primeiroPlano = true
        vinda++
    }

    /** O celular travou (a tela apagou). Nada a fazer se o nucleo ainda nao abriu. */
    suspend fun travarAgora() {
        if (App.estado.fase == "unlocked") runCatching { App.aplicar(Api.objeto("sessao.travar")) }
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
        marca.writeText(versao)
    }
    val pasta = File(contexto.noBackupFilesDir, "carteira").apply { mkdirs() }
    // Os separadores da regiao, os mesmos que a interface usa (Formato): a revisao que o nucleo
    // monta e a conferencia antes de assinar comparam o mesmo texto.
    val simbolos = android.icu.text.DecimalFormatSymbols.getInstance(Formato.locale)
    val padrao = android.text.format.DateFormat.getBestDateTimePattern(Formato.locale, "ddMMyyyyHHmm")
    val numeros = JSONObject().put("decimal", simbolos.decimalSeparator.toString()).put("grupo", simbolos.groupingSeparator.toString())
        .put("grupoPrimario", 3).put("grupoSecundario", 3).put("data", padrao)
    App.aplicar(Api.objeto("iniciar", JSONObject().put("pasta", pasta.absolutePath).put("recursos", recursos.absolutePath)
        .put("vigias", app.escalibur.wallet.vigias.Vigia.pasta(contexto).absolutePath)
        .put("pacote", JSONObject().put("nome", contexto.packageName).put("versao", BuildConfig.VERSION_NAME).put("build", BuildConfig.VERSION_CODE.toString()))
        .put("idioma", Textos.idioma)
        .put("textos", Textos.tabelaPlana()).put("numeros", numeros)))
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
    if (pronto) app.escalibur.wallet.ui.avisos.ConferenciaAberta()
    Box(Modifier.fillMaxSize().background(Paleta.vazio)) {
        if (pronto) {
            Crossfade(App.estado.fase, animationSpec = tween(150), label = "fase") { fase ->
                when (fase) {
                    "onboarding" -> FluxoDeAbertura(aparelhoComBloqueio)
                    "locked" -> {
                        LaunchedEffect(Unit) { app.escalibur.wallet.ui.enviar.PedidoDePassphrase.cancelar() }
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
    val entrada = remember(pedido) { EntradaDoPin(App.estado.pinDigitos) }
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
