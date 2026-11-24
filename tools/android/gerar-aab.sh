#!/bin/bash -p
# Gera o pacote da Google Play (AAB) e um APK de release para conferir no emulador: o nucleo em
# release, o app minificado e os dois assinados com a chave de upload.
#
#   tools/android/gerar-aab.sh      grava /private/tmp/escalibur-aab-<versao>-<build>.*/ (o AAB, o APK e o SHA256SUMS)
#
# A chave fica em ~/.escalibur/android/upload.jks e a senha no Keychain do Mac
# (conta escalibur-android, servico escalibur-android-upload). Nada disso vai para o repositorio.
#
# So do codigo publicado na main do GitHub, numa copia limpa, com o commit e a arvore dentro do app
# (tools/copia-publicada.sh, auditoria de 03/11/2026). Duas fases: a primeira, daqui, monta a copia limpa;
# a segunda roda o gerar-aab.sh de dentro dela, o publicado. O corpo fica em funcoes: o bash le cada uma
# inteira antes de rodar, e editar este arquivo durante o build nao muda o que roda (quarta passada).
set -euo pipefail
# O ambiente da loja (revisao da decima terceira passada da auditoria de 03/11/2026): o bash do sistema em modo privilegiado,
# sem funcao herdada nem BASH_ENV, e o resto so por lista de permitidos. Quem chama `bash script` para aqui, numa expansao
# que nenhuma funcao troca. Fora da lista, o script nasce de novo com o ambiente limpo: a pasta do usuario pelo servico de
# diretorio (e nao pelo HOME), o PATH do sistema, que o SIP protege, e o git sem configuracao de fora, sem fsmonitor e sem
# hooks. CDPATH, as variaveis do Perl, do compilador e do Java ficam todas de fora.
# O git, o Python, o swift e o xcodebuild de /usr/bin escolhem o programa de verdade pelo cache do xcrun, que fica
# na pasta temporaria do usuario: cada script comeca com um cache novo e vazio (xcrun_db), resolvido de novo pelo Xcode,
# que e do root (checagem final de 16/11/2026, rodada 3 dos 3 agentes).
case "$-" in *p*) ;; *) _sem_p=; : "${_sem_p:?rode pelo caminho do script, e nao por bash script}" ;; esac
casa=$(/usr/bin/dscl . -read "/Users/$(/usr/bin/id -un)" NFSHomeDirectory | /usr/bin/sed -n 's/^NFSHomeDirectory: //p')
limpo=true
for variavel in $(compgen -e); do
    case "$variavel" in
        HOME|PATH|TMPDIR|USER|LOGNAME|LANG|TERM|PWD|OLDPWD|SHLVL|_|GIT_CONFIG_NOSYSTEM|GIT_CONFIG_GLOBAL|GIT_NO_REPLACE_OBJECTS|GIT_CONFIG_COUNT|GIT_CONFIG_KEY_0|GIT_CONFIG_VALUE_0|GIT_CONFIG_KEY_1|GIT_CONFIG_VALUE_1|xcrun_db) ;;
        *) limpo=false ;;
    esac
done
[ -n "$casa" ] && [ "${HOME:-}" = "$casa" ] && [ "$PATH" = /usr/bin:/bin:/usr/sbin:/sbin ] && [ "${LANG:-}" = en_US.UTF-8 ] \
    && [ "${TMPDIR:-}" = "$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)" ] \
    && [ "${GIT_CONFIG_NOSYSTEM:-}" = 1 ] && [ "${GIT_CONFIG_GLOBAL:-}" = /dev/null ] && [ "${GIT_NO_REPLACE_OBJECTS:-}" = 1 ] \
    && [ "${GIT_CONFIG_COUNT:-}" = 2 ] && [ "${GIT_CONFIG_KEY_0:-}" = core.fsmonitor ] && [ "${GIT_CONFIG_VALUE_0:-}" = false ] \
    && [ "${GIT_CONFIG_KEY_1:-}" = core.hooksPath ] && [ "${GIT_CONFIG_VALUE_1:-}" = /dev/null ] \
    && [ -n "${xcrun_db:-}" ] && [ "${xcrun_db#"$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)"escalibur-xcrun.}" != "$xcrun_db" ] && [ ! -e "$xcrun_db" ] \
    || limpo=false
[ -n "$casa" ] || { echo "a pasta do usuario nao veio do servico de diretorio" >&2; exit 1; }
$limpo || exec /usr/bin/env -i HOME="$casa" USER="$(/usr/bin/id -un)" LOGNAME="$(/usr/bin/id -un)" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)" LANG=en_US.UTF-8 TERM="${TERM:-dumb}" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_COUNT=2 \
    GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null \
    xcrun_db="$(/usr/bin/mktemp -d "$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)escalibur-xcrun.XXXXXX")/xcrun_db" \
    /bin/bash -p "$0" "$@"

