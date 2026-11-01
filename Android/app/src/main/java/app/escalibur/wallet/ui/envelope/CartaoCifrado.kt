package app.escalibur.wallet.ui.envelope

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.CabecalhoDaFolha
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.PixelsCifrando
import app.escalibur.wallet.ui.comp.movimentoReduzido
import app.escalibur.wallet.ui.comp.relogio
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Letra
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** O que o cartao mostra: lacrado, a historia da senha certa, abrindo, aberto, a senha errada. */
enum class ModoDoCartao { lacrado, revelar, abrindo, aberto, negado }

/**
 * O arquivo do envelope como o app o ve (o `EnvelopeCipherCard` do iOS): o nome, o cadeado e uma
 * casa por palavra com o cifrado trocando, sobre um fundo de pixels que cifram. Nas telas de explicar,
 * conta a historia: a senha certa abre e as palavras de exemplo aparecem (`revelar`), ou a senha
 * errada treme e o cifrado embaralha de novo (`negado`). Nenhuma palavra de verdade: aberto, um visto
 * vazio no lugar de cada uma.
 */
@Composable
fun CartaoCifrado(modo: ModoDoCartao, modifier: Modifier = Modifier, nomeDoArquivo: String = "envelope-7F3A.esclbr", palavras: Int = 12) {
    val parado = movimentoReduzido()
    val agora by relogio(parado)
    val q = quadro(modo, agora.toDouble(), palavras, parado)
    // Os glifos trocam a 12 quadros por segundo, como a cifra viva; fazendo a conta, a 24; tentando a senha, a 30.
    val tique = when {
        parado -> 0L
        q.rapido -> (agora * 30).toLong()
        else -> (agora * (if (modo == ModoDoCartao.abrindo) 24 else 12)).toLong()
    }
    val forma = RoundedCornerShape(Raio.cartao)
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(Modifier.widthIn(max = 340.dp).fillMaxWidth().clip(forma).background(Paleta.corpo)) {
            // O fundo do cartao em pixels cinza que cifram: aparece em volta das palavras e segue
            // trocando tambem aberto, so mais apagado.
            FundoCifrado(tique / 3, Modifier.matchParentSize().padding(3.dp).alpha(if (q.destrancado) 0.6f else 0.9f))
            Column(Modifier.padding(Espaco.sm), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                Cabecalho(q, nomeDoArquivo)
                val colunas = if (q.mostrada.size > 12) 4 else 3
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    q.mostrada.indices.chunked(colunas).forEach { linha ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            for (i in linha) {
                                val onda = q.onda.getOrElse(i) { 0.0 }
                                Casa(i, q.mostrada[i], tique + (if (onda > 0.5) 53 else 0), Modifier.weight(1f))
                            }
                            repeat(colunas - linha.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
            Box(Modifier.matchParentSize().border(1.dp, Paleta.borda, forma))
        }
    }
}

/** Um quadro da historia. */
private class Quadro(palavras: Int) {
    /** 0 = nome do arquivo no topo, 1 = campo de senha. */
    var campo = 0.0
    var teclas = 0
    var cursor = false
    var destrancado = false
    /** A senha recusada: 0 nada, 1 o vermelho inteiro; e o tremor do campo, em dp. */
    var negado = 0.0
    var tremor = 0f
    /** A cifra mais rapida enquanto o app tenta a senha. */
    var rapido = false
    /** O balanco do cadeado, em graus. */
    var balanco = 0f
    /** Por palavra: o brilho da onda que embaralha de novo. */
    var onda = DoubleArray(12)
    /** Por palavra: 0 cifrada, 1 decifrada (palavra) ou aberta (visto). */
    var mostrada = DoubleArray(palavras)
}

/** A historia do `revelar`, em segundos dentro do laco. */
private object Historia {
    const val periodo = 8.6
    const val campoEntra = 0.5
    const val digitaDe = 0.8
    const val tecla = 0.19
    const val teclas = 8
    const val abre = 2.6
    const val revelaDe = 2.85
    const val revelaPasso = 0.09
    const val assenta = 0.32
    const val escondeDe = 7.0
    const val campoSai = 7.5
}

/** A tentativa errada do `negado`, em segundos dentro do laco. */
private object Errada {
    const val periodo = 5.4
    const val campoEntra = 0.4
    const val digitaDe = 0.7
    const val tecla = 0.15
    const val teclas = 6
    /** A tentativa: a cifra acelera. */
    const val tentaDe = 1.75
    const val tentaTempo = 0.9
    const val nega = 2.65
    /** Os pontos se apagam, do ultimo para o primeiro. */
    const val apagaDe = 3.05
    const val apagaPasso = 0.07
    /** A onda que embaralha o cifrado de novo, da esquerda para a direita. */
    const val ondaDe = 2.7
    const val ondaPasso = 0.05
    const val campoSai = 4.4
}

private fun quadro(modo: ModoDoCartao, agora: Double, palavras: Int, parado: Boolean): Quadro {
    val f = Quadro(if (modo == ModoDoCartao.aberto) palavras else 12)
    when (modo) {
        ModoDoCartao.lacrado, ModoDoCartao.abrindo -> {}
        ModoDoCartao.aberto -> f.destrancado = true
        ModoDoCartao.negado -> {
            if (parado) {
                f.campo = 1.0; f.teclas = Errada.teclas; f.negado = 1.0
                return f
            }
            val t = agora % Errada.periodo
            f.campo = suave((t - Errada.campoEntra) / 0.25) * (1 - suave((t - Errada.campoSai) / 0.3))
            val digitadas = (((t - Errada.digitaDe) / Errada.tecla).toInt() + 1).coerceIn(0, Errada.teclas).let { if (t < Errada.digitaDe) 0 else it }
            val apagadas = if (t < Errada.apagaDe) 0 else min(((t - Errada.apagaDe) / Errada.apagaPasso).toInt() + 1, Errada.teclas)
            f.teclas = max(digitadas - apagadas, 0)
            f.cursor = f.campo > 0.5 && (t < Errada.tentaDe || t > Errada.apagaDe + 0.5) && (t * 2.4).toInt() % 2 == 0
            // A tentativa: a cifra acelera um instante.
            val tentando = (t - Errada.tentaDe) / Errada.tentaTempo
            f.rapido = tentando >= 0 && tentando < 1
            val desde = t - Errada.nega
            f.negado = if (desde < 0) 0.0 else suave(desde / 0.1) * (1 - suave((t - Errada.apagaDe) / 0.2))
            // O tremor de quem errou: tres idas e voltas que acabam; o cadeado balanca junto.
            f.tremor = if (desde > 0 && desde < 0.45) (sin(desde * 40) * 7 * (1 - desde / 0.45)).toFloat() else 0f
            f.balanco = if (desde > 0 && desde < 0.5) (sin(desde * 30) * 14 * (1 - desde / 0.5)).toFloat() else 0f
            // A onda: cada palavra brilha um instante e troca a cifra, em ordem.
            for (i in 0 until 12) {
                val local = t - Errada.ondaDe - i * Errada.ondaPasso
                f.onda[i] = if (local < 0 || local > 0.35) 0.0 else sin(local / 0.35 * Math.PI)
            }
        }
        ModoDoCartao.revelar -> {
            if (parado) {
                f.campo = 1.0; f.teclas = Historia.teclas; f.destrancado = true
                f.mostrada.fill(1.0)
                return f
            }
            val t = agora % Historia.periodo
            f.campo = suave((t - Historia.campoEntra) / 0.25) * (1 - suave((t - Historia.campoSai) / 0.3))
            f.teclas = if (t < Historia.escondeDe && t >= Historia.digitaDe)
                (((t - Historia.digitaDe) / Historia.tecla).toInt() + 1).coerceIn(0, Historia.teclas) else 0
            f.cursor = f.campo > 0.5 && t < Historia.abre && (t * 2.4).toInt() % 2 == 0
            // O cadeado fecha e todas as palavras voltam a cifrar no mesmo instante.
            f.destrancado = t >= Historia.abre && t < Historia.escondeDe
            val esconde = suave((t - Historia.escondeDe) / 0.16)
            for (i in 0 until 12) f.mostrada[i] = suave((t - Historia.revelaDe - i * Historia.revelaPasso) / Historia.assenta) * (1 - esconde)
        }
    }
    return f
}

@Composable
private fun Cabecalho(q: Quadro, nomeDoArquivo: String) {
    Row(Modifier.fillMaxWidth().height(34.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(if (q.destrancado) Icones.envelopeAbertoCheio else Icones.envelopeCheio, Paleta.tinta, tamanho = 18.dp)
        }
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            Text(nomeDoArquivo, style = glifo, color = Paleta.tintaSuave, maxLines = 1, overflow = TextOverflow.Ellipsis,
                 modifier = Modifier.alpha((1 - q.campo).toFloat()))
            if (q.campo > 0.01) CampoDaSenha(q, Modifier.alpha(q.campo.toFloat()))
        }
        // Na senha errada, o cadeado so balanca: continua fechado, sem cor.
        Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) {
            Icone(if (q.destrancado) Icones.cadeadoAbertoCheio else Icones.cadeadoCheio, if (q.destrancado) Paleta.sucesso else Paleta.tintaSuave,
                  tamanho = 17.dp, modifier = Modifier.graphicsLayer { rotationZ = q.balanco; transformOrigin = TransformOrigin(0.5f, 0f) })
        }
    }
}

