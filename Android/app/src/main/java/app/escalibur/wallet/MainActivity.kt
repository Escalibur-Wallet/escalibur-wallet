package app.escalibur.wallet

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import app.escalibur.wallet.nucleo.Cofre
import app.escalibur.wallet.nucleo.Nucleo
import app.escalibur.wallet.ui.Ciclo
import app.escalibur.wallet.ui.Raiz
import app.escalibur.wallet.ui.SemAprendizado
import app.escalibur.wallet.ui.Textos
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.tema.TemaEscalibur
import app.escalibur.wallet.vigias.Vigia
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private var primeiraVinda = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Nenhuma tela do app aparece em captura, gravacao ou na lista de apps recentes. So o build
        // de depuracao, pedido de fora (adb, `--ez capturas true`), deixa capturar: para conferir as
        // telas no emulador.
        val capturas = BuildConfig.DEBUG && intent.getBooleanExtra("capturas", false)
        if (!capturas) window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        // Nenhuma janela de outro app por cima desta (o golpe da sobreposicao).
        window.setHideOverlayWindows(true)
        Textos.carregar(this)
        Vigia.receber(intent)
        // O app e escuro sempre: a barra de status e a de navegacao com icones claros, mesmo com o
        // aparelho no tema claro (o padrao seguia o tema do sistema e os icones sumiam no fundo).
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        setContent { TemaEscalibur { SemAprendizado { Raiz() } } }
        if (BuildConfig.DEBUG) {
            testeDeDepuracao()
            // Uma tela aberta direto depois de destrancar (adb, `--es tela enviar-eth`), para conferir
            // as etapas no emulador com a carteira de teste, que nao tem saldo.
            Navegacao.telaDeDepuracao = intent.getStringExtra("tela")
        }
    }

    /** O toque numa notificacao com o app ja aberto. */
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        Vigia.receber(intent)
    }

    override fun onStart() {
        super.onStart()
        if (primeiraVinda) {
            primeiraVinda = false
        } else {
            lifecycleScope.launch { Ciclo.voltou() }
        }
    }

    override fun onResume() {
        super.onResume()
        Cofre.primeiroPlano(this)
    }

    override fun onPause() {
        Cofre.primeiroPlano(null)
        super.onPause()
    }

    override fun onStop() {
        lifecycleScope.launch { Ciclo.foiParaSegundoPlano() }
        super.onStop()
    }

    /**
     * So no build de depuracao, e so pedido de fora (adb, `--es teste tls|cofre`): as conferencias
     * da rede e do cofre no aparelho, no logcat. A do cofre apaga o cofre: so no emulador.
     */
    private fun testeDeDepuracao() {
        val teste = intent.getStringExtra("teste") ?: return
        lifecycleScope.launch {
            val resultado = withContext(Dispatchers.IO) {
                when (teste) {
                    "tls" -> Nucleo.chamar("tls.teste", "{}")
                    "cofre" -> Nucleo.chamar(
                        "cofre.teste",
                        """{"biometria":${intent.getBooleanExtra("biometria", false)},"etapa":"${intent.getStringExtra("etapa") ?: "completo"}"}""",
                    )
                    else -> "teste desconhecido"
                }
            }
            android.util.Log.i("Escalibur", "$teste: $resultado")
        }
    }
}
