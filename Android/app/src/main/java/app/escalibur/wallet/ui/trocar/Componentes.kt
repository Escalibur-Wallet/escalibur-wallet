package app.escalibur.wallet.ui.trocar

import app.escalibur.wallet.ui.principal.Navegacao
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.foundation.layout.fillMaxSize
import app.escalibur.wallet.ui.principal.FolhaDoIos
import app.escalibur.wallet.ui.comp.ControleDaFolha
import app.escalibur.wallet.ui.comp.CabecalhoDaFolha
import app.escalibur.wallet.ui.carteira.TipoDeSelo
import app.escalibur.wallet.ui.comp.Girando
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.ui.graphics.graphicsLayer
import app.escalibur.wallet.ui.comp.TextoNumerico
import app.escalibur.wallet.ui.comp.movimentoReduzido
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.carteira.SeloDeToken
import app.escalibur.wallet.ui.comp.Aceite
import app.escalibur.wallet.ui.comp.Esqueleto
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.Logos
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.toqueDeSelecao
import app.escalibur.wallet.ui.receber.CampoDeBusca
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.launch
import org.json.JSONObject

/** Caixa de valor: "Voce paga", "Voce vende" e "Voce recebe". */
@Composable
internal fun CaixaDeValor(
    titulo: String, ativo: AtivoDaTroca?, texto: String, dica: String, saldo: String?, emMoeda: String?, passou: Boolean,
    carregando: Boolean, calculado: Boolean, aoDigitar: (String) -> Unit, aoEscolher: () -> Unit, aoFracao: ((Double) -> Unit)?,
    aoFoco: ((Boolean) -> Unit)? = null, editavel: Boolean = true,
    /** O valor e uma estimativa enquanto a cotacao nova nao chega: apagado e pulsando, com o "Recalculando" embaixo. */
    recalculando: Boolean = false,
) {
    var focado by remember { mutableStateOf(false) }
    // O pulso da estimativa: a opacidade vai e volta devagar. Com as animacoes desligadas, so apagado.
    val parado = movimentoReduzido()
    val pulso = rememberInfiniteTransition(label = "recalculando").animateFloat(
        0.95f, 0.6f, infiniteRepeatable(tween(700, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "pulso",
    )
    val forma = RoundedCornerShape(Raio.cartao)
    Column(
        Modifier.fillMaxWidth().clip(forma).background(Paleta.corpo).border(1.dp, Paleta.borda, forma).padding(Espaco.md),
        verticalArrangement = Arrangement.spacedBy(Espaco.xs),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(titulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.weight(1f))
            if (saldo != null) Text(saldo, style = estilo(Tipo.nota), color = if (passou) Paleta.baixa else Paleta.tintaApagada, maxLines = 1)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            Box(Modifier.weight(1f)) {
                val tamanho = if (texto.length <= 10) 30.sp else (30f * 10 / texto.length).coerceAtLeast(16f).sp
                val estiloDoValor = TextStyle(
                    fontSize = tamanho, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum",
                    color = when {
                        passou -> Paleta.baixa
                        calculado -> Paleta.tinta.copy(alpha = 0.92f)
                        else -> Paleta.tinta
                    },
                )
                if (carregando && texto.isEmpty()) {
                    Box(Modifier.height(40.dp), contentAlignment = Alignment.CenterStart) { Esqueleto(120.dp, 22.dp) }
                } else {
                    // O valor que veio do app (a cotacao), sem o teclado nele: os digitos rolam quando
                    // ele muda, como no iOS; o campo fica por baixo, para o toque cair nele.
                    val rolando = calculado && editavel && !focado && texto.isNotEmpty() && !passou
                    if (texto.isEmpty()) Text(dica, style = estiloDoValor.copy(color = Paleta.tintaMorta), maxLines = 1)
                    if (editavel) CampoDeNumero(texto, if (rolando) estiloDoValor.copy(color = Color.Transparent) else estiloDoValor,
                                                Modifier.fillMaxWidth().onFocusChanged { focado = it.isFocused; aoFoco?.invoke(it.isFocused) }, aoDigitar)
                    else Text(texto, style = estiloDoValor, maxLines = 1)
                    if (rolando) {
                        TextoNumerico(texto, estiloDoValor, if (recalculando) Paleta.tintaSuave else estiloDoValor.color,
                                      Modifier.graphicsLayer { alpha = if (!recalculando) 1f else if (parado) 0.7f else pulso.value },
                                      texto.replace(Formato.decimal, ".").toDoubleOrNull())
                    }
                }
            }
            PilulaDoToken(ativo, aoEscolher)
        }
        if (emMoeda != null || aoFracao != null || recalculando) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Text(emMoeda ?: "", style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.weight(1f), maxLines = 1)
                if (recalculando) {
                    Text(t("Recalculando"), style = estilo(Tipo.nota), color = Paleta.tintaApagada, maxLines = 1,
                         modifier = Modifier.graphicsLayer { alpha = if (parado) 0.7f else pulso.value })
                }
                if (aoFracao != null) {
                    for ((rotulo, fracao) in listOf("25%" to 0.25, "50%" to 0.5, t("Máx") to 1.0)) {
                        Box(
                            Modifier.height(26.dp).clip(CircleShape).background(Paleta.trilho).clickable { aoFracao(fracao) }.padding(horizontal = Espaco.sm),
                            contentAlignment = Alignment.Center,
                        ) { Text(rotulo, style = estilo(Tipo.rotulo), color = Paleta.tinta) }
                    }
                }
            }
        }
    }
}

