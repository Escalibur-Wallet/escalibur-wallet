package app.escalibur.wallet.ui.carteira

import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.comp.TelaComBarra
import app.escalibur.wallet.ui.comp.Ponto
import app.escalibur.wallet.ui.comp.LixeiraDePixels
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.DeslizeParaSeguir
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.comp.Avisos
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
        !carteira.temCopia -> t("Esta carteira não tem cópia confirmada. Removida, o saldo pode ficar inacessível para sempre.")
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
 * A confirmacao de remover uma carteira (o RemoveWalletScreen do iOS, 24/10/2026): uma tela inteira no
 * formato das telas de aviso, com a lixeira em pixels, o que acontece com o saldo, que so as palavras
 * anotadas trazem a carteira de volta, e o deslizar embaixo, que um toque sem querer nao dispara.
 * Depois dele vem o PIN e a biometria de sempre.
 */
@Composable
fun TelaDeRemover(carteira: Carteira, aoFechar: (confirmou: Boolean) -> Unit) {
    Dialog(onDismissRequest = { aoFechar(false) }, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        TelaComBarra({ aoFechar(false) }, iconeDoVoltar = Icones.fechar, rodape = {
            DeslizeParaSeguir(t("Deslize para remover"), true) { aoFechar(true) }
        }) { espaco ->
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco)
                    .padding(horizontal = Espaco.margem).padding(top = Espaco.xl, bottom = Espaco.md),
            ) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    // A lixeira em pixels: a carteira cai nela.
                    LixeiraDePixels(Modifier.size(150.dp, 156.dp))
                    Text(t("Remover %@ deste celular?", carteira.nome), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                         modifier = Modifier.padding(top = Espaco.xs))
                    Text(t("Antes de deslizar, confira o que acontece."), style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
                }
                if (!carteira.observacao && !carteira.temCopia) Faixa(TipoDeFaixa.falha, RemocaoDeCarteira.aviso(carteira), Modifier.padding(top = Espaco.lg))
                Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
                    if (carteira.observacao) {
                        Ponto(Icones.lista, t("Só sai da lista"), RemocaoDeCarteira.aviso(carteira))
                    } else {
                        Ponto(Icones.rede, t("Nada muda na blockchain"), t("O saldo continua na rede. Remover apaga a carteira só deste celular."))
                        Ponto(Icones.chave, t("Só as palavras trazem de volta"),
                              t("Para usar a carteira de novo, você precisa das %lld palavras que anotou, ou de um envelope Escalibur. Ninguém recupera sem elas, nem a Escalibur.",
                                carteira.palavras ?: 12))
                        if (carteira.temPassphrase) {
                            Ponto(Icones.cadeado, t("E a passphrase"), t("Esta carteira abre com uma passphrase. Sem ela, as palavras abrem só a carteira de sempre."))
                        }
                        Ponto(Icones.visto, t("Confira antes de remover"),
                              t("Tenha as palavras com você e confira que estão certas. Depois de removida, não dá para ver as palavras por aqui."))
                    }
                    // A unica carteira: removida, o nucleo apaga tudo e o app volta ao comeco.
                    if (App.estado.carteiras.all { it.id == carteira.id }) {
                        Ponto(Icones.atualizar, t("O app recomeça do zero"),
                              t("É a única carteira deste celular. Removida, o app volta a ser como recém-instalado: o PIN, os ajustes e os contatos são apagados."))
                    }
                }
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
            // O vermelho so na parte descoberta, nunca por baixo da linha: por baixo, ele aparecia nas
            // bordas durante o arrasto (pedido do dono, 30/10/2026, como no iOS).
            Box(
                Modifier.align(Alignment.CenterEnd).fillMaxHeight().width(with(densidade) { (-deslocamento.value).toDp() })
                    .clipToBounds().background(Paleta.baixa).clickable {
                        mudar(null)
                        aoApagar()
                    },
                contentAlignment = Alignment.Center,
            ) {
                Column(Modifier.requiredWidth(largura), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
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
