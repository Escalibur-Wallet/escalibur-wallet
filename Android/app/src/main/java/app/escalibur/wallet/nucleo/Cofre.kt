package app.escalibur.wallet.nucleo

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG
import android.hardware.biometrics.BiometricPrompt
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.system.Os
import android.system.OsConstants
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.security.keystore.UserNotAuthenticatedException
import java.io.File
import java.lang.ref.WeakReference
import java.nio.ByteBuffer
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.spec.MGF1ParameterSpec
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource

/**
 * O chaveiro e o Secure Enclave do Android: o Keystore, para o cofre do nucleo em Swift (o mesmo
 * RootKeyVault do iOS, por cima dos protocolos SecretStore e KeyWrapper).
 *
 * Armazenamento: cada item e um arquivo na pasta sem backup do app, cifrado em AES-GCM por uma
 * chave do Keystore que nunca sai do hardware e so funciona com o aparelho desbloqueado. O nome da
 * conta e a protecao entram no AAD (um item nao vira outro). Item com senha de aplicativo leva a
 * senha no AAD tambem, mas isso nao protege nada: o KeyMint entrega o claro antes de conferir a tag.
 * Quem segura o PIN e a camada de baixo, a chave do slot.
 *
 * Chaves de cada slot:
 * - aparelho: AES-GCM no Keystore.
 * - PIN (formato 2): uma chave HMAC no Keystore (StrongBox quando o aparelho tem). A senha derivada
 *   do PIN passa por ela, e o resultado vira a chave AES do embrulho: sem o hardware deste aparelho
 *   e a senha certa, nada abre, e cada chute passa por este hardware, um de cada vez. O formato 1
 *   (a senha so no AAD) so existe em cofres de teste do emulador, criados antes de 22/10/2026; abre
 *   e nunca mais e gravado.
 * - biometria: RSA-2048 no Keystore, que so decifra depois de uma biometria forte (classe 3) para
 *   aquela operacao. Embrulhar usa a chave publica e nao pede nada. As que seguem o cadastro
 *   morrem quando uma digital ou rosto e cadastrado ou tirado.
 *
 * Chamado pelo nucleo (JNI), de threads dele, nunca da thread da interface: a biometria bloqueia
 * quem chamou ate a decisao.
 */
object Cofre {
    // Os codigos que o nucleo le (Kit/Sources/Android/EscaliburAndroid/Cofre.swift).
    private const val OK = 0
    private const val AUSENTE = 1
    private const val SENHA = 2
    private const val FALHA = 3
    private const val DUPLICADO = 4
    private const val SEM_BLOQUEIO = 5
    private const val CANCELADO = 6
    private const val SEM_CHAVE = 7
    private const val INDISPONIVEL = 8
    /** O celular bloqueou antes de o Keystore usar a chave: nada foi conferido (o B7 do iOS). */
    private const val BLOQUEADO = 9

    private const val PREFIXO = "app.escalibur.wallet."
    private const val CHAVE_DO_ARMAZENAMENTO = PREFIXO + "cofre"
    private const val CHAVE_DA_VIGIA = PREFIXO + "vigia"
    private const val VERSAO: Byte = 1
    /** O embrulho dos slots do PIN com a senha na chave (HMAC no Keystore). */
    private const val VERSAO_DO_PIN: Byte = 2

    private lateinit var app: Context
    /** O contexto do app, para quem precisa dele fora de uma tela (a conferencia de integridade antes da credencial). */
    internal val contexto: Context get() = app
    private lateinit var pasta: File
    @Volatile private var atividade: WeakReference<Activity>? = null
    private val aleatorio = SecureRandom()
    private val trava = Any()

    /** Na abertura do app, antes de o nucleo ser carregado. */
    fun iniciar(contexto: Context) {
        app = contexto.applicationContext
        pasta = File(app.noBackupFilesDir, "cofre").apply { mkdirs() }
    }

    /** A sonda do StrongBox gera uma chave: so no processo da interface (a MainActivity chama), fora da thread dela, antes
     * de a tela do PIN perguntar. Os processos de fundo (o trabalho de hora em hora, os receivers) nao sondam. */
    fun aquecerStrongBox() {
        if (sondaDoStrongBox[0] == null) Thread { temStrongBox() }.apply { isDaemon = true }.start()
    }

    /** A atividade em primeiro plano, onde a biometria aparece. */
    fun primeiroPlano(activity: Activity?) {
        atividade = activity?.let { WeakReference(it) }
    }

    /** O pedido de biometria na tela agora, com o sinal de cancelar e a espera dele. */
    @Volatile private var pedidoAtual: Pair<CancellationSignal, CountDownLatch>? = null

    /**
     * O app saiu da frente: o pedido de biometria cai na hora, sem esperar a resposta do sistema, que
     * chega pela thread principal (auditoria de 03/11/2026: com o Super Security, o app congelava).
     */
    fun cancelarBiometria() {
        pedidoAtual?.let { (cancelar, pronto) ->
            cancelar.cancel()
            pronto.countDown()
        }
    }

    private val keyStore: KeyStore by lazy { KeyStore.getInstance("AndroidKeyStore").apply { load(null) } }

