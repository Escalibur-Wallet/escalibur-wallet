package app.escalibur.wallet.ui.abertura

import android.graphics.BitmapFactory
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.view.Surface
import android.view.TextureView
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.comp.BotaoDeCanto
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.Logos
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.SeloDaCarteira
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.legal.DocumentoLegal
import app.escalibur.wallet.ui.legal.FolhaLegal
import app.escalibur.wallet.ui.pin.EntradaDoPin
import app.escalibur.wallet.ui.pin.TelaDoPin
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.security.MessageDigest
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.pow
import kotlin.math.sin

/** Boas-vindas, o tour e o primeiro PIN. O PIN vem antes de a frase existir; o tour, antes do PIN. */
@Composable
fun FluxoDeAbertura(aparelhoComBloqueio: Boolean) {
    var passo by remember { mutableIntStateOf(0) } // 0 boas-vindas, 1 tour, 2 escolher, 3 repetir
    var paginaDoTour by remember { mutableIntStateOf(0) }
    val entrada = remember { EntradaDoPin(setOf(6)) }
    var primeiro by remember { mutableStateOf<ByteArray?>(null) }
    var trabalhando by remember { mutableStateOf(false) }
    var documento by remember { mutableStateOf<DocumentoLegal?>(null) }
    val escopo = rememberCoroutineScope()

    BackHandler(enabled = passo > 0 && !trabalhando) {
        when (passo) {
            3 -> { primeiro?.fill(0); primeiro = null; entrada.limpar(); passo = 2 }
            2 -> { entrada.limpar(); paginaDoTour = 1; passo = 1 }
            else -> passo = 0
        }
    }

    AnimatedContent(passo.coerceAtMost(2), transitionSpec = { fadeIn(tween(150)) togetherWith fadeOut(tween(150)) }, label = "abertura") { tela ->
        when (tela) {
            0 -> BoasVindas(aparelhoComBloqueio, aoComecar = { paginaDoTour = 0; passo = 1 }, aoAbrirDocumento = { documento = it })
            1 -> Tour(paginaDoTour) { passo = 2 }
            else -> {
                val quatro = entrada.tamanho == 4
                val textoDeSeis = t("Seis dígitos para destravar o app e confirmar envios quando a biometria falhar. Não use o PIN da tela do celular: quem rouba o celular geralmente já viu esse código.")
                val textoDeQuatro = t("Quatro dígitos para destravar o app e confirmar envios quando a biometria falhar. São mais fáceis de adivinhar que seis. Não use o PIN da tela do celular: quem rouba o celular geralmente já viu esse código.")
                Box {
                    TelaDoPin(
                        titulo = if (passo == 2) t("Escolha um PIN") else t("Repita o PIN"),
                        subtitulo = if (passo == 2) (if (quatro) textoDeQuatro else textoDeSeis)
                        else (if (quatro) t("Os mesmos quatro dígitos.") else t("Os mesmos seis dígitos.")),
                        reservaDoSubtitulo = textoDeQuatro,
                        entrada = entrada,
                        trabalhando = trabalhando,
                        aoCompletar = {
                            if (passo == 2) {
                                primeiro = entrada.tirar()
                                passo = 3
                            } else {
                                val segundo = entrada.tirar()
                                val pin = primeiro
                                primeiro = null
                                val iguais = pin != null && MessageDigest.isEqual(pin, segundo)
                                segundo.fill(0)
                                if (!iguais || pin == null) {
                                    pin?.fill(0)
                                    entrada.falhar(t("Os dois não conferem. Escolha de novo."))
                                    passo = 2
                                } else {
                                    trabalhando = true
                                    escopo.launch {
                                        try {
                                            App.aplicar(Api.comSegredo("sessao.cadastrarPIN", JSONObject(), pin))
                                        } catch (falha: FalhaDoNucleo) {
                                            entrada.falhar(t("Não foi possível guardar o PIN neste celular."))
                                            passo = 2
                                        } finally {
                                            trabalhando = false
                                        }
                                    }
                                }
                            }
                        },
                    ) {
                        BotaoTerciario(if (quatro) t("Usar PIN de 6 dígitos") else t("Usar PIN de 4 dígitos"),
                                       modifier = Modifier.alpha(if (passo == 2) 1f else 0f)) {
                            if (passo == 2) entrada.escolher(if (quatro) 6 else 4)
                        }
                        Text(
                            t("O PIN não recupera a carteira. Se você esquecer o PIN, a senha da carteira traz tudo de volta."),
                            style = estilo(Tipo.nota), color = Paleta.tintaApagada, textAlign = TextAlign.Center,
                            modifier = Modifier.padding(horizontal = Espaco.xl),
                        )
                    }
                    BotaoDeCanto(Icones.voltar, t("Voltar"), Modifier.statusBarsPadding().padding(start = Espaco.xs), ligado = !trabalhando) {
                        if (passo == 3) { primeiro?.fill(0); primeiro = null; entrada.limpar(); passo = 2 } else { entrada.limpar(); paginaDoTour = 1; passo = 1 }
                    }
                }
            }
        }
    }
    documento?.let { FolhaLegal(it) { documento = null } }
}

