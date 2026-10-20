package app.escalibur.wallet.ui.enviar

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.compose.CameraXViewfinder
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.LifecycleEventEffect
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Le um QR pela camera, em tela cheia na pilha (Navegacao). Os quadros vao para o ZXing aqui no aparelho e nenhuma imagem e guardada;
 * so o texto do codigo sai daqui. Sem a permissao, a tela explica e leva a pagina do app nas
 * configuracoes.
 */
@Composable
fun LeitorDeQR(aoFechar: () -> Unit, aoLer: (String) -> Unit) {
    val contexto = LocalContext.current
    val temCamera = remember { contexto.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }
    fun liberada() = ContextCompat.checkSelfPermission(contexto, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    var acesso by remember { mutableStateOf(if (!temCamera) "semCamera" else if (liberada()) "liberada" else "pedindo") }
    val pedido = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> acesso = if (ok) "liberada" else "negada" }
    LaunchedEffect(Unit) { if (acesso == "pedindo") pedido.launch(Manifest.permission.CAMERA) }
    // Quem volta das configuracoes com a camera ligada ja encontra o leitor.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { if (acesso == "negada" && liberada()) acesso = "liberada" }

    Box(Modifier.fillMaxSize().background(Paleta.vazio)) {
        when (acesso) {
            "liberada" -> {
                Camera(aoLer)
                Visor(Modifier.align(Alignment.Center))
                BotaoSecundario(t("Cancelar"), Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(Espaco.margem)) { aoFechar() }
            }
            "negada", "semCamera" -> SemCamera(semCamera = acesso == "semCamera", aoFechar = aoFechar) {
                runCatching {
                    contexto.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", contexto.packageName, null)))
                }
            }
            else -> Unit
        }
    }
}

@Composable
private fun Camera(aoLer: (String) -> Unit) {
    val contexto = LocalContext.current
    val dono = LocalLifecycleOwner.current
    var superficie by remember { mutableStateOf<SurfaceRequest?>(null) }
    DisposableEffect(dono) {
        val lido = AtomicBoolean(false)
        val analise = Executors.newSingleThreadExecutor()
        val leitor = QRCodeReader()
        val dicas = mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE), DecodeHintType.TRY_HARDER to true)
        val previa = Preview.Builder().build().apply { setSurfaceProvider { superficie = it } }
        val quadros = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build().apply {
            setAnalyzer(analise) { imagem ->
                imagem.use {
                    if (lido.get()) return@use
                    val texto = decodificar(it, leitor, dicas) ?: return@use
                    if (texto.length <= 512 && lido.compareAndSet(false, true)) ContextCompat.getMainExecutor(contexto).execute { aoLer(texto) }
                }
            }
        }
        val futuro = ProcessCameraProvider.getInstance(contexto)
        futuro.addListener({
            runCatching {
                val provedor = futuro.get()
                provedor.unbindAll()
                provedor.bindToLifecycle(dono, CameraSelector.DEFAULT_BACK_CAMERA, previa, quadros)
            }
        }, ContextCompat.getMainExecutor(contexto))
        onDispose {
            runCatching { futuro.get().unbindAll() }
            analise.shutdown()
        }
    }
    superficie?.let { CameraXViewfinder(surfaceRequest = it, modifier = Modifier.fillMaxSize()) }
}

/** O plano de luminancia (Y) do quadro, como o ZXing le. */
private fun decodificar(imagem: ImageProxy, leitor: QRCodeReader, dicas: Map<DecodeHintType, Any>): String? {
    val plano = imagem.planes.firstOrNull() ?: return null
    val buffer = plano.buffer.duplicate().apply { rewind() }
    val largura = imagem.width
    val altura = imagem.height
    val passo = plano.rowStride
    val bytes = ByteArray(largura * altura)
    for (linha in 0 until altura) {
        buffer.position(linha * passo)
        buffer.get(bytes, linha * largura, largura)
    }
    return try {
        val fonte = PlanarYUVLuminanceSource(bytes, largura, altura, 0, 0, largura, altura, false)
        leitor.decode(BinaryBitmap(HybridBinarizer(fonte)), dicas).text
    } catch (_: Exception) {
        null
    } finally {
        leitor.reset()
    }
}

/** O quadrado que mostra onde por o codigo. */
@Composable
private fun Visor(modifier: Modifier = Modifier) {
    Canvas(modifier.size(240.dp)) {
        val traco = 4.dp.toPx()
        drawRoundRect(Paleta.tinta, Offset(traco / 2, traco / 2), Size(size.width - traco, size.height - traco),
                      CornerRadius(24.dp.toPx()), style = Stroke(traco))
    }
}

@Composable
private fun SemCamera(semCamera: Boolean, aoFechar: () -> Unit, aoAbrirConfiguracoes: () -> Unit) {
    Column(
        Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        Visor(Modifier.size(160.dp))
        Text(if (semCamera) t("Este celular não lê QR pela câmera") else t("Libere a câmera para ler o QR"), style = estilo(Tipo.titulo),
             color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.lg))
        Text(
            if (semCamera) t("Cole ou digite o endereço no campo.")
            else t("A câmera só lê o código, aqui no celular. Nenhuma imagem é guardada nem sai do aparelho."),
            style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs),
        )
        if (!semCamera) {
            Text(t("Nas configurações do celular, em Apps, Escalibur Wallet, Permissões, ligue a Câmera."), style = estilo(Tipo.nota),
                 color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.lg))
        }
        Spacer(Modifier.weight(1f))
        if (semCamera) {
            BotaoPrimario(t("Voltar"), Modifier.fillMaxWidth()) { aoFechar() }
        } else {
            BotaoPrimario(t("Abrir configurações"), Modifier.fillMaxWidth()) { aoAbrirConfiguracoes() }
            BotaoTerciario(t("Agora não"), Modifier.fillMaxWidth()) { aoFechar() }
        }
    }
}
