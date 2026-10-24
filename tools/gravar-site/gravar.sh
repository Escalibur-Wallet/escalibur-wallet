#!/bin/bash
# Grava as telas do site no simulador e gera os videos e capas de site/midia.
#
#     GRAVAR_UDID=<udid de um simulador> tools/gravar-site/gravar.sh [cena ...]
#     GRAVAR_UDID=<udid> tools/gravar-site/gravar.sh fotos     as fotos paradas (site/midia/foto-*.webp)
#
# Sem cena, grava todas. Os videos do site sao em ingles desde 23/10/2026 (pedido do dono):
# GRAVAR_IDIOMA=en por padrao (pt-BR tambem funciona). O simulador volta ao idioma que tinha.
# GRAVAR_LIMPO=1 reinstala o app do zero: a carteira de teste entra de novo, na moeda do
# idioma (dolar em ingles). O app sai do build Debug deste repositorio (modo demo, carteira
# publica de teste do BIP-39, PIN de teste) e cada cena e um teste de Cenas.swift que
# marca o inicio e o fim do gesto; o video e cortado entre as marcas, reduzido para
# 720 px de largura, em H.264 sem audio, com o fim fundido no comeco para o laco nao
# pular. Quando a cena marca `capa`, o laco gira para comecar nesse quadro. A capa
# (a imagem antes de o video tocar, e a unica sem JavaScript) e o primeiro quadro, em WebP.
#
# Cenas.swift tambem tem `testSafari`, que abre o site no Safari do simulador e
# fotografa tela a tela (SAFARI_URL, SAFARI_FOTOS): a conferencia no celular de verdade.
#
# So simulador: o UDID tem de estar na lista do simctl. Nenhuma cena passa pela tela
# das palavras da carteira.
#
# Precisa de: Xcode, xcodegen e ffmpeg (com libx264 e libwebp).

set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1
RAIZ=$(pwd)

U="${GRAVAR_UDID:-}"
if [ -z "$U" ] || ! xcrun simctl list devices | grep -q "($U)"; then
    echo "GRAVAR_UDID precisa ser o UDID de um simulador (xcrun simctl list devices)"
    exit 1
fi
for ferramenta in xcodegen ffmpeg; do
    command -v "$ferramenta" >/dev/null || { echo "falta $ferramenta"; exit 1; }
done

# As do site (os alertas sairam em 23/10/2026; o Safe Keyboard entrou). `alertas`, `promessa` e
# `mercado` continuam gravaveis pelo nome.
TODAS=(carteira receber trocar limite envio moeda teclado envelope ponte passphrase)
CENAS=("$@")
[ ${#CENAS[@]} -eq 0 ] && CENAS=("${TODAS[@]}")

SAIDA="$RAIZ/site/midia"
TRABALHO="$RAIZ/build/gravar-site"
mkdir -p "$SAIDA" "$TRABALHO/bruto"

IDIOMA="${GRAVAR_IDIOMA:-en}"
case "$IDIOMA" in
    en) LINGUA=en; LOCAL=en_US ;;
    pt|pt-BR) LINGUA=pt-BR; LOCAL=pt_BR ;;
    *) echo "GRAVAR_IDIOMA: en ou pt-BR"; exit 1 ;;
esac

