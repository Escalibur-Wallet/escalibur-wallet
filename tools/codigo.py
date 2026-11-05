#!/usr/bin/env python3
"""O arquivo como o compilador ou o shell o veem, para as regras do verificar.sh que conferem que um trecho
EXISTE (quarta passada da auditoria de 03/11/2026): comentario nao conta, e no modo `--vivo` texto entre
aspas e ramo `#if false` do Swift tambem nao.

- Swift, Kotlin, Java e Gradle: comentario de linha e de bloco (que nos dois se aninha), texto entre aspas,
  aspas triplas, `#"..."#` do Swift, o codigo dentro de `${}` e `\\()`, e o caractere entre aspas simples do
  Kotlin. Os comentarios viram espacos e as quebras de linha ficam. No modo `--vivo`, o Swift so mantem os
  ramos `#if` que o build de Release da plataforma compila (flag nao definida e falsa, como no compilador).
- Shell, yml, Python e properties: `#` no comeco de uma palavra, fora de aspas, ate o fim da linha.
- xml, plist e entitlements: `<!-- -->`.
- O resto sai como esta.

Uma regra que confere AUSENCIA (o que nunca pode estar no arquivo) le o arquivo cru, nunca este: um texto
com `/*` dentro apagaria codigo de verdade.

    python3 tools/codigo.py <arquivo> [--vivo [--plataforma ios|android|ambas]]
    python3 tools/codigo.py --exige <arquivo> <trecho> [--plataforma ios|android]
    python3 tools/codigo.py --diretivas --plataforma ios|android|ambas <arquivo>...
    python3 tools/codigo.py --testes
"""
import os, re, sys, tempfile

SWIFT_KOTLIN = (".swift", ".kt", ".kts", ".java", ".gradle")
SHELL = (".sh", ".yml", ".yaml", ".py", ".properties")
XML = (".xml", ".plist", ".entitlements", ".xcprivacy")


def c_like(texto, vivo, swift):
    saida, n, i = list(texto), len(texto), 0
    # A pilha do que esta aberto: ("codigo", fecha) com o que fecha a interpolacao, ou ("texto", fim, escape).
    pilha = [("codigo", None, 0)]

    def apagar(a, b):
        saida[a:b] = [c if c == "\n" else " " for c in texto[a:b]]

    def dolares(i):
        # Kotlin 2.2: `$$"..."` so interpola com `$$` (o `${` de menos dolares e texto; sexta passada).
        j = i
        while not swift and j > 0 and texto[j - 1] == "$":
            j -= 1
        return i - j if i - j >= 2 else 1

    while i < n:
        topo = pilha[-1]
        if topo[0] == "codigo":
            fecha, nivel = topo[1], topo[2]
            if texto.startswith("//", i):
                fim = texto.find("\n", i)
                fim = n if fim < 0 else fim
                apagar(i, fim)
                i = fim
            elif texto.startswith("/*", i):
                profundidade, j = 1, i + 2
                while j < n and profundidade:
                    if texto.startswith("/*", j):
                        profundidade, j = profundidade + 1, j + 2
                    elif texto.startswith("*/", j):
                        profundidade, j = profundidade - 1, j + 2
                    else:
                        j += 1
                apagar(i, j)
                i = j
            elif not swift and texto[i] == "'":
                j = i + 1
                j += (6 if texto.startswith("u", j + 1) else 2) if j < n and texto[j] == "\\" else 1
                fim = texto.find("'", j) if j < n and texto[j] != "'" else j
                fim = n - 1 if fim < 0 else fim
                if vivo:
                    apagar(i + 1, fim)
                i = fim + 1
            elif texto[i] == "`":
                # Nome entre crases: opaco ate a proxima crase da mesma linha (aspas e apostrofo dentro nao abrem texto).
                # No modo vivo, um nome que nao e identificador simples (o Swift 6.2 aceita espaco, parenteses e `=`
                # entre crases) e nome, e nao codigo: o miolo sai (decima segunda passada).
                fim = texto.find("`", i + 1)
                quebra = texto.find("\n", i + 1)
                if fim >= 0 and (quebra < 0 or fim < quebra):
                    if vivo and not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", texto[i + 1:fim]):
                        apagar(i + 1, fim)
                    i = fim + 1
                else:
                    i = n if quebra < 0 else quebra
            elif swift and re.match(r"#+/", texto[i:]):
                # Regex literal estendida do Swift: `#/.../#`, com o mesmo numero de `#` no fecho.
                hashes = len(re.match(r"#+", texto[i:]).group(0))
                fecho = "/" + "#" * hashes
                fim = texto.find(fecho, i + hashes + 1)
                fim = n if fim < 0 else fim + len(fecho)
                if vivo:
                    apagar(i + hashes + 1, max(i + hashes + 1, fim - len(fecho)))
                i = fim
            elif swift and texto[i] == "/" and regex_comeca(texto, i, saida):
                # Regex literal `/.../` do Swift: so onde uma expressao comeca (depois de `(`, `,`, `=`, `:`, `[`,
                # `{`, `!`, `&`, `|`, `?`, `return` ou no comeco da linha) e sem espaco logo depois.
                j = i + 1
                while j < n and texto[j] not in "/\n":
                    j += 2 if texto[j] == "\\" else 1
                if vivo:
                    apagar(i + 1, j)
                i = j + 1
            elif swift and texto[i] == "#" and re.match(r'#+"', texto[i:]):
                hashes = len(re.match(r"#+", texto[i:]).group(0))
                triplo = texto.startswith('"""', i + hashes)
                abre = hashes + (3 if triplo else 1)
                pilha.append(("texto", ('"""' if triplo else '"') + "#" * hashes, "\\" + "#" * hashes))
                i += abre
            elif texto.startswith('"""', i):
                # No Kotlin, o `\` nao escapa nada dentro de aspas triplas; no Swift, escapa.
                pilha.append(("texto", '"""', "\\" if swift else None, dolares(i)))
                i += 3
            elif texto[i] == '"':
                pilha.append(("texto", '"', "\\", dolares(i)))
                i += 1
            elif fecha is not None and texto[i] in "({":
                pilha[-1] = ("codigo", fecha, nivel + 1)
                i += 1
            elif fecha is not None and texto[i] == fecha:
                if nivel == 0:
                    pilha.pop()
                else:
                    pilha[-1] = ("codigo", fecha, nivel - 1)
                i += 1
            elif fecha is not None and texto[i] in ")}":
                pilha[-1] = ("codigo", fecha, max(0, nivel - 1))
                i += 1
            else:
                i += 1
        else:
            fim, escape = topo[1], topo[2]
            prefixo = topo[3] if len(topo) > 3 else 1
            if fim == '"""' and texto.startswith(fim, i):
                # O fecho sao as tres ultimas aspas de uma fila de tres ou mais: as da frente sao texto.
                j = i
                while j < n and texto[j] == '"':
                    j += 1
                if vivo:
                    apagar(i, j - 3)
                pilha.pop()
                i = j
            elif texto.startswith(fim, i):
                pilha.pop()
                i += len(fim)
            elif swift and escape and texto.startswith(escape + "(", i):
                pilha.append(("codigo", ")", 0))
                i += len(escape) + 1
            elif not swift and texto.startswith("$" * prefixo + "{", i):
                pilha.append(("codigo", "}", 0))
                i += prefixo + 1
            elif escape and texto.startswith(escape, i):
                largura = len(escape) + 1
                if vivo:
                    apagar(i, min(i + largura, n))
                i += largura
            elif fim == '"' and texto[i] == "\n":
                pilha.pop()
                i += 1
            else:
                if vivo and texto[i] != "\n":
                    saida[i] = " "
                i += 1
    return "".join(saida)


