package app.escalibur.wallet.ui.carteira

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

/** O desenho de uma carteira nas listas: a carteira ou o olho, e o cadeado da passphrase. */
@Composable
fun GlifoDaCarteira(carteira: Carteira, tamanho: androidx.compose.ui.unit.Dp = 36.dp, selecionada: Boolean = false) {
    Box(Modifier.size(tamanho)) {
        Box(Modifier.size(tamanho).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.trilho), contentAlignment = Alignment.Center) {
            Icone(if (carteira.observacao) Icones.olho else Icones.carteira, if (selecionada) Paleta.tinta else Paleta.tintaApagada, tamanho = tamanho * 0.46f)
        }
        if (carteira.temPassphrase) {
            Box(
                Modifier.align(Alignment.BottomEnd).padding(start = 0.dp).size(tamanho * 0.44f).clip(CircleShape).background(Paleta.controle)
                    .border(2.dp, Paleta.vazio, CircleShape),
                contentAlignment = Alignment.Center,
            ) { Icone(Icones.cadeadoCheio, Paleta.tinta, tamanho = tamanho * 0.22f) }
        }
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
    val folha = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val haptico = LocalHapticFeedback.current
    val estado = App.estado
    var renomeando by remember { mutableStateOf<Carteira?>(null) }
    var copiando by remember { mutableStateOf<Carteira?>(null) }
    var ordem by remember(estado.carteiras) { mutableStateOf(estado.carteiras) }
    var arrastando by remember { mutableStateOf<String?>(null) }
    var deslocamento by remember { mutableFloatStateOf(0f) }
    val alturaDaLinha = with(LocalDensity.current) { Altura.linha.toPx() }

    fun fechar(depois: () -> Unit = {}) {
        escopo.launch { folha.hide() }.invokeOnCompletion {
            aoFechar()
            depois()
        }
    }

    ModalBottomSheet(onDismissRequest = aoFechar, sheetState = folha, containerColor = Paleta.corpo, dragHandle = null,
                     shape = RoundedCornerShape(topStart = Raio.folha, topEnd = Raio.folha)) {
        Column(Modifier.navigationBarsPadding()) {
            Box(Modifier.fillMaxWidth().height(Altura.barra + Espaco.xs)) {
                Text(t("Carteiras"), style = estilo(Tipo.acao), color = Paleta.tinta, modifier = Modifier.align(Alignment.Center))
                Box(Modifier.align(Alignment.CenterEnd).padding(end = Espaco.xs).size(Altura.toque).clickable { fechar() }, contentAlignment = Alignment.Center) {
                    Icone(Icones.fechar, Paleta.tintaSuave, tamanho = 18.dp, descricao = t("Fechar"))
                }
            }
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState(), enabled = arrastando == null).padding(top = Espaco.xs)) {
                ordem.forEachIndexed { indice, carteira ->
                    val selecionada = carteira.id == estado.selecionada || (estado.selecionada == null && indice == 0)
                    val esta = arrastando == carteira.id
                    val origem = ordem.indexOfFirst { it.id == arrastando }
                    val alvo = if (origem >= 0) (origem + (deslocamento / alturaDaLinha).roundToInt()).coerceIn(0, ordem.lastIndex) else -1
                    val abre = when {
                        origem < 0 || esta -> 0f
                        origem < alvo && indice in (origem + 1)..alvo -> -alturaDaLinha
                        origem > alvo && indice in alvo until origem -> alturaDaLinha
                        else -> 0f
                    }
                    val desliza by animateFloatAsState(abre, label = "abre")
                    Row(
                        Modifier.fillMaxWidth().height(Altura.linha).zIndex(if (esta) 1f else 0f)
                            .graphicsLayer { translationY = if (esta) deslocamento else desliza }
                            .scale(if (esta) 1.03f else 1f)
                            .background(if (selecionada || esta) Paleta.trilho else Paleta.corpo)
                            .pointerInput(carteira.id, ordem) {
                                detectDragGesturesAfterLongPress(
                                    onDragStart = {
                                        arrastando = carteira.id
                                        deslocamento = 0f
                                        haptico.performHapticFeedback(HapticFeedbackType.LongPress)
                                    },
                                    onDrag = { mudanca, arraste ->
                                        mudanca.consume()
                                        deslocamento += arraste.y
                                    },
                                    onDragEnd = {
                                        val de = ordem.indexOfFirst { it.id == arrastando }
                                        val para = (de + (deslocamento / alturaDaLinha).roundToInt()).coerceIn(0, ordem.lastIndex)
                                        if (de >= 0 && para != de) {
                                            val nova = ordem.toMutableList().apply { add(para, removeAt(de)) }
                                            ordem = nova
                                            escopo.launch {
                                                runCatching { App.aplicar(Api.objeto("carteira.ordenar", JSONObject().put("ids", JSONArray(nova.map { it.id })))) }
                                            }
                                        }
                                        arrastando = null
                                        deslocamento = 0f
                                    },
                                    onDragCancel = {
                                        arrastando = null
                                        deslocamento = 0f
                                    },
                                )
                            }
                            .clickable {
                                escopo.launch { runCatching { App.aplicar(Api.objeto("carteira.selecionar", JSONObject().put("id", carteira.id))) } }
                                fechar()
                            }
                            .padding(start = Espaco.margem, end = Espaco.xs),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                    ) {
                        GlifoDaCarteira(carteira, selecionada = selecionada)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(carteira.nome, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(subtituloDaCarteira(carteira), style = estilo(Tipo.nota),
                                 color = if (!carteira.temCopia && !carteira.observacao) Paleta.cautela else Paleta.tintaSuave, maxLines = 1)
                        }
                        if (selecionada) Icone(Icones.visto, Paleta.tinta, tamanho = 16.dp)
                        if (carteira.contas.isNotEmpty()) {
                            Box(Modifier.size(width = 36.dp, height = Altura.toque).clickable { copiando = carteira }, contentAlignment = Alignment.Center) {
                                Icone(Icones.copiar, Paleta.tintaSuave, tamanho = 15.dp, descricao = t("Copiar endereço de %@", carteira.nome))
                            }
                        }
                        Box(Modifier.size(Altura.toque).clickable { renomeando = carteira }, contentAlignment = Alignment.Center) {
                            Icone(Icones.lapis, Paleta.tintaSuave, tamanho = 15.dp, descricao = t("Editar o nome de %@", carteira.nome))
                        }
                    }
                }
                if (ordem.size > 1) {
                    Text(t("Segure uma carteira e arraste para mudar a ordem."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                         modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm))
                }
            }
            BotaoPrimario(t("Adicionar carteira"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md, bottom = Espaco.xs)) {
                fechar { Navegacao.abrir { AdicionarCarteira(primeira = false) { Navegacao.fechar() } } }
            }
        }
    }

    renomeando?.let { carteira -> Renomear(carteira) { renomeando = null } }
    copiando?.let { carteira -> CopiarEndereco(carteira) { copiando = null } }
}

