package app.escalibur.wallet.ui.comp

import android.os.Build
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
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
    }
}
