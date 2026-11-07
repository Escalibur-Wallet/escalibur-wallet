package app.escalibur.wallet.ui

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.escalibur.wallet.ui.novacarteira.Checagem

/**
 * O aviso fixo de root, codigo injetado ou depurador, um so para o app (o `DeviceIntegrity.Signal` do iOS): conferido na
 * abertura, a cada volta ao app e antes de cada credencial, ou seja, antes de abrir a chave raiz (auditoria das chaves de
 * 06/11/2026). Aceso, fica aceso ate o app fechar. So aviso: nunca bloqueia nem apaga.
 */
object Integridade {
    var suspeita by mutableStateOf(false)
        private set

    fun conferir(contexto: Context) {
        if (!suspeita) suspeita = runCatching { Checagem.pareceTerRoot(contexto) }.getOrDefault(false)
    }
}
