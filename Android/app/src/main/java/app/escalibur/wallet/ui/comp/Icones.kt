package app.escalibur.wallet.ui.comp

import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Os icones do app: traco arredondado numa grade de 24, no espirito dos simbolos do iOS. Desenhados
 * aqui, sem biblioteca de icones de terceiros. `cheio` sao os de preenchimento (alerta, falha).
 */
object Icones {
    private fun traco(nome: String, vararg caminhos: String, espessura: Float = 1.9f): ImageVector =
        ImageVector.Builder(nome, 24.dp, 24.dp, 24f, 24f).apply {
            for (caminho in caminhos) {
                addPath(
                    PathParser().parsePathString(caminho).toNodes(),
                    stroke = SolidColor(Color.Black), strokeLineWidth = espessura,
                    strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round,
                )
            }
        }.build()

    private fun cheio(nome: String, vararg caminhos: String): ImageVector =
        ImageVector.Builder(nome, 24.dp, 24.dp, 24f, 24f).apply {
            for (caminho in caminhos) addPath(PathParser().parsePathString(caminho).toNodes(), fill = SolidColor(Color.Black), pathFillType = androidx.compose.ui.graphics.PathFillType.EvenOdd)
        }.build()

    val voltar = traco("voltar", "M15 4.5 L7.5 12 L15 19.5", espessura = 2.2f)
    val avancar = traco("avancar", "M9 4.5 L16.5 12 L9 19.5", espessura = 2.2f)
    val abaixo = traco("abaixo", "M5 9 L12 16 L19 9", espessura = 2.2f)
    val acima = traco("acima", "M5 15 L12 8 L19 15", espessura = 2.2f)
    val fechar = traco("fechar", "M6 6 L18 18 M18 6 L6 18", espessura = 2.2f)
    val visto = traco("visto", "M4.5 12.5 L9.5 17.5 L19.5 6.5", espessura = 2.4f)
    val mais = traco("mais", "M12 5 V19 M5 12 H19", espessura = 2.2f)
    val menos = traco("menos", "M5 12 H19", espessura = 2.2f)

    val enviar = traco("enviar", "M12 20 V4.5 M5.5 11 L12 4.5 L18.5 11", espessura = 2.1f)
    val receber = traco("receber", "M12 4 V19.5 M5.5 13 L12 19.5 L18.5 13", espessura = 2.1f)
    val trocar = traco("trocar", "M4 8 H19 M15 4 L19 8 L15 12 M20 16 H5 M9 12 L5 16 L9 20")
    val trocarVertical = traco("trocarVertical", "M8 20 V5 M4 9 L8 5 L12 9 M16 4 V19 M12 15 L16 19 L20 15")
    val setaDiagonal = traco("setaDiagonal", "M7 17 L17 7 M9 7 H17 V15")
    val atualizar = traco("atualizar", "M19.5 12 A7.5 7.5 0 1 1 17.3 6.7 M19.5 4 V8.5 H15")

