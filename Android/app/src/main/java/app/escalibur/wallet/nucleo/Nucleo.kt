package app.escalibur.wallet.nucleo

/**
 * A ponte com o nucleo em Swift (o mesmo do iOS), carregado de libEscaliburAndroid.so.
 *
 * `chamar` recebe o nome de um metodo e os dados em JSON, e devolve JSON. Nunca recebe nem
 * devolve segredo: frase, PIN e chave passam por metodos proprios, em ByteBuffer direto.
 * Chame sempre fora da thread da interface (o nucleo pode ir a rede).
 */
object Nucleo {
    init {
        System.loadLibrary("c++_shared")
        System.loadLibrary("EscaliburAndroid")
    }

    @JvmStatic
    external fun chamar(metodo: String, corpo: String): String
}
