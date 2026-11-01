package app.escalibur.wallet.ui.comp

import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.draw.shadow
import kotlinx.coroutines.launch
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.graphicsLayer
import kotlin.math.cos
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.delay

/** Aviso que fica na pagina ate ser resolvido: risco, falha ou neutro, cada um com um fundo so. */
enum class TipoDeFaixa { cautela, falha, neutra }

@Composable
fun Faixa(
    tipo: TipoDeFaixa, titulo: String, modifier: Modifier = Modifier, mensagem: String? = null,
    /** Sem fundo nem contorno, com o icone no meio da altura do texto (pedido do dono, 27/10/2026). */
    simples: Boolean = false,
    tituloDaAcao: String? = null, acao: (() -> Unit)? = null,
) {
    val forma = RoundedCornerShape(Raio.cartao)
    Row(
        modifier
            .fillMaxWidth()
            .then(if (simples) Modifier else Modifier
                .clip(forma)
                .background(
                    when (tipo) {
                        TipoDeFaixa.cautela -> Paleta.cautelaFundo
                        TipoDeFaixa.falha -> Paleta.baixaFundo
                        TipoDeFaixa.neutra -> Paleta.corpo
                    }
                )
                .then(if (tipo == TipoDeFaixa.neutra) Modifier.border(1.dp, Paleta.borda, forma) else Modifier)
                .padding(Espaco.md)),
        horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
        verticalAlignment = if (simples) Alignment.CenterVertically else Alignment.Top,
    ) {
        Icone(
            when (tipo) {
                TipoDeFaixa.cautela -> Icones.alerta
                TipoDeFaixa.falha -> Icones.falha
                TipoDeFaixa.neutra -> Icones.info
            },
            when (tipo) {
                TipoDeFaixa.cautela -> Paleta.cautela
                TipoDeFaixa.falha -> Paleta.baixa
                TipoDeFaixa.neutra -> Paleta.tintaSuave
            },
            tamanho = 20.dp,
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Espaco.xxs)) {
            Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            if (mensagem != null) Text(mensagem, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            if (tituloDaAcao != null && acao != null) {
                Text(
                    tituloDaAcao, style = estilo(Tipo.nota).copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
                    color = Paleta.tinta,
                    modifier = Modifier.heightIn(min = 32.dp).clickable(role = Role.Button, onClick = acao).padding(top = 8.dp),
                )
            }
        }
    }
}

/**
 * A escolha exclusiva do app ("12 palavras | 24 palavras"): trilho escuro e um segmento claro que
 * desliza ate a opcao escolhida.
 */
@Composable
fun <T> Segmentado(opcoes: List<Pair<T, String>>, selecao: T, modifier: Modifier = Modifier, aoEscolher: (T) -> Unit) {
    val indice = opcoes.indexOfFirst { it.first == selecao }.coerceAtLeast(0)
    val toque = toqueDeSelecao()
    BoxWithConstraints(
        modifier
            .clip(CircleShape)
            .background(Paleta.corpo)
            .padding(2.dp)
            .height(36.dp),
    ) {
        val largura = maxWidth / opcoes.size.coerceAtLeast(1)
        val deslocamento by animateDpAsState(largura * indice, spring(dampingRatio = 0.86f, stiffness = 700f), label = "segmento")
        Box(
            Modifier
                .offset(x = deslocamento)
                .width(largura)
                .fillMaxHeight()
                .vidro(CircleShape, Vidros.selecao)
        )
        Row(Modifier.fillMaxWidth().fillMaxHeight()) {
            opcoes.forEachIndexed { posicao, (valor, titulo) ->
                Box(
                    Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Tab) {
                            if (valor != selecao) toque()
                            aoEscolher(valor)
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        titulo, fontSize = 13.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                        color = if (posicao == indice) Paleta.tinta else Paleta.tintaApagada, maxLines = 1,
                    )
                }
            }
        }
    }
}

