package app.escalibur.wallet.ui.carteira

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.runtime.Stable
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import kotlinx.coroutines.delay
import app.escalibur.wallet.ui.comp.BotaoDeAlerta
import app.escalibur.wallet.ui.comp.AlertaDoIos
import androidx.compose.foundation.layout.fillMaxSize
import app.escalibur.wallet.ui.principal.FolhaDoIos
import app.escalibur.wallet.ui.comp.ControleDaFolha
import app.escalibur.wallet.ui.comp.CabecalhoDaFolha
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.Transferencia
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.roundToInt

/**
 * O desenho de uma carteira nas listas (o WalletGlyph do iOS): a carteira cheia (a de so observar
 * tambem) e o cadeado da passphrase. `simples`: so o icone, sem o fundo, um pouco maior e um pouco
 * acima do centro (a lista de Carteiras nos Ajustes).
 */
@Composable
fun GlifoDaCarteira(carteira: Carteira, tamanho: androidx.compose.ui.unit.Dp = 36.dp, selecionada: Boolean = false, simples: Boolean = false) {
    Box(Modifier.size(tamanho)) {
        Box(Modifier.size(tamanho).clip(RoundedCornerShape(if (tamanho <= 24.dp) 6.dp else Raio.cartao)).background(if (simples) Color.Transparent else Paleta.trilho),
            contentAlignment = Alignment.Center) {
            Icone(Icones.carteiraCheia, if (selecionada) Paleta.tinta else Paleta.tintaApagada, tamanho = tamanho * (if (simples) 0.62f else 0.5f),
                  Modifier.offset(y = if (simples) (-1).dp else 0.dp))
        }
        if (carteira.temPassphrase) {
            Box(
                // Um pouco para fora do canto, como no iOS.
                Modifier.align(Alignment.BottomEnd).offset(tamanho * 0.12f, tamanho * 0.12f).size(tamanho * 0.44f).clip(CircleShape).background(Paleta.controle)
                    .border(2.dp, Paleta.vazio, CircleShape),
                contentAlignment = Alignment.Center,
            ) { Icone(Icones.cadeadoCheio, Paleta.tinta, tamanho = tamanho * 0.22f) }
        }
    }
}

/**
 * Reordenar as carteiras (o WalletReorder do iOS): segurar uma linha e arrastar. As outras abrem
 * espaco enquanto ela anda, e soltar grava a ordem nova nos metadados cifrados.
 */
@Stable
class OrdemDasCarteiras(private val escopo: kotlinx.coroutines.CoroutineScope) {
    var ordem by mutableStateOf<List<Carteira>>(emptyList())
    var arrastando by mutableStateOf<String?>(null)
        private set
    var deslocamento by mutableFloatStateOf(0f)
        private set
    var alturaDaLinha = 1f

    private val origem get() = ordem.indexOfFirst { it.id == arrastando }

    fun alvo(): Int = (origem + (deslocamento / alturaDaLinha).roundToInt()).coerceIn(0, ordem.lastIndex)

    /** Quanto uma linha que nao esta sendo arrastada desce ou sobe para abrir espaco. */
    fun abre(indice: Int): Float {
        val de = origem
        if (de < 0) return 0f
        val para = alvo()
        return when {
            de < para && indice in (de + 1)..para -> -alturaDaLinha
            de > para && indice in para until de -> alturaDaLinha
            else -> 0f
        }
    }

    fun comecar(id: String) { arrastando = id; deslocamento = 0f }
    fun mover(dy: Float) { deslocamento += dy }

    fun soltar() {
        val de = origem
        val para = if (de >= 0) alvo() else -1
        if (de >= 0 && para != de) {
            val nova = ordem.toMutableList().apply { add(para, removeAt(de)) }
            ordem = nova
            escopo.launch { runCatching { App.aplicar(Api.objeto("carteira.ordenar", JSONObject().put("ids", JSONArray(nova.map { it.id })))) } }
        }
        arrastando = null
        deslocamento = 0f
    }
}