# O que o build de Release compila em cada plataforma: as condicoes que o Swift avalia, com o mesmo valor. Flag
# que nao esta definida e falsa, como no compilador (`DEBUG` inclusive: so a configuracao Debug a define). O que nao
# esta nestas listas nao se conhece (sexta passada da auditoria de 03/11/2026).
MODULOS = {
    "ios": {"Darwin", "Foundation", "CryptoKit", "Security", "os", "LocalAuthentication", "UIKit", "SwiftUI", "Combine",
            "Network", "AVFoundation", "Speech", "UserNotifications", "WidgetKit", "BackgroundTasks", "StoreKit", "Observation",
            "ObjectiveC", "Dispatch", "CoreFoundation", "CommonCrypto"},
    "android": {"Android", "Foundation", "FoundationEssentials", "FoundationNetworking", "Dispatch"},
}
AUSENTES = {
    "ios": {"Android", "FoundationEssentials", "FoundationNetworking", "Glibc", "Musl", "WASILibc", "WinSDK", "CRT"},
    "android": {"Darwin", "CryptoKit", "Security", "os", "LocalAuthentication", "UIKit", "SwiftUI", "Combine", "Network",
                "AVFoundation", "Speech", "UserNotifications", "WidgetKit", "BackgroundTasks", "StoreKit", "ObjectiveC",
                "CommonCrypto", "Glibc", "Musl", "WASILibc", "WinSDK", "CRT"},
}
SISTEMA = {"ios": "iOS", "android": "Android"}
# As flags que o SwiftPM e o Xcode poem sozinhos, sem estar no Package.swift nem no projeto: nao se conhecem (decima
# passada da auditoria de 03/11/2026: valiam falso no leitor e verdadeiro no build). O mesmo vale para qualquer outro
# `SWIFT_` que o alvo nao define.
AUTOMATICAS = {"Xcode", "SWIFT_MODULE_RESOURCE_BUNDLE_AVAILABLE", "SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE"}
# O compilador de cada build: o do Xcode de .xcode-version no iPhone, o do tools/android/compilar-nucleo.sh no Android.
# O verificar.sh confere os dois.
VERSAO_SWIFT = {"ios": (6, 3, 3), "android": (6, 4, 1)}
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def flags_do_alvo(caminho):
    """As flags que o alvo do arquivo define: o SwiftPM define SWIFT_PACKAGE em todo alvo do Kit, e o Package.swift
    define CRYPTO_IN_SWIFTPM so na swift-crypto; o app (project.yml) nao define nenhuma. Fora desses alvos, None: so
    DEBUG e conhecida (falsa no Release), e o resto nao se conhece (setima passada da auditoria de 03/11/2026)."""
    if not caminho:
        return None
    relativo = os.path.relpath(os.path.abspath(caminho), RAIZ).replace(os.sep, "/")
    if relativo.startswith("Kit/Sources/SwiftCrypto/"):
        return {"SWIFT_PACKAGE", "CRYPTO_IN_SWIFTPM"}
    if relativo.startswith("Kit/Sources/") or relativo.startswith("Kit/Tests/"):
        return {"SWIFT_PACKAGE"}
    if relativo.startswith("App/"):
        return set()
    return None


def condicao(texto, plataforma, flags=None):
    """O valor de uma condicao de `#if` no Release da plataforma: True, False ou None quando alguma parte dela nao se
    conhece. Com None, o grupo `#if` inteiro sai, `#elseif` e `#else` inclusive: tomar o desconhecido por falso fazia
    `!canImport(X)` e o `#else` valerem (sexta passada da auditoria de 03/11/2026)."""
    desconhecido = []

    def valor(v):
        # Marcadores que nao sao nome do Swift: um `True` escrito no `#if` e uma flag (falsa), e nao o do Python.
        if v is None:
            desconhecido.append(True)
            return " \x02 "
        return " \x01 " if v else " \x02 "

    def nome_ou_funcao(m):
        if m.group(2) is None:
            nome = m.group(1)
            if nome in ("true", "false"):
                return valor(nome == "true")
            if flags is not None and nome in flags:
                return valor(True)
            if nome in AUTOMATICAS or nome.startswith("SWIFT_"):
                return valor(None)
            if flags is None:
                return valor(False if nome == "DEBUG" else None)
            return valor(False)
        return funcao(m.group(1), m.group(3))

    def funcao(nome, argumento):
        argumento = argumento.strip()
        if nome == "os":
            return valor(argumento == SISTEMA[plataforma])
        if nome == "canImport":
            return valor(True if argumento in MODULOS[plataforma] else False if argumento in AUSENTES[plataforma] else None)
        if nome == "arch":
            return valor(argumento == "arm64" if re.fullmatch(r"arm64|arm|i386|x86_64|wasm32|riscv64", argumento) else None)
        if nome == "targetEnvironment":
            return valor(False if argumento in ("simulator", "macCatalyst") else None)
        if nome == "_runtime":
            return valor({"_ObjC": plataforma == "ios", "_Native": plataforma == "android"}.get(argumento))
        if nome == "hasFeature":
            return valor(False if argumento == "Embedded" else None)
        if nome in ("swift", "compiler"):
            comparacao = re.fullmatch(r"(>=|<)\s*(\d+)(?:\.(\d+))?(?:\.(\d+))?", argumento)
            if not comparacao:
                return valor(None)
            versao = tuple(int(comparacao.group(k) or 0) for k in (2, 3, 4))
            atual = VERSAO_SWIFT[plataforma]
            return valor(atual >= versao if comparacao.group(1) == ">=" else atual < versao)
        return valor(None)

    # Uma passada so: cada nome (ou chamada) vira um marcador, e nenhum nome do arquivo chega ao `eval`.
    expressao = re.sub(r"\b([A-Za-z_][A-Za-z0-9_]*)(\s*\(([^()]*)\))?", nome_ou_funcao, texto)
    expressao = expressao.replace("&&", " and ").replace("||", " or ").replace("!", " not ")
    expressao = expressao.replace("\x01", "True").replace("\x02", "False")
    if desconhecido or not re.fullmatch(r"[\s()]*(?:(?:True|False|and|or|not)[\s()]*)*", expressao):
        return None
    try:
        return bool(eval(expressao, {"__builtins__": {}}, {}))
    except Exception:
        return None


def regex_comeca(texto, i, lido=None):
    """A `/` abre uma regex literal do Swift: depois de um sinal que comeca expressao, e sem espaco logo depois. O que vem
    antes e lido do texto ja sem comentario (`lido`): um `/* c */` antes da regex terminava em `*/` (decima segunda passada
    da auditoria de 03/11/2026)."""
    if i + 1 >= len(texto) or texto[i + 1] in " \t\n/*":
        return False
    lido = texto if lido is None else lido
    j = i - 1
    while j >= 0 and lido[j] in " \t":
        j -= 1
    if j < 0 or lido[j] == "\n":
        return True
    antes = "".join(lido[max(0, j - 40):j + 1])
    # `try!`, `try?` e `??` abrem expressao, e a `/` depois deles abre regex (decima segunda passada: o `!` do `try!` e o
    # segundo `?` do `??` eram lidos como posfixos).
    if re.search(r"(?<![\w.$`])try[!?]$", antes) or antes.endswith("??"):
        return True
    # `!` e `?` colados ao que vem antes sao posfixos (`n!/x`, `cafe!/2`, `a?/b`): a expressao ja fechou, e a `/` e divisao.
    # O leitor tomava por regex e apagava o resto da linha, que o compilador compila (decima primeira passada); o que vem
    # antes pode ser qualquer letra, e nao so ASCII (decima segunda). So o prefixo, com espaco, operador ou abertura antes,
    # abre regex.
    if antes[-1] in "!?" and len(antes) > 1 and not (antes[-2].isspace() or antes[-2] in "([{,;:=+-*/%<&|^~"):
        return False
    # A palavra-chave inteira, e nao um membro com o mesmo nome (`m.in/2`, `$in`, `` `in` ``).
    return antes[-1] in "(,=:[{!&|?;+-*%<>~^" or re.search(
        r"(?<![\w.$`])(?:try|await|in|return|throw|case|where|if|guard|while|switch|else|yield|repeat)$", antes) is not None


