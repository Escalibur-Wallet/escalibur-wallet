package app.escalibur.wallet.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONObject
import kotlin.coroutines.resume

/** Como o dono prova presenca para uma operacao que precisa da chave raiz. */
sealed class Credencial {
    abstract val motivo: String

    /** O PIN da credencial, quando ela e por PIN. Vai primeiro no segredo da chamada. */
    open val pin: ByteArray? get() = null

    class Pin(override val pin: ByteArray, override val motivo: String = "") : Credencial()
    class Biometria(override val motivo: String) : Credencial()
    /** O PIN e, com a biometria ligada, ela tambem: ver as palavras, remover, desligar a biometria. */
    class PinEBiometria(override val pin: ByteArray, override val motivo: String) : Credencial()
    /** Modo reforcado: o PIN e a biometria pela criptografia, em tudo. */
    class Reforcado(override val pin: ByteArray, override val motivo: String) : Credencial()

    fun json(): JSONObject = JSONObject()
        .put("tipo", when (this) { is Pin -> "pin"; is Biometria -> "biometria"; is PinEBiometria -> "pinEBiometria"; is Reforcado -> "reforcado" })
        .put("motivo", motivo)

    /** As partes do segredo: o PIN (se houver) e o que a operacao pede. */
    fun partes(vararg resto: ByteArray): Array<ByteArray> = (listOfNotNull(pin) + resto).toTypedArray()

    fun zerar() { pin?.fill(0) }
}

/**
 * Pede presenca do dono para uma operacao: biometria quando ligada, PIN quando nao, ou quando a
 * biometria falhar. Uma folha de PIN so, desenhada na raiz do app. O `AuthCoordinator` do iOS.
 */
object Autorizacao {
    class PedidoDePin(val motivo: String, val aviso: String?, val erro: String?, val responder: (ByteArray?) -> Unit)

    var pedido by mutableStateOf<PedidoDePin?>(null)
        private set

    /** O que uma operacao pede ao dono. */
    enum class Presenca {
        /** Biometria quando ligada, PIN quando nao: envios, trocas, ordens. */
        qualquer,
        /** O PIN sempre: o que muda as barreiras. */
        pin,
        /** O PIN e, com a biometria ligada, ela tambem: o que entrega ou destroi a carteira inteira. */
        pinEBiometria,
    }

    private suspend fun pedirPin(motivo: String, aviso: String?, erro: String?): ByteArray? = suspendCancellableCoroutine { continuacao ->
        pedido = PedidoDePin(motivo, aviso, erro) { pin ->
            pedido = null
            if (continuacao.isActive) continuacao.resume(pin) else pin?.fill(0)
        }
        continuacao.invokeOnCancellation { pedido = null }
    }

    /** A credencial para uma operacao. Nil quando o dono cancela. */
    suspend fun credencial(motivo: String, forcarPin: Boolean = false, aviso: String? = null, erro: String? = null): Credencial? {
        val estado = App.estado
        if (estado.reforcado) {
            val pin = pedirPin(motivo, aviso ?: avisoDoReforcado, erro) ?: return null
            return Credencial.Reforcado(pin, motivo)
        }
        val depoisDeReiniciar = estado.biometriaLigada && estado.pedePINDepoisDeReiniciar
        if (!forcarPin && estado.biometriaLigada && !depoisDeReiniciar) return Credencial.Biometria(motivo)
        val avisoFinal = aviso ?: if (depoisDeReiniciar && !forcarPin) avisoDeReinicio else null
        val pin = pedirPin(motivo, avisoFinal, erro) ?: return null
        return Credencial.Pin(pin, motivo)
    }

