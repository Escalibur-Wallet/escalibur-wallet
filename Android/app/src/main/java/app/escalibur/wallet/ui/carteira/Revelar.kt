package app.escalibur.wallet.ui.carteira

import app.escalibur.wallet.ui.comp.EmblemaCifrado
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import app.escalibur.wallet.ui.comp.acimaDoTeclado
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import app.escalibur.wallet.ui.comp.Segredo
import androidx.compose.foundation.text.input.clearText
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.BotaoDeCanto
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.enviar.PedidoDePassphrase
import app.escalibur.wallet.ui.importar.CampoSecreto
import app.escalibur.wallet.ui.novacarteira.ConferirPalavras
import app.escalibur.wallet.ui.novacarteira.GravarPalavras
import app.escalibur.wallet.ui.novacarteira.Trabalhando
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.Date

/**
 * Ver as palavras de uma carteira guardada, ou fazer a copia que faltou ("Gravar agora"), que
 * termina na conferencia digitada e, na carteira com passphrase, na conferencia dela (o RevealFlow
 * e o BackupNowFlow do iOS). As palavras ficam no nucleo; so o grupo na tela vira texto.
 */
@Composable
fun FluxoDeRevelar(carteira: Carteira, copia: Boolean, aoFechar: () -> Unit) {
    val escopo = rememberCoroutineScope()
    // Palavras ja conferidas e passphrase nao: o "Gravar agora" e so a passphrase, pelo cofre.
    val soAPassphrase = copia && carteira.palavrasConfirmadas && !carteira.passphraseConfirmada
    var etapa by remember { mutableStateOf(if (soAPassphrase) "passphrase" else "aviso") }
    var palavras by remember { mutableStateOf(carteira.palavras ?: 12) }
    var comPassphrase by remember { mutableStateOf(false) }
    var abrindo by remember { mutableStateOf(false) }
    var erro by remember { mutableStateOf<String?>(null) }

    fun fechar() {
        CoroutineScope(Dispatchers.IO).launch { runCatching { App.aplicar(Api.objeto("carteira.terminarRevelacao", JSONObject().put("id", carteira.id))) } }
        aoFechar()
    }
    DisposableEffect(Unit) {
        onDispose { CoroutineScope(Dispatchers.IO).launch { runCatching { Api.objeto("carteira.terminarRevelacao", JSONObject().put("id", carteira.id)) } } }
    }

    fun abrir() {
        erro = null
        escopo.launch {
            var passphrase: PedidoDePassphrase.Resposta? = null
            if (carteira.pedePassphrase) {
                passphrase = PedidoDePassphrase.pedir(carteira.nome,
                    t("%@ mostra as palavras e a passphrase. Digite a passphrase para seguir; depois vem a confirmação de sempre.", carteira.nome)) ?: return@launch
            }
            abrindo = true
            try {
                val segredo = passphrase?.bytes
                val aberto = Autorizacao.tentando(t("Ver a senha de %@", carteira.nome), Autorizacao.Presenca.pinEBiometria) { credencial ->
                    val partes = if (segredo != null) credencial.partes(segredo.copyOf()) else credencial.partes()
                    Api.comSegredo("carteira.revelar", JSONObject().put("id", carteira.id).put("credencial", credencial.json()), *partes)
                } ?: return@launch
                palavras = aberto.getInt("palavras")
                comPassphrase = aberto.getBoolean("passphrase")
                etapa = "palavras"
            } catch (falha: FalhaDoNucleo) {
                erro = when (falha.codigo) {
                    "passphrase.errada" -> t("A passphrase não confere. Nada foi assinado. Escreva igual ao que você anotou: maiúscula, acento e espaço contam.")
                    "passphrase.espera" -> t("Muitas passphrases erradas. Tente de novo às %@.", Formato.relogio(Date(falha.dados.optDouble("ate", 0.0).toLong())))
                    else -> Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível abrir a carteira agora.")
                }
            } finally {
                passphrase?.bytes?.fill(0)
                abrindo = false
            }
        }
    }

    BackHandler {
        when (etapa) {
            "conferir" -> etapa = "palavras"
            else -> fechar()
        }
    }
    Box(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().acimaDoTeclado()) {
        Column(Modifier.fillMaxSize()) {
            Spacer(Modifier.height(Altura.barra))
            when (etapa) {
                "aviso" -> Box(Modifier.weight(1f)) {
                    AvisoAntesDasPalavras(erro, abrindo) { abrir() }
                    if (abrindo) Trabalhando(t("Abrindo as palavras"))
                }
                "palavras" -> GravarPalavras(palavras, nomeDaCarteira = if (copia) null else carteira.nome, comPassphrase = comPassphrase) {
                    if (copia) etapa = "conferir" else fechar()
                }
                "conferir" -> ConferirPalavras(palavras, aoVoltar = { etapa = "palavras" }, aoDepois = null) {
                    escopo.launch {
                        runCatching { App.aplicar(Api.objeto("carteira.confirmarCopia", JSONObject().put("id", carteira.id))) }
                        if (comPassphrase && !carteira.passphraseConfirmada) etapa = "passphrase" else fechar()
                    }
                }
                "passphrase" -> ConferirPassphrase(carteira, comRascunho = !soAPassphrase) { fechar() }
            }
        }
        val voltar = etapa == "conferir"
        BotaoDeCanto(if (voltar) Icones.voltar else Icones.fechar, if (voltar) t("Voltar") else t("Fechar"), Modifier.padding(start = Espaco.xs)) {
            if (voltar) etapa = "palavras" else fechar()
        }
    }
}

