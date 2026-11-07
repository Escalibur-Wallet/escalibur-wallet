#!/usr/bin/env python3
"""Google Play Developer API do Escalibur Wallet (app.escalibur.wallet), com a conta de servico
play-publisher. A chave fica em ~/.escalibur/android/play-api.json, fora do repositorio.

  python3 tools/android/play.py conferir      # testa o acesso (abre e descarta uma edicao)
  python3 tools/android/play.py ficha         # textos, contato e imagens de tools/android/ficha-play.json
  python3 tools/android/play.py subir <aab>   # o AAB no teste interno, como rascunho
  python3 tools/android/play.py producao <aab> <versao> [fracao]   # o AAB em producao, para revisao, com as notas da ficha;
                                                                # com fracao (ex.: 0.05), lancamento gradual para essa parte
  python3 tools/android/play.py ampliar <versionCode> <fracao|completo>   # sobe a fracao do lancamento gradual, ou completa
  python3 tools/android/play.py pausar <versionCode>                       # pausa o lancamento gradual
  python3 tools/android/play.py completo <versionCode>                     # sai 0 so com o lancamento em 100% na producao

Cada mudanca na Play passa por uma "edicao": abrir, mudar, e so o commit publica. Sem commit,
nada muda na loja. Enquanto o app nunca foi publicado, a Play so aceita versao em rascunho: quem
lanca e o dono, na Play Console. Depois de publicado (28/10/2026), a versao vai direto para producao
com `producao`: o commit manda para a revisao do Google, e a aprovacao publica para todos.
"""
import hashlib, io, json, os, sys, time, urllib.error, urllib.parse, urllib.request

import jwt
from PIL import Image

PACOTE = "app.escalibur.wallet"
CHAVE = os.path.expanduser("~/.escalibur/android/play-api.json")
# O SHA-256 de cada AAB que este Mac enviou, por versionCode: o versoes.swift liberar-android so libera o build cujo pacote
# na Play e o que saiu daqui (revisao dos 3 agentes de 07/11/2026). Um versionCode enviado antes por outro nao entra aqui:
# o envio do dono falha como repetido, e isso e incidente.
ENVIADOS = os.path.expanduser("~/.escalibur/android/enviados.json")
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACOTE}"
ENVIO = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACOTE}"
RAIZ = os.path.normpath(os.path.join(os.path.dirname(__file__), "../.."))


def token():
    conta = json.load(open(CHAVE))
    agora = int(time.time())
    afirmacao = jwt.encode({"iss": conta["client_email"], "scope": "https://www.googleapis.com/auth/androidpublisher",
                            "aud": conta["token_uri"], "iat": agora, "exp": agora + 3600},
                           conta["private_key"], algorithm="RS256", headers={"kid": conta["private_key_id"]})
    corpo = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": afirmacao}).encode()
    return json.load(urllib.request.urlopen(conta["token_uri"], corpo, timeout=30))["access_token"]


def pedir(metodo, caminho, corpo=None, t=None, base=API, tipo="application/json"):
    dados = corpo if isinstance(corpo, bytes) else json.dumps(corpo).encode() if corpo is not None else None
    req = urllib.request.Request(base + caminho, data=dados, method=metodo,
                                 headers={"Authorization": "Bearer " + t, "Content-Type": tipo})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            texto = r.read()
            return json.loads(texto) if texto else {}
    except urllib.error.HTTPError as e:
        erro = json.loads(e.read() or b"{}").get("error", {})
        sys.exit(f"Play respondeu {e.code}: {erro.get('message', '')}")


def conferir():
    t = token()
    edicao = pedir("POST", "/edits", {}, t)["id"]
    detalhes = pedir("GET", f"/edits/{edicao}/details", t=t)
    faixas = pedir("GET", f"/edits/{edicao}/tracks", t=t).get("tracks", [])
    pedir("DELETE", f"/edits/{edicao}", t=t)
    print("acesso ok | idioma padrao:", detalhes.get("defaultLanguage"), "| e-mail:", detalhes.get("contactEmail") or "-")
    for f in faixas:
        print("faixa", f["track"] + ":", [(r.get("status"), r.get("versionCodes")) for r in f.get("releases", [])] or "vazia")


def png(caminho, alfa=False):
    """A Play pede o icone em PNG de 32 bits (com alfa), o destaque sem alfa e nenhuma tela mais
    comprida que o dobro da largura: a mais alta (as da App Store) perde o excesso em cima e embaixo."""
    imagem = Image.open(os.path.join(RAIZ, caminho)).convert("RGBA" if alfa else "RGB")
    largura, altura = imagem.size
    if altura > 2 * largura:
        topo = (altura - 2 * largura) // 2
        imagem = imagem.crop((0, topo, largura, topo + 2 * largura))
    saida = io.BytesIO()
    imagem.save(saida, "PNG")
    return saida.getvalue()


