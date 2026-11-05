#!/bin/bash -p
# Compila o nucleo (Kit/) para Android e poe a biblioteca no app Android.
#
#   tools/android/compilar-nucleo.sh                release
#   tools/android/compilar-nucleo.sh debug
#   tools/android/compilar-nucleo.sh release --loja o da loja (tools/android/gerar-aab.sh, na copia limpa): do zero, e
#                                                   todo modulo conferido no log do build
#
# Pede o Swift aberto (6.4.1, instalado pelo swiftly em ~/Library/Developer/Toolchains), o
# Swift SDK para Android da mesma versao e o NDK r30 (docs/android.md). O Swift do Xcode
# continua sendo o padrao do terminal: este script chama o aberto pelo caminho.
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

CONFIG="${1:-release}"
LOJA="${2:-}"
[ -z "$LOJA" ] || [ "$LOJA" = "--loja" ] || { echo "uso: tools/android/compilar-nucleo.sh [release|debug] [--loja]" >&2; exit 2; }
[ -z "$LOJA" ] || [ "$CONFIG" = release ] || { echo "o nucleo da loja e o de release" >&2; exit 2; }
SWIFT=~/Library/Developer/Toolchains/swift-6.4.1-RELEASE.xctoolchain/usr/bin/swift
# O NDK e sempre o r30 da pasta de sempre: um do ambiente trocaria o sysroot e o linker de todo build, e nao so o da
# loja (revisao da decima terceira passada).
export ANDROID_NDK_HOME="$HOME/Library/Android/android-ndk-r30"
NDK_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64"
DESTINO=Android/app/src/main/jniLibs/arm64-v8a

[ -x "$SWIFT" ] || { echo "falta o Swift 6.4.1 aberto (swiftly install 6.4.1)" >&2; exit 1; }
# O que muda o compilador por fora do repositorio, conferido antes de compilar (decima terceira passada da auditoria de
# 03/11/2026): o clang le CCC_OVERRIDE_OPTIONS, os caminhos de include do ambiente e um `<alvo>-clang.cfg` da pasta dele; o
# driver do Swift troca o frontend por variaveis SWIFT_* dele; o xcrun e o swift trocam o Xcode inteiro por uma
# variavel do ambiente; o SwiftPM troca o compilador do C pelo CC; e o Swift SDK poe as opcoes do swift-toolset.json em cada
# chamada do C. O SDK e os `.cfg` do toolchain pelo digesto, e nenhuma configuracao a mais do SwiftPM.
for variavel in $(compgen -e); do
    case "$variavel" in
        CCC_*|CPATH|C_INCLUDE_PATH|CPLUS_INCLUDE_PATH|OBJC_INCLUDE_PATH|OBJCPLUS_INCLUDE_PATH|LIBRARY_PATH|COMPILER_PATH|GCC_EXEC_PREFIX|SDKROOT|DYLD_*|LD_*|SWIFT_*|SWIFTPM_*|TOOLCHAINS|XCODE_XCCONFIG_FILE|CLANG_*|RC_*|DEVELOPER_DIR|CC|CXX|LD|AR|LIBTOOL|CFLAGS|CXXFLAGS|CPPFLAGS|LDFLAGS|BASH_ENV|ENV|SHELLOPTS|BASHOPTS|PS4)
            echo "a variavel de ambiente $variavel muda o compilador por fora do repositorio: o build nao roda com ela" >&2; exit 1 ;;
    esac
done
SDK_ANDROID=~/Library/org.swift.swiftpm/swift-sdks/swift-6.4.1-RELEASE_android.artifactbundle
[ "$(cd "$SDK_ANDROID" && shasum -a 256 info.json swift-android/swift-sdk.json swift-android/swift-toolset.json | cut -d' ' -f1 | tr '\n' ' ')" \
    = "2e575cf7fddf562e65e1e9d8e73f542c4680c8bf8e36d175f90d2f9c9f988e23 36ac608b34584a21f7ea1a0f044a17e61ba88692a45b488ee906472a1729c9b9 0f9e3a784a4e60bf4c816460dae0ed64e0a723167af111fc05bac8a010b0e065 " ] \
    || { echo "o Swift SDK do Android nao e o conferido (swift-sdk.json, swift-toolset.json ou info.json mudou)" >&2; exit 1; }
