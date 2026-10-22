package app.escalibur.wallet.ui.importar

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Chip
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** As 2048 palavras em ingles, por letra, com os bytes de cada uma para comparar sem texto da frase. */
private object PalavrasEmIngles {
    private var carregadas: List<Pair<String, ByteArray>>? = null

    fun todas(contexto: android.content.Context): List<Pair<String, ByteArray>> = carregadas ?: run {
        val lista = contexto.assets.open("nucleo/Wordlists/english.txt").bufferedReader().readLines()
            .map { it.trim() }.filter { it.isNotEmpty() }.map { it to it.toByteArray(Charsets.UTF_8) }
        carregadas = lista
        lista
    }
}

/**
 * As 2048 palavras em ingles para escolher tocando (o WordListPicker do iOS), por letra, sem teclado
 * nenhum. Cada toque preenche a proxima posicao vazia; a escolhida fica em verde, com o numero da
 * posicao, enquanto estiver na frase, e tocar de novo desmarca. A lista e publica, mas a sequencia
 * tocada nao: a janela inteira fica fora das capturas (FLAG_SECURE).
 */
@Composable
fun ListaDePalavras(entrada: EntradaDaFrase, aoEscolher: (String) -> Unit, aoTirar: (Int) -> Unit, aoFechar: () -> Unit) {
    val contexto = LocalContext.current
    val palavras = remember { PalavrasEmIngles.todas(contexto) }
    val letras = remember(palavras) { palavras.map { it.first.take(1) }.distinct().sorted() }
    val porLetra = remember(palavras) { palavras.groupBy { it.first.take(1) } }
    val haptico = LocalHapticFeedback.current
    val escopo = rememberCoroutineScope()
    val estado = rememberLazyListState()
    // A palavra que acabou de ser tocada da um pulo.
    var piscando by remember { mutableStateOf<String?>(null) }
    var toque by remember { mutableIntStateOf(0) }
    @Suppress("UNUSED_VARIABLE") val revisao = entrada.revisao
    val preenchidas = entrada.preenchidas
    val total = entrada.quantidade

    Column(Modifier.fillMaxSize().background(Paleta.vazio)) {
        CabecalhoDeFolha(t("Lista de palavras"), aoFechar)
        Text(
            if (preenchidas < total) t("Toque numa palavra para preencher a %lldª de %lld.", preenchidas + 1, total)
            else t("As %lld estão preenchidas.", total),
            style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xs),
        )
        // A barra enche a cada palavra.
        val fracao by animateFloatAsState(if (total > 0) preenchidas.toFloat() / total else 0f, spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow), label = "barra")
        Box(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xs).fillMaxWidth().height(4.dp).clip(CircleShape).background(Paleta.trilho)) {
            Box(Modifier.fillMaxHeight().fillMaxWidth(fracao).clip(CircleShape).background(Paleta.sucesso))
        }
        LazyRow(
            Modifier.padding(vertical = Espaco.sm), contentPadding = PaddingValues(horizontal = Espaco.margem),
            horizontalArrangement = Arrangement.spacedBy(Espaco.xs),
        ) {
            items(letras) { letra ->
                Chip(letra.uppercase(), selecionado = false) {
                    escopo.launch { estado.animateScrollToItem(letras.indexOf(letra)) }
                }
            }
        }
        LazyColumn(state = estado, contentPadding = PaddingValues(start = Espaco.margem, end = Espaco.margem, bottom = Espaco.xl),
                   verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
            items(letras, key = { it }) { letra ->
                Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Text(letra.uppercase(), style = estilo(Tipo.cabecalho), color = Paleta.tintaApagada)
                    BoxWithConstraints(Modifier.fillMaxWidth()) {
                        // Colunas de pelo menos 104, como o grid adaptavel do iOS.
                        val colunas = maxOf(1, ((maxWidth + Espaco.xs) / (104.dp + Espaco.xs)).toInt())
                        Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                            (porLetra[letra] ?: emptyList()).chunked(colunas).forEach { linha ->
                                Row(horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                                    linha.forEach { (palavra, bytes) ->
                                        val lugares = entrada.lugares(bytes)
                                        val acesa = lugares.isNotEmpty()
                                        val ligada = acesa || preenchidas < total
                                        val escala by animateFloatAsState(if (piscando == palavra) 1.04f else 1f,
                                                                           spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessMedium), label = "pulo")
                                        Box(
                                            Modifier.weight(1f).heightIn(min = 40.dp).scale(escala).clip(RoundedCornerShape(Raio.cartao))
                                                .background(if (acesa) Paleta.sucesso else Paleta.corpo)
                                                .clickable(enabled = ligada, role = Role.Button) {
                                                    haptico.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                                    if (acesa) aoTirar(lugares.last())
                                                    else {
                                                        aoEscolher(palavra)
                                                        toque++
                                                        val este = toque
                                                        piscando = palavra
                                                        escopo.launch {
                                                            delay(650)
                                                            if (toque == este) piscando = null
                                                        }
                                                    }
                                                }
                                                .semantics { contentDescription = if (acesa) palavra + ", " + t("escolhida, toque para tirar") else palavra },
                                            contentAlignment = Alignment.Center,
                                        ) {
                                            Text(palavra, fontSize = 15.sp, fontWeight = if (acesa) FontWeight.SemiBold else FontWeight.Medium,
                                                 color = if (acesa) Paleta.vazio else if (ligada) Paleta.tinta else Paleta.tintaApagada,
                                                 style = estilo(Tipo.corpo))
                                            if (acesa) {
                                                Text(lugares.joinToString("·") { "${it + 1}" }, fontSize = 10.sp, fontWeight = FontWeight.Bold,
                                                     color = Paleta.vazio.copy(alpha = 0.7f),
                                                     modifier = Modifier.align(Alignment.TopEnd).padding(top = 4.dp, end = 7.dp))
                                            }
                                        }
                                    }
                                    repeat(colunas - linha.size) { Spacer(Modifier.weight(1f)) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
