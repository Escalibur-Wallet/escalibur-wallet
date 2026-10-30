# Android

O app Android é o mesmo núcleo do iOS (`Kit/`, em Swift) compilado para Android, com a interface em Kotlin e Jetpack Compose em `Android/`. Tudo que decide (chaves, cofre, endereços, planos de envio, troca e ponte, avisos) roda no núcleo; o Kotlin desenha e passa o que o dono toca.

## Ferramentas

- Swift 6.4.1 aberto (`swiftly install 6.4.1`, em `~/Library/Developer/Toolchains`) e o Swift SDK para Android da mesma versão (`swift sdk install`, o `swift-6.4.1-RELEASE_android`). O Swift do Xcode continua sendo o padrão do terminal: os scripts chamam o aberto pelo caminho.
- NDK r30 em `~/Library/Android/android-ndk-r30`.
- JDK 21 e o SDK do Android (`~/Library/Android/sdk`), com a plataforma 37 e o emulador.
- Um AVD arm64 para testes (o núcleo só existe para arm64-v8a).

## Compilar

```
tools/android/compilar-nucleo.sh debug        # o núcleo, em Android/app/src/main/jniLibs/arm64-v8a
cd Android && ./gradlew assembleDebug          # o app
```

O núcleo de release (`compilar-nucleo.sh` sem argumento) sai sem símbolos de depuração. O Gradle confere o digesto de cada dependência (`Android/gradle/verification-metadata.xml`) e o da própria distribuição (`gradle-wrapper.properties`); dependência nova pede `./gradlew --write-verification-metadata sha256 assembleDebug assembleRelease bundleRelease assembleConferencia` e a revisão do diff.

O tipo de build `conferencia` é o release minificado pelo R8, com outro id (`app.escalibur.wallet.conferencia`) e a chave de depuração: instala ao lado do app de depuração para conferir no emulador o que o R8 faz, sem apagar as carteiras de teste. Todo método que o núcleo procura pelo JNI (`Kit/Sources/Android/EscaliburAndroid/Java.swift`) precisa de regra em `Android/app/proguard-rules.pro`; o `tools/verificar.sh` confere.

## Testar

- `tools/android/testar-nucleo.sh` roda os testes do núcleo no emulador.
- O app de depuração aceita `--ez capturas true` (só pelo adb) para tirar a proteção de captura de tela e conferir as telas por `adb exec-out screencap`. Sem ela, `adb emu screenrecord screenshot <arquivo>` pega a tela pelo console do emulador.
- Os avisos (preço, recebimento, ordem limite) rodam pelo JobScheduler, trabalho 4107: `adb shell cmd jobscheduler run -f app.escalibur.wallet 4107` força uma rodada. Os arquivos ficam em `no_backup/vigias` (`adb shell run-as app.escalibur.wallet ls no_backup/vigias`).

## Arquitetura

- **Ponte.** `Nucleo.chamar(metodo, json)` e `Nucleo.chamarComSegredo` (PIN, frase e passphrase em `byte[]`, zerados depois). Cada tela tem o seu retrato no núcleo; o Kotlin nunca guarda segredo em `String`.
- **Rede.** O `HTTPClient` do núcleo usa o `AndroidURLProtocol`, que chama `Rede.kt` (HttpsURLConnection, só TLS 1.2 e 1.3, só as autoridades do sistema). A lista de hosts é a mesma do iOS (`hosts.lock`); o Kotlin não fala com a internet.
- **Cofre.** O `RootKeyVault` e o `WalletVault` do iOS sobre o `KeystoreStore` (`Cofre.kt`): cada item cifrado em AES-GCM pela chave de armazenamento do Android Keystore (TEE, só com o celular desbloqueado), que só nasce com o cofre vazio e nunca é trocada por outra. Quem confere o PIN é a chave HMAC do slot do PIN (StrongBox quando o aparelho tem), um chute de cada vez: desde 26/10/2026 a senha derivada do PIN não entra mais no AAD da chave de armazenamento, que deixava quem tem root testar PINs no TEE sem passar pela chave do slot (o item do formato antigo passa ao novo na primeira abertura certa). A biometria é uma chave RSA invalidada quando muda o cadastro: por operação, com o objeto de cifra, exceto a `kand.bio` do modo reforçado, que aceita a biometria dos últimos 5 segundos (ver a revisão de 26/10/2026 sobre "Bloquear as carteiras").
- **Avisos.** `App/Vigias.swift` guarda as moedas dos alertas, as contas do aviso de recebimento e as ordens da CoW numa pasta sem backup, fora dos dados cifrados, aplica as regras do iOS e devolve o que aconteceu; `vigias/Vigia.kt` monta o texto no formato da região e publica a notificação local, com a versão pública na tela bloqueada. A conferência de fundo é um trabalho periódico do JobScheduler (cerca de 1 hora, de volta à agenda depois de reiniciar), sem restrição de rede.
- **Textos.** O Kotlin procura cada frase em português no catálogo do iOS (`Localizable.xcstrings`) e, se não achar, em `Android/app/textos-android.json`. `tools/android/textos.py` lista o que falta; o verificador exige zero.

## O que é diferente do iOS

- Sem confirmação por voz e sem widget.
- O alarme de atualização não confirmada (docs/seguranca.md §8.6) é só do iOS: a Google Play não tem consulta pública da versão mais nova.
- Os builds do Android são numerados de 1001 em diante (`versionCode`), para nunca repetir um build do iOS na lista assinada.

## Release

A chave de upload da Google Play fica em `~/.escalibur/android/upload.jks`, com a senha no Keychain do Mac (conta `escalibur-android`, serviço `escalibur-android-upload`). A chave de assinatura do app fica com a Google (Play App Signing); a de upload pode ser trocada pelo suporte da Play se for perdida, mas guarde uma cópia cifrada fora do Mac.

Antes do pacote, a versão e o build do Android entram na lista assinada (docs/release.md, "Autorizar a versão"), no Mac do dono:

```
swift tools/versoes/versoes.swift autorizar 1.0.0 1001 escalibur-mac-1
swift tools/versoes/versoes.swift conferir
```

Depois:

```
tools/android/gerar-aab.sh
```

O script recusa gerar o pacote se a lista assinada que vai dentro do app não autorizar a versão e o build do `build.gradle.kts`. Ele compila o núcleo de release e gera o AAB (`Android/app/build/outputs/bundle/release/app-release.aab`, o que vai para a Play) e um APK de release assinado com a mesma chave.
