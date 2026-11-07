# Release: da tag assinada ao TestFlight

O build que vai para a Apple sai do `.github/workflows/release.yml`, num runner limpo da GitHub, a partir de uma tag assinada pelo dono, e não do Mac de ninguém. É a parte do R7-M3 (auditoria 4) que dá para fechar: um elo verificável entre o commit auditado e o arquivo enviado à Apple.

## Uma vez só

No Mac do dono, a chave que assina as tags (com senha; se houver chave de segurança física, `-t ed25519-sk` deixa a privada presa nela):

```
ssh-keygen -t ed25519 -C "escalibur-release" -f ~/.ssh/escalibur_release
git config gpg.format ssh
git config user.signingkey ~/.ssh/escalibur_release.pub
```

A chave pública vai, numa linha, para `.github/assinantes` (o formato está no próprio arquivo), num commit que entra na main antes da primeira tag, e é cadastrada na GitHub como chave de assinatura, para a tag aparecer como verificada.

No GitHub:
- environment `release`, com o dono como revisor obrigatório e só as tags `testflight-*` e `v*` como origem; nele, e só nele, os segredos `ASC_KEY_ID`, `ASC_ISSUER_ID` e `ASC_KEY_P8`;
- a regra da main exige o check `verificar` antes de qualquer commit entrar;
- uma regra de tags em que só o dono cria, move ou apaga `testflight-*` e `v*`.

## Autorizar a versão (antes de ir para a loja)

O app instalado só aceita como confiável a versão que está na lista assinada do site (docs/seguranca.md §8.6). Antes de liberar uma versão nova na App Store, no Terminal do Mac do dono (pede o Touch ID):

```
swift tools/versoes/versoes.swift autorizar 1.0.1 8 escalibur-mac-1
swift tools/versoes/versoes.swift conferir
```

O `site/versoes.json` assinado entra num commit e sai com o site, e o archive leva o mesmo arquivo dentro do app: por isso a assinatura vem antes do archive. Versão na loja fora da lista trava o app de quem ainda está na versão anterior, com o alerta de tentativa de hack. Por isso a lista assinada sai antes da versão chegar na loja: esquecer de assinar trava o app de todo mundo.

Nenhum build sai sem ela (pedido do dono, 18/10/2026): o job `assinatura` do `release.yml` recusa a tag se o `site/versoes.json` do commit não trouxer a versão com aquele build, e o job `verificar` confere as assinaturas da lista contra o `ReleaseKeys`. Vale para `testflight-*` e `v*`. A ordem é: autorizar, commit do `versoes.json` na main (o site publica), e só então a tag. Depois do archive, o `montar` confere no próprio `.app` que a lista que vai dentro dele autoriza a versão e o build do `Info.plist` dele; um build montado no Mac passa pela mesma conferência antes do envio:

```
swift tools/versoes/versoes.swift conferir-app build/EscaliburWallet-1.0.1-8.xcarchive/Products/Applications/EscaliburWallet.app
```

## Liberar a versão (depois de a Apple publicar)

A tela "Esta versão está desatualizada" do app só empurra para uma versão liberada (docs/seguranca.md §8.6). Depois de a Apple publicar o build do dono na App Store, e de conferir no App Store Connect que o build aprovado é o que o dono enviou (o número e o dia do envio), no Terminal do Mac do dono (pede o Touch ID):

```
swift tools/versoes/versoes.swift liberar 1.0.2 19 escalibur-mac-1
```

O build é o aprovado que o App Store Connect mostra, e a conferência de que foi o dono quem o enviou, no dia do envio, é o que prende a liberação ao binário: os builds autorizados ficam públicos antes. A ferramenta recusa um build fora dos autorizados da versão ou que não seja do iPhone, a versão que a App Store não mostra no ar, e o relógio do Mac mais de 5 minutos fora da hora da Apple (o app ignora uma lista mais antiga que uma já vista). Se o envio de um build autorizado for recusado pela Apple como repetido, alguém enviou antes: é incidente, e não se autoriza outro número por cima. O `site/versoes.json` assinado entra num commit e sai com o site. O site sai antes do build seguinte: o app leva a lista de dentro dele como a mais nova já vista, e com o site atrás as telas de atualizar ficam desligadas nesse build até o site chegar. Para obrigar quem ficou para trás (`obrigatoria 1.0.2 - escalibur-mac-1` obriga quem está abaixo da 1.0.2; `obrigatoria - - escalibur-mac-1` tira), a versão de saída já tem de estar liberada.

No Android a tela lê só a lista: a Google Play não tem consulta pública da versão mais nova. Depois de o lançamento do build chegar a 100% na produção (`play.py ampliar <build> completo`) e de a Play Console mostrar que ele saiu da revisão do Google, no Terminal do Mac do dono (pede o Touch ID):

