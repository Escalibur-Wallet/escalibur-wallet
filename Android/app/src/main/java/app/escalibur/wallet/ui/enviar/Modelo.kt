package app.escalibur.wallet.ui.enviar

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.receber.opcional
import app.escalibur.wallet.ui.textos
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Um trecho do endereco que o dono le e digita. */
data class Trecho(val inicio: Int, val tamanho: Int) {
    companion object {
        fun de(j: JSONObject?) = j?.let { Trecho(it.getInt("inicio"), it.getInt("tamanho")) }
    }
}

/** O retrato de um envio, como o nucleo devolve (Envio.Estado, no Swift). */
class RetratoDoEnvio(json: JSONObject) {
    val numero = json.getInt("numero")
    val id = json.getString("id")
    val preco: Double? = if (json.has("preco")) json.getDouble("preco") else null
    val moeda = json.getString("moeda")
    val pedePassphrase = json.getBoolean("pedePassphrase")
    val nomeDaCarteira = json.getString("nomeDaCarteira")
    private val e = json.getJSONObject("envio")

    val etapa: String = e.getString("etapa")
    private val a = e.getJSONObject("ativo")
    val ativoID: String = a.getString("id")
    val simbolo: String = a.getString("simbolo")
    val rede: String = a.getString("rede")
    val redeNome: String = a.getString("redeNome")
    val redeCoingecko: String = a.getString("redeCoingecko")
    val coingecko: String? = a.opcional("coingecko")
    val casas: Int = a.getInt("casas")
    val custom: Boolean = a.getBoolean("custom")
    val conferido: Boolean = a.getBoolean("conferido")
    val quantidade: String = a.getString("quantidade")
    val disponivelDaTela: String = a.getString("disponivel")

    val familia: String = e.getString("familia")
    val tipoDeTag: String = e.getString("tipoDeTag")
    val textoDoDestino: String = e.getString("textoDoDestino")
    val destino: String? = e.opcional("destino")
    val tagDoEndereco: String? = e.opcional("tagDoEndereco")
    val problema: String? = e.opcional("problema")
    val sugestao: Triple<String, String, String>? = e.optJSONObject("sugestao")?.let { Triple(it.getString("ativo"), it.getString("simbolo"), it.getString("redeNome")) }
    val rotuloDoDestino: String? = e.opcional("rotuloDoDestino")
    val primeiroEnvio: Boolean = e.getBoolean("primeiroEnvio")
    val historicoLido: Boolean = e.getBoolean("historicoLido")

    class Parecido(val conhecido: String, val rotulo: String, val trechoColado: Trecho?, val trechoConhecido: Trecho?)
    class OutroID(val conhecido: String, val idConhecido: String, val rotulo: String, val trechoColado: Trecho?, val trechoConhecido: Trecho?)
    /** `todoEnvio`: o desafio e o da opcao "Conferir o endereco em todo envio" (os 6 ultimos), e nao o do historico ilegivel. */
    class Cego(val fonte: String, val trecho: Trecho, val todoEnvio: Boolean = false)

    val parecido: Parecido? = e.optJSONObject("parecido")?.let {
        Parecido(it.getString("conhecido"), it.getString("rotulo"), Trecho.de(it.optJSONObject("trechoColado")), Trecho.de(it.optJSONObject("trechoConhecido")))
    }
    val outroID: OutroID? = e.optJSONObject("outroID")?.let {
        OutroID(it.getString("conhecido"), it.getString("idConhecido"), it.getString("rotulo"),
                Trecho.de(it.optJSONObject("trechoColado")), Trecho.de(it.optJSONObject("trechoConhecido")))
    }
    val cego: Cego? = e.optJSONObject("cego")?.let { Cego(it.getString("fonte"), Trecho.de(it.getJSONObject("trecho"))!!, it.optBoolean("todoEnvio")) }
    /** Com um desafio na tela, o campo do endereco some: a resposta se leria nele. */
    val desafio: Boolean get() = parecido != null || outroID != null || cego != null

    val precisaConfirmarRede: Boolean = e.getBoolean("precisaConfirmarRede")
    val notaDaRede: String? = e.opcional("notaDaRede")
    val textoDaConfirmacaoDeRede: String? = e.opcional("textoDaConfirmacaoDeRede")
    val muxed: Boolean = e.getBoolean("muxed")
    val precisaEtapaDaTag: Boolean = e.getBoolean("precisaEtapaDaTag")
    val exigeTag: Boolean = e.getBoolean("exigeTag")
    val tag: String = e.getString("tag")
    val tagDoLink: Boolean = e.getBoolean("tagDoLink")
    val problemaDaTag: String? = e.opcional("problemaDaTag")
    val podeContinuar: Boolean = e.getBoolean("podeContinuar")

    private val d = e.optJSONObject("disponivel")
    /** O que da para gastar, pelo motor; sem ele, o saldo menos a reserva da rede. */
    val disponivel: String = d?.getString("quantidade") ?: disponivelDaTela
    val motorRespondeu: Boolean = d != null
    val notaDeReserva: String? = d?.opcional("notaDeReserva")
    val notaDeTaxa: String? = d?.opcional("notaDeTaxa")
    val ativacao: String? = e.opcional("ativacao")
    val valor: String = e.getString("valor")
    val tudo: Boolean = e.getBoolean("tudo")