# O digesto de uma pasta inteira (caminho, modo e SHA-256 de cada arquivo, e o alvo de cada link), o mesmo do
# compilar-nucleo.sh.
arvore() {
    python3 -I - "$1" <<'PY'
import hashlib, os, sys
raiz = sys.argv[1]
entradas = []
for pasta, subpastas, arquivos in os.walk(raiz):
    for nome in subpastas + arquivos:
        caminho = os.path.join(pasta, nome)
        relativo = os.path.relpath(caminho, raiz)
        if "__pycache__" in relativo.split(os.sep) or nome.endswith(".pyc"):
            continue
        if os.path.islink(caminho):
            entradas.append(f"L {relativo} {os.readlink(caminho)}")
        elif os.path.isfile(caminho):
            h = hashlib.sha256()
            with open(caminho, "rb") as arquivo:
                for bloco in iter(lambda: arquivo.read(1 << 20), b""):
                    h.update(bloco)
            entradas.append(f"F {relativo} {os.stat(caminho).st_mode & 0o7777:o} {h.hexdigest()}")
total = hashlib.sha256()
for entrada in sorted(entradas):
    total.update(entrada.encode("utf-8", "surrogateescape") + b"\n")
print(total.hexdigest())
PY
}

primeira_fase() {
    cd "$(dirname "$0")/../.."
    source tools/copia-publicada.sh
    /bin/bash -p "$limpa/tools/android/gerar-aab.sh" --na-copia-limpa "$raiz" "$commit" "$arvore"
}

segunda_fase() {
    local raiz="$1" commit="$2" arvore="$3" aqui
    cd "$(dirname "$0")/../.."
    aqui=$(pwd -P)
    [ "$(git rev-parse --show-toplevel)" = "$aqui" ] && [ "$aqui" != "$(cd "$raiz" && pwd -P)" ] \
        && [ "$(git rev-parse HEAD)" = "$commit" ] && [ "$(git rev-parse 'HEAD^{tree}')" = "$arvore" ] \
        && [ -z "$(git status --porcelain=v1 --untracked-files=all --ignored)" ] && [ -z "$(git ls-files -v | grep -v '^H ')" ] \
        || { echo "a segunda fase nao esta na copia limpa do commit publicado" >&2; exit 1; }
    # O ambiente do Gradle, do Kotlin e do R8, que montam a tela do PIN e das palavras e tem a senha de upload no
    # ambiente: nenhum agente nem opcao do Java, do Gradle ou do SDK por fora do repositorio, o JDK e o SDK das pastas de
    # sempre, e nenhum script de inicio nem ajuste no ~/.gradle (revisao da decima terceira passada).
    local variavel
    for variavel in $(compgen -e); do
        case "$variavel" in
            JAVA_TOOL_OPTIONS|_JAVA_OPTIONS|JDK_JAVA_OPTIONS|JAVA_OPTS|GRADLE_OPTS|GRADLE_USER_HOME|ORG_GRADLE_PROJECT_*|ANDROID_SDK_ROOT|ANDROID_NDK*|ANDROID_USER_HOME|KOTLIN_*|DYLD_*|LD_*|BASH_ENV|ENV|SHELLOPTS|BASHOPTS|PS4)
                echo "a variavel de ambiente $variavel muda o build do Android por fora do repositorio: nada foi montado" >&2; exit 1 ;;
        esac
    done
    [ ! -e "$HOME/.gradle/init.d" ] && [ ! -e "$HOME/.gradle/init.gradle" ] && [ ! -e "$HOME/.gradle/init.gradle.kts" ] \
        && [ ! -e "$HOME/.gradle/gradle.properties" ] \
        || { echo "o ~/.gradle tem script de inicio ou gradle.properties, que mudam o build: nada foi montado" >&2; exit 1; }
    export JAVA_HOME="$HOME/Library/Java/JavaVirtualMachines/jdk-21.0.12.1+1/Contents/Home"
    export ANDROID_HOME="$HOME/Library/Android/sdk"

    # A lista assinada que vai dentro do app precisa autorizar esta versao e este build (docs/release.md,
    # "Autorizar a versao"): sem isso, nada e gerado.
    local versao build
    versao=$(grep -oE 'versionName = "[^"]+"' Android/app/build.gradle.kts | sed -E 's/.*"(.*)"/\1/')
    build=$(grep -oE 'versionCode = [0-9]+' Android/app/build.gradle.kts | grep -oE '[0-9]+')
    python3 -I - "$versao" "$build" <<'PY' || { echo "a lista assinada nao autoriza $versao ($build): swift tools/versoes/versoes.swift autorizar $versao $build escalibur-mac-1" >&2; exit 1; }
