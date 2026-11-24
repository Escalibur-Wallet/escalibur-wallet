package app.escalibur.wallet.ui.ajustes

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import app.escalibur.wallet.ui.comp.acimaDoTeclado
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import kotlinx.coroutines.CancellationException
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.BuildConfig
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.carteira.Redes
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Chip
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.comp.Transferencia
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import org.json.JSONObject
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.OpcaoDoMenu
import app.escalibur.wallet.ui.comp.MenuFlutuante
import app.escalibur.wallet.ui.comp.TelaComBarra

/** O endereco publico do suporte. */
const val EMAIL_DO_SUPORTE = "support@escaliburwallet.com"

private enum class Assunto(val pedeRede: Boolean, val pedeTransacao: Boolean) {
    envio(true, true), troca(true, true), saldo(true, false), acesso(false, false), recuperar(false, false), ideia(false, false), outro(false, false);

    /** O icone de cada assunto, os do iOS. */
    val icone: ImageVector get() = when (this) {
        envio -> Icones.setasCimaBaixo
        troca -> Icones.trocar
        saldo -> Icones.olhoRiscado
        acesso -> Icones.digital
        recuperar -> Icones.setaCirculo
        ideia -> Icones.lampada
        outro -> Icones.balaoReticencias
    }

    val titulo: String get() = when (this) {
        envio -> t("Envio ou recebimento")
        troca -> t("Troca ou ponte")
        saldo -> t("Saldo que não aparece")
        acesso -> t("Entrar no app: PIN ou biometria")
        recuperar -> t("Importar ou recuperar uma carteira")
        ideia -> t("Sugestão")
        outro -> t("Outro assunto")
    }
}

/**
 * Fale com o suporte: um chamado em poucos passos, enviado pelo app de e-mail do celular para o
 * suporte, com um e-mail para a resposta digitado duas vezes. Vai junto so o que a pessoa escreveu,
 * esse e-mail e as versoes; nada de endereco da carteira nem saldo. Texto com cara de senha da
 * carteira nao sai.
 */
