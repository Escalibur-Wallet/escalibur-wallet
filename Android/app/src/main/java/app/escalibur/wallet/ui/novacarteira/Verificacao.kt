package app.escalibur.wallet.ui.novacarteira

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
import androidx.compose.material3.CircularProgressIndicator
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
        fun copia(contexto: Context): Checagem {
            val ha = runCatching { contexto.getSystemService(ClipboardManager::class.java).hasPrimaryClip() }.getOrDefault(false)
            return if (ha) Checagem("copia", t("Há algo copiado"), Resultado.Cautela(t("Se for a senha da carteira, apague depois de colar: outros apps podem ler a área de transferência.")))
            else Checagem("copia", t("Nada copiado na área de transferência"), Resultado.Passou)
        }
    }
}

/**
 * A checagem, antes das palavras: cada item roda na hora em que a linha dele gira, com o resultado
 * ao lado, e no fim o horario exato. Uma checagem que falha pede o "estou ciente" do dono; sem
 * bloqueio de tela, nao segue.
 */
@Composable
fun VerificacaoDoAparelho(tituloDoDeslize: String, criando: Boolean, aoSeguir: () -> Unit) {
    val contexto = LocalContext.current
    val passos = remember { Checagem.passos() }
    val resultados = remember { mutableStateListOf<Checagem>() }
    var conferidoAs by remember { mutableStateOf<Date?>(null) }
    var ciente by remember { mutableStateOf(false) }
    var rodada by remember { mutableStateOf(0) }
    val terminou = resultados.size >= passos.size
    val bloqueantes = resultados.filter { it.resultado is Checagem.Resultado.Falhou }
    val impede = bloqueantes.any { it.id == "bloqueio" }
    val podeSeguir = terminou && !impede && (bloqueantes.isEmpty() || ciente)

    LaunchedEffect(rodada) {
        resultados.clear()
        ciente = false
        conferidoAs = null
        for (passo in passos) {
            delay(520)
            resultados += passo.rodar(contexto)
        }
        conferidoAs = Date()
    }

    Column(Modifier.fillMaxSize().background(Paleta.vazio)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.lg)) {
            AnelDaChecagem(resultados.size.toFloat() / passos.size, terminou, terminou && bloqueantes.isNotEmpty(), Modifier.fillMaxWidth().height(200.dp))
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    when {
                        terminou && bloqueantes.isEmpty() -> t("Aparelho conferido")
                        terminou -> t("Atenção antes de seguir")
                        else -> t("Conferindo este celular")
                    },
                    style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm),
                )
                Text(
                    if (terminou) t("Tudo foi checado aqui, sem internet, e nada sai do aparelho.")
                    else passos.getOrNull(resultados.size)?.let { t("Checando: %@", it.titulo) } ?: t("Preparando a checagem"),
                    style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xxs),
                )
                conferidoAs?.takeIf { terminou }?.let {
                    Row(Modifier.padding(top = Espaco.xs), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icone(Icones.relogio, Paleta.tintaSuave, tamanho = 13.dp)
                        Text(t("Conferido às %@", SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(it)), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    }
                }
            }
            Column(Modifier.padding(top = Espaco.md)) {
                passos.forEachIndexed { indice, passo ->
                    LinhaDaChecagem(passo, resultados.getOrNull(indice), rodando = indice == resultados.size && !terminou)
                }
            }
            if (terminou && bloqueantes.isNotEmpty() && !impede) {
                Aceite(
                    ciente,
                    if (criando) t("Estou ciente de que este celular falhou na verificação de integridade e de que gerar as palavras aqui pode expor a carteira. Quero seguir mesmo assim.")
                    else t("Estou ciente de que este celular falhou na verificação de integridade e de que digitar as palavras aqui pode expor a carteira. Quero seguir mesmo assim."),
                    Modifier.padding(top = Espaco.md),
                ) { ciente = it }
            }
        }
        if (terminou) {
            Rodape {
                if (impede) BotaoSecundario(t("Checar de novo")) { rodada++ }
                DeslizeParaSeguir(tituloDoDeslize, podeSeguir, aoSeguir)
            }
        }
    }
}

