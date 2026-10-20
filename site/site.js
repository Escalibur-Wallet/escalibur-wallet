// O unico script do site, servido do proprio site (CSP script-src 'self'). Sem ele tudo
// continua legivel: os videos mostram a capa, a lista de tokens aparece inteira e o
// menu do celular abre pelo <details>. Com ele: os videos tocam so quando aparecem na
// tela (e param ao sair), cada um com botao de pausar, nada toca sozinho com
// "reduzir movimento" ligado, e a lista de tokens ganha a busca.
(function () {
  "use strict";

  var raiz = document.documentElement;
  raiz.classList.add("js");

  var calmo = window.matchMedia ? window.matchMedia("(prefers-reduced-motion: reduce)") : { matches: false };
  var videos = Array.prototype.slice.call(document.querySelectorAll("video[data-auto]"));

  function botaoDe(video) {
    var aparelho = video.closest(".aparelho");
    return aparelho ? aparelho.querySelector(".pausar") : null;
  }

  function mostrar(video, estado) {
    var botao = botaoDe(video);
    if (!botao) return;
    botao.setAttribute("data-estado", estado);
    botao.setAttribute("aria-label", estado === "pausado" ? "Tocar a animação" : "Pausar a animação");
  }

  function tocar(video) {
    video.muted = true;
    if (video.preload !== "auto") video.preload = "auto";
    var promessa = video.play();
    mostrar(video, "tocando");
    if (promessa && promessa.catch) {
      promessa.catch(function () { mostrar(video, "pausado"); });
    }
  }

  videos.forEach(function (video) {
    mostrar(video, "pausado");
    // O video aparece por cima da capa so quando ja tem quadro para mostrar.
    video.addEventListener("playing", function () { video.classList.add("visivel"); });
    var botao = botaoDe(video);
    if (!botao) return;
    botao.addEventListener("click", function () {
      if (video.paused) {
        video.removeAttribute("data-parado");
        tocar(video);
      } else {
        video.setAttribute("data-parado", "");
        video.pause();
        mostrar(video, "pausado");
      }
    });
  });

  if (!calmo.matches && "IntersectionObserver" in window) {
    var observador = new IntersectionObserver(function (entradas) {
      entradas.forEach(function (entrada) {
        var video = entrada.target;
        if (entrada.isIntersecting && entrada.intersectionRatio >= 0.35) {
          if (!video.hasAttribute("data-parado") && video.paused) tocar(video);
        } else if (!video.paused) {
          video.pause();
          if (!video.hasAttribute("data-parado")) mostrar(video, "pausado");
        }
      });
    }, { threshold: [0, 0.35, 0.7] });
    videos.forEach(function (video) { observador.observe(video); });
  }

  // Abertura: as moedas voam para a tela do iPhone do meio conforme a pagina rola. O
  // caminho de cada uma e medido no carregamento e quando a janela muda; a rolagem so
  // atualiza duas variaveis (--p e --s), e o resto e do CSS, na placa de video.
  var abertura = document.querySelector(".abertura");
  var moedas = abertura ? Array.prototype.slice.call(abertura.querySelectorAll(".abertura-moedas .moeda")) : [];
  var alvo = abertura ? abertura.querySelector(".abertura-aparelhos .aparelho:not(.lado) .tela") : null;
  if (moedas.length && alvo && !calmo.matches) {
    var pedido = false;
    var medir = function () {
      var caixa = abertura.getBoundingClientRect();
      var tela = alvo.getBoundingClientRect();
      var cx = tela.left - caixa.left + tela.width / 2;
      var cy = tela.top - caixa.top + tela.height * 0.42;
      moedas.forEach(function (moeda) {
        var x = moeda.offsetLeft + moeda.offsetWidth / 2;
        var y = moeda.offsetTop + moeda.offsetHeight / 2;
        moeda.style.setProperty("--tx", (cx - x).toFixed(1) + "px");
        moeda.style.setProperty("--ty", (cy - y).toFixed(1) + "px");
      });
    };
    var quadro = function () {
      pedido = false;
      var rolado = Math.max(0, -abertura.getBoundingClientRect().top);
      var bruto = Math.min(1, rolado / Math.max(1, abertura.offsetHeight * 0.55));
      var p = bruto * bruto * (3 - 2 * bruto);
      abertura.style.setProperty("--p", p.toFixed(4));
      abertura.style.setProperty("--s", Math.min(rolado, abertura.offsetHeight).toFixed(1) + "px");
    };
    var pedir = function () {
      if (pedido) return;
      pedido = true;
      window.requestAnimationFrame(quadro);
    };
    medir();
    quadro();
    window.addEventListener("scroll", pedir, { passive: true });
    window.addEventListener("resize", function () { medir(); pedir(); });
    window.addEventListener("load", function () { medir(); pedir(); });
  }

  // Busca na lista de tokens (redes/): por simbolo, nome ou rede.
  var campo = document.getElementById("busca-token");
  if (campo) {
    var itens = Array.prototype.slice.call(document.querySelectorAll("[data-busca]"));
    var vazio = document.getElementById("busca-vazia");
    var normalizar = function (texto) {
      return texto.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
    };
    campo.addEventListener("input", function () {
      var termo = normalizar(campo.value);
      var achados = 0;
      itens.forEach(function (item) {
        var mostra = !termo || item.getAttribute("data-busca").indexOf(termo) >= 0;
        item.hidden = !mostra;
        if (mostra) achados += 1;
      });
      if (vazio) vazio.hidden = achados > 0;
    });
  }

  // Suporte: o questionario do app (assunto, rede, o que aconteceu, e-mail duas vezes) vira
  // um e-mail pronto no app de e-mail de quem escreve. O site nao manda nada sozinho. Texto
  // com seis palavras BIP-39 seguidas nao sai, como no app.
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
    var lista = null;

    var assunto = function () { return chamado.querySelector('input[name="assunto"]:checked'); };
    var semAcento = function (texto) { return texto.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase(); };
    var seguidas = function (texto) {
      if (!lista) {
        if (!window.PALAVRAS_BIP39) return 0;
        lista = new Set(window.PALAVRAS_BIP39.map(semAcento));
      }
      var maior = 0, atual = 0;
      semAcento(texto).split(/[^a-z]+/).forEach(function (palavra) {
        if (!palavra) return;
        atual = lista.has(palavra) ? atual + 1 : 0;
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
