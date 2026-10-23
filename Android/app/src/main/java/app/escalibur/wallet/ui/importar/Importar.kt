package app.escalibur.wallet.ui.importar

import app.escalibur.wallet.ui.comp.EmblemaCifrado
import app.escalibur.wallet.ui.comp.Interruptor
import android.content.ClipboardManager
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import app.escalibur.wallet.ui.comp.acimaDoTeclado
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicSecureTextField
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.TextObfuscationMode
import androidx.compose.foundation.text.input.clearText
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Textos
import app.escalibur.wallet.ui.carteira.OrbitaDeMoedas
import app.escalibur.wallet.ui.carteira.Redes
import app.escalibur.wallet.ui.comp.Aceite
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Confirmacao
import app.escalibur.wallet.ui.comp.EnderecoEmBlocos
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.comp.Segmentado
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.SugestoesDePalavra
import app.escalibur.wallet.ui.ajustes.FolhaDoSafeKeyboard
import app.escalibur.wallet.ui.comp.PalavraPeloCelular
import app.escalibur.wallet.ui.comp.TecladoDePalavras
import app.escalibur.wallet.ui.comp.TecladoDoCelular
import app.escalibur.wallet.ui.principal.Navegacao
import androidx.compose.ui.semantics.Role
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.Vidros
import app.escalibur.wallet.ui.comp.vidro
import app.escalibur.wallet.ui.comp.rememberPalavra
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.novacarteira.Responsabilidade
import app.escalibur.wallet.ui.novacarteira.VerificacaoDoAparelho
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.receber.opcional
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.text.Normalizer

/**
 * As palavras em digitacao, uma por posicao, cada uma em bytes que o app zera (o PhraseEntry do
 * iOS). Na tela, cada palavra fechada aparece em pontos; segurar mostra.
 */
class EntradaDaFrase(quantas: Int = 12) {
    private var posicoes: MutableList<ByteArray?> = MutableList(quantas) { null }
    var quantidade by mutableIntStateOf(quantas)
        private set
    var ativa by mutableIntStateOf(0)
    /** Os bytes mudam sem o Compose ver: a revisao avisa as telas. */
    var revisao by mutableIntStateOf(0)
        private set

    fun mudarQuantidade(nova: Int) {
        while (posicoes.size < nova) posicoes.add(null)
        while (posicoes.size > nova) posicoes.removeAt(posicoes.lastIndex)?.fill(0)
        quantidade = nova
        ativa = minOf(ativa, nova - 1)
        revisao++
    }

    /** A palavra em NFKD minuscula, como a lista; a maior das listas cabe em 48 bytes. */
    fun definir(palavra: String, indice: Int) {
        posicoes[indice]?.fill(0)
        val bytes = Normalizer.normalize(palavra.trim().lowercase(), Normalizer.Form.NFKD).toByteArray(Charsets.UTF_8)
        posicoes[indice] = bytes.copyOf(minOf(bytes.size, 48))
        bytes.fill(0)
        revisao++
    }

    fun limpar(indice: Int) {
        posicoes[indice]?.fill(0)
        posicoes[indice] = null
        revisao++
    }

    fun preenchida(indice: Int): Boolean = posicoes.getOrNull(indice) != null

    /** As posicoes em que a palavra (em bytes, da lista) esta, sem virar a frase em texto. */
    fun lugares(palavra: ByteArray): List<Int> = posicoes.indices.filter { posicoes[it]?.contentEquals(palavra) == true }
    val preenchidas: Int get() = posicoes.count { it != null }

    /** Quantas letras tem a palavra (os pontos da tela). */
    fun letras(indice: Int): Int = posicoes.getOrNull(indice)?.let { String(it, Charsets.UTF_8).length } ?: 0

    /** So para mostrar enquanto o dono segura a posicao. */
    fun texto(indice: Int): String = posicoes.getOrNull(indice)?.let { String(it, Charsets.UTF_8) } ?: ""

    /** Distribui uma frase colada. Com uma contagem que nao e de frase, nada entra. */
    fun colar(texto: String): Int {
        val palavras = texto.split(Regex("[\\s,;]+")).filter { it.isNotBlank() }
        if (palavras.size !in TAMANHOS) return palavras.size
        mudarQuantidade(palavras.size)
        palavras.forEachIndexed { indice, palavra -> definir(palavra, indice) }
        ativa = palavras.size - 1
        return palavras.size
    }

    /** A frase inteira, palavras separadas por espaco. Quem chama zera. */
    fun frase(semAtiva: Boolean = false): ByteArray {
        val partes = posicoes.withIndex().filter { (indice, bytes) -> bytes != null && !(semAtiva && indice == ativa) }.map { it.value!! }
        val saida = ByteArray(partes.sumOf { it.size } + maxOf(0, partes.size - 1))
        var posicao = 0
        partes.forEachIndexed { indice, bytes ->
            if (indice > 0) saida[posicao++] = ' '.code.toByte()
            bytes.copyInto(saida, posicao)
            posicao += bytes.size
        }
        return saida
    }

    fun zerar() {
        posicoes.forEach { it?.fill(0) }
        posicoes = MutableList(quantidade) { null }
        ativa = 0
        revisao++
    }

    companion object {
        val TAMANHOS = listOf(12, 15, 18, 21, 24)
    }
}