[ -z "$(ls -A ~/Library/org.swift.swiftpm/swift-sdks/configuration 2>/dev/null)" ] \
    || { echo "ha configuracao do SwiftPM para os Swift SDKs (swift-sdks/configuration): o nucleo nao compila com ela" >&2; exit 1; }
[ "$(find "$(dirname "$SWIFT")/.." -name '*.cfg' -exec shasum -a 256 {} + | cut -d' ' -f1 | LC_ALL=C sort | tr '\n' ' ')" \
    = "46dee6b61cb6efb3748a08aefe5088961f7435767491e2b719d6e939d9a0dcf0 46dee6b61cb6efb3748a08aefe5088961f7435767491e2b719d6e939d9a0dcf0 b8ae741f12cebb7e1a4f3782ee75f83c0e4396a9c4dbdbcd3192d6ce48824afa b8ae741f12cebb7e1a4f3782ee75f83c0e4396a9c4dbdbcd3192d6ce48824afa " ] \
    || { echo "o toolchain tem um arquivo .cfg do clang que nao e um dos quatro conferidos" >&2; exit 1; }
[ -d "$ANDROID_NDK_HOME" ] || { echo "falta o NDK r30 em $ANDROID_NDK_HOME" >&2; exit 1; }
# O toolchain, o Swift SDK e o NDK sao os de sempre: os binarios que o build chama com a assinatura de quem os publica (a
# Swift Open Source e o Google), e, no build da loja, a arvore inteira de cada um pelo digesto, com as bibliotecas, os
# cabecalhos e os links pelo destino. As tres ficam numa pasta do usuario, que muda sem senha de administrador (revisao da
# decima terceira passada).
TOOLCHAIN=~/Library/Developer/Toolchains/swift-6.4.1-RELEASE.xctoolchain
for binario in swift swift-build swift-driver swift-frontend clang ld.lld; do
    codesign --verify --strict -R='anchor apple generic and certificate leaf[subject.OU] = "V9AUD2URP3"' "$TOOLCHAIN/usr/bin/$binario" 2>/dev/null \
        || { echo "o $binario do toolchain nao tem a assinatura da Swift Open Source" >&2; exit 1; }
done
for binario in clang ld.lld llvm-strip; do
    codesign --verify --strict -R='anchor apple generic and certificate leaf[subject.OU] = "EQHXZ8M8AV"' "$NDK_BIN/bin/$binario" 2>/dev/null \
        || { echo "o $binario do NDK nao tem a assinatura do Google" >&2; exit 1; }
done
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
if [ -n "$LOJA" ]; then
    [ "$(arvore "$TOOLCHAIN/usr")" = 44ce03df2d41af82411e4b180b5fb43327b8dee1a02e85b9b31ac4cea3748248 ] \
        && [ "$(arvore ~/Library/org.swift.swiftpm/swift-sdks/swift-6.4.1-RELEASE_android.artifactbundle)" = 938fe76a23621545eac3c4ed89652def09a23e34c87229ecb8c8b4a12ab70972 ] \
        && [ "$(arvore "$NDK_BIN")" = 7a6b0d0cca6c0efbf81f23f6f30b78cb921fd8970c023b9411402a9ef3ed8dfe ] \
        || { echo "o toolchain, o Swift SDK ou o NDK nao sao os conferidos (o digesto da arvore mudou)" >&2; exit 1; }
fi
# As flags do Swift do nucleo, lidas do pacote avaliado por este mesmo Swift: as que o verificador supoe, e nada mais
# (nona passada da auditoria de 03/11/2026).
# O SwiftPM so com o ambiente que o build precisa, o mesmo em toda sessao: nada do ambiente de quem chama chega ao
# compilador nem ao manifesto, e a chave do cache do manifesto (o ambiente inteiro, fora o do terminal) nao muda de uma vez
# para a outra. A pasta temporaria e a do usuario (700): o manifesto e compilado e roda dali (revisao da decima terceira
# passada).
swiftpm() {
    (cd Kit && env -i HOME="$HOME" PATH="$PATH" TMPDIR="$(getconf DARWIN_USER_TEMP_DIR)" ESCALIBUR_ANDROID=1 \
        ANDROID_NDK_HOME="$ANDROID_NDK_HOME" "$SWIFT" "$@")
}
swiftpm package dump-package 2>/dev/null | python3 -I tools/flags-do-pacote.py Kit/Package.swift \
    || { echo "o Package.swift define uma flag do Swift que o verificador nao conhece: nada foi compilado" >&2; exit 1; }