    /**
     * Executa uma operacao com a credencial, caindo para o PIN se a biometria for cancelada, tiver
     * mudado ou pedir o PIN depois de reiniciar; PIN errado ou espera voltam ao teclado com o aviso.
     * Devolve nil se o dono desistir. O apagamento e qualquer outro erro sobem.
     */
    suspend fun <T> tentando(motivo: String, presenca: Presenca = Presenca.qualquer, operacao: suspend (Credencial) -> T): T? {
        val ambos = presenca == Presenca.pinEBiometria
        var tentativa = credencial(motivo, forcarPin = presenca != Presenca.qualquer, aviso = if (ambos) avisoDosDois else null) ?: return null
        while (true) {
            if (ambos && tentativa is Credencial.Pin) tentativa = Credencial.PinEBiometria(tentativa.pin, motivo)
            var aviso: String? = null
            var erro: String? = null
            try {
                val resultado = operacao(tentativa)
                App.recarregar()
                return resultado
            } catch (falha: FalhaDoNucleo) {
                when (falha.codigo) {
                    "cofre.cancelled" -> aviso = if (ambos) avisoDosDoisCancelado else null
                    "cofre.biometryChanged" -> {
                        if (ambos) throw FalhaDoNucleo("cofre.biometryRequired", falha.dados)
                        aviso = t("A biometria deste celular mudou desde que foi ligada aqui. Confirme com o PIN; depois você pode religar.")
                    }
                    "cofre.pinRequiredAfterRestart" -> aviso = avisoDeReinicio
                    "cofre.pinErrado" -> erro = mensagemDePinErrado(falha)
                    "cofre.espera" -> erro = t("Tentativas demais. Tente de novo em %@.", Formato.duracao(falha.segundos))
                    "cofre.biometriaNaoConfirmou" -> erro = mensagemDeBiometriaNaoConfirmou(falha.restantes)
                    else -> throw falha
                }
            }
            App.recarregar()
            tentativa = credencial(motivo, forcarPin = true, aviso = aviso ?: if (ambos) avisoDosDois else null, erro = erro) ?: return null
        }
    }

    private val avisoDoReforcado get() = t("Depois do PIN, a biometria confirma que é você.")
    private val avisoDeReinicio get() = t("O celular reiniciou: o PIN é necessário uma vez antes de a biometria voltar a valer.")
    private val avisoDosDois: String? get() = if (App.estado.biometriaLigada) t("Depois do PIN, a biometria confirma que é você.") else null
    private val avisoDosDoisCancelado get() = t("A biometria não confirmou. Com ela ligada, isto pede o PIN e a biometria.")

    fun mensagemDeBiometriaNaoConfirmou(restantes: Int?): String =
        if (restantes != null && restantes <= 3) t("A biometria não confirmou, e isso conta como tentativa. Depois de mais %lld, as carteiras deste celular são apagadas.", restantes)
        else t("A biometria não confirmou, e isso conta como tentativa.")

    /** O aviso de PIN errado, o mesmo na tela de bloqueio e dentro das operacoes. */
    fun mensagemDePinErrado(falha: FalhaDoNucleo): String {
        val restantes = falha.restantes
        return when {
            restantes != null && restantes <= 3 -> t("PIN incorreto. Depois de mais %lld, as carteiras deste celular são apagadas.", restantes)
            falha.erros >= 2 && falha.dados.optDouble("proximaEspera", 0.0) > 0 ->
                t("PIN incorreto. Mais um erro e o app pede uma espera de %@.", Formato.duracao(falha.dados.optDouble("proximaEspera")))
            else -> t("PIN incorreto.")
        }
    }

    /** O texto de uma recusa conhecida, no lugar do erro generico. Nil quando nao e uma. */
    fun mensagemDeRecusa(erro: Throwable): String? {
        val falha = erro as? FalhaDoNucleo ?: return null
        return when (falha.codigo) {
            "cofre.esperaDaBiometria" -> t("A biometria deste celular mudou há pouco. Por segurança, isto volta a funcionar em %@.", Formato.duracao(falha.segundos))
            "cofre.biometryNotEnrolled" -> t("Nenhuma biometria cadastrada neste celular. Cadastre uma digital ou o rosto nas configurações do celular e tente de novo: as carteiras continuam aqui.")
            "cofre.biometryRequired" -> t("A biometria deste celular mudou desde que foi ligada aqui. Para isto, ligue a biometria de novo em Ajustes, Segurança; por segurança, volta a funcionar 24 horas depois.")
            "cofre.biometryUnavailable" -> t("A biometria não está disponível agora. Confira se ela está ligada nas configurações do celular e tente de novo.")
            "cofre.biometryLockedOut" -> t("O celular bloqueou a biometria depois de tentativas demais. Bloqueie e desbloqueie o celular com o PIN da tela, e tente de novo.")
            "cofre.wiped" -> t("Tentativas demais: as carteiras deste celular foram apagadas. Só as palavras de cada carteira trazem de volta.")
            else -> null
        }
    }
}
