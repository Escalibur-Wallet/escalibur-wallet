package app.escalibur.wallet.ui.comp

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalView
import android.view.View
import android.view.inputmethod.InputMethodManager
import androidx.compose.ui.platform.SoftwareKeyboardController
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.Dp
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import org.json.JSONArray
import org.json.JSONObject

/** As palavras da lista que comecam com o que foi digitado, e as letras que ainda levam a alguma. */
data class Sugestoes(val palavras: List<String>, val letras: Set<Char>) {
    companion object {
        /** `idiomas`: os das palavras ja fechadas da frase, quando ha. */
        suspend fun de(digitado: String, idiomas: JSONArray? = null): Sugestoes = runCatching {
            val corpo = JSONObject().put("digitado", digitado).put("limite", 4)
            idiomas?.let { corpo.put("idiomas", it) }
            val json = Api.objeto("carteira.sugestoes", corpo)
            val palavras = json.getJSONArray("palavras").let { lista -> (0 until lista.length()).map { lista.getString(it) } }
            val letras = json.getJSONArray("letras").let { lista -> (0 until lista.length()).mapNotNull { lista.getString(it).firstOrNull() }.toSet() }
            Sugestoes(palavras, letras)
        }.getOrDefault(Sugestoes(emptyList(), ('a'..'z').toSet()))
    }
}

/**
 * O campo de uma palavra, sem o teclado do sistema: mostra o que foi digitado no teclado proprio
 * (abaixo), em fonte de largura fixa, como na placa das palavras.
 */
@Composable
fun CampoDePalavra(texto: String, dica: String, ativo: Boolean, modifier: Modifier = Modifier, aoTocar: () -> Unit = {}) {
    val forma = RoundedCornerShape(Raio.cartao)
    Box(
        modifier.fillMaxWidth().height(56.dp).clip(forma).background(Paleta.corpo)
            .border(1.dp, if (ativo) Paleta.bordaForte else Paleta.borda, forma).clickable(onClick = aoTocar).padding(horizontal = Espaco.md),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (texto.isEmpty()) {
            Text(dica, style = estilo(Tipo.mono), color = Paleta.tintaApagada)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(texto, fontFamily = FontFamily.Monospace, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Paleta.tinta)
                if (ativo) Box(Modifier.padding(start = 2.dp).width(2.dp).height(22.dp).background(Paleta.acento))
            }
        }
    }
}

/** As sugestoes da palavra em digitacao, em chips. */
@Composable
fun SugestoesDePalavra(sugestoes: List<String>, modifier: Modifier = Modifier, aoEscolher: (String) -> Unit) {
    Row(modifier.fillMaxWidth().height(Altura.chip).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        for (palavra in sugestoes) Chip(palavra, selecionado = false) { aoEscolher(palavra) }
    }
}

/**
 * O teclado proprio das palavras (o WordKeyboard do iOS): so letras de a a z, apagar e seguir, sem
 * previsao, sem aprendizado e sem balao na tecla. So acendem as letras que ainda formam uma palavra da
 * lista, entao um erro de digitacao nem entra. Na ultima linha, o globo (onde a tela oferece o teclado
 * do celular), o nome do teclado (que abre a explicacao, onde a tela sabe abrir) e o Seguinte.
 * `demo`: a animacao dos Ajustes, sem toque e sem a faixa de navegacao, com `apertada` acesa.
 */
