// O site da Escalibur Wallet em escaliburwallet.com: os arquivos gerados pelo
// tools/gerar-site.py, servidos pela Cloudflare, e o /precos.json do Mercado ao vivo. O app
// da carteira nunca fala com este servidor (pedido do dono, 19/10/2026): a lista de versoes
// e a auditoria que o app abre vem do GitHub (escalibur-wallet.github.io).
//
// O /precos.json: quem busca o preco no CoinGecko e este Worker, nunca o navegador de quem
// visita (a pagina so fala com o proprio site, pela Content Security Policy). As moedas sao
// as do retrato que o gerador grava no mesmo caminho na publicacao, tiradas do codigo do
// app. A resposta fica 60 s no cache da Cloudflare; se o CoinGecko nao responder, sai o
// retrato da publicacao, com a hora em que foi tirado. Nada de quem visita vai ao CoinGecko:
// o pedido sai com cabecalhos novos, sem cookie, IP ou endereco da pagina.
const DOMINIO = "escaliburwallet.com";
const COINGECKO = "https://api.coingecko.com/api/v3";
const PRECOS = "/precos.json";
const CACHE_VIVO = 60;      // segundos no cache da Cloudflare, com o preco do CoinGecko
const CACHE_RETRATO = 30;   // com o retrato, para tentar de novo logo
const CACHE_NAVEGADOR = 20; // no navegador

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    // www e o endereco do workers.dev levam ao dominio, no mesmo caminho. O localhost e o
    // wrangler dev, para testar.
    const local = url.hostname === "localhost" || url.hostname === "127.0.0.1";
    if (url.hostname !== DOMINIO && !local) {
      url.hostname = DOMINIO;
      url.protocol = "https:";
      return Response.redirect(url.toString(), 301);
    }
    let resposta;
    if (url.pathname === PRECOS) {
      resposta = await precos(request, env, ctx);
    } else {
      resposta = await env.ASSETS.fetch(request);
    }
    const cabecalhos = new Headers(resposta.headers);
    cabecalhos.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
    cabecalhos.set("X-Content-Type-Options", "nosniff");
    cabecalhos.set("X-Frame-Options", "DENY");
    cabecalhos.set("Referrer-Policy", "strict-origin-when-cross-origin");
    cabecalhos.set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()");
    return new Response(resposta.body, { status: resposta.status, statusText: resposta.statusText, headers: cabecalhos });
  },
};

async function precos(request, env, ctx) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response(null, { status: 405, headers: { Allow: "GET, HEAD" } });
  }
  // Um so cache para todo mundo: a chave nao leva nada do pedido de quem visita.
  const chave = new Request(`https://${DOMINIO}${PRECOS}?vivo`);
  const cache = caches.default;
  let guardada = await cache.match(chave);
  if (!guardada) {
    const { corpo, idade } = await montar(request, env);
    guardada = new Response(corpo, {
      headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": `public, max-age=${idade}` },
    });
    ctx.waitUntil(cache.put(chave, guardada.clone()));
  }
  const cabecalhos = new Headers(guardada.headers);
  cabecalhos.set("Cache-Control", `public, max-age=${CACHE_NAVEGADOR}`);
  return new Response(request.method === "HEAD" ? null : guardada.body, { status: 200, headers: cabecalhos });
}

async function montar(request, env) {
  // O retrato da publicacao: as moedas que a pagina mostra e o que sai se o CoinGecko falhar.
  let retrato = null;
  try {
    const estatico = await env.ASSETS.fetch(new Request(new URL(PRECOS, request.url)));
    if (estatico.ok) retrato = await estatico.json();
  } catch (erro) {
    retrato = null;
  }
  const valido = (id) => typeof id === "string" && /^[a-z0-9-]{1,64}$/.test(id);
  const ids = (retrato && Array.isArray(retrato.ids) ? retrato.ids.filter(valido) : []).slice(0, 60);
  const vitrine = (retrato && Array.isArray(retrato.vitrine) ? retrato.vitrine : []).filter((id) => ids.includes(id));
  const reserva = () => ({
    corpo: JSON.stringify(Object.assign({ hora: null, moedas: {}, ids, vitrine }, retrato || {}, { ao_vivo: false })),
    idade: CACHE_RETRATO,
  });
  if (!ids.length) return reserva();
  try {
    const cabecalhos = { Accept: "application/json", "User-Agent": "escaliburwallet.com (site)" };
    // Opcional: a chave gratuita "demo" do CoinGecko, num segredo do Worker, se o limite sem
    // chave apertar (wrangler secret put COINGECKO_CHAVE).
    if (env.COINGECKO_CHAVE) cabecalhos["x-cg-demo-api-key"] = env.COINGECKO_CHAVE;
    const [mercado, simples] = await Promise.all([
      vitrine.length
        ? buscar(`${COINGECKO}/coins/markets?vs_currency=usd&ids=${vitrine.join(",")}&sparkline=true&price_change_percentage=24h`, cabecalhos)
        : Promise.resolve([]),
      buscar(`${COINGECKO}/simple/price?ids=${ids.join(",")}&vs_currencies=usd,brl&include_24hr_change=true`, cabecalhos),
    ]);
    const linhas = {};
    if (Array.isArray(mercado)) {
      for (const m of mercado) {
        if (m && valido(m.id) && m.sparkline_in_7d && Array.isArray(m.sparkline_in_7d.price)) linhas[m.id] = amostra(m.sparkline_in_7d.price);
      }
    }
    const moedas = {};
    for (const id of ids) {
      const d = simples && simples[id];
      if (!d || numero(d.usd) === null) continue;
      const antiga = retrato && retrato.moedas && retrato.moedas[id];
      moedas[id] = {
        usd: numero(d.usd), brl: numero(d.brl), var: numero(d.usd_24h_change, 4), var_brl: numero(d.brl_24h_change, 4),
        linha: linhas[id] || (antiga && Array.isArray(antiga.linha) ? antiga.linha : []),
      };
    }
    if (!Object.keys(moedas).length) return reserva();
    const hora = new Date().toISOString().replace(/\.\d+Z$/, "Z");
    return { corpo: JSON.stringify({ hora, ao_vivo: true, fonte: "CoinGecko", ids, vitrine, moedas }), idade: CACHE_VIVO };
  } catch (erro) {
    return reserva();
  }
}

async function buscar(url, cabecalhos) {
  const resposta = await fetch(url, { headers: cabecalhos, signal: AbortSignal.timeout(6000) });
  if (!resposta.ok) throw new Error(`CoinGecko ${resposta.status}`);
  return resposta.json();
}

function numero(v, digitos = 8) {
  return typeof v === "number" && Number.isFinite(v) ? Number(v.toPrecision(digitos)) : null;
}

// A semana em 56 pontos, como o gerador faz no retrato.
function amostra(pontos, quantos = 56) {
  const limpos = pontos.filter((p) => typeof p === "number" && Number.isFinite(p));
  if (limpos.length <= quantos) return limpos.map((p) => numero(p, 6));
  const passo = (limpos.length - 1) / (quantos - 1);
  return Array.from({ length: quantos }, (_, i) => numero(limpos[Math.round(i * passo)], 6));
}
