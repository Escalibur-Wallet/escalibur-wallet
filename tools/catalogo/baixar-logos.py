#!/usr/bin/python3 -IS
"""Embarca no app as logos das maiores moedas do CoinGecko, para nada ser baixado nem aberto da internet no celular.

    /usr/bin/python3 -IS tools/catalogo/baixar-logos.py [quantas]      # padrao: as 3000 maiores
    /usr/bin/python3 -IS tools/catalogo/baixar-logos.py --filtrar      # so passa o filtro de imitacao nas que nao estao no git
    /usr/bin/python3 -IS tools/catalogo/baixar-logos.py --regravar-todas   # regrava toda imagem da pasta so com os pixels
    /usr/bin/python3 -IS tools/catalogo/baixar-logos.py --revisar <folha.png>   # as novas perto das maiores, para olhar

So entra a moeda que o catalogo embarcado (catalogo-moedas.json) conhece e que ainda nao tem logo no app. A imagem e a
"small" (64 px) do host de imagens do CoinGecko, so PNG ou JPEG de ate 160 KB, sem redirecionamento para outro host, e e
remontada aqui como PNG de 64 px pelo sips, preso no sandbox de tools/catalogo/sips.sb (sem rede, sem criar processo, sem
ler a pasta do usuario, uma pasta de entrada e outra de saida por imagem). Do PNG do sips so ficam os pixels, regravados
num PNG novo (decisao do dono, 23/11/2026; docs/seguranca.md, "Logo de fora").

Fica de fora a logo que imita outra moeda (revisao dos 3 agentes de 23/11/2026): simbolo ou nome com BTC, ETH, USDT,
USDC, Bitcoin, Ethereum, Tether ou "USD Coin" (tambem com $ por S), simbolo de uma das 100 maiores com outro id, letra de
outra escrita, ou imagem parecida com uma logo que ja esta no app (dHash da parte visivel no circulo a 5 bits, ou a 10 das
maiores). O filtro e heuristico: --revisar monta a folha das que ficaram perto das maiores, e um humano olha antes do commit. O token reconhecido mostra essa logo, e uma imitacao faria um golpe parecer a moeda de verdade.

O iOS usa as imagens de Assets.xcassets/Logos e o Android copia a mesma pasta no build (copiarLogos). Depois de rodar, olhe
as novas antes do commit.
"""
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unicodedata
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../.."))
LOGOS = os.path.join(RAIZ, "App/EscaliburWallet/Resources/Assets.xcassets/Logos")
CATALOGO = os.path.join(RAIZ, "App/EscaliburWallet/Resources/catalogo-moedas.json")
PERFIL = os.path.join(RAIZ, "tools/catalogo/sips.sb")
API = "https://api.coingecko.com/api/v3/"
HOSTS_DA_API = {"api.coingecko.com"}
HOSTS = {"coin-images.coingecko.com", "assets.coingecko.com"}
MAXIMO = 160 * 1024
LADO = 64
# O maior lado aceito nas logos que ja estavam no app (as da lista conferida, das redes e dos provedores: 128 a 250 px).
MAIOR = 512
ID_OK = re.compile(r"[a-z0-9-]{1,100}")
# As pastas de entrada e saida de cada imagem (o sandbox so le a de entrada e so grava a de saida).
TEMPORARIA = "/private/tmp"
# Um User-Agent comum: um nome proprio deixaria o CDN entregar uma imagem preparada so para este Mac.
NAVEGADOR = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
IMITA_SIMBOLO = ("BTC", "ETH", "USDT", "USDC")
IMITA_NOME = ("bitcoin", "ethereum", "tether", "usd coin")
PARECIDA = 5
# Contra as logos das maiores moedas (as que um golpe imita), o limite e maior: uma copia diminuida ou deslocada do Tether
# nao pode passar (rodada 2 dos 3 agentes). Contra as outras da lista, PARECIDA: o limite maior em todas tirava logos
# redondas sem relacao nenhuma.
PARECIDA_PROTEGIDA = 10
PROTEGIDAS_FIXAS = {"tether", "usd-coin", "bitcoin", "ethereum", "solana", "binancecoin", "ripple", "dai", "weth",
                    "wrapped-bitcoin", "the-open-network", "tron", "ethena-usde", "usds", "paypal-usd", "usd1-wlfi"}
