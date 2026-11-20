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
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
 * app fica escondido de quem nao se declara ferramenta de acessibilidade (`setAccessibilityDataSensitive`),
 * mas so da leitura: esse servico ainda desenha uma janela por cima da carteira, que o
 * `setHideOverlayWindows` nao esconde e o `filterTouchesWhenObscured` nao ve, e o toque do dono passa
 * por baixo dela (pentest de 17/11/2026, provado no Android 16).
 *
 * Por isso todo servico que nao veio com o celular fecha a carteira, em qualquer Android, se declare
 * ferramenta ou nao. Como nos apps de banco, ela fica fechada enquanto ele estiver ligado, e nada dela e
 * montado por baixo (cobrir so com uma camada deixaria o servico ler a tela de baixo). Sem botao de seguir
 * mesmo assim: o proprio servico tocaria nele. Leitor de tela do sistema (o TalkBack que vem com o
 * celular) nao fecha nada.
 *
 * O que fechar tira e o que depende da carteira de verdade por baixo da janela: o toque que passava para o
 * PIN embaralhado, o aviso coberto, o PIN errado ate a espera e, no 14 e no 15, o toque as cegas nos botoes.
 * O que nenhum app tira: uma tela falsa inteira, desenhada pelo servico por cima de qualquer coisa, ate desta
 * tela fechada. Por isso o texto dela diz o que o servico pode fazer, e ao fechar a sessao trava e o pedido de
 * biometria que estiver na tela cai (`Raiz`).
 */
object Acessibilidade {
    var suspeitos by mutableStateOf<List<String>>(emptyList())
        private set

    /**
     * Para digitar segredo (as palavras, a passphrase, a senha do envelope), todo servico que nao veio com
     * o celular, ferramenta ou nao, e em qualquer Android (segunda passada da auditoria de 03/11/2026): no 14
     * em diante quem nao se diz ferramenta nao le a tela, mas ainda pode por uma camada transparente por
     * cima e ver onde o dono toca. No teclado de letras em posicao fixa, a posicao e a letra. Desde o pentest
     * de 17/11/2026 e a mesma lista que fecha a carteira inteira (`suspeitos`); o teclado desses campos fecha
     * por ela tambem (`TecladoFechadoPelaAcessibilidade`), como segunda barreira, e o `verificar.sh` confere as duas.
     */
    var suspeitosParaSegredo by mutableStateOf<List<String>>(emptyList())
        private set

    /**
     * Algum dos suspeitos le a tela do app: ate o Android 13, todos; do 14 em diante, quem se declara ferramenta
     * (os outros o `setAccessibilityDataSensitive` deixa sem a leitura). O ligado que o sistema nao descreve conta
     * como quem le. So escolhe o texto da tela fechada: quem nao le fecha a carteira do mesmo jeito.
     */
    var leemATela by mutableStateOf(false)
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
        val (todos, leem) = suspeitosAgora(contexto, gerente)
        suspeitos = todos
        suspeitosParaSegredo = todos
        leemATela = leem
    }

    /** Os que fecham a carteira e o teclado de segredo (todo ligado que nao veio com o celular), e se algum deles le a tela do app. */
    private fun suspeitosAgora(contexto: Context, gerente: AccessibilityManager): Pair<List<String>, Boolean> {
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
        // O rotulo e escolhido por quem fez o servico ("Sistema Android", "Google Play Protect"): vai com o pacote, cortado e
        // sem caractere de controle ou de formato, para o dono achar qual desligar (revisao dos 3 agentes, 17/11/2026).
        fun nome(info: AccessibilityServiceInfo): String {
            val pacote = info.resolveInfo?.serviceInfo?.packageName
            val rotulo = runCatching { info.resolveInfo.loadLabel(contexto.packageManager).toString() }.getOrNull()
                ?.filter { !it.isISOControl() && Character.getType(it) !in ROTULO_SEM }?.trim()?.take(40)?.trimEnd { it.isHighSurrogate() }
            return when {
                rotulo.isNullOrEmpty() -> pacote ?: info.id
                pacote == null || rotulo == pacote -> rotulo
                else -> "$rotulo ($pacote)"
            }
        }
        val deFora = ligados.values.filter { info -> !doSistema(info) }
        // A versao do Android e o "sou ferramenta" so dizem quem le a tela, para o texto. Fechar a carteira nao depende deles.
        val leem = desconhecidos.isNotEmpty() ||
            deFora.any { info -> Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE || info.isAccessibilityTool }
        return (deFora.map(::nome) + desconhecidos).distinct() to leem
    }

    /** Fora do rotulo mostrado: o que muda a direcao do texto ou quebra a linha (o rotulo e de quem fez o servico). */
    private val ROTULO_SEM = setOf(Character.FORMAT.toInt(), Character.LINE_SEPARATOR.toInt(), Character.PARAGRAPH_SEPARATOR.toInt())

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
 * (`suspeitosParaSegredo`): ele ve onde o dono toca. Segunda barreira desde 17/11/2026: a carteira inteira fecha pela
 * mesma lista (`Raiz`), e isto aparece no maximo ate o campo sair da tela.
 */