echo "preparando o simulador $U ($LINGUA)"
xcrun simctl boot "$U" 2>/dev/null || true
xcrun simctl bootstatus "$U" -b >/dev/null
# O idioma de antes volta no fim, para o simulador ficar como estava.
LINGUA_ANTES=$(xcrun simctl spawn "$U" defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n()"' | cut -d, -f1)
LOCAL_ANTES=$(xcrun simctl spawn "$U" defaults read -g AppleLocale 2>/dev/null || true)
voltar_idioma() {
    [ -n "$LINGUA_ANTES" ] && xcrun simctl spawn "$U" defaults write -g AppleLanguages -array "$LINGUA_ANTES"
    [ -n "$LOCAL_ANTES" ] && xcrun simctl spawn "$U" defaults write -g AppleLocale "$LOCAL_ANTES"
    true
}
trap voltar_idioma EXIT
xcrun simctl spawn "$U" defaults write -g AppleLanguages -array "$LINGUA"
xcrun simctl spawn "$U" defaults write -g AppleLocale "$LOCAL"
xcrun simctl status_bar "$U" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 --operatorName ""

echo "compilando o app (Debug, modo demo)"
# O mesmo build do simulador e dos testes (CLAUDE.md: um build por tipo, reaproveitado).
xcodebuild -project EscaliburWallet.xcodeproj -scheme EscaliburWallet -configuration Debug -sdk iphonesimulator \
    -destination "id=$U" -derivedDataPath build/dd-ui build -quiet
[ "${GRAVAR_LIMPO:-0}" = 1 ] && xcrun simctl uninstall "$U" app.escalibur.wallet 2>/dev/null || true
xcrun simctl install "$U" build/dd-ui/Build/Products/Debug-iphonesimulator/EscaliburWallet.app

echo "compilando as cenas"
xcodegen generate --spec tools/gravar-site/project.yml --project "$TRABALHO" --quiet
xcodebuild build-for-testing -project "$TRABALHO/GravarSite.xcodeproj" -scheme Cenas -destination "id=$U" \
    -derivedDataPath "$TRABALHO/dd" -quiet

agora() { python3 -c 'import time; print(f"{time.time():.3f}")'; }

# grava <teste> <arquivo bruto>: grava a tela enquanto o teste roda e devolve
# "inicio duracao capa" (capa: segundos desde o inicio, 0 sem a marca)
grava() {
    local teste="$1" bruto="$2" marcas="$TRABALHO/marcas-$1.txt" log="$TRABALHO/gravacao-$1.log"
    rm -f "$marcas" "$bruto"
    xcrun simctl io "$U" recordVideo --codec=h264 --force "$bruto" >"$log" 2>&1 &
    local gravador=$!
    for _ in $(seq 1 100); do grep -q "Recording started" "$log" 2>/dev/null && break; sleep 0.1; done
    local t0
    t0=$(agora)
    TEST_RUNNER_GRAVACAO_MARCAS="$marcas" TEST_RUNNER_GRAVACAO_IDIOMA="$IDIOMA" xcodebuild test-without-building -project "$TRABALHO/GravarSite.xcodeproj" \
        -scheme Cenas -destination "id=$U" -derivedDataPath "$TRABALHO/dd" -only-testing:"Cenas/Cenas/$teste" -quiet \
        >"$TRABALHO/teste-$1.log" 2>&1 || { kill -INT "$gravador"; wait "$gravador" || true; echo "a cena $teste falhou: $TRABALHO/teste-$1.log" >&2; return 1; }
    # A gravacao do simulador comeca um pouco depois do "Recording started": a folga no fim
    # garante que o corte chega ate a marca `fim`.
    sleep 2
    kill -INT "$gravador"
    wait "$gravador" || true
    python3 - "$marcas" "$t0" <<'PY'
import sys
marcas = dict(l.split() for l in open(sys.argv[1]) if l.strip())
t0 = float(sys.argv[2])
inicio, fim = float(marcas["inicio"]) - t0, float(marcas["fim"]) - t0
capa = float(marcas["capa"]) - t0 - inicio if "capa" in marcas else 0
print(f"{max(inicio, 0):.3f} {fim - inicio:.3f} {max(capa, 0):.3f}")
PY
}

FILTRO_BASE="fps=30,scale=720:-2:flags=lanczos,format=yuv420p,setsar=1"
X264=(-c:v libx264 -preset veryslow -crf 27 -tune animation -profile:v high -movflags +faststart -an)

# laco <entrada> <duracao> <saida.mp4>: o ultimo meio segundo funde no primeiro.
laco() {
    local entrada="$1" dur="$2" saida="$3" fusao=0.5
    local corte
    corte=$(python3 -c "print(f'{$dur - $fusao:.3f}')")
    ffmpeg -nostdin -loglevel error -y -i "$entrada" -filter_complex \
        "[0:v]split[a][b];[b]trim=0:$fusao,setpts=PTS-STARTPTS[c];[a][c]xfade=transition=fade:duration=$fusao:offset=$corte,format=yuv420p" \
        "${X264[@]}" "$saida"
}

capa() {
    ffmpeg -nostdin -loglevel error -y -i "$1" -frames:v 1 -c:v libwebp -quality 82 -compression_level 6 "$2"
}

# gira <video> <segundos> <saida>: o laco passa a comecar no quadro da capa. O fim do
# laco ja funde no comeco, entao a emenda nova cai em quadros continuos.
gira() {
    local video="$1" t="$2" saida="$3"
    ffmpeg -nostdin -loglevel error -y -i "$video" -filter_complex \
        "[0:v]trim=start=$t,setpts=PTS-STARTPTS[a];[0:v]trim=end=$t,setpts=PTS-STARTPTS[b];[a][b]concat=n=2:v=1,format=yuv420p" \
        "${X264[@]}" "$saida"
}

corta() {
    # corta <bruto> <inicio> <duracao> <saida intermediaria> [velocidade]
    local filtro="$FILTRO_BASE"
    [ -n "${5:-}" ] && filtro="setpts=PTS/$5,$FILTRO_BASE"
    ffmpeg -nostdin -loglevel error -y -ss "$2" -i "$1" -t "$3" -vf "$filtro" -c:v libx264 -crf 12 -preset fast -an "$4"
}

# A troca anda um quarto mais rapido (pedido do dono, 23/10/2026: o video estava lento).
velocidade() { case "$1" in trocar) echo 1.25 ;; *) echo "" ;; esac; }