# Alem das fixas, as maiores do catalogo: a imagem contra elas usa PARECIDA_PROTEGIDA, e o simbolo delas nao se repete.
PROTEGIDAS_ATE = 50
SIMBOLOS_ATE = 100
# Ate esta distancia de uma protegida, a logo entra na folha de revisao (--revisar) para olhar antes do commit.
REVISAR = 12
PNG = b"\x89PNG\r\n\x1a\n"


class SemRedirecionar(urllib.request.HTTPRedirectHandler):
    """Redirecionamento vira erro: a imagem so vem do host conferido antes do pedido."""

    def redirect_request(self, *argumentos, **nomeados):
        return None


ABRIR = urllib.request.build_opener(SemRedirecionar)


def pedir(url, hosts, limite=None):
    partes = urllib.parse.urlsplit(url)
    if partes.scheme != "https" or partes.hostname not in hosts:
        return None
    pedido = urllib.request.Request(url, headers={"Accept": "*/*", "User-Agent": NAVEGADOR})
    for tentativa in range(5):
        try:
            with ABRIR.open(pedido, timeout=30) as resposta:
                final = urllib.parse.urlsplit(resposta.geturl())
                if resposta.status != 200 or final.scheme != "https" or final.hostname not in hosts:
                    return None
                return resposta.read(limite + 1) if limite else resposta.read(8 * 1024 * 1024)
        except urllib.error.HTTPError as erro:
            if erro.code == 429:
                time.sleep(30 * (tentativa + 1))
                continue
            if erro.code in (301, 302, 303, 307, 308, 404):
                return None
            raise
    raise SystemExit(f"o CoinGecko segue recusando: {url}")


def maiores(quantas):
    moedas = []
    pagina = 1
    while len(moedas) < quantas:
        consulta = urllib.parse.urlencode({"vs_currency": "usd", "order": "market_cap_desc", "per_page": 250, "page": pagina})
        bruto = pedir(API + "coins/markets?" + consulta, HOSTS_DA_API)
        lote = json.loads(bruto) if bruto else None
        if not isinstance(lote, list) or not lote:
            break
        moedas += [moeda for moeda in lote if isinstance(moeda, dict)]
        pagina += 1
        time.sleep(6)
    return moedas[:quantas]


def eh_png_ou_jpeg(dados):
    return dados.startswith(PNG) or dados.startswith(b"\xff\xd8\xff")


def remontar(dados, lado=LADO):
    """O PNG de 64 px feito pelo sips no sandbox, ja enxuto, ou None. Cada imagem com uma pasta de entrada e outra de saida,
    novas e de nome sorteado: o sips so le a primeira e so grava a segunda."""
    pasta_entrada = os.path.realpath(tempfile.mkdtemp(prefix="escalibur-logo-entrada.", dir=TEMPORARIA))
    pasta_saida = os.path.realpath(tempfile.mkdtemp(prefix="escalibur-logo-saida.", dir=TEMPORARIA))
    try:
        entrada = os.path.join(pasta_entrada, "entrada")
        final = os.path.join(pasta_saida, "final.png")
        with open(entrada, "wb") as arquivo:
            arquivo.write(dados)
        comando = ["/usr/bin/sandbox-exec", "-f", PERFIL, "-D", f"ENTRADA={pasta_entrada}", "-D", f"SAIDA={pasta_saida}",
                   "/usr/bin/sips", "-s", "format", "png", *(["-Z", str(lado)] if lado else []), entrada, "--out", final]
        # Sem o terminal: o sips preso nao le o teclado nem escreve sequencias no TTY de quem roda o script.
        if subprocess.run(comando, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30,
                          env={"TMPDIR": pasta_saida + "/"}, start_new_session=True).returncode != 0:
            return None
        if not os.path.isfile(final) or os.path.islink(final):
            return None
        with open(final, "rb") as arquivo:
            pronto = enxugar(arquivo.read(MAXIMO * 16), lado or MAIOR)
        return pronto if pronto and len(pronto) <= MAXIMO * 4 else None
    finally:
        shutil.rmtree(pasta_entrada, ignore_errors=True)
        shutil.rmtree(pasta_saida, ignore_errors=True)


