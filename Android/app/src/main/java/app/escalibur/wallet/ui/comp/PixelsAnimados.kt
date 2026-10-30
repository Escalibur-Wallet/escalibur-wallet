package app.escalibur.wallet.ui.comp

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.tema.Raio
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

/*
 * As animacoes de pixels de 24/10/2026, as mesmas do iOS: o veu do saldo (PixelVeil), o campo que nasce
 * dos pixels (PixelBirth), a lixeira de remover carteira (PixelTrashScene), o visor do leitor de QR sem
 * camera (Viewfinder) e a abertura do envelope (EnvelopeOpenScene). Os tons e o ruido sao os do
 * `PixelsCifrando`.
 */

private fun suaveD(x: Double): Double { val t = x.coerceIn(0.0, 1.0); return t * t * (3 - 2 * t) }
private fun saidaD(x: Double): Double { val c = 1 - x.coerceIn(0.0, 1.0); return 1 - c * c * c }
private fun entradaD(x: Double): Double { val c = x.coerceIn(0.0, 1.0); return c * c * c }

/** O tom cifrado de um pixel agora, de 0 a 1, cruzando de um sorteio para o outro no compasso dele. */
private fun cifra(a: Int, b: Int, relogio: Double, ritmo: Double, semente: Long): Double {
    val fase = PixelsCifrando.ruido(a, b, semente)
    val batida = relogio * ritmo * (0.6 + 0.8 * fase) + fase * 8
    val degrau = floor(batida)
    val x = PixelsCifrando.ruido(a, b, degrau.toLong())
    val y = PixelsCifrando.ruido(a, b, degrau.toLong() + 1)
    return x + (y - x) * suaveD(batida - degrau)
}

private fun DrawScope.pixel(cx: Float, cy: Float, lado: Float, tom: Double, alfa: Float = 1f, canto: Float = 0.24f) {
    if (alfa <= 0.01f || lado <= 0.2f) return
    drawRoundRect(
        PixelsCifrando.cinza(tom).copy(alpha = alfa.coerceIn(0f, 1f)), Offset(cx - lado / 2, cy - lado / 2), Size(lado, lado),
        CornerRadius(lado * canto),
    )
}

/**
 * O veu de pixels do saldo: cobrindo (ao ocultar), uma frente corre da esquerda para a direita, os pixels
 * nascem pequenos e claros e encaixam, o numero some atras deles, e no fim os pixels se apagam.
 * Descobrindo (ao mostrar), os pixels acendem cobrindo o lugar e a frente corre de novo da esquerda para
 * a direita, levando os pixels e descobrindo o numero. `progresso`: 0, o numero limpo; 1, escondido.
 */
fun Modifier.veuDePixels(progresso: Float, revelando: Boolean, faixa: ClosedFloatingPointRange<Float> = 0.2f..0.9f): Modifier =
    drawWithContent {
        val tempo = (if (revelando) 1f - progresso else progresso).toDouble()
        val w = size.width
        val frente = 40.dp.toPx()
        val parte = 0.66
        val corrida = if (revelando) suaveD((tempo - (1 - parte)) / parte) else suaveD(tempo / parte)
        val f = -frente + corrida.toFloat() * (w + 2 * frente)
        // O numero fica onde a frente ainda nao passou (ocultando) ou ja passou (mostrando).
        val corte = (f - frente * 0.5f).coerceIn(0f, w)
        if (revelando) clipRect(right = corte) { this@drawWithContent.drawContent() }
        else clipRect(left = corte) { this@drawWithContent.drawContent() }
        val presenca = if (revelando) suaveD(tempo / (1 - parte)) else 1 - suaveD((tempo - parte) / (1 - parte))
        if (presenca <= 0.01) return@drawWithContent
        val passo = 7.dp.toPx()
        val celula = 5.5.dp.toPx()
        val topo = size.height * faixa.start
        val base = size.height * faixa.endInclusive
        val linhas = max(((base - topo) / passo).roundToInt(), 1)
        val y0 = topo + ((base - topo) - linhas * passo) / 2
        val colunas = ceil(w / passo).toInt()
        val batida = tempo * 16
        val degrau = floor(batida)
        val mistura = suaveD(batida - degrau)
        for (coluna in 0 until colunas) {
            val x = coluna * passo + passo / 2
            // Quanto deste pixel ja esta no lugar: 1 atras da frente ao cobrir, 1 adiante dela ao descobrir.
            val noLugar = if (revelando) suaveD(((x - (f - frente)) / frente).toDouble()) else suaveD(((f - x) / frente).toDouble())
            if (noLugar <= 0.02) continue
            for (linha in 0 until linhas) {
                val a = PixelsCifrando.ruido(coluna, linha, degrau.toLong())
                val b = PixelsCifrando.ruido(coluna, linha, degrau.toLong() + 1)
                val bit = a + (b - a) * mistura
                // Na frente, mais claro: os pixels acendem antes de encaixar.
                val calor = 4 * noLugar * (1 - noLugar)
                val tom = 0.2 + 0.36 * bit + 0.34 * calor * bit
                val lado = celula * (0.4f + 0.6f * noLugar.toFloat()) * (0.6f + 0.4f * presenca.toFloat())
                pixel(x, y0 + linha * passo + passo / 2, lado, tom, (noLugar * presenca).toFloat())
            }
        }
    }

