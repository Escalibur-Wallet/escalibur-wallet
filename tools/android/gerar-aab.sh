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
case "$-" in *p*) ;; *) _sem_p=; : "${_sem_p:?rode pelo caminho do script, e nao por bash script}" ;; esac
casa=$(/usr/bin/dscl . -read "/Users/$(/usr/bin/id -un)" NFSHomeDirectory | /usr/bin/sed -n 's/^NFSHomeDirectory: //p')
limpo=true
for variavel in $(compgen -e); do
    case "$variavel" in
        HOME|PATH|TMPDIR|USER|LOGNAME|LANG|TERM|PWD|OLDPWD|SHLVL|_|GIT_CONFIG_NOSYSTEM|GIT_CONFIG_GLOBAL|GIT_NO_REPLACE_OBJECTS|GIT_CONFIG_COUNT|GIT_CONFIG_KEY_0|GIT_CONFIG_VALUE_0|GIT_CONFIG_KEY_1|GIT_CONFIG_VALUE_1) ;;
        *) limpo=false ;;
    esac
done
[ -n "$casa" ] && [ "${HOME:-}" = "$casa" ] && [ "$PATH" = /usr/bin:/bin:/usr/sbin:/sbin ] && [ "${LANG:-}" = en_US.UTF-8 ] \
    && [ "${TMPDIR:-}" = "$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)" ] \
    && [ "${GIT_CONFIG_NOSYSTEM:-}" = 1 ] && [ "${GIT_CONFIG_GLOBAL:-}" = /dev/null ] && [ "${GIT_NO_REPLACE_OBJECTS:-}" = 1 ] \
    && [ "${GIT_CONFIG_COUNT:-}" = 2 ] && [ "${GIT_CONFIG_KEY_0:-}" = core.fsmonitor ] && [ "${GIT_CONFIG_VALUE_0:-}" = false ] \
    && [ "${GIT_CONFIG_KEY_1:-}" = core.hooksPath ] && [ "${GIT_CONFIG_VALUE_1:-}" = /dev/null ] || limpo=false
[ -n "$casa" ] || { echo "a pasta do usuario nao veio do servico de diretorio" >&2; exit 1; }
$limpo || exec /usr/bin/env -i HOME="$casa" USER="$(/usr/bin/id -un)" LOGNAME="$(/usr/bin/id -un)" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)" LANG=en_US.UTF-8 TERM="${TERM:-dumb}" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_COUNT=2 \
    GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null \
    /bin/bash -p "$0" "$@"

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
    printf 'sdk.dir=%s\n' "$ANDROID_HOME" > Android/local.properties

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
    ESCALIBUR_UPLOAD_SENHA="$(security find-generic-password -a escalibur-android -s escalibur-android-upload -w)"
    export ESCALIBUR_UPLOAD_SENHA
    # Sem o cache de configuracao (ele guardaria a senha da chave em disco, dentro de Android/.gradle) e sem
    # daemon (um daemon que sobra, se o build falhar, guardaria a senha no ambiente por horas).
    (cd "$aqui/Android" && ./gradlew -q --no-daemon --no-configuration-cache --dependency-verification strict -PcommitDeOrigem="$commit" -ParvoreDeOrigem="$arvore" bundleRelease assembleRelease)
    unset ESCALIBUR_UPLOAD_SENHA
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
