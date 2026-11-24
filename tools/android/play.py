#!/usr/bin/python3 -IS
"""Google Play Developer API do Escalibur Wallet (app.escalibur.wallet), com a conta de servico
play-publisher. A chave fica no Keychain deste Mac (o JSON em base64, servico escalibur-android-play-api, conta
escalibur-android, como a senha de upload); o arquivo ~/.escalibur/android/play-api.json so vale enquanto ela nao foi
para la (os comandos mais abaixo).

O script roda isolado e so com a biblioteca padrao: nenhum pacote da pasta do usuario entra no processo que le a chave e
assina o token (auditoria 8, 14/11/2026). Rode pelo caminho inteiro, /usr/bin/python3 -IS: o python3 do PATH pode ser
outro (um falso na primeira pasta do PATH rodaria no lugar, com o mesmo pedido do Keychain), e sem o -S o site-packages do
sistema entra. Sem o -I o script recusa, mas a recusa e um lembrete, e nao protecao: um .pth da pasta do usuario roda
antes dela e a engana (rodadas 2 e 3 da auditoria 8). A `ficha` tambem converte as imagens so com ela (zlib), antes de ler a
chave: era o Pillow da pasta do usuario, num processo a parte (rodada 1 da auditoria 8).

A chave e a senha de upload ficam no Keychain sem nenhum app de confianca (-T ""): cada leitura, inclusive a do
/usr/bin/security que este script chama, pede a confirmacao do dono na tela. Sem o -T, o proprio `security` fica na lista
e qualquer processo deste usuario le a chave calado. No pedido, toque em "Permitir", nunca em "Permitir sempre": esse poe o
security na lista e volta, calado, ao estado de antes. O -U nao troca a lista de um item que ja existe: apague o antigo e
grave de novo. A chave entra pela entrada do `security -i`, e nao pelos argumentos, que qualquer processo deste usuario le
com `ps` enquanto o comando roda (o printf e do proprio zsh). O `security -i` le linhas de ate 4095 caracteres e parte o
resto em outro comando: o tamanho e conferido antes, e acima disso nada e gravado (rodada 3 da auditoria 8):

  /usr/bin/security delete-generic-password -a escalibur-android -s escalibur-android-play-api
  b=$(/usr/bin/base64 -i ~/.escalibur/android/play-api.json); { [ ${#b} -lt 3900 ] && printf 'add-generic-password -T "" -a escalibur-android -s escalibur-android-play-api -w %s\n' "$b" | /usr/bin/security -i; } || echo "grande demais ou recusado: nada gravado" >&2; unset b
  /usr/bin/python3 -IS tools/android/play.py conferir   # tem de pedir o ok na tela e sair sem erro; se nao pedir, a lista nao ficou vazia
  /bin/rm ~/.escalibur/android/play-api.json

A chave passou semanas num arquivo, e o rm nao a tira dos snapshots do APFS nem do Time Machine: depois de passar para o
Keychain, crie uma chave nova na conta de servico (Google Cloud, IAM, Contas de servico, play-publisher, Chaves), grave a
nova do mesmo jeito, confira, apague o arquivo dela e exclua a antiga no Google Cloud.

  /usr/bin/python3 -IS tools/android/play.py conferir      # testa o acesso (abre e descarta uma edicao)
  /usr/bin/python3 -IS tools/android/play.py ficha         # textos, contato e imagens de tools/android/ficha-play.json
  /usr/bin/python3 -IS tools/android/play.py subir <aab>   # o AAB no teste interno, como rascunho
  /usr/bin/python3 -IS tools/android/play.py producao <aab> <versao> [fracao]   # o AAB em producao, para revisao, com as notas da ficha;
                                                                   # com fracao (ex.: 0.05), lancamento gradual para essa parte
  /usr/bin/python3 -IS tools/android/play.py ampliar <versionCode> <fracao|completo>   # sobe a fracao do lancamento gradual, ou completa
  /usr/bin/python3 -IS tools/android/play.py pausar <versionCode>                       # pausa o lancamento gradual
  /usr/bin/python3 -IS tools/android/play.py completo <versionCode>                     # sai 0 so com o lancamento em 100% na producao

Cada mudanca na Play passa por uma "edicao": abrir, mudar, e so o commit publica. Sem commit,
nada muda na loja. Enquanto o app nunca foi publicado, a Play so aceita versao em rascunho: quem
lanca e o dono, na Play Console. Depois de publicado (28/10/2026), a versao vai direto para producao
com `producao`: o commit manda para a revisao do Google, e a aprovacao publica para todos.
"""
import base64, hashlib, json, os, subprocess, sys, time, urllib.error, urllib.parse, urllib.request, zlib

# Isolado sempre: sem a pasta do usuario, sem PYTHONPATH, sem o diretorio do script na frente. Sem o -I, o processo ja rodou
# os .pth da pasta do usuario antes desta linha, e reabrir nao desfaz o que eles fizeram: recusa (rodada 2 da auditoria 8).
# E um lembrete, e nao protecao: o .pth que rodou antes pode trocar o sys.flags (rodada 3).
if __name__ == "__main__" and not (sys.flags.isolated and sys.flags.no_site):
    sys.exit("rode com /usr/bin/python3 -IS tools/android/play.py ...")

