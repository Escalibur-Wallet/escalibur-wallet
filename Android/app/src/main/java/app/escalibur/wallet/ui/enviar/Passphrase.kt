package app.escalibur.wallet.ui.enviar

import app.escalibur.wallet.ui.comp.Interruptor
import app.escalibur.wallet.ui.comp.seguraToques
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import app.escalibur.wallet.ui.comp.acimaDoTeclado
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.KeyboardActionHandler
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.TextObfuscationMode
import androidx.compose.foundation.text.input.clearText
import androidx.compose.foundation.text.BasicSecureTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Segmentado
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * A passphrase antes de mover saldo (o `PassphraseGate` do iOS): carteira com passphrase e "Pedir a
 * passphrase para enviar" pede ela antes da biometria ou do PIN. A conferencia e do assinador, no
 * nucleo; esta folha so coleta o que foi digitado, em bytes que o chamador zera.
 */
object PedidoDePassphrase {
    class Resposta(val bytes: ByteArray, val folga: Int?)

    class Pedido(val nomeDaCarteira: String, val motivo: String, val ofereceFolga: Boolean, val responder: (Resposta?) -> Unit)

    var pedido by mutableStateOf<Pedido?>(null)
        private set

    val escolhasDeFolga = listOf(5, 10, 15, 20)

    suspend fun pedir(nomeDaCarteira: String, motivo: String? = null): Resposta? = suspendCancellableCoroutine { continuacao ->
        pedido?.responder?.invoke(null)
        val linha = motivo ?: t("%@ pede a passphrase para mover saldo. Depois dela vem a biometria ou o PIN, como sempre.", nomeDaCarteira)
        pedido = Pedido(nomeDaCarteira, linha, motivo == null) { resposta ->
            pedido = null
            if (continuacao.isActive) continuacao.resume(resposta) else resposta?.bytes?.fill(0)
        }
        continuacao.invokeOnCancellation { pedido = null }
    }

    /** O app travou: a folha aberta responde "fechou". */
    fun cancelar() { pedido?.responder?.invoke(null) }
}

/** A folha, por cima de qualquer tela (desenhada na raiz, como a do PIN). */
@Composable
fun FolhaDaPassphrase(pedido: PedidoDePassphrase.Pedido) {
    val campo = remember(pedido) { TextFieldState() }
    var mostrar by remember { mutableStateOf(false) }
    var folgaLigada by remember(pedido) { mutableStateOf(false) }
    var minutos by remember(pedido) { mutableIntStateOf(PedidoDePassphrase.escolhasDeFolga.first()) }
    var respondida by remember(pedido) { mutableStateOf(false) }
    val foco = remember { FocusRequester() }

    fun fechar() {
        if (respondida) return
        respondida = true
        campo.clearText()
        pedido.responder(null)
    }

    fun confirmar() {
        if (respondida || campo.text.isEmpty()) return
        respondida = true
        // Os bytes saem direto do campo, sem passar por String; o campo zera o dele.
        val texto = campo.text
        val bytes = java.nio.charset.StandardCharsets.UTF_8.encode(java.nio.CharBuffer.wrap(texto))
        val copia = ByteArray(bytes.remaining()).also { bytes.get(it) }
        if (bytes.hasArray()) bytes.array().fill(0)
        campo.clearText()
        pedido.responder(PedidoDePassphrase.Resposta(copia, if (folgaLigada && pedido.ofereceFolga) minutos else null))
    }

    DisposableEffect(pedido) { onDispose { if (!respondida) { campo.clearText(); pedido.responder(null) } } }
    LaunchedEffect(pedido) { runCatching { foco.requestFocus() } }
    BackHandler { fechar() }

    Column(Modifier.fillMaxSize().background(Paleta.vazio).seguraToques().statusBarsPadding().navigationBarsPadding().acimaDoTeclado()) {
        CabecalhoDeFolha(t("Digite a passphrase"), { fechar() })
        Column(Modifier.weight(1f).padding(horizontal = Espaco.margem)) {
            Text(pedido.motivo, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
            Box(
                Modifier.padding(top = Espaco.lg).fillMaxWidth().height(Altura.primaria)
                    .background(Paleta.corpo, RoundedCornerShape(Raio.cartao))
                    .border(1.dp, Paleta.bordaForte, RoundedCornerShape(Raio.cartao))
                    .pointerInput(Unit) { detectTapGestures(onPress = { mostrar = true; tryAwaitRelease(); mostrar = false }, onTap = { runCatching { foco.requestFocus() } }) }
                    .padding(horizontal = Espaco.md),
                contentAlignment = androidx.compose.ui.Alignment.CenterStart,
            ) {
                if (campo.text.isEmpty()) Text(t("Passphrase"), style = estilo(Tipo.mono), color = Paleta.tintaMorta)
                BasicSecureTextField(
                    state = campo,
                    textObfuscationMode = if (mostrar) TextObfuscationMode.Visible else TextObfuscationMode.Hidden,
                    textStyle = estilo(Tipo.mono).copy(color = Paleta.tinta),
                    cursorBrush = SolidColor(Paleta.acento),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done, autoCorrectEnabled = false),
                    onKeyboardAction = KeyboardActionHandler { confirmar() },
                    modifier = Modifier.fillMaxWidth().focusRequester(foco),
                )
            }
            Text(t("Segure o dedo no campo para conferir o que digitou."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                 modifier = Modifier.padding(top = Espaco.xs))
            if (pedido.ofereceFolga) {
                Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        Text(t("Não pedir de novo por um tempo"), style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
                        Interruptor(folgaLigada, { folgaLigada = it })
                    }
                    Text(
                        if (folgaLigada) t("Nos próximos %lld minutos, %@ não pede a passphrase para mover saldo. A biometria ou o PIN continuam. Travar o app encerra.", minutos, pedido.nomeDaCarteira)
                        else t("Depois de a passphrase conferir, os próximos envios, trocas e ordens pulam esta etapa por alguns minutos."),
                        style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(end = 64.dp),
                    )
                    AnimatedVisibility(folgaLigada) {
                        Segmentado(PedidoDePassphrase.escolhasDeFolga.map { it to t("%lld min", it) }, minutos) { minutos = it }
                    }
                }
            }
            Spacer(Modifier.weight(1f))
        }
        BotaoPrimario(t("Continuar"), Modifier.padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs), ligado = campo.text.isNotEmpty()) { confirmar() }
    }
}