import json, sys
versao, build = sys.argv[1], sys.argv[2]
envelope = json.load(open("App/EscaliburWallet/Resources/Versoes/versoes.json"))
manifesto = json.loads(envelope["manifesto"])
sys.exit(0 if any(v["versao"] == versao and build in v["builds"] for v in manifesto["versoes"]) else 1)
PY
    swift tools/versoes/versoes.swift conferir

    # Os vetores da frase ao endereco no nucleo do Android otimizado como o da loja, antes de montar. Sem aparelho no adb,
    # para.
    # Sem atalho para pular: a loja nunca sai sem eles (decima terceira passada da auditoria de 03/11/2026).
    "$aqui/tools/android/testar-nucleo.sh" --derivacao || { echo "os vetores de derivacao falharam no Android: nada foi montado" >&2; exit 1; }

    "$aqui/tools/android/compilar-nucleo.sh" release --loja

    # O JDK, o SDK e o Gradle que montam o app (checagem final de 16/11/2026, M1): o Xcode ja e conferido pelo cdhash e o
    # toolchain Swift e o NDK pelo digesto, e estes ficavam de fora, todos gravaveis pelo usuario. O JDK pelo selo da
    # Temurin e pelo digesto da arvore; a plataforma e o build-tools do SDK pelo digesto; e o Gradle numa pasta nova a cada
    # build, com a distribuicao e as dependencias baixadas de novo e conferidas pelo distributionSha256Sum e pelo
    # verification-metadata. Nada do ~/.gradle nem do ~/.android entra (nem distribuicao extraida, nem cache, nem
    # transformacao, nem jar de lint). Aqui, logo antes do Gradle, e nao no comeco: o testar-nucleo.sh e o
    # compilar-nucleo.sh rodam o adb e o toolchain Swift, e o que eles mudassem no JDK, no SDK ou na copia limpa passaria
    # por uma conferencia feita antes (revisao dos 3 agentes da checagem final). A copia limpa e conferida de novo, e o
    # sdk.dir gravado agora.
    /usr/bin/codesign --verify --deep --strict \
        -R='identifier "net.java.openjdk.jdk" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "JCDTMS22B4"' \
        "$HOME/Library/Java/JavaVirtualMachines/jdk-21.0.12.1+1" \
        && [ "$(arvore "$JAVA_HOME")" = 7b238c151db1ae2a3dbf86e7dd237db46e577714baad2a326ae2d0c7be5cd3d3 ] \
        && [ "$(arvore "$ANDROID_HOME/platforms/android-37.0")" = 79a0343c9b1f159b66e28adad51838ef22cc9ac47570cb3fe42a2f0ff56400eb ] \
        && [ "$(arvore "$ANDROID_HOME/build-tools/36.0.0")" = a74275b60c4b098b13049d9c3fa17d1afa5f0e23ca9f354f05a42e8c670f6790 ] \
        || { echo "o JDK, a plataforma ou o build-tools do SDK nao sao os conferidos (selo ou digesto da arvore): nada foi montado" >&2; exit 1; }
    # Tambem o que o git ignora (rodada 3 dos 3 agentes): sem historico nem saida de build do Gradle plantados (apagados
    # aqui), e so as pastas que os vetores e o nucleo deixam, com os dois .so no jniLibs e nada mais.
    /bin/rm -rf Android/.gradle Android/.kotlin Android/build Android/app/build
    [ -z "$(git status --porcelain=v1 --untracked-files=all)" ] \
        && [ -z "$(git status --porcelain=v1 --ignored=traditional --untracked-files=normal | grep -vxF -e '!! build/' -e '!! Android/app/src/main/jniLibs/' -e '!! Kit/.build/' -e '!! Kit/.swiftpm/')" ] \
        && [ "$(cd Android/app/src/main/jniLibs && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ')" = "./arm64-v8a ./arm64-v8a/libEscaliburAndroid.so ./arm64-v8a/libc++_shared.so " ] \
        || { echo "a copia limpa mudou durante os vetores ou a compilacao do nucleo: nada foi montado" >&2; exit 1; }
    casa_gradle=$(mktemp -d)
    trap '/bin/rm -rf "$casa_gradle"' EXIT
    mkdir "$casa_gradle/android"
    export GRADLE_USER_HOME="$casa_gradle" ANDROID_USER_HOME="$casa_gradle/android"
    printf 'sdk.dir=%s\n' "$ANDROID_HOME" > Android/local.properties
    # O /usr/bin/security pelo caminho inteiro, e o item gravado com -T "" (docs/android.md): a leitura pede o ok do dono.
    ESCALIBUR_UPLOAD_SENHA="$(/usr/bin/security find-generic-password -a escalibur-android -s escalibur-android-upload -w)"
    export ESCALIBUR_UPLOAD_SENHA
    # Sem o cache de configuracao (ele guardaria a senha da chave em disco, dentro de Android/.gradle) e sem
    # daemon (um daemon que sobra, se o build falhar, guardaria a senha no ambiente por horas). O compilador do Kotlin
    # dentro do proprio Gradle, e nao no daemon dele, que herdaria a senha e ficaria ate 2 h ocioso (revisao dos 3 agentes
    # da checagem final de 16/11/2026).
    (cd "$aqui/Android" && ./gradlew -q --no-daemon --no-configuration-cache --dependency-verification strict -Pkotlin.compiler.execution.strategy=in-process -PcommitDeOrigem="$commit" -ParvoreDeOrigem="$arvore" bundleRelease assembleRelease)
    unset ESCALIBUR_UPLOAD_SENHA GRADLE_USER_HOME ANDROID_USER_HOME
    /bin/rm -rf "$casa_gradle"
    local apk=Android/app/build/outputs/apk/release/app-release.apk aab=Android/app/build/outputs/bundle/release/app-release.aab
    # O commit e a arvore entraram no APK e no AAB, que e o que vai para a Play, e nao so no pedido ao Gradle. Os
    # dex sao extraidos antes: com pipefail, o `grep -q` que achava cedo matava o `unzip` de SIGPIPE, e a
    # conferencia falhava com o valor presente (quinta passada da auditoria de 03/11/2026).
    local dex
    dex=$(mktemp -d)
    unzip -q "$apk" 'classes*.dex' -d "$dex/apk"
    unzip -q "$aab" 'base/dex/classes*.dex' -d "$dex/aab"
    for valor in "$commit" "$arvore"; do
        grep -rqaF -- "$valor" "$dex/apk" || { echo "o APK nao leva $valor" >&2; exit 1; }
        grep -rqaF -- "$valor" "$dex/aab" || { echo "o AAB nao leva $valor" >&2; exit 1; }
    done
    # O nucleo e a libc++ que entraram no APK e no AAB sao os do carimbo do compilar-nucleo.sh, byte a byte: nada no
    # Gradle trocou o .so depois da conferencia (o strip fica desligado no build.gradle.kts; revisao dos 3 agentes da
    # checagem final de 16/11/2026).
    local carimbo_modo carimbo_commit carimbo_nucleo carimbo_libcxx biblioteca
    read -r carimbo_modo carimbo_commit carimbo_nucleo carimbo_libcxx < build/android-kit/origem-do-nucleo.txt
    [ "$carimbo_modo" = release-loja ] && [ "$carimbo_commit" = "$commit" ] \
        || { echo "o carimbo do nucleo nao e o do modo da loja deste commit: nada foi entregue" >&2; exit 1; }
    unzip -q "$apk" 'lib/arm64-v8a/libEscaliburAndroid.so' 'lib/arm64-v8a/libc++_shared.so' -d "$dex/apk-lib"
    unzip -q "$aab" 'base/lib/arm64-v8a/libEscaliburAndroid.so' 'base/lib/arm64-v8a/libc++_shared.so' -d "$dex/aab-lib"
    for biblioteca in "$dex/apk-lib/lib/arm64-v8a" "$dex/aab-lib/base/lib/arm64-v8a"; do
        [ "$(shasum -a 256 "$biblioteca/libEscaliburAndroid.so" | cut -d' ' -f1)" = "$carimbo_nucleo" ] \
            && [ "$(shasum -a 256 "$biblioteca/libc++_shared.so" | cut -d' ' -f1)" = "$carimbo_libcxx" ] \
            || { echo "o nucleo ou a libc++ no pacote nao sao os do carimbo: nada foi entregue" >&2; exit 1; }
    done
    rm -rf "$dex"
    # Numa pasta nova fora do repositorio, e nao na pasta de trabalho, que outra sessao edita (setima passada).
    local saida
    saida=$(mktemp -d "/private/tmp/escalibur-aab-$versao-$build.XXXXXX")
    mkdir -p "$saida"
    cp "$aab" "$apk" "$saida/"
    (cd "$saida" && shasum -a 256 app-release.aab app-release.apk > SHA256SUMS)
    echo "Android $versao ($build), commit $commit, arvore $arvore: $saida"
    cat "$saida/SHA256SUMS"
}

main() {
    if [ "${1:-}" = "--na-copia-limpa" ]; then
        shift
        segunda_fase "$@"
    else
        primeira_fase "$@"
    fi
}

main "$@"; exit