def ramos_do_release(texto, plataforma, flags=None):
    """So os ramos `#if`/`#elseif`/`#else` que o build de Release da plataforma compila (quinta passada da
    auditoria de 03/11/2026: uma trava sob `#if DEBUG`, `#elseif false` ou flag nunca definida passava)."""
    # O Swift aceita a diretiva depois de `;` ou `{` na mesma linha, e o leitor so a ve no comeco: com uma no meio
    # da linha (texto e comentario ja apagados), o arquivo inteiro sai, e a regra falha fechado (setima passada).
    vazio = "\n".join(" " * len(l) for l in texto.split("\n"))
    abertos = 0
    for linha in texto.split("\n"):
        meio = re.search(r"#(?:if|elseif|else|endif)\b", linha)
        if meio and linha[:meio.start()].strip():
            return vazio
        comeco = re.match(r"\s*#(if|elseif|else|endif)\b", linha)
        if comeco:
            if comeco.group(1) != "if" and abertos == 0:
                return vazio
            abertos += {"if": 1, "endif": -1}.get(comeco.group(1), 0)
    # `#if` sem par: o arquivo inteiro sai, e a regra falha fechado (decima segunda passada).
    if abertos:
        return vazio
    saida, pilha = [], []  # cada nivel: [o ramo de agora vale, algum ramo ja valeu, o nivel de fora vale]
    for linha in texto.split("\n"):
        limpa = linha.strip()
        fora = all(nivel[0] for nivel in pilha)
        abre = re.match(r"#if\b(.*)$", limpa)
        senaose = re.match(r"#elseif\b(.*)$", limpa)
        if abre:
            vale = condicao(abre.group(1), plataforma, flags)
            # Desconhecida: nenhum ramo do grupo vale (o "ja valeu" fica ligado e fecha o `#elseif` e o `#else`).
            pilha.append([False, True, fora] if vale is None else [vale, vale, fora])
            saida.append("")
        elif senaose and pilha:
            nivel = pilha[-1]
            if nivel[1]:
                nivel[0] = False
            else:
                vale = condicao(senaose.group(1), plataforma, flags)
                nivel[0], nivel[1] = (False, True) if vale is None else (vale, vale)
            saida.append("")
        elif re.match(r"#else\b", limpa) and pilha:
            nivel = pilha[-1]
            nivel[0], nivel[1] = not nivel[1], True
            saida.append("")
        elif re.match(r"#endif\b", limpa) and pilha:
            pilha.pop()
            saida.append("")
        else:
            saida.append(linha if fora else "")
    # Cada linha com o tamanho de antes (em branco): o `--exige` compara as posicoes do arquivo vivo e do cru.
    return "\n".join(nova.ljust(len(velha)) for nova, velha in zip(saida, texto.split("\n")))


# Os nomes que as travas usam e o arquivo dono de cada um (decima segunda passada da auditoria de 03/11/2026): fora do
# dono, os quatro primeiros so aparecem como `Nome.` (um `enum`, parametro, generico, closure ou tupla com o nome
# sombreava o do EscaliburCore com o texto da trava igual); o SecureBytes, que aparece como tipo, nunca e declarado.
DONOS = {"SecureRandom": "Kit/Sources/EscaliburCore/Crypto/SecureRandom.swift", "Hex": "Kit/Sources/EscaliburCore/Encoding/Hex.swift",
         "Hash": "Kit/Sources/EscaliburCore/Crypto/Hash.swift", "Vigias": "Kit/Sources/Android/EscaliburAndroid/App/Vigias.swift"}
DONO_DO_SECUREBYTES = "Kit/Sources/EscaliburCore/Crypto/SecureBytes.swift"
_SB = r"`?SecureBytes`?"
DECLARA_SECUREBYTES = re.compile(
    r"\b(?:enum|struct|class|typealias|protocol|actor|let|var|func|case|associatedtype)\s+" + _SB + r"(?![\w])"
    r"|<\s*(?:[^<>]*,\s*)?" + _SB + r"\s*[:,>]"
    r"|[(,]\s*(?:\w+\s+)?" + _SB + r"\s*:"
    r"|\bfor\s+" + _SB + r"\b"
    r"|\{\s*\(?[\w\s,]*\b" + _SB + r"\b[^}]*?\bin\b"
    r"|\b(?:let|var)\s*\([^)]*\b" + _SB + r"\b"
    r"|\bimport\s+\w+\s+[\w.]*\." + _SB, re.S)


def sombras(caminho, vivo):
    """Os nomes donos fora do arquivo dono: uso que nao e `Nome.` e declaracao do SecureBytes."""
    relativo = os.path.relpath(os.path.abspath(caminho), RAIZ).replace(os.sep, "/")
    problemas = []
    for nome, dono in DONOS.items():
        if relativo == dono:
            continue
        for m in re.finditer(r"(?<![\w.$])`?" + nome + r"`?(?![\w])", vivo):
            if not re.match(r"\s*\.", vivo[m.end():]):
                problemas.append(f"{caminho}:{vivo[:m.start()].count(chr(10)) + 1}: {nome} sem ser `{nome}.` fora do arquivo dono")
    if relativo != DONO_DO_SECUREBYTES:
        for m in DECLARA_SECUREBYTES.finditer(vivo):
            problemas.append(f"{caminho}:{vivo[:m.start()].count(chr(10)) + 1}: SecureBytes declarado fora do arquivo dono")
    return problemas


def diretivas(caminho, plataforma):
    """As diretivas que o leitor nao resolve: um `#if` ou `#elseif` com condicao desconhecida em alguma plataforma, e
    uma diretiva no meio da linha. O leitor tira esse grupo do vivo, e o build pode compila-lo: um `if true { return
    true }` la dentro desligava uma trava com a regra verde (decima passada da auditoria de 03/11/2026). Todo `#if`,
    ativo ou nao, e toda plataforma que o arquivo compila."""
    cru = open(caminho, encoding="utf-8").read()
    texto = c_like(cru, True, True)
    flags = flags_do_alvo(caminho)
    plataformas = ("ios", "android") if plataforma == "ambas" else (plataforma,)
    problemas = []
    # Falha fechado para o que o leitor apagasse por engano (decima segunda passada): no texto sem comentario, mas com o
    # texto entre aspas e as regex, nenhuma diretiva fora do comeco da linha; e `#if` e `#endif` sempre aos pares.
    for numero, linha in enumerate(c_like(cru, False, True).split("\n"), 1):
        m = re.search(r"#(if|elseif|else|endif)\b", linha)
        if m and linha[:m.start()].strip():
            problemas.append(f"{caminho}:{numero}: diretiva fora do comeco da linha (no texto sem comentario)")
    abertos = 0
    for numero, linha in enumerate(texto.split("\n"), 1):
        m = re.match(r"\s*#(if|elseif|else|endif)\b", linha)
        if m and m.group(1) == "if":
            abertos += 1
        elif m and abertos == 0:
            problemas.append(f"{caminho}:{numero}: #{m.group(1)} sem #if")
        elif m and m.group(1) == "endif":
            abertos -= 1
        # Um nome entre crases que nao e identificador simples (o miolo sai no vivo): nenhum no Swift de primeira mao.
        if re.search(r"`[ \t]*`", linha):
            problemas.append(f"{caminho}:{numero}: nome entre crases que nao e identificador simples")
    if abertos:
        problemas.append(f"{caminho}: #if sem #endif")
    problemas += sombras(caminho, texto)
    for numero, linha in enumerate(texto.split("\n"), 1):
        m = re.search(r"#(if|elseif|else|endif)\b(.*)$", linha)
        if not m:
            continue
        if linha[:m.start()].strip():
            problemas.append(f"{caminho}:{numero}: diretiva no meio da linha")
        elif m.group(1) in ("if", "elseif"):
            for p in plataformas:
                if condicao(m.group(2), p, flags) is None:
                    problemas.append(f"{caminho}:{numero}: #{m.group(1)}{m.group(2)} nao se resolve no {SISTEMA[p]}")
    return problemas