```
swift tools/versoes/versoes.swift liberar-android 1012 escalibur-mac-1
```

A ferramenta recusa um build que não seja do Android, fora dos autorizados, não mais novo que o liberado antes, que a API da Play não mostre em 100% na produção (sem fração nem lista de países; a mesma conta de serviço do `play.py`, só lendo; `play.py completo <build>` mostra a faixa à mão), cujo pacote na Play não seja o que este Mac enviou (`~/.escalibur/android/enviados.json`, que o `play.py producao` e o `subir` gravam antes do commit, depois de conferir o SHA-256 que a Play guardou), ou com um pacote mais novo na Play que não saiu deste Mac. Um build enviado pela Play Console, ou antes de 07/11/2026, não está no `enviados.json` e não é liberado: anote o SHA-256 dele à mão só depois de conferir que o AAB é o seu (o `SHA256SUMS` do `gerar-aab.sh`). Ela pede o número do build digitado depois de conferir na Play Console que ele saiu da revisão (a API diz "completed" desde o envio), e grava o `minSdk` do `Android/app/build.gradle.kts`. Um envio recusado pela Play como `versionCode` repetido é incidente, como no iPhone: não se autoriza outro número por cima. Num incidente (build recusado pelo Google, lançamento pausado, build na Play que não é do dono), `liberar-android - escalibur-mac-1` tira a liberação. Em lançamento gradual, quem está fora da fração veria a tela e nenhuma atualização na Play. Para obrigar os builds abaixo de um (`obrigatoria-android 1012 escalibur-mac-1`; `obrigatoria-android - escalibur-mac-1` tira), o build de saída já tem de estar liberado, e a regra nunca pega ele.

## Assinar a tag

Cada release, num commit que já está na main:

```
git tag -s testflight-1.0.0-4 -m "TestFlight 1.0.0 (4)" <commit>
git tag -v testflight-1.0.0-4
git push origin testflight-1.0.0-4
```

- `1.0.0` tem de ser o `MARKETING_VERSION` do `project.yml` e do projeto gerado; o workflow recusa outro.
- `4` é o número do build (`CFBundleVersion`). Vale o da tag, passado ao `xcodebuild` como `CURRENT_PROJECT_VERSION=4`; o `CURRENT_PROJECT_VERSION` do `project.yml` fica para os builds locais. A App Store Connect recusa número repetido.
- `v1.0.0-N` segue o mesmo formato e o mesmo caminho, para quando houver build direto para a revisão. Mandar para a revisão um build que já está no TestFlight não precisa de tag nova.
- Depois do push, o run para no job `montar` esperando o dono aprovar o environment `release` (Actions, o run, Review deployments). Só então os segredos existem para o runner.

## O que o workflow prova

1. A tag é anotada, assinada por uma chave de `.github/assinantes` do próprio commit (`git tag -v` com `gpg.minTrustLevel=fully`), e aponta para um commit que está na main. Sem chave no arquivo, nenhum release roda.
2. Esse commit passou pelo mesmo `verificar.yml` que confere a main: o verificador, os testes do núcleo, o app em Release e o envelope.
3. O `.ipa` foi montado desse commit num runner `macos-26` limpo, com o Xcode do `.xcode-version` e o projeto do repositório, sem certificado nem chave privada de assinatura de código no runner: quem assina é a nuvem da Apple (certificado de distribuição gerenciado), acionada pela chave da API.
4. A assinatura que sai é de distribuição da equipe `2UNWMDD93S`, com os entitlements dos arquivos `.entitlements` do repositório e nada além dos que a Apple põe (`tools/conferir-entitlements.py`), sem `get-task-allow`, com o build da tag, com a lista assinada que autoriza esse build dentro do app (`versoes.swift conferir-app`) e sem nada do modo demo no binário.
5. O SHA-256 do `.ipa`, do binário principal e do binário principal sem a assinatura vai para `SHA256SUMS`, no resumo do run e no artefato `digestos-<tag>` (90 dias), com o `release.txt` (tag, commit, run, Xcode, imagem do runner).
6. Uma atestação de proveniência (SLSA, `actions/attest`) liga esses três digestos ao repositório, ao `release.yml`, ao commit e à tag. Ela é assinada pela Sigstore pública e fica registrada no log de transparência dela, que não expira com o run.
7. O arquivo enviado à App Store Connect (`altool --upload-package`) é o mesmo do digesto: o workflow confere antes de enviar.

A chave da API é uma chave de equipe (Team Key) com o papel Admin: a Apple só deixa Account Holder e Admin assinarem com certificado gerenciado pela nuvem, e chave individual não usa os endpoints de provisionamento. Admin também administra usuários, por isso ela só existe no environment `release`, que pede a aprovação do dono, e sai do runner no fim de cada passo que a usa.

