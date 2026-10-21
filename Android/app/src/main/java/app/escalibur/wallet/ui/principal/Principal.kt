package app.escalibur.wallet.ui.principal

import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import app.escalibur.wallet.ui.comp.seguraToques
import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.animation.core.tween
import androidx.compose.runtime.key
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.Velocity
import app.escalibur.wallet.ui.tema.Raio
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import app.escalibur.wallet.ui.comp.LocalEspacoDaBarra
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import app.escalibur.wallet.ui.comp.ComVidro
import app.escalibur.wallet.ui.comp.Vidros
import app.escalibur.wallet.ui.comp.vidro
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Letra
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt
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
 * A navegacao do iOS. Cada aba tem a sua pilha (empurrar abre dentro da aba, com a barra de abas
 * por cima, e trocar de aba guarda onde cada uma estava). Por cima de tudo, inclusive da barra,
 * ficam os fluxos de tela cheia (o `fullScreenCover`: enviar, revisar uma troca) e as folhas (o
 * `sheet`: receber, salvar um endereco). Voltar fecha o de cima.
 */
object Navegacao {
    var aba by mutableStateOf(Aba.carteira)
    private val pilhas = Aba.entries.associateWith { mutableStateListOf<Entrada>() }

    /** As telas empurradas na aba aberta. */
    val pilha: SnapshotStateList<Entrada> get() = pilhas.getValue(aba)

    fun pilhaDa(aba: Aba): SnapshotStateList<Entrada> = pilhas.getValue(aba)

    /** Os fluxos de tela cheia e as folhas, por cima de tudo. */
    val sobre = mutableStateListOf<Entrada>()

    enum class Modo { empurrada, coberta, folha }

    /**
     * Uma tela aberta. `posicao` vai de 1 (fora: a direita, se empurrada; embaixo, se coberta ou
     * folha) a 0 (no lugar).
     */
    class Entrada(val modo: Modo, val tela: @Composable () -> Unit) {
        val posicao = Animatable(1f)
        var saindo by mutableStateOf(false)
    }

    /** Empurra na aba aberta; dentro de um fluxo de tela cheia ou de uma folha, empurra nele. */
    fun abrir(tela: @Composable () -> Unit) {
        (if (sobre.isNotEmpty()) sobre else pilha).add(Entrada(Modo.empurrada, tela))
    }

    /** O fluxo de tela cheia: sobe de baixo e cobre a barra de abas. */
    fun cobrir(tela: @Composable () -> Unit) { sobre.add(Entrada(Modo.coberta, tela)) }

    /** A folha: sobe de baixo, e o que fica atras recua. */
    fun folha(tela: @Composable () -> Unit) { sobre.add(Entrada(Modo.folha, tela)) }

    /** A de cima, entre todas: a que o voltar fecha. */
    val doTopo: Entrada? get() = sobre.lastOrNull { !it.saindo } ?: pilha.lastOrNull { !it.saindo }

    /** Fecha a de cima: ela sai deslizando e so entao deixa a pilha. */
    fun fechar() { doTopo?.saindo = true }

    /** Volta a aba aberta para o comeco: so a de cima sai deslizando, como no iOS. */
    fun voltarAoComeco(aba: Aba) {
        val lista = pilhaDa(aba)
        val topo = lista.lastOrNull() ?: return
        lista.retainAll { it === topo }
        topo.saindo = true
    }

    fun fecharTudo() {
        sobre.clear()
        pilha.clear()
    }

