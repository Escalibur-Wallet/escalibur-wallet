package app.escalibur.wallet.ui.trocar

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** Um ativo da troca, como o nucleo descreve (Troca.Estado.Ativo, no Swift). */
class AtivoDaTroca(j: JSONObject) {
    val id: String = j.getString("id")
    val simbolo: String = j.getString("simbolo")
    val nome: String = j.getString("nome")
    val rede: String = j.getString("rede")
    val redeCoingecko: String = j.getString("redeCoingecko")
    val coingecko: String? = j.opcional("coingecko")
    val casas: Int = j.getInt("casas")
    val conferido: Boolean = j.getBoolean("conferido")
    val custom: Boolean = j.getBoolean("custom")
    val preco: Double? = j.duplo("preco")
}

internal fun JSONObject.duplo(chave: String): Double? = if (has(chave) && !isNull(chave)) getDouble(chave) else null

/** O retrato da troca de uma tela, como o nucleo devolve. */
class RetratoDaTroca(json: JSONObject) {
    val numero = json.getInt("numero")
    val moeda: String = json.getString("moeda")
    val pedePassphrase = json.getBoolean("pedePassphrase")
    val nomeDaCarteira: String = json.getString("nomeDaCarteira")
    private val e = json.getJSONObject("troca")

    class Rede(val id: String, val nome: String, val coingecko: String)

    private fun rede(j: JSONObject) = Rede(j.getString("id"), j.getString("nome"), j.getString("coingecko"))

    val alvo: String = e.getString("alvo")
    val carteira: String? = e.opcional("carteira")
    val observa: Boolean = e.getBoolean("observa")
    /** "agora" ou "limite". */
    val modo: String = e.getString("modo")
    val temLimite: Boolean = e.getBoolean("temLimite")
    val redes: List<Rede> = e.getJSONArray("redes").objetos().map(::rede)
    val rede: Rede? = e.optJSONObject("rede")?.let(::rede)
    val vende: AtivoDaTroca? = e.optJSONObject("vende")?.let(::AtivoDaTroca)
    val compra: AtivoDaTroca? = e.optJSONObject("compra")?.let(::AtivoDaTroca)
    val valor: String = e.getString("valor")
    /** Sobe quando o nucleo muda o texto do valor por conta propria: so entao o campo copia. */
    val versaoDoValor: Int = e.getInt("versaoDoValor")
    /** O valor a pagar, no inteiro da rede: o digitado ou o que a busca achou. */
    val entrada: String? = e.opcional("entrada")
    val recebeExato: Boolean = e.getBoolean("recebeExato")
    val recebido: String = e.getString("recebido")
    val versaoDoRecebido: Int = e.getInt("versaoDoRecebido")
    val resolvendo: Boolean = e.getBoolean("resolvendo")
    val abaixoDoAlvo: String? = e.opcional("abaixoDoAlvo")
    val saldo: String? = e.opcional("saldo")
    val saldoDaCompra: String? = e.opcional("saldoDaCompra")
    val temSaldo: Boolean = e.getBoolean("temSaldo")
    val passou: Boolean = e.getBoolean("passou")
    val tolerancia: Int = e.getInt("tolerancia")
    val automatica: Boolean = e.getBoolean("automatica")
    val toleranciaAuto: Int = e.getInt("toleranciaAuto")
    val chave: String = e.getString("chave")
    val podeCotar: Boolean = e.getBoolean("podeCotar")
    val cotando: Boolean = e.getBoolean("cotando")
    val emPartes: Boolean = e.getBoolean("emPartes")

