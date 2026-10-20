package app.escalibur.wallet.ui.comp

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo

/**
 * A confirmacao no centro da tela, para o que nao tem volta (apagar, sair sem a copia). O botao que
 * destroi fica em vermelho e embaixo; o de voltar, primeiro.
 */
@Composable
fun Confirmacao(
    titulo: String, mensagem: String, tituloDaAcao: String, aoConfirmar: () -> Unit, aoCancelar: () -> Unit,
    tituloDoCancelar: String = app.escalibur.wallet.ui.t("Cancelar"), destrutiva: Boolean = true,
) {
    AlertDialog(
        onDismissRequest = aoCancelar,
        containerColor = Paleta.corpo,
        shape = RoundedCornerShape(Raio.folha),
        title = { Text(titulo, style = estilo(Tipo.cabecalho), color = Paleta.tinta) },
        text = { Text(mensagem, style = estilo(Tipo.corpo), color = Paleta.tintaSuave) },
        confirmButton = {
            Column(Modifier.fillMaxWidth().padding(top = Espaco.xs), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                BotaoSecundario(tituloDoCancelar, acao = aoCancelar)
                if (destrutiva) BotaoDestrutivo(tituloDaAcao, acao = aoConfirmar) else BotaoPrimario(tituloDaAcao, acao = aoConfirmar)
            }
        },
    )
}
