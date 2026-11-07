#!/bin/bash -p
# Verificacoes que valem por afirmacao publica sobre a Escalibur Wallet.
#
# Cada uma existe porque a alternativa e o app prometer num texto algo que ninguem
# confere. Aqui qualquer pessoa confere, com uma linha de shell:
#
#     ./tools/verificar.sh            as verificacoes estaticas
#     ./tools/verificar.sh --testes   e tambem os testes do nucleo (vetores oficiais)
#     ./tools/verificar.sh --atualizar-simbolos   regrava simbolos.lock (revise o diff)
#     ./tools/verificar.sh --binario <EscaliburWallet.app>
#                                     e tambem o app de um build Release para aparelho
#                                     (arm64e, autenticacao de ponteiro, entitlements)
#
# O desenho de cada regra esta em docs/seguranca.md §8.3.

set -uo pipefail
# O caminho do .app vem relativo a quem chamou: resolvido antes de ir para a raiz.
app_binario=""
if [ "${1:-}" = "--binario" ] && [ -n "${2:-}" ]; then
    app_binario="$(cd "$(dirname "$2")" 2>/dev/null && pwd)/$(basename "$2")"
fi
cd "$(dirname "$0")/.." || exit 1

falhas=0
aviso() { echo "  ✗ $1"; falhas=$((falhas + 1)); }
ok() { echo "  ✓ $1"; }
secao() { echo; echo "$1"; }

CORE=Kit/Sources/EscaliburCore
CHAINS=Kit/Sources/EscaliburChains
KEYS=Kit/Sources/EscaliburKeys
NET=Kit/Sources/EscaliburNetwork
ENG=Kit/Sources/EscaliburEngines
APP=App/EscaliburWallet
# O widget e o que ele divide com o app.
WID=App/EscaliburWidgets
SHARED=App/Shared
# O app Android em Swift (a ponte e as telas do nucleo): vale para ele o que vale para o app do iOS.
APPA=Kit/Sources/Android/EscaliburAndroid