/**
 * Um campo que nasce dos pixels (o repita a passphrase): das duas pontas para o meio, cada pixel surge
 * no tom do fundo da tela, pequeno, e clareia ate um cinza que cifra de leve; as juntas fecham no tom do
 * campo e o campo de verdade fica pronto por baixo; entao cada pixel some no seu instante, encolhendo,
 * e o campo aparece pelos buracos. `tempo`: de 0 a 1 (1, o campo inteiro).
 */
fun Modifier.nascerDosPixels(tempo: Float, raio: Dp = Raio.cartao): Modifier = drawWithContent {
    if (tempo >= 1f) { drawContent(); return@drawWithContent }
    val nascidoAte = 0.4
    val fechado = 0.52
    val sumir = 0.12
    val t = tempo.toDouble()
    if (t >= fechado) drawContent()
    val juntar = suaveD((t - nascidoAte) / (fechado - nascidoAte))
    val passo = 6.dp.toPx()
    val celula = 4.9.dp.toPx()
    val colunas = ceil(size.width / passo).toInt()
    val linhas = ceil(size.height / passo).toInt()
    val x0 = (size.width - colunas * passo) / 2
    val y0 = (size.height - linhas * passo) / 2
    // O fundo da tela, de onde os pixels saem, e o do campo, onde eles assentam.
    val chao = 0.045
    val campo = 0.083
    val batida = t * 18
    val degrau = floor(batida)
    val mistura = suaveD(batida - degrau)
    val forma = Path().apply { addRoundRect(RoundRect(0f, 0f, size.width, size.height, CornerRadius(raio.toPx()))) }
    clipPath(forma) {
        for (coluna in 0 until colunas) {
            val ao = coluna.toDouble() / max(colunas - 1, 1)
            for (linha in 0 until linhas) {
                val nasce = 0.26 * (1 - abs(ao - 0.5) * 2) + 0.1 * PixelsCifrando.ruido(coluna, linha, 0xB1E)
                val some = fechado + (1 - fechado - sumir) * PixelsCifrando.ruido(coluna, linha, 0x50D)
                val cresce = suaveD((t - nasce) / 0.14)
                val foi = suaveD((t - some) / sumir)
                if (cresce <= 0.01 || foi >= 0.99) continue
                val a = PixelsCifrando.ruido(coluna, linha, degrau.toLong())
                val b = PixelsCifrando.ruido(coluna, linha, degrau.toLong() + 1)
                val bit = a + (b - a) * mistura
                var tom = chao + (0.075 + 0.11 * bit - chao) * cresce
                tom += (campo - tom) * juntar
                val cheio = celula * (0.35f + 0.65f * cresce.toFloat()) + (passo - celula + 0.6f) * juntar.toFloat()
                val lado = cheio * (1 - foi.toFloat())
                val canto = 0.24f * max(1 - juntar, foi).toFloat()
                pixel(x0 + (coluna + 0.5f) * passo, y0 + (linha + 0.5f) * passo, lado, tom, 1f, canto)
            }
        }
    }
}

