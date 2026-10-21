package app.escalibur.wallet.ui.novacarteira

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.PixelsCifrando
import app.escalibur.wallet.ui.comp.movimentoReduzido
import app.escalibur.wallet.ui.comp.relogio
import app.escalibur.wallet.ui.comp.suave
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.roundToInt
import kotlin.math.sin
import app.escalibur.wallet.ui.comp.DeslizeParaSeguir
import app.escalibur.wallet.ui.comp.Girando
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.KeyguardManager
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Debug
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.view.accessibility.AccessibilityManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.comp.Aceite
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.security.KeyStore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory

/** Uma verificacao real do aparelho, feita no proprio celular, sem rede. */
data class Checagem(val id: String, val titulo: String, val resultado: Resultado) {
    sealed class Resultado {
        object Passou : Resultado()
        /** Merece atencao, nao impede. */
        data class Cautela(val texto: String) : Resultado()
        /** Impede seguir (sem bloqueio de tela) ou exige o "sim" do dono (root, injecao). */
        data class Falhou(val texto: String) : Resultado()
    }

    class Passo(val id: String, val titulo: String, val rodar: (Context) -> Checagem)

    companion object {
        fun passos(): List<Passo> = listOf(
            Passo("bloqueio", t("Bloqueio de tela ativo"), ::bloqueio),
            Passo("hardware", t("Chave guardada no hardware"), ::hardware),
            Passo("root", t("Nenhum sinal de root"), ::root),
            Passo("injecao", t("Nenhum código injetado encontrado"), ::injecao),
            Passo("depurador", t("Nenhum depurador conectado"), ::depurador),
            Passo("origem", t("Instalado pela Google Play"), ::origem),
            Passo("acessibilidade", t("Nenhum app lendo a tela"), ::acessibilidade),
            Passo("tela", t("Tela protegida contra captura"), { Checagem("tela", t("Tela protegida contra captura"), Resultado.Passou) }),
            Passo("teclado", t("Teclado próprio para as palavras"), { Checagem("teclado", t("Teclado próprio para as palavras"), Resultado.Passou) }),
            Passo("sistema", "Android ${Build.VERSION.RELEASE}", ::sistema),
            Passo("copia", t("Nada copiado na área de transferência"), ::copia),
        )

        fun bloqueio(contexto: Context): Checagem {
            val seguro = contexto.getSystemService(KeyguardManager::class.java).isDeviceSecure
            return Checagem("bloqueio", t("Bloqueio de tela ativo"),
                if (seguro) Resultado.Passou else Resultado.Falhou(t("Sem bloqueio de tela, o Android não protege as chaves da carteira. Configure um PIN, padrão ou senha nas configurações do celular.")))
        }

        /** O nivel da chave que cifra o cofre: StrongBox, TEE ou (no pior caso) software. */
        fun hardware(contexto: Context): Checagem {
            val nivel = runCatching {
                val armazem = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                val chave = armazem.getKey("app.escalibur.wallet.cofre", null) as? SecretKey ?: return@runCatching null
                val info = SecretKeyFactory.getInstance(chave.algorithm, "AndroidKeyStore").getKeySpec(chave, KeyInfo::class.java) as KeyInfo
                info.securityLevel
            }.getOrNull()
            return when (nivel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX, KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT, null ->
                    Checagem("hardware", t("Chave guardada no hardware"), Resultado.Passou)
                else -> Checagem("hardware", t("Chave guardada no hardware"),
                    Resultado.Cautela(t("Este celular guarda a chave do cofre em software, sem o chip de segurança.")))
            }
        }

        fun root(contexto: Context): Checagem {
            val caminhos = listOf(
                "/system/bin/su", "/system/xbin/su", "/sbin/su", "/system/sbin/su", "/vendor/bin/su", "/su/bin/su", "/data/local/xbin/su",
                "/data/local/bin/su", "/system/app/Superuser.apk", "/data/adb/magisk", "/sbin/.magisk", "/data/adb/ksu", "/data/adb/ap",
            )
            val achado = caminhos.firstOrNull { File(it).exists() }
            val chavesDeTeste = Build.TAGS?.contains("test-keys") == true
            val pacotes = listOf("com.topjohnwu.magisk", "eu.chainfire.supersu", "me.weishu.kernelsu", "me.bmax.apatch")
            val app = pacotes.firstOrNull { runCatching { contexto.packageManager.getPackageInfo(it, 0) }.isSuccess }
            return if (achado != null || chavesDeTeste || app != null) {
                Checagem("root", t("Sinal de root encontrado"), Resultado.Falhou(t("Este celular parece ter root. Num aparelho assim, outro app pode ler a memória e o que você digita.")))
            } else {
                Checagem("root", t("Nenhum sinal de root"), Resultado.Passou)
            }
        }

        /** Bibliotecas de interceptacao carregadas no processo (Frida, Xposed e afins). */
        fun injecao(@Suppress("UNUSED_PARAMETER") contexto: Context): Checagem {
            val marcas = listOf("frida", "gadget", "xposed", "lsposed", "substrate", "riru", "zygisk", "edxp")
            val mapas = runCatching { File("/proc/self/maps").readLines() }.getOrDefault(emptyList())
            val achada = mapas.firstNotNullOfOrNull { linha -> marcas.firstOrNull { linha.lowercase().contains(it) } }
            return if (achada != null) {
                Checagem("injecao", t("Código injetado encontrado"), Resultado.Falhou(t("Há uma biblioteca de interceptação carregada no app (%@). Alguém pode estar lendo o que a tela mostra.", achada)))
            } else {
                Checagem("injecao", t("Nenhum código injetado encontrado"), Resultado.Passou)
            }
        }

        fun depurador(@Suppress("UNUSED_PARAMETER") contexto: Context): Checagem {
            val rastreado = runCatching {
                File("/proc/self/status").readLines().firstOrNull { it.startsWith("TracerPid:") }?.substringAfter(":")?.trim()?.toIntOrNull() ?: 0
            }.getOrDefault(0) != 0
            val conectado = Debug.isDebuggerConnected() || rastreado
            if (conectado && app.escalibur.wallet.BuildConfig.DEBUG) {
                return Checagem("depurador", t("Nenhum depurador conectado"), Resultado.Cautela(t("Build de teste, com depurador.")))
            }
            return if (conectado) Checagem("depurador", t("Depurador conectado"), Resultado.Falhou(t("Um depurador está preso ao app e pode ler a memória dele.")))
            else Checagem("depurador", t("Nenhum depurador conectado"), Resultado.Passou)
        }

        /** Instalado pela Google Play. Fora dela, o app pode nao ser o publicado. */
        fun origem(contexto: Context): Checagem {
            val instalador = runCatching { contexto.packageManager.getInstallSourceInfo(contexto.packageName).installingPackageName }.getOrNull()
            val daLoja = instalador == "com.android.vending"
            return when {
                daLoja -> Checagem("origem", t("Instalado pela Google Play"), Resultado.Passou)
                app.escalibur.wallet.BuildConfig.DEBUG -> Checagem("origem", t("Instalado pela Google Play"), Resultado.Cautela(t("Build de teste, instalado pelo computador.")))
                else -> Checagem("origem", t("Instalado pela Google Play"), Resultado.Cautela(t("Este app não veio da Google Play. Instale a Escalibur só pela Google Play.")))
            }
        }

        /**
         * Apps de acessibilidade ligados: eles leem tudo o que a tela mostra, e o golpe mais comum no
         * Android usa um deles. O leitor de tela tambem fala as palavras em voz alta.
         */
        fun acessibilidade(contexto: Context): Checagem {
            val gerente = contexto.getSystemService(AccessibilityManager::class.java)
            val servicos = gerente.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            val nomes = servicos.mapNotNull { info ->
                runCatching { info.resolveInfo.loadLabel(contexto.packageManager).toString() }.getOrNull()
            }.distinct()
            return when {
                nomes.isEmpty() -> Checagem("acessibilidade", t("Nenhum app lendo a tela"), Resultado.Passou)
                gerente.isTouchExplorationEnabled && nomes.size == 1 -> Checagem("acessibilidade", t("Leitor de tela ligado"),
                    Resultado.Cautela(t("O leitor de tela lê em voz alta o que aparece, inclusive as palavras. Use fone de ouvido, ou desligue nas configurações de acessibilidade.")))
                else -> Checagem("acessibilidade", t("Apps lendo a tela"),
                    Resultado.Cautela(t("Com acesso de acessibilidade, estes apps leem tudo o que a tela mostra: %@. Se não reconhece algum, desligue nas configurações de acessibilidade antes de seguir.", nomes.joinToString(", "))))
            }
        }

        /** A atualizacao de seguranca do celular: mais de 6 meses atras, merece atencao. */
        fun sistema(@Suppress("UNUSED_PARAMETER") contexto: Context): Checagem {
            val titulo = "Android ${Build.VERSION.RELEASE}"
            val patch = runCatching { SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(Build.VERSION.SECURITY_PATCH) }.getOrNull()
            val antiga = patch != null && Date().time - patch.time > 183L * 24 * 3600 * 1000
            return Checagem("sistema", titulo,
                if (antiga) Resultado.Cautela(t("A última atualização de segurança deste celular é de %@. Atualize quando puder.", Build.VERSION.SECURITY_PATCH)) else Resultado.Passou)
        }

        /** So pergunta se ha algo copiado: nunca le o conteudo. */
        /** A ultima conferencia terminada nesta abertura do app. */
        var ultimaConferencia: Date? = null

        fun copia(contexto: Context): Checagem {
            val ha = runCatching { contexto.getSystemService(ClipboardManager::class.java).hasPrimaryClip() }.getOrDefault(false)
            return if (ha) Checagem("copia", t("Há algo copiado"), Resultado.Cautela(t("Se for a senha da carteira, apague depois de colar: outros apps podem ler a área de transferência.")))
            else Checagem("copia", t("Nada copiado na área de transferência"), Resultado.Passou)
        }
    }
}

