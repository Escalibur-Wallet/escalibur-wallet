package app.escalibur.wallet.ui.bloqueio

import app.escalibur.wallet.ui.ajustes.mensagemDaEspera
import app.escalibur.wallet.ui.comp.CabecalhoDaFolha
import app.escalibur.wallet.ui.comp.FolhaSolta
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.scale
import app.escalibur.wallet.ui.comp.PixelsCifrando
import app.escalibur.wallet.ui.comp.movimentoReduzido
import app.escalibur.wallet.ui.comp.relogio
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.BotaoDestrutivo
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Confirmacao
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.SeloDaCarteira
import app.escalibur.wallet.ui.pin.EntradaDoPin
import app.escalibur.wallet.ui.pin.TelaDoPin
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import app.escalibur.wallet.vigias.Vigia
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * O app trancado. A biometria dispara sozinha quando o app vem para a frente, uma vez a cada vinda
 * (`vinda` muda a cada retorno ao primeiro plano).
 */
@Composable
fun TelaDeBloqueio(vinda: Int) {
    val estado = App.estado
    val entrada = remember { EntradaDoPin(estado.pinDigitos) }
    var trabalhando by remember { mutableStateOf(false) }
    var esqueci by remember { mutableStateOf(false) }
    var cofrePerdido by remember { mutableStateOf(false) }
    val escopo = rememberCoroutineScope()
    val depoisDeReiniciar = estado.biometriaLigada && estado.pedePINDepoisDeReiniciar
    var atraso by remember { mutableStateOf(estado.atraso) }

    LaunchedEffect(estado.pinDigitos) { entrada.usarTamanhos(estado.pinDigitos) }

    // A espera depois de erros, contando na tela.
    LaunchedEffect(atraso) {
        if (atraso <= 0) return@LaunchedEffect
        var restante = atraso
        while (restante > 0) {
            entrada.erro = t("Tentativas demais. Tente de novo em %@.", Formato.duracao(restante))
            delay(1000)
            restante -= 1
        }
        entrada.erro = null
        App.recarregar()
    }

    suspend fun tentarBiometria() {
        if (!App.estado.biometriaLigada || App.estado.atraso > 0) return
        try {
            App.aplicar(Api.objeto("sessao.destrancarBiometria"))
        } catch (falha: FalhaDoNucleo) {
            when (falha.codigo) {
                "cofre.pinRequiredAfterRestart" -> entrada.falhar(t("O celular reiniciou. Digite o PIN uma vez para a biometria voltar a valer."))
                "cofre.biometryChanged" -> entrada.falhar(t("A biometria deste celular mudou desde que foi ligada aqui. Entre com o PIN; depois você pode religar."))
                else -> Unit // cancelada: o teclado continua ali
            }
            App.recarregar()
        }
    }

    // Super Security: a biometria antes do PIN (pedido do dono, 01/11/2026). Confirmada, o nucleo guarda
    // para o proximo PIN so; cancelada, o teclado continua, e o PIN pede a biometria depois.
    var rostoConfirmado by remember { mutableStateOf(false) }
    suspend fun confirmarRosto() {
        if (!App.estado.reforcado || rostoConfirmado || App.estado.atraso > 0) return
        try {
            Api.objeto("sessao.confirmarRosto", JSONObject().put("motivo", t("Destravar a Escalibur")).put("abrir", true))
            rostoConfirmado = true
        } catch (falha: FalhaDoNucleo) {
            if (falha.codigo != "cofre.biometriaNaoConfirmou") entrada.falhar(Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível destravar. Tente de novo."))
            App.recarregar()
        }
    }

    LaunchedEffect(vinda) {
        atraso = App.estado.atraso
        rostoConfirmado = false
        // Com a atualizacao obrigatoria na tela, a biometria automatica nao abre por cima dela.
        if (app.escalibur.wallet.ui.atualizar.Atualizacao.cobrindo) return@LaunchedEffect
        if (App.estado.reforcado) confirmarRosto()
        else if (App.estado.biometriaLigada && !App.estado.pedePINDepoisDeReiniciar) tentarBiometria()
    }

    TelaDoPin(
        titulo = t("Digite o seu PIN"),
        subtitulo = when {
            // A espera de "Esperar 24 horas", se correndo: abrir o app vale, o saldo aparece e o resto espera.
            estado.reforcado && estado.espera > 0 -> mensagemDaEspera(estado.espera)
            estado.reforcado && rostoConfirmado -> t("A biometria confirmou. Agora o PIN.")
            estado.reforcado -> t("Super Security: primeiro a biometria, depois o PIN.")
            depoisDeReiniciar -> t("O celular reiniciou. Depois de reiniciar ou de a bateria acabar, o PIN é necessário uma vez antes de a biometria voltar a valer.")
            else -> null
        },
        entrada = entrada,
        trabalhando = trabalhando,
        topo = { SeloDaCarteira(44.dp, modifier = Modifier.padding(bottom = Espaco.md)) },
        iconeDeBiometria = when {
            estado.reforcado -> if (rostoConfirmado) null else Icones.digital
            estado.biometriaLigada && !depoisDeReiniciar -> Icones.digital
            else -> null
        },
        aoUsarBiometria = { escopo.launch { if (App.estado.reforcado) confirmarRosto() else tentarBiometria() } },
        aoCompletar = {
            val pin = entrada.tirar()
            trabalhando = true
            // A biometria confirmada vale este PIN so, certo ou errado.
            val comRosto = rostoConfirmado
            rostoConfirmado = false
            escopo.launch {
                try {
                    App.aplicar(Api.comSegredo("sessao.destrancar", JSONObject(), pin))
                } catch (falha: FalhaDoNucleo) {
                    when (falha.codigo) {
                        "cofre.pinErrado" -> entrada.falhar(Autorizacao.mensagemDePinErrado(falha))
                        "cofre.espera" -> entrada.falhar(t("Tentativas demais. Tente de novo em %@.", Formato.duracao(falha.segundos)))
                        "cofre.wiped" -> {
                            // O cofre ja se apagou: a gaveta sai mesmo se a limpeza do resto falhar.
                            Vigia.limparGaveta()
                            runCatching { App.aplicar(Api.objeto("sessao.apagarTudo")) }
                        }
                        // Super Security com a biometria trocada em "Bloquear as carteiras": o cofre nao abre mais,
                        // e apagar nao espera as 24 horas (como o iOS).
                        "cofre.hardenedSlotLost" -> {
                            cofrePerdido = true
                            esqueci = true
                        }
                        "cofre.biometriaNaoConfirmou" -> entrada.falhar(Autorizacao.mensagemDeBiometriaNaoConfirmou(falha.restantes))
                        else -> entrada.falhar(Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível destravar. Tente de novo."))
                    }
                    App.recarregar()
                    atraso = App.estado.atraso
                    // O proximo PIN pede a biometria antes de novo.
                    if (comRosto && App.estado.reforcado && !cofrePerdido) confirmarRosto()
                } finally {
                    trabalhando = false
                }
            }
        },
    ) {
        BotaoTerciario(t("Esqueci o PIN")) { esqueci = true }
    }
    if (esqueci) FolhaEsqueciOPin(cofrePerdido) { esqueci = false; cofrePerdido = false }
}

/** Nao existe redefinir o PIN: o caminho e apagar e importar cada carteira de novo. */
@Composable
private fun FolhaEsqueciOPin(perdido: Boolean, aoFechar: () -> Unit) {
    var confirmar by remember { mutableStateOf(false) }
    val escopo = rememberCoroutineScope()
    // O pedido de apagar: null sem pedido, 0 pronto, mais que 0 o que falta. Apagar pela tela de bloqueio
    // so 24 horas depois do pedido: quem pega o celular destravado nao apaga as carteiras do dono na hora
    // (revisao de seguranca de 27/10/2026).
    var restante by remember { mutableStateOf<Double?>(null) }
    var lido by remember { mutableStateOf(false) }
    fun ler(resposta: JSONObject) { restante = if (resposta.has("restante")) resposta.getDouble("restante") else null }
    var falhou by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        // A contagem anda com a folha aberta.
        while (true) {
            runCatching { ler(Api.objeto("sessao.esqueciPIN")) }
            lido = true
            kotlinx.coroutines.delay(30_000)
        }
    }
    FolhaSolta(aoFechar) {
    Column(Modifier.fillMaxSize().navigationBarsPadding()) {
        CabecalhoDaFolha("", aoFechar)
        // Redesenho do dono (01/11/2026, o mesmo do iOS): sem o icone num circulo nem o cartao de passos
        // numerados, que tinham cara de template. A cena de pixels conta a saida, e o texto vai a esquerda.
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem),
            horizontalAlignment = Alignment.Start,
        ) {
            CenaEsqueciOPin()
            Text(if (perdido) t("A biometria mudou") else t("Não existe redefinir o PIN"), style = estilo(Tipo.titulo), color = Paleta.tinta,
                 modifier = Modifier.padding(top = Espaco.md))
            Text(
                if (perdido) t("No Super Security, as carteiras deste celular só abrem com o PIN e a mesma biometria de quando ele foi ligado. O cadastro mudou, e ninguém consegue abrir, nem a Escalibur. Para voltar a usar o app, comece de novo:")
                else t("O PIN mora só neste celular, e ninguém tem cópia dele, nem a Escalibur. Para voltar a usar o app, comece de novo:"),
                style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs),
            )
            Column(
                Modifier.fillMaxWidth().padding(top = Espaco.lg),
                verticalArrangement = Arrangement.spacedBy(Espaco.base),
            ) {
                Passo(1, t("Tenha em mãos a senha de cada carteira (as 12 ou 24 palavras) ou o envelope Escalibur, e a passphrase de cada carteira que usa passphrase."))
                Passo(2, t("Apague as carteiras deste celular."))
                Passo(3, t("Crie um PIN novo e importe cada carteira de novo."))
            }
        }
        Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.sm, bottom = Espaco.xs), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            val falta = restante
            when {
                // O cofre ja nao abre: apagar na hora, com "Tentar de novo" antes (o motivo pode ter sido passageiro).
                perdido -> {
                    BotaoPrimario(t("Tentar de novo"), acao = aoFechar)
                    BotaoDestrutivo(t("Apagar as carteiras deste celular")) { confirmar = true }
                }
                !lido -> {}
                falta == null -> {
                    if (falhou) Text(t("Não foi possível fazer o pedido agora. Tente de novo."), style = estilo(Tipo.nota), color = Paleta.baixa,
                                     textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                    BotaoDestrutivo(t("Pedir para apagar em 24 horas")) {
                        escopo.launch { falhou = runCatching { ler(Api.objeto("sessao.pedirApagar")) }.isFailure }
                    }
                }
                falta > 0 -> {
                    Text(t("Apagar fica disponível em %@. Reiniciar o aparelho recomeça a contagem. Se lembrar o PIN, é só destravar: o pedido some.", Formato.duracao(falta)),
                         style = estilo(Tipo.nota), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                    BotaoTerciario(t("Cancelar o pedido"), Modifier.fillMaxWidth()) {
                        escopo.launch { runCatching { Api.objeto("sessao.cancelarApagar") }; restante = null }
                    }
                }
                else -> BotaoDestrutivo(t("Apagar as carteiras deste celular")) { confirmar = true }
            }
            BotaoSecundario(t("Voltar e tentar o PIN"), acao = aoFechar)
        }
    }
    }
    if (confirmar) {
        Confirmacao(
            titulo = t("Apagar as carteiras deste celular?"),
            mensagem = t("Sem a senha de cada carteira ou um envelope, e a passphrase das que usam passphrase, o saldo delas fica inacessível para sempre."),
            tituloDaAcao = t("Apagar permanentemente"),
            aoConfirmar = {
                confirmar = false
                escopo.launch {
                    // O nucleo confere de novo (espera cumprida ou cofre perdido) e pode recusar: sem derrubar o app.
                    runCatching { App.aplicar(Api.objeto("sessao.apagarTudo")) }.onSuccess { Vigia.limparGaveta() }
                    aoFechar()
                }
            },
            aoCancelar = { confirmar = false },
        )
    }
}

