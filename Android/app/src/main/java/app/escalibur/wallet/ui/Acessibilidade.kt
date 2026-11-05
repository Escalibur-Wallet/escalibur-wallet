package app.escalibur.wallet.ui

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.pm.ApplicationInfo
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo

/**
 * Servico de acessibilidade que nao veio com o celular (auditoria de 31/10/2026): ele le tudo o que a
 * tela mostra, o PIN, as palavras e a passphrase, e toca na tela no lugar do dono. E o golpe mais
 * comum dos virus de banco no Android. Ate o Android 13 nada esconde o app dele. Do 14 em diante o
 * app ja fica escondido de quem nao se declara ferramenta de acessibilidade (`setAccessibilityDataSensitive`),
 * e so quem se declara e nao veio com o celular fica de fora.
 *
 * Como nos apps de banco, a carteira fica fechada enquanto ele estiver ligado, e nada dela e montado
 * por baixo (cobrir so com uma camada deixaria o servico ler a tela de baixo). Sem botao de seguir
 * mesmo assim: o proprio servico tocaria nele. Leitor de tela do sistema (o TalkBack que vem com o
 * celular) nao fecha nada.
 */
object Acessibilidade {
    var suspeitos by mutableStateOf<List<String>>(emptyList())
        private set

    /**
     * Para digitar segredo (as palavras, a passphrase, a senha do envelope), todo servico que nao veio com
     * o celular, ferramenta ou nao, e em qualquer Android (segunda passada da auditoria de 03/11/2026): no 14
     * em diante quem nao se diz ferramenta nao le a tela, mas ainda pode por uma camada transparente por
     * cima e ver onde o dono toca. No teclado de letras em posicao fixa, a posicao e a letra. O resto da
     * carteira segue aberto; so o teclado desses campos fecha (`TecladoFechadoPelaAcessibilidade`).
     */
    var suspeitosParaSegredo by mutableStateOf<List<String>>(emptyList())
        private set

    private var ouvindo = false

    /** Na criacao e a cada volta para a frente, antes de qualquer tela; e quando o Android avisa que mudou. */
    fun conferir(contexto: Context) {
        val gerente = contexto.getSystemService(AccessibilityManager::class.java) ?: return
        atualizar(contexto.applicationContext, gerente)
        if (!ouvindo) {
            ouvindo = true
            val app = contexto.applicationContext
            gerente.addAccessibilityStateChangeListener { atualizar(app, gerente) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gerente.addAccessibilityServicesStateChangeListener { atualizar(app, gerente) }
            }
            // A lista que o sistema guarda, que muda tambem quando um servico liga com o app aberto
            // (tela dividida, atalho), sem aviso do AccessibilityManager no Android 11 e 12.
            app.contentResolver.registerContentObserver(
                Settings.Secure.getUriFor(Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES), false,
                object : ContentObserver(Handler(Looper.getMainLooper())) {
                    override fun onChange(selfChange: Boolean) { atualizar(app, gerente) }
                },
            )
        }
    }

    /**
     * Os ligados pelas duas fontes: a do AccessibilityManager e a lista que o sistema guarda em
     * `ENABLED_ACCESSIBILITY_SERVICES`. No Android 11 a 13 sem a atualizacao de dezembro de 2022
     * (CVE-2022-20495), um servico que nao declara o tipo de retorno some da primeira; da segunda
     * nao some (revisao de seguranca de 01/11/2026). Um ligado que o sistema nao descreve (fora da
     * lista dos instalados) conta como suspeito: nao da para provar que veio com o celular.
     */
    private fun atualizar(contexto: Context, gerente: AccessibilityManager) {
        val (todos, segredo) = suspeitosAgora(contexto, gerente)
        suspeitos = todos
        suspeitosParaSegredo = segredo
    }

