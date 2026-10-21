package app.escalibur.wallet.ui.comp

import app.escalibur.wallet.ui.tema.Raio
import androidx.compose.ui.graphics.Color
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.remember
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Animatable
import androidx.activity.compose.BackHandler
import kotlinx.coroutines.launch
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.clip
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo

/** A altura da barra de navegacao do iOS, abaixo da barra de status. */
val AlturaDaBarraDeNavegacao = 52.dp

/** Dentro de uma folha: a folha ja comeca abaixo da barra de status. */
val LocalDentroDaFolha = androidx.compose.runtime.staticCompositionLocalOf { false }

/**
 * Uma tela empurrada com a barra do iOS 26: o voltar num circulo de vidro a esquerda, o titulo no
 * centro e as acoes num vidro so a direita. O conteudo rola por baixo da barra, desfocado pelos
 * vidros, e some numa faixa do fundo da tela no alto (a borda de rolagem do iOS). O rodape de acao,
 * se houver, fica fixo embaixo, com o fundo solido, e o conteudo termina acima dele.
 *
 * O conteudo recebe o espaco de cima (barra de status e barra) e o de baixo (a barra de abas, a de
 * navegacao do Android, ou nada quando ha rodape) para pôr na rolagem.
 */
@Composable
fun TelaComBarra(
    aoVoltar: (() -> Unit)?,
    modifier: Modifier = Modifier,
    titulo: String? = null,
    centro: (@Composable () -> Unit)? = null,
    acoes: (@Composable RowScope.() -> Unit)? = null,
    rodape: (@Composable ColumnScope.() -> Unit)? = null,
    fundo: Color = Paleta.vazio,
    conteudo: @Composable (PaddingValues) -> Unit,
) {
    // Na folha, a barra desce um pouco do alto dela, como a barra de navegacao das folhas do iOS.
    val topo = if (LocalDentroDaFolha.current) 12.dp else WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val barraDeAbas = LocalEspacoDaBarra.current
    val baixo = when {
        rodape != null -> 0.dp
        barraDeAbas > 0.dp -> barraDeAbas
        else -> WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    }
    Column(modifier.fillMaxSize().background(fundo)) {
        ComVidro(
            Modifier.weight(1f).fillMaxWidth(),
            frente = {
                // A borda de rolagem: o conteudo some no fundo da tela debaixo da barra.
                Box(
                    Modifier.fillMaxWidth().height(topo + AlturaDaBarraDeNavegacao + Espaco.md).background(
                        Brush.verticalGradient(
                            0f to fundo, 0.55f to fundo.copy(alpha = 0.92f), 1f to fundo.copy(alpha = 0f),
                        ),
                    ),
                )
                Box(Modifier.padding(top = topo).fillMaxWidth().height(AlturaDaBarraDeNavegacao).padding(horizontal = Espaco.md)) {
                    if (aoVoltar != null) BotaoDeCanto(Icones.voltar, t("Voltar"), Modifier.align(Alignment.CenterStart), acao = aoVoltar)
                    Box(Modifier.align(Alignment.Center).padding(horizontal = 96.dp)) {
                        when {
                            centro != null -> centro()
                            titulo != null -> Text(titulo, style = estilo(Tipo.acao), color = Paleta.tinta, textAlign = TextAlign.Center,
                                                   maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    if (acoes != null) GrupoDeVidro(Modifier.align(Alignment.CenterEnd), conteudo = acoes)
                }
            },
        ) {
            conteudo(PaddingValues(top = topo + AlturaDaBarraDeNavegacao, bottom = baixo))
        }
        if (rodape != null) Rodape(conteudo = rodape)
    }
}

/**
 * Uma folha do iOS fora da navegacao do app (na tela de bloqueio, antes de destravar): sobe de baixo
 * com os cantos de cima redondos, comecando logo abaixo da barra de status, sobre o fundo que
 * escurece. Arrastada para baixo ou no voltar, desce e fecha.
 */
@Composable
fun FolhaSolta(aoFechar: () -> Unit, fundo: Color = Paleta.corpo, conteudo: @Composable () -> Unit) {
    val escopo = rememberCoroutineScope()
    val posicao = remember { Animatable(1f) }
    val curva = CubicBezierEasing(0.2f, 0.9f, 0.25f, 1f)
    LaunchedEffect(Unit) { posicao.animateTo(0f, tween(460, easing = curva)) }
    fun fechar() {
        escopo.launch {
            posicao.animateTo(1f, tween(320, easing = curva))
            aoFechar()
        }
    }
    BackHandler { fechar() }
    val topo = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 10.dp
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val altura = constraints.maxHeight.toFloat()
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.38f * (1f - posicao.value))).seguraToques())
        Box(
            Modifier.fillMaxSize().padding(top = topo)
                .graphicsLayer { translationY = altura * posicao.value }
                .clip(RoundedCornerShape(topStart = Raio.folha, topEnd = Raio.folha))
                .background(fundo)
                .draggable(
                    rememberDraggableState { d -> escopo.launch { posicao.snapTo((posicao.value + d / altura).coerceIn(0f, 1f)) } },
                    Orientation.Vertical,
                    onDragStopped = { v -> if (posicao.value > 0.25f || v > 1800f) fechar() else escopo.launch { posicao.animateTo(0f, spring(dampingRatio = 0.86f, stiffness = 420f)) } },
                )
                .seguraToques(),
        ) {
            CompositionLocalProvider(LocalDentroDaFolha provides true) { conteudo() }
        }
    }
}
