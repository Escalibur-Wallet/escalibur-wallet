package app.escalibur.wallet.ui.comp

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo

/** Uma opcao do menu: o selo (a rede, o token), o titulo e se e a escolhida. */
data class OpcaoDoMenu(val id: String, val titulo: String, val selo: @Composable () -> Unit)

/**
 * O menu flutuante do iOS (o popover das redes): preso logo abaixo do que o abriu, alinhado pela
 * direita dele, cresce a partir dali. Linhas de 48 com o selo, o titulo e o visto na escolhida;
 * tocar fora fecha. Lista propria, como no iOS: o menu do sistema nao mostra o logo de cada rede.
 */
@Composable
fun MenuFlutuante(aberto: Boolean, opcoes: List<OpcaoDoMenu>, escolhida: String?, aoFechar: () -> Unit, aoEscolher: (String) -> Unit) {
    val estado = remember { MutableTransitionState(false) }
    estado.targetState = aberto
    if (!estado.currentState && !estado.targetState) return
    val toque = toqueDeSelecao()
    Popup(
        popupPositionProvider = remember {
            object : PopupPositionProvider {
                override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
                    val folga = (8 * (anchorBounds.height / 36f)).toInt().coerceAtLeast(16)
                    val x = (anchorBounds.right - popupContentSize.width).coerceIn(folga, windowSize.width - popupContentSize.width - folga)
                    val y = (anchorBounds.bottom + folga / 2).coerceAtMost(windowSize.height - popupContentSize.height - folga)
                    return IntOffset(x, y)
                }
            }
        },
        onDismissRequest = aoFechar,
        properties = PopupProperties(focusable = true),
    ) {
        AnimatedVisibility(
            estado,
            enter = scaleIn(spring(dampingRatio = 0.82f, stiffness = 520f), initialScale = 0.6f, transformOrigin = TransformOrigin(1f, 0f)) + fadeIn(tween(120)),
            exit = scaleOut(tween(160), targetScale = 0.7f, transformOrigin = TransformOrigin(1f, 0f)) + fadeOut(tween(140)),
        ) {
            val forma = RoundedCornerShape(22.dp)
            Column(
                Modifier.width(250.dp).heightIn(max = 440.dp)
                    .shadow(28.dp, forma, ambientColor = Color.Black.copy(alpha = 0.6f), spotColor = Color.Black.copy(alpha = 0.6f))
                    .clip(forma).background(Paleta.corpo).border(1.dp, Paleta.borda, forma)
                    .verticalScroll(rememberScrollState()).padding(vertical = Espaco.xs),
            ) {
                for (opcao in opcoes) {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Button) {
                            if (opcao.id != escolhida) toque()
                            aoFechar()
                            aoEscolher(opcao.id)
                        }.padding(horizontal = Espaco.md),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                    ) {
                        opcao.selo()
                        Text(opcao.titulo, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, modifier = Modifier.weight(1f))
                        if (opcao.id == escolhida) Icone(Icones.visto, Paleta.tinta, tamanho = 15.dp)
                    }
                }
            }
        }
    }
}

/**
 * A capsula que abre o menu de redes (o `NetworkMenu` do iOS): o selo da rede, o nome e a seta, num
 * fundo de cartao com borda.
 */
@Composable
fun PilulaComMenu(titulo: String, selo: @Composable () -> Unit, opcoes: List<OpcaoDoMenu>, escolhida: String?, modifier: Modifier = Modifier,
                  descricao: String = titulo, aoEscolher: (String) -> Unit) {
    var aberto by remember { mutableStateOf(false) }
    Box(modifier) {
        Row(
            Modifier.heightIn(min = 36.dp).clip(CircleShape).background(Paleta.corpo).border(1.dp, Paleta.borda, CircleShape)
                .clickable(role = Role.Button, onClickLabel = descricao) { aberto = true }.padding(start = 6.dp, end = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            selo()
            Text(titulo, style = estilo(Tipo.rotulo), color = Paleta.tinta, maxLines = 1)
            Icone(Icones.abaixo, Paleta.tintaSuave, tamanho = 11.dp)
        }
        MenuFlutuante(aberto, opcoes, escolhida, aoFechar = { aberto = false }, aoEscolher = aoEscolher)
    }
}