@Composable
private fun LinhaDaChecagem(passo: Checagem.Passo, resultado: Checagem?, rodando: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = Espaco.xs), horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) {
            when {
                resultado?.resultado is Checagem.Resultado.Passou -> Icone(Icones.vistoCheio, Paleta.sucesso, tamanho = 21.dp)
                resultado?.resultado is Checagem.Resultado.Cautela -> Icone(Icones.alerta, Paleta.cautela, tamanho = 20.dp)
                resultado?.resultado is Checagem.Resultado.Falhou -> Icone(Icones.falha, Paleta.baixa, tamanho = 20.dp)
                rodando -> CircularProgressIndicator(color = Paleta.sucesso, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                else -> Box(Modifier.size(20.dp).clip(CircleShape).background(Paleta.vazio)) {
                    Canvas(Modifier.fillMaxSize()) { drawCircle(Paleta.borda, style = Stroke(1.5.dp.toPx())) }
                }
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

/** Um anel de pixels que acende em verde conforme cada item fica pronto, com o escudo no fim. */
@Composable
private fun AnelDaChecagem(progresso: Float, pronto: Boolean, alerta: Boolean, modifier: Modifier) {
    val giro = rememberInfiniteTransition(label = "varredura")
    val angulo by giro.animateFloat(0f, 360f, infiniteRepeatable(tween(1800, easing = LinearEasing)), label = "angulo")
    val brilho by giro.animateFloat(0.35f, 0.75f, infiniteRepeatable(tween(700), RepeatMode.Reverse), label = "brilho")
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(180.dp)) {
            val pixels = 48
            val raio = size.minDimension / 2 - 6.dp.toPx()
            val lado = 7.dp.toPx()
            for (i in 0 until pixels) {
                val fracao = i / pixels.toFloat()
                val a = Math.toRadians((fracao * 360 - 90).toDouble())
                val centro = Offset(center.x + raio * Math.cos(a).toFloat(), center.y + raio * Math.sin(a).toFloat())
                val aceso = fracao < progresso
                val cor = when {
                    alerta && pronto -> Paleta.cautela
                    aceso -> Paleta.sucesso
                    else -> Paleta.controle
                }
                drawRect(cor.copy(alpha = if (aceso || pronto) 1f else 0.9f), Offset(centro.x - lado / 2, centro.y - lado / 2), Size(lado, lado))
            }
            if (!pronto) {
                val interno = raio - 22.dp.toPx()
                for (linha in -4..4) for (coluna in -4..4) {
                    val x = center.x + coluna * 12.dp.toPx()
                    val y = center.y + linha * 12.dp.toPx()
                    if ((x - center.x) * (x - center.x) + (y - center.y) * (y - center.y) > interno * interno) continue
                    val fase = ((linha * 7 + coluna * 13 + 64) % 9) / 9f
                    val tom = 0.18f + 0.22f * ((brilho + fase) % 1f)
                    drawRect(Color(tom, tom, tom + 0.02f), Offset(x - 4.dp.toPx(), y - 4.dp.toPx()), Size(8.dp.toPx(), 8.dp.toPx()))
                }
                drawArc(Paleta.sucesso.copy(alpha = 0.5f), angulo, 40f, false, Offset(center.x - interno, center.y - interno), Size(interno * 2, interno * 2), style = Stroke(2.dp.toPx()))
            }
        }
        if (pronto) Icone(if (alerta) Icones.alerta else Icones.escudo, if (alerta) Paleta.cautela else Paleta.sucesso, tamanho = 56.dp)
    }
}

/**
 * Deslizar para seguir: o trilho com o cadeado que o dedo leva ate o fim. Para passos que pedem
 * atencao: um toque sem querer nao segue. Soltou antes do fim, volta.
 */
@Composable
fun DeslizeParaSeguir(titulo: String, ligado: Boolean, aoSeguir: () -> Unit) {
    val haptico = LocalHapticFeedback.current
    val escopo = rememberCoroutineScope()
    val posicao = remember { Animatable(0f) }
    var feito by remember { mutableStateOf(false) }
    val densidade = LocalDensity.current
    BoxWithConstraints(
        Modifier.fillMaxWidth().height(Altura.primaria).clip(CircleShape).background(if (ligado) Paleta.trilho else Paleta.corpo),
    ) {
        val pegador = Altura.primaria - 8.dp
        val curso = with(densidade) { (maxWidth - pegador - 8.dp).toPx() }
        Box(Modifier.fillMaxSize().padding(start = pegador), contentAlignment = Alignment.Center) {
            Text(titulo, style = estilo(Tipo.acao), color = if (ligado) Paleta.tintaSuave.copy(alpha = 1f - posicao.value / maxOf(curso, 1f)) else Paleta.tintaApagada, maxLines = 1)
        }
        Box(
            Modifier.padding(4.dp).offset { IntOffset(posicao.value.toInt(), 0) }.size(pegador).clip(CircleShape)
                .background(if (ligado) Paleta.acento else Paleta.controle)
                .pointerInput(ligado) {
                    if (!ligado) return@pointerInput
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            escopo.launch {
                                if (posicao.value >= curso * 0.92f && !feito) {
                                    feito = true
                                    posicao.animateTo(curso, tween(120))
                                    haptico.performHapticFeedback(HapticFeedbackType.Confirm)
                                    aoSeguir()
                                } else {
                                    posicao.animateTo(0f, spring(dampingRatio = 0.7f))
                                }
                            }
                        },
                    ) { _, arrasto -> escopo.launch { posicao.snapTo((posicao.value + arrasto).coerceIn(0f, curso)) } }
                },
            contentAlignment = Alignment.Center,
        ) {
            Icone(Icones.cadeadoCheio, if (ligado) Paleta.sobreAcento else Paleta.tintaApagada, tamanho = 20.dp)
        }
    }
}
