#!/usr/bin/env python3
"""Confere os entitlements de um app assinado contra os .entitlements do repositorio.

Uso: python3 -I tools/conferir-entitlements.py Payload/EscaliburWallet.app
     python3 -I tools/conferir-entitlements.py --ad-hoc EscaliburWallet.xcarchive/Products/Applications/EscaliburWallet.app

O release.yml roda isto no app de dentro do .ipa exportado, antes dos digestos e do
envio (docs/seguranca.md, secao 8.3, regra 18). Com --ad-hoc, no app do archive que o job
do build entregou, antes do export que usa a chave da App Store Connect: a assinatura
local tem de levar exatamente os entitlements do repositorio, sem nenhuma chave a mais
(rodada 1 da auditoria 8, 14/11/2026). Nos dois modos, o bundle id do app e do widget e
os unicos executaveis do app (o binario principal e o do widget). Para o app e o widget:
- cada chave do .entitlements do repositorio esta na assinatura, com o mesmo valor;
- fora delas, so as que a Apple poe na assinatura de distribuicao, com o valor certo
  (identificador do app, equipe, beta-reports-active, get-task-allow falso e o grupo de
  chaveiro do proprio app);
- qualquer outra chave (aps-environment, icloud-*, ubiquity-*, grupo de outro app,
  get-task-allow verdadeiro) para o release.
Quem audita roda o mesmo num app exportado ou decifrado. So biblioteca padrao.
"""
import pathlib
import plistlib
import stat
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
EQUIPE = "2UNWMDD93S"
# (caminho dentro do .app, .entitlements do repositorio, bundle id)
ALVOS = [
    ("", "App/EscaliburWallet/Resources/EscaliburWallet.entitlements", "app.escalibur.wallet"),
    ("PlugIns/EscaliburWidgets.appex", "App/EscaliburWidgets/EscaliburWidgets.entitlements", "app.escalibur.wallet.widgets"),
]


def da_apple(bundle):
    """As chaves que a assinatura de distribuicao acrescenta, e o unico valor aceito."""
    return {
        "application-identifier": f"{EQUIPE}.{bundle}",
        "com.apple.developer.team-identifier": EQUIPE,
        "beta-reports-active": True,
        "get-task-allow": False,
        "keychain-access-groups": [f"{EQUIPE}.{bundle}"],
    }


def assinados(caminho):
    # Pelo caminho inteiro: um `codesign` na frente do PATH responderia o que quisesse (rodada 2 da auditoria 8).
    saida = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(caminho)],
                           capture_output=True, check=False)
    if saida.returncode != 0:
        sys.exit(f"{caminho}: codesign nao leu a assinatura ({saida.stderr.decode(errors='replace').strip()})")
    return plistlib.loads(saida.stdout) if saida.stdout.strip() else {}


# Os unicos arquivos Mach-O do app: um plugin, framework ou biblioteca a mais seria assinado pelo export junto.
EXECUTAVEIS = {"EscaliburWallet", "PlugIns/EscaliburWidgets.appex/EscaliburWidgets"}
# O universal de 64 bits (cafebabf) tambem (rodada 3 da auditoria 8).
MACH_O = {b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
          b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


def estrutura(app):
    falhas = []
    if app.is_symlink() or not app.is_dir():
        return [f"{app}: nao e uma pasta de app"]
    for caminho in sorted(app.rglob("*")):
        relativo = caminho.relative_to(app).as_posix()
        modo = caminho.lstat().st_mode
        if not (stat.S_ISREG(modo) or stat.S_ISDIR(modo)):
            falhas.append(f"{relativo}: link simbolico ou arquivo especial")
        # Pelo caminho tambem, e nao so pelo cabecalho: nenhum plugin alem do widget, nenhum framework nem biblioteca (rodada 3).
        partes = relativo.split("/")
        if (partes[0] == "PlugIns" and len(partes) >= 2 and partes[1] != "EscaliburWidgets.appex") or partes[0] == "Frameworks" \
                or relativo.endswith((".dylib", ".framework")) or ("/" in relativo and relativo.endswith((".appex", ".app"))
                                                                  and relativo != "PlugIns/EscaliburWidgets.appex"):
            falhas.append(f"{relativo}: plugin, framework ou biblioteca que nao e do app")
        elif stat.S_ISREG(modo):
            with open(caminho, "rb") as arquivo:
                if arquivo.read(4) in MACH_O and relativo not in EXECUTAVEIS:
                    falhas.append(f"{relativo}: executavel que nao e o do app nem o do widget")
    for executavel in EXECUTAVEIS:
        if not (app / executavel).is_file():
            falhas.append(f"falta {executavel}")
    return falhas


def conferir(app, ad_hoc=False):
    falhas = estrutura(app)
    for dentro, arquivo, bundle in ALVOS:
        alvo = app / dentro if dentro else app
        esperados = plistlib.loads((RAIZ / arquivo).read_bytes())
        apple = {} if ad_hoc else da_apple(bundle)
        nome = dentro or app.name
        try:
            identificador = plistlib.loads((alvo / "Info.plist").read_bytes()).get("CFBundleIdentifier")
        except (OSError, plistlib.InvalidFileException) as erro:
            identificador = f"ilegivel ({erro})"
        if identificador != bundle:
            falhas.append(f"{nome}: CFBundleIdentifier {identificador!r}, o esperado e {bundle!r}")
        atuais = assinados(alvo)
        for chave, valor in esperados.items():
            if chave not in atuais:
                falhas.append(f"{nome}: falta {chave} (esta em {arquivo})")
            elif atuais[chave] != valor:
                falhas.append(f"{nome}: {chave} = {atuais[chave]!r}, o repositorio diz {valor!r}")
        for chave, valor in atuais.items():
            if chave in esperados:
                continue
            if chave not in apple:
                falhas.append(f"{nome}: {chave} = {valor!r} nao esta em {arquivo} nem e da assinatura da Apple")
            elif valor != apple[chave]:
                falhas.append(f"{nome}: {chave} = {valor!r}, o aceito e {apple[chave]!r}")
        for chave in () if ad_hoc else ("application-identifier", "com.apple.developer.team-identifier"):
            if chave not in atuais:
                falhas.append(f"{nome}: falta {chave}: nao e uma assinatura de distribuicao")
        print(f"{nome}: " + ", ".join(sorted(atuais)), flush=True)
    return falhas


if __name__ == "__main__":
    argumentos = sys.argv[1:]
    ad_hoc = argumentos[:1] == ["--ad-hoc"]
    if ad_hoc:
        argumentos = argumentos[1:]
    if len(argumentos) != 1:
        sys.exit("uso: conferir-entitlements.py [--ad-hoc] <EscaliburWallet.app>")
    falhas = conferir(pathlib.Path(argumentos[0]), ad_hoc)
    if falhas:
        print("\n".join(falhas), file=sys.stderr)
        sys.exit(f"{len(falhas)} divergencia(s) nos entitlements")
    print("entitlements do app e do widget conferem com o repositorio")
