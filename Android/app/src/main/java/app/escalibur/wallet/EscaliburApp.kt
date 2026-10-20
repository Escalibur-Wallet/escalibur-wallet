package app.escalibur.wallet

import android.app.Application
import app.escalibur.wallet.nucleo.Cofre

/** Prepara o cofre (a pasta sem backup e o contexto do Keystore) antes de o nucleo carregar. */
class EscaliburApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Cofre.iniciar(this)
    }
}