/** Antes das palavras: ninguem da Escalibur pede, e o dono declara que sabe o que elas sao. */
@Composable
private fun AvisoAntesDasPalavras(erro: String?, abrindo: Boolean, aoAbrir: () -> Unit) {
    val declaracoes = listOf(
        t("Quem tem as palavras tem o saldo"),
        t("A Escalibur nunca pede as palavras"),
        t("Devo ver as palavras sozinho, longe de câmeras"),
    )
    val cientes = remember { mutableStateListOf<Int>() }
    Column(Modifier.fillMaxSize().padding(horizontal = Espaco.margem).padding(top = Espaco.md, bottom = Espaco.xs)) {
        Text(t("Ninguém da Escalibur vai pedir suas palavras"), style = estilo(Tipo.titulo), color = Paleta.tinta)
        Text(t("Suporte, gerente de exchange, recuperação de conta: quem pede a senha da carteira está tentando roubar o saldo."),
             style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
        Text(t("Estou ciente que:"), style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
        Column(Modifier.padding(top = Espaco.xxs)) {
            declaracoes.forEachIndexed { indice, declaracao ->
                val marcada = indice in cientes
                Row(
                    Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).clickable { if (marcada) cientes.remove(indice) else cientes.add(indice) },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    Box(
                        Modifier.size(22.dp).clip(CircleShape).background(if (marcada) Paleta.sucesso else Paleta.vazio)
                            .border(1.5.dp, if (marcada) Paleta.sucesso else Paleta.tintaApagada, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) { if (marcada) Icone(Icones.visto, Paleta.vazio, tamanho = 12.dp) }
                    Text(declaracao, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
                }
            }
        }
        erro?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
        Spacer(Modifier.weight(1f))
        BotaoPrimario(t("Ver as palavras"), ligado = cientes.size == declaracoes.size, carregando = abrindo, acao = aoAbrir)
    }
}

/**
 * A passphrase digitada de onde o dono anotou. Logo depois das palavras, o nucleo compara com a
 * que ele abriu; sozinha, pelo cofre, com o PIN (nunca so o rosto: seria um chute por biometria).
 */
@Composable
private fun ConferirPassphrase(carteira: Carteira, comRascunho: Boolean, aoTerminar: () -> Unit) {
    val escopo = rememberCoroutineScope()
    val campo = remember { Segredo() }
    var revelar by remember { mutableStateOf(false) }
    var trabalhando by remember { mutableStateOf(false) }
    var mensagem by remember { mutableStateOf<String?>(null) }
    DisposableEffect(Unit) { onDispose { campo.clearText() } }

    fun conferir() {
        mensagem = null
        trabalhando = true
        escopo.launch {
            try {
                val resposta = if (comRascunho) {
                    Api.comSegredo("carteira.conferirPassphrase", JSONObject().put("id", carteira.id), campo.bytes())
                } else {
                    Autorizacao.tentando(t("Conferir a passphrase de %@", carteira.nome), Autorizacao.Presenca.pin) { credencial ->
                        Api.comSegredo("carteira.conferirPassphrase", JSONObject().put("id", carteira.id).put("credencial", credencial.json()),
                                       *credencial.partes(campo.bytes()))
                    } ?: return@launch
                }
                when (resposta.getString("resultado")) {
                    "confere" -> {
                        campo.clearText()
                        App.recarregar()
                        aoTerminar()
                    }
                    "antiga" -> mensagem = t("A passphrase de %@ foi gravada por uma versão anterior do app, e restaurada pelas palavras a conta da Cardano dela muda. Mova o saldo dela para outra carteira e crie a carteira com passphrase de novo.", carteira.nome)
                    else -> mensagem = t("Não confere com a passphrase desta carteira. Confira o que você anotou, letra por letra.")
                }
            } catch (falha: FalhaDoNucleo) {
                mensagem = when (falha.codigo) {
                    "passphrase.espera" -> t("Muitas passphrases erradas. Tente de novo às %@.", Formato.relogio(Date(falha.dados.optDouble("ate", 0.0).toLong())))
                    else -> Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível abrir a carteira agora.")
                }
            } finally {
                trabalhando = false
            }
        }
    }

    Column(Modifier.fillMaxSize().padding(horizontal = Espaco.margem).padding(top = Espaco.md, bottom = Espaco.xs)) {
        Box(Modifier.fillMaxWidth().padding(bottom = Espaco.md), contentAlignment = Alignment.Center) { EmblemaCifrado() }
        Text(t("Confira a passphrase"), style = estilo(Tipo.titulo), color = Paleta.tinta)
        Text(t("Digite a passphrase de %@ a partir de onde você anotou. Diferença de maiúscula, acento ou espaço já abre outra carteira, e o que chegar nesta se perde.", carteira.nome),
             style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
        Box(Modifier.padding(top = Espaco.lg)) { CampoSecreto(campo, t("Passphrase"), revelar) { revelar = it } }
        Text(t("Segure o dedo no campo para ver o que digitou."), style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.xs))
        mensagem?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
        Spacer(Modifier.weight(1f))
        BotaoPrimario(t("Conferir"), ligado = campo.text.isNotEmpty(), carregando = trabalhando) { conferir() }
    }
}