    class LinhaDaPlaca(val rotulo: String, val valor: String, val endereco: Boolean)
    class Plano(
        val titulo: String, val placa: List<LinhaDaPlaca>, val linhas: List<Pair<String, String>>, val avisos: List<String>, val saida: String,
        /** Quando os dados da rede vencem (ms): a revisao renova um pouco antes. */
        val venceEm: Long,
        /** Sobe quando a renovacao mudou o valor ou a taxa: o aceite e o deslizar recomecam. */
        val versao: Int,
        val mudou: Boolean,
    )

    val plano: Plano? = e.optJSONObject("plano")?.let { p ->
        Plano(
            p.getString("titulo"),
            p.getJSONArray("placa").objetos().map { LinhaDaPlaca(it.getString("rotulo"), it.getString("valor"), it.getBoolean("endereco")) },
            p.getJSONArray("linhas").objetos().map { it.getString("rotulo") to it.getString("valor") },
            p.getJSONArray("avisos").textos(), p.getString("saida"),
            p.optDouble("venceEm", 0.0).toLong(), p.optInt("versao"), p.optBoolean("mudou"),
        )
    }
    val erro: String? = e.opcional("erro")

    class Resultado(val id: String, val situacao: String, val detalhe: String?, val explorador: String?, val urlDoExplorador: String?)

    val resultado: Resultado? = e.optJSONObject("resultado")?.let {
        Resultado(it.getString("id"), it.getString("situacao"), it.opcional("detalhe"), it.opcional("explorador"), it.opcional("urlDoExplorador"))
    }
    val detalheIncerto: String? = e.opcional("detalheIncerto")
    val linhaDoEnvio: String = e.getString("linhaDoEnvio")
    val tempoDeConfirmacao: Int = e.getInt("tempoDeConfirmacao")

    class Contato(val nome: String, val endereco: String, val tag: String?)
    /** `liga`: uma e com passphrase e a outra nao; o envio liga as duas na blockchain. */
    class MinhaCarteira(val id: String, val nome: String, val endereco: String, val liga: Boolean = false)

    val contatos: List<Contato> = e.getJSONArray("contatos").objetos().map { Contato(it.getString("nome"), it.getString("endereco"), it.opcional("tag")) }
    val minhasCarteiras: List<MinhaCarteira> = e.getJSONArray("minhasCarteiras").objetos().map {
        MinhaCarteira(it.getString("id"), it.getString("nome"), it.getString("endereco"), it.optBoolean("liga"))
    }
    val variasCarteiras: Boolean = e.getBoolean("variasCarteiras")
}

/**
 * O envio aberto na tela. Cada chamada devolve o retrato inteiro, numerado pelo nucleo: o que
 * chegar fora de ordem (uma digitacao rapida, a leitura do historico) e descartado.
 */
class ControleDoEnvio {
    var retrato by mutableStateOf<RetratoDoEnvio?>(null)
        private set
    var trabalhando by mutableStateOf(false)
    /** A mensagem do motor na ultima recusa ("envio.motor"), quando ele explica. */
    var falha by mutableStateOf<String?>(null)

    fun aplicar(json: JSONObject) {
        val novo = runCatching { RetratoDoEnvio(json) }.getOrNull() ?: return
        val atual = retrato
        if (atual != null && (novo.id != atual.id || novo.numero <= atual.numero)) return
        retrato = novo
    }

    /** As chamadas rapidas em fila, na ordem da digitacao: uma letra antiga nunca chega depois. */
    private val fila = Mutex()

    /** As que vao a rede (historico, destino, plano): fora da fila, para nao segurar a digitacao. */
    private val longas = setOf("envio.historico", "envio.continuar", "envio.disponivel", "envio.revisar", "envio.retransmitir", "envio.acompanhar")

    /** Uma chamada "envio.*". Devolve se o nucleo aceitou. */
    suspend fun chamar(metodo: String, corpo: JSONObject = JSONObject()): Boolean = try {
        val resposta = if (metodo in longas) Api.objeto(metodo, corpo) else fila.withLock { Api.objeto(metodo, corpo) }
        aplicar(resposta)
        true
    } catch (erro: FalhaDoNucleo) {
        falha = erro.dados.optString("mensagem", "").ifEmpty { null }
        false
    }

    /** Uma chamada longa (rede), com o botao carregando. */
    suspend fun trabalhar(metodo: String, corpo: JSONObject = JSONObject()): Boolean {
        trabalhando = true
        try {
            return chamar(metodo, corpo)
        } finally {
            trabalhando = false
        }
    }

    suspend fun iniciar(ativo: String): FalhaDoNucleo? = try {
        retrato = RetratoDoEnvio(Api.objeto("envio.iniciar", JSONObject().put("ativo", ativo)))
        null
    } catch (erro: FalhaDoNucleo) {
        erro
    }

    /** A tela fechou: o envio dela sai da memoria do nucleo (o de uma tela aberta depois fica). */
    fun encerrar() {
        val id = retrato?.id ?: return
        CoroutineScope(Dispatchers.IO).launch {
            withContext(NonCancellable) { runCatching { Api.objeto("envio.encerrar", JSONObject().put("id", id)) } }
        }
    }
}
