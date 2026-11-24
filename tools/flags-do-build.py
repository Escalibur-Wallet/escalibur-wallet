#!/usr/bin/env python3
"""As flags que o compilador do Swift recebeu de fato no build da loja, lidas do log do build (o `xcodebuild` sem
`-quiet`, o `swift build -v` do nucleo do Android). O manifesto podia se avaliar de um jeito na conferencia
(tools/flags-do-pacote.py) e de outro no build, e o verificador so via a conferencia (decima passada da auditoria de
03/11/2026). Cada chamada do `swiftc` que compila fonte do Swift, com os arquivos de resposta (`@arquivo`) que ela le:

- o compilador e o do toolchain do build, pelo caminho resolvido, na versao que o tools/codigo.py usa para ler os `#if`
  (um `SWIFT_EXEC` com um `swiftc` de outra pasta punha as flags que quisesse);
- toda opcao esta numa lista fechada, a das que os builds de hoje passam, e a que leva valor consome o seguinte: uma
  opcao nova, ou um nome de opcao escondido como valor de outra, recusa a chamada (decima primeira passada);
- o modulo e um dos que o tools/codigo.py conhece, e os `-D` sao so os dele: nenhum no app; no Kit e no nucleo do
  Android, SWIFT_PACKAGE e os que o SwiftPM e o Xcode poem sozinhos (que o leitor trata como desconhecidos, e que por
  isso nenhum `#if` nosso usa); CRYPTO_IN_SWIFTPM e as features da swift-crypto so nela;
- o alvo e o aparelho da plataforma, o modo da linguagem e o 6 e a otimizacao e o `-O`, com as checagens;
- caminho de busca e de recurso (que decide o `canImport`) so do toolchain, da pasta deste build e das pastas `include`
  do C do Kit; plugin de macro so do toolchain; o que o build grava, so na pasta dele;
- cada fonte e da pasta do proprio modulo (que o verificador le) ou uma das duas geradas, no lugar dela na pasta do
  build; e todo .swift rastreado dessas pastas e compilado (um arquivo de trava tirado do build continuava lido pelas
  regras, com outro sem a trava compilado no lugar; decima segunda passada);
- arquivo de resposta so da pasta do build, com um caminho simples por linha (sem aspas, barra invertida nem
  comentario, que o compilador e este leitor partiriam de jeitos diferentes);
- uma linha com pedaco de chamada do compilador que nao e uma chamada inteira (a saida cortada por outra) falha;
- cada compilacao do C de um alvo nosso (o clang, com os arquivos de resposta) so com os `-D` da lista do alvo, sem
  `-U`, `-include`, `-Xclang`, plugin, `-O0` nem protetor de pilha desligado, e com os caminhos de busca no toolchain,
  na pasta do build e nas pastas do C do Kit; e nenhuma chamada do compilador ou do linker com `--wrap`, `--defsym`,
  `-alias` ou script de link, que troca uma funcao inteira (decima segunda passada: o C, que segura a entropia das
  chaves, nao tinha lista nenhuma);
- todo modulo que a plataforma compila aparece ao menos uma vez: um log sem nenhuma chamada (o formato mudou, o build
  nao compilou nada) falha. Com `--parcial` (o build incremental de quem desenvolve), so as chamadas que houve.

Chamada sem fonte do Swift e sem modulo nosso (ligar, montar o modulo de um cabecalho do C ou do SDK, perguntar a
versao) nao compila codigo nosso e fica de fora.

    python3 -I tools/flags-do-build.py ios|android <log> --build <pasta do build> [--parcial]
    python3 -I tools/flags-do-build.py --testes
"""
import os, pwd, re, shlex, subprocess, sys, tempfile

RAIZ = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MANIFESTO = os.path.join(RAIZ, "Kit", "Package.swift")
APP = {"EscaliburWallet", "EscaliburWidgets"}
KIT = {"EscaliburCore", "EscaliburChains", "EscaliburKeys", "EscaliburNetwork", "EscaliburEngines"}
CRIPTO = {"Crypto", "CryptoBoringWrapper"}
NUCLEO = {"EscaliburAndroid"}
ESPERADOS = {"ios": APP | KIT, "android": KIT | CRIPTO | NUCLEO}
# As pastas de fonte de cada modulo: as mesmas que o verificar.sh le (`--diretivas` e as regras).
FONTES = {**{m: ["App/EscaliburWallet", "App/EscaliburWidgets", "App/Shared"] for m in APP},
          **{m: [f"Kit/Sources/{m}"] for m in KIT}, **{m: [f"Kit/Sources/SwiftCrypto/{m}"] for m in CRIPTO},
          "EscaliburAndroid": ["Kit/Sources/Android/EscaliburAndroid"]}
INCLUDES_DO_C = ["Kit/Sources/CArgon2/include", "Kit/Sources/CSecp256k1/include", "Kit/Sources/SwiftCrypto/CCryptoBoringSSL/include",
                 "Kit/Sources/SwiftCrypto/CXKCP/include", "Kit/Sources/SwiftCrypto/CXKCPShims/include", "Kit/Sources/Android/CJNI/include"]
AUTOMATICAS = {"Xcode", "SWIFT_MODULE_RESOURCE_BUNDLE_AVAILABLE", "SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE"}
ALVO = {"ios": r"arm64e?-apple-ios[0-9.]+", "android": r"aarch64-unknown-linux-android[0-9]+"}
# As fatias que cada modulo compila: as duas do iPhone, e a do Android (decima segunda passada).
FATIAS = {"ios": {"arm64", "arm64e"}, "android": {"aarch64"}}
# Uma tarefa do build que chama o compilador do Swift: o que vem depois do `--` tem de ser ele.
TAREFA_DO_SWIFT = re.compile(r"^\s*builtin-(SwiftDriver|Swift-Compilation|Swift-Compilation-Requirements|swiftTaskExecution)\s+--\s+(\S+)")
# O do Android: o Swift do tools/android/compilar-nucleo.sh, o Swift SDK dele e o NDK r30.
TOOLCHAIN_ANDROID = "~/Library/Developer/Toolchains/swift-6.4.1-RELEASE.xctoolchain"
SDK_ANDROID = ("~/Library/org.swift.swiftpm/swift-sdks/swift-6.4.1-RELEASE_android.artifactbundle", "~/Library/Android/android-ndk-r30")

# As opcoes que os builds de hoje passam, e nenhuma outra.
SEM_VALOR = {"-O", "-g", "-c", "-application-extension", "-emit-const-values", "-emit-dependencies", "-emit-localized-strings",
             "-emit-module", "-emit-objc-header", "-explicit-module-build", "-no-color-diagnostics", "-color-diagnostics",
             "-no-emit-module-separately-wmo", "-save-temps", "-serialize-diagnostics", "-serialize-debugging-options",
             "-use-frontend-parseable-output", "-validate-clang-modules-once", "-whole-module-optimization",
             "-parse-as-library", "-static-stdlib"}
LEITURA = {"-I", "-F", "-Isystem"}
# O SDK, o sysroot e os recursos do Swift: o caminho exato de cada build, e nao qualquer pasta do toolchain (o SDK do
# simulador com alvo de aparelho passava; decima segunda passada).
EXATOS = {"-sdk": "sdk", "-sysroot": "sdk", "-resource-dir": "recursos"}
PLUGINS = {"-plugin-path", "-external-plugin-path"}
DO_BUILD = {"-module-cache-path", "-sdk-module-cache-path", "-clang-scanner-module-cache-path", "-emit-module-path",
            "-emit-objc-header-path", "-emit-localized-strings-path", "-output-file-map", "-clang-build-session-file",
            "-const-gather-protocols-list"}
OUTRAS_COM_VALOR = {"-module-name", "-target", "-swift-version", "-num-threads", "-package-name", "-working-directory",
                    "-file-prefix-map", "-enable-experimental-feature", "-enable-upcoming-feature", "-D", "-Xcc", "-Xfrontend"}
