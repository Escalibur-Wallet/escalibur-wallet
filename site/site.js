// O script do site, servido do proprio site (CSP script-src 'self'). Sem ele tudo continua
// legivel: os videos mostram a capa, as moedas ficam na imagem parada, a lista de precos
// mostra o retrato da publicacao, a lista de tokens aparece inteira e o menu do celular
// abre pelo <details>. Com ele: as animacoes de rolagem (so transform e opacity, num
// requestAnimationFrame so), os videos que tocam so quando aparecem, os precos ao vivo do
// /precos.json (do proprio site), a demonstracao da troca e, quando o aparelho aguenta, as
// moedas 3D (moedas3d.js, carregado depois). Com "reduzir movimento", nada se mexe sozinho.
(function () {
  "use strict";

  var raiz = document.documentElement;
  raiz.classList.add("js");
  var calmo = window.matchMedia ? window.matchMedia("(prefers-reduced-motion: reduce)") : { matches: false };
  var observa = "IntersectionObserver" in window;
  var movimento = !calmo.matches && observa;
  if (movimento) raiz.classList.add("movimento");
  var script = document.currentScript;
  var base = script && script.src ? script.src.replace(/site\.js(\?.*)?$/, "") : "";

  function limitar(v, a, b) { return v < a ? a : v > b ? b : v; }
  function suave(a, b, x) { var t = limitar((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); }
  function cada(seletor, fn, dentro) { Array.prototype.forEach.call((dentro || document).querySelectorAll(seletor), fn); }

  // MARK: Relogio: um requestAnimationFrame so para toda a pagina. Cada tarefa recebe o
  // estado do quadro (hora, rolagem, tamanho da janela) e diz se quer o proximo quadro.
  var tarefas = [];
  var pedido = false;
  function quadro(agora) {
    pedido = false;
    var estado = { t: agora / 1000, y: window.pageYOffset, vh: window.innerHeight, vw: window.innerWidth };
    var mais = false;
    for (var i = 0; i < tarefas.length; i++) {
      try { if (tarefas[i](estado)) mais = true; } catch (erro) { tarefas.splice(i--, 1); }
    }
    if (mais) pedir();
  }
  function pedir() {
    if (!pedido) { pedido = true; window.requestAnimationFrame(quadro); }
  }
  var aoMedir = [];
  window.EscaliburRelogio = {
    registrar: function (fn) { tarefas.push(fn); pedir(); },
    pedir: pedir,
    aoMedir: function (fn) { aoMedir.push(fn); },
  };
  window.addEventListener("scroll", pedir, { passive: true });
  var esperaMedir = 0;
  window.addEventListener("resize", function () {
    window.clearTimeout(esperaMedir);
    esperaMedir = window.setTimeout(function () { aoMedir.forEach(function (fn) { fn(); }); pedir(); }, 120);
  });

  // O topo ganha fundo quando a pagina rola.
  var rolou = false;
  window.EscaliburRelogio.registrar(function (e) {
    var agora = e.y > 8;
    if (agora !== rolou) { rolou = agora; raiz.classList.toggle("rolou", agora); }
    return false;
  });

  // MARK: Videos: tocam so quando aparecem (e param ao sair), cada um com botao de pausar.
  // Os da secao "Por dentro" (data-manual) sao do palco das telas, mais abaixo.
  var videos = Array.prototype.slice.call(document.querySelectorAll("video[data-auto]:not([data-manual])"));

  function botaoDe(video) {
    var aparelho = video.closest(".aparelho");
    return aparelho ? aparelho.querySelector(".pausar") : null;
  }
  function mostrar(botao, estado) {
    if (!botao) return;
    botao.setAttribute("data-estado", estado);
    botao.setAttribute("aria-label", estado === "pausado" ? "Tocar a animação" : "Pausar a animação");
  }
  function tocar(video, botao) {
    video.muted = true;
    if (video.preload !== "auto") video.preload = "auto";
    var promessa = video.play();
    mostrar(botao, "tocando");
    if (promessa && promessa.catch) promessa.catch(function () { mostrar(botao, "pausado"); });
  }
  function prepararVideo(video) {
    video.addEventListener("playing", function () { video.classList.add("visivel"); });
  }

  videos.forEach(function (video) {
    var botao = botaoDe(video);
    mostrar(botao, "pausado");
    prepararVideo(video);
    if (!botao) return;
    botao.addEventListener("click", function () {
      if (video.paused) { video.removeAttribute("data-parado"); tocar(video, botao); }
      else { video.setAttribute("data-parado", ""); video.pause(); mostrar(botao, "pausado"); }
    });
  });
  if (movimento) {
    var observadorVideo = new IntersectionObserver(function (entradas) {
      entradas.forEach(function (entrada) {
        var video = entrada.target, botao = botaoDe(video);
        if (entrada.isIntersecting && entrada.intersectionRatio >= 0.35) {
          if (!video.hasAttribute("data-parado") && video.paused) tocar(video, botao);
        } else if (!video.paused) {
          video.pause();
          if (!video.hasAttribute("data-parado")) mostrar(botao, "pausado");
        }
      });
    }, { threshold: [0, 0.35, 0.7] });
    videos.forEach(function (video) { observadorVideo.observe(video); });
  }

  // MARK: Revelar ao rolar
  if (movimento) {
    var revelar = new IntersectionObserver(function (entradas) {
      entradas.forEach(function (entrada) {
        if (entrada.isIntersecting) { entrada.target.classList.add("visivel"); revelar.unobserve(entrada.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    cada("[data-revelar]", function (el) { revelar.observe(el); });
  }

  // MARK: Abertura: o palco fica fixo; o titulo sobe e some, o iPhone sobe ate o meio e a
  // legenda aparece. As moedas 3D leem o mesmo progresso (window.EscaliburAbertura).
  var abertura = document.querySelector(".abertura");
  if (abertura && movimento) {
    var palco = abertura.querySelector(".abertura-palco");
    var texto = abertura.querySelector(".abertura-texto");
    var aparelhoAbertura = abertura.querySelector(".abertura-aparelho");
    var telaAbertura = aparelhoAbertura.querySelector(".tela");
    var legenda = abertura.querySelector(".abertura-legenda");
    var medida = null, ultimo = -1;
    var medirAbertura = function () {
      aparelhoAbertura.style.transform = "";
      var rp = palco.getBoundingClientRect(), ra = aparelhoAbertura.getBoundingClientRect();
      var largo = window.innerWidth >= 900;
      var alturaPalco = rp.height;
      var destino = largo ? (alturaPalco - ra.height) / 2 : Math.max(alturaPalco - ra.height - 28, (alturaPalco - ra.height) / 2 + 40);
      medida = {
        inicio: abertura.getBoundingClientRect().top + window.pageYOffset,
        alcance: Math.max(1, abertura.offsetHeight - alturaPalco),
        sobe: destino - (ra.top - rp.top),
      };
      ultimo = -1;
    };
    medirAbertura();
    window.EscaliburRelogio.aoMedir(medirAbertura);
    window.addEventListener("load", function () { medirAbertura(); pedir(); });
    window.EscaliburAbertura = {
      p: 0,
      palco: palco,
      tela: function () { return telaAbertura.getBoundingClientRect(); },
    };
    window.EscaliburRelogio.registrar(function (e) {
      var p = limitar((e.y - medida.inicio) / medida.alcance, 0, 1);
      if (p === ultimo) return false;
      ultimo = p;
      window.EscaliburAbertura.p = p;
      var a = suave(0, 0.3, p);
      texto.style.transform = "translate3d(0," + (-a * 110).toFixed(1) + "px,0) scale(" + (1 - a * 0.05).toFixed(4) + ")";
      texto.style.opacity = (1 - a).toFixed(3);
      texto.style.visibility = a >= 1 ? "hidden" : "";
      var b = suave(0.06, 0.48, p);
      aparelhoAbertura.style.transform = "translate3d(0," + (medida.sobe * b).toFixed(1) + "px,0) scale(" + (0.92 + 0.08 * b).toFixed(4) + ")";
      var c = suave(0.72, 0.88, p);
      legenda.style.opacity = c.toFixed(3);
      var largo = e.vw >= 900;
      legenda.style.transform = (largo ? "translate3d(0,calc(-50% + " : "translate3d(0,") + ((1 - c) * 24).toFixed(1) + "px" + (largo ? ")" : "") + ",0)";
      return false;
    });
  }

  // MARK: Manifesto: as palavras acendem, uma a uma, conforme o paragrafo passa pela tela.
  var manifesto = document.querySelector("[data-palavras]");
  if (manifesto && movimento) {
    var inteiro = manifesto.textContent.trim();
    var palavras = inteiro.split(/\s+/);
    manifesto.textContent = "";
    // O leitor de tela le a frase inteira; as palavras soltas sao so o desenho.
    var leitor = document.createElement("span");
    leitor.className = "so-leitor";
    leitor.textContent = inteiro;
    manifesto.appendChild(leitor);
    var spans = palavras.map(function (palavra, i) {
      var s = document.createElement("span");
      s.className = "palavra";
      s.setAttribute("aria-hidden", "true");
      s.textContent = palavra;
      manifesto.appendChild(s);
      if (i < palavras.length - 1) manifesto.appendChild(document.createTextNode(" "));
      return s;
    });
    var ultimoManifesto = -1;
    window.EscaliburRelogio.registrar(function (e) {
      var r = manifesto.getBoundingClientRect();
      if (r.bottom < -e.vh || r.top > e.vh * 2) return false;
      var p = limitar((e.vh * 0.88 - r.top) / (e.vh * 0.5 + r.height * 0.6), 0, 1);
      var passo = Math.round(p * 400);
      if (passo === ultimoManifesto) return false;
      ultimoManifesto = passo;
      var n = spans.length;
      for (var i = 0; i < n; i++) {
        var o = 0.22 + 0.78 * limitar(p * (n + 3) - i, 0, 1);
        spans[i].style.opacity = o.toFixed(3);
      }
      return false;
    });
  }

  // MARK: A cadeia do PIN acende degrau por degrau.
  if (movimento) {
    var degraus = document.querySelectorAll(".cadeia-acende li");
    if (degraus.length) {
      var observadorCadeia = new IntersectionObserver(function (entradas) {
        entradas.forEach(function (entrada) { entrada.target.classList.toggle("aceso", entrada.isIntersecting || entrada.boundingClientRect.top < 0); });
      }, { rootMargin: "0px 0px -35% 0px", threshold: 0 });
      Array.prototype.forEach.call(degraus, function (li) { observadorCadeia.observe(li); });
    }
  }

  // MARK: Por dentro do app: o iPhone fica fixo e a tela troca a cada passo.
  var palcoTelas = document.querySelector(".palco-telas");
  if (palcoTelas && observa) {
    var camadas = Array.prototype.slice.call(palcoTelas.querySelectorAll(".camada"));
    var passos = Array.prototype.slice.call(document.querySelectorAll(".passo-tela"));
    var botaoTelas = palcoTelas.querySelector(".pausar");
    var pausadoPeloDono = calmo.matches;
    var ativa = null;
    var noPalco = false;
    var videoDe = function (camada) { return camada.querySelector("video"); };
    camadas.forEach(function (camada) { prepararVideo(videoDe(camada)); });
    var atualizarVideo = function () {
      camadas.forEach(function (camada) {
        var v = videoDe(camada);
        if (camada === ativa && noPalco && !pausadoPeloDono) { if (v.paused) tocar(v, botaoTelas); }
        else if (!v.paused) v.pause();
      });
      if (pausadoPeloDono || !noPalco) mostrar(botaoTelas, "pausado");
    };
    var ativar = function (cena) {
      var nova = null;
      camadas.forEach(function (camada) {
        var sim = camada.getAttribute("data-cena") === cena;
        camada.classList.toggle("ativa", sim);
        if (sim) nova = camada;
      });
      passos.forEach(function (passo) { passo.classList.toggle("ativo", passo.getAttribute("data-cena") === cena); });
      if (nova !== ativa) {
        if (ativa) { var antigo = videoDe(ativa); antigo.pause(); antigo.classList.remove("visivel"); }
        ativa = nova;
        if (ativa) { var v = videoDe(ativa); try { v.currentTime = 0; } catch (erro) { /* ainda sem dados */ } }
      }
      atualizarVideo();
    };
    // O passo acende quando o texto dele passa pelo meio da tela (no celular, pela faixa
    // embaixo do iPhone).
    var observadorPassos = new IntersectionObserver(function (entradas) {
      entradas.forEach(function (entrada) {
        if (entrada.isIntersecting) ativar(entrada.target.closest(".passo-tela").getAttribute("data-cena"));
      });
    }, { rootMargin: window.innerWidth >= 700 ? "-45% 0px -45% 0px" : "-62% 0px -30% 0px", threshold: 0 });
    passos.forEach(function (passo) { observadorPassos.observe(passo.querySelector(".passo-texto") || passo); });
    new IntersectionObserver(function (entradas) {
      noPalco = entradas[0].isIntersecting;
      atualizarVideo();
    }, { threshold: 0.4 }).observe(palcoTelas);
    if (botaoTelas) {
      mostrar(botaoTelas, "pausado");
      botaoTelas.addEventListener("click", function () {
        pausadoPeloDono = !pausadoPeloDono;
        atualizarVideo();
      });
    }
    ativa = camadas[0] || null;
  }

  // MARK: Numeros, como o app: pt-BR, R$ ou US$.
  function casasDoPreco(v) { return v >= 1 ? 2 : v >= 0.01 ? 4 : 6; }
  var formatos = {};
  function formato(chave, opcoes) {
    if (!formatos[chave]) formatos[chave] = new Intl.NumberFormat("pt-BR", opcoes);
    return formatos[chave];
  }
  function dinheiro(v, fiat) {
    if (v == null || !isFinite(v)) return "";
    var c = casasDoPreco(Math.abs(v));
    return formato(fiat + c, { style: "currency", currency: fiat === "usd" ? "USD" : "BRL", minimumFractionDigits: c, maximumFractionDigits: c }).format(v);
  }
  function quantidade(v) {
    if (v == null || !isFinite(v)) return "";
    var a = Math.abs(v);
    var c = a >= 1000 ? 2 : a >= 1 ? 4 : a >= 0.0001 ? 6 : 8;
    return formato("q" + c, { minimumFractionDigits: 0, maximumFractionDigits: c }).format(v);
  }
  function porcento(v) { return formato("pct", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Math.abs(v)) + "%"; }
  function lerValor(texto) {
    var t = String(texto || "").replace(/\s/g, "");
    if (t.indexOf(",") >= 0) t = t.replace(/\./g, "").replace(",", ".");
    var n = parseFloat(t.replace(/[^0-9.]/g, ""));
    return isFinite(n) ? n : 0;
  }
  var SVG = "http://www.w3.org/2000/svg";
  function seta(estado) {
    if (estado === "estavel") return null;
    var svg = document.createElementNS(SVG, "svg");
    svg.setAttribute("viewBox", "0 0 8 8");
    svg.setAttribute("aria-hidden", "true");
    var p = document.createElementNS(SVG, "path");
    p.setAttribute("d", estado === "alta" ? "M4 1.2 7.2 6.4H.8Z" : "M4 6.8.8 1.6h6.4Z");
    svg.appendChild(p);
    return svg;
  }
  function pintarVariacao(el, v) {
    el.textContent = "";
    el.className = "variacao";
    if (v == null || !isFinite(v)) { el.removeAttribute("aria-label"); return; }
    var estado = v > 0.004 ? "alta" : v < -0.004 ? "baixa" : "estavel";
    el.classList.add(estado);
    var s = seta(estado);
    if (s) el.appendChild(s);
    var n = document.createElement("span");
    n.textContent = porcento(v);
    el.appendChild(n);
    el.setAttribute("aria-label", (estado === "alta" ? "Subiu " : estado === "baixa" ? "Caiu " : "Estável, ") + porcento(v));
  }
  function caminhoLinha(pontos, w, h, folga) {
    if (!pontos || pontos.length < 2) return "";
    var menor = Infinity, maior = -Infinity;
    pontos.forEach(function (p) { if (p < menor) menor = p; if (p > maior) maior = p; });
    var faixa = (maior - menor) || 1, passo = w / (pontos.length - 1);
    return pontos.map(function (p, i) {
      return (i ? "L" : "M") + (i * passo).toFixed(1) + " " + (h - folga - ((p - menor) / faixa) * (h - folga * 2)).toFixed(1);
    }).join(" ");
  }

  // MARK: Mercado ao vivo. O /precos.json e do proprio site: no dominio, o Worker busca no
  // CoinGecko pelo servidor (cache de 60 s); no endereco antigo, sem Worker, e o retrato da
  // publicacao. O navegador de quem visita nao fala com mais ninguem.
  var precos = null;
  var fiat = "brl";
  var escolhida = "bitcoin";
  var ouvintesPreco = [];
  var lista = document.getElementById("cotacoes");
  var estadoPrecos = document.getElementById("estado-precos");

  function valorEm(id, moeda) {
    var d = precos && precos.moedas && precos.moedas[id];
    if (!d) return null;
    return moeda === "usd" ? d.usd : (d.brl != null ? d.brl : null);
  }
  function variacaoDe(id) {
    var d = precos && precos.moedas && precos.moedas[id];
    if (!d) return null;
    return fiat === "usd" ? d["var"] : (d.var_brl != null ? d.var_brl : d["var"]);
  }
  function horaCurta(iso) {
    var d = new Date(iso);
    if (isNaN(d)) return "";
    return d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
  }
  function diaCurto(iso) {
    var d = new Date(iso);
    if (isNaN(d)) return "";
    return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
  }
  function pintarEstado() {
    if (!estadoPrecos) return;
    var texto = estadoPrecos.querySelector("[data-estado]");
    var vivo = !!(precos && precos.ao_vivo);
    estadoPrecos.classList.toggle("ao-vivo", vivo);
    if (precos && precos.hora && Object.keys(precos.moedas || {}).length) {
      texto.textContent = vivo ? "Ao vivo, atualizado às " + horaCurta(precos.hora)
        : "Preços de " + diaCurto(precos.hora) + " às " + horaCurta(precos.hora) + ", da publicação do site";
    } else {
      texto.textContent = "Os preços aparecem quando o servidor responde.";
    }
  }
  function pintarLista() {
    if (!lista) return;
    cada(".cotacao", function (botao) {
      var id = botao.getAttribute("data-moeda");
      var preco = botao.querySelector("[data-preco]");
      var novo = dinheiro(valorEm(id, fiat), fiat);
      if (preco.textContent !== novo) {
        if (preco.textContent) { preco.classList.add("mudou"); window.setTimeout(function () { preco.classList.remove("mudou"); }, 30); }
        preco.textContent = novo;
      }
      pintarVariacao(botao.querySelector("[data-variacao]"), variacaoDe(id));
      var d = precos && precos.moedas && precos.moedas[id];
      var faisca = botao.querySelector(".faisca");
      if (faisca && d && d.linha && d.linha.length > 1) {
        var sobe = d.linha[d.linha.length - 1] >= d.linha[0];
        faisca.setAttribute("class", "faisca " + (sobe ? "alta" : "baixa"));
        faisca.querySelector("path").setAttribute("d", caminhoLinha(d.linha, 120, 36, 2));
      }
    }, lista);
    pintarDestaque();
  }
  function pintarDestaque() {
    var destaque = document.querySelector(".destaque");
    if (!destaque || !lista) return;
    var botao = lista.querySelector('[data-moeda="' + escolhida + '"]');
    if (!botao) return;
    destaque.querySelector("[data-destaque-simbolo]").textContent = botao.getAttribute("data-simbolo");
    destaque.querySelector("[data-destaque-nome]").textContent = botao.getAttribute("data-nome");
    destaque.querySelector("[data-destaque-preco]").textContent = dinheiro(valorEm(escolhida, fiat), fiat);
    pintarVariacao(destaque.querySelector("[data-destaque-variacao]"), variacaoDe(escolhida));
    var logo = destaque.querySelector(".destaque-logo");
    var img = botao.querySelector(".logo img");
    if (img) {
      var atual = logo.querySelector("img") || document.createElement("img");
      atual.src = img.getAttribute("src");
      atual.alt = "";
      if (!atual.parentNode) logo.appendChild(atual);
    }
    var grafico = destaque.querySelector(".destaque-grafico");
    var d = precos && precos.moedas && precos.moedas[escolhida];
    var traco = grafico.querySelector(".traco"), area = grafico.querySelector(".area");
    if (d && d.linha && d.linha.length > 1) {
      var caminho = caminhoLinha(d.linha, 600, 180, 10);
      traco.setAttribute("d", caminho);
      area.setAttribute("d", caminho + " L600 180 L0 180 Z");
      grafico.classList.toggle("baixa", d.linha[d.linha.length - 1] < d.linha[0]);
      pintarVariacao(destaque.querySelector("[data-destaque-semana]"), (d.linha[d.linha.length - 1] / d.linha[0] - 1) * 100);
    } else {
      traco.setAttribute("d", "");
      area.setAttribute("d", "");
      pintarVariacao(destaque.querySelector("[data-destaque-semana]"), null);
    }
  }
  function aplicarPrecos(dados) {
    if (!dados || typeof dados !== "object" || !dados.moedas) return;
    // Uma resposta sem preco nenhum nao apaga o que ja estava na tela.
    if (precos && Object.keys(dados.moedas).length === 0) return;
    precos = dados;
    pintarEstado();
    pintarLista();
    ouvintesPreco.forEach(function (fn) { fn(); });
  }
  var buscando = false;
  function buscarPrecos() {
    if (buscando || !window.fetch) return;
    buscando = true;
    window.fetch(base + "precos.json", { credentials: "omit", headers: { Accept: "application/json" } })
      .then(function (r) { if (!r.ok) throw new Error(String(r.status)); return r.json(); })
      .then(aplicarPrecos)
      .catch(function () { pintarEstado(); })
      .then(function () { buscando = false; });
  }
  var mercadoVisivel = false;
  if (lista) {
    cada(".cotacao", function (botao) {
      botao.addEventListener("click", function () {
        escolhida = botao.getAttribute("data-moeda");
        cada(".cotacao", function (b) { b.setAttribute("aria-pressed", String(b === botao)); }, lista);
        pintarDestaque();
        document.dispatchEvent(new CustomEvent("escalibur:moeda", { detail: { id: escolhida } }));
      });
    }, lista);
    cada("[data-fiat]", function (botao) {
      botao.addEventListener("click", function () {
        fiat = botao.getAttribute("data-fiat");
        cada("[data-fiat]", function (b) { b.setAttribute("aria-pressed", String(b === botao)); });
        pintarLista();
        ouvintesPreco.forEach(function (fn) { fn(); });
      });
    });
    pintarDestaque();
    buscarPrecos();
    if (observa) {
      new IntersectionObserver(function (entradas) { mercadoVisivel = entradas[0].isIntersecting; }, { rootMargin: "200px" })
        .observe(document.getElementById("mercado") || lista);
    }
    // Ao vivo, de minuto em minuto, so com a pagina na frente e o mercado (ou a troca) na tela.
    window.setInterval(function () {
      if (document.hidden || !precos || !precos.ao_vivo) return;
      if (!mercadoVisivel && !trocaVisivel) return;
      buscarPrecos();
    }, 60000);
  }
  window.EscaliburPrecos = { atual: function () { return escolhida; } };

  // MARK: Seletor: um botao com a ficha (logo e nome) e a lista que abre embaixo. Teclado:
  // setas, Home e End na lista, Enter ou espaco escolhe, Esc fecha.
  var abertos = [];
  function Escolha(el, rotulo) {
    this.el = el;
    this.rotulo = rotulo;
    this.opcoes = [];
    this.valor = null;
    this.botao = document.createElement("button");
    this.botao.type = "button";
    this.botao.className = "ficha";
    this.botao.setAttribute("aria-haspopup", "listbox");
    this.botao.setAttribute("aria-expanded", "false");
    this.menu = document.createElement("div");
    this.menu.className = "menu";
    this.menu.setAttribute("role", "listbox");
    this.menu.setAttribute("aria-label", rotulo);
    this.menu.id = "menu-" + Math.random().toString(36).slice(2, 9);
    this.botao.setAttribute("aria-controls", this.menu.id);
    el.appendChild(this.botao);
    el.appendChild(this.menu);
    var self = this;
    this.botao.addEventListener("click", function () { self.alternar(); });
    this.botao.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); self.abrir(); }
    });
    this.menu.addEventListener("keydown", function (e) {
      var itens = Array.prototype.slice.call(self.menu.querySelectorAll(".opcao-menu"));
      var i = itens.indexOf(document.activeElement);
      if (e.key === "ArrowDown") { e.preventDefault(); itens[Math.min(itens.length - 1, i + 1)].focus(); }
      else if (e.key === "ArrowUp") { e.preventDefault(); itens[Math.max(0, i - 1)].focus(); }
      else if (e.key === "Home") { e.preventDefault(); itens[0].focus(); }
      else if (e.key === "End") { e.preventDefault(); itens[itens.length - 1].focus(); }
      else if (e.key === "Escape") { e.preventDefault(); self.fechar(true); }
      else if (e.key === "Tab") { self.fechar(false); }
    });
  }
  Escolha.prototype.definir = function (opcoes, valor) {
    this.opcoes = opcoes;
    this.valor = valor;
    var atual = opcoes.filter(function (o) { return o.id === valor; })[0] || opcoes[0];
    this.botao.textContent = "";
    if (atual) {
      if (atual.logo) { var img = document.createElement("img"); img.src = atual.logo; img.alt = ""; img.width = 30; img.height = 30; this.botao.appendChild(img); }
      var span = document.createElement("span"); span.textContent = atual.nome; this.botao.appendChild(span);
      this.botao.setAttribute("aria-label", this.rotulo + ": " + (atual.longo || atual.nome) + ". Trocar");
    }
    this.botao.disabled = opcoes.length < 2;
  };
  Escolha.prototype.montarMenu = function () {
    var self = this;
    this.menu.textContent = "";
    this.opcoes.forEach(function (o) {
      var item = document.createElement("button");
      item.type = "button";
      item.className = "opcao-menu";
      item.setAttribute("role", "option");
      item.setAttribute("aria-selected", String(o.id === self.valor));
      if (o.logo) { var img = document.createElement("img"); img.src = o.logo; img.alt = ""; img.width = 30; img.height = 30; item.appendChild(img); }
      var texto = document.createElement("span");
      texto.textContent = o.nome;
      if (o.detalhe) { var s = document.createElement("small"); s.textContent = o.detalhe; texto.appendChild(s); }
      item.appendChild(texto);
      item.addEventListener("click", function () { self.fechar(true); if (self.aoEscolher) self.aoEscolher(o.id); });
      self.menu.appendChild(item);
    });
  };
  Escolha.prototype.abrir = function () {
    abertos.slice().forEach(function (outro) { outro.fechar(false); });
    this.montarMenu();
    this.menu.classList.add("aberto");
    this.botao.setAttribute("aria-expanded", "true");
    abertos.push(this);
    var marcado = this.menu.querySelector('[aria-selected="true"]') || this.menu.querySelector(".opcao-menu");
    if (marcado) marcado.focus();
  };
  Escolha.prototype.fechar = function (devolverFoco) {
    if (!this.menu.classList.contains("aberto")) return;
    this.menu.classList.remove("aberto");
    this.botao.setAttribute("aria-expanded", "false");
    abertos = abertos.filter(function (a) { return a !== this; }, this);
    if (devolverFoco) this.botao.focus();
  };
  Escolha.prototype.alternar = function () {
    if (this.menu.classList.contains("aberto")) this.fechar(true); else this.abrir();
  };
  document.addEventListener("click", function (e) {
    abertos.slice().forEach(function (a) { if (!a.el.contains(e.target)) a.fechar(false); });
  });

  // MARK: A demonstracao da troca e da ponte. Os dados (redes com troca, tokens conferidos
  // e rotas da ponte) vem do codigo do app, no build (tools/gerador_site). A conta e so o
  // preco de mercado: nenhum agregador e chamado.
  var painel = document.getElementById("painel-troca");
  var trocaVisivel = false;
  if (painel) {
    var cfg = null;
    try { cfg = JSON.parse(painel.getAttribute("data-troca")); } catch (erro) { cfg = null; }
    if (cfg && cfg.redes && cfg.redes.length) iniciarTroca(cfg);
    if (observa) {
      new IntersectionObserver(function (entradas) { trocaVisivel = entradas[0].isIntersecting; }, { rootMargin: "200px" }).observe(painel);
    }
  }

  function iniciarTroca(cfg) {
    var estado = { rede: cfg.redes[0].id, de: cfg.redes[0].moedas[0].id, para: cfg.redes[0].moedas[1].id };
    var ponte = { ativo: "usdc", origem: null, destino: null };
    var campo = document.getElementById("troca-valor");
    var resultado = document.getElementById("troca-resultado");
    var campoPonte = document.getElementById("ponte-valor");
    var q = function (s) { return painel.querySelector(s); };
    var seletores = {};
    cada(".escolha", function (el) {
      var rotuloId = el.getAttribute("data-rotulo");
      var rotulo = el.getAttribute("data-rotulo-texto") || (rotuloId ? document.getElementById(rotuloId).textContent : "Escolher");
      seletores[el.getAttribute("data-escolha")] = new Escolha(el, rotulo);
    }, painel);
    var redeAtual = function () { return cfg.redes.filter(function (r) { return r.id === estado.rede; })[0]; };
    var moeda = function (id) { return redeAtual().moedas.filter(function (m) { return m.id === id; })[0]; };
    var PROVEDORES = {
      evm: "Quem cota: os agregadores e protocolos conferidos nesta rede. O app compara as cotações e mostra a melhor.",
      solana: "Quem cota: a Jupiter, com a rota montada no próprio celular.",
      xrpl: "Quem cota: o livro de ofertas do próprio XRP Ledger, lido em dois servidores.",
      stellar: "Quem cota: a própria Stellar, nas duas Horizons, com rota só por XLM e ativos da lista.",
    };
    var ROTAS = {
      cctp: "Rota: CCTP da Circle, na rápida ou na padrão.",
      across: "Rota: Across.",
      usdt0: "Rota: USDT0 da Tether.",
    };
    var paraOpcao = function (m) { return { id: m.id, nome: m.s, longo: m.n, detalhe: m.n, logo: m.l }; };

    function contaTroca() {
      var rede = redeAtual();
      seletores.rede.definir(cfg.redes.map(function (r) { return { id: r.id, nome: r.nome, logo: r.l }; }), rede.id);
      seletores.de.definir(rede.moedas.map(paraOpcao), estado.de);
      seletores.para.definir(rede.moedas.filter(function (m) { return m.id !== estado.de; }).map(paraOpcao), estado.para);
      var de = moeda(estado.de), para = moeda(estado.para);
      var valor = lerValor(campo.value);
      var pd = valorEm(de.id, "usd"), pp = valorEm(para.id, "usd");
      var cambio = q("[data-cambio]");
      if (pd && pp) {
        resultado.textContent = valor ? quantidade(valor * pd / pp) : "0";
        cambio.textContent = "1 " + de.s + " ≈ " + quantidade(pd / pp) + " " + para.s;
        q("[data-fiat-de]").textContent = valor ? "≈ " + dinheiro(valor * valorEm(de.id, fiat), fiat) : "";
        q("[data-fiat-para]").textContent = valor ? "≈ " + dinheiro(valor * pd / pp * valorEm(para.id, fiat), fiat) : "";
      } else {
        resultado.textContent = "";
        cambio.textContent = "Sem preço de mercado agora. No app, a cotação vem dos protocolos.";
        q("[data-fiat-de]").textContent = "";
        q("[data-fiat-para]").textContent = "";
      }
      q("[data-provedores]").textContent = PROVEDORES[rede.familia] || PROVEDORES.evm;
    }

    function rotasDe(ativo) { return (cfg.ponte.rotas[ativo] || []); }
    function redePonte(id) { return cfg.ponte.redes.filter(function (r) { return r.id === id; })[0]; }
    function contaPonte() {
      var rotas = rotasDe(ponte.ativo);
      var origens = [];
      rotas.forEach(function (r) { if (origens.indexOf(r[0]) < 0) origens.push(r[0]); });
      if (origens.indexOf(ponte.origem) < 0) ponte.origem = origens.indexOf("base") >= 0 ? "base" : origens[0];
      var destinos = rotas.filter(function (r) { return r[0] === ponte.origem; }).map(function (r) { return r[1]; });
      if (destinos.indexOf(ponte.destino) < 0) ponte.destino = destinos.indexOf("arbitrum") >= 0 ? "arbitrum" : destinos[0];
      var ativo = cfg.ponte.ativos.filter(function (a) { return a.id === ponte.ativo; })[0];
      seletores.ativo.definir(cfg.ponte.ativos.map(function (a) { return { id: a.id, nome: a.s, logo: a.l }; }), ponte.ativo);
      var opcaoRede = function (id) { var r = redePonte(id); return { id: id, nome: r ? r.nome : id, logo: r ? r.l : "" }; };
      seletores.origem.definir(origens.map(opcaoRede), ponte.origem);
      seletores.destino.definir(destinos.map(opcaoRede), ponte.destino);
      var rota = rotas.filter(function (r) { return r[0] === ponte.origem && r[1] === ponte.destino; })[0];
      var valor = lerValor(campoPonte.value);
      q("[data-ponte-simbolo]").textContent = ativo.s;
      var preco = valorEm(ativo.g, fiat);
      q("[data-fiat-ponte]").textContent = valor && preco ? "≈ " + dinheiro(valor * preco, fiat) : "";
      q("[data-rota]").textContent = (rota ? ROTAS[rota[2]] : "") + (valor ? " Chega cerca de " + quantidade(valor) + " " + ativo.s + ", menos a taxa da rota." : "");
    }

    seletores.rede.aoEscolher = function (id) {
      estado.rede = id;
      var rede = redeAtual();
      estado.de = rede.moedas[0].id;
      estado.para = rede.moedas[1].id;
      contaTroca();
    };
    seletores.de.aoEscolher = function (id) {
      if (id === estado.para) estado.para = estado.de;
      estado.de = id;
      if (estado.para === estado.de) estado.para = redeAtual().moedas.filter(function (m) { return m.id !== id; })[0].id;
      contaTroca();
    };
    seletores.para.aoEscolher = function (id) { estado.para = id; contaTroca(); };
    seletores.ativo.aoEscolher = function (id) { ponte.ativo = id; contaPonte(); };
    seletores.origem.aoEscolher = function (id) { ponte.origem = id; contaPonte(); };
    seletores.destino.aoEscolher = function (id) { ponte.destino = id; contaPonte(); };
    campo.addEventListener("input", contaTroca);
    campoPonte.addEventListener("input", contaPonte);
    var inverter = q(".inverter");
    inverter.addEventListener("click", function () {
      var de = estado.de;
      estado.de = estado.para;
      estado.para = de;
      inverter.classList.toggle("girou");
      contaTroca();
    });
    // As abas: setas trocam, como num tablist.
    var abas = Array.prototype.slice.call(painel.querySelectorAll('[role="tab"]'));
    var escolherAba = function (aba, foco) {
      abas.forEach(function (a) {
        var sim = a === aba;
        a.setAttribute("aria-selected", String(sim));
        a.tabIndex = sim ? 0 : -1;
        document.getElementById(a.getAttribute("aria-controls")).hidden = !sim;
      });
      if (foco) aba.focus();
      painel.querySelector(".painel-acao").textContent = aba.id === "aba-ponte" ? "Mandar pela ponte no app" : "Trocar no app";
    };
    abas.forEach(function (aba, i) {
      aba.addEventListener("click", function () { escolherAba(aba, false); });
      aba.addEventListener("keydown", function (e) {
        if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
          e.preventDefault();
          escolherAba(abas[(i + (e.key === "ArrowRight" ? 1 : abas.length - 1)) % abas.length], true);
        }
      });
    });
    ouvintesPreco.push(function () { contaTroca(); contaPonte(); });
    contaTroca();
    contaPonte();
  }

  // MARK: As moedas 3D: so com movimento, sem economia de dados e em aparelho que aguenta.
  // O moedas3d.js chega depois da pagina, e se o WebGL faltar, a imagem parada fica.
  function pode3D() {
    if (!movimento) return false;
    var conexao = navigator.connection;
    if (conexao && (conexao.saveData || /(^|-)2g$/.test(conexao.effectiveType || ""))) return false;
    if (navigator.deviceMemory && navigator.deviceMemory < 3) return false;
    if (navigator.hardwareConcurrency && navigator.hardwareConcurrency < 4) return false;
    return !!window.WebGLRenderingContext;
  }
  if (pode3D() && document.querySelector(".abertura-3d, .destaque-3d, .final-3d")) {
    var carregar3D = function () {
      var s = document.createElement("script");
      s.src = base + "moedas3d.js";
      s.async = true;
      document.head.appendChild(s);
    };
    var depois = function () {
      if (window.requestIdleCallback) window.requestIdleCallback(carregar3D, { timeout: 1200 });
      else window.setTimeout(carregar3D, 200);
    };
    if (document.readyState === "complete") depois(); else window.addEventListener("load", depois);
  }
  calmo.addEventListener && calmo.addEventListener("change", function () { if (calmo.matches) document.dispatchEvent(new CustomEvent("escalibur:calmo")); });

  // MARK: Busca na lista de tokens (redes/): por simbolo, nome ou rede.
  var campoBusca = document.getElementById("busca-token");
  if (campoBusca) {
    var itens = Array.prototype.slice.call(document.querySelectorAll("[data-busca]"));
    var vazio = document.getElementById("busca-vazia");
    var normalizar = function (texto) {
      return texto.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
    };
    campoBusca.addEventListener("input", function () {
      var termo = normalizar(campoBusca.value);
      var achados = 0;
      itens.forEach(function (item) {
        var mostra = !termo || item.getAttribute("data-busca").indexOf(termo) >= 0;
        item.hidden = !mostra;
        if (mostra) achados += 1;
      });
      if (vazio) vazio.hidden = achados > 0;
    });
  }

  // MARK: Suporte: o questionario do app (assunto, rede, o que aconteceu, e-mail duas vezes)
  // vira um e-mail pronto no app de e-mail de quem escreve. O site nao manda nada sozinho.
  // Texto com seis palavras BIP-39 seguidas nao sai, como no app.
  var chamado = document.getElementById("chamado");
  if (chamado) {
    var campoDetalhes = chamado.elements.detalhes;
    var campoTransacao = chamado.elements.transacao;
    var campoEmail = chamado.elements.email;
    var campoEmail2 = chamado.elements.email2;
    var passoRede = document.getElementById("passo-rede");
    var linhaTransacao = document.getElementById("campo-transacao");
    var alertaFrase = document.getElementById("alerta-frase");
    var erroEmail = document.getElementById("erro-email");
    var enviar = document.getElementById("enviar-chamado");
    var pronto = document.getElementById("chamado-pronto");
    var listaBip = null;

    var assunto = function () { return chamado.querySelector('input[name="assunto"]:checked'); };
    var semAcento = function (texto) { return texto.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase(); };
    var seguidas = function (texto) {
      if (!listaBip) {
        if (!window.PALAVRAS_BIP39) return 0;
        listaBip = new Set(window.PALAVRAS_BIP39.map(semAcento));
      }
      var maior = 0, atual = 0;
      semAcento(texto).split(/[^a-z]+/).forEach(function (palavra) {
        if (!palavra) return;
        atual = listaBip.has(palavra) ? atual + 1 : 0;
        if (atual > maior) maior = atual;
      });
      return maior;
    };
    var emailValido = function (texto) { return /^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(texto); };

    var atualizar = function () {
      var escolhido = assunto();
      var pedeRede = !!(escolhido && escolhido.hasAttribute("data-rede"));
      var pedeTransacao = !!(escolhido && escolhido.hasAttribute("data-transacao"));
      passoRede.hidden = !pedeRede;
      linhaTransacao.hidden = !pedeTransacao;
      // Os numeros dos passos seguem o que aparece, como no app.
      var numero = 0;
      Array.prototype.forEach.call(chamado.querySelectorAll(".passo"), function (passo) {
        if (passo.hidden) return;
        numero += 1;
        passo.querySelector(".passo-numero").textContent = String(numero);
      });
      var frase = seguidas(campoDetalhes.value) >= 6 || (pedeTransacao && seguidas(campoTransacao.value) >= 6);
      alertaFrase.hidden = !frase;
      var email = campoEmail.value.trim();
      var email2 = campoEmail2.value.trim();
      var iguais = email.toLowerCase() === email2.toLowerCase();
      var mensagem = "";
      if (email && email2 && !iguais) mensagem = "Os dois e-mails não conferem.";
      else if (email && !emailValido(email) && document.activeElement !== campoEmail) mensagem = "Confira o e-mail: falta o @ ou o domínio.";
      erroEmail.textContent = mensagem;
      erroEmail.hidden = !mensagem;
      enviar.disabled = !(escolhido && campoDetalhes.value.trim().length >= 10 && !frase && emailValido(email) && iguais);
    };

    chamado.addEventListener("input", atualizar);
    chamado.addEventListener("change", atualizar);
    campoEmail.addEventListener("blur", atualizar);
    chamado.addEventListener("submit", function (evento) {
      evento.preventDefault();
      atualizar();
      if (enviar.disabled) return;
      var escolhido = assunto();
      var linhas = ["Responder para: " + campoEmail.value.trim(), "Assunto: " + escolhido.value];
      if (escolhido.hasAttribute("data-rede")) linhas.push("Rede: " + chamado.elements.rede.value);
      linhas.push("", campoDetalhes.value.trim());
      var transacao = campoTransacao.value.trim();
      if (escolhido.hasAttribute("data-transacao") && transacao) linhas.push("", "ID da transação: " + transacao);
      linhas.push("", "Enviado pela página de suporte do site.");
      var assuntoEmail = "Suporte: " + escolhido.value + " · site";
      window.location.href = "mailto:" + chamado.getAttribute("data-para") +
        "?subject=" + encodeURIComponent(assuntoEmail) + "&body=" + encodeURIComponent(linhas.join("\n"));
      pronto.hidden = false;
    });
    atualizar();
  }
})();
