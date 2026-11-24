package app.escalibur.wallet.ui.comp

import android.os.Build
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider

/**
 * A protecao da janela principal (`MainActivity`) numa janela propria, de dialogo ou popup do Compose.
 * Cada uma e outra janela, e a raiz dela nao herda nada da Activity (auditoria de 03/11/2026): sem
 * isto, no Android 14 em diante, um servico de acessibilidade que nao se diz ferramenta lia o "Minhas
 * carteiras" do envio, com o endereco da carteira com passphrase. Todo dialogo e popup chama esta
 * funcao no comeco do conteudo; o `verificar.sh` confere.
 */
@Composable
fun ProtegerJanela() {
    val vista = LocalView.current
    SideEffect {
        val janela = (vista.parent as? DialogWindowProvider)?.window
        // No popup nao ha `Window`: a raiz e a propria vista que o Compose pos no WindowManager.
        val raiz = janela?.decorView ?: vista.rootView
        raiz.filterTouchesWhenObscured = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            raiz.setAccessibilityDataSensitive(View.ACCESSIBILITY_DATA_SENSITIVE_YES)
        }
        if (janela != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) janela.setHideOverlayWindows(true)
        // No Android 11, o toque com janela de outro app por cima tambem nao vale no dialogo (como na MainActivity).
        val original: android.view.Window.Callback? = janela?.callback
        if (janela != null && Build.VERSION.SDK_INT < Build.VERSION_CODES.S && original != null && original !is ToqueCoberto.Filtro) {
            janela.callback = ToqueCoberto.Filtro(original)
        }
    }
}

/**
 * O toque que chega com uma janela de outro app cobrindo parte da tela, no Android 11 (do 12 em diante a janela de cima
 * some, `setHideOverlayWindows`). Recusado, com o aviso no maximo a cada 4 segundos (auditoria 8, 14/11/2026).
 */
object ToqueCoberto {
    private var ultimoAviso = 0L

    fun recusa(evento: android.view.MotionEvent): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return false
        val coberto = android.view.MotionEvent.FLAG_WINDOW_IS_PARTIALLY_OBSCURED or android.view.MotionEvent.FLAG_WINDOW_IS_OBSCURED
        if (evento.flags and coberto == 0) return false
        val agora = android.os.SystemClock.elapsedRealtime()
        if (evento.actionMasked == android.view.MotionEvent.ACTION_DOWN && agora - ultimoAviso > 4_000) {
            ultimoAviso = agora
            Avisos.mostrar(app.escalibur.wallet.ui.t("Outro app está desenhando por cima da Escalibur. Feche a janela dele (bolha de conversa, filtro de tela, gravador) para tocar na carteira."))
        }
        return true
    }

    /** O `Window.Callback` do dialogo, com a mesma recusa antes de tudo. */
    class Filtro(private val original: android.view.Window.Callback) : android.view.Window.Callback by original {
        override fun dispatchTouchEvent(evento: android.view.MotionEvent): Boolean {
            if (!recusa(evento)) return original.dispatchTouchEvent(evento)
            cancelar(evento) { original.dispatchTouchEvent(it) }
            return true
        }
    }

    /** O gesto que comecou sem janela por cima e e recusado no meio: um ACTION_CANCEL para nada ficar apertado (rodada 1). */
    fun cancelar(evento: android.view.MotionEvent, entregar: (android.view.MotionEvent) -> Unit) {
        if (evento.actionMasked == android.view.MotionEvent.ACTION_DOWN) return
        val cancelado = android.view.MotionEvent.obtain(evento).apply { action = android.view.MotionEvent.ACTION_CANCEL }
        entregar(cancelado)
        cancelado.recycle()
    }
}

/**
 * O popup do Compose nao tem `Window`, e o `ProtegerJanela` nao pega o toque dele: no Android 11, o toque com janela de outro
 * app por cima e consumido aqui, antes do conteudo (rodada 1 da auditoria 8).
 */
fun androidx.compose.ui.Modifier.recusaToqueCoberto(): androidx.compose.ui.Modifier =
    this.then(androidx.compose.ui.Modifier.pointerInput(Unit) {
        awaitPointerEventScope {
            while (true) {
                val evento = awaitPointerEvent(androidx.compose.ui.input.pointer.PointerEventPass.Initial)
                val nativo = evento.motionEvent ?: continue
                if (ToqueCoberto.recusa(nativo)) evento.changes.forEach { it.consume() }
            }
        }
    })
