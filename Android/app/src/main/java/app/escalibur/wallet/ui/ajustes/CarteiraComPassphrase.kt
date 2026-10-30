package app.escalibur.wallet.ui.ajustes

import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.runtime.LaunchedEffect
import app.escalibur.wallet.ui.comp.nascerDosPixels
import app.escalibur.wallet.ui.comp.EmblemaCifrado
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import app.escalibur.wallet.ui.comp.acimaDoTeclado
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import app.escalibur.wallet.ui.comp.Segredo
import androidx.compose.foundation.text.input.clearText
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.importar.CampoSecreto
import app.escalibur.wallet.ui.novacarteira.VerificacaoDoAparelho
import app.escalibur.wallet.ui.principal.Aba
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.launch
import org.json.JSONObject
import app.escalibur.wallet.ui.comp.TelaComBarra
import androidx.compose.ui.layout.layout
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.width
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.movimentoReduzido
import app.escalibur.wallet.ui.comp.relogio
import app.escalibur.wallet.ui.comp.saltoDeSaida
import java.util.Date

/**
 * S3: a carteira da 25a palavra a partir da carteira escolhida. A frase nao aparece: o cofre abre,
 * deriva a carteira nova e grava, com uma confirmacao so. Em tres passos: o que e, a checagem do
 * aparelho e so entao os campos da passphrase.
 */
@Composable
fun FluxoDaCarteiraComPassphrase(base: Carteira) {
    var passo by remember { mutableStateOf("explicacao") }
    val palavras = base.palavras ?: 12
    BackHandler {
        when (passo) {
            "checagem" -> passo = "explicacao"
            "digitar" -> passo = "checagem"
            else -> Navegacao.fechar()
        }
    }
    if (passo == "explicacao") {
        // Como no iOS: o conteudo rola por baixo do voltar, e o Continuar fica preso embaixo.
        TelaComBarra({ Navegacao.fechar() }, rodape = { BotaoPrimario(t("Continuar")) { passo = "checagem" } }) { espaco ->
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(horizontal = Espaco.margem).padding(vertical = Espaco.md),
                   horizontalAlignment = Alignment.CenterHorizontally) {
                // A parede de pixels com a porta escondida: as palavras abrem a de sempre, e a chave
                // da passphrase revela a outra. Sobe 20 sobre o espaco de cima, como no iOS.
                CenaDaPassphrase(CenaDaPassphrase.portaEscondida, 190.dp, Modifier.layout { medida, limites ->
                    val peca = medida.measure(limites)
                    val sobe = 20.dp.roundToPx()
                    layout(peca.width, peca.height - sobe) { peca.place(0, -sobe) }
                })
                Text(t("Carteira com passphrase"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                     modifier = Modifier.padding(top = Espaco.md))
                Text(t("Uma senha extra, escolhida por você. Junto com a senha de %@, ela abre outra carteira, com outros endereços.", base.nome),
                     style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs))
                BotaoComoFuncionaDaPassphrase(Modifier.padding(top = Espaco.md))
                Column(
                    Modifier.padding(top = Espaco.lg).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(Espaco.base),
                    verticalArrangement = Arrangement.spacedBy(Espaco.md),
                ) {
                    PontoDaPassphrase(Icones.olhoRiscado, t("Quem achar só as %lld palavras vê a carteira de sempre, não a da passphrase.", palavras))
                    PontoDaPassphrase(Icones.lapis, t("Anote a passphrase longe das %lld. Para abrir a carteira com passphrase em outro aparelho, você vai precisar das duas.", palavras))
                    PontoDaPassphrase(Icones.alerta, t("Esquecer a passphrase é perder o acesso à carteira com passphrase. Ninguém recupera, nem a Escalibur."))
                }
            }
        }
        return
    }
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().acimaDoTeclado()) {
        when (passo) {
            "checagem" -> {
                CabecalhoDeFolha("", null, aoVoltar = { passo = "explicacao" })
                Box(Modifier.weight(1f)) { VerificacaoDoAparelho(t("Deslize para digitar a passphrase"), criando = false) { passo = "digitar" } }
            }
            "digitar" -> DigitarPassphrase(base) { passo = "checagem" }
        }
    }
}

@Composable
private fun PontoDaPassphrase(icone: ImageVector, texto: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(icone, Paleta.tinta, tamanho = 15.dp)
        }
        Text(texto, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f).padding(top = 5.dp))
    }
}

