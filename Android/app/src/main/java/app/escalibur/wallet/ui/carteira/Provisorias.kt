package app.escalibur.wallet.ui.carteira

import androidx.compose.runtime.Composable
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.TelaProvisoria
import app.escalibur.wallet.ui.t

@Composable
fun SeletorDeCarteiras(aoFechar: () -> Unit) = TelaProvisoria(t("Carteiras"), aoFechar)

@Composable
fun CopiaAgora(@Suppress("UNUSED_PARAMETER") carteira: Carteira) = TelaProvisoria(t("Gravar agora"))

@Composable
fun DetalheDoAtivo(id: String) = TelaProvisoria(id)
