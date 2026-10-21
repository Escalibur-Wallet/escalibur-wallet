package app.escalibur.wallet.ui.ajustes

import app.escalibur.wallet.ui.comp.Interruptor
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo

/** Um grupo de linhas de ajuste num cartao (o SettingsGroup do iOS). */
@Composable
fun GrupoDeAjustes(modifier: Modifier = Modifier, conteudo: @Composable ColumnScope.() -> Unit) {
    val forma = RoundedCornerShape(Raio.cartao)
    Column(
        modifier.padding(horizontal = Espaco.margem).fillMaxWidth().clip(forma).background(Paleta.corpo).border(1.dp, Paleta.borda, forma),
        content = conteudo,
    )
}

/** Um grupo com o titulo em cima. */
@Composable
fun SecaoDeAjustes(titulo: String, conteudo: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Text(titulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(horizontal = Espaco.margem))
        GrupoDeAjustes(conteudo = conteudo)
    }
}

@Composable
fun LinhaDeAjuste(
    icone: ImageVector?, titulo: String, valor: String? = null, corDoValor: Color = Paleta.tintaSuave, seta: Boolean = true,
    corDoTitulo: Color = Paleta.tinta, acao: (() -> Unit)? = null,
) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).then(if (acao != null) Modifier.clickable(onClick = acao) else Modifier)
            .padding(horizontal = Espaco.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        if (icone != null) Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) { Icone(icone, Paleta.tintaSuave, tamanho = 21.dp) }
        Text(titulo, style = estilo(Tipo.corpo), color = corDoTitulo, modifier = Modifier.weight(1f))
        if (valor != null) Text(valor, style = estilo(Tipo.nota), color = corDoValor)
        if (seta) Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 13.dp)
    }
}

/** Uma linha com o interruptor, no verde de ligado do iOS. */
@Composable
fun LinhaComInterruptor(
    icone: ImageVector?, titulo: String, ligado: Boolean, detalhe: String? = null, habilitado: Boolean = true,
    inicio: (@Composable RowScope.() -> Unit)? = null, cor: Color = Paleta.sucesso, aoMudar: (Boolean) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).padding(horizontal = Espaco.md, vertical = Espaco.xs),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        if (inicio != null) inicio() else if (icone != null) Icone(icone, Paleta.tintaSuave, tamanho = 18.dp, modifier = Modifier.width(28.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = estilo(Tipo.corpo), color = if (habilitado) Paleta.tinta else Paleta.tintaApagada)
            if (detalhe != null) Text(detalhe, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
        Interruptor(ligado, aoMudar, cor = cor, habilitado = habilitado)
    }
}

/** Uma linha de escolha, com o visto na escolhida. */
@Composable
fun LinhaDeEscolha(titulo: String, escolhida: Boolean, acao: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).clickable(onClick = acao).padding(horizontal = Espaco.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(titulo, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
        if (escolhida) Icone(Icones.visto, Paleta.tinta, tamanho = 16.dp)
    }
}

/** A nota embaixo de um grupo. */
@Composable
fun NotaDeAjuste(texto: String, cor: Color = Paleta.tintaApagada, modifier: Modifier = Modifier) {
    Text(texto, style = estilo(Tipo.nota), color = cor, modifier = modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xs))
}

/** Uma subtela dos Ajustes, na pilha: o titulo no centro e voltar no canto. */
@Composable
fun Subtela(titulo: String, conteudo: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding()) {
        CabecalhoDeFolha(titulo, null, aoVoltar = { Navegacao.fechar() })
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = Espaco.xl), content = conteudo)
    }
}
