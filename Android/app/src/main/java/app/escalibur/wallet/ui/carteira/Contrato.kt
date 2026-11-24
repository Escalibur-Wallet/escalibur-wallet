package app.escalibur.wallet.ui.carteira

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.EnderecoEmBlocos
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.SecaoDoGrafico
import app.escalibur.wallet.ui.comp.TelaComBarra
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.comp.esperasDoContrato
import app.escalibur.wallet.ui.comp.Transferencia
import app.escalibur.wallet.ui.principal.Aba
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import app.escalibur.wallet.ui.textos
import app.escalibur.wallet.ui.trocar.ControleDaTroca
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

/** O aviso de todo token fora da lista conferida (o `TokenReasonText.anyoneCanCreate` do iOS). */
val qualquerUmCriaToken: String
    get() = t("Qualquer pessoa cria um token com qualquer nome e qualquer símbolo. Este não está na lista conferida da Escalibur: o nome e o símbolo foram escritos por quem criou o contrato. Não abra sites que aparecem no nome e não conecte esta carteira a nada que o token peça.")

/** Cada sinal de golpe (`TokenSafety.Reason`), pelo nome que o nucleo manda. */
fun textoDoMotivo(motivo: String): String = when (motivo) {
    "link" -> t("O nome ou o símbolo traz um site ou um @. É o jeito mais comum de levar alguém a uma página que pede a senha da carteira.")
    "bait" -> t("O nome usa isca: resgate, prêmio, bônus, airdrop, visite.")
    "imitation" -> t("O símbolo imita o de uma moeda conhecida, com outro contrato.")
    "dust" -> t("Chegou uma quantia mínima sem você pedir. Serve para o endereço de quem mandou aparecer no seu histórico.")
    "flaggedBySource" -> t("A própria fonte da rede marca este token como golpe.")
    else -> t("O nome tem caracteres invisíveis ou que invertem o texto.")
}

/** Um ponto de lista com o icone a esquerda, na altura da primeira linha. */
@Composable
fun PontoDoToken(texto: String, icone: ImageVector, cor: androidx.compose.ui.graphics.Color, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Box(Modifier.width(18.dp).padding(top = 1.dp), contentAlignment = Alignment.TopCenter) { Icone(icone, cor, tamanho = 15.dp) }
        Text(texto, style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.weight(1f))
    }
}

/**
 * O contrato inteiro (ou o codigo e o emissor), para o dono conferir com a fonte oficial, com copiar e ver no explorador (o
 * `ContractPanel` do iOS). `token`: o que o nucleo devolve em "tokens.detalhe" e na leitura da moeda custom.
 */
