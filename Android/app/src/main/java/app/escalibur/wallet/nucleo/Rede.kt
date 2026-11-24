package app.escalibur.wallet.nucleo

import app.escalibur.wallet.BuildConfig
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.InetAddress
import java.net.NoRouteToHostException
import java.net.Socket
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLException
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * O transporte de rede do nucleo em Swift: o HttpsURLConnection do sistema, so com TLS 1.2 e 1.3.
 *
 * Quem decide o que sai do aparelho e o HTTPClient do nucleo (hosts, portas, caminhos, tamanho,
 * redirecionamento). Aqui so se leva e traz, sem cache, sem cookie e sem seguir redirecionamento,
 * e a regra de host, porta e caminho do HTTPClient vale de novo na saida (`permitido`).
 * Chamado pelo nucleo (JNI), de threads dele, nunca da thread da interface. Nenhum outro arquivo
 * do Kotlin abre conexao nem chama este (o verificar.sh confere).
 */
object Rede {
    private const val SEM_REDE = -1
    private const val PRAZO = -2
    private const val TLS = -3
    private const val CANCELADO = -4
    private const val RECUSADO = -5
    private const val OUTRA = -6
    private const val SEM_CONEXAO = -7

    private val abertas = ConcurrentHashMap<Long, HttpsURLConnection>()
    private val canceladas = ConcurrentHashMap.newKeySet<Long>()
    private val fabrica: SSLSocketFactory by lazy { SoTlsModerno(HttpsURLConnection.getDefaultSSLSocketFactory()) }

    /**
     * As portas alem da 443, iguais as do HTTPClient.extraPorts (o verificar.sh confere): a Ripple atende na 51234.
     * Uma funcao, e nao um mapa: nada a muda em tempo de execucao.
     */
    private fun portaExtra(host: String): Int? = when (host) {
        "s1.ripple.com" -> 51234
        "s2.ripple.com" -> 51234
        else -> null
    }

    /** Os caminhos, iguais aos do HTTPClient.pathPrefixes (o verificar.sh confere): do GitHub, so as logos da Trust Wallet. */
    private fun caminhoDo(host: String): String? = when (host) {
        "raw.githubusercontent.com" -> "/trustwallet/assets/"
        else -> null
    }

    /**
     * Devolve o status (ou o codigo da falha, negativo) e o tamanho dos cabecalhos em 4 bytes
     * cada, big-endian; os cabecalhos como "nome\u0000valor\u0000"; e o corpo, lido ate `limite`.
     */
    @JvmStatic
    fun requisitar(
        id: Long, metodo: String, endereco: String, cabecalhos: Array<String>, corpo: ByteArray?,
        prazoMs: Int, prazoTotalMs: Int, limite: Int,
    ): ByteArray {
        val url = runCatching { URL(endereco) }.getOrNull()
        if (url == null || !permitido(url)) return falha(RECUSADO)
        val inicio = System.nanoTime()
        val conexao = try {
            url.openConnection() as HttpsURLConnection
        } catch (e: IOException) {
            return falha(codigo(e))
        }
        abertas[id] = conexao
        // Conexao lida ate o fim volta ao pool do sistema e a proxima requisicao ao mesmo host nao
        // repete o handshake. Qualquer outro desfecho fecha o socket.
        var reaproveitar = false
        try {
            if (canceladas.remove(id)) return falha(CANCELADO)
            conexao.sslSocketFactory = fabrica
            conexao.instanceFollowRedirects = false
            conexao.useCaches = false
            conexao.allowUserInteraction = false
            conexao.connectTimeout = prazoMs
            conexao.readTimeout = prazoMs
            conexao.requestMethod = metodo
            for (i in 0 until cabecalhos.size - 1 step 2) conexao.setRequestProperty(cabecalhos[i], cabecalhos[i + 1])
            if (corpo != null) {
                conexao.doOutput = true
                conexao.setFixedLengthStreamingMode(corpo.size)
                conexao.outputStream.use { it.write(corpo) }
            }
            val status = conexao.responseCode
            if (status < 0) return falha(OUTRA)
            val lista = ByteArrayOutputStream()
            for ((nome, valores) in conexao.headerFields) {
                if (nome == null) continue
                lista.write(nome.toByteArray()); lista.write(0)
                lista.write(valores.joinToString(", ").toByteArray()); lista.write(0)
            }
            // Fora de 2xx o nucleo recusa pelo status, e o corpo nao interessa. Corpo maior que o
            // limite anunciado tambem nao e lido: o nucleo recusa pelo Content-Length.
            val lerCorpo = status in 200..299 && conexao.contentLengthLong <= limite
            val conteudo = if (lerCorpo) ler(conexao, limite, inicio, prazoTotalMs) else ByteArray(0)
            reaproveitar = lerCorpo && conteudo.size < limite
            return ByteBuffer.allocate(8 + lista.size() + conteudo.size)
                .putInt(status).putInt(lista.size()).put(lista.toByteArray()).put(conteudo).array()
        } catch (e: IOException) {
            return falha(if (canceladas.contains(id)) CANCELADO else codigo(e))
        } finally {
            if (BuildConfig.DEBUG) android.util.Log.d("EscaliburRede", "${url.host} ${(System.nanoTime() - inicio) / 1_000_000} ms")
            abertas.remove(id)
            if (canceladas.remove(id) || !reaproveitar) conexao.disconnect()
        }
    }