# Com a biblioteca do Swift estatica, o FoundationNetworking entra inteiro na .so e traz a
# libcurl, que pede o OpenSSL e a zlib do SDK e do NDK. A rede em si sai pelo transporte do
# Android (AndroidTransport.swift), nunca pela libcurl.
# Os caminhos do Mac (a pasta do repositorio e a do usuario) nao entram na biblioteca: sem o
# mapa, o __FILE__ da BoringSSL levava o nome do usuario para dentro do APK (auditoria 7).
# O C vendorizado (secp256k1, Argon2, BoringSSL) sai com o protetor de pilha explicito, e com o
# FORTIFY pelo cSettings dos alvos C no Package.swift: o Swift SDK nao passa pelo driver do NDK, que
# e quem liga os dois por padrao (auditoria Android de 31/10/2026, AA-07). O -D_FORTIFY_SOURCE nao
# pode vir por -Xcc: ele chega ao importador de C do Swift, e o open e o write da bionic viram
# sobrecargas que o Swift nao le (Metadados.swift nao compila). O verificar.sh confere no binario a
# pilha sem execucao, o RELRO e o BIND_NOW. A pilha zerada na declaracao (-ftrivial-auto-var-init=zero) e a
# do Enhanced Security do iOS, que no Package.swift so vale na Apple: aqui vai por -Xcc, que e so codegen.
# Com `-v`, o log tem cada chamada do compilador, e as flags que ele recebeu de fato sao conferidas (o manifesto podia
# se avaliar de um jeito na conferencia acima e de outro no build; decima passada da auditoria de 03/11/2026). O da
# loja compila do zero, e todo modulo tem de aparecer no log; o de quem desenvolve e incremental, e confere o que houve.
# Os avisos do compilador vao para outro arquivo: na mesma saida, um aviso entrava no meio de uma linha de comando, e o
# conferidor recusava a linha cortada (decima primeira passada).
RAIZ="$PWD"
if [ -n "$LOJA" ]; then
    [ ! -e build/android-kit ] || { echo "o nucleo da loja compila do zero, e build/android-kit ja existe" >&2; exit 1; }
    # O NDK da loja e o r30 da pasta de sempre, e nao um de outra pasta pelo ambiente (decima primeira passada).
    [ "$(cd "$ANDROID_NDK_HOME" && pwd -P)" = "$(cd "$HOME/Library/Android/android-ndk-r30" && pwd -P)" ] \
        || { echo "o nucleo da loja usa o NDK r30 em ~/Library/Android/android-ndk-r30" >&2; exit 1; }
fi
OPCOES=(--swift-sdk swift-6.4.1-RELEASE_android --triple aarch64-unknown-linux-android28 --static-swift-stdlib
    -Xcc -ffile-prefix-map="$RAIZ"=. -Xcc -ffile-prefix-map="$HOME"=~
    -Xcc -fstack-protector-strong -Xcc -ftrivial-auto-var-init=zero
    -Xswiftc -file-prefix-map -Xswiftc "$RAIZ"=. -Xswiftc -file-prefix-map -Xswiftc "$HOME"=~
    -Xlinker -lssl -Xlinker -lcrypto -Xlinker -lz -c "$CONFIG")
mkdir -p build
# O manifesto compilado antes, numa passada so do CJNI e noutra pasta, com o mesmo -v (que entra na chave do cache) e a
# saida descartada: no build conferido ele vem do cache, e a chamada do compilador dele (que o -v imprime como aviso) nao
# sai na saida de erro, que a conferencia abaixo recusa.
swiftpm build -v "${OPCOES[@]}" --scratch-path ../build/android-kit-manifesto --target CJNI > /dev/null 2>&1 \
    || { echo "o manifesto do Kit nao compilou" >&2; exit 1; }