def palavra_do_heredoc(linha, k):
    """O delimitador de um heredoc como o bash le: a palavra ate um branco ou `;&|()<>`, sem as aspas e sem as `\\`
    (`<<\\X`, `<<'FIM-X'` e `<<~EOF`, cujo fim e a linha `~EOF`; sexta passada da auditoria de 03/11/2026)."""
    palavra = ""
    while k < len(linha) and linha[k] not in " \t;&|()<>":
        c = linha[k]
        if c in "'\"":
            fim = linha.find(c, k + 1)
            fim = len(linha) if fim < 0 else fim
            palavra += linha[k + 1:fim]
            k = fim + 1
        elif c == "\\":
            palavra += linha[k + 1:k + 2]
            k += 2
        else:
            palavra += c
            k += 1
    return palavra, k


def shell(texto):
    """Shell: aspas que atravessam linhas, `\\` fora de aspas, `$'...'`, o corpo de heredoc (dado, e nao codigo) e o
    `#` no comeco de uma palavra (depois de espaco, tab ou `;&|()<>`). `<<<` e here-string, e nao heredoc."""
    saida, aspas, pendentes, corpo = [], None, [], None
    for linha in texto.split("\n"):
        if corpo is not None:
            delimitador, tira_tab = corpo
            if (linha.lstrip("\t") if tira_tab else linha) == delimitador:
                corpo = pendentes.pop(0) if pendentes else None
            saida.append("")
            continue
        fora, i = [], 0
        while i < len(linha):
            c = linha[i]
            if aspas == "'":
                fora.append(c)
                aspas = None if c == "'" else aspas
                i += 1
            elif aspas in ('"', "$'"):
                if c == "\\":
                    fora.append(linha[i:i + 2])
                    i += 2
                    continue
                fora.append(c)
                if (aspas == '"' and c == '"') or (aspas == "$'" and c == "'"):
                    aspas = None
                i += 1
            elif c == "\\":
                fora.append(linha[i:i + 2])
                i += 2
            elif linha.startswith("$'", i):
                aspas = "$'"
                fora.append("$'")
                i += 2
            elif c in "'\"":
                aspas = c
                fora.append(c)
                i += 1
            elif c == "#" and (i == 0 or linha[i - 1] in " \t;&|()<>"):
                break
            else:
                if linha.startswith("<<<", i):
                    fora.append("<<<")
                    i += 3
                    continue
                heredoc = re.match(r"<<(-?)[ \t]*", linha[i:])
                palavra, fim = palavra_do_heredoc(linha, i + len(heredoc.group(0))) if heredoc else ("", i)
                if palavra:
                    pendentes.append((palavra, heredoc.group(1) == "-"))
                    fora.append(linha[i:fim])
                    i = fim
                else:
                    fora.append(c)
                    i += 1
        saida.append("".join(fora))
        if pendentes and aspas is None:
            corpo = pendentes.pop(0)
    return "\n".join(saida)


def comentario_yaml(linha):
    """A linha sem o comentario do YAML: `#` no comeco ou depois de branco, fora de texto entre aspas. Aspas so abrem
    texto no comeco de um valor (depois de `: `, `- `, `? `, `[`, `{` ou `,`, e de uma ancora ou tag ali, como `&a` e
    `!!str`; decima passada); no meio de um valor sem aspas sao letras."""
    i, aspas = 0, None
    while i < len(linha):
        c = linha[i]
        if aspas:
            if aspas == "'" and linha.startswith("''", i):
                i += 2
                continue
            if aspas == '"' and c == "\\":
                i += 2
                continue
            if c == aspas:
                aspas = None
        elif c in "'\"" and re.search(r"(^|[:\-\[{,?])\s*(?:[&!]\S*\s+)*$", linha[:i]):
            aspas = c
        elif c == "#" and (i == 0 or linha[i - 1] in " \t"):
            return linha[:i]
        i += 1
    return linha


def recuo(linha):
    return len(linha) - len(linha.lstrip(" "))


def run_de_um_passo(linhas, i, coluna):
    """O `run:` da linha `i` (chave na `coluna`) e o de um item da lista `steps:`: debaixo de `env:` ou de outra chave,
    e texto (setima passada da auditoria de 03/11/2026)."""
    k, traco = i, None
    while k >= 0:
        linha = comentario_yaml(linhas[k]).rstrip()
        if linha.strip():
            m = re.match(r"^( *)(- +)?([A-Za-z0-9_.-]+):", linha)
            if not m:
                return False
            col = len(m.group(1)) + len(m.group(2) or "")
            if col < coluna:
                return False
            if col == coluna and m.group(2):
                traco = len(m.group(1))
                break
        k -= 1
    if traco is None:
        return False
    for j in range(k - 1, -1, -1):
        linha = comentario_yaml(linhas[j]).rstrip()
        if not linha.strip():
            continue
        r = recuo(linha)
        if r > traco or (r == traco and linha.lstrip().startswith("- ")):
            continue
        # `steps:` de um job: a chave de cima e o id do job, e a de cima dele e `jobs:` na coluna 0 (um `steps:`
        # debaixo de `matrix:` nao vale; oitava passada).
        return re.fullmatch(r" *steps:", linha) is not None and pai_e_job(linhas, j)
    return False


def acima(linhas, j):
    """A linha da chave de que a linha `j` faz parte (a primeira acima com recuo menor), ou None."""
    r = recuo(comentario_yaml(linhas[j]))
    for k in range(j - 1, -1, -1):
        linha = comentario_yaml(linhas[k]).rstrip()
        if linha.strip() and recuo(linha) < r and not linha.lstrip().startswith("- "):
            return k
        if linha.strip() and recuo(linha) < r:
            return None
    return None


def pai_e_job(linhas, j):
    job = acima(linhas, j)
    if job is None or not re.fullmatch(r" *[A-Za-z0-9_-]+:", comentario_yaml(linhas[job]).rstrip()):
        return False
    topo = acima(linhas, job)
    return topo is not None and comentario_yaml(linhas[topo]).rstrip() == "jobs:"