@Composable
fun TelaDeSuporte() {
    val contexto = LocalContext.current
    var assunto by remember { mutableStateOf<Assunto?>(null) }
    var rede by remember { mutableStateOf<String?>(null) }
    var detalhes by remember { mutableStateOf("") }
    var transacao by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var repeticao by remember { mutableStateOf("") }
    /** O que o nucleo achou: "" (nada), "chave", "palavras" (com o trecho), "hex" ou "rede" (`PrivateKeyGuard.supportSecret`). */
    var segredo by remember { mutableStateOf("") }
    var palavras by remember { mutableStateOf("") }
    /** O pedido da ultima resposta: ate ela chegar, o Enviar e o Copiar esperam (como o `emDia` dos contatos). */
    var conferidoPara by remember { mutableStateOf<List<String>?>(null) }
    var semAppDeEmail by remember { mutableStateOf(false) }
    val escopo = rememberCoroutineScope()
    // O ID e a rede so contam no assunto que os pede: fora dele, nem vao no chamado (como no iOS).
    // Lido na hora de cada chamada: dentro de uma tarefa, e o texto de agora, nao o da composicao.
    fun pedidoAgora() = listOf(detalhes, if (assunto?.pedeTransacao == true) transacao else "", if (assunto?.pedeRede == true) rede.orEmpty() else "")
    val pedido = pedidoAgora()
    /** A conferencia no nucleo; null na falha, que bloqueia. O cancelamento por uma tecla nova nao conta como falha: engolido, ele
     *  acendia o aviso enquanto o dono digitava (revisao de seguranca, 09/11/2026). */
    suspend fun conferir(pedido: List<String>): JSONObject? = try {
        Api.objeto("suporte.pareceFrase", JSONObject().put("detalhes", pedido[0]).put("transacao", pedido[1]).put("rede", pedido[2]))
    } catch (cancelado: CancellationException) {
        throw cancelado
    } catch (falha: Exception) {
        null
    }
    LaunchedEffect(pedido) {
        // O texto mudou: o "Copiar o chamado" de antes sai, e volta so pelo Enviar, que confere de novo.
        semAppDeEmail = false
        // Uma pausa curta na digitacao, como no iOS; o pedido e o desta chamada, nunca o lido de novo depois da espera.
        delay(150)
        val resposta = conferir(pedido)
        segredo = if (resposta == null) "chave" else resposta.optString("tipo")
        palavras = resposta?.optString("palavras").orEmpty()
        conferidoPara = pedido
    }
    val pareceFrase = segredo.isNotEmpty()
    val emDia = conferidoPara == pedido
    val emailValido = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(email.trim())
    val iguais = email.trim().equals(repeticao.trim(), ignoreCase = true)
    val pode = assunto != null && detalhes.isNotBlank() && emailValido && iguais && !pareceFrase && emDia
    val versao = BuildConfig.VERSION_NAME

    fun assuntoDoEmail() = t("Suporte: %@ · Escalibur %@", assunto?.titulo ?: "", versao)
    fun corpo(): String {
        val linhas = mutableListOf(t("Responder para: %@", email.trim()), t("Assunto: %@", assunto?.titulo ?: ""))
        if (assunto?.pedeRede == true) linhas += t("Rede: %@", rede?.let { Redes.rede(it)?.nome } ?: t("não sei"))
        linhas += ""
        linhas += detalhes.trim()
        if (assunto?.pedeTransacao == true && transacao.isNotBlank()) {
            linhas += ""
            linhas += t("ID da transação: %@", transacao.trim())
        }
        linhas += ""
        linhas += "Escalibur $versao · Android ${Build.VERSION.RELEASE}"
        return linhas.joinToString("\n")
    }

    fun abrirEmail() {
        val intencao = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")).apply {
            putExtra(Intent.EXTRA_EMAIL, arrayOf(EMAIL_DO_SUPORTE))
            putExtra(Intent.EXTRA_SUBJECT, assuntoDoEmail())
            putExtra(Intent.EXTRA_TEXT, corpo())
        }
        semAppDeEmail = runCatching { contexto.startActivity(intencao) }.isFailure
    }

    fun enviar() {
        semAppDeEmail = false
        // De novo, na hora: a resposta guardada pode ser de um texto de um instante antes (como no iOS).
        val agora = pedidoAgora()
        escopo.launch {
            val resposta = conferir(agora)
            val tipo = if (resposta == null) "chave" else resposta.optString("tipo")
            if (tipo.isNotEmpty() || agora != pedidoAgora()) {
                segredo = tipo.ifEmpty { segredo }
                return@launch
            }
            abrirEmail()
        }
    }

    var escolhendoRede by remember { mutableStateOf(false) }
    // Como no iOS: o titulo na barra, o conteudo rolando por baixo dela e o botao preso embaixo.
    TelaComBarra({ Navegacao.fechar() }, Modifier.acimaDoTeclado(), titulo = t("Suporte"),
                 rodape = { BotaoPrimario(t("Enviar ao suporte"), ligado = pode) { enviar() } }) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(horizontal = Espaco.margem).padding(vertical = Espaco.md)) {
            Text(t("Fale com o suporte"), style = estilo(Tipo.titulo), color = Paleta.tinta)
            Text(t("Conte o que aconteceu em poucos passos. O chamado vai para o suporte da Escalibur, e a resposta chega no seu e-mail."),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs))

            Passo(1, t("Sobre o que é?"))
            // Os assuntos num cartao so, com o icone de cada um e o visto verde no escolhido.
            Column(Modifier.padding(top = Espaco.sm).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)) {
                for (opcao in Assunto.entries) {
                    val escolhido = assunto == opcao
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).clickable { assunto = opcao }.padding(horizontal = Espaco.md),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                    ) {
                        Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) { Icone(opcao.icone, Paleta.tintaSuave, tamanho = 18.dp) }
                        Text(opcao.titulo, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
                        if (escolhido) Icone(Icones.vistoCheio, Paleta.sucesso, tamanho = 20.dp)
                    }
                }
            }
            var numero = 2
            if (assunto?.pedeRede == true) {
                Passo(numero++, t("Em qual rede?"))
                // A rede num menu, como o do iOS: o campo mostra a escolhida e abre a lista.
                Box(Modifier.padding(top = Espaco.sm)) {
                    Row(
                        Modifier.fillMaxWidth().height(Altura.campo).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
                            .clickable { escolhendoRede = true }.padding(horizontal = Espaco.md),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs),
                    ) {
                        val escolhida = rede?.let { id -> Redes.todas.firstOrNull { it.id == id } }
                        if (escolhida != null) SeloDaRede(escolhida.id, escolhida.coingecko, 22.dp, Paleta.corpo)
                        Text(escolhida?.nome ?: t("Não sei"), style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
                        Icone(Icones.abaixo, Paleta.tintaApagada, tamanho = 12.dp)
                    }
                    MenuFlutuante(
                        escolhendoRede,
                        listOf(OpcaoDoMenu("", t("Não sei")) { Box(Modifier.size(22.dp)) }) +
                            Redes.todas.map { opcao -> OpcaoDoMenu(opcao.id, opcao.nome) { SeloDaRede(opcao.id, opcao.coingecko, 22.dp, Paleta.corpo) } },
                        escolhida = rede ?: "", aoFechar = { escolhendoRede = false },
                    ) { rede = it.ifEmpty { null } }
                }
            }
            Passo(numero++, t("O que aconteceu?"))
            CampoDeTexto(detalhes, t("O que você fez, o que esperava e o que apareceu na tela."), linhas = 5, alturaMinima = 132.dp) { detalhes = it.take(4096) }
            when (segredo) {
                "palavras" -> Faixa(TipoDeFaixa.falha, t("Isto parece a senha da carteira"), Modifier.padding(top = Espaco.sm),
                    // O trecho que pesou: quem so conversava sabe o que trocar. Ele ja esta na tela, no campo.
                    mensagem = t("As palavras “%@” estão na lista das senhas de carteira. Se forem da sua, apague. Se não, escreva de outro jeito.", palavras))
                "hex" -> Faixa(TipoDeFaixa.falha, t("Isto parece uma chave ou o código de uma transação"), Modifier.padding(top = Espaco.sm),
                    mensagem = if (assunto?.pedeTransacao == true) t("Se for o código da transação, cole no campo do ID da transação. Se for uma chave, apague: ninguém da Escalibur precisa dela.")
                               else t("Apague o código longo: neste assunto o suporte não precisa dele. Se for uma chave, ninguém da Escalibur precisa dela."))
                "rede" -> Faixa(TipoDeFaixa.falha, t("Isto parece uma chave ou o código de uma transação"), Modifier.padding(top = Espaco.sm),
                    mensagem = t("Escolha a rede acima, para o app conferir se isto é o código de uma transação dessa rede."))
                "" -> {}
                else -> Faixa(TipoDeFaixa.falha, t("Isto parece a senha da carteira"), Modifier.padding(top = Espaco.sm),
                    mensagem = t("Apague as palavras ou a chave antes de mandar. Ninguém da Escalibur precisa delas, nem para ajudar."))
            }
            if (assunto?.pedeTransacao == true) {
                Text(t("ID da transação, se tiver"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.md))
                CampoDeTexto(transacao, t("Copie na Atividade, no detalhe do envio"), mono = true) { transacao = it.take(4096) }
            }
            Passo(numero, t("Seu e-mail para a resposta"))
            Box(Modifier.padding(top = Espaco.xs)) { CampoDeTexto(email, t("seu@email.com"), email = true) { email = it.take(120) } }
            CampoDeTexto(repeticao, t("Repita o e-mail"), email = true) { repeticao = it.take(120) }
            if (repeticao.isNotEmpty() && !iguais) Text(t("Os dois e-mails não conferem."), style = estilo(Tipo.nota), color = Paleta.baixa, modifier = Modifier.padding(top = Espaco.xs))
            else if (email.isNotEmpty() && !emailValido) Text(t("Confira o e-mail: falta o @ ou o domínio."), style = estilo(Tipo.nota), color = Paleta.baixa, modifier = Modifier.padding(top = Espaco.xs))
            if (semAppDeEmail && !pareceFrase && emDia) {
                Faixa(TipoDeFaixa.neutra, t("Nenhum app de e-mail abriu"), Modifier.padding(top = Espaco.md),
                      mensagem = t("Copie o chamado e mande pelo e-mail que você usa. O endereço do suporte vai junto no texto."),
                      tituloDaAcao = t("Copiar o chamado")) {
                    val agora = pedidoAgora()
                    escopo.launch {
                        val resposta = conferir(agora)
                        if (resposta == null || resposta.optString("tipo").isNotEmpty() || agora != pedidoAgora()) return@launch
                        Transferencia.copiar(contexto, t("Para: %@", EMAIL_DO_SUPORTE) + "\n" + assuntoDoEmail() + "\n\n" + corpo(), rotulo = "Escalibur")
                    }
                }
            }
            // Os avisos num cartao, como no iOS.
            Column(
                Modifier.padding(top = Espaco.lg).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(Espaco.base),
                verticalArrangement = Arrangement.spacedBy(Espaco.md),
            ) {
                Ponto(Icones.maoLevantada, t("Nunca mande as palavras da carteira, o PIN ou a senha de um envelope. Ninguém da Escalibur pede, nem pelo suporte."))
                Ponto(Icones.celular, t("A carteira roda só neste celular: o suporte não vê, não move nem devolve saldo, e não desfaz transação."))
                Ponto(Icones.documentoLupa, t("Vai junto só o que você escreveu, o seu e-mail, a versão do app e a do Android. Endereço da carteira e saldo não vão, e o app não guarda nada disso."))
            }
        }
    }
}

