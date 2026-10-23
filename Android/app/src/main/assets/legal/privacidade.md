# Política de privacidade

A Escalibur Wallet para Android é uma carteira que roda inteira no seu celular. Não existe conta, cadastro nem servidor da Escalibur, e o app só pede o seu e-mail se você abrir um chamado no Suporte, para a resposta. Este texto diz o que o app guarda, onde guarda, e com quem ele fala.

A Escalibur Wallet é oferecida por X TECH A.I FUND HOLDING E PARTICIPACOES LTDA, CNPJ 64.019.520/0001-29, chamada aqui de Escalibur. Contato: support@escaliburwallet.com.

## O que fica no seu celular

- **As chaves das carteiras.** Ficam cifradas na pasta do app, com chaves do Android Keystore presas a este aparelho (no chip de segurança, quando o celular tem um) e com o seu PIN. Não entram no backup do Google e não passam para outro celular.
- **Nomes das carteiras, endereços, contatos e ajustes.** Ficam num arquivo cifrado na pasta do app, fora do backup.
- **Alertas de preço.** As moedas que você marcou, as regras e o último preço visto ficam num arquivo à parte, fora do backup. Ele abre depois do primeiro desbloqueio do celular, e não só com o app destravado como o resto: é o que deixa o alerta chegar com o app fechado. Nele não entra saldo, endereço nem carteira.
- **Nada sai do aparelho por conta do app.** A senha da carteira (as palavras) só sai quando você mesmo lacra um envelope Escalibur, cifrado com uma senha só dele, e escolhe onde salvar o arquivo.

## O que a Escalibur recebe

Nada pelo app, com uma exceção: o registro de consultas que a Alchemy guarda na conta da Escalibur, descrito abaixo. O app não tem análise de uso, relatório de falhas, anúncios nem rastreamento, e não fala com nenhum servidor da Escalibur. O código é publicado para auditoria, e uma verificação automática recusa qualquer biblioteca desse tipo.

## Com quem o app fala

Para mostrar saldos, preços e histórico, e para enviar e trocar, o app fala direto com serviços públicos de cada rede, de empresas diferentes. Cada um vê o IP do seu celular e os endereços, valores e transações que o app consulta ou envia, e pode perceber que esses endereços são da mesma pessoa. Uma VPN esconde o IP. Desligar em Ajustes uma rede que você não usa para as consultas dela.

Com os alertas de preço ligados (vêm ligados com Bitcoin, Ethereum, XRP e Solana, se você permitir as notificações, e desligam em Ajustes, Alertas de preço), o celular consulta de tempos em tempos, também com o app fechado, o preço das moedas marcadas no CoinGecko e no CoinPaprika. Os dois veem o IP e a lista dessas moedas, nada mais.

O aviso de recebimento começa desligado. Se você ligar, em Ajustes, Aviso de recebimento, o celular confere cerca de uma vez por hora, também com o app fechado, o saldo das suas contas nos mesmos serviços de cada rede que o app já usa, do IP em que o celular estiver. Nas redes como o Bitcoin vão só o próximo endereço de recebimento e os dois últimos usados, cada endereço sempre ao mesmo serviço, e um segundo serviço só confere quando o saldo sobe. Para isso, os endereços públicos dessas contas e o último saldo visto de cada moeda ficam num arquivo à parte no celular, legível depois do primeiro desbloqueio, fora dos dados cifrados da carteira. Carteiras com passphrase ficam de fora, e as de só observar também, a não ser que você ligue. Nenhuma chave entra nele, e desligar o aviso apaga o arquivo.

Com uma ordem limite aberta, o celular pergunta à CoW de tempos em tempos, também com o app fechado, se ela foi executada, para avisar. Para isso, o identificador de cada ordem aberta (que traz o endereço da conta e o prazo, os mesmos dados que a CoW publica) fica num arquivo à parte, legível depois do primeiro desbloqueio. A ordem sai do arquivo quando termina. Para avisar do fim do prazo de uma ordem que você pediu para refazer, o arquivo guarda só um resumo do identificador e a hora.

A busca de Receber procura só na lista de moedas que já está no celular: o que você digita não sai do aparelho.

Ver uma transação ou um endereço no explorador da rede abre o navegador do celular, fora do app, com o endereço ou o hash na página: o site do explorador vê isso, e o histórico do navegador guarda.

Dentro do app, a lista abaixo é completa: o app não consegue falar com nenhum outro endereço, e o código confere isso a cada versão.

