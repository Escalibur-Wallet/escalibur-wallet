// O site da Escalibur Wallet em escaliburwallet.com: so os arquivos gerados pelo
// tools/gerar-site.py, servidos pela Cloudflare. O app da carteira nunca fala com este
// servidor (pedido do dono, 19/10/2026): a lista de versoes e a auditoria que o app abre
// vem do GitHub (escalibur-wallet.github.io).
const DOMINIO = "escaliburwallet.com";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // www e o endereco do workers.dev levam ao dominio, no mesmo caminho.
    if (url.hostname !== DOMINIO) {
      url.hostname = DOMINIO;
      url.protocol = "https:";
      return Response.redirect(url.toString(), 301);
    }
    const resposta = await env.ASSETS.fetch(request);
    const cabecalhos = new Headers(resposta.headers);
    cabecalhos.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
    cabecalhos.set("X-Content-Type-Options", "nosniff");
    cabecalhos.set("X-Frame-Options", "DENY");
    cabecalhos.set("Referrer-Policy", "strict-origin-when-cross-origin");
    cabecalhos.set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()");
    return new Response(resposta.body, { status: resposta.status, statusText: resposta.statusText, headers: cabecalhos });
  },
};