@Composable
fun rememberOrdemDasCarteiras(carteiras: List<Carteira>): OrdemDasCarteiras {
    val escopo = rememberCoroutineScope()
    val ordem = remember { OrdemDasCarteiras(escopo) }
    ordem.alturaDaLinha = with(LocalDensity.current) { Altura.linha.toPx() }
    // So quando a lista do nucleo muda: a ordem nova fica na tela enquanto o nucleo grava.
    remember(carteiras) { ordem.ordem = carteiras }
    return ordem
}

/** Uma linha da lista de carteiras que da para arrastar (o walletReorder do iOS). */
@Composable
fun Modifier.arrastavel(ordem: OrdemDasCarteiras, carteira: Carteira, indice: Int): Modifier {
    val haptico = LocalHapticFeedback.current
    val esta = ordem.arrastando == carteira.id
    val desliza by animateFloatAsState(if (esta) 0f else ordem.abre(indice), spring(dampingRatio = 0.85f, stiffness = 440f), label = "abre")
    val escala by animateFloatAsState(if (esta) 1.03f else 1f, spring(dampingRatio = 0.8f, stiffness = 440f), label = "escala")
    val sombra by animateFloatAsState(if (esta) 1f else 0f, label = "sombra")
    return this
        .zIndex(if (esta) 1f else 0f)
        .graphicsLayer {
            translationY = if (esta) ordem.deslocamento else desliza
            scaleX = escala
            scaleY = escala
        }
        .shadow((16 * sombra).dp, RectangleShape, clip = false, ambientColor = Color.Black.copy(alpha = 0.35f), spotColor = Color.Black.copy(alpha = 0.35f))
        .pointerInput(carteira.id) {
            detectDragGesturesAfterLongPress(
                onDragStart = {
                    ordem.comecar(carteira.id)
                    haptico.performHapticFeedback(HapticFeedbackType.LongPress)
                },
                onDrag = { mudanca, arraste ->
                    mudanca.consume()
                    val antes = ordem.alvo()
                    ordem.mover(arraste.y)
                    if (ordem.alvo() != antes) haptico.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                },
                onDragEnd = { ordem.soltar() },
                onDragCancel = { ordem.soltar() },
            )
        }
}

/** A linha de baixo de cada carteira na lista. */
fun subtituloDaCarteira(carteira: Carteira): String = when {
    carteira.observacao -> t("Só observar · %@", Redes.rede(carteira.contas.firstOrNull()?.first ?: "")?.nome ?: "")
    !carteira.palavrasConfirmadas -> t("Palavras não confirmadas")
    !carteira.passphraseConfirmada -> t("Passphrase não conferida")
    carteira.contas.size == 1 -> t("%lld palavras · 1 rede", carteira.palavras ?: 12)
    else -> t("%lld palavras · %lld redes", carteira.palavras ?: 12, carteira.contas.size)
}

