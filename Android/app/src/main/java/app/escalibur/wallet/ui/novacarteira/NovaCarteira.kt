package app.escalibur.wallet.ui.novacarteira

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
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
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.importar.EntradaDaFrase
import app.escalibur.wallet.ui.importar.TelaDaFrase
import androidx.compose.foundation.text.input.TextFieldState
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.carteira.Redes
import app.escalibur.wallet.ui.comp.Aceite
import app.escalibur.wallet.ui.comp.BotaoDeCanto
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.CampoDePalavra
import app.escalibur.wallet.ui.comp.Confirmacao
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.Ponto
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.comp.SeloDaCarteira
import app.escalibur.wallet.ui.comp.Segmentado
import app.escalibur.wallet.ui.comp.SugestoesDePalavra
import app.escalibur.wallet.ui.comp.TecladoDePalavras
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.comp.rememberPalavra
import app.escalibur.wallet.ui.legal.DocumentoLegal
import app.escalibur.wallet.ui.legal.FolhaLegal
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.security.SecureRandom
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** A versao do texto de aceite. Mudou o texto do aceite ou a clausula dos Termos, sobe o numero. */
const val VERSAO_DO_ACEITE = 1

/**
 * Da decisao de criar ate a carteira com copia conferida. A carteira e guardada **antes** de
 * mostrar as palavras: se o dono sair no meio, ela existe marcada "palavras nao confirmadas" e nao
 * recebe.
 */
@Composable
fun FluxoDeNovaCarteira(primeira: Boolean, aoTerminar: () -> Unit) {
    var passo by remember { mutableStateOf("antes") }
    var palavras by remember { mutableIntStateOf(12) }
    var carteira by remember { mutableStateOf<Carteira?>(null) }
    var guardando by remember { mutableStateOf(false) }
    var erro by remember { mutableStateOf<String?>(null) }
    var perguntandoDepois by remember { mutableStateOf(false) }
    // O dono escolhe as palavras: digita todas menos a ultima, e o app sorteia a ultima, que fecha a conta.
    var propria by remember { mutableStateOf(false) }
    val escopo = rememberCoroutineScope()

    fun cancelar() {
        escopo.launch { runCatching { Api.objeto("carteira.descartarRascunho") } }
        aoTerminar()
    }

    fun guardar() {
        guardando = true
        erro = null
        escopo.launch {
            try {
                val salva = Autorizacao.tentando(t("Guardar a carteira nova neste celular")) { credencial ->
                    Api.comSegredo("carteira.criar", JSONObject().put("palavras", palavras).put("credencial", credencial.json()), *credencial.partes())
                }
                if (salva == null) {
                    passo = "antes"
                } else {
                    carteira = Carteira.de(salva)
                    App.recarregar()
                    passo = "gravar"
                }
            } catch (falha: Throwable) {
                erro = Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível guardar a carteira. Tente de novo.")
                passo = "antes"
            } finally {
                guardando = false
            }
        }
    }

    /**
     * As palavras escolhidas: conferidas antes do PIN (cada uma da lista em ingles, nenhuma
     * combinacao que robo testa primeiro); depois o app sorteia a ultima e guarda a carteira como
     * a sorteada inteira, antes de mostrar a palavra nova. Devolve o erro para mostrar, ou nil.
     */
    suspend fun escolher(primeiras: ByteArray): String? {
        try {
            val conferida = Api.comSegredo("carteira.conferirEscolhidas", JSONObject(), primeiras.copyOf())
            if (conferida.has("fora")) return t("A palavra %lld não está na lista em inglês. Toque nela para corrigir.", conferida.getInt("fora"))
            guardando = true
            val salva = Autorizacao.tentando(t("Guardar a carteira nova neste celular")) { credencial ->
                Api.comSegredo("carteira.criarComPalavras", JSONObject().put("palavras", palavras).put("credencial", credencial.json()),
                               *credencial.partes(primeiras.copyOf()))
            } ?: return null
            carteira = Carteira.de(salva)
            App.recarregar()
            passo = "sorteada"
            return null
        } catch (falha: FalhaDoNucleo) {
            return when (falha.codigo) {
                "frase.fraca.repeated" -> t("Uma palavra aparece três vezes ou mais. Frases assim são as primeiras que os robôs testam: troque algumas.")
                "frase.fraca.sequence" -> t("Três palavras seguidas estão na ordem da lista. Frases assim são as primeiras que os robôs testam: troque algumas.")
                "frase.fraca.pattern" -> t("As palavras se repetem em bloco. Frases assim são as primeiras que os robôs testam: troque algumas.")
                else -> Autorizacao.mensagemDeRecusa(falha) ?: t("Use só palavras da lista em inglês, uma em cada campo.")
            }
        } finally {
            primeiras.fill(0)
            guardando = false
        }
    }

    BackHandler {
        when (passo) {
            "propria" -> passo = "antes"
            "aceite" -> passo = "antes"
            "checagem" -> passo = "aceite"
            "conferir" -> passo = "gravar"
            "criada" -> aoTerminar()
            else -> if (carteira == null) cancelar() else perguntandoDepois = true
        }
    }

    Box(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
        AnimatedContent(passo, transitionSpec = { fadeIn(tween(150)) togetherWith fadeOut(tween(150)) }, label = "nova") { atual ->
            Column(Modifier.fillMaxSize()) {
                if (atual != "propria") Spacer(Modifier.height(Altura.barra))
                when (atual) {
                    "antes" -> AntesDasPalavras(palavras, erro, { palavras = it }, aoEscolherAsPalavras = { erro = null; propria = true; passo = "aceite" }) {
                        erro = null
                        propria = false
                        passo = "aceite"
                    }
                    "aceite" -> Responsabilidade(t("Conferir o aparelho")) { passo = "checagem" }
                    "checagem" -> Box(Modifier.weight(1f)) {
                        VerificacaoDoAparelho(if (propria) t("Deslize para escolher as palavras") else t("Deslize para ver as palavras"), criando = true) {
                            if (propria) passo = "propria" else guardar()
                        }
                        if (guardando) Trabalhando(t("Criando a carteira"))
                    }
                    "propria" -> Box(Modifier.weight(1f)) {
                        EscolherPalavras(palavras, aoCancelar = { passo = "antes" }, aoEscolher = ::escolher)
                        if (guardando) Trabalhando(t("Criando a carteira"))
                    }
                    "sorteada" -> PalavraSorteada(palavras) { passo = "gravar" }
                    "gravar" -> GravarPalavras(palavras, nomeDaCarteira = null) { passo = "conferir" }
                    "conferir" -> ConferirPalavras(palavras, aoVoltar = { passo = "gravar" }, aoDepois = { perguntandoDepois = true }) {
                        escopo.launch {
                            carteira?.let { App.aplicar(Api.objeto("carteira.confirmarCopia", JSONObject().put("id", it.id))) }
                            passo = "criada"
                        }
                    }
                    "criada" -> carteira?.let { CarteiraCriada(it, primeira, aoTerminar) }
                }
            }
        }
        // Voltar um passo, ou fechar: com a carteira ja guardada e sem copia, fechar passa pelo aviso.
        if (passo != "criada" && passo != "propria") {
            val voltar = passo in listOf("aceite", "checagem", "conferir")
            BotaoDeCanto(if (voltar) Icones.voltar else Icones.fechar, if (voltar) t("Voltar") else t("Fechar"), Modifier.padding(start = Espaco.xs)) {
                when (passo) {
                    "aceite" -> passo = "antes"
                    "checagem" -> passo = "aceite"
                    "conferir" -> passo = "gravar"
                    else -> if (carteira == null) cancelar() else perguntandoDepois = true
                }
            }
        }
    }
    if (perguntandoDepois) {
        Confirmacao(
            titulo = t("Confirmar depois?"),
            mensagem = t("Sem a senha da carteira anotada, perder o celular é perder os ativos. Até você confirmar, a carteira fica marcada Palavras não confirmadas e não recebe."),
            tituloDaAcao = t("Confirmar depois"), tituloDoCancelar = t("Voltar e anotar"),
            aoConfirmar = { perguntandoDepois = false; cancelar() }, aoCancelar = { perguntandoDepois = false },
        )
    }
}