- **Preços, gráficos e logos das moedas:** `api.coingecko.com`, `api.coinpaprika.com`, `assets.coingecko.com`, `coin-images.coingecko.com`, `api.kraken.com`, `www.okx.com`. Para o preço de um token fora da lista que a carteira tem, o CoinGecko recebe o contrato desse token.
- **Gráfico de tokens que o CoinGecko não lista:** `api.geckoterminal.com`. Recebe só o contrato do token e a rede, nunca o seu endereço. O preço de lá desenha o gráfico e não entra no saldo total.
- **Lista de tokens da X Layer e da Sonic, e da BNB Chain quando a Alchemy não responde:** `tokens.coingecko.com`. A mesma lista para todo mundo, baixada para o app achar os tokens dessas redes; o saldo de cada um é lido nos serviços da própria rede.
- **Logos de tokens fora da lista:** `raw.githubusercontent.com`, só o repositório público de logos da Trust Wallet. O GitHub vê o IP e o contrato de cada token cuja logo o app busca.
- **Bitcoin, Litecoin e Dogecoin:** `api.bitcore.io`, `api.blockchair.com`, `api.blockcypher.com`, `blockstream.info`, `dogecoin.atomicwallet.io`, `litecoin.atomicwallet.io`, `litecoinspace.org`, `mempool.emzy.de`, `mempool.space`
- **Ethereum, Base, Arbitrum, Optimism, Polygon, BNB Chain, Avalanche, Plasma, X Layer, Linea, Unichain, Sonic e Celo:** `196.rpc.thirdweb.com`, `1rpc.io`, `42220.rpc.thirdweb.com`, `9745.rpc.thirdweb.com`, `api-explorer.linea.build`, `api.avax.network`, `api.routescan.io`, `arb1.arbitrum.io`, `arbitrum-one-rpc.publicnode.com`, `arbitrum.blockscout.com`, `arbitrum.drpc.org`, `arbitrum.meowrpc.com`, `avalanche-c-chain-rpc.publicnode.com`, `avalanche.drpc.org`, `base-rpc.publicnode.com`, `base.blockscout.com`, `base.drpc.org`, `bsc-dataseed.bnbchain.org`, `bsc-dataseed1.defibit.io`, `bsc-dataseed1.ninicoin.io`, `bsc-rpc.publicnode.com`, `celo-rpc.publicnode.com`, `celo.blockscout.com`, `cloudflare-eth.com`, `eth.blockscout.com`, `eth.drpc.org`, `ethereum-rpc.publicnode.com`, `explorer.optimism.io`, `forno.celo.org`, `linea-rpc.publicnode.com`, `linea.drpc.org`, `mainnet.base.org`, `mainnet.optimism.io`, `mainnet.unichain.org`, `optimism-rpc.publicnode.com`, `optimism.drpc.org`, `plasma.gateway.tenderly.co`, `polygon-bor-rpc.publicnode.com`, `polygon.blockscout.com`, `polygon.drpc.org`, `rpc.linea.build`, `rpc.plasma.to`, `rpc.soniclabs.com`, `rpc.xlayer.tech`, `sonic-rpc.publicnode.com`, `sonic.drpc.org`, `unichain-rpc.publicnode.com`, `unichain.blockscout.com`, `unichain.drpc.org`, `xlayer.drpc.org`
- **Histórico e tokens de Base, Arbitrum, Polygon e BNB Chain:** vêm da Alchemy (`base-mainnet.g.alchemy.com`, `arb-mainnet.g.alchemy.com`, `polygon-mainnet.g.alchemy.com`, `bnb-mainnet.g.alchemy.com`), com uma chave gratuita da Escalibur. A chave identifica o app, não você. A Alchemy vê o IP e o endereço consultado, como os outros serviços de cada rede. Ela também guarda, por até 10 dias, o registro de cada consulta feita com a chave da Escalibur, com o endereço consultado e a resposta (transações e saldos), e quem entra na conta da Escalibur na Alchemy consegue ver esse registro.
- **Envio protegido na Ethereum:** `rpc.flashbots.net`, `rpc.mevblocker.io`
- **Solana:** `api.mainnet.solana.com`, `public.rpc.solanavibestation.com`, `solana-mainnet.gateway.tatum.io`, `solana-rpc.publicnode.com`
- **XRP Ledger:** `s1.ripple.com`, `s2.ripple.com`, `xrplcluster.com`
- **Stellar:** `horizon.stellar.lobstr.co`, `horizon.stellar.org`
- **Tron:** `api.trongrid.io`, `api.tronstack.io`, `tron-rpc.publicnode.com`
- **TON:** `tonapi.io`, `toncenter.com`
- **Sui:** `fullnode.mainnet.sui.io`, `graphql.mainnet.sui.io`, `rpc-mainnet.suiscan.xyz`, `sui-mainnet.nodeinfra.com`
- **Cardano:** `api.koios.rest`, `api.yoroiwallet.com`, `zero.yoroiwallet.com`
- **Polkadot:** `polkadot-asset-hub-rpc.polkadot.io`, `rpc-asset-hub-polkadot.luckyfriday.io`, `asset-hub-polkadot-rpc.n.dwellir.com`, `statemint.api.onfinality.io`, `polkadot-asset-hub-public-sidecar.parity-chains.parity.io`, `subquery-history-polkadot-ah-prod.novasama-tech.org`
- **NEAR:** `api.fastnear.com`, `free.rpc.fastnear.com`, `near.drpc.org`, `rpc.shitzuapes.xyz`, `rpc.intea.rs`, `tx.main.fastnear.com`
- **Aptos:** `aptos-rest.publicnode.com`, `rpc.sentio.xyz`, `api.mainnet.aptoslabs.com`
- **Trocas e ordens limite:** `aggregator-api.kyberswap.com`, `api.cow.fi`, `api.jup.ag`, `api.velora.xyz`, `li.quest`, `open-api.de1.exchange`. Nas redes como a Ethereum, enquanto você cota, a cotação vai com um endereço sorteado a cada rodada, nunca o seu; o seu endereço só vai ao serviço escolhido quando você toca em Revisar, para montar a troca. A CoW recebe o seu endereço também para conferir se há uma ordem aberta, no máximo a cada 5 minutos.
- **Ponte entre redes:** `iris-api.circle.com` (Circle) e `app.across.to` (Across). A cotação vai sem o seu endereço: só redes, moeda e valor. Para acompanhar uma ponte, o app manda o hash da transação de depósito, que é público na rede.

