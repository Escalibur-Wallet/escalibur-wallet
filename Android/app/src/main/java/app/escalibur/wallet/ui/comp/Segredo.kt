package app.escalibur.wallet.ui.comp

import android.text.InputType
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedText
import android.view.inputmethod.ExtractedTextRequest
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusEventModifierNode
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.FocusState
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.KeyInputModifierNode
import androidx.compose.ui.node.CompositionLocalConsumerModifierNode
import androidx.compose.ui.node.ModifierNodeElement
import androidx.compose.ui.node.currentValueOf
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.PlatformTextInputMethodRequest
import androidx.compose.ui.platform.PlatformTextInputModifierNode
import androidx.compose.ui.platform.establishTextInputSession
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.password
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.tema.Paleta
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.nio.CharBuffer

/**
 * O segredo digitado (passphrase, senha do envelope), como o SecureInputField do iOS: cada tecla vira
 * bytes UTF-8 num buffer que o app zera, e a tela so mostra pontos. O TextFieldState do Compose guardava
 * o texto inteiro numa String a cada tecla, e o clearText nao apagava essas copias (revisao de
 * seguranca de 24/10/2026, M4). A conta e por escalar Unicode, como no iOS: o apagar tira o "ç" inteiro,
 * e nao so o ultimo byte dele.
 */
@Stable
class Segredo {
    private var buffer = ByteArray(64)
    private var usados = 0

    /** Quantos caracteres ha: o que a tela mostra, e o que se observa para saber o tamanho. */
    var tamanho by mutableIntStateOf(0)
        private set

    /** Um ponto por caractere: `text.isEmpty()` e `text.length` sem mostrar nada do segredo. */
    val text: CharSequence get() = Pontos(tamanho)

    /**
     * A metade alta de um par substituto que chegou sozinha: ha teclados que mandam o emoji em dois
     * pedacos. Ela espera a outra metade; uma metade que nunca forma par sai, em vez de derrubar o app
     * no codificador (caca de bugs de 25/10/2026).
     */
    private var metadeAlta: Char? = null

    fun acrescentar(texto: CharSequence) {
        if (texto.isEmpty()) return
        val letras = CharArray(texto.length + 1)
        var total = 0
        metadeAlta?.let { letras[total++] = it }
        metadeAlta = null
        for (i in texto.indices) letras[total++] = texto[i]
        if (Character.isHighSurrogate(letras[total - 1])) metadeAlta = letras[--total]
        // Uma metade de par sem a outra nao vira UTF-8, e o codificador do Android lanca mesmo
        // configurado para ignorar: ela sai aqui, antes.
        var limpos = 0
        var i = 0
        while (i < total) {
            val letra = letras[i]
            if (Character.isHighSurrogate(letra) && i + 1 < total && Character.isLowSurrogate(letras[i + 1])) {
                letras[limpos++] = letra
                letras[limpos++] = letras[i + 1]
                i += 2
            } else {
                if (!Character.isSurrogate(letra)) letras[limpos++] = letra
                i++
            }
        }
        val codificado = Charsets.UTF_8.newEncoder().encode(CharBuffer.wrap(letras, 0, limpos))
        letras.fill('\u0000')
        val n = codificado.remaining()
        if (usados + n > buffer.size) {
            val maior = ByteArray(maxOf(buffer.size * 2, usados + n))
            buffer.copyInto(maior, 0, 0, usados)
            buffer.fill(0)
            buffer = maior
        }
        codificado.get(buffer, usados, n)
        if (codificado.hasArray()) codificado.array().fill(0)
        usados += n
        tamanho = escalares()
    }

    /** Tira o ultimo caractere: volta pelos bytes de continuacao do UTF-8 (10xxxxxx) ate o inicio dele. */
    fun apagarUltimo() {
        metadeAlta = null
        if (usados == 0) return
        val inicio = inicioDoUltimo()
        buffer.fill(0, inicio, usados)
        usados = inicio
        tamanho = escalares()
    }

