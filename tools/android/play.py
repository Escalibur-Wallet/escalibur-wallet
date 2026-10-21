#!/usr/bin/env python3
"""Google Play Developer API do Escalibur Wallet (app.escalibur.wallet), com a conta de servico
play-publisher. A chave fica em ~/.escalibur/android/play-api.json, fora do repositorio.

  python3 tools/android/play.py conferir      # testa o acesso (abre e descarta uma edicao)
  python3 tools/android/play.py ficha         # textos, contato e imagens de tools/android/ficha-play.json
  python3 tools/android/play.py subir <aab>   # o AAB no teste interno, como rascunho

Cada mudanca na Play passa por uma "edicao": abrir, mudar, e so o commit publica. Sem commit,
nada muda na loja. Enquanto o app nunca foi publicado, a Play so aceita versao em rascunho: quem
lanca e o dono, na Play Console.
"""
import glob, io, json, os, sys, time, urllib.error, urllib.parse, urllib.request

import jwt
from PIL import Image

PACOTE = "app.escalibur.wallet"
CHAVE = os.path.expanduser("~/.escalibur/android/play-api.json")
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACOTE}"
ENVIO = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACOTE}"
RAIZ = os.path.normpath(os.path.join(os.path.dirname(__file__), "../.."))
IMAGENS = os.path.join(RAIZ, "build/loja-android")


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
    """A Play pede o icone em PNG de 32 bits (com alfa) e o destaque sem alfa."""
    imagem = Image.open(caminho).convert("RGBA" if alfa else "RGB")
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
        pasta = f["imagens"]
        envios = [("icon", [os.path.join(IMAGENS, "grafico/icone-512.png")], True),
                  ("featureGraphic", [os.path.join(IMAGENS, f"grafico/destaque-{pasta}.png")], False),
                  ("phoneScreenshots", sorted(glob.glob(os.path.join(IMAGENS, pasta, "*.png"))), False)]
        for tipo, arquivos, alfa in envios:
            pedir("DELETE", f"/edits/{edicao}/listings/{idioma}/{tipo}", t=t)
            for a in arquivos:
                pedir("POST", f"/edits/{edicao}/listings/{idioma}/{tipo}?uploadType=media", png(a, alfa), t, base=ENVIO, tipo="image/png")
        print(f"{idioma}: textos, icone, destaque e {len(envios[2][1])} telas")
    pedir("PATCH", f"/edits/{edicao}/details",
          {"defaultLanguage": dados["idiomaPadrao"], "contactEmail": dados["contato"]["email"], "contactWebsite": dados["contato"]["site"]}, t)
    for l in pedir("GET", f"/edits/{edicao}/listings", t=t).get("listings", []):
        if l["language"] not in dados["fichas"]:
            pedir("DELETE", f"/edits/{edicao}/listings/{l['language']}", t=t)
            print(f"{l['language']}: ficha que sobrou apagada")
    pedir("POST", f"/edits/{edicao}:commit", {}, t)
    print("ficha publicada na Play | idioma padrao:", dados["idiomaPadrao"])


def subir():
    aab = sys.argv[2] if len(sys.argv) > 2 else sys.exit("falta o caminho do AAB")
    notas = json.load(open(os.path.join(RAIZ, "tools/android/ficha-play.json")))["notasDaVersao"]
    t = token()
    edicao = pedir("POST", "/edits", {}, t)["id"]
    versao = pedir("POST", f"/edits/{edicao}/bundles?uploadType=media", open(aab, "rb").read(), t,
                   base=ENVIO, tipo="application/octet-stream")["versionCode"]
    pedir("PUT", f"/edits/{edicao}/tracks/internal", {"track": "internal", "releases": [{
        "name": "1.0.0", "versionCodes": [str(versao)], "status": "draft",
        "releaseNotes": [{"language": l, "text": texto} for l, texto in notas.items()]}]}, t)
    pedir("POST", f"/edits/{edicao}:commit", {}, t)
    print(f"AAB {versao} no teste interno, como rascunho")


if __name__ == "__main__":
    {"conferir": conferir, "ficha": ficha, "subir": subir}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
