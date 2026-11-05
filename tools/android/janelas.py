#!/usr/bin/env python3
"""Toda janela propria do Compose no app Android chama ProtegerJanela() logo no comeco do conteudo.

Um dialogo, um popup ou um menu do Compose e outra janela, e a raiz dela nao herda a protecao da
Activity (o filtro de toque contra sobreposicao, o "sensivel" da acessibilidade). Confere janela por
janela, e nao por arquivo (segunda passada da auditoria de 03/11/2026):
- as chamadas com ou sem o pacote na frente (`androidx.compose.ui.window.Popup(`), com parenteses ou so
  com o conteudo (`Popup { }`), e com o nome entre crases;
- o primeiro comando do conteudo e ProtegerJanela(), fora de comentario;
- sem conteudo no fim (o AlertDialog com campos), ProtegerJanela() dentro dos parenteses;
- as janelas no estilo antigo do Android (PopupWindow, PopupMenu, DialogFragment, addView no
  WindowManager) nem entram, nem um nome de janela trocado por `import ... as` ou passado como `::Dialog`.

O Kotlin e lido como o compilador le (terceira passada da auditoria de 03/11/2026): comentario de linha
e de bloco (que no Kotlin se aninha), texto entre aspas e entre aspas triplas, o codigo dentro de `${}`
(que continua sendo conferido) e o caractere entre aspas simples (antes, um `'"'` invertia o resto do
arquivo e escondia a janela que vinha depois).

    python3 tools/android/janelas.py            falha (saida 1) e lista o que estiver sem a protecao
    python3 tools/android/janelas.py --testes   confere a propria regra com os casos de ataque conhecidos
"""
import pathlib, re, sys, tempfile

RAIZ = pathlib.Path(__file__).resolve().parents[2]
KOTLIN = RAIZ / "Android/app/src/main/java"

JANELAS = ("Dialog", "Popup", "DropdownMenu", "CursorDropdownMenu", "ExposedDropdownMenu", "ExposedDropdownMenuBox", "ModalBottomSheet",
           "AlertDialog", "BasicAlertDialog", "DatePickerDialog", "TimePickerDialog", "TooltipBox", "BasicTooltipBox", "PlainTooltipBox", "RichTooltipBox")
NOMES = "|".join(JANELAS)
CHAMADA = re.compile(r"(?<![A-Za-z0-9_.:])((?:[a-z][A-Za-z0-9_]*\s*\.\s*)*)(" + NOMES + r")(?![A-Za-z0-9_])\s*(?:<[^<>()]*>\s*)?([({])")
PROIBIDAS = re.compile(r"(?<![A-Za-z0-9_])(PopupWindow\s*\(|PopupMenu\s*\(|DialogFragment\b|WindowManager\b[^\n]*\.addView\s*\()")
# O nome de uma janela trocado por outro (o import com `as`) ou passado como valor (a referencia `::`).
DISFARCES = re.compile(r"(?m)^\s*import\s+[\w.]*\b(?:" + NOMES + r")\s+as\b|::\s*(?:" + NOMES + r")(?![A-Za-z0-9_])")
PROTEGER = re.compile(r"(?:app\s*\.\s*escalibur\s*\.\s*wallet\s*\.\s*ui\s*\.\s*comp\s*\.\s*)?ProtegerJanela\s*\(\s*\)")


