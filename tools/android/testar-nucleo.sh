#!/bin/bash
# Roda os testes do nucleo (Core, Chains, Network) num Android de verdade: o emulador ou o
# aparelho ligado pelo adb.
#
#   tools/android/testar-nucleo.sh                       os tres
#   tools/android/testar-nucleo.sh EscaliburNetworkTests
#
# Os testes sao compilados com a biblioteca do Swift dinamica (o modulo Testing nao existe na
# estatica) e vao para /data/local/tmp/escalibur com as .so do Swift SDK e a libc++ do NDK. Os
# arquivos de teste que os testes leem do repositorio vao junto, num tar; ESCALIBUR_RAIZ diz onde
# eles ficaram no aparelho (CaminhoDoRepositorio.swift).
set -euo pipefail
cd "$(dirname "$0")/../.."
K=$PWD

SWIFT=~/Library/Developer/Toolchains/swift-6.4.1-RELEASE.xctoolchain/usr/bin/swift
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$HOME/Library/Android/android-ndk-r30}"
ADB=${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb
SDK_LIBS=~/Library/org.swift.swiftpm/swift-sdks/swift-6.4.1-RELEASE_android.artifactbundle/swift-android/swift-resources/usr/lib/swift-aarch64/android
NDK_LIBS=$(ls -d "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/sysroot/usr/lib/aarch64-linux-android | head -1)
D=/data/local/tmp/escalibur
P=$K/build/android-kit-testes/out/Products/Debug-android-aarch64
TESTES=("${@:-EscaliburCoreTests EscaliburChainsTests EscaliburNetworkTests}")
read -r -a TESTES <<< "${TESTES[*]}"

"$ADB" get-state > /dev/null || { echo "nenhum Android no adb (ligue o emulador)" >&2; exit 1; }

(cd Kit && ESCALIBUR_ANDROID=1 "$SWIFT" build --build-tests --swift-sdk swift-6.4.1-RELEASE_android \
    --triple aarch64-unknown-linux-android28 --scratch-path ../build/android-kit-testes > ../build/android-testes.log 2>&1) \
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
    "$ADB" shell "cd $D && ESCALIBUR_RAIZ=$D/repo ESCALIBUR_RAIZ_MAC=$K LD_LIBRARY_PATH=$D ./$t-test-runner --testing-library swift-testing 2>&1" > "$L" 2>&1 || falhou=1
    echo "== $t: $(tail -1 "$L" | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-120)"
    grep "recorded an issue" "$L" | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-260 | head -10 || true
done
exit $falhou
