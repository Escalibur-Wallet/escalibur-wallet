package app.escalibur.wallet.ui.comp

import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.PersistableBundle
import android.os.SystemClock
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.material3.Text
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.ui.tema.Letra
import app.escalibur.wallet.ui.tema.Paleta
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** QR com correcao de erro nivel H (o logo no meio cabe), modulos quadrados, sem suavizacao. */
object QR {
    fun imagem(texto: String, modulosPorLado: Int = 0): ImageBitmap? = runCatching {
        val matriz = QRCodeWriter().encode(texto, BarcodeFormat.QR_CODE, modulosPorLado, modulosPorLado,
            mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.H, EncodeHintType.MARGIN to 0))
        val largura = matriz.width
        val altura = matriz.height
        val pixels = IntArray(largura * altura) { indice -> if (matriz.get(indice % largura, indice / largura)) Paleta.placaTinta.toArgb() else Color.Transparent.toArgb() }
        android.graphics.Bitmap.createBitmap(pixels, largura, altura, android.graphics.Bitmap.Config.ARGB_8888).asImageBitmap()
    }.getOrNull()
}

@Composable
fun ImagemDoQR(texto: String, tamanho: Dp, modifier: Modifier = Modifier) {
    val imagem = remember(texto) { QR.imagem(texto) } ?: return
    Image(imagem, null, modifier.size(tamanho), filterQuality = FilterQuality.None)
}

/**
 * A area de transferencia do app: o que sai daqui e marcado como sensivel (o Android nao mostra o
 * conteudo na previa) e e apagado sozinho, se ainda for o que o app copiou. O endereco vale 2
 * minutos; a frase, 1.
 *
 * Desde o Android 10, o app em segundo plano nao le a area de transferencia, e e justamente quando
 * o dono foi colar em outro app que o prazo vence. Por isso a copia leva um rotulo sorteado, e o
 * rotulo e o prazo ficam num arquivo (sem o texto): no prazo, ou quando o app volta a ter o foco,
 * mesmo depois de o processo morrer, a copia vencida que ainda for a do app e apagada.
 *
 * A frase (`segredo`) nao espera o app voltar: um alarme do sistema acorda o app no prazo, mesmo
 * congelado ou fechado, e apaga sem ler, porque apagar nao precisa do foco (auditoria das chaves de
 * 06/11/2026). O custo: se o dono copiar outra coisa dentro daquele minuto, ela sai junto.
 *
 * Colar, em qualquer tela, le so o texto do item (`text`), nunca `coerceToText`: sem texto, ele
 * abriria a `content://` URI do app que copiou e leria o fluxo inteiro na thread da interface
 * (auditoria Android de 31/10/2026, AA-04). O verificar.sh recusa `coerceToText` no Kotlin.
 */
object Transferencia {
    private val escopo = CoroutineScope(Dispatchers.Main)
    private const val ARQUIVO = "transferencia.pendente"
    private const val SEGREDO = "segredo"