@Composable
private fun BoasVindas(aparelhoComBloqueio: Boolean, aoComecar: () -> Unit, aoAbrirDocumento: (DocumentoLegal) -> Unit) {
    Column(Modifier.fillMaxSize().background(Paleta.vazio).navigationBarsPadding().padding(bottom = Espaco.lg)) {
        Box(Modifier.fillMaxWidth().weight(1f).heightIn(min = 220.dp)) {
            HeroiDaAbertura(
                Modifier.fillMaxSize()
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(
                            Brush.verticalGradient(
                                0f to Color.Black, 0.62f to Color.Black, 0.84f to Color.Black.copy(alpha = 0.45f), 1f to Color.Transparent,
                            ),
                            blendMode = BlendMode.DstIn,
                        )
                    }
            )
        }
        Column(Modifier.padding(horizontal = Espaco.margem), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(t("Só você pode"), style = estilo(Tipo.heroi), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.lg))
            Text(
                t("As chaves ficam criptografadas só neste celular. Se você perder a senha da carteira, a Escalibur não tem como ajudar a recuperá-la."),
                style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm),
            )
            if (!aparelhoComBloqueio) {
                Faixa(
                    TipoDeFaixa.falha, t("Este celular não tem bloqueio de tela"),
                    mensagem = t("Configure um PIN, padrão ou senha na tela de bloqueio do celular. Sem ele, o Android não protege as chaves da carteira."),
                    modifier = Modifier.padding(top = Espaco.md),
                )
            }
            BotaoPrimario(t("Começar"), Modifier.padding(top = Espaco.lg), ligado = aparelhoComBloqueio, acao = aoComecar)
            AceiteDosDocumentos(aoAbrirDocumento)
        }
    }
}

/** "Ao continuar, voce aceita os Termos de uso e a Politica de privacidade", com os dois links. */
@Composable
private fun AceiteDosDocumentos(aoAbrir: (DocumentoLegal) -> Unit) {
    val termos = t("Termos de uso")
    val privacidade = t("Política de privacidade")
    val modelo = t("Ao continuar, você aceita os [Termos de uso](escalibur-doc:termos)\ne a [Política de privacidade](escalibur-doc:privacidade).")
    val texto = androidx.compose.ui.text.buildAnnotatedString {
        val link = Regex("\\[([^\\]]+)]\\(escalibur-doc:([a-z]+)\\)")
        var posicao = 0
        for (achado in link.findAll(modelo)) {
            append(modelo.substring(posicao, achado.range.first))
            val documento = if (achado.groupValues[2] == "termos") DocumentoLegal.termos else DocumentoLegal.privacidade
            pushLink(androidx.compose.ui.text.LinkAnnotation.Clickable(documento.name, androidx.compose.ui.text.TextLinkStyles(
                androidx.compose.ui.text.SpanStyle(color = Paleta.tintaSuave, textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline)
            )) { aoAbrir(documento) })
            append(achado.groupValues[1])
            pop()
            posicao = achado.range.last + 1
        }
        append(modelo.substring(posicao))
        if (posicao == 0 && termos.isEmpty() && privacidade.isEmpty()) append("")
    }
    Text(texto, style = estilo(Tipo.nota), color = Paleta.tintaApagada, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm))
}

