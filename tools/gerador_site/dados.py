"""Tudo o que o site mostra sobre o app sai daqui, lido do repositorio no build.

Redes de Chain.swift, tokens de TokenRegistry.swift, versao de project.yml, novidades do
historico da main, hosts do hosts.lock, dependencias dos *.lock, verificacoes do
tools/verificar.sh. Nada e digitado a mao: se o codigo muda, o site muda junto. Quando
a leitura nao reconhece um trecho, o gerador para com erro em vez de publicar uma lista
pela metade.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent.parent
REPO = "https://github.com/Escalibur-Wallet/escalibur-wallet"
CHAIN = RAIZ / "Kit/Sources/EscaliburChains/Chain.swift"
TOKENS = RAIZ / "Kit/Sources/EscaliburChains/TokenRegistry.swift"
LOGOS = RAIZ / "App/EscaliburWallet/Resources/Assets.xcassets/Logos"
COIN_LOGO = RAIZ / "App/EscaliburWallet/Design/CoinLogo.swift"
PROJETO = RAIZ / "project.yml"
HOSTS = RAIZ / "hosts.lock"
PRIVACIDADE = RAIZ / "App/EscaliburWallet/Resources/Legal/privacidade.md"
VERIFICAR = RAIZ / "tools/verificar.sh"


def falha(mensagem):
    sys.exit(f"gerar-site: {mensagem}")


# MARK: Versao


def versao():
    texto = PROJETO.read_text(encoding="utf-8")
    marketing = re.search(r'MARKETING_VERSION:\s*"?([0-9][0-9.]*)"?', texto)
    build = re.search(r'CURRENT_PROJECT_VERSION:\s*"?([0-9]+)"?', texto)
    if not marketing or not build:
        falha("MARKETING_VERSION ou CURRENT_PROJECT_VERSION fora do project.yml")
    return {"marketing": marketing.group(1), "build": build.group(1)}


# MARK: Redes

FAMILIAS = {
    "utxo": "UTXO", "evm": "EVM", "solana": "Solana", "xrpl": "XRP Ledger", "stellar": "Stellar",
    "tron": "Tron", "ton": "TON", "sui": "Sui", "cardano": "Cardano", "polkadot": "Polkadot",
    "near": "NEAR", "aptos": "Aptos",
}
CURVAS = {
    "utxo": "secp256k1", "evm": "secp256k1", "xrpl": "secp256k1", "tron": "secp256k1",
    "solana": "Ed25519", "stellar": "Ed25519", "ton": "Ed25519", "sui": "Ed25519", "cardano": "Ed25519",
    "polkadot": "Ed25519", "near": "Ed25519", "aptos": "Ed25519",
}
TAGS = {"none": None, "xrplTag": "tag de destino", "stellarMemo": "memo", "tonComment": "comentário"}


def _campo(bloco, nome, padrao=r'"([^"]*)"'):
    achado = re.search(rf"\b{nome}:\s*{padrao}", bloco)
    return achado.group(1) if achado else None


def redes():
    """As redes na ordem de `Chain.all`, a mesma da interface."""
    texto = CHAIN.read_text(encoding="utf-8")
    porvar = {}
    for var, bloco in re.findall(r"static let (\w+) = Chain\((.*?)\n    \)", texto, re.S):
        evm_id = _campo(bloco, "evmChainID", r"(nil|\d+)")
        porvar[var] = {
            "id": _campo(bloco, "id"), "nome": _campo(bloco, "name"), "familia": _campo(bloco, "family", r"\.(\w+)"),
            "simbolo": _campo(bloco, "nativeSymbol"), "nome_nativo": _campo(bloco, "nativeName"),
            "casas": int(_campo(bloco, "nativeDecimals", r"(\d+)") or 0), "gecko": _campo(bloco, "coingeckoID"),
            "chain_id": None if evm_id in (None, "nil") else int(evm_id),
            "explorador": _campo(bloco, "explorerName"), "explorador_endereco": _campo(bloco, "explorerAddress"),
            "segundos": int(_campo(bloco, "typicalConfirmationSeconds", r"(\d+)") or 0),
            "tag": TAGS.get(_campo(bloco, "destinationTag", r"\.(\w+)")),
            "slip44": int(_campo(bloco, "coinType", r"(\d+)") or 0),
        }
    padrao_evm = re.compile(
        r'static let (\w+) = evm\("([^"]+)", "([^"]+)", chainID: (\d+), symbol: "([^"]+)", nativeName: "([^"]+)", '
        r'gecko: "([^"]+)",\s*explorer: "([^"]+)", explorerName: "([^"]+)", seconds: (\d+)\)'
    )
    for var, ident, nome, chain_id, simbolo, nativo, gecko, explorador, nome_explorador, segundos in padrao_evm.findall(texto):
        porvar[var] = {
            "id": ident, "nome": nome, "familia": "evm", "simbolo": simbolo, "nome_nativo": nativo, "casas": 18,
            "gecko": gecko, "chain_id": int(chain_id), "explorador": nome_explorador,
            "explorador_endereco": f"{explorador}/address/{{address}}", "segundos": int(segundos), "tag": None, "slip44": 60,
        }
    lista = re.search(r"static let all: \[Chain\] = \[(.*?)\]", texto, re.S)
    if not lista:
        falha("Chain.all nao encontrado em Chain.swift")
    ordem = re.findall(r"\.(\w+)", lista.group(1))
    faltando = [v for v in ordem if v not in porvar]
    if faltando:
        falha(f"redes de Chain.all sem definicao reconhecida: {faltando}")
    saida = [porvar[v] for v in ordem]
    for rede in saida:
        if not all(rede[k] for k in ("id", "nome", "familia", "simbolo", "gecko")):
            falha(f"rede incompleta em Chain.swift: {rede}")
    return saida


# MARK: Tokens


def _sem_comentarios(texto):
    """Tira `//` ate o fim da linha, fora de string."""
    saida, em_string, i = [], False, 0
    while i < len(texto):
        c = texto[i]
        if c == '"' and (i == 0 or texto[i - 1] != "\\"):
            em_string = not em_string
        if not em_string and texto.startswith("//", i):
            fim = texto.find("\n", i)
            i = len(texto) if fim < 0 else fim
            continue
        saida.append(c)
        i += 1
    return "".join(saida)


def _entradas_do_array(corpo):
    """Os elementos de nivel zero de um array Swift, separados por virgula."""
    entradas, atual, nivel, em_string = [], [], 0, False
    for i, c in enumerate(corpo):
        if c == '"' and (i == 0 or corpo[i - 1] != "\\"):
            em_string = not em_string
        if not em_string:
            if c in "([":
                nivel += 1
            elif c in ")]":
                nivel -= 1
            elif c == "," and nivel == 0:
                entradas.append("".join(atual))
                atual = []
                continue
        atual.append(c)
    entradas.append("".join(atual))
    return [" ".join(e.split()) for e in entradas if e.strip()]


_ESTAVEL = r'(?:, stable: (true|false))?'
_PADROES_TOKEN = [
    ("erc20", re.compile(rf'^erc20\("(\w+)", "([^"]+)", "([^"]+)", "([^"]+)", (\d+), "([^"]+)"{_ESTAVEL}\)$')),
    ("spl", re.compile(rf'^spl\("([^"]+)", "([^"]+)", "([^"]+)", (\d+), "([^"]+)"{_ESTAVEL}\)$')),
    ("issued", re.compile(rf'^issued\("(\w+)", code: "([^"]+)", issuer: "([^"]+)", "([^"]+)", "([^"]+)", (\d+), "([^"]+)"{_ESTAVEL}\)$')),
    ("asset", re.compile(
        r'^Asset\(chainID: "(\w+)", kind: \.(?:token\(contract: "([^"]+)"\)|issued\(code: "([^"]+)", issuer: "([^"]+)"\)), '
        r'symbol: "([^"]+)", name: "([^"]+)", decimals: (\d+), coingeckoID: "([^"]+)", isStablecoin: (true|false)\)$'
    )),
]


def _bloco_tokens():
    texto = TOKENS.read_text(encoding="utf-8")
    inicio = texto.find("public static let tokens: [Asset] = [")
    if inicio < 0:
        falha("TokenRegistry.tokens nao encontrado")
    texto = _sem_comentarios(texto[inicio:])
    abre = texto.index("[Asset] = [") + len("[Asset] = [")
    nivel, em_string = 1, False
    for i in range(abre, len(texto)):
        c = texto[i]
        if c == '"' and texto[i - 1] != "\\":
            em_string = not em_string
        if em_string:
            continue
        if c in "([":
            nivel += 1
        elif c in ")]":
            nivel -= 1
            if nivel == 0:
                return texto[abre:i]
    falha("fim de TokenRegistry.tokens nao encontrado")


def tokens():
    """Os tokens da lista conferida, na ordem do arquivo."""
    saida = []
    for entrada in _entradas_do_array(_bloco_tokens()):
        for tipo, padrao in _PADROES_TOKEN:
            achado = padrao.match(entrada)
            if not achado:
                continue
            g = achado.groups()
            if tipo == "erc20":
                item = dict(rede=g[0], contrato=g[1], simbolo=g[2], nome=g[3], casas=int(g[4]), gecko=g[5], estavel=g[6] == "true")
            elif tipo == "spl":
                item = dict(rede="solana", contrato=g[0], simbolo=g[1], nome=g[2], casas=int(g[3]), gecko=g[4], estavel=g[5] == "true")
            elif tipo == "issued":
                item = dict(rede=g[0], codigo=g[1], emissor=g[2], simbolo=g[3], nome=g[4], casas=int(g[5]), gecko=g[6], estavel=g[7] == "true")
            else:
                item = dict(rede=g[0], simbolo=g[4], nome=g[5], casas=int(g[6]), gecko=g[7], estavel=g[8] == "true")
                if g[1]:
                    item["contrato"] = g[1]
                else:
                    item["codigo"], item["emissor"] = g[2], g[3]
            saida.append(item)
            break
        else:
            falha(f"token que o gerador nao sabe ler em TokenRegistry.swift: {entrada[:160]}")
    return saida


# MARK: Logos


def conjuntos_de_logo():
    """Os mesmos conjuntos do `CoinLogo` do app: logo sem circulo proprio vai num disco,
    logo escuro ganha disco claro."""
    texto = COIN_LOGO.read_text(encoding="utf-8") if COIN_LOGO.exists() else ""

    def conjunto(nome):
        achado = re.search(rf"static let {nome}: Set<String> = \[([^\]]*)\]", texto)
        return set(re.findall(r'"([^"]+)"', achado.group(1))) if achado else set()

    return conjunto("bareLogos"), conjunto("darkLogos")


def arquivo_de_logo(nome):
    """O arquivo de imagem do conjunto `nome` no catalogo do app, ou None."""
    pasta = LOGOS / f"{nome}.imageset"
    if not pasta.is_dir():
        return None
    try:
        conteudo = json.loads((pasta / "Contents.json").read_text(encoding="utf-8"))
        for imagem in conteudo.get("images", []):
            if imagem.get("filename") and (pasta / imagem["filename"]).is_file():
                return pasta / imagem["filename"]
    except (OSError, ValueError):
        return None
    return None


# MARK: Git


def _git(*args):
    try:
        return subprocess.run(["git", "-C", str(RAIZ), *args], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None


def commit_atual():
    sha = os.environ.get("GITHUB_SHA") or (_git("rev-parse", "HEAD") or "").strip()
    data = (_git("show", "-s", "--format=%cI", sha) or "").strip() if sha else ""
    return {"sha": sha or None, "data": data or None}


# O historico do repositorio comecou de novo num commit so em 20/10/2026 e de novo em
# 30/10/2026 (pedidos do dono). As entregas de antes ficam neste arquivo, congeladas como
# estavam, sem link para o GitHub.
NOVIDADES_ANTERIORES = RAIZ / "tools" / "gerador_site" / "novidades-anteriores.json"
RAIZ_DO_HISTORICO = "Escalibur Wallet 1.0.1: the published code"


def commits(limite=40):
    """O historico da main pela primeira linha de pais (cada mescla conta como uma entrega),
    e depois as entregas de antes do recomeco do historico. Em ingles (pedido do dono,
    23/10/2026): cada entrega passa pela tabela de traducao (novidades-en.json, pelo hash
    curto); a que nao esta na tabela e parece escrita em portugues fica de fora, com aviso."""
    lista = [c for c in _commits_do_git(limite + 10) if c["assunto"] != RAIZ_DO_HISTORICO]
    if NOVIDADES_ANTERIORES.is_file():
        anteriores = json.loads(NOVIDADES_ANTERIORES.read_text(encoding="utf-8"))
        lista += [dict(c, corpo=[tuple(b) for b in c["corpo"]], anterior=True) for c in anteriores]
    saida = []
    for c in lista:
        if len(saida) >= limite:
            break
        # Os commits do proprio site saem da lista depois (gerar-site.py, novidades_do_app).
        traduzida = c if re.match(r"^Site\b", c["assunto"]) else em_ingles(c)
        if traduzida:
            saida.append(traduzida)
    return saida


NOVIDADES_EN = RAIZ / "tools" / "gerador_site" / "novidades-en.json"
_TRADUCOES = None
# Palavras que so aparecem em texto em portugues (os commits sao escritos sem acento).
_PORTUGUES = re.compile(r"\b(nao|para|com|uma|sem|quando|pelo|pela|dos|das|nos|nas|agora|tambem|ate|entre|mais|so|ja|tela|carteira|redes)\b")


def em_ingles(c):
    global _TRADUCOES
    if _TRADUCOES is None:
        _TRADUCOES = json.loads(NOVIDADES_EN.read_text(encoding="utf-8")) if NOVIDADES_EN.is_file() else {}
    traducao = _TRADUCOES.get((c.get("sha") or "")[:7])
    if traducao:
        return dict(c, assunto=traducao["assunto"], corpo=[tuple(b) for b in traducao["corpo"]], en=True)
    texto = " ".join([c["assunto"]] + [b[1] for b in c["corpo"]]).lower()
    if len(_PORTUGUES.findall(texto)) >= 2:
        print(f"gerar-site: a novidade {c.get('sha', '')[:7]} esta em portugues e sem traducao em novidades-en.json; fica de fora",
              file=sys.stderr)
        return None
    return dict(c, en=True)


def _commits_do_git(limite):
    saida = _git("log", "--first-parent", f"-n{limite}", "--format=%H%x1f%cI%x1f%s%x1f%b%x1e", "HEAD")
    if not saida:
        return []
    lista = []
    for registro in saida.split("\x1e"):
        partes = registro.strip("\n").split("\x1f")
        if len(partes) < 4:
            continue
        sha, data, assunto, corpo = partes
        if assunto.startswith("Merge "):
            continue
        lista.append({"sha": sha.strip(), "data": data.strip(), "assunto": assunto.strip(), "corpo": _corpo_do_commit(corpo)})
    return lista


def _corpo_do_commit(corpo):
    """O corpo em blocos: ('titulo', texto), ('item', texto) ou ('p', texto). Sem as
    linhas de coautoria."""
    blocos, atual = [], None
    for bruta in corpo.split("\n"):
        linha = bruta.rstrip()
        if re.match(r"^(Co-Authored-By|Signed-off-by|Co-authored-by):", linha.strip()):
            continue
        if not linha.strip():
            atual = None
            continue
        if linha.lstrip().startswith("- "):
            atual = ["item", linha.lstrip()[2:].strip()]
            blocos.append(atual)
        elif atual is not None and bruta.startswith(" "):
            atual[1] += " " + linha.strip()
        elif atual is not None and atual[0] == "p":
            atual[1] += " " + linha.strip()
        else:
            atual = ["p", linha.strip()]
            blocos.append(atual)
    # Paragrafo curto seguido de itens e titulo de grupo ("Troca", "Envio").
    for i, bloco in enumerate(blocos):
        if bloco[0] == "p" and len(bloco[1]) <= 40 and not bloco[1].endswith(".") and i + 1 < len(blocos) and blocos[i + 1][0] == "item":
            bloco[0] = "titulo"
    return [tuple(b) for b in blocos]


# MARK: Hosts e dependencias


def hosts():
    return [l.strip().replace("https://", "") for l in HOSTS.read_text(encoding="utf-8").splitlines() if l.strip()]


def grupos_de_hosts():
    """Os hosts agrupados pelo uso, como a Politica de privacidade descreve cada um."""
    todos = hosts()
    grupos, vistos = [], set()
    for linha in PRIVACIDADE.read_text(encoding="utf-8").splitlines():
        achado = re.match(r"^- \*\*(.+?):?\*\*:?\s*(.*)$", linha.strip())
        if not achado:
            continue
        do_grupo = [h for h in re.findall(r"`([^`]+)`", achado.group(2)) if h in todos and h not in vistos]
        if do_grupo:
            grupos.append((achado.group(1).rstrip(":"), do_grupo))
            vistos.update(do_grupo)
    resto = [h for h in todos if h not in vistos]
    if resto:
        grupos.append(("Outros", resto))
    return grupos


DESCRICAO_TRAVA = {
    "secp256k1.lock": "libsecp256k1 do bitcoin-core, a curva das assinaturas de Bitcoin, Ethereum, XRP Ledger e Tron. Compilada do fonte.",
    "argon2.lock": "Argon2 de referência, a derivação de chave do PIN e do envelope. Compilado do fonte.",
    "wordlists.lock": "As listas oficiais de palavras do BIP-39, uma por idioma.",
    "forca.lock": "As listas de frequência do medidor de força da senha do envelope (zxcvbn-ts, MIT).",
    "recuperacao.lock": "O decifrador de referência do envelope e a especificação do formato, usados nos testes.",
    "modelos.lock": "As texturas da moeda 3D do tour, recortadas de “Bit Coin”, de marcio3d (CC BY 4.0).",
}


def travas():
    """Os arquivos *.lock da raiz (menos o hosts.lock): cada arquivo travado por SHA-256."""
    saida = []
    for caminho in sorted(RAIZ.glob("*.lock")):
        if caminho.name == "hosts.lock":
            continue
        texto = caminho.read_text(encoding="utf-8")
        item = {"arquivo": caminho.name, "descricao": DESCRICAO_TRAVA.get(caminho.name, ""), "origem": None, "versao": None,
                "extra": [], "arquivos": []}
        try:
            dados = json.loads(texto)
        except ValueError:
            dados = None
        if isinstance(dados, dict):
            item["origem"] = dados.get("origem")
            item["versao"] = dados.get("versao")
            for chave in ("tag_objeto", "tarball_sha256"):
                if dados.get(chave):
                    item["extra"].append((chave, dados[chave]))
            arquivos = dados.get("arquivos") if isinstance(dados.get("arquivos"), dict) else {
                k: v for k, v in dados.items() if isinstance(v, str) and re.fullmatch(r"[0-9a-f]{64}", v)}
            item["arquivos"] = sorted(arquivos.items())
        else:
            for linha in texto.splitlines():
                achado = re.match(r"^([0-9a-f]{64})\s+\*?(.+)$", linha.strip())
                if achado:
                    item["arquivos"].append((achado.group(2), achado.group(1)))
        saida.append(item)
    return saida


# MARK: Verificacoes do verificar.sh


def verificacoes():
    """As verificacoes do tools/verificar.sh, por secao: o que cada `ok` garante e a
    linha onde mora. As de `--testes` vem marcadas: so rodam com o Kit compilado."""
    linhas = VERIFICAR.read_text(encoding="utf-8").splitlines()
    n_hosts = len(hosts())
    travas_por_nome = {t["arquivo"]: len(t["arquivos"]) for t in travas()}
    secoes, atual, so_testes, em_funcao, pular = [], None, False, False, False
    for numero, linha in enumerate(linhas, 1):
        # Funcao de varias linhas (a de uma linha so, como `ok() { ...; }`, nao conta).
        if re.match(r"^\s*\w+\(\)\s*\{\s*$", linha):
            em_funcao = True
        if em_funcao and re.match(r"^\}", linha):
            em_funcao = False
            continue
        # O ramo de --atualizar-hosts reescreve as listas: nao e verificacao.
        if '"--atualizar-hosts" ]; then' in linha:
            pular = True
            continue
        if pular:
            pular = not re.match(r"^\s*(elif|else|fi)\b", linha)
            if pular:
                continue
        if re.match(r'^if \[ "\$\{1:-\}" = "--testes" \]', linha):
            so_testes = True
        achado = re.match(r'^\s*secao "([^"]+)"', linha)
        if achado:
            atual = {"nome": achado.group(1), "itens": []}
            secoes.append(atual)
            continue
        chamada = re.match(r"^conferir_lock (\S+) \S+ (\S+)", linha)
        if chamada and atual is not None:
            lock, nome = chamada.groups()
            atual["itens"].append((numero, f"{travas_por_nome.get(lock, 0)} arquivos de {nome} conferem com {lock}", so_testes))
            continue
        if em_funcao or atual is None:
            continue
        for mensagem in re.findall(r'\bok "((?:\$\([^)]*\)|[^"\\]|\\.)*)"', linha):
            atual["itens"].append((numero, _limpa_mensagem(mensagem, n_hosts), so_testes))
    return [s for s in secoes if s["itens"]]


def _limpa_mensagem(mensagem, n_hosts):
    # Sem o numero de servidores no site (pedido do dono, 23/10/2026): "os hosts", sem contar.
    mensagem = mensagem.replace("$(wc -l < hosts.lock | tr -d ' ') hosts", "os hosts")
    mensagem = mensagem.replace("$(wc -l < hosts.lock | tr -d ' ')", "")
    mensagem = re.sub(r"\s*\((?:[^()]|\([^)]*\))*\$[^)]*\)\)?", "", mensagem)
    mensagem = re.sub(r"\$\([^)]*\)|\$\{?\w+\}?", "", mensagem)
    mensagem = re.sub(r"\(\s*\)", "", mensagem)
    return " ".join(mensagem.split()).strip(" ,:")


# MARK: CI


def estado_ci():
    """O estado do workflow `verificar` para o commit publicado, que o workflow do site
    busca na API do GitHub e entrega num JSON (`SITE_CI`). Fora do CI: None."""
    caminho = os.environ.get("SITE_CI")
    if not caminho:
        return None
    try:
        dados = json.loads(Path(caminho).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    corridas = dados.get("workflow_runs") or []
    if not corridas:
        return {"estado": "sem", "url": None, "sha": None, "quando": None}
    corrida = corridas[0]
    if corrida.get("status") != "completed":
        estado = "rodando"
    else:
        estado = {"success": "passou", "failure": "falhou", "cancelled": "cancelado"}.get(corrida.get("conclusion"), "outro")
    url = corrida.get("html_url") or ""
    if not url.startswith(REPO + "/"):
        url = None
    return {"estado": estado, "url": url, "sha": corrida.get("head_sha"), "quando": corrida.get("updated_at")}


# MARK: Troca e ponte (a demonstracao da pagina inicial)

PONTE = RAIZ / "Kit/Sources/EscaliburChains/Bridge/BridgeAllowlist.swift"
MESH = RAIZ / "Kit/Sources/EscaliburChains/Bridge/USDT0Mesh.swift"

# As redes com troca nesta versao (TradeEngines.chains): as EVM menos Avalanche, X Layer e
# Celo, mais Solana, XRP Ledger e Stellar, como em README.md e docs/redes/motores.md. No XRP
# Ledger a troca e so XRP e RLUSD, pelo livro da propria rede.
TROCA_EVM_FORA = {"avalanche", "xlayer", "celo"}
TROCA_OUTRAS = {"solana", "xrpl", "stellar"}
TROCA_SO = {"xrpl": {"ripple-usd"}}


def redes_com_troca(lista_redes):
    return [r for r in lista_redes
            if (r["familia"] == "evm" and r["id"] not in TROCA_EVM_FORA) or r["id"] in TROCA_OUTRAS]


def _blocos_da_ponte(texto):
    """Cada `public static let x = BridgeChain(...)`, com o parentese fechado contado."""
    saida = {}
    for achado in re.finditer(r"public static let (\w+) = BridgeChain\(", texto):
        inicio, nivel, i = achado.end(), 1, achado.end()
        while nivel and i < len(texto):
            nivel += {"(": 1, ")": -1}.get(texto[i], 0)
            i += 1
        saida[achado.group(1)] = texto[inicio:i - 1]
    return saida


def ponte():
    """O que a ponte move e entre quais redes, lido de BridgeAllowlist.swift e da regra de
    `BridgeAsset.available(from:to:)`: USDC pelo CCTP quando as duas redes tem, senao pelo
    Across; ETH, USDT e WBTC pelo Across; USDT para a Tron pela Legacy Mesh da Tether, de onde
    ela tem o UsdtOFT. A Tron so recebe."""
    texto = PONTE.read_text(encoding="utf-8")
    blocos = _blocos_da_ponte(texto)
    lista = re.search(r"public static let chains: \[BridgeChain\] = \[([^\]]*)\]", texto)
    destinos = re.search(r"public static let destinations: \[BridgeChain\] = chains \+ \[([^\]]*)\]", texto)
    if not blocos or not lista or not destinos:
        falha("BridgeAllowlist.swift mudou de forma: atualize ponte() em tools/gerador_site/dados.py")
    nomes = [n.strip() for n in lista.group(1).split(",") if n.strip()]
    extras = [n.strip() for n in destinos.group(1).split(",") if n.strip()]

    def endereco(bloco, campo):
        achado = re.search(rf"\b{campo}: (nil|address\(\"([0-9a-fA-F]+)\"\)|\.zero|EVMAddress\()", bloco)
        if not achado or achado.group(1) == "nil":
            return None
        return (achado.group(2) or achado.group(1)).lower()

    redes_ponte = {}
    for nome in nomes + extras:
        bloco = blocos.get(nome)
        if bloco is None:
            falha(f"rede da ponte sem definicao: {nome}")
        rede = re.search(r"chain: \.(\w+)", bloco)
        if not rede:
            falha(f"rede da ponte sem chain: {nome}")
        redes_ponte[nome] = {
            "rede": rede.group(1),
            "cctp": "cctpDomain:" in bloco or bool(re.search(r"cctp: \.init|cctp: CCTP\(", bloco)),
            "across": bool(re.search(r"across: \.init", bloco)),
            "usdt": endereco(bloco, "usdt"),
            "eth_nativo": bool(re.search(r"nativeETH: true", bloco)),
            "eth_token": endereco(bloco, "ethToken"),
            "across_usdc": not re.search(r"acrossUSDC: false", bloco),
            "wbtc": endereco(bloco, "wbtc"),
            "tron": nome == "tron",
        }
    # A Legacy Mesh: as redes de origem (chainId) e o USDT que o UsdtOFT puxa em cada uma.
    mesh = {}
    for chain_id, usdt in re.findall(r"(\d+): Source\(chainID: \d+,.*?usdt: address\(\"([0-9a-fA-F]+)\"\)", MESH.read_text(encoding="utf-8"), re.S):
        mesh[int(chain_id)] = usdt.lower()
    if not mesh:
        falha("USDT0Mesh.swift mudou de forma: atualize ponte() em tools/gerador_site/dados.py")
    por_id = {r["id"]: r for r in redes()}

    def cadeia(nome):
        return por_id.get(redes_ponte[nome]["rede"])

    def malha(origem, destino):
        o, d = redes_ponte[origem], redes_ponte[destino]
        rede = cadeia(origem)
        fonte = mesh.get(rede["chain_id"]) if rede else None
        return d["tron"] and fonte is not None and o["usdt"] == fonte

    rotas = {"usdc": [], "eth": [], "usdt": [], "wbtc": []}
    for origem in nomes:
        for destino in nomes + extras:
            if origem == destino:
                continue
            o, d = redes_ponte[origem], redes_ponte[destino]
            if o["cctp"] and d["cctp"] and not d["tron"]:
                rotas["usdc"].append((origem, destino, "cctp"))
            elif o["across"] and d["across"] and o["across_usdc"] and d["across_usdc"]:
                rotas["usdc"].append((origem, destino, "across"))
            if (o["eth_nativo"] or o["eth_token"]) and (d["eth_nativo"] or d["eth_token"]) and o["across"] and d["across"]:
                rotas["eth"].append((origem, destino, "across"))
            if malha(origem, destino):
                rotas["usdt"].append((origem, destino, "usdt0"))
            elif o["usdt"] and d["usdt"] and o["across"] and d["across"]:
                rotas["usdt"].append((origem, destino, "across"))
            if o["wbtc"] and d["wbtc"] and o["across"] and d["across"]:
                rotas["wbtc"].append((origem, destino, "across"))
    ordem = [redes_ponte[n]["rede"] for n in nomes + extras]
    return {"redes": ordem, "rotas": {ativo: [(redes_ponte[a]["rede"], redes_ponte[b]["rede"], via) for a, b, via in lista_rotas]
                                       for ativo, lista_rotas in rotas.items()}}


# MARK: Ids do CoinPaprika (a segunda fonte de precos do site)

MERCADO_APP = RAIZ / "Kit/Sources/EscaliburNetwork/Market.swift"
PAPRIKA_GERADO = RAIZ / "Kit/Sources/EscaliburNetwork/PaprikaGeckoIDs.swift"


def ids_paprika(ids_gecko):
    """O id do CoinPaprika de cada moeda, pela mesma tabela do app: a feita a mao em
    Market.swift (`paprikaIDs`, do CoinGecko para o CoinPaprika) e a gerada em
    PaprikaGeckoIDs.swift (do CoinPaprika para o CoinGecko). Moeda sem par fica de fora."""
    mapa = {}
    texto = MERCADO_APP.read_text(encoding="utf-8") if MERCADO_APP.is_file() else ""
    bloco = re.search(r"static let paprikaIDs: \[String: String\] = \[(.*?)\]", texto, re.S)
    if bloco:
        mapa.update(dict(re.findall(r'"([a-z0-9-]+)":\s*"([a-z0-9-]+)"', bloco.group(1))))
    if PAPRIKA_GERADO.is_file():
        for paprika, gecko in re.findall(r'"([a-z0-9-]+)":\s*"([a-z0-9-]+)"', PAPRIKA_GERADO.read_text(encoding="utf-8")):
            mapa.setdefault(gecko, paprika)
    mapa.update(PAPRIKA_DO_SITE)
    return {g: mapa[g] for g in ids_gecko if g in mapa}


# Ids que a tabela do app nao tem, ou que o CoinPaprika trocou, conferidos na lista de tickers
# do CoinPaprika em 23/10/2026 (simbolo, nome e preco iguais aos do CoinGecko). O TON virou
# `toncoin-the-open-network`: o `ton-toncoin` da tabela do app ja nao existe la.
PAPRIKA_DO_SITE = {
    "the-open-network": "toncoin-the-open-network", "ripple-usd": "rlusd-ripple-usd", "euro-coin": "euroc-euro-coin",
    "weth": "weth-weth", "coinbase-wrapped-btc": "cbbtc-coinbase-wrapped-btc", "ethena-usde": "usde-ethena-usde",
    "raydium": "ray-raydium", "pyth-network": "pyth-pyth-network", "render-token": "rndr-render-token",
    "aerodrome-finance": "aero-aerodrome-finance",
}
