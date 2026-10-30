import groovy.json.JsonOutput
import groovy.json.JsonSlurper

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "app.escalibur.wallet"
    compileSdk = 37

    defaultConfig {
        applicationId = "app.escalibur.wallet"
        // Android 11: a biometria forte por operacao no Keystore (setUserAuthenticationParameters)
        // e o BiometricPrompt com a classe de biometria existem a partir dele. O nucleo em Swift e
        // compilado para android28 e roda em qualquer um destes.
        minSdk = 30
        targetSdk = 36
        // De 1001 em diante: os builds do Android nunca usam um numero de build do iOS.
        versionCode = 1008
        versionName = "1.0.1"
        // O nucleo so existe para arm64 (todos os aparelhos Android atuais e o emulador do Mac
        // com chip da Apple).
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    // A chave de upload da Google Play: fora do repositorio, em ~/.escalibur/android, com a senha no
    // Keychain do Mac. tools/android/gerar-aab.sh passa a senha por variavel de ambiente; sem ela, o
    // release sai sem assinatura.
    val senhaDeUpload: String? = System.getenv("ESCALIBUR_UPLOAD_SENHA")
    signingConfigs {
        create("upload") {
            if (senhaDeUpload != null) {
                storeFile = file(System.getenv("ESCALIBUR_UPLOAD_JKS") ?: "${System.getProperty("user.home")}/.escalibur/android/upload.jks")
                storePassword = senhaDeUpload
                keyAlias = "upload"
                keyPassword = senhaDeUpload
            }
        }
    }

    buildTypes {
        release {
            if (senhaDeUpload != null) signingConfig = signingConfigs.getByName("upload")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        // O release minificado, com outro id e a chave de depuracao: conferir no emulador o que o R8
        // faz, instalado ao lado do app de depuracao (e sem apagar as carteiras dele).
        create("conferencia") {
            initWith(getByName("release"))
            applicationIdSuffix = ".conferencia"
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        // As bibliotecas nativas ficam descomprimidas e alinhadas no APK (o carregador le
        // direto dele), e o .so do nucleo ja vem sem simbolos de depuracao.
        jniLibs { useLegacyPackaging = false }
    }

    androidResources {
        // As listas de palavras sao conferidas por digesto: nada de compressao mexendo nelas, e o
        // video toca direto do APK.
        noCompress += listOf("txt", "mp4")
    }
}

// O que o app Android usa do iOS e do nucleo vem direto das pastas deles, no build: nenhuma
// copia no repositorio que possa divergir.
val raiz: File = rootDir.parentFile

/** Copia arquivos para uma pasta que vira assets ou res do APK. */
abstract class CopiarParaOApp : DefaultTask() {
    @get:InputFiles abstract val origem: ConfigurableFileCollection
    @get:Input abstract val subpasta: Property<String>
    @get:Input abstract val achatar: Property<Boolean>
    @get:OutputDirectory abstract val saida: DirectoryProperty

    @TaskAction
    fun copiar() {
        val destino = saida.get().asFile.resolve(subpasta.get())
        destino.deleteRecursively()
        destino.mkdirs()
        origem.asFileTree.visit {
            if (!isDirectory) {
                val alvo = if (achatar.get()) destino.resolve(name) else destino.resolve(relativePath.pathString)
                alvo.parentFile.mkdirs()
                file.copyTo(alvo, overwrite = true)
            }
        }
    }
}

/**
 * As tabelas de texto de cada idioma, geradas do catalogo do iOS (Localizable.xcstrings) mais o que
 * so o Android diz (textos-android.json): `assets/textos/<idioma>.json`, da frase em portugues
 * para a traducao. Plural vira um objeto com as formas ("one", "other"...).
 */
abstract class GerarTextos : DefaultTask() {
    @get:InputFile abstract val catalogo: RegularFileProperty
    @get:InputFile abstract val adicoes: RegularFileProperty
    @get:OutputDirectory abstract val saida: DirectoryProperty

    @TaskAction
    fun gerar() {
        @Suppress("UNCHECKED_CAST")
        val strings = (JsonSlurper().parse(catalogo.get().asFile) as Map<String, Any?>)["strings"] as Map<String, Map<String, Any?>>
        val tabelas = sortedMapOf<String, MutableMap<String, Any>>()
        for ((chave, entrada) in strings) {
            @Suppress("UNCHECKED_CAST")
            val localizacoes = entrada["localizations"] as? Map<String, Map<String, Any?>> ?: continue
            for ((idioma, local) in localizacoes) {
                val valor = valorDe(local) ?: continue
                tabelas.getOrPut(idioma) { sortedMapOf() }[chave] = valor
            }
        }
        val extras = JsonSlurper().parse(adicoes.get().asFile) as Map<*, *>
        for (entrada in extras.entries) {
            val chave = entrada.key as String
            val traducoes = entrada.value as? Map<*, *> ?: continue
            for ((idioma, valor) in traducoes) tabelas.getOrPut(idioma as String) { sortedMapOf() }[chave] = valor as Any
        }
        val pasta = saida.get().asFile.resolve("textos")
        pasta.deleteRecursively()
        pasta.mkdirs()
        for ((idioma, tabela) in tabelas) pasta.resolve("$idioma.json").writeText(JsonOutput.toJson(tabela))
    }

    @Suppress("UNCHECKED_CAST")
    private fun valorDe(local: Map<String, Any?>): Any? {
        (local["stringUnit"] as? Map<String, Any?>)?.let { return it["value"] }
        val plural = (local["variations"] as? Map<String, Any?>)?.get("plural") as? Map<String, Map<String, Any?>> ?: return null
        return plural.mapValues { (_, forma) -> (forma["stringUnit"] as? Map<String, Any?>)?.get("value") ?: "" }
    }
}

/**
 * O pacote da loja nunca leva o nucleo de depuracao (cofre.teste, o saldo de teste, o detalhe nos
 * erros): o Gradle empacota o .so que estiver na pasta, de qualquer compilacao.
 */
abstract class ConferirNucleoDeRelease : DefaultTask() {
    @get:InputFile abstract val nucleo: RegularFileProperty

    @TaskAction
    fun conferir() {
        val texto = String(nucleo.get().asFile.readBytes(), Charsets.ISO_8859_1)
        check("cofre.teste" !in texto) { "o nucleo em jniLibs e o de depuracao: rode tools/android/compilar-nucleo.sh release" }
    }
}

val conferirNucleo = tasks.register<ConferirNucleoDeRelease>("conferirNucleoDeRelease") {
    nucleo.set(layout.projectDirectory.file("src/main/jniLibs/arm64-v8a/libEscaliburAndroid.so"))
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach { dependsOn(conferirNucleo) }

val gerarTextos = tasks.register<GerarTextos>("gerarTextos") {
    catalogo.set(raiz.resolve("App/EscaliburWallet/Resources/Localizable.xcstrings"))
    adicoes.set(layout.projectDirectory.file("textos-android.json"))
    saida.set(layout.buildDirectory.dir("gerado/textos"))
}
val copiarLogos = tasks.register<CopiarParaOApp>("copiarLogos") {
    origem.from(fileTree(raiz.resolve("App/EscaliburWallet/Resources/Assets.xcassets/Logos")) { include("**/*.png", "**/*.jpg") })
    subpasta.set("logos")
    achatar.set(true)
    saida.set(layout.buildDirectory.dir("gerado/logos"))
}
val copiarListas = tasks.register<CopiarParaOApp>("copiarListas") {
    origem.from(fileTree(raiz.resolve("Kit/Sources/EscaliburCore/Resources")) { include("Wordlists/**", "Forca/**") })
    origem.from(fileTree(raiz.resolve("App/EscaliburWallet/Resources")) { include("Versoes/**") })
    subpasta.set("nucleo")
    achatar.set(false)
    saida.set(layout.buildDirectory.dir("gerado/nucleo"))
}
val copiarAbertura = tasks.register<CopiarParaOApp>("copiarAbertura") {
    origem.from(
        raiz.resolve("App/EscaliburWallet/Resources/Abertura/abertura-espada.mp4"),
        raiz.resolve("App/EscaliburWallet/Resources/Assets.xcassets/AberturaEspada.imageset/abertura-espada.jpg"),
    )
    subpasta.set("abertura")
    achatar.set(true)
    saida.set(layout.buildDirectory.dir("gerado/abertura"))
}

androidComponents {
    onVariants { variante ->
        variante.sources.assets?.addGeneratedSourceDirectory(gerarTextos, GerarTextos::saida)
        variante.sources.assets?.addGeneratedSourceDirectory(copiarLogos, CopiarParaOApp::saida)
        variante.sources.assets?.addGeneratedSourceDirectory(copiarListas, CopiarParaOApp::saida)
        variante.sources.assets?.addGeneratedSourceDirectory(copiarAbertura, CopiarParaOApp::saida)
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.activity.compose)
    // O QR do Receber e a leitura do QR do Enviar: a biblioteca de codigos, sem rede.
    implementation(libs.zxing.core)
    // A camera do leitor de QR do Enviar: os quadros vao para o ZXing aqui mesmo, nada e gravado.
    implementation(libs.camera.camera2)
    implementation(libs.camera.lifecycle)
    implementation(libs.camera.compose)
    implementation(libs.lifecycle.runtime.compose)
}