/** O cofre guardando a carteira: os segundos do Argon2 do PIN e do Keystore. */
@Composable
fun Trabalhando(titulo: String) {
    Box(Modifier.fillMaxSize().background(Paleta.vazio.copy(alpha = 0.92f)).clickable(enabled = true, onClick = {}), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
            SeloDaCarteira(64.dp)
            Text(titulo, style = estilo(Tipo.cabecalho), color = Paleta.tinta)
            androidx.compose.material3.LinearProgressIndicator(color = Paleta.acento, trackColor = Paleta.trilho, modifier = Modifier.width(140.dp))
        }
    }
}

/** As palavras escolhidas pelo dono: a tela de digitar, com a ultima reservada para o sorteio. */
@Composable
private fun EscolherPalavras(palavras: Int, aoCancelar: () -> Unit, aoEscolher: suspend (ByteArray) -> String?) {
    val entrada = remember(palavras) { EntradaDaFrase(palavras - 1) }
    val semPassphrase = remember { TextFieldState() }
    val semRepeticao = remember { TextFieldState() }
    DisposableEffect(entrada) { onDispose { entrada.zerar() } }
    TelaDaFrase(entrada, semPassphrase, semRepeticao, false, {}, aoCancelar, escolhendo = palavras, aoEscolher = aoEscolher) {}
}

/**
 * A ultima palavra, sorteada: grande, com o numero, para o dono anotar no papel junto das que
 * escolheu. Depois, as palavras e a conferencia de sempre.
 */