# O que vai ao importador do C (`-Xcc`): os `-D` de hoje, os caminhos, e as opcoes fixas.
DEFINES_DO_C = {"SWIFT_PACKAGE", "_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST"}
C_FIXAS = {"-fno-omit-frame-pointer", "-fstack-protector-strong", "-ftrivial-auto-var-init=zero"}
C_COM_CAMINHO = {"-I": "leitura", "-iquote": "leitura", "-resource-dir": "leitura", "-ivfsoverlay": "build", "-ivfsstatcache": "build"}
# A opcao de valor unico aparece uma vez so: com duas, vale a ultima, e uma a mais no fim trocava o modo ou o alvo.
UNICAS = {"-module-name", "-target", "-swift-version", "-sdk", "-resource-dir", "-sysroot", "-package-name", "-working-directory",
          "-num-threads"}
# As fontes que o proprio build gera na pasta dele, cada uma so no seu modulo e no seu lugar: o acesso aos recursos do
# pacote (o EscaliburCore e o unico com recursos) e os simbolos do catalogo de imagens do app.
GERADAS = {"EscaliburCore": r"/EscaliburCore(-t)?\.build/DerivedSources/resource_bundle_accessor\.swift",
           "EscaliburWallet": r"/EscaliburWallet\.build/DerivedSources/GeneratedAssetSymbols\.swift"}
# Uma linha de arquivo de resposta: um caminho simples (decima segunda passada).
LINHA_DE_RESPOSTA = re.compile(r"[A-Za-z0-9_./+@=,-]*")
# Pedacos de chamada do compilador: numa linha que nao e uma chamada inteira, a saida foi cortada.
PEDACOS = re.compile(r"(^|\s)(-module-name|-Xfrontend|-swift-version|-emit-module-path|-plugin-path)\s|(^|\s)-Xcc\s+-")


# O C de cada alvo: a pasta dele e os `-D` que o Package.swift da (os mesmos do tools/flags-do-pacote.py), mais os que
# o SwiftPM e o Xcode poem sozinhos.
ALVOS_DO_C = {"CArgon2": "Kit/Sources/CArgon2", "CSecp256k1": "Kit/Sources/CSecp256k1",
              "CCryptoBoringSSL": "Kit/Sources/SwiftCrypto/CCryptoBoringSSL", "CXKCP": "Kit/Sources/SwiftCrypto/CXKCP",
              "CXKCPShims": "Kit/Sources/SwiftCrypto/CXKCPShims", "CJNI": "Kit/Sources/Android/CJNI"}
FORTIFY = {"_FORTIFY_SOURCE=2"}
DEFINES_DO_ALVO = {
    "CArgon2": FORTIFY, "CCryptoBoringSSL": FORTIFY, "CXKCPShims": FORTIFY, "CJNI": set(),
    "CXKCP": FORTIFY | {"XKCP_has_KeccakP1600"},
    "CSecp256k1": FORTIFY | {"ENABLE_MODULE_RECOVERY=1", "ENABLE_MODULE_EXTRAKEYS=1", "ENABLE_MODULE_SCHNORRSIG=1",
                             "ECMULT_WINDOW_SIZE=15", "COMB_BLOCKS=43", "COMB_TEETH=6"},
}
DEFINES_AUTOMATICOS_DO_C = {"SWIFT_PACKAGE", "Xcode"}
ALVOS_C_ESPERADOS = {"ios": {"CArgon2", "CSecp256k1"}, "android": {"CArgon2", "CSecp256k1", "CCryptoBoringSSL", "CXKCP", "CJNI"}}
# As opcoes que as compilacoes do C de hoje recebem, e nenhuma outra (decima terceira passada: a lista de proibidas
# deixava `--define-macro`, `-Wp,-D`, `--include=` e `-ftrivial-auto-var-init=uninitialized` passarem).
C_SEM_VALOR = {"-c", "-g", "-gmodules", "-fmodules", "-fmodules-validate-once-per-build-session", "-fno-color-diagnostics",
               "-fcolor-diagnostics", "-fpascal-strings", "-fstrict-aliasing", "-fdiagnostics-show-note-include-stack", "-MMD",
               "-fPIC", "-fblocks", "-fno-omit-frame-pointer", "-fstack-protector-strong", "-fvisibility-inlines-hidden",
               "-ftrivial-auto-var-init=zero", "-ftyped-memory-operations", "-fmacro-backtrace-limit=0", "-fmessage-length=0",
               "-Os", "-O3"}
C_COM_VALOR = {"-o": "build", "-MF": "build", "-MT": "qualquer", "-target": "alvo", "-x": "lingua", "-isysroot": "sdk",
               "--sysroot": "sdk", "-iframework": "leitura", "--serialize-diagnostics": "build", "-ivfsstatcache": "build"}
C_COM_IGUAL = {"-fbuild-session-file": "build", "-fmodule-name": "modulo", "-fmodules-cache-path": "build",
               "-fmodules-prune-after": "numero", "-fmodules-prune-interval": "numero", "-ffile-prefix-map": "mapa",
               "-fmodule-map-file": "leitura", "-std": "padrao"}
# O endurecimento de hoje tem de estar na chamada: no Android, a pilha zerada, o protetor de pilha e o FORTIFY (fora o CJNI,
# que nao o pede); no iPhone, a pilha zerada e o alocador por tipo no C vendorizado.
C_EXIGIDAS = {"android": {"-fstack-protector-strong", "-ftrivial-auto-var-init=zero"},
              "ios": {"-ftrivial-auto-var-init=zero", "-ftyped-memory-operations"}}
# O que troca uma funcao inteira no link, por qualquer grafia: nenhuma chamada a leva. E o que troca o linker, a pasta
# das ferramentas do driver ou carrega codigo no LTO, que tornaria as outras conferencias do link inuteis (revisao da
# decima terceira passada).
# As opcoes longas do lld valem com um traco ou com dois (revisao da decima terceira passada).
LINK_PROIBIDAS = re.compile(r"^(--?(wrap|defsym|script|undefined|undefined-glob|allow-multiple-definition|just-symbols|entry|"
                            r"export-dynamic-symbol|load-pass-plugin|plugin|plugin-opt|prefix|gcc-toolchain|gcc-install-dir)|"
                            r"-alias|-alias_list|-T|-sectalign|-z(muldefs)?|muldefs|-R|-u|-e|-init|-fini|-interposable|"
                            r"-interposable_list|-dylib_file|-reexport_library|-reexport-l\w*|-dyld_env|-tools-directory|"
                            r"-lto_library|-fpass-plugin|-mllvm|-Xllvm|-ccc-[a-z-]+|-fno-integrated-as|-no-integrated-as|"
                            r"-force_load|-load_hidden|-weak_library|-lazy_library|-upward_library|-weak-l\w*|-lazy-l\w*|"
                            r"-upward-l\w*|-needed_library|-needed-l\w*)([=,]|$)|^-B")
# As que dizem de onde vem o SDK: so o do build.
LINK_SDK = {"--sysroot", "-isysroot", "-syslibroot", "-sdk"}
# O linker que o driver escolhe: so o lld do NDK, so no Android (no iPhone, o ld do Xcode, sem opcao nenhuma).
LINKER_ESCOLHIDO = {"-fuse-ld": "nome", "-use-ld": "nome", "--ld-path": "caminho", "-ld-path": "caminho"}


