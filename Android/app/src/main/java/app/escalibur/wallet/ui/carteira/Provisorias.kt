package app.escalibur.wallet.ui.carteira

import androidx.compose.runtime.Composable
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.TelaProvisoria
import app.escalibur.wallet.ui.t

/** O "Gravar agora": a copia que faltou, pelas palavras ou so pela passphrase. */
@Composable
fun CopiaAgora(carteira: Carteira) = FluxoDeRevelar(carteira, copia = true) { app.escalibur.wallet.ui.principal.Navegacao.fechar() }

@Composable
fun DetalheDoAtivo(id: String) = TelaProvisoria(id)