/**
 * O campo de um numero. O que se digita fica como esta; o texto que vem de fora (a fracao do saldo,
 * o preco de agora, outra rede) entra com o cursor no fim.
 */
@Composable
internal fun CampoDeNumero(texto: String, estilo: TextStyle, modifier: Modifier, aoDigitar: (String) -> Unit) {
    var campo by remember { mutableStateOf(TextFieldValue(texto, TextRange(texto.length))) }
    LaunchedEffect(texto) { if (campo.text != texto) campo = TextFieldValue(texto, TextRange(texto.length)) }
    BasicTextField(
        campo, { novo ->
            val filtrado = novo.text.filter { it.isDigit() || it == ',' || it == '.' }.take(40)
            campo = if (filtrado == novo.text) novo else TextFieldValue(filtrado, TextRange(filtrado.length))
            if (filtrado != texto) aoDigitar(filtrado)
        },
        singleLine = true, textStyle = estilo, cursorBrush = SolidColor(Paleta.acento),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, autoCorrectEnabled = false), modifier = modifier,
    )
}

@Composable
private fun PilulaDoToken(ativo: AtivoDaTroca?, acao: () -> Unit) {
    Row(
        Modifier.height(40.dp).clip(CircleShape).background(Paleta.controle).clickable(onClick = acao).padding(start = 6.dp, end = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (ativo != null) {
            LogoDaMoeda(ativo.coingecko, ativo.simbolo, 28.dp, rede = ativo.rede, redeCoingecko = ativo.redeCoingecko, anel = Paleta.controle,
                        naoConferido = !ativo.conferido)
            Text(ativo.simbolo, style = estilo(Tipo.acao), color = Paleta.tinta, maxLines = 1)
        } else {
            Text(t("Escolher token"), style = estilo(Tipo.acao), color = Paleta.tinta, modifier = Modifier.padding(start = Espaco.xs))
        }
        Icone(Icones.abaixo, Paleta.tintaSuave, tamanho = 12.dp)
    }
}

/** Ordem grande: de uma vez, pelo preco da ordem inteira, ou em partes, por um preco melhor. */
@Composable
internal fun EscolhaDeExecucao(partes: RetratoDaTroca.Partes, emPartes: Boolean, aoEscolher: (Boolean) -> Unit) {
    Column(Modifier.padding(top = Espaco.md), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        OpcaoDeExecucao(!emPartes, t("De uma vez"), null, partes.notaDeUmaVez, partes.deUmaVez) { aoEscolher(false) }
        OpcaoDeExecucao(emPartes, t("Em partes"), partes.ganho, t("Preço melhor, preenchida pela CoW conforme chega liquidez, em até 1 hora"), partes.emPartes) {
            aoEscolher(true)
        }
    }
}

@Composable
private fun OpcaoDeExecucao(escolhida: Boolean, titulo: String, ganho: String?, nota: String, quantia: String, acao: () -> Unit) {
    val forma = RoundedCornerShape(Raio.cartao)
    val toque = toqueDeSelecao()
    Row(
        Modifier.fillMaxWidth().clip(forma).background(Paleta.corpo).border(1.dp, if (escolhida) Paleta.bordaForte else Paleta.borda, forma)
            .clickable {
                if (!escolhida) toque()
                acao()
            }.padding(Espaco.md),
        horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        Box(Modifier.size(20.dp).clip(CircleShape).border(1.5.dp, if (escolhida) Paleta.tinta else Paleta.tintaMorta, CircleShape),
            contentAlignment = Alignment.Center) {
            if (escolhida) Box(Modifier.size(10.dp).clip(CircleShape).background(Paleta.tinta))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
                if (ganho != null) Text(ganho, style = estilo(Tipo.nota), fontWeight = FontWeight.SemiBold, color = Paleta.alta)
                Spacer(Modifier.weight(1f))
                Text(quantia, style = estilo(Tipo.linha), color = if (escolhida) Paleta.tinta else Paleta.tintaSuave, maxLines = 1)
            }
            Text(nota, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
    }
}

// MARK: Tolerancia

private val marcas = listOf(10, 50, 100, 300, 1_000)

/** As marcas a distancias iguais, a escala linear entre duas vizinhas: o trecho baixo ganha espaco. */
private fun posicao(bps: Int): Float {
    val valor = bps.coerceIn(10, 1_000).toDouble()
    for (i in 0 until marcas.lastIndex) {
        if (valor <= marcas[i + 1]) return ((i + (valor - marcas[i]) / (marcas[i + 1] - marcas[i])) / marcas.lastIndex).toFloat()
    }
    return 1f
}

private fun valorEm(razao: Float): Int {
    val x = razao.coerceIn(0f, 1f) * marcas.lastIndex
    val i = minOf(x.toInt(), marcas.lastIndex - 1)
    val cru = marcas[i] + (x - i) * (marcas[i + 1] - marcas[i])
    return (Math.round(cru / 10.0) * 10).toInt().coerceIn(10, 1_000)
}

private fun rotulo(bps: Int) = Formato.agrupado(bps / 100.0, 2, aparar = true) + "%"

/**
 * T4: a tolerancia de preco. A ponta esquerda e "Auto": a menor que costuma passar para o par,
 * recalculada a cada cotacao. `aoMudar(null)` volta ao automatico. O preenchimento fica sempre na
 * tinta do app, monocromatico como o resto (pedido do dono, 23/10/2026: o mesmo controle, "so tirando
 * as cores"; antes ele ia do branco ao amarelo e ao rosa).
 */
@Composable
internal fun Tolerancia(bps: Int, automatica: Boolean, auto: Int, modifier: Modifier = Modifier, aoMudar: (Int?) -> Unit) {
    var arrasto by remember { mutableStateOf<Float?>(null) }
    val toque = toqueDeSelecao()
    val alvo = if (automatica) 0f else posicao(bps)
    val mostrada by animateFloatAsState(arrasto ?: alvo, tween(if (arrasto != null) 0 else 180), label = "tolerancia")
    fun escolher(razao: Float) {
        val valor = valorEm(razao)
        val novoAuto = valor <= 10
        if (novoAuto == automatica && (novoAuto || valor == bps)) return
        toque()
        aoMudar(if (novoAuto) null else valor)
    }
    val texto = if (automatica) t("Auto · %@", rotulo(auto)) else rotulo(bps)
    val explicacao = when {
        automatica -> t("A menor que costuma passar para este par, recalculada a cada cotação.")
        bps < 30 -> t("Protege mais o preço, mas a troca pode falhar se o mercado se mexer, e a taxa da rede é cobrada mesmo assim.")
        bps < 101 -> t("Equilíbrio: passa na maioria das trocas sem deixar espaço grande para robôs.")
        bps < 301 -> t("Passa mesmo com o mercado agitado ou com pouca liquidez. Em troca, você aceita receber até %@ a menos, e robôs podem explorar essa diferença.", texto)
        else -> t("Só para token com taxa na transferência ou liquidez muito baixa. Você aceita receber até %@ a menos, e robôs podem explorar essa diferença.", texto)
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(t("Tolerância de preço"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.weight(1f))
            Text(texto, style = estilo(Tipo.linha), color = Paleta.tinta)
        }
        // O gesto vive enquanto a regua existe e chama sempre a escolha de agora: com a tolerancia como
        // chave, cada valor novo reiniciava o gesto no meio do arrasto, e a bolinha ficava presa.
        val escolhaDeAgora by rememberUpdatedState<(Float) -> Unit> { escolher(it) }
        BoxWithConstraints(
            Modifier.fillMaxWidth().height(34.dp)
                .pointerInput(Unit) { detectTapGestures { escolhaDeAgora(it.x / size.width) } }
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onDragStart = { inicio -> arrasto = (inicio.x / size.width).coerceIn(0f, 1f) },
                        onDragEnd = { arrasto = null }, onDragCancel = { arrasto = null },
                    ) { mudanca, _ ->
                        val razao = (mudanca.position.x / size.width).coerceIn(0f, 1f)
                        arrasto = razao
                        escolhaDeAgora(razao)
                    }
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            val largura = maxWidth
            val bolinha = if (arrasto != null) 30.dp else 24.dp
            Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(Paleta.trilho))
            Box(Modifier.width(maxOf(6.dp, largura * mostrada)).height(6.dp).clip(CircleShape).background(Paleta.tinta))
            for (marca in marcas) {
                Box(Modifier.offset(x = largura * posicao(marca) - 2.dp).size(4.dp).clip(CircleShape)
                        .background(if (!automatica && marca <= bps) Paleta.vazio.copy(alpha = 0.35f) else Paleta.bordaForte))
            }
            Box(Modifier.offset(x = ((largura * mostrada) - bolinha / 2).coerceIn(0.dp, largura - bolinha)).size(bolinha).clip(CircleShape).background(Paleta.tinta))
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(24.dp)) {
            val largura = maxWidth
            marcas.forEachIndexed { indice, marca ->
                val escolhida = if (automatica) indice == 0 else marca == bps
                val nome = if (indice == 0) t("Auto") else rotulo(marca)
                val posicionado = when (indice) {
                    0 -> Modifier.align(Alignment.TopStart)
                    marcas.lastIndex -> Modifier.align(Alignment.TopEnd)
                    else -> Modifier.offset(x = largura * posicao(marca) - 20.dp).width(40.dp)
                }
                Text(
                    nome, style = estilo(Tipo.nota), color = if (escolhida) Paleta.tinta else Paleta.tintaApagada, textAlign = TextAlign.Center, maxLines = 1,
                    modifier = posicionado.clickable {
                        toque()
                        aoMudar(if (indice == 0) null else marca)
                    }.padding(vertical = 4.dp),
                )
            }
        }
        // A explicacao em cinza, sem cor de alerta: o texto ja diz o que se troca.
        Text(explicacao, style = estilo(Tipo.nota), color = Paleta.tintaApagada)
    }
}