@Composable
private fun Renomear(carteira: Carteira, aoFechar: () -> Unit) {
    val escopo = rememberCoroutineScope()
    var nome by remember { mutableStateOf(carteira.nome) }
    AlertDialog(
        onDismissRequest = aoFechar, containerColor = Paleta.corpo, shape = RoundedCornerShape(Raio.folha),
        title = { Text(t("Nome da carteira"), style = estilo(Tipo.cabecalho), color = Paleta.tinta) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                Text(t("Só aparece neste celular."), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                Box(
                    Modifier.fillMaxWidth().height(Altura.campo).background(Paleta.vazio, RoundedCornerShape(Raio.cartao))
                        .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(horizontal = Espaco.md),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    BasicTextField(
                        nome, { nome = it.take(40) }, singleLine = true, textStyle = estilo(Tipo.linha).copy(color = Paleta.tinta),
                        cursorBrush = SolidColor(Paleta.acento), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        },
        confirmButton = {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                BotaoPrimario(t("Salvar"), ligado = nome.isNotBlank()) {
                    // Sem controle nem caractere invisivel, ate 40: o mesmo saneamento dos nomes de envelope.
                    val limpo = nome.filter { !it.isISOControl() && Character.getType(it) != Character.FORMAT.toInt() }.trim().take(40)
                    escopo.launch {
                        if (limpo.isNotEmpty()) runCatching { App.aplicar(Api.objeto("carteira.renomear", JSONObject().put("id", carteira.id).put("nome", limpo))) }
                        aoFechar()
                    }
                }
                BotaoSecundario(t("Cancelar"), acao = aoFechar)
            }
        },
    )
}

/**
 * Copiar o endereco de uma carteira, por rede: a EVM e uma linha so (o mesmo endereco em todas), e
 * cada outra rede com endereco proprio. A area de transferencia e a do Receber (sensivel, 2 minutos).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CopiarEndereco(carteira: Carteira, aoFechar: () -> Unit) {
    val contexto = LocalContext.current
    val escopo = rememberCoroutineScope()
    val folha = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var abertas by remember { mutableStateOf(false) }
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
        Transferencia.copiar(contexto, endereco)
        escopo.launch { folha.hide() }.invokeOnCompletion {
            aoFechar()
            Avisos.mostrar(t("Endereço %@ copiado. Depois de colar, confira o endereço inteiro, inclusive o meio.", titulo))
        }
    }

    ModalBottomSheet(onDismissRequest = aoFechar, sheetState = folha, containerColor = Paleta.vazio, dragHandle = null,
                     shape = RoundedCornerShape(topStart = Raio.folha, topEnd = Raio.folha)) {
        Column(Modifier.navigationBarsPadding().padding(bottom = Espaco.md)) {
            Box(Modifier.fillMaxWidth().height(Altura.barra + Espaco.xs)) {
                Text(t("Copiar endereço"), style = estilo(Tipo.acao), color = Paleta.tinta, modifier = Modifier.align(Alignment.Center))
                Box(Modifier.align(Alignment.CenterEnd).padding(end = Espaco.xs).size(Altura.toque).clickable { aoFechar() }, contentAlignment = Alignment.Center) {
                    Icone(Icones.fechar, Paleta.tintaSuave, tamanho = 18.dp, descricao = t("Fechar"))
                }
            }
            Text(t("Escolha a rede. Depois de colar, confira o endereço inteiro, inclusive o meio."), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
                 modifier = Modifier.padding(horizontal = Espaco.margem))
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(top = Espaco.md),
                   verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                if (evm.isNotEmpty()) {
                    val endereco = carteira.endereco(evm.first().id)!!
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)) {
                        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = Espaco.sm), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                            Row(Modifier.weight(1f).clickable { abertas = !abertas }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                                SeloDaRede(evm.first().id, evm.first().coingecko, 32.dp, Paleta.corpo)
                                Column(Modifier.weight(1f).padding(vertical = Espaco.xs), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(t("Ethereum e redes EVM"), style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text(t("%lld redes", evm.size), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                                        Icone(if (abertas) Icones.acima else Icones.abaixo, Paleta.tintaApagada, tamanho = 10.dp)
                                    }
                                    Text(app.escalibur.wallet.ui.Formato.endereco(endereco), style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
                                }
                            }
                            Box(Modifier.size(Altura.toque + Espaco.xs).clickable { copiar(t("Ethereum e redes EVM"), endereco) }, contentAlignment = Alignment.Center) {
                                Icone(Icones.copiar, Paleta.tintaSuave, tamanho = 15.dp, descricao = t("Copiar"))
                            }
                        }
                        if (abertas) {
                            Column(Modifier.padding(start = Espaco.sm, end = Espaco.sm, bottom = Espaco.sm), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                                for (rede in evm) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                                        SeloDaRede(rede.id, rede.coingecko, 18.dp, Paleta.corpo)
                                        Text(rede.nome, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                                    }
                                }
                            }
                        }
                    }
                }
                for ((rede, endereco) in outras) {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 64.dp).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
                            .clickable { copiar(rede.nome, endereco) }.padding(horizontal = Espaco.sm),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                    ) {
                        SeloDaRede(rede.id, rede.coingecko, 32.dp, Paleta.corpo)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(rede.nome, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                            Text(app.escalibur.wallet.ui.Formato.endereco(endereco), style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1)
                        }
                        Spacer(Modifier.width(Espaco.xs))
                        Icone(Icones.copiar, Paleta.tintaSuave, tamanho = 15.dp)
                    }
                }
            }
        }
    }
}
