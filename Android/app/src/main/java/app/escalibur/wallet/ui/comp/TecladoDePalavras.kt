package app.escalibur.wallet.ui.comp

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
import androidx.compose.foundation.layout.RowScope
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
import org.json.JSONObject

/** As palavras da lista que comecam com o que foi digitado, e as letras que ainda levam a alguma. */
data class Sugestoes(val palavras: List<String>, val letras: Set<Char>) {
    companion object {
        suspend fun de(digitado: String): Sugestoes = runCatching {
            val json = Api.objeto("carteira.sugestoes", JSONObject().put("digitado", digitado))
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
 * O teclado proprio das palavras: so letras minusculas de a a z, apagar e seguir. As letras que nao
 * levam a nenhuma palavra da lista ficam apagadas. Nada passa pelo teclado do sistema, que pode ser
 * de terceiros e aprender o que se digita.
 */
@Composable
fun TecladoDePalavras(
    digitado: String, modifier: Modifier = Modifier, letrasPossiveis: Set<Char>? = null,
    aoDigitar: (Char) -> Unit, aoApagar: () -> Unit, aoSeguir: (() -> Unit)? = null, tituloDoSeguir: String = t("Próxima"),
) {
    val linhas = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
    val haptico = LocalHapticFeedback.current
    Column(
        modifier.fillMaxWidth().background(Paleta.corpo).navigationBarsPadding().padding(horizontal = 4.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        linhas.forEachIndexed { indice, linha ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                if (indice == 1) Spacer(Modifier.weight(0.5f))
                if (indice == 2) Spacer(Modifier.weight(0.6f))
                for (letra in linha) {
                    val possivel = letrasPossiveis?.contains(letra) ?: true
                    Tecla(letra.toString(), Modifier.weight(1f), ligada = possivel) {
                        haptico.performHapticFeedback(HapticFeedbackType.KeyboardTap)
                        aoDigitar(letra)
                    }
                }
                if (indice == 1) Spacer(Modifier.weight(0.5f))
                if (indice == 2) {
                    TeclaDeIcone(Icones.apagarLetra, t("Apagar"), Modifier.weight(1.4f), ligada = digitado.isNotEmpty()) {
                        haptico.performHapticFeedback(HapticFeedbackType.KeyboardTap)
                        aoApagar()
                    }
                }
            }
        }
        if (aoSeguir != null) {
            Row(Modifier.fillMaxWidth()) {
                Tecla(tituloDoSeguir, Modifier.weight(1f), ligada = digitado.isNotEmpty(), destaque = true) { aoSeguir() }
            }
        }
    }
}

@Composable
private fun RowScope.Tecla(texto: String, modifier: Modifier, ligada: Boolean, destaque: Boolean = false, acao: () -> Unit) {
    val interacao = remember { MutableInteractionSource() }
    val apertada by interacao.collectIsPressedAsState()
    Box(
        modifier.height(46.dp).clip(RoundedCornerShape(7.dp))
            .background(
                when {
                    destaque && ligada -> if (apertada) Paleta.acentoApertado else Paleta.acento
                    apertada -> Paleta.bordaForte
                    else -> Paleta.controle
                }
            )
            .clickable(interacao, indication = null, enabled = ligada, onClick = acao),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            texto, fontSize = if (texto.length == 1) 21.sp else 15.sp, fontWeight = if (texto.length == 1) FontWeight.Normal else FontWeight.SemiBold,
            color = when {
                !ligada -> Paleta.tintaMorta
                destaque -> Paleta.sobreAcento
                else -> Paleta.tinta
            },
        )
    }
}

@Composable
private fun RowScope.TeclaDeIcone(icone: androidx.compose.ui.graphics.vector.ImageVector, descricao: String, modifier: Modifier, ligada: Boolean, acao: () -> Unit) {
    Box(
        modifier.height(46.dp).clip(RoundedCornerShape(7.dp)).background(Paleta.trilho).clickable(enabled = ligada, onClickLabel = descricao, onClick = acao),
        contentAlignment = Alignment.Center,
    ) {
        Icone(icone, if (ligada) Paleta.tinta else Paleta.tintaMorta, tamanho = 22.dp, descricao = descricao)
    }
}

/** O estado de uma palavra em digitacao no teclado proprio, com as sugestoes do nucleo. */
class PalavraEmDigitacao {
    var texto by mutableStateOf("")
    var sugestoes by mutableStateOf(Sugestoes(emptyList(), ('a'..'z').toSet()))
        private set

    suspend fun atualizar() {
        sugestoes = Sugestoes.de(texto)
    }

    fun limpar() {
        texto = ""
    }
}

@Composable
fun rememberPalavra(): PalavraEmDigitacao {
    val palavra = remember { PalavraEmDigitacao() }
    LaunchedEffect(palavra.texto) { palavra.atualizar() }
    return palavra
}
