#!/bin/bash -p
# Roda os testes do nucleo (Core, Chains, Network) num Android de verdade: o emulador ou o
# aparelho ligado pelo adb.
#
#   tools/android/testar-nucleo.sh                       os tres
#   tools/android/testar-nucleo.sh EscaliburNetworkTests
#   tools/android/testar-nucleo.sh --derivacao           so os vetores da frase ao endereco, no
#                                                        nucleo otimizado como o da loja (trava do gerar-aab.sh)
#
# O Android troca o CommonCrypto pela BoringSSL, o CryptoKit pela swift-crypto e o NFKD da Apple pelo
# da Foundation de fora da Apple. Os vetores BIP-32, SLIP-10, Icarus e de endereco por rede tem de
# passar aqui tambem: divergir seria gerar enderecos que o mesmo papel nao reabre em outro lugar
# (revisao de blockchain de 26/10/2026).
#
# Os testes sao compilados com a biblioteca do Swift dinamica (o modulo Testing nao existe na
# estatica) e vao para /data/local/tmp/escalibur com as .so do Swift SDK e a libc++ do NDK. Os
# arquivos de teste que os testes leem do repositorio vao junto, num tar; ESCALIBUR_RAIZ diz onde
# eles ficaram no aparelho (CaminhoDoRepositorio.swift).
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
cd "$(dirname "$0")/../.."
K=$PWD

SWIFT=~/Library/Developer/Toolchains/swift-6.4.1-RELEASE.xctoolchain/usr/bin/swift
# O NDK e sempre o r30 da pasta de sempre, como no compilar-nucleo.sh.
export ANDROID_NDK_HOME="$HOME/Library/Android/android-ndk-r30"
ADB=$HOME/Library/Android/sdk/platform-tools/adb
SDK_LIBS=~/Library/org.swift.swiftpm/swift-sdks/swift-6.4.1-RELEASE_android.artifactbundle/swift-android/swift-resources/usr/lib/swift-aarch64/android
NDK_LIBS=$(ls -d "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/sysroot/usr/lib/aarch64-linux-android | head -1)
D=/data/local/tmp/escalibur
CONFIG=debug
FILTRO=""
if [ "${1:-}" = "--derivacao" ]; then
    shift
    set -- EscaliburCoreTests EscaliburKeysTests
    FILTRO="Mnemonic|BIP39|Derivation|DeriveAllChains|AddressVector|Signer|SigningSelfTest"
    # Os vetores no nucleo otimizado como o da loja (-O), e nao no de depuracao: uma divergencia no NFKD, no BIP-32 ou no
    # endereco que so aparecesse com o otimizador sairia na loja (decima segunda passada da auditoria de 03/11/2026). O
    # modulo Testing pede a biblioteca do Swift dinamica, e o `@testable`, o -enable-testing.
    CONFIG=release
fi
PASTA=build/android-kit-testes$([ "$CONFIG" = release ] && echo -release || true)
P=$K/$PASTA/out/Products/$([ "$CONFIG" = release ] && echo Release || echo Debug)-android-aarch64
TESTES=("${@:-EscaliburCoreTests EscaliburChainsTests EscaliburNetworkTests}")
read -r -a TESTES <<< "${TESTES[*]}"

"$ADB" get-state > /dev/null || { echo "nenhum Android no adb (ligue o emulador)" >&2; exit 1; }

(cd Kit && env -i HOME="$HOME" PATH="$PATH" TMPDIR="$(getconf DARWIN_USER_TEMP_DIR)" ESCALIBUR_ANDROID=1 \
    ANDROID_NDK_HOME="$ANDROID_NDK_HOME" "$SWIFT" build --build-tests --swift-sdk swift-6.4.1-RELEASE_android -c "$CONFIG" \
    $([ "$CONFIG" = release ] && echo -Xswiftc -enable-testing || true) \
    --triple aarch64-unknown-linux-android28 --scratch-path "../$PASTA" > ../build/android-testes.log 2>&1) \
    || { echo "a compilacao dos testes falhou (build/android-testes.log)" >&2; grep error: build/android-testes.log | head >&2; exit 1; }

"$ADB" shell "mkdir -p $D"
"$ADB" push -q "$SDK_LIBS"/*.so "$NDK_LIBS/libc++_shared.so" "$D/"
(cd "$P" && "$ADB" push -q ./*-test-runner ./*Tests.so "$D/" && for b in *.bundle; do "$ADB" push -q "$b" "$D/"; done)

tar --exclude="*.mp4" --exclude="Moeda3D" -czf build/repo-teste.tgz Kit/Tests Kit/Sources site/versoes.json project.yml App/EscaliburWallet
"$ADB" push -q build/repo-teste.tgz "$D/"
"$ADB" shell "cd $D && rm -rf repo && mkdir repo && tar -xzf repo-teste.tgz -C repo && rm repo-teste.tgz"
rm build/repo-teste.tgz

falhou=0
for t in "${TESTES[@]}"; do
    L=build/android-$t.log
    filtro=""
    [ -n "$FILTRO" ] && filtro="--filter '$FILTRO'"
    "$ADB" shell "cd $D && ESCALIBUR_RAIZ=$D/repo ESCALIBUR_RAIZ_MAC=$K LD_LIBRARY_PATH=$D ./$t-test-runner --testing-library swift-testing $filtro 2>&1" > "$L" 2>&1 || falhou=1
    echo "== $t: $(tail -1 "$L" | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-120)"
    grep "recorded an issue" "$L" | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-260 | head -10 || true
    # Os vetores rodaram todos: uma suite renomeada deixava o filtro vazio, e "0 testes passaram" contava como verde
    # (decima terceira passada). Vetor novo pede atualizar o numero aqui.
    if [ -n "$FILTRO" ]; then
        esperado=0
        if [ "$t" = EscaliburCoreTests ]; then esperado=11; fi
        if [ "$t" = EscaliburKeysTests ]; then esperado=40; fi
        sed 's/\x1b\[[0-9;]*m//g' "$L" | grep -qE "Test run with $esperado tests? in [0-9]+ suites? passed" \
            || { echo "== $t: nao rodaram os $esperado vetores esperados" >&2; falhou=1; }
    fi
done
exit $falhou
