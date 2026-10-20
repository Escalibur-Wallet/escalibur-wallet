package app.escalibur.wallet.ui.importar

import androidx.compose.runtime.Composable
import app.escalibur.wallet.ui.TelaProvisoria
import app.escalibur.wallet.ui.t

@Composable
fun FluxoDeImportar(aoCancelar: () -> Unit, @Suppress("UNUSED_PARAMETER") aoTerminar: () -> Unit) = TelaProvisoria(t("Importar"), aoCancelar)

@Composable
fun ObservarEndereco(aoCancelar: () -> Unit, @Suppress("UNUSED_PARAMETER") aoTerminar: () -> Unit) = TelaProvisoria(t("Só observar um endereço"), aoCancelar)