def ficha():
    dados = json.load(open(os.path.join(RAIZ, "tools/android/ficha-play.json")))
    t = token()
    edicao = pedir("POST", "/edits", {}, t)["id"]
    for idioma, f in dados["fichas"].items():
        pedir("PUT", f"/edits/{edicao}/listings/{idioma}",
              {"language": idioma, "title": f["titulo"], "shortDescription": f["curta"], "fullDescription": f["completa"]}, t)
        # Sem destaque nem telas, o idioma mostra os do idioma padrao.
        envios = [("icon", [dados["icone"]], True),
                  ("featureGraphic", [f["destaque"]] if f["destaque"] else [], False),
                  ("phoneScreenshots", f["telas"], False)]
        for tipo, arquivos, alfa in envios:
            pedir("DELETE", f"/edits/{edicao}/listings/{idioma}/{tipo}", t=t)
            for a in arquivos:
                pedir("POST", f"/edits/{edicao}/listings/{idioma}/{tipo}?uploadType=media", png(a, alfa), t, base=ENVIO, tipo="image/png")
        print(f"{idioma}: textos, icone, {'destaque' if f['destaque'] else 'sem destaque'} e {len(f['telas'])} telas")
    pedir("PATCH", f"/edits/{edicao}/details",
          {"defaultLanguage": dados["idiomaPadrao"], "contactEmail": dados["contato"]["email"], "contactWebsite": dados["contato"]["site"]}, t)
    for l in pedir("GET", f"/edits/{edicao}/listings", t=t).get("listings", []):
        if l["language"] not in dados["fichas"]:
            pedir("DELETE", f"/edits/{edicao}/listings/{l['language']}", t=t)
            print(f"{l['language']}: ficha que sobrou apagada")
    pedir("POST", f"/edits/{edicao}:commit", {}, t)
    print("ficha publicada na Play | idioma padrao:", dados["idiomaPadrao"])


def enviar_aab(edicao, aab, t):
    """Envia o AAB e confere que a Play guardou o mesmo arquivo (o SHA-256 dela e o do arquivo). Devolve o versionCode e o digesto."""
    dados = open(aab, "rb").read()
    digesto = hashlib.sha256(dados).hexdigest()
    pacote = pedir("POST", f"/edits/{edicao}/bundles?uploadType=media", dados, t, base=ENVIO, tipo="application/octet-stream")
    if pacote.get("sha256") != digesto:
        pedir("DELETE", f"/edits/{edicao}", t=t)
        sys.exit(f"a Play guardou outro arquivo (SHA-256 {pacote.get('sha256')}, o AAB e {digesto}): nada foi publicado")
    return pacote["versionCode"], digesto