# O C vendorizado (Argon2, secp256k1 e a cola da Escalibur) por lista fechada, como os modulos Swift
# (auditoria de 03/11/2026): todo simbolo de fora que os objetos compilados chamam esta em
# simbolos-c.lock, no Mac e no nucleo do Android. E alguns nunca passam, nem com o lock atualizado:
# rede, executar programa, carregar biblioteca, chamada direta ao kernel, ler e escrever arquivo, log
# e memoria executavel. O nome e comparado sem as formas fortificadas (`__open_2`, `__sendto_chk`
# viram `open` e `sendto`), e a instrucao que chama o kernel sem simbolo (`svc`, `syscall`) e
# procurada no desmonte (segunda passada da auditoria de 03/11/2026).
c_proibidos='^(socket|socketpair|connect|bind|listen|accept|accept4|send|recv|sendto|recvfrom|sendmsg|recvmsg|getaddrinfo|gethostbyname|gethostbyname2|getifaddrs|execve|execv|execvp|execl|execlp|execle|system|popen|fork|vfork|posix_spawn|posix_spawnp|dlopen|dlsym|dladdr|android_dlopen_ext|loader_.*|ptrace|syscall|open|openat|open64|fopen|fdopen|freopen|creat|opendir|fdopendir|mkstemp|mkstemps|tmpfile|read|write|pread|pwrite|readv|writev|ioctl|mmap|mmap64|mprotect|android_log_.*|syslog|vsyslog|os_log.*|sendmmsg|recvmmsg|connectx|sendfile|sendfile64|process_vm_readv|process_vm_writev|memfd_create|preadv|pwritev|preadv2|pwritev2|preadv64|pwritev64|res_query|res_send|res_nquery|res_nsend|res_search|res_nsearch|res_init|res_ninit|res_mkquery|getnameinfo|fexecve|mach_msg|mach_msg_trap|mach_msg2_trap|mach_vm_protect|mach_vm_allocate|mach_vm_map|mach_vm_write|mach_vm_read|vm_protect|vm_allocate|vm_map|vm_write|vm_read|task_for_pid|thread_create|pthread_jit_write_protect_np)$'
# Sem o `__` da frente e sem o `_chk` ou o `_2` do fim, e sem o `$NOCANCEL` do Mac.
nome_sem_fortificacao() { sed -E 's/\$NOCANCEL$//; s/^__(.+)_(chk|2)$/\1/; s/^__//'; }
nm_android() { ls ~/Library/Android/android-ndk-*/toolchains/llvm/prebuilt/*/bin/llvm-nm 2>/dev/null | tail -1; }
objdump_android() { ls ~/Library/Android/android-ndk-*/toolchains/llvm/prebuilt/*/bin/llvm-objdump 2>/dev/null | tail -1; }
# Os objetos do C do nucleo do Android de uma configuracao (Debug ou Release). Cada uma e conferida
# por si: a de depuracao chama outras funcoes (sem inline), e o build confere a que acabou de sair.
objetos_c_android() {
    local pasta="build/android-kit/out/Products/${1:-Release}-android-aarch64"
    [ -f "$pasta/CArgon2.o" ] && [ -f "$pasta/CSecp256k1.o" ] && echo "$pasta/CArgon2.o $pasta/CSecp256k1.o"
}
configuracoes_android() { for c in Debug Release; do [ -n "$(objetos_c_android "$c")" ] && echo "$c"; done; }
# O que os objetos chamam de fora deles mesmos (sem o que um objeto do modulo define para outro),
# sem o sublinhado que o Mac poe na frente de todo nome de C.
simbolos_do_c() {
    local plataforma="$1" ferramenta objetos
    if [ "$plataforma" = mac ]; then
        ferramenta=nm
        objetos=$(find Kit/.build/debug/CArgon2.build Kit/.build/debug/CSecp256k1.build -name '*.o' 2>/dev/null | tr '\n' ' ')
    else
        ferramenta=$(nm_android); objetos=$(objetos_c_android "${2:-Release}")
    fi
    [ -n "$objetos" ] && [ -n "$ferramenta" ] || return 0
    # shellcheck disable=SC2086
    comm -23 <("$ferramenta" -u $objetos 2>/dev/null | awk 'NF && $NF !~ /:$/ {print $NF}' | sort -u) \
             <("$ferramenta" -g --defined-only $objetos 2>/dev/null | awk 'NF >= 3 {print $NF}' | sort -u) \
        | { [ "$plataforma" = mac ] && sed 's/^_//' || cat; } | sed "s/^/$plataforma /"
}
conferir_simbolos_do_c() {
    local plataforma="$1" configuracao="${2:-Release}" atuais novos perigosos
    atuais=$(simbolos_do_c "$plataforma" "$configuracao")
    [ "$plataforma" = android ] && plataforma_dita="android ($configuracao)" || plataforma_dita="$plataforma"
    if [ -z "$atuais" ]; then
        aviso "checagem do C cega no $plataforma_dita: nenhum simbolo nos objetos do Argon2 e da secp256k1"
        return
    fi
    perigosos=$(echo "$atuais" | awk '{print $2}' | nome_sem_fortificacao | grep -E "$c_proibidos" | sort -u | tr '\n' ' ')
    # A chamada ao kernel sem passar por funcao nenhuma: a instrucao no desmonte dos objetos.
    local desmonte objetos
    if [ "$plataforma" = mac ]; then
        objetos=$(find Kit/.build/debug/CArgon2.build Kit/.build/debug/CSecp256k1.build -name '*.o' 2>/dev/null | tr '\n' ' ')
        # shellcheck disable=SC2086
        desmonte=$(xcrun objdump -d --no-show-raw-insn $objetos 2>/dev/null)
    else
        objetos=$(objetos_c_android "$configuracao")
        # shellcheck disable=SC2086
        desmonte=$("$(objdump_android)" -d --no-show-raw-insn $objetos 2>/dev/null)
    fi
    if [ -z "$desmonte" ]; then
        aviso "desmonte do C cego no $plataforma_dita"
    elif echo "$desmonte" | grep -qE '[[:space:]](svc|hvc|smc|syscall|sysenter)([[:space:]]|$)'; then
        perigosos="$perigosos chamada-direta-ao-kernel"
    fi
    novos=$(comm -23 <(echo "$atuais" | sort -u) <(grep "^$plataforma " simbolos-c.lock 2>/dev/null | sort -u) | awk '{print $2}' | tr '\n' ' ')
    if [ -n "$perigosos" ]; then
        aviso "o C do $plataforma_dita chama o que nunca pode: $perigosos"
    elif [ -n "$novos" ]; then
        aviso "simbolo de fora novo no C do $plataforma_dita: $novos(revise e rode --atualizar-simbolos)"
    else
        ok "o C do $plataforma_dita (Argon2, secp256k1 e a cola) so chama os $(echo "$atuais" | wc -l | tr -d ' ') simbolos de simbolos-c.lock"
    fi
}
# A trava do segredo na RAM no objeto compilado do nucleo do Android, e nao so no fonte (AA-01, quarta passada
# da auditoria de 03/11/2026): o SecureBytes chama mlock e madvise. Codigo morto, texto ou comentario nao
# deixam simbolo.
conferir_trava_do_segredo() {
    local objeto="build/android-kit/out/Intermediates.noindex/EscaliburKit.build/${1}-android-aarch64/EscaliburCore-t.build/Objects-normal/aarch64/SecureBytes.o"
    local chamadas
    chamadas=$("$(nm_android)" -u "$objeto" 2>/dev/null | awk '{print $NF}' | grep -cxE 'mlock|madvise')
    [ "$chamadas" = "2" ] && ok "o SecureBytes do nucleo do Android ($1) chama mlock e madvise (AA-01)" \
        || aviso "o SecureBytes do nucleo do Android ($1) sem mlock ou madvise no objeto (AA-01)"
}
# Chamado pelo compilar-nucleo.sh depois de cada build do nucleo do Android.
if [ "${1:-}" = "--c-android" ]; then
    case "${2:-release}" in debug) configuracao=Debug ;; *) configuracao=Release ;; esac
    conferir_simbolos_do_c android "$configuracao"
    conferir_trava_do_segredo "$configuracao"
    exit $(( falhas > 0 ))
fi

swift_em() { find "$@" -name "*.swift" 2>/dev/null; }
# As regras de codigo leem so .swift. Estas sao as outras extensoes que o Xcode ou o
# SwiftPM compilam ou incluem; fora do C vendorizado (secao "fontes e build"), nenhuma
# pode existir.
nao_swift=( -iname "*.m" -o -iname "*.mm" -o -iname "*.c" -o -iname "*.cc" -o -iname "*.cpp" -o -iname "*.cxx" -o -iname "*.c++"
    -o -iname "*.s" -o -iname "*.asm" -o -iname "*.h" -o -iname "*.hh" -o -iname "*.hpp" -o -iname "*.hxx" -o -iname "*.inc"
    -o -iname "*.modulemap" -o -iname "*.metal" -o -iname "module.map" -o -iname "*.swiftinterface" -o -iname "*.swiftmodule"
    -o -iname "*.swiftdoc" -o -iname "*.swiftsourceinfo" -o -iname "*.pcm" )
# Procura um padrao em codigo, ignorando linhas que sao so comentario (a regra vale
# para o que compila, nao para a explicacao de por que a regra existe).
procurar() { local padrao="$1"; shift; swift_em "$@" | xargs grep -nE "$padrao" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//'; }
# O arquivo como o compilador ou o shell o veem (tools/codigo.py), para as regras que conferem que um trecho
# EXISTE: comentario nao conta, nem aninhado (terceira e quarta passadas da auditoria de 03/11/2026). As
# travas de seguranca leem com `codigo_vivo`, que tambem tira o texto entre aspas e o ramo `#if false` do
# Swift. Regra de AUSENCIA le o arquivo cru: o filtro poderia apagar codigo de verdade.
codigo() { python3 -I tools/codigo.py "$1"; }
# O que esta no Kit compila nos dois apps: so conta o que e vivo no Release das duas plataformas (o nucleo so do
# Android, so no Android; o app, so no iPhone; setima passada da auditoria de 03/11/2026).
codigo_vivo() {
    case "$1" in
        Kit/Sources/Android/*) python3 -I tools/codigo.py "$1" --vivo --plataforma android ;;
        Kit/Sources/*) python3 -I tools/codigo.py "$1" --vivo --plataforma ambas ;;
        *) python3 -I tools/codigo.py "$1" --vivo ;;
    esac
}
codigo_vivo_ios() { python3 -I tools/codigo.py "$1" --vivo; }
# A mesma leitura, com os ramos que o Release do Android compila (o que so existe la, como a trava do AA-01).
codigo_vivo_android() { python3 -I tools/codigo.py "$1" --vivo --plataforma android; }

echo
echo "ESCALIBUR WALLET: verificacoes"
# O leitor de codigo confere a si mesmo com os casos de ataque das auditorias antes de qualquer regra usar
# ele (quarta passada de 03/11/2026).
leitor=$(python3 -I tools/codigo.py --testes 2>&1) && ok "o leitor de codigo (tools/codigo.py) passa nos casos das auditorias" \
    || { aviso "o leitor de codigo erra num caso das auditorias"; echo "$leitor"; }
# O leitor avalia `#if swift(...)` e `compiler(...)` com a versao do compilador de cada build: a do Xcode de
# .xcode-version no iPhone e a do toolchain do tools/android/compilar-nucleo.sh no Android (sexta passada).
versao_leitor=$(grep -oE '^VERSAO_SWIFT = \{"ios": \([0-9, ]+\), "android": \([0-9, ]+\)\}' tools/codigo.py | tr -d ' ')
versao_ios=$(xcrun swiftc --version 2>/dev/null | grep -oE 'Apple Swift version [0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9.]+$' | tr . ,)
versao_android=$(grep -oE 'swift-[0-9]+\.[0-9]+\.[0-9]+-RELEASE\.xctoolchain' tools/android/compilar-nucleo.sh | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | tr . ,)
[ "$(cat .xcode-version 2>/dev/null)" = "$(xcodebuild -version 2>/dev/null | head -1)" ] \
    && [ -n "$versao_ios" ] && [ -n "$versao_android" ] \
    && [ "$versao_leitor" = "VERSAO_SWIFT={\"ios\":($versao_ios),\"android\":($versao_android)}" ] \
    && ok "o leitor usa a versao do Swift de cada build (iPhone $versao_ios, Android $versao_android)" \
    || aviso "a versao do Swift do leitor (tools/codigo.py) nao e a do Xcode de .xcode-version ou a do toolchain do Android"
# Todo `#if` e `#elseif` do Swift de primeira mao se resolve no leitor, em cada plataforma que o arquivo compila: o
# leitor tira do vivo o grupo que nao resolve, e o build pode compila-lo (decima passada da auditoria de 03/11/2026:
# `hasFeature(...)`, um `canImport` que o leitor nao conhece ou uma flag que o SwiftPM poe sozinho escondiam um `if true
# { return true }` no topo de uma trava). A swift-crypto fica de fora: e travada por digesto.
# A lista vai pelo `xargs -0`, e nao por `$(find)`: o shell expandia um nome como `[x].swift` (decima primeira passada).
diretivas=$(find Kit/Sources -name '*.swift' -not -path 'Kit/Sources/SwiftCrypto/*' -not -path 'Kit/Sources/Android/*' -print0 \
        | xargs -0 python3 -I tools/codigo.py --diretivas --plataforma ambas 2>&1 \
    && find Kit/Sources/Android -name '*.swift' -print0 | xargs -0 python3 -I tools/codigo.py --diretivas --plataforma android 2>&1 \
    && find App -name '*.swift' -not -path 'App/EscaliburWalletTests/*' -not -path 'App/EscaliburWalletUITests/*' -print0 \
        | xargs -0 python3 -I tools/codigo.py --diretivas --plataforma ios 2>&1) \
    && ok "todo #if do Swift de primeira mao se resolve no leitor, no iPhone e no Android" \
    || { aviso "um #if do Swift que o leitor nao resolve: o build compila o que as regras nao leem"; echo "$diretivas"; }
# O Python das regras, dos scripts e dos workflows roda isolado (`-I`): sem ele, um `json.py` rastreado na pasta do
# script ou na atual, ou um PYTHONPATH do ambiente, trocava o modulo que o conferidor importa (decima passada). Em todo
# script e workflow rastreado, e em cada chamada, e nao na linha: sem espaco antes do `<<`, numa variavel, pelo caminho
# ou com a versao com ponto tambem conta (decima primeira passada). E nenhum .py rastreado com o nome de um modulo que o
# Python ja tem, nem sitecustomize, usercustomize ou .pth.
sem_isolar=$(git ls-files -z '*.sh' '*.yml' '*.yaml' | xargs -0 grep -HnE '[p]ython' | sed -E 's/[p]ython[0-9.]*"? -I([^A-Za-z0-9]|$)/X\1/g' \
    | grep -E '(^|[^A-Za-z0-9_])[p]ython[0-9.]*([^A-Za-z0-9_-]|$)')
# E nas ferramentas em Swift e no Gradle, o Python de um processo filho tambem com `-I` (decima segunda passada); o
# pacote (`json/__init__.py`) conta pelo nome da pasta.
sem_isolar="$sem_isolar$(git ls-files -z 'tools/*.swift' '*.kts' | xargs -0 grep -HnE '"[p]ython[0-9.]*"' 2>/dev/null | grep -vE '"[p]ython3", "-I"')"
sombra_py=$(git ls-files -z '*.py' '*.pth' | xargs -0 python3 -I -c '
import importlib.util, os, sys
for caminho in sys.argv[1:]:
    nome = os.path.splitext(os.path.basename(caminho))[0]
    if nome == "__init__":
        nome = os.path.basename(os.path.dirname(caminho))
    if caminho.endswith(".pth") or nome in ("sitecustomize", "usercustomize") or importlib.util.find_spec(nome) is not None:
        print(caminho)' 2>&1)
[ -z "$sem_isolar" ] && [ -z "$sombra_py" ] && ok "todo Python dos scripts e dos workflows roda isolado (-I), e nenhum .py rastreado sombreia um modulo" \
    || { aviso "Python sem -I num script ou workflow, ou um .py rastreado com nome de modulo do Python"; echo "$sem_isolar$sombra_py"; }
# As flags que o leitor da por definidas (`flags_do_alvo`) sao as do build: no Kit, so CRYPTO_IN_SWIFTPM, nos alvos da
# swift-crypto, e nenhum `-D` em flag solta; no app, so DEBUG, na configuracao Debug (setima passada). O Package.swift
# e lido avaliado (`swift package dump-package`, com e sem o nucleo do Android), e nao por regex: `+ [.define(...)]` ou
# um laco sobre `package.targets` passavam; o projeto, linha a linha (`[sdk=iphoneos*]` passava); e nenhuma linha de
# build passa `-D` ao Swift (oitava passada da auditoria de 03/11/2026).
# O do Android, com o Swift que compila o nucleo (o do tools/android/compilar-nucleo.sh, quando esta neste Mac; nona
# passada), e o manifesto sem `#if` nem ambiente (tools/flags-do-pacote.py, o mesmo que o compilar-nucleo.sh roda).
swift_android=$(sed -n 's/^SWIFT=\(.*\)$/\1/p' tools/android/compilar-nucleo.sh | head -1)
swift_android="${swift_android/#\~/$HOME}"
[ -x "$swift_android" ] || swift_android=swift
python3 -I tools/flags-do-pacote.py --testes >/dev/null 2>&1 \
    && (cd Kit && swift package dump-package 2>/dev/null) | python3 -I tools/flags-do-pacote.py Kit/Package.swift \
    && (cd Kit && ESCALIBUR_ANDROID=1 "$swift_android" package dump-package 2>/dev/null) | python3 -I tools/flags-do-pacote.py Kit/Package.swift \
    && python3 -I - <<'PY' && ok "as flags do Swift sao as que o leitor conhece (CRYPTO_IN_SWIFTPM na swift-crypto, DEBUG so no Debug)" \
    || aviso "uma flag do Swift que o leitor nao conhece (Package.swift, project.yml, project.pbxproj ou linha de build)"
import glob, re, sys
certo = True
projeto = open("EscaliburWallet.xcodeproj/project.pbxproj", encoding="utf-8").read()
for m in re.finditer(r"isa = XCBuildConfiguration;(.*?)name = ([^;]+);", projeto, re.S):
    for linha in m.group(1).split("\n"):
        if re.search(r"SWIFT_ACTIVE_COMPILATION_CONDITIONS|OTHER_SWIFT_FLAGS|SWIFT_FLAGS", linha):
            certo &= m.group(2) == "Debug" and linha == "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;"
certo &= len(re.findall(r"SWIFT_ACTIVE_COMPILATION_CONDITIONS|OTHER_SWIFT_FLAGS|SWIFT_FLAGS", projeto)) == 1
certo &= "baseConfigurationReference" not in projeto
# Nem outro compilador ou toolchain, que poria as flags que quisesse (decima passada).
certo &= not re.search(r"SWIFT_EXEC|SWIFT_DRIVER|TOOLCHAINS|SWIFT_PLUGIN|PLUGIN_SEARCH_PATHS", projeto)
certo &= not re.search(r"SWIFT_ACTIVE_COMPILATION_CONDITIONS|OTHER_SWIFT_FLAGS|xcconfig|SWIFT_EXEC|SWIFT_DRIVER|TOOLCHAINS|SWIFT_PLUGIN|PLUGIN_SEARCH_PATHS",
                       open("project.yml", encoding="utf-8").read())
certo &= not [c for c in glob.glob("**/*.xcconfig", recursive=True) if not c.startswith(("build/", "Kit/.build/"))]
# Uma lista fechada das chaves de ajuste do projeto, sem ajuste com condicao (`[arch=...]`, `[sdk=...]`): um caminho de
# busca (que muda o `canImport`), uma otimizacao sem checagens, um alias de modulo ou outro compilador entravam por uma
# chave que nenhuma regra olhava. A otimizacao e o modo da linguagem com o valor de cada configuracao (decima primeira
# passada da auditoria de 03/11/2026). Chave nova no project.yml pede entrar aqui, revisada.
CHAVES = {"ALWAYS_SEARCH_USER_PATHS", "ASSETCATALOG_COMPILER_APPICON_NAME", "BUNDLE_LOADER",
          "CLANG_ANALYZER_NONNULL", "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION", "CLANG_CXX_LANGUAGE_STANDARD",
          "CLANG_CXX_LIBRARY", "CLANG_ENABLE_MODULES", "CLANG_ENABLE_OBJC_ARC", "CLANG_ENABLE_OBJC_WEAK",
          "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING", "CLANG_WARN_BOOL_CONVERSION", "CLANG_WARN_COMMA",
          "CLANG_WARN_CONSTANT_CONVERSION", "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS",
          "CLANG_WARN_DIRECT_OBJC_ISA_USAGE", "CLANG_WARN_DOCUMENTATION_COMMENTS", "CLANG_WARN_EMPTY_BODY",
          "CLANG_WARN_ENUM_CONVERSION", "CLANG_WARN_INFINITE_RECURSION", "CLANG_WARN_INT_CONVERSION",
          "CLANG_WARN_NON_LITERAL_NULL_CONVERSION", "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF",
          "CLANG_WARN_OBJC_LITERAL_CONVERSION", "CLANG_WARN_OBJC_ROOT_CLASS",
          "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER", "CLANG_WARN_RANGE_LOOP_ANALYSIS",
          "CLANG_WARN_STRICT_PROTOTYPES", "CLANG_WARN_SUSPICIOUS_MOVE", "CLANG_WARN_UNGUARDED_AVAILABILITY",
          "CLANG_WARN_UNREACHABLE_CODE", "CLANG_WARN__DUPLICATE_METHOD_MATCH", "CODE_SIGN_ENTITLEMENTS",
          "CODE_SIGN_IDENTITY", "COPY_PHASE_STRIP", "CURRENT_PROJECT_VERSION", "DEAD_CODE_STRIPPING",
          "DEBUG_INFORMATION_FORMAT", "DEVELOPMENT_TEAM", "ENABLE_ENHANCED_SECURITY", "ENABLE_NS_ASSERTIONS",
          "ENABLE_STRICT_OBJC_MSGSEND", "ENABLE_TESTABILITY", "ENABLE_USER_SCRIPT_SANDBOXING",
          "GCC_C_LANGUAGE_STANDARD", "GCC_DYNAMIC_NO_PIC", "GCC_NO_COMMON_BLOCKS", "GCC_OPTIMIZATION_LEVEL",
          "GCC_PREPROCESSOR_DEFINITIONS", "GCC_WARN_64_TO_32_BIT_CONVERSION", "GCC_WARN_ABOUT_RETURN_TYPE",
          "GCC_WARN_UNDECLARED_SELECTOR", "GCC_WARN_UNINITIALIZED_AUTOS", "GCC_WARN_UNUSED_FUNCTION",
          "GCC_WARN_UNUSED_VARIABLE", "GENERATE_INFOPLIST_FILE", "INFOPLIST_FILE", "IPHONEOS_DEPLOYMENT_TARGET",
          "LD_RUNPATH_SEARCH_PATHS", "LOCALIZATION_PREFERS_STRING_CATALOGS", "MARKETING_VERSION",
          "MTL_ENABLE_DEBUG_INFO", "MTL_FAST_MATH", "ONLY_ACTIVE_ARCH", "PRODUCT_BUNDLE_IDENTIFIER", "PRODUCT_NAME",
          "SDKROOT", "SKIP_INSTALL", "SWIFT_ACTIVE_COMPILATION_CONDITIONS", "SWIFT_COMPILATION_MODE",
          "SWIFT_EMIT_LOC_STRINGS", "SWIFT_OPTIMIZATION_LEVEL", "SWIFT_STRICT_CONCURRENCY", "SWIFT_VERSION",
          "TARGETED_DEVICE_FAMILY", "TEST_HOST", "TEST_TARGET_NAME"}
# Lido como o Xcode le (o plist convertido pelo `plutil`), e nao linha a linha: duas chaves na mesma linha, uma chave na
# linha do `buildSettings = {` ou um valor com `name = Release;` dentro passavam (decima segunda passada).
import json, subprocess
lido = json.loads(subprocess.run(["plutil", "-convert", "json", "-o", "-", "EscaliburWallet.xcodeproj/project.pbxproj"],
                                 capture_output=True, check=True).stdout)
configuracoes = [o for o in lido["objects"].values() if o.get("isa") == "XCBuildConfiguration"]
certo &= len(configuracoes) > 0
for configuracao in configuracoes:
    nome, ajustes = configuracao.get("name"), configuracao.get("buildSettings", {})
    certo &= nome in ("Debug", "Release") and set(configuracao) <= {"isa", "name", "buildSettings"}
    certo &= set(ajustes) <= CHAVES
    if "SWIFT_OPTIMIZATION_LEVEL" in ajustes:
        certo &= ajustes["SWIFT_OPTIMIZATION_LEVEL"] == ("-O" if nome == "Release" else "-Onone")
    if "SWIFT_VERSION" in ajustes:
        certo &= ajustes["SWIFT_VERSION"] == "6.0"
    for chave in ("GCC_PREPROCESSOR_DEFINITIONS", "ENABLE_TESTABILITY"):
        if chave in ajustes:
            certo &= nome == "Debug"
for script in ("tools/arquivar.sh", "tools/android/compilar-nucleo.sh", "tools/android/gerar-aab.sh", "tools/android/testar-nucleo.sh",
               ".github/workflows/release.yml", ".github/workflows/verificar.yml"):
    texto = open(script, encoding="utf-8").read()
    # Quem define o compilador ou o toolchain, e nao a lista que recusa esses nomes no ambiente (decima terceira passada).
    # Sem a linha da lista (so nomes, `*` e `|`), o texto nao cita nenhum deles, em atribuicao, export, `printf -v`,
    # `declare` ou `read` (a ancora no `=` deixava esses de fora; revisao da decima terceira passada).
    sem_lista = "\n".join(l for l in texto.split("\n") if not re.fullmatch(r"[ \t]*CCC_\*(\|[A-Z0-9_]+\*?)+\)", l))
    # Aspas vazias e a barra no meio de um nome (`SWIFT_EX''EC`) nao o escondem.
    sem_lista = re.sub(r"''|\"\"|\\(?=[A-Za-z_])", "", sem_lista)
    certo &= not re.search(r"SWIFT_ACTIVE_COMPILATION_CONDITIONS|OTHER_SWIFT_FLAGS|-xcconfig|XCODE_XCCONFIG_FILE[ \t]*[=:]|export[ \t]+XCODE_XCCONFIG_FILE|-Xswiftc[ \t]+[\"']?-D|\b(SWIFT_EXEC\w*|SWIFT_DRIVER\w*|SWIFTPM_\w+|TOOLCHAINS|DEVELOPER_DIR)\b|-toolchain\b", sem_lista)
sys.exit(0 if certo else 1)
PY

# Os scripts da loja com o bloco do ambiente inteiro logo depois do `set -euo pipefail`, igual nos quatro: o bash
# privilegiado, a lista de permitidos de hoje e o renascer com o ambiente limpo. O digesto so no bash privilegiado e com o
# PATH do sistema; a segunda fase e a conferencia manual do digesto tambem no bash privilegiado (revisao da decima terceira
# passada).
python3 -I - <<'PY' && ok "os scripts da loja no bash privilegiado, com o ambiente por lista de permitidos" || aviso "script da loja sem o bloco do ambiente, ou com o bash do PATH"
import re, sys
certo = True
blocos = []
for script in ("tools/arquivar.sh", "tools/android/compilar-nucleo.sh", "tools/android/gerar-aab.sh", "tools/android/testar-nucleo.sh"):
    texto = open(script, encoding="utf-8").read()
    m = re.match(r'#!/bin/bash -p\n(?:#[^\n]*\n)*set -euo pipefail\n((?:#[^\n]*\n)*case "\$-" in .*?\n    /bin/bash -p "\$0" "\$@"\n)', texto, re.S)
    certo &= m is not None
    if m:
        blocos.append(m.group(1))
certo &= len(blocos) == 4 and len(set(blocos)) == 1
if blocos:
    b = blocos[0]
    for trecho in ('case "$-" in *p*) ;; *) _sem_p=; : "${_sem_p:?', '$limpo || exec /usr/bin/env -i HOME="$casa"', "PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=",
                   "GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null",
                   "casa=$(/usr/bin/dscl . -read "):
        certo &= trecho in b
    lista = re.search(r"\n        (HOME\|[^\n]*\)) ;;\n", b)
    certo &= lista is not None and lista.group(1) == ("HOME|PATH|TMPDIR|USER|LOGNAME|LANG|TERM|PWD|OLDPWD|SHLVL|_|GIT_CONFIG_NOSYSTEM|GIT_CONFIG_GLOBAL|"
                                                    "GIT_NO_REPLACE_OBJECTS|GIT_CONFIG_COUNT|GIT_CONFIG_KEY_0|GIT_CONFIG_VALUE_0|GIT_CONFIG_KEY_1|GIT_CONFIG_VALUE_1)")
digesto = open("tools/digesto.sh", encoding="utf-8").read()
certo &= digesto.startswith("#!/bin/bash -p\n") and 'case "$-" in *p*) ;; *) _sem_p=; : "${_sem_p:?' in digesto \
    and "\nexport PATH=/usr/bin:/bin:/usr/sbin:/sbin\n" in digesto and digesto.find('case "$-" in *p*)') < digesto.find("main()")
certo &= open("tools/verificar.sh", encoding="utf-8").read().startswith("#!/bin/bash -p\n")
for script, fase in (("tools/arquivar.sh", '/bin/bash -p "$limpa/tools/arquivar.sh" --na-copia-limpa'),
                     ("tools/android/gerar-aab.sh", '/bin/bash -p "$limpa/tools/android/gerar-aab.sh" --na-copia-limpa')):
    texto = open(script, encoding="utf-8").read()
    certo &= fase in texto and not re.search(r'(^|[^/])bash "[$]limpa', texto)
arquivar = open("tools/arquivar.sh", encoding="utf-8").read()
certo &= "| /usr/bin/env -i /bin/bash -p -s --" in arquivar and "| bash -s" not in arquivar
sys.exit(0 if certo else 1)
PY

# Caminho com espaco quebra o "find | xargs grep" das regras e deixa arquivo sem
# conferencia. Nenhum fonte pode ter espaco no caminho.
com_espaco=$(find Kit/Sources Kit/Tests App tools \( -name "*.swift" -o -name "*.py" -o -name "*.sh" -o "${nao_swift[@]}" \) 2>/dev/null | grep '[[:space:]]')
if [ -n "$com_espaco" ]; then
    echo "  ✗ arquivo com espaco no caminho escapa das regras: renomeie"
    echo "$com_espaco"
    exit 1
fi

# 1. Chaves e redes nao falam com a internet.
secao "fronteira de rede"
achados=$(procurar 'import (Network|WebKit|SafariServices|CFNetwork)\b|URLSession|URLRequest|NWConnection|NWPathMonitor|CFSocket|CFStream|CFHTTP|NSURLConnection|getaddrinfo|\bsocket\(|WKWebView|XMLParser|\b(Input|Output)?Stream\b|getStreamsToHost' "$CORE" "$CHAINS" "$KEYS")
[ -n "$achados" ] && { aviso "codigo de rede no nucleo, nas redes ou nas chaves"; echo "$achados"; } || ok "nucleo, redes e chaves nao tem codigo de rede"

achados=$(procurar 'NSClassFromString|NSSelectorFromString|objc_getClass|objc_lookUpClass|class_getInstanceMethod|method_exchange|dlopen|dlsym|objc_msgSend|\.perform\(|value\(forKey' "$CORE" "$CHAINS" "$KEYS")
[ -n "$achados" ] && { aviso "reflexao que contornaria a fronteira"; echo "$achados"; } || ok "sem reflexao no nucleo, nas redes e nas chaves"

# O app (iOS e Android), o widget e os motores tambem nao abrem conexao propria nem montam
# classe pelo nome: toda rede passa pelo HTTPClient, que so fala com a lista fechada. Um commit
# com `import Network` e um host montado em pedacos no app passava pelas regras (auditoria de
# 31/10/2026). O `perform(` de quem pede o PIN (`auth.perform`) nao e reflexao: so o com seletor conta.
achados=$(procurar 'import (Network|CFNetwork|WebKit)\b|NWConnection|NWListener|NWBrowser|NWPathMonitor|CFSocket|CFStream|CFHTTP|NSURLConnection|getaddrinfo|\bsocket\(|getStreamsToHost|\b(Input|Output)?Stream\b|WKWebView' "$APP" "$WID" "$SHARED" "$APPA" "$ENG")
[ -n "$achados" ] && { aviso "conexao propria no app, no widget ou nos motores"; echo "$achados"; } || ok "app, widget e motores nao abrem conexao propria"
achados=$(procurar 'NSClassFromString|NSSelectorFromString|objc_getClass|objc_lookUpClass|class_getInstanceMethod|method_exchange|dlopen|dlsym|objc_msgSend|\.perform\((#selector|Selector|NSSelector)|value\(forKey' "$APP" "$WID" "$SHARED" "$APPA" "$NET" "$ENG")
[ -n "$achados" ] && { aviso "reflexao no app, no widget, na rede ou nos motores"; echo "$achados"; } || ok "sem reflexao no app, no widget, na rede e nos motores"
# Dentro do modulo de rede, so o HTTPClient tem sessao: outra URLSession ali sairia da lista fechada.
achados=$(procurar 'URLSession\b' "$NET" | grep -v "^$NET/HTTPClient.swift:")
[ -n "$achados" ] && { aviso "URLSession no modulo de rede fora do HTTPClient"; echo "$achados"; } || ok "no modulo de rede, so o HTTPClient tem URLSession"

achados=$(swift_em "$APP" "$WID" "$SHARED" "$APPA" "$CORE" "$CHAINS" "$KEYS" "$ENG" | xargs grep -lE 'URLSession' 2>/dev/null)
[ -n "$achados" ] && { aviso "URLSession fora do modulo de rede"; echo "$achados"; } || ok "URLSession so no modulo de rede"

achados=$(procurar 'URLSession\.shared|AsyncImage' "$APP" "$APPA" "$NET" "$CORE" "$CHAINS" "$KEYS" "$ENG")
[ -n "$achados" ] && { aviso "URLSession.shared ou AsyncImage (gravam cache em disco)"; echo "$achados"; } || ok "sem URLSession.shared e sem AsyncImage"

achados=$(procurar 'import EscaliburKeys|SecureBytes|WalletSecret|RootKeyVault|WalletVault|Mnemonic|HDKey' "$NET")
[ -n "$achados" ] && { aviso "o modulo de rede enxerga segredo"; echo "$achados"; } || ok "o modulo de rede nao enxerga segredo nem chave"

achados=$(procurar 'import (Security|LocalAuthentication|EscaliburKeys)\b|SecItem[A-Z]|SecKey[A-Z]|SecAccessControl|LAContext' "$NET" "$ENG")
[ -n "$achados" ] && { aviso "rede ou motores tocam chaveiro, Secure Enclave ou biometria"; echo "$achados"; } || ok "rede e motores nao tocam chaveiro, Secure Enclave nem biometria"
deps_motores=$(awk '/name: "EscaliburEngines"/{f=1} f&&/dependencies/{print; exit}' Kit/Package.swift)
echo "$deps_motores" | grep -q 'EscaliburKeys' && aviso "EscaliburEngines depende de EscaliburKeys no Package.swift" || ok "EscaliburEngines nao depende de EscaliburKeys (o compilador garante)"
deps_rede=$(awk '/name: "EscaliburNetwork"/{f=1} f&&/dependencies/{print; exit}' Kit/Package.swift)
echo "$deps_rede" | grep -q 'EscaliburKeys' && aviso "EscaliburNetwork depende de EscaliburKeys no Package.swift" || ok "EscaliburNetwork nao depende de EscaliburKeys (o compilador garante)"

achados=$(procurar 'SecureBytes|WalletSecret|RootKeyVault|WalletVault|KeychainStore|SecureEnclaveWrapper|Signer\b|Mnemonic|HDKey|SecretStore' "$ENG")
[ -n "$achados" ] && { aviso "os motores enxergam segredo, cofre ou assinador"; echo "$achados"; } || ok "os motores so usam dado publico do modulo de chaves"

achados=$(procurar 'import (Network|WebKit|SafariServices|CFNetwork)\b|URLRequest|NWConnection|WKWebView' "$ENG")
[ -n "$achados" ] && { aviso "os motores falam com a rede sem passar pelo modulo de rede"; echo "$achados"; } || ok "os motores so falam com a rede pelo modulo de rede"

achados=$(procurar 'SigningPlan\(' "$APP" "$KEYS" "$NET" "$ENG" "$CORE")
[ -n "$achados" ] && { aviso "plano de assinatura construido fora das redes"; echo "$achados"; } || ok "plano de assinatura so nasce em EscaliburChains"

achados=$(procurar 'Secp256k1\.sign|Ed25519\.sign' "$CHAINS" "$NET" "$APP" "$ENG")
[ -n "$achados" ] && { aviso "assinatura fora do modulo de chaves"; echo "$achados"; } || ok "so o modulo de chaves assina"

# 2. Hosts travados.
secao "hosts"
hosts_atuais=$(grep -ohE 'https://[A-Za-z0-9.-]+' $(swift_em "$NET" "$ENG") "$APP/Resources/Info.plist" 2>/dev/null | sort -u)
gerar_allowed_hosts() {
    {
        echo "// Gerado por tools/verificar.sh --atualizar-hosts a partir do hosts.lock. Nao editar."
        echo "// O HTTPClient recusa qualquer host fora desta lista, em tempo de execucao."
        echo "enum AllowedHosts {"
        echo "    static let all: Set<String> = ["
        sed 's|https://||' hosts.lock | while read -r host; do echo "        \"$host\","; done
        echo "    ]"
        echo "}"
    } > "$NET/AllowedHosts.swift"
}
if [ "${1:-}" = "--atualizar-hosts" ]; then
    echo "$hosts_atuais" > hosts.lock
    gerar_allowed_hosts
    ok "hosts.lock e AllowedHosts.swift atualizados"
elif [ ! -f hosts.lock ]; then
    aviso "hosts.lock nao existe (gere com --atualizar-hosts e revise o diff)"
elif ! diff -q <(echo "$hosts_atuais") hosts.lock >/dev/null; then
    aviso "a lista de hosts mudou; revise e rode --atualizar-hosts"
    diff <(echo "$hosts_atuais") hosts.lock
else
    ok "$(wc -l < hosts.lock | tr -d ' ') hosts conferem com hosts.lock"
fi
# O TesteTLS do Android (inteiro em DEBUG) confere justamente que o http e recusado.
achados=$(swift_em "$APP" "$APPA" "$NET" "$CORE" "$CHAINS" "$KEYS" | grep -v "$APPA/TesteTLS.swift" | xargs grep -nE '"http://' 2>/dev/null)
[ -n "$achados" ] && { aviso "http sem TLS"; echo "$achados"; } || ok "nenhum http sem TLS"

if /usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity:NSAllowsArbitraryLoads" "$APP/Resources/Info.plist" 2>/dev/null | grep -q true; then
    aviso "ATS com NSAllowsArbitraryLoads ligado"
elif grep -qE 'NSExceptionAllowsInsecureHTTPLoads|NSAllowsLocalNetworking' "$APP/Resources/Info.plist"; then
    aviso "ATS com excecao"
else
    ok "ATS padrao, sem excecao"
fi

# 3. Dependencias.
esperado=$(sed 's|https://||' hosts.lock 2>/dev/null | sort)
gerado=$(grep -oE '^        "[^"]+",$' "$NET/AllowedHosts.swift" 2>/dev/null | tr -d ' ",' | sort)
[ "$esperado" = "$gerado" ] && ok "o cliente HTTP recusa em tempo de execucao todo host fora do hosts.lock" || aviso "AllowedHosts.swift difere do hosts.lock (rode --atualizar-hosts)"
codigo_vivo "$NET/HTTPClient.swift" | grep -q 'allowedHosts.contains(host)' && ok "HTTPClient confere o host de toda requisicao" || aviso "HTTPClient deixou de conferir o host"

secao "dependencias"
if grep -q "XCRemoteSwiftPackageReference" EscaliburWallet.xcodeproj/project.pbxproj 2>/dev/null; then aviso "pacote remoto no projeto"; else ok "nenhum pacote remoto no projeto"; fi
# Qualquer `.package(`, com a url na mesma linha ou nao, e `path:`, `id:` e `name:` tambem
# (auditoria 6, A6-14): o pacote nao tem dependencia nenhuma de fora.
if grep -qE '\.package[[:space:]]*\(' Kit/Package.swift; then aviso "dependencia de pacote no Package.swift"; else ok "nenhum pacote remoto no Package.swift"; fi
achados=$(find . -name Package.resolved -not -path "./build/*" -not -path "*/.build/*" -not -path "./.git/*" 2>/dev/null)
[ -n "$achados" ] && { aviso "Package.resolved: alguma dependencia foi resolvida"; echo "$achados"; } || ok "nenhum Package.resolved"
locais=$(grep -oE 'relativePath = [^;]+;' EscaliburWallet.xcodeproj/project.pbxproj 2>/dev/null | sort -u)
[ -z "$locais" ] || [ "$locais" = "relativePath = Kit;" ] && ok "o unico pacote local do projeto e o Kit" || { aviso "pacote local fora do Kit no projeto"; echo "$locais"; }
if grep -q '\.binaryTarget(' Kit/Package.swift; then aviso "alvo binario no Package.swift"; else ok "nenhum alvo binario"; fi
# A lista fechada das pastas dos alvos (segunda passada da auditoria de 03/11/2026): um alvo novo, de
# C ou de qualquer coisa, numa pasta que nao e uma destas, nao entra sem mudar esta lista. E no Kit,
# fora de Sources e Tests, so o Package.swift.
pastas_dos_alvos=$(grep -oE 'path: *"[^"]+"' Kit/Package.swift | sed -E 's/path: *"([^"]+)"/\1/' | LC_ALL=C sort -u | tr '\n' ' ')
pastas_esperadas=$(printf '%s\n' Sources/Android/CJNI Sources/Android/EscaliburAndroid Sources/CArgon2 Sources/CSecp256k1 \
    Sources/EscaliburChains Sources/EscaliburCore Sources/EscaliburEngines Sources/EscaliburKeys Sources/EscaliburNetwork \
    Sources/SwiftCrypto/CCryptoBoringSSL Sources/SwiftCrypto/CXKCP Sources/SwiftCrypto/CXKCPShims Sources/SwiftCrypto/Crypto \
    Sources/SwiftCrypto/CryptoBoringWrapper Tests/EscaliburChainsTests Tests/EscaliburCoreTests Tests/EscaliburEnginesTests \
    Tests/EscaliburKeysTests Tests/EscaliburNetworkTests | LC_ALL=C sort -u | tr '\n' ' ')
[ "$pastas_dos_alvos" = "$pastas_esperadas" ] && ok "os alvos do Package.swift so usam as 19 pastas conhecidas" \
    || aviso "pasta de alvo fora da lista no Package.swift: $pastas_dos_alvos"
outros_kit=$(find Kit -mindepth 1 -maxdepth 1 -not -name .build -not -name .swiftpm -not -name Sources -not -name Tests -not -name Package.swift 2>/dev/null)
[ -z "$outros_kit" ] && ok "no Kit, fora de Sources e Tests, so o Package.swift" || { aviso "arquivo ou pasta nova no Kit"; echo "$outros_kit"; }
alvos_sem_pasta=$(grep -nE '\.(executableTarget|macro|plugin)\(' Kit/Package.swift)
[ -z "$alvos_sem_pasta" ] && ok "nenhum alvo executavel, de macro ou de plugin" || { aviso "alvo de tipo novo no Package.swift"; echo "$alvos_sem_pasta"; }
achados=$(find . \( -name "*.xcframework" -o -name "*.framework" -o -name "*.a" -o -name "*.dylib" -o -name Podfile -o -name Cartfile \) -not -path "./build/*" -not -path "*/.build/*" -not -path "./.git/*" -not -path "./.claude/*" 2>/dev/null)
[ -n "$achados" ] && { aviso "binario ou gerenciador de terceiro"; echo "$achados"; } || ok "nenhum binario de terceiro"

# 3b. Fontes e build. As regras de rede, segredo e registro leem so .swift, e a pasta do
# app inteira e fonte do alvo (project.yml): um .m ou .c ali compilaria sem passar por
# nenhuma delas. O unico codigo que nao e Swift e o C vendorizado, travado por digesto.
# Um shader .metal so entra pela lista abaixo, revisado como codigo (hoje, nenhum).
secao "fontes e build"
# Caminhos separados por espaco; a lista so vale para .metal.
metal_permitidos=""
# A ponte JNI do Android (Kit/Sources/Android/CJNI) e C so para o Swift enxergar o jni.h do
# NDK: os dois arquivos so podem ter comentario, a guarda do cabecalho e esse include.
cjni=Kit/Sources/Android/CJNI
# O Kit inteiro, e nao so Sources e Tests: um alvo novo com a pasta ao lado delas (Kit/Vendor)
# passava (segunda passada da auditoria de 03/11/2026). So os builds ficam de fora.
achados=$(find App Kit \( -path Kit/.build -o -path Kit/.swiftpm \) -prune -o -type f \( "${nao_swift[@]}" \) -not -path "Kit/Sources/CArgon2/*" -not -path "Kit/Sources/CSecp256k1/*" -not -path "Kit/Sources/SwiftCrypto/*" -print 2>/dev/null \
    | while read -r fonte; do
        [[ "$fonte" == *.metal ]] && printf '%s\n' $metal_permitidos | grep -qxF "$fonte" && continue
        [[ "$fonte" == "$cjni/CJNI.c" || "$fonte" == "$cjni/include/CJNI.h" ]] && continue
        echo "$fonte"
    done)
[ -n "$achados" ] && { aviso "fonte que nao e Swift fora do C vendorizado (CArgon2, CSecp256k1 e SwiftCrypto)"; echo "$achados"; } \
    || ok "fora do C vendorizado (CArgon2, CSecp256k1 e SwiftCrypto), todo fonte e Swift"
# Nenhum modulo ja compilado nem biblioteca rastreada em lugar nenhum do repositorio: uma interface `Glibc.swiftinterface`
# ou um `module.map` achados por um caminho de busca faziam `canImport(Glibc)` valer no iPhone, e o leitor o da como falso
# (decima primeira passada da auditoria de 03/11/2026).
# Com `-z`: um caminho com acento sai entre aspas no `git ls-files` comum, e o `$` nao casava (decima segunda passada).
binarios=$(git ls-files -z | tr '\0' '\n' | grep -iE '\.(swiftinterface|swiftmodule|swiftdoc|swiftsourceinfo|swiftcrossimport|swiftoverlay|pcm|pch|tbd|a|o|bc|ll|sil|sib|apinotes|hmap|dylib|so(\.[0-9]+)*|framework|xcframework)(/|$)|(^|/)module\.map$')
[ -z "$binarios" ] && ok "nenhum modulo compilado, interface de modulo ou biblioteca rastreada no repositorio" \
    || { aviso "modulo compilado, interface de modulo ou biblioteca rastreada no repositorio"; echo "$binarios"; }
# Os modos da BoringSSL que deixam o sorteio deterministico ou ligam o modo de fuzzing, em nenhum arquivo rastreado fora do
# codigo dela (o Package.swift, os scripts, o projeto, o Gradle): no Android, a entropia da frase vem dela (decima segunda
# passada da auditoria de 03/11/2026). Os conferidores trazem os nomes nos casos de teste.
modos_inseguros=$(git grep -nE 'FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION|BORINGSSL_UNSAFE_DETERMINISTIC_MODE|BORINGSSL_UNSAFE_FUZZER_MODE|OPENSSL_RAND_DETERMINISTIC|BORINGSSL_UNSAFE' \
    -- ':!Kit/Sources/SwiftCrypto/' ':!tools/verificar.sh' ':!tools/flags-do-build.py' ':!tools/flags-do-pacote.py' 2>/dev/null)
[ -z "$modos_inseguros" ] && ok "nenhum modo inseguro da BoringSSL ligado fora do codigo dela" \
    || { aviso "modo inseguro da BoringSSL citado num arquivo de build"; echo "$modos_inseguros"; }
achados=$(cat "$cjni/CJNI.c" "$cjni/include/CJNI.h" 2>/dev/null | grep -vE '^\s*(//.*)?$|^#(ifndef|define|endif) CJNI_H|^#endif$|^#include (<jni\.h>|"CJNI\.h")$')
[ -n "$achados" ] && { aviso "a ponte JNI em C tem mais que o include do jni.h"; echo "$achados"; } \
    || ok "a ponte JNI em C so inclui o jni.h do NDK"
# Nada roda nem entra no binario por fora do fonte: fase de script de build (shell a cada
# build, com o repositorio e a rede na mao), acao de esquema, plugin do SwiftPM, framework
# ou biblioteca que nao e do SDK, flag de linker (carregaria codigo de fora). Hoje nao ha
# nenhum; o que for legitimo um dia entra aqui por nome.
pbx=EscaliburWallet.xcodeproj/project.pbxproj
achados=$( {
    grep -nE 'PBXShellScriptBuildPhase|shellScript|PBXBuildRule|OTHER_LDFLAGS|OTHER_LIBTOOLFLAGS|-Xlinker' "$pbx" | sed "s|^|$pbx:|"
    grep -nE '(lastKnownFileType|explicitFileType) = "?(wrapper\.(xc)?framework|archive\.ar|compiled\.mach-o\.dylib|sourcecode\.text-based-dylib-definition)' "$pbx" \
        | grep -v 'sourceTree = SDKROOT' | sed "s|^|$pbx:|"
    grep -nHE 'ShellScriptAction|<PreActions|<PostActions' EscaliburWallet.xcodeproj/xcshareddata/xcschemes/*.xcscheme
    grep -nE 'preBuildScripts|postCompileScripts|postBuildScripts|buildRules|buildToolPlugins|preActions|postActions|OTHER_LDFLAGS|OTHER_LIBTOOLFLAGS|-Xlinker|^[[:space:]]*- (framework|carthage|bundle):' project.yml \
        | sed 's|^|project.yml:|'
    grep -nE 'linkerSettings|\.plugin\(|plugins:|\.systemLibrary\(|linkedFramework|linkedLibrary' Kit/Package.swift | sed 's|^|Kit/Package.swift:|'
} 2>/dev/null)
[ -n "$achados" ] && { aviso "script de build, framework fora do SDK ou flag de linker no projeto"; echo "$achados"; } \
    || ok "sem fase de script, acao de esquema, plugin de build, framework fora do SDK nem flag de linker"
# Excecao estreita da regra 27: flag de compilacao so no C vendorizado, e so estas. A pilha
# zerada e o alocador por tipo do Enhanced Security nao chegam ao pacote pelo projeto, e o
# -O3 paga no Argon2 o custo do arm64e. Exatamente uma ocorrencia em cada alvo C, numa
# linha so, com a lista literal e presa as plataformas da Apple (o clang do NDK nao conhece o
# alocador por tipo; no Android a pilha zerada vai por -Xcc no compilar-nucleo.sh); variavel,
# condicao diferente, outro alvo ou outra flag falham (auditoria 4, C7-23; auditoria iOS de 31/10/2026, AI-01).
flags_c="-O3 -ftrivial-auto-var-init=zero -ftyped-memory-operations"
problemas=""
total=$(grep -o 'unsafeFlags' Kit/Package.swift | wc -l | tr -d ' ')
[ "$total" = "2" ] || problemas="$problemas; $total ocorrencias de unsafeFlags (o permitido e uma no CArgon2 e uma no CSecp256k1)"
vistos=""; pares=""
while IFS='|' read -r alvo linha; do
    [ -z "$alvo$linha" ] && continue
    case "$alvo" in CArgon2|CSecp256k1) vistos="$vistos $alvo" ;; *) problemas="$problemas; unsafeFlags no alvo ${alvo:-desconhecido}"; continue ;; esac
    echo "$linha" | grep -qE '^[[:space:]]*\.unsafeFlags\(\[("[^"]+", )*"[^"]+"\], \.when\(platforms: \[\.iOS, \.macOS\]\)\),?[[:space:]]*$' \
        || { problemas="$problemas; $alvo: unsafeFlags fora da forma literal de uma linha presa a iOS e macOS"; continue; }
    while IFS= read -r flag; do
        printf '%s\n' $flags_c | grep -qxF -- "$flag" || problemas="$problemas; $alvo: flag fora da lista ($flag)"
        [ "$flag" = "-O3" ] && [ "$alvo" != "CArgon2" ] && problemas="$problemas; -O3 fora do CArgon2"
        pares="$pares $alvo:$flag"
    done < <(echo "$linha" | grep -oE '"[^"]+"' | tr -d '"')
done < <(awk '/^[[:space:]]*\/\//{next} match($0, /name: "[A-Za-z0-9_]+"/){alvo=substr($0, RSTART+7, RLENGTH-8)} /unsafeFlags/{print alvo"|"$0}' Kit/Package.swift)
[ "$(echo $vistos | tr ' ' '\n' | sort | tr '\n' ' ')" = "CArgon2 CSecp256k1 " ] || problemas="$problemas; unsafeFlags tem de estar uma vez no CArgon2 e uma no CSecp256k1 (achado:${vistos:- nenhum})"
for par in CArgon2:-ftrivial-auto-var-init=zero CArgon2:-ftyped-memory-operations CSecp256k1:-ftrivial-auto-var-init=zero CSecp256k1:-ftyped-memory-operations; do
    case " $pares " in *" $par "*) ;; *) problemas="$problemas; falta ${par#*:} no ${par%%:*}" ;; esac
done
[ -n "$problemas" ] && aviso "flags de compilacao fora da excecao da regra 27: ${problemas#; }" \
    || ok "flags de compilacao so no C vendorizado: pilha zerada e alocador por tipo nos dois, -O3 so no Argon2"
# E no Android, a pilha zerada no C vai pelo script do nucleo (o clang do NDK nao tem o alocador por tipo).
codigo tools/android/compilar-nucleo.sh | grep -q -- '-Xcc -ftrivial-auto-var-init=zero' \
    && ok "pilha zerada no C tambem no nucleo do Android (compilar-nucleo.sh)" || aviso "compilar-nucleo.sh sem -ftrivial-auto-var-init=zero"
# Enhanced Security (Xcode 26) no projeto inteiro. Os quatro ajustes so aparecem na forma
# simples e valendo YES, onde quer que estejam: um NO (ou um condicional por SDK ou
# arquitetura) num alvo desligaria o arm64e, a pilha zerada ou o alocador por tipo sem
# mudar nenhum entitlement.
seguranca_build='ENABLE_ENHANCED_SECURITY|ENABLE_POINTER_AUTHENTICATION|CLANG_ENABLE_STACK_ZERO_INIT|CLANG_ENABLE_C_TYPED_ALLOCATOR_SUPPORT'
achados=$( {
    grep -nE "$seguranca_build" project.yml | grep -vE "^[0-9]+:[[:space:]]*#" \
        | grep -vE "^[0-9]+:[[:space:]]*($seguranca_build): YES$" | sed 's|^|project.yml:|'
    grep -nE "$seguranca_build" "$pbx" | grep -vE "^[0-9]+:[[:space:]]*($seguranca_build) = YES;$" | sed "s|^|$pbx:|"
    find . -name "*.xcconfig" -not -path "./build/*" -not -path "*/.build/*" -not -path "./.git/*" -not -path "./.claude/*" -print0 \
        | xargs -0 grep -nHE "$seguranca_build" | grep -vE "^[^:]+:[0-9]+:[[:space:]]*//" \
        | grep -vE "^[^:]+:[0-9]+:[[:space:]]*($seguranca_build)[[:space:]]*=[[:space:]]*YES[[:space:]]*$"
} 2>/dev/null)
base_es=$(awk '/^settings:/{f=1;next} /^[^[:space:]#]/{f=0} f && /^    ENABLE_ENHANCED_SECURITY: YES$/' project.yml)
cfgs_es=$(awk '/^[[:space:]]*[0-9A-F]+ \/\* [^*]+ \*\/ = \{/{ match($0, /\/\* [^*]+ \*\//); cfg=substr($0, RSTART+3, RLENGTH-6) }
    /ENABLE_ENHANCED_SECURITY = YES;/{print cfg}' "$pbx" | sort -u | tr '\n' ' ')
if [ -n "$achados" ]; then
    aviso "Enhanced Security desligado em algum ajuste do projeto"; echo "$achados"
elif [ -z "$base_es" ] || [ "$cfgs_es" != "Debug Release " ]; then
    aviso "ENABLE_ENHANCED_SECURITY: YES fora de settings.base do project.yml ou do Debug e do Release no pbxproj"
else
    ok "Enhanced Security ligado no projeto (Debug e Release), sem nenhum ajuste que o desligue"
fi
# O Kit (pacote local) so sai em arm64e com este ajuste do workspace; sem ele a fatia arm64e
# do app nao acha os modulos do Kit. O arquivo e versionado e o xcodegen nao o gera.
ajustes_ws=EscaliburWallet.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings
if [ "$(plutil -extract iOSPackagesShouldBuildARM64e raw -expect bool "$ajustes_ws" 2>/dev/null)" != "true" ]; then
    aviso "iOSPackagesShouldBuildARM64e ausente ou falso em $ajustes_ws"
elif git check-ignore -q "$ajustes_ws" 2>/dev/null; then
    aviso "$ajustes_ws ignorado pelo git: nao chegaria ao CI nem a quem clona"
else
    ok "o Kit tambem sai em arm64e (iOSPackagesShouldBuildARM64e no WorkspaceSettings.xcsettings versionado)"
fi
# Os avisos de memoria do clang sobre os dois C, com os mesmos -D, -I e fontes do
# Package.swift, so de leitura (-fsyntax-only: nada e compilado nem gravado). O C e
# travado por digesto: um aviso aqui e para revisar o upstream, nunca para editar o fonte.
alvo_c() {
    awk -v alvo="$1" '
        /^[[:space:]]*\/\// { next }
        match($0, /name: "[A-Za-z0-9_]+"/) { atual = substr($0, RSTART + 7, RLENGTH - 8) }
        atual != alvo { next }
        match($0, /path: "[^"]+"/) { base = "Kit/" substr($0, RSTART + 7, RLENGTH - 8) }
        match($0, /publicHeadersPath: "[^"]+"/) { print "I " base "/" substr($0, RSTART + 20, RLENGTH - 21) }
        match($0, /\.headerSearchPath\("[^"]+"\)/) { print "I " base "/" substr($0, RSTART + 19, RLENGTH - 21) }
        match($0, /\.define\("[^"]+", to: "[^"]+"\)/) {
            d = substr($0, RSTART + 9, RLENGTH - 11); gsub(/", to: "/, "=", d); print "D " d
        }
        /sources: \[/ { em_fontes = 1 }
        em_fontes {
            linha = $0; sub(/.*sources: \[/, "", linha)
            while (match(linha, /"[^"]+"/)) { print "S " base "/" substr(linha, RSTART + 1, RLENGTH - 2); linha = substr(linha, RSTART + RLENGTH) }
            if ($0 ~ /\]/) em_fontes = 0
        }' Kit/Package.swift
}
avisos_c=(-Wshadow -Wempty-body -Wbuiltin-memcpy-chk-size -Wformat-nonliteral -Warray-bounds -Warray-bounds-pointer-arithmetic
    -Wsuspicious-memaccess -Wsizeof-array-div -Wsizeof-pointer-div -Wreturn-stack-address)
saida_c=""
for alvo in CSecp256k1 CArgon2; do
    args_c=(); fontes_c=()
    while read -r tipo valor; do
        case "$tipo" in D) args_c+=("-D$valor") ;; I) args_c+=(-I "$valor") ;; S) fontes_c+=("$valor") ;; esac
    done < <(alvo_c "$alvo")
    if [ "${#fontes_c[@]}" = "0" ]; then
        saida_c="$saida_c$alvo: nenhum fonte lido do Package.swift"$'\n'
    elif ! saida=$(xcrun clang -fsyntax-only -Werror "${avisos_c[@]}" ${args_c[@]+"${args_c[@]}"} "${fontes_c[@]}" 2>&1); then
        saida_c="$saida_c$saida"$'\n'
    fi
done
[ -n "$saida_c" ] && { aviso "aviso de memoria do clang no C vendorizado"; echo "$saida_c" | grep -E 'error|warning' | head -20; } \
    || ok "nenhum aviso de memoria do clang no C vendorizado (sombra, limites, memcpy, sizeof, formato, pilha devolvida)"

# 3c. Workflows do GitHub. O que roda no CI e no release tambem e cadeia de suprimentos:
# toda acao e da propria GitHub (actions/ ou github/) e fixada por commit, 40 hexadecimais,
# nunca por tag movel; a outra forma aceita e um workflow deste repositorio. O repositorio
# exige o mesmo nas configuracoes, mas so o dono ve; aqui qualquer um confere. E segredo
# so aparece em job do environment release, o que tem revisor obrigatorio
# (docs/release.md); passar segredo adiante (`secrets:`) tambem falha.
secao "workflows"
# Toda chave `uses`, em qualquer grafia (entre aspas, num `{ }` ou com espaco antes dos dois pontos), e so a forma
# simples com o valor aceito passa (setima passada da auditoria de 03/11/2026).
achados=$(grep -HnE "(^|[[:space:]{,-])[\"']?uses[\"']?[[:space:]]*:" .github/workflows/*.yml \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*((actions|github)/[A-Za-z0-9._/-]+@[0-9a-f]{40}|\./\.github/workflows/[A-Za-z0-9._-]+\.yml)([[:space:]]+#.*)?[[:space:]]*$')
# E no YAML lido (o Ruby do sistema, o mesmo Psych dos runners), e nao so na linha: chave com escape (`"\x75ses"`),
# chave explicita (`? uses`) e apelido como chave passavam no grep; e nenhuma dessas tres formas nos workflows (oitava
# passada da auditoria de 03/11/2026). Nenhuma chave `shell`, em lugar nenhum: o leitor so le o `run:` como bash, e uma
# grafia de `shell:` que ele nao visse fazia o passo rodar outra coisa (decima passada).
lidos=$(ruby -ryaml -e '
    aceito = %r{\A((actions|github)/[A-Za-z0-9._/-]+@[0-9a-f]{40}|\./\.github/workflows/[A-Za-z0-9._-]+\.yml)\z}
    ruins = []
    olhar = lambda do |no, arquivo|
        case no
        when Hash then no.each { |chave, valor| ruins << "#{arquivo}: #{valor.inspect}" if chave.to_s == "uses" && !(valor.is_a?(String) && valor =~ aceito); ruins << "#{arquivo}: shell #{valor.inspect}" if chave.to_s == "shell"; olhar.(chave, arquivo); olhar.(valor, arquivo) }
        when Array then no.each { |item| olhar.(item, arquivo) }
        end
    end
    ARGV.each { |arquivo| olhar.(YAML.load_file(arquivo), arquivo) }
    puts ruins
    exit(ruins.empty? ? 0 : 1)' .github/workflows/*.yml 2>&1)
estranhas=$(grep -HnE '^[[:space:]-]*\?([[:space:]]|$)|"[^"]*\\[^"]*"[[:space:]]*:|^[[:space:]-]*\*[A-Za-z0-9_-]+[[:space:]]*:' .github/workflows/*.yml)
# O GitHub roda tambem `.yaml` e acao local em `.github/actions`, e as regras so leem `*.yml` (nona passada); e o
# `*.yml` do shell nao pega o nome com ponto no comeco, que o GitHub roda (decima passada).
estranhas="$estranhas$(find .github/workflows -mindepth 1 \( -name '.*' -o ! -type f -o ! -name '*.yml' \) 2>/dev/null)$(find .github/actions 2>/dev/null | head -1)"
[ -n "$achados" ] || [ -n "$lidos" ] || [ -n "$estranhas" ] && { aviso "acao de fora da GitHub ou sem SHA num workflow, chave shell ou workflow fora do *.yml"; echo "$achados$lidos$estranhas"; } \
    || ok "toda acao dos workflows vem da propria GitHub, fixada por SHA (na linha e no YAML lido), e sem shell que nao o bash"
# Exatamente os tres workflows, com os jobs de hoje e sem `name:` de job: o build da loja confia no job `verificar` do
# verificar.yml, e um outro com esse nome passava por ele (decima segunda passada da auditoria de 03/11/2026).
jobs_lidos=$(ruby -ryaml -e '
    esperados = { "release.yml" => %w[assinatura verificar montar], "site.yml" => %w[montar publicar], "verificar.yml" => %w[verificar] }
    lidos = Dir.children(".github/workflows").sort
    ruins = lidos == esperados.keys.sort ? [] : ["workflows: #{lidos.inspect}"]
    esperados.each do |arquivo, jobs|
        caminho = ".github/workflows/#{arquivo}"
        next unless File.file?(caminho)
        y = YAML.load_file(caminho)
        ruins << "#{arquivo}: jobs #{y["jobs"].keys.inspect}" unless y["jobs"].is_a?(Hash) && y["jobs"].keys == jobs
        (y["jobs"] || {}).each { |nome, job| ruins << "#{arquivo}: #{nome} com name" if job.is_a?(Hash) && job.key?("name") }
    end
    puts ruins
    exit(ruins.empty? ? 0 : 1)' 2>&1)
[ -z "$jobs_lidos" ] && ok "exatamente os tres workflows, com os jobs de hoje e sem nome trocado" \
    || { aviso "workflow a mais, job novo ou job com outro nome"; echo "$jobs_lidos"; }
achados=$(awk '
    function fecha(   i) { if (job != "" && !release) for (i = 1; i <= n; i++) print guardadas[i]; job = ""; n = 0; release = 0 }
    FNR == 1 { fecha(); emjobs = 0 }
    /^jobs:/ { emjobs = 1; next }
    emjobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { fecha(); job = $1; next }
    /^[[:space:]]*#/ { next }
    job != "" && /^    environment:[[:space:]]*release[[:space:]]*$/ { release = 1 }
    /^[[:space:]]*secrets:/ { print FILENAME ":" FNR ": " $0; next }
    /secrets\./ { if (job == "") print FILENAME ":" FNR ": " $0; else guardadas[++n] = FILENAME ":" FNR ": " $0 }
    END { fecha() }
' .github/workflows/*.yml)
[ -n "$achados" ] && { aviso "segredo fora de job do environment release"; echo "$achados"; } \
    || ok "segredo so em job do environment release"

# 4. Codigo vendorizado travado por digesto.
secao "codigo vendorizado"
conferir_lock() {
    local lock="$1" base="$2" nome="$3"
    local divergentes=0 total=0
    # O lock que sumiu ou ficou vazio nao confere nada: falha (quarta passada da auditoria de 03/11/2026).
    [ -s "$lock" ] || { aviso "$lock ausente ou vazio"; return; }
    while IFS= read -r linha; do
        arquivo=$(echo "$linha" | sed -n 's/^    "\([^"]*\)": "\([0-9a-f]\{64\}\)".*/\1/p')
        esperado=$(echo "$linha" | sed -n 's/^    "\([^"]*\)": "\([0-9a-f]\{64\}\)".*/\2/p')
        [ -z "$arquivo" ] && continue
        total=$((total + 1))
        atual=$(shasum -a 256 "$base/$arquivo" 2>/dev/null | cut -d' ' -f1)
        [ "$atual" != "$esperado" ] && { aviso "$nome/$arquivo nao confere"; divergentes=$((divergentes + 1)); }
    done < "$lock"
    [ "$total" -gt 0 ] || { aviso "$lock sem nenhum arquivo"; return; }
    [ "$divergentes" = "0" ] && ok "$total arquivos de $nome conferem com $lock"
}
conferir_lock secp256k1.lock Kit/Sources/CSecp256k1/upstream secp256k1
conferir_lock argon2.lock Kit/Sources/CArgon2 argon2
# A cola em C da Escalibur em volta deles, pelo digesto, e nenhum arquivo nas pastas do C fora dos
# tres locks (auditoria de 03/11/2026: um construtor que abria socket no arquivo de cola passava).
conferir_lock cola-c.lock . "cola em C"
fora_do_c=$(comm -23 <( { (cd Kit/Sources/CArgon2 && find . -type f | sed 's#^\./#Kit/Sources/CArgon2/#'); \
        (cd Kit/Sources/CSecp256k1 && find . -type f | sed 's#^\./#Kit/Sources/CSecp256k1/#'); } | sort) \
    <( (sed -n 's#^    "\([^"]*\)": "[0-9a-f]\{64\}".*#Kit/Sources/CArgon2/\1#p' argon2.lock; \
        sed -n 's#^    "\([^"]*\)": "[0-9a-f]\{64\}".*#Kit/Sources/CSecp256k1/upstream/\1#p' secp256k1.lock; \
        sed -n 's#^    "\([^"]*\)": "[0-9a-f]\{64\}".*#\1#p' cola-c.lock) | sort))
[ -n "$fora_do_c" ] && { aviso "arquivo no C do Argon2 ou da secp256k1 fora dos locks"; echo "$fora_do_c"; } \
    || ok "as pastas do Argon2 e da secp256k1 so tem o que os locks listam"
# O C do nucleo do Android, de cada configuracao compilada nesta maquina (o compilar-nucleo.sh tambem
# confere a que acabou de sair).
for configuracao in $(configuracoes_android); do conferir_simbolos_do_c android "$configuracao"; conferir_trava_do_segredo "$configuracao"; done
# A swift-crypto (so no build Android): cada arquivo igual ao do commit da versao, e nenhum a
# mais na pasta.
conferir_lock swift-crypto.lock Kit/Sources/SwiftCrypto swift-crypto
fora_da_swift_crypto=$(comm -23 <(cd Kit/Sources/SwiftCrypto && find . -type f | sed 's#^\./##' | sort) \
    <(sed -n 's/^    "\([^"]*\)": "[0-9a-f]\{64\}".*/\1/p' swift-crypto.lock | sort))
[ -n "$fora_da_swift_crypto" ] && { aviso "arquivo na swift-crypto fora do swift-crypto.lock"; echo "$fora_da_swift_crypto"; } \
    || ok "a pasta da swift-crypto so tem o que o swift-crypto.lock lista"
# O remendo da swift-crypto: o AEADContext zera o EVP_AEAD_CTX ao sair (auditoria das chaves de 06/11/2026). Uma troca da
# swift-crypto que o perca deixa a chave do AES-GCM e do ChaCha no heap liberado do Android.
# Como codigo, pelo leitor do compilador: a linha comentada nao conta (rodada 3).
python3 -I tools/codigo.py --exige Kit/Sources/SwiftCrypto/CryptoBoringWrapper/AEAD/BoringSSLAEAD.swift \
    'CCryptoBoringSSL_OPENSSL_cleanse(contextPointer, MemoryLayout<EVP_AEAD_CTX>.size)' --plataforma android \
    && ok "o AEAD da swift-crypto zera a chave ao sair (remendo)" || aviso "o remendo que zera o EVP_AEAD_CTX saiu da swift-crypto"
conferir_lock modelos.lock App/EscaliburWallet/Resources/Moeda3D "moeda 3D"
fora_do_lock=$(comm -23 <(ls App/EscaliburWallet/Resources/Moeda3D | sort) <(sed -n 's/^    "\([^"]*\)": "[0-9a-f]\{64\}".*/\1/p' modelos.lock | sort))
[ -n "$fora_do_lock" ] && { aviso "arquivo na moeda 3D fora do modelos.lock"; echo "$fora_do_lock"; } || ok "a pasta da moeda 3D so tem o que o modelos.lock lista"
divergentes=0
for idioma in $(sed -n 's/^ *"\([a-z_]*\)": "[0-9a-f]*".*/\1/p' wordlists.lock); do
    esperado=$(sed -n "s/^ *\"$idioma\": \"\([0-9a-f]*\)\".*/\1/p" wordlists.lock)
    atual=$(shasum -a 256 "$CORE/Resources/Wordlists/$idioma.txt" | cut -d' ' -f1)
    [ "$atual" != "$esperado" ] && { aviso "lista $idioma nao confere"; divergentes=$((divergentes + 1)); }
done
[ "$divergentes" = "0" ] && ok "as 10 listas BIP-39 conferem com wordlists.lock"
divergentes=0
for lista in $(sed -n 's/^ *"\([a-z-]*\)": "[0-9a-f]*".*/\1/p' forca.lock); do
    esperado=$(sed -n "s/^ *\"$lista\": \"\([0-9a-f]*\)\".*/\1/p" forca.lock)
    atual=$(shasum -a 256 "$CORE/Resources/Forca/$lista.txt" | cut -d' ' -f1)
    [ "$atual" != "$esperado" ] && { aviso "lista de forca $lista nao confere"; divergentes=$((divergentes + 1)); }
done
[ "$divergentes" = "0" ] && ok "as listas do medidor de forca conferem com forca.lock"

# 5. Registro e aleatoriedade.
# Decifrador de referencia (so para os testes, fora do app): decifrar.py e FORMATO.md
# travados por digesto. O app nao distribui decifrador para computador.
if (cd tools/referencia && shasum -a 256 -c ../../recuperacao.lock >/dev/null 2>&1); then
    ok "decifrador de referencia confere com recuperacao.lock"
else
    aviso "decifrador de referencia difere de recuperacao.lock"
fi
[ -e "$APP/Resources/Recuperacao" ] && aviso "decifrador para computador de volta no app" || ok "nenhum decifrador para computador dentro do app"

secao "registro e aleatoriedade"
achados=$(procurar '(^|[^A-Za-z0-9_.])(print|debugPrint|dump|NSLog)\(' "$APP" "$CORE" "$CHAINS" "$KEYS" "$NET")
[ -n "$achados" ] && { aviso "print/NSLog fora dos testes"; echo "$achados"; } || ok "nenhum print fora dos testes"
achados=$(procurar 'Logger\(|os_log' "$KEYS" "$CHAINS")
[ -n "$achados" ] && { aviso "logger no modulo de chaves ou de redes"; echo "$achados"; } || ok "chaves e redes nao registram nada"
achados=$(procurar '\.random\(|randomElement|shuffled\(\)|arc4random|drand48|\brand\(|SystemRandomNumberGenerator|GKRandom' "$CORE" "$CHAINS" "$KEYS" "$APP" "$APPA" | grep -v 'SecureBytes\.random(')
[ -n "$achados" ] && { aviso "aleatoriedade fora do SecRandomCopyBytes"; echo "$achados"; } || ok "a unica fonte de aleatoriedade e o SecRandomCopyBytes"

# 6. Chaveiro e biometria.
secao "chaveiro e biometria"
achados=$(swift_em "$APP" "$CORE" "$CHAINS" "$KEYS" "$NET" | xargs grep -lE 'SecItemAdd|SecItemUpdate|SecKeyCreateRandomKey' 2>/dev/null | grep -vE "$KEYS/(SecretStore|Enclave)\.swift")
[ -n "$achados" ] && { aviso "chamada ao chaveiro fora de SecretStore/Enclave"; echo "$achados"; } || ok "chaveiro so em SecretStore.swift e Enclave.swift"
# Tambem os outros caminhos para uma flag que sobrevive a um rosto novo: o nome antigo
# (.touchIDAny), as flags montadas por numero (rawValue) e flags(for:) chamada com uma chave
# escrita (so a propria chave de cada criacao passa por ela).
achados=$(procurar 'AfterFirstUnlock|AccessibleAlways|kSecAttrAccessibleWhenUnlocked\b|SynchronizableAny|\.userPresence|\.devicePasscode|\.or\b|kSecAttrSynchronizable as String: kCFBooleanTrue|\.touchIDAny|SecAccessControlCreateFlags\(rawValue|flags\(for: *\.' "$APP" "$KEYS")
[ -n "$achados" ] && { aviso "protecao fraca de chaveiro ou biometria"; echo "$achados"; } || ok "sem userPresence, devicePasscode, .or, touchIDAny, flags por numero, AfterFirstUnlock, WhenUnlocked sem ThisDeviceOnly"
# O .biometryAny tem uma excecao so: a kand.qualquer, a camada de fora do modo reforcado que
# sobrevive a um rosto novo (docs/seguranca.md §2.6), na linha dela em flags(for:) do
# Enclave.swift. Ela nunca abre nada sozinha: o unico embrulho com ela e o do miolo (que ainda
# pede o PIN pela kand.pin), no construtor do registro, e o app nem a nomeia.
excecao_any=$(awk '/static func flags\(for slot: WrapSlot\)/{f=1} f&&/^    }$/{f=0} f&&/^        case \.hardenedBiometryAny: return \[\.privateKeyUsage, \.biometryAny\]$/{print FILENAME":"FNR}' "$KEYS/Enclave.swift")
achados=$(procurar '\.biometryAny' "$APP" "$KEYS")
if [ "$(echo "$excecao_any" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]; then
    aviso "a excecao do .biometryAny saiu de flags(for:) da kand.qualquer"
    echo "$achados"
else
    fora=$(echo "$achados" | sed '/^$/d' | grep -vF "$excecao_any:")
    [ -n "$fora" ] && { aviso ".biometryAny fora da kand.qualquer em flags(for:)"; echo "$fora"; } || ok "biometryAny so na kand.qualquer, em flags(for:) do Enclave.swift"
fi
embrulho_any=$(awk '/private func buildHardenedRecord\(/{f=1} f&&/^    }$/{f=0} f&&/^            layers\[\.hardenedBiometryAny\] = try wrapper\.wrap\(middle, slot: \.hardenedBiometryAny\)$/{print FILENAME":"FNR}' "$KEYS/RootKeyVault.swift")
achados=$(procurar 'slot: *\.hardenedBiometryAny|wrap\([^)]*\.hardenedBiometryAny' "$APP" "$KEYS")
if [ "$(echo "$embrulho_any" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]; then
    aviso "o embrulho do miolo pela kand.qualquer saiu do construtor do registro"
    echo "$achados"
else
    fora=$(echo "$achados" | sed '/^$/d' | grep -vF "$embrulho_any:")
    [ -n "$fora" ] && { aviso "kand.qualquer embrulhando fora do construtor do registro"; echo "$fora"; } || ok "a kand.qualquer so embrulha o miolo, no construtor do registro"
fi
achados=$(procurar 'hardenedBiometryAny|kand\.qualquer' "$APP")
[ -n "$achados" ] && { aviso "o app nomeia a kand.qualquer"; echo "$achados"; } || ok "o app nao nomeia a kand.qualquer"
# O Keychain so existe no iPhone (no Android, o cofre e o Keystore, conferido nas regras do Android).
if ! codigo_vivo_ios "$KEYS/SecretStore.swift" | grep -q 'kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly'; then aviso "WhenPasscodeSetThisDeviceOnly sumiu"; else ok "itens em WhenPasscodeSetThisDeviceOnly"; fi
# A unica excecao (simulador) precisa estar atras de targetEnvironment(simulator).
excecao=$(awk '/#if targetEnvironment\(simulator\)/{d=1} /#else|#endif/{d=0} /kSecAttrAccessibleWhenUnlockedThisDeviceOnly/{ if(!d) print FILENAME": "NR }' "$KEYS/SecretStore.swift")
[ -n "$excecao" ] && { aviso "classe de simulador fora do bloco de simulador"; echo "$excecao"; } || ok "a excecao do simulador so compila para simulador"
achados=$(awk 'FNR==1{d=0} /#if targetEnvironment\(simulator\)/{d=1} /#else|#endif/{d=0} /SimulatorWrapper\(\)|SoftwareWrapper\(\)/{ if(!d) print FILENAME": "FNR": "$0 }' $(swift_em "$APP" "$KEYS"))
[ -n "$achados" ] && { aviso "embrulho em software fora do simulador"; echo "$achados"; } || ok "embrulho em software so no simulador e nos testes"
achados=$(swift_em "$CORE" "$CHAINS" "$KEYS" "$NET" | xargs grep -nE 'class (MemoryStore|SoftwareWrapper)\b' 2>/dev/null)
[ -n "$achados" ] && { aviso "duble de teste dentro do codigo que vai para o app"; echo "$achados"; } || ok "armazenamento em memoria e embrulho em software so existem nos testes"
achados=$(swift_em "$APP" "$KEYS" | xargs grep -n 'evaluatePolicy(' 2>/dev/null | grep -v 'canEvaluatePolicy' | grep -v "$APP/Services/KeyServices.swift")
[ -n "$achados" ] && { aviso "evaluatePolicy fora do simulador (booleano nao autoriza nada)"; echo "$achados"; } || ok "nenhum booleano de biometria autoriza operacao"

# 6b. Segredo em String e comparacao de segredo. Grep com falso positivo possivel:
# cada excecao e uma linha em tools/excecoes.allow ("arquivo|trecho|por que"),
# revisada como codigo.
secao "segredo"
filtrar_excecoes() {
    local entrada
    entrada=$(cat)
    [ -z "$entrada" ] && return
    while IFS='|' read -r arquivo trecho _; do
        [ -z "$arquivo" ] || [ "${arquivo#\#}" != "$arquivo" ] && continue
        entrada=$(echo "$entrada" | grep -vF "$arquivo:" ; echo "$entrada" | grep -F "$arquivo:" | grep -vF "$trecho")
        entrada=$(echo "$entrada" | sed '/^$/d')
    done < tools/excecoes.allow
    echo "$entrada"
}
achados=$(swift_em "$APP" "$CORE" "$CHAINS" "$KEYS" "$NET" "$ENG" | xargs grep -niE '(var|let) +[A-Za-z_]*(pin|senha|password|seed|mnemonic|phrase|entropy|privatekey|secret)[A-Za-z_]* *(: *String|= *"")|@State[^=]*(pin|senha|seed|mnemonic|phrase)[A-Za-z_]* *(: *String|= *"")' 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' | filtrar_excecoes)
[ -n "$achados" ] && { aviso "segredo guardado em String"; echo "$achados"; } || ok "nenhum segredo guardado em String (fora das excecoes revisadas)"
achados=$(procurar '(digest|tag|mac|hmac|secret|key)[A-Za-z_]* *[!=]=' "$KEYS" | filtrar_excecoes)
[ -n "$achados" ] && { aviso "segredo comparado com == (use Hash.constantTimeEqual)"; echo "$achados"; } || ok "segredo so comparado em tempo constante no modulo de chaves"
achados=$(procurar '(Data|String|NSData|NSString|NSArray|NSDictionary)\(contentsOf: *URL\(string' "$APP" "$CORE" "$CHAINS" "$KEYS" "$NET" "$ENG")
[ -n "$achados" ] && { aviso "leitura de URL remota fora do cliente HTTP"; echo "$achados"; } || ok "nenhuma leitura de rede por contentsOf"
achados=$(procurar '(Data|String|NSData|NSString)\(contentsOf:' "$CHAINS" "$KEYS" "$ENG")
[ -n "$achados" ] && { aviso "leitura de arquivo em redes, chaves ou motores"; echo "$achados"; } || ok "redes, chaves e motores nao leem arquivo"
# `contentsOf:` le de URL em variavel tambem, e uma URL https sairia por fora do HTTPClient. No
# modulo de rede e no widget, cada leitura de arquivo e uma excecao revisada (auditoria de 31/10/2026).
achados=$(procurar '\b(Data|String|NSData|NSString|NSArray|NSDictionary|XMLParser|NSAttributedString|UIImage|CIImage|PDFDocument)(\.init)?\(contentsOf:|\.init\(contentsOf:' "$WID" "$SHARED" "$NET" | filtrar_excecoes)
[ -n "$achados" ] && { aviso "contentsOf: fora das leituras de arquivo revisadas"; echo "$achados"; } || ok "no modulo de rede e no widget, toda leitura por contentsOf e de arquivo local revisado"

# 7. Plataforma.
secao "plataforma"
codigo_vivo "$APP/App/PlatformGuards.swift" | grep -q 'shouldAllowExtensionPointIdentifier' && codigo_vivo "$APP/App/PlatformGuards.swift" | grep -q '\.keyboard' \
    && ok "teclados de terceiros bloqueados" || aviso "bloqueio de teclado de terceiro sumiu"
codigo_vivo "$APP/App/PlatformGuards.swift" | grep -q 'willResignActiveNotification' && ok "cobertura antes da foto do seletor de apps" || aviso "cobertura do seletor sumiu"
codigo "$APP/Resources/EscaliburWallet.entitlements" | grep -q 'NSFileProtectionComplete' && ok "NSFileProtectionComplete em todo o conteiner" || aviso "protecao de arquivo sumiu"
codigo_vivo "$APP/App/PlatformGuards.swift" | grep -q 'sceneCaptureState' && codigo_vivo "$APP/App/PlatformGuards.swift" | grep -q 'isCaptured' \
    && ok "tela sensivel some com gravacao, espelhamento ou captura da cena" || aviso "defesa contra captura de tela incompleta"
# A camada segura contra captura acha a vista de desenho do campo seguro so pela
# hierarquia publica: nome de classe privada, seletor ou KVC ali e API privada por nome
# (docs/seguranca.md §7).
camada="$APP/Design/SecureCaptureContainer.swift"
if [ -f "$camada" ] && codigo_vivo "$camada" | grep -q 'isSecureTextEntry = true'; then
    achados=$(grep -nE 'NSClassFromString|NSSelectorFromString|Selector\(|#selector|forKey|perform\(|dlsym|objc_|"_[A-Za-z]' "$camada" | grep -vE '^[0-9]+:[[:space:]]*//')
    [ -n "$achados" ] && { aviso "camada segura contra captura com API privada por nome"; echo "$achados"; } || ok "camada segura contra captura so com API publica"
else
    aviso "camada segura contra captura sumiu"
fi
codigo_vivo "$APP/Services/Metadata.swift" | grep -q 'isExcludedFromBackup = true' && ok "metadados fora do backup do iCloud" || aviso "metadados podem ir para o backup"
# Protecao mais fraca que a Complete: so o marcador de instalacao, o arquivo dos
# alertas de preco (nao diz o que a carteira tem), o do aviso de recebimento (so os
# enderecos publicos), o das ordens limite abertas (so o UID de cada uma) com a chave dos resumos dos avisos de
# ordem (LimitOrderWatch.swift) e o do widget (so a moeda e o preco), que precisam abrir com o iPhone bloqueado.
achados=$(procurar 'UntilFirstUserAuthentication|completeUnlessOpen|CompleteUnlessOpen|FileProtectionType\.none|noFileProtection' "$APP" "$CORE" "$CHAINS" "$KEYS" "$NET" "$ENG" \
    | grep -vE "^$APP/(Services/KeyServices|Services/PriceAlerts|Services/ReceiptWatch|Services/LimitOrderWatch|Services/WidgetFeed)\.swift:")
[ -n "$achados" ] && { aviso "protecao de arquivo mais fraca fora das cinco excecoes"; echo "$achados"; } || ok "protecao abaixo da Complete so no marcador de instalacao, nos alertas de preco, no aviso de recebimento, nas ordens abertas e no widget"
# O widget: so o arquivo publico do preco. Quem grava nao toca cofre, chaveiro,
# metadados nem saldo; o widget nao importa o Kit, nao fala com a rede e nao le chaveiro.
widget_feed="$APP/Services/WidgetFeed.swift"
achados=$(grep -nE 'import (EscaliburKeys|EscaliburEngines|Security|LocalAuthentication)|KeyServices|RootKeyVault|SecretStore|MetadataStore|SecureBytes|AppSession|Portfolio|WalletMeta|DerivedAccount|balance|address' "$widget_feed" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//')
[ -n "$achados" ] && { aviso "o arquivo do widget toca cofre, chaveiro, metadados, saldo ou endereco"; echo "$achados"; } || ok "o arquivo do widget so leva a moeda e o preco, sem cofre, chaveiro, metadados, saldo nem endereco"
achados=$(find App/EscaliburWidgets App/Shared -name '*.swift' | xargs grep -nE 'import (Escalibur|Security|LocalAuthentication|Network)|URLSession|URLRequest|NWConnection|SecItem|Keychain|UserDefaults' 2>/dev/null)
[ -n "$achados" ] && { aviso "o widget importa o Kit, fala com a rede ou le o chaveiro"; echo "$achados"; } || ok "o widget so le o arquivo do App Group: sem Kit, sem rede, sem chaveiro"
# Enhanced Security (Xcode 26): as mesmas cinco chaves no app e no widget. A versao e as
# restricoes de plataforma vao como string; as chaves inteiras antigas (sem -string)
# impediam instalar no iOS 18 com o iOS 17 de minimo (Xcode 26.4). O checked-allocations
# (MIE) e qualquer soft-mode ficam de fora ate o teste num iPhone 17.
endurecido="com.apple.security.hardened-process com.apple.security.hardened-process.enhanced-security-version-string
    com.apple.security.hardened-process.platform-restrictions-string com.apple.security.hardened-process.hardened-heap
    com.apple.security.hardened-process.dyld-ro"
conjunto() { printf '%s\n' "$@" | sort | tr '\n' ' '; }
chaves_de() { /usr/libexec/PlistBuddy -c "Print" "$1" | grep -E '^\s+[a-z][^ ]* = ' | awk '{print $1}' | sort | tr '\n' ' '; }
# O plutil le o caminho com ponto como aninhamento: o ponto da chave vai escapado.
valor_de() { plutil -extract "${2//./\\.}" raw -expect "$3" "$1" 2>/dev/null; }
endurecido_errado() {
    local arquivo="$1" chave erros=""
    for chave in com.apple.security.hardened-process com.apple.security.hardened-process.hardened-heap com.apple.security.hardened-process.dyld-ro; do
        [ "$(valor_de "$arquivo" "$chave" bool)" = "true" ] || erros="$erros ${chave#com.apple.security.}"
    done
    [ "$(valor_de "$arquivo" com.apple.security.hardened-process.enhanced-security-version-string string)" = "1" ] || erros="$erros enhanced-security-version-string"
    [ "$(valor_de "$arquivo" com.apple.security.hardened-process.platform-restrictions-string string)" = "2" ] || erros="$erros platform-restrictions-string"
    grep -qE '<key>com\.apple\.security\.hardened-process\.(enhanced-security-version|platform-restrictions)</key>' "$arquivo" \
        && erros="$erros chave-inteira-antiga"
    grep -qiE '<key>[^<]*soft-mode[^<]*</key>' "$arquivo" && erros="$erros soft-mode"
    echo "$erros"
}
widget_ent=App/EscaliburWidgets/EscaliburWidgets.entitlements
chaves=$(chaves_de "$widget_ent")
grupos=$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups" "$widget_ent" 2>/dev/null | grep -c 'group.app.escalibur.wallet$')
[ "$chaves" = "$(conjunto com.apple.security.application-groups $endurecido)" ] && [ "$grupos" = "1" ] \
    && ok "entitlements do widget: so o App Group da carteira e o Enhanced Security" || aviso "entitlements do widget inesperados: $chaves"
erradas=$(endurecido_errado "$widget_ent")
[ -n "$erradas" ] && aviso "Enhanced Security do widget com valor ou tipo errado:$erradas" \
    || ok "Enhanced Security do widget: hardened-process, versao \"1\" e restricoes \"2\" como string, heap endurecido e dyld-ro"
recebimento="$APP/Services/ReceiptWatch.swift"
achados=$(grep -nE 'import (EscaliburKeys|Security|LocalAuthentication)|KeyServices|RootKeyVault|SecretStore|MetadataStore|SecureBytes|AppSession|Portfolio|WalletMeta|privateKey|mnemonic' "$recebimento" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//')
[ -n "$achados" ] && { aviso "o aviso de recebimento toca cofre, chaveiro ou metadados"; echo "$achados"; } || ok "o aviso de recebimento (segundo plano) so le enderecos publicos e saldo, sem cofre, chaveiro nem metadados"
ordens="$APP/Services/LimitOrderWatch.swift"
achados=$(grep -nE 'import (EscaliburKeys|EscaliburEngines|Security|LocalAuthentication)|KeyServices|RootKeyVault|SecretStore|MetadataStore|SecureBytes|AppSession|Portfolio|WalletMeta|DerivedAccount|privateKey|mnemonic' "$ordens" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//')
[ -n "$achados" ] && { aviso "o aviso das ordens limite toca cofre, chaveiro, conta ou metadados"; echo "$achados"; } || ok "o aviso das ordens limite (segundo plano) so le o UID e o andamento na CoW, sem cofre, chaveiro nem metadados"
alertas="$APP/Services/PriceAlerts.swift"
achados=$(grep -nE 'import (EscaliburKeys|Security|LocalAuthentication)|KeyServices|RootKeyVault|SecretStore|MetadataStore|SecureBytes|AppSession|Portfolio|balance' "$alertas" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//')
[ -n "$achados" ] && { aviso "os alertas de preco tocam cofre, chaveiro, metadados ou saldo"; echo "$achados"; } || ok "os alertas de preco (segundo plano) nao tocam cofre, chaveiro, metadados nem saldo"
achados=$(swift_em "$APP" "$CORE" "$CHAINS" "$KEYS" "$NET" "$ENG" | xargs grep -nE 'UserDefaults|@AppStorage' 2>/dev/null | grep -v "^$APP/App/Preferences.swift:")
[ -n "$achados" ] && { aviso "UserDefaults fora de Preferences.swift"; echo "$achados"; } || ok "UserDefaults so em Preferences.swift"
# Manifesto de privacidade: sem ele a App Store recusa o envio (API de motivo
# obrigatorio). Sem rastreamento, sem dado coletado, e o motivo do UserDefaults.
manifesto="$APP/Resources/PrivacyInfo.xcprivacy"
if plutil -lint "$manifesto" >/dev/null 2>&1 \
    && [ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$manifesto" 2>/dev/null)" = "false" ] \
    && [ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyCollectedDataTypes' "$manifesto" 2>/dev/null | grep -c Dict)" = "0" ] \
    && codigo "$manifesto" | grep -q 'NSPrivacyAccessedAPICategoryUserDefaults' && codigo "$manifesto" | grep -q 'CA92.1' \
    && codigo "$manifesto" | grep -q 'NSPrivacyAccessedAPICategorySystemBootTime' && codigo "$manifesto" | grep -q '35F9.1' \
    && codigo EscaliburWallet.xcodeproj/project.pbxproj | grep -q 'PrivacyInfo.xcprivacy'; then
    ok "manifesto de privacidade: sem rastreamento, sem coleta, motivos do UserDefaults e do tempo de boot, no projeto"
else
    aviso "manifesto de privacidade ausente, invalido ou fora do projeto"
fi
app_ent="$APP/Resources/EscaliburWallet.entitlements"
chaves=$(chaves_de "$app_ent")
grupos=$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups" "$app_ent" 2>/dev/null | grep -cE '^\s+group\.')
[ "$chaves" = "$(conjunto com.apple.developer.default-data-protection com.apple.security.application-groups $endurecido)" ] && [ "$grupos" = "1" ] \
    && ok "entitlements: a protecao de dados, um App Group so (o do widget) e o Enhanced Security" || aviso "entitlements inesperados: $chaves"
erradas=$(endurecido_errado "$app_ent")
[ -n "$erradas" ] && aviso "Enhanced Security do app com valor ou tipo errado:$erradas" \
    || ok "Enhanced Security do app: hardened-process, versao \"1\" e restricoes \"2\" como string, heap endurecido e dyld-ro"
achados=$(grep -oE 'NS[A-Za-z]+UsageDescription' "$APP/Resources/Info.plist" | sort -u | grep -vE 'NSFaceIDUsageDescription|NSCameraUsageDescription|NSMicrophoneUsageDescription|NSSpeechRecognitionUsageDescription')
[ -n "$achados" ] && { aviso "permissao fora da lista"; echo "$achados"; } || ok "permissoes: Face ID, camera, microfone e fala, nada mais"
achados=$(swift_em "$APP" | xargs grep -lE 'UIPasteboard' 2>/dev/null | grep -vE 'Receive/ReceiveSheet\.swift|NewWallet/ImportPhraseView\.swift|NewWallet/SecurityScreens\.swift|Design/Buttons\.swift')
[ -n "$achados" ] && { aviso "area de transferencia fora dos pontos conhecidos"; echo "$achados"; } || ok "area de transferencia so em quatro pontos"
# O Colar reserva (AppPasteButton) so le, e so quando o do sistema encolheu (30/10/2026).
achados=$(grep -n 'UIPasteboard' "$APP/Design/Buttons.swift" | grep -v 'UIPasteboard\.general\.string }')
[ -n "$achados" ] && { aviso "o Colar reserva faz mais que ler"; echo "$achados"; } || ok "o Colar reserva so le a area de transferencia"
# A checagem do aparelho nao olha a area de transferencia (tirada a pedido do dono, 22/10/2026).
achados=$(grep -nE 'UIPasteboard' "$APP/Features/NewWallet/SecurityScreens.swift")
[ -n "$achados" ] && { aviso "a checagem do aparelho mexe na area de transferencia"; echo "$achados"; } || ok "a checagem do aparelho nao olha a area de transferencia"
# Toda copia passa por setItems, local (nao vai para o Mac) e com validade. A frase vale
# no maximo 1 minuto e so sai pela tela das palavras, depois do aviso (CopyPhraseSheet).
f="$APP/Features/Receive/ReceiveSheet.swift"
# Todas as copias sao locais e a da frase e local com certeza. So o endereco de receber de uma
# carteira sem passphrase, fora do Super Security, vai tambem para o Mac (pedido do dono, 01/11/2026;
# auditoria de 03/11/2026): a unica copia sem localOnly e a de copyReceiveAddress, que pergunta a
# Pasteboard.macAllowed antes.
copias=$(grep -c 'UIPasteboard.general.setItems' "$f"); locais=$(grep -c '\.localOnly: true' "$f"); prazos=$(grep -c '\.expirationDate: Date().addingTimeInterval' "$f")
outras=$(grep -n 'UIPasteboard' "$f" | grep -v 'UIPasteboard.general.setItems' | grep -v 'var options: \[UIPasteboard.OptionsKey: Any\]')
endereco_local=$(awk '/static func copyReceiveAddress/,/^    }/' "$f" | grep -c 'guard macAllowed(session, hasPassphrase: hasPassphrase) else { return copyAddress(address) }')
frase_local=$(awk '/static func copyPhrase/,/^    }/' "$f" | grep -c '\.localOnly: true')
[ "$copias" -gt 0 ] && [ "$locais" = "$((copias - 1))" ] && [ "$endereco_local" = "1" ] && [ "$frase_local" = "1" ] && [ "$copias" = "$prazos" ] && [ -z "$outras" ] \
    && ok "toda copia expira e e local; so o endereco de receber pode ir ao Mac" || aviso "copia sem localOnly/expiracao"
soltos=$(procurar 'toMac|localOnly: false|\.localOnly\] = false' "$APP")
[ -z "$soltos" ] && ok "todo endereco que vai ao Mac passa por Pasteboard.macAllowed (sem passphrase, fora do Super Security)" \
    || { aviso "copia para o Mac fora de copyReceiveAddress"; echo "$soltos"; }
prazo=$(awk '/static func copyPhrase/,/^    }/' "$f" | grep -oE 'addingTimeInterval\([0-9]+\)' | grep -oE '[0-9]+')
chamadas=$(procurar 'Pasteboard\.copyPhrase' "$APP" | grep -v 'Receive/ReceiveSheet\.swift:')
[ -n "$prazo" ] && [ "$prazo" -le 60 ] && [ "$(echo "$chamadas" | grep -c .)" = "1" ] && echo "$chamadas" | grep -q 'NewWallet/RecordWordsView\.swift:' \
    && codigo_vivo "$APP/Features/NewWallet/RecordWordsView.swift" | grep -q 'CopyPhraseSheet {' \
    && ok "a frase so e copiada depois do aviso e some em ate 1 minuto" || { aviso "copia da frase fora do aviso ou com validade longa"; echo "$chamadas"; }
achados=$(procurar '^[[:space:]]*import +(Firebase[A-Za-z]*|Crashlytics|Sentry|Bugsnag|Amplitude|Mixpanel|Segment|AppsFlyer[A-Za-z]*|Adjust[A-Za-z]*|Branch|OneSignal|Datadog[A-Za-z]*|NewRelic|Instabug|FBSDK[A-Za-z]*|GoogleMobileAds|PostHog)\b' "$APP" "$APPA" "$NET" "$CORE" "$CHAINS" "$KEYS")
[ -n "$achados" ] && { aviso "SDK de terceiro"; echo "$achados"; } || ok "nenhum SDK de analise, falha ou anuncio"
achados=$(procurar 'WKWebView|UIWebView|ASWebAuthenticationSession|SFSafariViewController' "$APP" | grep -v "^$APP/Design/SiteBrowser.swift:")
# A unica excecao (pedido do dono, 18/10/2026): o navegador da Apple, em outro processo, so
# para o site da Escalibur, num arquivo so, que recusa endereco fora dele.
navegador="$APP/Design/SiteBrowser.swift"
if [ -n "$achados" ]; then
    aviso "navegador embutido fora do SiteBrowser"; echo "$achados"
elif grep -qE 'WKWebView|UIWebView|ASWebAuthenticationSession' "$navegador" \
    || ! codigo "$navegador" | grep -q 'static let host = "escalibur-wallet.github.io"' || ! codigo "$navegador" | grep -q 'url.scheme == "https" && url.host == host'; then
    aviso "o SiteBrowser abre mais que o site da Escalibur"
else
    ok "sem navegador embutido; so o Safari da Apple, para o site da Escalibur (SiteBrowser)"
fi

# 8. Modo de demonstracao so em depuracao.
secao "depuracao"
head -1 "$APP/App/DebugDemo.swift" | grep -q '^#if DEBUG' && ok "DebugDemo.swift inteiro atras de #if DEBUG" || aviso "DebugDemo.swift fora de #if DEBUG"
achados=$(awk 'FNR==1{d=0} /#if DEBUG/{d=1} /#endif/{d=0} /DebugDemo\./{ if(!d) print FILENAME": "FNR }' $(swift_em "$APP" | grep -v DebugDemo.swift))
[ -n "$achados" ] && { aviso "uso de DebugDemo fora de #if DEBUG"; echo "$achados"; } || ok "nenhum uso de DebugDemo fora de #if DEBUG"
# Argumento de inicializacao so em depuracao: quem abre o app passando argumentos (Xcode,
# um atalho, um app de terceiros) mudaria o comportamento do app da loja. Mesma tecnica da
# regra acima; `#else` e `#elseif` encerram o bloco, e um `#if` aninhado tambem, o que so
# pode acusar a mais, nunca deixar passar.
achados=$(awk 'FNR==1{d=0} /^[[:space:]]*#if DEBUG/{d=1} /^[[:space:]]*#(else|elseif|endif)/{d=0}
    /(ProcessInfo\.processInfo|ProcessInfo\(\)|processInfo)\.arguments|CommandLine\.(arguments|unsafeArgv|argc)/{ if(!d && $0 !~ /^[[:space:]]*\/\//) print FILENAME": "FNR": "$0 }' \
    $(swift_em App/EscaliburWallet App/Shared App/EscaliburWidgets))
[ -n "$achados" ] && { aviso "argumento de inicializacao lido fora de #if DEBUG"; echo "$achados"; } || ok "argumentos de inicializacao so lidos dentro de #if DEBUG"
# E o DEBUG so existe na configuracao Debug do projeto: com ele no Release, todo #if DEBUG
# iria para a loja, e as duas regras acima nao protegeriam nada.
achados=$(awk '/^[[:space:]]*[0-9A-F]+ \/\* [^*]+ \*\/ = \{/{ match($0, /\/\* [^*]+ \*\//); cfg=substr($0, RSTART+3, RLENGTH-6) }
    /SWIFT_ACTIVE_COMPILATION_CONDITIONS|GCC_PREPROCESSOR_DEFINITIONS|OTHER_SWIFT_FLAGS|OTHER_CFLAGS/{f=1}
    f && /DEBUG/{ if(cfg != "Debug") print FILENAME": "NR" ("cfg"): "$0 } /;[[:space:]]*$/{f=0}' "$pbx")
[ -n "$achados" ] && { aviso "DEBUG ligado fora da configuracao Debug"; echo "$achados"; } || ok "DEBUG so na configuracao Debug (o Release nao compila nada de #if DEBUG)"

# 9. Texto que o usuario le, sem travessao.
secao "determinismo"
achados=$(grep -rnE '__DATE__|__TIME__|__TIMESTAMP__' Kit/Sources/CSecp256k1 Kit/Sources/CArgon2 2>/dev/null)
[ -n "$achados" ] && { aviso "data de compilacao no C"; echo "$achados"; } || ok "nenhuma data de compilacao no C vendorizado"
if [ -f .xcode-version ]; then
    atual=$(xcodebuild -version 2>/dev/null | head -1)
    [ "$atual" = "$(cat .xcode-version)" ] && ok "Xcode igual ao .xcode-version ($atual)" || aviso "Xcode $atual difere do .xcode-version ($(cat .xcode-version))"
else
    aviso ".xcode-version nao existe"
fi

secao "privacidade"
faltando=""
for host in $(sed 's|https://||' hosts.lock); do
    for politica in privacidade.md privacidade-en.md; do
        codigo "$APP/Resources/Legal/$politica" | grep -qF "\`$host\`" || faltando="$faltando $host($politica)"
    done
done
[ -n "$faltando" ] && aviso "host fora da Politica de privacidade:$faltando" || ok "todo host do hosts.lock esta na Politica de privacidade, em portugues e em ingles"
# Contato (diretriz 1.5 da App Store e LGPD, art. 9): o e-mail do app e o mesmo da
# pagina de suporte, dos Termos e da Politica.
email=$(grep -oE 'static let email = "[^"]+"' "$APP/Features/Settings/SupportView.swift" 2>/dev/null | sed -E 's/.*"(.*)"/\1/')
faltando=""
for arquivo in site/suporte.md "$APP/Resources/Legal/termos.md" "$APP/Resources/Legal/privacidade.md" \
    "$APP/Resources/Legal/termos-en.md" "$APP/Resources/Legal/privacidade-en.md"; do
    codigo "$arquivo" | grep -qF "$email" 2>/dev/null || faltando="$faltando $arquivo"
done
if [ -z "$email" ]; then
    aviso "e-mail de suporte ausente no app (SupportView.swift)"
elif [ -n "$faltando" ]; then
    aviso "e-mail de suporte ($email) fora de:$faltando"
else
    ok "e-mail de suporte igual no app, na pagina de suporte, nos Termos e na Politica"
fi
saida_site=$(mktemp -d)
python3 -I tools/gerar-site.py "$saida_site/site" >/dev/null 2>&1 && [ -f "$saida_site/site/privacidade/index.html" ] && [ -f "$saida_site/site/suporte/index.html" ] \
    && [ -f "$saida_site/site/termos/index.html" ] \
    && ok "paginas publicas (suporte, privacidade, termos) geradas dos mesmos textos do app" || aviso "tools/gerar-site.py falhou"

# A lista de versoes assinada (docs/seguranca.md, "Versao autorizada"): a publicada no site
# tem de conferir com as chaves compiladas no app (ReleaseKeys.swift). Antes da primeira
# assinatura, o arquivo ainda nao existe.
if [ -f site/versoes.json ]; then
    if saida_versoes=$(swift tools/versoes/versoes.swift conferir 2>&1); then
        ok "${saida_versoes}"
    else
        aviso "site/versoes.json nao confere com as chaves de ReleaseKeys.swift: $saida_versoes"
    fi
else
    ok "lista de versoes assinada ainda nao criada (tools/versoes/versoes.swift autorizar)"
fi

# O site (tools/gerar-site.py) le redes e tokens do codigo por expressao regular. Se o
# codigo mudar de forma e o leitor ficar para tras, a contagem diverge e isto falha, em
# vez de o site publicar uma lista pela metade.
secao "site"
redes_codigo=$(awk '/static let all: \[Chain\] = \[/{f=1;next} f&&/\]/{exit} f' "$CHAINS/Chain.swift" | grep -oE '\.[a-z0-9]+' | wc -l | tr -d ' ')
tokens_codigo=$(awk '/public static let tokens: \[Asset\] = \[/{f=1;next} f&&/^    \]$/{exit} f' "$CHAINS/TokenRegistry.swift" | grep -cE '^[[:space:]]*(erc20|spl|issued|Asset)\(')
contagem=$(python3 -I tools/gerar-site.py --contagem 2>&1)
if [ "$contagem" = "redes $redes_codigo tokens $tokens_codigo" ]; then
    ok "o site lista as $redes_codigo redes de Chain.swift e os $tokens_codigo tokens de TokenRegistry.swift"
else
    aviso "o site leu \"$contagem\", e o codigo tem $redes_codigo redes e $tokens_codigo tokens (tools/gerador_site/dados.py)"
fi
paginas_site=$(find "$saida_site/site" -name '*.html' 2>/dev/null)
if [ -z "$paginas_site" ]; then
    aviso "o site nao foi gerado"
else
    # A fonte (fontes/) e o /precos.json do Mercado ao vivo tambem so do proprio site.
    sem_csp=$(echo "$paginas_site" | xargs grep -L "content=\"default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; media-src 'self'; font-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'\"" 2>/dev/null)
    # O unico script em linha aceito e o bloco de dados da inicial (schema.org), que nao executa.
    de_fora=$(echo "$paginas_site" | xargs grep -noE '(src|poster)="https?://|<link rel="(stylesheet|icon|apple-touch-icon|preload|modulepreload|manifest)"[^>]*href="https?://|<script>|<script [^>]*>[^<]|style="| on[a-z]+="' 2>/dev/null \
        | grep -vE ':[0-9]+:<script type="application/ld\+json">\{$')
    de_fora="$de_fora$(grep -noE 'url\(["'"'"']?(https?:)?//|@import' "$saida_site/site/estilo.css" 2>/dev/null)"
    if [ -n "$sem_csp$de_fora" ]; then
        aviso "pagina do site sem a Content Security Policy, ou com script, estilo ou recurso de fora"; echo "$sem_csp$de_fora"
    else
        ok "todas as paginas do site com Content Security Policy, sem script em linha e sem nada carregado de outro site"
    fi
    # Codigo citado nas paginas de auditoria sai como entidade HTML: o que sobra e texto.
    achados=$(echo "$paginas_site" | xargs grep -lE '—|–' 2>/dev/null)
    [ -n "$achados" ] && { aviso "travessao nas paginas do site"; echo "$achados"; } || ok "nenhum travessao nas paginas do site"
    # Os selos oficiais aparecem antes do lancamento por decisao do dono (18/10/2026), mas sem
    # link: enquanto o app nao esta na loja, o selo nao leva a lugar nenhum.
    sem_link=""
    codigo tools/gerar-site.py | grep -qE '^APP_STORE_URL = None' && sem_link="baixar-na-app-store"
    codigo tools/gerar-site.py | grep -qE '^PLAY_STORE_URL = None' && sem_link="$sem_link|disponivel-no-google-play"
    sem_link="${sem_link#|}"
    if [ -n "$sem_link" ] && echo "$paginas_site" | xargs grep -lE "<a [^>]*><img src=\"[^\"]*($sem_link)" >/dev/null 2>&1; then
        aviso "selo de loja com link sem o app na loja"
    else
        ok "selos das lojas sem link enquanto o app nao esta na loja (APP_STORE_URL e PLAY_STORE_URL em tools/gerar-site.py)"
    fi
fi
rm -rf "$saida_site"

secao "texto"
achados=$(swift_em "$APP" | xargs grep -nE '"[^"]*(—|–)[^"]*"' 2>/dev/null)
[ -n "$achados" ] && { aviso "travessao em texto de interface"; echo "$achados"; } || ok "nenhum travessao em texto de interface"
# Toda traducao do catalogo com os campos certos: traducao invalida (campo trocado,
# travessao) falha sempre. Texto sem traducao so e dito: o dono adiou as traducoes dos textos
# novos (16/10/2026), e o iPhone mostra o original em portugues ate elas entrarem. Texto novo
# entra pelo tools/traducao/sincronizar.sh (tools/traducao/glossario.md).
resumo=$(python3 -I tools/traducao/conferir.py --resumo 2>&1)
if echo "$resumo" | grep -qE ' [1-9][0-9]* invalidos'; then
    aviso "traducao invalida no catalogo (tools/traducao/conferir.py --resumo)"
    echo "$resumo" | grep -E ' [1-9][0-9]* invalidos' | head -14
elif python3 -I tools/traducao/conferir.py >/dev/null 2>&1; then
    ok "todo texto de tela traduzido nos $(echo "$resumo" | grep -c 'traduzidos') idiomas, sem campo trocado"
else
    faltando=$(echo "$resumo" | head -1 | sed -E 's/.* ([0-9]+) faltando.*/\1/')
    ok "nenhuma traducao invalida; $faltando texto(s) ainda sem traducao, adiados pelo dono (em portugues ate entrarem)"
fi

secao "android"
AND=Android/app/src/main
# A politica do Android: todo host do hosts.lock, menos os da conferencia de atualizacao da App
# Store, que o Android nao faz.
faltando=""
for host in $(sed 's|https://||' hosts.lock); do
    case "$host" in itunes.apple.com|escalibur-wallet.github.io) continue ;; esac
    for politica in privacidade.md privacidade-en.md; do
        codigo "$AND/assets/legal/$politica" | grep -qF "\`$host\`" 2>/dev/null || faltando="$faltando $host($politica)"
    done
done
[ -n "$faltando" ] && aviso "host fora da Politica de privacidade do Android:$faltando" || ok "todo host do hosts.lock esta na Politica do Android, em portugues e em ingles"
# As permissoes sao so as que a Politica explica.
permissoes=$(grep -oE 'uses-permission android:name="android\.permission\.[A-Z_]+"' "$AND/AndroidManifest.xml" | sed -E 's/.*permission\.([A-Z_]+)"/\1/' | sort | tr '\n' ' ')
esperadas="CAMERA HIDE_OVERLAY_WINDOWS INTERNET POST_NOTIFICATIONS RECEIVE_BOOT_COMPLETED USE_BIOMETRIC "
[ "$permissoes" = "$esperadas" ] && ok "permissoes do Android: so as da Politica ($permissoes)" || aviso "permissoes do Android diferentes das da Politica: $permissoes"
# Sem backup, sem texto puro, e so as autoridades do sistema.
codigo "$AND/AndroidManifest.xml" | grep -q 'android:allowBackup="false"' && codigo "$AND/AndroidManifest.xml" | grep -q 'android:usesCleartextTraffic="false"' \
    && codigo "$AND/res/xml/rede.xml" | grep -q '<certificates src="system" />' && ! grep -q 'src="user"' "$AND/res/xml/rede.xml" \
    && ok "Android sem backup, sem trafego em texto puro e sem certificado instalado pelo usuario" || aviso "manifesto ou rede.xml do Android afrouxado"
# A tela fora de captura e de recentes (so o build de depuracao, pedido pelo adb, deixa capturar).
codigo_vivo "$AND/java/app/escalibur/wallet/MainActivity.kt" | grep -q 'FLAG_SECURE' && codigo "$AND/java/app/escalibur/wallet/MainActivity.kt" | grep -q 'BuildConfig.DEBUG && intent.getBooleanExtra("capturas"' \
    && ok "FLAG_SECURE no Android, solto so no build de depuracao" || aviso "FLAG_SECURE do Android mudou"
# Cada dialogo, popup e menu do Compose e outra janela, que nao herda a protecao da Activity (auditoria
# de 03/11/2026): cada um comeca o conteudo com ProtegerJanela(), conferido janela por janela, com ou
# sem o pacote na frente e fora de comentario, e as janelas no estilo antigo nem entram (segunda passada).
# Os consertos de 31/10 que nao tinham regra (segunda passada da auditoria de 03/11/2026): o segredo
# preso na RAM e fora do core dump (AA-01), os metadados gravados com F_FULLFSYNC (AI-02), e toda
# notificacao do Android so neste celular, sem ir para o relogio.
# No Android, o sorteio do sistema mistura o getrandom(2) do kernel com o RAND_bytes da BoringSSL: um modo de build dela
# que deixasse o sorteio deterministico nao deixa a frase previsivel (decima terceira passada da auditoria de 03/11/2026).
# Toda derivacao de carteira passa antes pelo autoteste dos vetores publicos, no proprio aparelho e no binario da loja: um
# resultado diferente nao deriva nada (decima terceira passada da auditoria de 03/11/2026).
python3 -I tools/codigo.py --exige "$KEYS/Signer.swift" 'guard DerivationSelfTest.passed else { throw DerivationSelfTest.Failure() }' --plataforma ambas \
    && [ "$(grep -c 'static func deriveUnchecked' "$KEYS/Signer.swift")" = "1" ] \
    && [ -z "$(swift_em $CORE $CHAINS $KEYS $NET $ENG $APP Kit/Sources/Android | xargs grep -l 'deriveUnchecked' 2>/dev/null | grep -vxF "$KEYS/Signer.swift" | grep -vxF "$KEYS/DerivationSelfTest.swift")" ] \
    && ok "toda derivacao de carteira passa antes pelo autoteste dos vetores publicos" || aviso "derivacao de carteira sem o autoteste dos vetores publicos"
# A raiz da seed e a conta Cardano so dentro do modulo das chaves, e so pelo Signer (a assinatura e o deriveUnchecked):
# nenhuma grafia de `master(seed:`, `derivedAccount(` ou `icarusMaster(` fora dos tres arquivos, nenhuma extensao desses
# tipos fora do arquivo deles, e o `@testable import`, que abriria o que e do modulo, so nos testes (revisao da decima
# terceira passada).
python3 -I - <<'PY' && ok "a raiz da seed so no Signer, e o @testable so nos testes" || aviso "raiz da seed fora do Signer, ou @testable fora dos testes"
import re, subprocess, sys
certo = True
chaves = "Kit/Sources/EscaliburKeys/"
donos = {chaves + "Signer.swift": ("AccountDeriver",), chaves + "HDKey.swift": ("HDKey",), chaves + "CardanoKey.swift": ("CardanoKey",),
         chaves + "DerivationSelfTest.swift": ("DerivationSelfTest",), chaves + "SigningSelfTest.swift": ("SigningSelfTest",)}
definicoes = {chaves + "HDKey.swift": "    static func master(seed: SecureBytes, curve: Curve) throws -> HDKey {",
              chaves + "CardanoKey.swift": "    static func derivedAccount(_ secret: WalletSecret, chain: Chain = .cardano, account: UInt32 = 0) throws -> DerivedAccount {"}
for arquivo, linha in definicoes.items():
    certo &= open(arquivo, encoding="utf-8").read().split("\n").count(linha) == 1
cardano = open(chaves + "CardanoKey.swift", encoding="utf-8").read()
certo &= cardano.split("\n").count("    static func icarusMaster(entropy: SecureBytes, passphrase: SecureBytes) throws -> CardanoKey {") == 1
signer = open(chaves + "Signer.swift", encoding="utf-8").read()
# A assinatura, a derivacao (secp256k1 e ed25519) e a conferencia da passphrase, que nao fica no cofre (05/11/2026).
certo &= signer.count("HDKey.master(") == 4 and signer.count("CardanoKey.derivedAccount(") == 2
rastreados = subprocess.run(["git", "ls-files", "-z", "--", "*.swift"], capture_output=True, check=True).stdout.decode().split("\0")
for arquivo in filter(None, rastreados):
    texto = open(arquivo, encoding="utf-8").read()
    if not arquivo.startswith(("Kit/Tests/", "App/EscaliburWalletTests/", "App/EscaliburWalletUITests/")):
        certo &= "@testable" not in texto
        if arquivo not in (chaves + "Signer.swift", chaves + "HDKey.swift", chaves + "CardanoKey.swift"):
            certo &= not re.search(r"\bmaster\s*\(\s*seed\s*:|\bderivedAccount\s*\(|\bicarusMaster\s*\(", texto)
    for tipo in re.findall(r"\bextension\s+(HDKey|CardanoKey|AccountDeriver|DerivationSelfTest|SigningSelfTest)\b", texto):
        certo &= tipo in donos.get(arquivo, ())
sys.exit(0 if certo else 1)
PY
# A frase so e gravada no cofre depois de derivada, e o autoteste roda antes de abrir a RK: com ele ou a derivacao falhando,
# nada fica no cofre sem carteira, longe do "Remover" (revisao da decima terceira passada). Lido como o compilador le (sem
# comentario nem texto): os quatro unicos `wallets.save(` sao os de criar, importar e abrir com passphrase, cada um dentro
# da abertura da RK depois da derivacao, com o autoteste antes dela na mesma funcao; e ninguem guarda o cofre noutro nome.
# O nonce das assinaturas e conferido antes de abrir o cofre, pelos esquemas do plano.
python3 -I - <<'PY' && python3 -I tools/codigo.py --exige "$KEYS/Signer.swift" 'guard SigningSelfTest.passed(for: plan) else { throw SigningSelfTest.Failure() }' --plataforma ambas \
    && ok "a frase so vai ao cofre depois de derivada, e a assinatura passa pelo autoteste do nonce" || aviso "frase gravada antes da derivacao, ou assinatura sem o autoteste do nonce"
import re, subprocess, sys
certo = True
donos = {"App/EscaliburWallet/App/AppSession.swift": "ios", "Kit/Sources/Android/EscaliburAndroid/App/Sessao.swift": "android"}
SALVA = r"\bwallets\s*\.\s*save\s*\("
rastreados = subprocess.run(["git", "ls-files", "-z", "--", "*.swift"], capture_output=True, check=True).stdout.decode().split("\0")
for arquivo in filter(None, rastreados):
    if arquivo.startswith(("Kit/Tests/", "App/EscaliburWalletTests/", "App/EscaliburWalletUITests/")):
        continue
    cru = open(arquivo, encoding="utf-8").read()
    certo &= not re.search(r"=\s*(KeyServices|Chaves)\s*\.\s*wallets\s*($|[^.A-Za-z0-9_])", cru, re.M)
    if arquivo not in donos:
        certo &= not re.search(SALVA, cru)
        continue
    vivo = subprocess.run([sys.executable, "-I", "tools/codigo.py", arquivo, "--vivo", "--plataforma", donos[arquivo]],
                          capture_output=True, text=True, check=True).stdout
    salvas = [m.start() for m in re.finditer(SALVA, vivo)]
    certo &= len(salvas) == 2 and len(re.findall(SALVA, cru)) == 2
    for posicao in salvas:
        antes = vivo[:posicao]
        abre = [m.start() for m in re.finditer(r"\b(withRootKey|comChaveRaiz)\s*\(", antes)]
        deriva = [m.start() for m in re.finditer(r"\bAccountDeriver\s*\.\s*derive\s*\(\s*secret\s*\)", antes)]
        funcao = [m.start() for m in re.finditer(r"\bfunc\s", antes)]
        if not (abre and deriva and funcao):
            certo = False
            continue
        certo &= deriva[-1] > abre[-1] > funcao[-1]
        certo &= re.search(r"\bDerivationSelfTest\s*\.\s*require\s*\(\s*\)", vivo[funcao[-1]:abre[-1]]) is not None
sys.exit(0 if certo else 1)
PY
fda=$CORE/Platform/ForaDaApple.swift
python3 -I tools/codigo.py --exige "$fda" 'guard CCryptoBoringSSL_RAND_bytes(saida, count) == 1 else {' --plataforma android \
    && python3 -I tools/codigo.py --exige "$fda" 'let n = getrandom(base + feito, count - feito, 0)' --plataforma android \
    && python3 -I tools/codigo.py --exige "$fda" 'kernel.withUnsafeBytes { metade in for indice in 0..<count { saida[indice] ^= metade[indice] } }' --plataforma android \
    && python3 -I tools/codigo.py --exige "$fda" 'let kernel = SecureBytes(capacity: count)' --plataforma android \
    && ok "no Android, o sorteio mistura o getrandom do kernel com o da BoringSSL" || aviso "o sorteio do Android sem a mistura com o getrandom do kernel"
sb=$CORE/Crypto/SecureBytes.swift
codigo_vivo_android "$sb" | grep -qE '_ = mlock\(region' && codigo_vivo_android "$sb" | grep -qE 'madvise\(region, regionSize, MADV_DONTDUMP\)' \
    && ok "SecureBytes prende o segredo na RAM e fora do core dump (mlock, MADV_DONTDUMP)" || aviso "SecureBytes sem mlock ou MADV_DONTDUMP (AA-01)"
md=$APP/Services/Metadata.swift
codigo_vivo "$md" | grep -q 'fcntl(handle.fileDescriptor, F_FULLFSYNC)' && codigo_vivo "$md" | grep -q 'try writeDurably(sealed, to: file)' \
    && ! grep -qE 'sealed\.write\(to: [^)]*\.atomic' "$md" \
    && ok "metadados gravados com F_FULLFSYNC, rename e sync da pasta (AI-02)" || aviso "metadados sem a gravacao duravel (AI-02)"
# Toda notificacao nasce na funcao que poe setLocalOnly(true): o arquivo cru tem um `Notification.Builder(` so,
# na linha dela, e nenhum outro em lugar nenhum do Kotlin (quinta passada da auditoria de 03/11/2026: contar
# ocorrencias deixava um texto ou um setLocalOnly a mais cobrir outro Builder).
# As regras do Kotlin leem `src/main/java`: nenhum Kotlin nem Java em outra pasta (o release compila tambem
# `src/main/kotlin` e `src/release/`), e nenhum `sourceSets`/`srcDir` no Gradle (oitava passada de 03/11/2026).
# So as saidas de verdade do Gradle ficam de fora (uma pasta `build` dentro das fontes, rastreada, entrava; nona
# passada), nenhum link simbolico e nenhum arquivo rastreado que o git ignora no repositorio (as regras e o `find` nao
# seguem link, e o Gradle segue), e nenhuma fonte a mais pela API de variante do Gradle (so os quatro assets gerados).
fora_do_main=$(find Android -type f \( -name '*.kt' -o -name '*.java' -o -name '*.kts' \) -not -path 'Android/build/*' -not -path 'Android/app/build/*' \
    -not -path 'Android/.gradle/*' -not -path 'Android/app/src/main/java/*' -not -name '*.gradle.kts' 2>/dev/null)
# Nem pelo plugin do Kotlin (`source(...)` na tarefa de compilar, argumentos a mais do compilador, outro build incluido;
# decima passada), e nenhum Kotlin, Java ou Gradle rastreado fora dos lugares certos, no repositorio inteiro.
fora_do_main="$fora_do_main$(git ls-files | grep -E '\.(kt|kts|java|gradle)$' | grep -vE '^Android/app/src/main/java/|^Android/(app/)?build\.gradle\.kts$|^Android/settings\.gradle\.kts$')"
gradle_fontes=$(grep -rnE 'sourceSets|srcDir|sources\.(java|kotlin|resources|aidl|renderscript|jniLibs|shaders|mlModels)|addStaticSourceDirectory|addGeneratedSourceDirectory|addSource|source[[:space:]]*\(|setSource|registerJavaGeneratingTask|freeCompilerArgs|kotlinOptions|compilerOptions|includeBuild|buildSrc|apply[[:space:]]*\(?[[:space:]]*from|Xplugin|PluginClasspath' \
    Android --include='*.gradle.kts' --include='*.gradle' 2>/dev/null | grep -v -e '^Android/build/' -e '^Android/app/build/' \
    | grep -vE '^Android/app/build\.gradle\.kts:[0-9]+:        variante\.sources\.assets\?\.addGeneratedSourceDirectory\((gerarTextos, GerarTextos|copiarLogos, CopiarParaOApp|copiarListas, CopiarParaOApp|copiarAbertura, CopiarParaOApp)::saida\)$')
links=$(git ls-files -s | awk '$1 == "120000"')
ignorados=$(git ls-files -ci --exclude-standard)
[ -z "$fora_do_main" ] && [ -z "$gradle_fontes" ] && [ -z "$links" ] && [ -z "$ignorados" ] \
    && ok "todo o Kotlin do Android esta em src/main/java, onde as regras leem (sem link, sem fonte a mais no Gradle)" \
    || { aviso "Kotlin ou Java fora de src/main/java, fonte a mais no Gradle, link simbolico ou arquivo rastreado ignorado"; echo "$fora_do_main$gradle_fontes$links$ignorados"; }
# Fora do Vigia.kt, nenhum outro jeito de montar ou postar notificacao (NotificationCompat do androidx, o construtor
# antigo, recoverBuilder, servico em primeiro plano, notify, setLocalOnly(false), o do relogio, um apelido no import);
# dentro dele, um construtor e um notify so, com espaco ou quebra de linha no meio inclusive (sexta passada).
proibidas_notif='NotificationCompat|NotificationManagerCompat|Notification[[:space:]]*\.[[:space:]]*Builder|recoverBuilder|(^|[^A-Za-z0-9_.])Notification[[:space:]]*\(|startForeground|\.[[:space:]]*notify[[:space:]]*\(|setLocalOnly[[:space:]]*\([[:space:]]*false|WearableExtender|android\.app\.Notification|NotificationManager|NOTIFICATION_SERVICE|(^|[^A-Za-z0-9_])notify[[:space:]]*\(|::[[:space:]]*notify\b'
# Fora do Vigia.kt tambem nada do pacote de notificacoes do Android (um `import android.app.Notification as N` com
# `N.Builder` e `with(gerente) { notify(...) }` passava; setima passada).
vigia_kt="$AND/java/app/escalibur/wallet/vigias/Vigia.kt"
vigia_junto=$(tr -d ' \t\n' < "$vigia_kt")
! grep -rlE "$proibidas_notif" "$AND/java" --include='*.kt' --include='*.java' 2>/dev/null | grep -vxF "$vigia_kt" | grep -q . \
    && ! grep -qE 'Builder[[:space:]]+as[[:space:]]|recoverBuilder|NotificationCompat|setLocalOnly[[:space:]]*\([[:space:]]*false|WearableExtender|startForeground|(^|[^A-Za-z0-9_.])Notification[[:space:]]*\(' "$vigia_kt" \
    && [ "$(echo "$vigia_junto" | grep -oF 'Notification.Builder(' | grep -c .)" = "1" ] \
    && echo "$vigia_junto" | grep -qF 'Notification.Builder(contexto,canal).setLocalOnly(true)' \
    && [ "$(echo "$vigia_junto" | grep -oE '\.notify\(' | grep -c .)" = "1" ] && echo "$vigia_junto" | grep -qF 'gerente.notify(id,0,notificacao)' \
    && ok "toda notificacao do Android nasce so neste celular (setLocalOnly)" || aviso "notificacao do Android fora da funcao com setLocalOnly(true)"
# A etiqueta da notificacao de ordem e lida por qualquer app com acesso as notificacoes, e o UID traz o dono: no Android,
# todo aviso de ordem nasce num lugar so, com a etiqueta sorteada (nem o resumo da ordem, que ligava os avisos da mesma
# ordem), o Kotlin recusa etiqueta de ordem fora desse formato e qualquer etiqueta com cara de endereco, e o resumo
# guardado no arquivo e o HMAC com a chave da instalacao; no iPhone, o id e o HMAC; e remover a carteira ou apagar o
# app limpa a gaveta, nos dois apps (sexta e setima passadas da auditoria de 03/11/2026). Cru, para a ausencia.
vg=Kit/Sources/Android/EscaliburAndroid/App/Vigias.swift
vk=Android/app/src/main/java/app/escalibur/wallet/vigias/Vigia.kt
avisos_juntos=$(tr -d ' \t\n' < "$vg")
# A funcao que sorteia a etiqueta, inteira e numa definicao so: a linha do sorteio solta no arquivo passava com a funcao
# devolvendo outra coisa (decima passada da auditoria de 03/11/2026).
sorteada=$(cat <<'FIM'
    static func etiquetaSorteada() -> String? {
        guard let sorteio = try? SecureRandom.bytes(12), sorteio.count == 12 else { return nil }
        return Hex.encode(sorteio)
    }
FIM
)
[ "$(grep -cF 'Aviso(id: "ordem-limite.' "$vg")" = "1" ] \
    && [ "$(echo "$avisos_juntos" | grep -oF 'Aviso(id:"ordem-limite.' | grep -c .)" = "1" ] \
    && [ "$(echo "$avisos_juntos" | grep -oF ',canal:"ordens"' | grep -c .)" = "1" ] \
    && python3 -I tools/codigo.py --exige "$vg" 'return Aviso(id: "ordem-limite.\(etiqueta).\(sorteio)", canal: "ordens", tipo: tipo, ordem: tipo == "prazo" ? "" : "1")' --plataforma android \
    && python3 -I tools/codigo.py --exige "$vg" "$sorteada" --plataforma android \
    && [ "$(grep -oF 'etiquetaSorteada' "$vg" | grep -c .)" = "3" ] \
    && [ -z "$(swift_em Kit/Sources App | xargs grep -lF 'etiquetaSorteada' 2>/dev/null | grep -vxF "$vg")" ] \
    && [ "$(codigo_vivo_android "$vg" | grep -cF 'SecureRandom.bytes(12)')" = "1" ] \
    && [ "$(codigo_vivo_android "$vg" | grep -cF 'guard let sorteio = Vigias.etiquetaSorteada() else { return nil }')" = "2" ] \
    && python3 -I tools/codigo.py --exige "$vg" 'guard Vigias.epocaAgora == epoca, let chave = resumo(id, epoca: epoca) else { return }' --plataforma android \
    && codigo_vivo_android "$vg" | grep -qF 'Hash.hmacSHA256(key: $0, data: Array(id.utf8))' \
    && python3 -I tools/codigo.py --exige "$vk" 'if (ETIQUETAS[canal]?.matches(aviso.optString("id")) != true) continue' --plataforma android \
    && python3 -I tools/codigo.py --exige "$vk" 'if (canal == "ordens" && aviso.optString("ordem") !in setOf("", "1")) continue' --plataforma android \
    && python3 -I tools/codigo.py --exige "$vk" '"recebimentos" to Regex("^recebimento\\.([0-9a-f]{24}|discreto|mais)$"),' --plataforma android \
    && python3 -I tools/codigo.py --exige "$vg" 'return Aviso(id: "recebimento.\(sorteio)", canal: "recebimentos", tipo: "recebeu",' --plataforma android \
    && [ -z "$(swift_em Kit/Sources/Android | xargs grep -lE 'ordem-limite|"ordens"' 2>/dev/null | grep -vxF "$vg")" ] \
    && [ "$(codigo "$vg" | grep -oF 'ordem-limite' | grep -c .)" = "1" ] \
    && python3 -I tools/codigo.py --exige "$vk" 'if (SEQUENCIA_DE_ENDERECO.containsMatchIn(aviso.optString("id"))) continue' --plataforma android \
    && python3 -I tools/codigo.py --exige "$vk" '"ordens" to Regex("^ordem-limite\\.(executada|24h|prazo)\\.[0-9a-f]{24}$"),' --plataforma android \
    && python3 -I tools/codigo.py --exige "$vk" 'private val SEQUENCIA_DE_ENDERECO = Regex("[0-9a-fA-F]{40}")' --plataforma android \
    && codigo_vivo "$APP/Services/LimitRenewals.swift" | grep -qF 'HMAC<SHA256>.authenticationCode(for: Data(orderID.lowercased().utf8), using: NoticeKey.current())' \
    && codigo_vivo_android Android/app/src/main/java/app/escalibur/wallet/ui/carteira/ApagarCarteira.kt | grep -qF 'Vigia.limparGaveta()' \
    && codigo_vivo_android "$vk" | grep -qF 'cancelAll()' \
    && codigo_vivo "$APP/App/AppSession.swift" | grep -c 'removeAllDeliveredNotifications()' | grep -qx 2 \
    && ok "aviso de ordem sem o UID na etiqueta, e a gaveta limpa ao remover a carteira" || aviso "aviso de ordem com o UID na etiqueta ou gaveta que sobra da carteira removida"
# As regras conferem o texto das travas, e o texto e o mesmo com outro tipo por tras do nome: um `enum SecureRandom` ou
# `Hex` em outro arquivo, um parametro generico ou um import com esse nome sombreava o do EscaliburCore, e o sorteio da
# etiqueta virava constante com a regra verde (decima primeira passada da auditoria de 03/11/2026). Cada um desses nomes
# so e declarado no arquivo dono. Cru, para a ausencia.
nomes_donos='SecureRandom|Hex|SecureBytes|Vigias|Hash'
sombras=$(find Kit/Sources App -name '*.swift' -not -path 'Kit/Sources/SwiftCrypto/*' -not -path 'App/EscaliburWalletTests/*' \
        -not -path 'App/EscaliburWalletUITests/*' -print0 \
    | xargs -0 grep -HnE "\b(enum|struct|class|typealias|protocol|actor|let|var|func|case|associatedtype)[[:space:]]+($nomes_donos)\b|<[^=>][^>]*\b($nomes_donos)[[:space:]]*[:,>]|\bimport[[:space:]]+(enum|struct|class|typealias|protocol|func|var|let)[[:space:]]+[A-Za-z0-9_.]*\.($nomes_donos)\b|[(,][[:space:]]*($nomes_donos)[[:space:]]*:" 2>/dev/null \
    | grep -vE '^Kit/Sources/EscaliburCore/Crypto/Hash\.swift:[0-9]+:public enum Hash \{$|^Kit/Sources/EscaliburCore/Crypto/SecureRandom\.swift:[0-9]+:public enum SecureRandom \{$|^Kit/Sources/EscaliburCore/Crypto/SecureBytes\.swift:[0-9]+:public final class SecureBytes: @unchecked Sendable \{$|^Kit/Sources/EscaliburCore/Encoding/Hex\.swift:[0-9]+:public enum Hex \{$|^Kit/Sources/Android/EscaliburAndroid/App/Vigias\.swift:[0-9]+:enum Vigias \{$')
[ -z "$sombras" ] && ok "SecureRandom, Hex, SecureBytes, Hash e Vigias so sao declarados no arquivo dono (nada os sombreia)" \
    || { aviso "um tipo, parametro ou import com o nome de SecureRandom, Hex, SecureBytes, Hash ou Vigias fora do arquivo dono"; echo "$sombras"; }
# O binario da loja so sai do codigo publicado na main do GitHub, numa copia limpa (um worktree novo e
# destacado do commit publicado), e leva o commit e a arvore; a tela de Ajustes mostra o commit. Vale para
# o archive do iPhone, o do workflow e o AAB do Android, e o Gradle recusa o release sem os dois (terceira
# passada da auditoria de 03/11/2026). Fora de comentario, e os scripts da loja travados por digesto em
# loja.lock: mudou um deles, revise o diff e grave o digesto novo.
conferir_lock loja.lock . "scripts da loja"
# Lido tambem como JSON, como o copia-publicada.sh le, sem chave repetida: com "arquivos" duas vezes, o sed lia uma lista e
# o JSON outra (decima segunda passada da auditoria de 03/11/2026).
python3 -I - <<'PY' && ok "loja.lock e um JSON sem chave repetida, com os 29 arquivos" || aviso "loja.lock com chave repetida, outra forma ou outra contagem"
import json, sys
def sem_repetida(pares):
    if len(pares) != len({chave for chave, _ in pares}):
        raise ValueError("chave repetida")
    return dict(pares)
try:
    lock = json.load(open("loja.lock", encoding="utf-8"), object_pairs_hook=sem_repetida)
except ValueError:
    sys.exit(1)
sys.exit(0 if set(lock) == {"nota", "arquivos"} and isinstance(lock["arquivos"], dict) and len(lock["arquivos"]) == 29 else 1)
PY
# Exatamente os scripts da loja, o workflow do release e o que compila o nucleo: tirar uma entrada do lock e mudar o
# arquivo nao passa. No shell e no yml, texto entre aspas conta como vivo por desenho: o lock e o portao (sexta passada).
# Decima passada: tambem o conferidor das flags do build, o Package.swift (que decide as flags) e o Gradle (que decide
# as fontes do Kotlin e o R8); decima primeira: o projeto do Xcode (as chaves de ajuste, os caminhos e o esquema).
[ "$(sed -n 's/^    "\([^"]*\)": "[0-9a-f]\{64\}".*/\1/p' loja.lock 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')" = ".github/workflows/release.yml .github/workflows/verificar.yml .xcode-version Android/app/build.gradle.kts Android/app/proguard-rules.pro Android/build.gradle.kts Android/gradle.properties Android/gradle/libs.versions.toml Android/gradle/verification-metadata.xml Android/gradle/wrapper/gradle-wrapper.jar Android/gradle/wrapper/gradle-wrapper.properties Android/settings.gradle.kts EscaliburWallet.xcodeproj/project.pbxproj EscaliburWallet.xcodeproj/project.xcworkspace/contents.xcworkspacedata EscaliburWallet.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings EscaliburWallet.xcodeproj/xcshareddata/xcschemes/EscaliburWallet.xcscheme Kit/Package.swift project.yml tools/android/compilar-nucleo.sh tools/android/gerar-aab.sh tools/android/testar-nucleo.sh tools/arquivar.sh tools/codigo.py tools/copia-publicada.sh tools/digesto.sh tools/flags-do-build.py tools/flags-do-pacote.py tools/verificar.sh tools/versoes/versoes.swift " ] \
    && ok "loja.lock trava os scripts da loja, o release.yml, os conferidores das flags, o Package.swift, o projeto do Xcode e o Gradle" || aviso "loja.lock sem os scripts da loja, o release.yml, os conferidores das flags, o Package.swift, o projeto do Xcode ou o Gradle"
origem=0
exigidos=(
    "tools/copia-publicada.sh|git -C \"\$raiz\" fetch -q origin +refs/heads/main:refs/remotes/origin/main"
    "tools/copia-publicada.sh|git -C \"\$raiz\" ls-remote origin refs/heads/main"
    "tools/copia-publicada.sh|[ \"\$(git -C \"\$raiz\" hash-object --no-filters -- \"\$raiz/\$script\")\" = \"\$(git -C \"\$raiz\" rev-parse --verify \"\$commit:\$script\")\" ]"
    "tools/copia-publicada.sh|[ \"\$(git -C \"\$raiz\" rev-parse 'HEAD^{tree}')\" = \"\$arvore\" ]"
    "tools/copia-publicada.sh|git -C \"\$raiz\" -c core.hooksPath=/dev/null worktree add -q --detach \"\$limpa\" \"\$commit\""
    "tools/arquivar.sh|/bin/bash -p \"\$limpa/tools/arquivar.sh\" --na-copia-limpa"
    "tools/arquivar.sh|&& [ -z \"\$(git status --porcelain=v1 --untracked-files=all --ignored)\" ] && [ -z \"\$(git ls-files -v | grep -v '^H ')\" ]"
    "tools/android/gerar-aab.sh|&& [ -z \"\$(git status --porcelain=v1 --untracked-files=all --ignored)\" ] && [ -z \"\$(git ls-files -v | grep -v '^H ')\" ]"
    "tools/android/gerar-aab.sh|/bin/bash -p \"\$limpa/tools/android/gerar-aab.sh\" --na-copia-limpa"
    "tools/android/gerar-aab.sh|grep -rqaF -- \"\$valor\" \"\$dex/aab\""
    "Android/app/proguard-rules.pro|-keep class app.escalibur.wallet.BuildConfig"
    "Android/app/build.gradle.kts|git(\"rev-parse\", \"--absolute-git-dir\") != git(\"rev-parse\", \"--path-format=absolute\", \"--git-common-dir\")"
    "Android/app/build.gradle.kts|origemDoRelease[0] == git(\"rev-parse\", \"--verify\", \"refs/remotes/origin/main^{commit}\")"
    "Android/app/build.gradle.kts|carimbo.readText().trim() == \"release-loja \${origemDoRelease[0]} \${digestoDe(nucleo)} \${digestoDe(libcxx)}\""
    "tools/android/compilar-nucleo.sh|[ \"\$(shasum -a 256 \"\$LIBCXX\" | cut -d' ' -f1)\" = \"7466ed097631a564ed6bff0b47768caa76bf03270d2047b5a65c03f497b824df\" ]"
    "tools/android/compilar-nucleo.sh|> build/android-kit/origem-do-nucleo.txt"
    "tools/android/compilar-nucleo.sh|swiftpm package dump-package 2>/dev/null | python3 -I tools/flags-do-pacote.py Kit/Package.swift"
    "tools/android/compilar-nucleo.sh|(cd Kit && env -i HOME=\"\$HOME\" PATH=\"\$PATH\" TMPDIR=\"\$(getconf DARWIN_USER_TEMP_DIR)\" ESCALIBUR_ANDROID=1"
    "tools/android/compilar-nucleo.sh|swiftpm build -v \"\${OPCOES[@]}\" --scratch-path ../build/android-kit --product EscaliburAndroid"
    "tools/arquivar.sh|(cd Kit && swift package dump-package 2>/dev/null) | python3 -I tools/flags-do-pacote.py Kit/Package.swift"
    "tools/arquivar.sh|unset XCODE_XCCONFIG_FILE"
    "tools/arquivar.sh|python3 -I tools/flags-do-build.py ios \"\$saida/archive.log\" --build \"\$aqui/build/dd-release\""
    "tools/arquivar.sh|[ \"\$(xcodebuild -version | head -1)\" = \"\$(cat .xcode-version)\" ]"
    "tools/android/compilar-nucleo.sh|python3 -I tools/flags-do-build.py android \"build/nucleo-\$CONFIG.log\" --build build/android-kit \$([ -n \"\$LOJA\" ] || echo --parcial)"
    "tools/copia-publicada.sh|\$api/workflows/verificar.yml/runs?head_sha=\$commit&event=push&branch=main&per_page=30"
    "tools/copia-publicada.sh|x.get(\"path\") == \".github/workflows/verificar.yml\""
    "tools/copia-publicada.sh|curl -fsS --proto '=https' --max-time 30 \"\$api/runs/\$rodada/jobs\""
    "tools/copia-publicada.sh|all(hashlib.sha256(open(c, \"rb\").read()).hexdigest() == d for c, d in lock.items())"
    "tools/android/compilar-nucleo.sh|[ ! -e build/android-kit ] || { echo \"o nucleo da loja compila do zero, e build/android-kit ja existe\" >&2; exit 1; }"
    "tools/android/compilar-nucleo.sh|[ -z \"\$LOJA\" ] || [ \"\$CONFIG\" = release ] || { echo \"o nucleo da loja e o de release\" >&2; exit 2; }"
    "tools/android/gerar-aab.sh|\"\$aqui/tools/android/compilar-nucleo.sh\" release --loja"
    ".github/workflows/release.yml|python3 -I tools/flags-do-build.py ios \"\$RUNNER_TEMP/archive.log\" --build \"\$RUNNER_TEMP/dd\""
    ".github/workflows/release.yml|(cd Kit && swift package dump-package 2>/dev/null) | python3 -I tools/flags-do-pacote.py Kit/Package.swift"
    "tools/copia-publicada.sh|ls-files -v -- tools/copia-publicada.sh tools/arquivar.sh tools/android/gerar-aab.sh loja.lock | grep -v '^H '"
    "tools/copia-publicada.sh|[ -z \"\$(git status --porcelain=v1 --untracked-files=all --ignored)\" ]"
    "tools/arquivar.sh|source tools/copia-publicada.sh"
    "tools/arquivar.sh|ESCALIBUR_COMMIT=\"\$commit\" ESCALIBUR_TREE=\"\$arvore\""
    "tools/arquivar.sh|swift tools/versoes/versoes.swift conferir-app \"\$app\""
    "tools/android/gerar-aab.sh|source tools/copia-publicada.sh"
    "tools/android/gerar-aab.sh|-PcommitDeOrigem=\"\$commit\" -ParvoreDeOrigem=\"\$arvore\""
    "tools/android/gerar-aab.sh|grep -rqaF -- \"\$valor\" \"\$dex/apk\""
    "$APP/Resources/Info.plist|<string>\$(ESCALIBUR_COMMIT)</string>"
    "$APP/Resources/Info.plist|<string>\$(ESCALIBUR_TREE)</string>"
    ".github/workflows/release.yml|ESCALIBUR_COMMIT=\"\$GITHUB_SHA\" ESCALIBUR_TREE=\"\$arvore\""
    "Android/app/build.gradle.kts|buildConfigField(\"String\", \"COMMIT_DE_ORIGEM\""
    "Android/app/build.gradle.kts|buildConfigField(\"String\", \"ARVORE_DE_ORIGEM\""
    "Android/app/build.gradle.kts|tasks.matching { it.name == \"preReleaseBuild\" }.configureEach { dependsOn(conferirOrigem, conferirCDoNucleo) }"
)
faltam=""
# Cada trecho como codigo de verdade: fora de comentario e, no Kotlin e no Gradle, fora de texto entre aspas, no mesmo
# lugar (`codigo.py --exige`; sexta passada da auditoria de 03/11/2026).
# A plataforma antes, e nao num `case` dentro de `$( )`: o bash 3.2 do Mac nao o le, e a plataforma saia vazia, com o
# erro perdido na saida (decima terceira passada da auditoria de 03/11/2026).
for item in "${exigidos[@]}"; do
    plataforma_do_item=ios
    case "${item%%|*}" in Android/*|*.kts|*.kt) plataforma_do_item=android ;; esac
    python3 -I tools/codigo.py --exige "${item%%|*}" "${item#*|}" --plataforma "$plataforma_do_item" \
        && origem=$((origem + 1)) || faltam="$faltam ${item%%|*}"
done
[ "$origem" = "${#exigidos[@]}" ] && ok "o app da loja so sai do codigo publicado, numa copia limpa, e leva o commit e a arvore (iPhone, workflow e Android)" \
    || aviso "build da loja fora da copia limpa do publicado ou sem o commit e a arvore no binario ($origem de ${#exigidos[@]}:$faltam)"
# Digitar segredo com um servico de acessibilidade de fora ligado, ferramenta ou nao e em qualquer Android:
# o teclado das palavras e o de campo de senha fecham, e o do celular nem abre (segunda passada da
# auditoria de 03/11/2026). No 14+ quem nao se diz ferramenta nao le a tela, mas ve onde o dono toca.
codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -q 'if (sessao.deSegredo && deFora.isNotEmpty())' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -q 'if (!bloqueado && (sistema != null || peloCelular))' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoDePalavras.kt" | grep -q 'if (!demo && deFora.isNotEmpty())' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/Acessibilidade.kt" | grep -q 'val deFora = ligados.values.filter { info -> !doSistema(info) }' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/Segredo.kt" | grep -qF 'if (fechadoPelaAcessibilidade(segredo)) return true' \
    && [ "$(codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/Segredo.kt" | grep -cF 'if (fechadoPelaAcessibilidade(segredo)) return true')" -ge 3 ] \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -qF 'val bloqueado = (campoSecreto(info) || sistema?.palavras == true) &&' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -qF 'foco.clearFocus(force = true)' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -qF 'suspeitosParaSegredo.isNotEmpty()) awaitCancellation()' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoDePalavras.kt" | grep -qF 'TecladoFechadoPelaAcessibilidade(deFora)' \
    && ok "o teclado de segredo fecha com qualquer servico de acessibilidade de fora, em qualquer Android, tambem o fisico e o que ja estava aberto" \
    || aviso "teclado de segredo aberto com servico de acessibilidade de fora"
# A regra confere a si mesma antes, com os casos de ataque das auditorias (terceira passada de 03/11/2026).
janelas=$(python3 -I tools/android/janelas.py --testes 2>&1 && python3 -I tools/android/janelas.py 2>&1); codigo_janelas=$?
[ "$codigo_janelas" = "0" ] && ok "toda janela propria do Android (dialogo, popup, menu) comeca com ProtegerJanela()" \
    || { aviso "janela do Android sem ProtegerJanela()"; echo "$janelas"; }
# Nenhuma biblioteca de analise, anuncio ou relatorio de falha.
achados=$(grep -iE 'firebase|crashlytics|analytics|sentry|appsflyer|adjust|amplitude|mixpanel|segment|play-services-ads|bugsnag|datadog' Android/gradle/libs.versions.toml Android/app/build.gradle.kts 2>/dev/null)
[ -n "$achados" ] && { aviso "biblioteca de rastreamento no Android"; echo "$achados"; } || ok "nenhuma biblioteca de analise, anuncio ou relatorio de falha no Android"
# O Kotlin nao fala com a internet: o unico endereco e a pagina da auditoria, aberta no navegador.
enderecos=$(grep -rhoE '"https?://[^"]+' "$AND/java" | sed 's/^"//' | sort -u | tr '\n' ' ')
[ "$enderecos" = "https://escalibur-wallet.github.io/auditoria/ " ] && ok "o Kotlin so tem o endereco da auditoria (aberto no navegador)" || aviso "endereco novo no Kotlin: $enderecos"
achados=$(grep -rnE 't\("[^"]*(—|–)[^"]*"' "$AND/java" 2>/dev/null; grep -nE '—|–' Android/app/textos-android.json "$AND"/assets/legal/*.md 2>/dev/null)
[ -n "$achados" ] && { aviso "travessao em texto do Android"; echo "$achados" | head; } || ok "nenhum travessao nos textos, traducoes e documentos do Android"
# Cada dependencia do Gradle conferida pelo digesto, e o proprio Gradle pelo digesto da distribuicao.
codigo Android/gradle/verification-metadata.xml | grep -q '<verify-metadata>true</verify-metadata>' 2>/dev/null \
    && codigo Android/gradle/verification-metadata.xml | grep -q '<sha256 ' && codigo Android/gradle/wrapper/gradle-wrapper.properties | grep -q '^distributionSha256Sum=' \
    && ok "dependencias do Android conferidas pelo digesto ($(grep -c '<component ' Android/gradle/verification-metadata.xml) componentes) e o Gradle pela distribuicao" \
    || aviso "Android sem verification-metadata.xml ou sem o digesto do Gradle"
# A Google Play recusa biblioteca nativa sem alinhamento de 16 KB (Android 15 em diante).
readelf=$(ls ~/Library/Android/android-ndk-*/toolchains/llvm/prebuilt/*/bin/llvm-readelf 2>/dev/null | tail -1)
if [ -n "$readelf" ] && ls Android/app/src/main/jniLibs/arm64-v8a/*.so >/dev/null 2>&1; then
    curtas=""
    for so in Android/app/src/main/jniLibs/arm64-v8a/*.so; do
        "$readelf" -lW "$so" | awk '/LOAD/ {print $NF}' | grep -Eqv '^0x(4000|10000)$' && curtas="$curtas $(basename "$so")"
    done
    [ -n "$curtas" ] && aviso "biblioteca nativa sem alinhamento de 16 KB:$curtas" || ok "bibliotecas nativas do Android alinhadas a 16 KB"
    # O endurecimento do binario do nucleo: pilha sem execucao, RELRO e BIND_NOW (auditoria Android de 31/10/2026, AA-07).
    # (grep -c, e nao -q: com pipefail, o -q que sai cedo faz o readelf morrer de SIGPIPE e a regra acusar a toa.)
    so=Android/app/src/main/jniLibs/arm64-v8a/libEscaliburAndroid.so
    cabecalhos=$("$readelf" -lW "$so" 2>/dev/null)
    dinamico=$("$readelf" -d "$so" 2>/dev/null)
    [ "$(printf '%s' "$cabecalhos" | grep -c 'GNU_STACK.* RW ')" -gt 0 ] && [ "$(printf '%s' "$cabecalhos" | grep -c 'GNU_RELRO')" -gt 0 ] \
        && [ "$(printf '%s' "$dinamico" | grep -c 'BIND_NOW')" -gt 0 ] \
        && ok "nucleo do Android com pilha sem execucao, RELRO e BIND_NOW" || aviso "nucleo do Android sem pilha NX, RELRO ou BIND_NOW"
fi
# Colar le so o texto do item: coerceToText abriria uma content:// URI de outro app na thread da interface (AA-04).
achados=$(grep -rn 'coerceToText' "$AND/java" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)')
[ -n "$achados" ] && { aviso "coerceToText no Kotlin"; echo "$achados"; } || ok "colar no Android le so o texto da area de transferencia"
# A checagem de root por pacote so funciona com os pacotes em <queries> (AA-03), e a unica porta aberta e a MainActivity:
# o receiver do profileinstaller sai do manifesto (AA-05). O manifesto mesclado, quando ha um build, confirma.
faltando_queries=""
for pacote in com.topjohnwu.magisk eu.chainfire.supersu me.weishu.kernelsu me.bmax.apatch; do
    codigo "$AND/AndroidManifest.xml" | grep -q "<package android:name=\"$pacote\"" || faltando_queries="$faltando_queries $pacote"
done
[ -n "$faltando_queries" ] && aviso "gerenciador de root fora de <queries> no manifesto:$faltando_queries" || ok "os gerenciadores de root da checagem estao em <queries>"
codigo "$AND/AndroidManifest.xml" | grep -q 'ProfileInstallReceiver' && codigo "$AND/AndroidManifest.xml" | grep -q 'tools:node="remove"' \
    && ok "o receiver do profileinstaller sai do manifesto" || aviso "o receiver exportado do profileinstaller voltou ao manifesto"
exportados=""
# So os tipos de build de hoje: um intermediario de um tipo que ja saiu do build.gradle.kts nao conta.
for variante in debug release conferencia; do
    mesclado=$(ls Android/app/build/intermediates/merged_manifests/$variante/*/AndroidManifest.xml 2>/dev/null | head -1)
    [ -n "$mesclado" ] && [ -f "$mesclado" ] || continue
    fora=$(python3 -I - "$mesclado" <<'PY'
import re, sys
texto = open(sys.argv[1]).read()
for bloco in re.findall(r"<(?:activity|service|receiver|provider)\b[^>]*>", texto, re.S):
    if 'android:exported="true"' in bloco:
        nome = re.search(r'android:name="([^"]+)"', bloco).group(1)
        if nome != "app.escalibur.wallet.MainActivity":
            print(nome, end=" ")
PY
)
    [ -n "$fora" ] && exportados="$exportados $(basename "$(dirname "$(dirname "$mesclado")")"):$fora"
done
[ -n "$exportados" ] && aviso "componente exportado alem da MainActivity no manifesto mesclado:$exportados" || ok "no manifesto mesclado so a MainActivity e exportada"
# Todo metodo que o nucleo procura pelo JNI tem regra no ProGuard: sem ela, o R8 renomeia o metodo no
# release e a ligacao inteira falha (sem rede e sem cofre).
faltando=$(python3 -I - <<'PY'
import re
java = open("Kit/Sources/Android/EscaliburAndroid/Java.swift").read()
regras = open("Android/app/proguard-rules.pro").read()
blocos = {m.group(1): m.group(2) for m in re.finditer(r"-keep class app\.escalibur\.wallet\.nucleo\.(\w+)\s*\{(.*?)\}", regras, re.S)}
for classe, metodo in re.findall(r'\("(\w+)", "(\w+)", "\(', java):
    if not re.search(r"\b" + metodo + r"\(", blocos.get(classe, "")):
        print(f"{classe}.{metodo}", end=" ")
PY
)
[ -n "$faltando" ] && aviso "metodo do JNI sem regra no ProGuard: $faltando" || ok "todo metodo que o nucleo procura pelo JNI esta no ProGuard"
python3 -I tools/android/textos.py >/dev/null 2>&1 && ok "todo texto do Android traduzido nos 12 idiomas" || aviso "texto do Android sem traducao (tools/android/textos.py)"

# 10. Testes com vetores oficiais, e a fronteira conferida tambem no binario (regra 3
# de docs/seguranca.md §8.3): os objetos compilados de Chaves, Cadeias e Nucleo nao
# podem referenciar nenhum simbolo de rede. O modulo de rede e o controle: nele os
# simbolos aparecem, e a checagem que nao os achasse ali estaria cega.
# A fronteira tambem por lista de permissao (auditoria 6, A6-15): todo simbolo de fora que
# Chaves, Cadeias e Nucleo referenciam no binario, fora a biblioteca do Swift e o proprio
# codigo, esta em simbolos.lock. A lista de proibidos pega URLSession e sockets, nao
# XMLParser(contentsOf:) nem Stream; aqui um simbolo novo e revisado como um host novo.
simbolos_do_binario() {
    for modulo in EscaliburKeys EscaliburChains EscaliburCore; do nm -u Kit/.build/debug/$modulo.build/*.o 2>/dev/null; done \
        | sed 's/^_//' | grep -vE '^\$ss|^\$sS[^oC]|^\$s12_Concurrency|^\$s[0-9]+Escalibur|^_?swift|^_|\.o:$|^$' | sort -u
    # Sem os cabecalhos que o nm imprime para cada .o e sem linha em branco: so simbolos. Um
    # arquivo novo (o ForaDaApple.swift, vazio no Mac) nao conta como simbolo novo.
}
if [ "${1:-}" = "--atualizar-simbolos" ]; then
    (cd Kit && swift build >/dev/null 2>&1) || { echo "  ✗ o Kit nao compilou"; exit 1; }
    simbolos_do_binario > simbolos.lock
    ok "simbolos.lock atualizado: $(wc -l < simbolos.lock | tr -d ' ') simbolos (revise o diff)"
    # O C: o do Mac do build de agora; o do Android, do ultimo build do nucleo (sem ele, fica o que havia).
    { simbolos_do_c mac
      if [ -n "$(configuracoes_android)" ]; then for c in $(configuracoes_android); do simbolos_do_c android "$c"; done
      else grep '^android ' simbolos-c.lock 2>/dev/null; fi; } \
        | sort -u > simbolos-c.lock.novo && mv simbolos-c.lock.novo simbolos-c.lock
    ok "simbolos-c.lock atualizado: $(wc -l < simbolos-c.lock | tr -d ' ') simbolos do C (revise o diff)"
    exit 0
fi

if [ "${1:-}" = "--testes" ]; then
    secao "testes"
    saida=$(cd Kit && swift test 2>&1); codigo=$?
    if [ "$codigo" = "0" ]; then
        ok "testes do nucleo passam ($(echo "$saida" | grep -oE 'Test run with [0-9]+ tests' | tail -1))"
    else
        aviso "testes do nucleo falharam (saida $codigo)"
        echo "$saida" | grep -E "✘|error:|fatal error|Fatal error" | head -40
        echo "$saida" | tail -15
    fi
    proibidos='URLSession|_nw_|CFSocket|CFStream|CFHTTP|NSURLConnection|XMLParser|NSInputStream|NSOutputStream|So11InputStream|So12OutputStream|objc_getClass|^_dlopen$|^_dlsym$|^_socket$|^_connect$|^_getaddrinfo$'
    achados=""
    for modulo in EscaliburKeys EscaliburChains EscaliburCore; do
        n=$(nm -u Kit/.build/debug/$modulo.build/*.o 2>/dev/null | grep -cE "$proibidos")
        [ "$n" != "0" ] && achados="$achados $modulo($n)"
    done
    controle=$(nm -u Kit/.build/debug/EscaliburNetwork.build/*.o 2>/dev/null | grep -cE "$proibidos")
    if [ -n "$achados" ]; then
        aviso "simbolo de rede no binario:$achados"
    elif [ "$controle" = "0" ]; then
        aviso "checagem do binario cega: nem o modulo de rede mostrou simbolo de rede"
    else
        ok "binario de Chaves, Cadeias e Nucleo sem simbolo de rede (controle: $controle no de rede)"
    fi
    # O alocador por tipo chegou ao C vendorizado (-ftyped-memory-operations no Package.swift):
    # nos objetos de CArgon2 e CSecp256k1, malloc e calloc viram malloc_type_*, nenhum cru.
    for alvo in CArgon2 CSecp256k1; do
        simbolos=$(find "Kit/.build/debug/$alvo.build" -name '*.o' -exec nm -u {} + 2>/dev/null)
        crus=$(echo "$simbolos" | grep -xE '_(malloc|calloc|realloc)' | sort -u | tr '\n' ' ')
        if ! echo "$simbolos" | grep -qx '_malloc_type_malloc'; then
            aviso "$alvo sem _malloc_type_malloc nos objetos (alocador por tipo fora, ou checagem cega)"
        elif [ -n "$crus" ]; then
            aviso "$alvo ainda chama o alocador cru: $crus"
        else
            ok "$alvo aloca pelo alocador por tipo (_malloc_type_malloc, nenhum malloc ou calloc cru)"
        fi
    done
    conferir_simbolos_do_c mac
    novos=$(comm -23 <(simbolos_do_binario) <(sort -u simbolos.lock 2>/dev/null))
    if [ ! -f simbolos.lock ]; then
        aviso "simbolos.lock nao existe (gere com --atualizar-simbolos e revise)"
    elif [ "$(simbolos_do_binario | wc -l)" -lt 50 ]; then
        aviso "checagem dos simbolos cega: o binario de Chaves, Cadeias e Nucleo nao mostrou simbolo"
    elif [ -n "$novos" ]; then
        aviso "simbolo de fora novo em Chaves, Cadeias ou Nucleo; revise e rode --atualizar-simbolos"
        echo "$novos" | head -20
    else
        ok "Chaves, Cadeias e Nucleo so usam os $(wc -l < simbolos.lock | tr -d ' ') simbolos de fora de simbolos.lock"
    fi
fi

# 11. O app de distribuicao, de um build Release para aparelho (o CI de hoje compila para o
# simulador, que nao tem arm64e). O app e o widget com as fatias arm64 e arm64e, a arm64e com
# instrucoes de autenticacao de ponteiro, e, se o app vier assinado, as cinco chaves do
# Enhanced Security na assinatura (o perfil de provisionamento tem de trazer a capability).
if [ "${1:-}" = "--binario" ]; then
    secao "binario de distribuicao"
    if [ -z "$app_binario" ] || [ ! -d "$app_binario" ]; then
        aviso "--binario pede o caminho do EscaliburWallet.app de um build Release para aparelho"
    else
        # O app da loja leva o commit e a arvore de onde saiu (so pelo tools/arquivar.sh ou pelo release.yml).
        origem_commit=$(/usr/libexec/PlistBuddy -c 'Print :EscaliburCommit' "$app_binario/Info.plist" 2>/dev/null)
        origem_arvore=$(/usr/libexec/PlistBuddy -c 'Print :EscaliburTree' "$app_binario/Info.plist" 2>/dev/null)
        [[ "$origem_commit" =~ ^[0-9a-f]{40}$ && "$origem_arvore" =~ ^[0-9a-f]{40}$ ]] \
            && ok "o app leva o commit $origem_commit e a arvore $origem_arvore" \
            || aviso "o app nao leva o commit e a arvore de origem (archive fora do tools/arquivar.sh e do release.yml)"
        # A trava contra teclado de terceiros no binario, e nao so no fonte: o metodo implementado pela classe do
        # delegate, com endereco. O nome sozinho nas strings nao serve: o binario leva a lista de metodos opcionais do
        # protocolo UIApplicationDelegate mesmo sem a trava (quinta e sexta passadas da auditoria de 03/11/2026).
        # Em cada fatia do binario (arm64 e arm64e): um `#if` que tirasse a trava de uma fatia so passava (setima passada).
        fatias=$(lipo -archs "$app_binario/EscaliburWallet" 2>/dev/null)
        sem_trava=""
        for fatia in $fatias; do
            xcrun dyld_info -arch "$fatia" -objc "$app_binario/EscaliburWallet" 2>/dev/null \
                | grep -qE '^ +0x[0-9A-Fa-f]+ +-\[_TtC15EscaliburWallet14PlatformGuards application:shouldAllowExtensionPointIdentifier:\]' \
                || sem_trava="$sem_trava $fatia"
        done
        [ -n "$fatias" ] && [ -z "$sem_trava" ] \
            && ok "o app de distribuicao recusa teclado de terceiros (PlatformGuards implementa shouldAllowExtensionPointIdentifier)" \
            || aviso "o app de distribuicao sem a implementacao de shouldAllowExtensionPointIdentifier"
        for executavel in "$app_binario/EscaliburWallet" "$app_binario/PlugIns/EscaliburWidgets.appex/EscaliburWidgets"; do
            nome=$(basename "$executavel")
            arqs=$(lipo -archs "$executavel" 2>/dev/null)
            [ "$arqs" = "arm64 arm64e" ] && ok "$nome com as fatias arm64 e arm64e" || aviso "$nome com as fatias \"$arqs\" (esperado: arm64 arm64e)"
            pac=$(xcrun otool -tv -arch arm64e "$executavel" 2>/dev/null | grep -cE 'pacibsp|retab|blraa|braa')
            [ "${pac:-0}" -gt 0 ] && ok "$nome em arm64e com $pac instrucoes de autenticacao de ponteiro" \
                || aviso "$nome sem instrucao de autenticacao de ponteiro na fatia arm64e"
            pacote=$(dirname "$executavel")
            if codesign -d "$pacote" >/dev/null 2>&1; then
                assinados=$(mktemp)
                codesign -d --entitlements - --xml "$pacote" > "$assinados" 2>/dev/null
                erradas=$(endurecido_errado "$assinados")
                [ -n "$erradas" ] && aviso "$nome assinado sem o Enhanced Security completo:$erradas" \
                    || ok "$nome assinado com as cinco chaves do Enhanced Security"
                rm -f "$assinados"
            else
                echo "  - $nome sem assinatura: os entitlements so foram conferidos no arquivo"
            fi
        done
    fi
fi

echo
if [ "$falhas" = "0" ]; then echo "tudo conferido."; else echo "$falhas verificacao(oes) falharam."; fi
exit $(( falhas > 0 ))
