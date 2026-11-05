#!/usr/bin/env python3
"""As flags do Swift que o Kit/Package.swift define, lidas do pacote avaliado pelo SwiftPM (o JSON do
`swift package dump-package` na entrada): `define` so CRYPTO_IN_SWIFTPM, e so nos alvos da swift-crypto; fora disso,
so as tres features de hoje, nos mesmos alvos. E o manifesto sem `#if`, sem leitura de ambiente, sem `Context` (o
caminho do pacote, o git) e sem outro import, fora a linha do nucleo do Android: um `#if compiler(...)`, uma variavel so
do build do Android ou um `Context.packageDirectory` com o caminho da copia da loja mudavam as flags so la (oitava e nona
passadas da auditoria de 03/11/2026). O tools/codigo.py (`flags_do_alvo`) supoe exatamente isto. Os scripts da loja
rodam este mesmo conferidor na copia limpa, no caminho de verdade do build.

Decima passada: o manifesto e lido como o Swift le, com o texto entre aspas e o comentario a parte (um `"//"` escondia
o `import Darwin` do resto da linha), sem `;`, sem `#`, sem aspas triplas nem interpolacao, e sem nome que faca a
avaliacao mudar entre a conferencia e o build (sorteio, hora, processo, arquivo); e o pacote sem traits, sem
dependencia, sem plugin, macro ou binario, com os alvos dentro de Sources/ e Tests/, na versao 6.0.0 das ferramentas, e
nenhum ajuste do Swift com condicao.

    swift package dump-package | python3 -I tools/flags-do-pacote.py Kit/Package.swift
    python3 -I tools/flags-do-pacote.py --testes
"""
import json, re, sys

PERMITIDAS = {"import class Foundation.ProcessInfo", 'if ProcessInfo.processInfo.environment["ESCALIBUR_ANDROID"] != nil {'}
IMPORTS = {"import PackageDescription", "import class Foundation.ProcessInfo"}
PROIBIDOS = re.compile(r"\b(ProcessInfo|environment|getenv|setenv|CommandLine|Context|FileManager|FileHandle|contentsOf|"
                       r"fileURLWithPath|URL|Bundle|Process|random|Random|Date|UUID|arc4random\w*|time|clock\w*|Thread|"
                       r"Dispatch\w*|dlopen|dlsym|unsafeBitCast|withUnsafe\w*|Darwin|Glibc|Foundation)\b")