@Composable
fun TecladoFechadoPelaAcessibilidade(suspeitos: List<String>, modifier: Modifier = Modifier) {
    val contexto = LocalContext.current
    Column(modifier.fillMaxWidth().background(Paleta.corpo).navigationBarsPadding().padding(Espaco.margem),
           horizontalAlignment = Alignment.CenterHorizontally) {
        Text(t("%@ tem acesso de acessibilidade e pode ver onde você toca. Para digitar palavras e senhas, desligue ele.", suspeitos.joinToString(", ")),
             style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
        app.escalibur.wallet.ui.comp.BotaoSecundario(t("Abrir as configurações de acessibilidade"), Modifier.padding(top = Espaco.md)) {
            runCatching { contexto.startActivity(android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
        }
    }
}

/**
 * A carteira fechada enquanto um app de fora tem acesso de acessibilidade. `leem`: algum deles le a tela do app; senao
 * (Android 14 em diante, sem se declarar ferramenta), o risco que sobra e a janela por cima, e o texto diz isso.
 */
@Composable
fun TelaDeAcessibilidade(suspeitos: List<String>, leem: Boolean) {
    val contexto = LocalContext.current
    // No centro quando cabe. Quando nao cabe (celular pequeno, letra grande, idioma longo) rola, para o botao nunca ficar fora da tela.
    BoxWithConstraints(Modifier.fillMaxSize().background(Paleta.vazio).systemBarsPadding()) {
        Column(
            Modifier.fillMaxWidth().heightIn(min = maxHeight).verticalScroll(rememberScrollState())
                .padding(horizontal = Espaco.margem, vertical = Espaco.md),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
        ) {
            app.escalibur.wallet.ui.comp.EmblemaCifrado(72.dp)
            Text(if (leem) t("Desligue o app que lê a tela") else t("Desligue o app que pode cobrir a tela"),
                 style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.lg))
            Text(if (leem) t("%@ tem acesso de acessibilidade: lê tudo o que aparece no celular, inclusive o PIN e as palavras, e toca na tela no seu lugar. É o golpe mais usado contra carteiras no Android. A Escalibur fica fechada enquanto ele estiver ligado.", suspeitos.joinToString(", "))
                 else t("%@ tem acesso de acessibilidade: pode desenhar por cima da Escalibur e mostrar uma tela falsa no lugar da verdadeira. É o golpe mais usado contra carteiras no Android, e por isso a Escalibur fica fechada com qualquer app assim ligado, mesmo um de confiança.", suspeitos.joinToString(", ")),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm))
            // Muito mais gente passa por esta tela desde 17/11/2026 (gerenciador de senhas, antivirus, automacao): quem acha que o
            // app quebrou e desinstala perde as carteiras deste celular. A tela diz que elas estao guardadas e o que nao fazer. E diz
            // o que torna "seguros" verdade: com o acesso ligado nada da Escalibur pede segredo (o `Raiz` devolve antes do bloqueio, das
            // folhas de PIN e de passphrase, e o portao derruba a biometria), entao a tela da Escalibur que pedir e a falsa, desenhada
            // pelo servico. "Da Escalibur": a tela de bloqueio do proprio celular segue pedindo o PIN dele, e e verdadeira.
            Text(t("Seus fundos estão seguros: as carteiras continuam guardadas neste celular e voltam quando esse acesso for desligado. Enquanto ele estiver ligado, a Escalibur não pede PIN, senha, passphrase nem palavras: se uma tela da Escalibur pedir, é falsa. Não desinstale a Escalibur nem apague os dados dela, porque isso apaga as carteiras deste celular."),
                 style = estilo(Tipo.corpo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.md))
            app.escalibur.wallet.ui.comp.BotaoPrimario(t("Abrir as configurações de acessibilidade"), Modifier.padding(top = Espaco.lg)) {
                runCatching { contexto.startActivity(android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
            }
            Text(t("O leitor de tela que vem com o celular, como o TalkBack, não fecha a carteira."),
                 style = estilo(Tipo.nota), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.md))
        }
    }
}
