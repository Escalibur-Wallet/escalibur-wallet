package app.escalibur.wallet

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import app.escalibur.wallet.nucleo.Cofre
import app.escalibur.wallet.ui.Ciclo
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/** Prepara o cofre (a pasta sem backup e o contexto do Keystore) antes de o nucleo carregar. */
class EscaliburApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Cofre.iniciar(this)
        // A tela do celular apagou: o app trava na hora, como no iPhone quando ele bloqueia
        // (protectedDataWillBecomeUnavailable). Quem pega o celular depois passa pelo PIN do app.
        registerReceiver(object : BroadcastReceiver() {
            override fun onReceive(contexto: Context, intent: Intent) {
                MainScope().launch { Ciclo.travarAgora() }
            }
        }, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }
}
