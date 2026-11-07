package app.escalibur.wallet.ui.atualizar

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.BuildConfig
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.Ciclo
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.DeslizeParaSeguir
import app.escalibur.wallet.ui.comp.EmblemaCifrado
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.delay
import org.json.JSONObject

/**
 * A tela de versao desatualizada, o UpdateGuard do iOS (pedido do dono, 07/11/2026). A Google Play nao tem consulta publica
 * da versao mais nova: o nucleo le so a lista assinada do site e o build que o dono liberou nela, com o lancamento dele em
 * 100% na Play (docs/seguranca.md, "Versao autorizada"). Sem o alarme de hack do iPhone: sem a loja, nao da para saber se
 * ha na Play um build fora da lista. Ao voltar para a frente, no maximo a cada 6 horas; com a tela na frente, a cada minuto.
 */
object Atualizacao {
    /** A versao liberada na lista, quando a instalada esta desatualizada. */
    var versao by mutableStateOf<String?>(null)
        private set
    /** A lista obriga este build a atualizar: a tela sai sem o "Vou atualizar depois". */
    var obrigatoria by mutableStateOf(false)
        private set
    /** Tocou "Atualizar agora" e continua nesta versao (atualizar fecha o app): a obrigatoria ganha o "Usar em emergência". */
    var tentou by mutableStateOf(false)
        private set
    /** "Vou atualizar depois": a tela sai ate o app fechar. */
    private var adiada by mutableStateOf(false)
    /** "Usar em emergência" na obrigatoria: nenhuma das duas volta ate o app fechar. */
    private var emergencia by mutableStateOf(false)
    private var demonstracao = false
    private var ultima: Long? = null
    /** Sem resposta (site bloqueado ou fora do ar): a proxima tentativa so depois de 15 minutos, e nao a cada volta. */
    private var semRespostaAte: Long? = null
    private var conferindo = false
    private var carregada = false

    private const val PACOTE = "app.escalibur.wallet"
    private const val INTERVALO = 6 * 3600 * 1000L
    private const val INTERVALO_COM_TELA = 60 * 1000L
    private const val ESPERA_SEM_RESPOSTA = 15 * 60 * 1000L
    private const val VALIDADE_DA_TENTATIVA = 24 * 3600 * 1000L

    val naTela: Boolean get() = versao != null && if (obrigatoria) !emergencia else !adiada

    /** A obrigatoria na frente: a biometria automatica da tela de bloqueio nao abre por cima dela. */
    val cobrindo: Boolean get() = naTela && obrigatoria

    suspend fun conferir(contexto: Context) {
        if (demonstracao || conferindo) return
        if (!carregada) {
            carregada = true
            tentou = tentouHaPouco(contexto)
        }
        // Adiada ou em emergencia, volta as 6 horas: a cada volta, o GitHub veria o IP de quem adiou.
        val espera = if (naTela) INTERVALO_COM_TELA else INTERVALO
        val agora = SystemClock.elapsedRealtime()
        if (ultima?.let { agora - it < espera } == true || semRespostaAte?.let { agora < it } == true) return
        conferindo = true
        try {
            val pedido = JSONObject().put("versao", BuildConfig.VERSION_NAME).put("build", BuildConfig.VERSION_CODE.toString())
                .put("sdk", Build.VERSION.SDK_INT)
            val resposta = runCatching { Api.objeto("atualizacao.conferir", pedido) }.getOrNull() ?: return
            aplicar(resposta.optString("estado"), resposta.optString("versao").takeIf { it.isNotEmpty() })
        } finally {
            conferindo = false
        }
    }

    private fun aplicar(estado: String, nova: String?) {
        when (estado) {
            // Sem resposta, ou so uma lista mais antiga que a ja vista: fica o que se sabia, e a obrigatoria vira a comum (sem
            // internet nao ha o que instalar, e uma lista velha nao sustenta a obrigacao). Sem resposta, tenta de novo em 15
            // minutos: quem bloqueia o site nao transforma cada abertura do app num pedido visivel na rede.
            "sem-resposta", "antiga" -> {
                if (estado == "antiga") ultima = SystemClock.elapsedRealtime()
                else semRespostaAte = SystemClock.elapsedRealtime() + ESPERA_SEM_RESPOSTA
                obrigatoria = false
            }
            "desatualizada", "obrigatoria" -> {
                ultima = SystemClock.elapsedRealtime()
                semRespostaAte = null
                versao = nova ?: return
                obrigatoria = estado == "obrigatoria"
            }
            else -> {
                ultima = SystemClock.elapsedRealtime()
                semRespostaAte = null
                versao = null
                obrigatoria = false
            }
        }
    }

    /**
     * "Atualizar agora" tocado neste build nas ultimas 24 horas: a saida da obrigatoria continua depois de o sistema fechar o
     * app com a Play na frente, comum em celular com pouca memoria (revisao dos 3 agentes de 07/11/2026). O arquivo so
     * libera o deslizar que o toque ja liberaria; fica na pasta sem backup.
     */
    private fun arquivoDaTentativa(contexto: Context) = java.io.File(contexto.noBackupFilesDir, "atualizacao-tentou")

