package app.escalibur.wallet.ui.comp

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * O preenchimento do deslizar e do segurar (o `PixelFill` do iOS): pixels cinza que cifram. Atras do
 * cadeado, cada pixel troca de tom o tempo todo, como bits de um texto cifrado, cada um no seu
 * compasso, cruzando de um tom para o outro sem piscar. Na frente que avanca, os pixels nascem
 * pequenos e com mais contraste, e encaixam; de tempos em tempos uma passada clara corre a parte
 * cifrada. No fim, a varredura corre o resto do trilho, os tons param num cinza so e as juntas
 * fecham: o selo. Sem sorteio: o mesmo instante da sempre o mesmo desenho.
 *
 * `borda`: ate onde os pixels chegam, em px. `desdeOFim`: segundos desde que o dedo chegou ao fim
 * (nulo antes). `relogio`: segundos. `inclinacao`: quanto as linhas de baixo atrasam (a diagonal do
 * deslizar); zero, a frente anda reta.
 */
object PixelsCifrando {
    const val INCLINACAO = 0.55f
    const val FIM = 0.8f
    private const val TROCAS = 7.0
    private const val PASSADA = 1.8
    private const val VARREDURA = 0.34
    private const val SELO = 0.66

    fun DrawScope.desenhar(borda: Float, desdeOFim: Float?, relogio: Double, parado: Boolean, inclinacao: Float = INCLINACAO) {
        val celula = 6.dp.toPx()
        val junta = 1.5.dp.toPx()
        val frente = 48.dp.toPx()
        val passo = celula + junta
        val alcance = when {
            desdeOFim == null -> borda
            parado -> size.width * 2 + frente
            else -> { val fim = size.width + frente + 64.dp.toPx(); borda + (fim - borda) * saida(desdeOFim / VARREDURA.toFloat()) }
        }
        val solido = alcance - frente - 32.dp.toPx()
        val selo = when {
            desdeOFim == null -> 0.0
            parado -> 1.0
            else -> suave(((desdeOFim - VARREDURA * 0.8) / (FIM - VARREDURA)).toFloat()).toDouble()
        }
        val colunas = ceil(size.width / passo).toInt()
        val linhas = ceil((size.height + junta) / passo).toInt()
        val topo = (size.height - (linhas * passo - junta)) / 2
        val tempo = if (parado) 0.0 else relogio
        // A passada clara anda da esquerda ate a frente, e some no selo.
        val varre = ((tempo / PASSADA) % 1.0).toFloat() * maxOf(alcance + 40.dp.toPx(), 1f) - 20.dp.toPx()
        // Por baixo, as juntas: escuras com a cifra correndo, do cinza do selo no fim.
        if (solido > 0) drawRect(cinza(0.14 + (SELO - 0.14) * selo), size = Size(minOf(solido, size.width), size.height))
        val meio = (linhas - 1) / 2f
        for (coluna in 0 until colunas) {
            val x = coluna * passo
            if (x - alcance > frente) break
            for (linha in 0 until linhas) {
                // A linha do meio acompanha o cadeado; as de baixo vem um pouco atras.
                val atraso = (linha - meio) * passo * inclinacao
                val progresso = suave((alcance - atraso - (x + celula / 2)) / frente)
                if (progresso <= 0.02f) continue
                // O tom cifrado deste pixel agora: dois tons pelo hash do lugar e do compasso,
                // cruzados devagar, cada pixel com a sua fase.
                val fase = ruido(coluna, linha, 0x9E37)
                val batida = tempo * TROCAS * (0.6 + 0.8 * fase) + fase * 8
                val degrau = floor(batida)
                val mistura = suave((batida - degrau).toFloat()).toDouble()
                val a = ruido(coluna, linha, degrau.toLong())
                val b = ruido(coluna, linha, degrau.toLong() + 1)
                val bit = a + (b - a) * mistura
                // Na frente, mais contraste: os bits mais claros acendem antes de encaixar.
                val calor = 1 - progresso
                var tom = 0.17 + 0.26 * bit + 0.46 * calor * bit * bit * bit
                val distancia = ((x + celula / 2 - varre) / 22.dp.toPx()).toDouble()
                tom += 0.16 * exp(-distancia * distancia) * (1 - selo)
                tom += (SELO - tom) * selo
                // Nasce menor e encaixa no tamanho cheio; no selo, as juntas fecham.
                val recuo = celula * 0.32f * (1 - progresso) - junta / 2 * selo.toFloat()
                drawRoundRect(
                    cinza(tom).copy(alpha = 0.35f + 0.65f * progresso),
                    Offset(x + recuo, topo + linha * passo + recuo), Size(celula - 2 * recuo, celula - 2 * recuo),
                    CornerRadius(1.4.dp.toPx() * (1 - selo.toFloat())),
                )
            }
        }
    }

