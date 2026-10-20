package app.escalibur.wallet.ui.principal

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.abertura.OfertaDeBiometria
import app.escalibur.wallet.ui.carteira.AdicionarCarteira
import app.escalibur.wallet.ui.carteira.TelaDaCarteira
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.toqueDeSelecao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Paleta

enum class Aba { carteira, mercado, trocar, atividade, ajustes }

/**
 * O que fica por cima das abas: os fluxos de tela cheia (adicionar carteira, receber, enviar) e as
 * telas empilhadas (detalhe de um ativo). Voltar fecha o de cima.
 */
object Navegacao {
    var aba by mutableStateOf(Aba.carteira)
    val pilha = mutableStateListOf<@Composable () -> Unit>()

    fun abrir(tela: @Composable () -> Unit) { pilha.add(tela) }

    fun fechar() { if (pilha.isNotEmpty()) pilha.removeAt(pilha.lastIndex) }

    fun fecharTudo() { pilha.clear() }

    /** So no build de depuracao: a tela pedida pelo adb, aberta uma vez depois de destrancar. */
    var telaDeDepuracao: String? = null
}

/** O app destrancado. Sem carteira: a oferta da biometria (uma vez) e a primeira carteira. */
@Composable
fun Principal() {
    val estado = App.estado
    var ofereceuBiometria by rememberSaveable { mutableStateOf(false) }
    var primeiraVez by rememberSaveable { mutableStateOf(estado.carteiras.isEmpty()) }
    if (estado.carteiras.isEmpty() || primeiraVez) {
        if (!ofereceuBiometria && estado.biometriaPronta && !estado.biometriaLigada && !estado.reforcado) {
            OfertaDeBiometria { ofereceuBiometria = true }
        } else {
            AdicionarCarteira(primeira = true) { primeiraVez = false }
        }
        return
    }
    if (app.escalibur.wallet.BuildConfig.DEBUG) {
        androidx.compose.runtime.LaunchedEffect(Unit) {
            val tela = Navegacao.telaDeDepuracao ?: return@LaunchedEffect
            Navegacao.telaDeDepuracao = null
            if (tela.startsWith("enviar-")) Navegacao.abrir { app.escalibur.wallet.ui.enviar.FluxoDeEnviar("demo:" + tela.removePrefix("enviar-")) }
        }
    }
    Box(Modifier.fillMaxSize().background(Paleta.vazio)) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) {
                Crossfade(Navegacao.aba, animationSpec = tween(120), label = "aba") { aba ->
                    when (aba) {
                        Aba.carteira -> TelaDaCarteira()
                        Aba.mercado -> app.escalibur.wallet.ui.mercado.TelaDoMercado()
                        Aba.trocar -> app.escalibur.wallet.ui.trocar.TelaDeTrocar()
                        Aba.atividade -> app.escalibur.wallet.ui.atividade.TelaDeAtividade()
                        Aba.ajustes -> app.escalibur.wallet.ui.ajustes.TelaDeAjustes()
                    }
                }
            }
            BarraDeAbas()
        }
        Navegacao.pilha.forEachIndexed { indice, tela ->
            Box(Modifier.fillMaxSize().background(Paleta.vazio)) { tela() }
            if (indice == Navegacao.pilha.lastIndex) BackHandler { Navegacao.fechar() }
        }
    }
}

@Composable
private fun BarraDeAbas() {
    val toque = toqueDeSelecao()
    Row(
        Modifier.fillMaxWidth().background(Paleta.vazio).navigationBarsPadding().height(56.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val abas: List<Triple<Aba, String, ImageVector>> = listOf(
            Triple(Aba.carteira, t("Carteira"), Icones.carteira),
            Triple(Aba.mercado, t("Mercado"), Icones.mercado),
            Triple(Aba.trocar, t("Trocar"), Icones.trocar),
            Triple(Aba.atividade, t("Atividade"), Icones.atividade),
            Triple(Aba.ajustes, t("Ajustes"), Icones.ajustes),
        )
        for ((aba, titulo, icone) in abas) {
            val escolhida = Navegacao.aba == aba
            Column(
                Modifier.weight(1f).clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Tab) {
                    if (!escolhida) toque()
                    Navegacao.aba = aba
                },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Icone(icone, if (escolhida) Paleta.acento else Paleta.tintaApagada, tamanho = 24.dp)
                Text(titulo, fontSize = 10.sp, color = if (escolhida) Paleta.acento else Paleta.tintaApagada, maxLines = 1)
            }
        }
    }
}