    fun copiar(contexto: Context, texto: String, segundos: Long = 120, rotulo: String = "Escalibur", segredo: Boolean = false) {
        val gerente = contexto.getSystemService(ClipboardManager::class.java)
        val sorteio = ByteArray(8).also { java.security.SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
        val marca = "$rotulo $sorteio"
        val clipe = ClipData.newPlainText(marca, texto)
        clipe.description.extras = PersistableBundle().apply { putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true) }
        gerente.setPrimaryClip(clipe)
        val aplicativo = contexto.applicationContext
        runCatching {
            java.io.File(aplicativo.noBackupFilesDir, ARQUIVO)
                .writeText("$marca\n${System.currentTimeMillis() + segundos * 1000}\n${if (segredo) SEGREDO else ""}")
        }
        escopo.launch {
            delay(segundos * 1000)
            apagarSeVenceu(aplicativo, comFoco = false)
        }
        val alarmes = aplicativo.getSystemService(AlarmManager::class.java) ?: return
        // Um alarme so: a copia nova substitui o da anterior, e a que nao e segredo cancela o da frase.
        val aviso = PendingIntent.getBroadcast(
            aplicativo, 0, Intent(aplicativo, ApagarTransferencia::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        if (segredo) {
            runCatching { alarmes.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + segundos * 1000, aviso) }
        } else {
            runCatching { alarmes.cancel(aviso) }
        }
    }

    /**
     * Apaga a copia do app se o prazo passou e ela ainda esta la. Sem o foco, o Android nao deixa
     * ler: fica para quando o app voltar (`comFoco`).
     */
    fun apagarSeVenceu(contexto: Context, comFoco: Boolean, peloAlarme: Boolean = false) {
        val arquivo = java.io.File(contexto.noBackupFilesDir, ARQUIVO)
        val linhas = runCatching { arquivo.readLines() }.getOrNull() ?: return
        val marca = linhas.getOrNull(0) ?: return
        val prazo = linhas.getOrNull(1)?.toLongOrNull() ?: return
        val segredo = linhas.getOrNull(2) == SEGREDO
        // O alarme e o proprio prazo: o relogio de parede, mexido no meio, nao segura a frase.
        if (!(peloAlarme && segredo) && System.currentTimeMillis() < prazo) return
        val gerente = contexto.getSystemService(ClipboardManager::class.java)
        val descricao = runCatching { gerente.primaryClipDescription }.getOrNull()
        if (descricao == null) {
            // Sem o foco o Android nao deixa ler; a frase sai mesmo assim, sem ler.
            if (segredo) runCatching { gerente.clearPrimaryClip() }
            if (comFoco || segredo) arquivo.delete()
            return
        }
        if (descricao.label?.toString() == marca) runCatching { gerente.clearPrimaryClip() }
        arquivo.delete()
    }
}

/** O prazo da copia da frase: o sistema acorda o app aqui, mesmo em segundo plano, congelado ou fechado. */
class ApagarTransferencia : BroadcastReceiver() {
    override fun onReceive(contexto: Context, intent: Intent) {
        Transferencia.apagarSeVenceu(contexto.applicationContext, comFoco = false, peloAlarme = true)
    }
}

/**
 * O endereco inteiro em mono, em blocos de 4, com as pontas em destaque: e o que a pessoa confere.
 * O comeco destacado leva o prefixo fixo da rede ("0x", "bc1q"), que sozinho nao diferencia.
 */
object BlocosDeEndereco {
    fun inicio(endereco: String): Int {
        if (endereco.startsWith("0x") || endereco.startsWith("0X")) return 6
        val separador = endereco.indexOf('1')
        if (separador in 2..4 && endereco.substring(0, separador).all { it.isLowerCase() }) return separador + 2 + 4
        return 4
    }

    fun blocos(endereco: String): List<String> {
        val cabeca = minOf(inicio(endereco), endereco.length)
        val cauda = minOf(4, maxOf(endereco.length - cabeca, 0))
        if (endereco.length <= cabeca + cauda) return listOf(endereco)
        val meio = endereco.substring(cabeca, endereco.length - cauda)
        return listOf(endereco.take(cabeca)) + meio.chunked(4) + listOf(endereco.takeLast(cauda))
    }
}

@Composable
fun EnderecoEmBlocos(endereco: String, modifier: Modifier = Modifier, naPlaca: Boolean = false) {
    val blocos = BlocosDeEndereco.blocos(endereco)
    val texto = buildAnnotatedString {
        blocos.forEachIndexed { indice, bloco ->
            if (indice == 0 || indice == blocos.lastIndex) {
                withStyle(SpanStyle(background = Paleta.realce, color = Paleta.sobreRealce, fontWeight = FontWeight.Bold)) { append(bloco) }
            } else {
                withStyle(SpanStyle(color = if (naPlaca) Paleta.placaApagada else Paleta.tintaSuave)) { append(bloco) }
            }
            // O espaco entre os blocos e pequeno (dois espacos numa letra de 8 do texto, nao da mono), como
            // no iOS: so separa o olho, e a copia continua sem espacos.
            if (indice < blocos.lastIndex) withStyle(SpanStyle(fontSize = 8.sp, fontFamily = Letra.familia(FontWeight.Normal, 8f))) { append("  ") }
        }
    }
    Text(texto, fontFamily = FontFamily.Monospace, fontSize = 16.sp, fontWeight = FontWeight.Medium, lineHeight = 25.sp,
         modifier = modifier.semantics { contentDescription = endereco })
}