// MARK: A cotacao

@Composable
internal fun LinhasDaCotacao(controle: ControleDaTroca, r: RetratoDaTroca, cotacao: RetratoDaTroca.Cotacao, mudar: (JSONObject) -> Unit, aoVerRota: () -> Unit) {
    var invertida by remember { mutableStateOf(false) }
    var detalhes by remember { mutableStateOf(false) }
    // A cotacao de um pedido que ja mudou fica apagada ate a nova chegar.
    val apagada by animateFloatAsState(if (cotacao.atual) 1f else 0.45f, tween(180), label = "cotacao")
    Column(Modifier.padding(top = Espaco.lg).fillMaxWidth().animateContentSize().graphicsLayer { alpha = apagada },
           verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (invertida) cotacao.precoInvertido else cotacao.preco, style = estilo(Tipo.nota), color = Paleta.tinta, maxLines = 1,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).clickable { invertida = !invertida },
            )
            RelogioDaCotacao(controle.proxima, controle.buscando)
        }
        Row(Modifier.fillMaxWidth().clickable(onClick = aoVerRota).padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy((-6).dp)) {
                for (provedor in cotacao.provedores) LogoDoProvedor(provedor, 20.dp, Modifier.border(2.dp, Paleta.vazio, CircleShape))
            }
            Text(cotacao.rota, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Text(t("Ver rota"), style = estilo(Tipo.nota), fontWeight = FontWeight.SemiBold, color = Paleta.tinta)
        }
        Text(
            cotacao.taxaDaRede?.let { t("Taxas: rede %@ · sem taxa da Escalibur", Formato.valor(it, r.moeda)) }
                ?: t("Sem taxa da Escalibur. A taxa da rede aparece na revisão."),
            style = estilo(Tipo.nota), color = Paleta.tintaSuave,
        )
        r.abaixoDoAlvo?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.cautela) }
        // Em cinza, o texto secundario de sempre, sem cor de alerta (pedido do dono, 23/10/2026).
        r.naoVerificado?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.tintaSuave) }
        val impacto = cotacao.impacto ?: 0.0
        when (cotacao.nivel) {
            "visivel" -> Text(t("Impacto no preço %@%%", Formato.agrupado(impacto, 2)), style = estilo(Tipo.nota), color = Paleta.baixa)
            "confirmar" -> {
                Text(t("Esta ordem move o preço em %@%%. Dividir em ordens menores ajuda.", Formato.agrupado(impacto, 1)), style = estilo(Tipo.nota), color = Paleta.baixa)
                Aceite(r.impactoAceito, t("Entendo e quero trocar assim"), solto = true) { mudar(JSONObject().put("aceitarImpacto", it)) }
            }
            "bloqueado" -> Text(t("Esta troca perderia %@%% para o impacto no preço. Divida em ordens menores ou use uma ordem limite.", Formato.agrupado(impacto, 0)),
                                style = estilo(Tipo.nota), color = Paleta.baixa)
        }
        Row(Modifier.clickable { detalhes = !detalhes }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(t("Detalhes"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            Icone(if (detalhes) Icones.acima else Icones.abaixo, Paleta.tintaApagada, tamanho = 11.dp)
        }
        if (detalhes) {
            Detalhe(t("Garantido"), cotacao.garantidoTexto)
            Detalhe(t("Cotação do provedor"), cotacao.doProvedor)
            cotacao.prazo?.let { Detalhe(t("Prazo da ordem"), it) }
            cotacao.impacto?.let { Detalhe(t("Impacto no preço"), Formato.agrupado(it, 2) + "%") }
            if (r.protecao) Detalhe(t("Proteção contra robôs"), t("ligada"))
        }
    }
}