def proibidas_no_link(args, plataforma, raizes, build=""):
    """As opcoes de link que trocam uma funcao, em qualquer grafia: cada pedaco de um `-Wl,` e cada valor de `-Xlinker`
    (decima terceira passada: so o primeiro pedaco do `-Wl,` era olhado). O `-z` so passa com os valores de hoje, o
    linker so o lld do NDK no Android e a pasta de recursos do linker so a do toolchain."""
    pedacos = []
    k = 0
    while k < len(args):
        arg = args[k]
        if arg.startswith("-Wl,"):
            pedacos += arg[4:].split(",")
        elif arg in ("-Xlinker", "-Xclang-linker", "-Xcc", "--for-linker") and k + 1 < len(args):
            pedacos.append(args[k + 1])
            k += 1
        elif arg.startswith("--for-linker="):
            pedacos.append(arg[len("--for-linker="):])
        else:
            pedacos.append(arg)
        k += 1
    ruins = []
    for k, pedaco in enumerate(pedacos):
        valor = pedacos[k + 1] if k + 1 < len(pedacos) else ""
        if pedaco == "-z":
            if valor not in ("now", "relro", "noexecstack", "max-page-size=16384", "nostart-stop-gc"):
                ruins.append(f"-z {valor}")
        elif pedaco == "-e":
            # O ponto de entrada so o da extensao do widget.
            if valor != "_NSExtensionMain":
                ruins.append(f"-e {valor}")
        elif pedaco.partition("=")[0] in LINKER_ESCOLHIDO:
            nome, igual, escolhido = pedaco.partition("=")
            escolhido = escolhido if igual else valor
            lld = os.path.realpath(os.path.join(casa(SDK_ANDROID[1]), "toolchains/llvm/prebuilt/darwin-x86_64/bin/ld.lld"))
            certo = escolhido == "lld" if LINKER_ESCOLHIDO[nome] == "nome" else os.path.isabs(escolhido) and os.path.realpath(escolhido) == lld
            if plataforma != "android" or not certo:
                ruins.append(f"{nome} {escolhido}")
        elif pedaco.partition("=")[0] == "-resource-dir":
            nome, igual, pasta_de_recursos = pedaco.partition("=")
            pasta_de_recursos = pasta_de_recursos if igual else valor
            if not de_dentro(pasta_de_recursos, raizes["leitura"]):
                ruins.append(f"-resource-dir {pasta_de_recursos}")
        elif pedaco.partition("=")[0] in LINK_SDK:
            nome, igual, sdk = pedaco.partition("=")
            sdk = sdk if igual else valor
            if not (os.path.isabs(sdk) and os.path.realpath(sdk) in raizes["sdk"]):
                ruins.append(f"{nome} {sdk}")
        elif pedaco in ("-L", "-F") or (pedaco[:2] in ("-L", "-F") and len(pedaco) > 2 and not pedaco.startswith("-Lazy")):
            # As pastas de biblioteca e de framework: so do toolchain, do SDK, do build e a /usr/lib/swift do SDK.
            busca = valor if pedaco in ("-L", "-F") else pedaco[2:]
            if busca != "/usr/lib/swift" and not de_dentro(busca, tuple(raizes["leitura"]) + tuple(raizes["sdk"]) + ((build,) if build else ())):
                ruins.append(f"{pedaco[:2]} {busca}")
        elif not pedaco.startswith("-") and os.path.isabs(pedaco) and re.search(r"\.(o|a|so|dylib|tbd)$", pedaco):
            # Um objeto ou biblioteca de entrada so do toolchain, do SDK e do build (o relativo e da copia limpa, que nao
            # rastreia binario nenhum).
            if not de_dentro(pedaco, tuple(raizes["leitura"]) + tuple(raizes["sdk"]) + ((build,) if build else ())):
                ruins.append(f"entrada {pedaco}")
        elif LINK_PROIBIDAS.match(pedaco):
            ruins.append(pedaco)
    return ruins


def features(modulo):
    experimentais = {"DebugDescriptionMacro"} | ({"Lifetimes", "SourceWarningControl"} if modulo in CRIPTO else set())
    return experimentais, {"MemberImportVisibility"} if modulo in CRIPTO else set()


def permitidas(modulo):
    if modulo in APP:
        return set()
    if modulo in CRIPTO:
        return {"SWIFT_PACKAGE", "CRYPTO_IN_SWIFTPM"} | AUTOMATICAS
    if modulo in KIT | NUCLEO:
        return {"SWIFT_PACKAGE"} | AUTOMATICAS
    return None


def casa(caminho):
    """O `~` pela pasta do usuario no sistema, e nao pelo HOME do ambiente (revisao da decima terceira passada)."""
    return pwd.getpwuid(os.getuid()).pw_dir + caminho[1:] if caminho.startswith("~/") else caminho


def pasta(caminho):
    return os.path.realpath(casa(caminho)) + "/"


def raizes_do(plataforma):
    """O toolchain de cada build: o Xcode ativo (o `xcode-select -p`, o mesmo do xcodebuild), e o Swift aberto do
    Android. Com o caminho resolvido, e com a barra no fim (`/Xcode.app2` nao e `/Xcode.app`)."""
    if plataforma == "ios":
        # So o toolchain do Xcode e a plataforma do iPhone, e nao a pasta Developer inteira (decima segunda passada).
        xcode = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True, check=True).stdout.strip()
        toolchain = pasta(os.path.join(xcode, "Toolchains", "XcodeDefault.xctoolchain"))
        sdk = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], capture_output=True, text=True, check=True).stdout.strip()
        return {"compilador": (toolchain,), "leitura": (toolchain, pasta(os.path.join(xcode, "Platforms", "iPhoneOS.platform"))),
                "sdk": {os.path.realpath(sdk)}, "recursos": set()}
    ndk, artefato = (casa(p) for p in SDK_ANDROID[::-1])
    return {"compilador": (pasta(TOOLCHAIN_ANDROID),), "leitura": (pasta(TOOLCHAIN_ANDROID),) + tuple(pasta(p) for p in SDK_ANDROID),
            "sdk": {os.path.realpath(os.path.join(ndk, "toolchains/llvm/prebuilt/darwin-x86_64/sysroot"))},
            "recursos": {os.path.realpath(os.path.join(artefato, "swift-android/swift-resources/usr/lib/swift_static-aarch64"))}}


def de_dentro(caminho, raizes):
    return bool(caminho) and os.path.isabs(caminho) and (os.path.realpath(caminho) + "/").startswith(tuple(raizes))


def versao_do_codigo(plataforma):
    """A versao do Swift com que o tools/codigo.py le os `#if` desta plataforma (VERSAO_SWIFT, lida do texto)."""
    texto = open(os.path.join(RAIZ, "tools", "codigo.py"), encoding="utf-8").read()
    m = re.search(r'^VERSAO_SWIFT = \{"ios": \((\d+), (\d+), (\d+)\), "android": \((\d+), (\d+), (\d+)\)\}$', texto, re.M)
    if not m:
        return None
    return tuple(int(x) for x in (m.groups()[:3] if plataforma == "ios" else m.groups()[3:]))


def versao_do_compilador(compilador):
    saida = subprocess.run([compilador, "--version"], capture_output=True, text=True).stdout + ""
    m = re.search(r"Swift version (\d+)\.(\d+)(?:\.(\d+))?", saida)
    return tuple(int(x or 0) for x in m.groups()) if m else None


def chamada_do_c(linha):
    """O clang e os argumentos dele numa linha do log, ou None se a linha nao chama um."""
    if "clang" not in linha:
        return None
    try:
        partes = shlex.split(linha)
    except ValueError:
        return "", []
    # O compilador e o primeiro da linha, ou o que vem logo depois do `--` de uma tarefa; um caminho que termina em `/clang`
    # no meio dos argumentos (um `-o .../clang`) nao e (revisao da decima terceira passada).
    posicoes = [0] + ([partes.index("--") + 1] if "--" in partes else [])
    for k in posicoes:
        if k < len(partes) and os.path.basename(partes[k]) in ("clang", "clang++") and os.path.isabs(partes[k]):
            return partes[k], partes[k + 1:]
    return None


def expandir_c(args, build):
    """Os argumentos do clang com os arquivos de resposta abertos (o clang os le como o shell), so da pasta do build."""
    saida = []
    for arg in args:
        # O clang so abre o `@arquivo` que existe; o resto e o proprio texto (`-rpath @executable_path/Frameworks`). O
        # relativo que existe, a partir de onde o build roda, e recusado: as duas leituras nao seriam a mesma.
        if arg.startswith("@") and len(arg) > 1 and not os.path.isabs(arg[1:]):
            if any(os.path.exists(os.path.join(base, arg[1:])) for base in (RAIZ, os.path.join(RAIZ, "Kit"), os.path.join(RAIZ, "EscaliburWallet.xcodeproj"))):
                raise ValueError(f"arquivo de resposta relativo: {arg}")
            saida.append(arg)
        elif arg.startswith("@") and len(arg) > 1:
            if not de_dentro(arg[1:], (build,)):
                raise ValueError(f"arquivo de resposta fora da pasta do build: {arg[1:]}")
            with open(arg[1:], encoding="utf-8") as arquivo:
                saida += shlex.split(arquivo.read())
        else:
            saida.append(arg)
    return saida