    /**
     * O apagar do teclado conta em unidades UTF-16: um emoji vale duas e sai inteiro uma vez so. Antes
     * cada unidade tirava um caractere, e apagar um emoji levava o de antes junto.
     */
    fun apagarUnidades(n: Int) {
        metadeAlta = null
        var faltam = n
        while (faltam > 0 && usados > 0) {
            val inicio = inicioDoUltimo()
            faltam -= if (usados - inicio == 4) 2 else 1
            buffer.fill(0, inicio, usados)
            usados = inicio
        }
        tamanho = escalares()
    }

    private fun inicioDoUltimo(): Int {
        var inicio = usados - 1
        while (inicio > 0 && buffer[inicio].toInt() and 0xC0 == 0x80) inicio--
        return inicio
    }

    fun clearText() {
        buffer.fill(0)
        usados = 0
        tamanho = 0
        metadeAlta = null
    }

    /** Uma copia dos bytes, para o nucleo. Quem chama zera. */
    fun bytes(): ByteArray = buffer.copyOf(usados)

    /** O texto, so enquanto o dono segura o dedo no campo: vira String para a tela desenhar, que e o preco de mostrar. */
    fun revelado(): String = String(buffer, 0, usados, Charsets.UTF_8)

    private fun escalares(): Int = (0 until usados).count { buffer[it].toInt() and 0xC0 != 0x80 }

    private class Pontos(override val length: Int) : CharSequence {
        override fun get(index: Int): Char = '•'
        override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = Pontos(endIndex - startIndex)
        override fun toString(): String = "•".repeat(length)
    }
}

/**
 * Onde se digita o segredo: o teclado (o Safe Keyboard ou o do celular) escreve pela conexao propria
 * deste campo, que manda cada tecla direto para o `Segredo`. Nada do que foi digitado volta para o
 * teclado: ele so ve um campo de senha vazio. `aoConcluir`: o "Ir" do teclado.
 */
@Composable
fun EntradaDeSegredo(
    segredo: Segredo, descricao: String, revelar: Boolean, estilo: TextStyle, foco: FocusRequester,
    modifier: Modifier = Modifier, aoConcluir: (() -> Unit)? = null,
) {
    var focado by remember { mutableStateOf(false) }
    Row(
        modifier.then(ElementoDoSegredo(segredo, aoConcluir)).focusRequester(foco).onFocusChanged { focado = it.isFocused }.focusable()
            .semantics { password(); contentDescription = descricao },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (segredo.tamanho > 0) Text(if (revelar) segredo.revelado() else segredo.text.toString(), style = estilo, maxLines = 1)
        if (focado) Box(Modifier.width(2.dp).height(20.dp).background(Paleta.acento))
    }
}

private data class ElementoDoSegredo(val segredo: Segredo, val aoConcluir: (() -> Unit)?) : ModifierNodeElement<NoDoSegredo>() {
    override fun create() = NoDoSegredo(segredo, aoConcluir)
    override fun update(node: NoDoSegredo) {
        node.segredo = segredo
        node.aoConcluir = aoConcluir
    }
}

/**
 * Com o foco, abre a sessao de texto do campo (o TecladoSeguro.Raiz decide qual teclado); sem ele, fecha.
 * As teclas de um teclado fisico nao passam pela conexao: chegam aqui, como evento de tecla.
 */
