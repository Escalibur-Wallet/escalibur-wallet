#!/usr/bin/python3 -IS
"""Baixa os logos das moedas e redes da lista curada para dentro do app.

Logos embarcados, e nao baixados em tempo de uso: pedir o logo de um token a um CDN
conta ao CDN quais tokens a carteira tem. Roda uma vez por versao; o resultado vai
para o repositorio e passa por revisao como qualquer outro arquivo.

    python3 tools/baixar-logos.py              todos
    python3 tools/baixar-logos.py celo linea   so os nomes dados (id do CoinGecko da
                                               moeda ou id da rede em Chain.swift)

As maiores do Mercado (os antigos --mercado e --paprika) vem de tools/catalogo/baixar-logos.py, com o filtro de
imitacao. Toda imagem passa pelo mesmo caminho de la: o sips no sandbox de tools/catalogo/sips.sb e o PNG regravado so
com os pixels (revisao de seguranca, 23/11/2026).

So aceita imagem dos hosts de imagem do CoinGecko (os mesmos do `ImageLoader` do app),
id em [a-z0-9-] e ate 160 KB: uma resposta adulterada nao poe arquivo local nem de
outro host no repositorio (pentest de 14/10/2026, B7).
"""
import json, os, re, sys, hashlib, importlib.util

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(RAIZ, "App/EscaliburWallet/Resources/Assets.xcassets/Logos")
MOEDAS = ["bitcoin", "ethereum", "solana", "ripple", "stellar", "tron", "the-open-network", "litecoin",
          "dogecoin", "binancecoin", "avalanche-2", "polygon-ecosystem-token", "tether", "usd-coin", "dai",
          "wrapped-bitcoin", "weth", "chainlink", "uniswap", "arbitrum", "optimism", "jupiter-exchange-solana",
          "plasma", "okb", "sonic-3", "celo", "ripple-usd", "wrapped-steth", "usds", "leo-token",
          "coinbase-wrapped-btc", "binance-bitcoin", "binance-peg-xrp", "binance-peg-dogecoin", "binance-peg-cardano", "binance-peg-polkadot", "binance-peg-litecoin", "binance-peg-avalanche", "binance-peg-near-protocol", "binance-peg-sol", "wrapped-eeth", "ethena-usde", "susds", "usd1-wlfi", "crypto-com-chain",
          "global-dollar", "ethena", "paypal-usd", "ondo-finance", "tether-gold", "aave", "mantle", "aster-2",
          "sky", "morpho", "pax-gold", "pepe", "usdd", "bitget-token", "ethena-staked-usde", "jito-staked-sol",
          "pancakeswap-token", "render-token", "rocket-pool-eth", "nexo", "aerodrome-finance",
          "injective-protocol", "gho", "ether-fi", "pyth-network", "official-trump", "raydium", "fetch-ai",
          "curve-dao-token", "virtual-protocol", "coinbase-wrapped-staked-eth", "true-usd", "usdtb", "euro-coin",
          "pendle", "lido-dao", "the-graph", "gnosis", "jito-governance-token", "starknet",
          "ethereum-name-service", "syrup", "eigenlayer", "trust-wallet-token", "compound-governance-token",
          "crvusd", "agora-dollar", "convex-finance", "immutable-x", "havven", "basic-attention-token",
          "the-sandbox", "golem"]
MOEDAS += ["sui"]
MOEDAS += ["cardano"]
MOEDAS += ["polkadot"]
MOEDAS += ["near"]
MOEDAS += ["aptos"]
MOEDAS += ["shiba-inu", "bnb-frog-inu"]
# Os embrulhados da moeda da rede que a ordem limite da CoW cria (pedido do dono, 04/11/2026).
MOEDAS += ["wbnb", "wmatic", "wrapped-avax", "wrapped-xpl"]
# Provedores de troca e de ponte com token proprio: o logo e o do token no CoinGecko (a
# ShibaSwap usa o SHIB, a ponte da Tether o USDT0). LI.FI, De¹ e Circle (o CCTP) nao tem token:
# os logos deles vieram do site de cada um, em vetor, renderizados em 250 px e conferidos a mao
# (23/10/2026), e este script nao mexe neles.
PROVEDORES = {"kyberswap": "kyber-network-crystal", "cow": "cow-protocol", "velora": "paraswap",
              "jupiter": "jupiter-exchange-solana", "pancakeswap": "pancakeswap-token",
              "uniswap": "uniswap", "shibaswap": "shiba-inu", "across": "across-protocol", "usdt0": "usdt0"}