    class Perna(val provedor: String, val fracao: Double, val recebe: String)
    class Alternativa(val provedor: String, val garante: String, val diferenca: String?, val usar: Boolean)
    class Partes(val deUmaVez: String, val emPartes: String, val ganho: String?, val notaDeUmaVez: String)
    class Cotacao(j: JSONObject) {
        val atual: Boolean = j.getBoolean("atual")
        val garantido: String = j.getString("garantido")
        val preco: String = j.getString("preco")
        val precoInvertido: String = j.getString("precoInvertido")
        val rota: String = j.getString("rota")
        val provedores: List<String> = j.getJSONArray("provedores").textos()
        val taxaDaRede: Double? = j.duplo("taxaDaRede")
        val garantidoTexto: String = j.getString("garantidoTexto")
        val doProvedor: String = j.getString("doProvedor")
        val prazo: String? = j.opcional("prazo")
        val impacto: Double? = j.duplo("impacto")
        val nivel: String = j.getString("nivel")
        val partes: Partes? = j.optJSONObject("partes")?.let {
            Partes(it.getString("deUmaVez"), it.getString("emPartes"), it.opcional("ganho"), it.getString("notaDeUmaVez"))
        }
        val tituloDaRota: String = j.getString("tituloDaRota")
        val pernas: List<Perna> = j.getJSONArray("pernas").objetos().map { Perna(it.getString("provedor"), it.getDouble("fracao"), it.getString("recebe")) }
        val explicacao: String = j.getString("explicacao")
        val alternativas: List<Alternativa> = j.getJSONArray("alternativas").objetos().map {
            Alternativa(it.getString("provedor"), it.getString("garante"), it.opcional("diferenca"), it.getBoolean("usar"))
        }
    }

    class Validade(val segundos: Double?, val titulo: String)
    class ConferenciaDoPreco(val texto: String, val forte: Boolean, val confirmacao: String?, val confirmado: Boolean)
    class Limite(j: JSONObject) {
        val preco: String = j.getString("preco")
        val versaoDoPreco: Int = j.getInt("versaoDoPreco")
        val precoCompacto: String? = j.opcional("precoCompacto")
        val rotuloDoPreco: String = j.getString("rotuloDoPreco")
        val recebido: String = j.getString("recebido")
        /** O valor vendido saiu da conta (o recebido digitado com o preco fixo). */
        val calculado: Boolean = j.getBoolean("calculado")
        val validades: List<Validade> = j.getJSONArray("validades").objetos().map { Validade(it.duplo("segundos"), it.getString("titulo")) }
        val validade: Double? = j.duplo("validade")
        val semPrazo: String? = j.opcional("semPrazo")
        val custodia: String? = j.opcional("custodia")
        val conferencia: ConferenciaDoPreco? = j.optJSONObject("conferencia")?.let {
            ConferenciaDoPreco(it.getString("texto"), it.getBoolean("forte"), it.opcional("confirmacao"), it.getBoolean("confirmado"))
        }
        val editando: String? = j.opcional("editando")
    }

    val cotacao: Cotacao? = e.optJSONObject("cotacao")?.let(::Cotacao)
    val limite: Limite? = e.optJSONObject("limite")?.let(::Limite)
    val erro: String? = e.opcional("erro")
    val erroDoPlano: String? = e.opcional("erroDoPlano")
    val naoVerificado: String? = e.opcional("naoVerificado")
    val impactoAceito: Boolean = e.getBoolean("impactoAceito")
    val botao: String = e.getString("botao")
    val botaoLigado: Boolean = e.getBoolean("botaoLigado")
    val protecao: Boolean = e.getBoolean("protecao")
    val etapa: String = e.getString("etapa")

    /** Os textos de cada etapa, pelo que a revisao assina: troca, ordem limite ou cancelamento. */
    class Frases(j: JSONObject) {
        val tipo: String = j.getString("tipo")
        val montando: String = j.getString("montando")
        val naoMontou: String = j.getString("naoMontou")
        val confirmar: String = j.getString("confirmar")
        val enviando: String = j.getString("enviando")
        val feito: String = j.getString("feito")
        val mensagemDoFeito: String = j.getString("mensagemDoFeito")
        val incerto: String = j.getString("incerto")
        val passo: String? = j.opcional("passo")
    }

    class Revisao(j: JSONObject) {
        val titulo: String = j.getString("titulo")
        val sai: String? = j.opcional("sai")
        val entra: String? = j.opcional("entra")
        val enderecos: List<Pair<String, String>> = j.getJSONArray("enderecos").objetos().map { it.getString("rotulo") to it.getString("valor") }
        val linhas: List<Pair<String, String>> = j.getJSONArray("linhas").objetos().map { it.getString("rotulo") to it.getString("valor") }
        val avisos: List<String> = j.getJSONArray("avisos").textos()
        val transacoes: Int = j.getInt("transacoes")
        val nota: String = j.getString("nota")
        val erro: String? = j.opcional("erro")
    }

    class Resultado(val id: String?, val explorador: String, val url: String?, val situacao: String, val detalhe: String?, val ordem: Boolean)
    class Andamento(val estado: String, val fracao: Double, val recebido: String, val garantido: String)

