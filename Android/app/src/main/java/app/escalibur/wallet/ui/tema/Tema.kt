package app.escalibur.wallet.ui.tema

import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.R
import kotlin.math.exp
import kotlin.math.roundToInt

/**
 * A paleta da carteira, a mesma do iOS (App/EscaliburWallet/Design/Palette.swift): tudo hex
 * solido. Alfa sobre fundos diferentes muda a cor aparente.
 */
object Paleta {
    // Fundo e superficies, do mais fundo ao mais alto.
    val vazio = Color(0xFF0B0B0C)
    val corpo = Color(0xFF151518)
    val trilho = Color(0xFF1E1E22)
    val controle = Color(0xFF26262B)
    val borda = Color(0xFF2A2A2F)
    val bordaForte = Color(0xFF3A3A40)

    // Tinta.
    val tinta = Color(0xFFF5F5F6)
    val tintaSuave = Color(0xFFA8A8AE)
    val tintaApagada = Color(0xFF8A8A92)
    val tintaMorta = Color(0xFF434349)

    // A placa clara.
    val viva = Color(0xFFF5F5F6)
    val vivaApertada = Color(0xFFC9C9CE)
    val sobreViva = Color(0xFF070708)

    // Mercado e estado.
    val alta = Color(0xFFC4F135)
    val sucesso = Color(0xFF32D74B)
    val altaFundo = Color(0xFF1F260B)
    val baixa = Color(0xFFFF4D3D)
    val baixaFundo = Color(0xFF2D1413)
    val baixaCheia = Color(0xFFE8112D)
    val baixaApertada = Color(0xFF3C1816)
    val cautela = Color(0xFFF5A524)
    val cautelaFundo = Color(0xFF2C210F)

    // A cor do app: acao principal, aba escolhida, interruptores e selecao. Texto branco por cima.
    val acento = Color(0xFFFF007B)
    val acentoApertado = Color(0xFFD10065)
    val sobreAcento = Color.White
    val lima = Color(0xFFC4F135)
    val sobreLima = Color(0xFF0B0D05)

    /** Marca-texto das pontas do endereco. */
    val realce = Color(0xFFFFD60A)
    val sobreRealce = Color(0xFF0B0B0C)

    // A placa clara: so onde se confere caractere por caractere.
    val placaTinta = Color(0xFF070708)
    val placaApagada = Color(0xFF5C5C63)
    val placaLinha = Color(0xFFDADADF)

    /** Disco atras de logo escuro (XRP, XLM). */
    val discoDeLogo = Color(0xFFE4E4E7)
}

/** Espaco: oito valores, nada fora. */
object Espaco {
    val xxs = 4.dp
    val xs = 8.dp
    val sm = 12.dp
    val md = 16.dp
    val base = 20.dp
    val lg = 28.dp
    val xl = 40.dp
    val xxl = 64.dp

    /** Margem lateral de toda tela. */
    val margem = 20.dp
}

/** Raio cresce com o tamanho do objeto. Nunca pilula em botao de acao. */
object Raio {
    val selo = 6.dp
    val chip = 8.dp
    val trilho = 10.dp
    val cartao = 12.dp
    val botao = 14.dp
    val folha = 28.dp
}

object Altura {
    val primaria = 56.dp
    val secundaria = 52.dp
    val linha = 64.dp
    val linhaCompacta = 52.dp
    val barra = 44.dp
    val campo = 48.dp
    val chipDeToken = 40.dp
    val chip = 32.dp
    val pilula = 28.dp
    val selo = 22.dp
    val acaoRapida = 52.dp
    val teclaDoPin = 78.dp
    val toque = 44.dp
}

/**
 * A escala tipografica do iOS (Typography.swift). Uma familia so, a do sistema. Numero que muda ao
 * vivo ou fica em coluna leva digitos de largura fixa (so os digitos; nao e fonte monoespacada).
 * Mono de verdade so para endereco e palavra da frase.
 */
enum class Tipo(val base: Float, val peso: FontWeight, val tracking: Float, val linhaExtra: Float, val crescimento: Float) {
    heroi(34f, FontWeight.Bold, -0.8f, 2f, 1.3f),
    vitrine(40f, FontWeight.Bold, -1.0f, 0f, 1.3f),
    numero(32f, FontWeight.Bold, -0.6f, 0f, 1.3f),
    tecla(30f, FontWeight.Medium, 0f, 0f, 1.3f),
    titulo(24f, FontWeight.Bold, -0.6f, 2f, 1.6f),
    cabecalho(20f, FontWeight.SemiBold, -0.3f, 0f, 1.6f),
    acao(17f, FontWeight.SemiBold, 0f, 0f, 2.2f),
    linha(16f, FontWeight.SemiBold, -0.1f, 0f, 2.2f),
    corpo(15f, FontWeight.Normal, 0f, 4f, 2.2f),
    nota(13f, FontWeight.Normal, 0f, 3f, 2.2f),
    rotulo(12f, FontWeight.SemiBold, 0f, 0f, 2.2f),
    eixo(11f, FontWeight.Medium, 0f, 0f, 1.4f),
    mono(16f, FontWeight.Medium, 0f, 0f, 2.2f),
    monoPequeno(13f, FontWeight.Normal, 0f, 0f, 2.2f);