@Composable
fun PainelDoContrato(token: JSONObject, modifier: Modifier = Modifier) {
    val contexto = LocalContext.current
    val referencia = token.optString("referencia").takeIf { it.isNotEmpty() && it != "null" } ?: return
    val rede = token.optString("rede")
    val redeNome = token.optString("redeNome")
    val no = rede == "xrpl"
    val forma = RoundedCornerShape(Raio.cartao)
    Column(
        modifier.fillMaxWidth().clip(forma).background(Paleta.corpo).border(1.dp, Paleta.borda, forma).padding(Espaco.md),
        verticalArrangement = Arrangement.spacedBy(Espaco.xs),
    ) {
        token.optString("codigo").takeIf { it.isNotEmpty() && it != "null" }?.let { codigo ->
            Text(t("Código da moeda"), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            Text(codigo, style = estilo(Tipo.monoPequeno), color = Paleta.tinta)
            Text(if (no) t("Emissor no %@", redeNome) else t("Emissor na %@", redeNome), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                 modifier = Modifier.padding(top = Espaco.xxs))
        } ?: Text(if (no) t("%@ no %@", token.optString("rotulo"), redeNome) else t("%@ na %@", token.optString("rotulo"), redeNome),
                  style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        // Conta com nome (NEAR), tipo de moeda da Sui, numero de ativo: inteiro, sem quebrar em blocos que nao existem nele.
        if (referencia.length >= 26 && referencia.all { it.isLetterOrDigit() && it.code < 128 }) EnderecoEmBlocos(referencia)
        else Text(referencia, style = estilo(Tipo.mono), color = Paleta.tinta)
        Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            AcaoDoContrato(t("Copiar"), Icones.copiar) {
                Transferencia.copiar(contexto, referencia)
                Avisos.mostrar(t("Copiado. Confira o endereço inteiro com a fonte oficial do token."))
            }
            token.optString("explorador").takeIf { it.startsWith("https://") }?.let { url ->
                AcaoDoContrato(t("Ver no %@", token.optString("exploradorNome")), Icones.setaDiagonal) {
                    runCatching { contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                }
            }
        }
    }
}

@Composable
private fun AcaoDoContrato(titulo: String, icone: ImageVector, acao: () -> Unit) {
    Row(Modifier.heightIn(min = Altura.toque).clickable(onClick = acao), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icone(icone, Paleta.tinta, tamanho = 15.dp)
        Text(titulo, style = estilo(Tipo.nota), color = Paleta.tinta)
    }
}

/**
 * O aviso que o CoinGecko poe no token (dono do contrato pode bloquear venda, mudar taxa, cunhar), para o token que mostra
 * grafico pelo contrato (o `ContractNoticeBanner` do iOS). O texto vem em ingles, como o CoinGecko publica; o app nao traduz o
 * que nao escreveu.
 */
@Composable
fun AvisoDoContrato(id: String, modifier: Modifier = Modifier) {
    var aviso by remember(id) { mutableStateOf<String?>(null) }
    LaunchedEffect(id) {
        for (espera in esperasDoContrato) {
            if (espera > 0) delay(espera)
            // Sem erro, a resposta vale, com ou sem aviso; com erro (limite), de novo.
            val lido = runCatching { Api.objeto("mercado.avisoDoContrato", JSONObject().put("id", id)) }.getOrNull() ?: continue
            aviso = lido.optString("aviso").takeIf { lido.has("aviso") && !lido.isNull("aviso") && it.isNotBlank() }
            return@LaunchedEffect
        }
    }
    aviso?.let {
        Faixa(TipoDeFaixa.cautela, t("O CoinGecko marca este token com um aviso"), modifier,
              mensagem = t("O aviso, como o CoinGecko publica: “%@”", it))
    }
}

/** O aviso recolhido numa linha, que abre o porque num toque (o `ExpandableCaution` do iOS). */
@Composable
fun CautelaQueAbre(titulo: String, mensagem: String, modifier: Modifier = Modifier) {
    var aberta by remember { mutableStateOf(false) }
    val giro by animateFloatAsState(if (aberta) 180f else 0f, label = "seta")
    val forma = RoundedCornerShape(Raio.cartao)
    Column(
        modifier.fillMaxWidth().clip(forma).background(Paleta.cautelaFundo).clickable(role = Role.Button) { aberta = !aberta }
            .padding(Espaco.sm).animateContentSize(),
        verticalArrangement = Arrangement.spacedBy(Espaco.xs),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
            Icone(Icones.alerta, Paleta.cautela, tamanho = 14.dp)
            Text(titulo, style = estilo(Tipo.nota).copy(fontWeight = FontWeight.SemiBold), color = Paleta.tinta, modifier = Modifier.weight(1f))
            Icone(Icones.abaixo, Paleta.tintaSuave, tamanho = 12.dp, modifier = Modifier.rotate(giro))
        }
        if (aberta) Text(mensagem, style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(start = 22.dp))
    }
}

/**
 * Tocar num token de "Outros tokens" ou dos suspeitos (o `OtherTokenDetailView` do iOS): o contrato inteiro e o aviso de que
 * qualquer um cria token com qualquer nome. Sem enviar daqui (o caminho para enviar e adicionar como moeda custom, que le o token
 * de novo na rede). Trocar, sim, nas redes EVM e na Solana, se nao for suspeito: o motor confere as casas e simula antes de assinar.
 */
@Composable
fun DetalheDoOutroToken(id: String) {
    val escopo = rememberCoroutineScope()
    val retrato = Saldos.retrato
    val outro = (retrato.todosOsOutros + retrato.outros + retrato.suspeitos).firstOrNull { it.id == id }
    var detalhe by remember(id) { mutableStateOf<JSONObject?>(null) }
    LaunchedEffect(id) { detalhe = runCatching { Api.objeto("tokens.detalhe", JSONObject().put("id", id)) }.getOrNull() }
    var podeTrocar by remember(id) { mutableStateOf(false) }
    LaunchedEffect(id) {
        podeTrocar = outro?.suspeito == false && App.estado.carteira?.observacao != true && ControleDaTroca.permite(listOf(id))
    }
    if (outro == null) {
        TelaComBarra(aoVoltar = { Navegacao.fechar() }) {}
        return
    }
    val oculto = App.ocultarSaldos
    val moeda = App.estado.moeda
    val token = detalhe?.optJSONObject("token")
    TelaComBarra(aoVoltar = { Navegacao.fechar() }) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(top = Espaco.sm, bottom = Espaco.xl)) {
            Row(Modifier.padding(horizontal = Espaco.margem), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                LogoDaMoeda(null, outro.simbolo, 48.dp, anel = Paleta.vazio, naoConferido = true, rede = outro.rede, redeCoingecko = Redes.rede(outro.rede)?.coingecko)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(outro.simbolo, style = estilo(Tipo.titulo), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis,
                             modifier = Modifier.weight(1f, fill = false))
                        SeloDeToken(if (outro.suspeito) TipoDeSelo.suspeito else TipoDeSelo.naoVerificado)
                    }
                    Text(outro.nome, style = estilo(Tipo.nota), color = Paleta.tintaSuave, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }

            Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xxs)) {
                Text(t("Nesta carteira"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                Text(if (oculto) "••••" else Formato.cripto(outro.quantidade, outro.casas, outro.simbolo, Formato.EstiloCripto.cheio),
                     style = estilo(Tipo.numero), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
                val preco = outro.preco
                val valor = outro.valor
                val linhaDoPreco = when {
                    outro.suspeito -> t("Sem preço: token suspeito nunca entra no saldo total.")
                    preco == null || valor == null -> t("Sem preço confiável por contrato. Fica fora do saldo total.")
                    else -> t("%@ pelo preço do contrato, %@ cada.", Formato.valor(valor, moeda), Formato.preco(preco, moeda))
                }
                Text(linhaDoPreco, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            }

            // O grafico pelo contrato: CoinGecko, ou a pool de DEX com mais liquidez no GeckoTerminal. Token suspeito nunca ganha
            // grafico: um grafico bonito daria cara de confiavel a um golpe.
            if (!outro.suspeito) {
                Box(Modifier.padding(top = Espaco.lg)) {
                    SecaoDoGrafico(null, outro.preco, outro.variacao24h, moeda, precoGrande = false, contrato = id)
                }
                AvisoDoContrato(id, Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md))
            }

            Faixa(TipoDeFaixa.cautela, if (outro.suspeito) t("Este token tem cara de golpe") else t("Token não verificado"),
                  Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg), mensagem = qualquerUmCriaToken)

            val motivos = token?.optJSONArray("motivos").textos()
            if (outro.suspeito && motivos.isNotEmpty()) {
                Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Text(t("Por que está em suspeitos"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
                    for (motivo in motivos) PontoDoToken(textoDoMotivo(motivo), Icones.alertaContorno, Paleta.cautela)
                }
            }

            token?.let { PainelDoContrato(it, Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg)) }

            if (podeTrocar) {
                BotaoPrimario(t("Trocar %@", outro.simbolo), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg)) {
                    escopo.launch {
                        if (!ControleDaTroca.preparar(id, vende = true)) return@launch
                        Navegacao.fecharTudo()
                        Navegacao.aba = Aba.trocar
                    }
                }
            }

            if (token != null && detalhe?.optBoolean("podeAdicionar") == true) {
                Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Text(t("Se você conhece este token e confere o contrato com a fonte oficial dele, pode adicioná-lo como moeda custom. A carteira lê o token de novo na rede antes de salvar."),
                         style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    BotaoSecundario(t("Adicionar como moeda custom"), Modifier.fillMaxWidth()) {
                        val codigo = token.optString("codigo").takeIf { it.isNotEmpty() && it != "null" }
                        val referencia = token.optString("referencia")
                        Navegacao.folha {
                            AdicionarMoedaCustom(inicial = referencia, rede = token.optString("rede"), codigoInicial = codigo) { Navegacao.fechar() }
                        }
                    }
                }
            }
        }
    }
}