@Composable
private fun PalavraSorteada(palavras: Int, aoAnotar: () -> Unit) {
    var palavra by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(palavras) {
        palavra = runCatching { Api.lista("carteira.palavras", JSONObject().put("de", palavras - 1).put("ate", palavras)).getString(0) }.getOrNull()
    }
    DisposableEffect(Unit) { onDispose { palavra = null } }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(horizontal = Espaco.margem).padding(top = Espaco.md)) {
            Text(t("A %lldª palavra", palavras), style = estilo(Tipo.titulo), color = Paleta.tinta)
            Text(t("O app sorteou esta entre as %lld que fecham a conta com as suas %lld. Anote no papel, como a %lldª.", if (palavras == 12) 128 else 8, palavras - 1, palavras),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs))
            Row(
                Modifier.padding(top = Espaco.lg).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.viva)
                    .padding(horizontal = Espaco.lg, vertical = Espaco.lg),
                verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
            ) {
                Text("$palavras", fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Paleta.placaApagada)
                Text(palavra ?: "", fontSize = 40.sp, fontWeight = FontWeight.Bold, color = Paleta.placaTinta)
            }
            Text(t("Em seguida vêm as %lld palavras, para conferir o que você anotou, e a conferência de sempre.", palavras),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.md))
        }
        Rodape { BotaoPrimario(t("Anotei"), ligado = palavra != null) { palavra = null; aoAnotar() } }
    }
}

@Composable
private fun AntesDasPalavras(palavras: Int, erro: String?, aoEscolher: (Int) -> Unit, aoEscolherAsPalavras: () -> Unit, aoSeguir: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(top = Espaco.md, bottom = Espaco.md)) {
            PapelRabiscado(palavras, Modifier.align(Alignment.CenterHorizontally).padding(top = Espaco.xs))
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(t("Antes de ver as palavras"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.lg))
                Text(
                    t("A senha da carteira são %lld palavras, em ordem. Quem tiver as palavras tem o saldo. Sem elas, ninguém recupera a carteira, nem a Escalibur.", palavras),
                    style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs),
                )
                Segmentado(listOf(12 to t("12 palavras"), 24 to t("24 palavras")), palavras, Modifier.width(220.dp).padding(top = Espaco.md), aoEscolher)
            }
            Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
                Ponto(Icones.lapis, t("No papel, à mão"), t("Jamais tire print: a foto pode subir para a nuvem, e isso aumenta a chance de a sua carteira ser hackeada."))
                Ponto(Icones.relogio, t("Uns 2 minutos"), t("As palavras aparecem de três em três, na ordem. Anote cada grupo antes de passar para o próximo."))
                Ponto(Icones.celularRiscado, t("Fora do backup do Google"), t("Num celular novo, só as palavras ou um envelope trazem a carteira de volta."))
            }
            if (erro != null) Faixa(TipoDeFaixa.falha, erro, Modifier.padding(top = Espaco.md))
        }
        Rodape {
            BotaoPrimario(t("Continuar"), acao = aoSeguir)
            BotaoTerciario(t("Prefiro escolher as minhas palavras"), Modifier.fillMaxWidth(), acao = aoEscolherAsPalavras)
        }
    }
}

/**
 * A folha de anotar as palavras: papel claro com as linhas numeradas, em duas colunas, preenchidas
 * uma a uma com um risco de letra a mao e o lapis correndo junto. Nenhuma palavra de verdade.
 */