    val copiar = traco(
        "copiar",
        "M9 8.5 H18 A1.5 1.5 0 0 1 19.5 10 V19 A1.5 1.5 0 0 1 18 20.5 H9 A1.5 1.5 0 0 1 7.5 19 V10 A1.5 1.5 0 0 1 9 8.5 Z",
        "M16.5 5.5 V5 A1.5 1.5 0 0 0 15 3.5 H6 A1.5 1.5 0 0 0 4.5 5 V14 A1.5 1.5 0 0 0 6 15.5 H7.5",
    )
    val colar = traco(
        "colar",
        "M9 4.5 H15 V7 H9 Z",
        "M15 5.5 H17.5 A1.5 1.5 0 0 1 19 7 V19 A1.5 1.5 0 0 1 17.5 20.5 H6.5 A1.5 1.5 0 0 1 5 19 V7 A1.5 1.5 0 0 1 6.5 5.5 H9",
    )
    val compartilhar = traco("compartilhar", "M12 15 V3.5 M8 7.5 L12 3.5 L16 7.5 M8 11 H6.5 A1.5 1.5 0 0 0 5 12.5 V19 A1.5 1.5 0 0 0 6.5 20.5 H17.5 A1.5 1.5 0 0 0 19 19 V12.5 A1.5 1.5 0 0 0 17.5 11 H16")
    val olho = traco("olho", "M2.5 12 C5 7 8.5 5 12 5 C15.5 5 19 7 21.5 12 C19 17 15.5 19 12 19 C8.5 19 5 17 2.5 12 Z", "M12 15 A3 3 0 1 0 12 9 A3 3 0 1 0 12 15 Z")
    val olhoRiscado = traco("olhoRiscado", "M4 4 L20 20", "M9.9 5.3 C10.6 5.1 11.3 5 12 5 C15.5 5 19 7 21.5 12 C20.8 13.4 20 14.6 19.1 15.6 M15.5 17.9 C14.4 18.6 13.2 19 12 19 C8.5 19 5 17 2.5 12 C3.4 10.2 4.5 8.8 5.7 7.7")
    val cadeado = traco("cadeado", "M7.5 10.5 V7.5 A4.5 4.5 0 0 1 16.5 7.5 V10.5", "M6.5 10.5 H17.5 A1.5 1.5 0 0 1 19 12 V19 A1.5 1.5 0 0 1 17.5 20.5 H6.5 A1.5 1.5 0 0 1 5 19 V12 A1.5 1.5 0 0 1 6.5 10.5 Z")
    val escudo = traco("escudo", "M12 3 L19.5 6 V11.5 C19.5 16 16.3 19.4 12 21 C7.7 19.4 4.5 16 4.5 11.5 V6 Z", "M8.5 12 L11 14.5 L15.5 9.5")
    val digital = traco(
        "digital",
        "M5.5 10 C6.4 6.6 9 4.5 12 4.5 C15.9 4.5 19 7.6 19 11.5 V13",
        "M8 19.5 C7.4 17.6 7 15.4 7 12.5 C7 9.7 9.2 7.5 12 7.5 C14.8 7.5 17 9.7 17 12.5 V14",
        "M12 10.5 C10.9 10.5 10 11.4 10 12.5 C10 15.6 10.6 18.2 11.7 20.3",
        "M14.6 20 C14.2 18.2 14 16 14 13.5 V12.5 C14 11.4 13.1 10.5 12 10.5",
        "M4.5 14.5 C4.6 15.7 4.8 16.7 5.1 17.6",
    )
    val celular = traco("celular", "M8 2.5 H16 A2 2 0 0 1 18 4.5 V19.5 A2 2 0 0 1 16 21.5 H8 A2 2 0 0 1 6 19.5 V4.5 A2 2 0 0 1 8 2.5 Z", "M10.5 18.5 H13.5")
    val celularRiscado = traco("celularRiscado", "M3.5 3.5 L20.5 20.5", "M9 2.5 H16 A2 2 0 0 1 18 4.5 V14.5 M18 18.5 V19.5 A2 2 0 0 1 16 21.5 H8 A2 2 0 0 1 6 19.5 V6.5")
    val lapis = traco("lapis", "M15.5 4.5 L19.5 8.5 L8.5 19.5 L4 20 L4.5 15.5 Z", "M13.5 6.5 L17.5 10.5")
    val relogio = traco("relogio", "M12 21 A9 9 0 1 0 12 3 A9 9 0 1 0 12 21 Z", "M12 7 V12 L15.5 14")
    val ampulheta = traco("ampulheta", "M6.5 3.5 H17.5 M6.5 20.5 H17.5 M7.5 3.5 C7.5 8 12 9.5 12 12 C12 14.5 7.5 16 7.5 20.5 M16.5 3.5 C16.5 8 12 9.5 12 12 C12 14.5 16.5 16 16.5 20.5")
    val busca = traco("busca", "M10.5 17.5 A7 7 0 1 0 10.5 3.5 A7 7 0 1 0 10.5 17.5 Z", "M15.6 15.6 L20.5 20.5")
    val info = traco("info", "M12 21 A9 9 0 1 0 12 3 A9 9 0 1 0 12 21 Z", "M12 11 V16.5", "M12 7.6 V7.7", espessura = 2f)
    val pergunta = traco("pergunta", "M12 21 A9 9 0 1 0 12 3 A9 9 0 1 0 12 21 Z", "M9.5 9.3 C9.7 8 10.8 7 12.2 7 C13.6 7 14.7 8.1 14.7 9.4 C14.7 11.4 12 11.6 12 13.6", "M12 16.8 V16.9")
    val globo = traco("globo", "M12 21 A9 9 0 1 0 12 3 A9 9 0 1 0 12 21 Z", "M3 12 H21", "M12 3 C14.5 5.5 15.5 8.7 15.5 12 C15.5 15.3 14.5 18.5 12 21 C9.5 18.5 8.5 15.3 8.5 12 C8.5 8.7 9.5 5.5 12 3 Z")
    val sino = traco("sino", "M6 16.5 V11 A6 6 0 0 1 18 11 V16.5 L19.5 18 H4.5 Z", "M10 20.5 H14")
    val estrela = traco("estrela", "M12 3.5 L14.6 8.9 L20.5 9.6 L16.2 13.7 L17.3 19.6 L12 16.8 L6.7 19.6 L7.8 13.7 L3.5 9.6 L9.4 8.9 Z")
    val lixeira = traco("lixeira", "M4.5 6.5 H19.5 M9.5 6.5 V4.5 H14.5 V6.5 M6.5 6.5 L7.5 20.5 H16.5 L17.5 6.5", "M10 10.5 V16.5 M14 10.5 V16.5")
    val apagarLetra = traco("apagarLetra", "M9 5.5 H19 A1.5 1.5 0 0 1 20.5 7 V17 A1.5 1.5 0 0 1 19 18.5 H9 L3.5 12 Z", "M11.5 9.5 L16 14 M16 9.5 L11.5 14")
    val teclado = traco("teclado", "M3.5 6.5 H20.5 V16.5 H3.5 Z", "M7 10 H7.1 M10.5 10 H10.6 M14 10 H14.1 M17.5 10 H17.6 M8 13.5 H16")
    val qr = traco("qr", "M4 4 H10 V10 H4 Z M14 4 H20 V10 H14 Z M4 14 H10 V20 H4 Z", "M14 14 H16 M18 14 H20 V16 M14 18 V20 H16 M18 18 H20 V20 M16 16 H18 V18")
    val camera = traco("camera", "M4.5 7.5 H8 L9.5 5 H14.5 L16 7.5 H19.5 A1.5 1.5 0 0 1 21 9 V18 A1.5 1.5 0 0 1 19.5 19.5 H4.5 A1.5 1.5 0 0 1 3 18 V9 A1.5 1.5 0 0 1 4.5 7.5 Z", "M12 16.5 A3.5 3.5 0 1 0 12 9.5 A3.5 3.5 0 1 0 12 16.5 Z")
    val documento = traco("documento", "M6.5 3 H14 L18.5 7.5 V19.5 A1.5 1.5 0 0 1 17 21 H6.5 A1.5 1.5 0 0 1 5 19.5 V4.5 A1.5 1.5 0 0 1 6.5 3 Z", "M14 3 V7.5 H18.5", "M8.5 12 H15 M8.5 15.5 H15")
    val reticencias = traco("reticencias", "M6 12 H6.1 M12 12 H12.1 M18 12 H18.1", espessura = 2.8f)
    val ajustes = traco(
        "ajustes",
        "M12 15 A3 3 0 1 0 12 9 A3 3 0 1 0 12 15 Z",
        "M10.3 3.5 H13.7 L14.2 5.9 L15.8 6.8 L18.1 6 L19.8 8.9 L18 10.6 V12.4 V13.4 L19.8 15.1 L18.1 18 L15.8 17.2 L14.2 18.1 L13.7 20.5 H10.3 L9.8 18.1 L8.2 17.2 L5.9 18 L4.2 15.1 L6 13.4 V10.6 L4.2 8.9 L5.9 6 L8.2 6.8 L9.8 5.9 Z",
    )
    val carteira = traco("carteira", "M4.5 7 H18 A1.5 1.5 0 0 1 19.5 8.5 V18 A1.5 1.5 0 0 1 18 19.5 H6 A1.5 1.5 0 0 1 4.5 18 V7 Z M4.5 7 V6 A1.5 1.5 0 0 1 6 4.5 H16", "M15 12 H19.5 V15 H15 A1.5 1.5 0 0 1 15 12 Z")
    val mercado = traco("mercado", "M3.5 17.5 L9 11.5 L13 15 L20.5 7", "M15.5 7 H20.5 V12", "M3.5 20.5 H20.5")
    val atividade = traco("atividade", "M4 12 A8 8 0 1 0 6.3 6.3", "M3.5 4 V7.5 H7", "M12 8 V12 L14.5 14.5")
    val envelope = traco("envelope", "M4.5 6 H19.5 A1.5 1.5 0 0 1 21 7.5 V16.5 A1.5 1.5 0 0 1 19.5 18 H4.5 A1.5 1.5 0 0 1 3 16.5 V7.5 A1.5 1.5 0 0 1 4.5 6 Z", "M3.5 7 L12 13 L20.5 7")
    val chave = traco("chave", "M8 16 A4 4 0 1 0 8 8 A4 4 0 1 0 8 16 Z", "M12 12 H20.5 M17.5 12 V15 M20.5 12 V14")
    val pessoas = traco("pessoas", "M9 11 A3.5 3.5 0 1 0 9 4 A3.5 3.5 0 1 0 9 11 Z", "M3 19.5 C3 16.5 5.7 14.5 9 14.5 C12.3 14.5 15 16.5 15 19.5", "M16 4.3 A3.5 3.5 0 0 1 16 10.7 M18 14.8 C19.9 15.5 21 17.2 21 19.5")
    val microfone = traco("microfone", "M12 15 A3 3 0 0 0 15 12 V6 A3 3 0 0 0 9 6 V12 A3 3 0 0 0 12 15 Z", "M5.5 11.5 A6.5 6.5 0 0 0 18.5 11.5 M12 18 V21")
    val sair = traco("sair", "M14 4.5 H18 A1.5 1.5 0 0 1 19.5 6 V18 A1.5 1.5 0 0 1 18 19.5 H14", "M10 8 L6 12 L10 16 M6 12 H15")
    val marcador = traco("marcador", "M7 3.5 H17 V20.5 L12 16.5 L7 20.5 Z")

