package app.escalibur.wallet.ui.ajustes

import app.escalibur.wallet.ui.comp.EmblemaCifrado
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.clearText
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.importar.CampoSecreto
import app.escalibur.wallet.ui.importar.bytes
import app.escalibur.wallet.ui.novacarteira.VerificacaoDoAparelho
import app.escalibur.wallet.ui.principal.Aba
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.launch
import org.json.JSONObject
import app.escalibur.wallet.ui.comp.TelaComBarra
import androidx.compose.ui.layout.layout
import java.util.Date

/**
 * S3: a carteira da 25a palavra a partir da carteira escolhida. A frase nao aparece: o cofre abre,
 * deriva a carteira nova e grava, com uma confirmacao so. Em tres passos: o que e, a checagem do
 * aparelho e so entao os campos da passphrase.
 */
@Composable
fun FluxoDaCarteiraComPassphrase(base: Carteira) {
    var passo by remember { mutableStateOf("explicacao") }
    val palavras = base.palavras ?: 12
    BackHandler {
        when (passo) {
            "checagem" -> passo = "explicacao"
            "digitar" -> passo = "checagem"
            else -> Navegacao.fechar()
        }
    }
    if (passo == "explicacao") {
        // Como no iOS: o conteudo rola por baixo do voltar, e o Continuar fica preso embaixo.
        TelaComBarra({ Navegacao.fechar() }, rodape = { BotaoPrimario(t("Continuar")) { passo = "checagem" } }) { espaco ->
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(horizontal = Espaco.margem).padding(vertical = Espaco.md),
                   horizontalAlignment = Alignment.CenterHorizontally) {
                // A parede de pixels com a porta escondida: as palavras abrem a de sempre, e a chave
                // da passphrase revela a outra. Sobe 20 sobre o espaco de cima, como no iOS.
                CenaDaPassphrase(CenaDaPassphrase.portaEscondida, 190.dp, Modifier.layout { medida, limites ->
                    val peca = medida.measure(limites)
                    val sobe = 20.dp.roundToPx()
                    layout(peca.width, peca.height - sobe) { peca.place(0, -sobe) }
                })
                Text(t("Carteira com passphrase"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                     modifier = Modifier.padding(top = Espaco.md))
                Text(t("Uma senha extra, escolhida por você. Junto com a senha de %@, ela abre outra carteira, com outros endereços.", base.nome),
                     style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xs))
                BotaoComoFuncionaDaPassphrase(Modifier.padding(top = Espaco.md))
                Column(
                    Modifier.padding(top = Espaco.lg).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(Espaco.base),
                    verticalArrangement = Arrangement.spacedBy(Espaco.md),
                ) {
                    PontoDaPassphrase(Icones.olhoRiscado, t("Quem achar só as %lld palavras vê a carteira de sempre, não a da passphrase.", palavras))
                    PontoDaPassphrase(Icones.lapis, t("Anote a passphrase longe das %lld. Para abrir a carteira com passphrase em outro aparelho, você vai precisar das duas.", palavras))
                    PontoDaPassphrase(Icones.alerta, t("Esquecer a passphrase é perder o acesso à carteira com passphrase. Ninguém recupera, nem a Escalibur."))
                }
            }
        }
        return
    }
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().acimaDoTeclado()) {
        when (passo) {
            "checagem" -> {
                CabecalhoDeFolha("", null, aoVoltar = { passo = "explicacao" })
                Box(Modifier.weight(1f)) { VerificacaoDoAparelho(t("Deslize para digitar a passphrase"), criando = false) { passo = "digitar" } }
            }
            "digitar" -> DigitarPassphrase(base) { passo = "checagem" }
        }
    }
}

@Composable
private fun PontoDaPassphrase(icone: ImageVector, texto: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(icone, Paleta.tinta, tamanho = 15.dp)
        }
        Text(texto, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f).padding(top = 5.dp))
    }
}

