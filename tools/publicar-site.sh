#!/bin/bash
# Publica o site da Escalibur Wallet (desde 19/10/2026):
# - em https://escaliburwallet.com/, o endereco da App Store Connect, por um Worker de arquivos
#   estaticos na Cloudflare (tools/site-cloudflare). O app nunca fala com esse servidor;
# - no repositorio publico Escalibur-Wallet/escalibur-wallet.github.io, na raiz, em
#   https://escalibur-wallet.github.io/: dali o app le a lista de versoes e abre a auditoria.
# So o site gerado sai daqui, nenhum codigo do app.
#
# O endereco antigo (tmzzjr.github.io/escalibur-wallet) saiu em 07/11/2026: estava fora do ar, os
# builds 7 a 9 do TestFlight que liam a lista de la ja nao conferiam a lista desde 23/10, e o clone
# dele deixava um commit de fora gravar neste Mac por link simbolico (revisao final de 07/11/2026).
#
#   tools/publicar-site.sh           gera e mostra o que mudaria
#   tools/publicar-site.sh --enviar  gera, faz o commit e envia
set -euo pipefail
cd "$(dirname "$0")/.."

NOVO_REPO=https://github.com/Escalibur-Wallet/escalibur-wallet.github.io.git
NOVO=build/site-publicado-org
URL=https://escalibur-wallet.github.io/
DOMINIO=https://escaliburwallet.com/

# So o commit publicado, com o CI verde (revisao final de 07/11/2026): o gerador le a arvore de
# trabalho inteira (os arquivos da auditoria, os locks, os docs, as politicas) e o Worker sai dela,
# entao uma mudanca fora do commit sairia no ar sob "gerado do commit X", e um commit que nao esta
# no GitHub deixaria os links do rodape em 404.
if [ "${1:-}" = "--enviar" ]; then
    [ -z "$(git status --porcelain --untracked-files=all)" ] || { echo "ha mudanca fora do commit: faca o commit e o push antes de enviar" >&2; exit 1; }
    git fetch -q origin main
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "o HEAD nao e a main publicada no GitHub: faca o push antes" >&2; exit 1; }
fi
swift tools/versoes/versoes.swift conferir >/dev/null || { echo "site/versoes.json nao confere: nada publicado" >&2; exit 1; }

clonar() { # repositorio pasta
    if [ ! -d "$2/.git" ]; then
        git clone -q "$1" "$2" 2>/dev/null || { mkdir -p "$2"; git -C "$2" init -q -b main; git -C "$2" remote add origin "$1"; }
    fi
    git -C "$2" pull -q --ff-only origin main 2>/dev/null || true
    # Nenhum link simbolico vindo do repositorio publicado: um commit de fora nao grava fora da pasta.
    [ -z "$(git -C "$2" ls-files -s | awk '$1==120000')" ] || { echo "link simbolico em $2: confira o repositorio publicado" >&2; exit 1; }
}
clonar "$NOVO_REPO" "$NOVO"

# A lista de versoes nunca volta atras: publicar de um commit antigo levaria uma lista sem a versao
# da loja, e o iPhone mostraria o alarme de hack (revisao final de 07/11/2026).
if [ -f "$NOVO/versoes.json" ]; then
    python3 -I - "$NOVO/versoes.json" site/versoes.json <<'PY' || { echo "site/versoes.json e mais antiga que a publicada: nada publicado" >&2; exit 1; }
import json, sys
def emitido(caminho):
    return json.loads(json.load(open(caminho, encoding="utf-8"))["manifesto"])["emitido"]
sys.exit(0 if emitido(sys.argv[2]) >= emitido(sys.argv[1]) else 1)
PY
fi

# O estado do CI do commit publicado, como o workflow do site fazia.
ci=$(mktemp)
pasta=$(mktemp -d)
trap 'rm -rf "$ci" "$pasta"' EXIT
gh api "repos/Escalibur-Wallet/escalibur-wallet/actions/workflows/verificar.yml/runs?head_sha=$(git rev-parse HEAD)&per_page=1" > "$ci" 2>/dev/null \
    || echo '{}' > "$ci"
if [ "${1:-}" = "--enviar" ]; then
    python3 -I -c 'import json, sys; r = json.load(open(sys.argv[1])).get("workflow_runs") or [{}]; sys.exit(0 if r[0].get("conclusion") == "success" else 1)' "$ci" \
        || { echo "o CI deste commit ainda nao passou: espere ele terminar verde" >&2; exit 1; }
fi
# SITE_PRECOS=1: o retrato dos precos do Mercado ao vivo, tirado agora no CoinGecko, vai em
# /precos.json. No dominio o Worker responde ao vivo no mesmo caminho e so usa o retrato se o
# CoinGecko falhar; no GitHub Pages, sem Worker, a pagina mostra o retrato.
SITE_PRECOS=1 SITE_CI="$ci" SITE_BASE=/ python3 -I tools/gerar-site.py "$pasta/novo"
rm -rf build/site-dominio && cp -R "$pasta/novo" build/site-dominio

# O site da org: o site gerado na raiz, sem Jekyll.
find "$NOVO" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$pasta/novo/." "$NOVO/"
touch "$NOVO/.nojekyll"

mudou=0
git -C "$NOVO" add -A
if git -C "$NOVO" diff --cached --quiet; then
    echo "$NOVO: ja publicado"
else
    mudou=1
    echo "$NOVO:"; git -C "$NOVO" diff --cached --stat | tail -2
    if [ "${1:-}" = "--enviar" ]; then
        # Sempre em nome da Escalibur, nunca com a identidade do git deste Mac.
        git -C "$NOVO" -c user.name="Escalibur" -c user.email="support@escaliburwallet.com" \
            commit -q -m "Escalibur Wallet site, from commit $(git rev-parse --short HEAD)"
        git -C "$NOVO" push -q origin main
    fi
fi
# O dominio: o Worker na conta da Cloudflare do dominio (login do wrangler em pasta propria,
# para nao trocar o login das outras contas desta maquina). O wrangler tem versao fixa, com
# o lock commitado e sem scripts de instalacao: um pacote do npm comprometido nao entra no
# proximo envio sozinho (auditoria de 30/10/2026). Subir a versao so de proposito, olhando o
# diff do package-lock.json. Instala em build/, fora da arvore do app: o verificar.sh recusa
# binario de terceiro ali.
if [ "${1:-}" = "--enviar" ]; then
    mkdir -p build/wrangler
    cp tools/site-cloudflare/package.json tools/site-cloudflare/package-lock.json build/wrangler/
    (cd build/wrangler && npm ci --ignore-scripts --no-audit --no-fund --silent)
    saida=$(XDG_CONFIG_HOME="$HOME/.config-cloudflare-escalibur" build/wrangler/node_modules/.bin/wrangler deploy --config tools/site-cloudflare/wrangler.jsonc 2>&1) \
        || { echo "$saida" | grep -E "error|✘" >&2; echo "o Worker do dominio nao foi publicado" >&2; exit 1; }
    echo "$saida" | grep -E "Deployed|Uploaded [0-9]" || true
    # O dominio mostra este commit: senao, o envio nao terminou.
    commit=$(git rev-parse HEAD)
    for tentativa in 1 2 3 4 5 6; do
        pagina=$(curl -fsS "$DOMINIO" || true)
        [[ "$pagina" == *"commit/$commit"* ]] && { echo "enviado: $DOMINIO e $URL"; exit 0; }
        sleep 10
    done
    echo "o dominio nao mostra o commit $commit: confira o Worker" >&2
    exit 1
elif [ $mudou = 1 ]; then echo "nada enviado (use --enviar)"; fi