def yml(texto, vivo):
    """yml de workflow: o comentario do YAML, e o shell so nos blocos `run: |` e `run: |-`, sem o recuo do bloco,
    como o shell os recebe (o fim de heredoc mais recuado que o bloco nao fecha, como no bash). `run:` dobrado (`>`),
    entre aspas ou com indicador de recuo sai inteiro: o shell recebe outra coisa que o arquivo mostra. Um bloco de
    texto que nao e `run:` e dado: no modo `--vivo` sai (sexta passada da auditoria de 03/11/2026)."""
    linhas, saida, i = texto.split("\n"), [], 0
    # Um `shell:` que nao e o bash (no passo ou em `defaults:`) faz o `run:` ser outra coisa: nenhum conta (oitava
    # passada da auditoria de 03/11/2026).
    # Em qualquer grafia: entre aspas, com espaco antes dos dois pontos, com o valor na linha de baixo ou num `{ }`
    # (nona passada); so `shell: bash`, simples, passa.
    outro_shell = any(re.search(r"""(^|[\s{,?'"-])shell['"]?[ \t]*:""", comentario_yaml(l))
                      and not re.fullmatch(r" *(- +)?shell:[ \t]*bash", comentario_yaml(l).rstrip()) for l in linhas)
    while i < len(linhas):
        linha = linhas[i]
        chave = re.match(r"^( *)((?:- +)*)([A-Za-z0-9_.-]+):(?:[ \t]+(.*))?$", comentario_yaml(linha).rstrip())
        if not chave:
            # Fora de chave simples sem aspas (chave entre aspas, `chave :`, texto na linha de baixo, `{...}`): dado,
            # e no modo `--vivo` sai (oitava passada da auditoria de 03/11/2026).
            saida.append("" if vivo else comentario_yaml(linha))
            i += 1
            continue
        coluna = len(chave.group(1)) + len(chave.group(2))
        nome, valor = chave.group(3), (chave.group(4) or "").strip()
        # Um `run:` fora de um passo nao e shell: sai inteiro, como o `run:` em outra forma.
        fora_de_passo = nome == "run" and (outro_shell or not run_de_um_passo(linhas, i, coluna))
        j = i + 1
        while j < len(linhas) and (not linhas[j].strip() or recuo(linhas[j]) > coluna):
            j += 1
        # As linhas em branco do fim nao sao do valor.
        while j > i + 1 and not linhas[j - 1].strip():
            j -= 1
        conteudo = linhas[i + 1:j]
        # Ancora (`&a`) e tag (`!!str`) antes do indicador: o bloco continua bloco (setima passada).
        bloco = re.fullmatch(r"((?:[&!]\S*\s+)*)([|>])([+-]?)(\d?)([+-]?)", valor)
        if bloco:
            saida.append(comentario_yaml(linha))
            if nome == "run" and not fora_de_passo and not bloco.group(1) and bloco.group(2) == "|" and not bloco.group(4) and conteudo:
                margem = min(recuo(l) for l in conteudo if l.strip())
                corpo = [l[margem:] if l.strip() else "" for l in conteudo]
                tratado = shell("\n".join(corpo)).split("\n")
                saida += [" " * margem + t if t else "" for t in tratado]
            elif nome == "run" or vivo:
                saida += [""] * len(conteudo)
            else:
                saida += conteudo
            i = j
            continue
        if nome == "run":
            # Uma linha so: sem aspas, o comando vai ao shell; entre aspas ou continuado nas linhas de baixo, sai.
            comeco = comentario_yaml(linha)[:comentario_yaml(linha).index(":", coluna) + 1]
            if valor and valor[0] not in "'\"" and not conteudo and not fora_de_passo:
                saida.append(comeco + " " + shell(valor))
            else:
                saida.append(comeco)
                saida += [""] * len(conteudo)
            i = j
            continue
        if valor and conteudo:
            # Valor que continua nas linhas de baixo (texto entre aspas ou sem aspas em varias linhas): dado; no
            # modo `--vivo`, sai.
            saida.append(comentario_yaml(linha))
            saida += [""] * len(conteudo) if vivo else conteudo
            i = j
            continue
        # No modo `--vivo`, o valor de outra chave e dado: fica so a chave (oitava passada).
        saida.append(comentario_yaml(linha)[:comentario_yaml(linha).index(":", coluna) + 1] if vivo else comentario_yaml(linha))
        i += 1
    # Cada linha com o tamanho de antes: o `--exige` compara as posicoes do arquivo vivo e do cru (oitava passada).
    return "\n".join(nova.ljust(len(velha)) for nova, velha in zip(saida, linhas))


def python(texto):
    """Python: `#` em qualquer lugar fora de texto (aspas simples, duplas e triplas, com escape)."""
    saida, i, n, aspas = [], 0, len(texto), None
    while i < n:
        if aspas:
            if texto.startswith(aspas, i):
                saida.append(aspas)
                i += len(aspas)
                aspas = None
            elif texto[i] == "\\":
                saida.append(texto[i:i + 2])
                i += 2
            else:
                saida.append(texto[i])
                i += 1
        elif texto.startswith(('"""', "\'\'\'"), i):
            aspas = texto[i:i + 3]
            saida.append(aspas)
            i += 3
        elif texto[i] in "'\"":
            aspas = texto[i]
            saida.append(aspas)
            i += 1
        elif texto[i] == "#":
            fim = texto.find("\n", i)
            i = n if fim < 0 else fim
        else:
            saida.append(texto[i])
            i += 1
    return "".join(saida)


def ler(caminho, vivo=False, plataforma="ios"):
    texto = open(caminho, encoding="utf-8").read()
    if caminho.endswith(SWIFT_KOTLIN):
        swift = caminho.endswith(".swift")
        texto = c_like(texto, vivo, swift)
        if swift and vivo and plataforma == "ambas":
            # O Kit compila nas duas: a linha so fica se for viva no Release das duas (setima passada da auditoria de
            # 03/11/2026: uma trava sob `#if !os(Android)` num arquivo do Kit sumia do Android com a regra verde).
            flags = flags_do_alvo(caminho)
            ios = ramos_do_release(texto, "ios", flags).split("\n")
            android = ramos_do_release(texto, "android", flags).split("\n")
            texto = "\n".join(a if a == b else " " * len(a) for a, b in zip(ios, android))
        elif swift and vivo:
            texto = ramos_do_release(texto, plataforma, flags_do_alvo(caminho))
        return texto
    if caminho.endswith(".py"):
        return python(texto)
    if caminho.endswith(SHELL) or os.path.basename(caminho) == "Podfile":
        return yml(texto, vivo) if caminho.endswith((".yml", ".yaml")) else shell(texto)
    if caminho.endswith(".pro"):
        # ProGuard e R8: `#` ate o fim da linha.
        return re.sub(r"#[^\n]*", lambda m: " " * len(m.group(0)), texto)
    if caminho.endswith(XML):
        return re.sub(r"<!--.*?-->", lambda m: "\n" * m.group(0).count("\n"), texto, flags=re.S)
    return texto