def conferir_c(args, raizes, build, numero, plataforma="ios"):
    """Uma compilacao do C: (alvo nosso ou None, problemas), pela lista fechada das opcoes."""
    problemas = []
    fontes = [a for a in args if re.search(r"\.(c|cc|cpp|S|s)$", a) and not a.startswith("-")]
    alvo = None
    for fonte in fontes:
        for nome, pasta_do_alvo in ALVOS_DO_C.items():
            # O relativo conta a partir da raiz, como o build o le: um caminho relativo nao tira a fonte da lista fechada.
            if de_dentro(fonte if os.path.isabs(fonte) else os.path.join(RAIZ, fonte), (pasta(os.path.join(RAIZ, pasta_do_alvo)),)):
                alvo = nome
    if alvo is None:
        return None, problemas
    if "-c" not in args:
        # Uma fonte nossa sem o `-c` (o `--compile`, o `-shared`): fora da lista fechada, recusada.
        problemas.append(f"linha {numero}: {alvo} compilado sem -c")
        return alvo, problemas
    pastas_do_c = tuple(pasta(os.path.join(RAIZ, p)) for p in ALVOS_DO_C.values())
    leitura = tuple(raizes["leitura"]) + (build,) + pastas_do_c

    def valor_certo(tipo, valor):
        if tipo == "build":
            return de_dentro(valor, (build,))
        if tipo == "leitura":
            return de_dentro(valor, leitura)
        if tipo == "sdk":
            return os.path.isabs(valor) and os.path.realpath(valor) in raizes["sdk"]
        if tipo == "alvo":
            return re.fullmatch(r"arm64e?-apple-ios[0-9.]+|aarch64-unknown-linux-android[0-9]+", valor) is not None
        if tipo == "lingua":
            return valor in ("c", "c++", "assembler-with-cpp")
        if tipo == "numero":
            return re.fullmatch(r"[0-9]{1,8}", valor) is not None
        if tipo == "mapa":
            return re.fullmatch(r"[^=]+=[^=]*", valor) is not None
        if tipo == "modulo":
            return valor == alvo
        if tipo == "padrao":
            return re.fullmatch(r"(gnu|c)(89|99|11|17)|(gnu|c)\+\+(11|14|17|20)", valor) is not None
        return tipo == "qualquer"

    vistas = set()
    i = 0
    while i < len(args):
        arg = args[i]
        proximo = args[i + 1] if i + 1 < len(args) else None
        if not arg.startswith("-"):
            if arg not in fontes or not de_dentro(arg, (pasta(os.path.join(RAIZ, ALVOS_DO_C[alvo])),)):
                problemas.append(f"linha {numero}: {alvo} com uma entrada de fora da pasta dele: {arg}")
            i += 1
            continue
        if arg in C_SEM_VALOR:
            vistas.add(arg)
            i += 1
            continue
        if arg in C_COM_VALOR:
            if proximo is None or not valor_certo(C_COM_VALOR[arg], proximo):
                problemas.append(f"linha {numero}: {alvo} com {arg} {proximo}")
            i += 2
            continue
        nome, igual, valor = arg.partition("=")
        if igual and nome in C_COM_IGUAL:
            if not valor_certo(C_COM_IGUAL[nome], valor):
                problemas.append(f"linha {numero}: {alvo} com {arg}")
            i += 1
            continue
        if arg.startswith("-D") and len(arg) > 2:
            if arg[2:] not in DEFINES_DO_ALVO[alvo] | DEFINES_AUTOMATICOS_DO_C:
                problemas.append(f"linha {numero}: {alvo} com {arg}")
            vistas.add(arg)
            i += 1
            continue
        if (arg.startswith("-I") or arg.startswith("-F")) and len(arg) > 2:
            if not de_dentro(arg[2:], leitura):
                problemas.append(f"linha {numero}: {alvo} com {arg[:2]} fora do lugar: {arg[2:]}")
            i += 1
            continue
        # Aviso de compilacao, menos os que repassam opcoes ao linker, ao pre-processador e ao montador.
        if re.fullmatch(r"-W(no-)?[a-z0-9][a-z0-9+-]*(=[A-Za-z0-9_-]+)?", arg) and not re.match(r"-W[lpa],", arg):
            i += 1
            continue
        problemas.append(f"linha {numero}: {alvo} com uma opcao fora da lista: {arg}")
        i += 1
    exigidas = set(C_EXIGIDAS[plataforma])
    if plataforma == "android" and alvo != "CJNI":
        exigidas.add("-D_FORTIFY_SOURCE=2")
    if plataforma == "ios" and alvo not in ("CArgon2", "CSecp256k1"):
        exigidas = set()
    for faltando in sorted(exigidas - vistas):
        problemas.append(f"linha {numero}: {alvo} sem {faltando}")
    # Sem nivel de otimizacao, o clang compila em -O0, e o FORTIFY nao faz nada sem o __OPTIMIZE__ (revisao da decima
    # terceira passada).
    if not vistas & {"-Os", "-O3"}:
        problemas.append(f"linha {numero}: {alvo} sem -Os ou -O3")
    return alvo, problemas


def c_sem_o_clang(linha, build=""):
    """Uma chamada (o primeiro da linha e um caminho absoluto ou um comando) com uma fonte do C nossa, com ou sem `-c`,
    que o `chamada_do_c` nao reconhece: outro compilador, ou o clang chamado de outro jeito (`env clang`, `clang-19`).
    Os arquivos de resposta abertos, e o caminho relativo pela raiz (revisao da decima terceira passada). O cabecalho das
    tarefas do Xcode (`CompileC ...`) nao e chamada."""
    pastas_do_c = tuple(pasta(os.path.join(RAIZ, p)) for p in ALVOS_DO_C.values())
    try:
        partes = shlex.split(linha)
    except ValueError:
        return any(p in linha for p in pastas_do_c) and bool(re.match(r"\s*(/|[a-z][a-z0-9_+.-]*\s)", linha))
    if not partes or not (os.path.isabs(partes[0]) or re.fullmatch(r"[a-z][a-z0-9_+.-]*", partes[0])):
        return False
    try:
        args = expandir_c(partes[1:], build) if build else partes[1:]
    except (OSError, UnicodeDecodeError, ValueError):
        return True
    return any(re.search(r"\.(c|cc|cpp|S|s)$", a) and de_dentro(a if os.path.isabs(a) else os.path.join(RAIZ, a), pastas_do_c)
               for a in args if not a.startswith("-"))


def argumentos(linha):
    """O compilador e os argumentos dele numa linha do log, ou None se a linha nao chama um."""
    if "swiftc" not in linha and "swift-frontend" not in linha:
        return None
    try:
        partes = shlex.split(linha)
    except ValueError:
        return "", []
    # O compilador e um caminho absoluto, ou o que vem depois do `--` de uma tarefa do build; "for swiftc" num texto
    # do log nao e chamada.
    for k, parte in enumerate(partes):
        if os.path.basename(parte) in ("swiftc", "swift-frontend") and (os.path.isabs(parte) or (k > 0 and partes[k - 1] == "--")):
            return parte, partes[k + 1:]
    return None


def expandir(args, build, profundidade=0):
    """Os argumentos com os arquivos de resposta abertos: so da pasta do build, por caminho absoluto, e cada linha um
    caminho simples. O compilador parte o arquivo por linha, pula `//` e trata aspas e barra invertida de outro jeito
    que o shlex: com uma coisa so por linha e nada disso, as duas leituras sao a mesma (decima segunda passada)."""
    saida = []
    for arg in args:
        if arg.startswith("@") and len(arg) > 1:
            if profundidade > 0:
                raise ValueError("arquivo de resposta dentro de outro")
            if not de_dentro(arg[1:], (build,)):
                raise ValueError(f"arquivo de resposta fora da pasta do build: {arg[1:]}")
            with open(arg[1:], encoding="utf-8") as arquivo:
                linhas = arquivo.read().split("\n")
            if any(not LINHA_DE_RESPOSTA.fullmatch(linha) or linha.startswith("//") for linha in linhas):
                raise ValueError(f"arquivo de resposta com o que nao e um caminho simples: {arg[1:]}")
            saida += expandir([linha for linha in linhas if linha], build, profundidade + 1)
        else:
            saida.append(arg)
    return saida


