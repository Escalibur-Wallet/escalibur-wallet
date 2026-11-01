package app.escalibur.wallet.ui.carteira

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import app.escalibur.wallet.ui.comp.SeloDaRede
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.comp.BotaoDeCanto
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.comp.SeloDaCarteira
import app.escalibur.wallet.ui.envelope.FluxoDeAbrirEnvelope
import app.escalibur.wallet.ui.importar.FluxoDeImportar
import app.escalibur.wallet.ui.importar.ObservarEndereco
import app.escalibur.wallet.ui.novacarteira.FluxoDeNovaCarteira
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** De onde vem a carteira. As importacoes sao linhas; criar e o primario. */
@Composable
fun AdicionarCarteira(primeira: Boolean, aoTerminar: () -> Unit) {
    var rota by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { Redes.carregar() }
    when (rota) {
        "criar" -> { FluxoDeNovaCarteira(primeira) { rota = null; aoTerminar() }; return }
        "importar" -> { FluxoDeImportar(aoCancelar = { rota = null }) { rota = null; aoTerminar() }; return }
        "observar" -> { ObservarEndereco(aoCancelar = { rota = null }) { rota = null; aoTerminar() }; return }
        "envelope" -> { FluxoDeAbrirEnvelope(aoCancelar = { rota = null }) { rota = null; aoTerminar() }; return }
    }
    if (!primeira) BackHandler(onBack = aoTerminar)
    Box(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding()) {
        Column(Modifier.fillMaxSize()) {
            OrbitaDaCarteira(260.dp, Modifier.fillMaxWidth().padding(top = Espaco.xs))
            Column(Modifier.fillMaxWidth().padding(horizontal = Espaco.margem).padding(top = Espaco.sm), horizontalAlignment = Alignment.CenterHorizontally,
                   verticalArrangement = Arrangement.spacedBy(Espaco.xxs)) {
                Text(if (primeira) t("Sua primeira carteira") else t("Adicionar carteira"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center)
                Text(t("Uma frase, um endereço em cada rede. As chaves ficam só neste celular."), style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
            }
            Column(Modifier.padding(top = Espaco.md)) {
                LinhaDeOrigem(t("Importar com a senha da carteira"), t("Você já tem 12 ou 24 palavras de outra carteira."), Icones.palavras) { rota = "importar" }
                LinhaDeOrigem(t("Importar de um envelope Escalibur"), t("O arquivo .esclbr e a senha do envelope."), Icones.envelope) { rota = "envelope" }
                LinhaDeOrigem(t("Só observar um endereço"), t("Acompanhe um saldo sem poder enviar."), Icones.olho) { rota = "observar" }
            }
            Spacer(Modifier.weight(1f))
            Rodape { BotaoPrimario(t("Criar carteira nova")) { rota = "criar" } }
        }
        if (!primeira) BotaoDeCanto(Icones.fechar, t("Fechar"), Modifier.padding(start = Espaco.xs), acao = aoTerminar)
    }
}

@Composable
private fun LinhaDeOrigem(titulo: String, subtitulo: String, icone: ImageVector, acao: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = acao).height(72.dp).padding(horizontal = Espaco.margem),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) { Icone(icone, Color.White, tamanho = 18.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            Text(subtitulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
        Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 13.dp)
    }
}

/**
 * O selo do app no centro e as redes em duas orbitas, como o WalletOrbit do iOS: dentro as seis
 * principais (34 dp, uma volta a cada 40 s), fora as doze seguintes da lista de redes (30 dp, uma
 * volta a cada 60 s no sentido contrario). O selo entra crescendo, com uma mola.
 */
@Composable
fun OrbitaDaCarteira(altura: Dp, modifier: Modifier = Modifier) {
    val principais = listOf("bitcoin", "ethereum", "solana", "xrpl", "tron", "ton")
    val dentro = principais.mapNotNull { Redes.rede(it) }
    val fora = Redes.todas.filter { it.id !in principais }.take(12)
    val giro = rememberInfiniteTransition(label = "orbita")
    val segundos by giro.animateFloat(0f, 120f, infiniteRepeatable(tween(120_000, easing = LinearEasing)), label = "tempo")
    var apareceu by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { apareceu = true }
    val entrada by androidx.compose.animation.core.animateFloatAsState(if (apareceu) 1f else 0f,
        androidx.compose.animation.core.spring(dampingRatio = 0.72f, stiffness = 80f), label = "entrada")
    BoxWithConstraints(modifier.height(altura).graphicsLayer { alpha = entrada.coerceIn(0f, 1f) }, contentAlignment = Alignment.Center) {
        val raioFora = minOf(maxWidth, altura) / 2 - 20.dp
        val raioDentro = raioFora * 0.66f
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(Paleta.borda, raioFora.toPx(), style = Stroke(1.dp.toPx()))
            drawCircle(Paleta.borda, raioDentro.toPx(), style = Stroke(1.dp.toPx()))
        }
        val anguloFora = -segundos / 60.0 * 2 * PI
        val anguloDentro = segundos / 40.0 * 2 * PI
        fora.forEachIndexed { indice, rede ->
            val angulo = anguloFora + indice.toDouble() / fora.size * 2 * PI
            SeloDaRede(rede.id, rede.coingecko, tamanho = 30.dp,
                       modifier = Modifier.offset(raioFora * cos(angulo).toFloat(), raioFora * sin(angulo).toFloat()))
        }
        dentro.forEachIndexed { indice, rede ->
            val angulo = anguloDentro + indice.toDouble() / dentro.size * 2 * PI
            SeloDaRede(rede.id, rede.coingecko, tamanho = 34.dp,
                       modifier = Modifier.offset(raioDentro * cos(angulo).toFloat(), raioDentro * sin(angulo).toFloat()))
        }
        Box(Modifier.graphicsLayer { val escala = 0.7f + 0.3f * entrada; scaleX = escala; scaleY = escala }) { SeloDaCarteira(52.dp) }
    }
}
