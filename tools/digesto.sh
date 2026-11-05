#!/bin/bash -p
# O digesto da arvore de uma pasta (o .xcarchive inteiro, e nao so o .app, porque o export le o Info.plist e o resto
# do archive): cada entrada (arquivo, pasta e link simbolico) com o modo inteiro (tipo, setuid e setgid inclusive),
# os atributos estendidos, o caminho e o conteudo (o SHA-256 do arquivo, ou o destino do link). O tools/arquivar.sh imprime este digesto no fim do archive, e antes de assinar
# confira de novo com este mesmo script: um arquivo trocado, um link novo ou um modo mudado entre o archive e a
# assinatura mudam o digesto (sexta e setima passadas da auditoria de 03/11/2026).
#
#   tools/digesto.sh <pasta>
set -euo pipefail
# So no bash privilegiado (um `bash -s` pelo PATH leria BASH_ENV e funcoes do ambiente, e o shasum, que e Perl, as
# variaveis do Perl), com o PATH do sistema (revisao da decima terceira passada).
case "$-" in *p*) ;; *) _sem_p=; : "${_sem_p:?rode com /usr/bin/env -i /bin/bash -p}" ;; esac
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
unset CDPATH PERL5LIB PERL5OPT PERLLIB PERL5DB

main() {
    local pasta="${1:?uso: tools/digesto.sh <pasta>}"
    [ -d "$pasta" ] && [ ! -L "$pasta" ] || { echo "$pasta nao e uma pasta" >&2; exit 1; }
    cd "$pasta"
    find . -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' entrada; do
        local modo atributos
        modo=$(stat -f %p "$entrada")
        atributos=$(xattr -slx "$entrada" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
        if [ -L "$entrada" ]; then
            printf 'link %s %s %s %s\n' "$modo" "$atributos" "$entrada" "$(readlink "$entrada")"
        elif [ -d "$entrada" ]; then
            printf 'pasta %s %s %s\n' "$modo" "$atributos" "$entrada"
        elif [ -f "$entrada" ]; then
            printf 'arquivo %s %s %s %s\n' "$modo" "$atributos" "$entrada" "$(shasum -a 256 < "$entrada" | cut -d' ' -f1)"
        else
            printf 'outro %s\n' "$entrada"
        fi
    done | shasum -a 256 | cut -d' ' -f1
}

main "$@"; exit