def rastreados_do_git(pasta_relativa):
    saida = subprocess.run(["git", "-C", RAIZ, "ls-files", "-z", "--", pasta_relativa], capture_output=True, check=True).stdout
    return {os.path.join(RAIZ, c) for c in saida.decode("utf-8").split("\0") if c.endswith(".swift")}


def ler_chamada(args, raizes, build):
    """As opcoes da chamada pela lista fechada: (modulo, alvo, versao, defines, features, fontes, problemas)."""
    leitura = tuple(raizes["leitura"]) + (build,) + tuple(pasta(os.path.join(RAIZ, p)) for p in INCLUDES_DO_C)
    lido = {"modulo": None, "alvo": None, "versao": None, "O": False, "defines": [], "experimentais": [], "futuras": [],
            "fontes": [], "pacote": None, "unicas": set()}
    problemas = []

    def caminho(tipo, valor, opcao):
        dentro = {"leitura": leitura, "build": (build,), "plugin": tuple(raizes["compilador"])}[tipo]
        if not de_dentro(valor, dentro):
            problemas.append(f"{opcao} fora do lugar: {valor}")

    i = 0
    while i < len(args):
        arg = args[i]
        tem_valor = i + 1 < len(args)
        valor = args[i + 1] if tem_valor else None
        if arg in SEM_VALOR:
            lido["O"] |= arg == "-O"
            i += 1
            continue
        if not arg.startswith("-"):
            lido["fontes"].append(arg)
            i += 1
            continue
        if arg not in LEITURA | PLUGINS | DO_BUILD | OUTRAS_COM_VALOR | set(EXATOS):
            if arg.startswith("-D") and len(arg) > 2:
                lido["defines"].append(arg[2:])
            else:
                problemas.append(f"opcao fora da lista: {arg}")
            i += 1
            continue
        if not tem_valor:
            problemas.append(f"{arg} sem valor")
            break
        if arg in UNICAS:
            if arg in lido["unicas"]:
                problemas.append(f"{arg} mais de uma vez")
            lido["unicas"].add(arg)
        if arg in LEITURA:
            caminho("leitura", valor, arg)
        elif arg in EXATOS:
            if not os.path.isabs(valor) or os.path.realpath(valor) not in raizes[EXATOS[arg]]:
                problemas.append(f"{arg} que nao e o deste build: {valor}")
        elif arg in PLUGINS:
            # `-external-plugin-path pasta#servidor`: os dois do toolchain.
            for parte in valor.split("#"):
                caminho("plugin", parte, arg)
        elif arg in DO_BUILD:
            caminho("build", valor, arg)
        elif arg == "-module-name":
            lido["modulo"] = valor
        elif arg == "-target":
            lido["alvo"] = valor
        elif arg == "-swift-version":
            lido["versao"] = valor
        elif arg == "-num-threads":
            if not re.fullmatch(r"[0-9]{1,3}", valor):
                problemas.append(f"-num-threads {valor}")
        elif arg == "-package-name":
            lido["pacote"] = valor
        elif arg == "-working-directory":
            if not de_dentro(valor, (RAIZ + "/",)) and os.path.realpath(valor) != RAIZ:
                problemas.append(f"-working-directory fora do repositorio: {valor}")
        elif arg == "-file-prefix-map":
            if not re.fullmatch(r"[^=]+=[^=]*", valor):
                problemas.append(f"-file-prefix-map {valor}")
        elif arg == "-enable-experimental-feature":
            lido["experimentais"].append(valor)
        elif arg == "-enable-upcoming-feature":
            lido["futuras"].append(valor)
        elif arg == "-D":
            lido["defines"].append(valor)
        elif arg == "-Xfrontend":
            if valor == "-serialize-debugging-options":
                pass
            elif valor == "-const-gather-protocols-file" and args[i + 2:i + 3] == ["-Xfrontend"] and i + 3 < len(args):
                caminho("build", args[i + 3], valor)
                i += 2
            else:
                problemas.append(f"-Xfrontend {valor}")
        elif arg == "-Xcc":
            if valor.startswith("-D"):
                if valor[2:] not in DEFINES_DO_C:
                    problemas.append(f"-Xcc {valor}")
            elif valor in C_COM_CAMINHO:
                if args[i + 2:i + 3] == ["-Xcc"] and i + 3 < len(args):
                    caminho(C_COM_CAMINHO[valor], args[i + 3], valor)
                    i += 2
                else:
                    problemas.append(f"-Xcc {valor} sem o caminho")
            elif valor.startswith("-I"):
                caminho("leitura", valor[2:], "-Xcc -I")
            elif valor.startswith("-fmodule-map-file="):
                caminho("leitura", valor.split("=", 1)[1], "-Xcc -fmodule-map-file")
            elif valor.startswith("-ffile-prefix-map="):
                if not re.fullmatch(r"-ffile-prefix-map=[^=]+=[^=]*", valor):
                    problemas.append(f"-Xcc {valor}")
            elif valor in C_FIXAS or re.fullmatch(r"-fmodules-prune-(after|interval)=[0-9]+", valor):
                pass
            else:
                problemas.append(f"-Xcc {valor}")
        i += 2
    return lido, problemas


