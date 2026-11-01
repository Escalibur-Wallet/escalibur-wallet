package app.escalibur.wallet.ui.ajustes

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.comp.AlturaDoTecladoDePalavras
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.Interruptor
import app.escalibur.wallet.ui.comp.PixelsCifrando
import app.escalibur.wallet.ui.comp.Sugestoes
import app.escalibur.wallet.ui.comp.TecladoDePalavras
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Liga ou desliga o Safe Keyboard; no Super Security ele nao desliga. Desligar entrega o que se
 * digita ao teclado do celular, que pode ser de terceiros: pede o PIN. Devolve o erro para mostrar.
 */
private suspend fun gravarSafeKeyboard(ligado: Boolean): String? = runCatching {
    if (ligado) App.aplicar(Api.objeto("ajustes.tecladoProprio", JSONObject().put("ligado", true)))
    else Autorizacao.tentando(t("Desativar o Safe Keyboard"), Autorizacao.Presenca.pin) { credencial ->
        App.aplicar(Api.comSegredo("ajustes.tecladoProprio", JSONObject().put("ligado", false).put("credencial", credencial.json()), *credencial.partes()))
    }
}.exceptionOrNull()?.let { Autorizacao.mensagemDeRecusa(it) ?: t("Não foi possível salvar. Tente de novo.") }

/**
 * Seguranca, Safe Keyboard (o OwnKeyboardView do iOS): o titulo e o interruptor em cima, o teclado
 * digitando sozinho embaixo, e os idiomas logo abaixo dele. Sempre ligado no Super Security.
 */
@Composable
fun TelaDoSafeKeyboard() {
    val escopo = rememberCoroutineScope()
    val estado = App.estado
    var erro by remember { mutableStateOf<String?>(null) }
    Subtela("") {
        Column(Modifier.padding(horizontal = Espaco.margem)) {
            Text("Safe Keyboard", style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.sm))
            Text(t("As palavras da carteira digitadas num teclado desenhado pela Escalibur, no lugar do teclado do celular."),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs))
            val forma = RoundedCornerShape(Raio.cartao)
            Row(
                Modifier.padding(top = Espaco.lg).fillMaxWidth().heightIn(min = Altura.linhaCompacta).clip(forma).background(Paleta.corpo)
                    .border(1.dp, Paleta.borda, forma).padding(horizontal = Espaco.md),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(t("Usar o Safe Keyboard"), style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f))
                Interruptor(estado.tecladoProprio, { ligar -> escopo.launch { erro = gravarSafeKeyboard(ligar) } }, habilitado = !estado.reforcado)
            }
            (erro ?: if (estado.reforcado) t("No Super Security, o Safe Keyboard fica sempre ligado.") else null)?.let {
                Text(it, style = estilo(Tipo.nota), color = if (erro == null) Paleta.tintaApagada else Paleta.baixa, modifier = Modifier.padding(top = Espaco.xs))
            }
            DemoDoTeclado(Modifier.padding(top = Espaco.lg))
            Text(t("Ele escreve as palavras em inglês, português, espanhol, francês, italiano e tcheco. Para japonês, chinês ou coreano, o globo do teclado traz o do celular."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.xs))
            Column(
                Modifier.padding(top = Espaco.lg).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(Espaco.base),
                verticalArrangement = Arrangement.spacedBy(Espaco.md),
            ) {
                Ponto(Icones.olhoRiscado, t("O teclado do celular não vê as letras"),
                      t("Sem previsão, ditado nem palavra aprendida no dicionário do aparelho. E as palavras nunca saem do celular."))
                Ponto(Icones.wifiRiscado, t("Sem internet"), t("O teclado não tem conexão nenhuma, e a tela das palavras fica sem internet enquanto está aberta."))
            }
        }
    }
}

/**
 * O toque em "Safe Keyboard", na tela de digitar as palavras (o KeyboardInfoSheet do iOS): o que o
 * teclado e, com a animacao, e o botao de desligar. No Super Security ele nao desliga.
 */
@Composable
fun FolhaDoSafeKeyboard(aoFechar: () -> Unit) {
    val escopo = rememberCoroutineScope()
    var erro by remember { mutableStateOf<String?>(null) }
    BackHandler(onBack = aoFechar)
    Column(Modifier.fillMaxSize().background(Paleta.corpo).navigationBarsPadding()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md)) {
            DemoDoTeclado(Modifier.padding(top = Espaco.md), superficie = Paleta.vazio)
            Text("Safe Keyboard", style = estilo(Tipo.titulo), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg))
            Text(t("Feito para a segurança das palavras: desenhado pelo próprio app, no lugar do teclado do celular."),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs))
            Column(
                Modifier.padding(top = Espaco.lg).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.trilho).padding(Espaco.base),
                verticalArrangement = Arrangement.spacedBy(Espaco.md),
            ) {
                Ponto(Icones.wifiRiscado, t("Sem conexão com a internet"),
                      t("O teclado não tem conexão nenhuma, e esta tela inteira fica sem internet enquanto está aberta."))
                Ponto(Icones.olhoRiscado, t("O teclado do celular não vê as letras"),
                      t("Nada de previsão, ditado ou palavra aprendida. E as palavras nunca saem do celular."))
                Ponto(Icones.cadeadoCheio, t("Cifrado na tela"), t("Na tela, cada letra vira um símbolo que muda. Nada é gravado no celular."))
                Text(t("As sugestões e as teclas acesas mostram a palavra: digite longe de olhos e câmeras."), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            }
            erro?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
        }
        Column(
            Modifier.fillMaxWidth().background(Paleta.corpo).padding(horizontal = Espaco.margem).padding(top = Espaco.sm, bottom = Espaco.xs),
            verticalArrangement = Arrangement.spacedBy(Espaco.sm), horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            BotaoPrimario(t("Continuar digitando"), acao = aoFechar)
            if (App.estado.reforcado) {
                Text(t("No Super Security, o Safe Keyboard fica sempre ligado."), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            } else {
                BotaoSecundario(t("Desativar o Safe Keyboard")) {
                    escopo.launch {
                        erro = gravarSafeKeyboard(false)
                        if (erro == null) aoFechar()
                    }
                }
            }
        }
    }
}

