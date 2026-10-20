#!/usr/bin/env python3
"""Os textos do app Android que nao tem traducao.

Cada t("...") do Kotlin, e cada Textos.t("...") do nucleo do Android, procura a frase em portugues no catalogo do iOS
(App/EscaliburWallet/Resources/Localizable.xcstrings) e, se nao achar, na tabela do Android
(Android/app/textos-android.json). Este script lista as frases que nao estao em nenhum dos dois,
e as da tabela do Android sem algum dos idiomas do app.

    tools/android/textos.py            lista o que falta
    tools/android/textos.py --json     o mesmo, em JSON (para preencher a tabela)

Sai com 1 se faltar alguma coisa.
"""
import json
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
IDIOMAS = ["en", "es", "fr", "de", "hi", "id", "ja", "ko", "tr", "zh-Hans", "vi", "ar"]

catalogo = json.loads((RAIZ / "App/EscaliburWallet/Resources/Localizable.xcstrings").read_text())["strings"]
tabela = json.loads((RAIZ / "Android/app/textos-android.json").read_text())

# t("...") com a frase literal: aspas duplas, com escapes do Kotlin.
padrao = re.compile(r'\bt\(\s*"((?:[^"\\$]|\\.)*)"')
chaves = {}
for arquivo in sorted((RAIZ / "Android/app/src/main/java").rglob("*.kt")):
    for numero, linha in enumerate(arquivo.read_text().splitlines(), 1):
        for achado in padrao.finditer(linha):
            chave = achado.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8")
            chaves.setdefault(chave, f"{arquivo.relative_to(RAIZ)}:{numero}")

# Textos.t("...") do nucleo do Android (Swift): a mesma tabela, passada pelo "iniciar".
padrao_swift = re.compile(r'\bTextos\.t\(\s*"((?:[^"\\]|\\.)*)"')
for arquivo in sorted((RAIZ / "Kit/Sources/Android").rglob("*.swift")):
    for numero, linha in enumerate(arquivo.read_text().splitlines(), 1):
        for achado in padrao_swift.finditer(linha):
            chaves.setdefault(achado.group(1).replace('\\"', '"'), f"{arquivo.relative_to(RAIZ)}:{numero}")

faltando = {chave: onde for chave, onde in chaves.items() if chave not in catalogo and chave not in tabela}
incompletas = {chave: [i for i in IDIOMAS if i not in valor] for chave, valor in tabela.items()
               if not chave.startswith("_") and isinstance(valor, dict) and any(i not in valor for i in IDIOMAS)}
# Do catalogo do iOS, as que existem mas sem algum idioma (adiadas pelo dono): so informativo.
sem_traducao = sorted(chave for chave in chaves if chave in catalogo
                      and any(i not in catalogo[chave].get("localizations", {}) for i in ["en"]))

if "--json" in sys.argv:
    print(json.dumps({"faltando": faltando, "incompletas": incompletas}, ensure_ascii=False, indent=2))
else:
    for chave, onde in sorted(faltando.items(), key=lambda x: x[1]):
        print(f"falta  {onde}  {chave}")
    for chave, idiomas in incompletas.items():
        print(f"sem {','.join(idiomas)}  {chave}")
    print(f"{len(chaves)} textos; {len(faltando)} sem traducao; {len(incompletas)} incompletos na tabela do Android"
          + (f"; {len(sem_traducao)} do iOS sem ingles" if sem_traducao else ""))
sys.exit(1 if faltando or incompletas else 0)
