package app.escalibur.wallet.ui.comp

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.PersistableBundle
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
 */
object Transferencia {
    private val escopo = CoroutineScope(Dispatchers.Main)

    fun copiar(contexto: Context, texto: String, segundos: Long = 120, rotulo: String = "Escalibur") {
        val gerente = contexto.getSystemService(ClipboardManager::class.java)
        val clipe = ClipData.newPlainText(rotulo, texto)
        clipe.description.extras = PersistableBundle().apply { putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true) }
        gerente.setPrimaryClip(clipe)
        escopo.launch {
            delay(segundos * 1000)
            val atual = runCatching { gerente.primaryClip?.getItemAt(0)?.text?.toString() }.getOrNull()
            if (atual == texto) runCatching { gerente.clearPrimaryClip() }
        }
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
            if (indice < blocos.lastIndex) append("  ")
        }
    }
    Text(texto, fontFamily = FontFamily.Monospace, fontSize = 16.sp, fontWeight = FontWeight.Medium, lineHeight = 26.sp, modifier = modifier)
}
