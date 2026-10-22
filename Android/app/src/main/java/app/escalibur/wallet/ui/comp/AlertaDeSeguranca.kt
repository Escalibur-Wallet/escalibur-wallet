package app.escalibur.wallet.ui.comp

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import app.escalibur.wallet.ui.textos
import org.json.JSONObject

/**
 * O alerta de seguranca por cima de todo o app (o UpdateAlarmView do iOS): o que aconteceu, que
 * os fundos continuam protegidos e o que fazer. Sem botao para fechar.
 */
@Composable
fun AlertaDeSeguranca(a: JSONObject) {
    BackHandler {}
    Column(Modifier.fillMaxSize().background(Paleta.vazio).seguraToques().statusBarsPadding().navigationBarsPadding()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.lg)) {
            EmblemaCifrado(96.dp, Icones.escudoAlertaCheio, Paleta.baixa, Modifier.padding(top = Espaco.xl).align(Alignment.CenterHorizontally))
            Text(t("Alerta de segurança"), style = estilo(Tipo.nota), fontWeight = FontWeight.SemiBold, color = Paleta.tinta, textAlign = TextAlign.Center,
                 modifier = Modifier.fillMaxWidth().padding(top = Espaco.lg))
            Text(a.optString("titulo"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                 modifier = Modifier.fillMaxWidth().padding(top = Espaco.xs))
            Text(a.optString("mensagem"), style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.base))
            Row(
                Modifier.padding(top = Espaco.lg).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(Espaco.md),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.md),
            ) {
                // Os pixels que cifram: o que esta cifrado continua cifrado.
                EmblemaCifrado(76.dp, Icones.cadeadoCheio, Paleta.sucesso)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Espaco.xxs)) {
                    Text(a.optString("seguroTitulo"), style = estilo(Tipo.linha), color = Paleta.tinta)
                    Text(a.optString("seguroTexto"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                }
            }
            Text(t("O que fazer agora"), style = estilo(Tipo.cabecalho), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
            val passos = a.optJSONArray("passos").textos()
            Column(Modifier.padding(top = Espaco.md), verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
                passos.forEachIndexed { indice, passo ->
                    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                        if (passos.size > 1) {
                            Box(Modifier.padding(top = 1.dp).size(24.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                                Text("${indice + 1}", style = estilo(Tipo.nota), fontWeight = FontWeight.SemiBold, color = Paleta.tinta)
                            }
                        }
                        Text(passo, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
        Column(Modifier.padding(horizontal = Espaco.margem).padding(bottom = Espaco.md), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            Row(Modifier.fillMaxWidth().height(64.dp).clip(CircleShape).background(Paleta.trilho),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                Icone(Icones.cadeadoCheio, Paleta.tintaSuave, tamanho = 15.dp)
                Text(a.optString("rodape"), style = estilo(Tipo.acao), color = Paleta.tintaSuave, modifier = Modifier.padding(start = Espaco.xs))
            }
            Text(a.optString("nota"), style = estilo(Tipo.nota), color = Paleta.tintaApagada, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
    }
}