private class NoDoSegredo(segredo: Segredo, var aoConcluir: (() -> Unit)?) :
    Modifier.Node(), PlatformTextInputModifierNode, FocusEventModifierNode, CompositionLocalConsumerModifierNode,
    KeyInputModifierNode {
    private var sessao: Job? = null
    private val teclas = Teclas(segredo) { concluir() }
    var segredo: Segredo
        get() = teclas.segredo
        set(valor) { teclas.segredo = valor }

    override fun onKeyEvent(event: androidx.compose.ui.input.key.KeyEvent): Boolean = teclas.tecla(event.nativeKeyEvent)
    override fun onPreKeyEvent(event: androidx.compose.ui.input.key.KeyEvent): Boolean = false

    override fun onFocusEvent(focusState: FocusState) {
        if (focusState.isFocused) {
            if (sessao?.isActive == true) return
            val vista = currentValueOf(LocalView)
            sessao = coroutineScope.launch {
                establishTextInputSession {
                    startInputMethod(PlatformTextInputMethodRequest { info ->
                        info.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                        info.imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING or
                            EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN
                        info.initialSelStart = 0
                        info.initialSelEnd = 0
                        ConexaoDoSegredo(vista, segredo) { concluir() }
                    })
                }
            }
        } else {
            sessao?.cancel()
            sessao = null
        }
    }

    private fun concluir() {
        val acao = aoConcluir
        if (acao != null) acao() else currentValueOf(LocalFocusManager).clearFocus()
    }
}

/**
 * A conexao que o teclado usa. Cada texto que chega vai para o segredo; o que se pergunta de volta (o
 * texto antes do cursor, o texto extraido) e sempre vazio. O texto em composicao (teclados que montam a
 * palavra antes de confirmar) ja fica no segredo e e trocado a cada nova composicao.
 */
private class ConexaoDoSegredo(vista: View, private val segredo: Segredo, concluir: () -> Unit) : BaseInputConnection(vista, false) {
    /** Quantos caracteres do fim do segredo sao a composicao em andamento. */
    private var composicao = 0
    private val teclas = Teclas(segredo, concluir)

    private fun desfazerComposicao() {
        repeat(composicao) { segredo.apagarUltimo() }
        composicao = 0
    }

    override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
        desfazerComposicao()
        if (text != null) segredo.acrescentar(text)
        return true
    }

    override fun setComposingText(text: CharSequence?, newCursorPosition: Int): Boolean {
        desfazerComposicao()
        if (!text.isNullOrEmpty()) {
            segredo.acrescentar(text)
            composicao = Character.codePointCount(text, 0, text.length)
        }
        return true
    }

    override fun finishComposingText(): Boolean {
        composicao = 0
        return true
    }

    override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
        composicao = 0
        segredo.apagarUnidades(beforeLength)
        return true
    }

    override fun deleteSurroundingTextInCodePoints(beforeLength: Int, afterLength: Int): Boolean {
        composicao = 0
        repeat(beforeLength) { segredo.apagarUltimo() }
        return true
    }

    override fun sendKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_DEL) composicao = 0
        teclas.tecla(event)
        return true
    }

    override fun performEditorAction(editorAction: Int): Boolean {
        teclas.concluir()
        return true
    }

    override fun getTextBeforeCursor(n: Int, flags: Int): CharSequence = ""
    override fun getTextAfterCursor(n: Int, flags: Int): CharSequence = ""
    override fun getSelectedText(flags: Int): CharSequence? = null
    override fun getExtractedText(request: ExtractedTextRequest?, flags: Int): ExtractedText? = null
    override fun getCursorCapsMode(reqModes: Int): Int = 0
}

/**
 * Uma tecla de verdade (do teclado fisico, ou a que o teclado manda como tecla): apagar, Ir e cada
 * caractere, com o acento morto (´ e depois e vira é) como o Android compoe nos outros campos. Atalho
 * com Ctrl, setas e Tab ficam para o sistema.
 */
private class Teclas(var segredo: Segredo, val concluir: () -> Unit) {
    private var acento = 0

