package app.escalibur.wallet.ui.comp

import android.text.InputType
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.InterceptPlatformTextInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.PlatformTextInputMethodRequest
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay

/**
 * O Safe Keyboard em todo campo de texto do app (o SafeTextKeyboard do iOS): com ele ligado em
 * Seguranca (ou no Super Security), o campo que abre o teclado abre o do app, e o teclado do celular
 * nem chega a ver o campo. As teclas escrevem pela conexao do proprio campo, como um teclado comum:
 * o campo filtra e reage do mesmo jeito. Letras, numeros, simbolos e acentos, ou so os algarismos nos
 * campos de valor. O globo devolve o teclado do celular so naquele campo, ate ele perder o foco.
 *
 * Desligado, todo campo abre o teclado do celular sem aprendizado (o modo anonimo do teclado): o que
 * se digita aqui nao vira sugestao nem vai para o dicionario do teclado, que pode ser de terceiros.
 */
/** O lugar do teclado na tela, o do celular ou o Safe Keyboard: o imePadding que vale para os dois. */
@Composable
fun Modifier.acimaDoTeclado(): Modifier = windowInsetsPadding(WindowInsets.ime.union(WindowInsets(bottom = TecladoSeguro.altura)))

object TecladoSeguro {
    enum class Layout { texto, decimal, algarismos }

    /** `janela`: o campo esta numa janela propria (o alerta de renomear), que mostra o teclado nela. */
    class Sessao(val layout: Layout, val conexao: InputConnection, val info: EditorInfo, val janela: Any?) {
        /** O globo: o teclado do celular neste campo. */
        val pediuOSistema = CompletableDeferred<Unit>()
    }

    var sessao by mutableStateOf<Sessao?>(null)
        private set

    /** Os campos que trazem o proprio teclado do celular (as palavras com o globo) passam direto. */
    class PedidoDoSistema(val pedido: PlatformTextInputMethodRequest, val palavras: Boolean) : PlatformTextInputMethodRequest by pedido

    /** Um campo de outra janela: o teclado aparece nela, nao na da tela. */
    private class PedidoDaJanela(val pedido: PlatformTextInputMethodRequest, val janela: Any) : PlatformTextInputMethodRequest by pedido

    /**
     * O conteudo de uma janela propria (o Dialog do alerta): com o Safe Keyboard num campo dela, a janela
     * ocupa a tela, o conteudo fica no meio do espaco acima do teclado, e o teclado no fim dela.
     */
    @OptIn(ExperimentalComposeUiApi::class)
    @Composable
    fun NaJanela(conteudo: @Composable () -> Unit) {
        val janela = remember { Any() }
        val atual = sessao?.takeIf { it.janela === janela }
        var alturaAqui by remember { mutableStateOf(0.dp) }
        val densidade = LocalDensity.current
        Box(if (atual != null) Modifier.fillMaxSize() else Modifier, contentAlignment = Alignment.Center) {
            Box(Modifier.padding(bottom = if (atual != null) alturaAqui else 0.dp)) {
                InterceptPlatformTextInput(interceptor = { pedido, proximo -> proximo.startInputMethod(PedidoDaJanela(pedido, janela)) }, content = conteudo)
            }
            if (atual != null) Painel(atual, Modifier.align(Alignment.BottomCenter).onSizeChanged { alturaAqui = with(densidade) { it.height.toDp() } })
        }
    }

    /**
     * O campo dentro vai sempre pelo teclado do celular, sem aprendizado. `palavras`: tambem sem
     * sugestao, que mostraria a palavra da carteira na barra do teclado.
     */
    @OptIn(ExperimentalComposeUiApi::class)
    @Composable
    fun PeloCelular(palavras: Boolean, conteudo: @Composable () -> Unit) {
        InterceptPlatformTextInput(interceptor = { pedido, proximo -> proximo.startInputMethod(PedidoDoSistema(pedido, palavras)) }, content = conteudo)
    }

    private fun layout(info: EditorInfo): Layout = when (info.inputType and InputType.TYPE_MASK_CLASS) {
        InputType.TYPE_CLASS_NUMBER -> if (info.inputType and InputType.TYPE_NUMBER_FLAG_DECIMAL != 0) Layout.decimal else Layout.algarismos
        InputType.TYPE_CLASS_PHONE -> Layout.algarismos
        else -> Layout.texto
    }

