# Lido (source) pelos scripts da loja, tools/arquivar.sh e tools/android/gerar-aab.sh, na primeira fase: poe o
# shell numa copia limpa do commit publicado na main do GitHub e define `raiz`, `limpa`, `commit` e `arvore`. A
# segunda fase de cada script roda da copia de dentro dela, a publicada, e nunca da pasta de trabalho.
#
# O app da loja sai so do codigo publicado, e de nada mais (terceira e quarta passadas da auditoria de 03/11/2026):
# - a main e a do repositorio da Escalibur no GitHub, pela ref remota sem ambiguidade (uma tag local chamada
#   origin/main venceria o nome) e conferida com o que o GitHub responde agora;
# - a arvore daqui tem de ser a da main publicada. A juncao diaria muda o commit, nao a arvore, e o commit
#   gravado no app e o publicado, que existe no GitHub;
# - os scripts da loja daqui sao os do commit publicado: uma edicao local deles nao roda;
# - o build roda num worktree novo e destacado desse commit, fora desta pasta e sem os hooks do git. O que o git
#   ignora ou nao mostra (uma pasta build dentro das fontes, skip-worktree, status sem os arquivos novos) e o
#   que outra sessao editar nesta pasta durante o build ficam de fora;
# - o commit e a arvore vao dentro do app.
raiz=$(git rev-parse --show-toplevel)
[ "$(git -C "$raiz" remote get-url origin)" = "https://github.com/Escalibur-Wallet/escalibur-wallet.git" ] \
    || { echo "o remoto origin nao e o repositorio da Escalibur no GitHub" >&2; exit 1; }
git -C "$raiz" fetch -q origin +refs/heads/main:refs/remotes/origin/main \
    || { echo "sem a main do GitHub (git fetch origin main): o app da loja so sai do codigo publicado" >&2; exit 1; }
commit=$(git -C "$raiz" rev-parse --verify --end-of-options 'refs/remotes/origin/main^{commit}')
[ "$commit" = "$(git -C "$raiz" ls-remote origin refs/heads/main | cut -f1)" ] \
    || { echo "a main lida nao e a que o GitHub responde agora" >&2; exit 1; }
arvore=$(git -C "$raiz" rev-parse --verify --end-of-options "$commit^{tree}")
[ "$(git -C "$raiz" rev-parse 'HEAD^{tree}')" = "$arvore" ] \
    || { echo "o codigo daqui (HEAD) nao e o publicado na main do GitHub: publique antes (um push por dia)" >&2; exit 1; }
# Pelo conteudo, e nao pelo `git diff`: um `assume-unchanged` ou `skip-worktree` esconderia a edicao (quinta
# passada da auditoria de 03/11/2026).
[ -z "$(git -C "$raiz" ls-files -v -- tools/copia-publicada.sh tools/arquivar.sh tools/android/gerar-aab.sh loja.lock | grep -v '^H ')" ] \
    || { echo "um script da loja daqui esta marcado para o git nao olhar" >&2; exit 1; }
for script in tools/copia-publicada.sh tools/arquivar.sh tools/android/gerar-aab.sh loja.lock; do
    [ "$(git -C "$raiz" hash-object --no-filters -- "$raiz/$script")" = "$(git -C "$raiz" rev-parse --verify "$commit:$script")" ] \
        || { echo "os scripts da loja daqui nao sao os do commit publicado ($script)" >&2; exit 1; }
