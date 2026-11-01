package app.escalibur.wallet.ui

// Provisorio: as telas que ainda vao ser portadas do iOS. Cada uma sai daqui quando a de verdade
// entra no pacote dela.

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo

@Composable
fun TelaProvisoria(titulo: String, aoFechar: (() -> Unit)? = { Navegacao.fechar() }) {
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding()) {
        CabecalhoDeFolha(titulo, aoFechar)
        Text(titulo, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(Espaco.margem))
    }
}
