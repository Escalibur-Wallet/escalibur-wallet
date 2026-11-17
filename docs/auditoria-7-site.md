# Auditoria 7, site (10/11/2026)

Auditoria de segurança do site da Escalibur Wallet pedida pelo dono, sobre a árvore de trabalho de 10/11/2026 (a main `176a660c` de 07/11 mais as mudanças da revisão em curso, ainda sem commit) e sobre o que está no ar: `escaliburwallet.com` (o Worker da Cloudflare, `tools/site-cloudflare`) e a cópia em `escalibur-wallet.github.io` (GitHub Pages, de onde o app lê a lista de versões). Só leitura e consultas de fora (cabeçalhos HTTP, DNS, TLS, as APIs públicas do GitHub e do hstspreload.org): nada foi mudado nem publicado. O que foi lido: o Worker (`worker.js`, `wrangler.jsonc`), o gerador (`tools/gerar-site.py`, `tools/gerador_site/*.py`), as páginas e os scripts de `site/`, o script de publicação (`tools/publicar-site.sh`), os três workflows de `.github/workflows`, o `SECURITY.md` e as configurações do repositório público.

Nenhum crítico, nenhum alto. Um médio e cinco baixos, todos de configuração do domínio e do e-mail, fora do código: o código do site e o caminho de publicação não deram achado.

## Médios

| Item | Achado | Estado |
|---|---|---|
| S7-01 | **O e-mail do domínio pode ser falsificado.** `escaliburwallet.com` não tem registro DMARC (`_dmarc` vazio), o SPF termina em `~all` (falha branda) e nenhum seletor DKIM comum responde. Qualquer servidor manda um e-mail "de" `support@escaliburwallet.com` ou `security@escaliburwallet.com`, e quem recebe não tem instrução para recusar: cai na caixa de entrada ou no spam, à sorte. Para uma carteira é o golpe clássico, "o suporte da Escalibur pede as suas palavras". O app e o site já dizem que ninguém da Escalibur precisa das palavras, mas o domínio ainda assina o golpe. O MX é o Email Routing da Cloudflare, que só recebe. | Aberto: passo do dono na Cloudflare. Publicar `_dmarc` com `v=DMARC1; p=reject; adkim=s; aspf=s; rua=mailto:…` (a Cloudflare tem o DMARC Management em Email) e trocar o SPF para `-all`. Antes, confirmar como as respostas do suporte saem: se saem de um Gmail com "enviar como" `support@`, esse caminho precisa de DKIM (Google Workspace) ou passa a ser recusado. |

## Baixos

| Item | Achado | Estado |
|---|---|---|
| S7-02 | **TLS 1.0 e 1.1 aceitos na borda.** `curl --tls-max 1.0` e `openssl s_client -tls1` fecham a conexão com `escaliburwallet.com` (cifra `ECDHE-RSA-AES128-SHA`). É o padrão da Cloudflare, mínimo 1.0. Nenhum navegador atual negocia abaixo de 1.2, então o risco prático é pequeno; mas um site que vende segurança não deve oferecer protocolos aposentados (RFC 8996). | Aberto: Cloudflare, SSL/TLS, Edge Certificates, Minimum TLS Version em 1.2. |
| S7-03 | **Sem registro CAA.** Qualquer autoridade certificadora pode emitir para o domínio. O certificado de hoje é da Google Trust Services (WE1), pela Cloudflare. | Aberto: registros CAA para as autoridades que a Cloudflare usa (`pki.goog`, `letsencrypt.org`, `ssl.com`); a própria Cloudflare mantém os dela quando o domínio tem CAA. |
| S7-04 | **Sem DNSSEC.** Não há registro DS para `escaliburwallet.com`. O HSTS (dois anos, `preload`, inscrição em `hstspreload.org` com estado `pending`, conferido hoje) protege quem já visitou; o DNSSEC fecha a troca de resposta DNS para quem chega pela primeira vez. | Aberto: Cloudflare, DNS, Settings, DNSSEC (o DS vai ao registrador; no Cloudflare Registrar é automático). |
| S7-05 | **Sem `/.well-known/security.txt`.** O canal de relato existe (`SECURITY.md`, a página de segurança do site, o Private Vulnerability Reporting ligado no repositório, conferido hoje), mas o arquivo da RFC 9116, que as ferramentas e os pesquisadores procuram primeiro, responde 404. | Aberto: o gerador escreve `Contact: mailto:security@escaliburwallet.com`, `Policy`, `Preferred-Languages` e `Expires` (menos de um ano). Sem chave PGP publicada, o Private Vulnerability Reporting do GitHub é o caminho cifrado. |
| S7-06 | **A cópia no GitHub Pages sai sem os cabeçalhos do Worker.** `escalibur-wallet.github.io` tem a CSP só na `meta` (que não leva `frame-ancestors`), sem `X-Frame-Options`, com `access-control-allow-origin: *`. É o endereço que o app lê (a lista de versões é assinada e não depende disso) e que ele abre para a auditoria no Safari. Pode ser emoldurada por outro site; o conteúdo é estático e não tem ação de clique que valha um clickjacking. O GitHub Pages não deixa configurar cabeçalhos. | Registrado, aceito: a decisão de 19/10/2026 é o app nunca falar com o servidor do domínio. |