/**
 * A senha sendo digitada: pontos, um por tecla, e o cursor piscando logo depois do ultimo. O campo
 * tem a largura da senha inteira desde o comeco, para nao crescer a cada tecla.
 */
@Composable
private fun CampoDaSenha(q: Quadro, modifier: Modifier = Modifier) {
    Row(
        modifier.offset(x = q.tremor.dp).width(11.dp * Historia.teclas + 2.dp + Espaco.sm * 2).height(30.dp)
            .clip(CircleShape).background(Paleta.vazio).border(1.5.dp, Paleta.baixa.copy(alpha = q.negado.toFloat()), CircleShape)
            .padding(horizontal = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        repeat(q.teclas) { Box(Modifier.size(7.dp).clip(CircleShape).background(if (q.negado > 0.3) Paleta.baixa else Paleta.tinta)) }
        Box(Modifier.width(2.dp).height(16.dp).clip(RoundedCornerShape(1.dp)).background(Paleta.acento).alpha(if (q.cursor) 1f else 0f))
    }
}

@Composable
private fun Casa(i: Int, mostrada: Double, tique: Long, modifier: Modifier = Modifier) {
    val feita = mostrada >= 0.5
    val forma = RoundedCornerShape(Raio.chip)
    Row(
        modifier.height(30.dp).clip(forma).background(Paleta.vazio).border(1.dp, if (feita) Paleta.borda else Paleta.bordaForte, forma)
            .padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text("${i + 1}", style = numero, color = Paleta.tintaApagada, textAlign = TextAlign.End, modifier = Modifier.width(15.dp))
        Box(contentAlignment = Alignment.CenterStart) {
            Text(CifraDoEnvelope.glifos(i, tique + (mostrada * 40).toLong()), style = glifo, color = Paleta.tintaSuave, maxLines = 1, softWrap = false,
                 modifier = Modifier.alpha((1 - mostrada).toFloat()))
            if (i < CifraDoEnvelope.exemplo.size && mostrada > 0.01) {
                Text(CifraDoEnvelope.exemplo[i], style = palavra, color = Paleta.tinta, maxLines = 1, softWrap = false,
                     modifier = Modifier.graphicsLayer {
                         alpha = mostrada.toFloat()
                         val e = (0.92 + 0.08 * mostrada).toFloat()
                         scaleX = e; scaleY = e
                         transformOrigin = TransformOrigin(0f, 0.5f)
                     })
            }
        }
    }
}

/** O fundo cifrado do cartao: quadradinhos cinza enchendo a area, cada um no seu compasso, sorteados de um contador (so desenho). */
@Composable
private fun FundoCifrado(tique: Long, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val passo = 4.4.dp.toPx()
        val celula = 3.4.dp.toPx()
        val raio = CornerRadius(0.8.dp.toPx())
        val colunas = max(((size.width + passo - celula) / passo).toInt(), 1)
        val linhas = max(((size.height + passo - celula) / passo).toInt(), 1)
        for (linha in 0 until linhas) for (coluna in 0 until colunas) {
            val id = linha * 1000 + coluna
            // Cada pixel troca no proprio ritmo: um a cada 1 a 4 quadros.
            val ritmo = 1 + (PixelsCifrando.ruido(0, id, 0x51) * 4).toInt()
            // Cinza escuro, quase preto.
            val tom = 0.03 + 0.09 * PixelsCifrando.ruido(0, id, tique / ritmo)
            drawRoundRect(PixelsCifrando.cinza(tom), Offset(coluna * passo, linha * passo), Size(celula, celula), raio)
        }
    }
}