/** Um passo: o numero no mesmo tipo do texto, mais apagado, sem circulo nem cartao. */
@Composable
private fun Passo(numero: Int, texto: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Text("$numero", style = estilo(Tipo.linha), color = Paleta.tintaApagada, modifier = Modifier.width(16.dp))
        Text(texto, style = estilo(Tipo.corpo), color = Paleta.tinta)
    }
}

/**
 * A saida de quem esqueceu o PIN, em pixels que cifram (o `ForgotPINScene` do iOS): os seis pontos do
 * PIN se desfazem em ruido, as palavras anotadas aparecem uma a uma e sobem para virar um PIN novo, em
 * lima. Nada aqui e de verdade: pontos e palavras sao desenho.
 */
@Composable
private fun CenaEsqueciOPin() {
    val parado = movimentoReduzido()
    val segundos by relogio(parado)
    Canvas(Modifier.fillMaxWidth().height(176.dp)) {
        val periodo = 7.2
        val t = if (parado) 5.6 else (segundos.toDouble() % periodo)
        val escala = minOf(size.width / 300f, size.height / 176f)
        translate((size.width - 300f * escala) / 2, (size.height - 176f * escala) / 2) {
            scale(escala, escala, pivot = Offset.Zero) {
                val brilho = if (parado) 1.0 else minOf(suave(t / 0.3), 1 - suave((t - (periodo - 0.45)) / 0.45))
                desenharEsqueci(t, if (parado) 0.0 else segundos.toDouble(), brilho)
            }
        }
    }
}

