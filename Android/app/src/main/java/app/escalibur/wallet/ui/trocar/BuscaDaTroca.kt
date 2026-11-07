package app.escalibur.wallet.ui.trocar

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.carteira.AdicionarMoedaCustom
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.Girando
import app.escalibur.wallet.ui.comp.LogoDaMoeda
import app.escalibur.wallet.ui.comp.TelaComBarra
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.receber.AtivoRecebivel
import app.escalibur.wallet.ui.receber.LinhaDeRede
import app.escalibur.wallet.ui.receber.LinhaDoResultado
import app.escalibur.wallet.ui.receber.LinhaEsperando
import app.escalibur.wallet.ui.receber.NotaDaBusca
import app.escalibur.wallet.ui.receber.ResultadoDaBusca
import app.escalibur.wallet.ui.receber.TituloDeSecao
import app.escalibur.wallet.ui.receber.opcional
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.delay
import org.json.JSONObject

/**
 * A busca de qualquer moeda na escolha do que comprar, na troca de agora (pedido do dono, 06/11/2026): a mesma de Receber
 * ("receber.buscar"), com o CoinGecko e a lista embarcada. O `TokenPickerSheet` do iOS.
 */
internal class BuscaDaTroca {
    var tentativa by mutableIntStateOf(0)
    var resposta by mutableStateOf<Pair<String, JSONObject?>?>(null)
    /** O texto que o dono pediu para buscar em todas as moedas, com a lista daqui achando algo. */
    var ampliada by mutableStateOf<String?>(null)
}

/** Uma pergunta por texto, depois de uma pausa curta na digitacao, como em Receber. */
@Composable
internal fun AcompanharBusca(busca: BuscaDaTroca, termo: String, ligada: Boolean) {
    LaunchedEffect(termo.lowercase(), busca.tentativa, ligada) {
        if (!ligada || termo.length < 2) return@LaunchedEffect
        busca.resposta = null
        delay(350)
        busca.resposta = termo.lowercase() to runCatching { Api.objeto("receber.buscar", JSONObject().put("texto", termo)) }.getOrNull()
    }
}

/** Os achados fora do que a folha ja mostra. `listadas`: os ids do CoinGecko das moedas que ja aparecem em cima. */
internal fun LazyListScope.secaoDaBusca(busca: BuscaDaTroca, termo: String, listadas: Set<String>, nadaListado: Boolean, aoTocar: (ResultadoDaBusca) -> Unit) {
    if (termo.length < 2) return
    val atual = busca.resposta?.takeIf { it.first == termo.lowercase() }
    val r = atual?.second
    when {
        atual == null -> {
            item { TituloDeSecao(t("Mais moedas, fora da lista verificada")) }
            items(3) { LinhaEsperando() }
        }
        r == null || r.optString("estado") == "falhou" -> item {
            Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md)) {
                NotaDaBusca(t("O CoinGecko não respondeu agora. Aparecem só as moedas verificadas."))
                BotaoTerciario(t("Buscar de novo")) { busca.tentativa++ }
            }
        }
        r.optString("estado") == "frase" -> item {
            Box(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md)) {
                NotaDaBusca(t("Isto parece o começo das palavras de uma carteira, e a busca não saiu do celular. As palavras só se digitam ao importar uma carteira."))
            }
        }
        else -> {
            val achados = r.getJSONArray("resultados").objetos()
                .map { ResultadoDaBusca(it.getString("id"), it.getString("simbolo"), it.getString("nome"), if (it.has("posicao")) it.getInt("posicao") else null) }
                .filter { it.id !in listadas }
            if (achados.isNotEmpty()) {
                item { TituloDeSecao(t("Mais moedas, fora da lista verificada")) }
                items(achados, key = { "b" + it.id }) { achado -> LinhaDoResultado(achado, mostrarPosicao = true) { aoTocar(achado) } }
            } else if (nadaListado) {
                item { Box(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md)) { NotaDaBusca(t("Nenhuma moeda com esse nome ou símbolo.")) } }
            }
        }
    }
}

/**
 * Tocou numa moeda da busca: as opcoes de compra pela regra de `TradeCatalog` ("receber.redesDaTroca"), o
 * `TradeCatalogLookup` do iOS. O nucleo espera a leitura de agora inteira: as linhas so aparecem com o aviso do CoinGecko e
 * o contrato atual ja lidos. A da lista verificada e a ja adicionada vao direto; a nova passa antes pelo Adicionar moeda,
 * que le nome, simbolo e casas na propria rede e mostra o contrato inteiro com o aviso de nao verificado. `excluir`: o
 * ativo do outro lado da troca. `aoEscolher` recebe a rede e o ativo.
 */