/**
 * A checagem, antes das palavras: cada item roda na hora em que a linha dele gira, com o resultado
 * logo ao lado, e no fim o horario exato da conferencia. Quem volta desta tela e entra de novo ve
 * "Conferindo de novo", com o horario da anterior: e uma checagem nova, feita naquele instante. Uma
 * checagem que falha pede o "estou ciente" do dono; sem bloqueio de tela, nao segue.
 */
@Composable
fun VerificacaoDoAparelho(tituloDoDeslize: String, criando: Boolean, aoSeguir: () -> Unit) {
    val contexto = LocalContext.current
    val parado = movimentoReduzido()
    val passos = remember { Checagem.passos() }
    val resultados = remember { mutableStateListOf<Checagem>() }
    var anterior by remember { mutableStateOf<Date?>(null) }
    var conferidoAs by remember { mutableStateOf<Date?>(null) }
    var ciente by remember { mutableStateOf(false) }
    var rodada by remember { mutableIntStateOf(0) }
    val terminou = resultados.size >= passos.size
    val bloqueantes = resultados.filter { it.resultado is Checagem.Resultado.Falhou }
    val impede = bloqueantes.any { it.id == "bloqueio" }
    val podeSeguir = terminou && !impede && (bloqueantes.isEmpty() || ciente)

    LaunchedEffect(rodada) {
        anterior = Checagem.ultimaConferencia
        conferidoAs = null
        ciente = false
        resultados.clear()
        for (passo in passos) {
            delay(if (parado) 60 else 520)
            // A verificacao roda aqui, no instante em que a linha dela termina de girar.
            resultados += passo.rodar(contexto)
        }
        val agora = Date()
        conferidoAs = agora
        Checagem.ultimaConferencia = agora
    }

    Column(Modifier.fillMaxSize().background(Paleta.vazio)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.lg)) {
            AnelDaChecagem(if (passos.isEmpty()) 0f else resultados.size.toFloat() / passos.size, terminou, terminou && bloqueantes.isNotEmpty(),
                           Modifier.fillMaxWidth().height(220.dp))
            // Titulo, subtitulo e horario no centro, embaixo do anel.
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                AnimatedContent(
                    when {
                        terminou && bloqueantes.isEmpty() -> t("Aparelho conferido")
                        terminou -> t("Atenção antes de seguir")
                        anterior == null -> t("Conferindo este celular")
                        else -> t("Conferindo de novo")
                    },
                    transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(200)) }, label = "titulo",
                ) { titulo ->
                    Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm))
                }
                Text(
                    if (terminou) t("Tudo foi checado aqui, sem internet, e nada sai do aparelho.")
                    else passos.getOrNull(resultados.size)?.let { t("Checando: %@", it.titulo) } ?: t("Preparando a checagem"),
                    style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xxs),
                )
                val antes = anterior
                if (antes != null && !terminou) Carimbo(t("A anterior foi às %@. Esta é nova, item por item, agora.", relogio(antes)), Icones.atualizar)
                val agora = conferidoAs
                if (agora != null && terminou) {
                    Carimbo(if (antes == null) t("Conferido às %@", relogio(agora)) else t("Conferido de novo às %@", relogio(agora)), Icones.relogio)
                }
            }
            Column(Modifier.padding(top = Espaco.md)) {
                passos.forEachIndexed { indice, passo ->
                    LinhaDaChecagem(passo, resultados.getOrNull(indice), rodando = indice == resultados.size && !terminou)
                }
            }
            // Uma checagem falhou e da para seguir: o dono declara, marcando, que sabe o que falhou e o
            // que isso arrisca.
            if (terminou && bloqueantes.isNotEmpty() && !impede) {
                Aceite(
                    ciente,
                    if (criando) t("Estou ciente de que este celular falhou na verificação de integridade e de que gerar as palavras aqui pode expor a carteira. Quero seguir mesmo assim.")
                    else t("Estou ciente de que este celular falhou na verificação de integridade e de que digitar as palavras aqui pode expor a carteira. Quero seguir mesmo assim."),
                    Modifier.padding(top = Espaco.md),
                ) { ciente = it }
            }
        }
        // O deslizar so aparece quando a conferencia termina.
        AnimatedVisibility(
            terminou,
            enter = slideInVertically(spring(dampingRatio = 0.85f, stiffness = 250f)) { it } + fadeIn(),
            exit = slideOutVertically { it } + fadeOut(),
        ) {
            Rodape {
                if (impede) BotaoSecundario(t("Checar de novo")) { rodada++ }
                DeslizeParaSeguir(tituloDoDeslize, podeSeguir, aoSeguir)
            }
        }
    }
}