    /**
     * A regra do HTTPClient (`HTTPClient.permits`), de novo na saida e com a leitura do endereco que o
     * proprio Java faz: https, host do hosts.lock (HostsPermitidos.kt, em minusculas), a porta 443 (ou
     * a do host) e, quando o host tem, so o caminho dele, sem `..` nem escape; e nenhum usuario ou
     * senha no endereco. O nucleo ja confere antes de chamar; esta trava vale para o que chegar aqui
     * por outro caminho.
     */
    private fun permitido(url: URL): Boolean {
        if (url.protocol != "https" || url.userInfo != null) return false
        val host = (url.host ?: return false).lowercase()
        val porta = url.port
        // So no build de depuracao: os hosts do TesteTLS do nucleo, fora da lista de proposito.
        if (BuildConfig.DEBUG && doTesteTls(host, porta)) return true
        if (!HostsPermitidos.contem(host)) return false
        if (porta != -1 && porta != 443 && porta != portaExtra(host)) return false
        val caminho = caminhoDo(host) ?: return true
        return url.path.startsWith(caminho) && ".." !in url.path && '%' !in url.path
    }

    /** Os hosts do badssl.com do TesteTLS.swift, cada um com a porta dele. So vale com BuildConfig.DEBUG. */
    private fun doTesteTls(host: String, porta: Int): Boolean = when (host) {
        "badssl.com", "expired.badssl.com", "self-signed.badssl.com", "wrong.host.badssl.com",
        "untrusted-root.badssl.com", "revoked.badssl.com" -> porta == -1
        "tls-v1-0.badssl.com" -> porta == 1010
        "tls-v1-1.badssl.com" -> porta == 1011
        "tls-v1-2.badssl.com" -> porta == 1012
        else -> false
    }

    /** Fecha a conexao no meio: a thread que le recebe IOException e devolve CANCELADO. */
    @JvmStatic
    fun cancelar(id: Long) {
        canceladas.add(id)
        abertas[id]?.disconnect()
    }

    private fun ler(conexao: HttpsURLConnection, limite: Int, inicio: Long, prazoTotalMs: Int): ByteArray {
        val saida = ByteArrayOutputStream()
        val pedaco = ByteArray(16 * 1024)
        conexao.inputStream.use { entrada ->
            while (saida.size() < limite) {
                if ((System.nanoTime() - inicio) / 1_000_000 > prazoTotalMs) throw SocketTimeoutException("prazo total")
                val lidos = entrada.read(pedaco, 0, minOf(pedaco.size, limite - saida.size()))
                if (lidos < 0) break
                saida.write(pedaco, 0, lidos)
            }
        }
        return saida.toByteArray()
    }

    private fun codigo(e: IOException): Int = when (e) {
        is UnknownHostException, is NoRouteToHostException -> SEM_REDE
        is SocketTimeoutException -> PRAZO
        is SSLException -> TLS
        is ConnectException -> SEM_CONEXAO
        is InterruptedIOException -> PRAZO
        else -> if (e.cause is java.security.cert.CertificateException) TLS else OUTRA
    }

    private fun falha(codigo: Int): ByteArray = ByteBuffer.allocate(8).putInt(codigo).putInt(0).array()

    /** Toda conexao sai so com TLS 1.3 e 1.2, mesmo que o servidor ofereca versao mais velha. */
    private class SoTlsModerno(private val base: SSLSocketFactory) : SSLSocketFactory() {
        override fun getDefaultCipherSuites(): Array<String> = base.defaultCipherSuites
        override fun getSupportedCipherSuites(): Array<String> = base.supportedCipherSuites
        override fun createSocket(): Socket = prender(base.createSocket())
        override fun createSocket(s: Socket, host: String, port: Int, autoClose: Boolean): Socket = prender(base.createSocket(s, host, port, autoClose))
        override fun createSocket(host: String, port: Int): Socket = prender(base.createSocket(host, port))
        override fun createSocket(host: String, port: Int, localHost: InetAddress, localPort: Int): Socket =
            prender(base.createSocket(host, port, localHost, localPort))
        override fun createSocket(host: InetAddress, port: Int): Socket = prender(base.createSocket(host, port))
        override fun createSocket(address: InetAddress, port: Int, localAddress: InetAddress, localPort: Int): Socket =
            prender(base.createSocket(address, port, localAddress, localPort))

        private fun prender(socket: Socket): Socket {
            val ssl = socket as? SSLSocket ?: throw SSLException("conexao sem TLS")
            val versoes = ssl.supportedProtocols.filter { it == "TLSv1.3" || it == "TLSv1.2" }
            if (versoes.isEmpty()) throw SSLException("sem TLS 1.2")
            ssl.enabledProtocols = versoes.toTypedArray()
            return ssl
        }
    }
}
