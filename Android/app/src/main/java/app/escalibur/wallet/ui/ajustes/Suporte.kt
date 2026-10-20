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
import androidx.compose.foundation.layout.imePadding
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

/** O endereco publico do suporte. */
const val EMAIL_DO_SUPORTE = "support@escaliburwallet.com"

private enum class Assunto(val pedeRede: Boolean, val pedeTransacao: Boolean) {
    envio(true, true), troca(true, true), saldo(true, false), acesso(false, false), recuperar(false, false), ideia(false, false), outro(false, false);

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
    var pareceFrase by remember { mutableStateOf(false) }
    var semAppDeEmail by remember { mutableStateOf(false) }
    LaunchedEffect(detalhes) {
        pareceFrase = runCatching { Api.objeto("carteira.reconhecer", JSONObject().put("endereco", detalhes)).optBoolean("frase") }.getOrDefault(false)
    }
    val emailValido = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(email.trim())
    val iguais = email.trim().equals(repeticao.trim(), ignoreCase = true)
    val pode = assunto != null && detalhes.isNotBlank() && emailValido && iguais && !pareceFrase
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

    fun enviar() {
        semAppDeEmail = false
        val intencao = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")).apply {
            putExtra(Intent.EXTRA_EMAIL, arrayOf(EMAIL_DO_SUPORTE))
            putExtra(Intent.EXTRA_SUBJECT, assuntoDoEmail())
            putExtra(Intent.EXTRA_TEXT, corpo())
        }
        semAppDeEmail = runCatching { contexto.startActivity(intencao) }.isFailure
    }

    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().imePadding()) {
        CabecalhoDeFolha("", null, aoVoltar = { Navegacao.fechar() })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.lg)) {
            Text(t("Fale com o suporte"), style = estilo(Tipo.titulo), color = Paleta.tinta)
            Text(t("Conte o que aconteceu em poucos passos. O chamado vai para o suporte da Escalibur, e a resposta chega no seu e-mail."),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs))

            Passo(1, t("Sobre o que é?"))
            Column(Modifier.padding(top = Espaco.xs), verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                for (opcao in Assunto.entries) {
                    val escolhido = assunto == opcao
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = Altura.linhaCompacta).clip(RoundedCornerShape(Raio.cartao))
                            .background(if (escolhido) Paleta.trilho else Paleta.corpo)
                            .border(1.dp, if (escolhido) Paleta.bordaForte else Paleta.borda, RoundedCornerShape(Raio.cartao))
                            .clickable { assunto = opcao }.padding(horizontal = Espaco.md),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(opcao.titulo, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
                        if (escolhido) Icone(Icones.visto, Paleta.tinta, tamanho = 15.dp)
                    }
                }
            }
            var numero = 2
            if (assunto?.pedeRede == true) {
                Passo(numero++, t("Em qual rede?"))
                Row(Modifier.padding(top = Espaco.xs).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Chip(t("Não sei"), rede == null) { rede = null }
                    for (opcao in Redes.todas) Chip(opcao.nome, rede == opcao.id) { rede = opcao.id }
                }
            }
            Passo(numero++, t("O que aconteceu?"))
            CampoDeTexto(detalhes, t("O que você fez, o que esperava e o que apareceu na tela."), linhas = 5) { detalhes = it.take(2000) }
            if (pareceFrase) {
                Faixa(TipoDeFaixa.falha, t("Isto parece a senha da carteira"), Modifier.padding(top = Espaco.sm),
                      mensagem = t("Apague as palavras antes de mandar. Ninguém da Escalibur precisa delas, nem para ajudar."))
            }
            if (assunto?.pedeTransacao == true) {
                Text(t("ID da transação, se tiver"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.md))
                CampoDeTexto(transacao, t("Copie na Atividade, no detalhe do envio"), mono = true) { transacao = it.take(200) }
            }
            Passo(numero, t("Seu e-mail para a resposta"))
            CampoDeTexto(email, t("seu@email.com"), email = true) { email = it.take(120) }
            Box(Modifier.padding(top = Espaco.xs)) { CampoDeTexto(repeticao, t("Repita o e-mail"), email = true) { repeticao = it.take(120) } }
            if (repeticao.isNotEmpty() && !iguais) Text(t("Os dois e-mails não conferem."), style = estilo(Tipo.nota), color = Paleta.baixa, modifier = Modifier.padding(top = Espaco.xs))
            else if (email.isNotEmpty() && !emailValido) Text(t("Confira o e-mail: falta o @ ou o domínio."), style = estilo(Tipo.nota), color = Paleta.baixa, modifier = Modifier.padding(top = Espaco.xs))
            if (semAppDeEmail) {
                Faixa(TipoDeFaixa.neutra, t("Nenhum app de e-mail abriu"), Modifier.padding(top = Espaco.md),
                      mensagem = t("Copie o chamado e mande pelo e-mail que você usa. O endereço do suporte vai junto no texto."),
                      tituloDaAcao = t("Copiar o chamado")) {
                    Transferencia.copiar(contexto, t("Para: %@", EMAIL_DO_SUPORTE) + "\n" + assuntoDoEmail() + "\n\n" + corpo(), rotulo = "Escalibur")
                }
            }
            Column(Modifier.padding(top = Espaco.lg), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                Ponto(Icones.escudo, t("Nunca mande as palavras da carteira, o PIN ou a senha de um envelope. Ninguém da Escalibur pede, nem pelo suporte."))
                Ponto(Icones.celular, t("A carteira roda só neste celular: o suporte não vê, não move nem devolve saldo, e não desfaz transação."))
                Ponto(Icones.documento, t("Vai junto só o que você escreveu, o seu e-mail, a versão do app e a do Android. Endereço da carteira e saldo não vão, e o app não guarda nada disso."))
            }
        }
        Rodape { BotaoPrimario(t("Enviar ao suporte"), ligado = pode) { enviar() } }
    }
}

@Composable
private fun Passo(numero: Int, titulo: String) {
    Row(Modifier.padding(top = Espaco.lg), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        Box(Modifier.size(22.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Text("$numero", style = estilo(Tipo.rotulo), color = Paleta.tinta)
        }
        Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
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
private fun CampoDeTexto(texto: String, dica: String, linhas: Int = 1, mono: Boolean = false, email: Boolean = false, aoMudar: (String) -> Unit) {
    Box(
        Modifier.padding(top = Espaco.xs).fillMaxWidth().heightIn(min = Altura.campo).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
            .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(horizontal = Espaco.md, vertical = Espaco.sm),
    ) {
        if (texto.isEmpty()) Text(dica, style = estilo(Tipo.corpo), color = Paleta.tintaMorta)
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
