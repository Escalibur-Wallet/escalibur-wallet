# Auditoria 5 (19/10/2026)

Auditoria do que mudou desde a auditoria 4 (main `0a66578`), pedida pelo dono, feita numa passada só, sem revisores em paralelo: 112 commits até `eba1479`. O núcleo do Super Security (o modo reforçado, com as três políticas de quando o Face ID muda) já tinha passado por revisões próprias em 16/10/2026 (`15c7b00`, `b37a5b3`); aqui entrou o que mexeu nele depois delas. Uma auditoria completa, com os revisores de segurança em paralelo, vem em seguida.

## O que foi olhado

- **Chaves e assinatura:** as mudanças em `EscaliburKeys` depois da revisão das três políticas (a conferência da passphrase no `Signer`, o embrulho das chaves do PIN), o `PassphraseGate`, o `AuthCoordinator` e o caminho de ligar e desligar o Super Security.
- **Versão autorizada:** `ReleaseKeys`, `ReleaseManifest`, `ReleaseWatch`, o `UpdateGuard`, a ferramenta `tools/versoes/versoes.swift` e a trava do envio no `release.yml`.
- **Troca:** os motores diretos novos (Uniswap, PancakeSwap e ShibaSwap) contra o `TradeValidator`, as autorizações de token e o disponível de uma troca com ordens abertas.
- **Superfícies novas do app:** o navegador da auditoria (`SiteBrowser`), o campo de senha (`SecureInputField`), o Safe Keyboard no Super Security, o envelope (criar, repetir, abrir) e os hosts novos.
- **O binário do build 8** enviado ao TestFlight: segredos, código do modo demo, endereços sem TLS, assinatura e entitlements.

## Achados

### Médios

| Item | Achado | Estado |
|---|---|---|
| A5-01 | Ao ligar e ao desligar o Super Security, o iOS abria a janela "Digite a senha para Escalibur". O embrulho das chaves do PIN no Secure Enclave (`kpin`, `kand.pin.a/b`, com senha de aplicativo) buscava a chave sem a senha, e o sistema pedia a senha na tela; podia acontecer também ao criar ou trocar o PIN. A senha é derivada do PIN, o dono não a conhece: nada abria, mas a operação podia parar, e uma janela do sistema pedindo senha é o tipo de coisa que ensina o dono a digitar senha onde não deve. | Feito (`eba1479`). O embrulho dessas chaves leva a senha de aplicativo e proíbe interface (`wrap(_:slot:password:)`); o embrulho sem senha recusa os slots do PIN e também não mostra interface. O dublê dos testes acusa qualquer embrulho de chave do PIN sem a senha. O simulador não tem senha de aplicativo: só o próximo build no iPhone confirma. |
| A5-02 | O build 8 saiu do Mac do dono, não do `release.yml`: o repositório ficou privado e o GitHub Actions não roda sem cobrança. Sem a tag assinada e sem a atestação de proveniência da Sigstore. | Em parte. As mesmas conferências do `release.yml` rodaram no Mac (verificador completo com os testes do núcleo, versão e build no app e no widget, nada do modo demo, assinatura de distribuição da equipe, entitlements do repositório) e os digestos do `.ipa` ficaram em `build/saida-1.0.0-8/`. Falta o dono decidir: o repositório público de novo, ou o Actions pago. |
| A5-03 | Uma chave só assina a lista de versões (a do Mac do dono, hoje `escalibur-mac-1`, no Secure Enclave), sem cópia. Perder o Mac impede autorizar versão nova até sair uma versão do app com outra chave. | Aberto. Recomendado: uma segunda chave (YubiKey) e o limiar de 2 de 3 depois. |
| A5-04 | A tela "Taxas, código auditável e versão" diz que o código que guarda chaves, assina e fala com as redes é publicado. Com o repositório privado, o site mostra o código das chaves, não o resto. | Aberto: decisão do dono. |

### Baixos

| Item | Achado | Estado |
|---|---|---|
| A5-05 | Na troca imediata, o disponível não descontava o que as ordens limite abertas ainda iam vender: gastar esse saldo fazia a ordem falhar quando o preço chegasse. | Feito (`eba1479`): o mesmo desconto da ordem limite. |
| A5-06 | Passphrase errada ao mover saldo: o aviso ficava no fim da tela de revisão, fora da vista. | Feito (`8c5ff77`): o aviso aparece também no alto, por cima de tudo. |
| A5-07 | Com o Super Security ligado, o globo do Safe Keyboard e a folha de informações ainda deixavam usar o teclado do iPhone nas palavras. | Feito (`8cd8c3d`). |
| A5-08 | Segurar o campo de senha para ver o que foi digitado abria a lupa do iOS. | Feito (`8c5ff77`). |
| A5-09 | A escolha de 12 ou 24 palavras, ao criar a carteira, ficou atrás do rodapé desde que ele ganhou "Prefiro escolher as minhas palavras": quem abria não via a opção de 24. Achado pelo teste de interface. | Feito: a escolha logo abaixo do texto que diz quantas palavras são. |
| A5-10 | O horário da checagem do aparelho era lido pelo VoiceOver começando pelo nome do ícone do relógio. | Feito: o ícone é só enfeite para o leitor de tela. |

## Sem achado

- **`Signer`:** a passphrase digitada é conferida com a do cofre, as duas em NFKD e em tempo constante, antes de qualquer chave nascer; carteira sem passphrase recusa a digitada.
- **Motores diretos de troca:** o `TradeValidator` confere o router da lista, a função permitida e decodifica a chamada (token vendido e comprado, valor, destinatário igual ao dono, mínimo de saída). As autorizações de token são sempre exatas.
- **Lista de versões:** só vale com assinaturas das chaves compiladas, no limiar, do app certo; texto mexido depois de assinado recusa. A trava do `release.yml` recusa tag sem a versão e o build na lista.
- **`SiteBrowser`:** o navegador da Apple, em outro processo, só para `https://tmzzjr.github.io`; `WKWebView` e afins continuam proibidos, e o `verificar.sh` confere.
- **Hosts novos:** `itunes.apple.com` e `tmzzjr.github.io`, no `hosts.lock`, no `AllowedHosts` e na política de privacidade.
- **Binário do build 8:** nenhuma chave privada, token ou chave de API; nada do modo demo; nenhum endereço sem TLS.

## Testes

- `tools/verificar.sh --testes`: tudo conferido, 1553 testes do núcleo.
- Testes de interface, a suíte inteira, com o rosto do simulador aprovado em laço para os do Super Security entrarem: 93 testes, 73 passaram, 16 pulados por condição (rede ou ambiente que o teste pede) e 4 falharam. Um dependia da rede e passou na segunda vez (tokens suspeitos). Dois eram testes desatualizados pelas telas novas (o horário da checagem, agora com o ícone; "Oferta de moedas"), corrigidos. Um era defeito de tela (A5-09), corrigido. Os quatro passam agora.
- O caminho de Release da versão autorizada, no simulador: o build da lista abre normal; um build fora dela fica travado.
- Binário do build 8: sem segredo, sem código do modo demo, sem endereço sem TLS; assinatura e entitlements conferidos no envio.