    /** Um cinza do app: o mesmo tom levemente frio do trilho e dos textos. */
    fun cinza(tom: Double): Color {
        val t = tom.coerceIn(0.0, 1.0).toFloat()
        return Color(t * 0.97f, t * 0.97f, t)
    }

    /** Um numero de 0 a 1 que so depende do lugar e do compasso. */
    fun ruido(coluna: Int, linha: Int, degrau: Long): Double {
        var h = ((coluna.toLong() * 73_856_093L) xor (linha.toLong() * 19_349_663L) xor (degrau * 83_492_791L)).toULong()
        h = h xor (h shr 33)
        h *= 0xFF51AFD7ED558CCDuL
        h = h xor (h shr 33)
        h *= 0xC4CEB9FE1A85EC53uL
        h = h xor (h shr 33)
        return (h shr 11).toDouble() / (1uL shl 53).toDouble()
    }

    private fun saida(x: Float): Float { val t = x.coerceIn(0f, 1f); return 1 - (1 - t) * (1 - t) * (1 - t) }
}

/** Os segundos de um relogio que so anda enquanto `andando`. */
@Composable
private fun relogioQueAnda(andando: Boolean): Double {
    var tempo by remember { mutableStateOf(0.0) }
    if (andando) LaunchedEffect(Unit) {
        val inicio = withFrameNanos { it }
        val base = tempo
        while (true) withFrameNanos { tempo = base + (it - inicio) / 1e9 }
    }
    return tempo
}

/**
 * Deslizar para seguir (o `SlideToConfirm` do iOS): o trilho com o cadeado que o dedo leva ate o fim.
 * Para passos que pedem atencao (digitar as palavras): um toque sem querer nao segue. Atras do cadeado,
 * os pixels cifrando, sem texto por cima; no fim eles selam num cinza so, e a acao vem na hora. Em
 * repouso o cadeado da uma espiada para a direita de tempos em tempos. Soltou antes do fim, volta.
 * Com o leitor de tela, o toque duplo confirma.
 */
