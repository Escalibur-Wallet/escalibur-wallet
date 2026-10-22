#!/bin/bash
# Compila o nucleo (Kit/) para Android e poe a biblioteca no app Android.
#
#   tools/android/compilar-nucleo.sh            release (o que vai para a loja)
#   tools/android/compilar-nucleo.sh debug
#
# Pede o Swift aberto (6.4.1, instalado pelo swiftly em ~/Library/Developer/Toolchains), o
# Swift SDK para Android da mesma versao e o NDK r30 (docs/android.md). O Swift do Xcode
# continua sendo o padrao do terminal: este script chama o aberto pelo caminho.
set -euo pipefail
cd "$(dirname "$0")/../.."

CONFIG="${1:-release}"
SWIFT=~/Library/Developer/Toolchains/swift-6.4.1-RELEASE.xctoolchain/usr/bin/swift
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$HOME/Library/Android/android-ndk-r30}"
NDK_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64"
DESTINO=Android/app/src/main/jniLibs/arm64-v8a

[ -x "$SWIFT" ] || { echo "falta o Swift 6.4.1 aberto (swiftly install 6.4.1)" >&2; exit 1; }
[ -d "$ANDROID_NDK_HOME" ] || { echo "falta o NDK r30 em $ANDROID_NDK_HOME" >&2; exit 1; }

# Com a biblioteca do Swift estatica, o FoundationNetworking entra inteiro na .so e traz a
# libcurl, que pede o OpenSSL e a zlib do SDK e do NDK. A rede em si sai pelo transporte do
# Android (AndroidTransport.swift), nunca pela libcurl.
# Os caminhos do Mac (a pasta do repositorio e a do usuario) nao entram na biblioteca: sem o
# mapa, o __FILE__ da BoringSSL levava o nome do usuario para dentro do APK (auditoria 7).
RAIZ="$PWD"
(cd Kit && ESCALIBUR_ANDROID=1 "$SWIFT" build --swift-sdk swift-6.4.1-RELEASE_android \
    --triple aarch64-unknown-linux-android28 --static-swift-stdlib \
    -Xcc -ffile-prefix-map="$RAIZ"=. -Xcc -ffile-prefix-map="$HOME"=~ \
    -Xswiftc -file-prefix-map -Xswiftc "$RAIZ"=. -Xswiftc -file-prefix-map -Xswiftc "$HOME"=~ \
    -Xlinker -lssl -Xlinker -lcrypto -Xlinker -lz \
    --scratch-path ../build/android-kit --product EscaliburAndroid -c "$CONFIG")

mkdir -p "$DESTINO"
cp "build/android-kit/out/Products/$( [ "$CONFIG" = release ] && echo Release || echo Debug )-android-aarch64/libEscaliburAndroid.so" "$DESTINO/"
"$NDK_BIN/bin/llvm-strip" --strip-unneeded "$DESTINO/libEscaliburAndroid.so"
cp "$NDK_BIN/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$DESTINO/"
if strings -a "$DESTINO/libEscaliburAndroid.so" | grep -qF "$HOME"; then
    echo "a biblioteca ainda tem caminhos da pasta do usuario" >&2; exit 1
fi
ls -la "$DESTINO"