    private fun tentouHaPouco(contexto: Context): Boolean = runCatching {
        val (build, quando) = arquivoDaTentativa(contexto).readText().trim().split(" ").let { it[0] to it[1].toLong() }
        val idade = System.currentTimeMillis() - quando
        build == BuildConfig.VERSION_CODE.toString() && idade in 0 until VALIDADE_DA_TENTATIVA
    }.getOrDefault(false)

    /**
     * "Atualizar agora": a pagina do app no app da Play, e so na Play que vem com o sistema (outra loja que atende `market://`,
     * ou um app instalado com o nome de pacote da Play num aparelho sem Google, nao entra). Sem ela, nada abre, e a
     * obrigatoria ganha a saida do mesmo jeito.
     */
    fun atualizar(contexto: Context) {
        // Antes de abrir: com a Play na frente, o sistema pode fechar o app, e a saida tem de estar guardada.
        tentou = true
        runCatching { arquivoDaTentativa(contexto).writeText("${BuildConfig.VERSION_CODE} ${System.currentTimeMillis()}") }
        if (demonstracao) return
        val playDoSistema = runCatching {
            contexto.packageManager.getApplicationInfo("com.android.vending", 0).flags and ApplicationInfo.FLAG_SYSTEM != 0
        }.getOrDefault(false)
        if (playDoSistema) {
            runCatching {
                contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$PACOTE")).setPackage("com.android.vending"))
            }
        }
    }

    /** "Vou atualizar depois", ou "Usar em emergência" na obrigatoria depois de tentar atualizar. */
    fun depois() {
        if (obrigatoria) emergencia = true
        adiada = true
    }

    /** So no build de teste (`--es versao expirada|obrigatoria|tentou`): a tela sem uma versao de verdade na lista. */
    fun demonstrar(modo: String) {
        if (!BuildConfig.DEBUG) return
        demonstracao = true
        versao = "1.0.2"
        obrigatoria = modo != "expirada"
        tentou = modo == "tentou"
        adiada = false
        emergencia = false
    }
}

@Composable
fun TelaDeAtualizar() {
    val versao = Atualizacao.versao
    if (versao == null || !Atualizacao.naTela) return
    val contexto = LocalContext.current
    val obrigatoria = Atualizacao.obrigatoria
    // A tela so sai pelo deslizar: o voltar nao passa para a carteira por baixo.
    BackHandler {}
    // Com a obrigatoria na frente, de 5 em 5 minutos, so com o app na frente: tirada a obrigacao da lista, a tela sai sozinha.
    // O estado e lido dentro do laco: no segundo plano a composicao para e nao recomporia (no iPhone o app e suspenso).
    LaunchedEffect(obrigatoria) {
        while (obrigatoria) {
            delay(5 * 60 * 1000L)
            if (Ciclo.primeiroPlano) Atualizacao.conferir(contexto)
        }
    }
    val titulo = t("Esta versão está desatualizada")
    // O toque nao passa para a carteira por baixo; a semantica dela sai da arvore no Raiz.
    Column(Modifier.fillMaxSize().background(Paleta.vazio).pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent() } }
               .semantics { paneTitle = titulo }.statusBarsPadding()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.lg),
               horizontalAlignment = Alignment.CenterHorizontally) {
            // A seta num circulo simples, sem o anel de pixels, como no iPhone.
            Box(Modifier.padding(top = Espaco.xl).size(72.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                Icone(Icones.receber, Paleta.acento, tamanho = 26.dp)
            }
            Text(if (obrigatoria) t("Atualização obrigatória") else t("Atualização"), style = estilo(Tipo.nota).copy(fontWeight = FontWeight.SemiBold),
                 color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
            Text(titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                 modifier = Modifier.padding(top = Espaco.xs).semantics { heading() })
            // Sem o "confirmada pela lista assinada" do iPhone: a lista confirma que a Escalibur liberou o build, mas o app nao
            // confere o que a Play entrega no toque (no iPhone, a conferencia nova antes de abrir a loja confere).
            Text(if (obrigatoria) t("A Escalibur liberou a versão %@ na Google Play. Esta atualização é obrigatória: atualize para continuar usando o app.", versao)
                 else t("A Escalibur liberou a versão %@ na Google Play. Atualize para continuar com as correções mais recentes.", versao),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.base))
            Row(Modifier.padding(top = Espaco.lg).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(Espaco.md),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.md)) {
                EmblemaCifrado(76.dp, Icones.cadeadoCheio, Paleta.sucesso)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Espaco.xxs)) {
                    Text(t("Seus fundos estão seguros"), style = estilo(Tipo.linha), color = Paleta.tinta)
                    Text(t("Atualizar não pede suas palavras e mantém suas carteiras como estão."), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                }
            }
        }
        Rodape {
            BotaoPrimario(t("Atualizar agora")) { Atualizacao.atualizar(contexto) }
            if (!obrigatoria) {
                DeslizeParaSeguir(t("Vou atualizar depois"), ligado = true) { Atualizacao.depois() }
                Text(t("A tela volta na próxima vez que você abrir o app."), style = estilo(Tipo.nota), color = Paleta.tintaApagada, textAlign = TextAlign.Center)
            } else if (Atualizacao.tentou) {
                DeslizeParaSeguir(t("Usar em emergência"), ligado = true) { Atualizacao.depois() }
                Text(t("Só se precisar mexer nos fundos agora."), style = estilo(Tipo.nota), color = Paleta.tintaApagada, textAlign = TextAlign.Center)
            }
        }
    }
}
