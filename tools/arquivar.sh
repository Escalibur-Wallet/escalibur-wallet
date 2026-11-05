#!/bin/bash -p
# O archive do iPhone para a loja: so do codigo publicado na main do GitHub, numa copia limpa
# (tools/copia-publicada.sh), com o commit e a arvore dentro do app (a tela de Ajustes mostra o commit).
# Quem audita o GitHub confere que e este o codigo (auditoria de 03/11/2026). Depois do archive, as
# mesmas conferencias do release.yml. Assinar, exportar e enviar seguem docs/release.md.
#
# Duas fases: a primeira, daqui, monta a copia limpa; a segunda roda o arquivar.sh de dentro dela, o
# publicado. O corpo fica em funcoes: o bash le cada uma inteira antes de rodar, e editar este arquivo
# durante o archive nao muda o que roda (quarta passada da auditoria de 03/11/2026).
#
#   tools/arquivar.sh <build>      grava /private/tmp/escalibur-arquivo-<versao>-<build>.*/EscaliburWallet.xcarchive
#
# O archive sai numa pasta nova fora do repositorio (so do dono, 700), e nao na pasta de trabalho, que outra sessao
# edita; e o digesto da arvore do .app sai no fim, para conferir antes de assinar (sexta passada de 03/11/2026).
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
    cd "$(dirname "$0")/.."
    local build="${1:?uso: tools/arquivar.sh <build>}"
    source tools/copia-publicada.sh
    /bin/bash -p "$limpa/tools/arquivar.sh" --na-copia-limpa "$build" "$raiz" "$commit" "$arvore"
}