/**
 * A lixeira de remover carteira, em pixels cheios como o cadeado: a carteira aparece em cima, a tampa
 * gira na dobradica da esquerda ate quase de pe, a carteira desce para dentro, por tras da frente da
 * lixeira, e a tampa fecha com um quique curto. Com o movimento reduzido, a carteira parada em cima.
 */
@Composable
fun LixeiraDePixels(modifier: Modifier = Modifier) {
    val parado = movimentoReduzido()
    val segundos by relogio(parado)
    Canvas(modifier) {
        val t = if (parado) 0.6 else (segundos.toDouble() % 3.8)
        val relogioDosTons = segundos.toDouble()
        val p = 6.dp.toPx()
        val celula = 4.9.dp.toPx()
        val alca = listOf(".....#####.....", ".....#...#.....")
        val tampa = listOf("###############", ".#############.")
        val corpo = listOf("..###########..", "..##-##-##-##..", "..##-##-##-##..", "..##-##-##-##..", "..##-##-##-##..",
                           "..##-##-##-##..", "..##-##-##-##..", "..##-##-##-##..", "...#-##-##-#...", "...#########...")
        val carteira = listOf("###########", "###########", "#######----", "#######-o--", "#######----", "###########", "###########")
        val x0 = (size.width - 15 * p) / 2
        val topoDoCorpo = size.height - corpo.size * p
        val topoDaTampa = topoDoCorpo - 3 * p
        val topoDaAlca = topoDaTampa - 2 * p
        val chega = suaveD(t / 0.4)
        // O fechar leva 0,3 s, como no iOS (antes 0,22, rapido demais para parecer continuo).
        val abre = saidaD((t - 0.55) / 0.3) * (1 - suaveD((t - 1.55) / 0.3))
        val quique = if (t > 1.85 && t < 2.18) sin((t - 1.85) / 0.33 * Math.PI) else 0.0
        val cai = entradaD((t - 0.85) / 0.6)
        val repouso = topoDaAlca - 9 * p
        val topoDaCarteira = repouso + cai.toFloat() * (topoDoCorpo + 2 * p - repouso) - (1 - chega).toFloat() * 6
        fun tom(a: Int, b: Int) = cifra(a, b, relogioDosTons, 2.5, 0x7A5)
        fun quadrado(x: Float, y: Float, tom: Double, alfa: Float = 1f) =
            pixel(x, y, celula, tom, alfa, 0.22f)

        // A carteira, cortada na boca da lixeira: dali para baixo ela esta dentro.
        clipRect(bottom = topoDoCorpo) {
            carteira.forEachIndexed { linha, texto ->
                texto.forEachIndexed { coluna, marca ->
                    if (marca == '.') return@forEachIndexed
                    val t2 = when (marca) { '-' -> 0.34; 'o' -> 0.96; else -> 0.84 + 0.08 * tom(coluna, linha + 40) }
                    val nasceu = suaveD((chega - 0.6 * PixelsCifrando.ruido(coluna, linha, 0x3C1)) / 0.4)
                    quadrado(x0 + 2 * p + (coluna + 0.5f) * p, topoDaCarteira + (linha + 0.5f) * p, t2, nasceu.toFloat())
                }
            }
        }
        // O corpo, com os frisos mais escuros.
        corpo.forEachIndexed { linha, texto ->
            texto.forEachIndexed { coluna, marca ->
                if (marca == '.') return@forEachIndexed
                val t2 = if (marca == '-') 0.26 + 0.05 * tom(coluna, linha) else 0.5 + 0.1 * tom(coluna, linha)
                quadrado(x0 + (coluna + 0.5f) * p, topoDoCorpo + (linha + 0.5f) * p, t2)
            }
        }
        // A tampa e a alca juntas, girando na dobradica da esquerda ate quase de pe.
        val angulo = abre * 1.25 - quique * 0.12
        val dobradicaX = x0
        val dobradicaY = topoDaTampa + 2 * p
        for ((bloco, topo, base) in listOf(Triple(alca, topoDaAlca, 0.7), Triple(tampa, topoDaTampa, 0.78))) {
            bloco.forEachIndexed { linha, texto ->
                texto.forEachIndexed { coluna, marca ->
                    if (marca != '#') return@forEachIndexed
                    val dx = (coluna + 0.5f) * p
                    val dy = topo + (linha + 0.5f) * p - dobradicaY
                    val x = dobradicaX + dx * cos(angulo).toFloat() + dy * sin(angulo).toFloat()
                    val y = dobradicaY - dx * sin(angulo).toFloat() + dy * cos(angulo).toFloat()
                    quadrado(x, y, base + 0.1 * tom(coluna, linha + 20 + if (base > 0.75) 5 else 0))
                }
            }
        }
    }
}