# Os ajustes do C, do C++ e do linker de hoje, cada um com a condicao, e nenhum outro (decima segunda passada da auditoria
# de 03/11/2026): um `.define("FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION")` no C da BoringSSL deixava o sorteio dela
# deterministico no Android, de onde sai a frase, e um `-Xlinker --wrap` no linker trocava uma funcao inteira.
AJUSTES_DO_C = {
    "[\"CArgon2\", \"c\", \"define\", \"_FORTIFY_SOURCE=2\", {\"platformNames\": [\"android\", \"linux\"]}]",
    "[\"CArgon2\", \"c\", \"headerSearchPath\", \".\", null]",
    "[\"CArgon2\", \"c\", \"unsafeFlags\", [\"-O3\", \"-ftrivial-auto-var-init=zero\", \"-ftyped-memory-operations\"], {\"platformNames\": [\"ios\", \"macos\"]}]",
    "[\"CCryptoBoringSSL\", \"c\", \"define\", \"_FORTIFY_SOURCE=2\", {\"platformNames\": [\"android\", \"linux\"]}]",
    "[\"CCryptoBoringSSL\", \"cxx\", \"define\", \"_FORTIFY_SOURCE=2\", {\"platformNames\": [\"android\", \"linux\"]}]",
    "[\"CSecp256k1\", \"c\", \"define\", \"COMB_BLOCKS=43\", null]",
    "[\"CSecp256k1\", \"c\", \"define\", \"COMB_TEETH=6\", null]",
    "[\"CSecp256k1\", \"c\", \"define\", \"ECMULT_WINDOW_SIZE=15\", null]",
    "[\"CSecp256k1\", \"c\", \"define\", \"ENABLE_MODULE_EXTRAKEYS=1\", null]",
    "[\"CSecp256k1\", \"c\", \"define\", \"ENABLE_MODULE_RECOVERY=1\", null]",
    "[\"CSecp256k1\", \"c\", \"define\", \"ENABLE_MODULE_SCHNORRSIG=1\", null]",
    "[\"CSecp256k1\", \"c\", \"define\", \"_FORTIFY_SOURCE=2\", {\"platformNames\": [\"android\", \"linux\"]}]",
    "[\"CSecp256k1\", \"c\", \"headerSearchPath\", \"upstream\", null]",
    "[\"CSecp256k1\", \"c\", \"headerSearchPath\", \"upstream/src\", null]",
    "[\"CSecp256k1\", \"c\", \"unsafeFlags\", [\"-ftrivial-auto-var-init=zero\", \"-ftyped-memory-operations\"], {\"platformNames\": [\"ios\", \"macos\"]}]",
    "[\"CXKCP\", \"c\", \"define\", \"XKCP_has_KeccakP1600\", null]",
    "[\"CXKCP\", \"c\", \"define\", \"_FORTIFY_SOURCE=2\", {\"platformNames\": [\"android\", \"linux\"]}]",
    "[\"CXKCP\", \"c\", \"headerSearchPath\", \"common\", null]",
    "[\"CXKCP\", \"c\", \"headerSearchPath\", \"high\", null]",
    "[\"CXKCP\", \"c\", \"headerSearchPath\", \"include\", null]",
    "[\"CXKCP\", \"c\", \"headerSearchPath\", \"low\", null]",
    "[\"CXKCP\", \"c\", \"headerSearchPath\", \"low/KeccakP-1600\", null]",
    "[\"CXKCP\", \"c\", \"headerSearchPath\", \"low/common\", null]",
    "[\"CXKCPShims\", \"c\", \"define\", \"_FORTIFY_SOURCE=2\", {\"platformNames\": [\"android\", \"linux\"]}]",
}
# O que cada alvo exclui e compila: os do C e da swift-crypto como hoje, e nenhum outro com `exclude` ou `sources`: um
# arquivo de trava tirado do alvo seguia lido pelas regras (decima segunda passada).
ARQUIVOS = {"CArgon2": {"exclude": ["LICENSE.txt"], "sources": ["argon2.c", "core.c", "encoding.c", "ref.c", "thread.c", "blake2/blake2b.c", "escalibur_blake2b.c"]}, "CCryptoBoringSSL": {"exclude": ["hash.txt", "CMakeLists.txt", "PrivacyInfo.xcprivacy", "crypto/bio/connect.cc", "crypto/bio/socket_helper.cc", "crypto/bio/socket.cc"], "sources": None}, "CSecp256k1": {"exclude": ["upstream/COPYING"], "sources": ["upstream/src/secp256k1.c", "upstream/src/precomputed_ecmult.c", "upstream/src/precomputed_ecmult_gen.c"]}, "CXKCP": {"exclude": ["CMakeLists.txt", "PrivacyInfo.xcprivacy", "vendored-sources.txt"], "sources": None}, "CXKCPShims": {"exclude": ["CMakeLists.txt", "PrivacyInfo.xcprivacy"], "sources": None}, "Crypto": {"exclude": ["vendored-sources.txt", "CMakeLists.txt", "PrivacyInfo.xcprivacy", "Signatures/BoringSSL/MLDSA_boring.swift.gyb", "KEM/BoringSSL/MLKEM_boring.swift.gyb"], "sources": None}, "CryptoBoringWrapper": {"exclude": ["CMakeLists.txt", "PrivacyInfo.xcprivacy"], "sources": None}}
CRIPTO = ("Crypto", "CryptoBoringWrapper")
FEATURES = {("enableExperimentalFeature", "Lifetimes"), ("enableExperimentalFeature", "SourceWarningControl"),
            ("enableUpcomingFeature", "MemberImportVisibility")}