PACOTE = "app.escalibur.wallet"
CHAVE = os.path.expanduser("~/.escalibur/android/play-api.json")
# O SHA-256 de cada AAB que este Mac enviou, por versionCode: o versoes.swift liberar-android so libera o build cujo pacote
# na Play e o que saiu daqui (revisao de seguranca de 07/11/2026). Um versionCode enviado antes por outro nao entra aqui:
# o envio do dono falha como repetido, e isso e incidente.
ENVIADOS = os.path.expanduser("~/.escalibur/android/enviados.json")
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACOTE}"
ENVIO = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACOTE}"
RAIZ = os.path.normpath(os.path.join(os.path.dirname(__file__), "../.."))


# A chave veio do arquivo antigo, e nao do Keychain: o `conferir` sai com erro, para a migracao que falhou calada nao seguir
# para o rm do arquivo (rodada 4 da auditoria 8).
DO_ARQUIVO = False


def conta_de_servico():
    """O JSON da conta de servico: do Keychain; do arquivo antigo, com aviso, ate o dono passar a chave para la."""
    global DO_ARQUIVO
    lido = subprocess.run(["/usr/bin/security", "find-generic-password", "-a", "escalibur-android", "-s", "escalibur-android-play-api", "-w"],
                          capture_output=True, text=True)
    if lido.returncode == 0 and lido.stdout.strip():
        return json.loads(base64.b64decode(lido.stdout.strip()))
    if os.path.exists(CHAVE):
        print("aviso: a chave da Play ainda esta em arquivo; passe-a para o Keychain (ver o topo deste script) e apague o arquivo",
              file=sys.stderr)
        DO_ARQUIVO = True
        return json.load(open(CHAVE))
    sys.exit("sem a chave da conta de servico da Play no Keychain")


def b64url(dados):
    return base64.urlsafe_b64encode(dados).rstrip(b"=").decode()


def der(dados, inicio):
    """Um elemento DER: o tipo, o valor e onde comeca o proximo."""
    tipo, tamanho, i = dados[inicio], dados[inicio + 1], inicio + 2
    if tamanho & 0x80:
        quantos = tamanho & 0x7F
        tamanho, i = int.from_bytes(dados[i:i + quantos], "big"), i + quantos
    return tipo, dados[i:i + tamanho], i + tamanho


def sequencia(dados):
    itens, i = [], 0
    while i < len(dados):
        tipo, valor, i = der(dados, i)
        itens.append((tipo, valor))
    return itens


def rs256(mensagem, pem):
    """RSASSA-PKCS1-v1_5 com SHA-256 (o RS256 do JWT), so com a biblioteca padrao: a chave PKCS#8 da conta de servico, e a
    assinatura conferida com a publica antes de sair. Era o PyJWT da pasta do usuario, sem versao nem digesto."""
    corpo = base64.b64decode("".join(linha for linha in pem.strip().splitlines() if not linha.startswith("-----")))
    _, info, _ = der(corpo, 0)
    rsa = sequencia(der(sequencia(info)[2][1], 0)[1])
    n, e, d = (int.from_bytes(rsa[i][1], "big") for i in (1, 2, 3))
    k = (n.bit_length() + 7) // 8
    resumo = bytes.fromhex("3031300d060960864801650304020105000420") + hashlib.sha256(mensagem).digest()
    bloco = int.from_bytes(b"\x00\x01" + b"\xff" * (k - len(resumo) - 3) + b"\x00" + resumo, "big")
    assinatura = pow(bloco, d, n)
    if pow(assinatura, e, n) != bloco:
        sys.exit("a assinatura do token nao confere com a chave publica")
    return assinatura.to_bytes(k, "big")


def token():
    conta = conta_de_servico()
    agora = int(time.time())
    cabecalho = {"alg": "RS256", "typ": "JWT", "kid": conta["private_key_id"]}
    afirmacao = {"iss": conta["client_email"], "scope": "https://www.googleapis.com/auth/androidpublisher",
                 "aud": conta["token_uri"], "iat": agora, "exp": agora + 3600}
    entrada = b64url(json.dumps(cabecalho, separators=(",", ":")).encode()) + "." + b64url(json.dumps(afirmacao, separators=(",", ":")).encode())
    jwt = entrada + "." + b64url(rs256(entrada.encode(), conta["private_key"]))
    corpo = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": jwt}).encode()
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
    if DO_ARQUIVO:
        sys.exit("a chave veio do arquivo, e nao do Keychain: nao apague o arquivo; grave a chave no Keychain e confira de novo")


def bloco(tipo, corpo):
    return len(corpo).to_bytes(4, "big") + tipo + corpo + zlib.crc32(tipo + corpo).to_bytes(4, "big")


