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
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo

/** Um botao do alerta do iOS. */
data class BotaoDeAlerta(val titulo: String, val cor: Color = Paleta.tinta, val ligado: Boolean = true, val acao: () -> Unit)

/**
 * O alerta do iOS 26: um cartao escuro de cantos bem redondos, o titulo em negrito e a mensagem
 * alinhados a esquerda, e os botoes em capsula. Com rotulos curtos, lado a lado (o cancelar a
 * esquerda); senao, um embaixo do outro, o cancelar por ultimo. Entra encolhendo um pouco ate o
 * lugar, como o do iOS. `cancelar` e o botao de voltar; `acoes`, os outros.
 */
@Composable
fun AlertaDoIos(titulo: String, mensagem: String?, cancelar: BotaoDeAlerta?, acoes: List<BotaoDeAlerta>, aoFechar: () -> Unit,
                extra: (@Composable () -> Unit)? = null) {
    val entrada = remember { MutableTransitionState(false).apply { targetState = true } }
    Dialog(onDismissRequest = aoFechar, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        // O fundo escurece de leve, como atras do alerta do iOS.
        val janela = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect { janela?.setDimAmount(0.32f) }
        AnimatedVisibility(
            entrada,
            enter = scaleIn(spring(dampingRatio = 0.8f, stiffness = 600f), initialScale = 1.12f) + fadeIn(tween(160)),
            exit = scaleOut(tween(140), targetScale = 0.96f) + fadeOut(tween(140)),
        ) {
            val forma = RoundedCornerShape(32.dp)
            Column(
                Modifier.padding(horizontal = 40.dp).widthIn(max = 320.dp).fillMaxWidth()
                    .vidro(forma, EstiloDoVidro(tom = Color(0xFF232326), semFundo = Color(0xFF232326), brilho = 0.8f))
                    .padding(start = Espaco.base, end = Espaco.base, top = Espaco.base, bottom = Espaco.md),
                verticalArrangement = Arrangement.spacedBy(Espaco.xs),
            ) {
                Text(titulo, style = estilo(Tipo.acao), color = Paleta.tinta)
                if (mensagem != null) Text(mensagem, style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                extra?.invoke()
                val todos = acoes + listOfNotNull(cancelar)
                val ladoALado = todos.size == 2 && todos.all { it.titulo.length <= 12 }
                if (ladoALado) {
                    Row(Modifier.padding(top = Espaco.sm), horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                        for (b in listOfNotNull(cancelar) + acoes) Box(Modifier.weight(1f)) { BotaoDoAlerta(b) }
                    }
                } else {
                    Column(Modifier.padding(top = Espaco.sm), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                        for (b in todos) BotaoDoAlerta(b)
                    }
                }
            }
        }
    }
}

/**
 * A confirmacao no centro da tela, para o que nao tem volta (apagar, sair sem a copia): o alerta do
 * iOS, com a acao em vermelho quando destroi.
 */
@Composable
fun Confirmacao(
    titulo: String, mensagem: String, tituloDaAcao: String, aoConfirmar: () -> Unit, aoCancelar: () -> Unit,
    tituloDoCancelar: String = app.escalibur.wallet.ui.t("Cancelar"), destrutiva: Boolean = true,
    /** Um aviso so de leitura: so o botao da acao ("Entendi"). */
    soUmBotao: Boolean = false,
) {
    AlertaDoIos(
        titulo, mensagem,
        cancelar = if (soUmBotao) null else BotaoDeAlerta(tituloDoCancelar, acao = aoCancelar),
        acoes = listOf(BotaoDeAlerta(tituloDaAcao, if (destrutiva) Paleta.baixa else Paleta.tinta, acao = aoConfirmar)),
        aoFechar = aoCancelar,
    )
}

/** Um botao do alerta: capsula cinza na largura do cartao, o texto na cor da acao. */
@Composable
private fun BotaoDoAlerta(botao: BotaoDeAlerta) {
    val toque = remember { MutableInteractionSource() }
    val apertado by toque.collectIsPressedAsState()
    Box(
        Modifier.fillMaxWidth().height(48.dp).clip(CircleShape).background(if (apertado) Color(0xFF48484D) else Color(0xFF39393D))
            .clickable(toque, indication = null, enabled = botao.ligado, role = Role.Button, onClick = botao.acao),
        contentAlignment = Alignment.Center,
    ) {
        Text(botao.titulo, style = estilo(Tipo.acao), color = if (botao.ligado) botao.cor else Paleta.tintaApagada, maxLines = 1)
    }
}