private fun relogio(data: Date): String =
    SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(Formato.locale, "jjmmss"), Formato.locale).format(data)

/** O icone vai dentro do texto, no comeco da primeira linha. */
@Composable
private fun Carimbo(texto: String, icone: ImageVector) {
    Text(
        buildAnnotatedString {
            appendInlineContent("icone", "[i]")
            append(" ")
            append(texto)
        },
        style = estilo(Tipo.nota).copy(fontFeatureSettings = "tnum"), color = Paleta.tintaSuave, textAlign = TextAlign.Center,
        modifier = Modifier.padding(top = Espaco.xs).semantics { contentDescription = texto },
        inlineContent = mapOf("icone" to InlineTextContent(Placeholder(13.sp, 13.sp, PlaceholderVerticalAlign.TextCenter)) {
            Icone(icone, Paleta.tintaSuave, tamanho = 12.dp)
        }),
    )
}

@Composable
private fun LinhaDaChecagem(passo: Checagem.Passo, resultado: Checagem?, rodando: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = Espaco.xs), horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) {
            when {
                resultado?.resultado is Checagem.Resultado.Passou -> Icone(Icones.vistoCheio, Paleta.sucesso, tamanho = 21.dp)
                resultado?.resultado is Checagem.Resultado.Cautela -> Icone(Icones.exclamacaoCheia, Paleta.cautela, tamanho = 21.dp)
                resultado?.resultado is Checagem.Resultado.Falhou -> Icone(Icones.falha, Paleta.baixa, tamanho = 21.dp)
                rodando -> Girando(Paleta.sucesso, 20.dp)
                else -> Canvas(Modifier.size(20.dp)) { drawCircle(Paleta.borda, radius = size.minDimension / 2 - 0.75.dp.toPx(), style = Stroke(1.5.dp.toPx())) }
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(resultado?.titulo ?: passo.titulo, style = estilo(Tipo.linha), color = if (resultado == null && !rodando) Paleta.tintaApagada else Paleta.tinta)
            when (val r = resultado?.resultado) {
                is Checagem.Resultado.Cautela -> Text(r.texto, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                is Checagem.Resultado.Falhou -> Text(r.texto, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                else -> Unit
            }
        }
    }
}

/**
 * O escaneamento em pixels, no estilo do deslizar: por fora, um anel de pixels que acende em verde, em
 * ordem, conforme cada item fica pronto (cada pixel cresce devagar, um depois do outro); por dentro,
 * pixels cinza cifrando, com uma passada clara girando enquanto a checagem corre. No fim, o escudo
 * com o resultado, e o fundo do circulo em pixels verdes que se espalham do centro e respiram.
 */
@Composable
private fun AnelDaChecagem(progresso: Float, pronto: Boolean, alerta: Boolean, modifier: Modifier) {
    val parado = movimentoReduzido()
    val agora by relogio(parado)
    // Quando cada pixel de fora acendeu, para o brilho de chegada; e quando a checagem terminou.
    val acesoEm = remember { HashMap<Int, Float>() }
    var acesos by remember { mutableIntStateOf(0) }
    var prontoEm by remember { mutableStateOf<Float?>(null) }
    val externos = 56
    val internos = 40
    LaunchedEffect(progresso) {
        val novo = (progresso * externos).toInt()
        if (novo < acesos) acesoEm.clear()
        else if (novo > acesos) {
            // Na fila: um passo novo comeca onde o anterior parou, num ritmo constante.
            val fila = acesoEm.values.maxOrNull()?.plus(PASSO_DO_PIXEL) ?: 0f
            val inicio = maxOf(agora, fila)
            for (i in acesos until novo) acesoEm[i] = inicio + (i - acesos) * PASSO_DO_PIXEL
        }
        acesos = novo
    }
    LaunchedEffect(pronto) { prontoEm = if (pronto) agora else null }
    val escala by animateFloatAsState(if (pronto) 1.08f else 1f, spring(dampingRatio = 0.55f, stiffness = 190f), label = "escudo")
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val centro = center
            val relogio = if (parado || pronto) 0f else agora
            val cor = if (alerta) Paleta.cautela else Paleta.sucesso
            // Por fora: o progresso.
            for (i in 0 until externos) {
                val angulo = i.toDouble() / externos * 2 * PI - PI / 2
                val ponto = Offset(centro.x + 84.dp.toPx() * cos(angulo).toFloat(), centro.y + 84.dp.toPx() * sin(angulo).toFloat())
                val lado = 6.5.dp.toPx()
                val idade = if (i < acesos) (acesoEm[i]?.let { agora - it } ?: 10f) else -1f
                val revela = if (parado) (if (i < acesos) 1f else 0f) else suave(idade / 0.32f)
                if (revela < 1f) drawRoundRect(PixelsCifrando.cinza(tom(i, 0, relogio)), Offset(ponto.x - lado / 2, ponto.y - lado / 2), Size(lado, lado), CornerRadius(1.6.dp.toPx()))
                if (revela > 0f) {
                    val e = 0.55f + 0.45f * revela
                    drawRoundRect(cor.copy(alpha = revela), Offset(ponto.x - lado / 2 * e, ponto.y - lado / 2 * e), Size(lado * e, lado * e), CornerRadius(1.6.dp.toPx() * e))
                }
            }
            // Por dentro: a cifra, com a passada girando.
            val passada = ((relogio / 1.6f) % 1f) * 2 * PI.toFloat()
            for (i in 0 until internos) {
                val angulo = i.toFloat() / internos * 2 * PI.toFloat() - PI.toFloat() / 2
                var distancia = abs(angulo + PI.toFloat() / 2 - passada)
                distancia = minOf(distancia, 2 * PI.toFloat() - distancia)
                val brilho = if (pronto) 0f else exp(-(distancia / 0.5f) * (distancia / 0.5f))
                val ponto = Offset(centro.x + 66.dp.toPx() * cos(angulo), centro.y + 66.dp.toPx() * sin(angulo))
                val lado = 4.8.dp.toPx()
                val preenchimento = if (pronto) cor.copy(alpha = (0.35 + 0.25 * tom(i, 1, 0f)).toFloat()) else PixelsCifrando.cinza(tom(i, 1, relogio) + 0.4 * brilho)
                drawRoundRect(preenchimento, Offset(ponto.x - lado / 2, ponto.y - lado / 2), Size(lado, lado), CornerRadius(1.2.dp.toPx()))
            }
            // No fim, o fundo do circulo em pixels verdes que se espalham do centro.
            val desde = if (parado) 10f else prontoEm?.let { agora - it }
            if (pronto && desde != null) brilhoDoFim(centro, desde, cor, parado)
        }
        Icone(
            when { !pronto -> Icones.escudoMetade; alerta -> Icones.escudoAlertaCheio; else -> Icones.escudoVistoCheio },
            when { !pronto -> Paleta.tinta; alerta -> Paleta.cautela; else -> Paleta.sucesso },
            tamanho = 62.dp, modifier = Modifier.graphicsLayer { scaleX = escala; scaleY = escala },
        )
    }
}

