package app.escalibur.wallet.ui.ajustes

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.CabecalhoDaFolha
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.PixelsCifrando
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.movimentoReduzido
import app.escalibur.wallet.ui.comp.relogio
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.sin

/**
 * As cenas da carteira com passphrase (o `PassphrasePixelScene` do iOS), todas em pixels que cifram,
 * como o envelope. Uma parede de pixels com duas portas: as palavras abrem a de sempre; a da
 * passphrase fica escondida e so aparece quando a chave encosta. Nada aqui e de verdade.
 */
enum class CenaDaPassphrase { portaEscondida, soAsPalavras, codigosProprios, esquecida }

private object G {
    const val LARGURA = 300f
    const val ALTURA = 236f
    const val PASSO = 6f
    const val CELULA = 4.6f
    val parede = Offset(30f, 92f)
    const val COLUNAS = 40
    const val LINHAS = 22
    val portaDeSempre = Porta(6, 6, 8, 16)
    val portaEscondida = Porta(26, 6, 8, 16)
    val pastilhas = Offset(48f, 22f)
    const val PERIODO = 6.4
    val codigoDeSempre = Offset(33f, 30f)
    val codigoDoCofre = Offset(159f, 30f)
    const val CODIGO = 108f
}

private data class Porta(val coluna: Int, val linha: Int, val largura: Int, val altura: Int)

/** Enderecos de exemplo, so desenho: a mesma rede nas duas carteiras, um endereco em cada. */
private val exemplos = listOf(
    Triple("bitcoin", "bc1q8f4…3k2v", "bc1qz7m…9wd0"),
    Triple("ethereum", "0x4B1c…7e09", "0xA93f…12cD"),
    Triple("solana", "7xKp…Qm4T", "GhR2…d8Lw"),
)

private fun suave(x: Double): Double { val t = x.coerceIn(0.0, 1.0); return t * t * (3 - 2 * t) }
private fun pulso(x: Double, largura: Double): Double = if (abs(x) >= largura) 0.0 else 0.5 + 0.5 * cos(x / largura * Math.PI)