    // ---- Armazenamento (SecretStore) ----

    /** [status] e, com OK, o conteudo. */
    @JvmStatic
    fun ler(conta: String, senha: ByteArray?): ByteArray = try {
        val arquivo = arquivo(conta)
        if (!arquivo.exists()) byteArrayOf(AUSENTE.toByte())
        else {
            val bruto = arquivo.readBytes()
            if (bruto.size < 2 + 12 + 16 || bruto[0] != VERSAO) byteArrayOf(FALHA.toByte())
            else {
                val protecao = bruto[1].toInt()
                if (protecao == PROTECAO_SENHA_NO_AAD && senha == null) byteArrayOf(SENHA.toByte())
                else {
                    val cifra = Cipher.getInstance("AES/GCM/NoPadding")
                    cifra.init(Cipher.DECRYPT_MODE, chaveDoArmazenamento(paraGravar = false), GCMParameterSpec(128, bruto, 2, 12))
                    aadDoItem(conta, protecao, if (protecao == PROTECAO_SENHA_NO_AAD) senha else null)
                        .let { aad -> try { cifra.updateAAD(aad) } finally { aad.fill(0) } }
                    try {
                        val claro = cifra.doFinal(bruto, 14, bruto.size - 14)
                        try {
                            if (protecao == PROTECAO_SENHA_NO_AAD) migrar(conta, bruto, claro)
                            byteArrayOf(OK.toByte()) + claro
                        } finally { claro.fill(0) }
                    } catch (e: AEADBadTagException) {
                        // So o item com senha responde "senha": num item comum, a tag que nao confere e
                        // arquivo estragado, nunca PIN errado.
                        byteArrayOf((if (protecao == PROTECAO_SENHA_NO_AAD) SENHA else FALHA).toByte())
                    }
                }
            }
        }
    } catch (e: android.security.keystore.UserNotAuthenticatedException) {
        // A chave do armazenamento so funciona com o celular desbloqueado: travou no meio, e nada foi
        // conferido. Antes virava FALHA e a tentativa do PIN ficava gasta (revisao de seguranca do
        // Android de 26/10/2026).
        byteArrayOf(BLOQUEADO.toByte())
    } catch (e: Exception) {
        byteArrayOf(FALHA.toByte())
    } finally {
        senha?.fill(0)
    }

    /** `novo`: falha se ja existe (add); senao, so troca o que existe (update). */
    @JvmStatic
    fun gravar(conta: String, dados: ByteArray, protecao: Int, senha: ByteArray?, novo: Boolean): Int = try {
        synchronized(trava) {
            val arquivo = arquivo(conta)
            when {
                novo && arquivo.exists() -> DUPLICADO
                !novo && !arquivo.exists() -> AUSENTE
                novo && !aparelhoComBloqueio() -> SEM_BLOQUEIO
                else -> {
                    // Na troca, a protecao continua a do item gravado. O item com senha de aplicativo
                    // nasce, e e trocado, no formato sem a senha no AAD (ver PROTECAO_DO_PIN).
                    val pedida = if (novo) protecao else arquivo.readBytes().getOrNull(1)?.toInt() ?: return FALHA
                    val protecaoFinal = if (pedida == PROTECAO_SENHA_NO_AAD || pedida == PROTECAO_DO_PIN) PROTECAO_DO_PIN else pedida
                    gravarAtomico(arquivo, cifrar(conta, protecaoFinal, dados))
                    OK
                }
            }
        }
    } catch (e: Exception) {
        FALHA
    } finally {
        dados.fill(0)
        senha?.fill(0)
    }

    @JvmStatic
    fun apagar(conta: String): Int = try {
        val arquivo = arquivo(conta)
        if (!arquivo.exists() || arquivo.delete()) OK else FALHA
    } catch (e: Exception) {
        FALHA
    }

    @JvmStatic
    fun apagarTudo(): Int = try {
        synchronized(trava) {
            pasta.listFiles()?.forEach { if (it.name.endsWith(".item")) it.delete() }
            OK
        }
    } catch (e: Exception) {
        FALHA
    }

    /** OK (existe), AUSENTE, ou FALHA (nao se sabe). */
    @JvmStatic
    fun sondar(conta: String): Int = try {
        if (arquivo(conta).exists()) OK else AUSENTE
    } catch (e: Exception) {
        FALHA
    }

    private fun arquivo(conta: String): File {
        val nome = MessageDigest.getInstance("SHA-256").digest(("escalibur-wallet/android/v1/conta\u0000" + conta).toByteArray())
        return File(pasta, nome.joinToString("") { "%02x".format(it) } + ".item")
    }

    /**
     * O item com senha de aplicativo (o slot do PIN, `rk.pin`). No formato antigo (1) a senha entrava no
     * AAD do AES-GCM da chave de armazenamento, que mora no TEE: quem tem root testava cada PIN pedindo
     * ao TEE essa decifragem, em 1 a 3 ms, sem passar pela chave HMAC do slot (StrongBox quando ha), que
     * e o que deve conferir o PIN, um de cada vez (revisao de seguranca do Android de 26/10/2026). No
     * formato 2 a senha nao entra: o PIN errado passa por aqui e e recusado pela chave do slot. A senha
     * tambem deixa de vir do nucleo: so o item antigo a pede, e abrir com a certa o passa ao 2.
     */
    private const val PROTECAO_SENHA_NO_AAD = 1
    private const val PROTECAO_DO_PIN = 2