## O que não prova

- **Que o app da App Store é este `.ipa`, byte a byte.** A Apple troca a assinatura pela dela, recifra o executável com FairPlay e entrega a cada aparelho uma versão afinada dos recursos (App Thinning). O usuário comum não consegue comparar nada sozinho.
- **Que o build é reproduzível.** Ninguém compilou o mesmo commit duas vezes e comparou. O workflow registra o que montou; que outro build do mesmo commit dê o mesmo executável é afirmação a conferir (docs/seguranca.md, §8.5).
- **Que o código está certo.** A atestação prova de onde o binário veio, não que ele não tem falha.
- **Que ninguém mais envia builds.** Quem tiver a chave da API, ou entrar na conta da App Store Connect, envia build de qualquer lugar. A diferença é que esse build não tem atestação nem tag assinada: build sem as duas não saiu daqui.
- **Que a chave de assinatura das tags não vazou** e que o dono não foi coagido. A regra das tags (só o dono cria `testflight-*` e `v*`) e a aprovação do environment estreitam isso; chave vazada sai de `.github/assinantes` de vez.
- **Que a lista de assinantes é a de sempre.** Ela vem do próprio commit da tag: quem põe um commit na main e aprova o environment (o dono, ou quem tiver o acesso de administrador dele) também troca a lista. A troca fica no histórico público da main, e é o primeiro arquivo que um auditor deve olhar entre duas tags.

## O que um auditor confere

- **A origem de um build:** `release.txt` e `SHA256SUMS` do run (ou o resumo dele) dizem tag, commit e digestos; `gh attestation verify`, abaixo, confere que foi este workflow, neste commit.
- **O app instalado contra o build atestado:** com um iPhone de pesquisa (jailbreak) e uma ferramenta que extrai o executável decifrado, pela metodologia do WalletScrutiny. Tirar a assinatura da cópia (`codesign --remove-signature`) e comparar o SHA-256 com a linha `EscaliburWallet.sem-assinatura`, ou passar o arquivo direto no `gh attestation verify`. Se bater, o app da loja é o executável deste run. Se não bater, a diferença tem de ficar no que a Apple e a ferramenta mexem (assinatura e o campo `cryptid`); até hoje ninguém fez essa comparação, e o primeiro resultado vai para cá.
- **O código contra o build:** compilar a tag com o mesmo Xcode (`xcodebuild archive ... CURRENT_PROJECT_VERSION=N CODE_SIGNING_ALLOWED=NO`, como no workflow) e comparar o executável com o `sem-assinatura`. Pode diferir (caminhos, ordem de ligação); sem o build duplo do §8.5, isso não está provado.
- **Fora do alcance:** os recursos afinados que cada aparelho recebe, o que a Apple faz na revisão e na distribuição, e o que acontece na conta da App Store Connect.

## Conferir uma atestação

Com o arquivo na mão (o `.ipa`, o executável, ou o `sem-assinatura` de um app decifrado):

```
gh attestation verify EscaliburWallet.sem-assinatura \
  --repo Escalibur-Wallet/escalibur-wallet \
  --signer-workflow Escalibur-Wallet/escalibur-wallet/.github/workflows/release.yml \
  --source-ref refs/tags/testflight-1.0.0-4 \
  --deny-self-hosted-runners
```

`--source-digest <commit>` amarra também o commit. Sem o arquivo, só com o digesto: `gh api repos/Escalibur-Wallet/escalibur-wallet/attestations/sha256:<digesto>` lista as atestações dele, e `gh attestation download` guarda o pacote, que depois confere com `--bundle`.

## Se o export recusar

O archive sai sem assinatura e recebe, pelo `codesign`, uma assinatura local com os entitlements do repositório, para o export da nuvem saber o que o app pede. Isso não foi testado de ponta a ponta antes do primeiro release. Se a Apple recusar esse archive, ou o `.ipa` sair com outros entitlements (o `conferir-entitlements.py` para o release antes do envio), o caminho é um certificado Apple Development de longa duração, em `.p12`, como quarto segredo do environment `release`, importado num keychain temporário só para o archive.

## Build feito no Mac

Enquanto o workflow não roda, o build do TestFlight e o da Play saem do Mac do dono, mas só do código publicado (auditoria de 03/11/2026):

```
tools/arquivar.sh <build>              # iPhone: /private/tmp/escalibur-arquivo-<versao>-<build>.*/EscaliburWallet.xcarchive
tools/android/gerar-aab.sh             # Android: /private/tmp/escalibur-aab-<versao>-<build>.*/ (AAB, APK e SHA256SUMS)
```

