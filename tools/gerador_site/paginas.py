"""O HTML do site: a moldura de toda pagina, os componentes (iPhone, logo, botoes da
loja) e as paginas geradas dos dados (auditoria, codigo, redes e moedas, novidades).

Todo texto que vem de fora (commit, comentario de codigo, nome de token) passa por
html.escape. Nenhum atributo de evento, nenhum estilo em linha: a Content Security
Policy so deixa carregar o estilo e o script do proprio site.
"""

import hashlib
import html
import os
import re
from datetime import datetime

from . import acentos, codigo, dados

SITE_URL = "https://escaliburwallet.com/"
EMPRESA = "X TECH A.I FUND HOLDING E PARTICIPACOES LTDA"
CNPJ = "64.019.520/0001-29"

# As paginas do menu, na ordem: (pasta, rotulo).
MENU = [
    ("seguranca", "Segurança"),
    ("auditoria", "Auditoria"),
    ("redes", "Redes e moedas"),
    ("novidades", "Novidades"),
    ("suporte", "Suporte"),
]

MESES = ["jan.", "fev.", "mar.", "abr.", "maio", "jun.", "jul.", "ago.", "set.", "out.", "nov.", "dez."]
MESES_LONGOS = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro",
                "novembro", "dezembro"]

# Os arquivos que a pagina de auditoria abre linha a linha: (grupo, slug, titulo, caminho).
ARQUIVOS_CHAVE = [
    ("Assinatura", "assinador", "O assinador", "Kit/Sources/EscaliburKeys/Signer.swift"),
    ("Assinatura", "contrato-de-assinatura", "O contrato entre redes e assinador", "Kit/Sources/EscaliburChains/Signing.swift"),
    ("Assinatura", "conferencia-do-plano", "A conferência do plano", "Kit/Sources/EscaliburChains/PlanIntentCheck.swift"),
    ("Assinatura", "movimento-do-plano", "O que sai e o que entra", "Kit/Sources/EscaliburChains/PlanMovement.swift"),
    ("Contratos e destinos", "guarda-de-chamada-evm", "A guarda de chamada EVM", "Kit/Sources/EscaliburChains/EVM/EVMCallGuard.swift"),
    ("Contratos e destinos", "allowlist-de-troca", "A lista de contratos da troca", "Kit/Sources/EscaliburChains/Trade/TradeAllowlist.swift"),
    ("Contratos e destinos", "allowlist-da-ponte", "A lista de contratos da ponte", "Kit/Sources/EscaliburChains/Bridge/BridgeAllowlist.swift"),
    ("Contratos e destinos", "envenenamento-de-endereco", "Endereço parecido", "Kit/Sources/EscaliburChains/AddressPoisoning.swift"),
    ("Chaves", "chave-raiz", "A chave raiz, o PIN e o Face ID", "Kit/Sources/EscaliburKeys/RootKeyVault.swift"),
    ("Chaves", "secure-enclave", "As chaves do Secure Enclave", "Kit/Sources/EscaliburKeys/Enclave.swift"),
    ("Chaves", "politica-do-pin", "As regras do PIN", "Kit/Sources/EscaliburKeys/PINPolicy.swift"),
    ("Chaves", "chaveiro", "O chaveiro", "Kit/Sources/EscaliburKeys/SecretStore.swift"),
    ("Envelope", "envelope", "O envelope", "Kit/Sources/EscaliburCore/Envelope/Envelope.swift"),
    ("Envelope", "formato-do-envelope", "O formato .esclbr", "Kit/Sources/EscaliburCore/Envelope/VaultFormat.swift"),
    ("Rede", "cliente-http", "O cliente HTTP", "Kit/Sources/EscaliburNetwork/HTTPClient.swift"),
    ("Rede", "hosts-permitidos", "Os hosts permitidos", "Kit/Sources/EscaliburNetwork/AllowedHosts.swift"),
    ("Verificação", "verificador", "O verificador", "tools/verificar.sh"),
]


def e(texto):
    return html.escape(str(texto), quote=True)


def acento(texto):
    return e(acentos.acentuar(texto))


def numero(n):
    return f"{n:,}".replace(",", ".")


def data_curta(iso):
    if not iso:
        return ""
    d = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return f"{d.day} {MESES[d.month - 1]} {d.year}"


def data_longa(iso):
    if not iso:
        return ""
    d = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return f"{d.day} de {MESES_LONGOS[d.month - 1]} de {d.year}"


def data_iso(iso):
    return iso[:10] if iso else ""


def blob(ctx, caminho, linha=None):
    ref = ctx["commit"]["sha"] or "main"
    return f"{dados.REPO}/blob/{ref}/{caminho}" + (f"#L{linha}" if linha else "")


# MARK: Componentes

ICONE_PAUSA = '<svg class="pausa" viewBox="0 0 14 14" aria-hidden="true"><rect x="2.5" y="2" width="3" height="10" rx="1" fill="currentColor"/><rect x="8.5" y="2" width="3" height="10" rx="1" fill="currentColor"/></svg>'
ICONE_TOCAR = '<svg class="tocar" viewBox="0 0 14 14" aria-hidden="true"><path d="M4 2.4v9.2c0 .5.5.8.9.5l7-4.6c.4-.3.4-.8 0-1.1l-7-4.6c-.4-.2-.9 0-.9.6Z" fill="currentColor"/></svg>'


def aparelho(base, cena, rotulo, classe="", video=True, cedo=False):
    """Um iPhone desenhado em CSS com a gravacao real do app dentro.

    A capa e uma imagem com carregamento preguicoso (so baixa perto da tela) e leva o
    texto alternativo. O video fica por cima, invisivel e sem baixar nada (preload none)
    ate o site.js mandar tocar; sem JS, fica a capa."""
    carregamento = "eager" if cedo else "lazy"
    prioridade = ' fetchpriority="high"' if cedo else ""
    capa = (f'<img class="capa" src="{base}midia/{cena}.webp" alt="{e(rotulo)}" width="720" height="1566" '
            f'loading="{carregamento}" decoding="async"{prioridade}>')
    botao = ""
    if video:
        capa += (f'<video muted loop playsinline preload="none" data-auto aria-hidden="true" tabindex="-1">'
                 f'<source src="{base}midia/{cena}.mp4" type="video/mp4"></video>')
        botao = (f'<button class="pausar" type="button" data-estado="pausado" aria-label="Tocar a animação">'
                 f'{ICONE_PAUSA}{ICONE_TOCAR}</button>')
    classes = "aparelho" + (f" {classe}" if classe else "")
    return f'<div class="{classes}"><div class="tela">{capa}</div>{botao}</div>'


def botoes_baixar(ctx, base):
    """Os selos oficiais da App Store e do Google Play (pedido do dono, 18/10/2026). Com o
    link da loja, o selo leva a ele; antes do lancamento, o selo fica sem link, e a linha
    de baixo diz que e em breve."""
    selos = []
    for url, arquivo, alt, largura in (
        (ctx["app_store_url"], "baixar-na-app-store.svg", "Baixar na App Store", 156),
        (ctx["play_store_url"], "disponivel-no-google-play.png", "Disponível no Google Play", 175),
    ):
        imagem = f'<img src="{base}selos/{arquivo}" alt="{e(alt)}" width="{largura}" height="52">'
        if url:
            selos.append(f'<a class="selo-loja" href="{e(url)}">{imagem}</a>')
        else:
            selos.append(f'<span class="selo-loja em-breve">{imagem}</span>')
    faltam = [nome for url, nome in ((ctx["app_store_url"], "na App Store"), (ctx["play_store_url"], "no Google Play")) if not url]
    nota = f'<p class="lojas-nota">Em breve {" e ".join(faltam)}.</p>' if faltam else ""
    return '<div class="lojas"><div class="botoes">' + "".join(selos) + "</div>" + nota + "</div>"


def logo(ctx, base, nome, classe="", texto=""):
    """Um logo do catalogo do app, no mesmo disco do app."""
    caminho = ctx["logos"].get(nome)
    if not caminho:
        letras = re.sub(r"[^A-Za-z0-9]", "", texto)[:2].upper() or "?"
        return f'<span class="logo letra" aria-hidden="true">{e(letras)}</span>'
    classes = "logo" + (f" {classe}" if classe else "")
    return f'<span class="{classes}"><img src="{base}{caminho}" alt="" width="48" height="48" loading="lazy" decoding="async"></span>'


def logo_rede(ctx, base, rede):
    """Como o selo de rede do app (NetworkBadge): a Base e o quadrado branco no disco
    azul; XRP Ledger e Stellar, escuros, num disco claro."""
    if rede["id"] == "base":
        return '<span class="logo logo-base" aria-hidden="true"></span>'
    nome = f"rede-{rede['id']}" if f"rede-{rede['id']}" in ctx["logos"] else f"logo-{rede['gecko']}"
    classe = "clara" if rede["id"] in ("xrpl", "stellar") else ""
    return logo(ctx, base, nome, classe, rede["nome"])


def logo_token(ctx, base, token):
    soltas, escuras = ctx["conjuntos_logo"]
    classe = "solta" if token["gecko"] in soltas else ("clara" if token["gecko"] in escuras else "")
    return logo(ctx, base, f"logo-{token['gecko']}", classe, token["simbolo"])


def estado_ci(ctx, base, curto=False):
    commit = ctx["commit"]
    sha = commit["sha"]
    partes = []
    if sha:
        partes.append(f'Commit <a href="{dados.REPO}/commit/{sha}">{sha[:7]}</a> de {data_curta(commit["data"])}')
    ci = ctx["ci"]
    classe = "sem"
    if ci is None:
        partes.append("sem o estado do CI neste build local")
    else:
        textos = {
            "passou": "verificação no CI: passou", "falhou": "verificação no CI: falhou",
            "rodando": "verificação no CI: rodando", "cancelado": "verificação no CI: cancelada",
            "sem": "verificação no CI: ainda sem resultado para este commit", "outro": "verificação no CI: sem conclusão",
        }
        classe = ci["estado"]
        texto = textos.get(ci["estado"], "verificação no CI")
        partes.append(f'<a href="{e(ci["url"])}">{texto}</a>' if ci.get("url") else texto)
    return f'<p class="estado-ci {e(classe)}"><span class="ponto" aria-hidden="true"></span>{" · ".join(partes)}</p>'