@Composable
internal fun RedesDaTroca(achado: ResultadoDaBusca, excluir: String?, aoEscolher: (String, String) -> Unit) {
    var lida by remember { mutableStateOf<JSONObject?>(null) }
    var tentativa by remember { mutableIntStateOf(0) }
    // A rede e o contrato da moeda que o Adicionar moeda esta salvando: quando ela volta pronta, com o mesmo contrato,
    // segue para a troca.
    var adicionando by remember { mutableStateOf<Pair<String, String>?>(null) }
    LaunchedEffect(tentativa) {
        lida = null
        val pedido = JSONObject().put("id", achado.id).put("simbolo", achado.simbolo).put("nome", achado.nome)
        if (excluir != null) pedido.put("excluir", excluir)
        val r = runCatching { Api.objeto("receber.redesDaTroca", pedido) }.getOrNull() ?: JSONObject()
            .put("simbolo", achado.simbolo).put("aviso", false).put("conferida", false).put("opcoes", org.json.JSONArray())
        lida = r
        val (rede, contrato) = adicionando ?: return@LaunchedEffect
        adicionando = null
        r.getJSONArray("opcoes").objetos().firstOrNull {
            val ativo = it.getJSONObject("ativo")
            it.getBoolean("pronta") && ativo.getString("rede") == rede && ativo.opcional("contrato")?.equals(contrato, ignoreCase = true) == true
        }?.let { aoEscolher(rede, it.getJSONObject("ativo").getString("id")) }
    }
    TelaComBarra(aoVoltar = { Navegacao.fechar() }, fundo = Paleta.corpo) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(horizontal = Espaco.margem).padding(top = Espaco.xs, bottom = Espaco.lg)) {
            val r = lida
            if (r == null) {
                Column(Modifier.fillMaxWidth().padding(top = Espaco.xl), horizontalAlignment = Alignment.CenterHorizontally) {
                    Girando(Paleta.tintaSuave)
                    Text(t("Buscando as redes de %@", achado.simbolo), style = estilo(Tipo.nota), color = Paleta.tintaSuave, textAlign = TextAlign.Center,
                         modifier = Modifier.padding(top = Espaco.md))
                }
                return@TelaComBarra
            }
            val simbolo = r.getString("simbolo")
            val opcoes = r.getJSONArray("opcoes").objetos()
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                LogoDaMoeda(achado.id.takeUnless { it.startsWith("paprika:") }, simbolo, 32.dp, anel = Paleta.corpo)
                Text(t("Comprar %@", simbolo), style = estilo(Tipo.titulo), color = Paleta.tinta)
            }
            if (r.getBoolean("aviso")) {
                // O texto do aviso e de quem escreveu, com link: a tela so diz que existe.
                Text(t("O CoinGecko publicou um aviso sobre %@ (ataque, migração ou golpe). Confira as notícias da moeda antes de comprar.", simbolo),
                     style = estilo(Tipo.nota), color = Paleta.cautela, modifier = Modifier.padding(top = Espaco.sm))
            }
            if (achado.id.startsWith("paprika:")) {
                // Achada so no CoinPaprika: tentar de novo nao muda nada.
                Text(t("Esta moeda não está no CoinGecko. Fora da lista verificada, a troca só compra o contrato que o CoinGecko confirma."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                     modifier = Modifier.padding(top = Espaco.sm))
            } else if (!r.getBoolean("conferida")) {
                // Sem a leitura de agora confirmada pelo CoinGecko, nada de fora da lista: o contrato espera por ela.
                Text(t("O CoinGecko não respondeu agora. Aparecem só as moedas verificadas."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                     modifier = Modifier.padding(top = Espaco.sm))
                BotaoTerciario(t("Tentar de novo")) { tentativa++ }
            } else if (opcoes.isEmpty()) {
                Text(t("A troca ainda não compra %@ nas redes desta carteira.", simbolo),
                     style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
            }
            if (opcoes.isNotEmpty()) {
                if (opcoes.any { !it.getBoolean("pronta") }) {
                    Text(t("Escolha a rede. Fora da lista verificada, a moeda entra pelo contrato que o CoinGecko ou o CoinPaprika listam: antes da troca, a carteira lê nome, símbolo e casas na própria rede e mostra o contrato inteiro."),
                         style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
                }
                Column(Modifier.padding(top = Espaco.md)) {
                    for (opcao in opcoes) {
                        val ativo = AtivoRecebivel.de(opcao.getJSONObject("ativo"))
                        val pronta = opcao.getBoolean("pronta")
                        val detalhe = when {
                            ativo.nativo -> ativo.simbolo
                            opcao.getBoolean("verificada") -> ativo.padrao
                            else -> t("%@ · não verificado", ativo.padrao)
                        }
                        LinhaDeRede(ativo, ativo.redeNome, detalhe) {
                            if (pronta) {
                                aoEscolher(ativo.rede, ativo.id)
                                return@LinhaDeRede
                            }
                            val contrato = ativo.contrato ?: return@LinhaDeRede
                            adicionando = ativo.rede to contrato
                            Navegacao.folha { AdicionarMoedaCustom(inicial = contrato, rede = ativo.rede) { Navegacao.fechar(); tentativa++ } }
                        }
                    }
                }
            }
        }
    }
}