/**
 * O visor do leitor de QR sem camera, em pixels: os quatro cantos da mira e um QR de pixels que cifram.
 * Uma faixa clara desce e sobe pelo codigo, e os pixels nao assentam: a camera nao le.
 */
@Composable
fun VisorDePixels(modifier: Modifier = Modifier) {
    val parado = movimentoReduzido()
    val segundos by relogio(parado)
    Canvas(modifier) {
        val grade = 25
        val codigo = 17
        val braco = 5
        val relogio = segundos.toDouble()
        val varre = if (parado) 0.5 else (sin(relogio * 2 * Math.PI / 2.6 - Math.PI / 2) + 1) / 2
        val lado = min(size.width, size.height)
        val passo = lado / grade
        val ox = (size.width - lado) / 2
        val oy = (size.height - lado) / 2
        fun ponto(x: Float, y: Float, tom: Double, alfa: Float = 1f) =
            pixel(ox + x * passo + passo / 2, oy + y * passo + passo / 2, passo * 0.8f, tom, alfa)
        val ultimo = grade - 1
        for ((cx, cy, dx, dy) in listOf(listOf(0, 0, 1, 1), listOf(ultimo, 0, -1, 1), listOf(0, ultimo, 1, -1), listOf(ultimo, ultimo, -1, -1))) {
            for (k in 0 until braco) {
                ponto((cx + dx * k).toFloat(), cy.toFloat(), 0.92)
                if (k > 0) ponto(cx.toFloat(), (cy + dy * k).toFloat(), 0.92)
            }
        }
        fun olho(c: Int, r: Int): Boolean? {
            for ((fc, fr) in listOf(0 to 0, (codigo - 7) to 0, 0 to (codigo - 7))) {
                if (c in fc until fc + 7 && r in fr until fr + 7) {
                    val x = c - fc
                    val y = r - fr
                    if (x == 0 || x == 6 || y == 0 || y == 6) return true
                    return x in 2..4 && y in 2..4
                }
            }
            return null
        }
        val desloca = (grade - codigo) / 2
        val faixa = desloca - 1 + varre * (codigo + 1)
        for (c in 0 until codigo) {
            for (r in 0 until codigo) {
                val brilho = exp(-((r + desloca - faixa) / 1.1).pow(2))
                val tom = olho(c, r)?.let { if (it) 0.8 else 0.1 } ?: run {
                    val bit = cifra(c * 31 + r, 3, relogio, 3.0, 0x51A)
                    0.12 + 0.5 * bit * bit
                }
                ponto((c + desloca).toFloat(), (r + desloca).toFloat(), tom + (0.95 - tom) * 0.45 * brilho)
            }
        }
        for (c in (desloca - 1)..(desloca + codigo)) ponto(c.toFloat(), faixa.toFloat(), 0.96, 0.85f)
    }
}

/**
 * Abrir um envelope (a cena redesenhada do iOS, 24/10/2026): o envelope e um bloco de pixels que cifram,
 * com o cadeado no meio. A senha entra ponto a ponto embaixo; com o ultimo ponto o cadeado abre e se
 * desfaz, e uma frente desce pelo bloco decifrando: os pixels assentam nas 12 palavras da carteira, cada
 * uma com o seu numero. Nenhuma palavra de verdade: as palavras sao barras.
 */
@Composable
fun CenaDeAbrirEnvelope(modifier: Modifier = Modifier) {
    val parado = movimentoReduzido()
    val segundos by relogio(parado)
    Canvas(modifier) {
        val largura = 300f
        val altura = 236f
        val escala = min(size.width / largura, size.height / altura)
        translate((size.width - largura * escala) / 2, (size.height - altura * escala) / 2) {
            scale(escala, escala, Offset.Zero) { desenharAbertura(if (parado) 5.0 else segundos.toDouble() % 6.6, if (parado) 0.0 else segundos.toDouble()) }
        }
    }
}

