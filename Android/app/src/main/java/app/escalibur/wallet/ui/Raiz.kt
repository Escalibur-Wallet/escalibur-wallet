package app.escalibur.wallet.ui

import android.app.KeyguardManager
import android.content.Context
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
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
import app.escalibur.wallet.BuildConfig
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.abertura.FluxoDeAbertura
import app.escalibur.wallet.ui.bloqueio.TelaDeBloqueio
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.pin.EntradaDoPin
import app.escalibur.wallet.ui.pin.TelaDoPin
import app.escalibur.wallet.ui.principal.Principal
import app.escalibur.wallet.ui.tema.Paleta
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

    suspend fun voltou() {
        primeiroPlano = true
        runCatching { App.aplicar(Api.objeto("sessao.primeiroPlano")) }
        vinda++
    }
}

/** Os textos que o nucleo grava ou mostra no sistema (nome de carteira, motivo da biometria). */
private val textosDoNucleo = listOf("Destravar a Escalibur", "Carteira principal", "Carteira %lld", "envelope", "importada")

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
        for (pasta in listOf("Wordlists", "Forca")) {
            val destino = File(recursos, pasta).apply { mkdirs() }
            for (nome in contexto.assets.list("nucleo/$pasta").orEmpty()) {
                contexto.assets.open("nucleo/$pasta/$nome").use { entrada -> File(destino, nome).outputStream().use { entrada.copyTo(it) } }
            }
        }
        marca.writeText(versao)
    }
    val pasta = File(contexto.noBackupFilesDir, "carteira").apply { mkdirs() }
    val textos = JSONObject(Textos.tabela(textosDoNucleo))
    App.aplicar(Api.objeto("iniciar", JSONObject().put("pasta", pasta.absolutePath).put("recursos", recursos.absolutePath).put("textos", textos)))
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
    Box(Modifier.fillMaxSize().background(Paleta.vazio)) {
        if (pronto) {
            Crossfade(App.estado.fase, animationSpec = tween(150), label = "fase") { fase ->
                when (fase) {
                    "onboarding" -> FluxoDeAbertura(aparelhoComBloqueio)
                    "locked" -> TelaDeBloqueio(Ciclo.vinda)
                    "unlocked" -> Principal()
                    else -> Box(Modifier.fillMaxSize().background(Paleta.vazio))
                }
            }
        }
        Autorizacao.pedido?.let { FolhaDePin(it) }
        Avisos.Camada(Modifier.align(Alignment.TopCenter))
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