if [ "${CENAS[*]}" = fotos ]; then
    # As fotos paradas do fim do site: a Carteira e a pagina do bitcoin em cada periodo, em
    # tamanho cheio, para escolher a de grafico subindo. Saem em build/gravar-site/fotos.
    FOTOS="$TRABALHO/fotos"
    rm -rf "$FOTOS" && mkdir -p "$FOTOS"
    for teste in testFotos testCarteira; do
        TEST_RUNNER_GRAVACAO_FOTOS="$FOTOS" TEST_RUNNER_GRAVACAO_IDIOMA="$IDIOMA" xcodebuild test-without-building \
            -project "$TRABALHO/GravarSite.xcodeproj" -scheme Cenas -destination "id=$U" -derivedDataPath "$TRABALHO/dd" \
            -only-testing:"Cenas/Cenas/$teste" -quiet >"$TRABALHO/teste-$teste.log" 2>&1 || echo "$teste falhou: $TRABALHO/teste-$teste.log" >&2
    done
    ls "$FOTOS"
    exit 0
fi

for cena in "${CENAS[@]}"; do
    echo "cena: $cena"
    case "$cena" in
        envio)
            read -r i1 d1 _ < <(grava testEnviando "$TRABALHO/bruto/enviando.mp4")
            read -r i2 d2 _ < <(grava testEnviado "$TRABALHO/bruto/enviado.mp4")
            corta "$TRABALHO/bruto/enviando.mp4" "$i1" "$d1" "$TRABALHO/envio-a.mp4"
            corta "$TRABALHO/bruto/enviado.mp4" "$i2" "$d2" "$TRABALHO/envio-b.mp4"
            off=$(python3 -c "print(f'{$d1 - 0.4:.3f}')")
            ffmpeg -nostdin -loglevel error -y -i "$TRABALHO/envio-a.mp4" -i "$TRABALHO/envio-b.mp4" -filter_complex \
                "[0:v][1:v]xfade=transition=fade:duration=0.4:offset=$off,format=yuv420p" -c:v libx264 -crf 12 -preset fast -an \
                "$TRABALHO/envio-ab.mp4"
            total=$(python3 -c "print(f'{$d1 + $d2 - 0.4:.3f}')")
            laco "$TRABALHO/envio-ab.mp4" "$total" "$SAIDA/envio.mp4"
            ;;
        *)
            teste="test$(python3 -c "print('$cena'.capitalize())")"
            read -r inicio dur capa_em < <(grava "$teste" "$TRABALHO/bruto/$cena.mp4")
            vel=$(velocidade "$cena")
            corta "$TRABALHO/bruto/$cena.mp4" "$inicio" "$dur" "$TRABALHO/$cena-cortado.mp4" "$vel"
            if [ -n "$vel" ]; then
                dur=$(python3 -c "print(f'{$dur / $vel:.3f}')")
                capa_em=$(python3 -c "print(f'{$capa_em / $vel:.3f}')")
            fi
            if python3 -c "import sys; sys.exit(0 if 0.1 < $capa_em < $dur - 0.6 else 1)"; then
                laco "$TRABALHO/$cena-cortado.mp4" "$dur" "$TRABALHO/$cena-laco.mp4"
                gira "$TRABALHO/$cena-laco.mp4" "$capa_em" "$SAIDA/$cena.mp4"
            else
                laco "$TRABALHO/$cena-cortado.mp4" "$dur" "$SAIDA/$cena.mp4"
            fi
            ;;
    esac
    capa "$SAIDA/$cena.mp4" "$SAIDA/$cena.webp"
    echo "  $(du -h "$SAIDA/$cena.mp4" | cut -f1) $SAIDA/$cena.mp4"
done
