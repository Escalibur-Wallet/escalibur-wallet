package app.escalibur.wallet.ui.legal

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.Textos
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo

/**
 * Termos de uso e Politica de privacidade, lidos do proprio app: nenhum texto legal vem da internet,
 * entao o que o dono aceitou e o que esta nesta versao. Em portugues, o original; nos outros
 * idiomas, a traducao em ingles, que diz no comeco que o portugues prevalece.
 */
enum class DocumentoLegal(val arquivo: String) {
    termos("termos"), privacidade("privacidade");

    val titulo: String get() = if (this == termos) t("Termos de uso") else t("Política de privacidade")

    sealed class Bloco {
        data class Titulo(val texto: String) : Bloco()
        data class Item(val texto: String) : Bloco()
        data class Paragrafo(val texto: String) : Bloco()
    }

    fun blocos(contexto: Context): List<Bloco> {
        val nomes = if (Textos.idioma == "pt-BR") listOf(arquivo) else listOf("$arquivo-en", arquivo)
        for (nome in nomes) {
            val texto = runCatching { contexto.assets.open("legal/$nome.md").use { it.readBytes().decodeToString() } }.getOrNull() ?: continue
            return ler(texto)
        }
        return emptyList()
    }

    companion object {
        fun ler(texto: String): List<Bloco> {
            val blocos = mutableListOf<Bloco>()
            val paragrafo = mutableListOf<String>()
            fun fechar() {
                if (paragrafo.isNotEmpty()) blocos += Bloco.Paragrafo(paragrafo.joinToString(" "))
                paragrafo.clear()
            }
            for (cru in texto.lines()) {
                val linha = cru.trim()
                when {
                    linha.isEmpty() -> fechar()
                    linha.startsWith("<!--") -> Unit // nota interna, nunca mostrada
                    linha.startsWith("# ") -> fechar()
                    linha.startsWith("## ") -> { fechar(); blocos += Bloco.Titulo(linha.drop(3)) }
                    linha.startsWith("- ") -> { fechar(); blocos += Bloco.Item(linha.drop(2)) }
                    else -> paragrafo += linha
                }
            }
            fechar()
            return blocos
        }

        /** O negrito do markdown (**assim**) vira negrito; o resto fica como esta. */
        fun comNegrito(texto: String): AnnotatedString = buildAnnotatedString {
            val partes = texto.split("**")
            partes.forEachIndexed { indice, parte ->
                if (indice % 2 == 1) pushStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = Paleta.tinta))
                append(parte.replace("`", ""))
                if (indice % 2 == 1) pop()
            }
        }
    }
}

@Composable
fun FolhaLegal(documento: DocumentoLegal, aoFechar: () -> Unit) {
    BackHandler(onBack = aoFechar)
    val contexto = LocalContext.current
    val blocos = remember(documento) { documento.blocos(contexto) }
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
        CabecalhoDeFolha(documento.titulo, aoFechar)
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.xl),
            verticalArrangement = Arrangement.spacedBy(Espaco.sm),
        ) {
            for (bloco in blocos) {
                when (bloco) {
                    is DocumentoLegal.Bloco.Titulo -> Text(bloco.texto, style = estilo(Tipo.cabecalho), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.md))
                    is DocumentoLegal.Bloco.Item -> Row(horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                        Text("•", style = estilo(Tipo.corpo), color = Paleta.tintaApagada)
                        Text(DocumentoLegal.comNegrito(bloco.texto), style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                    }
                    is DocumentoLegal.Bloco.Paragrafo -> Text(DocumentoLegal.comNegrito(bloco.texto), style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                }
            }
        }
    }
}