swiftpm build -v "${OPCOES[@]}" --scratch-path ../build/android-kit --product EscaliburAndroid > "build/nucleo-$CONFIG.log" 2> "build/nucleo-$CONFIG-erros.log" \
    || { tail -40 "build/nucleo-$CONFIG-erros.log" "build/nucleo-$CONFIG.log" >&2; echo "o nucleo nao compilou (os logs em build/nucleo-$CONFIG*.log)" >&2; exit 1; }
# A lista fechada do conferidor e a do Release (o de depuracao tem -Onone, DEBUG e o build incremental).
if [ "$CONFIG" = release ]; then
    # Nenhuma chamada do compilador na saida de erro, que o conferidor nao le (decima segunda passada).
    ! grep -qE '(builtin-Swift|builtin-swift|/swiftc |/swift-frontend |/clang |/clang\+\+ )' "build/nucleo-$CONFIG-erros.log" \
        || { echo "uma chamada do compilador saiu na saida de erro do build, que o conferidor nao le" >&2; exit 1; }
    python3 -I tools/flags-do-build.py android "build/nucleo-$CONFIG.log" --build build/android-kit $([ -n "$LOJA" ] || echo --parcial) \
        || { echo "o build passou ao Swift uma flag, um alvo ou um plugin que o verificador nao conhece" >&2; exit 1; }
fi

mkdir -p "$DESTINO"
cp "build/android-kit/out/Products/$( [ "$CONFIG" = release ] && echo Release || echo Debug )-android-aarch64/libEscaliburAndroid.so" "$DESTINO/"
"$NDK_BIN/bin/llvm-strip" --strip-unneeded "$DESTINO/libEscaliburAndroid.so"
# A libc++ do NDK vem com simbolos de depuracao (9,4 MB): sai enxuta como o nucleo (AA-06). Ela roda no mesmo processo
# que as chaves: so a do NDK r30, pelo digesto (decima primeira passada da auditoria de 03/11/2026).
LIBCXX="$NDK_BIN/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
[ "$(shasum -a 256 "$LIBCXX" | cut -d' ' -f1)" = "7466ed097631a564ed6bff0b47768caa76bf03270d2047b5a65c03f497b824df" ] \
    || { echo "a libc++_shared.so do NDK nao e a do r30 conferido" >&2; exit 1; }
cp "$LIBCXX" "$DESTINO/"
"$NDK_BIN/bin/llvm-strip" --strip-unneeded "$DESTINO/libc++_shared.so"
# O C do nucleo que acabou de sair so chama o que o simbolos-c.lock permite, e nunca rede, exec,
# dlopen ou abrir arquivo (auditoria de 03/11/2026).
./tools/verificar.sh --c-android "$CONFIG" || { echo "o C do nucleo chama o que nao devia (veja acima)" >&2; exit 1; }
if strings -a "$DESTINO/libEscaliburAndroid.so" | grep -qF "$HOME"; then
    echo "a biblioteca ainda tem caminhos da pasta do usuario" >&2; exit 1
fi
# O carimbo de onde este nucleo saiu: a configuracao, o commit e os digestos do .so e da libc++. O release do Gradle so
# aceita o nucleo de release deste mesmo commit (quinta passada da auditoria de 03/11/2026: um .so velho, que o git
# ignora, ia num pacote carimbado com outro commit), e so o compilado pelo modo da loja, do zero e com o log conferido
# (decima primeira passada: um `release` sem `--loja`, rodado na copia limpa, passava).
mkdir -p build/android-kit
printf '%s %s %s %s\n' "$CONFIG${LOJA:+-loja}" "$(git rev-parse HEAD)" "$(shasum -a 256 "$DESTINO/libEscaliburAndroid.so" | cut -d' ' -f1)" \
    "$(shasum -a 256 "$DESTINO/libc++_shared.so" | cut -d' ' -f1)" > build/android-kit/origem-do-nucleo.txt
ls -la "$DESTINO"