Os dois leem `tools/copia-publicada.sh`:
- a árvore daqui (`HEAD^{tree}`) tem de ser a da `main` do GitHub: o push do dia vem antes do build;
- os scripts da loja daqui têm de ser os do commit publicado, comparados pelo conteúdo (`git hash-object`, que um `assume-unchanged` não esconde), e a `main` é lida pela ref remota e conferida com o `ls-remote` (uma tag local chamada `origin/main` não engana);
- o build roda num worktree novo e destacado do commit publicado, em `/private/tmp`, sem hooks, e sai dali no fim. A segunda fase de cada script roda da cópia de dentro dele e confere de novo que ela está limpa (nem arquivo ignorado, nem arquivo marcado para o git não olhar). Nada da pasta de trabalho entra: nem arquivo que o git ignora, nem mudança de outra sessão;
- o commit publicado e a árvore vão dentro do app (`EscaliburCommit` e `EscaliburTree` no `Info.plist`, `COMMIT_DE_ORIGEM` e `ARVORE_DE_ORIGEM` no `BuildConfig`) e são conferidos no binário. A tela de Ajustes mostra o commit; quem confere depois de uma junção diária compara a árvore: `git rev-parse <commit>^{tree}`.

O iPhone roda depois as mesmas conferências do `release.yml` (versão, lista assinada, nada do modo demo). No Android, o Gradle recusa o release fora de um worktree em `/private/tmp/escalibur-loja.*`, sem o commit e a árvore da própria pasta, com a pasta suja, com o commit diferente da `main` publicada ou com um núcleo que não foi compilado em release deste commit (o `compilar-nucleo.sh release --loja` grava o carimbo `build/android-kit/origem-do-nucleo.txt` com `release-loja`, o commit e o SHA-256 do `.so` e da `libc++_shared.so`, conferida pelo digesto do NDK r30), e confere o C do núcleo; o `gerar-aab.sh` confere os dois nos dex extraídos do APK e do AAB. Assinar, exportar e enviar seguem como antes, a partir desse archive. O archive sai numa pasta nova em `/private/tmp`, fora do repositório, com um app só e o `ApplicationPath` dele, e o script imprime o digesto do `.xcarchive` inteiro (cada arquivo, pasta e link simbólico, com o modo e o conteúdo); antes de assinar, confira que ele não mudou:

```
git -C <repositorio> show <commit impresso>:tools/digesto.sh | /usr/bin/env -i /bin/bash -p -s -- <pasta do archive>/EscaliburWallet.xcarchive
```

O script vem do commit publicado, e não da pasta de trabalho, que outra sessão pode editar.

As flags que o compilador do Swift recebeu de fato são conferidas no log de cada build da loja (`tools/flags-do-build.py`): o `arquivar.sh` e o `release.yml` gravam o log inteiro do archive (sem `-quiet`; o do Mac fica em `archive.log`, ao lado do `.xcarchive`), e o `compilar-nucleo.sh release --loja`, que o `gerar-aab.sh` chama, compila o núcleo do zero com `swift build -v` e grava `build/nucleo-release.log`. Cada chamada do `swiftc` e do `swift-frontend` que compila um módulo nosso tem de vir do toolchain de verdade (o Xcode do `xcode-select -p`, o Swift 6.4.1 do Android), para o aparelho e no modo 6 da linguagem, só com os `-D` que o verificador conhece para o módulo, com plugin de macro só do toolchain, e todo módulo da plataforma aparece ao menos uma vez. Toda opção do compilador está numa lista fechada, com o valor de cada uma, e os caminhos de busca só podem ser do toolchain, da pasta do build e das pastas `include` do C do Kit: uma opção a mais para tudo antes de assinar (décima e décima primeira passadas da auditoria de 03/11/2026). O núcleo de depuração não é conferido (as flags dele são outras).

O build da loja só começa com o CI (`verificar`) verde no commit publicado: depois do push do dia, espere o check no GitHub. A cópia limpa confere os digestos do `loja.lock` antes de montar.

O `loja.lock` trava também o `Kit/Package.swift`, o `flags-do-build.py`, o projeto do Xcode (`project.yml`, `project.pbxproj`, o workspace e o esquema; ele muda a cada arquivo novo do app) e os arquivos do Gradle (os três `.gradle.kts`, `gradle.properties`, `libs.versions.toml`, o wrapper, `verification-metadata.xml` e `proguard-rules.pro`). A versão do Android mora no `Android/app/build.gradle.kts`: ao subir o `versionCode` ou o `versionName`, revise o diff e grave o digesto novo no `loja.lock` (`shasum -a 256 Android/app/build.gradle.kts`).