    /** Os que fecham a carteira e os que fecham o teclado de segredo. */
    private fun suspeitosAgora(contexto: Context, gerente: AccessibilityManager): Pair<List<String>, List<String>> {
        val instalados = gerente.installedAccessibilityServiceList.associateBy { componente(it) }
        val ligados = gerente.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK).associateBy { componente(it) }.toMutableMap()
        val guardados = Settings.Secure.getString(contexto.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()
        val acessibilidadeLigada = Settings.Secure.getInt(contexto.contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0) == 1
        val desconhecidos = mutableListOf<String>()
        if (acessibilidadeLigada) {
            for (texto in guardados.split(':').map { it.trim() }.filter { it.isNotEmpty() }) {
                val nome = ComponentName.unflattenFromString(texto) ?: continue
                if (nome in ligados) continue
                val info = instalados[nome]
                if (info != null) ligados[nome] = info else desconhecidos.add(nome.packageName)
            }
        }
        fun nome(info: AccessibilityServiceInfo) = runCatching { info.resolveInfo.loadLabel(contexto.packageManager).toString() }.getOrNull() ?: info.id
        val deFora = ligados.values.filter { info -> !doSistema(info) }
        val suspeitos = deFora.filter { info -> Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE || info.isAccessibilityTool }.map(::nome)
        return (suspeitos + desconhecidos).distinct() to (deFora.map(::nome) + desconhecidos).distinct()
    }

    private fun componente(info: AccessibilityServiceInfo): ComponentName? =
        info.resolveInfo?.serviceInfo?.let { ComponentName(it.packageName, it.name) }

    /** Veio com o celular (tambem quando atualizado pela loja): so quem tem a chave do fabricante instala assim. */
    private fun doSistema(info: AccessibilityServiceInfo): Boolean {
        val app = info.resolveInfo?.serviceInfo?.applicationInfo ?: return false
        return app.flags and ApplicationInfo.FLAG_SYSTEM != 0
    }
}

/**
 * No lugar do teclado de um campo de segredo, enquanto um servico de acessibilidade de fora estiver ligado
 * (`suspeitosParaSegredo`): ele ve onde o dono toca. O resto da carteira segue aberto.
 */
@Composable
fun TecladoFechadoPelaAcessibilidade(suspeitos: List<String>, modifier: Modifier = Modifier) {
    val contexto = LocalContext.current
    Column(modifier.fillMaxWidth().background(Paleta.corpo).navigationBarsPadding().padding(Espaco.margem),
           horizontalAlignment = Alignment.CenterHorizontally) {
        Text(t("%@ tem acesso de acessibilidade e pode ver onde você toca. Para digitar palavras e senhas, desligue ele: o resto da carteira continua aberto.", suspeitos.joinToString(", ")),
             style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
        app.escalibur.wallet.ui.comp.BotaoSecundario(t("Abrir as configurações de acessibilidade"), Modifier.padding(top = Espaco.md)) {
            runCatching { contexto.startActivity(android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
        }
    }
}

/** A carteira fechada enquanto um app de fora le a tela. */
@Composable
fun TelaDeAcessibilidade(suspeitos: List<String>) {
    val contexto = LocalContext.current
    Column(
        Modifier.fillMaxSize().background(Paleta.vazio).systemBarsPadding().padding(horizontal = Espaco.margem),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        app.escalibur.wallet.ui.comp.EmblemaCifrado(72.dp)
        Text(t("Desligue o app que lê a tela"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
             modifier = Modifier.padding(top = Espaco.lg))
        Text(t("%@ tem acesso de acessibilidade: lê tudo o que aparece no celular, inclusive o PIN e as palavras, e toca na tela no seu lugar. É o golpe mais usado contra carteiras no Android. A Escalibur fica fechada enquanto ele estiver ligado.", suspeitos.joinToString(", ")),
             style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm))
        app.escalibur.wallet.ui.comp.BotaoPrimario(t("Abrir as configurações de acessibilidade"), Modifier.padding(top = Espaco.lg)) {
            runCatching { contexto.startActivity(android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
        }
        Text(t("O leitor de tela que vem com o celular, como o TalkBack, não fecha a carteira."),
             style = estilo(Tipo.nota), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.md))
    }
}