def estado_ci_curto(ctx):
    """A linha do commit publicado em uma linha so, em toda largura: o hash, a data curta e,
    quando o build sabe, o resultado do CI. No build local, sem o CI."""
    commit = ctx["commit"]
    sha = commit["sha"]
    if not sha:
        return ""
    ci = ctx["ci"]
    estados = {"passou": "CI passou", "falhou": "CI falhou", "rodando": "CI rodando", "cancelado": "CI cancelado"}
    classe = ci["estado"] if ci else "sem"
    parte_ci = ""
    if ci and ci["estado"] in estados:
        rotulo = estados[ci["estado"]]
        parte_ci = f' · <a href="{e(ci["url"])}">{rotulo}</a>' if ci.get("url") else f" · {rotulo}"
    return (f'<p class="estado-ci curto {e(classe)}"><span class="ponto" aria-hidden="true"></span>'
            f'<span><span class="ci-rotulo">Commit </span><a href="{dados.REPO}/commit/{sha}">{sha[:7]}</a> · {data_curta(commit["data"])}{parte_ci}</span></p>')


def frase_e_redes(ctx, base):
    """"Uma frase, 26 redes" (quarta rodada): no alto, as 12 palavras da frase como o app as
    mostra enquanto se digita, em glifos que cifram; embaixo, as redes, cada uma com o seu
    endereco proprio desenhado em pixels (um desenho tirado do nome da rede, nao o endereco de
    ninguem). O site.js acende as redes em onda, e os pixels de cada endereco decifram.
    Sem JS ou com movimento reduzido, tudo aparece parado."""
    redes = ctx["redes"]
    palavras = "".join(f'<li><span class="frase-n">{i + 1}</span><span class="frase-glifos" data-glifos="{4 + (i * 5) % 4}">{"•" * (4 + (i * 5) % 4)}</span></li>'
                       for i in range(12))
    itens = []
    for k, r in enumerate(redes):
        desenho = hashlib.sha256(("escalibur/site/" + r["id"]).encode()).hexdigest()[:40]
        itens.append(f'<li class="rede-ficha">{logo_rede(ctx, base, r)}<span class="rede-nome">{e(r["nome"])}</span>'
                     f'<canvas class="pixels-hash ficha-hash" data-hashes="{desenho}" data-colunas="20" data-linhas="2" data-atraso="{0.25 + k * 0.045:.2f}" aria-hidden="true"></canvas></li>')
    return (f'<div class="frase-redes">'
            f'<div class="frase-cartao"><p class="frase-titulo">Uma frase de 12 palavras</p>'
            f'<ol class="frase-palavras" aria-label="As 12 palavras, cifradas na tela como no app">{palavras}</ol></div>'
            f'<div class="frase-seta" aria-hidden="true"><span></span></div>'
            f'<ul class="redes-fichas" aria-label="As {len(redes)} redes que a frase abre">{"".join(itens)}'
            f'<li class="ficha-nota">Cada endereço sai da mesma frase, pelo caminho padrão da rede. '
            f'Os desenhos em pixels aqui são ilustrativos, não são endereços de ninguém.</li></ul></div>')


def redes_com_tag(ctx):
    nomes = {"tag de destino": "tag de destino", "memo": "memo", "comentário": "comentário"}
    partes = []
    for rede in ctx["redes"]:
        if rede["tag"]:
            preposicao = "no" if rede["nome"] in ("XRP Ledger",) else "na"
            partes.append(f"{nomes[rede['tag']]} {preposicao} {rede['nome']}")
    if not partes:
        return ""
    return e(", ".join(partes[:-1]) + (" e " if len(partes) > 1 else "") + partes[-1])


def grade_de_redes(ctx, base):
    """As redes numa faixa que desliza (pedido do dono, 18/10/2026): duas fileiras, em
    sentidos opostos, cada uma repetida uma vez para o laco nao ter emenda. A copia nao e
    lida pelo leitor de tela. Com "reduzir movimento", a faixa para e vira a grade de antes."""
    redes = ctx["redes"]
    meio = (len(redes) + 1) // 2

    def lista(fatia, copia=False):
        itens = "".join(f"<li>{logo_rede(ctx, base, r)}<span>{e(r['nome'])}</span></li>" for r in fatia)
        escondida = ' aria-hidden="true"' if copia else ""
        return f'<ul class="redes-lista"{escondida}>{itens}</ul>'

    fileiras = "".join(
        f'<div class="redes-fileira{" ao-contrario" if indice else ""}">{lista(fatia)}{lista(fatia, copia=True)}</div>'
        for indice, fatia in enumerate((redes[:meio], redes[meio:])))
    return f'<div class="redes-faixa-animada" role="group" aria-label="As {len(redes)} redes da carteira">{fileiras}</div>'


# As moedas que flutuam em volta dos iPhones da abertura, na ordem das posicoes do CSS
# (.moeda:nth-child): o id do CoinGecko e a profundidade.
MOEDAS_ABERTURA = [
    ("bitcoin", "perto"), ("ethereum", "perto"), ("tether", "meio"), ("solana", "perto"),
    ("ripple", "meio"), ("usd-coin", "meio"), ("binancecoin", "longe"), ("the-open-network", "meio"),
    ("tron", "longe"), ("dogecoin", "meio"), ("cardano", "longe"), ("avalanche-2", "longe"),
    ("sui", "longe"), ("chainlink", "longe"), ("stellar", "longe"), ("near", "longe"),
]


def moedas_abertura(ctx, base):
    """A camada de moedas da abertura (pedido do dono, 18/10/2026): logos de verdade, em
    tres profundidades. O site.js as leva para dentro do iPhone do meio conforme a pagina
    rola. So enfeite: fora do leitor de tela."""
    itens = []
    for gecko, profundidade in MOEDAS_ABERTURA:
        caminho = ctx["logos"].get(f"logo-{gecko}")
        if caminho:
            itens.append(f'<span class="moeda {profundidade}"><img src="{base}{caminho}" alt="" width="64" height="64" decoding="async"></span>')
    return '<div class="abertura-moedas" aria-hidden="true">' + "".join(itens) + "</div>"


def resumo_novidades(ctx, base, quantos=4):
    """As ultimas entregas, cada uma com o hash do commit em pixels (o site.js desenha: os 40
    digitos hexadecimais viram 40 tons de cinza, que decifram quando a lista aparece)."""
    itens = []
    for c in ctx["commits"][:quantos]:
        itens.append(
            f'<li><time datetime="{data_iso(c["data"])}">{data_curta(c["data"])}</time>'
            f'<p class="assunto" lang="en"><a href="{base}novidades/#c-{c["sha"][:7]}">{texto_novidade(c, c["assunto"])}</a></p></li>'
        )
    return '<ol class="linha-do-tempo">' + "".join(itens) + "</ol>"


# As verificacoes que o painel "Codigo auditavel" mostra passando, uma de cada grupo, na ordem.
FEED_GRUPOS = ["fronteira de rede", "chaveiro e biometria", "segredo", "hosts", "dependencias", "codigo vendorizado",
               "registro e aleatoriedade", "plataforma", "privacidade", "workflows", "testes"]


def feed_de_verificacoes(ctx, base):
    """Afirmacoes reais do tools/verificar.sh, uma de cada grupo: o site.js as acende em
    sequencia, como uma rodada do verificador. Cada uma leva a linha onde mora."""
    por_nome = {s["nome"]: s for s in ctx["verificacoes"]}
    itens = []
    for nome in FEED_GRUPOS:
        secao = por_nome.get(nome)
        if not secao:
            continue
        for linha, mensagem, _ in secao["itens"]:
            if "$" in mensagem:
                continue
            itens.append(f'<li><span class="feed-marca" aria-hidden="true"></span><span class="feed-texto">{acento(mensagem)}</span>'
                         f'<a class="feed-linha" href="{blob(ctx, "tools/verificar.sh", linha)}" aria-label="verificar.sh, linha {linha}">linha {linha}</a></li>')
            break
    return '<ol class="feed-verificacoes" aria-label="Algumas das verificações">' + "".join(itens) + "</ol>"


def link_codigo(base, slug, texto=None):
    for _, s, titulo, caminho in ARQUIVOS_CHAVE:
        if s == slug:
            nome = caminho.rsplit("/", 1)[-1]
            return f'<a class="codigo-link" href="{base}auditoria/codigo/{s}/">{e(texto or "Ler " + nome)}</a>'
    raise SystemExit(f"gerar-site: arquivo-chave desconhecido: {slug}")


# MARK: Pagina inicial: mercado ao vivo, troca e ponte, telas do app

# As moedas do "Mercado ao vivo", na ordem da lista. Toda moeda daqui tem de ser uma rede do
# app ou um token da lista conferida: o gerador confere e para se nao for.
VITRINE = ["bitcoin", "ethereum", "tether", "ripple", "binancecoin", "solana", "usd-coin", "tron",
           "dogecoin", "cardano", "the-open-network", "sui"]

# Na demonstracao da troca, os tokens de cada rede, por esta ordem de preferencia, ate quatro
# alem da moeda da rede. So os da lista conferida daquela rede.
TROCA_PREFERIDOS = [["usd-coin"], ["tether"], ["wrapped-bitcoin", "coinbase-wrapped-btc", "binance-bitcoin"], ["weth"],
                    ["chainlink"], ["jupiter-exchange-solana"], ["arbitrum"], ["optimism"], ["uniswap"], ["aave"],
                    ["pancakeswap-token"], ["aerodrome-finance"], ["raydium"], ["pyth-network"], ["render-token"],
                    ["euro-coin"], ["ripple-usd"], ["dai"], ["ethena-usde"]]
TROCA_POR_REDE = 8

PONTE_ATIVOS = [("usdc", "USDC", "usd-coin"), ("eth", "ETH", "ethereum"), ("usdt", "USDT", "tether"), ("wbtc", "WBTC", "wrapped-bitcoin")]


def ids_de_preco(ctx):
    """Todas as moedas que a pagina inicial precisa com preco: a vitrine e as da demonstracao."""
    validos = {r["gecko"] for r in ctx["redes"]} | {t["gecko"] for t in ctx["tokens"]}
    fora = [g for g in VITRINE if g not in validos]
    if fora:
        raise SystemExit(f"gerar-site: moeda da vitrine fora do app: {fora}")
    ids = list(VITRINE)
    for rede in dados_da_troca(ctx)["redes"]:
        for moeda in rede["moedas"]:
            if moeda["id"] not in ids:
                ids.append(moeda["id"])
    for _, _, gecko in PONTE_ATIVOS:
        if gecko not in ids:
            ids.append(gecko)
    return ids


def _nome_moeda(ctx, gecko):
    for r in ctx["redes"]:
        if r["gecko"] == gecko:
            return r["simbolo"], r["nome_nativo"] or r["nome"]
    for t in ctx["tokens"]:
        if t["gecko"] == gecko:
            return t["simbolo"], t["nome"]
    return gecko.upper(), gecko