private fun suave(x: Double): Double { val t = x.coerceIn(0.0, 1.0); return t * t * (3 - 2 * t) }

private fun DrawScope.desenharEsqueci(t: Double, relogio: Double, brilho: Double) {
    val passo = 6f
    val celula = 4.6f
    fun tom(id: Int, camada: Int): Double {
        val fase = PixelsCifrando.ruido(id, camada, 0x5F1)
        val batida = relogio * 4 * (0.6 + 0.8 * fase) + fase * 8
        val degrau = kotlin.math.floor(batida)
        val s = batida - degrau
        val a = PixelsCifrando.ruido(id, camada, degrau.toLong())
        val b = PixelsCifrando.ruido(id, camada, degrau.toLong() + 1)
        return a + (b - a) * s * s * (3 - 2 * s)
    }
    fun ponto(centro: Offset, cor: Color, alfa: Double) {
        val a = (alfa * brilho).toFloat()
        if (a <= 0.01f) return
        drawRoundRect(cor.copy(alpha = a), Offset(centro.x - celula / 2, centro.y - celula / 2), Size(celula, celula), CornerRadius(celula * 0.24f))
    }
    // Os seis pontos do PIN: 3 por 3 pixels cada, com 4 pixels entre eles.
    val larguraDosPontos = (6 * 3 + 5 * 4) * passo
    val xDosPontos = (300f - larguraDosPontos) / 2
    fun pixelDoPin(i: Int): Offset {
        val ponto = i / 9; val dentro = i % 9
        val coluna = ponto * 7 + dentro % 3
        return Offset(xDosPontos + (coluna + 0.5f) * passo, 40f + (dentro / 3 + 0.5f) * passo)
    }
    val pixelsDoPin = 6 * 9
    // 1. O PIN de antes: aceso, e depois se desfaz em ruido, cada pixel para um lado.
    val desfaz = suave((t - 0.9) / 1.5)
    for (i in 0 until pixelsDoPin) {
        val casa = pixelDoPin(i)
        val espalha = desfaz.toFloat() * 30
        val dx = (PixelsCifrando.ruido(i, 3, 1).toFloat() - 0.5f) * espalha * 2
        val dy = (PixelsCifrando.ruido(i, 3, 2).toFloat() - 0.5f) * espalha * 2 - desfaz.toFloat() * 8
        val valor = if (desfaz > 0) 0.3 + 0.45 * tom(i, 2) else 0.9
        ponto(Offset(casa.x + dx, casa.y + dy), PixelsCifrando.cinza(valor), 1 - suave((desfaz - 0.45) / 0.55))
    }
    // 2. As palavras anotadas aparecem, uma pastilha de cada vez.
    val xDasPalavras = (300f - (6 * 5 + 5) * passo) / 2
    data class Px(val casa: Offset, val id: Int, val aparece: Double)
    val pixels = ArrayList<Px>()
    for (pastilha in 0 until 12) {
        val aparece = suave((t - 2.3 - pastilha * 0.09) / 0.35)
        for (px in 0 until 5) for (py in 0 until 2) {
            pixels.add(Px(Offset(xDasPalavras + ((pastilha % 6) * 6 + px + 0.5f) * passo, 104f + ((pastilha / 6) * 3 + py + 0.5f) * passo),
                          pastilha * 10 + px * 2 + py, aparece))
        }
    }
    // 3. As palavras sobem e viram o PIN novo, em lima: so quem tem as palavras volta.
    val sobe = suave((t - 4.0) / 1.3)
    pixels.forEachIndexed { i, p ->
        val atraso = PixelsCifrando.ruido(p.id, 9, 0x2C) * 0.4
        val f = suave((sobe - atraso) / (1 - atraso + 0.0001))
        val alvo = pixelDoPin(i % pixelsDoPin)
        val x = p.casa.x + (alvo.x - p.casa.x) * f.toFloat()
        val y = p.casa.y + (alvo.y - p.casa.y) * f.toFloat() - kotlin.math.sin(f * Math.PI).toFloat() * 14
        ponto(Offset(x, y), PixelsCifrando.cinza(0.42 + 0.36 * tom(p.id, 5)), p.aparece * (1 - suave((f - 0.8) / 0.2)))
    }
    val assentou = suave((t - 5.0) / 0.5)
    for (i in 0 until pixelsDoPin) ponto(pixelDoPin(i), Paleta.lima, assentou)
    // As palavras ficam, apagadas, depois de virar o PIN: elas continuam sendo a saida.
    for (p in pixels) ponto(p.casa, PixelsCifrando.cinza(0.2 + 0.12 * tom(p.id, 6)), assentou * 0.9)
}