/**
 * A abertura: a espada cravada no pico, com as moedas vindo dos dois lados, em loop e sem som. O
 * primeiro quadro fica embaixo do video, para nao piscar preto enquanto ele carrega.
 */
@Composable
fun HeroiDaAbertura(modifier: Modifier = Modifier) {
    val contexto = LocalContext.current
    val quadro = remember {
        runCatching { contexto.assets.open("abertura/abertura-espada.jpg").use { BitmapFactory.decodeStream(it)?.asImageBitmap() } }.getOrNull()
    }
    val semMovimento = remember {
        android.provider.Settings.Global.getFloat(contexto.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    Box(modifier.clip(androidx.compose.ui.graphics.RectangleShape)) {
        if (quadro != null) Image(quadro, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        if (!semMovimento) VideoEmLoop("abertura/abertura-espada.mp4", Modifier.fillMaxSize())
    }
}

/** Um video mudo em loop, preenchendo o espaco e cortando o que sobra, centrado. */
@Composable
private fun VideoEmLoop(arquivo: String, modifier: Modifier) {
    val contexto = LocalContext.current
    val jogador = remember { MediaPlayer() }
    DisposableEffect(Unit) {
        onDispose {
            runCatching { jogador.stop() }
            jogador.release()
        }
    }
    BoxWithConstraints(modifier) {
        AndroidView(
            factory = { ctx ->
                TextureView(ctx).apply {
                    isOpaque = false
                    surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                        override fun onSurfaceTextureAvailable(textura: SurfaceTexture, largura: Int, altura: Int) {
                            runCatching {
                                contexto.assets.openFd(arquivo).use { descritor ->
                                    jogador.setDataSource(descritor.fileDescriptor, descritor.startOffset, descritor.length)
                                }
                                jogador.setSurface(Surface(textura))
                                jogador.isLooping = true
                                jogador.setVolume(0f, 0f)
                                jogador.setOnVideoSizeChangedListener { _, w, h -> ajustar(this@apply, w, h) }
                                jogador.setOnPreparedListener { it.start() }
                                jogador.prepareAsync()
                            }
                        }
                        override fun onSurfaceTextureSizeChanged(textura: SurfaceTexture, largura: Int, altura: Int) {}
                        override fun onSurfaceTextureDestroyed(textura: SurfaceTexture) = true
                        override fun onSurfaceTextureUpdated(textura: SurfaceTexture) {}
                    }
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
    }
}

/** Preenche a vista com o video sem distorcer: escala para cobrir e corta o que sobra. */
private fun ajustar(vista: TextureView, larguraDoVideo: Int, alturaDoVideo: Int) {
    if (larguraDoVideo == 0 || alturaDoVideo == 0 || vista.width == 0 || vista.height == 0) return
    val proporcaoDaVista = vista.width.toFloat() / vista.height
    val proporcaoDoVideo = larguraDoVideo.toFloat() / alturaDoVideo
    val matriz = android.graphics.Matrix()
    if (proporcaoDoVideo > proporcaoDaVista) {
        matriz.setScale(proporcaoDoVideo / proporcaoDaVista, 1f, vista.width / 2f, vista.height / 2f)
    } else {
        matriz.setScale(1f, proporcaoDaVista / proporcaoDoVideo, vista.width / 2f, vista.height / 2f)
    }
    vista.setTransform(matriz)
}

/** O que a Escalibur e, em dois passos com uma cena cada. */
@Composable
private fun Tour(paginaInicial: Int, aoTerminar: () -> Unit) {
    val paginas = 2
    val estado = rememberPagerState(initialPage = paginaInicial) { paginas }
    val escopo = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = Espaco.margem), horizontalArrangement = Arrangement.End) {
            BotaoTerciario(t("Pular"), Modifier.alpha(if (estado.currentPage < paginas - 1) 1f else 0f)) {
                if (estado.currentPage < paginas - 1) aoTerminar()
            }
        }
        HorizontalPager(estado, Modifier.weight(1f)) { pagina ->
            if (pagina == 0) {
                PaginaDoTour(
                    t("Uma chave para todas as suas moedas"),
                    t("Bitcoin, Ethereum, Solana e as maiores moedas do mundo, com a chave criada e guardada neste celular. Envie, receba e troque entre redes, com a taxa à vista antes de assinar."),
                ) { CenaDasRedes(ativa = estado.currentPage == 0) }
            } else {
                PaginaDoTour(
                    t("Você no controle"),
                    t("Antes de cada envio, você vê o que sai e para onde, e confirma com a sua biometria ou PIN. O código é publicado para auditoria: qualquer pessoa pode conferir."),
                ) { CenaDaAssinatura(ativa = estado.currentPage == 1) }
            }
        }
        MarcasDePagina(paginas, estado.currentPage, Modifier.align(Alignment.CenterHorizontally).padding(vertical = Espaco.md))
        BotaoPrimario(t("Continuar"), Modifier.padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs)) {
            if (estado.currentPage < paginas - 1) escopo.launch { estado.animateScrollToPage(estado.currentPage + 1) } else aoTerminar()
        }
    }
}

@Composable
private fun PaginaDoTour(titulo: String, texto: String, cena: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().padding(horizontal = Espaco.margem), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { cena() }
        Column(
            Modifier.fillMaxWidth().heightIn(min = 196.dp).padding(top = Espaco.lg),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.sm),
        ) {
            Text(titulo, style = estilo(Tipo.heroi), color = Paleta.tinta, textAlign = TextAlign.Center)
            Text(texto, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun MarcasDePagina(total: Int, atual: Int, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(total) { indice ->
            val largura by animateDpAsState(if (indice == atual) 22.dp else 8.dp, spring(dampingRatio = 0.85f), label = "marca")
            Box(Modifier.width(largura).height(8.dp).clip(CircleShape).background(if (indice == atual) Paleta.acento else Paleta.bordaForte))
        }
    }
}

/** O selo da carteira no centro e as moedas em duas orbitas, em sentidos contrarios. */
@Composable
private fun CenaDasRedes(ativa: Boolean) {
    val dentro = listOf("bitcoin", "ethereum", "solana", "tether", "ripple", "usd-coin")
    val fora = listOf("binancecoin", "the-open-network", "tron", "cardano", "polkadot", "avalanche-2", "dogecoin", "sui", "stellar", "near")
    var mostradas by remember { mutableIntStateOf(0) }
    LaunchedEffect(ativa) {
        if (!ativa) return@LaunchedEffect
        mostradas = 0
        delay(200)
        repeat(dentro.size + fora.size) {
            mostradas++
            delay(70)
        }
    }
    val giro = rememberInfiniteTransition(label = "orbitas")
    val tempo by giro.animateFloat(0f, (2 * PI * 25).toFloat(), infiniteRepeatable(tween(157_000, easing = LinearEasing)), label = "tempo")
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val lado = minOf(maxWidth, maxHeight)
        val raioDentro = lado * 0.25f
        val raioFora = lado * 0.42f
        Canvas(Modifier.fillMaxSize()) {
            val centro = Offset(size.width / 2, size.height / 2)
            drawCircle(Paleta.bordaForte, raioDentro.toPx(), centro, style = Stroke(1.dp.toPx()))
            drawCircle(Paleta.borda, raioFora.toPx(), centro, style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 6.dp.toPx()))))
        }
        fun posicao(angulo: Double, raio: androidx.compose.ui.unit.Dp, tamanho: androidx.compose.ui.unit.Dp) =
            Modifier.offset(maxWidth / 2 + raio * cos(angulo).toFloat() - tamanho / 2, maxHeight / 2 + raio * sin(angulo).toFloat() - tamanho / 2)
        dentro.forEachIndexed { indice, id ->
            val angulo = indice.toDouble() / dentro.size * 2 * PI + tempo * 0.16
            MoedaQueEntra(id, lado * 0.14f, mostradas > indice, posicao(angulo, raioDentro, lado * 0.14f))
        }
        fora.forEachIndexed { indice, id ->
            val angulo = indice.toDouble() / fora.size * 2 * PI + 0.3 - tempo * 0.1
            MoedaQueEntra(id, lado * 0.105f, mostradas > dentro.size + indice, posicao(angulo, raioFora, lado * 0.105f))
        }
        SeloDaCarteira(lado * 0.2f, modifier = Modifier.align(Alignment.Center).scale(if (mostradas > 0) 1f else 0.8f))
    }
}

