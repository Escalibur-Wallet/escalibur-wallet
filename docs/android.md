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

O tipo de build `conferencia` é o release minificado pelo R8, com outro id (`app.escalibur.wallet.conferencia`) e a chave de depuração: instala ao lado do app de depuração para conferir no emulador o que o R8 faz, sem apagar as carteiras de teste. Como o release, ele recusa empacotar o núcleo de depuração: antes dele, `compilar-nucleo.sh release` (auditoria Android de 31/10/2026). Todo método que o núcleo procura pelo JNI (`Kit/Sources/Android/EscaliburAndroid/Java.swift`) precisa de regra em `Android/app/proguard-rules.pro`; o `tools/verificar.sh` confere.

## Testar

- `tools/android/testar-nucleo.sh` roda os testes do núcleo no emulador.
- O app de depuração aceita `--ez capturas true` (só pelo adb) para tirar a proteção de captura de tela e conferir as telas por `adb exec-out screencap`. Sem ela, `adb emu screenrecord screenshot <arquivo>` pega a tela pelo console do emulador.
- Os avisos (preço, recebimento, ordem limite) rodam pelo JobScheduler, trabalho 4107: `adb shell cmd jobscheduler run -f app.escalibur.wallet 4107` força uma rodada. Os arquivos ficam em `no_backup/vigias` (`adb shell run-as app.escalibur.wallet ls no_backup/vigias`).

## Arquitetura

- **Ponte.** `Nucleo.chamar(metodo, json)` e `Nucleo.chamarComSegredo` (PIN, frase e passphrase em `byte[]`, zerados depois). Cada tela tem o seu retrato no núcleo; o Kotlin nunca guarda segredo em `String`.
- **Rede.** O `HTTPClient` do núcleo usa o `AndroidURLProtocol`, que chama `Rede.kt` (HttpsURLConnection, só TLS 1.2 e 1.3, só as autoridades do sistema). A lista de hosts é a mesma do iOS (`hosts.lock`); o Kotlin não fala com a internet.
- **Cofre.** O `RootKeyVault` e o `WalletVault` do iOS sobre o `KeystoreStore` (`Cofre.kt`): cada item cifrado em AES-GCM pela chave de armazenamento do Android Keystore (TEE, só com o celular desbloqueado), que só nasce com o cofre vazio e nunca é trocada por outra. Quem confere o PIN é a chave HMAC do slot do PIN (StrongBox quando o aparelho tem), um chute de cada vez: desde 26/10/2026 a senha derivada do PIN não entra mais no AAD da chave de armazenamento, que deixava quem tem root testar PINs no TEE sem passar pela chave do slot (o item do formato antigo passa ao novo na primeira abertura certa). A biometria é uma chave RSA invalidada quando muda o cadastro, sempre por operação, com o objeto de cifra. Até 07/11/2026 a `kand.bio` do modo reforçado aceitava a biometria dos últimos 5 segundos, que valiam também para a digital do desbloqueio do celular (com root, abria a camada de fora sem pedido nenhum na tela; Médio 11 da auditoria de 31/10/2026). A chave criada antes disso continua abrindo pelo caminho dela (o `KeyInfo` diz o prazo) até o modo reforçado recriá-la: passar por "Continuar normal" e voltar, o realinhamento da vigia, ou desligar e ligar. Trocar direto entre "Bloquear as carteiras" e "Esperar 24 horas" reaproveita a mesma `kand.bio` e não a recria. Recriar na própria "Bloquear as carteiras" sem trocar de política exigiria uma geração nova da chave (como a `kand.pin.a`/`.b`) e um cabeçalho novo do registro: fica como risco residual, e exige root mais o PIN. A vigia nova do "Esperar 24 horas" não abre sem um segundo pedido: o `init` dela diz se o cadastro mudou (a chave invalidada lança antes de qualquer biometria) e, sem abrir, quem decide é o hash do cadastro, que no Android vem de outra chave invalidada pelo cadastro. No Android o buffer seguro do núcleo (`SecureBytes`) prende as páginas na RAM (`mlock`) e as tira do core dump (`MADV_DONTDUMP`); desde 07/11/2026 os segredos de até 2 KiB ficam numa arena só, travada e com páginas de guarda nas pontas (`LockedArena`), porque a cota de memória travada do Android (64 KiB) acabava no 17º buffer com região própria e o `mlock` falhava em silêncio. O que não cabe segue com região própria, e a falha do `mlock` é contada no núcleo (`LockedArena.lockFailures`), sem aviso na tela nem teste que a leia: em aparelho com RAM Plus, Extensão de memória e afins o swap é um arquivo no flash, e o iOS não tem isso. O bloco de 256 MiB do Argon2 não cabe na cota e fica exposto durante a derivação do PIN; é por isso que o PIN é conferido pela chave HMAC do hardware, e não só pelo Argon2 (auditoria Android de 31/10/2026).
- **Avisos.** `App/Vigias.swift` guarda as moedas dos alertas, as contas do aviso de recebimento e as ordens da CoW numa pasta sem backup, fora dos dados cifrados, aplica as regras do iOS e devolve o que aconteceu; `vigias/Vigia.kt` monta o texto no formato da região e publica a notificação local, com a versão pública na tela bloqueada. A conferência de fundo é um trabalho periódico do JobScheduler (cerca de 1 hora, de volta à agenda depois de reiniciar), sem restrição de rede.
- **Textos.** O Kotlin procura cada frase em português no catálogo do iOS (`Localizable.xcstrings`) e, se não achar, em `Android/app/textos-android.json`. `tools/android/textos.py` lista o que falta; o verificador exige zero.

## O que é diferente do iOS

- Sem confirmação por voz e sem widget.
- O alarme de atualização não confirmada (docs/seguranca.md §8.6) é só do iOS: a Google Play não tem consulta pública da versão mais nova. A tela "Esta versão está desatualizada" e a obrigatória existem desde 07/11/2026, lendo só a lista assinada: o build que o dono liberou nela com o lançamento em 100% na Play (`versoes.swift liberar-android`).
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