def pedacos_do_png(png, lado=LADO):
    if not png.startswith(PNG):
        return None
    pedacos, i = [], 8
    while i + 12 <= len(png):
        tamanho = struct.unpack(">I", png[i:i + 4])[0]
        tipo, corpo = png[i + 4:i + 8], png[i + 8:i + 8 + tamanho]
        if len(corpo) != tamanho or i + 12 + tamanho > len(png):
            return None
        if zlib.crc32(tipo + corpo) & 0xFFFFFFFF != struct.unpack(">I", png[i + 8 + tamanho:i + 12 + tamanho])[0]:
            return None
        pedacos.append((tipo, corpo))
        i += 12 + tamanho
        if tipo == b"IEND":
            break
    tipos = [tipo for tipo, _ in pedacos]
    if not tipos or tipos[0] != b"IHDR" or tipos[-1] != b"IEND" or b"IDAT" not in tipos or len(pedacos[0][1]) != 13:
        return None
    largura, altura, bits, cor, compressao, filtro, entrelacado = struct.unpack(">IIBBBBB", pedacos[0][1])
    if not (1 <= largura <= lado and 1 <= altura <= lado) or bits != 8 or cor not in (0, 2, 3, 4, 6):
        return None
    if compressao or filtro or entrelacado:
        return None
    return pedacos


def enxugar(png, lado=LADO):
    """O PNG regravado so com os pixels: IHDR de ate 64 px, 8 bits, cinza, RGB, cinza com alfa ou RGBA, sem entrelacamento,
    e um IDAT com o filtro de cada linha escolhido aqui. Paleta, tRNS, EXIF, gama e qualquer outro bloco que o sips escreva ficam de fora,
    e nenhum byte que nao seja pixel passa para o app."""
    lido = pixels(png, lado)
    if not lido:
        return None
    largura, altura, cor, linhas = lido

    def pedaco(tipo, corpo):
        return struct.pack(">I", len(corpo)) + tipo + corpo + struct.pack(">I", zlib.crc32(tipo + corpo) & 0xFFFFFFFF)

    cabecalho = struct.pack(">IIBBBBB", largura, altura, 8, cor, 0, 0, 0)
    canais = {0: 1, 2: 3, 4: 2, 6: 4}[cor]
    imagem = zlib.compress(b"".join(filtrar_linha(linha, anterior, canais)
                                    for linha, anterior in zip(linhas, [bytearray(len(linhas[0]))] + linhas[:-1])), 9)
    return PNG + pedaco(b"IHDR", cabecalho) + pedaco(b"IDAT", imagem) + pedaco(b"IEND", b"")


def filtrar_linha(linha, anterior, canais):
    """A linha com o filtro de PNG (0 a 4) que deixa menos bytes, calculado aqui a partir dos pixels: so comprime melhor."""
    opcoes = []
    for filtro in range(5):
        saida = bytearray([filtro])
        for x, valor in enumerate(linha):
            a = linha[x - canais] if x >= canais else 0
            b = anterior[x]
            c = anterior[x - canais] if x >= canais else 0
            if filtro == 0:
                previsto = 0
            elif filtro == 1:
                previsto = a
            elif filtro == 2:
                previsto = b
            elif filtro == 3:
                previsto = (a + b) // 2
            else:
                estimativa = a + b - c
                pa, pb, pc = abs(estimativa - a), abs(estimativa - b), abs(estimativa - c)
                previsto = a if pa <= pb and pa <= pc else b if pb <= pc else c
            saida.append((valor - previsto) & 255)
        opcoes.append((sum(v if v < 128 else 256 - v for v in saida[1:]), bytes(saida)))
    return min(opcoes)[1]