def _logo_moeda(ctx, base, gecko):
    caminho = ctx["logos"].get(f"logo-{gecko}")
    return f"{base}{caminho}" if caminho else ""


def dados_da_troca(ctx, base=""):
    """O que a demonstracao da troca e da ponte pode mostrar, tirado do codigo do app: as redes
    com troca (dados.redes_com_troca), os tokens conferidos de cada uma e as rotas da ponte
    (dados.ponte)."""
    por_rede = {}
    for t in ctx["tokens"]:
        por_rede.setdefault(t["rede"], []).append(t)
    redes_troca = []
    for rede in dados.redes_com_troca(ctx["redes"]):
        moedas = [{"id": rede["gecko"], "s": rede["simbolo"], "n": rede["nome_nativo"] or rede["nome"],
                   "l": _logo_moeda(ctx, base, rede["gecko"])}]
        so = dados.TROCA_SO.get(rede["id"])
        lista = {t["gecko"]: t for t in por_rede.get(rede["id"], [])}
        for grupo in TROCA_PREFERIDOS:
            if len(moedas) >= TROCA_POR_REDE:
                break
            # Um token de cada grupo (um BTC embrulhado so), e o WETH so onde a moeda da rede nao e o ETH.
            gecko = next((g for g in grupo if g in lista and (so is None or g in so) and g != rede["gecko"]
                          and not (g == "weth" and rede["gecko"] == "ethereum")), None)
            if gecko:
                t = lista[gecko]
                moedas.append({"id": gecko, "s": t["simbolo"], "n": t["nome"], "l": _logo_moeda(ctx, base, gecko)})
        if len(moedas) > 1:
            redes_troca.append({"id": rede["id"], "nome": rede["nome"], "familia": rede["familia"],
                                "l": _logo_rede_src(ctx, base, rede), "moedas": moedas})
    ponte = dados.ponte()
    por_id = {r["id"]: r for r in ctx["redes"]}
    redes_ponte = [{"id": r, "nome": por_id[r]["nome"], "l": _logo_rede_src(ctx, base, por_id[r])} for r in ponte["redes"] if r in por_id]
    ativos = [{"id": a, "s": s, "g": g, "l": _logo_moeda(ctx, base, g)} for a, s, g in PONTE_ATIVOS]
    return {"redes": redes_troca, "ponte": {"redes": redes_ponte, "ativos": ativos, "rotas": ponte["rotas"]}}


def _logo_rede_src(ctx, base, rede):
    nome = f"rede-{rede['id']}" if f"rede-{rede['id']}" in ctx["logos"] else f"logo-{rede['gecko']}"
    caminho = ctx["logos"].get(nome)
    return f"{base}{caminho}" if caminho else ""


def troca_dados_attr(ctx, base):
    import json
    return e(json.dumps(dados_da_troca(ctx, base), ensure_ascii=False, separators=(",", ":")))


def _significativo(valor, casas):
    texto = f"{valor:,.{casas}f}"
    return texto.replace(",", "X").replace(".", ",").replace("X", ".")


def formatar_preco(valor, moeda="usd"):
    """Como o site.js formata: R$ ou US$, duas casas acima de 1, quatro acima de 0,01, seis
    abaixo disso."""
    if valor is None:
        return ""
    casas = 2 if valor >= 1 else (4 if valor >= 0.01 else 6)
    simbolo = "R$" if moeda == "brl" else "US$"
    return f"{simbolo} {_significativo(valor, casas)}"


def _linha_svg(pontos):
    if not pontos or len(pontos) < 2:
        return ""
    menor, maior = min(pontos), max(pontos)
    faixa = (maior - menor) or 1
    passo = 120 / (len(pontos) - 1)
    caminho = " ".join(f"{'M' if i == 0 else 'L'}{i * passo:.1f} {34 - (p - menor) / faixa * 32:.1f}" for i, p in enumerate(pontos))
    return caminho


ICONE_SETA = {
    "alta": '<svg viewBox="0 0 8 8" aria-hidden="true"><path d="M4 1.2 7.2 6.4H.8Z"/></svg>',
    "baixa": '<svg viewBox="0 0 8 8" aria-hidden="true"><path d="M4 6.8.8 1.6h6.4Z"/></svg>',
}


def variacao(valor):
    """A pilula de variacao do app (ChangePill): so a seta tem cor, lima na alta e vermelho
    na queda; o numero fica sem sinal. Abaixo de 0,01%, neutra, sem seta."""
    if valor is None:
        return '<span class="variacao" data-variacao></span>'
    estado = "alta" if valor > 0.004 else ("baixa" if valor < -0.004 else "estavel")
    seta = ICONE_SETA.get(estado, "")
    rotulo = {"alta": "Subiu", "baixa": "Caiu", "estavel": "Estável"}[estado]
    numero = _significativo(abs(valor), 2) + "%"
    return f'<span class="variacao {estado}" data-variacao aria-label="{rotulo} {numero}">{seta}<span>{numero}</span></span>'


def lista_de_precos(ctx, base, retrato):
    """A lista do Mercado ao vivo, ja com o retrato da publicacao. O site.js troca pelos
    precos do /precos.json quando consegue."""
    moedas = (retrato or {}).get("moedas", {})
    itens = []
    for indice, gecko in enumerate(VITRINE):
        simbolo, nome = _nome_moeda(ctx, gecko)
        dado = moedas.get(gecko, {})
        preco = formatar_preco(dado.get("usd"))
        caminho = _linha_svg(dado.get("linha"))
        sobe = (dado.get("var") or 0) >= 0
        linha = (f'<svg class="faisca {"alta" if sobe else "baixa"}" viewBox="0 0 120 36" preserveAspectRatio="none" aria-hidden="true">'
                 f'<path d="{caminho}"/></svg>')
        selecionada = ' aria-pressed="true"' if indice == 0 else ' aria-pressed="false"'
        itens.append(
            f'<li><button class="cotacao" type="button" data-moeda="{e(gecko)}" data-simbolo="{e(simbolo)}" data-nome="{e(nome)}"{selecionada}>'
            f'{logo(ctx, base, f"logo-{gecko}", "", simbolo)}'
            f'<span class="cotacao-nome"><b>{e(simbolo)}</b><small>{e(nome)}</small></span>'
            f'{linha}'
            f'<span class="cotacao-valor"><b data-preco>{e(preco)}</b>{variacao(dado.get("var"))}</span>'
            f'</button></li>')
    return '<ol class="cotacoes" id="cotacoes">' + "".join(itens) + "</ol>"


def hora_do_retrato(retrato):
    hora = (retrato or {}).get("hora")
    if not hora or not (retrato or {}).get("moedas"):
        return "Os preços aparecem quando o servidor responde."
    d = datetime.fromisoformat(hora.replace("Z", "+00:00"))
    return f"Preços de {d.day} {MESES[d.month - 1]} {d.year}, {d.hour:02d}:{d.minute:02d} UTC, da publicação do site"


def destaque_do_mercado(ctx, base, retrato):
    """A moeda em destaque do Mercado ao vivo (a primeira da vitrine), ja com o retrato: sem
    JS, e o que fica; com JS, o site.js troca pela escolhida e pelo preco ao vivo."""
    gecko = VITRINE[0]
    simbolo, nome = _nome_moeda(ctx, gecko)
    dado = ((retrato or {}).get("moedas") or {}).get(gecko, {})
    caminho = _logo_moeda(ctx, base, gecko)
    logo_html = f'<img src="{caminho}" alt="" width="160" height="160">' if caminho else ""
    linha = dado.get("linha") or []
    traco, area, semana, classe = "", "", None, ""
    if len(linha) > 1:
        menor, maior = min(linha), max(linha)
        faixa = (maior - menor) or 1
        passo = 600 / (len(linha) - 1)
        traco = " ".join(f"{'M' if i == 0 else 'L'}{i * passo:.1f} {180 - 10 - (v - menor) / faixa * 160:.1f}" for i, v in enumerate(linha))
        area = traco + " L600 180 L0 180 Z"
        semana = (linha[-1] / linha[0] - 1) * 100
        classe = " baixa" if linha[-1] < linha[0] else ""
    return f"""<div class="destaque-moeda">
<span class="destaque-logo" aria-hidden="true">{logo_html}</span>
<canvas class="destaque-3d" aria-hidden="true"></canvas>
</div>
<div class="destaque-dados" aria-live="polite">
<p class="destaque-nome"><b data-destaque-simbolo>{e(simbolo)}</b><span data-destaque-nome>{e(nome)}</span></p>
<p class="destaque-preco" data-destaque-preco>{e(formatar_preco(dado.get("usd")))}</p>
<p class="destaque-variacao">{variacao(dado.get("var")).replace("data-variacao", "data-destaque-variacao", 1)}<span class="apoio">em 24 h</span></p>
</div>
<div class="destaque-grafico{classe}" aria-hidden="true">
<svg viewBox="0 0 600 180" preserveAspectRatio="none"><path class="area" d="{area}"/><path class="traco" d="{traco}"/></svg>
<p class="apoio">Últimos 7 dias{variacao(semana).replace("data-variacao", "data-destaque-semana", 1) if semana is not None else '<span class="variacao" data-destaque-semana></span>'}</p>
</div>"""


# As telas do app na secao que fixa o iPhone: (cena, titulo, texto, rotulo da gravacao).
TELAS = [
    ("receber", "Receber", "O QR e o endereço inteiro, com o começo e o fim em destaque para você conferir antes de passar adiante.",
     "Receber, no app em inglês: da Carteira até o QR do bitcoin, e o endereço copiado"),
    ("envio", "Enviar", "A rede monta a transação, o app confere destino, valor e taxa, e acompanha a confirmação na própria rede.",
     "Enviar, no app em inglês: a moeda saindo da carteira e a confirmação no XRP Ledger"),
    ("trocar", "Trocar", "A cotação vem dos protocolos públicos de cada rede, comparados entre si. Você vê o mínimo que recebe antes de assinar.",
     "Trocar, no app em inglês: 250 XRP por RLUSD no XRP Ledger, com a cotação chegando"),
    ("limite", "Ordem limite", "O preço que você escolher, com prazo ou até cancelar. O celular avisa quando ela executa ou está perto de vencer.",
     "Ordem limite, no app em inglês: o preço acima do atual e o prazo da oferta"),
    ("ponte", "Ponte entre redes", "USDC da Base para a Arbitrum: a taxa e o tempo de cada rota aparecem antes de assinar, e o destino é sempre a sua própria conta.",
     "Ponte, no app em inglês: USDC da Base para a Arbitrum pelo CCTP, nas rotas rápida e padrão"),
    ("moeda", "Página da moeda", "O gráfico em cinco períodos, de 24 horas a todo o histórico, com o preço, a variação e os números do mercado.",
     "Página do bitcoin, no app em inglês: o gráfico de 7 dias, em alta"),
    ("teclado", "Safe Keyboard", "As palavras da carteira num teclado desenhado pelo próprio app. O teclado do seu celular não vê as letras, e nada é previsto nem aprendido.",
     "Safe Keyboard, no app em inglês: o teclado do app digitando sozinho"),
]


