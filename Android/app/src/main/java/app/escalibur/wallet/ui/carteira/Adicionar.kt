package app.escalibur.wallet.ui.carteira

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
import androidx.compose.ui.graphics.PathEffect
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
                LinhaDeOrigem(t("Importar com a senha da carteira"), t("Você já tem 12 ou 24 palavras de outra carteira."), Icones.teclado) { rota = "importar" }
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
        Box(Modifier.size(40.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) { Icone(icone, Paleta.tinta, tamanho = 19.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            Text(subtitulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
        Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 15.dp)
    }
}

/** O selo do app no centro e as redes em duas orbitas, girando devagar em sentidos opostos. */
@Composable
fun OrbitaDaCarteira(altura: Dp, modifier: Modifier = Modifier) {
    val dentro = listOf("bitcoin", "ethereum", "solana", "ripple", "tron")
    val fora = listOf("binancecoin", "the-open-network", "cardano", "stellar", "dogecoin", "polkadot", "sui", "near")
    val giro = rememberInfiniteTransition(label = "orbita")
    val tempo by giro.animateFloat(0f, (2 * PI * 20).toFloat(), infiniteRepeatable(tween(400_000, easing = LinearEasing)), label = "tempo")
    Box(modifier.height(altura), contentAlignment = Alignment.Center) {
        val raioDentro = altura * 0.27f
        val raioFora = altura * 0.44f
        Canvas(Modifier.size(altura)) {
            drawCircle(Paleta.bordaForte, raioDentro.toPx(), style = Stroke(1.dp.toPx()))
            drawCircle(Paleta.borda, raioFora.toPx(), style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 6.dp.toPx()))))
        }
        dentro.forEachIndexed { indice, id ->
            val angulo = indice.toDouble() / dentro.size * 2 * PI + tempo * 0.5
            LogoDaMoeda(id, tamanho = altura * 0.13f, modifier = Modifier.offset(raioDentro * cos(angulo).toFloat(), raioDentro * sin(angulo).toFloat()))
        }
        fora.forEachIndexed { indice, id ->
            val angulo = indice.toDouble() / fora.size * 2 * PI + 0.3 - tempo * 0.32
            LogoDaMoeda(id, tamanho = altura * 0.1f, modifier = Modifier.offset(raioFora * cos(angulo).toFloat(), raioFora * sin(angulo).toFloat()))
        }
        SeloDaCarteira(altura * 0.22f)
    }
}