def conferir(plataforma, linhas, build, parcial=False, raizes=None, versao=True, rastreados=rastreados_do_git):
    raizes = raizes or raizes_do(plataforma)
    build = pasta(build)
    problemas, vistos, compiladores = [], set(), set()
    compiladas = {}
    alvos_c = set()
    tarefas = {}
    for numero, linha in enumerate(linhas, 1):
        tarefa = TAREFA_DO_SWIFT.match(linha)
        if tarefa and os.path.basename(tarefa.group(2)) not in ("swiftc", "swift-frontend"):
            problemas.append(f"linha {numero}: a tarefa do Swift chama outra coisa: {tarefa.group(2)}")
            continue
        do_c = chamada_do_c(linha)
        if do_c is not None:
            compilador_c, args_c = do_c
            try:
                args_c = expandir_c(args_c, build)
            except (OSError, UnicodeDecodeError, ValueError) as erro:
                problemas.append(f"linha {numero}: arquivo de resposta do C que nao se le ({erro})")
                continue
            if proibidas_no_link(args_c, plataforma, raizes, build):
                problemas.append(f"linha {numero}: opcao de link que troca funcao ou o linker: {proibidas_no_link(args_c, plataforma, raizes, build)}")
            alvo, achados = conferir_c(args_c, raizes, build, numero, plataforma)
            if alvo is not None:
                if not de_dentro(compilador_c, raizes["compilador"]):
                    problemas.append(f"linha {numero}: o C do {alvo} com um compilador de fora do toolchain: {compilador_c}")
                alvos_c.add(alvo)
                problemas += achados
            continue
        chamada = argumentos(linha)
        if chamada is None:
            if c_sem_o_clang(linha, build):
                problemas.append(f"linha {numero}: uma fonte do C nossa compilada sem o clang do toolchain")
            if PEDACOS.search(linha):
                problemas.append(f"linha {numero}: pedaco de chamada do compilador fora de uma chamada (a saida foi cortada?)")
            continue
        compilador, args = chamada
        try:
            args = expandir(args, build)
        except (OSError, UnicodeDecodeError, ValueError) as erro:
            problemas.append(f"linha {numero}: arquivo de resposta que nao se le ({erro})")
            continue
        if not compilador:
            problemas.append(f"linha {numero}: chamada do compilador que nao se le")
            continue
        if proibidas_no_link(args, plataforma, raizes, build):
            problemas.append(f"linha {numero}: opcao de link que troca funcao ou o linker: {proibidas_no_link(args, plataforma, raizes, build)}")
        fontes = [a for a in args if a.endswith(".swift") and not a.startswith("-")]
        nomes = [args[k + 1] for k, a in enumerate(args[:-1]) if a == "-module-name"]
        nosso = any(n in ESPERADOS["ios"] | ESPERADOS["android"] for n in nomes)
        if not fontes and not nosso and not {"-filelist", "-primary-filelist"} & set(args):
            continue
        if nomes == ["main"] and fontes and all(os.path.realpath(f) == MANIFESTO for f in fontes):
            # O manifesto, que o SwiftPM compila como o modulo `main` (as diretivas dele o tools/flags-do-pacote.py recusa).
            continue
        if not de_dentro(compilador, raizes["compilador"]):
            problemas.append(f"linha {numero}: compilador de fora do toolchain: {compilador}")
            continue
        compiladores.add(compilador)
        lido, achados = ler_chamada(args, raizes, build)
        problemas += [f"linha {numero}: {a}" for a in achados]
        modulo = lido["modulo"]
        if len(nomes) != 1 or permitidas(modulo) is None:
            problemas.append(f"linha {numero}: modulo que o verificador nao conhece: {nomes}")
            continue
        vistos.add(modulo)
        if tarefa:
            tarefas.setdefault((modulo, lido["alvo"]), set()).add(tuple(args))
        if not lido["alvo"] or not re.fullmatch(ALVO[plataforma], lido["alvo"]):
            problemas.append(f"linha {numero}: {modulo} para outro alvo: {lido['alvo']}")
        if lido["versao"] != "6":
            problemas.append(f"linha {numero}: {modulo} no modo {lido['versao']} da linguagem")
        if not lido["O"]:
            problemas.append(f"linha {numero}: {modulo} sem o -O do Release")
        if lido["pacote"] not in ((None,) if modulo in APP else ("kit",)):
            problemas.append(f"linha {numero}: {modulo} com -package-name {lido['pacote']}")
        for define in lido["defines"]:
            if define not in permitidas(modulo):
                problemas.append(f"linha {numero}: {modulo} com -D{define}")
        experimentais, futuras = features(modulo)
        for nome in set(lido["experimentais"]) - experimentais:
            problemas.append(f"linha {numero}: {modulo} com a feature experimental {nome}")
        for nome in set(lido["futuras"]) - futuras:
            problemas.append(f"linha {numero}: {modulo} com a feature {nome}")
        dentro = tuple(pasta(os.path.join(RAIZ, p)) for p in FONTES[modulo])
        for fonte in lido["fontes"]:
            gerada = modulo in GERADAS and de_dentro(fonte, (build,)) and re.search(GERADAS[modulo] + "$", fonte) is not None
            if not fonte.endswith(".swift") or not (gerada or de_dentro(fonte, dentro)):
                problemas.append(f"linha {numero}: {modulo} com uma fonte de fora da pasta dele: {fonte}")
            elif not gerada:
                compiladas.setdefault(modulo, set()).add(os.path.realpath(fonte))
    if versao:
        esperada = versao_do_codigo(plataforma)
        for compilador in sorted(compiladores):
            if versao_do_compilador(compilador) != esperada:
                problemas.append(f"o compilador {compilador} nao e o Swift {esperada} com que o leitor le os #if")
    # As tres tarefas de um modulo numa fatia recebem os mesmos argumentos: uma linha cortada entre duas opcoes, ou uma
    # tarefa com outra flag, aparece como diferenca (decima segunda passada).
    for (modulo, alvo), variantes in sorted(tarefas.items(), key=lambda item: (item[0][0], item[0][1] or "")):
        if len(variantes) > 1:
            problemas.append(f"{modulo} ({alvo}): as tarefas do Swift com argumentos diferentes entre si")
    if not parcial:
        for modulo in sorted(ESPERADOS[plataforma] - vistos):
            problemas.append(f"o log nao compila o modulo {modulo}")
        for modulo in sorted(ESPERADOS[plataforma] & vistos):
            fatias = {(alvo or "").split("-")[0] for (m, alvo) in tarefas if m == modulo}
            if fatias != FATIAS[plataforma]:
                problemas.append(f"o log compila o {modulo} nas fatias {sorted(fatias)}, e nao em {sorted(FATIAS[plataforma])}")
        for alvo in sorted(ALVOS_C_ESPERADOS[plataforma] - alvos_c):
            problemas.append(f"o log nao compila o C do {alvo}")
        # Todo .swift rastreado das pastas entra no build: no Kit e no nucleo, a pasta inteira no seu modulo; no app, o
        # app compila as pastas dele e a compartilhada, e o app com o widget compilam todas as tres.
        for modulo in sorted(ESPERADOS[plataforma] - APP):
            faltam = rastreados(FONTES[modulo][0]) - compiladas.get(modulo, set())
            if faltam:
                problemas.append(f"{modulo} nao compila {len(faltam)} arquivo(s) rastreado(s) da pasta dele")
        if plataforma == "ios":
            do_app = rastreados("App/EscaliburWallet") | rastreados("App/Shared")
            todos = do_app | rastreados("App/EscaliburWidgets")
            juntos = compiladas.get("EscaliburWallet", set()) | compiladas.get("EscaliburWidgets", set())
            if do_app - compiladas.get("EscaliburWallet", set()) or todos - juntos:
                problemas.append(f"o app nao compila {len((do_app - compiladas.get('EscaliburWallet', set())) | (todos - juntos))} arquivo(s) rastreado(s) dele")
    return problemas