private val numero = TextStyle(fontFamily = Letra.familia(FontWeight.Medium, 11f), fontWeight = FontWeight.Medium, fontSize = 11.sp, fontFeatureSettings = "tnum")
private val glifo = TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium, fontSize = 13.sp)
private val palavra = TextStyle(fontFamily = Letra.familia(FontWeight.SemiBold, 13f), fontWeight = FontWeight.SemiBold, fontSize = 13.sp)

/**
 * "Como funciona" do envelope (o `EnvelopeHowItWorks` do iOS), em tres telas: a senha da carteira
 * virando um arquivo cifrado que so abre com a senha que a pessoa escolhe. Nenhuma palavra de verdade.
 */
@Composable
fun ComoFuncionaOEnvelope(aoFechar: () -> Unit) {
    val paginas = listOf(
        t("As palavras viram um arquivo cifrado") to
            t("O app cifra uma cópia da senha da sua carteira com outra senha, que só você escolhe. Tudo acontece aqui no celular, e o envelope fica salvo só aqui, até você decidir onde guardar uma cópia."),
        t("Sem a senha, o arquivo é ruído") to
            t("Tudo dentro dele é criptografado aqui no celular. Sem a senha, ele não mostra quantas palavras guarda nem o que tem dentro, e uma senha errada só devolve ruído."),
        t("Só a sua senha abre") to
            t("Com a senha certa, as palavras voltam. Sem ela, ninguém abre, nem a Escalibur, e senha esquecida não se recupera. Cada tentativa exige uma conta pesada, de propósito: adivinhar uma senha forte fica lento demais."),
    )
    val estado = rememberPagerState { paginas.size }
    val escopo = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().background(Paleta.vazio).navigationBarsPadding()) {
        CabecalhoDaFolha(t("Como funciona"), aoFechar)
        HorizontalPager(estado, Modifier.weight(1f)) { indice ->
            Column(Modifier.fillMaxSize().padding(horizontal = Espaco.margem), horizontalAlignment = Alignment.CenterHorizontally) {
                // So a tela visivel anima. As duas do cartao descem um pouco, com o texto, para o conjunto ficar no centro.
                Box(Modifier.padding(top = if (indice == 0) Espaco.lg else Espaco.lg + 32.dp).fillMaxWidth().height(236.dp),
                    contentAlignment = Alignment.Center) {
                    if (estado.currentPage == indice) when (indice) {
                        0 -> CenaDoEnvelope()
                        // As duas seguintes sao o mesmo arquivo: primeiro uma senha errada que nao abre;
                        // depois a senha certa abre o envelope e revela as palavras.
                        1 -> CartaoCifrado(ModoDoCartao.negado)
                        else -> CartaoCifrado(ModoDoCartao.revelar)
                    }
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