def pixels(png, lado=LADO):
    """(largura, altura, tipo de cor, linhas sem filtro) de um PNG simples, ou None. O IDAT e aberto com o tamanho exato que
    o cabecalho pede, e cada linha com filtro de 0 a 4."""
    pedacos = pedacos_do_png(png, lado)
    if not pedacos:
        return None
    largura, altura, _, cor, _, _, _ = struct.unpack(">IIBBBBB", pedacos[0][1])
    if cor == 3:
        return None
    canais = {0: 1, 2: 3, 4: 2, 6: 4}[cor]
    linha_bytes = largura * canais
    esperado = altura * (linha_bytes + 1)
    try:
        abrir = zlib.decompressobj()
        bruto = abrir.decompress(b"".join(corpo for tipo, corpo in pedacos if tipo == b"IDAT"), esperado + 1)
    except zlib.error:
        return None
    if len(bruto) != esperado or abrir.unconsumed_tail:
        return None
    anterior = bytearray(linha_bytes)
    linhas = []
    p = 0
    for _ in range(altura):
        filtro = bruto[p]
        if filtro > 4:
            return None
        linha = bytearray(bruto[p + 1:p + 1 + linha_bytes])
        p += 1 + linha_bytes
        for x in range(linha_bytes):
            a = linha[x - canais] if x >= canais else 0
            b = anterior[x]
            c = anterior[x - canais] if x >= canais else 0
            if filtro == 1:
                linha[x] = (linha[x] + a) & 255
            elif filtro == 2:
                linha[x] = (linha[x] + b) & 255
            elif filtro == 3:
                linha[x] = (linha[x] + (a + b) // 2) & 255
            elif filtro == 4:
                estimativa = a + b - c
                pa, pb, pc = abs(estimativa - a), abs(estimativa - b), abs(estimativa - c)
                linha[x] = (linha[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        linhas.append(linha)
        anterior = linha
    return largura, altura, cor, linhas


def cinza(png):
    """Os pixels em cinza (sobre fundo medio onde ha transparencia) e o alfa, ou None."""
    lido = pixels(png, MAIOR)
    if not lido:
        return None
    largura, altura, cor, linhas = lido
    canais = {0: 1, 2: 3, 4: 2, 6: 4}[cor]
    saida = []
    for linha in linhas:
        valores = []
        for x in range(largura):
            px = linha[x * canais:(x + 1) * canais]
            if cor == 0:
                r = g = b = px[0]
                alfa = 255
            elif cor == 4:
                r = g = b = px[0]
                alfa = px[1]
            elif cor == 2:
                r, g, b = px
                alfa = 255
            else:
                r, g, b, alfa = px
            luz = 0.299 * r + 0.587 * g + 0.114 * b
            valores.append(((luz * alfa + 128 * (255 - alfa)) / 255, luz, alfa))
        saida.append(valores)
    return largura, altura, cor, saida


# O fundo escuro do app (Palette.void), sobre o qual a logo aparece: a luz de cada pixel e a que o usuario ve.
LUZ_DO_FUNDO = 11


def visivel(png):
    """A logo como o app mostra: so o circulo inscrito, cada pixel composto sobre o fundo escuro do app, e o que tem a
    mesma luz do canto vira fundo (com ou sem ligacao com ele, e qualquer que seja o alfa: um anel invisivel nao conta).
    Recortada na caixa do que sobra, sem linhas e colunas esparsas. Devolve (largura, altura, luz, fundo), ou None."""
    lido = cinza(png)
    if not lido:
        return None
    largura, altura, _, pixels_ = lido
    raio = min(largura, altura) / 2
    luz = [[(p[1] * p[2] + LUZ_DO_FUNDO * (255 - p[2])) / 255 for p in linha] for linha in pixels_]
    canto = luz[0][0]
    fora = {(y, x) for y in range(altura) for x in range(largura)
            if (x + 0.5 - largura / 2) ** 2 + (y + 0.5 - altura / 2) ** 2 > raio ** 2 or abs(luz[y][x] - canto) <= 12}
    valor = [[canto if (y, x) in fora else luz[y][x] for x in range(largura)] for y in range(altura)]
    minimo = max(2, min(largura, altura) // 20)
    linhas = [y for y in range(altura) if sum(1 for x in range(largura) if (y, x) not in fora) >= minimo]
    colunas = [x for x in range(largura) if sum(1 for y in range(altura) if (y, x) not in fora) >= minimo]
    if not linhas or not colunas:
        return largura, altura, valor, [[(y, x) in fora for x in range(largura)] for y in range(altura)]
    y0, y1, x0, x1 = min(linhas), max(linhas) + 1, min(colunas), max(colunas) + 1
    return (x1 - x0, y1 - y0, [linha[x0:x1] for linha in valor[y0:y1]],
            [[(y, x) in fora for x in range(x0, x1)] for y in range(y0, y1)])


def hash_de(largo, alto, valor):
    bits = 0
    for linha in range(8):
        a0, a1 = linha * alto // 8, max(linha * alto // 8 + 1, (linha + 1) * alto // 8)
        valores = []
        for coluna in range(9):
            b0, b1 = coluna * largo // 9, max(coluna * largo // 9 + 1, (coluna + 1) * largo // 9)
            area = [valor[y][x] for y in range(a0, min(a1, alto)) for x in range(b0, min(b1, largo))]
            valores.append(sum(area) / max(1, len(area)))
        for coluna in range(8):
            bits = (bits << 1) | (1 if valores[coluna] > valores[coluna + 1] else 0)
    return bits


def dhash(png):
    """dHash 9x8 da parte visivel (`visivel`): 64 bits, um por par de vizinhos na horizontal (media de area)."""
    lido = visivel(png)
    return hash_de(*lido[:3]) if lido else None


def variacoes(png):
    """Os hashes da logo e de imitacoes faceis dela: espelhada, e com a luz 16 acima ou abaixo onde nao e fundo. Contra as
    protegidas vale o menor (rodada 4 dos 3 agentes). Giro, negativo e redesenho ficam para o olho (--revisar)."""
    lido = visivel(png)
    if not lido:
        return []
    largo, alto, valor, fundo = lido
    saida = [hash_de(largo, alto, valor), hash_de(largo, alto, [linha[::-1] for linha in valor])]
    for passo in (16, -16):
        mudada = [[v if fundo[y][x] else min(255, max(0, v + passo)) for x, v in enumerate(linha)] for y, linha in enumerate(valor)]
        saida.append(hash_de(largo, alto, mudada))
    return saida


# Letras que parecem as de um simbolo protegido: "U$DT", "U5DC", "B1TC".
PARECE = str.maketrans({"$": "S", "5": "S", "0": "O", "1": "I", "|": "I", "3": "E"})


def letra_aceita_no_nome(c):
    """No nome: ASCII, letra com acento (decomposicao canonica, NFD) que vira ASCII sem ele, ou CJK, kana e hangul. Largura
    cheia, letra matematica, sobrescrito, cirilico, grego, lisu, cherokee, versalete, caractere invisivel e ₮₿Ξ ficam
    de fora."""
    if c.isascii():
        return c.isprintable()
    if unicodedata.category(c) in ("Cf", "Cc", "Co", "Cs", "Cn") or unicodedata.normalize("NFKC", c) != c:
        return False
    if c.isalpha() and unicodedata.normalize("NFD", c)[0].isascii():
        return True
    return unicodedata.name(c, "").startswith(("CJK", "HANGUL", "HIRAGANA", "KATAKANA")) and c not in "\u20ae\u20bf\u039e"


def dobrado(texto):
    """Sem acento, sem caixa, so letras e numeros: "Téther", "Teth-er" e "Tet.her" viram "tether"."""
    sem_acento = "".join(c for c in unicodedata.normalize("NFKD", texto) if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]", "", sem_acento.lower())


def imita_pelo_texto(simbolo, nome, ident="", simbolos_protegidos=None):
    """O simbolo so com ASCII imprimivel e o nome com letras aceitas; sem as palavras das moedas grandes (dobradas, e
    tambem com $ por S, 5 por S, 0 por O); e sem repetir o simbolo de uma das maiores."""
    simbolo = simbolo or ""
    nome = nome or ""
    if not all(c.isascii() and c.isprintable() for c in simbolo) or not all(letra_aceita_no_nome(c) for c in nome):
        return True
    for texto in (simbolo.upper(), simbolo.upper().translate(PARECE)):
        letras = re.sub(r"[^A-Z0-9]", "", texto)
        if any(protegido in letras for protegido in IMITA_SIMBOLO):
            return True
        if simbolos_protegidos and letras in simbolos_protegidos and ident not in simbolos_protegidos[letras]:
            return True
    textos = {dobrado(nome), dobrado(simbolo), dobrado(nome.upper().translate(PARECE)), dobrado(simbolo.upper().translate(PARECE))}
    return any(dobrado(palavra) in texto for palavra in IMITA_NOME for texto in textos)


def maiores_do_catalogo(catalogo, ate):
    """Os ids do catalogo ate a posicao `ate`."""
    return {ident for ident, item in catalogo.items() if isinstance(item[3], int) and item[3] <= ate}


def simbolos_de(catalogo, ids):
    """Simbolo normalizado -> os ids protegidos que o usam."""
    saida = {}
    for ident in ids:
        if ident in catalogo:
            letras = re.sub(r"[^A-Z0-9]", "", str(catalogo[ident][1]).upper())
            if letras:
                saida.setdefault(letras, set()).add(ident)
    return saida


def protecao(catalogo):
    """(ids cuja imagem usa o limite maior, simbolos que nao se repetem)."""
    imagem = set(PROTEGIDAS_FIXAS) | maiores_do_catalogo(catalogo, PROTEGIDAS_ATE)
    return imagem, simbolos_de(catalogo, set(PROTEGIDAS_FIXAS) | maiores_do_catalogo(catalogo, SIMBOLOS_ATE))


def png_da_pasta(pasta):
    """O PNG de 64 px de uma logo que ja esta no app (algumas sao JPEG ou maiores): pelo mesmo sips no sandbox."""
    arquivos = [nome for nome in os.listdir(pasta) if nome.lower().endswith((".png", ".jpg", ".jpeg"))]
    if not arquivos:
        return None
    with open(os.path.join(pasta, arquivos[0]), "rb") as arquivo:
        dados = arquivo.read(MAXIMO * 8)
    return enxugar(dados, MAIOR) or remontar(dados, None)


def hashes_do_app(ignorar=()):
    hashes = {}
    for nome in sorted(os.listdir(LOGOS)):
        if not nome.startswith("logo-") or not nome.endswith(".imageset") or nome[5:-9] in ignorar:
            continue
        png = png_da_pasta(os.path.join(LOGOS, nome))
        marca = dhash(png) if png else None
        if marca is not None:
            hashes[nome[5:-9]] = marca
    return hashes


def parecida(marca, hashes, protegidas_=frozenset(), outras=()):
    """O id da logo do app parecida com esta: a PARECIDA bits ou menos do hash da logo, ou a PARECIDA_PROTEGIDA de uma
    protegida pelo menor entre a logo e as variacoes dela (`variacoes`)."""
    for ident, ref in hashes.items():
        if bin(ref ^ marca).count("1") <= PARECIDA:
            return ident
        if ident in protegidas_ and min(bin(ref ^ m).count("1") for m in (marca, *outras)) <= PARECIDA_PROTEGIDA:
            return ident
    return None


def gravar(ident, png):
    pasta = os.path.join(LOGOS, f"logo-{ident}.imageset")
    os.makedirs(pasta, exist_ok=True)
    with open(os.path.join(pasta, f"logo-{ident}.png"), "wb") as arquivo:
        arquivo.write(png)
    with open(os.path.join(pasta, "Contents.json"), "w") as arquivo:
        json.dump({"images": [{"filename": f"logo-{ident}.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, arquivo)


def filtrar():
    """Passa o filtro de imitacao nas logos que ainda nao estao no git, comparando com as que estao."""
    no_git = subprocess.run(["/usr/bin/git", "-C", RAIZ, "ls-files", "--", LOGOS], capture_output=True, text=True, check=True).stdout
    antigas = {match for match in re.findall(r"/logo-([a-z0-9-]+)\.imageset/", no_git)}
    catalogo = {item[0]: item for item in json.load(open(CATALOGO))}
    novas = [nome[5:-9] for nome in os.listdir(LOGOS) if nome.startswith("logo-") and nome.endswith(".imageset") and nome[5:-9] not in antigas]
    referencia = hashes_do_app(ignorar=set(novas))
    guardadas, simbolos = protecao(catalogo)
    tiradas = []
    for ident in sorted(novas):
        item = catalogo.get(ident)
        png = png_da_pasta(os.path.join(LOGOS, f"logo-{ident}.imageset"))
        marca = dhash(png) if png else None
        motivo = None
        if not item or imita_pelo_texto(item[1], item[2], ident, simbolos):
            motivo = "nome ou simbolo"
        elif marca is None:
            motivo = "nao abriu"
        else:
            igual = parecida(marca, referencia, guardadas, variacoes(png))
            motivo = f"parecida com {igual}" if igual else None
        if motivo:
            shutil.rmtree(os.path.join(LOGOS, f"logo-{ident}.imageset"))
            tiradas.append(f"{ident} ({motivo})")
    print(f"tiradas {len(tiradas)} de {len(novas)}:")
    for linha in tiradas:
        print("  " + linha)


def regravar_todas():
    """Regrava toda imagem da pasta (logo-, rede-, provedor-) so com os pixels, em PNG: sai o EXIF, o perfil de cor, o
    texto e qualquer outro bloco que viesse de fora antes deste script (rodada 2 dos 3 agentes, 23/11/2026)."""
    feitas, ruins = 0, []
    for nome in sorted(os.listdir(LOGOS)):
        if not nome.endswith(".imageset"):
            continue
        pasta = os.path.join(LOGOS, nome)
        base = nome[:-len(".imageset")]
        arquivos = [arquivo for arquivo in os.listdir(pasta) if arquivo.lower().endswith((".png", ".jpg", ".jpeg"))]
        if len(arquivos) != 1 or os.path.islink(os.path.join(pasta, arquivos[0])):
            ruins.append(nome)
            continue
        with open(os.path.join(pasta, arquivos[0]), "rb") as arquivo:
            dados = arquivo.read(MAXIMO * 16)
        png = enxugar(dados, MAIOR) or remontar(dados, None)
        if not png:
            ruins.append(nome)
            continue
        if arquivos[0] != base + ".png":
            os.remove(os.path.join(pasta, arquivos[0]))
        with open(os.path.join(pasta, base + ".png"), "wb") as arquivo:
            arquivo.write(png)
        with open(os.path.join(pasta, "Contents.json"), "w") as arquivo:
            json.dump({"images": [{"filename": base + ".png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, arquivo)
        feitas += 1
    print(f"regravadas {feitas}, com problema {len(ruins)}: {' '.join(ruins)}")


def rgb_64(png):
    """A imagem em 64x64 RGB sobre o cinza escuro do app (vizinho mais proximo), para a folha de revisao."""
    lido = pixels(png, MAIOR)
    if not lido:
        return None
    largura, altura, cor, linhas = lido
    canais = {0: 1, 2: 3, 4: 2, 6: 4}[cor]
    saida = []
    for y in range(64):
        linha = linhas[min(altura - 1, y * altura // 64)]
        fila = bytearray()
        for x in range(64):
            px = linha[min(largura - 1, x * largura // 64) * canais:][:canais]
            r, g, b = (px[0], px[0], px[0]) if cor in (0, 4) else (px[0], px[1], px[2])
            alfa = px[1] if cor == 4 else px[3] if cor == 6 else 255
            fila += bytes(int((v * alfa + 11 * (255 - alfa)) / 255) for v in (r, g, b))
        saida.append(fila)
    return saida


def revisar(destino):
    """Folha de revisao: cada logo nova a ate REVISAR bits de uma protegida, ao lado dela. Olhar antes do commit."""
    catalogo = {item[0]: item for item in json.load(open(CATALOGO))}
    guardadas, _ = protecao(catalogo)
    no_git = subprocess.run(["/usr/bin/git", "-C", RAIZ, "ls-files", "--", LOGOS], capture_output=True, text=True, check=True).stdout
    antigas = set(re.findall(r"/logo-([a-z0-9-]+)\.imageset/", no_git))
    referencia = {ident: marca for ident, marca in hashes_do_app().items() if ident in guardadas and ident in antigas}
    pares = []
    for nome in sorted(os.listdir(LOGOS)):
        ident = nome[5:-9]
        if not nome.startswith("logo-") or not nome.endswith(".imageset") or ident in antigas:
            continue
        png = png_da_pasta(os.path.join(LOGOS, nome))
        marca = dhash(png) if png else None
        if marca is None or not referencia:
            continue
        perto, distancia = min(((outra, bin(m ^ marca).count("1")) for outra, m in referencia.items()), key=lambda par: par[1])
        if distancia <= REVISAR:
            pares.append((distancia, ident, perto))
    pares.sort()
    por_linha, lado = 4, 64
    linhas_da_folha = []
    for inicio in range(0, len(pares), por_linha):
        faixa = [bytearray(b"\x1e" * 3 * (por_linha * (2 * lado + 24))) for _ in range(lado + 8)]
        for coluna, (_, ident, perto) in enumerate(pares[inicio:inicio + por_linha]):
            for deslocamento, quem in ((0, ident), (lado + 4, perto)):
                imagem = rgb_64(png_da_pasta(os.path.join(LOGOS, f"logo-{quem}.imageset")) or b"")
                if not imagem:
                    continue
                x0 = (coluna * (2 * lado + 24) + deslocamento) * 3
                for y in range(lado):
                    faixa[y + 4][x0:x0 + lado * 3] = imagem[y]
        linhas_da_folha += faixa
    if linhas_da_folha:
        largura = len(linhas_da_folha[0]) // 3

        def pedaco(tipo, corpo):
            return struct.pack(">I", len(corpo)) + tipo + corpo + struct.pack(">I", zlib.crc32(tipo + corpo) & 0xFFFFFFFF)

        with open(destino, "wb") as arquivo:
            arquivo.write(PNG + pedaco(b"IHDR", struct.pack(">IIBBBBB", largura, len(linhas_da_folha), 8, 2, 0, 0, 0))
                          + pedaco(b"IDAT", zlib.compress(b"".join(b"\x00" + bytes(linha) for linha in linhas_da_folha), 9))
                          + pedaco(b"IEND", b""))
    for distancia, ident, perto in pares:
        print(f"{distancia:2d}  {ident}  ~  {perto}")
    print(f"{len(pares)} para revisar" + (f", folha em {destino}" if pares else ""))


def main():
    if sys.argv[1:] == ["--filtrar"]:
        filtrar()
        return
    if sys.argv[1:2] == ["--revisar"] and len(sys.argv) == 3:
        revisar(sys.argv[2])
        return
    if sys.argv[1:] == ["--regravar-todas"]:
        regravar_todas()
        return
    quantas = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
    catalogo = {item[0]: item for item in json.load(open(CATALOGO))}
    tem = {nome[len("logo-"):-len(".imageset")] for nome in os.listdir(LOGOS) if nome.endswith(".imageset")}
    referencia = hashes_do_app()
    guardadas, simbolos = protecao(catalogo)
    novas = puladas = imitacoes = 0
    for moeda in maiores(quantas):
        ident = moeda.get("id") if isinstance(moeda.get("id"), str) else ""
        if ident in tem or ident not in catalogo or not ID_OK.fullmatch(ident):
            continue
        item = catalogo[ident]
        if imita_pelo_texto(item[1], item[2], ident, simbolos):
            imitacoes += 1
            continue
        endereco = (moeda.get("image") if isinstance(moeda.get("image"), str) else "").replace("/large/", "/small/")
        dados = pedir(endereco, HOSTS, MAXIMO)
        if not dados or len(dados) > MAXIMO or not eh_png_ou_jpeg(dados):
            puladas += 1
            continue
        png = remontar(dados)
        marca = dhash(png) if png else None
        if marca is None:
            puladas += 1
            continue
        if parecida(marca, referencia, guardadas, variacoes(png)):
            imitacoes += 1
            continue
        gravar(ident, png)
        referencia[ident] = marca
        tem.add(ident)
        novas += 1
        time.sleep(0.2)
    print(f"logos novas: {novas}, imitacoes de fora: {imitacoes}, puladas (formato, host ou tamanho): {puladas}")


if __name__ == "__main__":
    main()