@Composable
fun DeslizeParaSeguir(titulo: String, ligado: Boolean, aoSeguir: () -> Unit) {
    val haptico = LocalHapticFeedback.current
    val escopo = rememberCoroutineScope()
    val densidade = LocalDensity.current
    val parado = movimentoReduzido()
    val deslocamento = remember { Animatable(0f) }
    val espiada = remember { Animatable(0f) }
    var arrastando by remember { mutableStateOf(false) }
    var feito by remember { mutableStateOf(false) }
    var feitoEm by remember { mutableStateOf<Double?>(null) }
    var assentado by remember { mutableStateOf(false) }
    val altura = 64.dp
    val pegador = altura - 8.dp
    // A espiada: o cadeado anda um pouco e volta, para dizer que desliza.
    LaunchedEffect(ligado) {
        if (!ligado || parado) return@LaunchedEffect
        while (true) {
            delay(2600)
            if (arrastando || feito || deslocamento.value != 0f) continue
            espiada.animateTo(with(densidade) { 16.dp.toPx() }, tween(300, easing = LinearOutSlowInEasing))
            espiada.animateTo(0f, spring(dampingRatio = 0.55f, stiffness = 250f))
        }
    }
    BoxWithConstraints(
        Modifier.fillMaxWidth().height(altura).semantics {
            role = Role.Button
            contentDescription = titulo
            if (!ligado) disabled()
            onClick { if (ligado) aoSeguir(); ligado }
        },
    ) {
        val curso = with(densidade) { maxOf((maxWidth - pegador - 8.dp).toPx(), 1f) }
        val quatro = with(densidade) { 4.dp.toPx() }
        val pegadorPx = with(densidade) { pegador.toPx() }
        val avanco = minOf(deslocamento.value + espiada.value, curso)
        val mostrando = ligado && (avanco > 0f || feito)
        val agora = relogioQueAnda(mostrando && !parado && !assentado)
        Box(Modifier.fillMaxSize().clip(CircleShape).background(Paleta.trilho))
        if (mostrando) {
            Canvas(Modifier.fillMaxSize().clip(CircleShape)) {
                with(PixelsCifrando) { desenhar(quatro + avanco + pegadorPx / 2, feitoEm?.let { (agora - it).toFloat() }, agora, parado) }
            }
        }
        // O texto so na frente do cadeado: onde os pixels ja preencheram, nada.
        if (!feito) {
            Row(
                Modifier.fillMaxSize().padding(start = pegador * 0.8f).drawWithContent {
                    clipRect(left = quatro + avanco + pegadorPx - pegadorPx * 0.8f) { this@drawWithContent.drawContent() }
                },
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
            ) {
                val cor = if (ligado) Paleta.tinta else Paleta.tintaApagada
                Text(titulo, style = estilo(Tipo.acao), color = cor, maxLines = 1)
                Spacer(Modifier.width(Espaco.xs))
                Icone(Icones.chevronsDireita, cor, tamanho = 13.dp)
            }
        }
        Box(
            Modifier.offset { IntOffset((quatro + avanco).roundToInt(), quatro.roundToInt()) }.size(pegador).clip(CircleShape)
                .background(if (ligado) Color.White else Paleta.controle)
                .pointerInput(ligado) {
                    if (!ligado) return@pointerInput
                    detectHorizontalDragGestures(
                        onDragStart = { arrastando = true; escopo.launch { espiada.snapTo(0f) } },
                        onDragEnd = {
                            arrastando = false
                            if (feito) return@detectHorizontalDragGestures
                            escopo.launch {
                                if (deslocamento.value > curso * 0.85f) {
                                    feito = true
                                    feitoEm = agora
                                    haptico.performHapticFeedback(HapticFeedbackType.Confirm)
                                    aoSeguir()
                                    launch { deslocamento.animateTo(curso, spring(dampingRatio = 0.9f, stiffness = 630f)) }
                                    delay((PixelsCifrando.FIM * 1000).toLong())
                                    assentado = true
                                } else {
                                    deslocamento.animateTo(0f, spring(dampingRatio = 0.7f, stiffness = 320f))
                                }
                            }
                        },
                        onDragCancel = { arrastando = false; escopo.launch { deslocamento.animateTo(0f, spring(dampingRatio = 0.7f, stiffness = 320f)) } },
                    ) { _, arrasto ->
                        if (feito) return@detectHorizontalDragGestures
                        val antes = deslocamento.value
                        escopo.launch { deslocamento.snapTo((antes + arrasto).coerceIn(0f, curso)) }
                        if (antes == 0f && arrasto > 0) haptico.performHapticFeedback(HapticFeedbackType.SegmentTick)
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            Icone(Icones.cadeadoCheio, if (ligado) Paleta.vazio else Paleta.tintaApagada, tamanho = 20.dp)
        }
    }
}

/**
 * Um botao que so dispara depois de segurado por `segundos` (o `HoldButton` do iOS): os pixels
 * enchem o fundo enquanto o dedo esta em cima, e soltar antes cancela. Para o "usar mesmo assim" de
 * um risco grande, que nao pode sair de um toque sem querer. Com 0 segundos, e um toque comum.
 */
@Composable
fun BotaoDeSegurar(titulo: String, modifier: Modifier = Modifier, segundos: Float = 2f, acao: () -> Unit) {
    val haptico = LocalHapticFeedback.current
    val escopo = rememberCoroutineScope()
    val parado = movimentoReduzido()
    val fracao = remember { Animatable(0f) }
    var segurando by remember { mutableStateOf(false) }
    val agora = relogioQueAnda((segurando || fracao.value > 0f) && !parado)
    BoxWithConstraints(
        modifier.fillMaxWidth().height(Altura.secundaria).clip(CircleShape).background(Paleta.trilho)
            .semantics { role = Role.Button; contentDescription = titulo; onClick { acao(); true } }
            .pointerInput(segundos) {
                awaitEachGesture {
                    awaitFirstDown()
                    if (segundos <= 0f) {
                        val solto = waitForUpOrCancellation()
                        if (solto != null) acao()
                        return@awaitEachGesture
                    }
                    segurando = true
                    val enchendo: Job = escopo.launch {
                        fracao.snapTo(0f)
                        fracao.animateTo(1f, tween((segundos * 1000).toInt(), easing = LinearEasing))
                        haptico.performHapticFeedback(HapticFeedbackType.Reject)
                        acao()
                    }
                    waitForUpOrCancellation()
                    segurando = false
                    if (enchendo.isActive) {
                        enchendo.cancel()
                        // Soltou antes do fim: os pixels voltam dali, rapido.
                        escopo.launch { fracao.animateTo(0f, tween(200)) }
                    } else {
                        escopo.launch { delay(250); fracao.snapTo(0f) }
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        val largura = constraints.maxWidth.toFloat()
        val extra = with(LocalDensity.current) { (48.dp + 32.dp).toPx() }
        if (fracao.value > 0f) {
            Canvas(Modifier.fillMaxSize()) {
                with(PixelsCifrando) { desenhar(fracao.value * (largura + extra), null, agora, parado, inclinacao = 0f) }
            }
        }
        Text(titulo, style = estilo(Tipo.acao), color = Paleta.tinta, maxLines = 1)
    }
}

/**
 * O botao primario de copiar (o `CopyButton` do iOS). No toque, a capsula da um pulo curto, o icone
 * de copiar vira visto com um quique, o rotulo sobe e da lugar ao `feito`, e uma faixa clara atravessa
 * a capsula da esquerda para a direita. Depois de 2 segundos volta, pelo caminho inverso. Com o
 * movimento reduzido, so troca o icone e o texto.
 */
@Composable
fun BotaoDeCopiar(titulo: String, feito: String, modifier: Modifier = Modifier, acao: () -> Unit) {
    val haptico = LocalHapticFeedback.current
    val escopo = rememberCoroutineScope()
    val parado = movimentoReduzido()
    var copiado by remember { mutableStateOf(false) }
    var toques by remember { mutableIntStateOf(0) }
    var volta by remember { mutableStateOf<Job?>(null) }
    val pulo = remember { Animatable(1f) }
    val faixa = remember { Animatable(-1f) }
    val quique = remember { Animatable(1f) }
    val interacao = remember { MutableInteractionSource() }
    val apertado by interacao.collectIsPressedAsState()
    BoxWithConstraints(
        modifier.fillMaxWidth().height(Altura.primaria)
            .graphicsLayer { val e = if (parado) 1f else pulo.value * (if (apertado) 0.985f else 1f); scaleX = e; scaleY = e }
            .clip(CircleShape).background(if (apertado) Paleta.acentoApertado else Paleta.acento)
            .clickable(interacao, indication = null, role = Role.Button) {
                acao()
                toques++
                haptico.performHapticFeedback(HapticFeedbackType.Confirm)
                copiado = true
                volta?.cancel()
                volta = escopo.launch { delay(2000); copiado = false }
                if (!parado) {
                    escopo.launch {
                        pulo.animateTo(1f, keyframes { durationMillis = 540; 0.96f at 80; 1.025f at 260; 1f at 540 })
                    }
                    escopo.launch { faixa.snapTo(-1f); faixa.animateTo(1f, tween(650, easing = FastOutSlowInEasing)); faixa.snapTo(-1f) }
                    escopo.launch { quique.snapTo(0.6f); quique.animateTo(1f, spring(dampingRatio = 0.45f, stiffness = 500f)) }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        val largura = constraints.maxWidth.toFloat()
        if (!parado && faixa.value > -1f && faixa.value < 1f) {
            Canvas(Modifier.fillMaxSize()) {
                val banda = largura * 0.45f
                val x = (largura + banda) * (faixa.value + 1) / 2 - banda
                drawRect(Brush.horizontalGradient(listOf(Color.White.copy(alpha = 0f), Color.White.copy(alpha = 0.6f), Color.White.copy(alpha = 0f)),
                                                  startX = x, endX = x + banda), Offset(x, 0f), Size(banda, size.height))
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            Box(Modifier.size(20.dp).graphicsLayer { scaleX = quique.value; scaleY = quique.value }, contentAlignment = Alignment.Center) {
                Icone(if (copiado) Icones.visto else Icones.copiar, Paleta.sobreAcento, tamanho = 19.dp)
            }
            AnimatedContent(
                copiado,
                transitionSpec = {
                    if (parado) fadeIn(tween(150)) togetherWith fadeOut(tween(150))
                    else (slideInVertically(spring(dampingRatio = 0.8f, stiffness = 400f)) { it } + fadeIn()) togetherWith
                        (slideOutVertically(spring(dampingRatio = 0.8f, stiffness = 400f)) { -it } + fadeOut())
                },
                label = "copiado",
            ) { feitoAgora ->
                Text(if (feitoAgora) feito else titulo, style = estilo(Tipo.acao), color = Paleta.sobreAcento, maxLines = 1)
            }
        }
    }
}

/**
 * O selo das telas onde se digita um segredo (o `CipherEmblem` do iOS): o cadeado no meio de dois
 * aneis de pixels cinza que cifram, o mesmo desenho do preenchimento do deslizar. Cada pixel troca de
 * tom no seu compasso, e uma passada mais clara gira devagar pelos aneis. Pequeno e calmo de
 * proposito: diz "isto aqui esta cifrado" sem chamar mais atencao que o campo.
 */
@Composable
fun EmblemaCifrado(tamanho: androidx.compose.ui.unit.Dp = 88.dp, icone: androidx.compose.ui.graphics.vector.ImageVector = Icones.cadeadoCheio,
                   cor: Color = Paleta.tinta, modifier: Modifier = Modifier) {
    val parado = movimentoReduzido()
    val agora = relogioQueAnda(!parado)
    Box(modifier.size(tamanho), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val centro = center
            val passada = ((agora / 2.6) % 1.0) * 2 * Math.PI
            val celula = 4.5.dp.toPx()
            listOf(40 to 5.dp.toPx(), 30 to 14.dp.toPx()).forEachIndexed { anel, (quantos, recuo) ->
                val raio = size.minDimension / 2 - recuo
                for (i in 0 until quantos) {
                    val angulo = i.toDouble() / quantos * 2 * Math.PI - Math.PI / 2
                    val fase = PixelsCifrando.ruido(i, anel, 0x51ED)
                    val batida = agora * 5 * (0.6 + 0.8 * fase) + fase * 8
                    val degrau = floor(batida)
                    val t = batida - degrau
                    val mistura = t * t * (3 - 2 * t)
                    val a = PixelsCifrando.ruido(i, anel, degrau.toLong())
                    val b = PixelsCifrando.ruido(i, anel, degrau.toLong() + 1)
                    val bit = a + (b - a) * mistura
                    var distancia = kotlin.math.abs(angulo + Math.PI / 2 - passada)
                    distancia = minOf(distancia, 2 * Math.PI - distancia)
                    val brilho = exp(-(distancia / 0.55) * (distancia / 0.55))
                    val tom = 0.2 + 0.28 * bit + 0.38 * brilho * (if (anel == 0) 1.0 else 0.7)
                    val x = centro.x + (raio * kotlin.math.cos(angulo)).toFloat()
                    val y = centro.y + (raio * kotlin.math.sin(angulo)).toFloat()
                    drawRoundRect(PixelsCifrando.cinza(tom), Offset(x - celula / 2, y - celula / 2), Size(celula, celula), CornerRadius(1.2.dp.toPx()))
                }
            }
        }
        Box(Modifier.size(tamanho * 0.5f).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(icone, cor, tamanho = tamanho * 0.2f)
        }
    }
}

/** A tela de espera com o selo (o `CipherWorking` do iOS): o cofre abrindo depois do PIN, no meio da tela inteira. */
@Composable
fun TrabalhandoCifrado(titulo: String) {
    androidx.compose.foundation.layout.Column(
        Modifier.fillMaxSize().background(Paleta.vazio),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.md, Alignment.CenterVertically),
    ) {
        EmblemaCifrado()
        Text(titulo, style = estilo(Tipo.cabecalho), color = Paleta.tinta)
    }
}

/** O sorteio em pixels (o `DrawPixels` do iOS): quatro por quatro quadradinhos cinza trocando de tom, no lugar do dado. */
@Composable
fun PixelsDoSorteio(modifier: Modifier = Modifier) {
    val parado = movimentoReduzido()
    val agora = relogioQueAnda(!parado)
    Canvas(modifier) {
        val celulas = 4
        val passo = size.width / celulas
        val lado = passo * 0.74f
        for (linha in 0 until celulas) for (coluna in 0 until celulas) {
            val fase = PixelsCifrando.ruido(coluna, linha, 0x51A)
            val batida = agora * (1.4 + 1.8 * fase) + fase * 8
            val degrau = floor(batida)
            val t = batida - degrau
            val mistura = t * t * (3 - 2 * t)
            val a = PixelsCifrando.ruido(coluna, linha, degrau.toLong())
            val b = PixelsCifrando.ruido(coluna, linha, degrau.toLong() + 1)
            val tom = 0.22 + 0.62 * (a + (b - a) * mistura)
            drawRoundRect(PixelsCifrando.cinza(tom), Offset(coluna * passo + (passo - lado) / 2, linha * passo + (passo - lado) / 2), Size(lado, lado),
                          CornerRadius(lado * 0.22f))
        }
    }
}
