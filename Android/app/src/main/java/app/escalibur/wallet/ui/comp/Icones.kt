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

    /** Cheio com os cantos arredondados: o mesmo caminho, preenchido e contornado na mesma cor. */
    private fun cheioRedondo(nome: String, caminho: String, raio: Float): ImageVector =
        ImageVector.Builder(nome, 24.dp, 24.dp, 24f, 24f).apply {
            addPath(PathParser().parsePathString(caminho).toNodes(), fill = SolidColor(Color.Black), stroke = SolidColor(Color.Black),
                    strokeLineWidth = raio * 2, strokeLineJoin = StrokeJoin.Round, pathFillType = androidx.compose.ui.graphics.PathFillType.EvenOdd)
        }.build()

    /** Traco com uma parte cheia (a ponta de seta do grafico, a do relogio). */
    private fun tracoComPonta(nome: String, traco: String, ponta: String, espessura: Float): ImageVector =
        ImageVector.Builder(nome, 24.dp, 24.dp, 24f, 24f).apply {
            addPath(PathParser().parsePathString(traco).toNodes(), stroke = SolidColor(Color.Black), strokeLineWidth = espessura,
                    strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round)
            addPath(PathParser().parsePathString(ponta).toNodes(), fill = SolidColor(Color.Black), stroke = SolidColor(Color.Black),
                    strokeLineWidth = espessura * 0.5f, strokeLineJoin = StrokeJoin.Round)
        }.build()

    private fun cheio(nome: String, vararg caminhos: String): ImageVector =
        ImageVector.Builder(nome, 24.dp, 24.dp, 24f, 24f).apply {
            for (caminho in caminhos) addPath(PathParser().parsePathString(caminho).toNodes(), fill = SolidColor(Color.Black), pathFillType = androidx.compose.ui.graphics.PathFillType.EvenOdd)
        }.build()

    val alertaContorno = traco("alertaContorno", "M12 3.8 L21.2 19.6 H2.8 Z", "M12 9.8 V14", "M12 16.9 V17", espessura = 2f)
    val coracao = traco("coracao", "M12 20.2 C11.2 19.6 3 14.3 3 8.9 C3 6.1 5.1 4 7.8 4 C9.6 4 11.1 5 12 6.4 C12.9 5 14.4 4 16.2 4 C18.9 4 21 6.1 21 8.9 C21 14.3 12.8 19.6 12 20.2 Z", espessura = 2f)
    val coracaoCheio = cheio("coracaoCheio", "M12 20.2 C11.2 19.6 3 14.3 3 8.9 C3 6.1 5.1 4 7.8 4 C9.6 4 11.1 5 12 6.4 C12.9 5 14.4 4 16.2 4 C18.9 4 21 6.1 21 8.9 C21 14.3 12.8 19.6 12 20.2 Z")
    val trianguloAcima = cheioRedondo("trianguloAcima", "M12 5.5 L19.5 18 H4.5 Z", raio = 1.4f)
    val trianguloAbaixo = cheioRedondo("trianguloAbaixo", "M12 18.5 L19.5 6 H4.5 Z", raio = 1.4f)
    // Os dos Ajustes, finos como os simbolos de peso regular do iOS.
    val carteiraContorno = traco("carteiraContorno",
        "M5.2 7.2 H18.4 A2.6 2.6 0 0 1 21 9.8 V18.4 A2.6 2.6 0 0 1 18.4 21 H5.6 A2.6 2.6 0 0 1 3 18.4 V7.6",
        "M3 7.6 L15.6 3.3 A1.6 1.6 0 0 1 17.7 4.8 V7.2",
        "M16.4 11.6 H21 V16.6 H16.4 A2.5 2.5 0 0 1 16.4 11.6 Z", "M16.6 14.1 H16.7", espessura = 1.55f)
    val livro = traco("livro", "M6.8 3 H18.5 A1 1 0 0 1 19.5 4 V19 A1 1 0 0 1 18.5 20 H6.8 A2.3 2.3 0 0 1 4.5 17.7 V5.3 A2.3 2.3 0 0 1 6.8 3 Z",
                      "M8.5 3 V20", "M4.5 17.7 A2.3 2.3 0 0 1 6.8 15.4 H19.5", espessura = 1.55f)
    val rede = traco("rede", "M12 21 A9 9 0 1 0 12 3 A9 9 0 1 0 12 21 Z", "M12 3 C9.3 5.5 8.2 8.7 8.2 12 C8.2 15.3 9.3 18.5 12 21 C14.7 18.5 15.8 15.3 15.8 12 C15.8 8.7 14.7 5.5 12 3 Z",
                     "M3 12 H21", "M4.4 7.2 H19.6", "M4.4 16.8 H19.6", "M12 3 V21", espessura = 1.4f)
    val receberCirculo = traco("receberCirculo", "M12 21 A9 9 0 1 0 12 3 A9 9 0 1 0 12 21 Z", "M12 7.5 V16", "M8.3 12.5 L12 16.2 L15.7 12.5", espessura = 1.55f)
    val celularComCadeado = traco("celularComCadeado", "M8 2.5 H16 A2 2 0 0 1 18 4.5 V19.5 A2 2 0 0 1 16 21.5 H8 A2 2 0 0 1 6 19.5 V4.5 A2 2 0 0 1 8 2.5 Z",
        "M10.2 11 V9.8 A1.8 1.8 0 0 1 13.8 9.8 V11", "M9.6 11 H14.4 V15 H9.6 Z", espessura = 1.7f)
    val chevronsDireita = traco("chevronsDireita", "M5.5 6 L11.5 12 L5.5 18 M12.5 6 L18.5 12 L12.5 18", espessura = 2.6f)
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
    // A seta da esquerda em cima e a da direita embaixo, longas e finas, como o arrow.left.arrow.right do iOS.
    val trocar = traco("trocar", "M2.53 5.78 H21.53 M8.61 0.9 L2.53 5.78 L8.61 10.66 M2.53 18.1 H21.53 M15.83 13.04 L21.53 18.1 L15.83 23.16", espessura = 1.55f)
    val trocarVertical = traco("trocarVertical", "M8 20 V5 M4 9 L8 5 L12 9 M16 4 V19 M12 15 L16 19 L20 15")
    val setaDiagonal = traco("setaDiagonal", "M7 17 L17 7 M9 7 H17 V15")
    val atualizar = traco("atualizar", "M19.5 12 A7.5 7.5 0 1 1 17.3 6.7 M19.5 4 V8.5 H15")

    val copiar = traco(
        "copiar",
        // Duas folhas em pe, como o doc.on.doc do iOS.
        "M10 7 H17.5 A1.8 1.8 0 0 1 19.3 8.8 V19.2 A1.8 1.8 0 0 1 17.5 21 H10 A1.8 1.8 0 0 1 8.2 19.2 V8.8 A1.8 1.8 0 0 1 10 7 Z",
        "M15.6 4.8 A1.8 1.8 0 0 0 13.8 3 H6.5 A1.8 1.8 0 0 0 4.7 4.8 V15.2 A1.8 1.8 0 0 0 6.5 17 H8.2",
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
    val escudoAlerta = traco("escudoAlerta", "M12 3 L19.5 6 V11.5 C19.5 16 16.3 19.4 12 21 C7.7 19.4 4.5 16 4.5 11.5 V6 Z", "M12 8 V12.5", "M12 15.6 V15.8", espessura = 2.1f)
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
    val sinoCheio = cheio("sinoCheio", "M12 3 A6.5 6.5 0 0 0 5.5 9.5 V15.6 L3.9 17.4 C3.4 18 3.8 19 4.6 19 H19.4 C20.2 19 20.6 18 20.1 17.4 L18.5 15.6 V9.5 A6.5 6.5 0 0 0 12 3 Z", "M9.6 20.2 A2.5 2.5 0 0 0 14.4 20.2 Z")
    /** O sino com o ponto do aviso (o bell.badge do iOS): o contorno abre onde o ponto fica. */
    val sinoComPonto = tracoComPonta("sinoComPonto", "M6 16.5 V11 A6 6 0 0 1 13.6 5.2 M17.95 10.2 Q18 10.6 18 11 V16.5 L19.5 18 H4.5 L6 16.5 M10 20.5 H14",
                                     "M19 3.7 A2.5 2.5 0 1 1 18.99 3.7 Z", 1.9f)
    /** O simbolo do bitcoin (o bitcoinsign do iOS), para os numeros redondos. */
    val bitcoin = traco("bitcoin", "M8 5 V19", "M8 5 H13 A3.25 3.25 0 0 1 13 11.5 H8", "M8 11.5 H13.8 A3.75 3.75 0 0 1 13.8 19 H8",
                        "M10.2 3 V5 M13 3 V5 M10.2 19 V21 M13 19 V21", espessura = 1.8f)
    /** O circulo cheio com o menos vazado (o minus.circle.fill do iOS). */
    val menosCirculoCheio = cheio("menosCirculoCheio", "M12 2.5 A9.5 9.5 0 1 1 11.99 2.5 Z M7.6 11.05 H16.4 A0.95 0.95 0 0 1 16.4 12.95 H7.6 A0.95 0.95 0 0 1 7.6 11.05 Z")
    /** Os nove pontos do teclado do PIN (o circle.grid.3x3 do iOS). */
    val gradeDoPin = cheio("gradeDoPin", (0..8).joinToString(" ") { i ->
        val x = 5.4f + (i % 3) * 6.6f
        val y = 5.4f + (i / 3) * 6.6f
        "M${x - 2f} $y A2 2 0 1 0 ${x + 2f} $y A2 2 0 1 0 ${x - 2f} $y Z"
    })
    /** O escudo com o cadeado (o lock.shield do iOS). */
    val escudoCadeado = tracoComPonta("escudoCadeado", "M12 3 L19.5 6 V11.5 C19.5 16 16.3 19.4 12 21 C7.7 19.4 4.5 16 4.5 11.5 V6 Z M10.3 11.2 V10 A1.7 1.7 0 0 1 13.7 10 V11.2",
                                      "M9.3 11.2 H14.7 V15.4 H9.3 Z", 1.8f)
    /** O cadeado com a seta em volta (o lock.rotation do iOS): o app que se tranca sozinho. */
    val cadeadoGirando = tracoComPonta("cadeadoGirando", "M19.5 12 A7.5 7.5 0 1 1 17.3 6.7 M19.5 4 V8.5 H15 M10.6 11.6 V10.5 A1.4 1.4 0 0 1 13.4 10.5 V11.6",
                                       "M9.7 11.6 H14.3 V15.4 H9.7 Z", 1.8f)
    /** A chave em pe (o key do iOS). */
    val chaveEmPe = traco("chaveEmPe", "M12 3.5 A3.75 3.75 0 1 1 11.99 3.5 Z", "M12 11 V20.5 M12 15.5 H14.5 M12 18.5 H14")
    val alvo = traco("alvo", "M12 21 A9 9 0 1 0 12 3 A9 9 0 1 0 12 21 Z", "M12 16 A4 4 0 1 0 12 8 A4 4 0 1 0 12 16 Z")
    val altaEQueda = traco("altaEQueda", "M8 19 V5 M4.5 8.5 L8 5 L11.5 8.5", "M16 5 V19 M12.5 15.5 L16 19 L19.5 15.5")
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
    // Os eixos e a linha que sobe, com a ponta cheia (o chart.line.uptrend.xyaxis do iOS).
    val mercado = tracoComPonta("mercado", "M1.81 2.88 V21.12 H23.09 M2.57 14.66 L7.13 9.34 L12.83 14.28 L18.6 8.3",
                                "M16.1 6.3 L22.49 4.93 L20.97 11.24 Z", espessura = 1.55f)
    // O relogio com a seta girando para tras, aberta a esquerda (o clock.arrow.circlepath do iOS).
    val atividade = tracoComPonta("atividade", "M3.2 10.6 A10.26 10.26 0 1 1 4.99 18.33 M12.91 6.68 V14.28 L15.57 16.18",
                                  "M0.75 10.48 H6.45 L3.49 14.43 Z", espessura = 1.55f)
    val envelope = traco("envelope", "M4.5 6 H19.5 A1.5 1.5 0 0 1 21 7.5 V16.5 A1.5 1.5 0 0 1 19.5 18 H4.5 A1.5 1.5 0 0 1 3 16.5 V7.5 A1.5 1.5 0 0 1 4.5 6 Z", "M3.5 7 L12 13 L20.5 7")
    val envelopeAberto = traco("envelopeAberto", "M3 10 L12 4 L21 10 V19 A1.5 1.5 0 0 1 19.5 20.5 H4.5 A1.5 1.5 0 0 1 3 19 Z", "M3.5 10.5 L12 15.5 L20.5 10.5")
    val chave = traco("chave", "M8 16 A4 4 0 1 0 8 8 A4 4 0 1 0 8 16 Z", "M12 12 H20.5 M17.5 12 V15 M20.5 12 V14")
    val pessoas = traco("pessoas", "M9 11 A3.5 3.5 0 1 0 9 4 A3.5 3.5 0 1 0 9 11 Z", "M3 19.5 C3 16.5 5.7 14.5 9 14.5 C12.3 14.5 15 16.5 15 19.5", "M16 4.3 A3.5 3.5 0 0 1 16 10.7 M18 14.8 C19.9 15.5 21 17.2 21 19.5")
    val microfone = traco("microfone", "M12 15 A3 3 0 0 0 15 12 V6 A3 3 0 0 0 9 6 V12 A3 3 0 0 0 12 15 Z", "M5.5 11.5 A6.5 6.5 0 0 0 18.5 11.5 M12 18 V21")
    val sair = traco("sair", "M14 4.5 H18 A1.5 1.5 0 0 1 19.5 6 V18 A1.5 1.5 0 0 1 18 19.5 H14", "M10 8 L6 12 L10 16 M6 12 H15")
    val marcador = traco("marcador", "M7 3.5 H17 V20.5 L12 16.5 L7 20.5 Z")

    val alerta = cheio("alerta", "M12 2.8 C12.6 2.8 13.1 3.1 13.4 3.6 L22.1 18.6 C22.7 19.6 22 21 20.7 21 H3.3 C2 21 1.3 19.6 1.9 18.6 L10.6 3.6 C10.9 3.1 11.4 2.8 12 2.8 Z M11 9 V14 H13 V9 Z M11 16 V18 H13 V16 Z")
    val falha = cheio("falha", "M8.3 2.5 H15.7 L21.5 8.3 V15.7 L15.7 21.5 H8.3 L2.5 15.7 V8.3 Z M8.5 7.1 L7.1 8.5 L10.6 12 L7.1 15.5 L8.5 16.9 L12 13.4 L15.5 16.9 L16.9 15.5 L13.4 12 L16.9 8.5 L15.5 7.1 L12 10.6 Z")
    val vistoCheio = cheio("vistoCheio", "M12 2 A10 10 0 1 1 12 22 A10 10 0 1 1 12 2 Z M10.6 15.8 L17.3 9.1 L15.9 7.7 L10.6 13 L8.1 10.5 L6.7 11.9 Z")
    val fecharCheio = cheio("fecharCheio", "M12 2 A10 10 0 1 1 12 22 A10 10 0 1 1 12 2 Z M8.5 7.1 L7.1 8.5 L10.6 12 L7.1 15.5 L8.5 16.9 L12 13.4 L15.5 16.9 L16.9 15.5 L13.4 12 L16.9 8.5 L15.5 7.1 L12 10.6 Z")
    /** As da barra de abas, cheias como as do iOS 26. */
    val carteiraCheia = cheio(
        "carteiraCheia",
        "M3.49 6.06 H19.3 A3.04 3.04 0 0 1 22.34 9.1 V19.28 A3.04 3.04 0 0 1 19.3 22.32 H3.49 A3.04 3.04 0 0 1 0.45 19.28 V9.1 A3.04 3.04 0 0 1 3.49 6.06 Z " +
            "M6.23 4.16 L16.6 1.42 C17.7 1.13 18.69 1.9 18.69 3.04 V4.16 Z " +
            "M17.44 8.96 H20.11 A3.6 3.6 0 0 1 23.71 12.56 V15.98 A3.6 3.6 0 0 1 20.11 19.58 H17.44 A3.6 3.6 0 0 1 13.84 15.98 V12.56 A3.6 3.6 0 0 1 17.44 8.96 Z " +
            "M17.59 9.71 H20.71 A3 3 0 0 1 23.71 12.71 V15.83 A3 3 0 0 1 20.71 18.83 H17.59 A3 3 0 0 1 14.59 15.83 V12.71 A3 3 0 0 1 17.59 9.71 Z " +
            "M19.6 14.27 A1.37 1.37 0 1 0 16.86 14.27 A1.37 1.37 0 1 0 19.6 14.27 Z",
    )
    // Oito dentes de pontas redondas, um apontando para cima, e o furo no meio (o gearshape.fill).
    val engrenagemCheia = cheioRedondo(
        "engrenagemCheia",
        "M9.3 4.36 L9.97 2 L14.03 2 L14.7 4.36 L14.9 4.44 L15.1 4.52 L15.29 4.6 L15.49 4.69 L17.63 3.49 L20.51 6.37 L19.31 8.51 L19.4 8.71 " +
            "L19.48 8.9 L19.56 9.1 L19.64 9.3 L22 9.97 L22 14.03 L19.64 14.7 L19.56 14.9 L19.48 15.1 L19.4 15.29 L19.31 15.49 L20.51 17.63 " +
            "L17.63 20.51 L15.49 19.31 L15.29 19.4 L15.1 19.48 L14.9 19.56 L14.7 19.64 L14.03 22 L9.97 22 L9.3 19.64 L9.1 19.56 L8.9 19.48 " +
            "L8.71 19.4 L8.51 19.31 L6.37 20.51 L3.49 17.63 L4.69 15.49 L4.6 15.29 L4.52 15.1 L4.44 14.9 L4.36 14.7 L2 14.03 L2 9.97 L4.36 9.3 " +
            "L4.44 9.1 L4.52 8.9 L4.6 8.71 L4.69 8.51 L3.49 6.37 L6.37 3.49 L8.51 4.69 L8.71 4.6 L8.9 4.52 L9.1 4.44 Z " +
            "M16.25 12 A4.25 4.25 0 1 0 7.75 12 A4.25 4.25 0 1 0 16.25 12 Z",
        raio = 0.6f,
    )
    /** O escudo da checagem do aparelho: a metade esquerda cheia enquanto confere. */
    val escudoMetade = ImageVector.Builder("escudoMetade", 24.dp, 24.dp, 24f, 24f).apply {
        addPath(PathParser().parsePathString("M12 2.5 L20 5.6 V11.3 C20 16.3 16.6 20.1 12 21.7 C7.4 20.1 4 16.3 4 11.3 V5.6 Z").toNodes(),
                stroke = SolidColor(Color.Black), strokeLineWidth = 1.9f, strokeLineJoin = StrokeJoin.Round)
        addPath(PathParser().parsePathString("M12 2.5 L4 5.6 V11.3 C4 16.3 7.4 20.1 12 21.7 Z").toNodes(), fill = SolidColor(Color.Black))
    }.build()
    val escudoVistoCheio = cheio("escudoVistoCheio",
        "M12 2.5 L20 5.6 V11.3 C20 16.3 16.6 20.1 12 21.7 C7.4 20.1 4 16.3 4 11.3 V5.6 Z M10.6 15.6 L16.9 9.3 L15.5 7.9 L10.6 12.8 L8.4 10.6 L7 12 Z")
    val escudoAlertaCheio = cheio("escudoAlertaCheio",
        "M12 2.5 L20 5.6 V11.3 C20 16.3 16.6 20.1 12 21.7 C7.4 20.1 4 16.3 4 11.3 V5.6 Z M11 7.2 H13 V13.2 H11 Z M11 15.1 H13 V17.1 H11 Z")
    val exclamacaoCheia = cheio("exclamacaoCheia", "M12 2 A10 10 0 1 1 12 22 A10 10 0 1 1 12 2 Z M11 6.5 H13 V13.5 H11 Z M11 15.5 H13 V17.5 H11 Z")
    val reproduzirCirculo = tracoComPonta("reproduzirCirculo", "M12 3 A9 9 0 1 1 11.99 3 Z", "M10.2 8.6 L15.4 12 L10.2 15.4 Z", 1.7f)
    val documentoCadeado = traco("documentoCadeado", "M6.5 3 H14 L18.5 7.5 V19.5 A1.5 1.5 0 0 1 17 21 H6.5 A1.5 1.5 0 0 1 5 19.5 V4.5 A1.5 1.5 0 0 1 6.5 3 Z",
                                 "M14 3 V7.5 H18.5", "M9.3 14.6 H14.2 V18 H9.3 Z", "M10.3 14.6 V13.4 A1.45 1.45 0 0 1 13.2 13.4 V14.6", espessura = 1.7f)
    val disco = traco("disco", "M3.5 13 L6.1 6.6 A2 2 0 0 1 7.95 5.4 H16.05 A2 2 0 0 1 17.9 6.6 L20.5 13",
                      "M5.5 13 H18.5 A2 2 0 0 1 20.5 15 V17 A2 2 0 0 1 18.5 19 H5.5 A2 2 0 0 1 3.5 17 V15 A2 2 0 0 1 5.5 13 Z", "M16.6 16 V16.05")
    val envelopeCheio = cheio("envelopeCheio", "M4.2 5 H19.8 A2.2 2.2 0 0 1 22 7.2 V16.8 A2.2 2.2 0 0 1 19.8 19 H4.2 A2.2 2.2 0 0 1 2 16.8 V7.2 A2.2 2.2 0 0 1 4.2 5 Z " +
        "M2.6 7.1 L12 13.9 L21.4 7.1 V5.6 L12 12.4 L2.6 5.6 Z M2.6 17.6 L7.4 12.6 L8.4 13.6 L3.6 18.6 Z M21.4 17.6 L16.6 12.6 L15.6 13.6 L20.4 18.6 Z")
    val envelopeAbertoCheio = cheio("envelopeAbertoCheio", "M2 10 L12 3 L22 10 V18.8 A2.2 2.2 0 0 1 19.8 21 H4.2 A2.2 2.2 0 0 1 2 18.8 Z " +
        "M3.6 10.4 L12 4.7 L20.4 10.4 L12 15.8 Z")
    val cadeadoAbertoCheio = cheio("cadeadoAbertoCheio", "M3 12 A2 2 0 0 1 5 10 H15 A2 2 0 0 1 17 12 V19 A2 2 0 0 1 15 21 H5 A2 2 0 0 1 3 19 Z",
                                   "M12 10 V6.8 A4.5 4.5 0 0 1 21 6.8 V9 H19 V6.8 A2.5 2.5 0 0 0 14 6.8 V10 Z")
    val cadeadoCheio = cheio("cadeadoCheio", "M7 10 V7.5 A5 5 0 0 1 17 7.5 V10 H17.5 A2 2 0 0 1 19.5 12 V19 A2 2 0 0 1 17.5 21 H6.5 A2 2 0 0 1 4.5 19 V12 A2 2 0 0 1 6.5 10 Z M9 10 H15 V7.5 A3 3 0 0 0 9 7.5 Z")
}

@Composable
fun Icone(icone: ImageVector, cor: Color, tamanho: Dp = 20.dp, modifier: Modifier = Modifier, descricao: String? = null) {
    Icon(icone, contentDescription = descricao, tint = cor, modifier = modifier.size(tamanho))
}