/** Os bytes de uma passphrase digitada, sem passar por String. Quem chama zera. */
fun TextFieldState.bytes(): ByteArray {
    val buffer = Charsets.UTF_8.encode(java.nio.CharBuffer.wrap(text))
    val saida = ByteArray(buffer.remaining()).also { buffer.get(it) }
    if (buffer.hasArray()) buffer.array().fill(0)
    return saida
}

/** Importar com a senha da carteira: o aceite, a checagem do aparelho, as palavras e a conferencia
 * (a ordem do AddWalletView do iOS). */
@Composable
fun FluxoDeImportar(aoCancelar: () -> Unit, aoTerminar: () -> Unit) {
    var etapa by remember { mutableStateOf("aceite") }
    val entrada = remember { EntradaDaFrase() }
    val passphrase = remember { TextFieldState() }
    val repeticao = remember { TextFieldState() }
    var usaPassphrase by remember { mutableStateOf(false) }
    var previa by remember { mutableStateOf<JSONObject?>(null) }
    DisposableEffect(Unit) {
        onDispose {
            entrada.zerar()
            passphrase.clearText()
            repeticao.clearText()
        }
    }
    Box(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
        when (etapa) {
            "aceite" -> {
                BackHandler(onBack = aoCancelar)
                Column(Modifier.fillMaxSize()) {
                    CabecalhoDeFolha("", aoCancelar)
                    Responsabilidade(t("Conferir o aparelho")) { etapa = "checagem" }
                }
            }
            "checagem" -> {
                BackHandler { etapa = "aceite" }
                Column(Modifier.fillMaxSize()) {
                    CabecalhoDeFolha("", aoCancelar)
                    VerificacaoDoAparelho(t("Deslize para digitar as palavras"), criando = false) { etapa = "frase" }
                }
            }
            "frase" -> TelaDaFrase(entrada, passphrase, repeticao, usaPassphrase, { usaPassphrase = it }, aoCancelar) { conferida ->
                previa = conferida
                etapa = "previa"
            }
            "previa" -> previa?.let { dados ->
                PreviaDaImportacao(dados, entrada, if (usaPassphrase) passphrase else null, aoVoltar = { etapa = "frase" }, aoGuardar = aoTerminar)
            }
        }
    }
}

/**
 * A tela das palavras. `escolhendo` (12 ou 24): criar uma carteira com as palavras do dono, todas
 * menos a ultima, que o app sorteia para a conta da frase fechar; `aoEscolher` recebe as primeiras
 * (em bytes que zera) e devolve o erro para mostrar, ou nil.
 */