    val alerta = cheio("alerta", "M12 2.8 C12.6 2.8 13.1 3.1 13.4 3.6 L22.1 18.6 C22.7 19.6 22 21 20.7 21 H3.3 C2 21 1.3 19.6 1.9 18.6 L10.6 3.6 C10.9 3.1 11.4 2.8 12 2.8 Z M11 9 V14 H13 V9 Z M11 16 V18 H13 V16 Z")
    val falha = cheio("falha", "M8.3 2.5 H15.7 L21.5 8.3 V15.7 L15.7 21.5 H8.3 L2.5 15.7 V8.3 Z M8.5 7.1 L7.1 8.5 L10.6 12 L7.1 15.5 L8.5 16.9 L12 13.4 L15.5 16.9 L16.9 15.5 L13.4 12 L16.9 8.5 L15.5 7.1 L12 10.6 Z")
    val vistoCheio = cheio("vistoCheio", "M12 2 A10 10 0 1 1 12 22 A10 10 0 1 1 12 2 Z M10.6 15.8 L17.3 9.1 L15.9 7.7 L10.6 13 L8.1 10.5 L6.7 11.9 Z")
    val fecharCheio = cheio("fecharCheio", "M12 2 A10 10 0 1 1 12 22 A10 10 0 1 1 12 2 Z M8.5 7.1 L7.1 8.5 L10.6 12 L7.1 15.5 L8.5 16.9 L12 13.4 L15.5 16.9 L16.9 15.5 L13.4 12 L16.9 8.5 L15.5 7.1 L12 10.6 Z")
    val cadeadoCheio = cheio("cadeadoCheio", "M7 10 V7.5 A5 5 0 0 1 17 7.5 V10 H17.5 A2 2 0 0 1 19.5 12 V19 A2 2 0 0 1 17.5 21 H6.5 A2 2 0 0 1 4.5 19 V12 A2 2 0 0 1 6.5 10 Z M9 10 H15 V7.5 A3 3 0 0 0 9 7.5 Z")
}

@Composable
fun Icone(icone: ImageVector, cor: Color, tamanho: Dp = 20.dp, modifier: Modifier = Modifier, descricao: String? = null) {
    Icon(icone, contentDescription = descricao, tint = cor, modifier = modifier.size(tamanho))
}