@Composable
private fun Passo(numero: Int, titulo: String) {
    Row(Modifier.padding(top = Espaco.lg), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Box(Modifier.size(24.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Text("$numero", style = estilo(Tipo.rotulo), color = Paleta.tinta)
        }
        Text(titulo, style = estilo(Tipo.cabecalho), color = Paleta.tinta)
    }
}

@Composable
private fun Ponto(icone: ImageVector, texto: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) { Icone(icone, Paleta.tinta, tamanho = 15.dp) }
        Text(texto, style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.weight(1f).padding(top = 6.dp))
    }
}

@Composable
private fun CampoDeTexto(texto: String, dica: String, linhas: Int = 1, mono: Boolean = false, email: Boolean = false,
                         alturaMinima: androidx.compose.ui.unit.Dp = Altura.campo, aoMudar: (String) -> Unit) {
    // Sem borda, so o fundo do cartao, como os campos do iOS.
    Box(
        Modifier.padding(top = Espaco.xs).fillMaxWidth().heightIn(min = alturaMinima).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
            .padding(horizontal = Espaco.md, vertical = Espaco.sm),
        contentAlignment = if (linhas == 1) Alignment.CenterStart else Alignment.TopStart,
    ) {
        if (texto.isEmpty()) Text(dica, style = estilo(Tipo.corpo), color = Paleta.tintaApagada)
        BasicTextField(
            texto, aoMudar, singleLine = linhas == 1, minLines = linhas,
            textStyle = estilo(if (mono) Tipo.monoPequeno else Tipo.corpo).copy(color = Paleta.tinta), cursorBrush = SolidColor(Paleta.acento),
            keyboardOptions = KeyboardOptions(
                capitalization = if (email || mono) KeyboardCapitalization.None else KeyboardCapitalization.Sentences,
                keyboardType = if (email) KeyboardType.Email else KeyboardType.Text, autoCorrectEnabled = !email && !mono,
            ),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