def sem_comentarios(texto):
    """O codigo como o compilador ve: comentario, texto entre aspas e caractere viram espacos (as quebras
    de linha ficam, para o numero da linha), o codigo dentro de `${}` fica, e as crases dos nomes saem."""
    saida, n, i = list(texto), len(texto), 0
    # A pilha do que esta aberto: ("codigo", chaves abertas no `${}`) ou ("texto", triplo?).
    pilha = [("codigo", 0)]

    def apagar(a, b):
        saida[a:b] = [c if c == "\n" else " " for c in texto[a:b]]

    while i < n:
        modo, info = pilha[-1]
        if modo == "codigo":
            if texto.startswith("//", i):
                fim = texto.find("\n", i)
                fim = n if fim < 0 else fim
                apagar(i, fim)
                i = fim
            elif texto.startswith("/*", i):
                nivel, j = 1, i + 2
                while j < n and nivel:
                    if texto.startswith("/*", j):
                        nivel, j = nivel + 1, j + 2
                    elif texto.startswith("*/", j):
                        nivel, j = nivel - 1, j + 2
                    else:
                        j += 1
                apagar(i, j)
                i = j
            elif texto[i] == "'":
                j = i + 1
                if j < n and texto[j] == "\\":
                    j += 6 if texto.startswith("u", j + 1) else 2
                else:
                    j += 1
                fim = texto.find("'", j) if j < n and texto[j] != "'" else j
                fim = n - 1 if fim < 0 else fim
                apagar(i + 1, fim)
                i = fim + 1
            elif texto.startswith('"""', i):
                pilha.append(("texto", True))
                i += 3
            elif texto[i] == '"':
                pilha.append(("texto", False))
                i += 1
            elif texto[i] == "`":
                # O nome entre crases: so um identificador simples fica (para `Dialog` ainda ser achado); com
                # aspas ou qualquer outro caractere, o nome inteiro sai, e as aspas dele nao abrem texto
                # (quarta passada da auditoria de 03/11/2026). Nome entre crases nao atravessa linha.
                fim = texto.find("`", i + 1)
                quebra = texto.find("\n", i + 1)
                if fim < 0 or (0 <= quebra < fim):
                    fim = n if quebra < 0 else quebra
                    apagar(i, fim)
                    i = fim
                    continue
                if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", texto[i + 1:fim]):
                    saida[i] = saida[fim] = " "
                else:
                    apagar(i, fim + 1)
                i = fim + 1
            elif texto[i] == "{" and len(pilha) > 1:
                pilha[-1] = ("codigo", info + 1)
                i += 1
            elif texto[i] == "}" and len(pilha) > 1:
                if info == 0:
                    saida[i] = " "
                    pilha.pop()
                else:
                    pilha[-1] = ("codigo", info - 1)
                i += 1
            else:
                i += 1
        else:
            triplo = info
            if triplo and texto.startswith('"""', i):
                # O fim e o ultimo de uma fila de aspas: as da frente fazem parte do texto.
                j = i
                while j < n and texto[j] == '"':
                    j += 1
                apagar(i, j - 3)
                pilha.pop()
                i = j
            elif not triplo and texto[i] == '"':
                pilha.pop()
                i += 1
            elif not triplo and texto[i] == "\\":
                apagar(i, min(i + 2, n))
                i += 2
            elif not triplo and texto[i] == "\n":
                pilha.pop()
                i += 1
            elif texto.startswith("${", i):
                apagar(i, i + 2)
                pilha.append(("codigo", 0))
                i += 2
            else:
                if texto[i] != "\n":
                    saida[i] = " "
                i += 1
    return "".join(saida)


def fecha(texto, abre, a="(", f=")"):
    """A posicao do fechamento do `a` em `abre`."""
    nivel = 0
    for j in range(abre, len(texto)):
        if texto[j] == a:
            nivel += 1
        elif texto[j] == f:
            nivel -= 1
            if nivel == 0:
                return j
    return -1


def comeca_protegido(conteudo):
    """O conteudo (depois do `{`) comeca com ProtegerJanela(), aceitando o parametro do lambda (`x ->`)."""
    dentro = conteudo.lstrip()
    dentro = re.sub(r"^[A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*\s*->\s*", "", dentro)
    return PROTEGER.match(dentro) is not None


def problemas(caminho, nome=None):
    original = caminho.read_text(encoding="utf-8")
    texto = sem_comentarios(original)
    linha = lambda pos: texto.count("\n", 0, pos) + 1
    rel = nome or (caminho.relative_to(RAIZ) if RAIZ in caminho.parents else caminho)
    achados = [f"{rel}:{linha(m.start())}: janela no estilo antigo ({m.group(1).strip()})" for m in PROIBIDAS.finditer(texto)]
    achados += [f"{rel}:{linha(m.start())}: nome de janela disfarcado ({m.group(0).strip()})" for m in DISFARCES.finditer(texto)]
    for m in CHAMADA.finditer(texto):
        if re.search(r"\bfun\s+$", texto[max(0, m.start() - 12):m.start()]):
            continue
        abre = m.end() - 1
        if m.group(3) == "{":
            if not comeca_protegido(texto[abre + 1:]):
                achados.append(f"{rel}:{linha(m.start())}: {m.group(2)} sem ProtegerJanela() no comeco do conteudo")
            continue
        fim = fecha(texto, abre)
        if fim < 0:
            achados.append(f"{rel}:{linha(m.start())}: {m.group(2)} sem fechar")
            continue
        corpo = texto[fim + 1:].lstrip()
        if corpo.startswith("{"):
            if not comeca_protegido(corpo[1:]):
                achados.append(f"{rel}:{linha(m.start())}: {m.group(2)} sem ProtegerJanela() no comeco do conteudo")
        elif not PROTEGER.search(texto[abre:fim]):
            achados.append(f"{rel}:{linha(m.start())}: {m.group(2)} sem ProtegerJanela()")
    return achados