@Composable
fun PapelRabiscado(palavras: Int, modifier: Modifier = Modifier, largura: androidx.compose.ui.unit.Dp = 270.dp, altura: androidx.compose.ui.unit.Dp = 178.dp) {
    val porLinha = if (palavras > 12) 0.16f else 0.3f
    val escrita = palavras * porLinha
    val periodo = escrita + 1.6f
    val tempo = remember(palavras) { Animatable(0f) }
    LaunchedEffect(palavras) {
        while (true) {
            tempo.snapTo(0f)
            tempo.animateTo(periodo, tween((periodo * 1000).toInt(), easing = LinearEasing))
        }
    }
    val t = tempo.value
    val apagando = ((t - escrita - 1.1f) / 0.4f).coerceIn(0f, 1f)
    Canvas(modifier.width(largura).height(altura).rotate(-2f).shadow(14.dp, RoundedCornerShape(10.dp), ambientColor = Color.Black, spotColor = Color.Black)) {
        drawRoundRect(Paleta.viva, cornerRadius = androidx.compose.ui.geometry.CornerRadius(10.dp.toPx()))
        val linhas = (palavras + 1) / 2
        val topo = 16.dp.toPx()
        val base = 12.dp.toPx()
        val alturaDaLinha = (size.height - topo - base) / linhas
        val coluna = (size.width - 24.dp.toPx()) / 2
        var lapis: Offset? = null
        for (indice in 0 until palavras) {
            val c = indice / linhas
            val l = indice % linhas
            val x = 14.dp.toPx() + c * (coluna + 4.dp.toPx())
            val linhaDeBase = topo + (l + 0.78f) * alturaDaLinha
            drawRect(Paleta.placaLinha, Offset(x + 20.dp.toPx(), linhaDeBase + 2.dp.toPx()), Size(coluna - 26.dp.toPx(), 0.8.dp.toPx()))
            drawContext.canvas.nativeCanvas.drawText(
                "${indice + 1}", x + 2.dp.toPx(), linhaDeBase - alturaDaLinha * 0.05f,
                android.graphics.Paint().apply {
                    color = android.graphics.Color.rgb(0x5C, 0x5C, 0x63); textSize = (if (palavras > 12) 7.5f else 9f) * density
                    isFakeBoldText = true; isAntiAlias = true
                },
            )
            val progresso = ((t - indice * porLinha) / porLinha).coerceIn(0f, 1f)
            if (progresso <= 0f) continue
            val comprimento = (coluna - 40.dp.toPx()) * (0.55f + 0.4f * ((indice * 37) % 10) / 10f)
            val caminho = Path()
            val passos = 28
            val feitos = (passos * progresso).toInt()
            var ultimo = Offset(x + 24.dp.toPx(), linhaDeBase - 2.dp.toPx())
            caminho.moveTo(ultimo.x, ultimo.y)
            for (passo in 0..feitos) {
                val u = passo / passos.toFloat()
                val onda = sin(u * 22.0 + indice) * 0.5 + sin(u * 9.0 + indice * 2) * 0.5
                ultimo = Offset(x + 24.dp.toPx() + comprimento * u, linhaDeBase - 2.dp.toPx() - (onda * alturaDaLinha * (if (palavras > 12) 0.16 else 0.2)).toFloat())
                caminho.lineTo(ultimo.x, ultimo.y)
            }
            drawPath(caminho, Paleta.placaTinta.copy(alpha = 0.85f * (1 - apagando)),
                     style = Stroke((if (palavras > 12) 1.1f else 1.5f) * density, cap = StrokeCap.Round, join = StrokeJoin.Round))
            if (progresso < 1f) lapis = ultimo
        }
        lapis?.takeIf { apagando == 0f }?.let { ponta ->
            // O lapis: um traco grosso inclinado com a ponta onde o risco esta.
            drawLine(Paleta.placaTinta, ponta + Offset(4.dp.toPx(), -4.dp.toPx()), ponta + Offset(14.dp.toPx(), -14.dp.toPx()), strokeWidth = 4.dp.toPx(), cap = StrokeCap.Round)
            drawLine(Paleta.placaTinta, ponta, ponta + Offset(4.dp.toPx(), -4.dp.toPx()), strokeWidth = 1.5.dp.toPx(), cap = StrokeCap.Round)
        }
    }
}

/**
 * Antes das palavras, ao criar e ao importar: o que muda numa carteira so do dono, e o aceite de
 * responsabilidade gravado nos metadados. Aparece toda vez, com a caixa desmarcada.
 */
@Composable
fun Responsabilidade(tituloDoSeguir: String, carregando: Boolean = false, aoSeguir: () -> Unit) {
    var aceito by remember { mutableStateOf(false) }
    var termos by remember { mutableStateOf(false) }
    val escopo = rememberCoroutineScope()
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(top = Espaco.xs, bottom = Espaco.xs)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Box(Modifier.size(60.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                    Icone(Icones.escudo, Paleta.tinta, tamanho = 28.dp)
                }
                Text(t("Só você tem a chave"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs))
                Text(t("A carteira é só sua. Por isso, o cuidado com ela também é."), style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
            }
            Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
                Ponto(Icones.celular, t("Criptografada, só neste celular"), t("Tudo da carteira é criptografado e fica guardado somente aqui."))
                Ponto(Icones.olhoRiscado, t("A Escalibur não tem acesso"), t("As chaves nunca saem deste celular. Ninguém da Escalibur consegue ver nem recuperar a sua carteira."))
                Ponto(Icones.chave, t("As palavras recuperam"), t("A senha da carteira, as 12 ou 24 palavras, é a única forma de trazer a carteira de volta."))
                Ponto(Icones.pessoas, t("Ninguém da Escalibur pede"), t("Nem por suporte, e-mail ou mensagem. Quem pedir as palavras quer o seu saldo."))
            }
            Aceite(aceito, t("Entendo que só eu guardo a senha desta carteira. Se eu perder a senha ou alguém tiver acesso a ela, a Escalibur não tem como recuperar meus ativos. Li e aceito os Termos de uso."),
                   Modifier.padding(top = Espaco.lg)) { aceito = it }
            Text(
                t("Ler os Termos de uso"), style = estilo(Tipo.nota).copy(fontWeight = FontWeight.SemiBold, textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline),
                color = Paleta.tintaApagada, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().heightIn(min = Altura.toque).clickable { termos = true }.padding(top = Espaco.sm),
            )
        }
        Rodape {
            BotaoPrimario(if (aceito) tituloDoSeguir else t("Marque o aceite para continuar"), ligado = aceito, carregando = carregando) {
                escopo.launch {
                    runCatching { App.aplicar(Api.objeto("sessao.aceitarResponsabilidade", JSONObject().put("versao", VERSAO_DO_ACEITE))) }
                    aoSeguir()
                }
            }
        }
    }
    if (termos) FolhaLegal(DocumentoLegal.termos) { termos = false }
}