    val frases: Frases? = e.optJSONObject("frases")?.let(::Frases)
    val revisaoVende: AtivoDaTroca? = e.optJSONObject("revisaoVende")?.let(::AtivoDaTroca)
    val revisaoCompra: AtivoDaTroca? = e.optJSONObject("revisaoCompra")?.let(::AtivoDaTroca)
    val falhaDaMontagem: String? = e.opcional("falhaDaMontagem")
    /** Edicao: a etapa 1 (cancelar a ordem atual) ja saiu. */
    val cancelou: Boolean = e.getBoolean("cancelou")
    val revisao: Revisao? = e.optJSONObject("revisao")?.let(::Revisao)
    val resultado: Resultado? = e.optJSONObject("resultado")?.let {
        Resultado(it.opcional("id"), it.getString("explorador"), it.opcional("url"), it.getString("situacao"), it.opcional("detalhe"), it.getBoolean("ordem"))
    }
    val andamento: Andamento? = e.optJSONObject("andamento")?.let {
        Andamento(it.getString("estado"), it.getDouble("fracao"), it.getString("recebido"), it.getString("garantido"))
    }
    val semAndamento: Boolean = e.getBoolean("semAndamento")
    val detalheIncerto: String? = e.opcional("detalheIncerto")
    val valorEmMoeda: Double? = e.duplo("valorEmMoeda")
}

/** Uma linha da escolha de token. */
class OpcaoDeToken(j: JSONObject) {
    val ativo = AtivoDaTroca(j.getJSONObject("ativo"))
    val quantidade: String? = j.opcional("quantidade")
    val fora: Boolean = j.getBoolean("fora")
}

/**
 * A troca de uma tela. O estado fica no nucleo: a da aba (`ControleDaTroca.aba`) vive enquanto o
 * app esta aberto, e a aba que sai e volta pega o mesmo retrato; editar e cancelar uma ordem tem a
 * propria, que sai da memoria quando a tela fecha. O que chegar fora de ordem e descartado.
 */
class ControleDaTroca(val alvo: String) {
    var retrato by mutableStateOf<RetratoDaTroca?>(null)
        private set
    var trabalhando by mutableStateOf(false)
    /** Segundos ate a proxima cotacao. */
    var proxima by mutableIntStateOf(15)
    /** Uma rodada de cotacao no ar. */
    var buscando by mutableStateOf(false)
    /** Na aba: a Ponte escolhida no seletor (ela tem o proprio formulario, fora da troca). */
    var naPonte by mutableStateOf(false)

    fun aplicar(json: JSONObject) {
        val novo = runCatching { RetratoDaTroca(json) }.getOrNull() ?: return
        if (novo.alvo != alvo) return
        val atual = retrato
        if (atual != null && novo.numero <= atual.numero) return
        retrato = novo
    }

    /** As chamadas rapidas em fila, na ordem da digitacao: uma letra antiga nunca chega depois. */
    private val fila = Mutex()

    /** As que vao a rede: fora da fila, para nao segurar a digitacao. */
    private val longas = setOf("troca.cotar", "troca.revisar", "troca.remontar", "troca.cancelar", "troca.retransmitir", "troca.acompanhar")

    suspend fun chamar(metodo: String, corpo: JSONObject = JSONObject()): Boolean = try {
        corpo.put("alvo", alvo)
        val resposta = if (metodo in longas) Api.objeto(metodo, corpo) else fila.withLock { Api.objeto(metodo, corpo) }
        aplicar(resposta)
        true
    } catch (erro: FalhaDoNucleo) {
        false
    }

    /** Uma mudanca do formulario ("troca.definir"), na fila da digitacao. */
    fun definir(mudanca: JSONObject) {
        escopo.launch { chamar("troca.definir", mudanca) }
    }

    /** Uma chamada longa, com o botao carregando. */
    suspend fun trabalhar(metodo: String, corpo: JSONObject = JSONObject()): Boolean {
        trabalhando = true
        try {
            return chamar(metodo, corpo)
        } finally {
            trabalhando = false
        }
    }

    /** A tela de editar ou de cancelar fechou: a troca dela sai da memoria do nucleo. */
    fun encerrar() {
        if (alvo == "aba") return
        CoroutineScope(Dispatchers.IO).launch {
            withContext(NonCancellable) { runCatching { Api.objeto("troca.encerrar", JSONObject().put("alvo", alvo)) } }
        }
    }