ICONES_TELAS = {
    "receber": '<path d="M12 4v12M7 11l5 5 5-5M5 20h14"/>',
    "envio": '<path d="M12 20V8M7 13l5-5 5 5M5 4h14"/>',
    "trocar": '<path d="M5 8h13M14.5 4.5 18 8l-3.5 3.5M19 16H6M9.5 12.5 6 16l3.5 3.5"/>',
    "limite": '<circle cx="12" cy="12" r="8"/><path d="M12 7.5V12l3 2"/>',
    "ponte": '<path d="M3 16c3-5 6-7 9-7s6 2 9 7M7 12.2V17M12 9v8M17 12.2V17"/>',
    "moeda": '<path d="M4 17l5-5 3.5 3.5L20 8M15 8h5v5"/>',
    "teclado": '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 10h.01M10.5 10h.01M14 10h.01M17.5 10h.01M8 14h8"/>',
}


def telas_do_app(ctx, base):
    """"Por dentro do app", refeita na quarta rodada: centralizada, sem placa. Um carrossel de
    iPhones com as gravacoes reais: o da vez no meio, grande, tocando; os vizinhos dos lados,
    menores, inclinados e apagados. As abas em cima escolhem, a legenda e a barra embaixo
    acompanham o video, e no fim do video entra o seguinte. Sem JS, os iPhones ficam numa
    fileira que desliza, cada um com a sua legenda."""
    abas, itens = [], []
    for i, (cena, titulo, texto, rotulo) in enumerate(TELAS):
        selecionada = "true" if i == 0 else "false"
        abas.append(
            f'<button type="button" class="aba-tela" role="tab" id="aba-{cena}" data-cena="{cena}" aria-controls="tela-{cena}" '
            f'aria-selected="{selecionada}" tabindex="{0 if i == 0 else -1}">'
            f'<span class="aba-icone" aria-hidden="true"><svg viewBox="0 0 24 24">{ICONES_TELAS.get(cena, "")}</svg></span>'
            f'<span class="aba-nome">{e(titulo)}</span></button>')
        carregamento = "eager" if i == 0 else "lazy"
        itens.append(
            f'<figure class="carrossel-item{" ativo" if i == 0 else ""}" data-cena="{cena}" id="tela-{cena}" role="tabpanel" aria-labelledby="aba-{cena}">'
            f'<div class="aparelho"><div class="tela">'
            f'<img class="capa" src="{base}midia/{cena}.webp" alt="{e(rotulo)}" width="720" height="1566" loading="{carregamento}" decoding="async">'
            f'<video muted playsinline preload="none" data-manual aria-hidden="true" tabindex="-1"><source src="{base}midia/{cena}.mp4" type="video/mp4"></video>'
            f'</div></div><figcaption class="carrossel-texto"><b>{e(titulo)}</b><span>{e(texto)}</span></figcaption></figure>')
    abas_html = f'<div class="carrossel-abas" role="tablist" aria-label="Telas do app">{"".join(abas)}</div>'
    palco = (f'<div class="carrossel-palco">{"".join(itens)}</div>'
             f'<div class="carrossel-rodape"><p class="carrossel-legenda" aria-hidden="true">{e(TELAS[0][2])}</p>'
             f'<span class="carrossel-progresso" aria-hidden="true"><i></i></span>'
             f'<button class="pausar carrossel-pausar" type="button" data-estado="pausado" aria-label="Tocar a animação">{ICONE_PAUSA}{ICONE_TOCAR}</button></div>')
    return abas_html, palco


# MARK: Moldura


# A Content Security Policy de toda pagina: so o que vem do proprio site. A fonte e o
# /precos.json (o Mercado ao vivo) tambem: o navegador de quem visita nao fala com mais
# ninguem. O tools/verificar.sh confere esta linha em cada pagina gerada.
CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; media-src 'self'; "
       "font-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'")


def moldura(ctx, base, rota, titulo, descricao, corpo, ativa=None):
    """A pagina inteira: cabeca com CSP, topo, conteudo e rodape."""
    nome = "Escalibur Wallet" if not titulo else f"{titulo} · Escalibur Wallet"
    canonica = SITE_URL + (rota + "/" if rota else "")
    menu = []
    for pasta, rotulo in MENU:
        atual = ' aria-current="page"' if pasta == ativa else ""
        menu.append(f'<a href="{base}{pasta}/"{atual}>{rotulo}</a>')
    menu_html = "".join(menu)
    banner = ""
    if ctx["app_store_id"]:
        banner = f'<meta name="apple-itunes-app" content="app-id={e(ctx["app_store_id"])}">\n'
    imagem_og = ""
    if ctx["tem_imagem_og"]:
        # A versao no endereco muda quando a imagem muda: WhatsApp, iMessage e as redes guardam
        # a previa pelo endereco, e sem ela mostrariam a imagem antiga.
        versao = hashlib.sha256((dados.RAIZ / "site" / "compartilhar.jpg").read_bytes()).hexdigest()[:10]
        imagem_og = (f'<meta property="og:image" content="{SITE_URL}compartilhar.jpg?v={versao}">\n'
                     '<meta property="og:image:width" content="1200">\n<meta property="og:image:height" content="630">\n'
                     f'<meta name="twitter:card" content="summary_large_image">\n<meta name="twitter:image" content="{SITE_URL}compartilhar.jpg?v={versao}">\n')
    return f"""<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta http-equiv="Content-Security-Policy" content="{CSP}">
<meta name="referrer" content="no-referrer">
<meta name="description" content="{e(descricao)}">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#0B0B0C">
{banner}<title>{e(nome)}</title>
<link rel="canonical" href="{canonica}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Escalibur Wallet">
<meta property="og:title" content="{e(nome)}">
<meta property="og:description" content="{e(descricao)}">
<meta property="og:url" content="{canonica}">
<meta property="og:locale" content="pt_BR">
{imagem_og}<link rel="preload" href="{base}fontes/inter.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="{base}estilo.css">
<link rel="icon" href="{base}icone-64.png" sizes="64x64" type="image/png">
<link rel="apple-touch-icon" href="{base}icone-180.png">
<script src="{base}site.js" defer></script>
</head>
<body{' class="inicio"' if rota == "" else ""}>
<a class="pular" href="#conteudo">Pular para o conteúdo</a>
<header class="topo">
<div class="wrap topo-barra">
<a class="marca" href="{base}"><img src="{base}icone-64.png" alt="" width="28" height="28">Escalibur Wallet</a>
<nav class="nav-largo" aria-label="Principal">{menu_html}</nav>
<details class="nav-curto">
<summary aria-label="Menu"><span>Menu</span><span class="icone-menu" aria-hidden="true"></span></summary>
<nav class="nav-curto-lista" aria-label="Principal"><a href="{base}">Início</a>{menu_html}</nav>
</details>
</div>
</header>
<main id="conteudo">
{corpo}
</main>
{rodape(ctx, base)}
</body>
</html>
"""


def rodape(ctx, base):
    v = ctx["versao"]
    sha = ctx["commit"]["sha"]
    gerado = ""
    if sha:
        gerado = (f'<p>Este site foi gerado do commit <a href="{dados.REPO}/commit/{sha}">{sha[:7]}</a>, '
                  f'de {data_curta(ctx["commit"]["data"])}. Sem análise de uso, sem cookie, sem nada carregado de outro site.</p>')
    return f"""<footer class="rodape">
<div class="wrap">
<div class="rodape-colunas">
<div class="rodape-marca">
<a class="marca" href="{base}"><img src="{base}icone-64.png" alt="" width="28" height="28">Escalibur Wallet</a>
<p>Carteira cripto sem custódia.<br>Versão {e(v["marketing"])} (build {e(v["build"])}).</p>
{botoes_baixar(ctx, base)}
</div>
<div>
<h2>Produto</h2>
<ul><li><a href="{base}">Início</a></li><li><a href="{base}redes/">Redes e moedas</a></li><li><a href="{base}novidades/">Novidades</a></li></ul>
</div>
<div>
<h2>Segurança</h2>
<ul><li><a href="{base}seguranca/">Como protege</a></li><li><a href="{base}auditoria/">Auditoria</a></li><li><a href="{dados.REPO}">Código no GitHub</a></li><li><a href="{base}suporte/">Relatar um bug</a></li></ul>
</div>
<div>
<h2>Ajuda</h2>
<ul><li><a href="{base}suporte/">Suporte</a></li><li><a href="{base}privacidade/">Privacidade</a></li><li><a href="{base}termos/">Termos de uso</a></li></ul>
</div>
</div>
<div class="rodape-legal">
<p>A Escalibur Wallet é oferecida por {EMPRESA}, CNPJ {CNPJ}.</p>
<p>Apple, iPhone, Face ID e App Store são marcas da Apple Inc. Android, Google Play e o logo do Google Play são marcas do Google LLC. Os logos de redes e moedas pertencem aos seus donos e aparecem só para identificar cada uma.</p>
{gerado}
</div>
</div>
</footer>"""


# MARK: Modelos (site/*.html)

_MARCADOR = re.compile(r"\{\{\s*(\w+)(?:\s+([^}]*?))?\s*\}\}")