/**
 * Gravar (e revelar): tres palavras por vez, num cartao claro sobre o baralho dos proximos. As
 * palavras somem quando o app sai da frente e depois de 60 s na tela, e voltam com um toque. So o
 * grupo na tela e os vizinhos viram texto; o resto fica no nucleo.
 */
@Composable
fun GravarPalavras(palavras: Int, nomeDaCarteira: String?, comPassphrase: Boolean = false, aoTerminar: () -> Unit) {
    val porGrupo = 3
    // A passphrase, quando a carteira tem, e o ultimo cartao.
    val grupoDaPassphrase = if (comPassphrase) palavras / porGrupo else -1
    val grupos = palavras / porGrupo + (if (comPassphrase) 1 else 0)
    var grupo by remember { mutableIntStateOf(0) }
    var escondidas by remember { mutableStateOf(false) }
    var todas by remember { mutableStateOf(false) }
    val mostradas = remember { mutableStateMapOf<Int, List<String>>() }
    val arrasto = remember { Animatable(0f) }
    val escopo = rememberCoroutineScope()
    val ultimo = todas || grupo == grupos - 1

    // No segundo plano, as palavras escondem; voltam com um toque.
    val dono = LocalLifecycleOwner.current
    DisposableEffect(dono) {
        val observador = LifecycleEventObserver { _, evento -> if (evento == Lifecycle.Event.ON_STOP) escondidas = true }
        dono.lifecycle.addObserver(observador)
        onDispose { dono.lifecycle.removeObserver(observador); mostradas.clear() }
    }
    // As mesmas palavras na tela por 60 s seguidos escondem sozinhas.
    LaunchedEffect(grupo, todas, escondidas) {
        if (!escondidas) { delay(60_000); escondidas = true }
    }
    LaunchedEffect(grupo, todas, escondidas) {
        if (escondidas) { mostradas.clear(); return@LaunchedEffect }
        val faixa = if (todas) 0 until grupos else maxOf(0, grupo - 1)..minOf(grupos - 1, grupo + 1)
        for (chave in mostradas.keys.toList()) if (chave !in faixa) mostradas.remove(chave)
        for (indice in faixa) {
            if (mostradas[indice] == null && indice == grupoDaPassphrase) {
                mostradas[indice] = listOfNotNull(runCatching { Api.objeto("carteira.passphraseDoRascunho").optString("passphrase", "").ifEmpty { null } }.getOrNull())
            } else if (mostradas[indice] == null) {
                val inicio = indice * porGrupo
                mostradas[indice] = runCatching {
                    Api.lista("carteira.palavras", JSONObject().put("de", inicio).put("ate", minOf(inicio + porGrupo, palavras))).let { lista ->
                        (0 until lista.length()).map { lista.getString(it) }
                    }
                }.getOrDefault(emptyList())
            }
        }
    }

    fun mover(delta: Int) {
        val alvo = (grupo + delta).coerceIn(0, grupos - 1)
        if (alvo == grupo) return
        escopo.launch {
            arrasto.animateTo(if (delta > 0) -600f else 600f, tween(160))
            grupo = alvo
            arrasto.snapTo(0f)
        }
    }

    Column(Modifier.fillMaxSize().padding(horizontal = Espaco.margem).padding(top = Espaco.md, bottom = Espaco.xs)) {
        Text(if (nomeDaCarteira == null) t("Grave a senha da carteira") else t("Senha da carteira"), style = estilo(Tipo.titulo), color = Paleta.tinta)
        val prefixo = nomeDaCarteira?.let { "$it · " } ?: ""
        Text(
            when {
                todas -> t("%@As %lld palavras, em ordem", prefixo, palavras)
                grupo == grupoDaPassphrase -> prefixo + t("Passphrase")
                else -> t("%@Palavras %lld a %lld de %lld", prefixo, grupo * porGrupo + 1, minOf(grupo * porGrupo + porGrupo, palavras), palavras)
            },
            style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xxs),
        )
        if (todas) {
            Box(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = Espaco.md)) {
                ChapaDeTodas(palavras, mostradas, escondidas, mostradas[grupoDaPassphrase]?.firstOrNull()) { escondidas = false }
            }
        } else {
            Box(
                Modifier.fillMaxWidth().padding(top = Espaco.lg).height(84.dp * porGrupo + 16.dp + 32.dp)
                    .pointerInput(grupo) {
                        detectHorizontalDragGestures(
                            onDragEnd = {
                                escopo.launch {
                                    when {
                                        arrasto.value < -70 && grupo < grupos - 1 -> mover(1)
                                        arrasto.value > 70 && grupo > 0 -> mover(-1)
                                        else -> arrasto.animateTo(0f, spring(dampingRatio = 0.75f))
                                    }
                                }
                            },
                        ) { _, delta -> escopo.launch { arrasto.snapTo(arrasto.value + delta) } }
                    },
            ) {
                // O baralho: os proximos atras, um pouco abaixo e menores, num cinza mais claro.
                for (profundidade in 2 downTo 0) {
                    val indice = grupo + profundidade
                    if (indice >= grupos) continue
                    val tons = listOf(Paleta.viva, Color(0xFFDADADF), Color(0xFFBEBEC4))
                    Box(
                        Modifier.fillMaxWidth().height(84.dp * porGrupo + 16.dp)
                            .graphicsLayer {
                                val escala = 1 - 0.06f * profundidade
                                scaleX = escala; scaleY = escala
                                transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 1f)
                                translationY = 10.dp.toPx() * profundidade
                                if (profundidade == 0) { translationX = arrasto.value; rotationZ = arrasto.value / 25f }
                            }
                            .shadow(if (profundidade == 0) 10.dp else 0.dp, RoundedCornerShape(16.dp))
                            .clip(RoundedCornerShape(16.dp)).background(tons[profundidade]),
                    ) {
                        if (profundidade == 0 && grupo == grupoDaPassphrase) {
                            CartaoDaPassphrase(mostradas[grupo]?.firstOrNull() ?: "", escondidas) { escondidas = false }
                        } else if (profundidade == 0) {
                            CartaoDePalavras(grupo * porGrupo, mostradas[grupo] ?: emptyList(), escondidas) { escondidas = false }
                        }
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(top = Espaco.md), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)) {
                repeat(grupos) { indice ->
                    val largura by animateDpAsState(if (indice == grupo) 18.dp else 6.dp, label = "grupo")
                    Box(Modifier.width(largura).height(6.dp).clip(CircleShape).background(if (indice == grupo) Paleta.acento else Paleta.bordaForte))
                }
            }
        }
        BotaoTerciario(if (todas) t("Ver três por vez") else t("Ver todas de uma vez"), Modifier.fillMaxWidth()) { todas = !todas }
        if (!todas) Spacer(Modifier.weight(1f))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            if (grupo > 0 && !todas) BotaoSecundario(t("Anteriores"), Modifier.weight(1f), altura = Altura.primaria) { mover(-1) }
            BotaoPrimario(
                if (ultimo) (if (nomeDaCarteira == null) t("Já anotei as %lld", palavras) else t("Fechar")) else t("Próximas"),
                Modifier.weight(1f),
            ) { if (ultimo) aoTerminar() else mover(1) }
        }
    }
}