Cada um desses serviços tem a própria política de privacidade. Abrir a página da auditoria, em Ajustes, abre o navegador do celular, fora do app.

## Permissões do Android

- **Biometria:** quem decide é o Android. O app recebe só "confirmou" ou "não confirmou", nunca a sua digital ou o seu rosto.
- **Câmera:** só para ler QR code de endereço, no aparelho, e só quando você toca em Ler QR. Nenhuma imagem é guardada.
- **Notificações:** todas locais, criadas no próprio celular, e só com a sua permissão: o app não tem token de push e nenhum servidor manda nada para ele. Saem para: alertas de preço, com a moeda e o preço, ou só "Alerta de preço", como você escolher; aviso de recebimento (se você ligar), só com "Entrou moeda na carteira", ou com o valor e a moeda que entraram, se você escolher; chegada de uma ponte, sem valor; e ordens limite, 24 horas antes de vencer, quando executa e quando o prazo acaba, sem moeda nem valor. Nunca o saldo da carteira. Na tela bloqueada, o aviso de recebimento nunca mostra o valor: com o celular travado sai só "Entrou moeda na carteira", e o que sai com ele destravado não aparece na tela bloqueada. Os outros avisos aparecem na tela bloqueada como o Android estiver ajustado, e o padrão do Android é mostrar o conteúdo.
- **Iniciar com o aparelho:** só para pôr a conferência dos avisos de volta na agenda do Android depois que o celular reinicia.
- **Internet e esconder janelas por cima do app:** a rede para os serviços acima; esconder janelas de outros apps impede o golpe da sobreposição.

## Área de transferência

Endereço copiado fica marcado como sensível (o Android não mostra a prévia) e é apagado sozinho depois de 2 minutos, se ainda for o que o app copiou. Com o app em segundo plano o Android não deixa conferir: ele é apagado quando você volta ao app. O app não copia as palavras da carteira.

## Seus direitos

Pelo app, a Escalibur não recebe nem guarda dado nenhum seu. A exceção é o registro de consultas que a Alchemy guarda na conta da Escalibur, descrito acima: a Escalibur só consegue vê-lo por até 10 dias. A própria Alchemy guarda o IP das consultas por até 90 dias, e outros dados delas pela política dela. Fora isso, não há o que consultar, corrigir ou apagar do nosso lado. Desinstalar o app apaga os arquivos dele e as chaves do Keystore deste celular. Para apagar uma carteira na hora, use Ajustes, a carteira, Remover deste celular.

## Contato

Dúvidas sobre esta política ou sobre os seus dados: support@escaliburwallet.com. Um chamado de suporte sai do app pelo seu aplicativo de e-mail, com o endereço que você digitar para a resposta, o assunto, o que você escrever, a versão do app e a do Android, e serve só para responder. O app não guarda o chamado nem o seu e-mail. Nunca mande as palavras da carteira, o PIN nem a senha de um envelope.

## Mudanças

Mudanças nesta política vêm junto com uma versão nova do app e ficam registradas no código publicado.