/** A caixa de marcar de um aceite: o dono declara, com um toque, que leu o que esta escrito. */
@Composable
fun Aceite(marcado: Boolean, texto: String, modifier: Modifier = Modifier, solto: Boolean = false, aoMudar: (Boolean) -> Unit) {
    val toque = toqueDeSelecao()
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Raio.cartao))
            .background(if (solto) Color.Transparent else Paleta.corpo)
            .clickable(role = Role.Checkbox) {
                toque()
                aoMudar(!marcado)
            }
            .padding(if (solto) Espaco.xxs else Espaco.md),
        horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        val forma = RoundedCornerShape(7.dp)
        Box(
            Modifier
                .padding(top = 1.dp)
                .size(24.dp)
                .clip(forma)
                .background(if (marcado) Paleta.controle else Paleta.vazio)
                .border(1.5.dp, if (marcado) Paleta.tintaSuave else Paleta.bordaForte, forma),
            contentAlignment = Alignment.Center,
        ) {
            if (marcado) Icone(Icones.visto, Paleta.tinta, tamanho = 15.dp)
        }
        Text(texto, style = estilo(Tipo.nota), color = if (marcado) Paleta.tinta else Paleta.tintaSuave, modifier = Modifier.weight(1f))
    }
}

@Composable
fun Chip(titulo: String, selecionado: Boolean, modifier: Modifier = Modifier, acao: () -> Unit) {
    val toque = toqueDeSelecao()
    Box(
        modifier
            .height(Altura.chip)
            .clip(CircleShape)
            .then(if (selecionado) Modifier.vidro(CircleShape, Vidros.selecao) else Modifier.border(1.dp, Paleta.borda, CircleShape))
            .clickable(role = Role.Button) {
                if (!selecionado) toque()
                acao()
            }
            .padding(horizontal = Espaco.sm),
        contentAlignment = Alignment.Center,
    ) {
        Text(titulo, style = estilo(Tipo.rotulo), color = if (selecionado) Paleta.tinta else Paleta.tintaSuave, maxLines = 1)
    }
}

/** O titulo de cada aba, sempre na mesma altura. */
@Composable
fun TituloDeAba(titulo: String, modifier: Modifier = Modifier, direita: @Composable RowScope.() -> Unit = {}) {
    Row(
        modifier.fillMaxWidth().height(Altura.barra).padding(horizontal = Espaco.margem),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.weight(1f))
        direita()
    }
}

@Composable
fun Cartao(modifier: Modifier = Modifier, preenchimento: Dp = Espaco.md, conteudo: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Raio.cartao))
            .background(Paleta.corpo)
            .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao))
            .padding(preenchimento),
        content = conteudo,
    )
}

/** A barra que brilha no lugar de um valor que ainda vem. */
@Composable
fun Esqueleto(largura: Dp, altura: Dp = 14.dp, modifier: Modifier = Modifier) {
    val transicao = rememberInfiniteTransition(label = "esqueleto")
    val brilho by transicao.animateFloat(0.45f, 0.9f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "brilho")
    Box(
        modifier
            .width(largura)
            .height(altura)
            .clip(RoundedCornerShape(altura / 2))
            .background(Paleta.trilho.copy(alpha = brilho))
    )
}

/**
 * O cabecalho de uma folha do iOS (o `SheetHeader`): o titulo grande a esquerda e o fechar num circulo
 * pequeno a direita, com um botao a mais antes dele quando preciso (o "+" do Receber).
 */
