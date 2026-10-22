package app.escalibur.wallet.ui.carteira

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
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
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoDeSegurar
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Remover uma carteira deste celular: o aviso do que se perde e a remocao, com PIN e biometria (menos a
 * de so observar, que nao guarda chave). Um caminho so para a lista, a troca de carteira e os ajustes
 * da carteira (o WalletRemoval do iOS).
 */
object RemocaoDeCarteira {
    fun aviso(carteira: Carteira): String = when {
        carteira.observacao -> t("O endereço sai da lista. Nada muda na rede.")
        !carteira.temCopia -> t("Esta carteira não tem cópia confirmada. Removida, o saldo fica inacessível para sempre.")
        carteira.temPassphrase -> t("O saldo continua na blockchain. Sem a senha da carteira e a passphrase, ou um envelope, você não volta a acessá-lo.")
        else -> t("O saldo continua na blockchain. Sem a senha da carteira ou um envelope, você não volta a acessá-lo.")
    }

    /** Devolve se removeu. */
    suspend fun remover(carteira: Carteira): Boolean {
        try {
            val removeu = if (carteira.observacao) {
                App.aplicar(Api.objeto("carteira.removerObservacao", JSONObject().put("id", carteira.id)))
            } else {
                Autorizacao.tentando(t("Remover %@ deste celular", carteira.nome), Autorizacao.Presenca.pinEBiometria) { credencial ->
                    App.aplicar(Api.comSegredo("carteira.remover", JSONObject().put("id", carteira.id).put("credencial", credencial.json()), *credencial.partes()))
                }
            }
            if (removeu != null) {
                App.recarregar()
                return true
            }
        } catch (falha: FalhaDoNucleo) {
            Avisos.mostrar(Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível remover agora."))
        }
        return false
    }
}

/**
 * A confirmacao de apagar uma carteira (o RemoveWalletPopup do iOS): um popup no meio da tela, com o
 * aviso e um botao que so apaga segurado, enchendo de vermelho. Soltar antes cancela. Depois dele vem
 * o PIN e a biometria de sempre.
 */
@Composable
fun PopupDeRemover(carteira: Carteira, aoFechar: (confirmou: Boolean) -> Unit) {
    val entrada = remember { MutableTransitionState(false).apply { targetState = true } }
    Dialog(onDismissRequest = { aoFechar(false) }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val janela = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect { janela?.setDimAmount(0.5f) }
        AnimatedVisibility(
            entrada,
            enter = scaleIn(spring(dampingRatio = 0.86f, stiffness = 600f), initialScale = 0.92f) + fadeIn(tween(160)),
            exit = scaleOut(tween(140), targetScale = 0.96f) + fadeOut(tween(140)),
        ) {
            val forma = RoundedCornerShape(28.dp)
            Column(
                Modifier.padding(horizontal = Espaco.xl).widthIn(max = 340.dp).fillMaxWidth().clip(forma).background(Paleta.corpo)
                    .border(1.dp, Paleta.borda, forma).padding(horizontal = Espaco.lg).padding(top = Espaco.lg, bottom = Espaco.sm),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                GlifoDaCarteira(carteira, 44.dp, selecionada = true)
                Text(t("Remover %@ deste celular?", carteira.nome), style = estilo(Tipo.cabecalho), color = Paleta.tinta, textAlign = TextAlign.Center,
                     modifier = Modifier.padding(top = Espaco.md))
                Text(RemocaoDeCarteira.aviso(carteira), style = estilo(Tipo.nota), color = Paleta.tintaSuave, textAlign = TextAlign.Center,
                     modifier = Modifier.padding(top = Espaco.xs))
                BotaoDeSegurar(t("Segure para remover"), Modifier.padding(top = Espaco.lg), segundos = 1.6f, cor = Paleta.baixa) { aoFechar(true) }
                BotaoTerciario(t("Cancelar"), Modifier.padding(top = Espaco.xs)) { aoFechar(false) }
            }
        }
    }
}

/**
 * Arrastar a linha para a esquerda mostra o apagar, como nas listas do iOS. Uma linha aberta por vez
 * (`aberta`); tocar nela fecha. O arrasto so conta na horizontal: a lista continua rolando e o
 * segurar-e-arrastar da ordem continua igual.
 */
@Composable
fun LinhaQueApaga(
    id: String, aberta: String?, aoMudar: (String?) -> Unit, aoApagar: () -> Unit,
    modifier: Modifier = Modifier, superficie: Color = Paleta.corpo, conteudo: @Composable () -> Unit,
) {
    val largura = 84.dp
    val px = with(LocalDensity.current) { largura.toPx() }
    val densidade = LocalDensity.current
    val escopo = rememberCoroutineScope()
    val haptico = LocalHapticFeedback.current
    val deslocamento = remember { Animatable(0f) }
    val estaAberta = aberta == id
    // O gesto vive enquanto a linha existe: le sempre o estado de agora.
    val abertaAgora by rememberUpdatedState(aberta)
    val mudar by rememberUpdatedState(aoMudar)
    LaunchedEffect(estaAberta) { deslocamento.animateTo(if (estaAberta) -px else 0f, spring(dampingRatio = 0.86f, stiffness = 500f)) }
    Box(
        modifier.fillMaxWidth().height(IntrinsicSize.Min).clipToBounds()
            .semantics { customActions = listOf(CustomAccessibilityAction(t("Apagar")) { aoApagar(); true }) },
    ) {
        if (deslocamento.value < 0f) {
            Box(
                Modifier.align(Alignment.CenterEnd).fillMaxHeight().width(maxOf(largura, with(densidade) { (-deslocamento.value).toDp() }))
                    .background(Paleta.baixa).clickable {
                        mudar(null)
                        aoApagar()
                    },
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Icone(Icones.lixeira, Color.White, tamanho = 18.dp)
                    Text(t("Apagar"), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                }
            }
        }
        Box(
            Modifier.graphicsLayer { translationX = deslocamento.value }.background(superficie)
                .pointerInput(id) {
                    detectHorizontalDragGestures(
                        onDragStart = { if (abertaAgora != null && abertaAgora != id) mudar(null) },
                        onDragEnd = {
                            val abrir = deslocamento.value < -px / 2
                            if (abrir && abertaAgora != id) haptico.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            mudar(if (abrir) id else if (abertaAgora == id) null else abertaAgora)
                            escopo.launch { deslocamento.animateTo(if (abrir) -px else 0f, spring(dampingRatio = 0.86f, stiffness = 500f)) }
                        },
                        onDragCancel = { escopo.launch { deslocamento.animateTo(if (abertaAgora == id) -px else 0f) } },
                    ) { mudanca, dx ->
                        mudanca.consume()
                        escopo.launch { deslocamento.snapTo((deslocamento.value + dx).coerceIn(-px * 1.3f, 0f)) }
                    }
                },
        ) {
            conteudo()
            // Aberta, tocar na linha fecha (e nao abre a carteira).
            if (estaAberta) Box(Modifier.matchParentSize().clickable(remember { MutableInteractionSource() }, indication = null) { mudar(null) })
        }
    }
}