    suspend fun opcoes(vende: Boolean): List<OpcaoDeToken> =
        runCatching { Api.lista("troca.opcoes", JSONObject().put("vende", vende).put("alvo", alvo)).objetos().map(::OpcaoDeToken) }.getOrDefault(emptyList())

    companion object {
        /** As mudancas do formulario vivem alem da tela: a que saiu ainda chega ao nucleo. */
        private val escopo = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

        val aba = ControleDaTroca("aba")

        /**
         * "Trocar", "Vender" e "Comprar" de outra tela: a aba abre na rede do ativo, com ele de um
         * lado. Devolve se o nucleo aceitou (ativo que pode ir para a troca, sem revisao aberta).
         */
        suspend fun preparar(ativo: String, vende: Boolean): Boolean =
            aba.chamar("troca.preparar", JSONObject().put("ativo", ativo).put("vende", vende))

        /** Todos os ativos podem ir para a troca. */
        suspend fun permite(ativos: List<String>): Boolean =
            runCatching { Api.objeto("troca.permite", JSONObject().put("ativos", JSONArray(ativos))).getBoolean("permite") }.getOrDefault(false)
    }
}

// MARK: As ordens abertas

class LinhaDaOrdem(j: JSONObject) {
    val id: String = j.getString("id")
    val rede: String = j.getString("rede")
    val redeNome: String = j.getString("redeNome")
    val redeCoingecko: String = j.getString("redeCoingecko")
    val vende: AtivoDaTroca? = j.optJSONObject("vende")?.let(::AtivoDaTroca)
    val titulo: String = j.getString("titulo")
    val tituloCurto: String = j.getString("tituloCurto")
    val detalhe: String = j.getString("detalhe")
    val porNoMinimo: String = j.getString("porNoMinimo")
    val preco: String? = j.opcional("preco")
    val precoCurto: String? = j.opcional("precoCurto")
    /** Quando vence, em milissegundos; nil e ate cancelar. */
    val vence: Long? = j.duplo("vence")?.toLong()
    val fracao: Double? = j.duplo("fracao")
    val recebido: String? = j.opcional("recebido")
    val falta: String? = j.opcional("falta")
    val criada: Long? = j.duplo("criada")?.toLong()
    val onde: String = j.getString("onde")
    val podeCancelar: Boolean = j.getBoolean("podeCancelar")
    val explicacao: String = j.getString("explicacao")
}

class OrdemTerminada(j: JSONObject) {
    val id: String = j.getString("id")
    val vende: AtivoDaTroca? = j.optJSONObject("vende")?.let(::AtivoDaTroca)
    val titulo: String = j.getString("titulo")
    val resultado: String = j.getString("resultado")
    val executada: Boolean = j.getBoolean("executada")
    val fracao: Double = j.getDouble("fracao")
}

class RetratoDasOrdens(j: JSONObject) {
    val carregando: Boolean = j.getBoolean("carregando")
    val falha: String? = j.opcional("falha")
    val ordens: List<LinhaDaOrdem> = j.getJSONArray("ordens").objetos().map(::LinhaDaOrdem)
    val terminadas: List<OrdemTerminada> = j.getJSONArray("terminadas").objetos().map(::OrdemTerminada)
    val semResposta: String? = j.opcional("semResposta")
    val podeAssinar: Boolean = j.getBoolean("podeAssinar")
}

/** O livro das ordens abertas, lido pelo nucleo; uma ordem criada ou cancelada pede leitura nova. */
object ControleDasOrdens {
    var retrato by mutableStateOf<RetratoDasOrdens?>(null)
        private set
    /** Sobe quando uma ordem foi criada ou cancelada: a lista na tela rele na hora. */
    var pedido by mutableIntStateOf(0)
        private set

    suspend fun ler(inicial: Boolean) {
        runCatching { retrato = RetratoDasOrdens(Api.objeto("ordens.lista", JSONObject().put("inicial", inicial))) }
    }

    /** Sem ir a rede: so o que o livro ja tem (a ordem com cancelamento enviado sai na hora). */
    suspend fun mostrar() {
        runCatching { retrato = RetratoDasOrdens(Api.objeto("ordens.retrato")) }
    }

    fun reler() { pedido++ }
}