# Os casos das auditorias: o trecho tem de sumir (comentado ou morto) ou ficar (codigo de verdade).
CASOS = [
    # (extensao, fonte, trecho, vivo, fica?)
    (".kt", "/* off /** doc */ if (fechadoPelaAcessibilidade(segredo)) return true */", "fechadoPelaAcessibilidade", False, False),
    (".kt", "val x = 0//trava()", "trava()", False, False),
    (".kt", "// trava()", "trava()", False, False),
    (".kt", 'val s = "/* nao e comentario"\ntrava()\nval t = "*/"', "trava()", False, True),
    (".kt", 'val s = "trava()"', "trava()", True, False),
    (".kt", 'val s = "${trava()}"', "trava()", True, True),
    (".kt", "val c = '\"'\ntrava()", "trava()", False, True),
    (".swift", "/* a /* b */ trava() */", "trava()", False, False),
    (".swift", "#if false\n_ = mlock(region, n)\n#endif", "mlock(region", True, False),
    (".swift", "#if false\nx()\n#else\n_ = mlock(region, n)\n#endif", "mlock(region", True, True),
    (".swift", "#if DEBUG\ntrava()\n#endif", "trava()", True, False),
    (".swift", "#if DEBUG\nx()\n#else\ntrava()\n#endif", "trava()", True, True),
    (".swift", "#if false\nx()\n#elseif false\ntrava()\n#endif", "trava()", True, False),
    (".swift", "#if 0\nx()\n#elseif 0\ntrava()\n#endif", "trava()", True, False),
    (".swift", "#if FLAG_NUNCA_DEFINIDA\ntrava()\n#endif", "trava()", True, False),
    (".swift", "#if os(iOS)\nx()\n#else\ntrava()\n#endif", "trava()", True, False),
    (".swift", "#if os(iOS) && !targetEnvironment(simulator)\ntrava()\n#endif", "trava()", True, True),
    (".swift", "#if !canImport(Darwin)\ntrava()\n#endif", "trava()", True, False),
    (".swift", "#if !canImport(Darwin)\ntrava()\n#endif", "trava()", True, True, "android"),
    (".swift", "#if canImport(Darwin)\nx()\n#elseif canImport(Android)\ntrava()\n#endif", "trava()", True, True, "android"),
    (".swift", "#if canImport(Darwin)\ntrava()\n#elseif canImport(Android)\nx()\n#endif", "trava()", True, True),
    (".swift", "#if DEBUG\n#if true\ntrava()\n#endif\n#endif", "trava()", True, False),
    (".swift", "#if compiler(>=6.1)\ntrava()\n#endif", "trava()", True, True),
    (".swift", 'let s = "_ = mlock(region"', "mlock(region", True, False),
    (".swift", 'let s = "\\(mlock(region))"', "mlock(region", True, True),
    (".swift", 'let s = #"/*"#\n_ = mlock(region, n)', "mlock(region", True, True),
    (".swift", '_ = mlock(region, n) // ok', "mlock(region", True, True),
    (".sh", "true;#source tools/copia-publicada.sh", "source tools/copia-publicada.sh", False, False),
    (".sh", "# source tools/copia-publicada.sh", "source tools/copia-publicada.sh", False, False),
    (".sh", "source tools/copia-publicada.sh", "source tools/copia-publicada.sh", False, True),
    (".sh", 'echo "#x"; trava', "trava", False, True),
    (".sh", "echo ${#lista}; trava", "trava", False, True),
    # Quinta passada (cybersecurity): o que o leitor lia errado.
    (".kt", 'val caminho = """C:\\"""\nval nota = """ foco.clearFocus(force = true) """', "clearFocus", True, False),
    (".kt", 'val x = """a""""\ntrava()', "trava()", False, True),
    (".kt", "fun `user's case`() {}\n// trava()", "trava()", False, False),
    (".swift", 'let r = /"/; x() // trava()', "trava()", False, False),
    (".swift", 'let r = #/"/#; x() // trava()', "trava()", False, False),
    (".swift", "let y = a/b; trava()", "trava()", False, True),
    (".swift", "let y = a / b // trava()", "trava()", False, False),
    (".sh", "echo \\' # source tools/copia-publicada.sh", "source tools/copia-publicada.sh", False, False),
    (".sh", "echo $'it\\'s' # source tools/copia-publicada.sh", "source tools/copia-publicada.sh", False, False),
    (".sh", 'x="a\nb" # source tools/copia-publicada.sh', "source tools/copia-publicada.sh", False, False),
    (".sh", ": <<'X'\nsource tools/copia-publicada.sh\nX", "source tools/copia-publicada.sh", False, False),
    (".sh", "(true)#source tools/copia-publicada.sh", "source tools/copia-publicada.sh", False, False),
    (".sh", "cat <<EOF\nfora\nEOF\nsource tools/copia-publicada.sh", "source tools/copia-publicada.sh", False, True),
    (".py", "x = 1#trava()", "trava()", False, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - run: |\n          python3 - <<'PY'\n          print(1)\n          PY\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", False, True),
    (".sh", "grep -q x <<<EOF\ntrava", "trava", False, True),
    # Sexta passada de 03/11/2026: o desconhecido tira o grupo inteiro, a versao do Swift por plataforma, a regex do
    # Swift depois de palavra-chave, o `$$` do Kotlin, o delimitador de heredoc como palavra e o yml.
    (".swift", "#if !canImport(ObjectiveC)\ntrava()\n#endif", "trava()", True, False, "ios"),
    (".swift", "#if canImport(ObjectiveC)\nx()\n#else\ntrava()\n#endif", "trava()", True, False, "ios"),
    (".swift", "#if !_runtime(_ObjC)\ntrava()\n#endif", "trava()", True, False, "ios"),
    (".swift", "#if compiler(>=6.4)\ntrava()\n#endif", "trava()", True, False, "ios"),
    (".swift", "#if compiler(>=6.4)\ntrava()\n#endif", "trava()", True, True, "android"),
    (".swift", "#if swift(>=6.3.4)\ntrava()\n#endif", "trava()", True, False, "ios"),
    (".swift", "#if hasFeature(Algo)\nx()\n#else\ntrava()\n#endif", "trava()", True, False),
    (".swift", "#if DEBUG\nx()\n#elseif hasFeature(Algo)\ny()\n#else\ntrava()\n#endif", "trava()", True, False),
    (".swift", "#if DEBUG\nx()\n#else\ntrava()\n#endif", "trava()", True, True),
    (".swift", "#if !canImport(UIKit)\ntrava()\n#endif", "trava()", True, True, "android"),
    (".swift", 'let ok = try /"/.firstMatch(in: s) != nil; let t = " trava() "', "trava()", True, False),
    (".swift", '{ (s: String) in /"/ }; let t = " trava() "', "trava()", True, False),
    (".kt", 'val s = $$"${trava()}"', "trava()", True, False),
    (".kt", 'val s = $$"$${trava()}"', "trava()", True, True),
    (".kt", 'val s = $$"""${trava()}"""', "trava()", True, False),
    (".sh", ": <<\\X\ntrava\nX", "trava", False, False),
    (".sh", ": <<'FIM-X'\ntrava\nFIM-X", "trava", False, False),
    (".sh", ": <<FIM-X\nFIM\ntrava\nFIM-X", "trava", False, False),
    (".sh", ": <<~EOF\nEOF\ntrava\n~EOF", "trava", False, False),
    (".sh", ": <<~EOF\nx\n~EOF\nfica", "fica", False, True),
    (".yml", "jobs:\n  a:\n    steps:\n      - run: |\n          python3 - <<'PY'\n          x\n            PY\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", False, False),
    (".yml", "run: >\n  true # ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", False, False),
    (".yml", "run: >\n  true\n  ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", False, False),
    (".yml", "run: 'true # ESCALIBUR_COMMIT=x'", "ESCALIBUR_COMMIT=x", False, False),
    (".yml", "run: |2\n  ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", False, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - run: |\n          echo oi\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", False, True),
    (".yml", "jobs:\n  a:\n    steps:\n      - run: >\n          true # ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", False, False),
    (".yml", "name: Don't stop\njobs:\n  a:\n    steps:\n      - run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", False, True),
    (".yml", "env:\n  NOTA: |\n    ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - run: ./tools/verificar.sh --testes # comentario", "./tools/verificar.sh --testes", False, True),
    (".yml", "steps:\n  - run: echo oi # ./tools/verificar.sh", "./tools/verificar.sh", False, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - name: x\n        run: |\n          ESCALIBUR_COMMIT=x\n      - run: y", "ESCALIBUR_COMMIT=x", False, True),
    # Setima passada: a diretiva no meio da linha, `True` como flag, e o yml com ancora, tag e texto continuado.
    (".swift", "x(); #if DEBUG\ntrava()\n#endif", "trava()", True, False),
    (".swift", "#if !DEBUG\ny(); #else\ntrava()\n#endif", "trava()", True, False),
    (".swift", "func f() { #if DEBUG\ntrava()\n#endif\n}", "trava()", True, False),
    (".swift", "#if True\ntrava()\n#endif", "trava()", True, False),
    (".swift", "#if !os(Android)\ntrava()\n#endif", "trava()", True, False, "ambas"),
    (".swift", "#if os(Android)\nx()\n#else\ny()\n#endif\ntrava()", "trava()", True, True, "ambas"),
    (".swift", "#if !True\ntrava()\n#endif", "trava()", True, False),
    (".yml", "env:\n  NOTA: &n |\n    ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "env:\n  NOTA: !!str |\n    ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "env:\n  NOTA: \"a\n    ESCALIBUR_COMMIT=x\"", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "run: &r |\n  ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", False, False),
    (".yml", "env:\n  run: |\n    ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    # Oitava passada: chave entre aspas, `chave :`, texto na linha de baixo, outro shell, `steps:` de matrix, valor
    # de outra chave.
    (".yml", "env:\n  \"NOTA\": |\n    ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "env:\n  NOTA : |\n    ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "env:\n  NOTA:\n    ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - shell: cat {0}\n        run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "defaults:\n  run:\n    shell: cat {0}\njobs:\n  a:\n    steps:\n      - run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "jobs:\n  a:\n    strategy:\n      matrix:\n        steps:\n          - run: |\n              ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "env:\n  NOTA: ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - shell: bash\n        run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, True),
    (".yml", "jobs:\n  a:\n    steps:\n      - \"shell\": cat {0}\n        run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - shell : cat {0}\n        run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - run: |\n          ESCALIBUR_COMMIT=x\n        shell:\n          cat {0}", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "defaults: {run: {shell: \"cat {0}\"}}\njobs:\n  a:\n    steps:\n      - run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - name: x # nota\n        run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, True),
    (".yml", "jobs:\n  a:\n    steps:\n    - run: |\n        ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, True),
    (".yml", "jobs:\n  a:\n    steps:\n      - name: x\n        env:\n          run: |\n            ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - uses: y\n      - name: x\n        run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, True),
    (".py", 'x = "#"; trava()', "trava()", False, True),
    # Decima primeira passada: `!` e `?` posfixos antes da `/` sao divisao, e o resto da linha e codigo.
    (".swift", "let _ = n!/sabota()", "sabota()", True, True),
    (".swift", "if n!/sabota() > 0 { trava() }", "trava()", True, True),
    (".swift", "if a?/b > 0 { trava() }", "trava()", True, True),
    (".swift", "let x = f()!/2; trava()", "trava()", True, True),
    (".swift", "let x = a[0]!/2; trava()", "trava()", True, True),
    (".swift", 'if !/"/.matches(s) { trava() }; let t = " x "', "trava()", True, True),
    (".swift", 'let ok = !/a b/.matches(s); let t = " trava() "', "trava()", True, False),
    # Decima segunda passada: `try!`, `try?`, `as!` e `as?` sao palavra-chave, e a `/` depois deles abre regex.
    (".swift", "_ = try? /allowedHosts.contains(host)/.firstMatch(in: h)", "allowedHosts.contains(host)", True, False),
    (".swift", "_ = try! /trava()/.firstMatch(in: h)", "trava()", True, False),
    (".swift", "_ = try!/trava()/.firstMatch(in: h)", "trava()", True, False),
    (".swift", 'let r = try? /"/.firstMatch(in: h); trava()', "trava()", True, True),
    (".swift", 'let r = try! /"/.firstMatch(in: h); trava()', "trava()", True, True),
    (".swift", "let n = retry!/2; trava()", "trava()", True, True),
    # Decima segunda passada (militar): nome fora do ASCII, `??`, comentario antes da regex, `/=`, membro com nome de
    # palavra-chave, e nome entre crases com espaco.
    (".swift", "let q = caf\u00e9!/2; trava()", "trava()", True, True),
    (".swift", "let q = \u0394!/2; trava()", "trava()", True, True),
    (".swift", "let r = c ?? /trava()/", "trava()", True, False),
    (".swift", "let r = /* p */ /trava()/", "trava()", True, False),
    (".swift", "let r = /=trava()/", "trava()", True, False),
    (".swift", "let a = m.in/2; trava()", "trava()", True, True),
    (".swift", "let a = m.case/2; trava()", "trava()", True, True),
    (".swift", "let a = m.return/1; trava()", "trava()", True, True),
    (".swift", "func `chama trava() aqui`() -> Int { 0 }", "trava()", True, False),
    (".swift", "func `trava`() -> Int { 0 }", "trava", True, True),
    (".kt", "fun `trava() no teste`() {}", "trava()", True, False),
    # Decima passada: texto entre aspas depois de ancora ou tag nao e comentario, e o `shell:` depois dele conta; no
    # meio de um valor sem aspas, o `&` nao abre nada.
    (".yml", "jobs:\n  a:\n    steps:\n      - {name: &n \"x #\", shell: cat {0}, run: y}\n      - run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - {name: !!str \"x #\", shell: cat {0}, run: y}\n      - run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - ? \"x #\"\n        : shell: cat {0}\n      - run: |\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True, False),
    (".yml", "jobs:\n  a:\n    steps:\n      - run: echo a&b \"x # ESCALIBUR_COMMIT=x\"", "ESCALIBUR_COMMIT=x", False, False),
]


# (extensao, fonte, trecho, acha?)
EXIGE = [
    (".kts", 'check(git("rev-parse", "HEAD") == x)', 'git("rev-parse", "HEAD") == x', True),
    (".kts", 'val nota = """check(git("rev-parse", "HEAD") == x)"""\ncheck(git("rev-parse", "HEAD!") == x)', 'git("rev-parse", "HEAD") == x', False),
    (".kts", '// check(git("rev-parse", "HEAD") == x)', 'git("rev-parse", "HEAD") == x', False),
    (".kts", 'val s = "release ${a[0]} $b"', '"release ${a[0]} $b"', True),
    (".swift", '#if DEBUG\nlet x = trava()\n#endif\nlet y = 1', "let x = trava()", False),
    (".pro", "# -keep class a.B { *; }\n-dontwarn x", "-keep class a.B", False),
    (".pro", "-keep class a.B { *; }", "-keep class a.B", True),
    (".yml", "jobs:\n  a: # x\n    env:\n      NOTA: a\n    steps:\n      - name: y # z\n        run: |\n          echo oi\n          ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", True),
    (".yml", "env:\n  NOTA: ESCALIBUR_COMMIT=x", "ESCALIBUR_COMMIT=x", False),
]


def testes():
    erros = []
    with tempfile.TemporaryDirectory() as pasta:
        for indice, (extensao, fonte, trecho, vivo, fica, *resto) in enumerate(CASOS):
            plataforma = resto[0] if resto else "ios"
            caminho = os.path.join(pasta, f"caso{indice}{extensao}")
            open(caminho, "w", encoding="utf-8").write(fonte)
            if (trecho in ler(caminho, vivo, plataforma)) != fica:
                erros.append(f"caso {indice} ({extensao}, vivo={vivo}, {plataforma}): {fonte!r} devia {'manter' if fica else 'tirar'} {trecho!r}")
        for indice, (extensao, fonte, trecho, fica) in enumerate(EXIGE):
            caminho = os.path.join(pasta, f"exige{indice}{extensao}")
            open(caminho, "w", encoding="utf-8").write(fonte)
            if exige(caminho, trecho, "ios") != fica:
                erros.append(f"exige {indice} ({extensao}): {fonte!r} devia {'achar' if fica else 'recusar'} {trecho!r}")
    # As flags por alvo, direto na condicao (setima passada).
    diretos = [
        (condicao("True", "ios", set()), False), (condicao("!SWIFT_PACKAGE", "ios", {"SWIFT_PACKAGE"}), False),
        (condicao("CRYPTO_IN_SWIFTPM", "ios", set()), False), (condicao("FOO", "ios", None), None),
        (condicao("!DEBUG", "ios", None), True), (condicao("SWIFT_PACKAGE && canImport(Darwin)", "ios", {"SWIFT_PACKAGE"}), True),
        (flags_do_alvo(os.path.join(RAIZ, "App/EscaliburWallet/x.swift")), set()),
        (flags_do_alvo(os.path.join(RAIZ, "Kit/Sources/SwiftCrypto/x.swift")), {"SWIFT_PACKAGE", "CRYPTO_IN_SWIFTPM"}),
        (flags_do_alvo(os.path.join(RAIZ, "Kit/Sources/EscaliburCore/x.swift")), {"SWIFT_PACKAGE"}),
        (flags_do_alvo("/private/tmp/x.swift"), None),
        # Decima passada: as flags que o SwiftPM e o Xcode poem sozinhos nao se conhecem, e SWIFT_PACKAGE so no Kit.
        (condicao("Xcode", "ios", {"SWIFT_PACKAGE"}), None), (condicao("!Xcode", "android", {"SWIFT_PACKAGE"}), None),
        (condicao("SWIFT_MODULE_RESOURCE_BUNDLE_AVAILABLE", "ios", {"SWIFT_PACKAGE"}), None),
        (condicao("SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE", "android", set()), None),
        (condicao("SWIFT_PACKAGE", "ios", set()), None), (condicao("SWIFT_PACKAGE", "ios", {"SWIFT_PACKAGE"}), True),
        (condicao("SWIFT_OUTRA", "ios", None), None), (condicao("FLAG_NUNCA_DEFINIDA", "ios", set()), False),
    ]
    for indice, (obtido, esperado) in enumerate(diretos):
        if obtido != esperado:
            erros.append(f"direto {indice}: {obtido!r} em vez de {esperado!r}")
    # Decima passada: toda diretiva que o leitor nao resolve aparece (fonte, plataforma, acha?).
    casos_diretivas = [
        ("#if hasFeature(ConciseMagicFile)\nx()\n#endif", "ios", True),
        ("#if canImport(CoreGraphics)\nx()\n#endif", "ios", True),
        ("#if Xcode\nx()\n#endif", "ios", True),
        ("#if SWIFT_MODULE_RESOURCE_BUNDLE_AVAILABLE\nx()\n#endif", "android", True),
        ("#if os(iOS)\nx()\n#elseif canImport(Algo)\ny()\n#endif", "ios", True),
        ("#if false\n#if hasFeature(Algo)\nx()\n#endif\n#endif", "ios", True),
        ("#if canImport(Algo)\nx()\n#endif", "ambas", True),
        ("#if os(iOS)\nx()\n#else\n#if canImport(Algo)\ny()\n#endif\n#endif", "ambas", True),
        ("x(); #if DEBUG\ny()\n#endif", "ios", True),
        ("#if DEBUG\nx()\n#else\ny()\n#endif", "ios", False),
        ("#if canImport(Darwin)\nx()\n#elseif canImport(Android)\ny()\n#endif", "ambas", False),
        ("#if os(Android) || !canImport(UIKit)\nx()\n#endif", "ambas", False),
        ('// #if Algo\n/* #if Algo */', "ios", False),
        # Decima segunda passada: fora do comeco da linha no texto sem comentario (ate dentro de texto), sem par, e nome
        # entre crases.
        ('let s = "#if Algo"', "ios", True),
        ("let a = c ?? /x/; #if DEBUG\ny()\n#endif", "ios", True),
        ("#endif", "ios", True),
        ("#if DEBUG\nx()", "ios", True),
        ("#if DEBUG\nx()\n#endif\n#else", "ios", True),
        ("func `a b`() {}", "ios", True),
        ("func `ab`() {}", "ios", False),
    ]
    casos_diretivas += [
        ("let x = Hex.encode(a)", "ios", False),
        ("enum `Hex` { }", "ios", True),
        ("enum\nHex { }", "ios", True),
        ("func f<Hex>(_ a: Hex) {}", "ios", True),
        ("func i(_ Hex: Int) {}", "ios", True),
        ("let f = { Hex in 1 }", "ios", True),
        ("for Hash in xs {}", "ios", True),
        ("let (SecureRandom, b) = (1, 2)", "ios", True),
        ("let s: SecureBytes = try SecureBytes(count: 2)", "ios", False),
        ("func g<SecureBytes: Sequence>() {}", "ios", True),
        ("func j(rotulo SecureBytes: Int) {}", "ios", True),
        ("struct `SecureBytes` {}", "ios", True),
        ("let f = { (a, SecureBytes) in 1 }", "ios", True),
        ('let s = "Hex invalido"', "ios", False),
    ]
    with tempfile.TemporaryDirectory() as pasta:
        for indice, (fonte, plataforma, acha) in enumerate(casos_diretivas):
            caminho = os.path.join(pasta, f"diretiva{indice}.swift")
            open(caminho, "w", encoding="utf-8").write(fonte)
            if bool(diretivas(caminho, plataforma)) != acha:
                erros.append(f"diretiva {indice} ({plataforma}): {fonte!r} devia {'acusar' if acha else 'passar'}")
    for erro in erros:
        print(erro)
    return 1 if erros else 0


def exige(caminho, trecho, plataforma):
    """O trecho existe como codigo: no arquivo sem comentario, e no mesmo lugar do arquivo vivo igual ao proprio
    trecho lido vivo. Um trecho que so existe dentro de texto entre aspas, ou com outro texto dentro das aspas dele,
    nao conta (sexta passada da auditoria de 03/11/2026: os tres `check` do Gradle dentro de aspas triplas passavam)."""
    cru, vivo = ler(caminho, False, plataforma), ler(caminho, True, plataforma)
    if caminho.endswith(SHELL):
        # No shell e no yml, o codigo vivo e o proprio texto (aspas inclusive): o trecho tem de estar igual no vivo.
        esperado = trecho
    else:
        with tempfile.TemporaryDirectory() as pasta:
            avulso = os.path.join(pasta, "trecho" + os.path.splitext(caminho)[1])
            open(avulso, "w", encoding="utf-8").write(trecho)
            esperado = ler(avulso, True, plataforma)
    k = cru.find(trecho)
    while k >= 0:
        if vivo[k:k + len(trecho)] == esperado:
            return True
        k = cru.find(trecho, k + 1)
    return False


def main():
    if sys.argv[1:2] == ["--testes"]:
        return testes()
    if sys.argv[1:2] == ["--diretivas"]:
        # Sem arquivo nenhum, ou com outra plataforma, falha: a regra nao confere o vazio.
        resto = sys.argv[2:]
        if len(resto) < 3 or resto[0] != "--plataforma" or resto[1] not in ("ios", "android", "ambas"):
            return 2
        problemas = []
        for caminho in resto[2:]:
            try:
                problemas += diretivas(caminho, resto[1])
            except (OSError, UnicodeDecodeError):
                problemas.append(f"{caminho}: nao foi lido")
        for problema in problemas:
            print(problema)
        return 1 if problemas else 0
    if sys.argv[1:2] == ["--exige"] and len(sys.argv) >= 4:
        plataforma = sys.argv[sys.argv.index("--plataforma") + 1] if "--plataforma" in sys.argv[4:] else "ios"
        # Plataforma que o leitor nao conhece (vazia, por um `$( )` que o shell nao leu) falha, e nao vira outra coisa.
        if plataforma not in MODULOS and plataforma != "ambas":
            return 2
        try:
            return 0 if exige(sys.argv[2], sys.argv[3], plataforma) else 1
        except OSError:
            return 1
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    plataforma = sys.argv[sys.argv.index("--plataforma") + 1] if "--plataforma" in sys.argv[2:] else "ios"
    if plataforma not in MODULOS and plataforma != "ambas":
        return 2
    try:
        texto = ler(sys.argv[1], vivo="--vivo" in sys.argv[2:], plataforma=plataforma)
    except OSError:
        return 1
    try:
        sys.stdout.write(texto)
        sys.stdout.flush()
    except BrokenPipeError:
        os._exit(0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