# Os casos de ataque das auditorias (cybersecurity e militar, 03/11/2026) e os jeitos certos: quantos
# achados cada um tem de dar.
CASOS = {
    "protegido": ("Dialog(onDismissRequest = {}) { ProtegerJanela(); Texto() }", 0),
    "protegido com parametro": ("DropdownMenu(expanded = true, onDismissRequest = {}) { escopo -> ProtegerJanela() }", 0),
    "protegido com pacote": ("app.escalibur.wallet.ui.comp.ProtegerJanela\nandroidx.compose.ui.window.Popup(onDismissRequest = {}) {\n app.escalibur.wallet.ui.comp.ProtegerJanela()\n}", 0),
    "alerta com campos": ("AlertDialog(onDismissRequest = {}, confirmButton = {}, text = { ProtegerJanela(); Texto() })", 0),
    "definicao": ("@Composable fun Dialog(x: Int) {}", 0),
    "sem protecao": ("Dialog(onDismissRequest = {}) { MinhasCarteiras() }", 1),
    "protecao depois": ("Dialog(onDismissRequest = {}) { MinhasCarteiras(); ProtegerJanela() }", 1),
    "protecao comentada": ("Dialog(onDismissRequest = {}) { // ProtegerJanela()\n MinhasCarteiras() }", 1),
    "protecao em bloco": ("Dialog(onDismissRequest = {}) { /* ProtegerJanela() */ MinhasCarteiras() }", 1),
    "sem parenteses": ("Popup { MinhasCarteiras() }", 1),
    "com pacote sem parenteses": ("androidx.compose.ui.window.Popup { MinhasCarteiras() }", 1),
    "depois de aspas em caractere": ("val aspas = '\"'\nDialog(onDismissRequest = {}) { MinhasCarteiras() }", 1),
    "depois de escape em caractere": ("val c = '\\''\nval d = '\\u0022'\nDialog(onDismissRequest = {}) { MinhasCarteiras() }", 1),
    "dentro de template": ('val t = "${ run { Dialog(onDismissRequest = {}) { MinhasCarteiras() }; 1 } }"', 1),
    "depois de texto triplo": ('val t = """a "" ${1} b""""\nDialog(onDismissRequest = {}) { MinhasCarteiras() }', 1),
    "comentario aninhado": ("/* a /* b */ Dialog(onDismissRequest = {}) { MinhasCarteiras() } */\nPopup { MinhasCarteiras() }", 1),
    "nome entre crases": ("`Dialog`(onDismissRequest = {}) { MinhasCarteiras() }", 1),
    "aspas num nome entre crases": ('val `q"x` = 0; Dialog(onDismissRequest = {}) { MinhasCarteiras() }', 1),
    "aspas triplas num nome entre crases": ('val `x"""y` = 0\nDialog(onDismissRequest = {}) { MinhasCarteiras() }\nPopup { MinhasCarteiras() }', 2),
    "menu de cursor": ("CursorDropdownMenu(expanded = true, position = p, onDismissRequest = {}) { MinhasCarteiras() }", 1),
    "import com outro nome": ("import androidx.compose.ui.window.Dialog as Janela\nJanela(onDismissRequest = {}) { MinhasCarteiras() }", 1),
    "referencia": ("val janela = ::Dialog", 1),
    "estilo antigo": ("val p = PopupWindow(contexto)", 1),
}


def testes():
    erros = []
    with tempfile.TemporaryDirectory() as pasta:
        for nome, (fonte, esperado) in CASOS.items():
            arquivo = pathlib.Path(pasta) / "Caso.kt"
            arquivo.write_text(fonte, encoding="utf-8")
            achados = problemas(arquivo, nome=nome)
            if len(achados) != esperado:
                erros.append(f"{nome}: esperado {esperado}, achou {len(achados)} {achados}")
    for erro in erros:
        print(erro)
    return 1 if erros else 0


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--testes":
        return testes()
    raiz = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else KOTLIN
    todos = [p for arquivo in sorted(raiz.rglob("*.kt")) for p in problemas(arquivo)]
    for p in todos:
        print(p)
    return 1 if todos else 0


if __name__ == "__main__":
    sys.exit(main())