@Composable
fun TecladoDePalavras(
    digitado: String, modifier: Modifier = Modifier, letrasPossiveis: Set<Char>? = null,
    aoDigitar: (Char) -> Unit, aoApagar: () -> Unit, aoSeguir: () -> Unit = {}, tituloDoSeguir: String = t("Seguinte"),
    podeSeguir: Boolean = digitado.isNotEmpty(), aoLimpar: (() -> Unit)? = null, aoSistema: (() -> Unit)? = null, aoSobre: (() -> Unit)? = null,
    demo: Boolean = false, apertada: Char? = null,
) {
    val linhas = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
    val haptico = LocalHapticFeedback.current
    BoxWithConstraints(
        modifier.fillMaxWidth().background(Paleta.corpo).then(if (demo) Modifier else Modifier.navigationBarsPadding())
            .padding(horizontal = 3.dp).padding(top = 8.dp, bottom = 6.dp),
    ) {
        val espaco = 6.dp
        val unidade = (maxWidth - espaco * 9) / 10
        fun toque(acao: () -> Unit): () -> Unit = {
            if (!demo) {
                haptico.performHapticFeedback(HapticFeedbackType.KeyboardTap)
                acao()
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            for (indice in 0..1) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(espaco, Alignment.CenterHorizontally)) {
                    for (letra in linhas[indice]) {
                        TeclaDePalavra(unidade, letra.toString(), ligada = letrasPossiveis?.contains(letra) ?: true, forcada = apertada == letra, acao = toque { aoDigitar(letra) }) {
                            Text(letra.toString(), fontSize = 22.sp, color = it)
                        }
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(espaco)) {
                Spacer(Modifier.width(unidade * 1.4f))
                Spacer(Modifier.weight(1f))
                for (letra in linhas[2]) {
                    TeclaDePalavra(unidade, letra.toString(), ligada = letrasPossiveis?.contains(letra) ?: true, forcada = apertada == letra, acao = toque { aoDigitar(letra) }) {
                        Text(letra.toString(), fontSize = 22.sp, color = it)
                    }
                }
                Spacer(Modifier.weight(1f))
                // Segurar o apagar limpa a palavra inteira.
                TeclaDePalavra(unidade * 1.4f, t("Apagar"), ligada = digitado.isNotEmpty(), acao = toque(aoApagar), aoSegurar = aoLimpar?.let { toque(it) }) {
                    Icone(Icones.apagarLetra, it, tamanho = 20.dp)
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(espaco), verticalAlignment = Alignment.CenterVertically) {
                // O globo e o Seguinte com a mesma largura: o nome do teclado fica no centro.
                if (aoSistema != null) {
                    TeclaDePalavra(unidade * 2.5f, t("Usar o teclado do celular"), ligada = true, acao = toque(aoSistema)) {
                        Icone(Icones.globo, it, tamanho = 20.dp)
                    }
                } else {
                    Spacer(Modifier.width(unidade * 2.5f))
                }
                val sobre = t("Sobre o Safe Keyboard")
                Row(
                    Modifier.weight(1f).height(44.dp).then(if (aoSobre != null && !demo) Modifier.clickable(onClick = aoSobre) else Modifier)
                        .semantics { contentDescription = sobre },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
                ) {
                    Icone(Icones.cadeadoCheio, Paleta.tintaApagada, tamanho = 11.dp)
                    Text("Safe Keyboard", style = estilo(Tipo.nota), color = Paleta.tintaApagada, maxLines = 1, modifier = Modifier.padding(start = 6.dp))
                    if (aoSobre != null) Icone(Icones.info, Paleta.tintaApagada, tamanho = 12.dp, modifier = Modifier.padding(start = 6.dp))
                }
                TeclaDePalavra(unidade * 2.5f, tituloDoSeguir, ligada = podeSeguir, forte = true, acao = toque(aoSeguir)) {
                    Text(tituloDoSeguir, style = estilo(Tipo.acao), color = it, maxLines = 1)
                }
            }
        }
    }
}

/** A altura do teclado das palavras, sem a faixa de navegacao: 4 teclas de 44, 3 vaos de 10 e as bordas. */
val AlturaDoTecladoDePalavras = 44.dp * 4 + 10.dp * 3 + 8.dp + 6.dp

/** A tecla apertada so muda de tom: nada de balao com a letra em cima, que uma gravacao leria. */
@Composable
private fun TeclaDePalavra(
    largura: Dp, descricao: String, ligada: Boolean, forte: Boolean = false, forcada: Boolean = false,
    acao: () -> Unit, aoSegurar: (() -> Unit)? = null, conteudo: @Composable (Color) -> Unit,
) {
    val interacao = remember { MutableInteractionSource() }
    val apertada by interacao.collectIsPressedAsState()
    val fundo = when {
        forte && ligada -> if (apertada || forcada) Paleta.acentoApertado else Paleta.acento
        !ligada -> Paleta.trilho
        apertada || forcada -> Paleta.bordaForte
        else -> Paleta.controle
    }
    val cor = when {
        !ligada -> Paleta.tintaMorta
        forte -> Paleta.sobreAcento
        else -> Paleta.tinta
    }
    Box(
        Modifier.width(largura).height(44.dp).clip(RoundedCornerShape(8.dp)).background(fundo)
            .then(
                if (aoSegurar != null) Modifier.combinedClickable(interacao, indication = null, enabled = ligada, onLongClick = aoSegurar, onClick = acao)
                else Modifier.clickable(interacao, indication = null, enabled = ligada, onClick = acao)
            )
            .semantics { contentDescription = descricao },
        contentAlignment = Alignment.Center,
    ) { conteudo(cor) }
}

/**
 * As palavras pelo teclado do celular: com o Safe Keyboard desligado, ou pelo globo (frases em japones,
 * chines ou coreano, que o teclado proprio nao escreve). Um campo sem tamanho fica com o foco e recebe as
 * letras do teclado do celular, sem sugestao e sem aprendizado; a tela mostra o que foi digitado no campo
 * da palavra, como no teclado proprio. Ocupa o lugar do teclado: a altura do teclado do celular.
 * `todosOsIdiomas`: depois do globo, com a barra de candidatos que o japones e o chines pedem; antes, o
 * teclado de senha, so letras latinas e sem sugestao nenhuma (como o asciiCapable sem correcao do iOS).
 */
class TecladoDoCelular {
    internal val foco = FocusRequester()
    internal var controle: SoftwareKeyboardController? = null
    internal var vista: View? = null

    /**
     * De volta ao campo, com o teclado do celular aberto (o toque no campo da palavra). Fechado pelo
     * voltar, o campo continua com o foco e o pedido do Compose nao reabre: o pedido vai direto ao Android.
     */
    fun mostrar() {
        runCatching { foco.requestFocus() }
        controle?.show()
        vista?.let { v -> v.post { v.context.getSystemService(InputMethodManager::class.java)?.showSoftInput(v, 0) } }
    }
}

@Composable
fun PalavraPeloCelular(
    texto: String, aoMudar: (String) -> Unit, aoSeguir: () -> Unit, teclado: TecladoDoCelular,
    todosOsIdiomas: Boolean = false, limite: Int = 12,
) {
    teclado.controle = LocalSoftwareKeyboardController.current
    teclado.vista = LocalView.current
    var campo by remember { mutableStateOf(TextFieldValue(texto, TextRange(texto.length))) }
    LaunchedEffect(texto) { if (campo.text != texto) campo = TextFieldValue(texto, TextRange(texto.length)) }
    LaunchedEffect(todosOsIdiomas) { teclado.mostrar() }
    Box(Modifier.fillMaxWidth().windowInsetsBottomHeight(WindowInsets.ime.union(WindowInsets.navigationBars))) {
        TecladoSeguro.PeloCelular(palavras = true) {
            BasicTextField(
                campo, { novo ->
                    val limpo = novo.text.lowercase().filter { it.isLetter() }.take(limite)
                    campo = if (limpo == novo.text) novo else TextFieldValue(limpo, TextRange(limpo.length))
                    if (limpo != texto) aoMudar(limpo)
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false,
                    keyboardType = if (todosOsIdiomas) KeyboardType.Text else KeyboardType.Password, imeAction = ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(onNext = { aoSeguir() }),
                modifier = Modifier.size(1.dp).alpha(0f).focusRequester(teclado.foco),
            )
        }
    }
}

/**
 * O estado de uma palavra em digitacao no teclado proprio, com as sugestoes do nucleo. A resposta do
 * nucleo chega um instante depois de cada tecla: ate chegar a do texto atual, nenhuma letra fica
 * apagada (uma tecla certa tocada rapido nao se perde) e o Seguinte pergunta antes de fechar.
 */
class PalavraEmDigitacao {
    var texto by mutableStateOf("")
    var idiomas by mutableStateOf<JSONArray?>(null)
    private var resposta by mutableStateOf<Pair<String, Sugestoes>?>(null)

    /** As sugestoes do texto atual; de um texto anterior, nenhuma. */
    val sugestoes: Sugestoes
        get() = resposta?.takeIf { it.first == texto }?.second ?: Sugestoes(emptyList(), ('a'..'z').toSet())

    suspend fun atualizar() {
        val digitado = texto
        val nova = Sugestoes.de(digitado, idiomas)
        if (texto == digitado) resposta = digitado to nova
    }

    /** As sugestoes do texto atual, esperando a resposta se ela ainda nao veio. */
    suspend fun sugestoesAgora(): Sugestoes {
        resposta?.takeIf { it.first == texto }?.let { return it.second }
        val digitado = texto
        return Sugestoes.de(digitado, idiomas).also { if (texto == digitado) resposta = digitado to it }
    }

    fun limpar() {
        texto = ""
    }
}

@Composable
fun rememberPalavra(): PalavraEmDigitacao {
    val palavra = remember { PalavraEmDigitacao() }
    LaunchedEffect(palavra.texto, palavra.idiomas) { palavra.atualizar() }
    return palavra
}
