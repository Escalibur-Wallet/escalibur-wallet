package app.escalibur.wallet.ui

import android.view.inputmethod.EditorInfo
import androidx.compose.runtime.Composable
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.platform.InterceptPlatformTextInput
import androidx.compose.ui.platform.PlatformTextInputMethodRequest

/**
 * Todo campo do app abre o teclado sem aprendizado (o modo anonimo do teclado): o que se digita
 * aqui, endereco, nome, passphrase ou uma frase colada por engano, nao vira sugestao nem vai para o
 * dicionario do teclado, que pode ser de terceiros.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun SemAprendizado(conteudo: @Composable () -> Unit) {
    InterceptPlatformTextInput(
        interceptor = { pedido, proximo ->
            proximo.startInputMethod(PlatformTextInputMethodRequest { atributos ->
                val conexao = pedido.createInputConnection(atributos)
                atributos.imeOptions = atributos.imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
                conexao
            })
        },
        content = conteudo,
    )
}
