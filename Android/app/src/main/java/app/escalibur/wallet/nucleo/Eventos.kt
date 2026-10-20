package app.escalibur.wallet.nucleo

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * O que o nucleo avisa sem a interface perguntar (o saldo de cada rede que chega). Chamado pelo
 * nucleo (JNI), de threads dele.
 */
object Eventos {
    data class Evento(val nome: String, val json: String)

    private val fluxo = MutableSharedFlow<Evento>(extraBufferCapacity = 64)
    val eventos: SharedFlow<Evento> = fluxo.asSharedFlow()

    @JvmStatic
    fun emitir(nome: String, json: String) {
        fluxo.tryEmit(Evento(nome, json))
    }
}
