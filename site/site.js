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

  function ruidoBits(a, b, c) {
    var h = (Math.imul(a | 0, 374761393) + Math.imul(b | 0, 668265263) + Math.imul(c | 0, 1274126177)) | 0;
    h = Math.imul(h ^ (h >>> 13), 1103515245);
    h ^= h >>> 16;
    return (h >>> 0) / 4294967295;
  }
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

  // MARK: Abertura: o palco fica fixo; o titulo sobe e some, o iPhone sobe ate o meio, a
  // legenda aparece decifrando e, no fim, a pagina entra no iPhone (a tela do app cresce ate
  // cobrir tudo, no mesmo preto do app). As moedas 3D leem o mesmo progresso.
  var abertura = document.querySelector(".abertura");
  if (abertura && movimento) {
    var palco = abertura.querySelector(".abertura-palco");
    var texto = abertura.querySelector(".abertura-texto");
    var aparelhoAbertura = abertura.querySelector(".abertura-aparelho");
    var telaAbertura = aparelhoAbertura.querySelector(".tela");
    var legenda = abertura.querySelector(".abertura-legenda");
    // A imersao (quinta rodada): a tela do app vira pixels, nos tons da propria gravacao,
    // enquanto a camera entra nela; os pixels se juntam no cadeado de pixels do site e do app,
    // que trava, e a camera atravessa o cadeado pelo buraco da fechadura. So depois o texto
    // seguinte sobe, sem tela preta.
    var bits = document.createElement("canvas");
    bits.className = "abertura-bits";
    bits.setAttribute("aria-hidden", "true");
    palco.appendChild(bits);
    var gBits = bits.getContext("2d");
    var dprBits = Math.min(window.devicePixelRatio || 1, 2);
    var COLS_BITS = 28, LINHAS_BITS = 61;
    var luzBits = null;
    (function () {
      var capa = telaAbertura.querySelector("img.capa");
      if (!capa) return;
      var ler = function () {
        try {
          var c = document.createElement("canvas");
          c.width = COLS_BITS; c.height = LINHAS_BITS;
          var g = c.getContext("2d");
          g.drawImage(capa, 0, 0, COLS_BITS, LINHAS_BITS);
          var d = g.getImageData(0, 0, COLS_BITS, LINHAS_BITS).data;
          luzBits = new Float32Array(COLS_BITS * LINHAS_BITS);
          for (var k = 0; k < luzBits.length; k++) luzBits[k] = (0.3 * d[k * 4] + 0.59 * d[k * 4 + 1] + 0.11 * d[k * 4 + 2]) / 255;
        } catch (erro) { luzBits = null; }
      };
      if (capa.complete && capa.naturalWidth) ler(); else capa.addEventListener("load", ler);
    })();
    var medirBits = function () {
      var r = palco.getBoundingClientRect();
      bits.width = Math.round(r.width * dprBits); bits.height = Math.round(r.height * dprBits);
    };
    medirBits();
    window.EscaliburRelogio.aoMedir(medirBits);
    // Os pixels: um por celula da tela (28 x 61). Os que viram cadeado guardam a celula do
    // cadeado (o mesmo desenho da pagina Seguranca e das Chaves, numa grade de 32); os outros
    // passam pela camera e somem.
    var pixelsAbertura = null, cadeadoCaixa = null;
    var montarPixels = function () {
      var celulas = [];
      for (var k = 0; k < CADEADO_FECHADO.length; k++) if (CADEADO_FECHADO[k] > 0) celulas.push({ x: k % GC, y: (k / GC) | 0 });
      var x0 = 99, x1 = -1, y0 = 99, y1 = -1;
      celulas.forEach(function (c) { x0 = Math.min(x0, c.x); x1 = Math.max(x1, c.x); y0 = Math.min(y0, c.y); y1 = Math.max(y1, c.y); });
      cadeadoCaixa = { cols: x1 - x0 + 1, linhas: y1 - y0 + 1 };
      // A fechadura: o miolo vazio da parte de baixo do cadeado, onde a camera passa.
      var furo = { x: 0, y: 0, n: 0 };
      var cheia = function (x, y) { return CADEADO_FECHADO[y * GC + x] > 0; };
      for (var y = Math.ceil(y0 + (y1 - y0) / 2); y <= y1; y++) for (var x = x0 + 1; x < x1; x++) {
        if (cheia(x, y)) continue;
        var esquerda = false, direita = false;
        for (var xe = x0; xe < x; xe++) if (cheia(xe, y)) esquerda = true;
        for (var xd = x + 1; xd <= x1; xd++) if (cheia(xd, y)) direita = true;
        if (esquerda && direita) { furo.x += x; furo.y += y; furo.n++; }
      }
      cadeadoCaixa.furoX = furo.n ? furo.x / furo.n - x0 + 0.5 : cadeadoCaixa.cols / 2;
      cadeadoCaixa.furoY = furo.n ? furo.y / furo.n - y0 + 0.5 : cadeadoCaixa.linhas * 0.7;
      var lista = [], dono = {};
      celulas.forEach(function (c) {
        // A celula da tela no mesmo lugar relativo: a tela se condensa no desenho.
        var u = (c.x - x0 + 0.5) / cadeadoCaixa.cols, v = (c.y - y0 + 0.5) / cadeadoCaixa.linhas;
        var col = Math.min(COLS_BITS - 1, Math.floor(u * COLS_BITS)), lin = Math.min(LINHAS_BITS - 1, Math.floor((0.12 + v * 0.76) * LINHAS_BITS));
        dono[lin * COLS_BITS + col] = { cx: c.x - x0 + 0.5, cy: c.y - y0 + 0.5 };
      });
      for (var l = 0; l < LINHAS_BITS; l++) for (var c2 = 0; c2 < COLS_BITS; c2++) {
        var k2 = l * COLS_BITS + c2;
        lista.push({ c: c2, l: l, alvo: dono[k2] || null, sorte: ruidoBits(c2, l, 5), fundo: 0.35 + 0.65 * ruidoBits(c2, l, 9) });
      }
      pixelsAbertura = lista;
    };
    var TONS_BITS = 14;
    var desenharBits = function (p, t) {
      var entra = suave(0.8, 0.86, p), forma = suave(0.855, 0.915, p), trava = suave(0.91, 0.925, p);
      var passa = suave(0.945, 0.995, p), fim = 1 - suave(0.985, 1, p);
      gBits.clearRect(0, 0, bits.width, bits.height);
      if (entra <= 0) return;
      if (!pixelsAbertura) montarPixels();
      var W = bits.width, H = bits.height;
      var rp = palco.getBoundingClientRect(), rt = telaAbertura.getBoundingClientRect();
      var x0 = (rt.left - rp.left) * dprBits, y0 = (rt.top - rp.top) * dprBits, w = rt.width * dprBits, h = rt.height * dprBits;
      // O fundo da pagina cobre a tela do app: os pixels ficam no lugar da gravacao.
      gBits.globalAlpha = entra;
      gBits.fillStyle = "#0B0B0C";
      gBits.fillRect(Math.max(0, x0), Math.max(0, y0), Math.min(W, x0 + w) - Math.max(0, x0), Math.min(H, y0 + h) - Math.max(0, y0));
      gBits.globalAlpha = 1;
      var cw = w / COLS_BITS, ch = h / LINHAS_BITS, ladoTela = Math.min(cw, ch) * 0.8;
      // O cadeado no meio do palco, com a celula do tamanho certo para caber.
      var celula = Math.min(W, H) * 0.5 / Math.max(cadeadoCaixa.cols, cadeadoCaixa.linhas);
      var cxC = W / 2 - cadeadoCaixa.cols * celula / 2, cyC = H / 2 - cadeadoCaixa.linhas * celula / 2;
      var furoX = cxC + cadeadoCaixa.furoX * celula, furoY = cyC + cadeadoCaixa.furoY * celula;
      // A trava: um pulso de luz quando o desenho fecha.
      var pulso = trava * (1 - suave(0.93, 0.95, p));
      var tique = Math.floor(t * 9);
      var baldes = [];
      for (var b = 0; b < TONS_BITS; b++) baldes.push([]);
      for (var k = 0; k < pixelsAbertura.length; k++) {
        var px = pixelsAbertura[k];
        var tom0 = luzBits ? 0.25 + luzBits[px.l * COLS_BITS + px.c] * 0.75 : px.fundo;
        var sx = x0 + (px.c + 0.5) * cw, sy = y0 + (px.l + 0.5) * ch;
        var x, y, lado, tom, alfa;
        if (px.alvo) {
          // Cada pixel do cadeado sai da sua celula da tela num instante proprio.
          var f = suave(0, 1, forma * 1.35 - px.sorte * 0.35);
          var ex = cxC + px.alvo.cx * celula, ey = cyC + px.alvo.cy * celula;
          x = sx + (ex - sx) * f; y = sy + (ey - sy) * f;
          lado = ladoTela + (celula * 0.84 - ladoTela) * f;
          tom = tom0 + (0.82 + 0.18 * ruidoBits(px.c, px.l, tique) - tom0) * f;
          tom = Math.min(1, tom + pulso * 0.35);
          lado *= 1 + pulso * 0.06;
          alfa = entra;
          // A camera passa pela fechadura: cada pixel numa profundidade propria.
          if (passa > 0) {
            var z = 1 - passa * (0.92 + 0.12 * px.sorte);
            if (z <= 0.04) continue;
            var s = 1 / z;
            x = furoX + (x - furoX) * s; y = furoY + (y - furoY) * s; lado *= s;
            alfa *= 1 - suave(5, 12, s);
          }
        } else {
          // Os outros passam pela camera, para fora, e somem enquanto o cadeado se forma.
          var s2 = 1 + forma * 1.6;
          x = W / 2 + (sx - W / 2) * s2; y = H / 2 + (sy - H / 2) * s2; lado = ladoTela * s2;
          tom = tom0 * (0.7 + 0.3 * ruidoBits(px.c, px.l, tique + 3));
          alfa = entra * (1 - suave(0.05, 0.75, forma + px.sorte * 0.2));
        }
        alfa *= fim;
        if (alfa <= 0.02 || lado < 0.5) continue;
        if (x + lado < 0 || y + lado < 0 || x - lado > W || y - lado > H) continue;
        var nivel = Math.min(TONS_BITS - 1, Math.floor(tom * alfa * TONS_BITS));
        if (nivel < 1) continue;
        baldes[nivel].push(x - lado / 2, y - lado / 2, lado);
      }
      for (var n = 1; n < TONS_BITS; n++) {
        var lista = baldes[n];
        if (!lista.length) continue;
        var v = Math.round(18 + (n / (TONS_BITS - 1)) * 232);
        gBits.fillStyle = "rgb(" + v + "," + v + "," + Math.min(255, v + 2) + ")";
        gBits.beginPath();
        for (var q = 0; q < lista.length; q += 3) gBits.rect(lista[q], lista[q + 1], lista[q + 2], lista[q + 2]);
        gBits.fill();
      }
    };
    var medida = null, ultimo = -1;
    var medirAbertura = function () {
      aparelhoAbertura.style.transform = "";
      var rp = palco.getBoundingClientRect(), ra = aparelhoAbertura.getBoundingClientRect();
      var largo = window.innerWidth >= 900;
      var alturaPalco = rp.height;
      var destino = largo ? (alturaPalco - ra.height) / 2 : Math.max(alturaPalco - ra.height - 28, (alturaPalco - ra.height) / 2 + 40);
      var sobe = destino - (ra.top - rp.top);
      // Do lugar de chegada, o centro da tela do app vai ao centro do palco e cresce ate a
      // tela cobrir o palco inteiro (a camera entra nela).
      var centroChegada = ra.top - rp.top + sobe + ra.height / 2;
      medida = {
        inicio: abertura.getBoundingClientRect().top + window.pageYOffset,
        alcance: Math.max(1, abertura.offsetHeight - alturaPalco),
        sobe: sobe,
        centraliza: alturaPalco / 2 - centroChegada,
        cresce: Math.max(rp.width / (ra.width * 0.93), alturaPalco / (ra.height * 0.96)) * 1.12,
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
      // Na imersao, os bits trocam sozinhos: o quadro segue mesmo sem rolagem.
      var naImersao = p > 0.78 && p < 1;
      if (p === ultimo && !naImersao) return false;
      ultimo = p;
      window.EscaliburAbertura.p = p;
      var a = suave(0, 0.26, p);
      texto.style.transform = "translate3d(0," + (-a * 110).toFixed(1) + "px,0) scale(" + (1 - a * 0.05).toFixed(4) + ")";
      texto.style.opacity = (1 - a).toFixed(3);
      texto.style.visibility = a >= 1 ? "hidden" : "";
      var b = suave(0.05, 0.42, p);
      var z = suave(0.74, 0.92, p);
      var escala = (0.92 + 0.08 * b) * (1 + (medida.cresce - 1) * z * z);
      // A camera chega inclinada e endireita ao entrar: o iPhone deita um pouco e volta.
      var inclina = 16 * Math.sin(Math.PI * suave(0.7, 0.9, p));
      aparelhoAbertura.style.transform = "translate3d(0," + (medida.sobe * b + medida.centraliza * suave(0.72, 0.86, p)).toFixed(1) + "px,0) perspective(1100px) rotateX(" + inclina.toFixed(2) + "deg) scale(" + escala.toFixed(4) + ")";
      desenharBits(p, e.t);
      var c = suave(0.56, 0.64, p) * (1 - suave(0.7, 0.76, p));
      legenda.style.opacity = c.toFixed(3);
      legenda.classList.toggle("visivel", c > 0.5);
      var largo = e.vw >= 900;
      legenda.style.transform = (largo ? "translate3d(0,calc(-50% + " : "translate3d(0,") + ((1 - c) * 24).toFixed(1) + "px" + (largo ? ")" : "") + ",0)";
      return naImersao;
    });
  }

  // MARK: Manifesto: cada palavra comeca cifrada, em glifos que trocam como os do app, e
  // decifra quando a rolagem chega nela.
  var manifesto = document.querySelector("[data-palavras]");
  var secaoManifesto = document.getElementById("manifesto");
  var prontoDesde = 0;
  if (manifesto && secaoManifesto && movimento) {
    var inteiro = manifesto.textContent.trim();
    var palavrasM = inteiro.split(/\s+/);
    manifesto.textContent = "";
    // A palavra de verdade fica no texto (transparente, mas selecionavel e lida pelo leitor
    // de tela); por cima, so o desenho: os glifos e depois a palavra.
    var palavrasCifra = palavrasM.map(function (palavra, i) {
      var s = document.createElement("span");
      s.className = "palavra cifrada";
      var real = document.createElement("span");
      real.className = "real";
      real.textContent = palavra;
      var vista = document.createElement("span");
      vista.className = "vista";
      vista.setAttribute("aria-hidden", "true");
      s.appendChild(real);
      s.appendChild(vista);
      manifesto.appendChild(s);
      if (i < palavrasM.length - 1) manifesto.appendChild(document.createTextNode(" "));
      return { el: s, vista: vista, texto: palavra, aberta: false, desde: -9, mostrado: "" };
    });
    window.EscaliburRelogio.registrar(function (e) {
      var r = manifesto.getBoundingClientRect();
      if (r.bottom < -40 || r.top > e.vh + 40) return false;
      // O manifesto nasce no centro da tela, no fim do mergulho (pedido do dono, 23/10/2026): ele
      // ocupa a ultima tela da abertura, invisivel ate o cadeado fechar, e entao decifra ali mesmo,
      // pelo tempo. Voltando a rolagem para dentro do mergulho, some e cifra de novo.
      var abertura = window.EscaliburAbertura;
      var pronto = !abertura || abertura.p >= 0.985;
      if (pronto !== secaoManifesto.classList.contains("pronto")) {
        secaoManifesto.classList.toggle("pronto", pronto);
        prontoDesde = e.t;
      }
      var p = pronto ? limitar((e.t - prontoDesde - 0.15) / 0.9, 0, 1) : 0;
      var n = palavrasCifra.length, tique = Math.floor(e.t * 11);
      palavrasCifra.forEach(function (w, i) {
        var abrir = p * (n + 2) - i > 0.5;
        if (abrir !== w.aberta) { w.aberta = abrir; w.desde = e.t; w.el.classList.toggle("cifrada", !abrir); }
        var k = w.aberta ? (e.t - w.desde) / 0.32 : 0;
        var saida = "";
        for (var j = 0; j < w.texto.length; j++) {
          var ch = w.texto[j];
          saida += w.aberta && (j / w.texto.length < k || /[.,]/.test(ch)) ? ch : (/[.,]/.test(ch) ? ch : glifoDe(i * 31 + j, tique + i));
        }
        if (saida !== w.mostrado) { w.vista.textContent = saida; w.mostrado = saida; }
      });
      return true;
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

  // MARK: Por dentro do app (quinta rodada): um iPhone so, parado no meio enquanto a pessoa
  // rola; a gravacao troca a cada passo. A mesma regra das Chaves: cada passo ocupa uma tela
  // de rolagem e so troca depois de passar 35% do trecho seguinte, um de cada vez, depois
  // que a tela anterior apareceu. So a rolagem longa e rapida vai direto.
  var passeio = document.querySelector("[data-passeio]");
  if (passeio) {
    var abasP = Array.prototype.slice.call(passeio.querySelectorAll(".aba-tela"));
    var telasP = Array.prototype.slice.call(passeio.querySelectorAll(".passeio-tela"));
    var legendasP = Array.prototype.slice.call(passeio.querySelectorAll(".passeio-legenda"));
    var botaoP = passeio.querySelector(".passeio-pausar");
    var trilhoP = document.querySelector(".telas-trilho");
    var nP = telasP.length;
    var atualP = -1, prontaP = 0, travaP = 0, naTelaP = false, pausadoP = calmo.matches;
    var yP = null, tP = 0, velocidadeP = 0, gestoP = null;
    var videoP = function (n) { return telasP[n].querySelector("video"); };
    telasP.forEach(function (tela) { prepararVideo(tela.querySelector("video")); });
    var tocarP = function () {
      telasP.forEach(function (tela, n) {
        var v = videoP(n);
        if (n === atualP && naTelaP && !pausadoP) { if (v.paused) tocar(v, botaoP); }
        else if (!v.paused) v.pause();
      });
      if (pausadoP || !naTelaP) mostrar(botaoP, "pausado");
    };
    var mostrarP = function (n, t, foco) {
      if (n === atualP) return;
      var antes = atualP;
      atualP = n;
      telasP.forEach(function (tela, k) { tela.classList.toggle("ativa", k === n); });
      legendasP.forEach(function (l, k) { l.hidden = k !== n; });
      abasP.forEach(function (a, k) { a.setAttribute("aria-selected", String(k === n)); a.tabIndex = k === n ? 0 : -1; });
      if (foco) abasP[n].focus();
      var fileira = abasP[n].parentNode;
      if (fileira.scrollWidth > fileira.clientWidth + 2) {
        fileira.scrollTo({ left: abasP[n].offsetLeft - (fileira.clientWidth - abasP[n].offsetWidth) / 2, behavior: movimento ? "smooth" : "auto" });
      }
      if (antes >= 0) { var velho = videoP(antes); velho.pause(); velho.classList.remove("visivel"); }
      try { videoP(n).currentTime = 0; } catch (erro) { /* ainda sem dados */ }
      tocarP();
      // O passo seguinte so entra depois que esta tela apareceu (a troca leva 0,45 s).
      prontaP = t + 0.8;
      pedir();
    };
    var progressoP = function () {
      var r = trilhoP.getBoundingClientRect();
      return limitar(-r.top / Math.max(1, r.height - window.innerHeight), 0, 0.9999);
    };
    mostrarP(movimento ? Math.floor(progressoP() * nP) : 0, performance.now() / 1000);
    abasP.forEach(function (aba, n) {
      aba.addEventListener("click", function () {
        var t = performance.now() / 1000;
        if (movimento) {
          var r = trilhoP.getBoundingClientRect();
          var alcance = r.height - window.innerHeight;
          travaP = t + 1.4;
          window.scrollTo({ top: window.pageYOffset + r.top + alcance * (n + 0.5) / nP, behavior: "smooth" });
        }
        mostrarP(n, t, false);
      });
      aba.addEventListener("keydown", function (e) {
        var anda = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
        if (anda) { e.preventDefault(); abasP[(n + anda + nP) % nP].click(); abasP[(n + anda + nP) % nP].focus(); }
      });
    });
    if (botaoP) {
      mostrar(botaoP, "pausado");
      botaoP.addEventListener("click", function () { pausadoP = !pausadoP; tocarP(); });
    }
    if (observa) {
      new IntersectionObserver(function (e) { naTelaP = e[0].isIntersecting; tocarP(); if (naTelaP) pedir(); }, { threshold: 0.4 }).observe(passeio);
    }
    if (movimento) {
      window.EscaliburRelogio.registrar(function (e) {
        if (!naTelaP) { yP = null; return false; }
        var t = e.t, yAgora = window.pageYOffset;
        if (yP !== null && t > tP) {
          var instante = Math.abs(yAgora - yP) / window.innerHeight / (t - tP);
          velocidadeP += (Math.min(instante, 20) - velocidadeP) * Math.min(1, (t - tP) * 6);
        }
        yP = yAgora; tP = t;
        if (t <= travaP) return true;
        var seg = progressoP() * nP, alvo = atualP;
        if (velocidadeP > 2 && gestoP === null) gestoP = seg;
        else if (velocidadeP < 0.5) gestoP = null;
        if (seg >= atualP + 1.35) alvo = Math.min(nP - 1, Math.floor(seg - 0.35));
        else if (seg < atualP - 0.35) alvo = Math.max(0, Math.floor(seg + 0.35));
        if (alvo !== atualP) {
          if (gestoP !== null && Math.abs(seg - gestoP) >= 2) mostrarP(alvo, t);
          else if (t >= prontaP) mostrarP(atualP + (alvo > atualP ? 1 : -1), t);
        }
        return true;
      });
    }
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
  // Tudo em dolar (pedido do dono, 23/10/2026).
  var fiat = "usd";
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
      texto.textContent = vivo ? "Ao vivo, atualizado às " + horaCurta(precos.hora) + (precos.fonte && precos.fonte !== "CoinGecko" ? ", pelo " + precos.fonte : "")
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
      // A semana vem da hora em que foi lida: se ja passou de 3 horas, a legenda diz ate quando.
      var rotuloSemana = grafico.querySelector(".apoio").firstChild;
      var horaLinha = precos && precos.linha_hora ? new Date(precos.linha_hora) : null;
      rotuloSemana.nodeValue = horaLinha && Date.now() - horaLinha > 3 * 3600 * 1000 ? "Semana até " + diaCurto(precos.linha_hora) : "Últimos 7 dias";
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
    this.nota = el.getAttribute("data-nota");
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
    // No celular a lista abre como folha embaixo, sobre um fundo que fecha ao toque.
    this.fundo = document.createElement("div");
    this.fundo.className = "menu-fundo";
    el.appendChild(this.fundo);
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
    var alca = document.createElement("span");
    alca.className = "menu-alca";
    this.menu.appendChild(alca);
    var grade = document.createElement("div");
    grade.className = "menu-grade" + (this.opcoes.length < 6 ? " uma" : "");
    this.menu.appendChild(grade);
    if (this.nota) {
      var nota = document.createElement("p");
      nota.className = "menu-nota";
      nota.textContent = this.nota;
      this.menu.appendChild(nota);
    }
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
      grade.appendChild(item);
    });
  };
  Escolha.prototype.abrir = function () {
    abertos.slice().forEach(function (outro) { outro.fechar(false); });
    this.montarMenu();
    this.menu.classList.add("aberto");
    this.fundo.classList.add("aberto");
    this.botao.setAttribute("aria-expanded", "true");
    abertos.push(this);
    var marcado = this.menu.querySelector('[aria-selected="true"]') || this.menu.querySelector(".opcao-menu");
    if (marcado) marcado.focus();
  };
  Escolha.prototype.fechar = function (devolverFoco) {
    if (!this.menu.classList.contains("aberto")) return;
    this.menu.classList.remove("aberto");
    this.fundo.classList.remove("aberto");
    this.botao.setAttribute("aria-expanded", "false");
    abertos = abertos.filter(function (a) { return a !== this; }, this);
    if (devolverFoco) this.botao.focus();
  };
  Escolha.prototype.alternar = function () {
    if (this.menu.classList.contains("aberto")) this.fechar(true); else this.abrir();
  };
  document.addEventListener("click", function (e) {
    abertos.slice().forEach(function (a) { if (!a.el.contains(e.target) || e.target === a.fundo) a.fechar(false); });
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
    // O saldo de exemplo da demonstracao, como o do video do app (1.250 USDC na Base).
    var SALDO_DEMO = { usdc: 1250, usdt: 1250, eth: 0.5, wbtc: 0.02 };
    var rotaCCTP = "rapida";
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
      var via = rota ? rota[2] : "";
      var nomeDestino = (redePonte(ponte.destino) || {}).nome || ponte.destino;
      var valor = lerValor(campoPonte.value);
      var preco = valorEm(ativo.g, fiat);
      q("[data-ponte-simbolo]").textContent = ativo.s;
      q("[data-ponte-saldo]").textContent = "Saldo " + quantidade(SALDO_DEMO[ponte.ativo]) + " " + ativo.s;
      q("[data-fiat-ponte]").textContent = valor && preco ? "≈ " + dinheiro(valor * preco, fiat) : "";
      q("[data-ponte-chega]").textContent = "Chega na " + nomeDestino;
      q("#ponte-resultado").textContent = valor ? "≈ " + quantidade(valor) : "0";
      // Rapida e Padrao so no USDC pelo CCTP, como no app.
      var rotas2 = q("[data-ponte-rotas]");
      rotas2.hidden = via !== "cctp";
      cada("[data-rota-cctp]", function (b) { b.setAttribute("aria-checked", String(b.getAttribute("data-rota-cctp") === rotaCCTP)); }, rotas2);
      // As linhas do app (BridgeForm), com os mesmos textos.
      var linhas = [];
      if (via === "usdt0") linhas.push("Pela USDT0 da própria Tether: o contrato dela entrega o mesmo valor em USDT na Tron (TRC-20)");
      else if (via === "cctp") linhas.push("Pelo CCTP da Circle: queima aqui e a própria Circle cunha o mesmo USDC na " + nomeDestino);
      else if (via === "across") linhas.push("Pelo Across: um relayer entrega na " + nomeDestino + " em segundos");
      linhas.push("Tempo: " + (via === "cctp" ? (rotaCCTP === "rapida" ? "menos de 1 minuto" : "uns 20 minutos (sem taxa do protocolo)") : via === "across" ? "segundos" : "uns minutos"));
      linhas.push(ponte.destino === "tron" ? "Vai para a sua própria conta na Tron, desta mesma carteira" : "Vai para a sua própria conta na " + nomeDestino + ", o mesmo endereço");
      linhas.push("Sem taxa da Escalibur");
      var lista = q("[data-ponte-detalhes]");
      lista.textContent = "";
      linhas.forEach(function (l) { var li = document.createElement("li"); li.textContent = l; lista.appendChild(li); });
      var inverterRedes = q(".inverter-redes");
      inverterRedes.disabled = !rotas.some(function (r) { return r[0] === ponte.destino && r[1] === ponte.origem; });
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
    cada("[data-fracao]", function (b) {
      b.addEventListener("click", function () {
        var v = SALDO_DEMO[ponte.ativo] * Number(b.getAttribute("data-fracao"));
        campoPonte.value = formato("q-campo", { maximumFractionDigits: 6, useGrouping: false }).format(v);
        contaPonte();
      });
    }, painel);
    cada("[data-rota-cctp]", function (b) {
      b.addEventListener("click", function () { rotaCCTP = b.getAttribute("data-rota-cctp"); contaPonte(); });
    }, painel);
    q(".inverter-redes").addEventListener("click", function () {
      var o = ponte.origem;
      ponte.origem = ponte.destino;
      ponte.destino = o;
      contaPonte();
    });
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
      painel.querySelector(".painel-acao").textContent = aba.id === "aba-ponte" ? "Revisar ponte no app" : "Trocar no app";
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

  // MARK: Pixels que cifram: a mesma linguagem do app (PixelFill, CipherEmblem). Uma grade
  // de pixels cinza, cada um trocando de tom no seu compasso, como bits de um texto cifrado;
  // os desenhos (o PIN, a memoria, o chip, a chave, o cadeado) se montam e se desfazem pixel
  // a pixel, com uma passada clara correndo. Sem sorteio: o hash do lugar decide o tom.
  function ruido(a, b, c) {
    var h = (Math.imul(a | 0, 374761393) + Math.imul(b | 0, 668265263) + Math.imul(c | 0, 1274126177)) | 0;
    h = Math.imul(h ^ (h >>> 13), 1103515245);
    h ^= h >>> 16;
    return (h >>> 0) / 4294967295;
  }
  function suaveT(t) { t = t < 0 ? 0 : t > 1 ? 1 : t; return t * t * (3 - 2 * t); }

  // Um desenho em texto: "#" aceso, "+" meio aceso, "." apagado.
  function deTexto(linhas, cols, rows, x0, y0, escala) {
    var m = new Float32Array(cols * rows), s = escala || 1;
    linhas.forEach(function (linha, y) {
      for (var x = 0; x < linha.length; x++) {
        var v = linha[x] === "#" ? 1 : linha[x] === "+" ? 0.55 : 0;
        if (!v) continue;
        for (var dy = 0; dy < s; dy++) for (var dx = 0; dx < s; dx++) {
          var cx = x0 + x * s + dx, cy = y0 + y * s + dy;
          if (cx >= 0 && cy >= 0 && cx < cols && cy < rows) m[cy * cols + cx] = v;
        }
      }
    });
    return m;
  }

  function Pixels(canvas, cols, rows, opcoes) {
    opcoes = opcoes || {};
    this.canvas = canvas;
    this.g = canvas.getContext("2d");
    this.cols = cols; this.rows = rows;
    this.n = cols * rows;
    this.alvo = new Float32Array(this.n);
    this.de = new Float32Array(this.n);
    this.atual = new Float32Array(this.n);
    this.inicio = new Float32Array(this.n);
    this.fundo = opcoes.fundo === undefined ? 0.06 : opcoes.fundo;
    this.ritmo = opcoes.ritmo || 6;
    // Quanto o tom aceso varia com a cifra: nos icones, menos, para o desenho ler.
    this.cifra = opcoes.cifra === undefined ? 0.42 : opcoes.cifra;
    this.base = 0.84 - this.cifra;
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.agitado = 0;
    this.medir();
  }
  Pixels.prototype.medir = function () {
    var r = this.canvas.getBoundingClientRect();
    this.w = Math.max(1, r.width); this.h = Math.max(1, r.height);
    var w = Math.round(this.w * this.dpr), h = Math.round(this.h * this.dpr);
    if (this.canvas.width !== w || this.canvas.height !== h) { this.canvas.width = w; this.canvas.height = h; }
  };
  // Troca o desenho: cada pixel muda no seu tempo, a partir de `centro` (ou ao acaso).
  Pixels.prototype.mudar = function (mapa, agora, opcoes) {
    opcoes = opcoes || {};
    var dur = opcoes.duracao || 0.9, cx = (this.cols - 1) / 2, cy = (this.rows - 1) / 2, maxd = Math.hypot(cx, cy);
    for (var i = 0; i < this.n; i++) {
      var x = i % this.cols, y = (i / this.cols) | 0;
      var ordem = opcoes.varrer === "esquerda" ? x / this.cols : opcoes.varrer === "acaso" ? ruido(x, y, 77) : Math.hypot(x - cx, y - cy) / maxd;
      this.de[i] = this.atual[i];
      this.alvo[i] = mapa[i];
      this.inicio[i] = agora + ordem * dur * 0.75 + ruido(x, y, 3) * dur * 0.25;
    }
  };
  Pixels.prototype.desenhar = function (t, efeitos) {
    var g = this.g, cols = this.cols, rows = this.rows;
    var passo = Math.min(this.w / cols, this.h / rows) * this.dpr;
    var lado = passo * 0.8, ox = (this.canvas.width - passo * cols) / 2 + (passo - lado) / 2, oy = (this.canvas.height - passo * rows) / 2 + (passo - lado) / 2;
    g.clearRect(0, 0, this.canvas.width, this.canvas.height);
    var niveis = 24, caminhos = [];
    for (var k = 0; k < niveis; k++) caminhos.push([]);
    var varre = efeitos && efeitos.passada !== undefined ? efeitos.passada : ((t / 2.4) % 1) * (cols + 16) - 8;
    var calmo = efeitos && efeitos.calmo;
    for (var i = 0; i < this.n; i++) {
      var x = i % cols, y = (i / cols) | 0;
      var p = suaveT((t - this.inicio[i]) / 0.42);
      var aceso = this.de[i] + (this.alvo[i] - this.de[i]) * p;
      this.atual[i] = aceso;
      // O tom cifrado deste pixel agora: dois tons do hash, cruzados devagar, cada um no seu compasso.
      var fase = ruido(x, y, 0x9e37);
      var bit = 0.5;
      if (!calmo) {
        var batida = t * this.ritmo * (0.6 + 0.8 * fase) + fase * 8, k0 = Math.floor(batida), m = suaveT(batida - k0);
        var a = ruido(x, y, k0), b = ruido(x, y, k0 + 1);
        bit = a + (b - a) * m;
      }
      // Na troca, os pixels a caminho acendem mais: a frente que encaixa.
      // So nos pixels que mudam: os outros nao piscam com a troca.
      var frente = p > 0 && p < 1 ? Math.sin(p * Math.PI) * Math.abs(this.alvo[i] - this.de[i]) : 0;
      var tom = this.fundo + aceso * (this.base + this.cifra * bit) + frente * 0.35 * bit;
      if (!calmo) {
        var d = (x - varre + (y - rows / 2) * 0.35) / 4;
        tom += 0.18 * Math.exp(-d * d) * aceso;
      }
      if (efeitos && efeitos.extra) tom += efeitos.extra(x, y, aceso, bit) || 0;
      var nivel = Math.max(0, Math.min(niveis - 1, Math.round(tom * (niveis - 1))));
      if (tom > 0.02) caminhos[nivel].push(i);
    }
    for (k = 1; k < niveis; k++) {
      var lista = caminhos[k];
      if (!lista.length) continue;
      var v = Math.round(Math.pow(k / (niveis - 1), 0.9) * 245 + 4);
      g.fillStyle = "rgb(" + v + "," + v + "," + (v + 2) + ")";
      g.beginPath();
      for (var j = 0; j < lista.length; j++) {
        var c = lista[j];
        g.rect(ox + (c % cols) * passo, oy + ((c / cols) | 0) * passo, lado, lado);
      }
      g.fill();
    }
  };

  // Os icones da Privacidade, numa grade de 16: o desenho em "#", e o risco do "sem" em "+"
  // (um tom abaixo), com uma folga apagada dos dois lados para o desenho continuar lendo.
  var ICONES = {
    conta: [
      "................", "......####......", ".....######.....", ".....######.....", ".....######.....", "......####......",
      "................", "....########....", "...##########...", "..############..", "..############..", "..############..",
      "................", "................", "................", "................"],
    olho: [
      "................", "................", "................", ".....######.....", "...###....###...", "..##..####..##..",
      ".##..######..##.", ".##..######..##.", "..##..####..##..", "...###....###...", ".....######.....", "................",
      "................", "................", "................", "................"],
    servidores: [
      "................", ".##############.", ".#............#.", ".#.##.........#.", ".#............#.", ".##############.",
      "................", ".##############.", ".#............#.", ".#.##.........#.", ".#............#.", ".##############.",
      "................", "......####......", "....########....", "................"],
    site: [
      "................", ".##############.", ".#.#.#........#.", ".##############.", ".#............#.", ".#..########..#.",
      ".#............#.", ".#..######....#.", ".#............#.", ".#..########..#.", ".#............#.", ".#..####......#.",
      ".#............#.", ".##############.", "................", "................"],
  };
  function icone(nome) {
    var m = deTexto(ICONES[nome], 16, 16, 0, 0);
    if (nome === "conta" || nome === "olho") {
      for (var y = 1; y < 15; y++) for (var x = 1; x < 15; x++) {
        var d = x - y;
        if (d === 0) m[y * 16 + x] = 1;
        else if (Math.abs(d) === 1) m[y * 16 + x] = 0;
      }
    }
    return m;
  }

  // Uma cena de pixels que so anima na tela (e para fora dela).
  function cenaPixels(canvas, cols, rows, opcoes, quadro) {
    var px = new Pixels(canvas, cols, rows, opcoes);
    var visivel = false;
    if (observa) new IntersectionObserver(function (e) { visivel = e[0].isIntersecting; if (visivel) pedir(); }, { rootMargin: "80px" }).observe(canvas);
    window.EscaliburRelogio.aoMedir(function () { px.medir(); });
    window.EscaliburRelogio.registrar(function (estado) {
      if (!visivel || document.hidden) return false;
      return quadro(px, estado.t, estado) !== false;
    });
    return px;
  }
  function agoraS() { return performance.now() / 1000; }

  // MARK: Particulas: os pixels do desenho voam de um desenho para o outro (cada pixel aceso
  // do proximo sai de um pixel aceso do atual), e cifram no lugar, trocando de tom. Sem fundo:
  // so os pixels do desenho. Usado nas Chaves e no cadeado da pagina Seguranca.
  function pontosDe(mapa, cols) {
    var lista = [];
    for (var i = 0; i < mapa.length; i++) if (mapa[i] > 0.01) lista.push({ x: i % cols, y: (i / cols) | 0, v: mapa[i] });
    return lista;
  }
  function Particulas(canvas, cols, rows) {
    this.canvas = canvas; this.g = canvas.getContext("2d");
    this.cols = cols; this.rows = rows;
    this.lista = [];
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.medir();
  }
  Particulas.prototype.medir = Pixels.prototype.medir;
  // Leva as particulas para o desenho `mapa`, a partir do instante `agora`.
  Particulas.prototype.formar = function (mapa, agora, opcoes) {
    opcoes = opcoes || {};
    var alvos = pontosDe(mapa, this.cols), cols = this.cols, rows = this.rows;
    var cx = cols / 2, cy = rows / 2;
    var angulo = function (p) { return Math.atan2(p.y - cy, p.x - cx); };
    // As vivas, na posicao de agora; as que sobram somem, as que faltam nascem de uma viva.
    var vivas = this.lista.filter(function (p) { return p.alfaAlvo > 0; });
    vivas.forEach(function (p) { var q = p.agora(agora); p.x0 = q.x; p.y0 = q.y; p.a0 = q.a; p.v0 = q.v; });
    vivas.sort(function (a, b) { return angulo({ x: a.x0, y: a.y0 }) - angulo({ x: b.x0, y: b.y0 }); });
    alvos.sort(function (a, b) { return angulo(a) - angulo(b); });
    var nova = [], dur = opcoes.duracao || 0.85, espalha = opcoes.espalha || 0.35;
    for (var k = 0; k < alvos.length; k++) {
      var de = vivas.length ? vivas[Math.floor(k * vivas.length / alvos.length)] : null;
      var semente = ruido(k, alvos.length, 7);
      var origem = de ? { x: de.x0, y: de.y0, a: de.a0 === undefined ? 1 : de.a0, v: de.v0 }
        : opcoes.de === "espalhado" ? { x: ruido(k, 1, 11) * cols, y: ruido(k, 2, 13) * rows, a: 0, v: alvos[k].v }
        : { x: cx, y: cy, a: 0, v: alvos[k].v };
      nova.push(new Particula(k, origem, alvos[k], agora + semente * espalha, dur));
    }
    // As que nao tem lugar no desenho novo se apagam onde estao.
    if (vivas.length > alvos.length) {
      vivas.forEach(function (p, i) {
        if (i % Math.ceil(vivas.length / Math.max(1, vivas.length - alvos.length)) === 0 && nova.length < vivas.length + alvos.length) {
          var q = { x: p.x0, y: p.y0, a: p.a0, v: p.v0 };
          var some = new Particula(1000 + i, q, { x: q.x + (ruido(i, 3, 5) - 0.5) * 3, y: q.y + (ruido(i, 4, 5) - 0.5) * 3, v: 0 }, agora, dur * 0.7);
          some.alfaAlvo = 0;
          nova.push(some);
        }
      });
    }
    this.lista = nova;
  };
  // Espalha tudo (para o cadeado se desfazer e se montar de novo).
  Particulas.prototype.espalhar = function (agora) {
    var cols = this.cols, rows = this.rows;
    this.lista.forEach(function (p, i) {
      var q = p.agora(agora);
      p.x0 = q.x; p.y0 = q.y; p.a0 = q.a; p.v0 = q.v;
      p.x1 = q.x + (ruido(i, 9, 1) - 0.5) * cols * 0.7; p.y1 = q.y + (ruido(i, 9, 2) - 0.5) * rows * 0.7;
      p.inicio = agora + ruido(i, 9, 3) * 0.3; p.dur = 0.9; p.alfaAlvo = 0;
    });
  };
  function Particula(id, de, para, inicio, dur) {
    this.id = id; this.x0 = de.x; this.y0 = de.y; this.a0 = de.a; this.v0 = de.v === undefined ? para.v : de.v;
    this.x1 = para.x; this.y1 = para.y; this.v1 = para.v; this.inicio = inicio; this.dur = dur; this.alfaAlvo = 1;
    this.arco = (ruido(id, 21, 4) - 0.5) * 6;
  }
  Particula.prototype.agora = function (t) {
    var k = (t - this.inicio) / this.dur;
    k = k < 0 ? 0 : k > 1 ? 1 : k;
    var e = k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
    var dx = this.x1 - this.x0, dy = this.y1 - this.y0, d = Math.hypot(dx, dy) || 1;
    var curva = Math.sin(e * Math.PI) * this.arco * Math.min(1, d / 10);
    return {
      x: this.x0 + dx * e - dy / d * curva, y: this.y0 + dy * e + dx / d * curva,
      a: this.a0 + (this.alfaAlvo - this.a0) * e, v: this.v0 + ((this.v1 === undefined ? this.v0 : this.v1) - this.v0) * e, k: k,
    };
  };
  Particulas.prototype.desenhar = function (t, opcoes) {
    opcoes = opcoes || {};
    var g = this.g, cols = this.cols, rows = this.rows;
    var passo = Math.min(this.canvas.width / cols, this.canvas.height / rows);
    var lado = passo * 0.82, ox = (this.canvas.width - passo * cols) / 2, oy = (this.canvas.height - passo * rows) / 2;
    g.clearRect(0, 0, this.canvas.width, this.canvas.height);
    var calmo = opcoes.calmo, tique = Math.floor(t * 8), varre = ((t / 2.6) % 1) * (cols + 20) - 10;
    var niveis = {}, chaves = [];
    for (var i = 0; i < this.lista.length; i++) {
      var p = this.lista[i], q = p.agora(t);
      if (q.a < 0.02) continue;
      var bit = calmo ? 0.6 : (function () {
        var fase = ruido(p.id, 5, 9), batida = t * 5 * (0.6 + 0.8 * fase) + fase * 8, k0 = Math.floor(batida), m = suaveT(batida - k0);
        var a = ruido(p.id, k0, 3), b = ruido(p.id, k0 + 1, 3);
        return a + (b - a) * m;
      })();
      var voando = q.k > 0 && q.k < 1 ? Math.sin(q.k * Math.PI) : 0;
      var tom = q.v * (0.5 + 0.42 * bit) + voando * 0.3;
      if (!calmo) { var d = (q.x - varre + (q.y - rows / 2) * 0.4) / 4; tom += 0.16 * Math.exp(-d * d) * q.v; }
      if (opcoes.extra) tom += opcoes.extra(p, q, bit, tique) || 0;
      tom = Math.max(0, Math.min(1, tom)) * q.a;
      var nivel = Math.round(tom * 20);
      if (nivel < 1) continue;
      if (!niveis[nivel]) { niveis[nivel] = []; chaves.push(nivel); }
      niveis[nivel].push(q);
    }
    chaves.forEach(function (n) {
      var v = Math.round(Math.pow(n / 20, 0.9) * 245 + 6);
      g.fillStyle = "rgb(" + v + "," + v + "," + (v + 2) + ")";
      g.beginPath();
      niveis[n].forEach(function (q) { g.rect(ox + q.x * passo + (passo - lado) / 2, oy + q.y * passo + (passo - lado) / 2, lado, lado); });
      g.fill();
    });
  };
  function cenaParticulas(canvas, cols, rows, quadro) {
    var pt = new Particulas(canvas, cols, rows);
    var visivel = false;
    if (observa) new IntersectionObserver(function (e) { visivel = e[0].isIntersecting; if (visivel) pedir(); }, { rootMargin: "80px" }).observe(canvas);
    window.EscaliburRelogio.aoMedir(function () { pt.medir(); });
    window.EscaliburRelogio.registrar(function (estado) {
      if (!visivel || document.hidden) return false;
      return quadro(pt, estado.t) !== false;
    });
    return pt;
  }

  // Os desenhos das Chaves, numa grade de 32: o cadeado e o mesmo da pagina Seguranca.
  var GC = 32;
  var CADEADO_FECHADO = deTexto(["..#####..", ".##...##.", ".#.....#.", ".#.....#.", "#########", "#########", "####.####", "####.####", "#########", "#########"], GC, GC, 7, 6, 2);
  var DESENHOS_CHAVE = [
    // O PIN: seis pontos.
    deTexto(["###.###.###", "###.###.###", "###.###.###", "...........", "###.###.###", "###.###.###", "###.###.###"], GC, GC, 5, 8, 2),
    // Argon2id: um bloco de memoria, cheio, que trabalha.
    (function () { var m = new Float32Array(GC * GC); for (var y = 6; y <= 25; y++) for (var x = 6; x <= 25; x++) m[y * GC + x] = 0.8; return m; })(),
    // O chip.
    deTexto([
      "...#..#..#...", "#############", "#...........#", "##..#####..##", "#...#...#...#",
      "##..#.#.#..##", "#...#...#...#", "##..#####..##", "#...........#", "#############", "...#..#..#..."], GC, GC, 3, 5, 2),
    CADEADO_FECHADO,
    // A assinatura: o visto.
    deTexto([
      "..........##", ".........###", "........###.", ".......###..", "#.....###...",
      "##..####....", ".#####......", "..###......."], GC, GC, 4, 8, 2),
  ];

  // MARK: Chaves: o PIN, a memoria, o chip, o cofre (o cadeado da pagina Seguranca, que abre)
  // e a assinatura. Os passos sao botoes: tocar leva ao passo (e a rolagem acompanha);
  // rolar tambem anda. Com movimento reduzido, o toque troca o desenho sem voo.
  var trilhoChaves = document.querySelector(".chaves-trilho");
  var telaChaves = document.querySelector(".pixels-chave");
  if (trilhoChaves && telaChaves) {
    var botoesChaves = Array.prototype.slice.call(document.querySelectorAll(".chaves-passo"));
    var numeroChaves = document.querySelector("[data-chaves-n]");
    var etapa = -1, travaAte = 0, prontaEm = 0;
    // A velocidade da rolagem, em telas por segundo, suavizada: so a rolagem longa e rapida
    // pula passos.
    var yAntes = null, tAntes = 0, velocidade = 0, gesto = null;
    var pxChaves;
    var mostrarEtapa = function (n, t) {
      if (n === etapa) return;
      etapa = n;
      botoesChaves.forEach(function (b, i) { b.classList.toggle("ativo", i === n); b.setAttribute("aria-pressed", String(i === n)); });
      if (numeroChaves) numeroChaves.textContent = String(n + 1);
      var detalheChaves = document.querySelector(".chaves-detalhe");
      if (detalheChaves) detalheChaves.textContent = botoesChaves[n].querySelector("span").textContent;
      // No celular os passos viram uma fileira: o escolhido fica a vista.
      var fileira = botoesChaves[n].closest(".chaves-passos");
      if (fileira && fileira.scrollWidth > fileira.clientWidth) {
        var li = botoesChaves[n].parentNode;
        fileira.scrollTo({ left: li.offsetLeft - (fileira.clientWidth - li.offsetWidth) / 2, behavior: movimento ? "smooth" : "auto" });
      }
      // Rapido, sem perder o voo (pedido do dono, 23/10/2026: a montagem demorava).
      pxChaves.formar(DESENHOS_CHAVE[n], movimento ? t : t - 10, { duracao: 0.5, espalha: 0.16 });
      // O passo seguinte so entra quando este termina de montar (0,5 s de voo e 0,16 s de espera).
      prontaEm = t + 0.7;
      pedir();
    };
    var progressoDe = function () {
      var r = trilhoChaves.getBoundingClientRect();
      return limitar(-r.top / Math.max(1, r.height - window.innerHeight), 0, 0.9999);
    };
    pxChaves = cenaParticulas(telaChaves, GC, GC, function (pt, t) {
      if (etapa < 0) mostrarEtapa(movimento ? Math.floor(progressoDe() * 5) : 0, t);
      if (movimento) {
        var yAgora = window.pageYOffset;
        if (yAntes !== null && t > tAntes) {
          var instante = Math.abs(yAgora - yAntes) / window.innerHeight / (t - tAntes);
          velocidade += (Math.min(instante, 20) - velocidade) * Math.min(1, (t - tAntes) * 6);
        }
        yAntes = yAgora; tAntes = t;
      }
      if (movimento && t > travaAte) {
        // Cada passo ocupa uma tela inteira de rolagem e so troca depois de passar 35% do
        // trecho seguinte (pedido do dono, 23/10/2026: pulava com um toque leve do trackpad).
        // Um passo de cada vez, depois que o desenho anterior montou. So a rolagem longa e
        // rapida vai direto: mais de 2 telas por segundo, por dois passos inteiros ou mais
        // desde o comeco do gesto.
        var seg = progressoDe() * 5, alvo = etapa;
        if (velocidade > 2 && gesto === null) gesto = seg;
        else if (velocidade < 0.5) gesto = null;
        if (seg >= etapa + 1.35) alvo = Math.min(4, Math.floor(seg - 0.35));
        else if (seg < etapa - 0.35) alvo = Math.max(0, Math.floor(seg + 0.35));
        if (alvo !== etapa) {
          if (gesto !== null && Math.abs(seg - gesto) >= 2) mostrarEtapa(alvo, t);
          else if (t >= prontaEm) mostrarEtapa(etapa + (alvo > etapa ? 1 : -1), t);
        }
      }
      pt.desenhar(t, {
        calmo: !movimento,
        extra: function (p, q, bit, tique) {
          // A memoria do Argon2id trabalhando: pixels que relampejam no bloco.
          if (etapa === 1) return ruido(p.id, tique, 17) > 0.9 ? 0.4 : 0;
          if (etapa === 2 && q.x > 13 && q.x < 19 && q.y > 13 && q.y < 19) return 0.2 * (0.5 + 0.5 * Math.sin(t * 3));
          return 0;
        },
      });
      return movimento;
    });
    botoesChaves.forEach(function (botao, n) {
      botao.addEventListener("click", function () {
        var t = performance.now() / 1000;
        if (movimento) {
          // Leva a rolagem ao meio do trecho deste passo, e o desenho ja troca.
          var r = trilhoChaves.getBoundingClientRect();
          var alcance = r.height - window.innerHeight;
          var alvo = window.pageYOffset + r.top + alcance * (n + 0.5) / 5;
          travaAte = t + 1.1;
          window.scrollTo({ top: alvo, behavior: "smooth" });
        }
        mostrarEtapa(n, t);
      });
    });
  }

  // MARK: Seguranca: o cadeado de pixels se monta das particulas espalhadas ja travado (a
  // haste fechada desde o inicio, pedido do dono, 23/10/2026), fica, se desfaz e se monta de
  // novo. Sozinho, sem anel e sem fundo.
  var telaCadeado = document.querySelector(".pixels-cadeado");
  if (telaCadeado) {
    var ciclo = null, fase = 0;
    cenaParticulas(telaCadeado, GC, GC, function (pt, t) {
      if (!movimento) {
        if (ciclo === null) { ciclo = t; pt.formar(CADEADO_FECHADO, t - 10, {}); }
        pt.desenhar(t, { calmo: true });
        return false;
      }
      if (ciclo === null) { ciclo = t; fase = 1; pt.formar(CADEADO_FECHADO, t, { de: "espalhado", duracao: 1.3, espalha: 0.6 }); }
      var dentro = t - ciclo;
      if (fase === 1 && dentro > 6.2) { fase = 2; pt.espalhar(t); }
      if (fase === 2 && dentro > 7.4) { ciclo = null; pt.lista = []; }
      pt.desenhar(t, {});
    });
  }

  // MARK: Privacidade: cada icone se monta em pixels quando aparece.
  cada(".pixels-icone", function (canvas) {
    var mapa = icone(canvas.getAttribute("data-icone"));
    var feito = false;
    cenaPixels(canvas, 16, 16, { fundo: 0.05, ritmo: 3, cifra: 0.18 }, function (px, t) {
      if (!feito) { feito = true; px.mudar(mapa, movimento ? t + 0.2 : t - 10, { duracao: 1.1, varrer: "acaso" }); }
      px.desenhar(t, { calmo: !movimento });
      return movimento;
    });
  });

  // MARK: Hashes de commit em pixels (inicio, Novidades e Auditoria): cada digito
  // hexadecimal vira um tom de cinza. Linha a linha (um hash numa grade) ou coluna a coluna
  // (a parede da pagina Novidades: um commit por coluna, os 8 primeiros digitos). Decifram da
  // esquerda para a direita quando aparecem.
  cada(".pixels-hash", function (canvas, i) {
    var hashes = (canvas.getAttribute("data-hashes") || "").split(",").filter(function (h) { return /^[0-9a-f]{40}$/.test(h); });
    if (!hashes.length) return;
    var colunas = Number(canvas.getAttribute("data-colunas")) || 20, linhas = Number(canvas.getAttribute("data-linhas")) || 2;
    var porColuna = canvas.getAttribute("data-ordem") === "coluna";
    var mapa = new Float32Array(colunas * linhas);
    for (var c = 0; c < colunas; c++) for (var l = 0; l < linhas; l++) {
      var digito = porColuna ? hashes[c % hashes.length][l] : hashes[0][(l * colunas + c) % 40];
      mapa[l * colunas + c] = 0.1 + parseInt(digito, 16) / 15 * 0.9;
    }
    var feito = false;
    cenaPixels(canvas, colunas, linhas, { fundo: 0.05, ritmo: 4, cifra: 0.2 }, function (px, t) {
      var atraso = canvas.hasAttribute("data-atraso") ? Number(canvas.getAttribute("data-atraso")) : 0.2 + (i % 6) * 0.12;
      if (!feito) { feito = true; px.mudar(mapa, movimento ? t + atraso : t - 10, { duracao: porColuna ? 2 : 1.2, varrer: "esquerda" }); }
      px.desenhar(t, { calmo: !movimento, passada: -99 });
      return movimento;
    });
  });

  // Novidades: aberta pelo link de uma entrega (#c-xxxxxxx), ela ja vem expandida.
  var abrirNovidade = function () {
    var alvo = window.location.hash && document.getElementById(window.location.hash.slice(1));
    var detalhe = alvo && alvo.classList.contains("entrega") ? alvo.querySelector("details") : null;
    if (detalhe) { detalhe.open = true; alvo.classList.add("destacada"); }
  };
  abrirNovidade();
  window.addEventListener("hashchange", abrirNovidade);

  // MARK: Texto que decifra: os glifos do app (os mesmos 16 do LiveCipher, em minuscula,
  // para a linha nao pular) trocam ate a letra de verdade, da esquerda para a direita.
  var GLIFOS = "0123456789abcdef";
  function glifoDe(i, tique) { return GLIFOS[Math.floor(ruido(i, tique, 41) * 16)]; }
  function decifrar(el, duracao) {
    if (!movimento || !el) return;
    var nos = [];
    (function andar(no) {
      if (no.nodeType === 3) { if (no.nodeValue.trim()) nos.push({ no: no, texto: no.nodeValue }); return; }
      for (var c = no.firstChild; c; c = c.nextSibling) andar(c);
    })(el);
    var total = nos.reduce(function (s, n) { return s + n.texto.length; }, 0);
    if (!total) return;
    var dur = duracao || 0.7, t0 = agoraS();
    el.setAttribute("data-decifrando", "");
    var passo = function () {
      var t = agoraS() - t0, tique = Math.floor(t * 14), base = 0;
      nos.forEach(function (n) {
        var saida = "";
        for (var k = 0; k < n.texto.length; k++) {
          var ch = n.texto[k], limite = ((base + k) / total) * dur * 0.75 + ruido(base + k, 5, 9) * dur * 0.25;
          saida += t >= limite || /\s/.test(ch) ? ch : glifoDe(base + k, tique);
        }
        n.no.nodeValue = saida;
        base += n.texto.length;
      });
      if (t < dur) window.requestAnimationFrame(passo);
      else { nos.forEach(function (n) { n.no.nodeValue = n.texto; }); el.removeAttribute("data-decifrando"); }
    };
    window.requestAnimationFrame(passo);
  }
  window.EscaliburDecifrar = decifrar;


  // MARK: O golpe do endereco parecido: o meio do falso decifra quando aparece, e as seis
  // caixas se preenchem, uma a uma.
  var golpe = document.querySelector(".golpe");
  if (golpe && movimento && observa) {
    var caixas = Array.prototype.slice.call(golpe.querySelectorAll(".golpe-caixas i"));
    var letras = ["2", "0", "d", "3", "7", "4"];
    var timers = [];
    var tocarGolpe = function () {
      timers.forEach(clearTimeout); timers = [];
      decifrar(golpe.querySelector("[data-cifra-meio]"), 1.1);
      caixas.forEach(function (c) { c.textContent = ""; c.className = ""; });
      caixas[0].className = "cursor";
      letras.forEach(function (l, i) {
        timers.push(setTimeout(function () {
          caixas[i].textContent = l;
          caixas[i].className = "";
          if (caixas[i + 1]) caixas[i + 1].className = "cursor";
        }, 1300 + i * 260));
      });
    };
    new IntersectionObserver(function (e) { if (e[0].isIntersecting) tocarGolpe(); }, { threshold: 0.45 }).observe(golpe);
  }

  // MARK: Codigo auditavel: uma rodada do verificador, linha a linha, quando aparece.
  var feed = document.querySelector(".feed-verificacoes");
  if (feed && movimento && observa) {
    var linhasFeed = Array.prototype.slice.call(feed.querySelectorAll("li"));
    var timersFeed = [];
    new IntersectionObserver(function (e) {
      timersFeed.forEach(clearTimeout); timersFeed = [];
      if (!e[0].isIntersecting) { linhasFeed.forEach(function (li) { li.classList.remove("ok"); }); return; }
      linhasFeed.forEach(function (li, i) { timersFeed.push(setTimeout(function () { li.classList.add("ok"); }, 250 + i * 320)); });
    }, { threshold: 0.35 }).observe(feed);
  }

  // O podio do fim sobe quando aparece.
  var podio = document.querySelector(".podio");
  if (podio && movimento && observa) {
    new IntersectionObserver(function (e) { if (e[0].isIntersecting) podio.classList.add("visivel"); }, { threshold: 0.15 }).observe(podio);
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
  if (pode3D() && document.querySelector(".abertura-3d, .destaque-3d, .final-3d, .redes-3d")) {
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
