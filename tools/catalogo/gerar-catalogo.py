#!/usr/bin/env python3
"""Gera a lista de moedas com as redes que o Receber do iPhone traz dentro do app.

Com a lista embarcada, tocar numa moeda da busca nao pergunta nada ao CoinGecko: as redes
e os contratos ja estao no app (pedido do dono, 30/10/2026, depois de "O CoinGecko pediu
uma pausa" na busca da BNB Tiger). A busca tambem cai nela quando o CoinGecko e o
CoinPaprika nao respondem. Moeda listada depois do build segue pela leitura na rede.

Fontes, sem chave:
- `GET /coins/list?include_platform=true`: id, simbolo, nome e o contrato em cada rede;
- `GET /coins/markets` (4 paginas de 250): a posicao no mercado das 1.000 maiores, para a
  busca na lista por em cima a moeda de verdade e nao a copia com o mesmo simbolo.

So entram as redes em que a carteira recebe token por endereco (EVM, Solana, Tron e TON),
pelo id da rede em Chain.swift. Moeda sem nenhuma dessas redes entra sem contrato: o app ja
sabe, sem perguntar, que ainda nao recebe ela. O app confere tudo de novo ao ler
(`CoinList`): nome e simbolo limpos, formato do contrato, simbolo protegido e contrato ja na
lista verificada.

    python3 tools/catalogo/gerar-catalogo.py
"""
import json, os, re, sys, time, urllib.error, urllib.request

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MERCADO = os.path.join(RAIZ, "Kit/Sources/EscaliburNetwork/Market.swift")
SAIDA = os.path.join(RAIZ, "App/EscaliburWallet/Resources/catalogo-moedas.json")
API = "https://api.coingecko.com/api/v3"
# Redes de tokenPlatforms em que a carteira ainda nao mostra token fora da lista
# (CustomToken.supports): ficam de fora para a lista nao crescer a toa.
SEM_TOKEN = {"sui", "aptos", "near", "cardano"}
ID = re.compile(r"^[a-z0-9-]{1,120}$")


def buscar(caminho):
    for espera in (0, 20, 45, 90):
        time.sleep(espera)
        pedido = urllib.request.Request(API + caminho, headers={"Accept": "application/json", "User-Agent": "escalibur-catalogo"})
        try:
            with urllib.request.urlopen(pedido, timeout=60) as resposta:
                return json.load(resposta)
        except urllib.error.HTTPError as erro:
            if erro.code != 429:
                raise
            print(f"CoinGecko em pausa (429); de novo em instantes", file=sys.stderr)
    sys.exit("o CoinGecko nao liberou; rode de novo daqui a alguns minutos")


def plataformas():
    """{plataforma do CoinGecko: id da rede}, de MarketService.tokenPlatforms."""
    texto = open(MERCADO, encoding="utf-8").read()
    bloco = texto[texto.index("static let tokenPlatforms"):]
    bloco = bloco[:bloco.index("\n    ]\n")]
    pares = re.findall(r'"([a-z0-9]+)": \("([a-z0-9-]+)"', bloco)
    if len(pares) < 10:
        sys.exit("nao achei MarketService.tokenPlatforms em Market.swift")
    return {gecko: rede for rede, gecko in pares if rede not in SEM_TOKEN}


def main():
    redes = plataformas()
    lista = buscar("/coins/list?include_platform=true")
    posicoes = {}
    for pagina in range(1, 5):
        for moeda in buscar(f"/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=250&page={pagina}"):
            if moeda.get("market_cap_rank"):
                posicoes[moeda["id"]] = moeda["market_cap_rank"]
        time.sleep(3)
    saida = []
    for moeda in lista:
        ident, simbolo, nome = moeda.get("id"), moeda.get("symbol"), moeda.get("name")
        if not (isinstance(ident, str) and ID.match(ident) and isinstance(simbolo, str) and isinstance(nome, str)):
            continue
        contratos = {}
        for plataforma, contrato in sorted((moeda.get("platforms") or {}).items()):
            rede = redes.get(plataforma)
            if rede and isinstance(contrato, str) and 0 < len(contrato) <= 100 and rede not in contratos:
                contratos[rede] = contrato
        saida.append([ident, simbolo[:40], nome[:80], posicoes.get(ident), contratos])
    if sum(1 for m in saida if m[4]) < 5000:
        sys.exit("menos de 5.000 moedas com rede: resposta estranha, nada gravado")
    with open(SAIDA, "w", encoding="utf-8") as arquivo:
        # Uma moeda por linha: a revisao do diff mostra o que entrou e o que saiu.
        arquivo.write("[\n" + ",\n".join(json.dumps(m, ensure_ascii=False, separators=(",", ":")) for m in saida) + "\n]\n")
    print(f"{len(saida)} moedas ({sum(1 for m in saida if m[4])} com rede), {len(posicoes)} com posicao, {os.path.getsize(SAIDA) // 1024} KB em {os.path.relpath(SAIDA, RAIZ)}")


if __name__ == "__main__":
    main()