    /** A altura do Safe Keyboard na tela agora (com a faixa de navegacao); zero, fechado. */
    var altura by mutableStateOf(0.dp)
        private set

    /** O globo foi tocado: o teclado do celular sobe no campo, com a conexao nova dele. */
    private var pedidosDoCelular by mutableIntStateOf(0)

    /**
     * O teclado fica por cima de tudo no fim da tela, como o do celular: cobre a barra de abas, e as telas
     * que sobem com o teclado (`acimaDoTeclado`) sobem com ele tambem.
     */
    @OptIn(ExperimentalComposeUiApi::class)
    @Composable
    fun Raiz(conteudo: @Composable () -> Unit) {
        val atual = sessao
        val vista = LocalView.current
        LaunchedEffect(pedidosDoCelular) {
            if (pedidosDoCelular == 0) return@LaunchedEffect
            delay(150)
            vista.context.getSystemService(InputMethodManager::class.java)?.showSoftInput(vista, 0)
        }
        Box(Modifier.fillMaxSize().background(Paleta.vazio)) {
            InterceptPlatformTextInput(
                interceptor = { pedido, proximo ->
                    var original = pedido
                    var sistema: PedidoDoSistema? = null
                    var janela: Any? = null
                    while (true) {
                        original = when (original) {
                            is PedidoDoSistema -> original.also { sistema = it }.pedido
                            is PedidoDaJanela -> original.also { janela = it.janela }.pedido
                            else -> break
                        }
                    }
                    val semAprendizado = PlatformTextInputMethodRequest { atributos ->
                        val conexao = original.createInputConnection(atributos)
                        atributos.imeOptions = atributos.imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
                        if (sistema?.palavras == true) atributos.inputType = atributos.inputType or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                        conexao
                    }
                    if (sistema != null || !App.estado.tecladoProprio) proximo.startInputMethod(semAprendizado)
                    val info = EditorInfo()
                    val conexao = original.createInputConnection(info)
                    val nova = Sessao(layout(info), conexao, info, janela)
                    sessao = nova
                    try {
                        nova.pediuOSistema.await()
                    } finally {
                        if (sessao === nova) sessao = null
                    }
                    pedidosDoCelular++
                    proximo.startInputMethod(semAprendizado)
                },
                content = conteudo,
            )
            if (atual != null && atual.janela == null) {
                val densidade = LocalDensity.current
                Painel(atual, Modifier.align(Alignment.BottomCenter).onSizeChanged { altura = with(densidade) { it.height.toDp() } })
                DisposableEffect(Unit) { onDispose { altura = 0.dp } }
            }
        }
    }