def anotar_envio(versao, digesto):
    """Antes do commit (o digesto ja foi conferido com a Play): um envio que nao chegou ao commit anotado nao faz mal, porque
    o versoes.swift confere a Play; um commit sem anotacao viraria incidente falso. Troca o arquivo de uma vez, 0600."""
    try:
        enviados = json.load(open(ENVIADOS)) if os.path.exists(ENVIADOS) else {}
    except ValueError:
        sys.exit(f"{ENVIADOS} ilegivel: confira o arquivo antes de enviar (nada foi publicado)")
    enviados[str(versao)] = digesto
    temporario = ENVIADOS + ".novo"
    with os.fdopen(os.open(temporario, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as arquivo:
        json.dump(enviados, arquivo, indent=1, sort_keys=True)
        arquivo.flush()
        os.fsync(arquivo.fileno())
    os.replace(temporario, ENVIADOS)


def subir():
    aab = sys.argv[2] if len(sys.argv) > 2 else sys.exit("falta o caminho do AAB")
    notas = json.load(open(os.path.join(RAIZ, "tools/android/ficha-play.json")))["notasDaVersao"]
    t = token()
    edicao = pedir("POST", "/edits", {}, t)["id"]
    versao, digesto = enviar_aab(edicao, aab, t)
    pedir("PUT", f"/edits/{edicao}/tracks/internal", {"track": "internal", "releases": [{
        "name": "1.0.0", "versionCodes": [str(versao)], "status": "draft",
        "releaseNotes": [{"language": l, "text": texto} for l, texto in notas.items()]}]}, t)
    anotar_envio(versao, digesto)
    pedir("POST", f"/edits/{edicao}:commit", {}, t)
    print(f"AAB {versao} no teste interno, como rascunho")


def producao():
    aab = sys.argv[2] if len(sys.argv) > 2 else sys.exit("falta o caminho do AAB")
    nome = sys.argv[3] if len(sys.argv) > 3 else sys.exit("falta a versao (ex.: 1.0.1)")
    notas = json.load(open(os.path.join(RAIZ, "tools/android/ficha-play.json")))["notasDaVersao"]
    t = token()
    edicao = pedir("POST", "/edits", {}, t)["id"]
    versao, digesto = enviar_aab(edicao, aab, t)
    fracao = float(sys.argv[4]) if len(sys.argv) > 4 else None
    if fracao is not None and not 0 < fracao < 1:
        sys.exit("a fracao do lancamento gradual vai de 0 a 1, sem os dois (ex.: 0.05)")
    lancamento = {"name": nome, "versionCodes": [str(versao)],
                  "releaseNotes": [{"language": l, "text": texto} for l, texto in notas.items()]}
    # Gradual: so essa parte dos usuarios recebe, e da para pausar se aparecer problema (07/11/2026).
    lancamento.update({"status": "inProgress", "userFraction": fracao} if fracao is not None else {"status": "completed"})
    pedir("PUT", f"/edits/{edicao}/tracks/production", {"track": "production", "releases": [lancamento]}, t)
    anotar_envio(versao, digesto)
    pedir("POST", f"/edits/{edicao}:commit", {}, t)
    parte = f", lancamento gradual para {fracao:.0%}" if fracao is not None else ""
    print(f"AAB {versao} ({nome}) em producao{parte}, enviado para revisao")


def mudar_lancamento(versao, mudanca):
    t = token()
    edicao = pedir("POST", "/edits", {}, t)["id"]
    faixa = pedir("GET", f"/edits/{edicao}/tracks/production", None, t)
    lancamentos = faixa.get("releases", [])
    alvo = next((r for r in lancamentos if str(versao) in r.get("versionCodes", [])), None)
    if alvo is None:
        sys.exit(f"o {versao} nao esta na faixa de producao")
    mudanca(alvo)
    pedir("PUT", f"/edits/{edicao}/tracks/production", {"track": "production", "releases": lancamentos}, t)
    pedir("POST", f"/edits/{edicao}:commit", {}, t)
    print(f"{versao}: {alvo.get('status')}" + (f" para {alvo['userFraction']:.0%}" if alvo.get("userFraction") else ""))


def ampliar():
    versao = sys.argv[2] if len(sys.argv) > 2 else sys.exit("falta o versionCode")
    valor = sys.argv[3] if len(sys.argv) > 3 else sys.exit("falta a fracao ou completo")
    def mudanca(alvo):
        if valor == "completo":
            alvo["status"] = "completed"
            alvo.pop("userFraction", None)
        else:
            fracao = float(valor)
            if not 0 < fracao < 1:
                sys.exit("a fracao vai de 0 a 1, sem os dois")
            alvo["status"], alvo["userFraction"] = "inProgress", fracao
    mudar_lancamento(versao, mudanca)


def pausar():
    versao = sys.argv[2] if len(sys.argv) > 2 else sys.exit("falta o versionCode")
    mudar_lancamento(versao, lambda alvo: alvo.__setitem__("status", "halted"))


def completo():
    """So le: o versoes.swift liberar-android libera o build so com o lancamento dele em 100% na producao."""
    versao = sys.argv[2] if len(sys.argv) > 2 else sys.exit("falta o versionCode")
    t = token()
    edicao = pedir("POST", "/edits", {}, t)["id"]
    faixa = pedir("GET", f"/edits/{edicao}/tracks/production", None, t)
    pedir("DELETE", f"/edits/{edicao}", t=t)
    alvo = next((r for r in faixa.get("releases", []) if str(versao) in r.get("versionCodes", [])), None)
    if alvo is None:
        sys.exit(f"o {versao} nao esta na faixa de producao")
    print(f"{versao}: {alvo.get('status')}" + (f" para {alvo['userFraction']:.0%}" if alvo.get("userFraction") else ""))
    sys.exit(0 if alvo.get("status") == "completed" and not alvo.get("userFraction") and not alvo.get("countryTargeting") else 1)


if __name__ == "__main__":
    {"conferir": conferir, "ficha": ficha, "subir": subir, "producao": producao, "ampliar": ampliar, "pausar": pausar, "completo": completo}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