@Composable
internal fun TelaDaFrase(
    entrada: EntradaDaFrase, passphrase: TextFieldState, repeticao: TextFieldState, usaPassphrase: Boolean,
    aoMudarPassphrase: (Boolean) -> Unit, aoCancelar: () -> Unit, escolhendo: Int? = null,
    aoEscolher: (suspend (ByteArray) -> String?)? = null, conferindo: String? = null,
    aoConferirCopia: (suspend (frase: ByteArray, passphrase: ByteArray?) -> String?)? = null, aoConferir: (JSONObject) -> Unit,
) {
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    val palavra = rememberPalavra()
    var digitando by remember { mutableStateOf(false) }
    var mensagem by remember { mutableStateOf<String?>(null) }
    var colado by remember { mutableStateOf(false) }
    var trabalhando by remember { mutableStateOf(false) }
    var confirmarLimpar by remember { mutableStateOf(false) }
    var mostrar by remember { mutableStateOf(false) }
    var maisTamanhos by remember { mutableStateOf(false) }
    var outroTamanho by remember { mutableIntStateOf(12) }
    val revisao = entrada.revisao
    // O teclado das palavras (o ImportPhraseView do iOS): o Safe Keyboard com o ajuste ligado, na
    // primeira carteira e na conferencia da copia; o globo troca pelo do celular nesta tela, para as
    // frases em japones, chines ou coreano. No Super Security, nunca.
    var peloCelular by remember { mutableStateOf(false) }
    var confirmarCelular by remember { mutableStateOf(false) }
    val reforcado = App.estado.reforcado
    val proprio = (App.estado.tecladoProprio || conferindo != null || App.estado.carteiras.isEmpty()) && (!peloCelular || reforcado)
    val celular = remember { TecladoDoCelular() }

    // Sem internet enquanto as palavras estao na tela: a conferencia e toda local.
    DisposableEffect(Unit) {
        escopo.launch { runCatching { Api.objeto("rede.silencio", JSONObject().put("ligar", true)) } }
        onDispose { CoroutineScope(Dispatchers.IO).launch { runCatching { Api.objeto("rede.silencio", JSONObject().put("ligar", false)) } } }
    }
    // Os idiomas das palavras ja fechadas, fora a posicao em digitacao: as sugestoes seguem eles.
    // Escolhendo, so a lista em ingles: a frase gerada e so em ingles.
    LaunchedEffect(revisao, entrada.ativa) {
        palavra.idiomas = if (escolhendo != null) org.json.JSONArray().put("english")
                          else runCatching { Api.comSegredo("carteira.idiomas", JSONObject(), entrada.frase(semAtiva = true)).optJSONArray("idiomas") }.getOrNull()
    }
    var avisoAberto by remember { mutableStateOf(false) }

    fun escolher() {
        val receber = aoEscolher ?: return
        mensagem = null
        trabalhando = true
        escopo.launch {
            try {
                mensagem = receber(entrada.frase())
            } finally {
                trabalhando = false
            }
        }
    }

    fun fechar(escolhida: String) {
        val limpa = escolhida.trim()
        if (limpa.isEmpty()) return
        entrada.definir(limpa, entrada.ativa)
        palavra.limpar()
        mensagem = null
        if (entrada.ativa < entrada.quantidade - 1) entrada.ativa++ else digitando = false
    }

    // O Seguinte: a primeira sugestao do que esta digitado (a palavra exata vem antes); sem
    // sugestao, o digitado.
    fun seguir() {
        escopo.launch { fechar(palavra.sugestoesAgora().palavras.firstOrNull() ?: palavra.texto) }
    }

    // Saindo das posicoes com uma palavra completa digitada, ela entra; pela metade, fica so no campo.
    fun pronto(depois: () -> Unit = {}) {
        escopo.launch {
            if (palavra.texto.isNotEmpty() && palavra.sugestoesAgora().palavras.firstOrNull() == palavra.texto) fechar(palavra.texto)
            digitando = false
            depois()
        }
    }

    // Da lista: a palavra entra na posicao em edicao, se vazia, ou na primeira vazia, e a seguinte
    // vazia fica ativa. Com todas preenchidas, a lista fecha.
    fun escolherDaLista(escolhida: String) {
        val alvo = if (entrada.preenchida(entrada.ativa)) (0 until entrada.quantidade).firstOrNull { !entrada.preenchida(it) } else entrada.ativa
        if (alvo == null) { Navegacao.fechar(); return }
        entrada.definir(escolhida, alvo)
        mensagem = null
        val proxima = (0 until entrada.quantidade).firstOrNull { !entrada.preenchida(it) }
        if (proxima != null) entrada.ativa = proxima else Navegacao.fechar()
    }

    // Da lista: a palavra marcada sai da ultima posicao em que esta, e essa posicao fica ativa.
    fun tirarDaLista(lugar: Int) {
        entrada.limpar(lugar)
        entrada.ativa = lugar
        mensagem = null
    }

    fun colar() {
        val gerente = contexto.getSystemService(ClipboardManager::class.java)
        val texto = runCatching { gerente.primaryClip?.getItemAt(0)?.coerceToText(contexto)?.toString() }.getOrNull().orEmpty()
        if (texto.isBlank()) return
        palavra.limpar()
        val quantas = entrada.colar(texto)
        runCatching { gerente.clearPrimaryClip() }
        colado = true
        digitando = false
        mensagem = if (quantas in EntradaDaFrase.TAMANHOS) null
                   else t("O texto colado tem %lld palavras, e uma frase tem 12, 15, 18, 21 ou 24. Nada foi preenchido: confira o que você copiou.", quantas)
    }

    fun importar() {
        mensagem = null
        if (usaPassphrase) {
            val a = passphrase.bytes()
            val b = repeticao.bytes()
            val iguais = a.isNotEmpty() && java.security.MessageDigest.isEqual(a, b)
            a.fill(0)
            b.fill(0)
            if (!iguais) {
                mensagem = t("As duas versões da passphrase não conferem.")
                return
            }
        }
        trabalhando = true
        escopo.launch {
            try {
                val validacao = Api.comSegredo("carteira.validarFrase", JSONObject(), entrada.frase())
                when (validacao.getString("resultado")) {
                    "valida" -> {
                        if (aoConferirCopia != null) {
                            // Conferindo uma copia: a frase vai para quem pediu, sem enderecos nem carteira nova.
                            mensagem = aoConferirCopia(entrada.frase(), if (usaPassphrase) passphrase.bytes() else null)
                        } else {
                            val partes = if (usaPassphrase) arrayOf(entrada.frase(), passphrase.bytes()) else arrayOf(entrada.frase())
                            aoConferir(Api.comSegredo("carteira.previa", JSONObject(), *partes))
                        }
                    }
                    "tamanho" -> mensagem = t("Faltam palavras: %lld de %lld.", validacao.optInt("contagem"), entrada.quantidade)
                    "desconhecida" -> mensagem = t("A palavra %lld não existe na lista. Confira no papel.", validacao.optInt("posicao"))
                    "conferencia" -> mensagem = t("Todas as palavras existem, mas a conferência da frase não fecha. Alguma está trocada ou fora de ordem. Confira no papel.")
                    "idiomas" -> mensagem = t("As palavras são de idiomas diferentes. Confira no papel.")
                    else -> mensagem = t("Esta frase vale em mais de um idioma, e a escolha muda a carteira. Importe pela versão em inglês da frase.")
                }
            } catch (_: FalhaDoNucleo) {
                mensagem = t("Não foi possível importar a carteira.")
            } finally {
                trabalhando = false
            }
        }
    }

    BackHandler { if (digitando) pronto() else aoCancelar() }
    Column(Modifier.fillMaxSize()) {
        CabecalhoDeFolha("", aoCancelar)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                EmblemaCifrado(modifier = Modifier.padding(bottom = Espaco.xs))
                Text(when {
                         escolhendo != null -> t("Escolha as suas palavras")
                         conferindo != null -> t("Confira a seed phrase de %@", conferindo)
                         else -> t("Importar com a senha da carteira")
                     }, style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center)
                Text(
                    when {
                        escolhendo != null -> t("Digite %lld palavras da lista em inglês, na ordem em que você anotou. A %lldª o app sorteia, para a conta da frase fechar.", escolhendo - 1, escolhendo)
                        conferindo != null -> t("Digite as palavras de onde você anotou, todas, em ordem. No Super Security, essa cópia é o único caminho de volta.")
                        else -> t("Digite as palavras na ordem em que você anotou, uma em cada campo.")
                    },
                    style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center,
                )
            }
            if (escolhendo != null) {
                // Compacto, com a setinha para abrir o porque.
                Column(
                    Modifier.padding(top = Espaco.lg).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.cautelaFundo)
                        .clickable { avisoAberto = !avisoAberto }.padding(Espaco.sm).animateContentSize(),
                    verticalArrangement = Arrangement.spacedBy(Espaco.xs),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                        Icone(Icones.alerta, Paleta.cautela, tamanho = 14.dp)
                        Text(t("Escolhidas a dedo, as palavras ficam mais fáceis de adivinhar"), style = estilo(Tipo.nota), fontWeight = FontWeight.SemiBold,
                             color = Paleta.tinta, modifier = Modifier.weight(1f))
                        Icone(if (avisoAberto) Icones.acima else Icones.abaixo, Paleta.tintaSuave, tamanho = 12.dp)
                    }
                    if (avisoAberto) {
                        Text(t("Pessoas tendem a escolher palavras favoritas, do mesmo tema ou próximas na lista, e robôs testam essas combinações sem parar. O seguro é sortear cada palavra com dado ou moeda, ou deixar o app sortear. Uma passphrase forte por cima dá mais uma camada de proteção."),
                             style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(start = 22.dp))
                    }
                }
            }
            // O tamanho e o Colar na mesma linha, como no iOS. Conferindo uma copia, nada de colar: a
            // conferencia e do papel.
            if (escolhendo == null && conferindo == null) Row(Modifier.padding(top = Espaco.lg), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    // A outra opcao ao lado da de 24 fica a ultima escolhida (15, 18 ou 21 continuam ali
                    // depois de passar pela de 24), e nao volta para 12.
                    LaunchedEffect(entrada.quantidade) { if (entrada.quantidade != 24) outroTamanho = entrada.quantidade }
                    val opcoes = if (maisTamanhos) EntradaDaFrase.TAMANHOS else listOf(if (entrada.quantidade == 24) outroTamanho else entrada.quantidade, 24)
                    Segmentado(opcoes.map { it to if (maisTamanhos) "$it" else t("%lld palavras", it) }, entrada.quantidade, Modifier.weight(1f)) {
                        entrada.mudarQuantidade(it)
                        palavra.limpar()
                        maisTamanhos = false
                    }
                    if (!maisTamanhos) {
                        Box(Modifier.size(40.dp).clip(CircleShape).background(Paleta.corpo).clickable { maisTamanhos = true }, contentAlignment = Alignment.Center) {
                            Icone(Icones.mais, Paleta.tintaSuave, tamanho = 16.dp, descricao = t("Outros tamanhos de frase"))
                        }
                    }
                }
                Row(
                    Modifier.height(40.dp).vidro(CircleShape, Vidros.barra).clickable(role = Role.Button) { colar() }.padding(horizontal = Espaco.sm),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icone(Icones.colar, Paleta.tinta, tamanho = 17.dp)
                    Text(t("Colar"), style = estilo(Tipo.corpo), fontSize = 17.sp, color = Paleta.tinta)
                }
            }
            if (colado) {
                Text(t("Colado. A área de transferência foi limpa agora."), style = estilo(Tipo.nota), color = Paleta.cautela, modifier = Modifier.padding(top = Espaco.xs))
            }
            GradeDaFrase(entrada, revisao, digitando, palavra.texto, mostrar, Modifier.padding(top = Espaco.md), sorteada = escolhendo) { indice ->
                pronto {
                    entrada.ativa = indice
                    palavra.limpar()
                    digitando = true
                    if (!proprio) celular.mostrar()
                }
            }
            if (escolhendo != null) {
                BotaoSecundario(t("Escolher na lista de palavras"), Modifier.padding(top = Espaco.sm), icone = Icones.lista) {
                    pronto {
                        palavra.limpar()
                        Navegacao.folha {
                            ListaDePalavras(entrada, aoEscolher = { escolherDaLista(it) }, aoTirar = { tirarDaLista(it) }) { Navegacao.fechar() }
                        }
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(top = Espaco.xs), verticalAlignment = Alignment.CenterVertically) {
                if (entrada.preenchidas > 0) BotaoTerciario(t("Limpar")) { confirmarLimpar = true }
                Spacer(Modifier.weight(1f))
                BotaoTerciario(if (mostrar) t("Esconder palavras") else t("Mostrar palavras")) { mostrar = !mostrar }
            }
            if (escolhendo == null && conferindo == null) Row(Modifier.padding(top = Espaco.md), verticalAlignment = Alignment.CenterVertically) {
                Text(t("Esta carteira usa passphrase"), style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
                Interruptor(usaPassphrase, aoMudarPassphrase, cor = Paleta.acento)
            }
            AnimatedVisibility(usaPassphrase) {
                Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Text(t("Com a passphrase errada, a carteira abre vazia e sem aviso nenhum. Por isso ela é digitada duas vezes. Segure o dedo num campo para conferir as duas."),
                         style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs))
                    var revelar by remember { mutableStateOf(false) }
                    CampoSecreto(passphrase, t("Passphrase"), revelar) { revelar = it }
                    CampoSecreto(repeticao, t("Repita a passphrase"), revelar) { revelar = it }
                }
            }
            mensagem?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
            Column(
                Modifier.padding(top = Espaco.lg).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(Espaco.base),
                verticalArrangement = Arrangement.spacedBy(Espaco.md),
            ) {
                Garantia(Icones.cadeadoCheio, t("Escondidas nos campos"), t("Segure uma palavra para conferir. As sugestões mostram a palavra para você escolher."))
                Garantia(Icones.celular, t("Só neste celular"), t("O app não manda as palavras para lugar nenhum, e ninguém da Escalibur pede estas palavras."))
                Garantia(Icones.wifiRiscado, t("Sem internet nesta tela"),
                         t("Enquanto ela está aberta, o app não fala com rede nenhuma. A conferência é feita aqui: a última palavra traz uma soma de verificação das outras, calculada no celular com a lista de 2048 palavras que vem dentro do app."))
            }
        }
        if (digitando) {
            Row(Modifier.fillMaxWidth().height(52.dp).background(Paleta.corpo).padding(horizontal = Espaco.margem), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) {
                    val sugestoes = palavra.sugestoes.palavras
                    when {
                        palavra.texto.isEmpty() -> Text(t("Palavra %lld de %lld", entrada.ativa + 1, entrada.quantidade), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                        sugestoes.isEmpty() -> Unit
                        else -> SugestoesDePalavra(sugestoes) { fechar(it) }
                    }
                    if (palavra.texto.isNotEmpty() && palavra.sugestoes.letras.isEmpty() && sugestoes.isEmpty()) {
                        Text(t("Nenhuma palavra da lista começa assim."), style = estilo(Tipo.nota), color = Paleta.cautela)
                    }
                }
                BotaoTerciario(t("Pronto")) { pronto() }
            }
            if (proprio) {
                TecladoDePalavras(
                    palavra.texto, letrasPossiveis = palavra.sugestoes.letras,
                    aoDigitar = { if (palavra.texto.length < 12) palavra.texto += it },
                    aoApagar = {
                        if (palavra.texto.isNotEmpty()) palavra.texto = palavra.texto.dropLast(1)
                        else if (entrada.preenchida(entrada.ativa)) entrada.limpar(entrada.ativa)
                    },
                    aoLimpar = { palavra.limpar() },
                    aoSeguir = { seguir() },
                    tituloDoSeguir = if (entrada.ativa < entrada.quantidade - 1) t("Próxima") else t("Pronto"),
                    aoSistema = if (reforcado) null else ({ confirmarCelular = true }),
                    aoSobre = { Navegacao.folha { FolhaDoSafeKeyboard { Navegacao.fechar() } } },
                )
            } else {
                PalavraPeloCelular(palavra.texto, { palavra.texto = it }, { seguir() }, celular, todosOsIdiomas = peloCelular)
            }
        } else {
            Rodape {
                if (escolhendo != null) {
                    BotaoPrimario(t("Sortear a %lldª palavra", escolhendo), ligado = entrada.preenchidas == entrada.quantidade, carregando = trabalhando) { escolher() }
                } else {
                    BotaoPrimario(if (conferindo != null) t("Conferir") else t("Importar"), ligado = entrada.preenchidas == entrada.quantidade, carregando = trabalhando) { importar() }
                }
            }
        }
    }
    if (confirmarCelular) {
        Confirmacao(
            t("Usar o teclado do celular?"),
            t("Só para frases em japonês, chinês ou coreano, que o Safe Keyboard não escreve. O teclado do celular recebe as letras que você digitar."),
            t("Usar o do celular"), destrutiva = false,
            aoConfirmar = {
                confirmarCelular = false
                peloCelular = true
            },
            aoCancelar = { confirmarCelular = false },
        )
    }
    if (confirmarLimpar) {
        Confirmacao(
            t("Apagar as palavras digitadas?"), t("As %lld palavras saem desta tela. Você digita de novo, a partir da primeira.", entrada.preenchidas), t("Apagar"),
            aoConfirmar = {
                confirmarLimpar = false
                entrada.zerar()
                palavra.limpar()
                digitando = false
                colado = false
                mensagem = null
            },
            aoCancelar = { confirmarLimpar = false },
        )
    }
}