def preencher(ctx, base, modelo, origem):
    """Troca cada {{nome argumentos}} do modelo pelo HTML gerado. Marcador desconhecido
    para o build: o site nao sai com um {{...}} perdido na pagina."""

    def troca(achado):
        nome, argumento = achado.group(1), (achado.group(2) or "").strip()
        partes = [p.strip() for p in argumento.split("|")] if argumento else []
        if nome == "base":
            return base
        classe = partes[2] if len(partes) > 2 else ""
        cedo = "cedo" in classe.split()
        classe = " ".join(c for c in classe.split() if c != "cedo")
        if nome == "aparelho":
            return aparelho(base, partes[0], partes[1], classe, cedo=cedo)
        if nome == "capa":
            return aparelho(base, partes[0], partes[1], classe, video=False, cedo=cedo)
        if nome == "codigo":
            return link_codigo(base, partes[0], partes[1] if len(partes) > 1 else None)
        valores = {
            "botoes_baixar": lambda: botoes_baixar(ctx, base),
            "versao": lambda: e(ctx["versao"]["marketing"]),
            "build": lambda: e(ctx["versao"]["build"]),
            "n_redes": lambda: str(len(ctx["redes"])),
            "n_redes_resto": lambda: str(len(ctx["redes"]) - 7),
            "n_tokens": lambda: str(len(ctx["tokens"])),
            "n_verificacoes": lambda: str(ctx["n_verificacoes"]),
            "n_testes": lambda: numero(ctx["n_testes"]),
            "n_travados": lambda: str(ctx["n_travados"]),
            "redes_logos": lambda: grade_de_redes(ctx, base),
            "moedas_abertura": lambda: moedas_abertura(ctx, base),
            "redes_com_tag": lambda: redes_com_tag(ctx),
            "estado_ci": lambda: estado_ci(ctx, base),
            "novidades_resumo": lambda: resumo_novidades(ctx, base),
            "situacao_loja": lambda: ("Disponível na App Store." if ctx["app_store_url"] else "Em preparação para a App Store e o Google Play."),
            "prazos_seguranca": lambda: prazos_seguranca(),
            "prazos_linha": lambda: prazos_linha(),
            "repo": lambda: dados.REPO,
            "precos": lambda: lista_de_precos(ctx, base, ctx.get("retrato")),
            "precos_hora": lambda: e(hora_do_retrato(ctx.get("retrato"))),
            "destaque": lambda: destaque_do_mercado(ctx, base, ctx.get("retrato")),
            "troca_dados": lambda: troca_dados_attr(ctx, base),
            "telas_aparelho": lambda: telas_do_app(ctx, base)[0],
            "telas_passos": lambda: telas_do_app(ctx, base)[1],
            "n_redes_troca": lambda: str(len(dados_da_troca(ctx)["redes"])),
            "verificacoes_feed": lambda: feed_de_verificacoes(ctx, base),
            "redes_frase": lambda: frase_e_redes(ctx, base),
            "estado_ci_curto": lambda: estado_ci_curto(ctx),
        }
        if nome not in valores:
            raise SystemExit(f"gerar-site: marcador desconhecido {{{{{nome}}}}} em {origem}")
        return valores[nome]()

    return _MARCADOR.sub(troca, modelo)


def prazos_seguranca():
    texto = (dados.RAIZ / "SECURITY.md").read_text(encoding="utf-8")
    bloco = re.search(r"Prazos que assumimos:\n((?:- .+\n?)+)", texto)
    if not bloco:
        return ""
    itens = [l[2:].strip().rstrip(";.") for l in bloco.group(1).splitlines() if l.startswith("- ")]
    return "<ul class=\"pontos\">" + "".join(f"<li>{e(i[0].upper() + i[1:])}.</li>" for i in itens) + "</ul>"


def prazos_linha():
    """Os prazos do SECURITY.md numa linha do tempo: o prazo grande, o que acontece nele."""
    texto = (dados.RAIZ / "SECURITY.md").read_text(encoding="utf-8")
    bloco = re.search(r"Prazos que assumimos:\n((?:- .+\n?)+)", texto)
    if not bloco:
        return ""
    itens = []
    for linha in bloco.group(1).splitlines():
        if not linha.startswith("- "):
            continue
        frase = linha[2:].strip().rstrip(";.")
        oque, _, prazo = frase.rpartition(" em ")
        if not oque:
            oque, prazo = frase, ""
        itens.append(f"<li><b>{e(prazo)}</b><span>{e(oque[0].upper() + oque[1:])}</span></li>")
    return '<ol class="prazos">' + "".join(itens) + "</ol>"


# MARK: Paginas de texto (suporte, privacidade, termos)


def pagina_de_texto(ctx, base, rota, titulo, descricao, corpo_html, ativa=None, sobretitulo=""):
    sobre = f'<p class="sobretitulo">{e(sobretitulo)}</p>' if sobretitulo else ""
    corpo = f"""<header class="cabeca-pagina"><div class="wrap estreito">{sobre}<h1 class="titulo-pagina">{e(titulo)}</h1></div></header>
<article class="artigo"><div class="wrap estreito">
{corpo_html}
</div></article>"""
    return moldura(ctx, base, rota, titulo, descricao, corpo, ativa)


# MARK: Auditoria


def _nome_secao(nome):
    texto = acentos.acentuar(nome)
    return texto[0].upper() + texto[1:]


def pagina_auditoria(ctx, base):
    v = ctx["versao"]
    commit = ctx["commit"]
    sha = commit["sha"]
    ci = ctx["ci"]

    if ci is None:
        ci_html = "Sem dado<small>Este build foi gerado fora do GitHub Actions.</small>"
    else:
        rotulos = {"passou": "Passou", "falhou": "Falhou", "rodando": "Rodando", "cancelado": "Cancelada",
                   "sem": "Ainda sem resultado", "outro": "Sem conclusão"}
        rotulo = rotulos.get(ci["estado"], "Sem dado")
        detalhe = "Workflow verificar, no macOS: verificar.sh --testes, app em Release e testes de unidade."
        if ci.get("url"):
            detalhe += f' <a href="{e(ci["url"])}">Ver a execução</a>.'
        ci_html = f"{rotulo}<small>{detalhe}</small>"

    commit_html = "Sem git neste build"
    if sha:
        commit_html = (f'<a href="{dados.REPO}/commit/{sha}"><code>{sha[:12]}</code></a>'
                       f'<small>{data_longa(commit["data"])}, na main.</small>')

    publicado = f"""<dl class="publicado">
<div><dt>Commit publicado</dt><dd>{commit_html}</dd></div>
<div><dt>Verificação no CI</dt><dd>{ci_html}</dd></div>
<div><dt>Versão do app</dt><dd>{e(v["marketing"])} (build {e(v["build"])})<small>De project.yml. {"Disponível na App Store." if ctx["app_store_url"] else "Em preparação para a App Store."}</small></dd></div>
</dl>"""

    ref = sha or "main"
    xcode = (dados.RAIZ / ".xcode-version").read_text(encoding="utf-8").strip() if (dados.RAIZ / ".xcode-version").exists() else "Xcode"
    passos = f"""<ol class="passos">
<li><code>git clone {dados.REPO}.git
cd escalibur-wallet
git checkout {e(ref[:12])}</code><span>O mesmo commit desta página.</span></li>
<li><code>./tools/verificar.sh --testes</code><span>As verificações abaixo e os {numero(ctx["n_testes"])} testes do núcleo. Num Mac com {e(xcode)}.</span></li>
<li><code>python3 tools/gerar-site.py build/site</code><span>Gera este site de novo, com os mesmos números.</span></li>
</ol>"""

    grupos = []
    for i, secao in enumerate(ctx["verificacoes"]):
        itens = []
        for linha, mensagem, so_testes in secao["itens"]:
            marca = '<span class="marca-teste">com --testes</span>' if so_testes else ""
            itens.append(
                f'<li><span>{acento(mensagem)}{marca} '
                f'<span class="onde"><a href="{blob(ctx, "tools/verificar.sh", linha)}" aria-label="verificar.sh, linha {linha}">linha {linha}</a></span></span></li>'
            )
        grupos.append(
            f'<section class="cartao"><h3>{e(_nome_secao(secao["nome"]))}<span class="conta">{len(secao["itens"])}</span></h3>'
            f'<ul class="checagens">{"".join(itens)}</ul></section>'
        )

    hosts = []
    for rotulo, lista in ctx["grupos_hosts"]:
        chips = "".join(f"<li>{e(h)}</li>" for h in lista)
        hosts.append(f'<section class="cartao"><h3>{e(rotulo)}</h3>'
                     f'<ul class="hosts">{chips}</ul></section>')

    travas = []
    for t in ctx["travas"]:
        meta = []
        if t["origem"]:
            meta.append(f'Origem: <a href="{e(t["origem"])}">{e(t["origem"].replace("https://", ""))}</a>')
        if t["versao"]:
            meta.append(f"versão <code>{e(t['versao'])}</code>")
        for chave, valor in t["extra"]:
            rotulo = {"tag_objeto": "objeto da tag", "tarball_sha256": "SHA-256 do pacote"}.get(chave, chave)
            meta.append(f"{rotulo} <code>{e(valor)}</code>")
        linhas = "".join(f"<div><dt>{e(nome)}</dt><dd>{e(digesto)}</dd></div>" for nome, digesto in t["arquivos"])
        descricao = f"<p>{e(t['descricao'])}</p>" if t["descricao"] else ""
        travas.append(
            f'<details class="grupo"><summary><code>{e(t["arquivo"])}</code><span class="conta">{len(t["arquivos"])} arquivos</span></summary>'
            f'<div class="grupo-corpo"><div class="trava-meta">{descricao}<p>{" · ".join(meta)}</p>'
            f'<p><a href="{blob(ctx, t["arquivo"])}">Ver {e(t["arquivo"])} no GitHub</a></p></div>'
            f'<dl class="digestos">{linhas}</dl></div></details>'
        )

    arquivos = []
    grupo_atual = None
    for grupo, slug, titulo, caminho in ARQUIVOS_CHAVE:
        info = ctx["arquivos_chave"][slug]
        if grupo != grupo_atual:
            if grupo_atual is not None:
                arquivos.append("</ul>")
            arquivos.append(f'<h3 class="sobretitulo subtitulo-bloco">{e(grupo)}</h3><ul class="arquivos">')
            grupo_atual = grupo
        arquivos.append(
            f'<li><a href="{base}auditoria/codigo/{slug}/"><b>{e(titulo)}</b>'
            f'<span>{e(info["resumo_curto"])}</span><code>{e(caminho)} · {numero(info["linhas"])} linhas</code></a></li>'
        )
    arquivos.append("</ul>")
    arquivos_html = "".join(arquivos)

    auditorias = "".join(
        f'<li><b>{e(a["titulo"])}</b><a href="{blob(ctx, a["caminho"])}">Ler o relatório no GitHub</a></li>'
        for a in ctx["auditorias"]
    )

    hash_cabeca = ""
    if sha and re.fullmatch(r"[0-9a-f]{40}", sha):
        hash_cabeca = (f'<figure class="hash-cabeca"><canvas class="pixels-hash grande" data-hashes="{e(sha)}" data-colunas="8" data-linhas="5" aria-hidden="true"></canvas>'
                       f'<figcaption>Commit publicado <code>{e(sha[:12])}</code>, em pixels: cada tom é um dígito do hash.</figcaption></figure>')
    corpo = f"""<header class="cabeca-pagina cabeca-centro"><div class="wrap">
{hash_cabeca}
<p class="sobretitulo">Auditoria</p>
<h1 class="titulo-pagina">Confira você mesmo.</h1>
<p class="lead">Tudo nesta página saiu do repositório no build que a publicou: as verificações que rodam a cada mudança, os servidores que o app pode chamar, o que vem de fora conferido arquivo por arquivo e os arquivos que guardam as chaves. Nada é buscado depois.</p>
<ul class="seg-resumo" aria-label="Em resumo" data-revelar>
<li><b>{ctx["n_verificacoes"]}</b><span>verificações a cada mudança</span></li>
<li><b>0</b><span>dependências baixadas da internet para montar o app</span></li>
<li><b>{numero(ctx["n_testes"])}</b><span>testes do núcleo</span></li>
</ul>
</div></header>

<section class="bloco titulos-centro" aria-labelledby="t-build"><div class="wrap">
<h2 id="t-build">Este build</h2>
{publicado}
<h3 class="sobretitulo subtitulo-bloco">Conferir na sua máquina</h3>
{passos}
</div></section>

<section class="bloco titulos-centro" aria-labelledby="t-verificacoes"><div class="wrap">
<h2 id="t-verificacoes">{ctx["n_verificacoes"]} verificações</h2>
<p class="lead intro">O <code>tools/verificar.sh</code> confere no código o que o app promete em texto. Cada linha abaixo é uma afirmação que o script prova a cada mudança, no CI, e para o merge se falhar. Cada uma leva à linha onde mora.</p>
<div class="mosaico">{"".join(grupos)}</div>
</div></section>

<section class="bloco titulos-centro" aria-labelledby="t-hosts"><div class="wrap">
<h2 id="t-hosts">Uma lista fechada de servidores, e nenhum outro</h2>
<p class="lead intro">O app só fala com os endereços do <code>hosts.lock</code>. O cliente HTTP recusa qualquer outro em tempo de execução, e cada um está na Política de privacidade, com o que vê. Agrupados como a Política descreve.</p>
<p class="apoio links-bloco">{link_codigo(base, "hosts-permitidos", "Ler a lista compilada no app")} · <a href="{blob(ctx, "hosts.lock")}">hosts.lock no GitHub</a></p>
<div class="mosaico">{"".join(hosts)}</div>
</div></section>

<section class="bloco titulos-centro" aria-labelledby="t-travas"><div class="wrap">
<h2 id="t-travas">O que vem de fora, conferido arquivo por arquivo</h2>
<p class="lead intro">Nenhum pacote é baixado na hora de montar o app, e nenhum binário vem pronto. As bibliotecas de criptografia e as listas de palavras estão no repositório, compiladas do fonte, e o verificador confere a impressão digital (SHA-256) de cada arquivo.</p>
<div class="verificacoes">{"".join(travas)}</div>
</div></section>

<section class="bloco titulos-centro" aria-labelledby="t-codigo"><div class="wrap">
<h2 id="t-codigo">O código que importa</h2>
<p class="lead intro">Os arquivos que assinam, conferem o que se assina, guardam as chaves e falam com a rede, linha a linha, no commit publicado. Cada linha leva à mesma linha no GitHub.</p>
<div class="arquivos-grupos">{arquivos_html}</div>
</div></section>

<section class="bloco titulos-centro" aria-labelledby="t-auditorias"><div class="wrap">
<h2 id="t-auditorias">Auditorias de segurança</h2>
<p class="lead intro">Os relatórios das revisões de segurança, com os achados e o que foi feito de cada um.</p>
<ul class="auditorias">{auditorias}</ul>
</div></section>"""
    return moldura(ctx, base, "auditoria", "Auditoria", "Confira o código da Escalibur Wallet: verificações, servidores, dependências travadas e os arquivos que guardam as chaves, gerados do repositório.", corpo, "auditoria")