    fun tecla(evento: KeyEvent): Boolean {
        if (evento.action != KeyEvent.ACTION_DOWN) return false
        when (evento.keyCode) {
            KeyEvent.KEYCODE_DEL -> { acento = 0; segredo.apagarUltimo(); return true }
            KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> { concluir(); return true }
        }
        if (evento.isCtrlPressed || evento.isMetaPressed) return false
        val letra = evento.unicodeChar
        if (letra == 0) return false
        if (letra and KeyCharacterMap.COMBINING_ACCENT != 0) {
            acento = letra and KeyCharacterMap.COMBINING_ACCENT_MASK
            return true
        }
        if (Character.isISOControl(letra)) return false
        val antes = acento
        acento = 0
        if (antes != 0) {
            val composta = KeyCharacterMap.getDeadChar(antes, letra)
            if (composta != 0) {
                segredo.acrescentar(String(Character.toChars(composta)))
                return true
            }
            segredo.acrescentar(String(Character.toChars(antes)))
        }
        segredo.acrescentar(String(Character.toChars(letra)))
        return true
    }
}

/**
 * So para o build de depuracao (`adb ... --es teste segredo`): a conexao do teclado e o buffer,
 * tecla por tecla, como um teclado de verdade escreveria. Devolve "ok" ou o que falhou.
 */
fun provaDoSegredo(vista: View): String {
    val falhas = mutableListOf<String>()
    fun confere(nome: String, ok: Boolean) { if (!ok) falhas += nome }
    val s = Segredo()
    val c = ConexaoDoSegredo(vista, s) {}
    c.commitText("a", 1); c.commitText("ç", 1); c.commitText("😀", 1)
    confere("tres caracteres", s.tamanho == 3)
    confere("bytes em UTF-8", s.bytes().contentEquals("aç😀".toByteArray(Charsets.UTF_8)))
    c.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
    confere("apagar tira o emoji inteiro", s.bytes().contentEquals("aç".toByteArray(Charsets.UTF_8)))
    c.setComposingText("ab", 1); c.setComposingText("abc", 1); c.commitText("abc", 1)
    confere("composicao troca e confirma", s.revelado() == "açabc" && s.tamanho == 5)
    c.deleteSurroundingText(2, 0)
    confere("apagar ao redor", s.revelado() == "aça")
    c.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
    c.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
    confere("apagar o ç inteiro", s.revelado() == "a")
    confere("o teclado nao le nada de volta", c.getTextBeforeCursor(100, 0).isEmpty() && c.getExtractedText(null, 0) == null)
    confere("so pontos no texto", s.text.length == 1 && s.text.toString() == "•")
    c.commitText("😀", 1); c.deleteSurroundingText(2, 0)
    confere("apagar ao redor conta o emoji como duas unidades", s.revelado() == "a")
    c.commitText("\uD83D", 1)
    confere("meio emoji espera a outra metade", s.tamanho == 1)
    c.commitText("\uDE00", 1)
    confere("as duas metades formam o emoji", s.revelado() == "a😀" && s.tamanho == 2)
    c.commitText("\uDE00", 1); c.commitText("\uD83Db", 1)
    confere("metade sem par sai sem derrubar", s.revelado() == "a😀b")
    c.deleteSurroundingTextInCodePoints(2, 0)
    confere("apagar por escalar", s.revelado() == "a")
    val t = Teclas(s) {}
    confere("tecla fisica escreve", t.tecla(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_B)) && s.revelado() == "ab")
    confere("tab fica para o sistema", !t.tecla(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_TAB)))
    val ctrl = KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_V, 0, KeyEvent.META_CTRL_ON or KeyEvent.META_CTRL_LEFT_ON)
    confere("ctrl fica para o sistema", !t.tecla(ctrl) && s.revelado() == "ab")
    t.tecla(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
    confere("apagar fisico", s.revelado() == "a")
    repeat(200) { c.commitText("x", 1) }
    confere("cresce alem do buffer inicial", s.tamanho == 201)
    s.clearText()
    confere("zerado", s.tamanho == 0 && s.bytes().isEmpty() && s.text.isEmpty())
    return if (falhas.isEmpty()) "ok" else "falhou: " + falhas.joinToString()
}