    fun remover(entrada: Entrada) {
        sobre.remove(entrada)
        pilhas.values.forEach { it.remove(entrada) }
    }

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
            if (tela.startsWith("enviar-")) Navegacao.cobrir { app.escalibur.wallet.ui.enviar.FluxoDeEnviar("demo:" + tela.removePrefix("enviar-")) }
            when (tela) {
                // Como no importar: o fechar no alto, abaixo da barra de status.
                "checagem" -> Navegacao.cobrir {
                    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
                        app.escalibur.wallet.ui.comp.CabecalhoDeFolha("", { Navegacao.fechar() })
                        app.escalibur.wallet.ui.novacarteira.VerificacaoDoAparelho(t("Deslize para digitar as palavras"), criando = false) { Navegacao.fechar() }
                    }
                }
                "receber" -> Navegacao.folha { app.escalibur.wallet.ui.receber.FluxoDeReceber() }
                "mercado" -> Navegacao.aba = Aba.mercado
                "trocar" -> Navegacao.aba = Aba.trocar
                "atividade" -> Navegacao.aba = Aba.atividade
                "ajustes" -> Navegacao.aba = Aba.ajustes
            }
        }
    }
    app.escalibur.wallet.ui.avisos.VigiasDaSessao()
    app.escalibur.wallet.ui.trocar.PerguntaDasVencidas()
    // A barra flutua sobre o conteudo, como no iOS 26: com navegacao por gestos, no lugar da barra
    // do iPhone; com os tres botoes do Android, logo acima deles.
    val navegacao = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val folga = if (navegacao <= 28.dp) 20.dp else navegacao + 6.dp
    val abas = rememberSaveableStateHolder()
    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black)) {
        val largura = constraints.maxWidth.toFloat()
        val altura = constraints.maxHeight.toFloat()
        // Antes das telas: o voltar de dentro de uma tela (um passo de um fluxo) vem depois e tem a vez.
        VoltarDoTopo()
        Box(Modifier.fillMaxSize().recuo(Navegacao.sobre.firstOrNull(), largura)) {
            ComVidro(Modifier.fillMaxSize(), frente = { BarraDeAbas(folga, Modifier.align(Alignment.BottomCenter)) }) {
                Box(Modifier.fillMaxSize().background(Paleta.vazio)) {
                    CompositionLocalProvider(LocalEspacoDaBarra provides folga + AlturaDaBarra + Espaco.md) {
                        // Cada aba guarda onde estava (a rolagem, as telas abertas), como as abas do iOS.
                        abas.SaveableStateProvider(Navegacao.aba) {
                            val pilha = Navegacao.pilha
                            Box(Modifier.fillMaxSize().recuo(pilha.firstOrNull(), largura)) {
                                when (Navegacao.aba) {
                                    Aba.carteira -> TelaDaCarteira()
                                    Aba.mercado -> app.escalibur.wallet.ui.mercado.TelaDoMercado()
                                    Aba.trocar -> app.escalibur.wallet.ui.trocar.TelaDeTrocar()
                                    Aba.atividade -> app.escalibur.wallet.ui.atividade.TelaDeAtividade()
                                    Aba.ajustes -> app.escalibur.wallet.ui.ajustes.TelaDeAjustes()
                                }
                            }
                            Camadas(pilha, largura, altura)
                            // A faixa da barra de status leva o fundo da tela, chapado: o conteudo rolado
                            // some por baixo do relogio e da bateria, como no iOS.
                            Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(Paleta.vazio))
                        }
                    }
                }
            }
        }
        Camadas(Navegacao.sobre, largura, altura)
    }
}

/**
 * Cada tela aberta, com o movimento do iOS: a empurrada entra da direita por cima da anterior, que
 * recua um terco e escurece; a de tela cheia sobe de baixo; a folha sobe de baixo, com os cantos de
 * cima redondos, e o que fica atras encolhe um pouco e escurece. Fechar faz o caminho inverso.
 */
@Composable
private fun Camadas(entradas: SnapshotStateList<Navegacao.Entrada>, largura: Float, altura: Float) {
    entradas.forEachIndexed { indice, entrada ->
        key(entrada) {
            LaunchedEffect(entrada.saindo) {
                if (entrada.saindo) {
                    entrada.posicao.animateTo(1f, tween(if (entrada.modo == Navegacao.Modo.empurrada) 320 else 340, easing = CurvaDoIos))
                    Navegacao.remover(entrada)
                } else if (entrada.posicao.value > 0f) {
                    entrada.posicao.animateTo(0f, tween(if (entrada.modo == Navegacao.Modo.empurrada) 420 else 460, easing = CurvaDoIos))
                }
            }
            val deCima = entradas.getOrNull(indice + 1)
            when (entrada.modo) {
                Navegacao.Modo.folha -> Folha(entrada, deCima, largura, altura)
                else -> Box(
                    Modifier.fillMaxSize()
                        .graphicsLayer {
                            if (entrada.modo == Navegacao.Modo.empurrada) translationX = largura * entrada.posicao.value
                            else translationY = altura * entrada.posicao.value
                        }
                        .recuo(deCima, largura)
                        .background(Paleta.vazio)
                        .seguraToques(),
                ) { entrada.tela() }
            }
        }
    }
}

/**
 * A folha do iOS: comeca logo abaixo da barra de status, com os cantos de cima redondos. Arrastada
 * para baixo (pelo conteudo ja no topo, ou por onde nao rola), desce junto com o dedo; soltou depois
 * de um quarto, ou num gesto rapido, fecha.
 */
