package app.escalibur.wallet.vigias

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.icu.text.NumberFormat
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.escalibur.wallet.MainActivity
import app.escalibur.wallet.R
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.Textos
import app.escalibur.wallet.ui.t
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.math.abs
import kotlin.math.floor

/**
 * Os avisos sem servidor: alertas de preco, moeda recebida, ordem limite e ponte. O nucleo confere
 * e diz o que aconteceu; aqui viram notificacoes locais, com o texto na lingua e no formato do
 * aparelho. Nenhuma notificacao remota, nenhum token de push.
 *
 * A tela bloqueada: a versao publica de cada uma ("Alerta de preço", "Recebimento") so vale se o
 * dono escondeu o conteudo sensivel nos ajustes do Android, e o padrao do sistema mostra tudo. Por
 * isso o recebimento com valor nunca vai para a tela bloqueada: com o celular travado, sai o texto
 * discreto; destravado, sai com o valor e some da tela bloqueada (VISIBILITY_SECRET).
 */
object Vigia {
    private const val TRABALHO = 4107
    /**
     * O Android decide quando roda; isto e so o intervalo pedido. Uma hora: a cada rodada os
     * provedores recebem os enderecos do IP do momento, e 20 minutos davam ate 72 por dia (auditoria
     * de privacidade, 22/10/2026).
     */
    private const val INTERVALO = 60 * 60 * 1000L
    private const val FLEXIBILIDADE = 15 * 60 * 1000L
    /** O rosa do icone do app, atras da espada. */
    private const val ROSA = 0xFFFF007B.toInt()

    /** O toque numa notificacao, esperando o app destravar. */
    var pedido by mutableStateOf<Pedido?>(null)

    class Pedido(val moeda: String?, val ordem: String?, val recebimento: Boolean)

    /** A pasta dos arquivos dos avisos: sem backup, fora dos dados cifrados da carteira. */
    fun pasta(contexto: Context) = File(contexto.noBackupFilesDir, "vigias")

    private val canais = listOf(
        "precos" to "Alertas de preço",
        "recebimentos" to "Recebimentos",
        "ordens" to "Ordens limite",
        "pontes" to "Pontes",
    )

    /** O titulo que a tela bloqueada mostra no lugar do conteudo. */
    private fun publico(canal: String) = when (canal) {
        "precos" -> t("Alerta de preço")
        "recebimentos" -> t("Recebimento")
        "ordens" -> t("Ordem limite")
        else -> t("Ponte")
    }