@Composable
internal fun Detalhe(rotulo: String, valor: String) {
    Row(Modifier.heightIn(min = 24.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(rotulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.weight(1f))
        Text(valor, style = estilo(Tipo.nota), color = Paleta.tinta, textAlign = TextAlign.End)
    }
}

/**
 * A proxima cotacao: um anel amarelo que esvazia, com os segundos no meio. Cada segundo mostrado
 * esvazia ate o seguinte, e o ultimo chega a zero bem quando a busca comeca. Buscando, o anel fica
 * vazio, com o trilho respirando, e a cotacao nova o enche de volta (pedido do dono, 23/10/2026: no
 * fim ele voltava um quarto de volta e ficava girando).
 */
@Composable
private fun RelogioDaCotacao(segundos: Int, buscando: Boolean) {
    val parado = movimentoReduzido()
    val mostrado = if (buscando) 0 else segundos.coerceIn(0, 15)
    val restante = (mostrado - 1).coerceAtLeast(0) / 15f
    // Recomecou (cotacao nova): enche rapido; contando: esvazia no ritmo do segundo.
    val enchendo = !buscando && segundos >= 15
    val fracao by animateFloatAsState(
        restante, if (parado) tween(0) else if (enchendo) tween(450, easing = FastOutSlowInEasing) else tween(1000, easing = LinearEasing), label = "relogio",
    )
    val respiro = rememberInfiniteTransition(label = "buscando").animateFloat(
        0.22f, 0.52f, infiniteRepeatable(tween(600, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "respiro",
    )
    Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(24.dp)) {
            val traco = 2.5.dp.toPx()
            val trilho = if (buscando && !parado) respiro.value else 0.22f
            drawCircle(Paleta.cautela.copy(alpha = trilho), style = Stroke(traco), radius = size.minDimension / 2 - traco / 2)
            if (fracao > 0.001f) {
                drawArc(Paleta.cautela, -90f, 360f * fracao, false, topLeft = Offset(traco / 2, traco / 2),
                        size = Size(size.width - traco, size.height - traco), style = Stroke(traco, cap = StrokeCap.Round))
            }
        }
        Text("$mostrado", color = Paleta.cautela, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
    }
}

/**
 * O logo de quem executa a troca ou a ponte, das imagens do app (as mesmas do iOS): os de quem tem
 * token vem do CoinGecko (UNI, SHIB, ACX, USDT0); os de LI.FI, De¹ e Circle, do site de cada um
 * (pedido do dono, 23/10/2026). Nome desconhecido: a inicial num disco.
 */
@Composable
fun LogoDoProvedor(nome: String, tamanho: Dp, modifier: Modifier = Modifier) {
    val contexto = LocalContext.current
    val chave = nome.lowercase()
    val arquivo = listOf("velora" to "provedor-velora", "kyber" to "provedor-kyberswap", "cow" to "provedor-cow", "jupiter" to "provedor-jupiter",
                         "pancake" to "provedor-pancakeswap", "uniswap" to "provedor-uniswap", "shiba" to "provedor-shibaswap",
                         "li.fi" to "provedor-lifi", "lifi" to "provedor-lifi", "de¹" to "provedor-de1", "de1" to "provedor-de1",
                         "across" to "provedor-across", "circle" to "provedor-circle", "cctp" to "provedor-circle", "usdt0" to "provedor-usdt0",
                         "stellar" to "rede-stellar", "xrp" to "rede-xrpl").firstOrNull { chave.contains(it.first) }?.second
    val imagem = remember(arquivo) { arquivo?.let { Logos.imagem(contexto, it) } }
    // O coelho da PancakeSwap vem sem fundo: o disco azul da marca por tras.
    val coelho = arquivo == "provedor-pancakeswap"
    Box(modifier.size(tamanho).clip(CircleShape).background(if (coelho) Color(0xFF1FC7D4) else Paleta.controle), contentAlignment = Alignment.Center) {
        if (imagem != null) {
            Image(imagem, null, Modifier.size(if (coelho) tamanho * 0.68f else tamanho), contentScale = if (coelho) ContentScale.Fit else ContentScale.Crop,
                  filterQuality = FilterQuality.High)
        } else {
            Text(nome.take(1).uppercase(), color = Paleta.tinta, fontWeight = FontWeight.Bold, fontSize = (tamanho.value * 0.5f).sp)
        }
    }
}

// MARK: As folhas

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun Folha(titulo: String, aoFechar: () -> Unit, conteudo: @Composable (fechar: (() -> Unit) -> Unit) -> Unit) {
    val controleDaFolha = remember { ControleDaFolha() }
    fun fechar(depois: () -> Unit) {
        controleDaFolha.depois = depois
        controleDaFolha.fechar()
    }
    FolhaDoIos(aoFechar = { aoFechar(); controleDaFolha.depois?.invoke(); controleDaFolha.depois = null }, media = true) { fecharFolha ->
        controleDaFolha.fechar = fecharFolha
        Column(Modifier.fillMaxSize().background(Paleta.corpo).navigationBarsPadding()) {
            CabecalhoDaFolha(titulo, { fechar {} })
            Box(Modifier.padding(top = Espaco.xs)) { conteudo(::fechar) }
        }
    }
}

/** A escolha do token. Vendendo, so o que a carteira tem nesta rede; as verificadas primeiro. */
@Composable
internal fun FolhaDeTokens(controle: ControleDaTroca, vende: Boolean, r: RetratoDaTroca, aoFechar: () -> Unit, aoEscolher: (String) -> Unit) {
    var opcoes by remember { mutableStateOf<List<OpcaoDeToken>?>(null) }
    var busca by remember { mutableStateOf("") }
    // Sobe a cada moeda adicionada pelo contrato: a lista le de novo e ja traz a nova.
    var adicionadas by remember { mutableIntStateOf(0) }
    LaunchedEffect(adicionadas) { opcoes = controle.opcoes(vende) }
    Folha(t("Escolher token"), aoFechar) { fechar ->
        CampoDeBusca(busca, t("Buscar por nome"), Modifier.padding(horizontal = Espaco.margem)) { busca = it }
        val termo = busca.trim()
        val todas = opcoes ?: emptyList()
        val lista = todas.filter { termo.isEmpty() || it.ativo.simbolo.contains(termo, true) || it.ativo.nome.contains(termo, true) }
        val conferidas = lista.filter { !it.fora }
        val fora = lista.filter { it.fora }
        LazyColumn(Modifier.fillMaxWidth().heightIn(min = 320.dp).padding(top = Espaco.xs, bottom = Espaco.md)) {
            if (opcoes == null) item {
                Box(Modifier.fillMaxWidth().padding(Espaco.lg), contentAlignment = Alignment.Center) { Girando(Paleta.tintaSuave, 20.dp) }
            }
            if (fora.isNotEmpty() && conferidas.isNotEmpty()) item { Secao(t("Verificadas")) }
            items(conferidas, key = { it.ativo.id }) { opcao -> LinhaDoToken(opcao) { fechar { aoEscolher(opcao.ativo.id) } } }
            if (fora.isNotEmpty()) {
                item { Secao(t("Fora da lista verificada")) }
                items(fora, key = { "fora-" + it.ativo.id }) { opcao -> LinhaDoToken(opcao) { fechar { aoEscolher(opcao.ativo.id) } } }
            }
            if (vende && opcoes != null && lista.isEmpty()) item {
                val rede = r.rede?.nome ?: ""
                Text(if (termo.isEmpty()) t("Nada para vender na %@ ainda. Receba ou troque em outra rede primeiro.", rede)
                     else t("Nada com este nome entre o que você tem na %@.", rede),
                     style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md))
            }
            // Qualquer token que os provedores trocam nesta rede, pelo contrato: lido na rede antes de entrar na lista.
            val rede = r.rede
            if (rede != null && rede.aceitaFora) item {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = Altura.linha).clickable {
                        Navegacao.folha { app.escalibur.wallet.ui.carteira.AdicionarMoedaCustom(rede = rede.id) { Navegacao.fechar(); adicionadas++ } }
                    }.padding(horizontal = Espaco.margem),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    Box(Modifier.size(36.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                        Icone(Icones.mais, Paleta.tinta, tamanho = 15.dp)
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(t("Adicionar moeda pelo contrato"), style = estilo(Tipo.linha), color = Paleta.tinta)
                        Text(t("Qualquer token que os provedores trocam na %@", rede.nome), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    }
                }
            }
        }
    }
}

@Composable
private fun Secao(titulo: String) {
    Text(titulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave,
         modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md, bottom = Espaco.xxs))
}