@Composable
private fun Folha(entrada: Navegacao.Entrada, deCima: Navegacao.Entrada?, largura: Float, altura: Float) {
    val escopo = rememberCoroutineScope()
    val topo = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 10.dp
    val alturaDaFolha = altura - with(androidx.compose.ui.platform.LocalDensity.current) { topo.toPx() }
    fun soltar(velocidade: Float) {
        escopo.launch {
            if (entrada.posicao.value > 0.25f || velocidade > 1800f) entrada.saindo = true
            else entrada.posicao.animateTo(0f, spring(dampingRatio = 0.86f, stiffness = 420f))
        }
    }
    val arraste = remember(entrada) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                // Folha ja descida e o dedo subindo: primeiro a folha volta para o lugar.
                if (available.y < 0 && entrada.posicao.value > 0f && !entrada.saindo) {
                    val antes = entrada.posicao.value
                    val depois = (antes + available.y / alturaDaFolha).coerceAtLeast(0f)
                    escopo.launch { entrada.posicao.snapTo(depois) }
                    return Offset(0f, (depois - antes) * alturaDaFolha)
                }
                return Offset.Zero
            }

            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                // O conteudo no topo e o dedo descendo: a folha desce junto.
                if (available.y > 0 && source == NestedScrollSource.UserInput && !entrada.saindo) {
                    escopo.launch { entrada.posicao.snapTo((entrada.posicao.value + available.y / alturaDaFolha).coerceIn(0f, 1f)) }
                    return Offset(0f, available.y)
                }
                return Offset.Zero
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                if (entrada.posicao.value > 0f && !entrada.saindo) {
                    soltar(available.y)
                    return available
                }
                return Velocity.Zero
            }
        }
    }
    Box(
        Modifier.fillMaxSize()
            .padding(top = topo)
            .graphicsLayer { translationY = alturaDaFolha * entrada.posicao.value }
            .recuo(deCima, largura)
            .clip(RoundedCornerShape(topStart = Raio.folha, topEnd = Raio.folha))
            .background(Paleta.vazio)
            .nestedScroll(arraste)
            .draggable(
                rememberDraggableState { delta ->
                    if (!entrada.saindo) escopo.launch { entrada.posicao.snapTo((entrada.posicao.value + delta / alturaDaFolha).coerceIn(0f, 1f)) }
                },
                Orientation.Vertical,
                onDragStopped = { soltar(it) },
            )
            .seguraToques(),
    ) { entrada.tela() }
}

/**
 * Como uma tela fica quando outra abre por cima: recua e escurece (empurrada), ou encolhe e
 * escurece, com os cantos redondos (folha). Sob tela cheia, fica como esta.
 */
private fun Modifier.recuo(acima: Navegacao.Entrada?, largura: Float): Modifier =
    if (acima == null || acima.modo == Navegacao.Modo.coberta) this else this
        .graphicsLayer {
            val r = 1f - acima.posicao.value
            if (acima.modo == Navegacao.Modo.empurrada) {
                translationX = -largura * 0.3f * r
            } else {
                val escala = 1f - 0.075f * r
                scaleX = escala
                scaleY = escala
                shape = RoundedCornerShape((Raio.folha.value * 1.4f * r).dp)
                clip = r > 0f
            }
        }
        .drawWithContent {
            drawContent()
            val r = 1f - acima.posicao.value
            if (r > 0f) drawRect(Color.Black.copy(alpha = (if (acima.modo == Navegacao.Modo.empurrada) 0.22f else 0.38f) * r))
        }

/**
 * O voltar do Android para a tela do topo: o gesto da beirada leva a tela junto com o dedo, como o
 * arrastar da beirada no iPhone (a empurrada vai para a direita; a de tela cheia e a folha descem);
 * soltou antes do fim, ela volta para o lugar.
 */
@Composable
private fun VoltarDoTopo() {
    val topo = Navegacao.doTopo
    val escopo = rememberCoroutineScope()
    PredictiveBackHandler(enabled = topo != null) { gesto ->
        val entrada = Navegacao.doTopo ?: return@PredictiveBackHandler
        val alcance = if (entrada.modo == Navegacao.Modo.empurrada) 0.92f else 0.3f
        try {
            gesto.collect { evento -> entrada.posicao.snapTo(evento.progress * alcance) }
            entrada.saindo = true
        } catch (e: kotlin.coroutines.cancellation.CancellationException) {
            escopo.launch { entrada.posicao.animateTo(0f, spring(dampingRatio = 0.9f, stiffness = 500f)) }
            throw e
        }
    }
}

/** A curva do empurrar do iOS: sai rapido e assenta devagar. */
private val CurvaDoIos = androidx.compose.animation.core.CubicBezierEasing(0.2f, 0.9f, 0.25f, 1f)

/** A altura da barra de abas, sem a folga embaixo. */
val AlturaDaBarra = 62.dp

/**
 * A barra de abas do iOS 26: uma capsula de vidro flutuando sobre o conteudo, com a aba escolhida
 * marcada por um vidro mais claro que desliza ate ela. O dedo arrastado pela barra leva a marca
 * junto (ela cresce e vira uma gota de vidro); ao soltar, ela assenta na aba mais perto.
 */
