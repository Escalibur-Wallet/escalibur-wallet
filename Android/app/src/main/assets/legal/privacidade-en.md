# Privacy policy

This is a translation of the Portuguese policy. If the two differ, the Portuguese version prevails.

Escalibur Wallet for Android is a wallet that runs entirely on your phone. There is no Escalibur account, sign-up or server, and the app only asks for your email if you open a ticket in Support, for the reply. This text says what the app keeps, where it keeps it, and who it talks to.

Escalibur Wallet is offered by X TECH A.I FUND HOLDING E PARTICIPACOES LTDA, CNPJ 64.019.520/0001-29, called Escalibur here. Contact: support@escaliburwallet.com.

## What stays on your phone

- **The wallet keys.** They stay encrypted in the app’s folder, with Android Keystore keys tied to this device (in the security chip, when the phone has one) and with your PIN. They are not included in the Google backup and do not move to another phone.
- **Wallet names, addresses, contacts and settings.** They stay in an encrypted file in the app’s folder, outside the backup.
- **Price alerts.** The coins you picked, the rules and the last price seen stay in a separate file, outside the backup. It opens after the phone’s first unlock, and not only with the app unlocked like the rest: that is what lets an alert arrive with the app closed. It holds no balance, address or wallet.
- **Nothing leaves the device because of the app.** The recovery phrase (the words) only leaves when you yourself seal an Escalibur Envelope, encrypted with a password of its own, and choose where to save the file.

## What Escalibur receives

Nothing through the app, with one exception: the lookup log that Alchemy keeps in Escalibur's account, described below. The app has no usage analytics, crash reports, ads or tracking, and does not talk to any Escalibur server. The code is published for audit, and an automatic check rejects any library of that kind.

## Who the app talks to

To show balances, prices and history, and to send and swap, the app talks directly to public services for each network, run by different companies. Each one sees your phone’s IP address and the addresses, amounts and transactions the app looks up or sends, and can tell that those addresses belong to the same person. A VPN hides the IP. Turning off a network you don’t use in Settings stops its lookups.

With price alerts on (they come on with Bitcoin, Ethereum, XRP and Solana if you allow notifications, and turn off in Settings, Price alerts), the phone checks from time to time, even with the app closed, the price of the coins you picked on CoinGecko and CoinPaprika. Both see the IP and the list of those coins, nothing more.

Incoming alerts come off on a new install. If you turn them on, in Settings, Incoming alerts, the phone checks about once an hour, also with the app closed, the balance of your accounts on the same services of each network the app already uses, from whatever IP the phone is on. On networks like Bitcoin, only the next receiving address and the last two used ones are checked, each address always with the same service. On every network, when a balance changes, a service from another company checks before the alert; if an address's service is down, that address waits for the next time. For that, the public addresses of those accounts and the last balance seen for each coin stay in a separate file on the phone, readable after the first unlock, outside the wallet's encrypted data. Passphrase wallets are left out, and so are watch-only wallets unless you include them. No key goes into it, and turning the alert off deletes the file.

With a limit order open, the phone asks CoW from time to time, even with the app closed, whether it was filled, so it can alert you. For that, the identifier of each open order (which carries the account address and the deadline, the same data CoW publishes) stays in a separate file, readable after the first unlock. The order leaves the file when it ends. To alert you when an order you asked to renew expires, the file keeps only a digest of the identifier and the time.

The Receive search only looks in the list of coins already on the phone: what you type never leaves the device.

Viewing a transaction or an address on the network's explorer opens the phone's browser, outside the app, with the address or the hash in the page: the explorer's site sees it, and the browser history keeps it.

Inside the app, the list below is complete: the app cannot talk to any other address, and the code checks this in every version.