private const val PASSO_DO_PIXEL = 0.035f

/** O tom cifrado de um pixel agora, como no deslizar. */
private fun tom(indice: Int, anel: Int, relogio: Float): Double {
    val fase = PixelsCifrando.ruido(indice, anel, 0x2B7F)
    val batida = relogio * 6 * (0.6 + 0.8 * fase) + fase * 8
    val degrau = floor(batida)
    val t = batida - degrau
    val mistura = t * t * (3 - 2 * t)
    val a = PixelsCifrando.ruido(indice, anel, degrau.toLong())
    val b = PixelsCifrando.ruido(indice, anel, degrau.toLong() + 1)
    return 0.16 + 0.22 * (a + (b - a) * mistura)
}

/**
 * Terminado: o fundo do circulo em pixels verdes, fracos, do centro para a borda de dentro, em aneis
 * concentricos como os de fora. Assentados, os pixels respiram, cada um no seu tempo, e uma onda sai
 * do centro de tempos em tempos. `desde`: segundos desde o fim.
 */
private fun DrawScope.brilhoDoFim(centro: Offset, desde: Float, cor: Color, parado: Boolean) {
    val raio = 52.dp.toPx()
    val espaco = 6.5.dp.toPx()
    var indice = 0
    for (anel in 0..(raio / espaco).toInt()) {
        val r = anel * espaco
        val quantos = if (anel == 0) 1 else maxOf(6, (2 * PI * r / espaco).roundToInt())
        // Aneis alternados meio passo girados: o desenho fica tramado, nao em raios.
        val giro = if (anel % 2 == 0) 0.0 else PI / quantos
        for (vaga in 0 until quantos) {
            val angulo = vaga.toDouble() / quantos * 2 * PI + giro
            val x = centro.x + (r * cos(angulo)).toFloat()
            val y = centro.y + (r * sin(angulo)).toFloat()
            val chegou = suave((desde - r / raio * 0.5f) / 0.3f)
            val ruido = PixelsCifrando.ruido(indice, 7, 0x5D1).toFloat()
            var nivel = 0.10f + 0.14f * ruido
            if (!parado && desde > 0.8f) {
                // Respira: cada pixel no seu ritmo; e a onda passa do centro para a borda.
                val respira = 0.5f + 0.5f * sin(desde * (1.1f + 0.9f * ruido) + ruido * 6.28f)
                val frente = (desde / 2.8f) % 1f * 1.3f
                val onda = exp(-((r / raio - frente) / 0.12f) * ((r / raio - frente) / 0.12f))
                nivel = nivel * (0.65f + 0.55f * respira) + 0.22f * onda
            }
            // A borda some devagar: o contorno fica redondo.
            val beira = suave((raio - r) / 8.dp.toPx())
            val lado = 3.2.dp.toPx()
            drawRoundRect(cor.copy(alpha = minOf(nivel, 0.6f) * chegou * (0.35f + 0.65f * beira)), Offset(x - lado / 2, y - lado / 2), Size(lado, lado), CornerRadius(0.8.dp.toPx()))
            indice++
        }
    }
}
