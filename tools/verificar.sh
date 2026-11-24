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
sem_isolar=$(git ls-files -z '*.sh' '*.yml' '*.yaml' | xargs -0 grep -HnE '[p]ython' | sed -E 's/[p]ython[0-9.]*"? -(IS?|SI)([^A-Za-z0-9]|$)/X\2/g' \
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
                                                    "GIT_NO_REPLACE_OBJECTS|GIT_CONFIG_COUNT|GIT_CONFIG_KEY_0|GIT_CONFIG_VALUE_0|GIT_CONFIG_KEY_1|GIT_CONFIG_VALUE_1|xcrun_db)")
    # O cache do xcrun novo e vazio em cada script (rodada 3 dos 3 agentes da checagem final de 16/11/2026): o git, o
    # Python e o swift de /usr/bin escolhem o programa por ele.
    for trecho in ('&& [ -n "${xcrun_db:-}" ] && [ "${xcrun_db#"$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)"escalibur-xcrun.}" != "$xcrun_db" ] && [ ! -e "$xcrun_db" ] \\\n    || limpo=false\n',
                   '    xcrun_db="$(/usr/bin/mktemp -d "$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)escalibur-xcrun.XXXXXX")/xcrun_db" \\\n    /bin/bash -p "$0" "$@"\n'):
        certo &= trecho in b
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
    ARGV.each { |arquivo| olhar.(YAML.safe_load(File.read(arquivo)), arquivo) }
    puts ruins
    exit(ruins.empty? ? 0 : 1)' .github/workflows/*.yml 2>&1)