def png(caminho, alfa=False):
    """A Play pede o icone em PNG de 32 bits (com alfa), o destaque e as telas sem alfa, e nenhuma tela mais comprida que o
    dobro da largura: a mais alta (as da App Store) perde o excesso em cima e embaixo. So PNG de 8 bits, sem paleta nem
    entrelacamento; sai so com IHDR, IDAT e IEND."""
    dados = open(os.path.join(RAIZ, caminho), "rb").read()
    if not dados.startswith(b"\x89PNG\r\n\x1a\n"):
        sys.exit(f"{caminho}: a ficha so aceita PNG")
    i, cabecalho, comprimido = 8, b"", bytearray()
    while i + 12 <= len(dados):
        tamanho, tipo = int.from_bytes(dados[i:i + 4], "big"), dados[i + 4:i + 8]
        corpo = dados[i + 8:i + 8 + tamanho]
        if zlib.crc32(tipo + corpo) != int.from_bytes(dados[i + 8 + tamanho:i + 12 + tamanho], "big"):
            sys.exit(f"{caminho}: bloco {tipo!r} com CRC errado")
        i += 12 + tamanho
        if tipo == b"IHDR":
            cabecalho = corpo
        elif tipo == b"IDAT":
            comprimido += corpo
        elif tipo == b"IEND":
            break
    if len(cabecalho) != 13:
        sys.exit(f"{caminho}: PNG sem IHDR")
    largura, altura = int.from_bytes(cabecalho[0:4], "big"), int.from_bytes(cabecalho[4:8], "big")
    canais = {0: 1, 2: 3, 4: 2, 6: 4}.get(cabecalho[9])
    if cabecalho[8] != 8 or canais is None or cabecalho[12] != 0:
        sys.exit(f"{caminho}: so PNG de 8 bits, sem paleta nem entrelacamento")
    topo, linhas = (altura - 2 * largura) // 2 if altura > 2 * largura else 0, min(altura, 2 * largura)
    alvo = 4 if alfa else 3
    if canais == alvo and topo == 0 and linhas == altura:
        return b"\x89PNG\r\n\x1a\n" + bloco(b"IHDR", cabecalho) + bloco(b"IDAT", bytes(comprimido)) + bloco(b"IEND", b"")
    cru, passo = zlib.decompress(bytes(comprimido)), largura * canais
    if len(cru) != altura * (passo + 1):
        sys.exit(f"{caminho}: dados do PNG com tamanho errado")
    saida, anterior = bytearray(), bytearray(passo)
    for y in range(topo + linhas):
        filtro, linha = cru[y * (passo + 1)], bytearray(cru[y * (passo + 1) + 1:(y + 1) * (passo + 1)])
        for x in range(passo):
            a = linha[x - canais] if x >= canais else 0
            b, c = anterior[x], anterior[x - canais] if x >= canais else 0
            if filtro == 1:
                linha[x] = (linha[x] + a) & 255
            elif filtro == 2:
                linha[x] = (linha[x] + b) & 255
            elif filtro == 3:
                linha[x] = (linha[x] + (a + b) // 2) & 255
            elif filtro == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                linha[x] = (linha[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
            elif filtro != 0:
                sys.exit(f"{caminho}: filtro {filtro} desconhecido")
        anterior = linha
        if y < topo:
            continue
        saida.append(0)
        for x in range(0, passo, canais):
            pixel = linha[x:x + canais]
            cor = pixel[:3] if canais >= 3 else pixel[:1] * 3
            saida += cor + (bytes([pixel[-1] if canais in (2, 4) else 255]) if alfa else b"")
    cabecalho = largura.to_bytes(4, "big") + linhas.to_bytes(4, "big") + bytes([8, 6 if alfa else 2, 0, 0, 0])
    return b"\x89PNG\r\n\x1a\n" + bloco(b"IHDR", cabecalho) + bloco(b"IDAT", zlib.compress(bytes(saida), 9)) + bloco(b"IEND", b"")


def ficha():
    dados = json.load(open(os.path.join(RAIZ, "tools/android/ficha-play.json")))
    # As imagens convertidas antes de ler a chave e pedir o token.
    imagens = {}
    for f in dados["fichas"].values():
        for a, alfa in [(dados["icone"], True)] + ([(f["destaque"], False)] if f["destaque"] else []) + [(tela, False) for tela in f["telas"]]:
            imagens[(a, alfa)] = png(a, alfa)
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
                pedir("POST", f"/edits/{edicao}/listings/{idioma}/{tipo}?uploadType=media", imagens[(a, alfa)], t, base=ENVIO, tipo="image/png")
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
    # A faixa so aceita um lancamento completo: o novo em 100% substitui o anterior ("Only one completed release is allowed").
    if alvo.get("status") == "completed":
        lancamentos = [r for r in lancamentos if r is alvo or r.get("status") != "completed"]
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
    mudar_lancamento(versao, lambda alvo: alvo.update(status="halted"))


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