    @Composable
    private fun Painel(sessao: Sessao, modifier: Modifier) {
        val foco = LocalFocusManager.current
        BackHandler { foco.clearFocus() }
        val modelo = remember(sessao) { Modelo(sessao, fechar = { foco.clearFocus() }, sistema = { sessao.pediuOSistema.complete(Unit) }) }
        Column(modifier.fillMaxWidth().seguraToques().background(Paleta.corpo).navigationBarsPadding()) {
            if (sessao.layout == Layout.texto) Barra(modelo)
            BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = 3.dp).padding(top = 8.dp, bottom = 6.dp)) {
                val espaco = 6.dp
                val unidade = (maxWidth - espaco * 9) / 10
                when (sessao.layout) {
                    Layout.texto -> Texto(modelo, unidade, espaco)
                    else -> Numeros(modelo, maxWidth, espaco)
                }
            }
        }
    }

    private class Modelo(val sessao: Sessao, val fechar: () -> Unit, val sistema: () -> Unit) {
        enum class Pagina { letras, numeros, simbolos, acentos }

        var pagina by mutableStateOf(Pagina.letras)
        var maiuscula by mutableStateOf(false)
        /** O globo; fora no Super Security. */
        val ofereceOSistema get() = !App.estado.reforcado

        fun digitar(texto: String) {
            sessao.conexao.commitText(texto, 1)
            // Maiuscula vale para uma letra, como no do celular.
            if (maiuscula && (pagina == Pagina.letras || pagina == Pagina.acentos)) maiuscula = false
        }

        /** O apagar do teclado: a selecao inteira, ou o caractere antes do cursor. */
        fun apagar() {
            sessao.conexao.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
            sessao.conexao.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
        }

        /** O "Ir": a acao do campo (seguir, enviar, pronto); no de varias linhas, a quebra de linha. */
        fun ir() {
            val info = sessao.info
            val acao = info.imeOptions and EditorInfo.IME_MASK_ACTION
            val varias = info.inputType and InputType.TYPE_TEXT_FLAG_MULTI_LINE != 0
            if (varias && (acao == EditorInfo.IME_ACTION_UNSPECIFIED || acao == EditorInfo.IME_ACTION_NONE)) sessao.conexao.commitText("\n", 1)
            else if (acao == EditorInfo.IME_ACTION_UNSPECIFIED || acao == EditorInfo.IME_ACTION_NONE) fechar()
            else sessao.conexao.performEditorAction(acao)
        }
    }

    private val letras = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm").map { linha -> linha.map(Char::toString) }
    private val numeros = listOf(
        "1234567890".map(Char::toString), listOf("-", "/", ":", ";", "(", ")", "$", "&", "@", "\""), listOf(".", ",", "?", "!", "'"),
    )
    private val simbolos = listOf(
        listOf("[", "]", "{", "}", "#", "%", "^", "*", "+", "="), listOf("_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"), listOf(".", ",", "?", "!", "'"),
    )
    private val acentos = listOf(
        listOf("á", "à", "â", "ã", "ä", "é", "è", "ê", "ë", "í"), listOf("ì", "î", "ï", "ó", "ò", "ô", "õ", "ö", "ú"), listOf("ù", "û", "ü", "ç", "ñ", "ý", "ÿ"),
    )

    /** A barra do alto no teclado de texto: o nome do teclado e o "Pronto". Nada de sugestao: ela mostraria a senha. */
    @Composable
    private fun Barra(modelo: Modelo) {
        Row(Modifier.fillMaxWidth().height(44.dp).padding(start = Espaco.md, end = Espaco.xs), verticalAlignment = Alignment.CenterVertically) {
            Icone(Icones.cadeadoCheio, Paleta.tintaApagada, tamanho = 11.dp)
            Text("Safe Keyboard", style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(start = 6.dp))
            Spacer(Modifier.weight(1f))
            val descricao = t("Fechar o teclado")
            Box(
                Modifier.height(44.dp).clickable(onClick = modelo.fechar).semantics { contentDescription = descricao }.padding(horizontal = Espaco.sm),
                contentAlignment = Alignment.Center,
            ) {
                Text(t("Pronto"), style = estilo(Tipo.acao), color = Paleta.tinta)
            }
        }
    }

    @Composable
    private fun Texto(modelo: Modelo, unidade: Dp, espaco: Dp) {
        val linhas = when (modelo.pagina) {
            Modelo.Pagina.letras -> letras
            Modelo.Pagina.numeros -> numeros
            Modelo.Pagina.simbolos -> simbolos
            Modelo.Pagina.acentos -> acentos
        }
        val deLetras = modelo.pagina == Modelo.Pagina.letras || modelo.pagina == Modelo.Pagina.acentos
        val alta = modelo.maiuscula && deLetras
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            for (indice in 0..1) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(espaco, Alignment.CenterHorizontally)) {
                    for (c in linhas[indice]) Caractere(modelo, c, alta, unidade)
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(espaco)) {
                when (modelo.pagina) {
                    Modelo.Pagina.letras, Modelo.Pagina.acentos ->
                        Tecla(unidade * 1.4f, t("Maiúscula"), selecionada = modelo.maiuscula, acao = { modelo.maiuscula = !modelo.maiuscula }) {
                            Icone(if (modelo.maiuscula) Icones.maiusculaCheia else Icones.maiuscula, Paleta.tinta, tamanho = 20.dp)
                        }
                    Modelo.Pagina.numeros -> Tecla(unidade * 1.4f, t("Símbolos"), acao = { modelo.pagina = Modelo.Pagina.simbolos }) { Rotulo("#+=") }
                    Modelo.Pagina.simbolos -> Tecla(unidade * 1.4f, t("Números"), acao = { modelo.pagina = Modelo.Pagina.numeros }) { Rotulo("123") }
                }
                Spacer(Modifier.weight(1f))
                for (c in linhas[2]) Caractere(modelo, c, alta, if (deLetras) unidade else unidade * 1.3f)
                Spacer(Modifier.weight(1f))
                Tecla(unidade * 1.4f, t("Apagar"), acao = modelo::apagar) { Icone(Icones.apagarLetra, Paleta.tinta, tamanho = 20.dp) }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(espaco)) {
                val emLetras = modelo.pagina == Modelo.Pagina.letras
                Tecla(unidade * 1.5f, if (emLetras) t("Números") else t("Letras"), acao = {
                    modelo.pagina = if (emLetras) Modelo.Pagina.numeros else Modelo.Pagina.letras
                }) { Rotulo(if (emLetras) "123" else "ABC") }
                Tecla(unidade * 1.2f, t("Acentos"), selecionada = modelo.pagina == Modelo.Pagina.acentos, acao = {
                    modelo.pagina = if (modelo.pagina == Modelo.Pagina.acentos) Modelo.Pagina.letras else Modelo.Pagina.acentos
                }) { Rotulo("áé") }
                Tecla(null, t("Espaço"), Modifier.weight(1f), acao = { modelo.digitar(" ") }) {
                    Text(t("espaço"), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                }
                if (modelo.ofereceOSistema) {
                    Tecla(unidade * 1.2f, t("Usar o teclado do celular"), acao = modelo.sistema) { Icone(Icones.globo, Paleta.tinta, tamanho = 19.dp) }
                }
                Tecla(unidade * 1.7f, t("Ir"), forte = true, acao = modelo::ir) { Icone(Icones.retorno, Paleta.sobreAcento, tamanho = 19.dp) }
            }
        }
    }

    @Composable
    private fun Caractere(modelo: Modelo, valor: String, alta: Boolean, largura: Dp) {
        val mostrado = if (alta) valor.uppercase() else valor
        Tecla(largura, mostrado, acao = { modelo.digitar(mostrado) }) {
            Text(mostrado, fontSize = 22.sp, color = Paleta.tinta)
        }
    }

    @Composable
    private fun Rotulo(texto: String) {
        Text(texto, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Paleta.tinta)
    }

    @Composable
    private fun Numeros(modelo: Modelo, largura: Dp, espaco: Dp) {
        val coluna = (largura - espaco * 2) / 3
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            for (linha in listOf("123", "456", "789")) {
                Row(horizontalArrangement = Arrangement.spacedBy(espaco)) {
                    for (d in linha) Tecla(coluna, d.toString(), acao = { modelo.digitar(d.toString()) }) { Text(d.toString(), fontSize = 24.sp, color = Paleta.tinta) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(espaco)) {
                if (modelo.sessao.layout == Layout.decimal) {
                    val decimal = Formato.decimal
                    Tecla(coluna, decimal, acao = { modelo.digitar(decimal) }) { Text(decimal, fontSize = 24.sp, color = Paleta.tinta) }
                } else {
                    Tecla(coluna, t("Fechar o teclado"), acao = modelo.fechar) { Icone(Icones.fecharTeclado, Paleta.tinta, tamanho = 20.dp) }
                }
                Tecla(coluna, "0", acao = { modelo.digitar("0") }) { Text("0", fontSize = 24.sp, color = Paleta.tinta) }
                Tecla(coluna, t("Apagar"), acao = modelo::apagar) { Icone(Icones.apagarLetra, Paleta.tinta, tamanho = 20.dp) }
            }
        }
    }

    /** A tecla apertada so muda de tom, sem o balao com a letra em cima. */
    @Composable
    private fun Tecla(
        largura: Dp?, descricao: String, modifier: Modifier = Modifier, forte: Boolean = false, selecionada: Boolean = false,
        acao: () -> Unit, conteudo: @Composable () -> Unit,
    ) {
        val interacao = remember { MutableInteractionSource() }
        val apertada by interacao.collectIsPressedAsState()
        val haptico = LocalHapticFeedback.current
        Box(
            modifier.then(if (largura != null) Modifier.width(largura) else Modifier).height(44.dp).clip(RoundedCornerShape(8.dp))
                .background(
                    when {
                        forte -> if (apertada) Paleta.acentoApertado else Paleta.acento
                        apertada || selecionada -> Paleta.bordaForte
                        else -> Paleta.controle
                    }
                )
                .clickable(interacao, indication = null) {
                    haptico.performHapticFeedback(HapticFeedbackType.KeyboardTap)
                    acao()
                }
                .semantics { contentDescription = descricao },
            contentAlignment = Alignment.Center,
        ) { conteudo() }
    }
}