@Composable
private fun CartaoDePalavras(inicio: Int, palavras: List<String>, escondidas: Boolean, aoMostrar: () -> Unit) {
    if (escondidas) {
        Column(Modifier.fillMaxSize().padding(Espaco.md), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Text(t("Escondidas para ninguém ler por cima do seu ombro."), style = estilo(Tipo.corpo), color = Paleta.placaTinta, textAlign = TextAlign.Center)
            Box(
                Modifier.padding(top = Espaco.sm).height(40.dp).clip(RoundedCornerShape(Raio.cartao)).border(1.5.dp, Paleta.placaTinta, RoundedCornerShape(Raio.cartao))
                    .clickable(onClick = aoMostrar).padding(horizontal = Espaco.md),
                contentAlignment = Alignment.Center,
            ) { Text(t("Mostrar de novo"), style = estilo(Tipo.acao), color = Paleta.placaTinta) }
        }
        return
    }
    Column(Modifier.fillMaxSize().padding(vertical = Espaco.xs)) {
        palavras.forEachIndexed { deslocamento, palavra ->
            Row(Modifier.fillMaxWidth().height(84.dp).padding(horizontal = Espaco.base), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espaco.md)) {
                Text("%02d".format(inicio + deslocamento + 1), color = Paleta.placaApagada, modifier = Modifier.width(34.dp),
                     style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"))
                Text(palavra, fontFamily = FontFamily.Monospace, fontSize = 30.sp, fontWeight = FontWeight.SemiBold, color = Paleta.placaTinta, maxLines = 1)
            }
            if (deslocamento < palavras.size - 1) Box(Modifier.fillMaxWidth().padding(start = Espaco.base).height(1.dp).background(Paleta.placaLinha))
        }
    }
}

/**
 * A passphrase inteira, sem cortar: o espaco aparece como ␣ e a contagem vem embaixo, porque um
 * espaco a mais ou um caractere que sumiu ja abre outra carteira.
 */
@Composable
private fun CartaoDaPassphrase(passphrase: String, escondidas: Boolean, aoMostrar: () -> Unit) {
    if (escondidas) {
        CartaoDePalavras(0, emptyList(), true, aoMostrar)
        return
    }
    Row(Modifier.fillMaxSize().padding(horizontal = Espaco.base, vertical = Espaco.md), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espaco.md)) {
        Text("Pass", color = Paleta.placaApagada, modifier = Modifier.width(44.dp), style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold))
        Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            Text(passphrase.replace(" ", "␣"), fontFamily = FontFamily.Monospace, fontSize = 26.sp, fontWeight = FontWeight.SemiBold, color = Paleta.placaTinta)
            Text(contagemDaPassphrase(passphrase), style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold), color = Paleta.placaApagada)
        }
    }
}