estranhas=$(grep -HnE '^[[:space:]-]*\?([[:space:]]|$)|"[^"]*\\[^"]*"[[:space:]]*:|^[[:space:]-]*\*[A-Za-z0-9_-]+[[:space:]]*:' .github/workflows/*.yml)
# O GitHub roda tambem `.yaml` e acao local em `.github/actions`, e as regras so leem `*.yml` (nona passada); e o
# `*.yml` do shell nao pega o nome com ponto no comeco, que o GitHub roda (decima passada).
estranhas="$estranhas$(find .github/workflows -mindepth 1 \( -name '.*' -o ! -type f -o ! -name '*.yml' \) 2>/dev/null)$(find .github/actions 2>/dev/null | head -1)"
[ -n "$achados" ] || [ -n "$lidos" ] || [ -n "$estranhas" ] && { aviso "acao de fora da GitHub ou sem SHA num workflow, chave shell ou workflow fora do *.yml"; echo "$achados$lidos$estranhas"; } \
    || ok "toda acao dos workflows vem da propria GitHub, fixada por SHA (na linha e no YAML lido), e sem shell que nao o bash"
# Rodada 8 da auditoria 8: so ASCII que se imprime, sem tab nem CR, nos workflows. O YAML quebra linha tambem no CR e no NEL, e as
# regras de texto so no LF: uma linha depois de um CR solto sumia de todas elas e o GitHub a rodava.
achados=$(LC_ALL=C grep -nE '[^ -~]' .github/workflows/*.yml | cut -c1-120)
[ -z "$achados" ] && ok "os workflows so com ASCII que se imprime (sem CR, NEL nem tab escondendo uma linha das regras)" \
    || { aviso "workflow com CR, tab ou caractere fora do ASCII"; echo "$achados"; }
# Exatamente os tres workflows, com os jobs de hoje e sem `name:` de job: o build da loja confia no job `verificar` do
# verificar.yml, e um outro com esse nome passava por ele (decima segunda passada da auditoria de 03/11/2026).
jobs_lidos=$(ruby -ryaml -e '
    esperados = { "release.yml" => %w[assinatura verificar montar enviar], "site.yml" => %w[montar publicar], "verificar.yml" => %w[verificar] }
    lidos = Dir.children(".github/workflows").sort
    ruins = lidos == esperados.keys.sort ? [] : ["workflows: #{lidos.inspect}"]
    esperados.each do |arquivo, jobs|
        caminho = ".github/workflows/#{arquivo}"
        next unless File.file?(caminho)
        y = YAML.safe_load(File.read(caminho))
        ruins << "#{arquivo}: jobs #{y["jobs"].keys.inspect}" unless y["jobs"].is_a?(Hash) && y["jobs"].keys == jobs
        (y["jobs"] || {}).each { |nome, job| ruins << "#{arquivo}: #{nome} com name" if job.is_a?(Hash) && job.key?("name") }
        # Rodada 13 da auditoria 8: o gatilho de cada workflow e o environment de cada job fixos. Um job do site.yml com
        # `environment: release` e um gatilho de tag chegava a chave da App Store Connect: a regra do segredo so pedia o environment.
        gatilhos = { "release.yml" => { "push" => { "tags" => ["testflight-*", "v*"] } },
                     "verificar.yml" => { "push" => { "branches" => ["main"] }, "pull_request" => nil, "workflow_call" => nil },
                     "site.yml" => { "workflow_dispatch" => nil } }
        ruins << "#{arquivo}: gatilho #{y[true].inspect}" unless y[true] == gatilhos[arquivo] && !y.key?("on")
        # Rodada 15: o segredo pelo YAML lido, e nao so pelo texto: o escape do YAML (`\x73ecrets`, a linha quebrada com barra) e o
        # `environment: release` dentro de um texto enganavam o awk. Qualquer chave ou valor com "secrets", fora do enviar do
        # release (fixado por digesto), barra.
        textos = lambda do |o, saida|
            case o
            when Hash then o.each { |k, v| saida << k.to_s; textos.(v, saida) }
            when Array then o.each { |v| textos.(v, saida) }
            else saida << o.to_s
            end
            saida
        end
        ruins << "#{arquivo}: segredo fora dos jobs" unless textos.(y.reject { |k, _| k == "jobs" }, []).grep(/secrets/i).empty?
        (y["jobs"] || {}).each do |nome, job|
            next if arquivo == "release.yml" && nome == "enviar"
            ruins << "#{arquivo}: #{nome} com segredo" unless textos.(job, []).grep(/secrets/i).empty?
        end
        # Rodada 16: nenhuma tag no YAML (o `!!binary` escondia o texto do segredo da regra de texto).
        com_tag = lambda { |no| (no.respond_to?(:tag) && no.tag) || (no.respond_to?(:children) && (no.children || []).any? { |c| com_tag.(c) }) }
        ruins << "#{arquivo}: tag no YAML" if com_tag.(YAML.parse(File.read(caminho)))
        # Rodada 14: as chaves do topo pelo texto, na ordem de hoje: o leitor de YAML junta um `on:` repetido e um `yes:` na mesma
        # chave, e o ultimo vale.
        topo = File.read(caminho).scan(/^[^\s#][^:]*:/)
        ruins << "#{arquivo}: topo #{topo.inspect}" unless topo == ["name:", "on:", "permissions:", "concurrency:", "jobs:"]
        ambientes = { ["release.yml", "enviar"] => "release",
                      ["site.yml", "publicar"] => { "name" => "github-pages", "url" => "${{ steps.publicacao.outputs.page_url }}" } }
        (y["jobs"] || {}).each do |nome, job|
            next unless job.is_a?(Hash)
            ruins << "#{arquivo}: #{nome} com environment #{job["environment"].inspect}" unless job["environment"] == ambientes[[arquivo, nome]]
        end
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
    tolower($0) ~ /(^|[^a-z0-9_])secrets([^a-z0-9_]|$)/ { if (job == "") print FILENAME ":" FNR ": " $0; else guardadas[++n] = FILENAME ":" FNR ": " $0 }
    END { fecha() }
' .github/workflows/*.yml)
[ -n "$achados" ] && { aviso "segredo fora de job do environment release"; echo "$achados"; } \
    || ok "segredo so em job do environment release"
# O envio do release (rodada 1 da auditoria 8): o zip sem atributo nem link, conferido entrada por entrada antes de abrir,
# o bundle id e os entitlements da assinatura ad hoc antes do export, e a chave fora do $RUNNER_TEMP e do ambiente dos
# filhos. O checkout esparso traz os .entitlements que o conferidor le.
release_sem_comentario=$(grep -vE '^[[:space:]]*#' .github/workflows/release.yml)
# Rodada 11: o passo da tag sem os objetos de troca (`GIT_NO_REPLACE_OBJECTS`), o unico `fetch` o da tag, e a lista de
# assinantes citada so nas seis linhas de hoje (um `git show` ou um `curl` por cima dela depois do cat-file passava).
# Rodada 7: as regras do `||`, do `&&` e do que muda o shell sobre as linhas juntas, como o bash junta a barra no fim (o
# `cmd |\` com `| true` na linha seguinte escapava), e o molde que fecha o `||` vale para todo `&&` tambem (o `cmd && echo`
# engolia a falha com qualquer comando depois), salvo o `if ...; then`. E nada de `${!`, o nome da variavel montado na hora, nem
# de `declare`, `typeset`, `printenv` e `compgen`, que montam ou leem o nome do mesmo jeito (rodada 8).
release_junto=$(sed -e ':a' -e '/\\$/{$!N;s/\\\n[[:space:]]*//;ta' -e '}' <<<"$release_sem_comentario")
molde_do_ou='\|\|[[:space:]]*\{ ((tail [^;]*|echo "\$[a-z]+"); )?echo "::error::[^"]*"; exit 1; \}$'
# Rodada 3: a linha inteira (um `|| true` no fim passava), e nada que siga depois de uma falha no arquivo todo.
# Rodada 6: nada de dois `||` na linha, de `&` em segundo plano nem `coproc`, do `&& :` que engole o teste, nem de
# variavel que muda o shell dos passos seguintes (GITHUB_ENV, GITHUB_PATH, BASH_ENV, SHELLOPTS, BASHOPTS). E os passos
# lidos pelo YAML, e nao so pelo texto: o `- run:` com traco, o `"run":` entre aspas e o mapa numa linha escapavam das
# regras do `run`. Todo `run` abre com `set -euo pipefail` (so o da limpeza nao), e o YAML tem tantos `run` quantas as
# linhas `run:` que as regras leem.
passos_release=$(ruby -ryaml -rjson -rdigest -e '
    y = YAML.safe_load(File.read(".github/workflows/release.yml"))
    ruins = []
    lidos = 0
    (y["jobs"] || {}).each do |nome, job|
        (job.is_a?(Hash) ? job["steps"] || [] : []).each_with_index do |passo, i|
            next unless passo.is_a?(Hash) && passo.key?("run")
            lidos += 1
            corpo = passo["run"]
            limpeza = passo["if"] == "always()" && corpo == "rm -rf \"$HOME\"/.asc.*"
            ruins << "#{nome}, passo #{i + 1}: o run nao abre com set -euo pipefail" unless corpo.is_a?(String) && (limpeza || corpo.start_with?("set -euo pipefail\n"))
            # Rodada 7: nada de `${{` dentro do run (a injecao classica: uma saida do montar vira comando no enviar); tudo
            # entra pelo `env:`.
            ruins << "#{nome}, passo #{i + 1}: ${{ dentro do run" if corpo.to_s.include?("${{")
        end
        # Rodada 7: so as quatro acoes de hoje, fixadas por SHA (o `actions/github-script` rodava codigo sem `run:`), e o unico
        # workflow chamado e o verificar.yml.
        (job.is_a?(Hash) ? job["steps"] || [] : []).each_with_index do |passo, i|
            usa = passo.is_a?(Hash) ? passo["uses"] : nil
            next if usa.nil?
            ruins << "#{nome}, passo #{i + 1}: acao fora da lista (#{usa})" unless usa.is_a?(String) && usa =~ /\Aactions\/(checkout|upload-artifact|download-artifact|attest)@[0-9a-f]{40}\z/
        end
        ruins << "#{nome}: workflow chamado fora do verificar.yml" if job.is_a?(Hash) && job.key?("uses") && !(nome == "verificar" && job["uses"] == "./.github/workflows/verificar.yml")
        # Rodada 8: so as variaveis de hoje no `env:` do job e dos passos (o `PATH` trocava o Python, o codesign e o shasum que
        # o enviar chama pelo nome, como o GITHUB_PATH ja barrado).
        conhecidas = %w[TAG VERSAO BUILD DIGESTO ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8]
        envs = [job.is_a?(Hash) ? job["env"] : nil] + (job.is_a?(Hash) ? job["steps"] || [] : []).map { |passo| passo.is_a?(Hash) ? passo["env"] : nil }
        envs.compact.each do |env|
            fora = env.is_a?(Hash) ? env.keys.map(&:to_s) - conhecidas : ["(nao e mapa)"]
            ruins << "#{nome}: env fora da lista (#{fora.join(", ")})" unless fora.empty?
        end
    end
    ruins << "env no topo do workflow" if y.key?("env")
    # Rodada 9: o `needs` de cada job fixo (sem o verificar, o montar e o enviar saiam com o verificador vermelho), e o
    # verificar.yml, que e o portao, so com as chaves de hoje: sem `if`, `continue-on-error`, `env` nem `defaults`.
    esperado = { "assinatura" => nil, "verificar" => "assinatura", "montar" => %w[assinatura verificar], "enviar" => %w[assinatura montar] }
    (y["jobs"] || {}).each { |nome, job| ruins << "#{nome}: needs #{job["needs"].inspect}" if job.is_a?(Hash) && job["needs"] != esperado[nome] }
    ruins << "release.yml: chave no topo fora da lista" unless (y.keys - ["name", true, "permissions", "concurrency", "jobs"]).empty?
    # Rodada 9: as chaves, a maquina e as permissoes de cada job fixas: um `container` ou `services`, ou outro `runs-on` (um runner
    # proprio), mudavam onde o job roda e com que git, gpg e Xcode, e uma permissao a mais dava escrita ao token.
    chaves = { "assinatura" => %w[runs-on timeout-minutes permissions outputs steps], "verificar" => %w[needs permissions uses],
               "montar" => %w[needs runs-on timeout-minutes permissions outputs env steps],
               "enviar" => %w[needs runs-on timeout-minutes environment permissions env steps] }
    maquina = { "assinatura" => "ubuntu-24.04", "verificar" => nil, "montar" => "macos-26", "enviar" => "macos-26" }
    leitura = { "contents" => "read" }
    permissoes = { "assinatura" => leitura, "verificar" => leitura, "montar" => leitura,
                   "enviar" => { "contents" => "read", "id-token" => "write", "attestations" => "write" } }
    (y["jobs"] || {}).each do |nome, job|
        next unless job.is_a?(Hash) && chaves[nome]
        ruins << "#{nome}: chaves #{(job.keys - chaves[nome]).inspect}" unless (job.keys - chaves[nome]).empty?
        ruins << "#{nome}: runs-on #{job["runs-on"].inspect}" unless job["runs-on"] == maquina[nome]
        ruins << "#{nome}: permissions #{job["permissions"].inspect}" unless job["permissions"] == permissoes[nome]
        ruins << "#{nome}: environment #{job["environment"].inspect}" unless job["environment"] == (nome == "enviar" ? "release" : nil)
    end
    ruins << "release.yml: permissions no topo" unless y["permissions"] == leitura
    v = YAML.safe_load(File.read(".github/workflows/verificar.yml"))
    ruins << "verificar.yml: chave no topo fora da lista" unless v.is_a?(Hash) && (v.keys - ["name", true, "permissions", "concurrency", "jobs"]).empty?
    ruins << "verificar.yml: permissions no topo" unless v.is_a?(Hash) && v["permissions"] == leitura
    # Rodada 10: a acao de cada passo pelo SHA exato de hoje, e nao so pelo formato (o commit de um fork da rede do repositorio
    # oficial resolve pelo mesmo nome); o job da assinatura com os dois passos de hoje; a linha do HEAD em cada job que le a
    # arvore; e o corpo do verificar.yml, que e o portao: o verificador uma vez, depois da linha do HEAD, e nada que engula a
    # falha (o `|| true` deixava o job verde com o verificador vermelho).
    acoes = %w[actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9
               actions/download-artifact@37930b1c2abaa49bbe596cd826c3c89aef350131 actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6
               actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683]
    [["release.yml", y], ["verificar.yml", v]].each do |arquivo, w|
        ((w.is_a?(Hash) ? w["jobs"] : nil) || {}).each do |nome, job|
            (job.is_a?(Hash) ? job["steps"] || [] : []).each_with_index do |passo, i|
                usa = passo.is_a?(Hash) ? passo["uses"] : nil
                ruins << "#{arquivo}, #{nome}, passo #{i + 1}: acao fora do SHA de hoje (#{usa})" if usa && !acoes.include?(usa)
            end
        end
    end
    # Rodada 11: o passo da tag e o que roda antes do verificador no verificar.yml fixos por digesto, e nao por lista de formas (o
    # `GITHUB_SHA=$(...)`, o `unset GIT_NO_REPLACE_OBJECTS`, o `cp /usr/bin/true tools/verific?r.sh` e o nome da variavel montado
    # na hora passavam). Em JSON, que nao muda de formato entre versoes do Ruby. Mudou de proposito: o digesto novo entra aqui,
    # com a revisao do passo.
    # Rodada 12: o job da assinatura inteiro, e nao so o passo da tag: o primeiro passo podia deixar de ser o checkout e gravar um
    # gitconfig com outro programa de assinatura, e a tag do atacante passava no `tag -v`.
    ruins << "assinatura: o job mudou" unless Digest::SHA256.hexdigest(JSON.generate(y.dig("jobs", "assinatura"))) == "c6023443e5b19ee61ea365eb936a9fc32545c34829734f0fe149e93986dc8e70"
    # E o enviar, o unico com a chave da App Store Connect, inteiro: um passo novo com o env dos tres segredos (o valor que a regra
    # aceita) e um `curl` para fora passava, e roda depois da aprovacao do environment, que nao mostra o corpo dos passos.
    ruins << "enviar: o job mudou" unless Digest::SHA256.hexdigest(JSON.generate(y.dig("jobs", "enviar"))) == "8ff17e1242029e9c3bc990e9c3e2bbe4fdc143f60e52069a3c7fe7bea6621b43"
    antes_v = ((v.is_a?(Hash) ? v.dig("jobs", "verificar", "steps") : nil) || []).take_while { |p| !p.is_a?(Hash) || p["run"] != "./tools/verificar.sh --testes" }
    ruins << "verificar.yml: o que roda antes do verificador mudou" unless Digest::SHA256.hexdigest(JSON.generate(antes_v)) == "7665ef81bafcf6960c4ced333d7fd04dcaebd7b8b1f4ad1d37b7706fe7268e44"
    # Rodada 12: as outputs dos jobs e o env dos jobs e dos passos pelo valor exato de hoje (uma output trocada passava pelas
    # regras, e so o loja.lock barrava).
    valores = {
        ["assinatura", "outputs"] => { "versao" => "${{ steps.tag.outputs.versao }}", "build" => "${{ steps.tag.outputs.build }}" },
        ["montar", "outputs"] => { "digesto" => "${{ steps.pacote.outputs.digesto }}" },
        ["montar", "env"] => { "VERSAO" => "${{ needs.assinatura.outputs.versao }}", "BUILD" => "${{ needs.assinatura.outputs.build }}" },
        ["enviar", "env"] => { "VERSAO" => "${{ needs.assinatura.outputs.versao }}", "BUILD" => "${{ needs.assinatura.outputs.build }}",
                               "DIGESTO" => "${{ needs.montar.outputs.digesto }}" },
    }
    valores.each { |(nome, chave), valor| ruins << "#{nome}: #{chave} mudou" unless y.dig("jobs", nome, chave) == valor }
    ruins << "enviar: outputs" unless y.dig("jobs", "enviar", "outputs").nil?
    chave_asc = { "ASC_KEY_ID" => "${{ secrets.ASC_KEY_ID }}", "ASC_ISSUER_ID" => "${{ secrets.ASC_ISSUER_ID }}", "ASC_KEY_P8" => "${{ secrets.ASC_KEY_P8 }}" }
    (y["jobs"] || {}).each do |nome, job|
        (job.is_a?(Hash) ? job["steps"] || [] : []).each_with_index do |passo, i|
            next unless passo.is_a?(Hash) && passo.key?("env")
            certo = nome == "assinatura" && i == 1 ? { "TAG" => "${{ github.ref_name }}" } : (nome == "enviar" ? chave_asc : nil)
            ruins << "#{nome}, passo #{i + 1}: env mudou" unless passo["env"] == certo
        end
    end
    cabeca = %q<[ "$(git rev-parse HEAD)" = "$GITHUB_SHA" ] || { echo "::error::checkout fora do commit da tag"; exit 1; }>
    passos_a = (y.dig("jobs", "assinatura", "steps") || [])
    ruins << "assinatura: #{passos_a.size} passos" unless passos_a.size == 2
    %w[assinatura montar enviar].each do |nome|
        tem = (y.dig("jobs", nome, "steps") || []).any? { |p| p.is_a?(Hash) && p["run"].to_s.lines.map(&:strip).include?(cabeca) }
        ruins << "#{nome}: sem a linha do HEAD" unless tem
    end
    passos_v = ((v.is_a?(Hash) ? v.dig("jobs", "verificar", "steps") : nil) || []).select { |p| p.is_a?(Hash) }
    corpos_v = passos_v.map { |p| p["run"] }.compact
    cabeca_v = %q<[ "$(git rev-parse HEAD)" = "$GITHUB_SHA" ] || { echo "::error::checkout fora do commit do run"; exit 1; }>
    ruins << "verificar.yml: o passo do verificador mudou ou saiu" unless corpos_v.count { |c| c == "./tools/verificar.sh --testes" } == 1
    ruins << "verificar.yml: a linha do HEAD nao abre o primeiro run" unless corpos_v.first.to_s.lines.map(&:strip).reject { |l| l.start_with?("#") }.first == cabeca_v
    ruins << "verificar.yml: o verificador antes da linha do HEAD" unless (passos_v.index { |p| p["run"].to_s.include?(cabeca_v) } || 99) < (passos_v.index { |p| p["run"] == "./tools/verificar.sh --testes" } || -1)
    # Rodada 11: nada que mude o shell dos passos seguintes, e o verificador citado so no passo dele (o `: > tools/verificar.sh`
    # ou o `git show` por cima dele no primeiro passo deixavam o portao verde).
    ruins << "verificar.yml: muda o shell dos passos" if corpos_v.any? { |c| c =~ /GITHUB_ENV|GITHUB_PATH|BASH_ENV|SHELLOPTS|BASHOPTS/ }
    ruins << "verificar.yml: o verificador citado fora do passo dele" unless corpos_v.count { |c| c.include?("verificar.sh") } == 1
    corpos_v.each_with_index do |c, i|
        c.to_s.lines.map(&:strip).each do |l|
            ruins << "verificar.yml, run #{i + 1}: || fora do molde" if l.include?("||") && l !~ /\|\|\s*\{ [^{}]*; exit 1; \}\z/
            ruins << "verificar.yml, run #{i + 1}: engole a falha" if l =~ /(\A|[;&|\s])(exit\s+0|set\s+\+|trap)(\s|;|\z)|&&\s*(:|true)(\s|;|\z)|(\A|[;|&]\s*)(true|:)\s*\z/
        end
    end
    # Rodada 9: o checkout dos dois workflows so com as opcoes de hoje: um `ref:` (ou `repository:`) trazia a arvore de outra
    # branch, e a tag era conferida contra a lista de assinantes de la.
    [["release.yml", y], ["verificar.yml", v]].each do |arquivo, w|
        ((w.is_a?(Hash) ? w["jobs"] : nil) || {}).each do |nome, job|
            (job.is_a?(Hash) ? job["steps"] || [] : []).each_with_index do |passo, i|
                next unless passo.is_a?(Hash) && passo["uses"].to_s.start_with?("actions/checkout@")
                com = passo["with"]
                fora = com.is_a?(Hash) ? com.keys.map(&:to_s) - %w[persist-credentials fetch-depth sparse-checkout sparse-checkout-cone-mode] : ["(sem with)"]
                ruins << "#{arquivo}, #{nome}, passo #{i + 1}: checkout com #{fora.join(", ")}" unless fora.empty?
                ruins << "#{arquivo}, #{nome}, passo #{i + 1}: checkout com credencial" unless com.is_a?(Hash) && com["persist-credentials"] == false
            end
        end
    end
    ((v.is_a?(Hash) ? v["jobs"] : nil) || {}).each { |nome, job| ruins << "verificar.yml, #{nome}: runs-on #{job["runs-on"].inspect}" unless job.is_a?(Hash) && job["runs-on"] == "macos-26" }
    ((v.is_a?(Hash) ? v["jobs"] : nil) || {}).each do |nome, job|
        fora = job.is_a?(Hash) ? job.keys - %w[runs-on timeout-minutes steps] : ["(nao e mapa)"]
        ruins << "verificar.yml, #{nome}: #{fora.join(", ")}" unless fora.empty?
        (job.is_a?(Hash) ? job["steps"] || [] : []).each_with_index do |passo, i|
            fora = passo.is_a?(Hash) ? passo.keys - %w[uses with name run] : ["(nao e mapa)"]
            ruins << "verificar.yml, #{nome}, passo #{i + 1}: #{fora.join(", ")}" unless fora.empty?
        end
    end
    # Rodada 8: nada de `defaults` nem `working-directory` (desviavam o `python3 -I tools/...` relativo para outra pasta).
    ruins << "defaults no topo do workflow" if y.key?("defaults")
    (y["jobs"] || {}).each do |nome, job|
        next unless job.is_a?(Hash)
        ruins << "#{nome}: defaults" if job.key?("defaults")
        # Rodada 8: o `if` lido pelo YAML, e nao contado no texto (o `"if": false` entre aspas e o `if : false` pulavam o passo que
        # confere o archive). Nenhum no job, e no passo so o da limpeza.
        ruins << "#{nome}: if no job" if job.key?("if")
        (job["steps"] || []).each_with_index do |passo, i|
            next unless passo.is_a?(Hash) && passo.key?("if")
            ruins << "#{nome}, passo #{i + 1}: if fora da limpeza" unless passo["if"] == "always()" && passo["run"] == "rm -rf \"$HOME\"/.asc.*"
        end
        (job["steps"] || []).each_with_index { |passo, i| ruins << "#{nome}, passo #{i + 1}: working-directory" if passo.is_a?(Hash) && passo.key?("working-directory") }
    end
    texto = File.readlines(".github/workflows/release.yml").count { |l| l !~ /^\s*#/ && l =~ /^\s+run: / }
    ruins << "#{lidos} run no YAML e #{texto} nas linhas que as regras leem" unless lidos == texto
    puts ruins' 2>&1)
[ -z "$passos_release" ] \
    && grep -qxF '          ditto -c -k --norsrc --noextattr --noacl --keepParent EscaliburWallet.xcarchive archive.zip' <<<"$release_sem_comentario" \
    && grep -qxF '              if not nome.startswith("EscaliburWallet.xcarchive/") or ".." in partes or "\\" in nome or "\0" in nome:' <<<"$release_sem_comentario" \
    && grep -qxF '              elif info.create_system != 3 or not (stat.S_ISREG(modo) or stat.S_ISDIR(modo)):' <<<"$release_sem_comentario" \
    && grep -qxF '          python3 -I "$GITHUB_WORKSPACE/tools/conferir-entitlements.py" --ad-hoc "$app"' <<<"$release_sem_comentario" \
    && ! grep -qE 'continue-on-error|set[[:space:]]+[+]|set[[:space:]]+-o?[[:space:]]*[a-z]*[[:space:]]*\+|trap[[:space:]].*(ERR|RETURN|DEBUG)|^[[:space:]]+shell:' <<<"$release_sem_comentario" \
    && [ -z "$(grep -E '^[[:space:]]*set[[:space:]]' <<<"$release_sem_comentario" | grep -vxE '[[:space:]]+set -euo pipefail')" ] \
    && [ -z "$(awk 'aberto { if ($0 !~ /^[[:space:]]+set -euo pipefail$/) print NR": "$0; aberto = 0 } /^[[:space:]]+run: \|$/ { aberto = 1 }' <<<"$release_sem_comentario")" ] \
    && [ "$(grep -cE '^[[:space:]]+if:' <<<"$release_sem_comentario")" = 1 ] \
    && [ "$(grep -A1 -E '^[[:space:]]+if:' <<<"$release_sem_comentario" | tr -d '\n')" = '        if: always()        run: rm -rf "$HOME"/.asc.*' ] \
    && [ -z "$(grep -E '\|\|' <<<"$release_junto" | grep -vE "$molde_do_ou")" ] \
    && [ -z "$(grep -E '&&' <<<"$release_junto" | grep -vE '^[^;]*'"$molde_do_ou" | grep -vE '^[[:space:]]+(if|elif) [^;]*; then$')" ] \
    && ! grep -qE '(^|[;&|[:space:]])(shopt|eval|exit[[:space:]]+0)([[:space:]]|;|$)|^[[:space:]]+run:[[:space:]]*([>]|\|[-+0-9])|[^&]&[[:space:]]*$' <<<"$release_sem_comentario" \
    && [ -z "$(grep -E '(^|[[:space:];])trap[[:space:]]' <<<"$release_sem_comentario" | grep -vxF "          trap 'rm -rf \"\$pasta\"' EXIT")" ] \
    && ! grep -qE '\|\|.*\|\||(^|[^&>|<])&([^&>]|$)|\bcoproc\b|GITHUB_PATH|GITHUB_ENV|BASH_ENV|SHELLOPTS|BASHOPTS|&&[[:space:]]*(:|true)([[:space:];]|$)|\$\{!|\b(declare|typeset|printenv|compgen)\b' <<<"$release_junto" \
    && grep -qxF '          [ "$(shasum -a 256 entrada/archive.zip | cut -d'"'"' '"'"' -f1)" = "$DIGESTO" ] || { echo "::error::o archive nao e o que o build montou"; exit 1; }' <<<"$release_sem_comentario" \
    && grep -qxF '          if [ -n "$(find archive ! -type f ! -type d -print -quit)" ]; then' <<<"$release_sem_comentario" \
    && grep -qxF '          grep -F "  $nome" SHA256SUMS | shasum -a 256 -c -' <<<"$release_sem_comentario" \
    && grep -qxF '          python3 -I "$GITHUB_WORKSPACE/tools/conferir-entitlements.py" "$app"' <<<"$release_sem_comentario" \
    && grep -qF "grep -qx 'TeamIdentifier=2UNWMDD93S' <<<\"\$info\" && grep -q '^Authority=Apple Distribution: ' <<<\"\$info\"" <<<"$release_sem_comentario" \
    && grep -qxF '          if ! git merge-base --is-ancestor "$commit" refs/remotes/origin/main; then' <<<"$release_sem_comentario" \
    && grep -qF -- '-c gpg.minTrustLevel=fully' <<<"$release_sem_comentario" \
    && [ "$(grep -cE '^[[:space:]]+run:' <<<"$release_sem_comentario")" = "$(( $(grep -cE '^[[:space:]]+run: \|$' <<<"$release_sem_comentario") + 1 ))" ] \
    && [ -z "$(grep -E '(^|[;&|[:space:]{])exit([[:space:]]|;|$)' <<<"$release_sem_comentario" | grep -vE 'exit 1(;| \}|$)')" ] \
    && grep -qxF '            App/EscaliburWallet/Resources/EscaliburWallet.entitlements' <<<"$release_sem_comentario" \
    && grep -qxF '            App/EscaliburWidgets/EscaliburWidgets.entitlements' <<<"$release_sem_comentario" \
    && [ "$(grep -cxF '          pasta=$(mktemp -d "$HOME/.asc.XXXXXX")' <<<"$release_sem_comentario")" = 2 ] \
    && [ "$(grep -cxF '          unset ASC_KEY_P8' <<<"$release_sem_comentario")" = 2 ] \
    && [ "$(grep -cxF '          [ "$(git rev-parse HEAD)" = "$GITHUB_SHA" ] || { echo "::error::checkout fora do commit da tag"; exit 1; }' <<<"$release_sem_comentario")" = 3 ] \
    && grep -qxF '          git cat-file blob "$GITHUB_SHA:.github/assinantes" > "$assinantes"' <<<"$release_sem_comentario" \
    && grep -qxF '          export GIT_NO_REPLACE_OBJECTS=1' <<<"$release_sem_comentario" \
    && grep -qF -- 'git -c gpg.ssh.program=/usr/bin/ssh-keygen -c gpg.program=/bin/false -c gpg.x509.program=/bin/false -c gpg.format=ssh' <<<"$release_sem_comentario" \
    && [ "$(grep -cxF '          git fetch --no-tags --force origin "+refs/tags/$TAG:refs/tags/$TAG"' <<<"$release_junto")" = 1 ] \
    && [ "$(grep -cE '[[:space:]]fetch([[:space:]]|$)' <<<"$release_junto")" = 1 ] \
    && [ "$(grep -c 'assinantes' <<<"$release_junto")" = 6 ] \
    && [ -z "$(grep -oE '(^|[^A-Za-z0-9_.-])git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+[a-z-]+' <<<"$release_junto" | sed -E 's/.*git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+//' | grep -vxE 'rev-parse|fetch|cat-file|tag|merge-base')" ] \
    && grep -qxF '          [ "$(git rev-parse HEAD)" = "$GITHUB_SHA" ] || { echo "::error::checkout fora do commit do run"; exit 1; }' .github/workflows/verificar.yml \
    && ! grep -qF 'RUNNER_TEMP/asc' <<<"$release_sem_comentario" \
    && [ "$(grep -cF -- '--ad-hoc "$app"' <<<"$release_sem_comentario")" = 1 ] \
    && [ "$(grep -cF 'xcodebuild -exportArchive' <<<"$release_sem_comentario")" = 1 ] \
    && [ "$(grep -nF -- '--ad-hoc "$app"' <<<"$release_sem_comentario" | cut -d: -f1)" -lt "$(grep -nF 'xcodebuild -exportArchive' <<<"$release_sem_comentario" | cut -d: -f1)" ] \
    && ok "o envio do release confere o zip, o bundle id e os entitlements antes do export, com a chave fora do archive" \
    || { aviso "envio do release sem a conferencia do zip e dos entitlements antes do export, ou com a chave ao alcance do archive"; [ -n "$passos_release" ] && echo "$passos_release"; }
# A Play: nada de pacote da pasta do usuario no play.py (todo import da lista fechada da biblioteca padrao, lido pela arvore
# do Python), o script so roda isolado desde a primeira linha, e o Keychain pelo caminho inteiro do security (rodadas 1 e 2).
imports_da_play=$(python3 -I - tools/android/play.py <<'PY'
import ast, sys
arvore = ast.parse(open(sys.argv[1], encoding="utf-8").read())
nomes = set()
for no in ast.walk(arvore):
    if isinstance(no, ast.Import):
        nomes |= {apelido.name.split(".")[0] for apelido in no.names}
    elif isinstance(no, ast.ImportFrom):
        nomes.add("<from " + str(no.module) + " import>")
    elif isinstance(no, ast.Call) and getattr(no.func, "id", getattr(no.func, "attr", "")) in ("__import__", "import_module", "exec", "eval", "compile", "getattr", "__getattribute__", "vars", "globals", "locals", "setattr", "delattr"):
        nomes.add("<chamada " + getattr(no.func, "id", getattr(no.func, "attr", "")) + ">")
    # Rodada 7: tambem pelo nome sem chamar (`f = exec; f(...)` passava).
    elif isinstance(no, ast.Name) and no.id in ("__builtins__", "__import__", "importlib", "exec", "eval", "compile", "getattr", "vars", "globals",
                                                 "locals", "setattr", "delattr", "breakpoint", "__loader__", "__spec__"):
        nomes.add("<" + no.id + ">")
    elif isinstance(no, ast.Attribute) and no.attr in ("__builtins__", "__import__", "__dict__", "__globals__", "_gcd_import", "meta_path", "path_hooks"):
        nomes.add("<." + no.attr + ">")
    elif isinstance(no, ast.Attribute) and isinstance(no.value, ast.Name) and no.value.id == "sys" and no.attr in ("path", "modules"):
        nomes.add("<sys." + no.attr + ">")
    elif isinstance(no, ast.Attribute) and no.attr == "sys":
        nomes.add("<.sys>")
    # Rodada 6: o loader de um modulo carrega qualquer arquivo (`type(hashlib.__loader__)("x", caminho).load_module()`);
    # nenhum atributo `__...__`, nem os nomes da carga por loader.
    elif isinstance(no, ast.Attribute) and (no.attr.startswith("__") or no.attr in ("load_module", "exec_module", "find_spec", "find_module", "loader", "path_importer_cache", "spec_from_file_location", "module_from_spec")):
        nomes.add("<." + no.attr + ">")
# Uma lista fechada, e nao a biblioteca padrao inteira: o Python 3.9 do Mac nao tem o sys.stdlib_module_names, e modulo
# novo no play.py passa por revisao antes de entrar aqui.
fora = sorted(nomes - {"base64", "hashlib", "json", "os", "subprocess", "sys", "time", "urllib", "zlib"})
print("ok" if not fora else "fora da lista do play.py: " + ", ".join(fora))
PY
)
[ "$imports_da_play" = "ok" ] \
    && [ "$(head -1 tools/android/play.py)" = "#!/usr/bin/python3 -IS" ] \
    && grep -qxF 'if __name__ == "__main__" and not (sys.flags.isolated and sys.flags.no_site):' tools/android/play.py \
    && grep -qxF '    sys.exit("rode com /usr/bin/python3 -IS tools/android/play.py ...")' tools/android/play.py \
    && ! grep -qF 'os.execv' tools/android/play.py \
    && grep -qF '["/usr/bin/security", "find-generic-password", "-a", "escalibur-android", "-s", "escalibur-android-play-api", "-w"]' tools/android/play.py \
    && grep -qF 'ESCALIBUR_UPLOAD_SENHA="$(/usr/bin/security find-generic-password -a escalibur-android -s escalibur-android-upload -w)"' tools/android/gerar-aab.sh \
    && ok "play.py so com a biblioteca padrao e isolado desde a primeira linha, e o Keychain da Play pelo /usr/bin/security" \
    || { aviso "play.py com pacote de fora, sem o isolamento no comeco, ou Keychain lido por outro security"; echo "$imports_da_play"; }

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
for idioma in $(sed -n 's/^ *"\([a-z0-9_]*\)": "[0-9a-f]*".*/\1/p' wordlists.lock); do
    esperado=$(sed -n "s/^ *\"$idioma\": \"\([0-9a-f]*\)\".*/\1/p" wordlists.lock)
    atual=$(shasum -a 256 "$CORE/Resources/Wordlists/$idioma.txt" | cut -d' ' -f1)
    [ "$atual" != "$esperado" ] && { aviso "lista $idioma nao confere"; divergentes=$((divergentes + 1)); }
done
[ "$divergentes" = "0" ] && ok "as 10 listas BIP-39 e a SLIP-39 conferem com wordlists.lock"
# Toda lista da pasta esta no lock: a SLIP-39 fora dele passava sem conferir (revisao dos 3 agentes, 14/11/2026).
fora_do_lock=$(comm -23 <(ls "$CORE/Resources/Wordlists" | sed 's/\.txt$//' | LC_ALL=C sort) <(sed -n 's/^ *"\([a-z0-9_]*\)": .*/\1/p' wordlists.lock | LC_ALL=C sort))
[ -n "$fora_do_lock" ] && { aviso "lista de palavras fora do wordlists.lock"; echo "$fora_do_lock"; } || ok "toda lista de palavras da pasta esta no wordlists.lock"
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
# As palavras saem do cofre so por AppSession.walletPhrase, e a remocao so por AppSession.remove(_:credential:): os dois
# conferem a presenca inteira na propria operacao, e nao na tela que pede (rodada 1 da auditoria 8). No Android, o nucleo
# pede o credencialForte em revelar, remover e abrir o envelope.
# Rodada 2: a frase so dentro do corpo do walletPhrase, e o cofre aberto so nos lugares conhecidos (a entropia tambem da as
# palavras); no Android, cada um dos tres metodos com o credencialForte dentro dele, e nao so tres em qualquer lugar.
achados=$( { procurar '\.phrase[[:space:]]*\(' "$APP" | grep -vE '\bentry\.phrase\(\)|\.phrase\((let |wordCount:)' | grep -v "^$APP/App/AppSession.swift:"
             procurar 'KeyServices[[:space:]]*\.[[:space:]]*wallets\b' "$APP" | grep -vE "^$APP/(App/AppSession|Features/Settings/HardenedModeView)\.swift:" \
                 | grep -vE 'vault: KeyServices\.wallets[,)]'
             procurar 'KeyServices[[:space:]]*\.[[:space:]]*wallets[[:space:]]*\.[[:space:]]*open[[:space:]]*\(' "$APP" | grep -vE "^$APP/(App/AppSession|Features/Settings/HardenedModeView)\.swift:"
             # Rodada 4: o arquivo com as linhas juntas (a referencia partida em duas linhas), o `.self`, o apelido de tipo e a
             # frase guardada numa variavel para chamar depois.
             for f in $(swift_em "$APP" | grep -vE "^$APP/(App/AppSession|Features/Settings/HardenedModeView)\.swift$"); do
                 codigo_vivo_ios "$f" | tr '\n' ' ' | sed -E 's/vault:[[:space:]]*KeyServices[[:space:]]*\.[[:space:]]*wallets[[:space:]]*[,)]//g' \
                     | grep -qE 'KeyServices([[:space:]]*\.[[:space:]]*self)?[[:space:]]*\.[[:space:]]*wallets|typealias[^=]*=[[:space:]]*KeyServices[[:space:]]*($|[^.[:alnum:][:space:]]|[[:space:]]+[a-z])|=[[:space:]]*KeyServices([[:space:]]*\.[[:space:]]*self)?[[:space:]]*($|[^.[:alnum:][:space:]]|[[:space:]]+[a-z])' \
                     && echo "$f: o cofre por outra referencia"
             done
             procurar '\b(secret|segredo|stored|original)\.phrase\b[[:space:]]*($|[^([:space:]])' "$APP"
             # Rodada 5: a extensao do KeyServices, o tipo dele como valor e o caminho de chave, fora do arquivo dele; e o cofre
             # passado adiante so onde ja e, contado por arquivo.
             procurar 'extension[[:space:]]+KeyServices\b|KeyServices[[:space:]]*\.[[:space:]]*(Type|self|store)\b|\\KeyServices|\bWalletVault[[:space:]]*\(|\bKeychainStore[[:space:]]*\(' "$APP" "$WID" "$SHARED" | grep -v "^$APP/Services/KeyServices.swift:"
             [ "$(codigo_vivo_ios "$APP/Features/Settings/ConfirmPassphraseView.swift" | grep -oE 'vault:[[:space:]]*KeyServices[[:space:]]*\.[[:space:]]*wallets' | wc -l | tr -d ' ')" = 1 ] || echo "ConfirmPassphraseView: o cofre passado adiante fora da conta"
             [ "$(codigo_vivo_ios "$APP/Services/PassphraseGate.swift" | grep -oE 'vault:[[:space:]]*KeyServices[[:space:]]*\.[[:space:]]*wallets' | wc -l | tr -d ' ')" = 2 ] || echo "PassphraseGate: o cofre passado adiante fora da conta"
             for f in $(swift_em "$APP" | grep -vE "^$APP/(App/AppSession|Features/Settings/HardenedModeView|Features/Settings/ConfirmPassphraseView|Services/PassphraseGate)\.swift$"); do
                 codigo_vivo_ios "$f" | grep -qE 'vault:[[:space:]]*KeyServices' && echo "$f: o cofre passado adiante"
             done
             # Rodada 6: o tipo do cofre e do Keychain por qualquer referencia, com as linhas juntas (o `WalletVault.init(`,
             # o nome partido entre linhas, o tipo guardado numa variavel), e o `KeyServices.init`; so o limite da
             # passphrase fica de fora.
             for f in $(swift_em "$APP" "$WID" "$SHARED" | grep -vE "^$APP/Services/KeyServices\.swift$"); do
                 codigo_vivo_ios "$f" | tr '\n' ' ' | sed -E 's/WalletVault[[:space:]]*\.[[:space:]]*maxPassphraseBytes([^[:alnum:]_]|$)/ \1/g' \
                     | grep -qE '\b(WalletVault|KeychainStore)\b|KeyServices[[:space:]]*\.[[:space:]]*init\b' && echo "$f: o tipo do cofre fora do KeyServices"
             done
             codigo_vivo_ios "$APP/App/AppSession.swift" | awk '/func walletPhrase\(/ { dentro = 1 } /\.phrase[[:space:]]*\([[:space:]]*\)/ && !dentro { print "AppSession: .phrase() fora do walletPhrase: " $0 } dentro && /^    }$/ { dentro = 0 }'
             codigo "Kit/Sources/Android/EscaliburAndroid/Nucleo.swift" | awk '
                 /^[[:space:]]*(case |default:)/ { if (caso != "" && !forte) print "Nucleo: sem credencialForte em " caso; caso = ""; forte = 0 }
                 /^[[:space:]]*case / && /"(carteira\.revelar|envelope\.abrirCarteira|carteira\.remover)"/ { caso = $0 }
                 { linha = $0; gsub(/"[^"]*"/, "", linha); if (caso != "" && linha ~ /credencialForte\(\)/) forte = 1 }
                 END { if (caso != "" && !forte) print "Nucleo: sem credencialForte em " caso }'; } )
[ "$(codigo_vivo_ios "$APP/App/AppSession.swift" | grep -cF 'guard credential.isFullPresence else {')" = 2 ] \
    && [ "$(codigo_vivo_ios "$APP/App/AppSession.swift" | grep -cF 'KeyServices.wallets.open(')" = 3 ] \
    && [ "$(codigo_vivo_ios "$APP/Features/Settings/HardenedModeView.swift" | grep -cF 'KeyServices.wallets.open(')" = 1 ] \
    && [ "$(codigo "Kit/Sources/Android/EscaliburAndroid/Nucleo.swift" | grep -cF 'Sessao.shared.revelar(')" = 1 ] \
    && [ "$(codigo "Kit/Sources/Android/EscaliburAndroid/Nucleo.swift" | grep -cF 'Envelopes.abrirCarteira(')" = 1 ] \
    && codigo_vivo_ios "$APP/App/AppSession.swift" | grep -qF 'func walletPhrase(_ credential: Credential, walletID: UUID, check: SecureBytes?, fingerprint: [UInt8]?) async throws -> SecureBytes {' \
    && codigo_vivo_ios "$APP/App/AppSession.swift" | grep -qF 'private func removeNow(_ wallet: WalletMeta) throws {' \
    && codigo_vivo_ios "$APP/Services/AuthCoordinator.swift" | grep -qF 'if both, !attempt.isFullPresence {' \
    && [ -z "$achados" ] \
    && [ "$(codigo_vivo "Kit/Sources/Android/EscaliburAndroid/Nucleo.swift" | grep -cF 'try credencialForte()')" = 3 ] \
    && [ "$(codigo "Kit/Sources/Android/EscaliburAndroid/Nucleo.swift" | grep -cF 'Sessao.shared.remover(')" = 2 ] \
    && codigo_vivo "Kit/Sources/Android/EscaliburAndroid/App/Sessao.swift" | grep -qF 'case .pinEBiometria, .reforcado: try comChaveRaiz(credencial) { _ in }' \
    && [ "$(codigo_vivo_ios "$APP/App/AppSession.swift" | awk '/func addWallet\(/ { dentro = 1 } dentro && /checkTronControl\(id\)|checkForeignControl\(id\)|checkTONVersion\(id\)/ { n++ } dentro && /^    }$/ { dentro = 0 } END { print n + 0 }')" = 3 ] \
    && codigo_vivo_ios "$APP/App/AppSession.swift" | grep -qF 'if origin != .created || chosenWords, metadata.selectedWalletID == id || origin == .importedEnvelope {' \
    && codigo_vivo "Kit/Sources/Android/EscaliburAndroid/App/Sessao.swift" | awk '/func revelar\(_ id: UUID, credencial: Credencial/ { dentro = 1 } dentro && passo == 2 { if ($0 ~ /^[[:space:]]*throw RootKeyVault\.Failure\.biometryRequired$/) achou = 1; passo = 0 } dentro && passo == 1 { passo = ($0 ~ /^[[:space:]]*credencial\.zerar\(\)$/) ? 2 : 0 } dentro && /case \.pin, \.biometria:$/ { passo = (anterior ~ /^[[:space:]]*case \.pinEBiometria, \.reforcado: break$/ && antes ~ /^[[:space:]]*switch credencial \{$/) ? 1 : 0 } dentro && /^    }$/ { exit } { antes = anterior; anterior = $0 } END { exit !achou }' \
    && codigo_vivo "Kit/Sources/Android/EscaliburAndroid/App/Envelopes.swift" | awk '/static func abrirCarteira\(_ id: UUID, credencial: Credencial/ { dentro = 1 } dentro && passo == 2 { if ($0 ~ /^[[:space:]]*throw RootKeyVault\.Failure\.biometryRequired$/) achou = 1; passo = 0 } dentro && passo == 1 { passo = ($0 ~ /^[[:space:]]*credencial\.zerar\(\)$/) ? 2 : 0 } dentro && /case \.pin, \.biometria:$/ { passo = (anterior ~ /^[[:space:]]*case \.pinEBiometria, \.reforcado: break$/ && antes ~ /^[[:space:]]*switch credencial \{$/) ? 1 : 0 } dentro && /^    }$/ { exit } { antes = anterior; anterior = $0 } END { exit !achou }' \
    && codigo_vivo "Kit/Sources/Android/EscaliburAndroid/App/Sessao.swift" | awk '/func remover\(_ id: UUID, credencial: Credencial\?\)/ { dentro = 1 } dentro && passo == 2 { if ($0 ~ /^[[:space:]]*throw RootKeyVault\.Failure\.biometryRequired$/) achou = 1; passo = 0 } dentro && passo == 1 { passo = ($0 ~ /^[[:space:]]*credencial\.zerar\(\)$/) ? 2 : 0 } dentro && /case \.pin, \.biometria:$/ { passo = (anterior ~ /^[[:space:]]*case \.pinEBiometria, \.reforcado: try comChaveRaiz\(credencial\) \{ _ in \}$/ && antes ~ /^[[:space:]]*switch credencial \{$/) ? 1 : 0 } dentro && /^    }$/ { exit } { antes = anterior; anterior = $0 } END { exit !achou }' \
    && ok "ver as palavras, lacrar e remover conferem o PIN e o rosto na propria operacao, nas duas plataformas" \
    || { aviso "palavras ou remocao sem a presenca inteira conferida na operacao"; echo "$achados"; }
# A logo baixada so chega ao ImageIO remontada pelo StrictImage, e a de moeda nao verificada nem e baixada (auditoria 8).
# Rodada 2: tambem o AsyncImage, o UIImage de arquivo e os provedores de dados do CoreGraphics; de fora, so as tres leituras
# de arquivo do proprio app (a moeda 3D da abertura, o logo do widget e o do modo demo), linha por linha.
achados=$(procurar '\b(UIImage|CIImage|NSImage)\b[[:space:]]*(\.init)?[[:space:]]*\(([[:space:]]*$|[[:space:]]*(data|contentsOfFile|contentsOf):)|\.init\(data:|\bUIImageReader\b|NSTextAttachment\([[:space:]]*data:|PDFDocument\([[:space:]]*data:|AsyncImage[[:space:]]*\(|CGImageSourceCreateWithData|CGImageSourceCreateWithURL|CGImageSourceCreateWithDataProvider|CGImageSourceCreateIncremental|pngDataProviderSource|jpegDataProviderSource' "$APP" "$WID" "$SHARED" \
    | grep -v "^$APP/Design/CoinLogo.swift:[0-9]*:[[:space:]]*guard let source = CGImageSourceCreateWithData(data as CFData, noCache)," \
    | grep -v "^$APP/Features/Onboarding/BitcoinCoin3D.swift:[0-9]*:[[:space:]]*guard let url = Bundle.main.url(forResource: name, withExtension: \"jpg\"), let image = UIImage(contentsOfFile: url.path)" \
    | grep -v "^$WID/PriceWidget.swift:[0-9]*:[[:space:]]*return UIImage(contentsOfFile: url.path)$" \
    | grep -v "^$APP/App/DebugDemo.swift:[0-9]*:[[:space:]]*logo: WidgetSnapshot.logo.flatMap { UIImage(contentsOfFile: \$0.path) })")
[ -z "$achados" ] \
    && codigo_vivo_ios "$APP/Design/CoinLogo.swift" | grep -qF 'guard let data = StrictImage.sanitize(received) else { return nil }' \
    && codigo_vivo_ios "$APP/Design/CoinLogo.swift" | grep -qF 'guard !unverified, bundled == nil, let remoteURL, let data = await ImageLoader.shared.data(for: remoteURL, persist: true) else { return }' \
    && ok "imagem da internet so pelo StrictImage, e a moeda nao verificada fica com as letras" \
    || { aviso "imagem da internet decodificada sem o StrictImage"; echo "$achados"; }
# A conta com outra chave no controle (EIP-7702, signatario, proxy, chave trocada) nao mostra o endereco para receber, como a
# Tron, nas duas plataformas (auditoria 8, decisao do dono de 14/11/2026).
codigo_vivo_ios "$APP/Services/Metadata.swift" | grep -qF '!(chain.family == .tron && tronForeignControl == true) && foreignControl(on: chain) == nil' \
    && codigo_vivo "Kit/Sources/Android/EscaliburAndroid/App/Metadados.swift" | grep -qF '!(chain.family == .tron && tronForeignControl == true) && foreignControl(on: chain) == nil' \
    && ok "Receber fechado em toda rede com outra chave no controle, nas duas plataformas" \
    || aviso "Receber aberto com outra chave no controle"

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
# Pasteboard.macAllowed antes. O unico outro uso e o clearSecret, que esvazia a area quando o Colar
# do app traz uma frase ou uma chave (revisao dos 3 agentes, 09/11/2026): so a linha que esvazia, uma
# vez, dentro dele.
copias=$(grep -c 'UIPasteboard.general.setItems' "$f"); locais=$(grep -c '\.localOnly: true' "$f"); prazos=$(grep -c '\.expirationDate: Date().addingTimeInterval' "$f")
# Rodada 10: tambem a leitura do numero da area (o `changeCount`, que nao avisa o colar), na copia do endereco de receber e na
# retirada dela quando a conta deixa de receber; esvaziar, so pelo clearSecret.
outras=$(grep -n 'UIPasteboard' "$f" | grep -v 'UIPasteboard.general.setItems' | grep -v 'var options: \[UIPasteboard.OptionsKey: Any\]' \
    | grep -vE '^[0-9]+:        UIPasteboard\.general\.items = \[\]$' \
    | grep -vxE '[0-9]+:        defer \{ lastReceive = \(address, UIPasteboard\.general\.changeCount\) \}' \
    | grep -vxE '[0-9]+:        if UIPasteboard\.general\.changeCount == last\.change \{ clearSecret\(\) \}')
esvazia=$(grep -c '^        UIPasteboard\.general\.items = \[\]$' "$f")
# O clearSecret inteiro e so a linha que esvazia: nada de continuacao gravando outra coisa (revisao dos 3 agentes, 14/11/2026).
esvazia_no_clear=$(awk '/static func clearSecret\(\) \{/,/^    }/' "$f" | tr '\n' '|')
[ "$esvazia_no_clear" = "    static func clearSecret() {|        UIPasteboard.general.items = []|    }|" ] && esvazia_no_clear=1 || esvazia_no_clear=0
endereco_local=$(awk '/static func copyReceiveAddress/,/^    }/' "$f" | grep -c 'guard macAllowed(session, hasPassphrase: hasPassphrase) else { return copyAddress(address) }')
frase_local=$(awk '/static func copyPhrase/,/^    }/' "$f" | grep -c '\.localOnly: true')
[ "$copias" -gt 0 ] && [ "$locais" = "$((copias - 1))" ] && [ "$endereco_local" = "1" ] && [ "$frase_local" = "1" ] && [ "$copias" = "$prazos" ] && [ -z "$outras" ] \
    && [ "$esvazia" = "1" ] && [ "$esvazia_no_clear" = "1" ] \
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
    # A CSP do cabecalho do Worker e a da meta mais frame-ancestors: com as duas diferentes, o navegador aplica as duas e a
    # pagina quebra calada (revisao final de 07/11/2026).
    csp_meta=$(python3 -I -c 'import re, sys; t = open(sys.argv[1], encoding="utf-8").read(); m = re.search(r"^CSP = \((.*?)\)$", t, re.S | re.M); print("".join(re.findall(r"\"([^\"]*)\"", m.group(1))) if m else "")' tools/gerador_site/paginas.py)
    csp_worker=$(python3 -I -c 'import re, sys; t = open(sys.argv[1], encoding="utf-8").read(); m = re.search(r"^const CSP = (.*?);$", t, re.S | re.M); print("".join(re.findall(r"\"([^\"]*)\"", m.group(1))) if m else "")' tools/site-cloudflare/worker.js)
    [ -n "$csp_meta" ] && [ "$csp_worker" = "$csp_meta; frame-ancestors 'none'" ] \
        && ok "a CSP do Worker e a das paginas, mais frame-ancestors" \
        || aviso "a CSP do Worker (tools/site-cloudflare/worker.js) nao e a das paginas (paginas.py) mais frame-ancestors"
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
# A politica do Android: todo host do hosts.lock, menos a consulta da App Store, que o Android nao faz
# (a lista de versoes do github.io ele le desde 07/11/2026, para a tela de atualizar).
faltando=""
for host in $(sed 's|https://||' hosts.lock); do
    case "$host" in itunes.apple.com) continue ;; esac
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
    && codigo "$AND/AndroidManifest.xml" | grep -qF 'android:networkSecurityConfig="@xml/rede"' \
    && [ "$(find Android/app -path '*/build' -prune -o -name 'rede.xml' -print)" = Android/app/src/main/res/xml/rede.xml ] \
    && ! grep -qE 'sourceSets|srcDir' Android/app/build.gradle.kts \
    && [ "$(grep -E '^[[:space:]]*android\.builder\.sdkDownload' Android/gradle.properties)" = 'android.builder.sdkDownload=false' ] \
    && ! grep -q -- '-Pandroid\.' tools/android/gerar-aab.sh \
    && ok "Android sem backup, sem trafego em texto puro e sem certificado instalado pelo usuario" || aviso "manifesto ou rede.xml do Android afrouxado"
# Os tres hosts do preco de referencia da troca so com as raizes que a Cloudflare usa, nas duas plataformas e com a mesma
# lista (checagem final de 16/11/2026, M3): uma autoridade coagida nao forja a referencia.
python3 -I - "$APP/Resources/Info.plist" "$AND/res/xml/rede.xml" <<'PY' && ok "preco de referencia da troca com as autoridades fixadas no iPhone e no Android" || aviso "pins do preco de referencia ausentes ou diferentes entre iPhone e Android"
import plistlib, sys, xml.etree.ElementTree as ET
HOSTS = {"api.coingecko.com", "api.coinpaprika.com", "api.kraken.com"}
PINS = {"hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=", "Vfd95BwDeSQo+NUYxVEEIlvkOlWY2SalKK1lPhzOx78=", "QXnt2YHvdHR3tJYmQIr0Paosp6t/nggsEGD4QJZ3Q0g=",
        "mEflZT5enoR1FuXLgYYGqnVEoZvmf9c2bVBpiOjYQ0c=", "C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=", "diGVwiVYbubAI3RW4hB9xU8e/CH2GnkuvVFZE8zmgzI=",
        "0cRTd+vc1hjNFlHcLgLCHXUeWqn80bNDH/bs9qMTSPo=", "oyD01TTXvpfBro3QSZc1vIlcMjrdLTiL/M9mLCPX+Zo=", "K89VOmb1cJAN3TK6bf4ezAbJGC1mLcG2Dh97dnwr3VQ=",
        "G/ANXI8TwJTdF+AFBM8IiIUPEv0Gf6H5LA/b9guG4yE=",
        "sCkq5UWXjg+7mKu9lMhhYF5bGLsy7VI/UNW3tccdR7w=", "fk6IOKit1ild5647BH06ujSIq5XbCgqlbYl6ANhhi88="}
certo = True
ats = plistlib.load(open(sys.argv[1], "rb")).get("NSAppTransportSecurity", {})
fixados = ats.get("NSPinnedDomains", {})
certo &= set(fixados) == HOSTS and set(ats) == {"NSAllowsArbitraryLoads", "NSPinnedDomains"}
for host, regra in fixados.items():
    certo &= set(regra) == {"NSIncludesSubdomains", "NSPinnedCAIdentities"} and regra["NSIncludesSubdomains"] is False
    certo &= [set(i) for i in regra["NSPinnedCAIdentities"]] == [{"SPKI-SHA256-BASE64"}] * len(PINS)
    certo &= {i["SPKI-SHA256-BASE64"] for i in regra["NSPinnedCAIdentities"]} == PINS
raiz = ET.parse(sys.argv[2]).getroot()
configs = raiz.findall("domain-config")
certo &= len(configs) == 1 and len(raiz.findall("debug-overrides")) == 0
if configs:
    c = configs[0]
    certo &= c.get("cleartextTrafficPermitted") == "false" and not c.findall("domain-config")
    certo &= {d.text for d in c.findall("domain")} == HOSTS and all(d.get("includeSubdomains") == "false" for d in c.findall("domain"))
    certo &= [a.get("src") for a in c.findall("trust-anchors/certificates")] == ["system"]
    certo &= all(a.get("overridePins") in (None, "false") for a in raiz.iter("certificates"))
    conjuntos = c.findall("pin-set")
    certo &= len(conjuntos) == 1 and conjuntos[0].get("expiration") is None
    if conjuntos:
        pins = conjuntos[0].findall("pin")
        certo &= all(p.get("digest") == "SHA-256" for p in pins) and {p.text for p in pins} == PINS and len(pins) == len(PINS)
sys.exit(0 if certo else 1)
PY
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
# A frase nova nasce do sorteio do sistema e de nada mais (licao da Coldcard, 19/11/2026; endurecida na rodada dos 3
# agentes do mesmo dia, que furou a primeira versao com sombra de nome, sobrecarga mais nova e chamada trocada):
# - BIP39.swift, SecureBytes.swift, o ForaDaApple.swift (o sorteio do Android: uma linha a mais deixava 32 bits de entropia,
#   rodada 3), o Mnemonic.swift (o `validWordCounts` que o `generate` le, rodada 3), o WordlistDigest.swift e o Recursos.swift
#   (o digesto esperado da lista e a pasta de onde ela vem: os dois juntos trocavam a lista so no app, rodada 4) e o Wordlist.swift (o `nfkdWords` que o `phrase(fromEntropy:)` le: um subscript com estado deixava 33 bits,
#   rodada 3) travados inteiros pelo digesto do texto sem comentario (o `phrase(fromEntropy:)`, o
#   sorteio dos bits livres do `completing`, um `didSet` no `count`: nada muda sem rever esta regra), e as duas linhas do
#   sorteio exigidas pelo texto;
# - quem cria a frase nos dois apps chama o `generate` ou o `completing` nas linhas de sempre; `phrase(fromEntropy:`,
#   `PhraseDraft(phrase:` e `Rascunho(frase:` so onde ja estao;
# - em nenhum Swift do app ou do Kit fora dos testes (com crase tirada, linha quebrada e comentario no meio, no texto cru e
#   no sem comentario): declaracao de SecRandomCopyBytes, kSecRandomDefault, errSecSuccess, getrandom ou
#   CCryptoBoringSSL_RAND_bytes fora do ForaDaApple.swift (la, so as tres de sempre, e nenhuma no iOS); outra
#   `generate(wordCount`, `random(count`, `phrase(fromEntropy` ou `completing`; `extension BIP39` ou `extension SecureBytes`
#   fora dos donos, ou typealias para eles; @_silgen_name, @_disfavoredOverload, @_dynamicReplacement ou @_extern; @_cdecl
#   fora dos nomes do JNI;
# - no modo --testes, o objeto compilado do SecureBytes chama o _SecRandomCopyBytes do sistema (o binario da loja e conferido
#   no envio, pelo `nm`).
# O limite: um caminho novo ate a carteira em outra parte do app e assunto da revisao do codigo, como no da acessibilidade.
bip=$CORE/BIP39/BIP39.swift
sorteio_digesto() { sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//' | grep -v '^$' | shasum -a 256 | cut -d' ' -f1; }
sorteio_bip=$(codigo "$bip" | sorteio_digesto)
sorteio_sb=$(codigo "$CORE/Crypto/SecureBytes.swift" | sorteio_digesto)
sorteio_fda=$(codigo "$fda" | sorteio_digesto)
sorteio_wl=$(codigo "$CORE/BIP39/Wordlist.swift" | sorteio_digesto)
sorteio_mn=$(codigo "$CORE/BIP39/Mnemonic.swift" | sorteio_digesto)
sorteio_wd=$(codigo "$CORE/BIP39/WordlistDigest.swift" | sorteio_digesto)
sorteio_rec=$(codigo "$CORE/Platform/Recursos.swift" | sorteio_digesto)
sorteio_rascunho=$(cat <<'SWIFT'
final class PhraseDraft {
    let phrase: SecureBytes
    let wordCount: Int

    init(wordCount: Int) throws {
        phrase = try BIP39.generate(wordCount: wordCount)
        self.wordCount = wordCount
    }
SWIFT
)
sorteio_sessao=$(cat <<'SWIFT'
        let frase = try BIP39.generate(wordCount: palavras)
        return try guardarRascunho(Rascunho(frase: frase, palavras: palavras), escolhidas: false, credencial: credencial)
SWIFT
)
[ "$sorteio_bip" = "568c32793be8f2824e865379667422611c75d172dc80c407ec56a900db2d6d67" ] \
    && [ "$sorteio_sb" = "78c6ea1834787c23cdbe4e4ebe96f69e32553b9df25c0cbace46215d1b1f16c8" ] \
    && [ "$sorteio_fda" = "2707933756bc2680693d2dfb01ea3255104dc6ffc03f609efd40f2e2488f8bec" ] \
    && [ "$sorteio_wl" = "b22d1188ba9cef2e7ca0a7940462ea417e3be0db4926c67fe3c460e7405a9974" ] \
    && [ "$sorteio_mn" = "95f34ce602e5b0167e16f3c97ccf7e777080299489782dba3f763b0565b0af8b" ] \
    && [ "$sorteio_wd" = "7b762bdb0bb918152e5f4fd2d4e2c072daef297fea00d02fc00bb472661a9fff" ] \
    && [ "$sorteio_rec" = "d8d0176ab1f5d45738afbd60fb91050f89ca16e7152f54660d2985609776aa4b" ] \
    && python3 -I tools/codigo.py --exige "$bip" 'let entropy = try SecureBytes.random(count: entropyBytes)' --plataforma ambas \
    && python3 -I tools/codigo.py --exige "$CORE/Crypto/SecureBytes.swift" 'let status = SecRandomCopyBytes(kSecRandomDefault, count, bytes.base)' --plataforma ambas \
    && python3 -I tools/codigo.py --exige "$APP/Features/NewWallet/NewWalletFlow.swift" "$sorteio_rascunho" \
    && python3 -I tools/codigo.py --exige "$APP/Features/NewWallet/NewWalletFlow.swift" 'created = try PhraseDraft(wordCount: wordCount)' \
    && python3 -I tools/codigo.py --exige "$APP/Features/NewWallet/NewWalletFlow.swift" 'full = try BIP39.completing(firstWords)' \
    && python3 -I tools/codigo.py --exige Kit/Sources/Android/EscaliburAndroid/App/Sessao.swift "$sorteio_sessao" --plataforma android \
    && python3 -I tools/codigo.py --exige Kit/Sources/Android/EscaliburAndroid/App/Sessao.swift 'frase = try BIP39.completing(primeiras)' --plataforma android \
    && [ -z "$(codigo_vivo_ios "$fda" | tr -d '`' | grep -E 'SecRandomCopyBytes|kSecRandomDefault|errSecSuccess|getrandom|CCryptoBoringSSL_RAND_bytes')" ] \
    && SORTEIO_INVENTARIO=bff15c02dc6854dbce200d610c2bb502670fd5717784e44ee2934aaf29d03052 python3 -I - <<'PY' && ok "a frase nova nasce do SecureBytes.random e ele so do SecRandomCopyBytes do sistema" || aviso "a frase nova ou o SecureBytes.random fora do sorteio do sistema"
import hashlib, os, re, subprocess, sys
sys.path.insert(0, "tools")
import codigo
CORE = "Kit/Sources/EscaliburCore/"
BIP, SB, FORA = CORE + "BIP39/BIP39.swift", CORE + "Crypto/SecureBytes.swift", CORE + "Platform/ForaDaApple.swift"
JNI = "Kit/Sources/Android/EscaliburAndroid/JNI.swift"
lista = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.swift"],
                       capture_output=True, check=True).stdout.decode().split("\0")
fontes = sorted(a for a in set(filter(None, lista)) if os.path.isfile(a) and a.startswith(("Kit/Sources/", "App/"))
                and not a.startswith(("App/EscaliburWalletTests/", "App/EscaliburWalletUITests/")))
NOMES = ("SecRandomCopyBytes", "kSecRandomDefault", "errSecSuccess", "getrandom", "CCryptoBoringSSL_RAND_bytes")
def declara(nome):
    n = re.escape(nome) + r"(?![\w])"
    return re.compile(
        r"\b(?:enum|struct|class|typealias|protocol|actor|let|var|func|associatedtype|macro)\s+" + n
        + r"|\bcase\s+(?:let|var)\s+" + n
        + r"|<\s*(?:[^<>]*,\s*)?" + n + r"\s*[:,>]"
        + r"|[(,]\s*(?:\w+\s+)?" + n + r"\s*:"
        + r"|\bfor\s+(?:case\s+(?:let|var)\s+)?" + n
        + r"|\{\s*\(?[\w\s,]*(?<![\w])" + n + r"[^}]*?\bin\b"
        + r"|\b(?:let|var)\s*\([^)]*(?<![\w])" + n
        + r"|\bimport\s+\w+\s+[\w.]*\." + n, re.S)
DECLARA = {nome: declara(nome) for nome in NOMES}
NA_FORA = {"SecRandomCopyBytes": 1, "kSecRandomDefault": 1, "errSecSuccess": 1, "getrandom": 0, "CCryptoBoringSSL_RAND_bytes": 0}
# Quantas declaracoes cada arquivo tem de cada uma (fora da lista, nenhuma): o Mnemonic.generate e o da isca e dos testes.
MNEMONIC = CORE + "BIP39/Mnemonic.swift"
FUNCOES = [(re.compile(r"\bfunc\s+" + f, re.S), donos) for f, donos in (
    (r"generate\s*(?:<[^>]*>)?\s*\(\s*wordCount(?![\w])", {BIP: 1, MNEMONIC: 1}),
    (r"phrase\s*(?:<[^>]*>)?\s*\(\s*fromEntropy(?![\w])", {BIP: 1}),
    (r"completing(?![\w])", {BIP: 2}), (r"random\s*(?:<[^>]*>)?\s*\(\s*count(?![\w])", {SB: 1}))]
EXT_BIP = re.compile(r"\bextension\s+(?:EscaliburCore\s*\.\s*)?BIP39(?![\w])")
EXT_SB = re.compile(r"\bextension\s+(?:EscaliburCore\s*\.\s*)?SecureBytes(?![\w])")
DONOS_SB = {SB, "Kit/Sources/EscaliburKeys/Enclave.swift", "Kit/Sources/EscaliburKeys/WalletVault.swift"}
APELIDO = re.compile(r"\btypealias\s+\w+\s*(?:<[^>]*>)?\s*=\s*(?:EscaliburCore\s*\.\s*)?(?:BIP39|SecureBytes)(?![\w])")
PROIBIDOS = re.compile(r"@\s*_(?:silgen_name|disfavoredOverload|dynamicReplacement|extern)(?![\w])")
# Com e sem parenteses: `@c func getpid()` compila no Swift 6.3 e toma o lugar da funcao da libc no link (rodada 4).
CDECL = re.compile(r"@\s*(?:_cdecl|c)(?![\w])")
CDECL_OK = re.compile(r'@_cdecl\("(?:JNI_OnLoad|Java_app_escalibur_[A-Za-z0-9_]+)"\)')
# Quem usa o texto, e quantas vezes: a frase de entropia dada, o rascunho com frase dada (iPhone) e o do Android.
USOS = [(re.compile(r"\bphrase\s*\(\s*fromEntropy\s*:"), None,
         {BIP: None, "Kit/Sources/EscaliburKeys/WalletVault.swift": None, "Kit/Sources/EscaliburKeys/DerivationSelfTest.swift": None}),
        (re.compile(r"\bPhraseDraft\s*\(\s*phrase\s*:"), 3,
         {"App/EscaliburWallet/Features/NewWallet/NewWalletFlow.swift": 1, "App/EscaliburWallet/Features/Settings/RevealFlow.swift": 1,
          "App/EscaliburWallet/Features/Envelope/OpenEnvelopeFlow.swift": 1}),
        (re.compile(r"\bRascunho\s*\(\s*frase\s*:"), 4,
         {"Kit/Sources/Android/EscaliburAndroid/App/Sessao.swift": 3, "Kit/Sources/Android/EscaliburAndroid/App/Envelopes.swift": 1})]
# Rodada 2 dos 3 agentes (19/11/2026): um tipo, let ou generico com o nome de quem cria a frase (`enum BIP39` aninhado no
# PhraseDraft, `extension Sessao`) ganha do de verdade na linha exigida; um so, no dono, e nenhum outro em lugar nenhum.
NEWFLOW = "App/EscaliburWallet/Features/NewWallet/NewWalletFlow.swift"
SESSAO = "Kit/Sources/Android/EscaliburAndroid/App/Sessao.swift"
TIPOS = {"BIP39": {BIP: 1}, "SecureBytes": {SB: 1}, "PhraseDraft": {NEWFLOW: 1}, "Rascunho": {SESSAO: 1}, "EscaliburCore": {}, "EscaliburKeys": {}}
TIPO_RE = {nome: declara(nome) for nome in TIPOS}
GERA = re.compile(r"\b(?:let|var|case|subscript)\s+(?:generate|completing)(?![\w])")
DINAMICOS = re.compile(r"\bcallAsFunction\b|@\s*dynamicMemberLookup\b|@\s*dynamicCallable\b")
EXPORTADO = re.compile(r"@\s*_exported\s+import\b")
problemas = []
for arquivo in fontes:
    cru = open(arquivo, encoding="utf-8").read()
    sem = codigo.ler(arquivo, False).replace("`", "")
    textos = (cru.replace("`", ""), sem)
    for nome, regra in DECLARA.items():
        if nome not in textos[0] and nome not in textos[1]:
            continue
        if arquivo == FORA:
            if len(regra.findall(sem)) != NA_FORA[nome]:
                problemas.append(f"{arquivo}: {nome} declarado {len(regra.findall(sem))} vezes (esperado {NA_FORA[nome]})")
        elif any(regra.search(t) for t in textos):
            problemas.append(f"{arquivo}: declara {nome}")
    for regra, donos in FUNCOES:
        n = max(len(regra.findall(t)) for t in textos)
        if n != donos.get(arquivo, 0):
            problemas.append(f"{arquivo}: {n} declaracoes de {regra.pattern}")
    if arquivo != BIP and any(EXT_BIP.search(t) for t in textos):
        problemas.append(f"{arquivo}: extension BIP39 fora do dono")
    if arquivo not in DONOS_SB and not arquivo.startswith("Kit/Sources/SwiftCrypto/") and any(EXT_SB.search(t) for t in textos):
        problemas.append(f"{arquivo}: extension SecureBytes fora dos donos")
    if any(APELIDO.search(t) for t in textos):
        problemas.append(f"{arquivo}: typealias para BIP39 ou SecureBytes")
    if any(PROIBIDOS.search(t) for t in textos):
        problemas.append(f"{arquivo}: atributo que troca funcao (@_silgen_name, @_disfavoredOverload, @_dynamicReplacement, @_extern)")
    cdecl = max(len(CDECL.findall(t)) for t in textos)
    if cdecl and (arquivo != JNI or cdecl != len(CDECL_OK.findall(cru))):
        problemas.append(f"{arquivo}: @_cdecl fora dos nomes do JNI")
    if not arquivo.startswith("Kit/Sources/SwiftCrypto/"):
        for nome, regra in TIPO_RE.items():
            if nome not in textos[0] and nome not in textos[1]:
                continue
            n = max(len(regra.findall(t)) for t in textos)
            if n != TIPOS[nome].get(arquivo, 0):
                problemas.append(f"{arquivo}: {n} declaracoes com o nome {nome}")
        if any(EXPORTADO.search(t) for t in textos):
            problemas.append(f"{arquivo}: @_exported import")
    if arquivo != BIP and any(GERA.search(t) for t in textos):
        problemas.append(f"{arquivo}: let, var, case ou subscript chamado generate ou completing")
    if any(DINAMICOS.search(t) for t in textos):
        problemas.append(f"{arquivo}: callAsFunction, @dynamicMemberLookup ou @dynamicCallable")
    for regra, _, donos in USOS:
        n = max(len(regra.findall(t)) for t in textos)
        esperado = donos.get(arquivo, 0)
        if (esperado is None and n == 0) or (esperado is not None and n != esperado):
            problemas.append(f"{arquivo}: {regra.pattern} {n} vezes")
# Uma funcao em C, C++, Objective-C ou assembly com o nome do sorteio ganha dele no link (provado na rodada de 19/11):
# nenhum desses arquivos do Kit ou do app cita o SecRandomCopyBytes ou o kSecRandomDefault.
outros = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "Kit/Sources", "App"],
                        capture_output=True, check=True).stdout.decode().split("\0")
for arquivo in sorted(set(filter(None, outros))):
    if os.path.isfile(arquivo) and arquivo.endswith((".c", ".h", ".m", ".mm", ".cc", ".cpp", ".hpp", ".s", ".S", ".inc", ".cxx", ".c++",
                                                     ".cp", ".C", ".M", ".hh", ".hxx", ".h++", ".ipp", ".modulemap")):
        texto = open(arquivo, encoding="utf-8", errors="replace").read()
        if re.search(r"SecRandomCopyBytes|kSecRandomDefault", texto):
            problemas.append(f"{arquivo}: cita o SecRandomCopyBytes")
        # Um nome Swift dado a uma funcao C (`swift_name`, que o pre-processador ainda emenda) entra no lugar de outra.
        if not arquivo.startswith("Kit/Sources/SwiftCrypto/") and re.search(r"swift_name|SWIFT_NAME", texto):
            problemas.append(f"{arquivo}: swift_name")
# O inventario do EscaliburCore (rodada 2 dos 3 agentes, 19/11/2026): uma extensao de tipo de fora (Array, UInt32,
# UnsafeMutableRawPointer) ou uma declaracao de topo no modulo ganha da biblioteca padrao dentro do BIP39 e do SecureBytes
# travados, sem citar nome nenhum. Toda extensao de tipo de fora (com o corpo) e todo nome de topo, vivos no iPhone ou no
# Android, entram num digesto: mudou, a regra para, e quem mexeu confere a lista impressa e grava o digesto novo.
def nivel(texto):
    marcas, prof = [], 0
    for c in texto:
        marcas.append(prof)
        prof += 1 if c == "{" else -1 if c == "}" else 0
    return marcas
def corpo(texto, inicio):
    i = texto.find("{", inicio)
    if i < 0:
        return ""
    prof = 0
    for j in range(i, len(texto)):
        prof += 1 if texto[j] == "{" else -1 if texto[j] == "}" else 0
        if prof == 0:
            return " ".join(texto[i:j + 1].split())
    return " ".join(texto[i:].split())
nucleo = [a for a in fontes if a.startswith(CORE)]
vivos = {(a, plat): codigo.ler(a, True, plat).replace("`", "") for a in nucleo for plat in ("ios", "android")}
# O esqueleto de cada arquivo, em qualquer grafia (rodada 3: `extension[UInt8]`, `func>>` e `let(SHA256, _)` compilam sem
# espaco e escapavam das buscas por palavra): todo caractere de nivel 0, imports inclusive, e toda extensao de nivel 0, de
# qualquer tipo, com o cabecalho e o corpo.
inventario = set()
for (arquivo, plataforma), texto in vivos.items():
    marcas = nivel(texto)
    topo = " ".join("".join(c if m == 0 else " " for c, m in zip(texto, marcas)).split())
    inventario.add(f"{arquivo} {plataforma} topo {hashlib.sha256(topo.encode()).hexdigest()}")
    for m in re.finditer(r"\bextension(?![\w])", texto):
        if marcas[m.start()] == 0:
            cabeca = " ".join(texto[m.end():texto.find("{", m.end())].split())
            inventario.add(f"{arquivo} {plataforma} extension {cabeca} {hashlib.sha256(corpo(texto, m.end()).encode()).hexdigest()}")
lista_do_nucleo = "\n".join(sorted(inventario))
if hashlib.sha256(lista_do_nucleo.encode()).hexdigest() != os.environ.get("SORTEIO_INVENTARIO", ""):
    problemas.append("o inventario do EscaliburCore mudou (extensao de tipo de fora ou nome de topo):")
    problemas.extend("  " + linha for linha in sorted(inventario))
for problema in problemas:
    print("    " + problema)
sys.exit(1 if problemas else 0)
PY
sb=$CORE/Crypto/SecureBytes.swift
# A cota de memoria travada do Android (64 KiB) acaba no 17o buffer com regiao propria: o segredo pequeno vai para uma
# arena travada, e nenhum mlock tem o resultado engolido (auditoria das chaves de 06/11/2026).
codigo_vivo_android "$sb" | grep -qF 'if mlock(region.advanced(by: pageSize), payloadPages * pageSize) != 0 { LockedArena.noteLockFailure() }' \
    && codigo_vivo_android "$sb" | grep -qE 'madvise\(region, regionSize, MADV_DONTDUMP\)' \
    && codigo_vivo_android "$sb" | grep -qF 'if let slot = LockedArena.take(capacity) {' \
    && codigo_vivo_android "$sb" | grep -qF 'mlock(base, payload) == 0' \
    && ! codigo_vivo_android "$sb" | grep -qE '_ = mlock' \
    && ok "SecureBytes prende o segredo na RAM e fora do core dump (arena travada, mlock conferido, MADV_DONTDUMP)" || aviso "SecureBytes sem a arena travada, sem MADV_DONTDUMP ou com mlock sem conferir (AA-01)"
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
python3 -I - <<'PY' && ok "loja.lock e um JSON sem chave repetida, com os 32 arquivos" || aviso "loja.lock com chave repetida, outra forma ou outra contagem"
import json, sys
def sem_repetida(pares):
    if len(pares) != len({chave for chave, _ in pares}):
        raise ValueError("chave repetida")
    return dict(pares)
try:
    lock = json.load(open("loja.lock", encoding="utf-8"), object_pairs_hook=sem_repetida)
except ValueError:
    sys.exit(1)
# Rodada 15: e a contagem do copia-publicada.sh igual a do lock, lida dele, e nao so um 32 fixo nos dois lugares.
import re
conta = re.findall(r"len\(lock\) == ([0-9]+) and all\(", open("tools/copia-publicada.sh", encoding="utf-8").read())
sys.exit(0 if set(lock) == {"nota", "arquivos"} and isinstance(lock["arquivos"], dict) and len(lock["arquivos"]) == 32
         and conta == [str(len(lock["arquivos"]))] else 1)
PY
# Exatamente os scripts da loja, o workflow do release e o que compila o nucleo: tirar uma entrada do lock e mudar o
# arquivo nao passa. No shell e no yml, texto entre aspas conta como vivo por desenho: o lock e o portao (sexta passada).
# Decima passada: tambem o conferidor das flags do build, o Package.swift (que decide as flags) e o Gradle (que decide
# as fontes do Kotlin e o R8); decima primeira: o projeto do Xcode (as chaves de ajuste, os caminhos e o esquema). Rodada 1
# da auditoria 8: o conferidor de entitlements, que roda no job do envio, o que tem a chave da App Store Connect.
[ "$(sed -n 's/^    "\([^"]*\)": "[0-9a-f]\{64\}".*/\1/p' loja.lock 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')" = ".github/workflows/release.yml .github/workflows/site.yml .github/workflows/verificar.yml .xcode-version Android/app/build.gradle.kts Android/app/proguard-rules.pro Android/build.gradle.kts Android/gradle.properties Android/gradle/libs.versions.toml Android/gradle/verification-metadata.xml Android/gradle/wrapper/gradle-wrapper.jar Android/gradle/wrapper/gradle-wrapper.properties Android/settings.gradle.kts EscaliburWallet.xcodeproj/project.pbxproj EscaliburWallet.xcodeproj/project.xcworkspace/contents.xcworkspacedata EscaliburWallet.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings EscaliburWallet.xcodeproj/xcshareddata/xcschemes/EscaliburWallet.xcscheme Kit/Package.swift project.yml tools/android/compilar-nucleo.sh tools/android/gerar-aab.sh tools/android/play.py tools/android/testar-nucleo.sh tools/arquivar.sh tools/codigo.py tools/conferir-entitlements.py tools/copia-publicada.sh tools/digesto.sh tools/flags-do-build.py tools/flags-do-pacote.py tools/verificar.sh tools/versoes/versoes.swift " ] \
    && ok "loja.lock trava os scripts da loja, o release.yml, os conferidores das flags, o Package.swift, o projeto do Xcode, o Gradle e o envio a Play" || aviso "loja.lock sem os scripts da loja, o release.yml, os conferidores das flags, o Package.swift, o projeto do Xcode, o Gradle ou o envio a Play"
# A ordem das travas da loja (rodada 3 dos 3 agentes da checagem final de 16/11/2026): no gerar-aab.sh, o JDK e o SDK
# conferidos depois dos vetores e do nucleo e antes do Gradle; no testar-nucleo.sh, o toolchain antes do swift build.
python3 -I - <<'PY' && ok "a conferencia do JDK, do SDK e do toolchain vem antes de usa-los" || aviso "trava da loja fora de ordem"
import sys
g = open("tools/android/gerar-aab.sh", encoding="utf-8").read()
t = open("tools/android/testar-nucleo.sh", encoding="utf-8").read()
def pos(texto, trecho):
    i = texto.find(trecho)
    return i if i >= 0 and texto.count(trecho) == 1 else -1
a, b, c, d = (pos(g, '"$aqui/tools/android/compilar-nucleo.sh" release --loja'), pos(g, "/usr/bin/codesign --verify --deep --strict"),
              pos(g, "/bin/rm -rf Android/.gradle Android/.kotlin Android/build Android/app/build"), pos(g, "./gradlew -q --no-daemon"))
e, f = pos(t, 'for binario in swift swift-build swift-driver swift-frontend clang ld.lld; do'), pos(t, '"$SWIFT" build --build-tests')
sys.exit(0 if min(a, b, c, d, e, f) >= 0 and a < b < c < d and e < f else 1)
PY
origem=0
exigidos=(
    # Rodada 14 da auditoria 8: a contagem do loja.lock na copia limpa igual a do verificador (32): com 29 la, o build da loja
    # parava no arquivar.sh e no gerar-aab.sh, com a mensagem de um arquivo que nao confere.
    "tools/copia-publicada.sh|sys.exit(0 if len(lock) == 32 and all(hashlib.sha256(open(c, \"rb\").read()).hexdigest() == d for c, d in lock.items()) else 1)"
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
    # Checagem final de 16/11/2026, M1: o JDK pelo selo da Temurin e pelo digesto, o SDK pelo digesto e o Gradle numa pasta
    # nova a cada build, sem nada do ~/.gradle.
    "tools/android/gerar-aab.sh|-R='identifier \"net.java.openjdk.jdk\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"JCDTMS22B4\"'"
    "tools/android/gerar-aab.sh||| { echo \"o JDK, a plataforma ou o build-tools do SDK nao sao os conferidos (selo ou digesto da arvore): nada foi montado\" >&2; exit 1; }"
    # Revisao dos 3 agentes da checagem final: a conferencia logo antes do Gradle, com a copia limpa de novo; o ~/.android
    # fora; o Kotlin dentro do Gradle; o nucleo do pacote igual ao do carimbo; o adb do Google; sem strip e sem baixar SDK.
    "tools/android/gerar-aab.sh||| { echo \"a copia limpa mudou durante os vetores ou a compilacao do nucleo: nada foi montado\" >&2; exit 1; }"
    "tools/android/gerar-aab.sh|trap '/bin/rm -rf \"\$casa_gradle\"' EXIT"
    "tools/android/gerar-aab.sh|export GRADLE_USER_HOME=\"\$casa_gradle\" ANDROID_USER_HOME=\"\$casa_gradle/android\""
    "tools/android/gerar-aab.sh|--dependency-verification strict -Pkotlin.compiler.execution.strategy=in-process -PcommitDeOrigem="
    "tools/android/gerar-aab.sh|read -r carimbo_modo carimbo_commit carimbo_nucleo carimbo_libcxx < build/android-kit/origem-do-nucleo.txt"
    "tools/android/gerar-aab.sh|[ \"\$carimbo_modo\" = release-loja ] && [ \"\$carimbo_commit\" = \"\$commit\" ] \\"
    "tools/android/gerar-aab.sh|[ \"\$(shasum -a 256 \"\$biblioteca/libEscaliburAndroid.so\" | cut -d' ' -f1)\" = \"\$carimbo_nucleo\" ] \\"
    "tools/android/gerar-aab.sh|&& [ \"\$(shasum -a 256 \"\$biblioteca/libc++_shared.so\" | cut -d' ' -f1)\" = \"\$carimbo_libcxx\" ] \\"
    "tools/android/gerar-aab.sh||| { echo \"o nucleo ou a libc++ no pacote nao sao os do carimbo: nada foi entregue\" >&2; exit 1; }"
    "tools/android/testar-nucleo.sh|-R='identifier \"adb\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"EQHXZ8M8AV\"' \"\$ADB\" \\"
    # Rodada 3: o toolchain, o Swift SDK e o NDK conferidos antes dos vetores; as pastas ignoradas antes do Gradle.
    "tools/android/testar-nucleo.sh||| { echo \"o \$binario do toolchain nao tem a assinatura da Swift Open Source\" >&2; exit 1; }"
    "tools/android/testar-nucleo.sh||| { echo \"o \$binario do NDK nao tem a assinatura do Google\" >&2; exit 1; }"
    "tools/android/testar-nucleo.sh|[ \"\$(arvore \"\$TOOLCHAIN/usr\")\" = 44ce03df2d41af82411e4b180b5fb43327b8dee1a02e85b9b31ac4cea3748248 ] \\"
    "tools/android/testar-nucleo.sh||| { echo \"o toolchain, o Swift SDK ou o NDK nao sao os conferidos (o digesto da arvore mudou)\" >&2; exit 1; }"
    "tools/android/gerar-aab.sh|/bin/rm -rf Android/.gradle Android/.kotlin Android/build Android/app/build"
    "tools/android/gerar-aab.sh|[ -z \"\$(git status --porcelain=v1 --untracked-files=all)\" ] \\"
    "tools/android/gerar-aab.sh|&& [ -z \"\$(git status --porcelain=v1 --ignored=traditional --untracked-files=normal | grep -vxF -e '!! build/' -e '!! Android/app/src/main/jniLibs/' -e '!! Kit/.build/' -e '!! Kit/.swiftpm/')\" ] \\"
    "tools/android/gerar-aab.sh|&& [ \"\$(cd Android/app/src/main/jniLibs && find . -mindepth 1 | LC_ALL=C sort | tr '\\n' ' ')\" = \"./arm64-v8a ./arm64-v8a/libEscaliburAndroid.so ./arm64-v8a/libc++_shared.so \" ] \\"
    "tools/android/gerar-aab.sh|unzip -q \"\$apk\" 'lib/arm64-v8a/libEscaliburAndroid.so' 'lib/arm64-v8a/libc++_shared.so' -d \"\$dex/apk-lib\""
    "tools/android/gerar-aab.sh|unzip -q \"\$aab\" 'base/lib/arm64-v8a/libEscaliburAndroid.so' 'base/lib/arm64-v8a/libc++_shared.so' -d \"\$dex/aab-lib\""
    "tools/android/gerar-aab.sh|for biblioteca in \"\$dex/apk-lib/lib/arm64-v8a\" \"\$dex/aab-lib/base/lib/arm64-v8a\"; do"
    "tools/android/testar-nucleo.sh||| { echo \"o adb nao tem a assinatura do Google: nada foi rodado\" >&2; exit 1; }"
    "Android/app/build.gradle.kts|jniLibs { useLegacyPackaging = false; keepDebugSymbols += \"**/*.so\" }"
    "tools/android/gerar-aab.sh|&& [ \"\$(arvore \"\$JAVA_HOME\")\" = 7b238c151db1ae2a3dbf86e7dd237db46e577714baad2a326ae2d0c7be5cd3d3 ]"
    "tools/android/gerar-aab.sh|&& [ \"\$(arvore \"\$ANDROID_HOME/platforms/android-37.0\")\" = 79a0343c9b1f159b66e28adad51838ef22cc9ac47570cb3fe42a2f0ff56400eb ]"
    "tools/android/gerar-aab.sh|&& [ \"\$(arvore \"\$ANDROID_HOME/build-tools/36.0.0\")\" = a74275b60c4b098b13049d9c3fa17d1afa5f0e23ca9f354f05a42e8c670f6790 ]"
    "tools/android/gerar-aab.sh|export GRADLE_USER_HOME=\"\$casa_gradle\""
    # Checagem final de 16/11/2026, M3: sem preco de referencia, a troca pede o aceite tambem com duas fontes.
    "Kit/Sources/EscaliburEngines/EVM/EVMTradeEngine.swift|unanchored = market.reference.oracleOut == nil"
    "Kit/Sources/EscaliburEngines/Stellar/StellarTradeEngine.swift|unanchored: marketReference.oracleOut == nil"
    "Kit/Sources/EscaliburEngines/Stellar/StellarTradeEngine.swift|guard !quote.unanchored || request.acceptsUnanchored else {"
    "Kit/Sources/EscaliburEngines/Stellar/StellarTradeEngine.swift|return quote.unanchored ? plan.addingWarnings([.uncomparedPrice]) : plan"
    "Kit/Sources/EscaliburEngines/XRPL/XRPLTradeEngine.swift|unanchored: marketReference.oracleOut == nil"
    "Kit/Sources/EscaliburEngines/XRPL/XRPLTradeEngine.swift|guard !quote.unanchored || request.acceptsUnanchored else {"
    "Kit/Sources/EscaliburEngines/XRPL/XRPLTradeEngine.swift|return quote.unanchored ? plan.addingWarnings([.uncomparedPrice]) : plan"
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
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -qF 'if (!bloqueado && !deTerceiros && (sistema != null || peloCelular)) {' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoDePalavras.kt" | grep -q 'if (!demo && deFora.isNotEmpty())' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/Acessibilidade.kt" | grep -q 'val deFora = ligados.values.filter { info -> !doSistema(info) }' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/Segredo.kt" | grep -qF 'if (fechadoPelaAcessibilidade(segredo)) return true' \
    && [ "$(codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/Segredo.kt" | grep -cF 'if (fechadoPelaAcessibilidade(segredo)) return true')" -ge 3 ] \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -qF 'val deSegredo = campoSecreto(info) || sistema?.palavras == true' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -qF 'val bloqueado = deSegredo && app.escalibur.wallet.ui.Acessibilidade.suspeitosParaSegredo.isNotEmpty()' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -qF 'foco.clearFocus(force = true)' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -qF 'suspeitosParaSegredo.isNotEmpty()) awaitCancellation()' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoDePalavras.kt" | grep -qF 'TecladoFechadoPelaAcessibilidade(deFora)' \
    && ok "o teclado de segredo fecha com qualquer servico de acessibilidade de fora, em qualquer Android, tambem o fisico e o que ja estava aberto" \
    || aviso "teclado de segredo aberto com servico de acessibilidade de fora"
# A carteira inteira fecha com qualquer servico de acessibilidade que nao veio com o celular, em qualquer Android, se
# declare ferramenta ou nao (pentest de 17/11/2026, A-1): do 14 em diante, esconder a leitura nao tira de cima da tela a
# janela do servico, que o setHideOverlayWindows nao esconde e o filterTouchesWhenObscured nao ve. Fechou, travou: o portao
# do Raiz derruba o pedido de biometria e trava a sessao, e so depois mostra a tela fechada.
# Trecho solto nao segura esta regra (tres rodadas dos 3 agentes, 17/11/2026: um filtro encadeado no `deFora`, um retorno
# cedo, uma condicao na frente da linha do Raiz, a carteira montada dentro da tela fechada, um import que troca o objeto, o
# `setContent` com outra coisa dentro, o travar sem o `sessao.travar`). Vai por digesto do codigo sem comentario e sem
# diferenca de espaco, do caminho inteiro entre abrir o app e o portao:
#   - Acessibilidade.kt inteiro, sem o texto entre aspas (a regra e a tela fechada; o texto da tela pode mudar), e o
#     objeto de novo com o texto entre aspas, que nele e parte da regra;
#   - Raiz.kt: o `package` e os imports (um import ganha da declaracao do mesmo pacote e trocaria o objeto, a tela ou o
#     travar), o comeco do `Raiz` ate o retorno da tela fechada, e o `travarAgora`;
#   - MainActivity.kt do topo ate o `setContent`, e o `onStart` ate a conferencia; o `TemaEscalibur`; o `cancelarBiometria`.
# Mudou de proposito (um import novo no Raiz.kt tambem conta): confira que o portao segue como esta descrito aqui e grave
# o digesto novo. Em volta, sem digesto, sempre no codigo sem comentario e sem crase (o Kotlin aceita qualquer nome entre
# crases, e a crase escondia o nome da conferencia):
#   - so a MainActivity monta tela (`setContent`, `ComposeView`, `Composition`), uma vez, e o app tem uma Activity so;
#   - o teclado proprio repassa o conteudo e nao usa nenhum pacote de tela;
#   - as telas de entrada (bloqueio, PIN, carteira) so sao citadas, por palavra, nos arquivos de sempre;
#   - os nomes do caminho (`Acessibilidade`, `TelaDeAcessibilidade`, `Ciclo`, `Raiz`, `TecladoSeguro`, `TemaEscalibur`,
#     `Cofre`) so sao declarados onde ja sao, 8 vezes: uma propriedade, uma funcao de extensao ou um objeto com o mesmo
#     nome, em qualquer arquivo, ganharia do verdadeiro na resolucao de nomes do Kotlin.
# O limite desta trava e este: escrever em outra parte do app um caminho novo ate a carteira e assunto da revisao do codigo.
a11y_normal() { sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//' | grep -v '^$'; }
a11y_digesto() { a11y_normal | shasum -a 256 | cut -d' ' -f1; }
a11y_w="$AND/java/app/escalibur/wallet"
a11y_arquivo=$(codigo_vivo "$a11y_w/ui/Acessibilidade.kt" | a11y_digesto)
a11y_objeto=$(codigo "$a11y_w/ui/Acessibilidade.kt" | awk '/^object Acessibilidade \{/ { d = 1 } d { print } d && /^\}/ { exit }' | a11y_digesto)
a11y_cabeca=$(codigo "$a11y_w/ui/Raiz.kt" | grep -E '^[[:space:]]*(package|import)([[:space:]]|$)' | a11y_digesto)
a11y_raiz=$(codigo "$a11y_w/ui/Raiz.kt" | awk '/^fun Raiz\(\) \{/ { d = 1 } d { print } d && /^ *return[[:space:]]*$/ { exit }' | a11y_digesto)
a11y_travar=$(codigo "$a11y_w/ui/Raiz.kt" | awk '/^    suspend fun travarAgora\(\) \{/ { d = 1 } d { print } d && /^    \}[[:space:]]*$/ { exit }' | a11y_digesto)
a11y_entrada=$(codigo "$a11y_w/MainActivity.kt" | awk '{ print } /^ *setContent \{/ { exit }' | a11y_digesto)
a11y_volta=$(codigo "$a11y_w/MainActivity.kt" | awk '/^    override fun onStart\(\)/ { d = 1 } d { print } d && /Acessibilidade\.conferir\(this\)/ { exit }' | a11y_digesto)
a11y_tema=$(codigo "$a11y_w/ui/tema/Tema.kt" | awk '/^fun TemaEscalibur\(/ { d = 1 } d { print } d && /^\}[[:space:]]*$/ { exit }' | a11y_digesto)
a11y_bio=$(codigo "$a11y_w/nucleo/Cofre.kt" | awk '/^    fun cancelarBiometria\(\) \{/ { d = 1 } d { print } d && /^    \}[[:space:]]*$/ { exit }' | a11y_digesto)
a11y_compoe=$(for a11y_f in $(grep -rlE 'setContent|ComposeView|Composition|Recomposer' "$AND/java"); do codigo "$a11y_f" | tr -d '`' | grep -qwE 'setContent|ComposeView|AbstractComposeView|Composition|createComposition|Recomposer' && echo "$a11y_f"; done)
a11y_entradas="$a11y_w/ui/(Raiz|bloqueio/Bloqueio|ajustes/Seguranca|abertura/Abertura|pin/Pin|principal/Principal)\\.kt"
a11y_telas=$(for a11y_f in $(grep -rlE 'TelaDeBloqueio|TelaDoPin|Principal|FluxoDeAbertura|TelaSemBloqueio' "$AND/java"); do codigo_vivo "$a11y_f" | tr -d '`' | grep -qwE 'TelaDeBloqueio|TelaDoPin|Principal|FluxoDeAbertura|TelaSemBloqueio' && echo "$a11y_f"; done | grep -vxE "$a11y_entradas")
a11y_nomes='Acessibilidade|TelaDeAcessibilidade|Ciclo|Raiz|TecladoSeguro|TemaEscalibur|Cofre'
a11y_declarados=$(for a11y_f in $(grep -rlE "$a11y_nomes" "$AND/java"); do codigo "$a11y_f" | tr -d '`' | tr '\n' ' ' | sed 's/[^A-Za-z0-9_]/&&/g'; echo; done | grep -oE "(^|[^A-Za-z0-9_])((object|class|interface|typealias)[[:space:]]+|(fun|val|var)[[:space:]]+([^(=;{}:]*[^A-Za-z0-9_])?)($a11y_nomes)([^A-Za-z0-9_]|\$)" | wc -l | tr -d ' ')
[ "$a11y_arquivo" = "20acc5962d6dd59452e65042da0e5050729f99c5cd0d2e5a1ede55f039496780" ] \
    && [ "$a11y_objeto" = "ad14b7fb067545166519596412863d1797d3bdcb33da8325c5cbfb07761a017e" ] \
    && [ "$a11y_cabeca" = "1c98a9beb2b9f85366394f8dc297f6a02b0df8c8804b261ce0c5662f4d9a66e9" ] \
    && [ "$a11y_raiz" = "9b176acca2fd4ea622dd48fc75a7499a8ae52bc9b1aa9009be88025ecad45d5b" ] \
    && [ "$a11y_travar" = "24a864f24d8d3b848bdb7d42e4fe59f09c517407ed9b2ddc518616f2ed8625ae" ] \
    && [ "$a11y_entrada" = "11467a9a0b8950a5afc982a698f20e678d5a96a53d962a350eaf36dc2e939136" ] \
    && [ "$a11y_volta" = "395bf07a4a43d0060e0aa9d2ffb4fb0708eb908484af083478e0438d320e7044" ] \
    && [ "$a11y_tema" = "6c2389bc9fbf567ffc4c3b2c4c3ce02532c918d268078787af85a82a9a9c7de0" ] \
    && [ "$a11y_bio" = "7f98514ffff5400f1529d705c1f4733be42750e1ce649cc3fe433137692318c5" ] \
    && [ "$(codigo "$a11y_w/ui/Raiz.kt" | grep -c '^fun Raiz() {')" = 1 ] \
    && [ "$a11y_compoe" = "$a11y_w/MainActivity.kt" ] \
    && [ "$(codigo "$a11y_w/MainActivity.kt" | tr -d '`' | grep -oE '(^|[^A-Za-z0-9_])setContent([^A-Za-z0-9_]|$)' | wc -l | tr -d ' ')" = 2 ] \
    && [ "$(find "$AND/.." -name AndroidManifest.xml -exec cat {} + | grep -oE '<activity' | wc -l | tr -d ' ')" = 1 ] \
    && [ "$(codigo "$a11y_w/ui/comp/TecladoSeguro.kt" | a11y_normal | grep -cxF 'content = conteudo,')" = 1 ] \
    && [ -z "$(codigo "$a11y_w/ui/comp/TecladoSeguro.kt" | tr -d '`' | tr '\n' ' ' | sed 's/[[:space:]]*\.[[:space:]]*/./g' | grep -oE 'app\.escalibur\.wallet\.ui\.[a-z][A-Za-z0-9_]*\.' | grep -vxE 'app\.escalibur\.wallet\.ui\.(comp|tema)\.')" ] \
    && [ -z "$a11y_telas" ] \
    && [ "$a11y_declarados" = 8 ] \
    && ok "a carteira fecha e trava com qualquer servico de acessibilidade de fora, em qualquer Android, ferramenta ou nao" \
    || aviso "carteira aberta com servico de acessibilidade de fora (Acessibilidade.kt, o portao do Raiz ou os imports dele, o travar, a entrada da MainActivity ou o que fica em volta mudou: confira o portao e grave o digesto novo)"
# A frase e a passphrase nunca vao para o teclado padrao de outro app: nem pelo Safe Keyboard desligado, nem pelo globo, nem
# trocando o padrao no meio (auditoria 8, 14/11/2026).
codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -qF 'val deTerceiros = deSegredo && tecladoDeTerceiros(vista.context)' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -qF 'if (nova.deSegredo && tecladoDeTerceiros(vista.context)) {' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt" | grep -qF 'Settings.Secure.getUriFor(Settings.Secure.DEFAULT_INPUT_METHOD)' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/importar/Importar.kt" | grep -qF 'val tecladoDeOutroApp = app.escalibur.wallet.ui.comp.TecladoSeguro.tecladoDeTerceiros(contexto)' \
    && ok "a frase e a passphrase nunca vao para o teclado de outro app no Android" \
    || aviso "campo de segredo no Android sem a recusa do teclado de outro app"
# Rodada 1 da auditoria 8: so os teclados de sistema da lista contam como do aparelho; o teclado do celular escreve no
# campo de segredo mas nao le o que ja esta nele; e a conta de campos de segredo abertos e um contador.
teclado="$AND/java/app/escalibur/wallet/ui/comp/TecladoSeguro.kt"
grep -qF 'private val tecladosDoAparelho = setOf("com.google.android.inputmethod.latin", "com.android.inputmethod.latin", "com.samsung.android.honeyboard")' "$teclado" \
    && codigo_vivo "$teclado" | grep -qF 'if (pacote !in tecladosDoAparelho) return true' \
    && codigo_vivo "$teclado" | grep -qF 'if (campoSecreto(atributos) || sistema?.palavras == true) {' \
    && codigo_vivo "$teclado" | grep -qF 'SemLeitura(conexao)' \
    && grep -vE '^[[:space:]]*//' "$teclado" | grep -qF 'androidx.core.view.inputmethod.EditorInfoCompat.setInitialSurroundingText(atributos, "")' \
    && [ "$(codigo "$teclado" | awk '/private class SemLeitura/ { dentro = 1; next } dentro && /^    }[[:space:]]*$/ { dentro = 0 } dentro && /override fun (getTextBeforeCursor|getTextAfterCursor|getSelectedText|getExtractedText|getSurroundingText|setComposingRegion|requestCursorUpdates|performContextMenuAction|takeSnapshot|getCursorCapsMode)\(/ && /= ""[[:space:]]*$|= null[[:space:]]*$|= false[[:space:]]*$|= 0[[:space:]]*$/ { n++ } END { print n + 0 }')" = 11 ] \
    && [ "$(codigo "$teclado" | awk '/private class SemLeitura/ { dentro = 1; next } dentro && /^    }[[:space:]]*$/ { dentro = 0 } dentro && /override fun/ { n++ } END { print n + 0 }')" = 11 ] \
    && [ "$(codigo "$teclado" | awk '/private class SemLeitura/ { dentro = 1; next } dentro && /^    }[[:space:]]*$/ { dentro = 0 } dentro && /override fun/ { sub(/^.*override fun /, ""); sub(/\(.*/, ""); print }' | sort | tr '\n' ' ')" = "getCursorCapsMode getExtractedText getSelectedText getSurroundingText getTextAfterCursor getTextBeforeCursor performContextMenuAction requestCursorUpdates requestCursorUpdates setComposingRegion takeSnapshot " ] \
    && [ "$(codigo_vivo "$teclado" | grep -cF 'segredosNoCelular++')" = 2 ] \
    && ! grep -qE 'segredoNoCelular[^s]' "$teclado" \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/novacarteira/NovaCarteira.kt" | grep -qF 'app.escalibur.wallet.ui.comp.TecladoSeguro.tecladoDeTerceiros(' \
    && ok "teclado do celular so de sistema e da lista, sem ler o campo de segredo, e o contador de campos abertos" \
    || aviso "teclado do Android sem a lista de teclados de sistema, sem a conexao que nao le ou sem o contador"
# Android 11: o toque com janela de outro app por cima e recusado na Activity, nos dialogos e no popup (auditoria 8 e rodada 1).
codigo_vivo "$AND/java/app/escalibur/wallet/MainActivity.kt" | grep -qF 'if (!app.escalibur.wallet.ui.comp.ToqueCoberto.recusa(evento)) return super.dispatchTouchEvent(evento)' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/MainActivity.kt" | grep -qF 'app.escalibur.wallet.ui.comp.ToqueCoberto.cancelar(evento) { super.dispatchTouchEvent(it) }' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/Janela.kt" | grep -qF 'janela.callback = ToqueCoberto.Filtro(original)' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/Janela.kt" | grep -qF 'if (!recusa(evento)) return original.dispatchTouchEvent(evento)' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/Janela.kt" | grep -qF 'if (ToqueCoberto.recusa(nativo)) evento.changes.forEach { it.consume() }' \
    && codigo_vivo "$AND/java/app/escalibur/wallet/ui/comp/Menu.kt" | grep -qF 'Modifier.recusaToqueCoberto()' \
    && ok "no Android 11, toque com janela de outro app por cima recusado na Activity, nos dialogos e no popup" \
    || aviso "toque coberto por outro app aceito em alguma janela do Android 11"
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
    # O objeto do SecureBytes chama o _SecRandomCopyBytes do sistema, e nao um com o mesmo nome do proprio Swift (regra do
    # sorteio, rodada dos 3 agentes de 19/11/2026). O binario da loja e conferido pelo nm no arquivar.sh.
    sorteio_o=$(nm -u Kit/.build/debug/EscaliburCore.build/SecureBytes.swift.o 2>/dev/null)
    grep -qx '_SecRandomCopyBytes' <<<"$sorteio_o" && grep -qx '_kSecRandomDefault' <<<"$sorteio_o" \
        && ok "o SecureBytes compilado chama o SecRandomCopyBytes do sistema" || aviso "o SecureBytes compilado nao chama o SecRandomCopyBytes do sistema"
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