def pagina_codigo(ctx, base, slug, titulo, caminho):
    info = ctx["arquivos_chave"][slug]
    fonte = info["fonte"]
    linhas = codigo.destacar(caminho, fonte)
    if linhas and linhas[-1] == "" and fonte.endswith("\n"):
        linhas = linhas[:-1]
    sha = ctx["commit"]["sha"]
    corpo_linhas = "".join(
        f'<tr id="L{n}"><td class="n"><a href="{blob(ctx, caminho, n)}" aria-label="Linha {n} no GitHub">{n}</a></td>'
        f'<td class="l">{conteudo or " "}</td></tr>'
        for n, conteudo in enumerate(linhas, 1)
    )
    no_commit = f"no commit {sha[:7]}" if sha else "na main"
    corpo = f"""<header class="codigo-cabeca"><div class="wrap">
<a class="voltar" href="{base}auditoria/#t-codigo">Auditoria</a>
<h1 class="titulo-pagina">{e(titulo)}</h1>
<code class="caminho">{e(caminho)}</code>
<p class="lead">{e(info["resumo"])}</p>
<div class="codigo-meta"><span>{numero(len(linhas))} linhas</span><span>SHA-256 <code>{info["digesto"][:16]}…</code></span><a href="{blob(ctx, caminho)}">Abrir no GitHub, {no_commit}</a></div>
</div></header>
<div class="wrap"><div class="fonte" tabindex="0" aria-label="Código de {e(caminho)}"><table><tbody>{corpo_linhas}</tbody></table></div></div>"""
    return moldura(ctx, base, f"auditoria/codigo/{slug}", titulo, f"{titulo}: {caminho}, linha a linha, no código da Escalibur Wallet.", corpo, "auditoria")


# MARK: Redes e moedas


def _tempo(segundos):
    if segundos < 60:
        return f"cerca de {segundos} s"
    minutos = round(segundos / 60)
    return f"cerca de {minutos} min"


# "Abrir em outro app": como as mesmas palavras abrem o mesmo saldo fora da Escalibur, rede
# por rede (auditoria 4, C7-09). Saiu dos Ajustes do app e ficou aqui (pedido do dono,
# 18/10/2026). O levantamento, com as fontes, esta em docs/blockchain.md. Por rede: os apps que
# abrem a mesma conta, a armadilha, e quem aceita a passphrase (None: nenhum app comum).
OUTRO_APP_EVM = ("MetaMask, Rabby ou Trust Wallet, na primeira conta.",
                 "O endereço é o mesmo em todas as redes EVM. Se a rede não aparece, adicione pelo número da rede; se um token não aparece, importe pelo contrato.",
                 "A Rabby aceita; a MetaMask não.")
OUTRO_APP = {
    "bitcoin": ("Sparrow, Electrum ou BlueWallet, no tipo Native SegWit (bc1q).",
                "O troco fica em endereços próprios da carteira, e esses três os encontram. Em Taproot, Legacy ou Nested, o app mostra outra conta.",
                "Sparrow, Electrum e BlueWallet aceitam."),
    "litecoin": ("Trust Wallet, endereço ltc1q.", None, None),
    "dogecoin": ("Trust Wallet.", None, None),
    "solana": ("Phantom.", "Na Trust Wallet e no Ledger Live, a mesma frase mostra outro endereço.",
               "Só pela linha de comando (solana-keygen)."),
    "xrpl": ("Xaman, em Importar com frase, ou Trust Wallet.",
             "Se a Xaman perguntar a curva, escolha secp256k1. A conta guarda 1 XRP de reserva.", "A Xaman aceita."),
    "stellar": ("Freighter, LOBSTR ou Trust Wallet.", "Parte do XLM fica reservada pela rede.", None),
    "tron": ("Trust Wallet ou TronLink.", "Para mover USDT é preciso ter TRX.", None),
    "ton": ("Tonkeeper, MyTonWallet ou Trust Wallet.", "Na Tonkeeper, escolha a versão V4R2: a W5 da mesma frase é outro endereço.", None),
    "sui": ("Slush ou Trust Wallet.", None, None),
    "cardano": ("Eternl ou Trust Wallet. A Yoroi só aceita 15 ou 24 palavras.", "Na Ledger, a mesma frase abre outra conta.",
                "Só a Trezor e a ferramenta cardano-address."),
    "polkadot": ("Só a Trust Wallet.", "Polkadot.js, Nova, Talisman e Ledger mostram outra conta, vazia. O saldo está na Polkadot Asset Hub.", None),
    "near": ("MyNearWallet ou Trust Wallet.", "A conta é o código de 64 caracteres, não um nome .near.", None),
    "aptos": ("Petra ou Trust Wallet.", None, None),
}
SEM_PASSPHRASE = "Nenhum app comum conhecido aceita a passphrase nesta rede. O saldo daqui só sai pela Escalibur ou por ferramenta técnica."


def secao_outro_app(ctx, base):
    """As redes da carteira com os apps que abrem a mesma conta, as EVM juntas numa linha."""
    redes = ctx["redes"]
    evm = [r for r in redes if r["familia"] == "evm"]
    fora = [r for r in redes if r["familia"] != "evm"]
    grupos = fora[:1] + ([evm] if evm else []) + fora[1:]
    linhas = []
    for grupo in grupos:
        if isinstance(grupo, list):
            primeiro, nome = grupo[0], f"Redes EVM ({len(grupo)})"
            apps, nota, passphrase = OUTRO_APP_EVM
            extra = f'<small>{e(", ".join(r["nome"] for r in grupo))}</small>'
        else:
            primeiro, nome = grupo, grupo["nome"]
            apps, nota, passphrase = OUTRO_APP.get(grupo["id"], ("Trust Wallet.", None, None))
            extra = ""
        partes = [f'<p><b>Abre em:</b> {e(apps)}</p>']
        if nota:
            partes.append(f'<p><b>Atenção:</b> {e(nota)}</p>')
        partes.append(f'<p><b>Com passphrase:</b> {e(passphrase or SEM_PASSPHRASE)}</p>')
        linhas.append(f'<li>{logo_rede(ctx, base, primeiro)}<div><b>{e(nome)}</b>{extra}</div>'
                      f'<div class="outro-app-texto">{"".join(partes)}</div></li>')
    decifrar = blob(ctx, "tools/referencia/decifrar.py")
    return f"""<section class="bloco titulos-centro" aria-labelledby="t-outro-app" id="outro-app"><div class="wrap">
<h2 id="t-outro-app">Abrir em outro app</h2>
<p class="lead intro">As palavras da carteira abrem o mesmo saldo em outros apps, se você não tiver mais a Escalibur. Cada rede tem os apps que abrem a mesma conta.</p>
<ul class="regras-outro-app">
<li>Use sempre a primeira conta do outro app. Digite as palavras em minúsculas, com um espaço entre elas.</li>
<li>Com passphrase: sem ela, ou com uma letra diferente, abre outra carteira, vazia.</li>
<li>Antes de mover tudo, confira se o endereço que o outro app mostra começa e termina como o da Escalibur. Mova um valor pequeno primeiro.</li>
<li class="regra-cuidado">Baixe o outro app só da loja oficial. Nunca digite as palavras num site nem as mande a ninguém: quem oferece recuperar saldo quer o saldo.</li>
</ul>
<ul class="tabela-redes outro-app">{"".join(linhas)}</ul>
<p class="apoio">Tem um envelope Escalibur? O programa público <a href="{decifrar}">decifrar.py</a>, no código da Escalibur, abre o envelope num computador, sem o celular, e devolve as palavras e a passphrase.</p>
<p class="apoio">Conferido em outubro de 2026, no código e na documentação de cada app. Os apps mudam: confira o endereço antes de mover.</p>
</div></section>"""