/** As posicoes em duas colunas: o numero e, no lugar da palavra, pontos; segurar mostra. */
@Composable
private fun GradeDaFrase(
    entrada: EntradaDaFrase, revisao: Int, digitando: Boolean, digitado: String, mostrar: Boolean, modifier: Modifier = Modifier,
    sorteada: Int? = null, aoTocar: (Int) -> Unit,
) {
    // Escolhendo: a ultima aparece, mas e do app, sem campo.
    val total = entrada.quantidade + if (sorteada != null) 1 else 0
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        for (linha in 0 until (total + 1) / 2) {
            Row(horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                for (coluna in 0..1) {
                    val indice = linha * 2 + coluna
                    if (indice < entrada.quantidade) {
                        PosicaoDaFrase(indice, entrada, revisao, ativa = digitando && entrada.ativa == indice, digitado, mostrar, Modifier.weight(1f)) { aoTocar(indice) }
                    } else if (sorteada != null && indice == entrada.quantidade) {
                        PosicaoSorteada(sorteada, Modifier.weight(1f))
                    } else {
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

/** A posicao da ultima palavra, reservada: o mesmo tamanho e numero das outras, fundo rebaixado. */
@Composable
private fun PosicaoSorteada(numero: Int, modifier: Modifier) {
    Row(
        modifier.height(44.dp).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.trilho).padding(start = Espaco.sm, end = 9.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs),
    ) {
        Text("%02d".format(numero), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Paleta.tintaApagada)
        Text(t("o app sorteia"), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Paleta.tintaSuave, maxLines = 1, softWrap = false,
             overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        // O sorteio em pixels, como no iOS.
        app.escalibur.wallet.ui.comp.PixelsDoSorteio(Modifier.size(16.dp))
    }
}

@Composable
private fun PosicaoDaFrase(
    indice: Int, entrada: EntradaDaFrase, @Suppress("UNUSED_PARAMETER") revisao: Int, ativa: Boolean, digitado: String, mostrar: Boolean,
    modifier: Modifier, aoTocar: () -> Unit,
) {
    var segurando by remember { mutableStateOf(false) }
    // O toque de agora: o gesto vive enquanto a posicao existe, e o que o toque faz muda (o globo).
    val tocar by rememberUpdatedState(aoTocar)
    val forma = RoundedCornerShape(Raio.cartao)
    val preenchida = entrada.preenchida(indice)
    Row(
        modifier.height(44.dp).clip(forma).background(Paleta.corpo).border(if (ativa) 1.5.dp else 1.dp, if (ativa) Paleta.tintaSuave else Paleta.borda, forma)
            .pointerInput(indice) {
                detectTapGestures(
                    onPress = {
                        segurando = true
                        tryAwaitRelease()
                        segurando = false
                    },
                    onTap = { tocar() },
                )
            }
            .padding(horizontal = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs),
    ) {
        Text("%02d".format(indice + 1), style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"),
             color = if (ativa) Paleta.tintaSuave else Paleta.tintaApagada)
        val texto = when {
            ativa && digitado.isNotEmpty() -> digitado
            ativa && !preenchida -> ""
            preenchida && (mostrar || segurando) -> entrada.texto(indice)
            preenchida -> "•".repeat(entrada.letras(indice).coerceIn(3, 8))
            else -> ""
        }
        if (texto.isEmpty() && !ativa) {
            Text(t("palavra"), fontFamily = FontFamily.Monospace, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Paleta.tintaMorta)
        } else {
            Text(texto, fontFamily = FontFamily.Monospace, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Paleta.tinta, maxLines = 1)
        }
        if (ativa) Box(Modifier.width(2.dp).height(20.dp).background(Paleta.acento))
    }
}

@Composable
fun CampoSecreto(campo: TextFieldState, dica: String, revelar: Boolean, aoRevelar: (Boolean) -> Unit) {
    Box(
        Modifier.fillMaxWidth().height(Altura.primaria).background(Paleta.corpo, RoundedCornerShape(Raio.cartao))
            .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao))
            .pointerInput(Unit) { detectTapGestures(onPress = { aoRevelar(true); tryAwaitRelease(); aoRevelar(false) }) }
            .padding(horizontal = Espaco.md),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (campo.text.isEmpty()) Text(dica, style = estilo(Tipo.mono), color = Paleta.tintaMorta)
        BasicSecureTextField(
            state = campo, textObfuscationMode = if (revelar) TextObfuscationMode.Visible else TextObfuscationMode.Hidden,
            textStyle = estilo(Tipo.mono).copy(color = Paleta.tinta), cursorBrush = SolidColor(Paleta.acento),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun Garantia(icone: ImageVector, titulo: String, detalhe: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) { Icone(icone, Paleta.tintaSuave, tamanho = 14.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            Text(detalhe, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
    }
}

/**
 * A conferencia antes de guardar uma carteira que veio de fora: os primeiros enderecos, a impressao
 * digital, quem controla a conta na Tron e o aceite de que quem deu as palavras controla a carteira.
 */
@Composable
private fun PreviaDaImportacao(dados: JSONObject, entrada: EntradaDaFrase, passphrase: TextFieldState?, aoVoltar: () -> Unit, aoGuardar: () -> Unit) {
    ConferenciaDaImportacao(dados, comPassphrase = passphrase != null, doEnvelope = false, aoVoltar = aoVoltar,
                            aoGuardar = { entrada.zerar(); aoGuardar() }) { tronOutraChave ->
        Autorizacao.tentando(t("Guardar a carteira importada neste celular")) { credencial ->
            val corpo = JSONObject().put("credencial", credencial.json()).put("palavras", entrada.quantidade).put("tronOutraChave", tronOutraChave)
            val partes = if (passphrase != null) credencial.partes(entrada.frase(), passphrase.bytes()) else credencial.partes(entrada.frase())
            Api.comSegredo("carteira.importar", corpo, *partes)
        } != null
    }
}

/**
 * A conferencia de uma carteira que veio de fora, pela frase ou por um envelope: o envelope pode
 * ter vindo de outra pessoa, e o aceite diz isso. `guardar` pede a autorizacao e guarda; devolve
 * falso se o dono desistiu.
 */
@Composable
internal fun ConferenciaDaImportacao(
    dados: JSONObject, comPassphrase: Boolean, doEnvelope: Boolean, aoVoltar: () -> Unit, aoGuardar: () -> Unit,
    guardar: suspend (tronOutraChave: Boolean) -> Boolean,
) {
    val escopo = rememberCoroutineScope()
    var aceito by remember { mutableStateOf(false) }
    var tronOutraChave by remember { mutableStateOf(false) }
    var guardando by remember { mutableStateOf(false) }
    var mensagem by remember { mutableStateOf<String?>(null) }
    // A recusa aparece no fim da lista, abaixo dos enderecos: a tela desce ate ela.
    val rolagem = rememberScrollState()
    LaunchedEffect(mensagem) { if (mensagem != null) rolagem.animateScrollTo(rolagem.maxValue) }
    LaunchedEffect(Unit) {
        val tron = dados.opcional("tron") ?: return@LaunchedEffect
        // A tela das palavras saiu: o silencio da rede termina antes de perguntar a Tron (a saida
        // dela fecha o silencio em paralelo, e a pergunta chegava a ser recusada).
        runCatching { Api.objeto("rede.silencio", JSONObject().put("ligar", false)) }
        tronOutraChave = runCatching { Api.objeto("carteira.tron", JSONObject().put("endereco", tron)).getBoolean("outraChave") }.getOrDefault(false)
    }
    BackHandler(onBack = aoVoltar)
    Column(Modifier.fillMaxSize()) {
        CabecalhoDeFolha("", null, aoVoltar = aoVoltar)
        Column(Modifier.weight(1f).verticalScroll(rolagem).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md)) {
            Text(t("Confira antes de guardar"), style = estilo(Tipo.titulo), color = Paleta.tinta)
            Text(
                if (comPassphrase) t("Se esta carteira já recebeu antes, estes endereços são os que você conhece. Se não baterem, a frase ou a passphrase está diferente, e o que abriria aqui é outra carteira, vazia.")
                else t("Se esta carteira já recebeu antes, estes endereços são os que você conhece. Se não baterem, alguma palavra está diferente, e o que abriria aqui é outra carteira, vazia."),
                style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm),
            )
            Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
                for (item in dados.getJSONArray("enderecos").objetos()) {
                    Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                            SeloDaRede(item.getString("rede"), Redes.rede(item.getString("rede"))?.coingecko ?: item.getString("rede"), 20.dp, Paleta.vazio)
                            Text(item.getString("nome"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                        }
                        EnderecoEmBlocos(item.getString("endereco"))
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(Espaco.xxs)) {
                    Text(t("Impressão digital da carteira"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    Text(dados.getString("digital"), style = estilo(Tipo.linha), color = Paleta.tinta)
                    Text(t("A mesma que carteiras de hardware mostram para esta frase."), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                }
            }
            if (tronOutraChave) {
                Faixa(TipoDeFaixa.falha, t("Na Tron, esta conta é controlada por outra chave"), Modifier.padding(top = Espaco.lg),
                      mensagem = t("É o golpe da frase com saldo: o que entrar nela, quem controla a outra chave leva. Não deposite nada nesta carteira."))
            }
            mensagem?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
        }
        Rodape {
            Aceite(aceito, if (doEnvelope) t("Entendo que quem me mandou este envelope e a senha dele controla esta carteira e pode levar o que entrar nela. Só deposito aqui se o envelope for meu.")
                           else t("Entendo que quem me deu estas palavras controla esta carteira e pode levar o que entrar nela. Só deposito aqui se as palavras forem só minhas.")) { aceito = it }
            BotaoPrimario(t("Guardar esta carteira"), Modifier.padding(top = Espaco.sm), ligado = aceito, carregando = guardando) {
                guardando = true
                mensagem = null
                escopo.launch {
                    try {
                        if (guardar(tronOutraChave)) {
                            App.recarregar()
                            aoGuardar()
                        }
                    } catch (falha: FalhaDoNucleo) {
                        mensagem = when (falha.codigo) {
                            "sessao.jaImportada" -> t("Esta carteira já está neste app, com o nome %@.", falha.dados.optString("nome"))
                            else -> Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível importar a carteira.")
                        }
                    } finally {
                        guardando = false
                    }
                }
            }
            BotaoTerciario(t("Voltar e conferir"), Modifier.fillMaxWidth(), acao = aoVoltar)
        }
    }
}

/** So observar um endereco: a rede pelo formato, sem chave nenhuma neste celular. */
@Composable
fun ObservarEndereco(aoCancelar: () -> Unit, aoTerminar: () -> Unit) {
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    var endereco by remember { mutableStateOf("") }
    var nome by remember { mutableStateOf(t("Carteira fria")) }
    var reconhecida by remember { mutableStateOf<JSONObject?>(null) }
    var erro by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(endereco) {
        val resposta = runCatching { Api.objeto("carteira.reconhecer", JSONObject().put("endereco", endereco)) }.getOrNull()
        if (resposta?.optBoolean("frase") == true) {
            endereco = ""
            erro = t("Este código traz as palavras de uma senha de carteira, não um endereço. Quem tem essas palavras tem o saldo: não mostre a ninguém.")
            return@LaunchedEffect
        }
        reconhecida = resposta?.optJSONObject("reconhecida")
    }
    BackHandler(onBack = aoCancelar)
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().acimaDoTeclado()) {
        CabecalhoDeFolha("", aoCancelar)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                OrbitaDeMoedas(icone = Icones.olho)
                Text(t("Observar um endereço"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs))
                Text(t("Acompanhe o saldo de um endereço sem guardar chave nenhuma neste celular."), style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
            }
            Text(t("Endereço"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.lg))
            Row(
                Modifier.padding(top = Espaco.xs).fillMaxWidth().heightIn(min = 56.dp).background(Paleta.corpo, RoundedCornerShape(Raio.cartao))
                    .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(start = Espaco.md, end = Espaco.xs, top = Espaco.xxs, bottom = Espaco.xxs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.weight(1f)) {
                    if (endereco.isEmpty()) Text(t("Cole ou digite o endereço"), style = estilo(Tipo.corpo), color = Paleta.tintaMorta)
                    BasicTextField(
                        endereco, { endereco = it.take(512); erro = null }, maxLines = 4,
                        textStyle = estilo(Tipo.mono).copy(color = Paleta.tinta), cursorBrush = SolidColor(Paleta.acento),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = KeyboardType.Ascii),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                if (endereco.isEmpty()) {
                    Row(
                        Modifier.height(32.dp).clip(CircleShape).background(Paleta.controle).clickable {
                            val gerente = contexto.getSystemService(ClipboardManager::class.java)
                            endereco = runCatching { gerente.primaryClip?.getItemAt(0)?.coerceToText(contexto)?.toString() }.getOrNull().orEmpty().trim().take(512)
                        }.padding(horizontal = Espaco.sm),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icone(Icones.colar, Paleta.tinta, tamanho = 14.dp)
                        Text(t("Colar"), style = estilo(Tipo.rotulo), color = Paleta.tinta)
                    }
                } else {
                    Box(Modifier.size(Altura.toque).clickable { endereco = "" }, contentAlignment = Alignment.Center) {
                        Icone(Icones.fecharCheio, Paleta.tintaApagada, tamanho = 20.dp, descricao = t("Apagar o endereço"))
                    }
                }
            }
            val achada = reconhecida
            if (achada != null) {
                val rede = achada.getJSONObject("rede")
                val evm = achada.getBoolean("evm")
                val redesEVM = achada.getJSONArray("redesEVM").objetos()
                Row(
                    Modifier.padding(top = Espaco.sm).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(Espaco.sm),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    if (evm) {
                        Box {
                            redesEVM.take(4).forEachIndexed { indice, item ->
                                SeloDaRede(item.getString("id"), item.getString("coingecko"), 28.dp, Paleta.corpo, Modifier.padding(start = (indice * 18).dp))
                            }
                        }
                    } else {
                        SeloDaRede(rede.getString("id"), rede.getString("coingecko"), 32.dp, Paleta.corpo)
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(if (evm) t("Endereço EVM") else t("Endereço %@", rede.getString("nome")), style = estilo(Tipo.linha), color = Paleta.tinta)
                        val nomes = redesEVM.map { it.getString("nome") }
                        Text(if (evm) t("Vale em %@.", android.icu.text.ListFormatter.getInstance(Textos.locale).format(nomes)) else t("Rede reconhecida."),
                             style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    }
                    Icone(Icones.vistoCheio, Paleta.alta, tamanho = 20.dp)
                }
            } else if (endereco.isNotBlank()) {
                Text(t("Não reconheci este endereço em nenhuma rede ligada. Confira se copiou inteiro."), style = estilo(Tipo.nota), color = Paleta.baixa,
                     modifier = Modifier.padding(top = Espaco.sm))
            }
            Text(t("Nome da carteira"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.lg))
            Box(
                Modifier.padding(top = Espaco.xs).fillMaxWidth().height(Altura.campo).background(Paleta.corpo, RoundedCornerShape(Raio.cartao))
                    .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(horizontal = Espaco.md),
                contentAlignment = Alignment.CenterStart,
            ) {
                BasicTextField(
                    nome, { nome = it.take(40) }, singleLine = true, textStyle = estilo(Tipo.linha).copy(color = Paleta.tinta),
                    cursorBrush = SolidColor(Paleta.acento), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Row(Modifier.padding(top = Espaco.sm), horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Icone(Icones.olho, Paleta.tintaApagada, tamanho = 13.dp)
                Text(t("Desta carteira você vê saldo e histórico. Enviar e trocar ficam desligados."), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            }
            erro?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
        }
        Rodape {
            BotaoPrimario(t("Observar"), ligado = reconhecida != null) {
                escopo.launch {
                    try {
                        Api.objeto("carteira.observar", JSONObject().put("endereco", endereco).put("nome", nome))
                        App.recarregar()
                        aoTerminar()
                    } catch (_: FalhaDoNucleo) {
                        erro = t("Não foi possível guardar.")
                    }
                }
            }
        }
    }
}
