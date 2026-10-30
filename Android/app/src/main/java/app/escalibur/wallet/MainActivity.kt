package app.escalibur.wallet

import android.os.Build
import android.os.Bundle
import android.view.View
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
import app.escalibur.wallet.ui.comp.TecladoSeguro
import app.escalibur.wallet.ui.Textos
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.tema.TemaEscalibur
import app.escalibur.wallet.vigias.Vigia
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private companion object {
        /** A primeira vinda do processo, nao da Activity: uma Activity recriada (tema, fonte ou
         * idioma do sistema) passa pelo bloqueio automatico como qualquer volta. */
        var primeiraVindaDoProcesso = true
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Nenhuma tela do app aparece em captura, gravacao ou na lista de apps recentes. So o build
        // de depuracao, pedido de fora (adb, `--ez capturas true`), deixa capturar: para conferir as
        // telas no emulador.
        val capturas = BuildConfig.DEBUG && intent.getBooleanExtra("capturas", false)
        if (!capturas) window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        // Nenhuma janela de outro app por cima desta (o golpe da sobreposicao). No Android 11 a
        // janela nao some: o toque que chega com outra janela por cima e recusado.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) window.setHideOverlayWindows(true)
        window.decorView.filterTouchesWhenObscured = true
        // Servico de acessibilidade que nao e ferramenta de acessibilidade (o TalkBack e) nao le
        // nada do app: nem as palavras, nem as teclas do PIN e do Safe Keyboard. E o golpe mais
        // comum no Android. Antes do Android 14, a checagem do aparelho avisa.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            window.decorView.setAccessibilityDataSensitive(View.ACCESSIBILITY_DATA_SENSITIVE_YES)
        }
        // Nenhum gerenciador de senhas oferece guardar a passphrase ou a senha do envelope.
        window.decorView.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        Textos.carregar(this)
        Vigia.receber(this, intent)
        // O app e escuro sempre: a barra de status e a de navegacao com icones claros, mesmo com o
        // aparelho no tema claro (o padrao seguia o tema do sistema e os icones sumiam no fundo).
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        setContent { TemaEscalibur { TecladoSeguro.Raiz { Raiz() } } }
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
        if (BuildConfig.DEBUG) intent.getStringExtra("tela")?.let { Navegacao.telaDeDepuracao = it }
        Vigia.receber(this, intent)
    }

    override fun onStart() {
        super.onStart()
        if (primeiraVindaDoProcesso) {
            primeiraVindaDoProcesso = false
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

    override fun onWindowFocusChanged(temFoco: Boolean) {
        super.onWindowFocusChanged(temFoco)
        // Com o foco o Android deixa ler a area de transferencia: a copia do app que venceu enquanto ele
        // estava em segundo plano e apagada agora.
        if (temFoco) app.escalibur.wallet.ui.comp.Transferencia.apagarSeVenceu(this, comFoco = true)
    }

    override fun onStop() {
        Ciclo.foiParaSegundoPlano()
        super.onStop()
    }

    /**
     * So no build de depuracao, e so pedido de fora (adb, `--es teste tls|cofre|segredo`): as
     * conferencias da rede, do cofre e do campo de segredo no aparelho, no logcat. A do cofre apaga o
     * cofre: so no emulador.
     */
    private fun testeDeDepuracao() {
        val teste = intent.getStringExtra("teste") ?: return
        if (teste == "segredo") {
            android.util.Log.i("Escalibur", "segredo: " + app.escalibur.wallet.ui.comp.provaDoSegredo(window.decorView))
            return
        }
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