def ler(manifesto):
    """O manifesto em duas leituras: sem comentario (o texto fica) e sem comentario nem texto. None quando tem o que
    este leitor nao le: aspas triplas, texto com `\\(` ou que atravessa a linha, ou comentario que nao fecha."""
    sem_comentario, vivo, i, n = list(manifesto), list(manifesto), 0, len(manifesto)

    def branco(lista, a, b):
        for k in range(a, b):
            if lista[k] != "\n":
                lista[k] = " "

    while i < n:
        if manifesto.startswith("//", i):
            fim = manifesto.find("\n", i)
            fim = n if fim < 0 else fim
            branco(sem_comentario, i, fim)
            branco(vivo, i, fim)
            i = fim
        elif manifesto.startswith("/*", i):
            profundidade, j = 1, i + 2
            while j < n and profundidade:
                if manifesto.startswith("/*", j):
                    profundidade, j = profundidade + 1, j + 2
                elif manifesto.startswith("*/", j):
                    profundidade, j = profundidade - 1, j + 2
                else:
                    j += 1
            if profundidade:
                return None
            branco(sem_comentario, i, j)
            branco(vivo, i, j)
            i = j
        elif manifesto[i] == '"':
            if manifesto.startswith('"""', i):
                return None
            j = i + 1
            while j < n and manifesto[j] not in '"\n':
                if manifesto[j] == "\\":
                    if manifesto.startswith("\\(", j) or manifesto[j + 1:j + 2] in ("", "\n"):
                        return None
                    j += 2
                else:
                    j += 1
            if j >= n or manifesto[j] != '"':
                return None
            branco(vivo, i + 1, j)
            i = j + 1
        else:
            i += 1
    return "".join(sem_comentario), "".join(vivo)


def manifesto_certo(manifesto):
    lidos = ler(manifesto)
    if lidos is None:
        return False
    for com_texto, vivo in zip(lidos[0].split("\n"), lidos[1].split("\n")):
        linha = com_texto.strip()
        if ";" in vivo or "#" in vivo:
            return False
        if linha in PERMITIDAS:
            continue
        if re.search(r"\bimport\b", vivo) and linha not in IMPORTS:
            return False
        if PROIBIDOS.search(vivo):
            return False
    return True


def pacote_certo(pacote, ajustes_do_c=None, arquivos=None):
    ajustes_do_c = AJUSTES_DO_C if ajustes_do_c is None else ajustes_do_c
    arquivos = ARQUIVOS if arquivos is None else arquivos
    if pacote.get("toolsVersion") != {"_version": "6.0.0"} or pacote.get("traits", []) != [] or pacote.get("dependencies") != []:
        return False
    if not pacote.get("targets"):
        return False
    vistos_do_c = set()
    for alvo in pacote["targets"]:
        nome, tipo_do_alvo = alvo.get("name") or "", alvo.get("type")
        if tipo_do_alvo not in ("regular", "test") or alvo.get("pluginUsages") or alvo.get("pluginCapability") \
                or alvo.get("url") or alvo.get("checksum"):
            return False
        caminho = alvo.get("path") or ("Tests/" if tipo_do_alvo == "test" else "Sources/") + nome
        if not re.fullmatch(r"(Sources|Tests)/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*", caminho) or ".." in caminho.split("/"):
            return False
        esperado = arquivos.get(nome, {"exclude": [], "sources": None})
        if (alvo.get("exclude") or []) != esperado["exclude"] or alvo.get("sources") != esperado["sources"]:
            return False
        for ajuste in alvo.get("settings", []):
            if ajuste.get("tool") != "swift":
                tipos = ajuste.get("kind") or {}
                if len(tipos) != 1:
                    return False
                tipo = next(iter(tipos))
                chave = json.dumps([nome, ajuste.get("tool"), tipo, (tipos[tipo] or {}).get("_0"), ajuste.get("condition")], sort_keys=True)
                if chave not in ajustes_do_c:
                    return False
                vistos_do_c.add(chave)
                continue
            tipos = ajuste.get("kind") or {}
            if ajuste.get("condition") or len(tipos) != 1:
                return False
            tipo = next(iter(tipos))
            valor = (tipos[tipo] or {}).get("_0")
            if not isinstance(valor, str) or nome not in CRIPTO or not caminho.startswith("Sources/SwiftCrypto/"):
                return False
            if tipo == "define":
                if valor != "CRYPTO_IN_SWIFTPM":
                    return False
            elif (tipo, valor) not in FEATURES:
                return False
    # Todos, e nao so nenhum a mais: tirar o _FORTIFY_SOURCE ou a pilha zerada tambem muda o binario.
    return vistos_do_c == ajustes_do_c