## Revisado sem problema

- Cabeçalhos do domínio: HSTS de dois anos com `includeSubDomains` e `preload`; CSP no cabeçalho e na `meta` (`default-src 'none'`, tudo `'self'`, `base-uri 'none'`, `form-action 'none'`, `frame-ancestors 'none'`); `Cross-Origin-Opener-Policy: same-origin`; `X-Frame-Options: DENY`; `X-Content-Type-Options: nosniff`; `Referrer-Policy: strict-origin-when-cross-origin`; `Permissions-Policy` sem câmera, microfone, localização e pagamento; páginas com `max-age=0, must-revalidate`, CSS e JS imutáveis só com `?v=`. `www` e `http` redirecionam em 301 para o domínio em HTTPS, sem porta, com o HSTS no redirecionamento que já chegou em HTTPS. O 404 sai com os mesmos cabeçalhos.
- A página no ar: um `<script>` só (`site.js?v=…`), um JSON-LD com `<` escapado, nenhum `style=` em linha, nenhum script ou fonte de fora; os únicos links externos são a Play, o GitHub da Escalibur, o CoinGecko e o CoinPaprika. O domínio e a cópia do GitHub mostram o mesmo commit (`176a660c`).
- `site.js`: só `textContent` e `createElement` (nenhum `innerHTML`, `insertAdjacentHTML` ou `eval`); o `fetch` é de `precos.json` no próprio site com `credentials: "omit"`; o `moedas3d.js` é carregado do próprio site; o formulário de suporte monta um `mailto:` com `encodeURIComponent` e recusa texto com seis palavras seguidas das listas BIP-39.
- O Worker: `/precos.json` com uma chave de cache só (nada de quem visita), ids validados por expressão regular, só números na resposta, o retrato da publicação como reserva, `falhas` só com o status; o pedido ao CoinGecko e ao CoinPaprika sai sem cookie, IP ou endereço da página; `observability` desligada; `GET` e `HEAD` só.
- O gerador: todo texto passa por `html.escape`, marcador desconhecido derruba o build, a mensagem dos commits é saneada antes de virar HTML.
- Publicação: `publicar-site.sh --enviar` só com a árvore limpa, o HEAD igual à `origin/main`, o CI do commit verde, a lista de versões conferida e nunca mais antiga que a publicada, sem link simbólico no clone; o wrangler em versão fixa com lock e `--ignore-scripts`, instalado fora da árvore; o commit publicado é lido de volta do domínio antes de dar o envio por terminado. Os workflows: ações fixadas por SHA, `permissions: contents: read`, o `site.yml` só manual e com o job de publicar sem checkout.
- Repositório público: Private Vulnerability Reporting ligado, secret scanning e push protection ligados, ruleset "main protegida" ativo (sem force-push e sem apagar a main), sem bypass.

## Observações, sem mudança pedida

- A ruleset da `main` não exige status check nem revisão: um push direto que quebra o `verificar` entra na `main`, e só o `publicar-site.sh` e o `release.yml` o recusam depois. Exigir o `verificar` verde na ruleset bloquearia o push direto, que é o fluxo de hoje; fica como escolha do dono.
- A raiz de confiança do site continua no Mac do dono (o login do wrangler em `~/.config-cloudflare-escalibur`, o `gh`), como a A6-02 registrou.
- `dependabot_security_updates` desligado: o site tem uma dependência só (o wrangler, com lock e versão fixa) e o `requisitos-ci.txt` é por hash. Sem efeito prático.

## Testes

- Cabeçalhos e redirecionamentos de dez endereços (o domínio, `www`, `http`, `/precos.json`, `/seguranca/`, um 404, `site.js`, um SVG dos selos, a cópia do GitHub e o `versoes.json` dela); DNS (A, AAAA, NS, MX, TXT, `_dmarc`, DS, CAA e sete seletores DKIM); TLS (`openssl s_client` em 1.0, `curl --tls-max` em 1.0, 1.1 e 1.2, o certificado); `hstspreload.org`; a API do GitHub (visibilidade, Private Vulnerability Reporting, secret scanning, rulesets).
- `tools/verificar.sh`: as regras da seção `site` passam (as três recusas da rodada são do iOS, ver `auditoria-7-ios.md`).
