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
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.Raiz
import app.escalibur.wallet.ui.comp.TecladoSeguro
import app.escalibur.wallet.ui.envelope.EnvelopeCompartilhado
import app.escalibur.wallet.ui.envelope.EnvelopeRecebido
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
        app.escalibur.wallet.nucleo.Cofre.aquecerStrongBox()
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
        // comum no Android.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            window.decorView.setAccessibilityDataSensitive(View.ACCESSIBILITY_DATA_SENSITIVE_YES)
        }
        // Antes do Android 14, e do 14 em diante com quem se diz ferramenta sem ter vindo com o celular:
        // a carteira fica fechada enquanto o servico estiver ligado (ver `Acessibilidade`).
        app.escalibur.wallet.ui.Acessibilidade.conferir(this)
        // Nenhum gerenciador de senhas oferece guardar a passphrase ou a senha do envelope.
        window.decorView.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        Textos.carregar(this)
        Vigia.receber(this, intent)
        // So na primeira criacao: recriada (tema, idioma), a Activity recebe o mesmo pedido de novo.
        if (savedInstanceState == null) {
            EnvelopeRecebido.receber(intent, origemDoIntent())
            // A copia do envelope lacrado que foi para a folha de compartilhar, se ficou de outra vez.
            EnvelopeCompartilhado.apagar(this)
        }
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
            // A tela de versao desatualizada sem uma versao de verdade na lista (`--es versao expirada|obrigatoria|tentou`).
            intent.getStringExtra("versao")?.let { app.escalibur.wallet.ui.atualizar.Atualizacao.demonstrar(it) }
        }
    }

    /** O toque numa notificacao, ou um envelope aberto em outro app, com o app ja aberto. */
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // O `referrer` le o intent da Activity: o novo, e nao o da abertura.
        setIntent(intent)
        if (BuildConfig.DEBUG) intent.getStringExtra("tela")?.let { Navegacao.telaDeDepuracao = it }
        if (BuildConfig.DEBUG) intent.getStringExtra("versao")?.let { app.escalibur.wallet.ui.atualizar.Atualizacao.demonstrar(it) }
        Vigia.receber(this, intent)
        EnvelopeRecebido.receber(intent, origemDoIntent())
    }

    /**
     * O app que mandou o intent: a tela de senha do envelope diz de onde ele veio (auditoria Android de
     * 31/10/2026, AA-10). O `referrer` le primeiro os extras EXTRA_REFERRER e EXTRA_REFERRER_NAME, que
     * quem manda escreve como quiser ("Escalibur Suporte"): eles saem antes, e fica o que o sistema poe
     * (segunda passada da auditoria de 03/11/2026). So um nome de pacote de verdade, que o PackageManager
     * resolve, vira nome; e o pacote vai junto, porque o rotulo do app tambem e escolhido por quem o fez.
     * Sem isso, "um app que nao se identificou".
     */
    private fun origemDoIntent(): String? {
        intent?.removeExtra(android.content.Intent.EXTRA_REFERRER)
        intent?.removeExtra(android.content.Intent.EXTRA_REFERRER_NAME)
        val pacote = referrer?.takeIf { it.scheme == "android-app" }?.host ?: callingPackage
        if (pacote == packageName) return null
        val nomeDePacote = Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$")
        if (pacote == null || !nomeDePacote.matches(pacote)) return t("um app que não se identificou")
        val rotulo = runCatching { packageManager.getApplicationLabel(packageManager.getApplicationInfo(pacote, 0)).toString() }.getOrNull()
            ?: return t("um app que não se identificou")
        return if (rotulo.isBlank() || rotulo == pacote) pacote else "$rotulo ($pacote)"
    }

    override fun onStart() {
        super.onStart()
        // Antes de qualquer quadro: um servico ligado enquanto o app estava fora fecha a carteira ja.
        app.escalibur.wallet.ui.Acessibilidade.conferir(this)
        // A tela na frente: as palavras voltam a poder ser lidas, tambem na primeira vinda. O processo pode ter nascido sem
        // tela (a conferencia de hora em hora, a volta depois de reiniciar) e a tela apagada ter travado a leitura antes de
        // haver Activity (revisao final de 07/11/2026).
        app.escalibur.wallet.nucleo.PalavrasNaTela.liberar()
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
                    "rsa" -> testeDoRsa()
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

    /** So de depuracao: o embrulho do slot de biometria cifra no nucleo (RSA-OAEP da BoringSSL) e o Keystore abre com o
     * mesmo `oaep` do Cofre, numa chave de teste sem biometria, apagada no fim (auditoria das chaves de 06/11/2026). */
    private fun testeDoRsa(): String {
        val alias = "app.escalibur.wallet.teste.rsa"
        val keyStore = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return try {
            java.security.KeyPairGenerator.getInstance(android.security.keystore.KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore").run {
                initialize(android.security.keystore.KeyGenParameterSpec.Builder(alias,
                    android.security.keystore.KeyProperties.PURPOSE_DECRYPT or android.security.keystore.KeyProperties.PURPOSE_ENCRYPT)
                    .setKeySize(2048)
                    .setDigests(android.security.keystore.KeyProperties.DIGEST_SHA256)
                    .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
                    .build())
                generateKeyPair()
            }
            val publica = android.util.Base64.encodeToString(keyStore.getCertificate(alias).publicKey.encoded, android.util.Base64.NO_WRAP)
            val resposta = org.json.JSONObject(Nucleo.chamar("cofre.rsaTeste", org.json.JSONObject().put("publica", publica).toString()))
            val cifrado = android.util.Base64.decode(resposta.getString("cifrado"), android.util.Base64.NO_WRAP)
            val claro = android.util.Base64.decode(resposta.getString("claro"), android.util.Base64.NO_WRAP)
            val rsa = javax.crypto.Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
            rsa.init(javax.crypto.Cipher.DECRYPT_MODE, keyStore.getKey(alias, null) as java.security.PrivateKey,
                javax.crypto.spec.OAEPParameterSpec("SHA-256", "MGF1", java.security.spec.MGF1ParameterSpec.SHA1, javax.crypto.spec.PSource.PSpecified.DEFAULT))
            val aberto = rsa.doFinal(cifrado)
            "rsa ${cifrado.size} bytes, keystore abre: ${if (aberto.contentEquals(claro)) "igual" else "DIFERENTE"}"
        } catch (e: Exception) {
            "rsa ERRO ${e.javaClass.simpleName}: ${e.message}"
        } finally {
            runCatching { keyStore.deleteEntry(alias) }
        }
    }
}
