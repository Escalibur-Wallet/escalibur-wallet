package app.escalibur.wallet.ui.carteira

import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.Esqueleto
import app.escalibur.wallet.ui.comp.TelaComBarra
import app.escalibur.wallet.ui.comp.TextoNumerico
import app.escalibur.wallet.ui.mercado.BotaoFavorito
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.atividade.DetalheDaAtividade
import app.escalibur.wallet.ui.atividade.LinhaDaAtividade
import app.escalibur.wallet.ui.atividade.Movimento
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.SecaoDoGrafico
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.Transferencia
import app.escalibur.wallet.ui.enviar.FluxoDeEnviar
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.principal.Navegacao
import kotlinx.coroutines.launch
import app.escalibur.wallet.ui.trocar.ControleDaTroca
import app.escalibur.wallet.ui.principal.Aba
import androidx.compose.runtime.rememberCoroutineScope
import app.escalibur.wallet.ui.receber.FluxoDeReceber
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo

/** O "Gravar agora": a copia que faltou, pelas palavras ou so pela passphrase. */
@Composable
fun CopiaAgora(carteira: Carteira) = FluxoDeRevelar(carteira, copia = true) { Navegacao.fechar() }

/** Um ativo da carteira, numa rolagem so: a posicao e o numero grande; o preco, com o grafico, vem logo abaixo. */
@Composable
fun DetalheDoAtivo(id: String) {
    val contexto = LocalContext.current
    val escopo = rememberCoroutineScope()
    val retrato = Saldos.retrato
    val linha = retrato.todasAsLinhas.firstOrNull { it.id == id }
    val oculto = App.ocultarSaldos
    val moeda = App.estado.moeda
    var historico by remember { mutableStateOf<List<Movimento>?>(null) }
    LaunchedEffect(id) {
        val ids = linha?.posicoes?.map { it.ativo }.orEmpty()
        historico = runCatching {
            Api.objeto("atividade.mostrar").optJSONArray("itens").objetos().map(::Movimento)
                .filter { m -> linha != null && (m.coingecko == linha.coingecko && linha.coingecko != null || ids.any { it.startsWith(m.rede) && m.simbolo == linha.simbolo }) }
        }.getOrDefault(emptyList())
    }
    if (linha == null) {
        TelaComBarra(aoVoltar = { Navegacao.fechar() }) {}
        return
    }
    val observacao = App.estado.carteira?.observacao == true
    var podeTrocar by remember(id) { mutableStateOf(false) }
    LaunchedEffect(id) { podeTrocar = ControleDaTroca.permite(linha.posicoes.map { it.ativo }) }
    val ativo = linha.posicoes.firstOrNull()?.ativo
    TelaComBarra(
        aoVoltar = { Navegacao.fechar() },
        centro = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                LogoDaMoeda(linha.coingecko, linha.simbolo, 20.dp, naoConferido = !linha.conferido && !linha.reconhecido)
                Text(linha.nome, style = estilo(Tipo.acao), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (linha.custom) SeloDeToken(TipoDeSelo.custom)
            }
        },
        acoes = if (linha.coingecko != null) ({ BotaoFavorito(linha.coingecko) }) else null,
        rodape = if (observacao) null else ({
            Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                BotaoSecundario(t("Enviar"), Modifier.weight(1f), altura = Altura.primaria) { Navegacao.cobrir { FluxoDeEnviar(ativo) } }
                BotaoSecundario(t("Receber"), Modifier.weight(1f), altura = Altura.primaria) { Navegacao.folha { FluxoDeReceber(ativo) } }
                if (podeTrocar && ativo != null) {
                    BotaoPrimario(t("Trocar"), Modifier.weight(1f)) {
                        escopo.launch {
                            if (!ControleDaTroca.preparar(ativo, vende = true)) return@launch
                            Navegacao.fecharTudo()
                            Navegacao.aba = Aba.trocar
                        }
                    }
                }
            }
        }),
    ) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(top = Espaco.sm, bottom = Espaco.xl)) {
            // A posicao: o valor vem da carteira de agora, para a cotacao que chega depois aparecer aqui tambem.
            Column(Modifier.padding(horizontal = Espaco.margem), verticalArrangement = Arrangement.spacedBy(Espaco.xxs)) {
                Text(t("Sua posição"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                val valor = linha.valor
                if (!oculto && valor == null && Saldos.esperandoPreco(linha)) {
                    Esqueleto(150.dp, 26.dp, Modifier.padding(vertical = 4.dp))
                } else {
                    TextoNumerico(if (oculto) "R$ ••••••" else valor?.let { Formato.valor(it, moeda) } ?: t("sem preço"), estilo(Tipo.numero), Paleta.tinta, valor = valor)
                }
                Text(if (oculto) "••••" else Formato.cripto(linha.total, linha.casas, linha.simbolo, Formato.EstiloCripto.cheio), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            }
            // O reconhecido pelo CoinGecko tambem tem grafico, pelo id que o CoinGecko deu ao contrato
            // (como no iOS); sem CoinGecko e sem OKX, o nucleo desenha pela pool de DEX do contrato.
            (linha.coingecko ?: linha.grafico)?.let { coingecko ->
                Box(Modifier.padding(top = Espaco.lg)) {
                    SecaoDoGrafico(coingecko, linha.preco, linha.variacao24h, moeda, estavel = linha.estavel, precoGrande = false)
                }
            }
            if (linha.posicoes.size > 1) {
                Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xl), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Text(t("Por rede"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
                    for (posicao in linha.posicoes) {
                        val rede = Redes.rede(posicao.rede)
                        Row(Modifier.fillMaxWidth().height(36.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                            SeloDaRede(posicao.rede, rede?.coingecko ?: posicao.rede, 20.dp, Paleta.vazio)
                            Text(posicao.redeNome, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
                            Text(if (oculto) "•••" else Formato.cripto(posicao.quantidade, posicao.casas, linha.simbolo, Formato.EstiloCripto.cheio),
                                 style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                        }
                    }
                }
            }
            linha.posicoes.firstOrNull()?.let { posicao ->
                val contrato = posicao.contrato ?: return@let
                if (contrato.contains(":")) return@let
                Row(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(if (posicao.rede == "xrpl") t("Contrato no %@", posicao.redeNome) else t("Contrato na %@", posicao.redeNome), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                        Text(Formato.endereco(contrato), style = estilo(Tipo.monoPequeno), color = Paleta.tintaSuave)
                    }
                    Box(Modifier.size(Altura.toque).clickable {
                        Transferencia.copiar(contexto, contrato)
                        Avisos.mostrar(t("Contrato copiado."))
                    }, contentAlignment = Alignment.Center) { Icone(Icones.copiar, Paleta.tintaSuave, tamanho = 15.dp, descricao = t("Copiar contrato")) }
                }
            }
            AtividadeDoAtivo(historico, linha.simbolo, oculto, Modifier.padding(top = Espaco.xl))
        }
    }
}

/** A secao "Atividade" da pagina do ativo: as ultimas oito, e o caminho para a lista inteira na aba Atividade. */
@Composable
private fun AtividadeDoAtivo(historico: List<Movimento>?, simbolo: String, oculto: Boolean, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(t("Atividade"), style = estilo(Tipo.cabecalho), color = Paleta.tinta, modifier = Modifier.padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs))
        when {
            historico == null -> repeat(3) {
                Row(Modifier.fillMaxWidth().heightIn(min = Altura.linha).padding(horizontal = Espaco.margem), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                    Box(Modifier.size(40.dp).clip(CircleShape).background(Paleta.corpo))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) { Esqueleto(120.dp); Esqueleto(80.dp) }
                    Esqueleto(72.dp, 16.dp)
                }
            }
            historico.isEmpty() -> Text(t("Nenhum movimento de %@ ainda. Envios, recebimentos e trocas aparecem aqui.", simbolo), style = estilo(Tipo.nota),
                                        color = Paleta.tintaSuave, modifier = Modifier.padding(horizontal = Espaco.margem))
            else -> {
                for (m in historico.take(8)) LinhaDaAtividade(m, oculto) { Navegacao.abrir { DetalheDaAtividade(m) } }
                if (historico.size > 8) {
                    BotaoTerciario(t("Ver tudo na Atividade"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xs)) {
                        Navegacao.fecharTudo()
                        Navegacao.aba = Aba.atividade
                    }
                }
            }
        }
    }
}