@Composable
fun CenaDaPassphrase(cena: CenaDaPassphrase, altura: Dp = 236.dp, modifier: Modifier = Modifier) {
    val parado = movimentoReduzido()
    val agora by relogio(parado)
    // Com o movimento reduzido, o quadro que conta a historia, parado.
    val repouso = when (cena) {
        CenaDaPassphrase.portaEscondida -> 4.6
        CenaDaPassphrase.soAsPalavras -> 4.2
        CenaDaPassphrase.codigosProprios -> 3.6
        CenaDaPassphrase.esquecida -> 4.4
    }
    val t = if (parado) repouso else agora.toDouble() % G.PERIODO
    val volta = if (parado) 1 else (agora / G.PERIODO).toInt() % exemplos.size
    BoxWithConstraints(modifier.fillMaxWidth().height(altura)) {
        val escala = min(maxWidth.value / G.LARGURA, maxHeight.value / G.ALTURA)
        val ox = (maxWidth.value - G.LARGURA * escala) / 2
        val oy = (maxHeight.value - G.ALTURA * escala) / 2
        val entrada = (min(suave(t / 0.35), 1 - suave((t - (G.PERIODO - 0.5)) / 0.5))).toFloat()
        Canvas(Modifier.fillMaxSize().graphicsLayer { alpha = entrada }) {
            val px = density
            val pincel = Pincel(this, agora.toDouble(), escala * px, ox * px, oy * px)
            when (cena) {
                CenaDaPassphrase.portaEscondida -> {
                    val revela = suave((t - 2.6) / 0.9)
                    pincel.parede()
                    pincel.pastilhas(suave((t - 0.6) / 1.0), G.portaDeSempre)
                    pincel.porta(G.portaDeSempre, suave((t - 1.5) / 0.5), 0.0)
                    val chaveEntra = suave((t - 1.9) / 0.7)
                    pincel.chave(Offset((300 - 60 * chaveEntra).toFloat(), 70f), chaveEntra * (1 - suave((t - 3.5) / 0.4)))
                    pincel.porta(G.portaEscondida, suave((t - 3.6) / 0.6), revela, escondida = true, revela = revela)
                }
                CenaDaPassphrase.soAsPalavras -> {
                    pincel.parede()
                    pincel.pastilhas(suave((t - 0.5) / 1.0), G.portaDeSempre)
                    pincel.porta(G.portaDeSempre, suave((t - 1.4) / 0.5), 0.0)
                    // A luz varre a parede da esquerda para a direita: a porta escondida nao acende.
                    pincel.varredura(suave((t - 2.2) / 1.8))
                    pincel.porta(G.portaEscondida, 0.0, 0.0, escondida = true, revela = 0.0)
                }
                CenaDaPassphrase.codigosProprios -> {
                    pincel.codigo(G.codigoDeSempre, 11 + volta * 7, suave((t - 0.3) / 1.0))
                    pincel.codigo(G.codigoDoCofre, 29 + volta * 7, suave((t - 0.9) / 1.0))
                    // Uma moeda de pixels cai no codigo da direita: deposito no cofre.
                    val queda = suave((t - 2.4) / 0.8)
                    val meio = G.codigoDoCofre.x + G.CODIGO / 2
                    pincel.moeda(Offset(meio, (2 + 66 * queda).toFloat()), queda * (1 - suave((t - 3.3) / 0.4)))
                    pincel.clarao(G.codigoDoCofre, pulso(t - 3.25, 0.5))
                }
                CenaDaPassphrase.esquecida -> {
                    val some = suave((t - 1.8) / 1.6)
                    pincel.parede()
                    pincel.porta(G.portaEscondida, 0.0, 1 - some, escondida = true, revela = 1 - some)
                    pincel.porta(G.portaDeSempre, 0.0, 0.0)
                    // A chave se desfaz em ruido, de dentro para fora.
                    pincel.chave(Offset(220f, 70f), 1.0, desfaz = suave((t - 1.0) / 1.6))
                    pincel.pastilhas(0.0, G.portaDeSempre, 0.55)
                }
            }
        }
        // Embaixo de cada codigo, a moeda e o endereco dele: o de sempre e o com passphrase.
        if (cena == CenaDaPassphrase.codigosProprios) {
            val (rede, deSempre, doCofre) = exemplos[volta]
            for ((codigo, titulo, endereco, cofre, aparece) in listOf(
                Rotulo(G.codigoDeSempre, t("De sempre"), deSempre, false, suave((t - 0.9) / 0.4)),
                Rotulo(G.codigoDoCofre, t("Com passphrase"), doCofre, true, suave((t - 1.5) / 0.4)),
            )) {
                if (aparece <= 0.01) continue
                val meio = ox + (codigo.x + G.CODIGO / 2) * escala
                val sobe = (1 - aparece).toFloat() * 6
                val y = oy + (codigo.y + G.CODIGO + 20 + sobe) * escala
                // O meio da linha do titulo (18 de altura) no ponto, como no iOS; a escala parte do alto.
                Column(
                    Modifier.noPonto(meio.dp, (y - 9 * escala).dp).graphicsLayer {
                        alpha = (aparece * entrada).toFloat(); scaleX = escala; scaleY = escala
                        transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 0f)
                    },
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SeloDaRede(rede, rede, 18.dp, Paleta.vazio)
                        Spacer(Modifier.width(6.dp))
                        if (cofre) {
                            Icone(Icones.cadeado, Paleta.tintaSuave, tamanho = 10.dp)
                            Spacer(Modifier.width(3.dp))
                        }
                        Text(titulo, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Paleta.tintaSuave, maxLines = 1)
                    }
                    Text(endereco, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace, color = Paleta.tinta,
                         maxLines = 1, modifier = Modifier.padding(top = 5.dp))
                }
            }
        }
    }
}

private data class Rotulo(val codigo: Offset, val titulo: String, val endereco: String, val cofre: Boolean, val aparece: Double)

/** Poe o conteudo com o meio do alto dele no ponto (x, y) do quadro. */
private fun Modifier.noPonto(x: Dp, y: Dp) = layout { medida, limites ->
    val peca = medida.measure(limites.copy(minWidth = 0, minHeight = 0))
    layout(limites.maxWidth, limites.maxHeight) { peca.place(x.roundToPx() - peca.width / 2, y.roundToPx()) }
}