@Composable
private fun Ponto(icone: ImageVector, titulo: String, detalhe: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(icone, Paleta.tintaSuave, tamanho = 15.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            Text(detalhe, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
    }
}

/**
 * O Safe Keyboard digitando sozinho, em escala (o KeyboardDemo do iOS): a tecla escurece sem balao, as
 * letras que nao formam palavra apagam, o campo mostra a palavra cifrada, e no fim a sugestao fecha a
 * palavra. Palavras da lista em ingles, nunca uma frase de verdade.
 */
@Composable
fun DemoDoTeclado(modifier: Modifier = Modifier, superficie: Color = Paleta.corpo) {
    val palavras = remember { listOf("abandon", "zebra", "orbit") }
    var palavra by remember { mutableIntStateOf(0) }
    var letras by remember { mutableIntStateOf(0) }
    var digitado by remember { mutableStateOf("") }
    var apertada by remember { mutableStateOf<Char?>(null) }
    var fechada by remember { mutableStateOf(false) }
    var sugestoes by remember { mutableStateOf(Sugestoes(emptyList(), ('a'..'z').toSet())) }
    var tique by remember { mutableLongStateOf(0L) }
    LaunchedEffect(digitado) { sugestoes = Sugestoes.de(digitado) }
    LaunchedEffect(Unit) { while (isActive) { delay(1000L / 12); tique++ } }
    LaunchedEffect(Unit) {
        while (isActive) {
            for ((indice, texto) in palavras.withIndex()) {
                palavra = indice
                fechada = false
                letras = 0
                digitado = ""
                delay(700)
                // Ate a palavra ser a unica da lista com esse comeco, como quem digita de verdade.
                val ate = minOf(texto.length, maxOf(4, texto.length - 2))
                for (letra in texto.take(ate)) {
                    apertada = letra
                    delay(170)
                    apertada = null
                    digitado += letra
                    letras++
                    delay(150)
                }
                delay(650)
                fechada = true
                digitado = ""
                delay(1100)
            }
        }
    }
    val descricao = t("Animação: o Safe Keyboard digitando uma palavra da lista")
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(superficie).padding(vertical = Espaco.sm)
            .clearAndSetSemantics { contentDescription = descricao },
        verticalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        Row(Modifier.fillMaxWidth().height(44.dp).padding(horizontal = Espaco.md), verticalAlignment = Alignment.CenterVertically) {
            Text("%02d".format(palavra + 1), style = estilo(Tipo.nota).copy(fontFeatureSettings = "tnum"), fontWeight = FontWeight.SemiBold, color = Paleta.tintaSuave)
            Text(cifra(if (fechada) 4 else letras, palavra, tique), fontFamily = FontFamily.Monospace, fontSize = 15.sp, fontWeight = FontWeight.Medium,
                 color = Paleta.tintaSuave, maxLines = 1, modifier = Modifier.padding(start = Espaco.xs))
            Spacer(Modifier.weight(1f))
            AnimatedVisibility(!fechada && letras > 0, enter = fadeIn(), exit = fadeOut()) {
                Box(Modifier.height(28.dp).clip(CircleShape).background(Paleta.controle).padding(horizontal = Espaco.sm), contentAlignment = Alignment.Center) {
                    Text(palavras[palavra], style = estilo(Tipo.rotulo), color = Paleta.tinta)
                }
            }
        }
        val escala = 0.84f
        BoxWithConstraints(Modifier.fillMaxWidth().height(AlturaDoTecladoDePalavras * escala).clipToBounds()) {
            TecladoDePalavras(
                digitado, letrasPossiveis = sugestoes.letras, aoDigitar = {}, aoApagar = {},
                podeSeguir = digitado.isNotEmpty() && sugestoes.palavras.isNotEmpty(), aoSistema = {}, demo = true, apertada = apertada,
                modifier = Modifier.wrapContentSize(Alignment.TopStart, unbounded = true).requiredSize(maxWidth / escala, AlturaDoTecladoDePalavras)
                    .graphicsLayer { scaleX = escala; scaleY = escala; transformOrigin = TransformOrigin(0f, 0f) },
            )
        }
    }
}

/** Glifos que trocam a cada tique, como a cifra viva da tela de importar. */
private fun cifra(quantos: Int, palavra: Int, tique: Long): String {
    if (quantos == 0) return t("palavra")
    val alfabeto = "0123456789ABCDEF"
    return (0 until quantos).map { alfabeto[(PixelsCifrando.ruido(it, palavra, tique) * 16).toInt() % 16] }.joinToString("")
}