REDES = {"base": "base", "arbitrum": "arbitrum-one", "optimism": "optimistic-ethereum", "polygon": "polygon-pos",
         "bnb": "binance-smart-chain", "avalanche": "avalanche", "ethereum": "ethereum", "solana": "solana",
         "tron": "tron", "ton": "the-open-network", "stellar": "stellar", "xrpl": "xrp", "litecoin": "litecoin",
         "dogecoin": "dogecoin", "bitcoin": "bitcoin",
         "plasma": "plasma", "xlayer": "x-layer", "linea": "linea", "unichain": "unichain", "sonic": "sonic",
         "celo": "celo"}
REDES["sui"] = "sui"
REDES["cardano"] = "cardano"
REDES["polkadot"] = "polkadot"
REDES["near"] = "near-protocol"
REDES["aptos"] = "aptos"
ARGS = sys.argv[1:]
if ARGS[:1] in (["--paprika"], ["--mercado"]):
    raise SystemExit("as maiores do Mercado vem de tools/catalogo/baixar-logos.py")
SO = set(ARGS)
ORIGENS = ("https://coin-images.coingecko.com/", "https://assets.coingecko.com/")
API = "https://api.coingecko.com/api/v3/"
ID = re.compile(r"^[a-z0-9-]{1,80}$")
LIMITE = 160 * 1024

# O caminho das imagens de tools/catalogo/baixar-logos.py: pedido sem redirecionamento, sips no sandbox, so pixels.
_espec = importlib.util.spec_from_file_location("catalogo_logos", os.path.join(RAIZ, "tools/catalogo/baixar-logos.py"))
CATALOGO = importlib.util.module_from_spec(_espec)
_espec.loader.exec_module(CATALOGO)

def get(url):
    if not (url.startswith(API) or url.startswith(ORIGENS)):
        raise SystemExit("host recusado: " + url)
    hosts = {"api.coingecko.com"} if url.startswith(API) else CATALOGO.HOSTS
    dados = CATALOGO.pedir(url, hosts, None if url.startswith(API) else LIMITE)
    if dados is None: raise SystemExit("sem resposta (ou redirecionado): " + url)
    return dados

def salvar(nome, url, lado=None):
    if not ID.match(nome.split("-", 1)[1] if "-" in nome else nome) or not isinstance(url, str) or not url.startswith(ORIGENS):
        print("recusado", nome, url); return
    dados = get(url)
    if len(dados) > LIMITE:
        print("grande demais", nome, len(dados)); return
    # So PNG ou JPEG, como o script novo: WebP seria mais um decodificador no sips.
    if not (dados.startswith(b"\x89PNG") or dados.startswith(b"\xff\xd8\xff")):
        print("formato recusado", nome, url); return
    # Sempre pelo sips no sandbox e regravado so com os pixels, em PNG.
    dados = CATALOGO.remontar(dados, lado)
    if not dados:
        print("o sips nao converteu", nome); return
    pasta = os.path.join(ASSETS, nome + ".imageset")
    os.makedirs(pasta, exist_ok=True)
    for velho in os.listdir(pasta):
        if velho.lower().endswith((".jpg", ".jpeg")): os.remove(os.path.join(pasta, velho))
    arquivo = nome + ".png"
    open(os.path.join(pasta, arquivo), "wb").write(dados)
    json.dump({"images": [{"filename": arquivo, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}},
              open(os.path.join(pasta, "Contents.json"), "w"))
    print(nome, len(dados), hashlib.sha256(dados).hexdigest()[:12])

os.makedirs(ASSETS, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}},
          open(os.path.join(ASSETS, "Contents.json"), "w"))
moedas = [m for m in MOEDAS if not SO or m in SO]
if moedas:
    mercados = json.loads(get("https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=" + ",".join(moedas)))
    for m in mercados:
        if m.get("id") in moedas: salvar("logo-" + m["id"], m.get("image"))
plataformas = {p["id"]: p for p in json.loads(get("https://api.coingecko.com/api/v3/asset_platforms"))}
for rede, pid in REDES.items():
    if SO and rede not in SO: continue
    p = plataformas.get(pid)
    img = (p or {}).get("image") or {}
    url = img.get("large") or img.get("small")
    if url: salvar("rede-" + rede, url)
    else: print("sem logo de plataforma", rede)
prov = json.loads(get("https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=" + ",".join(PROVEDORES.values())))
por_id = {m["id"]: m for m in prov}
for nome, gid in PROVEDORES.items():
    m = por_id.get(gid)
    if m: salvar("provedor-" + nome, m["image"])
    else: print("sem logo de provedor", nome)