@Composable
fun CabecalhoDaFolha(titulo: String, aoFechar: (() -> Unit)?, modifier: Modifier = Modifier,
                     extra: Triple<androidx.compose.ui.graphics.vector.ImageVector, String, () -> Unit>? = null) {
    Row(modifier.fillMaxWidth().padding(horizontal = Espaco.margem).padding(top = Espaco.lg), verticalAlignment = Alignment.CenterVertically) {
        Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.weight(1f))
        if (extra != null) {
            Box(Modifier.size(Altura.toque).clip(CircleShape).clickable(onClickLabel = extra.second, onClick = extra.third), contentAlignment = Alignment.Center) {
                Box(Modifier.size(30.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                    Icone(extra.first, Paleta.tinta, tamanho = 15.dp, descricao = extra.second)
                }
            }
        }
        if (aoFechar != null) {
            Box(Modifier.size(Altura.toque).clip(CircleShape).clickable(onClickLabel = t("Fechar"), onClick = aoFechar), contentAlignment = Alignment.Center) {
                Box(Modifier.size(30.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                    Icone(Icones.fechar, Paleta.tintaSuave, tamanho = 13.dp, descricao = t("Fechar"))
                }
            }
        }
    }
}

/** O cabecalho de uma folha: titulo no centro e o fechar no canto. */
@Composable
fun CabecalhoDeFolha(titulo: String, aoFechar: (() -> Unit)?, modifier: Modifier = Modifier, aoVoltar: (() -> Unit)? = null) {
    Box(modifier.fillMaxWidth().height(Altura.barra + Espaco.xs).padding(horizontal = Espaco.xs)) {
        if (titulo.isEmpty()) {
            // A tela cheia do iOS, sem titulo: o botao fica a esquerda. Com voltar e fechar juntos, o
            // voltar a esquerda e o fechar vai para a direita.
            if (aoVoltar != null) BotaoDeCanto(Icones.voltar, t("Voltar"), Modifier.align(Alignment.CenterStart), acao = aoVoltar)
            if (aoFechar != null) BotaoDeCanto(Icones.fechar, t("Fechar"), Modifier.align(if (aoVoltar != null) Alignment.CenterEnd else Alignment.CenterStart),
                                               acao = aoFechar)
            return@Box
        }
        if (aoVoltar != null) BotaoDeCanto(Icones.voltar, t("Voltar"), Modifier.align(Alignment.CenterStart), acao = aoVoltar)
        Text(titulo, style = estilo(Tipo.acao), color = Paleta.tinta, textAlign = TextAlign.Center,
             modifier = Modifier.align(Alignment.Center).padding(horizontal = Altura.toque), maxLines = 1)
        if (aoFechar != null) BotaoDeCanto(Icones.fechar, t("Fechar"), Modifier.align(Alignment.CenterEnd), acao = aoFechar)
    }
}

/**
 * O aviso curto que aparece e some sozinho (copiado, salvo), como o do iOS: um cartao na largura da
 * tela, no alto, por cima de tudo, com o icone do tipo. Some em 2,5 s; arrastado para cima, sai na hora.
 */
object Avisos {
    enum class Tipo { sucesso, falha, informacao }

    data class Aviso(val texto: String, val tipo: Tipo, val numero: Int)

    var atual by mutableStateOf<Aviso?>(null)
        private set
    private var contador = 0

    fun mostrar(texto: String, tipo: Tipo = Tipo.sucesso) {
        contador++
        atual = Aviso(texto, tipo, contador)
    }

    @Composable
    fun Camada(modifier: Modifier = Modifier) {
        val aviso = atual
        val escopo = rememberCoroutineScope()
        val arraste = remember { Animatable(0f) }
        LaunchedEffect(aviso?.numero) {
            arraste.snapTo(0f)
            if (aviso != null) {
                delay(2500)
                if (atual?.numero == aviso.numero) atual = null
            }
        }
        var ultimo by remember { mutableStateOf<Aviso?>(null) }
        if (aviso != null) ultimo = aviso
        AnimatedVisibility(
            visible = aviso != null, modifier = modifier.statusBarsPadding().padding(top = Espaco.xs),
            enter = slideInVertically(spring(dampingRatio = 0.86f, stiffness = 440f)) { -it * 2 } + fadeIn(),
            exit = slideOutVertically(tween(200)) { -it * 2 } + fadeOut(tween(200)),
        ) {
            val mostrado = ultimo ?: return@AnimatedVisibility
            val (icone, cor) = when (mostrado.tipo) {
                Tipo.sucesso -> Icones.vistoCheio to Paleta.alta
                Tipo.falha -> Icones.fecharCheio to Paleta.baixa
                Tipo.informacao -> Icones.info to Paleta.tintaSuave
            }
            Row(
                Modifier.padding(horizontal = Espaco.margem).fillMaxWidth()
                    .graphicsLayer { translationY = arraste.value }
                    .shadow(24.dp, RoundedCornerShape(Raio.cartao), ambientColor = Color.Black.copy(alpha = 0.5f), spotColor = Color.Black.copy(alpha = 0.5f))
                    .clip(RoundedCornerShape(Raio.cartao)).background(Paleta.trilho).border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao))
                    .pointerInput(mostrado.numero) {
                        // Segue o dedo para cima; para baixo, so cede um pouco. Solto alto o bastante, sai.
                        detectVerticalDragGestures(
                            onDragEnd = {
                                if (arraste.value < -24.dp.toPx()) atual = null
                                else escopo.launch { arraste.animateTo(0f, spring(dampingRatio = 0.8f, stiffness = 500f)) }
                            },
                        ) { _, dy: Float -> escopo.launch { arraste.snapTo(arraste.value + if (arraste.value + dy < 0) dy else dy / 5) } }
                    }
                    .heightIn(min = 48.dp).padding(horizontal = Espaco.md, vertical = Espaco.sm),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
            ) {
                Icone(icone, cor, tamanho = 19.dp)
                Text(mostrado.texto, style = estilo(app.escalibur.wallet.ui.tema.Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
            }
        }
    }
}

/** O ponto de um passo ("Uns 2 minutos"): o icone num circulo, o titulo e o detalhe. */
@Composable
fun Ponto(icone: androidx.compose.ui.graphics.vector.ImageVector, titulo: String, detalhe: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(icone, Paleta.tinta, tamanho = 18.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            Text(detalhe, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
    }
}

@Composable
fun Divisor(modifier: Modifier = Modifier) {
    Spacer(modifier.fillMaxWidth().height(1.dp).background(Paleta.borda))
}

private fun t(chave: String) = app.escalibur.wallet.ui.t(chave)

/**
 * Uma camada por cima de outra tela segura todos os toques: sem isto, o toque num lugar vazio
 * passava para a tela de baixo (um toque no canto da escolha do Enviar abria a lista de carteiras).
 */
fun Modifier.seguraToques(): Modifier = pointerInput(Unit) {
    awaitPointerEventScope { while (true) awaitPointerEvent() }
}

/**
 * Quanto o fim de cada aba precisa deixar livre embaixo: a barra de abas flutua por cima do
 * conteudo, e o ultimo item nao pode ficar atras dela. Zero fora das abas.
 */
val LocalEspacoDaBarra = androidx.compose.runtime.staticCompositionLocalOf { 0.dp }

/** A situacao de uma movimentacao ou ordem (o `StatusBadge` do iOS): pendente com o ponto pulsando. */
enum class TipoDeSituacao { pendente, aberta, parcial, feita, encerrada, falhou }

@Composable
fun SeloDeSituacao(tipo: TipoDeSituacao, texto: String, modifier: Modifier = Modifier) {
    val (cor, fundo) = when (tipo) {
        TipoDeSituacao.pendente -> Paleta.tintaSuave to Paleta.trilho
        TipoDeSituacao.aberta, TipoDeSituacao.parcial -> Paleta.tinta to Paleta.controle
        TipoDeSituacao.feita -> Paleta.alta to Paleta.altaFundo
        TipoDeSituacao.encerrada -> Paleta.tintaApagada to Paleta.trilho
        TipoDeSituacao.falhou -> Paleta.baixa to Paleta.baixaFundo
    }
    Row(
        modifier.height(Altura.selo).clip(RoundedCornerShape(Raio.selo)).background(fundo).padding(horizontal = Espaco.xs),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (tipo == TipoDeSituacao.pendente) {
            val pulso by rememberInfiniteTransition(label = "pulso").animateFloat(0.45f, 1f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "alfa")
            Box(Modifier.size(6.dp).graphicsLayer { alpha = pulso }.clip(CircleShape).background(Paleta.tintaSuave))
        }
        Text(texto, style = estilo(Tipo.rotulo), color = cor, maxLines = 1)
    }
}

/**
 * O giro da moeda no detalhe (o `CoinSpin` do iOS): duas voltas em 3D ao abrir, assentando devagar,
 * e uma volta a cada 4,5 segundos. O verso desfaz o espelho, para o logo nunca aparecer invertido.
 */
fun Modifier.moedaGirando(atraso: Long = 0): Modifier = composed {
    val parado = movimentoReduzido()
    val angulo = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        if (parado) return@LaunchedEffect
        delay(150 + atraso)
        angulo.animateTo(angulo.value + 720f, tween(1500, easing = CubicBezierEasing(0.2f, 0.8f, 0.25f, 1f)))
        while (true) {
            delay(4500)
            angulo.animateTo(angulo.value + 360f, tween(1100, easing = FastOutSlowInEasing))
        }
    }
    graphicsLayer {
        val frente = cos(Math.toRadians(angulo.value.toDouble())) >= 0
        rotationY = angulo.value
        scaleX = if (frente) 1f else -1f
        cameraDistance = 6f * density
    }
}

/** O fechar de uma folha do iOS e o que fazer depois que ela saiu. */
class ControleDaFolha {
    var fechar: () -> Unit = {}
    var depois: (() -> Unit)? = null
}