@Composable
private fun BarraDeAbas(folga: Dp, modifier: Modifier = Modifier) {
    val toque = toqueDeSelecao()
    val abas: List<Triple<Aba, String, ImageVector>> = listOf(
        Triple(Aba.carteira, t("Carteira"), Icones.carteiraCheia),
        Triple(Aba.mercado, t("Mercado"), Icones.mercado),
        Triple(Aba.trocar, t("Trocar"), Icones.trocar),
        Triple(Aba.atividade, t("Atividade"), Icones.atividade),
        Triple(Aba.ajustes, t("Ajustes"), Icones.engrenagemCheia),
    )
    val escolhida = abas.indexOfFirst { it.first == Navegacao.aba }.coerceAtLeast(0)
    val escopo = rememberCoroutineScope()
    val posicao = remember { Animatable(escolhida.toFloat()) }
    val erguida = remember { Animatable(0f) }
    var arrastando by remember { mutableStateOf(false) }
    LaunchedEffect(escolhida) {
        if (!arrastando) posicao.animateTo(escolhida.toFloat(), spring(dampingRatio = 0.74f, stiffness = 380f))
    }
    BoxWithConstraints(
        modifier.padding(horizontal = 21.dp).padding(bottom = folga).fillMaxWidth().height(AlturaDaBarra)
            .shadow(22.dp, CircleShape, ambientColor = Color.Black, spotColor = Color.Black)
            .vidro(CircleShape, Vidros.barra)
            .pointerInput(abas.size) {
                val margem = 4.dp.toPx()
                val largura = (size.width - margem * 2) / abas.size
                awaitEachGesture {
                    val primeiro = awaitFirstDown()
                    val tocada = ((primeiro.position.x - margem) / largura).toInt().coerceIn(0, abas.lastIndex)
                    var moveu = false
                    arrastando = true
                    escopo.launch { erguida.animateTo(1f, spring(dampingRatio = 0.62f, stiffness = 520f)) }
                    while (true) {
                        val mudanca = awaitPointerEvent().changes.firstOrNull { it.id == primeiro.id } ?: break
                        if (!mudanca.pressed) break
                        if (!moveu && abs(mudanca.position.x - primeiro.position.x) > viewConfiguration.touchSlop) moveu = true
                        if (moveu) {
                            mudanca.consume()
                            val alvo = ((mudanca.position.x - margem) / largura - 0.5f).coerceIn(0f, abas.lastIndex.toFloat())
                            escopo.launch { posicao.animateTo(alvo, spring(dampingRatio = 0.9f, stiffness = 1400f)) }
                        }
                    }
                    val destino = if (moveu) posicao.value.roundToInt() else tocada
                    arrastando = false
                    if (abas[destino].first != Navegacao.aba) {
                        toque()
                        Navegacao.aba = abas[destino].first
                    } else if (!moveu) {
                        // A aba ja aberta, tocada de novo: volta ao comeco dela, como no iOS.
                        Navegacao.voltarAoComeco(Navegacao.aba)
                    }
                    escopo.launch { erguida.animateTo(0f, spring(dampingRatio = 0.7f, stiffness = 360f)) }
                    escopo.launch { posicao.animateTo(destino.toFloat(), spring(dampingRatio = 0.74f, stiffness = 380f)) }
                }
            },
    ) {
        val margem = 4.dp
        val largura = (maxWidth - margem * 2) / abas.size
        Box(
            Modifier.offset { IntOffset((margem + largura * posicao.value).roundToPx(), 0) }
                .padding(vertical = margem).width(largura).fillMaxHeight()
                .graphicsLayer {
                    // Erguida, a marca cresce; andando, estica no sentido do movimento.
                    val estica = (abs(posicao.velocity) * 0.035f).coerceAtMost(0.22f)
                    scaleX = 1f + 0.14f * erguida.value + estica
                    scaleY = 1f + 0.14f * erguida.value - estica * 0.35f
                }
                .vidro(CircleShape, if (erguida.value > 0.5f) Vidros.gota else Vidros.selecao),
        )
        Row(Modifier.fillMaxSize().padding(horizontal = margem)) {
            abas.forEachIndexed { indice, (aba, titulo, icone) ->
                val ativa = Navegacao.aba == aba
                val cor = if (ativa) Paleta.acento else Paleta.tinta
                Column(
                    Modifier.weight(1f).fillMaxHeight().semantics(mergeDescendants = true) {
                        role = Role.Tab
                        selected = ativa
                    },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Icone(icone, cor, tamanho = 26.dp)
                    Text(titulo, style = TextStyle(fontFamily = Letra.familia(FontWeight.Medium, 10f), fontWeight = FontWeight.Medium, fontSize = 10.sp,
                                                   letterSpacing = Letra.espacoNatural(10f).em),
                         color = cor, maxLines = 1, modifier = Modifier.padding(top = 3.dp))
                }
            }
        }
    }
}