/** O ultimo passo: os dois campos da passphrase e o nome da carteira nova. */
@Composable
private fun androidx.compose.foundation.layout.ColumnScope.DigitarPassphrase(base: Carteira, aoVoltar: () -> Unit) {
    val escopo = rememberCoroutineScope()
    val passphrase = remember { Segredo() }
    val repeticao = remember { Segredo() }
    var revelar by remember { mutableStateOf(false) }
    var nome by remember { mutableStateOf(t("%@ com passphrase", base.nome)) }
    var mensagem by remember { mutableStateOf<String?>(null) }
    var trabalhando by remember { mutableStateOf(false) }
    /** A carteira nova neste celular (id e a escolhida antes), enquanto o app procura movimento nela. */
    var nova by remember { mutableStateOf<Pair<String, String?>?>(null) }
    DisposableEffect(Unit) {
        onDispose {
            passphrase.clearText()
            repeticao.clearText()
        }
    }

    fun abrir() {
        if (trabalhando || passphrase.text.isEmpty()) return
        mensagem = null
        val a = passphrase.bytes()
        val b = repeticao.bytes()
        val iguais = a.isNotEmpty() && java.security.MessageDigest.isEqual(a, b)
        b.fill(0)
        if (!iguais) {
            a.fill(0)
            mensagem = t("As duas versões da passphrase não conferem.")
            return
        }
        trabalhando = true
        val titulo = nome.filter { !it.isISOControl() && Character.getType(it) != Character.FORMAT.toInt() }.trim().take(40)
            .ifEmpty { t("%@ com passphrase", base.nome) }
        escopo.launch {
            try {
                val aberta = Autorizacao.tentando(t("Abrir a carteira com passphrase")) { credencial ->
                    Api.comSegredo("carteira.abrirComPassphrase", JSONObject().put("base", base.id).put("nome", titulo).put("credencial", credencial.json()),
                                   *credencial.partes(a.copyOf()))
                } ?: return@launch
                passphrase.clearText()
                repeticao.clearText()
                App.recarregar()
                // A mesma frase com a mesma passphrase e a mesma carteira: ela ja estava aqui.
                if (aberta.optBoolean("jaAberta")) {
                    Avisos.mostrar(t("Esta carteira já está aberta, como %@. Ela passa a ser a carteira em uso.", aberta.getJSONObject("carteira").getString("nome")))
                    Navegacao.fecharTudo()
                    Navegacao.aba = Aba.carteira
                    return@launch
                }
                // Nova neste celular: antes de abrir, o app procura movimento nela (pedido do dono, 25/10/2026).
                nova = aberta.getJSONObject("carteira").getString("id") to aberta.optString("anterior").ifEmpty { null }
            } catch (falha: FalhaDoNucleo) {
                mensagem = when (falha.codigo) {
                    "sessao.passphraseLonga" -> t("A passphrase passou do tamanho máximo: até 256 caracteres sem acento, menos com acento. Encurte para seguir.")
                    "sessao.passphraseInvisivel" -> t("A passphrase tem um caractere invisível ou um espaço diferente do espaço comum. Escreva de novo, só com letras, números, símbolos e espaço comum: é o que dá para anotar no papel.")
                    // Na porta de criar nada esta errado: toda passphrase abre uma carteira.
                    "passphrase.espera" -> t("Muitas tentativas seguidas. Tente de novo às %@.", Formato.relogio(Date(falha.dados.optDouble("ate", 0.0).toLong())))
                    else -> Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível criar a carteira agora.")
                }
            } finally {
                a.fill(0)
                trabalhando = false
            }
        }
    }

    nova?.let { (id, anterior) ->
        BuscaDeMovimento(id, anterior, aoUsar = {
            Navegacao.fecharTudo()
            Navegacao.aba = Aba.carteira
        }) { nova = null }
        return
    }
    CabecalhoDeFolha("", null, aoVoltar = aoVoltar)
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md),
           verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        // O selo das telas onde se digita um segredo.
        Box(Modifier.fillMaxWidth().padding(bottom = Espaco.xs), contentAlignment = Alignment.Center) { EmblemaCifrado() }
        // O titulo e o texto no centro.
        Text(t("Digite a passphrase"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        Text(t("Escreva igual ao que você anotou. Diferença de maiúscula, acento ou espaço já abre outra carteira."), style = estilo(Tipo.corpo),
             color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(bottom = Espaco.md))
        Text(t("Passphrase"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        CampoSecreto(passphrase, t("Passphrase"), revelar) { revelar = it }
        // A repeticao so aparece quando a primeira comeca a ser digitada, e o campo inteiro nasce dos
        // pixels, como no iOS (24/10/2026); a dica entra quando ele termina.
        if (passphrase.text.isNotEmpty() || repeticao.text.isNotEmpty()) {
            val parado = app.escalibur.wallet.ui.comp.movimentoReduzido()
            val nascer = remember { androidx.compose.animation.core.Animatable(if (parado) 1f else 0f) }
            LaunchedEffect(Unit) { nascer.animateTo(1f, androidx.compose.animation.core.tween(1000, easing = androidx.compose.animation.core.LinearEasing)) }
            Box(Modifier.nascerDosPixels(nascer.value)) { CampoSecreto(repeticao, t("Repita a passphrase"), revelar) { revelar = it } }
            Text(t("Segure o dedo num campo para conferir as duas."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                 modifier = Modifier.graphicsLayer { alpha = if (nascer.value >= 1f) 1f else 0f })
        }
        Text(t("Nome"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
        Box(
            Modifier.fillMaxWidth().height(Altura.campo).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
                .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(horizontal = Espaco.md),
            contentAlignment = Alignment.CenterStart,
        ) {
            BasicTextField(nome, { nome = it.take(40) }, singleLine = true, textStyle = estilo(Tipo.linha).copy(color = Paleta.tinta),
                           cursorBrush = SolidColor(Paleta.acento), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                           modifier = Modifier.fillMaxWidth())
        }
        mensagem?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.sm)) }
    }
    Rodape {
        BotaoPrimario(t("Abrir carteira"), ligado = passphrase.text.isNotEmpty() && repeticao.text.isNotEmpty(), carregando = trabalhando) { abrir() }
    }
}

/**
 * Depois de abrir uma carteira com passphrase nova neste celular: procura movimento nela, rede por rede
 * (o PassphraseUsageView do iOS). Toda passphrase abre alguma carteira, e quem tentava lembrar a sua so
 * via que tinha errado uma letra pelo saldo zerado (pedido do dono, 25/10/2026). Com movimento, abre a
 * carteira. Sem nenhum, diz isso e deixa tentar outra passphrase, sem guardar a carteira vazia.
 */
@Composable
private fun androidx.compose.foundation.layout.ColumnScope.BuscaDeMovimento(
    id: String, anterior: String?, aoUsar: () -> Unit, aoTentarOutra: () -> Unit,
) {
    val escopo = rememberCoroutineScope()
    var rodada by remember { mutableStateOf(0) }
    var fase by remember { mutableStateOf("procurando") }
    var falharam by remember { mutableStateOf("") }
    var mensagem by remember { mutableStateOf<String?>(null) }
    // Daqui so se sai decidindo: usar a carteira ou tentar outra passphrase.
    BackHandler {}
    LaunchedEffect(rodada) {
        fase = "procurando"
        mensagem = null
        fase = try {
            val resposta = Api.objeto("carteira.usoDaPassphrase", JSONObject().put("id", id))
            when (resposta.optString("resultado")) {
                "usada" -> {
                    Avisos.mostrar(t("Esta carteira já teve movimento. Ela passa a ser a carteira em uso."))
                    aoUsar()
                    return@LaunchedEffect
                }
                "nunca" -> "nunca"
                else -> {
                    falharam = resposta.optString("falharam")
                    "incompleta"
                }
            }
        } catch (falha: FalhaDoNucleo) {
            falharam = ""
            "incompleta"
        }
    }

    fun tentarOutra() {
        escopo.launch {
            try {
                Api.objeto("carteira.descartarPassphrase", JSONObject().put("id", id).apply { anterior?.let { put("anterior", it) } })
                App.recarregar()
                aoTentarOutra()
            } catch (falha: FalhaDoNucleo) {
                mensagem = Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível apagar a carteira deste celular agora. Ela continua aqui; tente de novo.")
            }
        }
    }

    val (titulo, detalhe) = when (fase) {
        "procurando" -> t("Procurando movimento") to t("Conferindo as redes desta carteira, uma a uma. Leva alguns segundos.")
        "nunca" -> t("Esta carteira ainda não foi usada") to t("Nas redes que a Escalibur lê, ela nunca recebeu nem enviou nada. Tem certeza de que a passphrase está certa? Maiúsculas, acentos e espaços contam. Se é uma carteira nova, pode usar. Outros apps podem guardar saldo em caminhos que a Escalibur não lê, como o Taproot do Bitcoin.")
        else -> t("Nenhuma transferência até agora") to
            if (falharam.isEmpty()) t("Não foi possível procurar movimento agora. Confira a internet e procure de novo.")
            else t("Nas redes que responderam, esta carteira nunca teve movimento. Não responderam agora: %@.", falharam)
    }
    Column(Modifier.weight(1f).statusBarsPadding().padding(horizontal = Espaco.margem), horizontalAlignment = Alignment.CenterHorizontally,
           verticalArrangement = Arrangement.Center) {
        ArteDaBusca(fase != "procurando")
        Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.md))
        Text(detalhe, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm))
        mensagem?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
    }
    Rodape {
        when (fase) {
            "procurando" -> BotaoTerciario(t("Abrir sem esperar"), Modifier.fillMaxWidth()) { aoUsar() }
            "nunca" -> {
                // O botao principal nao empurra para descartar: a busca nao le todo caminho que outro app usa.
                BotaoPrimario(t("Usar esta carteira")) { aoUsar() }
                BotaoTerciario(t("Tentar outra passphrase"), Modifier.fillMaxWidth().padding(top = Espaco.xs)) { tentarOutra() }
            }
            else -> {
                BotaoPrimario(t("Procurar de novo")) { rodada++ }
                BotaoTerciario(t("Tentar outra passphrase"), Modifier.fillMaxWidth().padding(top = Espaco.xs)) { tentarOutra() }
                BotaoTerciario(t("Usar esta carteira"), Modifier.fillMaxWidth()) { aoUsar() }
            }
        }
    }
}

