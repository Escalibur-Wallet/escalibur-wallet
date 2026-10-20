package app.escalibur.wallet.ui.pin

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlin.math.sin

/**
 * O PIN em digitacao. Os digitos vao direto para um byte[] de tamanho fixo: o PIN nunca vira
 * String, nem estado de texto, nem passa por teclado do sistema (que aprende o que se digita).
 * `tamanhos`: os que fecham o PIN (os do cofre, ao conferir; o escolhido, ao criar). Com dois, o
 * PIN fecha sozinho no maior e o menor vai pela tecla OK.
 */
@Stable
class EntradaDoPin(tamanhos: Set<Int>) {
    var tamanhos by mutableStateOf(tamanhos)
        private set
    var quantos by mutableIntStateOf(0)
        private set
    var erro by mutableStateOf<String?>(null)
    var tremida by mutableIntStateOf(0)
        private set
    private var digitos = ByteArray(6)

    val tamanho: Int get() = tamanhos.maxOrNull() ?: 6
    val aceitaMenor: Boolean get() = tamanhos.size > 1 && quantos in tamanhos && quantos < tamanho
    val completo: Boolean get() = quantos == tamanho

    fun escolher(novo: Int) {
        if (novo != 4 && novo != 6) return
        limpar()
        tamanhos = setOf(novo)
    }

    fun usarTamanhos(novos: Set<Int>) {
        if (quantos == 0) tamanhos = novos
    }

    fun digitar(digito: Int) {
        if (quantos >= tamanho) return
        digitos[quantos] = (0x30 + digito).toByte()
        quantos++
    }

    fun apagar() {
        if (quantos == 0) return
        quantos--
        digitos[quantos] = 0
    }

    /** Entrega o PIN digitado (quem recebe zera) e comeca do zero. */
    fun tirar(): ByteArray {
        val pin = digitos.copyOf(quantos)
        digitos.fill(0)
        quantos = 0
        erro = null
        return pin
    }

    fun falhar(mensagem: String) {
        erro = mensagem
        tremida++
        digitos.fill(0)
        quantos = 0
    }

    fun limpar() {
        digitos.fill(0)
        quantos = 0
        erro = null
    }
}

/** Um ponto por digito. Erro: os pontos apagam, os aros ficam vermelhos e uma sacudida curta. */
@Composable
fun PontosDoPin(preenchidos: Int, tamanho: Int, falhou: Boolean, tremida: Int) {
    val deslocamento = remember { Animatable(0f) }
    LaunchedEffect(tremida) {
        if (tremida > 0) {
            deslocamento.snapTo(0f)
            deslocamento.animateTo(1f, tween(260))
        }
    }
    Row(
        Modifier
            .offset(x = (10 * sin(deslocamento.value * Math.PI * 6)).dp)
            .semantics { contentDescription = t("%lld de %lld dígitos", preenchidos, tamanho) },
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        repeat(tamanho) { indice ->
            val cheio = indice < preenchidos
            val escala by animateFloatAsState(if (cheio) 1f else 0.6f, tween(120), label = "ponto")
            Box(Modifier.size(12.dp).border(1.5.dp, if (falhou) Paleta.baixa else Paleta.tintaApagada, CircleShape), contentAlignment = Alignment.Center) {
                if (cheio) Box(Modifier.size(12.dp).scale(escala).clip(CircleShape).background(Paleta.tinta))
            }
        }
    }
}