/** A contagem, e o aviso de que a quebra de linha da tela nao e caractere. */
fun contagemDaPassphrase(passphrase: String): String {
    val quantos = passphrase.codePointCount(0, passphrase.length)
    val contagem = if (passphrase.contains(" ")) t("%lld caracteres. ␣ é um espaço.", quantos) else t("%lld caracteres.", quantos)
    return if (quantos > 16) contagem + " " + t("A quebra de linha não é espaço.") else contagem
}

/** A frase inteira numa chapa clara, em duas colunas, em ordem de cima para baixo. */
@Composable
private fun ChapaDeTodas(palavras: Int, mostradas: Map<Int, List<String>>, escondidas: Boolean, passphrase: String? = null, aoMostrar: () -> Unit) {
    val todas = (0 until palavras / 3).flatMap { mostradas[it] ?: emptyList() }
    val metade = (palavras + 1) / 2
    Box(
        Modifier.fillMaxWidth().shadow(14.dp, RoundedCornerShape(16.dp)).clip(RoundedCornerShape(16.dp))
            .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color(0xFFE6E7EA), Color(0xFFB9BBC2)))).padding(Espaco.lg),
    ) {
        if (escondidas) {
            CartaoDePalavras(0, emptyList(), true, aoMostrar)
        } else Column {
            Row(horizontalArrangement = Arrangement.spacedBy(Espaco.md)) {
                for (coluna in 0..1) {
                    Column(Modifier.weight(1f)) {
                        for (indice in coluna * metade until minOf(palavras, (coluna + 1) * metade)) {
                            Row(Modifier.height(40.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                                Text("%02d".format(indice + 1), fontSize = 13.sp, fontWeight = FontWeight.Black, color = Color(0xFF55575E), modifier = Modifier.width(24.dp))
                                Text(todas.getOrElse(indice) { "" }, fontFamily = FontFamily.Monospace, fontSize = 19.sp, fontWeight = FontWeight.Bold, color = Color(0xFF2A2B30), maxLines = 1)
                            }
                        }
                    }
                }
            }
            if (passphrase != null) {
                Column(Modifier.padding(top = Espaco.sm), verticalArrangement = Arrangement.spacedBy(Espaco.xxs)) {
                    Box(Modifier.fillMaxWidth().height(1.5.dp).background(Color(0xFF9C9EA5)))
                    Row(Modifier.padding(top = Espaco.xs), horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                        Text("Pass", fontSize = 13.sp, fontWeight = FontWeight.Black, color = Color(0xFF55575E))
                        Text(passphrase.replace(" ", "␣"), fontFamily = FontFamily.Monospace, fontSize = 19.sp, fontWeight = FontWeight.Bold, color = Color(0xFF2A2B30))
                    }
                    Text(contagemDaPassphrase(passphrase), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFF55575E))
                }
            }
        }
    }
}

/** Conferir digitando 3 posicoes sorteadas, uma de cada terco da frase (quatro em 24 palavras). */
@Composable
fun ConferirPalavras(palavras: Int, aoVoltar: () -> Unit, aoDepois: (() -> Unit)?, aoConferir: () -> Unit) {
    val posicoes = remember {
        val partes = if (palavras == 24) 4 else 3
        val tamanho = palavras / partes
        val aleatorio = SecureRandom()
        (0 until partes).map { parte -> parte * tamanho + aleatorio.nextInt(tamanho) }
    }
    var atual by remember { mutableIntStateOf(0) }
    var erro by remember { mutableStateOf<String?>(null) }
    val erros = remember { mutableStateMapOf<Int, Int>() }
    val palavra = rememberPalavra()
    val escopo = rememberCoroutineScope()

    fun conferir() {
        val posicao = posicoes[atual]
        val digitada = palavra.texto
        escopo.launch {
            val confere = runCatching {
                Api.objeto("carteira.conferir", JSONObject().put("indice", posicao).put("palavra", digitada)).getBoolean("confere")
            }.getOrDefault(false)
            if (confere) {
                palavra.limpar()
                erro = null
                if (atual + 1 < posicoes.size) atual++ else aoConferir()
            } else {
                erros[posicao] = (erros[posicao] ?: 0) + 1
                erro = t("Não é a palavra %lld. Confira a posição %lld no seu papel.", posicao + 1, posicao + 1)
            }
        }
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(horizontal = Espaco.margem).padding(top = Espaco.md)) {
            Text(t("Confirme a senha da carteira"), style = estilo(Tipo.titulo), color = Paleta.tinta)
            Text(t("Digite a palavra %lld", posicoes[atual] + 1), style = estilo(Tipo.cabecalho), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
            Text(t("%lld de %lld", atual + 1, posicoes.size), style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.xxs))
            CampoDePalavra(palavra.texto, t("palavra %lld", posicoes[atual] + 1), ativo = true, modifier = Modifier.padding(top = Espaco.md))
            SugestoesDePalavra(if (palavra.texto.length >= 2) palavra.sugestoes.palavras else emptyList(), Modifier.padding(top = Espaco.sm)) {
                palavra.texto = it
                conferir()
            }
            erro?.let {
                Text(it, style = estilo(Tipo.nota), color = Paleta.baixa, modifier = Modifier.padding(top = Espaco.sm))
                if ((erros[posicoes[atual]] ?: 0) >= 2) BotaoTerciario(t("Ver as palavras de novo"), acao = aoVoltar)
            }
            Spacer(Modifier.weight(1f))
            if (aoDepois != null) BotaoTerciario(t("Anotar e confirmar depois"), Modifier.fillMaxWidth(), acao = aoDepois)
        }
        TecladoDePalavras(
            palavra.texto, letrasPossiveis = palavra.sugestoes.letras,
            aoDigitar = { if (palavra.texto.length < 8) palavra.texto += it },
            aoApagar = { palavra.texto = palavra.texto.dropLast(1) },
            aoSeguir = { conferir() }, tituloDoSeguir = t("Confirmar"),
        )
    }
}

