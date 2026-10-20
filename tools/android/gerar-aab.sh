#!/bin/bash
# Gera o pacote da Google Play (AAB) e um APK de release para conferir no emulador: o nucleo em
# release, o app minificado e os dois assinados com a chave de upload.
#
#   tools/android/gerar-aab.sh
#
# A chave fica em ~/.escalibur/android/upload.jks e a senha no Keychain do Mac
# (conta escalibur-android, servico escalibur-android-upload). Nada disso vai para o repositorio.
set -euo pipefail
cd "$(dirname "$0")/../.."

# A lista assinada que vai dentro do app precisa autorizar esta versao e este build (docs/release.md,
# "Autorizar a versao"): sem isso, nada e gerado.
versao=$(grep -oE 'versionName = "[^"]+"' Android/app/build.gradle.kts | sed -E 's/.*"(.*)"/\1/')
build=$(grep -oE 'versionCode = [0-9]+' Android/app/build.gradle.kts | grep -oE '[0-9]+')
python3 - "$versao" "$build" <<'PY' || { echo "a lista assinada nao autoriza $versao ($build): swift tools/versoes/versoes.swift autorizar $versao $build escalibur-mac-1" >&2; exit 1; }
import json, sys
versao, build = sys.argv[1], sys.argv[2]
envelope = json.load(open("App/EscaliburWallet/Resources/Versoes/versoes.json"))
manifesto = json.loads(envelope["manifesto"])
sys.exit(0 if any(v["versao"] == versao and build in v["builds"] for v in manifesto["versoes"]) else 1)
PY
swift tools/versoes/versoes.swift conferir

tools/android/compilar-nucleo.sh release
export JAVA_HOME="${JAVA_HOME:-$HOME/Library/Java/JavaVirtualMachines/jdk-21.0.12.1+1/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ESCALIBUR_UPLOAD_SENHA="$(security find-generic-password -a escalibur-android -s escalibur-android-upload -w)"
export ESCALIBUR_UPLOAD_SENHA
(cd Android && ./gradlew -q bundleRelease assembleRelease)
unset ESCALIBUR_UPLOAD_SENHA
ls -la Android/app/build/outputs/bundle/release/ Android/app/build/outputs/apk/release/