private fun DrawScope.desenharAbertura(t: Double, relogio: Double) {
    val colunas = 38
    val linhas = 22
    val passo = 6f
    val celula = 4.6f
    val origemX = (300f - colunas * passo) / 2
    val origemY = 14f
    val cadeado = listOf("..#####..", ".##...##.", ".#.....#.", ".#.....#.", "#########",
                         "#########", "####.####", "####.####", "#########", "#########")
    val colunaDoCadeado = 15
    val linhaDoCadeado = 6
    fun alvo(c0: Int, r0: Int): Double {
        val c = c0 - 2
        val r = r0 - 4
        if (c < 0 || r < 0 || c % 12 >= 10 || r % 4 >= 2 || c / 12 >= 3 || r / 4 >= 4) return 0.0
        val palavra = (r / 4) * 3 + c / 12
        val x = c % 12
        if (x == 0) return 0.45
        if (x == 1) return 0.0
        val tamanho = 4 + (PixelsCifrando.ruido(palavra, 3, 0x51D) * 5).toInt()
        return if (x - 2 < tamanho) 1.0 else 0.0
    }
    fun bit(a: Int, b: Int, ritmo: Double = 3.0) = cifra(a, b, relogio, ritmo, 0x0E5C)
    fun ponto(c: Int, r: Int) = Offset(origemX + (c + 0.5f) * passo, origemY + (r + 0.5f) * passo)

    val alfa = (suaveD(t / 0.4) * (1 - suaveD((t - 5.9) / 0.6))).toFloat()
    if (alfa <= 0.01f) return
    val frente = suaveD((t - 2.6) / 1.3) * (linhas + 4) - 2
    val ergue = saidaD((t - 1.95) / 0.3) * passo * 1.2
    val sumiuCadeado = ((t - 2.35) / 0.4).coerceIn(0.0, 1.0)
    val halo = 1 - suaveD((t - 2.35 - 0.1) / 0.4)
    for (c in 0 until colunas) {
        for (r in 0 until linhas) {
            val borda = r == 0 || c == 0 || r == linhas - 1 || c == colunas - 1
            val cifrado = (if (borda) 0.26 else 0.13) + 0.22 * bit(c, r)
            val destino = if (borda) 0.2 else alvo(c, r).let { if (it > 0) 0.12 + 0.8 * it else 0.075 }
            val assenta = suaveD((frente - r) / 2.2)
            val calor = 4 * assenta * (1 - assenta)
            var tom = cifrado + (destino - cifrado) * assenta + 0.3 * calor * bit(c, r, 7.0)
            val lx = c - colunaDoCadeado
            val ly = r - linhaDoCadeado
            if (lx in -1..9 && ly in -1..10) tom += (0.05 - tom) * 0.85 * halo
            val o = ponto(c, r)
            pixel(o.x, o.y, celula, tom, alfa)
        }
    }
    cadeado.forEachIndexed { y, linha ->
        linha.forEachIndexed { x, marca ->
            if (marca != '#') return@forEachIndexed
            val n = PixelsCifrando.ruido(x, y, 0x10C)
            val foi = ((sumiuCadeado - 0.5 * n) / 0.5).coerceIn(0.0, 1.0)
            if (foi >= 1) return@forEachIndexed
            val o = ponto(colunaDoCadeado + x, linhaDoCadeado + y)
            val py = o.y - (if (y < 4) ergue.toFloat() else 0f) - foi.toFloat() * 8
            pixel(o.x, py, celula * (1 - 0.7f * foi.toFloat()), 0.95, alfa * (1 - foi.toFloat()))
        }
    }
    // A senha: cada ponto acende quando a tecla entra, com um tranco pequeno.
    val pontosY = origemY + linhas * passo + 34
    for (k in 0 until 6) {
        val digitado = ((t - 0.7 - k * 0.18) / 0.15).coerceIn(0.0, 1.0)
        val tranco = 1 + 0.35 * sin(digitado * Math.PI)
        pixel(150f + (k - 2.5f) * 18, pontosY, (9 * tranco).toFloat(), 0.22 + 0.73 * digitado, alfa)
    }
}