def testes():
    erros = []
    manifestos = [
        ('import PackageDescription\nlet p = Package(name: "a // b", targets: [])', True),
        ('import PackageDescription\nimport class Foundation.ProcessInfo\n'
         'if ProcessInfo.processInfo.environment["ESCALIBUR_ANDROID"] != nil {\n}', True),
        ('import PackageDescription\nlet s = "//"; import Darwin', False),
        ('import PackageDescription\nlet s = "//"\nimport Darwin', False),
        ('import PackageDescription\n/* */ import Darwin', False),
        ('import PackageDescription\nlet ligar = Bool.random()', False),
        ('import PackageDescription\nlet s = #"a"#', False),
        ('import PackageDescription\n#if compiler(>=6.4)\n#endif', False),
        ('import PackageDescription\nlet s = """\na\n"""', False),
        ('import PackageDescription\nlet s = "\\(1)"', False),
        ('import PackageDescription\nlet s = "a', False),
        ('import PackageDescription\n/* aberto', False),
        ('import PackageDescription\nlet d = Context.packageDirectory', False),
        ('import PackageDescription\nlet s = "a" ; let t = 1', False),
    ]
    for indice, (fonte, certo) in enumerate(manifestos):
        if manifesto_certo(fonte) != certo:
            erros.append(f"manifesto {indice}: {fonte!r} devia {'passar' if certo else 'ser recusado'}")
    base = {"toolsVersion": {"_version": "6.0.0"}, "traits": [], "dependencies": [], "targets": [
        {"name": "Crypto", "type": "regular", "path": "Sources/SwiftCrypto/Crypto", "settings": [
            {"tool": "swift", "kind": {"define": {"_0": "CRYPTO_IN_SWIFTPM"}}},
            {"tool": "swift", "kind": {"enableUpcomingFeature": {"_0": "MemberImportVisibility"}}}]},
        {"name": "EscaliburCore", "type": "regular", "path": "Sources/EscaliburCore", "settings": []},
        {"name": "EscaliburCoreTests", "type": "test", "path": None, "settings": []}]}

    def variante(mudar):
        pacote = json.loads(json.dumps(base))
        mudar(pacote)
        return pacote

    pacotes = [
        (base, True),
        (variante(lambda p: p.update(traits=[{"name": "Extra", "enabledTraits": []}])), False),
        (variante(lambda p: p.update(toolsVersion={"_version": "6.1.0"})), False),
        (variante(lambda p: p.update(dependencies=[{"sourceControl": [{}]}])), False),
        (variante(lambda p: p["targets"].append({"name": "Gerador", "type": "plugin", "path": "Sources/Gerador"})), False),
        (variante(lambda p: p["targets"].append({"name": "Macros", "type": "macro", "path": "Sources/Macros"})), False),
        (variante(lambda p: p["targets"].append({"name": "Bin", "type": "binary", "url": "https://x", "checksum": "0"})), False),
        (variante(lambda p: p["targets"][1].update(pluginUsages=[{"plugin": ["Gerador", None]}])), False),
        (variante(lambda p: p["targets"][1].update(path="../App/EscaliburWallet")), False),
        (variante(lambda p: p["targets"][0]["settings"].append({"tool": "swift", "kind": {"define": {"_0": "FOO"}}})), False),
        (variante(lambda p: p["targets"][1]["settings"].append({"tool": "swift", "kind": {"define": {"_0": "CRYPTO_IN_SWIFTPM"}}})), False),
        (variante(lambda p: p["targets"][0]["settings"].append({"tool": "swift", "kind": {"enableExperimentalFeature": {"_0": "Embedded"}}})), False),
        (variante(lambda p: p["targets"][0]["settings"][0].update(condition={"config": "debug"})), False),
        (variante(lambda p: p["targets"][0]["settings"].append({"tool": "swift", "kind": {"unsafeFlags": {"_0": ["-DFOO"]}}})), False),
        (variante(lambda p: p.update(targets=[])), False),
    ]
    # O C por lista fechada, e os arquivos de cada alvo (decima segunda passada).
    c_de_teste = {json.dumps(["CSecp256k1", "c", "define", "COMB_TEETH=6", None], sort_keys=True)}
    secp = {"name": "CSecp256k1", "type": "regular", "path": "Sources/CSecp256k1", "sources": ["a.c"],
            "settings": [{"tool": "c", "kind": {"define": {"_0": "COMB_TEETH=6"}}}]}
    arquivos_de_teste = {"CSecp256k1": {"exclude": [], "sources": ["a.c"]}}
    com_c = [
        (variante(lambda p: p["targets"].append(json.loads(json.dumps(secp)))), True),
        (variante(lambda p: p["targets"].append(dict(json.loads(json.dumps(secp)), settings=secp["settings"] + [
            {"tool": "c", "kind": {"define": {"_0": "FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"}}}]))), False),
        (variante(lambda p: p["targets"].append(dict(json.loads(json.dumps(secp)), settings=secp["settings"] + [
            {"tool": "linker", "kind": {"unsafeFlags": {"_0": ["-Xlinker", "--wrap=RAND_bytes"]}}}]))), False),
        (variante(lambda p: p["targets"].append(dict(json.loads(json.dumps(secp)), settings=[]))), False),
        (variante(lambda p: p["targets"].append(dict(json.loads(json.dumps(secp)), sources=["a.c", "b.c"]))), False),
        (variante(lambda p: p["targets"][1].update(exclude=["HTTPClient.swift"])), False),
        (variante(lambda p: p["targets"][1].update(sources=["BIP39"])), False),
    ]
    for indice, (pacote, certo) in enumerate(com_c):
        if pacote_certo(pacote, c_de_teste, arquivos_de_teste) != certo:
            erros.append(f"pacote com C {indice} devia {'passar' if certo else 'ser recusado'}")
    for indice, (pacote, certo) in enumerate(pacotes):
        if pacote_certo(pacote, set(), {}) != certo:
            erros.append(f"pacote {indice} devia {'passar' if certo else 'ser recusado'}")
    for erro in erros:
        print(erro)
    return 1 if erros else 0


def main():
    if sys.argv[1:] == ["--testes"]:
        return testes()
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    try:
        manifesto = open(sys.argv[1], encoding="utf-8").read()
        pacote = json.load(sys.stdin)
    except Exception:
        return 1
    # Um JSON com outra forma (o que devia ser lista nao e) e recusado, e nao aceito por erro.
    try:
        return 0 if manifesto_certo(manifesto) and pacote_certo(pacote) else 1
    except Exception:
        return 1


if __name__ == "__main__":
    sys.exit(main())
