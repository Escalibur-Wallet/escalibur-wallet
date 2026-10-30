#!/bin/bash
# Publica o site da Escalibur Wallet (desde 19/10/2026):
# - em https://escaliburwallet.com/, o endereco da App Store Connect, por um Worker de arquivos
#   estaticos na Cloudflare (tools/site-cloudflare). O app nunca fala com esse servidor;
# - no repositorio publico Escalibur-Wallet/escalibur-wallet.github.io, na raiz, em
#   https://escalibur-wallet.github.io/: dali o app le a lista de versoes e abre a auditoria.
# So o site gerado sai daqui, nenhum codigo do app.
#
# O endereco antigo (tmzzjr.github.io/escalibur-wallet, repositorio tmzzjr/tmzzjr.github.io)
# continua recebendo a mesma publicacao: os builds 7 a 9 do TestFlight leem a lista de
# versoes de la. As paginas dele apontam o site novo como canonico.
#
#   tools/publicar-site.sh           gera e mostra o que mudaria
#   tools/publicar-site.sh --enviar  gera, faz o commit e envia
set -euo pipefail
cd "$(dirname "$0")/.."

NOVO_REPO=https://github.com/Escalibur-Wallet/escalibur-wallet.github.io.git
NOVO=build/site-publicado-org
ANTIGO_REPO=https://github.com/tmzzjr/tmzzjr.github.io.git
ANTIGO=build/site-publicado
URL=https://escalibur-wallet.github.io/

# So o que esta no commit, e com a lista de versoes que confere (auditoria 6): o site e de
# onde o app le a lista, e o gerador le a arvore de trabalho.
if [ "${1:-}" = "--enviar" ] && [ -n "$(git status --porcelain -- site tools/gerar-site.py tools/gerador_site App/EscaliburWallet/Resources/Legal)" ]; then
    echo "o site ou o gerador tem mudanca fora do commit: faca o commit antes de enviar" >&2
    exit 1
fi
swift tools/versoes/versoes.swift conferir >/dev/null || { echo "site/versoes.json nao confere: nada publicado" >&2; exit 1; }

clonar() { # repositorio pasta
    if [ ! -d "$2/.git" ]; then
        git clone -q "$1" "$2" 2>/dev/null || { mkdir -p "$2"; git -C "$2" init -q -b main; git -C "$2" remote add origin "$1"; }
    fi
    git -C "$2" pull -q --ff-only origin main 2>/dev/null || true
}
clonar "$NOVO_REPO" "$NOVO"
clonar "$ANTIGO_REPO" "$ANTIGO"

# O estado do CI do commit publicado, como o workflow do site fazia.
ci=$(mktemp)
pasta=$(mktemp -d)
trap 'rm -rf "$ci" "$pasta"' EXIT
gh api "repos/Escalibur-Wallet/escalibur-wallet/actions/workflows/verificar.yml/runs?head_sha=$(git rev-parse HEAD)&per_page=1" > "$ci" 2>/dev/null \
    || echo '{}' > "$ci"
# SITE_PRECOS=1: o retrato dos precos do Mercado ao vivo, tirado agora no CoinGecko, vai em
# /precos.json. No dominio o Worker responde ao vivo no mesmo caminho e so usa o retrato se o
# CoinGecko falhar; nos enderecos do GitHub Pages, sem Worker, a pagina mostra o retrato.
SITE_PRECOS=1 SITE_CI="$ci" SITE_BASE=/ python3 tools/gerar-site.py "$pasta/novo"
rm -rf build/site-dominio && cp -R "$pasta/novo" build/site-dominio
SITE_PRECOS=1 SITE_CI="$ci" SITE_BASE=/escalibur-wallet/ python3 tools/gerar-site.py "$pasta/antigo"

# O site da org: o site gerado na raiz, sem Jekyll.
find "$NOVO" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$pasta/novo/." "$NOVO/"
touch "$NOVO/.nojekyll"

# O endereco antigo: a mesma publicacao na pasta escalibur-wallet/, e a raiz da conta
# levando para o site novo.
rm -rf "$ANTIGO/escalibur-wallet"
cp -R "$pasta/antigo" "$ANTIGO/escalibur-wallet"
cp "$pasta/antigo/404.html" "$ANTIGO/404.html"
touch "$ANTIGO/.nojekyll"
cat > "$ANTIGO/index.html" <<HTML
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Escalibur Wallet</title>
<meta http-equiv="refresh" content="0; url=$URL">
<link rel="canonical" href="$URL">
</head>
<body><p><a href="$URL">Escalibur Wallet</a></p></body>
</html>
HTML

mudou=0
for destino in "$NOVO" "$ANTIGO"; do
    git -C "$destino" add -A
    if git -C "$destino" diff --cached --quiet; then
        echo "$destino: ja publicado"
        continue
    fi
    mudou=1
    echo "$destino:"; git -C "$destino" diff --cached --stat | tail -2
    if [ "${1:-}" = "--enviar" ]; then
        # Sempre em nome da Escalibur, nunca com a identidade do git deste Mac.
        git -C "$destino" -c user.name="Escalibur" -c user.email="support@escaliburwallet.com" \
            commit -q -m "Escalibur Wallet site, from commit $(git rev-parse --short HEAD)"
        git -C "$destino" push -q origin main
    fi
done
# O dominio: o Worker na conta da Cloudflare do dominio (login do wrangler em pasta propria,
# para nao trocar o login das outras contas desta maquina).
if [ "${1:-}" = "--enviar" ]; then
    XDG_CONFIG_HOME="$HOME/.config-cloudflare-escalibur" npx -y wrangler deploy --config tools/site-cloudflare/wrangler.jsonc 2>&1 \
        | grep -E "Deployed|Uploaded [0-9]|error|✘" || true
    echo "enviado: https://escaliburwallet.com/ e $URL"
elif [ $mudou = 1 ]; then echo "nada enviado (use --enviar)"; fi