    private fun cifrar(conta: String, protecao: Int, dados: ByteArray): ByteArray {
        val cifra = Cipher.getInstance("AES/GCM/NoPadding")
        cifra.init(Cipher.ENCRYPT_MODE, chaveDoArmazenamento(paraGravar = true))
        aadDoItem(conta, protecao, null).let { aad -> try { cifra.updateAAD(aad) } finally { aad.fill(0) } }
        val cifrado = cifra.doFinal(dados)
        return byteArrayOf(VERSAO, protecao.toByte()) + cifra.iv + cifrado
    }

    /** O item antigo, aberto com a senha certa, passa ao formato 2 na hora, numa troca atomica. So se o
     * arquivo ainda e o que foi lido; falhando, fica no antigo e abre igual na proxima. */
    private fun migrar(conta: String, lido: ByteArray, claro: ByteArray) {
        try {
            synchronized(trava) {
                val arquivo = arquivo(conta)
                if (arquivo.exists() && arquivo.readBytes().contentEquals(lido)) gravarAtomico(arquivo, cifrar(conta, PROTECAO_DO_PIN, claro))
            }
        } catch (e: Exception) {
        }
    }

    private fun aadDoItem(conta: String, protecao: Int, senha: ByteArray?): ByteArray {
        val base = ("escalibur-wallet/android/v1/item\u0000" + conta + "\u0000").toByteArray() + byteArrayOf(protecao.toByte())
        return if (protecao == 1 && senha != null) base + senha else base
    }

    /**
     * Grava e troca de uma vez, e so volta depois de a troca estar no disco: o fsync da pasta leva o
     * rename junto. Sem ele, no f2fs, um reinicio forcado logo depois de um PIN errado devolvia o
     * contador de tentativas antigo.
     */
    private fun gravarAtomico(arquivo: File, corpo: ByteArray) {
        val temporario = File(pasta, arquivo.name + ".novo")
        temporario.outputStream().use { saida ->
            saida.write(corpo)
            saida.fd.sync()
        }
        if (!temporario.renameTo(arquivo)) {
            temporario.delete()
            throw java.io.IOException("troca do arquivo")
        }
        val descritor = Os.open(pasta.absolutePath, OsConstants.O_RDONLY, 0)
        try { Os.fsync(descritor) } finally { Os.close(descritor) }
    }

    /**
     * A chave que cifra os arquivos do cofre. So nasce com o cofre vazio, na primeira gravacao: com
     * algum item gravado, a chave que nao vem (ausente, ou o Keystore que nao respondeu) recusa, e
     * nunca e trocada por outra. Antes ela era recriada em silencio, e dali em diante nenhum arquivo
     * abria: o PIN certo parecia errado e as carteiras do aparelho se perdiam (caca de bugs de
     * 25/10/2026). Sem a chave, o cofre fica indisponivel, e as palavras no papel continuam valendo.
     */
    private fun chaveDoArmazenamento(paraGravar: Boolean): SecretKey {
        (keyStore.getKey(CHAVE_DO_ARMAZENAMENTO, null) as? SecretKey)?.let { return it }
        if (!paraGravar || keyStore.containsAlias(CHAVE_DO_ARMAZENAMENTO) || cofreTemItens()) throw Recusa(INDISPONIVEL)
        // Fora do StrongBox: cada leitura e gravacao passa por ela, e o TEE e bem mais rapido.
        return gerarAes(CHAVE_DO_ARMAZENAMENTO, strongBox = false)
    }

    /** Algum item gravado na pasta do cofre? Sem conseguir listar, responde que sim. */
    private fun cofreTemItens(): Boolean = pasta.listFiles()?.any { it.name.endsWith(".item") } ?: true

    /** Sem bloqueio de tela, o Keystore fica destravado para sempre: nenhuma chave abre (no iOS,
     * tirar o codigo apaga as carteiras). O caminho volta quando o bloqueio volta. */
    fun aparelhoComBloqueio(): Boolean = app.getSystemService(KeyguardManager::class.java).isDeviceSecure

