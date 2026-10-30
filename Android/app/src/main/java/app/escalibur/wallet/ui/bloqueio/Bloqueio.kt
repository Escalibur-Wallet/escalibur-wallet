package app.escalibur.wallet.ui.bloqueio

import app.escalibur.wallet.ui.comp.CabecalhoDaFolha
import app.escalibur.wallet.ui.comp.FolhaSolta
import androidx.activity.compose.BackHandler
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

    LaunchedEffect(vinda) {
        atraso = App.estado.atraso
        if (App.estado.biometriaLigada && !App.estado.pedePINDepoisDeReiniciar) tentarBiometria()
    }

    TelaDoPin(
        titulo = t("Digite o seu PIN"),
        subtitulo = when {
            estado.reforcado -> t("Super Security: depois do PIN, a biometria confirma que é você.")
            depoisDeReiniciar -> t("O celular reiniciou. Depois de reiniciar ou de a bateria acabar, o PIN é necessário uma vez antes de a biometria voltar a valer.")
            else -> null
        },
        entrada = entrada,
        trabalhando = trabalhando,
        topo = { SeloDaCarteira(44.dp, modifier = Modifier.padding(bottom = Espaco.md)) },
        iconeDeBiometria = if (estado.biometriaLigada && !depoisDeReiniciar) Icones.digital else null,
        aoUsarBiometria = { escopo.launch { tentarBiometria() } },
        aoCompletar = {
            val pin = entrada.tirar()
            trabalhando = true
            escopo.launch {
                try {
                    App.aplicar(Api.comSegredo("sessao.destrancar", JSONObject(), pin))
                } catch (falha: FalhaDoNucleo) {
                    when (falha.codigo) {
                        "cofre.pinErrado" -> entrada.falhar(Autorizacao.mensagemDePinErrado(falha))
                        "cofre.espera" -> entrada.falhar(t("Tentativas demais. Tente de novo em %@.", Formato.duracao(falha.segundos)))
                        "cofre.wiped" -> runCatching { App.aplicar(Api.objeto("sessao.apagarTudo")) }
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
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(Modifier.size(72.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                Icone(Icones.celularComCadeado, Paleta.tinta, tamanho = 34.dp)
            }
            Text(if (perdido) t("A biometria mudou") else t("Não existe redefinir o PIN"), style = estilo(Tipo.titulo), color = Paleta.tinta,
                 textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.md))
            Text(
                if (perdido) t("No Super Security, as carteiras deste celular só abrem com o PIN e a mesma biometria de quando ele foi ligado. O cadastro mudou, e ninguém consegue abrir, nem a Escalibur. Para voltar a usar o app, comece de novo:")
                else t("O PIN mora só neste celular, e ninguém tem cópia dele, nem a Escalibur. Para voltar a usar o app, comece de novo:"),
                style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs),
            )
            Column(
                Modifier.fillMaxWidth().padding(top = Espaco.lg).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.trilho).padding(Espaco.base),
                verticalArrangement = Arrangement.spacedBy(Espaco.md),
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
                    runCatching { App.aplicar(Api.objeto("sessao.apagarTudo")) }
                    aoFechar()
                }
            },
            aoCancelar = { confirmar = false },
        )
    }
}

@Composable
private fun Passo(numero: Int, texto: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(28.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Text("$numero", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Paleta.tinta)
        }
        Text(texto, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.padding(top = 3.dp))
    }
}
