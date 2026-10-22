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
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.io.File
import java.lang.ref.WeakReference
import java.nio.ByteBuffer
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.spec.MGF1ParameterSpec
import java.util.concurrent.CountDownLatch
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
import javax.crypto.spec.SecretKeySpec

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

    private const val PREFIXO = "app.escalibur.wallet."
    private const val CHAVE_DO_ARMAZENAMENTO = PREFIXO + "cofre"
    private const val CHAVE_DA_VIGIA = PREFIXO + "vigia"
    private const val VERSAO: Byte = 1
    /** O embrulho dos slots do PIN com a senha na chave (HMAC no Keystore). */
    private const val VERSAO_DO_PIN: Byte = 2

    private lateinit var app: Context
    private lateinit var pasta: File
    @Volatile private var atividade: WeakReference<Activity>? = null
    private val aleatorio = SecureRandom()
    private val trava = Any()

    /** Na abertura do app, antes de o nucleo ser carregado. */
    fun iniciar(contexto: Context) {
        app = contexto.applicationContext
        pasta = File(app.noBackupFilesDir, "cofre").apply { mkdirs() }
    }

    /** A atividade em primeiro plano, onde a biometria aparece. */
    fun primeiroPlano(activity: Activity?) {
        atividade = activity?.let { WeakReference(it) }
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
                if (protecao == 1 && senha == null) byteArrayOf(SENHA.toByte())
                else {
                    val cifra = Cipher.getInstance("AES/GCM/NoPadding")
                    cifra.init(Cipher.DECRYPT_MODE, chaveDoArmazenamento(), GCMParameterSpec(128, bruto, 2, 12))
                    aadDoItem(conta, protecao, senha).let { aad -> try { cifra.updateAAD(aad) } finally { aad.fill(0) } }
                    val claro = cifra.doFinal(bruto, 14, bruto.size - 14)
                    try { byteArrayOf(OK.toByte()) + claro } finally { claro.fill(0) }
                }
            }
        }
    } catch (e: AEADBadTagException) {
        byteArrayOf(SENHA.toByte())
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
                    // Na troca, a protecao continua a do item gravado. A senha nao fica gravada em
                    // lugar nenhum: item com senha so nasce com ela (o cofre nunca troca um).
                    val protecaoFinal = if (novo) protecao else arquivo.readBytes().getOrNull(1)?.toInt() ?: return FALHA
                    if (protecaoFinal == 1 && senha == null) return SENHA
                    val cifra = Cipher.getInstance("AES/GCM/NoPadding")
                    cifra.init(Cipher.ENCRYPT_MODE, chaveDoArmazenamento())
                    aadDoItem(conta, protecaoFinal, senha).let { aad -> try { cifra.updateAAD(aad) } finally { aad.fill(0) } }
                    val cifrado = cifra.doFinal(dados)
                    val corpo = byteArrayOf(VERSAO, protecaoFinal.toByte()) + cifra.iv + cifrado
                    gravarAtomico(arquivo, corpo)
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

    private fun chaveDoArmazenamento(): SecretKey {
        (keyStore.getKey(CHAVE_DO_ARMAZENAMENTO, null) as? SecretKey)?.let { return it }
        // Fora do StrongBox: cada leitura e gravacao passa por ela, e o TEE e bem mais rapido.
        return gerarAes(CHAVE_DO_ARMAZENAMENTO, strongBox = false)
    }

    /** Sem bloqueio de tela, o Keystore fica destravado para sempre: nenhuma chave abre (no iOS,
     * tirar o codigo apaga as carteiras). O caminho volta quando o bloqueio volta. */
    fun aparelhoComBloqueio(): Boolean = app.getSystemService(KeyguardManager::class.java).isDeviceSecure

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
     * invalidou conta como ausente, e e apagada: no iOS o proprio SE a destroi. */
    @JvmStatic
    fun sondarChave(slot: String): Int = try {
        if (!keyStore.containsAlias(alias(slot))) AUSENTE
        else if (usaBiometria(slot) && invalidada(alias(slot))) {
            keyStore.deleteEntry(alias(slot))
            AUSENTE
        } else OK
    } catch (e: Exception) {
        FALHA
    }

    @JvmStatic
    fun apagarChave(slot: String) {
        try { keyStore.deleteEntry(alias(slot)) } catch (e: Exception) {}
    }

    /** [status] e, com OK, o embrulho. */
    @JvmStatic
    fun embrulhar(slot: String, segredo: ByteArray, senha: ByteArray?): ByteArray = try {
        when {
            usaSenha(slot) != (senha != null) -> byteArrayOf(FALHA.toByte())
            usaBiometria(slot) -> {
                val publica = keyStore.getCertificate(alias(slot))?.publicKey ?: throw SemChave()
                // Hibrido: uma chave AES nova por embrulho, cifrada pela RSA; o segredo, pela AES.
                val chave = ByteArray(32).also { aleatorio.nextBytes(it) }
                try {
                    val rsa = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
                    rsa.init(Cipher.ENCRYPT_MODE, publica, oaep)
                    val chaveCifrada = rsa.doFinal(chave)
                    val aes = Cipher.getInstance("AES/GCM/NoPadding")
                    val iv = ByteArray(12).also { aleatorio.nextBytes(it) }
                    aes.init(Cipher.ENCRYPT_MODE, SecretKeySpec(chave, "AES"), GCMParameterSpec(128, iv))
                    aes.updateAAD(aadDoEmbrulho(slot, null))
                    byteArrayOf(OK.toByte(), VERSAO) + inteiro(chaveCifrada.size) + chaveCifrada + iv + aes.doFinal(segredo)
                } finally {
                    chave.fill(0)
                }
            }
            usaSenha(slot) -> {
                val sal = ByteArray(16).also { aleatorio.nextBytes(it) }
                val chave = chaveDoPin(slot, senha!!, sal)
                try {
                    val aes = Cipher.getInstance("AES/GCM/NoPadding")
                    val iv = ByteArray(12).also { aleatorio.nextBytes(it) }
                    aes.init(Cipher.ENCRYPT_MODE, SecretKeySpec(chave, "AES"), GCMParameterSpec(128, iv))
                    aes.updateAAD(aadDoEmbrulho(slot, null) + VERSAO_DO_PIN)
                    byteArrayOf(OK.toByte(), VERSAO_DO_PIN) + sal + iv + aes.doFinal(segredo)
                } finally {
                    chave.fill(0)
                }
            }
            else -> {
                val chave = keyStore.getKey(alias(slot), null) as? SecretKey ?: throw SemChave()
                val aes = Cipher.getInstance("AES/GCM/NoPadding")
                aes.init(Cipher.ENCRYPT_MODE, chave)
                aes.updateAAD(aadDoEmbrulho(slot, null))
                val cifrado = aes.doFinal(segredo)
                byteArrayOf(OK.toByte(), VERSAO) + aes.iv + cifrado
            }
        }
    } catch (e: SemChave) {
        byteArrayOf(SEM_CHAVE.toByte())
    } catch (e: Exception) {
        byteArrayOf(FALHA.toByte())
    } finally {
        segredo.fill(0)
        senha?.fill(0)
    }

    /** [status] e, com OK, o segredo. Nos slots de biometria, `motivo` e o texto da biometria; sem
     * motivo, nenhuma interface (e recusa). */
    @JvmStatic
    fun desembrulhar(slot: String, blob: ByteArray, senha: ByteArray?, motivo: String?): ByteArray = try {
        val claro = abrir(slot, blob, senha, motivo)
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

    /**
     * Abre `blob` pela biometria e, na mesma autenticacao, a vigia do modo reforcado. Devolve
     * [status][vigia][tamanho do segredo em 4 bytes][segredo][conteudo da vigia]; vigia 0 abriu,
     * 1 a chave nao existe mais, 2 nao se sabe.
     */
    @JvmStatic
    fun desembrulharVigiando(slot: String, blob: ByteArray, motivo: String, slotVigia: String, vigia: ByteArray): ByteArray = try {
        val claro = abrir(slot, blob, null, motivo)
        try {
            val (estado, conteudo) = abrirVigia(slotVigia, vigia)
            try {
                byteArrayOf(OK.toByte(), estado.toByte()) + inteiro(claro.size) + claro + conteudo
            } finally {
                conteudo.fill(0)
            }
        } finally {
            claro.fill(0)
        }
    } catch (e: Recusa) {
        byteArrayOf(e.codigo.toByte())
    } catch (e: Exception) {
        byteArrayOf(FALHA.toByte())
    }

    private fun abrir(slot: String, blob: ByteArray, senha: ByteArray?, motivo: String?): ByteArray {
        if (usaSenha(slot) != (senha != null)) throw Recusa(FALHA)
        if (!aparelhoComBloqueio()) throw Recusa(INDISPONIVEL)
        if (usaSenha(slot) && blob.firstOrNull() == VERSAO_DO_PIN) return abrirPeloPin(slot, blob, senha!!)
        if (blob.isEmpty() || blob[0] != VERSAO) throw Recusa(FALHA)
        if (!usaBiometria(slot)) {
            val chave = keyStore.getKey(alias(slot), null) as? SecretKey ?: throw Recusa(SEM_CHAVE)
            if (blob.size < 1 + 12 + 16) throw Recusa(FALHA)
            val aes = Cipher.getInstance("AES/GCM/NoPadding")
            aes.init(Cipher.DECRYPT_MODE, chave, GCMParameterSpec(128, blob, 1, 12))
            aadDoEmbrulho(slot, senha).let { aad -> try { aes.updateAAD(aad) } finally { aad.fill(0) } }
            return try {
                aes.doFinal(blob, 13, blob.size - 13)
            } catch (e: AEADBadTagException) {
                throw Recusa(if (usaSenha(slot)) SENHA else FALHA)
            }
        }
        if (motivo == null) throw Recusa(CANCELADO)
        val privada = keyStore.getKey(alias(slot), null) as? PrivateKey ?: throw Recusa(SEM_CHAVE)
        val partes = partesHibridas(blob) ?: throw Recusa(FALHA)
        val rsa = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
        // A chave que aceita a biometria recente (`kand.bio`, a unica de "Bloquear as carteiras"):
        // a biometria vem antes, sem objeto de cifra, e a cifra abre dentro da janela dela. Com o
        // app recem-aberto nao ha biometria recente, e iniciar a cifra primeiro recusava.
        if (!porOperacao(slot)) {
            biometria(null, motivo)
            try {
                rsa.init(Cipher.DECRYPT_MODE, privada, oaep)
            } catch (e: KeyPermanentlyInvalidatedException) {
                keyStore.deleteEntry(alias(slot))
                throw Recusa(SEM_CHAVE)
            } catch (e: Exception) {
                throw Recusa(FALHA)
            }
            val chave = try { rsa.doFinal(partes.first) } catch (e: Exception) { throw Recusa(FALHA) }
            try {
                return abrirHibrido(slot, chave, partes.second)
            } finally {
                chave.fill(0)
            }
        }
        try {
            rsa.init(Cipher.DECRYPT_MODE, privada, oaep)
        } catch (e: KeyPermanentlyInvalidatedException) {
            keyStore.deleteEntry(alias(slot))
            throw Recusa(SEM_CHAVE)
        }
        val autenticada = biometria(rsa, motivo) ?: throw Recusa(FALHA)
        val chave = try { autenticada.doFinal(partes.first) } catch (e: Exception) { throw Recusa(FALHA) }
        try {
            return abrirHibrido(slot, chave, partes.second)
        } finally {
            chave.fill(0)
        }
    }

    /** A vigia, sem interface: a autenticacao que acabou de abrir a outra camada vale para ela
     * por alguns segundos (a chave da vigia aceita a biometria recente, ver `gerarRsa`). */
    private fun abrirVigia(slot: String, blob: ByteArray): Pair<Int, ByteArray> {
        if (!keyStore.containsAlias(alias(slot))) return 1 to ByteArray(0)
        return try {
            val privada = keyStore.getKey(alias(slot), null) as? PrivateKey ?: return 1 to ByteArray(0)
            val partes = partesHibridas(blob) ?: return 2 to ByteArray(0)
            val rsa = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
            rsa.init(Cipher.DECRYPT_MODE, privada, oaep)
            val chave = rsa.doFinal(partes.first)
            try { 0 to abrirHibrido(slot, chave, partes.second) } finally { chave.fill(0) }
        } catch (e: KeyPermanentlyInvalidatedException) {
            keyStore.deleteEntry(alias(slot))
            1 to ByteArray(0)
        } catch (e: Exception) {
            2 to ByteArray(0)
        }
    }

    private fun partesHibridas(blob: ByteArray): Pair<ByteArray, ByteArray>? {
        if (blob.size < 1 + 4 + 12 + 16) return null
        val tamanho = ByteBuffer.wrap(blob, 1, 4).int
        if (tamanho <= 0 || 5 + tamanho > blob.size) return null
        return blob.copyOfRange(5, 5 + tamanho) to blob.copyOfRange(5 + tamanho, blob.size)
    }

    private fun abrirHibrido(slot: String, chave: ByteArray, resto: ByteArray): ByteArray {
        if (resto.size < 12 + 16) throw Recusa(FALHA)
        val aes = Cipher.getInstance("AES/GCM/NoPadding")
        aes.init(Cipher.DECRYPT_MODE, SecretKeySpec(chave, "AES"), GCMParameterSpec(128, resto, 0, 12))
        aes.updateAAD(aadDoEmbrulho(slot, null))
        return try { aes.doFinal(resto, 12, resto.size - 12) } catch (e: AEADBadTagException) { throw Recusa(FALHA) }
    }

    /** Formato 2: [2][sal 16][iv 12][cifrado + tag]. Senha errada da outra chave AES, e a tag recusa. */
    private fun abrirPeloPin(slot: String, blob: ByteArray, senha: ByteArray): ByteArray {
        if (blob.size < 1 + 16 + 12 + 16) throw Recusa(FALHA)
        val chave = chaveDoPin(slot, senha, blob.copyOfRange(1, 17))
        try {
            val aes = Cipher.getInstance("AES/GCM/NoPadding")
            aes.init(Cipher.DECRYPT_MODE, SecretKeySpec(chave, "AES"), GCMParameterSpec(128, blob, 17, 12))
            aes.updateAAD(aadDoEmbrulho(slot, null) + VERSAO_DO_PIN)
            return try { aes.doFinal(blob, 29, blob.size - 29) } catch (e: AEADBadTagException) { throw Recusa(SENHA) }
        } finally {
            chave.fill(0)
        }
    }

    /**
     * A chave AES de um embrulho do PIN: a senha passa pela chave HMAC do slot, que nunca sai do
     * hardware, e o resultado e estendido com o sal deste embrulho (HKDF-SHA256). Quem copia o
     * arquivo, ou le a memoria do Keystore, so testa PINs neste aparelho, um de cada vez.
     */
    private fun chaveDoPin(slot: String, senha: ByteArray, sal: ByteArray): ByteArray {
        val hmac = keyStore.getKey(alias(slot), null) as? SecretKey ?: throw SemChave()
        val entrada = "escalibur-wallet/android/v2/pin\u0000$slot\u0000".toByteArray() + senha
        val semente = try {
            Mac.getInstance("HmacSHA256").run { init(hmac); doFinal(entrada) }
        } catch (e: java.security.InvalidKeyException) {
            // A chave do slot ainda e a AES do formato 1: este embrulho nao e dela.
            throw SemChave()
        } finally {
            entrada.fill(0)
        }
        try {
            val extraida = Mac.getInstance("HmacSHA256").run { init(SecretKeySpec(sal, "HmacSHA256")); doFinal(semente) }
            try {
                val info = "escalibur-wallet/android/v2/embrulho\u0000$slot".toByteArray() + 1
                return Mac.getInstance("HmacSHA256").run { init(SecretKeySpec(extraida, "HmacSHA256")); doFinal(info) }
            } finally {
                extraida.fill(0)
            }
        } finally {
            semente.fill(0)
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
     * A chave de biometria. A do rosto que segue o cadastro no modo reforcado (`kand.bio`) tambem
     * e a vigia: aceita a biometria dos ultimos segundos, para abrir na mesma autenticacao da outra
     * camada sem pedir de novo. As outras pedem a biometria para cada operacao.
     */
    /** Pede a biometria a cada operacao (o objeto de cifra no pedido); `kand.bio` aceita a recente. */
    private fun porOperacao(slot: String) = slot != "kand.bio"

    private fun gerarRsa(alias: String, segueCadastro: Boolean) {
        val porOperacao = porOperacao(alias.removePrefix(PREFIXO))
        fun spec(comStrongBox: Boolean) = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_DECRYPT or KeyProperties.PURPOSE_ENCRYPT)
            .setKeySize(2048)
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationParameters(if (porOperacao) 0 else 5, KeyProperties.AUTH_BIOMETRIC_STRONG)
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
        Handler(Looper.getMainLooper()).post {
            try {
                val prompt = BiometricPrompt.Builder(activity)
                    .setTitle(motivo)
                    .setAllowedAuthenticators(BIOMETRIC_STRONG)
                    .setConfirmationRequired(false)
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
        pronto.await()
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