/** O ultimo passo: os dois campos da passphrase e o nome da carteira nova. */
@Composable
private fun androidx.compose.foundation.layout.ColumnScope.DigitarPassphrase(base: Carteira, aoVoltar: () -> Unit) {
    val escopo = rememberCoroutineScope()
    val passphrase = remember { TextFieldState() }
    val repeticao = remember { TextFieldState() }
    var revelar by remember { mutableStateOf(false) }
    var nome by remember { mutableStateOf(t("%@ com passphrase", base.nome)) }
    var mensagem by remember { mutableStateOf<String?>(null) }
    var trabalhando by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        onDispose {
            passphrase.clearText()
            repeticao.clearText()
        }
    }

    fun abrir() {
        if (trabalhando || passphrase.text.isEmpty()) return
        mensagem = null
        val a = passphrase.bytes()
        val b = repeticao.bytes()
        val iguais = a.isNotEmpty() && java.security.MessageDigest.isEqual(a, b)
        b.fill(0)
        if (!iguais) {
            a.fill(0)
            mensagem = t("As duas versões da passphrase não conferem.")
            return
        }
        trabalhando = true
        val titulo = nome.filter { !it.isISOControl() && Character.getType(it) != Character.FORMAT.toInt() }.trim().take(40)
            .ifEmpty { t("%@ com passphrase", base.nome) }
        escopo.launch {
            try {
                val aberta = Autorizacao.tentando(t("Abrir a carteira com passphrase")) { credencial ->
                    Api.comSegredo("carteira.abrirComPassphrase", JSONObject().put("base", base.id).put("nome", titulo).put("credencial", credencial.json()),
                                   *credencial.partes(a.copyOf()))
                } ?: return@launch
                passphrase.clearText()
                repeticao.clearText()
                App.recarregar()
                // A mesma frase com a mesma passphrase e a mesma carteira: ela ja estava aqui.
                if (aberta.optBoolean("jaAberta")) {
                    Avisos.mostrar(t("Esta carteira já está aberta, como %@. Ela passa a ser a carteira em uso.", aberta.getJSONObject("carteira").getString("nome")))
                }
                // Aberta, a carteira nova ja e a escolhida: o app vai para a Carteira.
                Navegacao.fecharTudo()
                Navegacao.aba = Aba.carteira
            } catch (falha: FalhaDoNucleo) {
                mensagem = when (falha.codigo) {
                    "sessao.passphraseInvisivel" -> t("A passphrase tem um caractere invisível ou um espaço diferente do espaço comum. Escreva de novo, só com letras, números, símbolos e espaço comum: é o que dá para anotar no papel.")
                    "passphrase.espera" -> t("Muitas passphrases erradas. Tente de novo às %@.", Formato.relogio(Date(falha.dados.optDouble("ate", 0.0).toLong())))
                    else -> Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível criar a carteira agora.")
                }
            } finally {
                a.fill(0)
                trabalhando = false
            }
        }
    }

    CabecalhoDeFolha("", null, aoVoltar = aoVoltar)
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md),
           verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
        // O selo das telas onde se digita um segredo.
        Box(Modifier.fillMaxWidth().padding(bottom = Espaco.xs), contentAlignment = Alignment.Center) { EmblemaCifrado() }
        // O titulo e o texto no centro.
        Text(t("Digite a passphrase"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        Text(t("Escreva igual ao que você anotou. Diferença de maiúscula, acento ou espaço já abre outra carteira."), style = estilo(Tipo.corpo),
             color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(bottom = Espaco.md))
        Text(t("Passphrase"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        CampoSecreto(passphrase, t("Passphrase"), revelar) { revelar = it }
        // A repeticao so aparece quando a primeira comeca a ser digitada.
        if (passphrase.text.isNotEmpty() || repeticao.text.isNotEmpty()) {
            CampoSecreto(repeticao, t("Repita a passphrase"), revelar) { revelar = it }
            Text(t("Segure o dedo num campo para conferir as duas."), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
        Text(t("Nome"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
        Box(
            Modifier.fillMaxWidth().height(Altura.campo).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
                .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(horizontal = Espaco.md),
            contentAlignment = Alignment.CenterStart,
        ) {
            BasicTextField(nome, { nome = it.take(40) }, singleLine = true, textStyle = estilo(Tipo.linha).copy(color = Paleta.tinta),
                           cursorBrush = SolidColor(Paleta.acento), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                           modifier = Modifier.fillMaxWidth())
        }
        mensagem?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.sm)) }
    }
    Rodape {
        BotaoPrimario(t("Abrir carteira"), ligado = passphrase.text.isNotEmpty() && repeticao.text.isNotEmpty(), carregando = trabalhando) { abrir() }
    }
}