    private fun criarCanais(contexto: Context) {
        val gerente = contexto.getSystemService(NotificationManager::class.java)
        for ((id, nome) in canais) {
            val canal = NotificationChannel(id, t(nome), NotificationManager.IMPORTANCE_DEFAULT).apply {
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
            gerente.createNotificationChannel(canal)
        }
    }

    /** Notificacoes ligadas para o app (e, do Android 13 em diante, a permissao dada). */
    fun permitido(contexto: Context): Boolean {
        val gerente = contexto.getSystemService(NotificationManager::class.java)
        if (!gerente.areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < 33 || contexto.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    /** Ja recusou de vez: so os ajustes do sistema ligam de novo. */
    fun negado(contexto: Context): Boolean = !permitido(contexto)

    /** A pagina de notificacoes do app nos ajustes do Android. */
    fun abrirAjustesDoSistema(contexto: Context) {
        val intencao = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, contexto.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { contexto.startActivity(intencao) }
    }

    /**
     * Confere agora e publica o que houver. Nao cancela no meio: o nucleo ja marcou o saldo e o preco
     * vistos, e um aviso descartado aqui nao voltaria.
     */
    suspend fun conferir(contexto: Context, forcar: Boolean = false) = withContext(NonCancellable) {
        val resposta = runCatching { Api.objeto("vigias.conferir", JSONObject().put("forcar", forcar)) }.getOrNull() ?: return@withContext
        publicar(contexto, resposta.optJSONArray("avisos"))
        agendar(contexto, resposta.optBoolean("agendar"))
    }

    /** Depois de mudar um ajuste: a checagem do segundo plano entra ou sai da agenda. */
    suspend fun atualizarAgenda(contexto: Context) {
        val resposta = runCatching { Api.objeto("vigias.agenda") }.getOrNull() ?: return
        agendar(contexto, resposta.optBoolean("agendar"))
    }

    fun agendar(contexto: Context, ligar: Boolean) {
        val agenda = contexto.getSystemService(JobScheduler::class.java)
        if (!ligar) {
            agenda.cancel(TRABALHO)
            return
        }
        // A agenda da versao anterior (20 minutos) fica persistida: troca pela de agora.
        val pendente = agenda.getPendingJob(TRABALHO)
        if (pendente != null && pendente.intervalMillis == INTERVALO) return
        if (pendente != null) agenda.cancel(TRABALHO)
        val trabalho = JobInfo.Builder(TRABALHO, ComponentName(contexto, ConferenciaDoFundo::class.java))
            .setPeriodic(INTERVALO, FLEXIBILIDADE)
            // Sem exigir rede (pediria mais uma permissao): o aviso de 24 horas da ordem nem precisa
            // dela, e sem rede a conferencia so nao acha nada.
            .setPersisted(true)
            .build()
        runCatching { agenda.schedule(trabalho) }
    }

    fun publicar(contexto: Context, avisos: JSONArray?) {
        if (avisos == null || avisos.length() == 0 || !permitido(contexto)) return
        criarCanais(contexto)
        val gerente = contexto.getSystemService(NotificationManager::class.java)
        val travado = contexto.getSystemService(android.app.KeyguardManager::class.java)?.isDeviceLocked ?: true
        for (indice in 0 until avisos.length()) {
            val aviso = avisos.optJSONObject(indice) ?: continue
            val canal = aviso.optString("canal", "precos")
            // "Recebeu 10.000 USDT" na tela bloqueada marca o dono como alvo (pentest de 14/10/2026, B1).
            val comValor = canal == "recebimentos" && aviso.optString("tipo") in setOf("recebeu", "mais")
            val (titulo, texto) = if (comValor && travado) t("Entrou moeda na carteira") to t("Abra a Escalibur para ver.") else textos(aviso)
            val id = aviso.optString("id")
            val publica = Notification.Builder(contexto, canal)
                .setSmallIcon(R.drawable.ic_notificacao)
                .setColor(ROSA)
                .setContentTitle(publico(canal))
                .build()
            val notificacao = Notification.Builder(contexto, canal)
                .setSmallIcon(R.drawable.ic_notificacao)
                .setColor(ROSA)
                .setContentTitle(titulo)
                .setContentText(texto)
                .setStyle(Notification.BigTextStyle().bigText(texto))
                .setAutoCancel(true)
                .setVisibility(if (comValor && !travado) Notification.VISIBILITY_SECRET else Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(publica)
                .setContentIntent(abrir(contexto, id, aviso))
                .build()
            gerente.notify(id, 0, notificacao)
        }
    }

    /** Um segredo so do app, na pasta sem backup, que vai em cada notificacao. */
    @Synchronized
    private fun ficha(contexto: Context): String {
        val arquivo = File(contexto.noBackupFilesDir, "aviso.ficha")
        runCatching { arquivo.readText() }.getOrNull()?.takeIf { it.length == 64 }?.let { return it }
        val nova = ByteArray(32).also { java.security.SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
        arquivo.writeText(nova)
        return nova
    }

    /** O toque so abre o app: nenhuma acao na notificacao. Depois do PIN, o app leva ao lugar. */
    private fun abrir(contexto: Context, id: String, aviso: JSONObject): PendingIntent {
        val intencao = Intent(contexto, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("aviso", true)
            .putExtra("aviso.ficha", ficha(contexto))
        if (aviso.optString("canal") == "precos") aviso.optString("moeda").takeIf { it.isNotEmpty() }?.let { intencao.putExtra("aviso.moeda", it) }
        if (aviso.optString("canal") == "ordens") intencao.putExtra("aviso.ordem", aviso.optString("ordem"))
        if (aviso.optString("canal") == "recebimentos") intencao.putExtra("aviso.recebimento", true)
        return PendingIntent.getActivity(contexto, id.hashCode(), intencao, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** O toque que abriu (ou trouxe) o app. */
    fun receber(contexto: Context, intencao: Intent?) {
        if (intencao?.getBooleanExtra("aviso", false) != true) return
        // A MainActivity e exportada: um intent de outro app com "aviso" fechava o fluxo aberto e
        // navegava. So a notificacao daqui leva a ficha.
        val recebida = intencao.getStringExtra("aviso.ficha")?.toByteArray() ?: return
        if (!java.security.MessageDigest.isEqual(recebida, ficha(contexto).toByteArray())) return
        pedido = Pedido(intencao.getStringExtra("aviso.moeda"), intencao.getStringExtra("aviso.ordem"), intencao.getBooleanExtra("aviso.recebimento", false))
        intencao.removeExtra("aviso")
    }

    // MARK: Texto

    /** "R$ 81.000" no nivel inteiro; "R$ 1,10" e "R$ 0,000012" abaixo disso. */
    private fun nivel(valor: Double, unidade: String): String =
        if (valor >= 1 && valor == floor(valor)) Formato.dinheiro(Formato.agrupado(valor, 0), Formato.simboloDaMoeda(unidade))
        else Formato.preco(valor, unidade)

    /** "5,2%", no formato da regiao, sem sinal (o titulo diz se subiu ou caiu). */
    private fun percentual(valor: Double): String =
        NumberFormat.getPercentInstance(Formato.locale).apply { minimumFractionDigits = 1; maximumFractionDigits = 1 }.format(abs(valor) / 100)

    private fun textos(aviso: JSONObject): Pair<String, String> {
        val nome = aviso.optString("nome")
        val unidade = aviso.optString("unidade", "usd")
        fun numero(chave: String): Double? = if (aviso.has(chave) && !aviso.isNull(chave)) aviso.getDouble(chave) else null
        val agora = numero("preco")?.let { t("Agora %@", Formato.preco(it, unidade)) } ?: ""
        val dia = numero("variacao")?.let { t(", %@ em 24 h.", Formato.percentual(it)) } ?: "."
        return when (aviso.optString("canal") to aviso.optString("tipo")) {
            "precos" to "passou" -> t("%@ passou de %@", nome, nivel(numero("nivel") ?: 0.0, unidade)) to agora + dia
            "precos" to "caiu" -> t("%@ caiu abaixo de %@", nome, nivel(numero("nivel") ?: 0.0, unidade)) to agora + dia
            "precos" to "subiu" -> t("%@ subiu %@ em 24 h", nome, percentual(numero("variacao") ?: 0.0)) to "$agora."
            "precos" to "desceu" -> t("%@ caiu %@ em 24 h", nome, percentual(numero("variacao") ?: 0.0)) to "$agora."
            "precos" to "mais" -> t("Mais %lld alertas de preço", aviso.optInt("quantos")) to t("Abra o Mercado para ver.")
            "precos" to "discreto" -> t("Alerta de preço") to t("Abra o app para ver o que mudou.")
            "recebimentos" to "recebeu" -> t("Recebeu %@", aviso.optString("quantia")) to t("Na %@. O saldo novo já está na carteira.", aviso.optString("rede"))
            "recebimentos" to "mais" -> t("Mais %lld recebimentos", aviso.optInt("quantos")) to t("Abra a Atividade para ver.")
            "recebimentos" to "discreto" -> t("Entrou moeda na carteira") to t("Abra a Escalibur para ver.")
            "ordens" to "executada" -> t("Sua ordem limite foi executada") to t("A troca saiu no seu preço. O saldo novo já está na carteira.")
            "ordens" to "prazo" -> t("O prazo de uma ordem limite acabou") to t("Abra a Escalibur: se ainda faltar vender, o app pergunta se refaz com o mesmo preço.")
            "ordens" to "vence24h" -> t("Sua ordem limite vence em 24 horas") to t("Se ela ainda não executou, abra a Escalibur para ver ou mudar o preço.")
            "pontes" to "chegou" -> t("Sua ponte chegou") to t("Conferido na %@. Abra a Escalibur para ver.", aviso.optString("rede"))
            else -> t("Escalibur Wallet") to t("Abra a Escalibur para ver.")
        }
    }
}

/**
 * A checagem do segundo plano, quando o Android deixa: os alertas de preco, o aviso de recebimento
 * e as ordens limite abertas. Nao abre a sessao nem o cofre: le so os arquivos dos avisos.
 */
class ConferenciaDoFundo : JobService() {
    private var trabalho: Job? = null

    override fun onStartJob(parametros: JobParameters): Boolean {
        trabalho = CoroutineScope(Dispatchers.IO).launch {
            runCatching {
                Textos.carregar(applicationContext)
                val preparo = Api.objeto("vigias.preparar", JSONObject().put("pasta", Vigia.pasta(applicationContext).absolutePath))
                if (preparo.optBoolean("agendar")) Vigia.conferir(applicationContext, forcar = true)
                else Vigia.agendar(applicationContext, false)
            }
            jobFinished(parametros, false)
        }
        return true
    }

    override fun onStopJob(parametros: JobParameters): Boolean {
        trabalho?.cancel()
        return true
    }
}
