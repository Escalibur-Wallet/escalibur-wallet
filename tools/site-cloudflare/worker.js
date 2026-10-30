// O site da Escalibur Wallet em escaliburwallet.com: os arquivos gerados pelo
// tools/gerar-site.py, servidos pela Cloudflare, e o /precos.json do Mercado ao vivo. O app
// da carteira nunca fala com este servidor (pedido do dono, 19/10/2026): a lista de versoes
// e a auditoria que o app abre vem do GitHub (escalibur-wallet.github.io).
//
// O /precos.json: quem busca o preco e este Worker, nunca o navegador de quem visita (a
// pagina so fala com o proprio site, pela Content Security Policy). As moedas sao as do
// retrato que o gerador grava no mesmo caminho na publicacao, tiradas do codigo do app. Duas
// fontes, sem chave, nesta ordem: o CoinGecko (preco, variacao e a semana) e o CoinPaprika
// (preco e variacao; a mesma reserva do app, com os mesmos ids). Se as duas falharem, sai o
// retrato da publicacao, com a hora em que foi tirado. Em `falhas`, so o motivo de cada
// fonte que falhou (o status HTTP ou "tempo", "vazio", "rede"), para conferir em producao:
// nada de quem visita. O pedido as fontes sai com cabecalhos novos, sem cookie, IP ou
// endereco da pagina. Tudo em dolar (pedido do dono, 23/10/2026).
const DOMINIO = "escaliburwallet.com";
const COINGECKO = "https://api.coingecko.com/api/v3";
const PRECOS = "/precos.json";
const PAPRIKA = "https://api.coinpaprika.com/v1";
const CACHE_VIVO = 60;      // segundos no cache da Cloudflare, com o preco ao vivo
const CACHE_RETRATO = 30;   // com o retrato, para tentar de novo logo
const CACHE_NAVEGADOR = 20; // no navegador

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    // www, http e o endereco do workers.dev levam ao dominio em https, no mesmo caminho. O
    // localhost e o wrangler dev, para testar.
    const local = url.hostname === "localhost" || url.hostname === "127.0.0.1";
    if ((url.hostname !== DOMINIO || url.protocol !== "https:") && !local) {
      url.hostname = DOMINIO;
      url.protocol = "https:";
      return Response.redirect(url.toString(), 301);
    }
    let resposta;
    let status;
    if (url.pathname === PRECOS) {
      resposta = await precos(request, env, ctx);
      status = resposta.status;
    } else {
      // O arquivo pelo caminho, sem a query (o ?v= do CSS e do JS so muda o endereco).
      const arquivo = new URL(url);
      arquivo.search = "";
      resposta = await env.ASSETS.fetch(new Request(arquivo, request));
      // A barra final (/seguranca -> /seguranca/) e permanente: 301 em vez do 307 dos arquivos.
      status = resposta.status === 307 ? 301 : resposta.status;
    }
    const cabecalhos = new Headers(resposta.headers);
    const guardar = url.pathname === PRECOS || status !== 200 ? null : cacheDe(url);
    if (guardar) cabecalhos.set("Cache-Control", guardar);
    cabecalhos.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
    cabecalhos.set("X-Content-Type-Options", "nosniff");
    cabecalhos.set("X-Frame-Options", "DENY");
    cabecalhos.set("Referrer-Policy", "strict-origin-when-cross-origin");
    cabecalhos.set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()");
    return new Response(resposta.body, { status, statusText: status === resposta.status ? resposta.statusText : "", headers: cabecalhos });
  },
};