/** O pincel das cenas: pixels quadrados, cada um no seu tom de cinza que cifra, no quadro de 300 por 236. */
private class Pincel(val d: DrawScope, val relogio: Double, val e: Float, val ox: Float, val oy: Float) {
    fun tom(id: Int, camada: Int): Double {
        val fase = PixelsCifrando.ruido(id, camada, 0x6A2)
        val batida = relogio * 4 * (0.6 + 0.8 * fase) + fase * 8
        val degrau = floor(batida)
        val s = batida - degrau
        val mistura = s * s * (3 - 2 * s)
        val a = PixelsCifrando.ruido(id, camada, degrau.toLong())
        val b = PixelsCifrando.ruido(id, camada, degrau.toLong() + 1)
        return a + (b - a) * mistura
    }

    fun ponto(centro: Offset, valor: Double, alfa: Double = 1.0, lado: Float = G.CELULA, cor: Color? = null) {
        if (alfa <= 0.01) return
        val l = lado * e
        d.drawRoundRect(
            (cor ?: PixelsCifrando.cinza(valor)).copy(alpha = alfa.toFloat().coerceIn(0f, 1f)),
            topLeft = Offset(ox + centro.x * e - l / 2, oy + centro.y * e - l / 2), size = Size(l, l), cornerRadius = CornerRadius(l * 0.24f),
        )
    }

    fun naParede(coluna: Int, linha: Int) = Offset(G.parede.x + coluna * G.PASSO + G.PASSO / 2, G.parede.y + linha * G.PASSO + G.PASSO / 2)

    /** A parede. A porta escondida tem o mesmo tom da parede. */
    fun parede() {
        for (coluna in 0 until G.COLUNAS) for (linha in 0 until G.LINHAS) {
            val id = coluna * 64 + linha
            val borda = linha == 0 || coluna == 0 || coluna == G.COLUNAS - 1
            val bit = tom(id, 1)
            ponto(naParede(coluna, linha), if (borda) 0.34 + 0.12 * bit else 0.12 + 0.12 * bit)
        }
    }

    /** Uma porta: contorno mais claro e o miolo, que acende ao abrir. A escondida so mostra o contorno quando revelada. */
    fun porta(p: Porta, abre: Double, brilho: Double, escondida: Boolean = false, revela: Double = 1.0) {
        val contorno = ArrayList<Pair<Int, Int>>()
        for (c in p.coluna until p.coluna + p.largura) contorno.add(c to p.linha)
        for (r in p.linha + 1 until p.linha + p.altura) contorno.add(p.coluna + p.largura - 1 to r)
        for (r in p.linha + 1 until p.linha + p.altura) contorno.add(0, p.coluna to r)
        contorno.forEachIndexed { indice, (c, r) ->
            val ordem = indice.toDouble() / contorno.size
            val aceso = if (escondida) suave((revela - ordem * 0.8) / 0.2) else 1.0
            val bit = tom(c * 97 + r, 3)
            ponto(naParede(c, r), 0.12 + 0.12 * bit + aceso * (0.42 + 0.12 * bit))
        }
        // O miolo: ao abrir, as duas metades se afastam do meio e a luz de dentro aparece.
        val meio = p.coluna + (p.largura - 1) / 2.0
        for (c in p.coluna + 1 until p.coluna + p.largura - 1) for (r in p.linha + 1 until p.linha + p.altura) {
            val doMeio = abs(c - meio) / ((p.largura - 2) / 2.0)
            val foi = if (abre > doMeio * 0.9) 1.0 else 0.0
            val bit = tom(c * 131 + r, 4)
            val painel = 0.2 + 0.14 * bit
            val luz = 0.55 + 0.25 * bit
            ponto(naParede(c, r), painel * (1 - foi) + luz * foi + 0.1 * brilho)
        }
        if (!escondida) {
            // A macaneta, enquanto a porta esta fechada.
            ponto(naParede(p.coluna + p.largura - 2, p.linha + p.altura / 2 + 1), 0.95, 1 - abre)
        } else {
            // A fechadura: dois pixels claros no meio da porta escondida.
            val fechadura = naParede(p.coluna + p.largura / 2, p.linha + p.altura / 2)
            ponto(fechadura, 0.9, revela * (1 - abre))
            ponto(Offset(fechadura.x, fechadura.y + G.PASSO), 0.9, revela * (1 - abre))
        }
    }