def pagina_redes(ctx, base):
    redes = ctx["redes"]
    por_id = {r["id"]: r for r in redes}
    linhas = []
    for r in redes:
        familia = dados.FAMILIAS.get(r["familia"], r["familia"])
        if r["chain_id"] is not None:
            familia += f", chainId {r['chain_id']}"
        elif familia == r["nome"]:
            familia = f"curva {dados.CURVAS.get(r['familia'], '')}".strip()
        detalhes = [r["simbolo"], familia]
        segunda = [f"confirma em {_tempo(r['segundos'])}"]
        if r["tag"]:
            segunda.append(f"pede {r['tag']}")
        segunda.append(f"explorador {r['explorador']}")
        linhas.append(
            f'<li>{logo_rede(ctx, base, r)}<div><b>{e(r["nome"])}</b><small>{e(" · ".join(detalhes))}</small>'
            f'<small>{e(", ".join(segunda))}</small></div></li>'
        )

    # Uma linha por moeda: mesmo simbolo e mesmo id de preco. O ETH da Binance na BNB tem
    # o preco do WETH, mas nao e o WETH: fica na linha dele.
    grupos = {}
    for t in ctx["tokens"]:
        grupos.setdefault((t["simbolo"].upper(), t["gecko"]), []).append(t)
    ordenados = sorted(grupos.values(), key=lambda g: (g[0]["simbolo"].lower(), g[0]["nome"].lower()))
    itens = []
    for grupo in ordenados:
        primeiro = grupo[0]
        estavel = '<span class="selo-estavel">stablecoin</span>' if primeiro["estavel"] else ""
        minis = "".join(logo_rede(ctx, base, por_id[t["rede"]]) for t in grupo[:6] if t["rede"] in por_id)
        resto = f'<span class="mais-redes">+{len(grupo) - 6}</span>' if len(grupo) > 6 else ""
        nomes_redes = ", ".join(por_id[t["rede"]]["nome"] for t in grupo if t["rede"] in por_id)
        contratos = []
        for t in grupo:
            rede = por_id.get(t["rede"])
            if not rede:
                continue
            if "contrato" in t:
                alvo, rotulo = t["contrato"], t["contrato"]
            else:
                alvo, rotulo = t["emissor"], f"{t['simbolo']} emitido por {t['emissor']}"
            url = (rede["explorador_endereco"] or "").replace("{address}", alvo)
            link = f'<a href="{e(url)}">{e(rotulo)}</a>' if url.startswith("https://") else e(rotulo)
            variante = f" · {t['nome']}" if t["nome"] != primeiro["nome"] else ""
            contratos.append(f"<div><dt>{e(rede['nome'])}, {t['casas']} casas{e(variante)}</dt><dd>{link}</dd></div>")
        busca = " ".join([primeiro["simbolo"], primeiro["nome"], primeiro["gecko"], nomes_redes]).lower()
        busca = re.sub(r"\s+", " ", busca)
        plural = "redes" if len(grupo) > 1 else "rede"
        itens.append(
            f'<li data-busca="{e(acentos_fora(busca))}"><details class="token"><summary>{logo_token(ctx, base, primeiro)}'
            f'<span class="token-nome"><b>{e(primeiro["simbolo"])}</b>{estavel}<small>{e(primeiro["nome"])} · {len(grupo)} {plural}</small></span>'
            f'<span class="mini-redes" aria-label="{e(nomes_redes)}">{minis}{resto}</span></summary>'
            f'<dl class="contratos">{"".join(contratos)}</dl></details></li>'
        )

    corpo = f"""<header class="cabeca-pagina cabeca-centro cabeca-moedas">
<picture class="cabeca-moedas-paradas" aria-hidden="true">
<source media="(max-width: 699px)" srcset="{base}midia/moedas-estreito.webp" width="780" height="1560">
<img src="{base}midia/moedas-largo.webp" alt="" width="1600" height="1000" decoding="async" draggable="false">
</picture>
<canvas class="redes-3d" aria-hidden="true"></canvas>
<div class="wrap">
<p class="sobretitulo">Redes e moedas</p>
<h1 class="titulo-pagina">{len(redes)} redes.<br>{len(ctx["tokens"])} tokens conferidos.</h1>
<p class="lead">Esta página sai do código do app a cada publicação: as redes de <a href="{blob(ctx, "Kit/Sources/EscaliburChains/Chain.swift")}">Chain.swift</a> e os tokens de <a href="{blob(ctx, "Kit/Sources/EscaliburChains/TokenRegistry.swift")}">TokenRegistry.swift</a>. Nenhuma rede ou token entra no app por resposta de servidor.</p>
</div></header>

<section class="bloco titulos-centro" aria-labelledby="t-redes"><div class="wrap">
<h2 id="t-redes">As redes</h2>
<p class="lead intro">Cada carteira é uma frase BIP-39 de 12 ou 24 palavras, derivada pelos caminhos padrão de cada rede. O chainId, o explorador e o tempo de confirmação são constantes compiladas.</p>
<ul class="tabela-redes">{"".join(linhas)}</ul>
</div></section>

<section class="bloco titulos-centro" aria-labelledby="t-tokens"><div class="wrap">
<h2 id="t-tokens">Os tokens conferidos</h2>
<p class="lead intro">{len(grupos)} moedas em {len(ctx["tokens"])} contratos. Cada contrato foi conferido na fonte oficial do emissor e lido em dois nós da rede antes de entrar na lista. Token fora dela aparece no app como não verificado, sem entrar no saldo total sem preço pelo contrato.</p>
<div class="busca"><label class="apoio" for="busca-token">Procurar por nome, símbolo ou rede</label><br><input id="busca-token" type="search" placeholder="USDC, Solana, Lido…" autocomplete="off" spellcheck="false"></div>
<ul class="lista-tokens">{"".join(itens)}</ul>
<p id="busca-vazia" class="apoio" hidden>Nenhum token da lista com esse nome. Fora da lista, o app mostra o token como não verificado.</p>
</div></section>
{secao_outro_app(ctx, base)}"""
    return moldura(ctx, base, "redes", "Redes e moedas", f"As {len(redes)} redes e os {len(ctx['tokens'])} tokens conferidos da Escalibur Wallet, gerados do código do app.", corpo, "redes")


def acentos_fora(texto):
    import unicodedata
    return "".join(c for c in unicodedata.normalize("NFD", texto) if unicodedata.category(c) != "Mn")


# MARK: Novidades


def texto_novidade(c, texto):
    """Em ingles, como esta; o portugues antigo ganhava acento aqui."""
    return e(texto) if c.get("en") else acento(texto)


def corpo_do_commit(blocos, c=None):
    c = c or {}
    partes, lista = [], []

    def fecha():
        if lista:
            partes.append("<ul>" + "".join(f"<li>{texto_novidade(c, i)}</li>" for i in lista) + "</ul>")
            lista.clear()

    for tipo, texto in blocos:
        if tipo == "item":
            lista.append(texto)
            continue
        fecha()
        if tipo == "titulo":
            partes.append(f"<h3>{texto_novidade(c, texto)}</h3>")
        else:
            partes.append(f"<p>{texto_novidade(c, texto)}</p>")
    fecha()
    return "".join(partes)


def pagina_novidades(ctx, base):
    """As entregas, em ingles (dados.em_ingles). Abrindo pelo link de uma novidade
    (#c-xxxxxxx), o site.js ja abre aquela."""
    v = ctx["versao"]
    entregas = []
    for c in ctx["commits"]:
        corpo = corpo_do_commit(c["corpo"], c)
        detalhe = f'<details class="entrega-detalhe"><summary>O que mudou</summary><div class="entrega-corpo" lang="en">{corpo}</div></details>' if corpo else ""
        rodape = "" if c.get("anterior") else f'<p class="commit"><a href="{dados.REPO}/commit/{c["sha"]}">Commit {c["sha"][:7]} no GitHub</a></p>'
        entregas.append(
            f'<article class="entrega" id="c-{c["sha"][:7]}"><time datetime="{data_iso(c["data"])}">{data_longa(c["data"])}</time>'
            f'<h2 lang="en">{texto_novidade(c, c["assunto"])}</h2>{detalhe}{rodape}</article>'
        )
    situacao = "Disponível na App Store." if ctx["app_store_url"] else "Em preparação para a App Store e o Google Play."
    vazio = "<p>O histórico não estava disponível neste build.</p>" if not entregas else ""
    hashes = ",".join(c["sha"] for c in ctx["commits"] if re.fullmatch(r"[0-9a-f]{40}", c["sha"] or ""))
    parede = (f'<canvas class="pixels-hash parede" data-hashes="{e(hashes)}" data-colunas="{hashes.count(",") + 1}" data-linhas="8" '
              f'data-ordem="coluna" aria-hidden="true"></canvas>') if hashes else ""
    corpo = f"""<header class="cabeca-pagina cabeca-centro"><div class="wrap">
{parede}
<p class="sobretitulo">Novidades</p>
<h1 class="titulo-pagina">O que mudou.</h1>
<p class="lead">Versão <strong>{e(v["marketing"])}</strong> (build {e(v["build"])}). {situacao} Cada entrega é um commit público no GitHub, e cada coluna de pixels acima é o hash de um deles.</p>
<p class="apoio">Gerada a cada publicação, do histórico da main. As entregas aparecem em inglês, a língua dos commits.</p>
</div></header>
<section class="bloco"><div class="wrap estreito">{vazio}{"".join(entregas)}</div></section>"""
    return moldura(ctx, base, "novidades", "Novidades", "As últimas atualizações da Escalibur Wallet, geradas do histórico de commits.", corpo, "novidades")