def testes():
    erros = []
    with tempfile.TemporaryDirectory() as temporaria:
        temporaria = os.path.realpath(temporaria)
        dev = os.path.join(temporaria, "Developer")
        build = os.path.join(temporaria, "dd")
        raizes = {"compilador": (dev + "/",), "leitura": (dev + "/",), "sdk": {f"{dev}/SDKs/iPhoneOS.sdk"}, "recursos": set()}
        xcode = f"{dev}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
        os.makedirs(build)
        lista = os.path.join(build, "x.SwiftFileList")
        open(lista, "w", encoding="utf-8").write(f"{RAIZ}/Kit/Sources/EscaliburCore/a.swift\n")
        ruim = os.path.join(build, "ruim.resp")
        open(ruim, "w", encoding="utf-8").write("-D\nFOO\n")
        aspas = os.path.join(build, "aspas.resp")
        open(aspas, "w", encoding="utf-8").write(f"\"{RAIZ}/Kit/Sources/EscaliburCore/a.swift\"\n")
        fora = os.path.join(temporaria, "fora.resp")
        open(fora, "w", encoding="utf-8").write(f"{RAIZ}/Kit/Sources/EscaliburCore/a.swift\n")

        def falsos(pasta_relativa):
            return {f"{RAIZ}/{pasta_relativa}/a.swift"} if pasta_relativa in {FONTES[m][0] for m in ESPERADOS["ios"]} else set()
        base = f"-O -whole-module-optimization -swift-version 6 -target arm64-apple-ios17.0 -sdk {dev}/SDKs/iPhoneOS.sdk"

        def chamada(modulo, extra="", fatia="arm64"):
            pacote = "" if modulo in APP else "-package-name kit -DSWIFT_PACKAGE -DXcode"
            pasta_fonte = FONTES[modulo][0]
            alvo = base.replace("-target arm64-apple-ios17.0", f"-target {fatia}-apple-ios17.0")
            return f"    builtin-SwiftDriver -- {xcode} -module-name {modulo} {alvo} {pacote} {RAIZ}/{pasta_fonte}/a.swift {extra}"

        clang = f"{dev}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"

        def do_c(alvo, extra=""):
            arquivo = f"{RAIZ}/{ALVOS_DO_C[alvo]}/a.c"
            endurecido = "-ftrivial-auto-var-init=zero -ftyped-memory-operations" if alvo in ("CArgon2", "CSecp256k1") else ""
            return (f"    {clang} -x c -target arm64-apple-ios17.0 -Os -DSWIFT_PACKAGE {endurecido} -I{RAIZ}/{ALVOS_DO_C[alvo]}/include "
                    f"{extra} -c {arquivo} -o {build}/a.o")

        todos = [chamada(m, fatia=f) for m in sorted(ESPERADOS["ios"]) for f in ("arm64", "arm64e")]
        todos += [do_c("CArgon2"), do_c("CSecp256k1", "-DCOMB_TEETH=6")]

        # A chamada do modulo na fatia arm64e trocada pela com o extra (as tres tarefas de uma fatia sao uma so aqui).
        def com(*extras, modulo="EscaliburCore"):
            return [l for l in todos if l != chamada(modulo, fatia="arm64e")] + [chamada(modulo, e, fatia="arm64e") for e in extras]

        casos = [
            (todos, False, True),
            (todos[:-1], False, False),
            (todos[:-1], True, True),
            (com("-DFOO"), False, False),
            (com("-D FOO"), False, False),
            (com("-Xfrontend -DFOO"), False, False),
            (com("-Xcc -DFOO"), False, False),
            (com("-Xcc -DSWIFT_PACKAGE"), False, True),
            (com("-DSWIFT_PACKAGE", modulo="EscaliburWallet"), False, False),
            (com("-DCRYPTO_IN_SWIFTPM"), False, False),
            (todos + [chamada("EscaliburCore").replace("EscaliburCore", "Outro", 1)], False, False),
            (com(f"@{ruim}"), False, False),
            (com(f"@{build}/sumiu.resp"), False, False),
            (com(f"@{lista}"), False, True),
            (com("-target arm64-apple-ios17.0-simulator"), False, False),
            (com("--target=arm64-apple-ios17.0-simulator"), False, False),
            (com("-target-variant arm64-apple-ios17.0-macabi"), False, False),
            (com("-swift-version 5"), False, False),
            (com("-language-mode 5"), False, False),
            (com("-Ounchecked"), False, False),
            (com("-remove-runtime-asserts"), False, False),
            (com("-enforce-exclusivity=unchecked"), False, False),
            (com("-Xfrontend -assert-config -Xfrontend Unchecked"), False, False),
            (com("-module-alias Foundation=X"), False, False),
            (com(f"-vfsoverlay {temporaria}/o.yaml"), False, False),
            (com("-Xllvm -load=/tmp/x.dylib"), False, False),
            (com("-Xcc -fplugin=/tmp/x.dylib"), False, False),
            (com("-enable-experimental-feature Embedded"), False, False),
            (com("-enable-experimental-feature Lifetimes"), False, False),
            (com("-enable-upcoming-feature MemberImportVisibility"), False, False),
            (com("-enable-experimental-feature DebugDescriptionMacro"), False, True),
            (com("-I /tmp/glibc"), False, False),
            (com(f"-I {build}/Products"), False, True),
            (com(f"-I {RAIZ}/Kit/Sources/CArgon2/include"), False, True),
            (com(f"-I {RAIZ}/Kit/Sources/EscaliburCore"), False, False),
            (com("-Xcc -I/tmp/glibc"), False, False),
            (com("-Xcc -iquote -Xcc /tmp/x"), False, False),
            (com("-Xcc -iquote"), False, False),
            (com("-Xcc -fmodule-map-file=/tmp/module.modulemap"), False, False),
            (com(f"-Xcc -fmodule-map-file={RAIZ}/Kit/Sources/CArgon2/include/module.modulemap"), False, True),
            (com("-resource-dir /tmp/r"), False, False),
            (com("-sdk /tmp/sdk"), False, False),
            (todos + [chamada("EscaliburCore", fatia="arm64").replace("SDKs/iPhoneOS.sdk", "SDKs/iPhoneSimulator.sdk")], False, False),
            (com(f"-plugin-path {dev}/Toolchains/x"), False, True),
            (com(f"-plugin-path {dev}/../fora"), False, False),
            (com(f"-plugin-path {dev}2/x"), False, False),
            (com(f"-external-plugin-path {dev}/p#{dev}/bin/swift-plugin-server"), False, True),
            (com(f"-external-plugin-path {dev}/p#/tmp/servidor"), False, False),
            (com("-load-plugin-executable /tmp/x#M"), False, False),
            (com("-module-cache-path /tmp/cache"), False, False),
            (com(f"-module-cache-path {build}/ModuleCache.noindex"), False, True),
            (com("-working-directory /tmp"), False, False),
            (com(f"-working-directory {RAIZ}"), False, True),
            (com("-package-name outro"), False, False),
            (com("/tmp/fora.swift"), False, False),
            (com(f"{RAIZ}/App/EscaliburWallet/x.swift"), False, False),
            (com(f"{build}/x/EscaliburCore.build/DerivedSources/resource_bundle_accessor.swift"), False, True),
            (com(f"{build}/x/EscaliburCore.build/DerivedSources/GeneratedAssetSymbols.swift"), False, False),
            (com(f"{build}/x/Outro.build/DerivedSources/resource_bundle_accessor.swift"), False, False),
            (com(f"{build}/DerivedSources/outra.swift"), False, False),
            (com(f"@{aspas}"), False, False),
            (com(f"@{fora}"), False, False),
            (com("@x.resp"), False, False),
            (todos + ["    lues -const-gather-protocols-list /x -module-name EscaliburCore -DFOO"], False, False),
            (todos + ["    -Xcc -DFOO -swift-version 6"], False, False),
            (com("-swift-version 6"), False, False),
            (com("-target arm64-apple-ios17.0"), False, False),
            (com("-I -emit-pcm -DFOO"), False, False),
            (com("-num-threads -compile-module-from-interface"), False, False),
            (todos + [f"    builtin-SwiftDriver -- {xcode} -module-name EscaliburCore -emit-pcm -DFOO {base} {RAIZ}/Kit/Sources/EscaliburCore/a.swift"], False, False),
            (todos + [f"    builtin-SwiftDriver -- /tmp/x/swiftc -module-name EscaliburCore {base} {RAIZ}/Kit/Sources/EscaliburCore/a.swift"], False, False),
            (todos + [f"    builtin-SwiftDriver -- {dev}/../../x/swiftc -module-name EscaliburCore {base} {RAIZ}/Kit/Sources/EscaliburCore/a.swift"], False, False),
            (todos + [f"    builtin-SwiftDriver -- tools/swiftc -module-name EscaliburCore {base} {RAIZ}/Kit/Sources/EscaliburCore/a.swift"], False, False),
            (todos + [chamada("EscaliburCore").replace(" -O ", " ")], False, False),
            (todos + [f"ExecuteExternalTool {xcode} --version"], False, True),
            (todos + [f"    {xcode} --version -module-name EscaliburCore -DFOO {base} {RAIZ}/Kit/Sources/EscaliburCore/a.swift"], False, False),
            (todos + ["Discovering version info for swiftc"], False, True),
            (todos + [f"    {xcode} -target arm64-apple-ios17.0 -emit-library -o x.so"], False, True),
            (todos + [f"    {xcode} -target arm64-apple-ios17.0 -emit-library /a/b.swift -DFOO -o x.so"], False, False),
            (todos + [f"    {xcode} -frontend -emit-pcm -module-name SwiftShims -Xcc -DX"], False, True),
            (todos + [f"    {xcode} -frontend -c -primary-file {MANIFESTO} -module-name main -target arm64-apple-macosx14.0"], False, True),
            (todos + [f"    {xcode} -frontend -c -primary-file {MANIFESTO} -primary-file /a/b.swift -module-name main -DFOO"], False, False),
            (todos + [f"    {xcode} -frontend -c -primary-file /a/Package.swift -module-name main -DFOO"], False, False),
            (todos + [f"    {xcode} -module-name 'EscaliburCore"], False, False),
            # Decima segunda passada: o C e o link.
            (todos + [do_c("CCryptoBoringSSL", "-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION")], False, False),
            (todos + [do_c("CArgon2", "-D OPENSSL_RAND_DETERMINISTIC")], False, False),
            (todos + [do_c("CSecp256k1", "-UNDEBUG")], False, False),
            (todos + [do_c("CArgon2", "-include /tmp/x.h")], False, False),
            (todos + [do_c("CArgon2", "-Xclang -load")], False, False),
            (todos + [do_c("CArgon2", "-O0")], False, False),
            (todos + [do_c("CArgon2", "-fno-stack-protector")], False, False),
            (todos + [do_c("CArgon2", "-I/tmp/openssl")], False, False),
            (todos + [do_c("CArgon2", "-D_FORTIFY_SOURCE=2")], False, True),
            (todos[:-1], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Xlinker --wrap=RAND_bytes -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,--defsym,a=b -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Xlinker -rpath -Xlinker @executable_path/Frameworks -o x"], False, True),
            (todos + [f"    {xcode} -emit-library -Xlinker -alias -Xlinker _a -Xlinker _b -o x.so"], False, False),
            # Decima terceira passada: as grafias que a lista de proibidas deixava passar.
            (todos + [do_c("CArgon2", "--define-macro=FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION")], False, False),
            (todos + [do_c("CArgon2", "--define-macro X")], False, False),
            (todos + [do_c("CArgon2", "-Wp,-DX")], False, False),
            (todos + [do_c("CArgon2", "--include=/tmp/x.h")], False, False),
            (todos + [do_c("CArgon2", "--undefine-macro=_FORTIFY_SOURCE")], False, False),
            (todos + [do_c("CArgon2", "-idirafter /tmp/x")], False, False),
            (todos + [do_c("CArgon2", "-ftrivial-auto-var-init=uninitialized")], False, False),
            (todos + [do_c("CArgon2").replace("-ftrivial-auto-var-init=zero ", "")], False, False),
            (todos + [do_c("CArgon2", "-Wall -Wno-unused-function")], False, True),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,-z,now,--wrap=RAND_bytes -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,--as-needed,--defsym=a=b -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,-z,muldefs -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Xlinker -z -Xlinker now -o x"], False, True),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -e _NSExtensionMain -o x"], False, True),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -e _outro -o x"], False, False),
            (todos + [f"    {xcode} -filelist {lista} -module-name Outro"], False, False),
            # Revisao da decima terceira passada: C sem otimizacao, linker trocado, codigo no LTO e C sem o clang.
            (todos + [do_c("CArgon2").replace(" -Os ", " ")], False, False),
            (todos + [f"    {xcode} -target arm64-apple-ios17.0 -emit-library -o x.so -use-ld=/tmp/ld"], False, False),
            (todos + [f"    {xcode} -target arm64-apple-ios17.0 -emit-library -o x.so -ld-path=/tmp/ld"], False, False),
            (todos + [f"    {xcode} -target arm64-apple-ios17.0 -emit-library -o x.so -tools-directory /tmp"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -fuse-ld=lld -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 --ld-path=/tmp/ld -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -B/tmp -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -B /tmp -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,-lto_library,/tmp/l.dylib -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,-mllvm,-x -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,--load-pass-plugin=/tmp/p.so -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Xlinker -dyld_env -Xlinker A=1 -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,-interposable_list,/tmp/l -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,--undefined-glob=x -o x"], False, False),
            (todos + [f"    {xcode} -emit-library -Xclang-linker -resource-dir -Xclang-linker /tmp/rd -o x.so"], False, False),
            (todos + [f"    /tmp/cc -target arm64-apple-ios17.0 -Os -c {RAIZ}/{ALVOS_DO_C['CArgon2']}/a.c -o {build}/b.o"], False, False),
            (todos + [f"    env clang -target arm64-apple-ios17.0 -Os -c {RAIZ}/{ALVOS_DO_C['CArgon2']}/a.c -o {build}/b.o"], False, False),
            # Segunda revisao: o apelido do -Xlinker, um traco no lld, carga forcada, pasta e entrada de fora, SDK de fora,
            # C sem -c, relativo, com o compilador no meio ou por arquivo de resposta.
            (todos + [f"    {clang} -target arm64-apple-ios17.0 --for-linker=--wrap=RAND_bytes -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 --for-linker --wrap=RAND_bytes -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,-allow-multiple-definition -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,-script=/tmp/x.ld -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -Wl,-force_load,/tmp/outra.a -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -L/tmp/libs -loutra -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 /tmp/outro.o -o x"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 --sysroot=/tmp/s -o x"], False, False),
            (todos + [f"    {xcode} -emit-library -sdk /tmp/sdk -o x.so"], False, False),
            (todos + [f"    {clang} -target arm64-apple-ios17.0 -L{build}/b -L/usr/lib/swift -o x"], False, True),
            (todos + [do_c("CArgon2").replace(" -c ", " --compile ")], False, False),
            (todos + [do_c("CArgon2").replace(" -c ", " -shared ")], False, False),
            (todos + [do_c("CArgon2").replace(f" -c {RAIZ}/", " -c ")], False, False),
            (todos + [f"    /opt/llvm/bin/clang-19 -O0 -c {RAIZ}/{ALVOS_DO_C['CArgon2']}/a.c -o {build}/clang"], False, False),
            (todos + [f"    /tmp/cc -O0 --compile {RAIZ}/{ALVOS_DO_C['CArgon2']}/a.c"], False, False),
            (todos + [f"    /tmp/cc -O0 -c {ALVOS_DO_C['CArgon2']}/a.c"], False, False),
            ([], False, False),
        ]
        # O linker do Android: so o lld do NDK, pelo nome ou pelo caminho, e nada mais.
        lld = os.path.join(casa(SDK_ANDROID[1]), "toolchains/llvm/prebuilt/darwin-x86_64/bin/ld.lld")
        raizes_android = {"leitura": (pasta(SDK_ANDROID[1]),)}
        if proibidas_no_link(["-fuse-ld=lld", f"--ld-path={lld}", "-use-ld=lld", f"-ld-path={lld}"], "android", raizes_android):
            erros.append("o lld do NDK devia passar no Android")
        for ruim in (["-fuse-ld=bfd"], ["--ld-path=/tmp/ld.lld"], ["-use-ld=/tmp/ld"], ["-ld-path", "/tmp/ld"],
                     ["-Xclang-linker", "-resource-dir", "-Xclang-linker", "/tmp/rd"]):
            if not proibidas_no_link(ruim, "android", raizes_android):
                erros.append(f"o linker {ruim} devia ser recusado no Android")
        # Um arquivo rastreado da pasta que nao entra no build.
        def com_mais_um(pasta_relativa):
            return falsos(pasta_relativa) | ({f"{RAIZ}/{pasta_relativa}/trava.swift"} if pasta_relativa == "Kit/Sources/EscaliburNetwork" else set())
        # So uma fatia, e duas tarefas do mesmo modulo com argumentos diferentes.
        so_arm64 = [l for l in todos if "arm64e-apple" not in l]
        if not conferir("ios", so_arm64, build, False, raizes, versao=False, rastreados=falsos):
            erros.append("o log com uma fatia so devia ser recusado")
        cortada = todos + [chamada("EscaliburCore").replace("-package-name kit", "")]
        if not conferir("ios", cortada, build, False, raizes, versao=False, rastreados=falsos):
            erros.append("as tarefas com argumentos diferentes deviam ser recusadas")
        if not conferir("ios", todos + [f"    builtin-SwiftDriver -- {dev}/Toolchains/X/usr/bin/swiftc-6.3 -module-name EscaliburCore"], build,
                        False, raizes, versao=False, rastreados=falsos):
            erros.append("a tarefa do Swift com outro compilador devia ser recusada")
        if not conferir("ios", todos, build, False, raizes, versao=False, rastreados=com_mais_um):
            erros.append("o arquivo rastreado fora do build devia ser recusado")
        for indice, (linhas, parcial, certo) in enumerate(casos):
            achados = conferir("ios", linhas, build, parcial, raizes, versao=False, rastreados=falsos)
            if (not achados) != certo:
                erros.append(f"caso {indice} devia {'passar' if certo else 'ser recusado'}: {achados[:3]}")
    if versao_do_codigo("ios") is None or versao_do_codigo("android") is None:
        erros.append("a VERSAO_SWIFT do tools/codigo.py nao se le")
    for erro in erros:
        print(erro)
    return 1 if erros else 0


def main():
    if sys.argv[1:] == ["--testes"]:
        return testes()
    args = sys.argv[1:]
    parcial = "--parcial" in args
    args = [a for a in args if a != "--parcial"]
    if len(args) != 4 or args[0] not in ESPERADOS or args[2] != "--build":
        print(__doc__)
        return 2
    try:
        linhas = open(args[1], encoding="utf-8", errors="replace").read().split("\n")
        problemas = conferir(args[0], linhas, args[3], parcial)
    except (OSError, subprocess.CalledProcessError) as erro:
        print(f"o log ou o toolchain nao se le: {erro}")
        return 1
    for problema in problemas[:40]:
        print(problema)
    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main())