    /** As palavras: 12 pastilhas de pixels no alto. `voa` leva os pixels para a porta. */
    fun pastilhas(voa: Double, p: Porta, alfa: Double = 1.0) {
        val alvo = naParede(p.coluna + p.largura / 2, p.linha + p.altura / 2)
        for (pastilha in 0 until 12) {
            val coluna = pastilha % 6
            val linha = pastilha / 6
            for (x in 0 until 5) for (y in 0 until 2) {
                val id = pastilha * 10 + x * 2 + y
                val casa = Offset(G.pastilhas.x + (coluna * 6 + x) * G.PASSO, G.pastilhas.y + (linha * 3 + y) * G.PASSO)
                val atraso = PixelsCifrando.ruido(id, 9, 0x1F) * 0.45
                val f = suave((voa - atraso) / (1 - atraso + 0.0001))
                val px = casa.x + (alvo.x - casa.x) * f.toFloat()
                val py = casa.y + (alvo.y - casa.y) * f.toFloat() - sin(f * Math.PI).toFloat() * 18
                ponto(Offset(px, py), 0.45 + 0.35 * tom(id, 5), alfa * (1 - suave((f - 0.85) / 0.15)))
            }
        }
    }

    /** A chave da passphrase em pixels: argola, haste e dentes. `desfaz` espalha os pixels. */
    fun chave(origem: Offset, alfa: Double, desfaz: Double = 0.0) {
        val desenho = listOf(".###.......", "#...#######", ".###...#.#.")
        desenho.forEachIndexed { linha, texto ->
            texto.forEachIndexed { coluna, letra ->
                if (letra != '#') return@forEachIndexed
                val id = linha * 20 + coluna
                val espalha = desfaz.toFloat() * 26
                val dx = (PixelsCifrando.ruido(id, 7, 1).toFloat() - 0.5f) * espalha * 2
                val dy = (PixelsCifrando.ruido(id, 7, 2).toFloat() - 0.5f) * espalha * 2 - desfaz.toFloat() * 10
                val tomDaChave = if (desfaz > 0) 0.3 + 0.4 * tom(id, 8) else 0.92
                ponto(Offset(origem.x + coluna * G.PASSO + dx, origem.y + linha * G.PASSO + dy), tomDaChave, alfa * (1 - suave((desfaz - 0.5) / 0.5)))
            }
        }
    }

    /** Uma faixa de luz que varre a parede. */
    fun varredura(progresso: Double) {
        if (progresso <= 0 || progresso >= 1) return
        val x = G.parede.x + progresso.toFloat() * G.COLUNAS * G.PASSO
        for (linha in 0 until G.LINHAS) for (desvio in -2..2) {
            ponto(Offset(x + desvio * G.PASSO, G.parede.y + linha * G.PASSO + G.PASSO / 2), 0.9, 0.28 * (1 - abs(desvio) / 3.0))
        }
    }

    /** Um codigo de deposito de pixels: 17 por 17, com os tres quadrados de canto; o miolo troca ate assentar. */
    fun codigo(origem: Offset, semente: Int, assenta: Double) {
        val lado = 17
        val passo = G.CODIGO / lado
        fun canto(c: Int, r: Int): Boolean? {
            for ((fc, fr) in listOf(0 to 0, lado - 7 to 0, 0 to lado - 7)) {
                if (c in fc until fc + 7 && r in fr until fr + 7) {
                    val x = c - fc
                    val y = r - fr
                    if (x == 0 || x == 6 || y == 0 || y == 6) return true
                    return x in 2..4 && y in 2..4
                }
            }
            return null
        }
        for (c in 0 until lado) for (r in 0 until lado) {
            val id = semente * 1000 + c * 31 + r
            val ligado = canto(c, r) ?: run {
                val assentado = PixelsCifrando.ruido(id, semente, 3) > 0.5
                val piscando = tom(id, 6) > 0.5
                if (PixelsCifrando.ruido(id, 2, 5) < assenta) assentado else piscando
            }
            ponto(Offset(origem.x + (c + 0.5f) * passo, origem.y + (r + 0.5f) * passo), if (ligado) 0.86 else 0.14, lado = passo * 0.82f)
        }
    }

    /** Uma moeda de pixels: um disco 5 por 5 com a borda clara. */
    fun moeda(centro: Offset, alfa: Double) {
        for (c in -2..2) for (r in -2..2) {
            if (c * c + r * r > 5) continue
            val borda = c * c + r * r >= 4
            ponto(Offset(centro.x + c * G.PASSO, centro.y + r * G.PASSO), if (borda) 0.95 else 0.7, alfa)
        }
    }