# MARK: 404


def pagina_404(ctx):
    # O 404 e a unica pagina com caminho absoluto: a raiz no site da org; na copia do
    # endereco antigo (tmzzjr.github.io/escalibur-wallet, para os builds 7 a 9), a pasta.
    base = os.environ.get("SITE_BASE", "/")
    corpo = f"""<header class="cabeca-pagina"><div class="wrap estreito">
<p class="sobretitulo">Erro 404</p>
<h1 class="titulo-pagina">Esta página não existe.</h1>
<p class="lead">O endereço pode ter mudado. Comece pelo início, ou vá direto ao que procura.</p>
<div class="botoes"><a class="botao botao-principal" href="{base}">Ir para o início</a><a class="botao botao-secundario" href="{base}suporte/">Suporte</a></div>
</div></header>"""
    return moldura(ctx, base, "404", "Página não encontrada", "Página não encontrada.", corpo)


def digesto(texto):
    return hashlib.sha256(texto.encode("utf-8")).hexdigest()


# MARK: Suporte (o questionario do app)

# Os assuntos da tela de Suporte do app (SupportView.Topic), na mesma ordem: titulo, se
# pergunta a rede, se pergunta a transacao, e o icone (o simbolo do app, em traco).
ASSUNTOS = [
    ("Envio ou recebimento", True, True, '<path d="M7 16V4M3.5 7.5 7 4l3.5 3.5M13 4v12M9.5 12.5 13 16l3.5-3.5"/>'),
    ("Troca ou ponte", True, True, '<path d="M4 7h12M12.5 3.5 16 7l-3.5 3.5M16 13H4M7.5 9.5 4 13l3.5 3.5"/>'),
    ("Saldo que não aparece", True, False, '<path d="M2.5 10s2.8-5 7.5-5 7.5 5 7.5 5-2.8 5-7.5 5-7.5-5-7.5-5Z"/><circle cx="10" cy="10" r="2.2"/><path d="M3.5 3.5 16.5 16.5"/>'),
    ("Entrar no app: PIN ou Face ID", False, False, '<path d="M3 6.5V5a2 2 0 0 1 2-2h1.5M13.5 3H15a2 2 0 0 1 2 2v1.5M17 13.5V15a2 2 0 0 1-2 2h-1.5M6.5 17H5a2 2 0 0 1-2-2v-1.5M7.5 8v1M12.5 8v1M10 8v3H9.2M7.8 13.2c1.3 1 3.1 1 4.4 0"/>'),
    ("Importar ou recuperar uma carteira", False, False, '<path d="M4.5 10a5.5 5.5 0 1 0 1.6-3.9M4 3.5v3h3"/>'),
    ("Sugestão", False, False, '<path d="M7.5 14.5h5M8.3 17h3.4M10 3a5 5 0 0 0-3 9c.6.5 1 1.2 1 2h4c0-.8.4-1.5 1-2a5 5 0 0 0-3-9Z"/>'),
    ("Outro assunto", False, False, '<path d="M4 4.5h12a1.5 1.5 0 0 1 1.5 1.5v6.5A1.5 1.5 0 0 1 16 14H9l-3.5 3v-3H4a1.5 1.5 0 0 1-1.5-1.5V6A1.5 1.5 0 0 1 4 4.5Z"/><circle cx="7" cy="9.2" r=".6"/><circle cx="10" cy="9.2" r=".6"/><circle cx="13" cy="9.2" r=".6"/>'),
]

ICONE_MAO = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M6.5 10V4.8a1.2 1.2 0 0 1 2.4 0V9M8.9 8.5V3.6a1.2 1.2 0 0 1 2.4 0v4.9M11.3 8.5V4.6a1.2 1.2 0 0 1 2.4 0v5.2M13.7 9.5V7.2a1.2 1.2 0 0 1 2.4 0v4.6c0 3-2.2 5.2-5.2 5.2-1.8 0-3.2-.8-4.2-2.2L4 11.2a1.3 1.3 0 0 1 2.1-1.5l.4.5"/></svg>'
ICONE_IPHONE = '<svg viewBox="0 0 20 20" aria-hidden="true"><rect x="5.5" y="2" width="9" height="16" rx="2.2"/><path d="M8.5 4.2h3"/></svg>'
ICONE_LUPA = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M5 2.5h6.5L15 6v2M15 13.5V17a.5.5 0 0 1-.5.5h-9A.5.5 0 0 1 5 17V3"/><circle cx="12.5" cy="11.5" r="2.8"/><path d="m14.6 13.6 2.4 2.4"/></svg>'


def _secoes(itens):
    """O suporte.md em secoes: a abertura e cada ## com o que vem embaixo."""
    secoes, atual = {"": []}, ""
    for tipo, texto in itens:
        if tipo == "h2":
            atual = texto
            secoes[atual] = []
        else:
            secoes[atual].append((tipo, texto))
    return secoes


def pagina_suporte(ctx, base, itens, email, inline):
    """A pagina de suporte no desenho da tela do app (pedido do dono, 18/10/2026): o mesmo
    questionario em passos, que vira um e-mail pronto (o site.js monta; o site nao manda
    nada sozinho), e as duvidas do suporte.md em cartoes que abrem. O texto continua sendo o
    do suporte.md, o mesmo que o verificar.sh confere."""
    secoes = _secoes(itens)
    palavras = next((v for k, v in secoes.items() if k.startswith("Nunca mande")), [])
    duvidas = next((v for k, v in secoes.items() if k.startswith("Antes de escrever")), [])
    nao_faz = next((v for k, v in secoes.items() if k.startswith("O que a Escalibur")), [])
    falha_titulo = next((k for k in secoes if k.startswith("Falha")), "")
    falha = secoes.get(falha_titulo, [])

    opcoes = "".join(
        f'<label class="opcao"><input type="radio" name="assunto" value="{e(titulo)}"'
        f'{" data-rede" if rede else ""}{" data-transacao" if transacao else ""}>'
        f'<span class="opcao-icone"><svg viewBox="0 0 20 20" aria-hidden="true">{icone}</svg></span>'
        f'<span class="opcao-nome">{e(titulo)}</span><span class="opcao-marca" aria-hidden="true"></span></label>'
        for titulo, rede, transacao, icone in ASSUNTOS)
    redes = "".join(f'<option>{e(r["nome"])}</option>' for r in ctx["redes"])

    cartoes = []
    for tipo, texto in duvidas:
        if tipo != "li":
            continue
        achado = re.match(r"\*\*(.+?)\*\*\s*(.*)", texto)
        pergunta, resposta = (achado.group(1), achado.group(2)) if achado else (texto, "")
        cartoes.append(f'<details class="duvida"><summary>{e(pergunta.rstrip("."))}</summary><p>{inline(resposta)}</p></details>')

    def texto(lista):
        return " ".join(inline(t) for tipo, t in lista if tipo == "p")

    mail = f'<a href="mailto:{e(email)}">{e(email)}</a>'
    corpo = f"""<header class="cabeca-pagina"><div class="wrap">
<p class="sobretitulo">Ajuda</p>
<h1 class="titulo-pagina">Fale com o suporte</h1>
<p class="lead">Conte o que aconteceu em poucos passos. O chamado abre pronto no seu app de e-mail, e a resposta chega no e-mail que você digitar.</p>
</div></header>
<section class="bloco suporte" aria-label="Chamado e dúvidas comuns"><div class="wrap suporte-grade">
<form class="chamado" id="chamado" data-para="{e(email)}" novalidate>
<fieldset class="passo"><legend><span class="passo-numero">1</span>Sobre o que é?</legend>
<div class="opcoes">{opcoes}</div>
</fieldset>
<fieldset class="passo" id="passo-rede" hidden><legend><span class="passo-numero">2</span>Em qual rede?</legend>
<select name="rede" class="campo"><option>Não sei</option>{redes}</select>
</fieldset>
<fieldset class="passo"><legend><span class="passo-numero">2</span>O que aconteceu?</legend>
<textarea name="detalhes" class="campo" rows="6" placeholder="O que você fez, o que esperava e o que apareceu na tela."></textarea>
<p class="alerta-frase" id="alerta-frase" hidden><b>Isto parece a senha da carteira.</b> Apague as palavras antes de mandar. Ninguém da Escalibur precisa delas, nem para ajudar.</p>
<label class="campo-rotulo" id="campo-transacao" hidden>ID da transação, se tiver<input name="transacao" class="campo" autocomplete="off" spellcheck="false" placeholder="Copie na Atividade, no detalhe do envio"></label>
</fieldset>
<fieldset class="passo"><legend><span class="passo-numero">3</span>Seu e-mail para a resposta</legend>
<input type="email" name="email" class="campo" autocomplete="email" placeholder="seu@email.com">
<input type="email" name="email2" class="campo" autocomplete="off" placeholder="Repita o e-mail">
<p class="erro-campo" id="erro-email" hidden></p>
</fieldset>
<button class="botao botao-principal" id="enviar-chamado" type="submit" disabled>Enviar ao suporte</button>
<p class="chamado-pronto" id="chamado-pronto" hidden><b>Chamado pronto no seu e-mail.</b> Depois de enviar, a resposta do suporte chega no e-mail que você digitou.</p>
<p class="apoio so-sem-js">Sem JavaScript, o questionário não monta o e-mail: escreva direto para {mail}.</p>
<p class="apoio chamado-direto">Prefere escrever direto? {mail}</p>
</form>
<aside class="suporte-lado">
<div class="aviso-palavras">{ICONE_MAO}<div><h2>Nunca mande as palavras da carteira</h2><p>{texto(palavras)}</p></div></div>
<h2 class="duvidas-titulo">Antes de escrever</h2>
<div class="duvidas">{"".join(cartoes)}</div>
<ul class="pontos-cartao">
<li>{ICONE_IPHONE}<p>{texto(nao_faz)}</p></li>
<li>{ICONE_LUPA}<p>Vai junto só o que você escreveu e o seu e-mail. Endereço da carteira e saldo não vão, e o site não guarda nada: o e-mail sai do seu app de e-mail.</p></li>
</ul>
<h2 class="duvidas-titulo">{e(falha_titulo)}</h2>
<p class="apoio falha-texto">{texto(falha)}</p>
</aside>
</div></section>
<script src="{base}palavras-bip39.js" defer></script>"""
    return moldura(ctx, base, "suporte", "Suporte", "Como falar com a Escalibur e o que fazer antes de escrever.", corpo, "suporte")