@Composable
private fun LinhaDoToken(opcao: OpcaoDeToken, acao: () -> Unit) {
    val ativo = opcao.ativo
    Row(
        Modifier.fillMaxWidth().heightIn(min = Altura.linha).clickable(onClick = acao).padding(horizontal = Espaco.margem),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        LogoDaMoeda(ativo.coingecko, ativo.simbolo, 36.dp, rede = ativo.rede, redeCoingecko = ativo.redeCoingecko, anel = Paleta.corpo, naoConferido = !ativo.conferido)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(ativo.simbolo, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                if (!ativo.conferido) SeloDeToken(if (ativo.custom) TipoDeSelo.custom else TipoDeSelo.naoVerificado)
            }
            Text(ativo.nome, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        opcao.quantidade?.let { Text(Formato.cripto(it, ativo.casas), style = estilo(Tipo.nota), color = Paleta.tinta) }
    }
}

/** T3: a rota, com a divisao entre provedores e as outras cotacoes da rodada. */
@Composable
internal fun FolhaDaRota(cotacao: RetratoDaTroca.Cotacao, aoFechar: () -> Unit, aoUsar: (String) -> Unit) {
    Folha(cotacao.tituloDaRota, aoFechar) { _ ->
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.lg),
               verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            for (perna in cotacao.pernas) {
                Row(Modifier.heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    LogoDoProvedor(perna.provedor, 28.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(perna.provedor, style = estilo(Tipo.linha), color = Paleta.tinta)
                        Text(if (cotacao.pernas.size > 1) t("%lld%% do valor", Math.round(perna.fracao * 100)) else t("Rota de agora"),
                             style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    }
                    Text(perna.recebe, style = estilo(Tipo.nota), color = Paleta.tinta)
                }
            }
            Text(cotacao.explicacao, style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs))
            if (cotacao.alternativas.isNotEmpty()) {
                Text(t("Outras cotações"), style = estilo(Tipo.cabecalho), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.md))
                Text(t("O mínimo garantido de cada provedor, pelo valor inteiro. Escolha outro se preferir: na revisão ele é cotado, conferido e simulado de novo."),
                     style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                for (alternativa in cotacao.alternativas) {
                    Row(Modifier.heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                        LogoDoProvedor(alternativa.provedor, 28.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(alternativa.provedor, style = estilo(Tipo.linha), color = Paleta.tinta)
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(alternativa.garante, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                                alternativa.diferenca?.let { Text(it, style = estilo(Tipo.nota), color = if (it.startsWith("+")) Paleta.alta else Paleta.tintaApagada) }
                            }
                        }
                        if (alternativa.usar) {
                            Box(Modifier.height(32.dp).clip(CircleShape).background(Paleta.controle).clickable { aoUsar(alternativa.provedor) }
                                    .padding(horizontal = Espaco.sm), contentAlignment = Alignment.Center) {
                                Text(t("Usar"), style = estilo(Tipo.rotulo), color = Paleta.tinta)
                            }
                        }
                    }
                }
            }
        }
    }
}