/** Carteira criada, com nome editavel: o selo com as redes em volta, o check verde, o nome. */
@Composable
fun CarteiraCriada(carteira: Carteira, primeira: Boolean, aoTerminar: () -> Unit) {
    var nome by remember { mutableStateOf(carteira.nome) }
    val escopo = rememberCoroutineScope()
    val moedas = remember(carteira) {
        carteira.contas.mapNotNull { Redes.rede(it.first)?.coingecko }.distinct().take(12)
    }
    fun salvar(depois: () -> Unit = {}) {
        val limpo = nome.trim()
        escopo.launch {
            if (limpo.isNotEmpty() && limpo != carteira.nome) {
                runCatching { App.aplicar(Api.objeto("carteira.renomear", JSONObject().put("id", carteira.id).put("nome", limpo.take(40)))) }
            }
            depois()
        }
    }
    Column(Modifier.fillMaxSize().padding(horizontal = Espaco.margem).padding(top = Espaco.md, bottom = Espaco.xs), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        SeloComRedes(moedas)
        Text(t("Carteira criada"), style = estilo(Tipo.heroi), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.lg))
        Text(
            t("Endereços prontos em %lld redes. Guarde o papel longe do celular: se o celular sumir, o papel traz a carteira de volta, aqui ou em outros apps. O site da Escalibur, em Redes e moedas, diz quais.", carteira.contas.size),
            style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm),
        )
        Text(t("Nome da carteira"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.lg))
        BasicTextField(
            nome, { nome = it.take(40) }, singleLine = true,
            textStyle = estilo(Tipo.linha).copy(color = Paleta.tinta, textAlign = TextAlign.Center),
            cursorBrush = SolidColor(Paleta.acento),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { salvar() }),
            modifier = Modifier.padding(top = Espaco.xs).fillMaxWidth().height(Altura.campo).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
                .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(horizontal = Espaco.md, vertical = 13.dp),
        )
        Spacer(Modifier.weight(1f))
        BotaoPrimario(t("Ir para a carteira")) { salvar(aoTerminar) }
    }
}

@Composable
private fun SeloComRedes(moedas: List<String>) {
    var mostradas by remember { mutableIntStateOf(0) }
    var conferido by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(200)
        repeat(moedas.size) { mostradas++; delay(55) }
        delay(120)
        conferido = true
    }
    val giro = rememberInfiniteTransition(label = "anel")
    val volta by giro.animateFloat(0f, (2 * PI).toFloat(), infiniteRepeatable(tween(40_000, easing = LinearEasing)), label = "volta")
    Box(Modifier.size(220.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(176.dp)) { drawCircle(Paleta.borda, style = Stroke(1.dp.toPx())) }
        moedas.forEachIndexed { indice, id ->
            val angulo = indice.toDouble() / moedas.size * 2 * PI - PI / 2 + volta
            LogoDaMoeda(
                id, tamanho = 30.dp,
                modifier = Modifier.offset((88 * cos(angulo)).dp, (88 * sin(angulo)).dp)
                    .graphicsLayer { val e = if (mostradas > indice) 1f else 0.3f; scaleX = e; scaleY = e; alpha = if (mostradas > indice) 1f else 0f },
            )
        }
        SeloDaCarteira(84.dp)
        Box(
            Modifier.offset(33.dp, 33.dp).scale(if (conferido) 1f else 0.2f).size(30.dp).clip(CircleShape).background(Paleta.vazio).padding(3.dp)
                .clip(CircleShape).background(Paleta.sucesso),
            contentAlignment = Alignment.Center,
        ) { Icone(Icones.visto, Paleta.vazio, tamanho = 15.dp) }
    }
}

@Suppress("unused")
private val estiloMono = TextStyle(fontFamily = FontFamily.Monospace)

@Suppress("unused")
private fun IntOffset.metade() = IntOffset(x / 2, y / 2)