segunda_fase() {
    local build="$1" raiz="$2" commit="$3" arvore="$4" aqui
    cd "$(dirname "$0")/.."
    aqui=$(pwd -P)
    [ "$(git rev-parse --show-toplevel)" = "$aqui" ] && [ "$aqui" != "$(cd "$raiz" && pwd -P)" ] \
        && [ "$(git rev-parse HEAD)" = "$commit" ] && [ "$(git rev-parse 'HEAD^{tree}')" = "$arvore" ] \
        && [ -z "$(git status --porcelain=v1 --untracked-files=all --ignored)" ] && [ -z "$(git ls-files -v | grep -v '^H ')" ] \
        || { echo "a segunda fase nao esta na copia limpa do commit publicado" >&2; exit 1; }
    local versao saida app digesto
    versao=$(sed -n 's/^ *MARKETING_VERSION: *"\([0-9.]*\)".*/\1/p' project.yml | head -1)
    saida=$(mktemp -d "/private/tmp/escalibur-arquivo-$versao-$build.XXXXXX")
    # Um xcconfig do ambiente sobrescreveria os ajustes do projeto, flags do Swift inclusive; e as flags do pacote sao
    # conferidas aqui, no caminho de verdade do build, que um manifesto podia distinguir (nona passada).
    unset XCODE_XCCONFIG_FILE
    # Nada no ambiente que mude o compilador por fora do repositorio (decima terceira passada).
    for variavel in $(compgen -e); do
        case "$variavel" in
            CCC_*|CPATH|C_INCLUDE_PATH|CPLUS_INCLUDE_PATH|OBJC_INCLUDE_PATH|OBJCPLUS_INCLUDE_PATH|LIBRARY_PATH|COMPILER_PATH|GCC_EXEC_PREFIX|SDKROOT|DYLD_*|LD_*|SWIFT_*|SWIFTPM_*|TOOLCHAINS|XCODE_XCCONFIG_FILE|CLANG_*|RC_*|DEVELOPER_DIR|CC|CXX|LD|AR|LIBTOOL|CFLAGS|CXXFLAGS|CPPFLAGS|LDFLAGS|BASH_ENV|ENV|SHELLOPTS|BASHOPTS|PS4)
                echo "a variavel de ambiente $variavel muda o compilador por fora do repositorio: o build nao roda com ela" >&2; exit 1 ;;
        esac
    done
    # O Xcode do .xcode-version, como no release.yml: o leitor avalia `#if compiler(...)` com a versao dele (decima
    # primeira passada da auditoria de 03/11/2026).
    [ "$(xcodebuild -version | head -1)" = "$(cat .xcode-version)" ] \
        || { echo "o Xcode ativo nao e o do .xcode-version ($(cat .xcode-version)): nada foi montado" >&2; exit 1; }
    # E o da pasta de sempre, no build exato, com o compilador, o clang e o ld assinados pela Apple: uma copia alterada
    # ou um beta da mesma versao diz o mesmo nome (revisao da decima terceira passada). O CI escolhe o dele pelo nome.
    local ferramenta
    [ "$(xcode-select -p)" = /Applications/Xcode.app/Contents/Developer ] && [ "$(xcodebuild -version | sed -n 2p)" = "Build version 17F113" ] \
        || { echo "o Xcode ativo nao e o /Applications/Xcode.app do build 17F113: nada foi montado" >&2; exit 1; }
    # E o hash exato da assinatura de cada um no 17F113: um binario da Apple de outro Xcode tambem tem o selo.
    for ferramenta in swift-frontend:11fd09c613e42ab16630ab94892cc9409b02c1aa clang:20a014a92f165cfaf456ba661639d0535043c4b7 \
                      ld:08fef69d7476af67d62beb5a812153a22d356ffe; do
        codesign --verify --strict -R="anchor apple and cdhash H\"${ferramenta#*:}\"" \
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/${ferramenta%%:*}" 2>/dev/null \
            || { echo "o ${ferramenta%%:*} do Xcode nao e o do build 17F113 assinado pela Apple: nada foi montado" >&2; exit 1; }
    done
    (cd Kit && swift package dump-package 2>/dev/null) | python3 -I tools/flags-do-pacote.py Kit/Package.swift \
        || { echo "o Package.swift define uma flag do Swift que o verificador nao conhece: nada foi montado" >&2; exit 1; }
    # O log inteiro, e nao `-quiet`: as flags que o compilador recebeu de fato sao conferidas nele, todo modulo nosso
    # compilado ao menos uma vez (o build e do zero, na copia limpa). O manifesto podia se avaliar de um jeito na
    # conferencia acima e de outro no build (decima passada).
    xcodebuild -project EscaliburWallet.xcodeproj -scheme EscaliburWallet -configuration Release \
        -destination 'generic/platform=iOS' -archivePath "$saida/EscaliburWallet.xcarchive" -derivedDataPath "$aqui/build/dd-release" \
        CURRENT_PROJECT_VERSION="$build" ESCALIBUR_COMMIT="$commit" ESCALIBUR_TREE="$arvore" CODE_SIGNING_ALLOWED=NO archive \
        > "$saida/archive.log" 2> "$saida/archive-erros.log" \
        || { tail -40 "$saida/archive-erros.log" "$saida/archive.log" >&2; echo "o archive falhou (os logs em $saida)" >&2; exit 1; }
    ! grep -qE '(builtin-Swift|builtin-swift|/swiftc |/swift-frontend |/clang |/clang\+\+ )' "$saida/archive-erros.log" \
        || { echo "uma chamada do compilador saiu na saida de erro do archive, que o conferidor nao le" >&2; exit 1; }
    python3 -I tools/flags-do-build.py ios "$saida/archive.log" --build "$aqui/build/dd-release" \
        || { echo "o build passou ao Swift uma flag, um alvo ou um plugin que o verificador nao conhece: nada foi montado" >&2; exit 1; }
    app="$saida/EscaliburWallet.xcarchive/Products/Applications/EscaliburWallet.app"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :EscaliburCommit' "$app/Info.plist")" = "$commit" ] \
        && [ "$(/usr/libexec/PlistBuddy -c 'Print :EscaliburTree' "$app/Info.plist")" = "$arvore" ] \
        || { echo "o app nao leva o commit $commit e a arvore $arvore no Info.plist" >&2; exit 1; }
    for plist in "$app/Info.plist" "$app/PlugIns/EscaliburWidgets.appex/Info.plist"; do
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$versao" ] \
            && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" = "$build" ] \
            || { echo "$plist sem a versao $versao ($build)" >&2; exit 1; }
    done
    swift tools/versoes/versoes.swift conferir-app "$app" \
        || { echo "o app nao leva a lista assinada que autoriza $versao ($build)" >&2; exit 1; }
    if strings "$app/EscaliburWallet" | grep -E "abandon abandon abandon|DebugDemo|envio-incerto|enviar-eth"; then
        echo "o binario de distribuicao carrega codigo do modo demo" >&2
        exit 1
    fi
    # O export segue o ApplicationPath do Info.plist do archive: so o app daqui, e nada mais em Products/Applications
    # (setima passada da auditoria de 03/11/2026).
    [ "$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:ApplicationPath' "$saida/EscaliburWallet.xcarchive/Info.plist")" = "Applications/EscaliburWallet.app" ] \
        && [ "$(ls -A "$saida/EscaliburWallet.xcarchive/Products/Applications")" = "EscaliburWallet.app" ] \
        || { echo "o archive tem outro app ou outro ApplicationPath" >&2; exit 1; }
    digesto=$(tools/digesto.sh "$saida/EscaliburWallet.xcarchive")
    echo "archive de $versao ($build), commit $commit, arvore $arvore: $saida"
    echo "digesto do archive: $digesto (antes de assinar, com o script do commit publicado:"
    echo "  git -C $raiz show $commit:tools/digesto.sh | /usr/bin/env -i /bin/bash -p -s -- $saida/EscaliburWallet.xcarchive  tem de dar o mesmo)"
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