@Composable
private fun MoedaQueEntra(id: String, tamanho: androidx.compose.ui.unit.Dp, visivel: Boolean, modifier: Modifier) {
    val escala = remember { Animatable(0.2f) }
    LaunchedEffect(visivel) { escala.animateTo(if (visivel) 1f else 0.2f, spring(dampingRatio = 0.62f, stiffness = 220f)) }
    LogoDaMoeda(id, tamanho = tamanho, modifier = modifier.graphicsLayer { scaleX = escala.value; scaleY = escala.value; alpha = if (visivel) 1f else 0f })
}

/**
 * A moeda de Bitcoin gira devagar, esperando; a biometria procura e confirma; a moeda da um giro
 * rapido e para de frente.
 */
@Composable
private fun CenaDaAssinatura(ativa: Boolean) {
    var confirmado by remember { mutableStateOf(false) }
    var procurando by remember { mutableStateOf(false) }
    val angulo = remember { Animatable(0f) }
    LaunchedEffect(ativa) {
        if (!ativa) return@LaunchedEffect
        confirmado = false
        procurando = false
        angulo.snapTo(0f)
        val giroLento = launch {
            while (true) angulo.animateTo(angulo.value + (2 * PI).toFloat(), tween(3400, easing = LinearEasing))
        }
        delay(1300)
        procurando = true
        delay(1500)
        giroLento.cancel()
        confirmado = true
        val alvo = ((floor(angulo.value / (2 * PI)) + 2) * 2 * PI).toFloat()
        angulo.animateTo(alvo, tween(1100, easing = FastOutSlowInEasing))
    }
    Column(Modifier.fillMaxSize().padding(horizontal = Espaco.lg), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        MoedaQueGira(angulo.value, Modifier.size(200.dp))
        Spacer(Modifier.height(Espaco.lg))
        Column(Modifier.alpha(if (procurando || confirmado) 1f else 0f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            val volta = rememberInfiniteTransition(label = "procura")
            val rotacao by volta.animateFloat(0f, 360f, infiniteRepeatable(tween(900, easing = LinearEasing)), label = "rotacao")
            Box(Modifier.size(68.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    drawCircle(if (confirmado) Paleta.acento else Paleta.bordaForte, style = Stroke(2.dp.toPx()))
                    if (!confirmado) {
                        drawArc(Paleta.acento, rotacao, 79f, false, style = Stroke(2.5.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round))
                    }
                }
                Icone(if (confirmado) Icones.visto else Icones.digital, Paleta.tinta, tamanho = 30.dp)
            }
            Text(
                if (confirmado) t("Assinado neste celular") else t("Confirme com a biometria"),
                style = estilo(Tipo.nota), color = if (confirmado) Paleta.tinta else Paleta.tintaSuave,
            )
        }
    }
}

/** A moeda de Bitcoin de frente ou de lado: a face encolhe com o cosseno do giro e a borda aparece. */
@Composable
private fun MoedaQueGira(angulo: Float, modifier: Modifier) {
    val contexto = LocalContext.current
    val logo = remember { Logos.imagem(contexto, "logo-bitcoin") }
    Canvas(modifier) {
        val raio = size.minDimension * 0.42f
        val centro = Offset(size.width / 2, size.height / 2 - 8.dp.toPx())
        val largura = cos(angulo.toDouble()).toFloat()
        val espessura = raio * 0.16f * abs(sin(angulo.toDouble())).toFloat()
        // A sombra no chao, que encolhe quando a moeda esta de lado.
        drawOval(Color.Black.copy(alpha = 0.45f), Offset(centro.x - raio * (0.35f + 0.5f * abs(largura)), centro.y + raio * 1.12f), Size(raio * 2 * (0.35f + 0.5f * abs(largura)), raio * 0.16f))
        // A borda da moeda.
        if (espessura > 0.5f) {
            drawOval(Color(0xFFB86E0C), Offset(centro.x - raio * abs(largura) - espessura / 2, centro.y - raio), Size(raio * 2 * abs(largura) + espessura, raio * 2))
        }
        if (logo != null && abs(largura) > 0.02f) {
            scale(scaleX = abs(largura), scaleY = 1f, pivot = centro) {
                drawImage(
                    logo, srcOffset = IntOffset.Zero, srcSize = IntSize(logo.width, logo.height),
                    dstOffset = IntOffset((centro.x - raio).toInt(), (centro.y - raio).toInt()), dstSize = IntSize((raio * 2).toInt(), (raio * 2).toInt()),
                )
                if (largura < 0) drawCircle(Color(0xFFE38A12).copy(alpha = 0.55f), raio, centro)
            }
        }
    }
}

/** Oferecer a biometria, depois do PIN e antes da primeira carteira. */
@Composable
fun OfertaDeBiometria(aoTerminar: () -> Unit) {
    var pedindoPin by remember { mutableStateOf(false) }
    val entrada = remember { EntradaDoPin(App.estado.pinDigitos) }
    var trabalhando by remember { mutableStateOf(false) }
    val escopo = rememberCoroutineScope()
    if (pedindoPin) {
        BackHandler { entrada.limpar(); pedindoPin = false }
        TelaDoPin(
            titulo = t("Confirme com o PIN"), subtitulo = t("Para ligar a biometria nesta carteira."), entrada = entrada, trabalhando = trabalhando,
            aoCompletar = {
                val pin = entrada.tirar()
                trabalhando = true
                escopo.launch {
                    try {
                        App.aplicar(Api.comSegredo("sessao.ligarBiometria", JSONObject().put("motivo", t("Confirme a biometria para ligar")), pin))
                        aoTerminar()
                    } catch (falha: FalhaDoNucleo) {
                        entrada.falhar(
                            when (falha.codigo) {
                                "cofre.pinErrado" -> t("PIN incorreto.")
                                "cofre.espera" -> t("Tentativas demais. Tente de novo em %@.", app.escalibur.wallet.ui.Formato.duracao(falha.segundos))
                                "cofre.cancelled" -> t("A biometria não confirmou. Ela continua desligada; você pode ligar depois nos Ajustes.")
                                else -> t("Não foi possível ligar a biometria agora.")
                            }
                        )
                    } finally {
                        trabalhando = false
                    }
                }
            },
        ) {
            BotaoTerciario(t("Voltar")) { entrada.limpar(); pedindoPin = false }
        }
    } else {
        Column(
            Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.weight(1f))
            Box(Modifier.size(96.dp).clip(CircleShape).background(Paleta.trilho), contentAlignment = Alignment.Center) {
                Icone(Icones.digital, Paleta.tinta, tamanho = 46.dp)
            }
            Text(t("Destravar com a biometria"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.lg))
            Text(
                t("Destrava o app e confirma envios em 1 segundo. Se a biometria falhar, o PIN vale."),
                style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm),
            )
            Spacer(Modifier.weight(1f))
            BotaoPrimario(t("Usar a biometria")) { pedindoPin = true }
            BotaoSecundario(t("Agora não"), Modifier.padding(top = Espaco.sm), acao = aoTerminar)
        }
    }
}