/** O teclado do PIN: plano, sem letras. */
@Composable
fun TecladoDoPin(entrada: EntradaDoPin, ligado: Boolean, iconeDeBiometria: ImageVector? = null, aoUsarBiometria: (() -> Unit)? = null, aoCompletar: () -> Unit) {
    val haptico = LocalHapticFeedback.current
    val linhas = listOf(listOf(1, 2, 3), listOf(4, 5, 6), listOf(7, 8, 9), listOf(null, 0, -1))
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        for (linha in linhas) {
            Row(horizontalArrangement = Arrangement.spacedBy(26.dp)) {
                for (tecla in linha) {
                    when (tecla) {
                        -1 -> TeclaDeFuncao(Icones.apagarLetra, t("Apagar"), ligado) { entrada.apagar() }
                        null -> when {
                            entrada.aceitaMenor -> Tecla("OK", ligado) { aoCompletar() }
                            iconeDeBiometria != null && aoUsarBiometria != null -> TeclaDeFuncao(iconeDeBiometria, t("Usar a biometria"), ligado, aoUsarBiometria)
                            else -> Spacer(Modifier.size(Altura.teclaDoPin))
                        }
                        else -> Tecla("$tecla", ligado) {
                            haptico.performHapticFeedback(HapticFeedbackType.KeyboardTap)
                            entrada.digitar(tecla)
                            if (entrada.completo) aoCompletar()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Tecla(texto: String, ligado: Boolean, acao: () -> Unit) {
    val interacao = remember { MutableInteractionSource() }
    val apertado by interacao.collectIsPressedAsState()
    val escala by animateFloatAsState(if (apertado) 0.94f else 1f, tween(100), label = "tecla")
    Box(
        Modifier
            .size(Altura.teclaDoPin)
            .graphicsLayer { scaleX = escala; scaleY = escala }
            .clip(CircleShape)
            .background(if (apertado) Paleta.borda else Paleta.trilho)
            .clickable(interacao, indication = null, enabled = ligado, onClick = acao),
        contentAlignment = Alignment.Center,
    ) {
        Text(texto, style = estilo(Tipo.tecla), color = Paleta.tinta)
    }
}

@Composable
private fun TeclaDeFuncao(icone: ImageVector, descricao: String, ligado: Boolean, acao: () -> Unit) {
    Box(
        Modifier.size(Altura.teclaDoPin).clip(CircleShape).clickable(enabled = ligado, onClickLabel = descricao, onClick = acao),
        contentAlignment = Alignment.Center,
    ) {
        Icone(icone, Paleta.tintaSuave, tamanho = 26.dp, descricao = descricao)
    }
}

/**
 * Tela de PIN completa: titulo, texto, pontos, erro, teclado e rodape. `reservaDoSubtitulo`: o
 * texto mais longo que o subtitulo pode ter nesta sequencia, para o teclado nao mudar de lugar.
 */
@Composable
fun TelaDoPin(
    titulo: String,
    subtitulo: String?,
    entrada: EntradaDoPin,
    modifier: Modifier = Modifier,
    reservaDoSubtitulo: String? = null,
    trabalhando: Boolean = false,
    topo: (@Composable () -> Unit)? = null,
    iconeDeBiometria: ImageVector? = null,
    aoUsarBiometria: (() -> Unit)? = null,
    aoCompletar: () -> Unit,
    rodape: @Composable ColumnScope.() -> Unit = {},
) {
    val haptico = LocalHapticFeedback.current
    LaunchedEffect(entrada.tremida) { if (entrada.tremida > 0) haptico.performHapticFeedback(HapticFeedbackType.Reject) }
    Column(
        modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f).heightIn(min = Espaco.xs))
        topo?.invoke()
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = Espaco.margem))
            if (subtitulo != null) {
                Box(Modifier.padding(horizontal = Espaco.xl), contentAlignment = Alignment.TopCenter) {
                    if (reservaDoSubtitulo != null) {
                        Text(reservaDoSubtitulo, style = estilo(Tipo.corpo), color = Paleta.vazio.copy(alpha = 0f), textAlign = TextAlign.Center)
                    }
                    Text(subtitulo, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
                }
            }
        }
        Spacer(Modifier.weight(0.6f).heightIn(min = Espaco.sm))
        Box(Modifier.height(24.dp), contentAlignment = Alignment.Center) {
            if (trabalhando) {
                CircularProgressIndicator(color = Paleta.tintaSuave, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
            } else {
                PontosDoPin(entrada.quantos, entrada.tamanho, entrada.erro != null && entrada.quantos == 0, entrada.tremida)
            }
        }
        Text(
            entrada.erro ?: " ", style = estilo(Tipo.nota), color = Paleta.baixa, textAlign = TextAlign.Center,
            modifier = Modifier.heightIn(min = 40.dp).padding(horizontal = Espaco.margem).padding(top = Espaco.sm),
        )
        Spacer(Modifier.weight(0.4f).heightIn(min = Espaco.md))
        TecladoDoPin(entrada, !trabalhando, iconeDeBiometria, aoUsarBiometria, aoCompletar)
        Column(
            Modifier.fillMaxWidth().padding(top = Espaco.md, bottom = Espaco.xs),
            horizontalAlignment = Alignment.CenterHorizontally, content = rodape,
        )
        Spacer(Modifier.height(Espaco.lg))
    }
}