    val digitosFixos: Boolean get() = this == vitrine || this == numero || this == linha || this == nota || this == eixo
    val monoespacado: Boolean get() = this == mono || this == monoPequeno
}

/**
 * A letra do app: a Inter, a mais proxima da SF Pro do iPhone que pode ir num app Android (a SF Pro
 * so pode ser usada nos aparelhos da Apple). Variavel: o peso e o tamanho otico (o "Display" a
 * partir de 20 pontos, como a SF Pro) saem do mesmo arquivo.
 */
object Letra {
    private val familias = HashMap<Long, FontFamily>()

    @OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
    fun familia(peso: FontWeight, tamanho: Float): FontFamily {
        val otico = tamanho.coerceIn(14f, 32f).roundToInt()
        val chave = peso.weight.toLong() * 100 + otico
        return synchronized(familias) {
            familias.getOrPut(chave) {
                FontFamily(Font(R.font.inter, peso, variationSettings = FontVariation.Settings(
                    FontVariation.weight(peso.weight), FontVariation.Setting("opsz", otico.toFloat()))))
            }
        }
    }

    /**
     * O espaco entre letras que a SF Pro ja traz por tamanho, na formula da Inter (em em): sem
     * ele, a Inter sai mais aberta que o iPhone nos titulos.
     */
    fun espacoNatural(tamanho: Float): Float = -0.0223f + 0.185f * exp(-0.1745f * tamanho)

    /** Para texto sem estilo proprio: todos os pesos, no tamanho otico do corpo. */
    @OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
    val padrao: FontFamily by lazy {
        FontFamily((1..9).map { FontWeight(it * 100) }.map { peso ->
            Font(R.font.inter, peso, variationSettings = FontVariation.Settings(FontVariation.weight(peso.weight), FontVariation.Setting("opsz", 15f)))
        })
    }
}

/**
 * O estilo no tamanho de texto que o dono escolheu no Android, com o mesmo teto do iOS: saldo e
 * titulo grandes crescem menos.
 */
@Composable
@ReadOnlyComposable
fun estilo(tipo: Tipo): TextStyle {
    val escala = LocalDensity.current.fontScale
    val tamanho = tipo.base * minOf(escala, tipo.crescimento) / escala
    return TextStyle(
        fontSize = tamanho.sp,
        fontWeight = tipo.peso,
        fontFamily = if (tipo.monoespacado) FontFamily.Monospace else Letra.familia(tipo.peso, tipo.base),
        letterSpacing = if (tipo.monoespacado) (tipo.tracking / tipo.base).em
                        else (Letra.espacoNatural(tipo.base) + tipo.tracking / tipo.base).em,
        lineHeight = (tamanho * 1.22f + tipo.linhaExtra).sp,
        lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
        fontFeatureSettings = if (tipo.digitosFixos) "tnum" else null,
    )
}

private val esquemaEscuro = darkColorScheme(
    primary = Paleta.acento,
    onPrimary = Paleta.sobreAcento,
    background = Paleta.vazio,
    onBackground = Paleta.tinta,
    surface = Paleta.corpo,
    onSurface = Paleta.tinta,
    surfaceVariant = Paleta.trilho,
    onSurfaceVariant = Paleta.tintaSuave,
    outline = Paleta.borda,
    error = Paleta.baixa,
)

/** O app e escuro sempre, como no iOS. */
@Composable
fun TemaEscalibur(conteudo: @Composable () -> Unit) {
    MaterialTheme(colorScheme = esquemaEscuro) {
        // Texto sem estilo proprio tambem sai na letra do app.
        CompositionLocalProvider(LocalTextStyle provides TextStyle(fontFamily = Letra.padrao, letterSpacing = Letra.espacoNatural(15f).em),
                                 content = conteudo)
    }
}

/** Para quem precisa do tamanho em dp de um texto em sp, sem crescer alem do teto. */
fun Density.semCrescer(valor: Float) = (valor / fontScale).sp