    /**
     * 1 se o aparelho tem StrongBox, o chip de seguranca separado, e ele aceita a chave do PIN. Sem ele, a chave que
     * confere o PIN fica no TEE do processador, e com root no aparelho destravado um PIN de 4 digitos cai em segundos: o
     * PIN passa a ter 6 (decisao do dono, 07/11/2026). Pela sonda, e nao so pela feature anunciada: a chave do PIN cai no
     * TEE quando o StrongBox recusa (`gerarHmac`), e o aparelho que anuncia e recusa liberava os 4 digitos (revisao dos
     * pendentes de 07/11/2026). A sonda gera uma HMAC descartavel so no StrongBox, confere o nivel (Android 12 em diante)
     * e a apaga; o resultado fica para o processo.
     */
    @JvmStatic
    fun temStrongBox(): Int = synchronized(sondaDoStrongBox) {
        sondaDoStrongBox[0]?.let { return it }
        val resultado = try {
            if (!app.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_STRONGBOX_KEYSTORE)) 0
            else {
                val alias = PREFIXO + "sonda.strongbox"
                keyStore.deleteEntry(alias)
                val gerador = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore")
                gerador.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                    .setKeySize(256).setDigests(KeyProperties.DIGEST_SHA256).setIsStrongBoxBacked(true).build())
                val chave = gerador.generateKey()
                val noChip = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                    val info = javax.crypto.SecretKeyFactory.getInstance(chave.algorithm, "AndroidKeyStore")
                        .getKeySpec(chave, KeyInfo::class.java) as KeyInfo
                    info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
                } else true
                keyStore.deleteEntry(alias)
                if (noChip) 1 else 0
            }
        } catch (e: Exception) {
            runCatching { keyStore.deleteEntry(PREFIXO + "sonda.strongbox") }
            0
        }
        sondaDoStrongBox[0] = resultado
        resultado
    }
    private val sondaDoStrongBox = arrayOfNulls<Int>(1)

    /** Para a interface: o que a sonda ja respondeu, sem esperar por ela (a geracao no StrongBox demora em alguns aparelhos,
     * e a tela nao pode parar). Null enquanto ela roda: a opcao de 4 digitos fica escondida. Quem decide e o nucleo. */
    fun strongBoxConhecido(): Int? = sondaDoStrongBox[0]

    // ---- Chaves de cada slot (KeyWrapper) ----

    private fun usaBiometria(slot: String) = slot == "kbio" || slot == "kand.bio" || slot == "kand.qualquer"
    private fun usaSenha(slot: String) = slot == "kpin" || slot == "kpin.novo" || slot == "kand.pin.a" || slot == "kand.pin.b"
    private fun segueCadastro(slot: String) = slot == "kbio" || slot == "kand.bio"
    private fun alias(slot: String) = PREFIXO + slot

    @JvmStatic
    fun criarChave(slot: String): Int = try {
        if (!aparelhoComBloqueio()) SEM_BLOQUEIO
        else {
            keyStore.deleteEntry(alias(slot))
            when {
                usaBiometria(slot) -> gerarRsa(alias(slot), segueCadastro(slot))
                usaSenha(slot) -> gerarHmac(alias(slot))
                else -> gerarAes(alias(slot), strongBox = true)
            }
            OK
        }
    } catch (e: Exception) {
        INDISPONIVEL
    }

    /** OK (existe), AUSENTE, ou FALHA (nao se sabe). A chave de biometria que o cadastro novo
     * invalidou conta como ausente, mas nao e apagada aqui: ha atualizacao de fabricante que lanca
     * a invalidacao sem ter havido cadastro novo, e apagar era perda sem volta (no modo "Bloquear as
     * carteiras", o cofre inteiro). Quem decide e o cofre, que apaga o slot pela politica dele
     * (revisao de seguranca do Android de 26/10/2026). */
    @JvmStatic
    fun sondarChave(slot: String): Int = try {
        if (!keyStore.containsAlias(alias(slot))) AUSENTE
        else if (usaBiometria(slot) && invalidada(alias(slot))) AUSENTE
        else OK
    } catch (e: Exception) {
        FALHA
    }

    @JvmStatic
    fun apagarChave(slot: String) {
        try { keyStore.deleteEntry(alias(slot)) } catch (e: Exception) {}
    }

    // ---- Embrulho (KeyWrapper) ----
    //
    // Nos slots de biometria e do PIN, so o que o Keystore faz passa por aqui: a RSA que abre a chave AES do
    // embrulho (depois da biometria) e o HMAC da senha do PIN. O AES-GCM e o HKDF sao feitos no nucleo
    // (Kit/Sources/Android/EscaliburAndroid/Cofre.swift), sobre buffers que ele zera, e a chave raiz nunca entra
    // no Java: aqui, o SecretKeySpec e a Conscrypt guardavam copias dela e das chaves do embrulho no heap
    // (auditoria das chaves de 06/11/2026). O que o Keystore devolve sai pelo [status][segredo], que o nucleo
    // copia e zera no lugar. Os formatos gravados nao mudaram.

    /** [status] e, com OK, o embrulho. So o slot do aparelho: o AES-GCM e do Keystore, no hardware. */
    @JvmStatic
    fun embrulhar(slot: String, segredo: ByteArray, senha: ByteArray?): ByteArray = try {
        if (usaBiometria(slot) || usaSenha(slot) || senha != null) throw Recusa(FALHA)
        val chave = keyStore.getKey(alias(slot), null) as? SecretKey ?: throw SemChave()
        val aes = Cipher.getInstance("AES/GCM/NoPadding")
        aes.init(Cipher.ENCRYPT_MODE, chave)
        aes.updateAAD(aadDoEmbrulho(slot, null))
        val cifrado = aes.doFinal(segredo)
        byteArrayOf(OK.toByte(), VERSAO) + aes.iv + cifrado
    } catch (e: SemChave) {
        byteArrayOf(SEM_CHAVE.toByte())
    } catch (e: Exception) {
        byteArrayOf(FALHA.toByte())
    } finally {
        segredo.fill(0)
        senha?.fill(0)
    }

    /** [status] e, com OK, o segredo. So o slot do aparelho e o formato 1 dos slots do PIN (cofres de teste do
     * emulador, a senha so no AAD): os dois sao AES-GCM do Keystore, no hardware. */
    @JvmStatic
    fun desembrulhar(slot: String, blob: ByteArray, senha: ByteArray?, motivo: String?): ByteArray = try {
        if (usaBiometria(slot) || usaSenha(slot) != (senha != null)) throw Recusa(FALHA)
        if (!aparelhoComBloqueio()) throw Recusa(INDISPONIVEL)
        if (blob.size < 1 + 12 + 16 || blob[0] != VERSAO) throw Recusa(FALHA)
        val chave = keyStore.getKey(alias(slot), null) as? SecretKey ?: throw Recusa(SEM_CHAVE)
        val aes = Cipher.getInstance("AES/GCM/NoPadding")
        aes.init(Cipher.DECRYPT_MODE, chave, GCMParameterSpec(128, blob, 1, 12))
        aadDoEmbrulho(slot, senha).let { aad -> try { aes.updateAAD(aad) } finally { aad.fill(0) } }
        val claro = try {
            aes.doFinal(blob, 13, blob.size - 13)
        } catch (e: AEADBadTagException) {
            throw Recusa(if (usaSenha(slot)) SENHA else FALHA)
        }
        try { byteArrayOf(OK.toByte()) + claro } finally { claro.fill(0) }
    } catch (e: Recusa) {
        byteArrayOf(e.codigo.toByte())
    } catch (e: SemChave) {
        byteArrayOf(SEM_CHAVE.toByte())
    } catch (e: Exception) {
        byteArrayOf(FALHA.toByte())
    } finally {
        senha?.fill(0)
    }

    /** [status] e, com OK, a chave publica RSA (X.509) do slot de biometria: o nucleo embrulha com ela, sem pedir nada. */
    @JvmStatic
    fun publica(slot: String): ByteArray = try {
        if (!usaBiometria(slot)) throw Recusa(FALHA)
        val publica = keyStore.getCertificate(alias(slot))?.publicKey ?: throw SemChave()
        byteArrayOf(OK.toByte()) + publica.encoded
    } catch (e: Recusa) {
        byteArrayOf(e.codigo.toByte())
    } catch (e: SemChave) {
        byteArrayOf(SEM_CHAVE.toByte())
    } catch (e: Exception) {
        byteArrayOf(FALHA.toByte())
    }

    /** [status] e, com OK, a chave AES de um embrulho de biometria, que a RSA do slot abriu depois da
     * biometria. Sem `motivo`, nenhuma interface (e recusa). */
    @JvmStatic
    fun abrirChave(slot: String, chaveCifrada: ByteArray, motivo: String?): ByteArray = try {
        val chave = decifrarComBiometria(slot, chaveCifrada, motivo)
        try { byteArrayOf(OK.toByte()) + chave } finally { chave.fill(0) }
    } catch (e: Recusa) {
        byteArrayOf(e.codigo.toByte())
    } catch (e: Exception) {
        byteArrayOf(FALHA.toByte())
    }

    /**
     * Abre a chave do embrulho pela biometria e, na mesma autenticacao, a da vigia do modo reforcado.
     * Devolve [status][vigia][chave 32][chave da vigia 32, so se abriu]; vigia 0 abriu, 1 a chave nao
     * existe mais, 2 nao se sabe. Sem a chave cifrada da vigia (o nucleo nao leu o embrulho dela), 2.
     */
    @JvmStatic
    fun abrirChaveVigiando(slot: String, chaveCifrada: ByteArray, motivo: String, slotVigia: String, chaveCifradaDaVigia: ByteArray?): ByteArray = try {
        val chave = decifrarComBiometria(slot, chaveCifrada, motivo)
        try {
            val (estado, daVigia) = decifrarVigia(slotVigia, chaveCifradaDaVigia)
            try {
                // Um array so, do tamanho certo: somar com `+` criava arrays intermediarios com as chaves.
                val saida = ByteArray(2 + chave.size + daVigia.size)
                saida[0] = OK.toByte()
                saida[1] = estado.toByte()
                chave.copyInto(saida, 2)
                daVigia.copyInto(saida, 2 + chave.size)
                saida
            } finally {
                daVigia.fill(0)
            }
        } finally {
            chave.fill(0)
        }
    } catch (e: Recusa) {
        byteArrayOf(e.codigo.toByte())
    } catch (e: Exception) {
        byteArrayOf(FALHA.toByte())
    } finally {
        chaveCifradaDaVigia?.fill(0)
    }

    /**
     * [status] e, com OK, a semente do embrulho do PIN: a senha passa pela chave HMAC do slot, que nunca sai
     * do hardware. O nucleo estende com o sal do embrulho (HKDF-SHA256): quem copia o arquivo, ou le a
     * memoria do Keystore, so testa PINs neste aparelho, um de cada vez. `abrindo` pede o bloqueio de tela,
     * como o desembrulho sempre pediu.
     */
    @JvmStatic
    fun semente(slot: String, senha: ByteArray, abrindo: Boolean): ByteArray = try {
        if (!usaSenha(slot)) throw Recusa(FALHA)
        if (abrindo && !aparelhoComBloqueio()) throw Recusa(INDISPONIVEL)
        val hmac = keyStore.getKey(alias(slot), null) as? SecretKey ?: throw SemChave()
        // A chave do slot ainda e a AES do formato 1: este embrulho nao e dela. Pelo algoritmo, e nao
        // pela excecao: o celular bloqueado tambem lanca InvalidKeyException.
        if (!hmac.algorithm.equals("HmacSHA256", ignoreCase = true)) throw SemChave()
        val entrada = "escalibur-wallet/android/v2/pin\u0000$slot\u0000".toByteArray() + senha
        val semente = try {
            Mac.getInstance("HmacSHA256").run { init(hmac); doFinal(entrada) }
        } catch (e: android.security.keystore.UserNotAuthenticatedException) {
            throw Recusa(BLOQUEADO)
        } finally {
            entrada.fill(0)
        }
        try { byteArrayOf(OK.toByte()) + semente } finally { semente.fill(0) }
    } catch (e: Recusa) {
        byteArrayOf(e.codigo.toByte())
    } catch (e: SemChave) {
        byteArrayOf(SEM_CHAVE.toByte())
    } catch (e: Exception) {
        byteArrayOf(FALHA.toByte())
    } finally {
        senha.fill(0)
    }

    private fun decifrarComBiometria(slot: String, chaveCifrada: ByteArray, motivo: String?): ByteArray {
        if (!usaBiometria(slot)) throw Recusa(FALHA)
        if (!aparelhoComBloqueio()) throw Recusa(INDISPONIVEL)
        if (motivo == null) throw Recusa(CANCELADO)
        val privada = keyStore.getKey(alias(slot), null) as? PrivateKey ?: throw Recusa(SEM_CHAVE)
        val rsa = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
        if (!comPrazo(privada)) {
            try {
                rsa.init(Cipher.DECRYPT_MODE, privada, oaep)
            } catch (e: KeyPermanentlyInvalidatedException) {
                // Sem apagar: o cofre decide (ver `sondarChave`).
                throw Recusa(SEM_CHAVE)
            } catch (e: UserNotAuthenticatedException) {
                // Uma chave com prazo que o KeyInfo nao mostrou: segue pelo caminho dela, abaixo.
                return decifrarComPrazo(rsa, privada, chaveCifrada, motivo)
            }
            val autenticada = biometria(rsa, motivo) ?: throw Recusa(FALHA)
            return try { autenticada.doFinal(chaveCifrada) } catch (e: Exception) { throw Recusa(FALHA) }
        }
        return decifrarComPrazo(rsa, privada, chaveCifrada, motivo)
    }

    /**
     * A `kand.bio` criada antes de 07/11/2026 aceita a biometria dos ultimos 5 s: a biometria vem antes, sem objeto de
     * cifra, e a cifra abre dentro da janela dela (com o app recem-aberto nao ha biometria recente, e iniciar a cifra
     * primeiro recusava). As de agora sao por operacao, como as outras (ver `gerarRsa`).
     */
    private fun decifrarComPrazo(rsa: Cipher, privada: PrivateKey, chaveCifrada: ByteArray, motivo: String): ByteArray {
        biometria(null, motivo)
        try {
            rsa.init(Cipher.DECRYPT_MODE, privada, oaep)
        } catch (e: KeyPermanentlyInvalidatedException) {
            // Sem apagar: o cofre decide (ver `sondarChave`).
            throw Recusa(SEM_CHAVE)
        } catch (e: Exception) {
            throw Recusa(FALHA)
        }
        return try { rsa.doFinal(chaveCifrada) } catch (e: Exception) { throw Recusa(FALHA) }
    }

    /**
     * A vigia, sem interface. A `kand.bio` de antes de 07/11/2026 aceita a biometria recente e abre com a que acabou de
     * abrir a outra camada. A de agora pede a biometria para a operacao: aqui so o `init` diz se o cadastro mudou (a chave
     * invalidada lanca nele, antes de qualquer biometria), e sem abrir ela responde "nao se sabe" (2), e quem decide e o
     * hash do cadastro, que no Android vem de outra chave invalidada pelo cadastro (`cadastroDaBiometria`).
     */
    private fun decifrarVigia(slot: String, chaveCifrada: ByteArray?): Pair<Int, ByteArray> {
        if (!keyStore.containsAlias(alias(slot))) return 1 to ByteArray(0)
        return try {
            val privada = keyStore.getKey(alias(slot), null) as? PrivateKey ?: return 1 to ByteArray(0)
            val rsa = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
            rsa.init(Cipher.DECRYPT_MODE, privada, oaep)
            if (chaveCifrada == null || chaveCifrada.isEmpty() || !comPrazo(privada)) return 2 to ByteArray(0)
            0 to rsa.doFinal(chaveCifrada)
        } catch (e: KeyPermanentlyInvalidatedException) {
            keyStore.deleteEntry(alias(slot))
            1 to ByteArray(0)
        } catch (e: Exception) {
            2 to ByteArray(0)
        }
    }

    private fun gerarHmac(alias: String) {
        fun spec(comStrongBox: Boolean) = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setKeySize(256)
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUnlockedDeviceRequired(true)
            .setIsStrongBoxBacked(comStrongBox)
            .build()
        val gerador = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore")
        try {
            gerador.init(spec(true))
            gerador.generateKey()
        } catch (e: StrongBoxUnavailableException) {
            // A sonda disse StrongBox e ele recusou agora: a chave do PIN nao cai calada no TEE (o PIN de 4 digitos ja pode
            // ter passado pela sonda). A criacao falha, a sonda passa a dizer "sem StrongBox", e na proxima tentativa o PIN
            // pede 6 digitos e a chave nasce no TEE (revisao dos pendentes de 07/11/2026).
            val sondado = synchronized(sondaDoStrongBox) {
                (sondaDoStrongBox[0] == 1).also { if (it) sondaDoStrongBox[0] = 0 }
            }
            if (sondado) throw e
            gerador.init(spec(false))
            gerador.generateKey()
        }
    }

    private fun aadDoEmbrulho(slot: String, senha: ByteArray?): ByteArray {
        val base = ("escalibur-wallet/android/v1/embrulho\u0000" + slot).toByteArray()
        return if (senha != null) base + 0 + senha else base
    }

    /** OAEP com SHA-256 e MGF1 com SHA-1: o par que o Keystore aceita em todo Android 11+. */
    private val oaep = OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA1, PSource.PSpecified.DEFAULT)

    private fun gerarAes(alias: String, strongBox: Boolean): SecretKey {
        fun spec(comStrongBox: Boolean) = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUnlockedDeviceRequired(true)
            .setIsStrongBoxBacked(comStrongBox)
            .build()
        val gerador = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        if (strongBox) {
            try {
                gerador.init(spec(true))
                return gerador.generateKey()
            } catch (e: StrongBoxUnavailableException) {
                // Sem StrongBox, o TEE do aparelho.
            }
        }
        gerador.init(spec(false))
        return gerador.generateKey()
    }

    /**
     * A chave de biometria: pede a biometria para cada operacao (o objeto de cifra no pedido), inclusive a `kand.bio` do
     * modo reforcado. Ate 07/11/2026 a `kand.bio` aceitava a biometria dos ultimos 5 s, que valiam tambem para a digital
     * do desbloqueio do celular: com root, dava para abrir a camada de fora sem o dono ver pedido nenhum (Medio 11 da
     * auditoria de 31/10/2026). A que ja existe segue assim ate o modo reforcado recriar a chave (ver `comPrazo`).
     */
    private fun gerarRsa(alias: String, segueCadastro: Boolean) {
        fun spec(comStrongBox: Boolean) = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_DECRYPT or KeyProperties.PURPOSE_ENCRYPT)
            .setKeySize(2048)
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
            .setInvalidatedByBiometricEnrollment(segueCadastro)
            .setUnlockedDeviceRequired(true)
            .setIsStrongBoxBacked(comStrongBox)
            .build()
        val gerador = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore")
        try {
            gerador.initialize(spec(true))
            gerador.generateKeyPair()
        } catch (e: StrongBoxUnavailableException) {
            gerador.initialize(spec(false))
            gerador.generateKeyPair()
        }
    }

    /** A chave aceita a biometria recente (a `kand.bio` de antes de 07/11/2026), e nao so a do pedido da operacao? */
    private fun comPrazo(privada: PrivateKey): Boolean = try {
        val info = KeyFactory.getInstance(privada.algorithm, "AndroidKeyStore").getKeySpec(privada, KeyInfo::class.java)
        @Suppress("DEPRECATION")
        info.userAuthenticationValidityDurationSeconds > 0
    } catch (e: Exception) {
        false
    }

    private fun invalidada(alias: String): Boolean = try {
        val privada = keyStore.getKey(alias, null) as? PrivateKey
        if (privada == null) false
        else {
            Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding").init(Cipher.DECRYPT_MODE, privada, oaep)
            false
        }
    } catch (e: KeyPermanentlyInvalidatedException) {
        true
    } catch (e: Exception) {
        false
    }

    // ---- A biometria ----

    /**
     * Mostra a biometria forte na atividade em primeiro plano e espera a decisao. Devolve a cifra
     * liberada. Cancelar, nao reconhecer e o bloqueio do sistema sao CANCELADO: quem decide se o
     * cadastro mudou e o cofre.
     */
    /**
     * O pedido de biometria do sistema. Com `cifra`, ela volta autenticada para esta operacao; sem,
     * o pedido so autentica, e a chave que aceita a biometria recente abre logo depois.
     */
    private fun biometria(cifra: Cipher?, motivo: String): Cipher? {
        check(Looper.myLooper() != Looper.getMainLooper()) { "biometria na thread da interface" }
        val activity = atividade?.get() ?: throw Recusa(CANCELADO)
        val pronto = CountDownLatch(1)
        val resultado = AtomicReference<Cipher?>(null)
        val autenticou = java.util.concurrent.atomic.AtomicBoolean(false)
        val erro = AtomicInteger(CANCELADO)
        val cancelar = CancellationSignal()
        pedidoAtual = cancelar to pronto
        Handler(Looper.getMainLooper()).post {
            try {
                val prompt = BiometricPrompt.Builder(activity)
                    .setTitle(motivo)
                    .setAllowedAuthenticators(BIOMETRIC_STRONG)
                    // Com rosto classe 3, olhar para a tela bastava para assinar um envio (o dono
                    // dormindo ou coagido): a confirmacao pede um toque depois do rosto. Na digital
                    // nao muda nada (revisao de seguranca do Android de 26/10/2026).
                    .setConfirmationRequired(true)
                    .setNegativeButton(activity.getString(android.R.string.cancel), activity.mainExecutor) { _, _ -> pronto.countDown() }
                    .build()
                val retorno = object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        resultado.set(result.cryptoObject?.cipher)
                        autenticou.set(true)
                        pronto.countDown()
                    }
                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        if (errorCode == BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT_PERMANENT) erro.set(INDISPONIVEL)
                        pronto.countDown()
                    }
                }
                if (cifra != null) prompt.authenticate(BiometricPrompt.CryptoObject(cifra), cancelar, activity.mainExecutor, retorno)
                else prompt.authenticate(cancelar, activity.mainExecutor, retorno)
            } catch (e: Exception) {
                erro.set(FALHA)
                pronto.countDown()
            }
        }
        // Sem resposta em 60 s, o pedido cai: nunca uma espera sem fim com o cofre preso nela.
        val respondeu = try {
            pronto.await(60, TimeUnit.SECONDS)
        } finally {
            pedidoAtual = null
        }
        if (!respondeu) {
            cancelar.cancel()
            throw Recusa(CANCELADO)
        }
        if (!autenticou.get()) throw Recusa(erro.get())
        return if (cifra != null) resultado.get() ?: throw Recusa(FALHA) else null
    }

    /** 0 pronta, 1 nada cadastrado, 2 indisponivel, 3 bloqueada pelo sistema. */
    @JvmStatic
    fun estadoDaBiometria(): Int = when (app.getSystemService(BiometricManager::class.java).canAuthenticate(BIOMETRIC_STRONG)) {
        BiometricManager.BIOMETRIC_SUCCESS -> 0
        BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> 1
        // Indisponivel por um momento (o sensor ocupado): o sistema decide na hora, nada e apagado.
        BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> 0
        else -> 2
    }

    /**
     * O que no iOS e o `evaluatedPolicyDomainState`: muda quando o cadastro de biometria muda. O
     * Android nao da esse numero ao app; a vigia e uma chave que o proprio Keystore invalida no
     * cadastro novo, e o estado e o hash da geracao dela. Nil sem biometria cadastrada.
     */
    @JvmStatic
    fun cadastroDaBiometria(): ByteArray? = try {
        if (estadoDaBiometria() != 0) null
        else synchronized(trava) {
            val geracao = File(pasta, "vigia.geracao")
            val valida = keyStore.containsAlias(CHAVE_DA_VIGIA) && geracao.exists() && !vigiaInvalidada()
            if (!valida) {
                keyStore.deleteEntry(CHAVE_DA_VIGIA)
                KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                    init(KeyGenParameterSpec.Builder(CHAVE_DA_VIGIA, KeyProperties.PURPOSE_ENCRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setUserAuthenticationRequired(true)
                        .setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                        .setInvalidatedByBiometricEnrollment(true)
                        .build())
                    generateKey()
                }
                gravarAtomico(geracao, ByteArray(16).also { aleatorio.nextBytes(it) })
            }
            MessageDigest.getInstance("SHA-256").run {
                update("escalibur-wallet/android/v1/bio.estado".toByteArray())
                digest(geracao.readBytes())
            }
        }
    } catch (e: Exception) {
        null
    }

    private fun vigiaInvalidada(): Boolean = try {
        val chave = keyStore.getKey(CHAVE_DA_VIGIA, null) as SecretKey
        Cipher.getInstance("AES/GCM/NoPadding").init(Cipher.ENCRYPT_MODE, chave)
        false
    } catch (e: KeyPermanentlyInvalidatedException) {
        true
    } catch (e: Exception) {
        false
    }

    /** 16 bytes que so mudam quando o aparelho reinicia: o numero de boots do sistema. */
    @JvmStatic
    fun boot(): ByteArray? = try {
        val boots = Settings.Global.getInt(app.contentResolver, Settings.Global.BOOT_COUNT)
        "ESCBOOTC".toByteArray() + ByteBuffer.allocate(8).putLong(boots.toLong()).array()
    } catch (e: Exception) {
        null
    }

    private fun inteiro(valor: Int): ByteArray = ByteBuffer.allocate(4).putInt(valor).array()

    private class Recusa(val codigo: Int) : Exception()
    private class SemChave : Exception()
}