/**
 * Tres cartoes de rede, no desenho da Atividade vazia (a UsageSearchArt do iOS): entram um a um com o
 * status girando enquanto o app procura movimento; sem nenhum, cada status assenta num traco, um depois
 * do outro. Com o movimento reduzido, aparecem parados.
 */
@Composable
private fun ArteDaBusca(assentou: Boolean) {
    val parado = movimentoReduzido()
    val agora by relogio(parado)
    var assentouEm by remember { mutableStateOf<Float?>(null) }
    LaunchedEffect(assentou) { assentouEm = if (assentou) agora else null }
    val redes = listOf(Triple("bitcoin", "bitcoin", 0.62f), Triple("ethereum", "ethereum", 0.48f), Triple("solana", "solana", 0.7f))
    Box(Modifier.fillMaxWidth().height(220.dp), contentAlignment = Alignment.Center) {
        Column(Modifier.width(290.dp), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            redes.forEachIndexed { indice, (rede, coingecko, largura) ->
                val aparece = if (parado) 1f else ((agora - 0.15f - indice * 0.3f) / 0.4f).coerceIn(0f, 1f)
                val assenta = when {
                    !assentou -> 0f
                    parado -> 1f
                    else -> ((agora - (assentouEm ?: agora) - indice * 0.25f) / 0.3f).coerceIn(0f, 1f)
                }
                Row(
                    Modifier.fillMaxWidth().height(62.dp)
                        .graphicsLayer { alpha = aparece; translationY = (1 - aparece) * 16.dp.toPx() }
                        .clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(horizontal = Espaco.sm),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    SeloDaRede(rede, coingecko, 40.dp, Paleta.corpo)
                    Column(Modifier.weight(1f).graphicsLayer { alpha = 1f - assenta * 0.4f }, verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        Box(Modifier.width(150.dp * largura).height(9.dp).clip(CircleShape).background(Paleta.bordaForte))
                        Box(Modifier.width(90.dp * largura).height(7.dp).clip(CircleShape).background(Paleta.controle))
                    }
                    Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                        Canvas(Modifier.size(18.dp).graphicsLayer { alpha = 1 - assenta; rotationZ = if (parado) 0f else agora * 360f }) {
                            drawArc(Paleta.tintaApagada, -90f, 252f, false, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round))
                        }
                        Box(
                            Modifier.size(22.dp).graphicsLayer { val e = saltoDeSaida(assenta); scaleX = e; scaleY = e }
                                .border(1.5.dp, Paleta.bordaForte, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            Box(Modifier.width(8.dp).height(2.dp).clip(CircleShape).background(Paleta.tintaSuave))
                        }
                    }
                }
            }
        }
    }
}