- **Coin prices, charts and logos:** `api.coingecko.com`, `api.coinpaprika.com`, `assets.coingecko.com`, `coin-images.coingecko.com`, `api.kraken.com`, `www.okx.com`. For the price of a token outside the list that the wallet holds, CoinGecko receives that token's contract or, if it was already recognized, the coin's identifier, at most every 15 minutes.
- **Charts for tokens CoinGecko does not list:** `api.geckoterminal.com`. It receives only the token contract and the network, never your address. The price from there draws the chart and does not count in the total balance.
- **Token list for X Layer and Sonic, and for BNB Chain when Alchemy does not respond:** `tokens.coingecko.com`. The same list for everyone, downloaded so the app can find tokens on these networks; the balance of each one is read from the network's own services.
- **Logos of unlisted tokens:** `raw.githubusercontent.com`, only Trust Wallet's public logo repository. GitHub sees the IP and the contract of each token whose logo the app fetches.
- **Bitcoin, Litecoin and Dogecoin:** `api.bitcore.io`, `api.blockchair.com`, `api.blockcypher.com`, `blockstream.info`, `dogecoin.atomicwallet.io`, `litecoin.atomicwallet.io`, `litecoinspace.org`, `mempool.emzy.de`, `mempool.space`
- **Ethereum, Base, Arbitrum, Optimism, Polygon, BNB Chain, Avalanche, Plasma, X Layer, Linea, Unichain, Sonic and Celo:** `196.rpc.thirdweb.com`, `1rpc.io`, `42220.rpc.thirdweb.com`, `9745.rpc.thirdweb.com`, `api-explorer.linea.build`, `api.avax.network`, `api.routescan.io`, `arb1.arbitrum.io`, `arbitrum-one-rpc.publicnode.com`, `arbitrum.blockscout.com`, `arbitrum.drpc.org`, `arbitrum.meowrpc.com`, `avalanche-c-chain-rpc.publicnode.com`, `avalanche.drpc.org`, `base-rpc.publicnode.com`, `base.blockscout.com`, `base.drpc.org`, `bsc-dataseed.bnbchain.org`, `bsc-dataseed1.defibit.io`, `bsc-dataseed1.ninicoin.io`, `bsc-rpc.publicnode.com`, `celo-rpc.publicnode.com`, `celo.blockscout.com`, `cloudflare-eth.com`, `eth.blockscout.com`, `eth.drpc.org`, `ethereum-rpc.publicnode.com`, `explorer.optimism.io`, `forno.celo.org`, `linea-rpc.publicnode.com`, `linea.drpc.org`, `mainnet.base.org`, `mainnet.optimism.io`, `mainnet.unichain.org`, `optimism-rpc.publicnode.com`, `optimism.drpc.org`, `plasma.gateway.tenderly.co`, `polygon-bor-rpc.publicnode.com`, `polygon.blockscout.com`, `polygon.drpc.org`, `rpc.linea.build`, `rpc.plasma.to`, `rpc.soniclabs.com`, `rpc.xlayer.tech`, `sonic-rpc.publicnode.com`, `sonic.drpc.org`, `unichain-rpc.publicnode.com`, `unichain.blockscout.com`, `unichain.drpc.org`, `xlayer.drpc.org`
- **Base, Arbitrum, Polygon and BNB Chain history and tokens:** they come from Alchemy (`base-mainnet.g.alchemy.com`, `arb-mainnet.g.alchemy.com`, `polygon-mainnet.g.alchemy.com`, `bnb-mainnet.g.alchemy.com`), with a free Escalibur key. The key identifies the app, not you. Alchemy sees the IP and the address looked up, like the other services of each network. It also keeps, for up to 10 days, a log of each lookup made with Escalibur's key, with the address looked up and the response (transactions and balances), and whoever signs in to Escalibur's Alchemy account can see that log.
- **Protected sends on Ethereum:** `rpc.flashbots.net`, `rpc.mevblocker.io`
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
- **Swaps and limit orders:** `aggregator-api.kyberswap.com`, `api.cow.fi`, `api.jup.ag`, `api.velora.xyz`, `li.quest`, `open-api.de1.exchange`. On networks like Ethereum, while you get quotes, each round goes with a randomly drawn address, never yours; your address only goes to the services that build the swap when you tap Review: the chosen one and, if the swap is split between services or the simulation refuses the chosen one, the others in that swap. CoW also receives your address to check for an open order, at most every 5 minutes.
- **Bridge between networks:** `iris-api.circle.com` (Circle) and `app.across.to` (Across). The quote goes without your address: only networks, coin and amount. To follow a bridge, the app sends the hash of the deposit transaction, which is public on the network.

Each of these services has its own privacy policy. Opening the audit page, in Settings, opens the phone’s browser, outside the app.

## Android permissions

- **Biometrics:** Android decides. The app only receives "confirmed" or "not confirmed", never your fingerprint or face.
- **Camera:** only to read an address QR code, on the device, and only when you tap Scan QR. No image is kept.
- **Notifications:** all local, created on the phone itself, and only with your permission: the app has no push token and no server sends it anything. They go out for: price alerts, with the coin and the price, or just "Price alert", as you choose; the incoming alert (if you turn it on), with just "Coins arrived in your wallet", or with the amount and coin that arrived, if you choose; a bridge arriving, with no amount; and limit orders, 24 hours before they expire, when they fill and when they expire, with no coin or amount. Never the wallet balance. On the lock screen, the incoming alert never shows the amount: with the phone locked it only says "Coins arrived in your wallet", and the one posted while unlocked does not appear on the lock screen. Other alerts show on the lock screen as Android is set, and Android's default is to show the content.
- **Run at startup:** only to put the alert checks back on Android’s schedule after the phone restarts.
- **Internet and hiding windows over the app:** the network for the services above; hiding other apps’ windows blocks the overlay scam.

## Clipboard

A copied address is marked as sensitive (Android doesn’t show a preview) and is cleared on its own after 2 minutes, if it is still what the app copied. With the app in the background Android does not let it check: it is cleared when you return to the app. The app never copies the wallet words.

## Your rights

Through the app, Escalibur receives and keeps no data of yours. The exception is the lookup log that Alchemy keeps in Escalibur's account, described above: Escalibur can only see it for up to 10 days. Alchemy itself keeps the IP of the lookups for up to 90 days, and other data about them under its own policy. Beyond that, there is nothing to look up, correct or delete on our side. Uninstalling the app deletes its files and its Keystore keys on this phone. To delete a wallet right away, use Settings, the wallet, Remove from this phone.

## Contact

Questions about this policy or your data: support@escaliburwallet.com. A support ticket leaves the app through your email app, with the address you type for the reply, the subject, what you write, the app version and the Android version, and is used only to reply. The app keeps neither the ticket nor your email. Never send the wallet words, the PIN or an envelope password.

## Changes

Changes to this policy come with a new version of the app and are recorded in the published code.