done
# O CI deste commit passou (o verificar.yml: o verificador inteiro, os testes e o app em Release): o loja.lock e as
# regras so valiam onde o verificador roda, e o build daqui nao sabia se ele tinha passado (decima primeira passada).
# A ultima rodada do proprio verificar.yml, de push na main e deste commit, terminada e verde, com o job `verificar`
# verde: pelo nome do check, um job chamado `verificar` em outro workflow, ou uma rodada de pull request no mesmo commit,
# contava (decima segunda passada).
api=https://api.github.com/repos/Escalibur-Wallet/escalibur-wallet/actions
rodada=$(curl -fsS --proto '=https' --max-time 30 "$api/workflows/verificar.yml/runs?head_sha=$commit&event=push&branch=main&per_page=30" \
    | python3 -I -c 'import json, sys; c = sys.argv[1]; r = [x for x in json.load(sys.stdin)["workflow_runs"] if x.get("head_sha") == c and x.get("path") == ".github/workflows/verificar.yml" and x.get("event") == "push" and x.get("head_branch") == "main"]; r.sort(key=lambda x: (x.get("run_started_at") or "", x.get("run_attempt") or 0)); ok = bool(r) and r[-1].get("status") == "completed" and r[-1].get("conclusion") == "success"; print(r[-1]["id"] if ok else ""); sys.exit(0 if ok else 1)' "$commit") \
    && [ -n "$rodada" ] \
    && curl -fsS --proto '=https' --max-time 30 "$api/runs/$rodada/jobs" \
        | python3 -I -c 'import json, sys; j = [x for x in json.load(sys.stdin)["jobs"] if x.get("name") == "verificar"]; sys.exit(0 if len(j) == 1 and j[0].get("conclusion") == "success" else 1)' \
    || { echo "o CI (verificar.yml) do commit $commit nao passou, ou ainda roda: espere o verde no GitHub" >&2; exit 1; }
limpa=$(mktemp -d /private/tmp/escalibur-loja.XXXXXX)
git -C "$raiz" -c core.hooksPath=/dev/null worktree add -q --detach "$limpa" "$commit"
trap 'git -C "$raiz" worktree remove --force "$limpa"' EXIT
cd "$limpa"
[ "$(git rev-parse HEAD)" = "$commit" ] && [ "$(git rev-parse 'HEAD^{tree}')" = "$arvore" ] \
    && [ -z "$(git status --porcelain=v1 --untracked-files=all --ignored)" ] && [ -z "$(git ls-files -v | grep -v '^H ')" ] \
    || { echo "a copia limpa em $limpa nao confere com o commit $commit" >&2; exit 1; }
# Os arquivos travados no loja.lock conferem na copia limpa, e nao so onde o verificar.sh roda (decima primeira passada).
python3 -I -c 'import hashlib, json, sys; lock = json.load(open("loja.lock", encoding="utf-8"), object_pairs_hook=lambda p: dict(p) if len(p) == len({k for k, _ in p}) else sys.exit(1))["arquivos"]; sys.exit(0 if len(lock) == 29 and all(hashlib.sha256(open(c, "rb").read()).hexdigest() == d for c, d in lock.items()) else 1)' \
    || { echo "um arquivo travado no loja.lock nao confere na copia limpa do commit $commit" >&2; exit 1; }
# Cada arquivo da copia limpa e o blob do commit, byte a byte e sem filtro, e nenhum a mais: o worktree divide a
# configuracao e os atributos do repositorio de trabalho, e um filtro dali mudaria o que o build compila sem que o status
# visse (revisao da decima terceira passada).
python3 -I - "$commit" <<'PY' || { echo "a copia limpa nao e, byte a byte, o commit $commit" >&2; exit 1; }
import os, subprocess, sys
commit = sys.argv[1]
esperado = {}
for item in filter(None, subprocess.run(["git", "ls-tree", "-r", "-z", "--full-tree", commit], capture_output=True, check=True).stdout.split(b"\0")):
    cabeca, caminho = item.split(b"\t", 1)
    modo, tipo, objeto = cabeca.split(b" ")
    if tipo != b"blob" or modo not in (b"100644", b"100755") or b"\n" in caminho:
        sys.exit(1)
    esperado[caminho.decode()] = objeto.decode()
caminhos = sorted(esperado)
lido = subprocess.run(["git", "hash-object", "--no-filters", "--stdin-paths"], input=("\n".join(caminhos) + "\n").encode(),
                      capture_output=True, check=True).stdout.decode().split()
presentes = set()
for pasta, subpastas, arquivos in os.walk("."):
    if pasta == ".":
        subpastas[:] = [d for d in subpastas if d != ".git"]
        arquivos = [a for a in arquivos if a != ".git"]
    presentes.update(os.path.relpath(os.path.join(pasta, a), ".") for a in arquivos)
sys.exit(0 if lido == [esperado[c] for c in caminhos] and presentes == set(caminhos) else 1)
PY