// Quanto o navegador guarda cada arquivo. O CSS e o JS com ?v= (a versao no endereco, que muda
// com o arquivo): um ano. Fonte, imagem, video e icone: um dia, servindo o antigo enquanto
// confere. As paginas ficam como os arquivos da Cloudflare mandam (sempre conferir).
function cacheDe(url) {
  if (/\.(css|js)$/.test(url.pathname) && url.searchParams.has("v")) return "public, max-age=31536000, immutable";
  if (/^\/(fontes|midia|logos|selos)\//.test(url.pathname) || /^\/(icone(-\d+)?\.png|favicon\.ico|compartilhar\.jpg)$/.test(url.pathname)) {
    return "public, max-age=86400, stale-while-revalidate=604800";
  }
  return null;
}

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
  // O retrato da publicacao: as moedas que a pagina mostra, os ids do CoinPaprika e o que
  // sai se as duas fontes falharem.
  let retrato = null;
  try {
    const estatico = await env.ASSETS.fetch(new Request(new URL(PRECOS, request.url)));
    if (estatico.ok) retrato = await estatico.json();
  } catch (erro) {
    retrato = null;
  }
  const valido = (id) => typeof id === "string" && /^[a-z0-9-]{1,80}$/.test(id);
  const ids = (retrato && Array.isArray(retrato.ids) ? retrato.ids.filter(valido) : []).slice(0, 80);
  const vitrine = (retrato && Array.isArray(retrato.vitrine) ? retrato.vitrine : []).filter((id) => ids.includes(id));
  const paprika = {};
  if (retrato && retrato.paprika && typeof retrato.paprika === "object") {
    for (const id of ids) if (valido(retrato.paprika[id])) paprika[id] = retrato.paprika[id];
  }
  const antigas = (retrato && retrato.moedas) || {};
  const falhas = {};
  const reserva = () => ({
    corpo: JSON.stringify(Object.assign({ hora: null, moedas: {}, ids, vitrine }, retrato || {}, { ao_vivo: false, falhas })),
    idade: CACHE_RETRATO,
  });
  if (!ids.length) return reserva();
  const cabecalhos = { Accept: "application/json", "User-Agent": "escaliburwallet.com (site)" };

  // 1. CoinGecko: o preco, a variacao de 24 h e a semana.
  try {
    const gecko = Object.assign({}, cabecalhos);
    // Opcional: a chave gratuita "demo" do CoinGecko, num segredo do Worker
    // (wrangler secret put COINGECKO_CHAVE), se o limite sem chave apertar.
    if (env.COINGECKO_CHAVE) gecko["x-cg-demo-api-key"] = env.COINGECKO_CHAVE;
    const [mercado, simples] = await Promise.all([
      vitrine.length
        ? buscar(`${COINGECKO}/coins/markets?vs_currency=usd&ids=${vitrine.join(",")}&sparkline=true&price_change_percentage=24h`, gecko)
        : Promise.resolve([]),
      buscar(`${COINGECKO}/simple/price?ids=${ids.join(",")}&vs_currencies=usd&include_24hr_change=true`, gecko),
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
      moedas[id] = { usd: numero(d.usd), var: numero(d.usd_24h_change, 4), linha: linhas[id] || linhaAntiga(antigas[id]) };
    }
    if (Object.keys(moedas).length) {
      return vivo({ fonte: "CoinGecko", moedas, ids, vitrine, falhas, linha_hora: Object.keys(linhas).length ? agora() : (retrato && retrato.linha_hora) || null });
    }
    falhas.coingecko = "vazio";
  } catch (erro) {
    falhas.coingecko = motivo(erro);
  }

  // 2. CoinPaprika: a lista inteira numa chamada so, como o app faz com muitas moedas. Sem a
  // semana: o grafico fica o do retrato, com a hora dele.
  try {
    if (!Object.keys(paprika).length) throw new Error("vazio");
    const lista = await buscar(`${PAPRIKA}/tickers?quotes=USD`, cabecalhos);
    if (!Array.isArray(lista)) throw new Error("vazio");
    const porPaprika = {};
    for (const item of lista) if (item && valido(item.id)) porPaprika[item.id] = item;
    const moedas = {};
    for (const id of ids) {
      const item = paprika[id] && porPaprika[paprika[id]];
      const usd = item && item.quotes && item.quotes.USD;
      if (usd && numero(usd.price) !== null) {
        moedas[id] = { usd: numero(usd.price), var: numero(usd.percent_change_24h, 4), linha: linhaAntiga(antigas[id]) };
      } else if (antigas[id] && numero(antigas[id].usd) !== null) {
        // Moeda que o CoinPaprika nao tem (so na demonstracao da troca): o preco do retrato, marcado.
        moedas[id] = { usd: numero(antigas[id].usd), var: null, linha: linhaAntiga(antigas[id]), antigo: true };
      }
    }
    if (Object.keys(moedas).some((id) => !moedas[id].antigo)) {
      return vivo({ fonte: "CoinPaprika", moedas, ids, vitrine, falhas, linha_hora: (retrato && retrato.linha_hora) || null });
    }
    falhas.coinpaprika = "vazio";
  } catch (erro) {
    falhas.coinpaprika = motivo(erro);
  }
  return reserva();
}

function vivo(dados) {
  return { corpo: JSON.stringify(Object.assign({ hora: agora(), ao_vivo: true }, dados)), idade: CACHE_VIVO };
}

function agora() {
  return new Date().toISOString().replace(/\.\d+Z$/, "Z");
}

function linhaAntiga(antiga) {
  return antiga && Array.isArray(antiga.linha) ? antiga.linha : [];
}

// So o motivo, curto: o status HTTP, "tempo" (passou de 6 s), "rede" ou "vazio".
function motivo(erro) {
  if (erro && typeof erro.status === "number") return erro.status;
  if (erro && (erro.name === "TimeoutError" || erro.name === "AbortError")) return "tempo";
  if (erro && erro.message === "vazio") return "vazio";
  return "rede";
}

async function buscar(url, cabecalhos) {
  const resposta = await fetch(url, { headers: cabecalhos, signal: AbortSignal.timeout(6000) });
  if (!resposta.ok) {
    const erro = new Error("http");
    erro.status = resposta.status;
    throw erro;
  }
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
