package app.escalibur.wallet.nucleo

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
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

    /**
     * Quantas vezes o nucleo avisou "estado" ou "copia.retirar": um StateFlow nunca perde o ultimo aviso, e o fluxo de cima perde
     * com o buffer cheio (a rajada de saldos da importacao). A raiz recarrega o estado e retira a copia por ele (rodada 15).
     */
    val estadoMudou = MutableStateFlow(0L)

    @JvmStatic
    fun emitir(nome: String, json: String) {
        // A ordem do nucleo para tirar a copia fica anotada ja, sem passar pelo fluxo, que perde o aviso com o buffer cheio ou sem
        // ninguem ouvindo (rodada 14 da auditoria 8): ela vale na volta do foco ou da lista.
        if (nome == "copia.retirar") app.escalibur.wallet.ui.comp.Transferencia.anotarRetirada(json)
        if (nome == "estado" || nome == "copia.retirar") estadoMudou.update { it + 1 }
        fluxo.tryEmit(Evento(nome, json))
    }
}