/**
 * As carteiras deste app: tocar escolhe, o lapis renomeia, o copiar abre os enderecos por rede.
 * Segurar uma linha e arrastar muda a ordem.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SeletorDeCarteiras(aoFechar: () -> Unit) {
    val escopo = rememberCoroutineScope()
    val controleDaFolha = remember { ControleDaFolha() }
    val haptico = LocalHapticFeedback.current
    val estado = App.estado
    var renomeando by remember { mutableStateOf<Carteira?>(null) }
    var copiando by remember { mutableStateOf<Carteira?>(null) }
    // A linha com o apagar a mostra, e a carteira no popup de apagar.
    var aberta by remember { mutableStateOf<String?>(null) }
    var apagando by remember { mutableStateOf<Carteira?>(null) }
    val ordem = rememberOrdemDasCarteiras(estado.carteiras)

    fun fechar(depois: () -> Unit = {}) {
        controleDaFolha.depois = depois
        controleDaFolha.fechar()
    }

    FolhaDoIos(aoFechar = { aoFechar(); controleDaFolha.depois?.invoke(); controleDaFolha.depois = null }, media = true) { fecharFolha ->
        controleDaFolha.fechar = fecharFolha
        Column(Modifier.fillMaxSize().background(Paleta.corpo).navigationBarsPadding()) {
            CabecalhoDaFolha(t("Carteiras"), { fechar() })
            // A lista ocupa o meio e o botao fica no rodape, como no iOS.
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState(), enabled = ordem.arrastando == null).padding(top = Espaco.md)) {
                ordem.ordem.forEachIndexed { indice, carteira ->
                    val selecionada = carteira.id == estado.selecionada || (estado.selecionada == null && indice == 0)
                    val esta = ordem.arrastando == carteira.id
                    LinhaQueApaga(carteira.id, aberta, { aberta = it }, { apagando = carteira }, Modifier.zIndex(if (esta) 1f else 0f)) {
                    Row(
                        Modifier.fillMaxWidth().height(Altura.linha)
                            .arrastavel(ordem, carteira, indice)
                            .background(if (selecionada || esta) Paleta.trilho else Paleta.corpo)
                            .clickable {
                                escopo.launch { runCatching { App.aplicar(Api.objeto("carteira.selecionar", JSONObject().put("id", carteira.id))) } }
                                fechar()
                            }
                            .padding(horizontal = Espaco.margem),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                    ) {
                        GlifoDaCarteira(carteira, selecionada = selecionada)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(carteira.nome, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(subtituloDaCarteira(carteira), style = estilo(Tipo.nota),
                                 color = if (!carteira.temCopia && !carteira.observacao) Paleta.cautela else Paleta.tintaSuave, maxLines = 1)
                        }
                        if (selecionada) Icone(Icones.visto, Paleta.tinta, tamanho = 15.dp)
                        if (carteira.contas.isNotEmpty()) {
                            Box(Modifier.size(width = 36.dp, height = Altura.toque).clickable { copiando = carteira }, contentAlignment = Alignment.Center) {
                                Icone(Icones.copiar, Paleta.tintaSuave, tamanho = 17.dp, descricao = t("Copiar endereço de %@", carteira.nome))
                            }
                        }
                        Box(Modifier.size(Altura.toque).clickable { renomeando = carteira }, contentAlignment = Alignment.Center) {
                            Icone(Icones.lapis, Paleta.tintaSuave, tamanho = 15.dp, descricao = t("Editar o nome de %@", carteira.nome))
                        }
                    }
                    }
                }
                if (ordem.ordem.size > 1) {
                    Text(t("Segure uma carteira e arraste para mudar a ordem."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                         modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm))
                }
            }
            BotaoPrimario(t("Adicionar carteira"), Modifier.padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs)) {
                fechar { Navegacao.cobrir { AdicionarCarteira(primeira = false) { Navegacao.fechar() } } }
            }
        }
    }

    renomeando?.let { carteira -> Renomear(carteira) { renomeando = null } }
    apagando?.let { carteira ->
        PopupDeRemover(carteira) { confirmou ->
            apagando = null
            if (confirmou) escopo.launch { RemocaoDeCarteira.remover(carteira) }
        }
    }
    copiando?.let { carteira -> CopiarEndereco(carteira) { copiando = null } }
}

@Composable
private fun Renomear(carteira: Carteira, aoFechar: () -> Unit) {
    val escopo = rememberCoroutineScope()
    var nome by remember { mutableStateOf(carteira.nome) }
    fun salvar() {
        // Sem controle nem caractere invisivel, ate 40: o mesmo saneamento dos nomes de envelope.
        val limpo = nome.filter { !it.isISOControl() && Character.getType(it) != Character.FORMAT.toInt() }.trim().take(40)
        escopo.launch {
            if (limpo.isNotEmpty()) runCatching { App.aplicar(Api.objeto("carteira.renomear", JSONObject().put("id", carteira.id).put("nome", limpo))) }
            aoFechar()
        }
    }
    AlertaDoIos(
        t("Nome da carteira"), t("Só aparece neste celular."),
        cancelar = BotaoDeAlerta(t("Cancelar"), acao = aoFechar),
        acoes = listOf(BotaoDeAlerta(t("Salvar"), ligado = nome.isNotBlank()) { salvar() }),
        aoFechar = aoFechar,
    ) {
        Box(
            Modifier.padding(top = Espaco.xs).fillMaxWidth().height(40.dp).background(Paleta.vazio, RoundedCornerShape(Raio.trilho))
                .padding(horizontal = Espaco.sm),
            contentAlignment = Alignment.CenterStart,
        ) {
            BasicTextField(
                nome, { nome = it.take(40) }, singleLine = true, textStyle = estilo(Tipo.corpo).copy(color = Paleta.tinta),
                cursorBrush = SolidColor(Paleta.acento), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

/**
 * Copiar o endereco da carteira (o CopyAddressSheet do iOS): as redes EVM numa linha so (o mesmo
 * endereco), e cada rede com endereco proprio, com o icone, o nome e o comeco e o fim do endereco.
 * Copiar marca o visto, fecha e mostra o aviso.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CopiarEndereco(carteira: Carteira, aoFechar: () -> Unit) {
    val contexto = LocalContext.current
    val escopo = rememberCoroutineScope()
    val controleDaFolha = remember { ControleDaFolha() }
    // A lista das redes EVM aberta, e o endereco que acabou de ser copiado.
    var abertas by remember { mutableStateOf(false) }
    var copiado by remember { mutableStateOf<String?>(null) }
    val redes = Redes.todas
    val evm = redes.filter { it.familia == "evm" && carteira.endereco(it.id) != null }
    val outras = buildList {
        val vistos = evm.mapNotNull { carteira.endereco(it.id) }.toMutableSet()
        for (rede in redes) {
            if (rede.familia == "evm") continue
            val endereco = carteira.endereco(rede.id) ?: continue
            if (vistos.add(endereco)) add(rede to endereco)
        }
    }

    fun copiar(titulo: String, endereco: String) {
        if (copiado != null) return
        Transferencia.copiar(contexto, endereco)
        copiado = endereco
        controleDaFolha.depois = { Avisos.mostrar(t("Endereço %@ copiado. Depois de colar, confira o endereço inteiro, inclusive o meio.", titulo)) }
        escopo.launch {
            delay(450)
            controleDaFolha.fechar()
        }
    }

    FolhaDoIos(aoFechar = { aoFechar(); controleDaFolha.depois?.invoke(); controleDaFolha.depois = null }, media = true) { fecharFolha ->
        controleDaFolha.fechar = fecharFolha
        Column(Modifier.fillMaxSize().background(Paleta.vazio).navigationBarsPadding()) {
            CabecalhoDaFolha(t("Copiar endereço"), { controleDaFolha.fechar() })
            Text(t("Escolha a rede. Depois de colar, confira o endereço inteiro, inclusive o meio."), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
                 modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xs))
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem, vertical = Espaco.md),
                   verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                if (evm.isNotEmpty()) {
                    val endereco = carteira.endereco(evm.first().id)!!
                    val titulo = t("Ethereum e redes EVM")
                    val destaque = emDestaque(evm)
                    val giro by animateFloatAsState(if (abertas) 180f else 0f, label = "seta")
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(start = Espaco.md, end = Espaco.xs)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                            // Tocar na linha abre as redes que usam este endereco; copiar fica no botao da direita.
                            Row(Modifier.weight(1f).heightIn(min = 64.dp).clickable(remember { MutableInteractionSource() }, null) { abertas = !abertas },
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                                // Tres redes sobrepostas, lidas da direita para a esquerda: a BNB Chain na ponta, por cima.
                                Box(Modifier.size(48.dp, 36.dp), contentAlignment = Alignment.CenterStart) {
                                    destaque.take(3).reversed().forEachIndexed { indice, rede ->
                                        SeloDaRede(rede.id, rede.coingecko, 24.dp, Paleta.corpo, Modifier.offset(x = 12.dp * indice))
                                    }
                                }
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text(nomesDasRedes(destaque), style = estilo(Tipo.nota), color = Paleta.tintaApagada, maxLines = 1,
                                             overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                                        Icone(Icones.abaixo, Paleta.tintaApagada, tamanho = 10.dp, Modifier.rotate(giro))
                                    }
                                    Text(carteira.curto(evm.first().id) ?: "", style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
                                }
                            }
                            Box(Modifier.size(Altura.toque).clickable { copiar(titulo, endereco) }, contentAlignment = Alignment.Center) {
                                MarcaDeCopiar(copiado == endereco, t("Copiar endereço %@", titulo))
                            }
                        }
                        AnimatedVisibility(abertas, enter = fadeIn() + expandVertically(expandFrom = Alignment.Top),
                                           exit = fadeOut() + shrinkVertically(shrinkTowards = Alignment.Top)) {
                            Column(Modifier.padding(top = Espaco.xs, bottom = Espaco.md), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                                for (par in destaque.chunked(2)) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                                        for (rede in par) {
                                            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                                SeloDaRede(rede.id, rede.coingecko, 18.dp, Paleta.corpo)
                                                Text(rede.nome, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
                                            }
                                        }
                                        if (par.size == 1) Spacer(Modifier.weight(1f))
                                    }
                                }
                            }
                        }
                    }
                }
                for ((rede, endereco) in outras) {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 64.dp).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
                            .clickable { copiar(rede.nome, endereco) }.padding(horizontal = Espaco.md),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                    ) {
                        Box(Modifier.size(48.dp, 36.dp), contentAlignment = Alignment.CenterStart) {
                            SeloDaRede(rede.id, rede.coingecko, 36.dp, Paleta.corpo)
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(rede.nome, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                            Text(carteira.curto(rede.id) ?: "", style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
                        }
                        Spacer(Modifier.width(Espaco.xs))
                        MarcaDeCopiar(copiado == endereco, null)
                    }
                }
            }
        }
    }
}

/** O copiar, que vira o visto verde quando copia (o symbolEffect replace do iOS). */
@Composable
private fun MarcaDeCopiar(copiado: Boolean, descricao: String?) {
    AnimatedContent(copiado, transitionSpec = {
        (fadeIn(tween(180)) + scaleIn(tween(220), 0.6f)) togetherWith (fadeOut(tween(120)) + scaleOut(tween(150), 0.6f))
    }, label = "copiado") { feito ->
        if (feito) Icone(Icones.visto, Paleta.alta, tamanho = 15.dp, descricao = descricao)
        else Icone(Icones.copiar, Paleta.tintaSuave, tamanho = 18.dp, descricao = descricao)
    }
}

/**
 * As redes EVM em destaque na linha das EVM, nesta ordem: BNB Chain, Ethereum e Base (pedido do
 * dono, 17/10/2026). As outras seguem na ordem de sempre.
 */
private val evmEmDestaque = listOf("bnb", "ethereum", "base")

private fun emDestaque(redes: List<Redes.Rede>): List<Redes.Rede> =
    evmEmDestaque.mapNotNull { id -> redes.firstOrNull { it.id == id } } + redes.filter { it.id !in evmEmDestaque }

/** Duas no texto e "e mais N": com a terceira, a linha quebrava. */
private fun nomesDasRedes(redes: List<Redes.Rede>): String {
    val mostradas = redes.take(2).joinToString(", ") { it.nome }
    val resto = redes.size - 2
    return if (resto > 0) t("%@ e mais %lld", mostradas, resto) else mostradas
}