    /** Um clarao sobre o codigo, quando a moeda entra. */
    fun clarao(origem: Offset, quanto: Double) {
        if (quanto <= 0.01) return
        d.drawRoundRect(
            Color.White.copy(alpha = (0.12 * quanto).toFloat()), topLeft = Offset(ox + (origem.x - 4) * e, oy + (origem.y - 4) * e),
            size = Size((G.CODIGO + 8) * e, (G.CODIGO + 8) * e), cornerRadius = CornerRadius(6 * e),
        )
    }
}

/** O botao "Como funciona" da carteira com passphrase. */
@Composable
internal fun BotaoComoFuncionaDaPassphrase(modifier: Modifier = Modifier) {
    Row(
        modifier.height(34.dp).clip(CircleShape).background(Paleta.trilho)
            .clickable(role = Role.Button) { Navegacao.folha { ComoFuncionaAPassphrase { Navegacao.fechar() } } }
            .padding(horizontal = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icone(Icones.reproduzirCirculo, Paleta.tinta, tamanho = 15.dp)
        Text(t("Como funciona"), style = estilo(Tipo.rotulo), color = Paleta.tinta)
    }
}

/**
 * "Como funciona" da carteira com passphrase (o `PassphraseHowItWorks` do iOS): quatro passos em
 * cenas de pixels, no formato do "Como funciona" do envelope.
 */
@Composable
fun ComoFuncionaAPassphrase(aoFechar: () -> Unit) {
    val paginas = listOf(
        t("Um cofre escondido nas mesmas palavras") to
            t("A passphrase é uma senha extra que você escolhe. Junto com as palavras da carteira, ela abre outra carteira, separada da de sempre. Ela pode ter até 256 caracteres sem acento; com acento, cabem menos."),
        t("Quem só tem as palavras não abre o cofre") to
            t("Se alguém achar as suas palavras, vê só a carteira de sempre e não tem nem como saber que você tem uma passphrase. O saldo da carteira com passphrase continua fora do alcance."),
        t("Endereços próprios para receber") to
            t("A carteira com passphrase tem outros endereços de depósito, em todas as redes. Para guardar no cofre, receba nos endereços dela."),
        t("Anote longe das palavras, e não esqueça") to
            t("Guarde a passphrase num lugar diferente das palavras. Esquecer a passphrase é perder a carteira com passphrase: ninguém recupera, nem a Escalibur."),
    )
    val cenas = listOf(CenaDaPassphrase.portaEscondida, CenaDaPassphrase.soAsPalavras, CenaDaPassphrase.codigosProprios, CenaDaPassphrase.esquecida)
    val estado = rememberPagerState { paginas.size }
    val escopo = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().background(Paleta.vazio).navigationBarsPadding()) {
        CabecalhoDaFolha(t("Como funciona"), aoFechar)
        HorizontalPager(estado, Modifier.weight(1f)) { indice ->
            Column(Modifier.fillMaxSize().padding(horizontal = Espaco.margem), horizontalAlignment = Alignment.CenterHorizontally) {
                // So a tela visivel anima.
                Box(Modifier.padding(top = Espaco.lg).fillMaxWidth().height(236.dp)) {
                    if (estado.currentPage == indice) CenaDaPassphrase(cenas[indice])
                }
                Text(paginas[indice].first, style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                     modifier = Modifier.padding(top = Espaco.xl))
                Text(paginas[indice].second, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center,
                     modifier = Modifier.padding(top = Espaco.sm))
            }
        }
        // Os pontos de pagina do iOS.
        Row(Modifier.align(Alignment.CenterHorizontally).padding(vertical = Espaco.sm), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            repeat(paginas.size) { i ->
                Box(Modifier.size(7.dp).clip(CircleShape).background(Paleta.tinta.copy(alpha = if (i == estado.currentPage) 1f else 0.3f)))
            }
        }
        val ultima = estado.currentPage == paginas.size - 1
        BotaoPrimario(if (ultima) t("Entendi") else t("Próximo"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm, bottom = Espaco.xs)) {
            if (!ultima) escopo.launch { estado.animateScrollToPage(estado.currentPage + 1) } else aoFechar()
        }
    }
}
