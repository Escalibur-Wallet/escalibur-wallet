package app.escalibur.wallet

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.nucleo.Nucleo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Nenhuma tela do app aparece em captura, gravacao ou na lista de apps recentes.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        enableEdgeToEdge()
        setContent { Prova() }
    }
}

/** A prova da ponte: o nucleo em Swift responde de dentro do APK. */
@Composable
private fun Prova() {
    var versao by remember { mutableStateOf("...") }
    var saldo by remember { mutableStateOf("...") }
    LaunchedEffect(Unit) {
        android.util.Log.i("Escalibur", "chamando o nucleo")
        val inicio = withContext(Dispatchers.IO) { Nucleo.chamar("iniciar", "{}") }
        android.util.Log.i("Escalibur", "iniciar: $inicio")
        versao = withContext(Dispatchers.IO) { Nucleo.chamar("versao", "{}") }
        android.util.Log.i("Escalibur", "versao: $versao")
        saldo = withContext(Dispatchers.IO) {
            Nucleo.chamar("saldo", """{"rede":"ethereum","enderecos":["0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"]}""")
        }
        android.util.Log.i("Escalibur", "saldo: ${saldo.take(600)}")
        if (BuildConfig.DEBUG) {
            val tls = withContext(Dispatchers.IO) { Nucleo.chamar("tls.teste", "{}") }
            android.util.Log.i("Escalibur", "tls: $tls")
        }
    }
    Column(Modifier.fillMaxSize().background(Color(0xFF0B0B0C)).padding(24.dp)) {
        Text("Escalibur Wallet", color = Color(0xFFF5F5F6), fontSize = 28.sp)
        Text("Nucleo: $versao", color = Color(0xFFA8A8AE), fontSize = 14.sp, modifier = Modifier.padding(top = 16.dp))
        Text("Saldo (vitalik.eth): ${saldo.take(400)}", color = Color(0xFFA8A8AE), fontSize = 12.sp, modifier = Modifier.padding(top = 16.dp))
    }
}
