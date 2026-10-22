package app.escalibur.wallet.ui.envelope

import app.escalibur.wallet.ui.comp.EmblemaCifrado
import app.escalibur.wallet.ui.comp.Girando
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import app.escalibur.wallet.ui.comp.acimaDoTeclado
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.escalibur.wallet.BuildConfig
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoDeCanto
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Confirmacao
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.enviar.PedidoDePassphrase
import app.escalibur.wallet.ui.importar.CampoSecreto
import app.escalibur.wallet.ui.importar.ConferenciaDaImportacao
import app.escalibur.wallet.ui.importar.bytes
import app.escalibur.wallet.ui.novacarteira.GravarPalavras
import app.escalibur.wallet.ui.novacarteira.VerificacaoDoAparelho
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.Locale

/** O tamanho fixo de todo envelope `.esclbr` v1. */
private const val TAMANHO_DO_ENVELOPE = 16_504

/** "cerca de 3 segundos": o tempo do Argon2 neste celular. */
private fun cercaDe(segundos: Double): String {
    val n = maxOf(1, Math.round(segundos).toInt())
    return if (n == 1) t("cerca de 1 segundo") else t("cerca de %lld segundos", n)
}

@Composable
private fun PontoDoEnvelope(icone: ImageVector, texto: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(icone, Paleta.tinta, tamanho = 18.dp)
        }
        Text(texto, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f).padding(top = 5.dp))
    }
}

/** O "Como funciona" do envelope, o mesmo em lacrar e em abrir: uma capsula com o play. */
@Composable
private fun BotaoComoFunciona(modifier: Modifier = Modifier) {
    Row(
        modifier.height(34.dp).clip(CircleShape).background(Paleta.trilho)
            .clickable(role = Role.Button) { Navegacao.folha { ComoFuncionaOEnvelope { Navegacao.fechar() } } }
            .padding(horizontal = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icone(Icones.reproduzirCirculo, Paleta.tinta, tamanho = 15.dp)
        Text(t("Como funciona"), style = estilo(Tipo.rotulo), color = Paleta.tinta)
    }
}

/** As escolhas da senha do envelope: capsulas da mesma largura, com o icone do que fazem (o sorteio em pixels). */
@Composable
private fun BotaoDeOpcao(titulo: String, icone: ImageVector?, modifier: Modifier = Modifier, acao: () -> Unit) {
    Row(
        modifier.fillMaxWidth().height(48.dp).clip(CircleShape).background(Paleta.trilho).border(1.dp, Paleta.borda, CircleShape)
            .clickable(role = Role.Button, onClick = acao),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs, Alignment.CenterHorizontally),
    ) {
        if (icone == null) app.escalibur.wallet.ui.comp.PixelsDoSorteio(Modifier.size(16.dp)) else Icone(icone, Paleta.tinta, tamanho = 15.dp)
        Text(titulo, style = estilo(Tipo.acao), color = Paleta.tinta, maxLines = 1)
    }
}

// MARK: Lacrar

/**
 * V1: lacrar a senha de uma carteira num envelope Escalibur. A explicacao, a checagem do aparelho,
 * a senha do envelope (seis palavras sorteadas, ou a propria com o medidor e o "sim" abaixo de
 * forte), a repeticao com o nome e o lacre. O arquivo sai pelo seletor do sistema, para onde o
 * dono escolher.
 */
@Composable
fun FluxoDeLacrar(carteira: Carteira, demo: String? = null) {
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    var passo by remember { mutableStateOf("explicacao") }
    var erro by remember { mutableStateOf<String?>(null) }
    var trabalhando by remember { mutableStateOf(false) }
    var segundos by remember { mutableStateOf(3.0) }
    var sugestao by remember { mutableStateOf<List<String>>(emptyList()) }
    var propria by remember { mutableStateOf(false) }
    val senha = remember { TextFieldState() }
    val repeticao = remember { TextFieldState() }
    var revelar by remember { mutableStateOf(false) }
    var nome by remember { mutableStateOf(carteira.nome) }
    var risco by remember { mutableStateOf<JSONObject?>(null) }
    var arquivo by remember { mutableStateOf<ByteArray?>(null) }
    var nomeDoArquivo by remember { mutableStateOf("") }
    var fraca by remember { mutableStateOf(false) }
    /** A parte do lacre na tela: 0 a conta da senha, 1 a cifra, 2 a gravacao. */
    var parte by remember { mutableStateOf(0) }
    var inicioDoLacre by remember { mutableStateOf(0L) }
    val vista = androidx.compose.ui.platform.LocalView.current

    // O custo do Argon2 deste celular, medido fora da tela.
    LaunchedEffect(Unit) {
        runCatching { segundos = Api.objeto("envelope.calibrar").optDouble("segundos", 3.0) }
    }
    // So na depuracao: uma etapa do lacre sem a carteira aberta, para ver a tela. Nada e cifrado.
    if (BuildConfig.DEBUG && demo != null) LaunchedEffect(Unit) {
        when (demo) {
            "lacrar-criar" -> { sugestao = CifraDoEnvelope.exemplo.take(6); passo = "criar" }
            "lacrar-propria" -> { propria = true; passo = "criar" }
            "lacrar-repetir" -> passo = "repetir"
            "lacrando" -> {
                inicioDoLacre = System.currentTimeMillis()
                passo = "lacrando"
                delay((segundos * 1000).toLong())
                parte = 1
                delay(450)
                parte = 2
                nomeDoArquivo = "envelope-7F3A.esclbr"
                delay(450)
                passo = "feito"
            }
        }
    }
    DisposableEffect(Unit) {
        onDispose {
            senha.clearText()
            repeticao.clearText()
            arquivo?.fill(0)
            CoroutineScope(Dispatchers.IO).launch { runCatching { Api.objeto("envelope.encerrar") } }
        }
    }
    val salvar = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri: Uri? ->
        val dados = arquivo ?: return@rememberLauncherForActivityResult
        if (uri == null) return@rememberLauncherForActivityResult
        escopo.launch {
            val ok = withContext(Dispatchers.IO) {
                // "wt" trunca o que havia no arquivo; e so diz "salvo" depois de ler de volta o mesmo
                // conteudo (um provedor de nuvem que gravou pela metade nao passa).
                runCatching {
                    contexto.contentResolver.openOutputStream(uri, "wt")?.use { it.write(dados) } ?: return@runCatching false
                    val lido = contexto.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return@runCatching false
                    java.security.MessageDigest.isEqual(lido, dados)
                }.getOrDefault(false)
            }
            Avisos.mostrar(if (ok) t("Arquivo salvo.") else t("Não foi possível salvar o arquivo. Tente de novo."))
        }
    }

    fun fechar() {
        Navegacao.fechar()
    }

    fun sortear() {
        escopo.launch {
            sugestao = runCatching { Api.objeto("envelope.sugerir").getJSONArray("palavras").let { lista -> (0 until lista.length()).map { lista.getString(it) } } }
                .getOrDefault(emptyList())
        }
    }

    // A espera depois de a biometria mudar recusa ja no "Continuar", antes da checagem e do PIN.
    fun comecar() {
        erro = null
        escopo.launch {
            trabalhando = true
            val recusa = Autorizacao.recusaAntes(Autorizacao.Presenca.pinEBiometria)
            trabalhando = false
            if (recusa != null) erro = recusa else passo = "checagem"
        }
    }

    // Depois do deslize: o PIN e a biometria abrem as palavras. Na carteira que pede a passphrase,
    // ela vem antes e o cofre confere.
    fun abrirCarteira() {
        escopo.launch {
            erro = null
            var passphrase: PedidoDePassphrase.Resposta? = null
            if (carteira.pedePassphrase) {
                passphrase = PedidoDePassphrase.pedir(carteira.nome,
                    t("O envelope de %@ leva a passphrase junto. Digite a passphrase para seguir; depois vem a confirmação de sempre.", carteira.nome))
                if (passphrase == null) { passo = "explicacao"; return@launch }
            }
            trabalhando = true
            try {
                val segredo = passphrase?.bytes
                val aberta = Autorizacao.tentando(t("Lacrar a senha de %@ num envelope", carteira.nome), Autorizacao.Presenca.pinEBiometria) { credencial ->
                    val partes = if (segredo != null) credencial.partes(segredo.copyOf()) else credencial.partes()
                    Api.comSegredo("envelope.abrirCarteira", JSONObject().put("id", carteira.id).put("credencial", credencial.json()), *partes)
                }
                if (aberta == null) { passo = "explicacao"; return@launch }
                sortear()
                passo = "criar"
            } catch (falha: FalhaDoNucleo) {
                erro = when (falha.codigo) {
                    "passphrase.errada" -> t("A passphrase não confere. Nada foi assinado. Escreva igual ao que você anotou: maiúscula, acento e espaço contam.")
                    else -> Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível abrir a carteira agora.")
                }
                passo = "explicacao"
            } finally {
                passphrase?.bytes?.fill(0)
                trabalhando = false
            }
        }
    }

    fun seguirDaCriacao() {
        erro = null
        escopo.launch {
            if (!propria) {
                if (runCatching { Api.objeto("envelope.usarSorteada") }.isSuccess) {
                    sugestao = emptyList()
                    passo = "repetir"
                }
                return@launch
            }
            val resposta = runCatching { Api.comSegredo("envelope.conferir", JSONObject(), senha.bytes()) }.getOrNull() ?: return@launch
            when (resposta.getString("resultado")) {
                "ok" -> passo = "repetir"
                "curta" -> erro = t("Use pelo menos 4 caracteres.")
                "usaFrase" -> erro = t("Esta senha usa palavras da própria carteira. Quem achar o papel abre o envelope. Escolha outra.")
                "risco" -> risco = resposta
            }
        }
    }

    fun voltarParaCriar() {
        repeticao.clearText()
        erro = null
        escopo.launch {
            val palavras = runCatching { Api.objeto("envelope.voltar").getJSONArray("palavras") }.getOrNull()
            if (palavras != null && palavras.length() > 0) sugestao = (0 until palavras.length()).map { palavras.getString(it) }
            passo = "criar"
        }
    }

    fun lacrar() {
        erro = null
        parte = 0
        inicioDoLacre = System.currentTimeMillis()
        passo = "lacrando"
        escopo.launch {
            try {
                val lacrado = Api.comSegredo("envelope.lacrar", JSONObject().put("nome", nome.trim().take(64)), repeticao.bytes())
                arquivo = Base64.decode(lacrado.getString("arquivo"), Base64.NO_WRAP)
                nomeDoArquivo = lacrado.getString("nome")
                fraca = lacrado.optBoolean("fraca")
                App.recarregar()
                senha.clearText()
                repeticao.clearText()
                // A cifra e a gravacao levam milissegundos: a tela mostra cada uma por um instante,
                // para o dono ver o que aconteceu, e so entao o envelope fecha.
                parte = 1
                delay(450)
                parte = 2
                delay(450)
                passo = "feito"
                vista.performHapticFeedback(android.view.HapticFeedbackConstants.CONFIRM)
            } catch (falha: FalhaDoNucleo) {
                repeticao.clearText()
                erro = when (falha.codigo) {
                    "envelope.naoConferem" -> t("As duas não conferem. Digite a senha do envelope de novo.")
                    "envelope.notEnoughMemory" -> t("Pouca memória livre agora. Feche outros apps e tente de novo.")
                    else -> t("Não foi possível lacrar o envelope.")
                }
                passo = "repetir"
            }
        }
    }

    BackHandler(enabled = passo != "lacrando") {
        when (passo) {
            "repetir" -> voltarParaCriar()
            else -> fechar()
        }
    }
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().acimaDoTeclado()) {
        when (passo) {
            "explicacao" -> {
                // A cena comeca por baixo do fechar, sem cortar o alto dela (como no iOS).
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem)
                               .padding(top = Altura.barra + Espaco.xs + 8.dp, bottom = Espaco.lg)) {
                        // A mesma cena do passo 1 do "Como funciona", toda em pixels.
                        CenaDoEnvelope(Modifier.padding(bottom = Espaco.xs))
                        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                            Text(t("Criptografar a senha da carteira"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center)
                            Text(t("Uma cópia de segurança da senha da carteira, trancada com outra senha que só você conhece."), style = estilo(Tipo.corpo),
                                 color = Paleta.tintaSuave, textAlign = TextAlign.Center)
                            BotaoComoFunciona(Modifier.padding(top = Espaco.xxs))
                        }
                        Column(
                            Modifier.padding(top = Espaco.md).fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(Espaco.base),
                            verticalArrangement = Arrangement.spacedBy(Espaco.md),
                        ) {
                            PontoDoEnvelope(Icones.documentoCadeado, t("A senha da carteira vira um arquivo criptografado, aqui no celular."))
                            PontoDoEnvelope(Icones.chaveEmPe, t("Só você cria a senha do arquivo. Ela nunca sai deste celular."))
                            PontoDoEnvelope(Icones.olhoRiscado, t("O arquivo não passa por nós. Sem a sua senha, ninguém abre. Só você."))
                            PontoDoEnvelope(Icones.disco, t("Guarde onde quiser: sem a sua senha, o arquivo criptografado não abre."))
                        }
                    }
                    CabecalhoDeFolha("", { fechar() })
                }
                // O aviso fica junto do botao: embaixo da lista, ele passava despercebido e o fluxo
                // parecia voltar ao comeco sozinho (visto pelo dono, 22/10/2026).
                Rodape {
                    erro?.let { Faixa(TipoDeFaixa.falha, it) }
                    BotaoPrimario(t("Continuar"), carregando = trabalhando) { comecar() }
                }
            }
            "checagem" -> {
                CabecalhoDeFolha("", { fechar() })
                Box(Modifier.weight(1f)) {
                    VerificacaoDoAparelho(t("Deslize para criar a senha"), criando = false) { abrirCarteira() }
                    if (trabalhando) app.escalibur.wallet.ui.novacarteira.Trabalhando(t("Abrindo as palavras"))
                }
            }
            "criar" -> CriarSenha(propria, sugestao, senha, revelar, { revelar = it }, erro,
                                  aoSortear = { sortear() }, aoPropria = { erro = null; propria = true },
                                  aoSorteadas = { senha.clearText(); erro = null; propria = false; sortear() }, aoFechar = { fechar() }) { seguirDaCriacao() }
            "repetir" -> {
                CabecalhoDeFolha("", { fechar() }, aoVoltar = { voltarParaCriar() })
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md)) {
                    Box(Modifier.fillMaxWidth().padding(bottom = Espaco.md), contentAlignment = Alignment.Center) { EmblemaCifrado() }
                    Text(t("Repita a senha do envelope"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                         modifier = Modifier.fillMaxWidth())
                    Box(Modifier.padding(top = Espaco.lg)) { CampoSecreto(repeticao, t("Senha do envelope"), revelar) { revelar = it } }
                    Text(t("Segure o dedo no campo para ver o que digitou."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                         modifier = Modifier.padding(top = Espaco.xs))
                    erro?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.baixa, modifier = Modifier.padding(top = Espaco.xs)) }
                    Text(t("Nome dentro do envelope"), style = estilo(Tipo.nota), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.lg))
                    Box(Modifier.padding(top = Espaco.xs)) { CampoDeTexto(nome) { nome = it.take(64) } }
                    Text(t("O nome fica cifrado. O arquivo não diz de quem é."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                         modifier = Modifier.padding(top = Espaco.xs))
                }
                Rodape { BotaoPrimario(t("Lacrar envelope"), ligado = repeticao.text.isNotEmpty()) { lacrar() } }
            }
            // Lacrando e lacrado dividem a cena: as palavras caem no envelope, a aba fecha e o cadeado
            // se monta, sem o envelope sair do lugar.
            "lacrando", "feito" -> {
                CabecalhoDeFolha("", { fechar() })
                LacreEmCena(passo == "feito", parte, inicioDoLacre, segundos, nomeDoArquivo, fraca) { salvar.launch(nomeDoArquivo) }
            }
        }
    }
    risco?.let { r ->
        AvisoDeRisco(r, aoSortear = {
            risco = null
            senha.clearText()
            propria = false
            sortear()
        }) {
            risco = null
            escopo.launch {
                runCatching { Api.objeto("envelope.aceitarRisco") }
                passo = "repetir"
            }
        }
    }
}

/** A senha do envelope: o caminho padrao e o forte, seis palavras sorteadas; a propria e livre. */
@Composable
private fun ColumnScope.CriarSenha(
    propria: Boolean, sugestao: List<String>, senha: TextFieldState, revelar: Boolean, aoRevelar: (Boolean) -> Unit, erro: String?,
    aoSortear: () -> Unit, aoPropria: () -> Unit, aoSorteadas: () -> Unit, aoFechar: () -> Unit, aoSeguir: () -> Unit,
) {
    CabecalhoDeFolha("", aoFechar)
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md)) {
        // Digitando a senha propria: o selo das telas onde se digita um segredo.
        if (propria) Box(Modifier.fillMaxWidth().padding(bottom = Espaco.md), contentAlignment = Alignment.Center) { EmblemaCifrado() }
        Text(t("Crie a senha do envelope"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        Text(t("Só ela abre o envelope, em qualquer aparelho. Não é o PIN e não pode ser a senha da carteira. Não existe redefinir."),
             style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = Espaco.sm))
        if (propria) {
            Box(Modifier.padding(top = Espaco.lg)) { CampoSecreto(senha, t("Senha do envelope"), revelar, aoRevelar) }
            Text(t("Segure o dedo no campo para ver o que digitou."), style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.xs))
            LinhaDaForca(senha, Modifier.padding(top = Espaco.sm))
            BotaoDeOpcao(t("Usar 6 palavras sorteadas"), null, Modifier.padding(top = Espaco.md), acao = aoSorteadas)
        } else {
            // As seis palavras na placa laqueada, como a senha da carteira.
            androidx.compose.animation.Crossfade(sugestao, label = "sorteadas") { palavras ->
                Text(
                    palavras.joinToString(" "), fontFamily = FontFamily.Monospace, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Paleta.placaTinta,
                    modifier = Modifier.padding(top = Espaco.lg).fillMaxWidth().background(Paleta.viva, app.escalibur.wallet.ui.comp.PlacaLaqueada()).padding(Espaco.base),
                )
            }
            Text(t("Seis palavras sorteadas neste celular. Anote em outro lugar, longe do papel da senha da carteira."), style = estilo(Tipo.nota),
                 color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
            Row(Modifier.padding(top = Espaco.md), horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                BotaoDeOpcao(t("Sortear outras"), null, Modifier.weight(1f), acao = aoSortear)
                BotaoDeOpcao(t("Criar a minha"), Icones.lapis, Modifier.weight(1f), acao = aoPropria)
            }
        }
        erro?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.baixa, modifier = Modifier.padding(top = Espaco.xs)) }
    }
    Rodape {
        Text(t("Na próxima tela, você digita a senha de novo para confirmar."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
             textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(bottom = Espaco.sm))
        if (propria) BotaoPrimario(t("Continuar"), ligado = senha.text.isNotEmpty(), acao = aoSeguir)
        else BotaoPrimario(t("Anotei, continuar"), ligado = sugestao.isNotEmpty(), acao = aoSeguir)
    }
}

/** Ao vivo, enquanto o dono digita: em quanto tempo a senha cai, com o custo deste celular. */
@Composable
private fun LinhaDaForca(senha: TextFieldState, modifier: Modifier = Modifier) {
    var medida by remember { mutableStateOf<Pair<Int, JSONObject>?>(null) }
    @OptIn(kotlinx.coroutines.FlowPreview::class)
    LaunchedEffect(senha) {
        snapshotFlow { senha.text.length }.debounce(450).collect { tamanho ->
            medida = if (tamanho == 0) null else runCatching { tamanho to Api.comSegredo("envelope.medir", JSONObject(), senha.bytes()) }.getOrNull()
        }
    }
    val tamanho = senha.text.length
    val atual = medida?.takeIf { it.first == tamanho }?.second
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        when {
            tamanho == 0 -> Text(t("Qualquer senha com pelo menos 4 caracteres. Quanto mais longa e menos óbvia, mais tempo ela aguenta. Não use a senha da carteira."),
                                 style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            atual == null -> Text(t("Medindo a senha…"), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            atual.optBoolean("curta") -> Text(t("No mínimo 4 caracteres."), style = estilo(Tipo.nota), color = Paleta.baixa)
            else -> {
                val cor = when (atual.optString("faixa")) {
                    "muitoFraca" -> Paleta.baixa
                    "fraca" -> Paleta.cautela
                    "media" -> Paleta.tinta
                    else -> Paleta.sucesso
                }
                Text(atual.optString("texto"), style = estilo(Tipo.nota), color = cor)
                if (atual.optBoolean("soDigitos")) {
                    Text(t("Não use o código do celular nem o PIN do app: quem já viu você digitar abre o envelope."), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                }
            }
        }
    }
}

/** O risco de uma senha abaixo de forte, dito com o tempo, antes do lacre. */
@Composable
private fun AvisoDeRisco(r: JSONObject, aoSortear: () -> Unit, aoUsar: () -> Unit) {
    val media = r.optBoolean("media")
    androidx.compose.ui.window.Dialog(onDismissRequest = aoSortear) {
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.folha)).background(Paleta.corpo).padding(Espaco.lg),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icone(Icones.alerta, if (media) Paleta.tinta else Paleta.baixa, tamanho = 34.dp)
            Text(r.optString("titulo"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.md))
            Text(t("Seis palavras sorteadas aguentam milhões de anos."), style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center,
                 modifier = Modifier.padding(top = Espaco.sm))
            BotaoPrimario(t("Usar 6 palavras sorteadas"), Modifier.padding(top = Espaco.lg), acao = aoSortear)
            BotaoDeSegurar(if (r.optBoolean("segurar")) t("Segure para usar mesmo assim") else t("Usar mesmo assim"),
                           segundos = if (r.optBoolean("segurar")) 2 else 0, modifier = Modifier.padding(top = Espaco.sm), acao = aoUsar)
        }
    }
}

/** O botao que so age depois de segurado pelo tempo dado (o HoldButton do iOS); sem tempo, um toque. */
@Composable
private fun BotaoDeSegurar(titulo: String, segundos: Int, modifier: Modifier = Modifier, acao: () -> Unit) {
    val escopo = rememberCoroutineScope()
    val progresso = remember { Animatable(0f) }
    val forma = RoundedCornerShape(Raio.botao)
    Box(
        modifier.fillMaxWidth().height(Altura.secundaria).clip(forma).border(1.dp, Paleta.borda, forma)
            .pointerInput(segundos) {
                detectTapGestures(onPress = {
                    if (segundos == 0) {
                        if (tryAwaitRelease()) acao()
                        return@detectTapGestures
                    }
                    val trabalho = escopo.launch {
                        progresso.snapTo(0f)
                        progresso.animateTo(1f, tween(segundos * 1000, easing = LinearEasing))
                        acao()
                    }
                    tryAwaitRelease()
                    if (progresso.value < 1f) {
                        trabalho.cancel()
                        escopo.launch { progresso.animateTo(0f, tween(150)) }
                    }
                })
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.align(Alignment.CenterStart).fillMaxHeight().fillMaxWidth(progresso.value).background(Paleta.baixaFundo))
        Text(titulo, style = estilo(Tipo.acao), color = Paleta.baixa)
    }
}

/**
 * Lacrando e lacrado na mesma cena (o `sealStage` do iOS): as palavras viram pixels e caem no envelope
 * enquanto a senha fica cara de adivinhar, a aba fecha gravando, e lacrado o cadeado se monta e o
 * anel acende. A cena e os textos ficam no mesmo lugar nas duas etapas; o rodape troca embaixo.
 */
@Composable
private fun ColumnScope.LacreEmCena(feito: Boolean, parte: Int, inicio: Long, segundos: Double, nomeDoArquivo: String, fraca: Boolean, aoSalvar: () -> Unit) {
    val f by androidx.compose.animation.core.animateFloatAsState(if (feito) 1f else 0f, tween(250), label = "lacrado")
    val etapa = when {
        feito -> EtapaDoLacre.lacrado
        parte >= 2 -> EtapaDoLacre.gravando
        else -> EtapaDoLacre.trabalhando
    }
    Column(Modifier.weight(1f).fillMaxWidth().padding(horizontal = Espaco.margem).padding(bottom = Espaco.xs)) {
        // O alto da cena fica vazio depois que as palavras caem: o conjunto sobe metade disso.
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            Column(Modifier.offset(y = -AltoVazioDaCena / 2), horizontalAlignment = Alignment.CenterHorizontally) {
                CenaDoEnvelope(Modifier.padding(bottom = Espaco.xl), etapa = etapa)
                Box(contentAlignment = Alignment.TopCenter) {
                    Column(Modifier.fillMaxWidth().alpha(1 - f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                        Text(t("Lacrando o envelope"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center)
                        androidx.compose.animation.Crossfade(parte, label = "parte") { p ->
                            Text(when (p) {
                                0 -> t("Deixando a senha difícil de adivinhar")
                                1 -> t("Cifrando a senha da carteira")
                                else -> t("Gravando o arquivo")
                            }, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center)
                        }
                        ProgressoDoLacre(inicio, segundos, terminado = parte > 0, Modifier.padding(top = Espaco.sm).width(220.dp))
                        Text(t("Leva %@, só neste celular, sem internet.", cercaDe(segundos)), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                             textAlign = TextAlign.Center)
                    }
                    if (feito) Column(Modifier.fillMaxWidth().alpha(f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                        Text(t("Envelope lacrado"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center)
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                            Icone(Icones.documentoCadeado, Paleta.tintaSuave, tamanho = 15.dp)
                            Text(nomeDoArquivo, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
                        }
                        Text(t("O arquivo não mostra o que guarda. Guarde o arquivo e a senha em lugares diferentes: quem tiver os dois tem a carteira."),
                             style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.xxs))
                        if (fraca) {
                            Faixa(TipoDeFaixa.cautela, t("Senha muito fraca: guarde o arquivo num pendrive ou no seu computador, nunca na nuvem nem por e-mail."),
                                  Modifier.padding(top = Espaco.xs))
                        }
                    }
                }
            }
        }
        // Os dois rodapes ocupam a mesma altura: o meio de cima nao muda ao lacrar.
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
            Column(Modifier.fillMaxWidth().alpha(f)) {
                BotaoPrimario(t("Salvar ou enviar o arquivo"), ligado = feito, acao = aoSalvar)
                Text(t("Para abrir: Ajustes, Abrir um envelope, neste ou em outro celular com o app."), style = estilo(Tipo.nota), color = Paleta.tintaApagada,
                     textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = Espaco.sm))
            }
            if (!feito) Text(t("A senha do envelope não sai deste celular."), style = estilo(Tipo.nota), color = Paleta.tintaApagada, textAlign = TextAlign.Center,
                             modifier = Modifier.fillMaxWidth().padding(bottom = Espaco.sm).alpha(1 - f))
        }
    }
}

/**
 * A barra do lacre, em pixels: anda pelo tempo que este celular costuma levar e para em 92% ate o
 * Argon2 terminar de verdade; dai enche. Cada pixel aceso cifra de leve; os apagados ficam escuros.
 */
@Composable
private fun ProgressoDoLacre(inicio: Long, estimativa: Double, terminado: Boolean, modifier: Modifier = Modifier) {
    // O relogio so faz a barra redesenhar a cada quadro; o tempo vem do inicio do lacre.
    val quadro = app.escalibur.wallet.ui.comp.relogio(terminado)
    Canvas(modifier.height(6.dp)) {
        quadro.value
        val decorrido = (System.currentTimeMillis() - inicio) / 1000.0
        val bruto = (decorrido / maxOf(estimativa, 0.5)).coerceIn(0.0, 1.0)
        // Desacelera perto do fim: 1 - (1 - t)^2, ate 92%.
        val fracao = if (terminado) 1.0 else 0.92 * (1 - (1 - bruto) * (1 - bruto))
        val quantos = 30
        val passo = size.width / quantos
        val lado = minOf(passo - 1.6.dp.toPx(), size.height)
        val acesos = (fracao * quantos).toInt()
        val relogio = System.currentTimeMillis() / 1000.0
        for (i in 0 until quantos) {
            val bit = app.escalibur.wallet.ui.comp.PixelsCifrando.ruido(i, (relogio * 6).toInt() % 997, 0x4E)
            val tom = if (i < acesos) 0.62 + 0.3 * bit else 0.16
            drawRoundRect(app.escalibur.wallet.ui.comp.PixelsCifrando.cinza(tom), Offset(i * passo + (passo - lado) / 2, (size.height - lado) / 2),
                          Size(lado, lado), CornerRadius(1.2.dp.toPx()))
        }
    }
}

@Composable
private fun CampoDeTexto(texto: String, aoMudar: (String) -> Unit) {
    Box(
        Modifier.fillMaxWidth().height(Altura.campo).clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)
            .border(1.dp, Paleta.borda, RoundedCornerShape(Raio.cartao)).padding(horizontal = Espaco.md),
        contentAlignment = Alignment.CenterStart,
    ) {
        BasicTextField(texto, aoMudar, singleLine = true, textStyle = estilo(Tipo.linha).copy(color = Paleta.tinta), cursorBrush = SolidColor(Paleta.acento),
                       keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences), modifier = Modifier.fillMaxWidth())
    }
}

// MARK: Abrir

/** O nome do idioma da lista de palavras, na lingua do app. */
private fun nomeDoIdioma(idioma: String): String {
    val codigo = when (idioma) {
        "english" -> "en"; "spanish" -> "es"; "portuguese" -> "pt"; "french" -> "fr"; "italian" -> "it"; "czech" -> "cs"
        "japanese" -> "ja"; "korean" -> "ko"; "chineseSimplified" -> "zh-Hans"; "chineseTraditional" -> "zh-Hant"
        else -> return idioma
    }
    // O nome como o idioma escreve, igual ao iOS: "inglês" em portugues, "English" em ingles.
    return Locale.forLanguageTag(codigo).getDisplayName(Formato.locale)
}

/**
 * Abrir um envelope Escalibur: o arquivo `.esclbr` escolhido no seletor do sistema e a senha do
 * envelope. A senha da carteira e decifrada so aqui, sem internet; depois, importar a carteira ou
 * so ver as palavras.
 */
@Composable
fun FluxoDeAbrirEnvelope(aoCancelar: () -> Unit = { Navegacao.fechar() }, aoTerminar: () -> Unit = aoCancelar) {
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    var passo by remember { mutableStateOf("escolher") }
    var nomeDoArquivo by remember { mutableStateOf("") }
    var segundos by remember { mutableStateOf(3.0) }
    var erro by remember { mutableStateOf<String?>(null) }
    val senha = remember { TextFieldState() }
    var revelar by remember { mutableStateOf(false) }
    var pesado by remember { mutableStateOf(false) }
    var pesadoConfirmado by remember { mutableStateOf(false) }
    var aberto by remember { mutableStateOf<JSONObject?>(null) }
    var previa by remember { mutableStateOf<JSONObject?>(null) }
    var trabalhando by remember { mutableStateOf(false) }
    var palavras by remember { mutableStateOf(12) }

    DisposableEffect(Unit) {
        onDispose {
            senha.clearText()
            CoroutineScope(Dispatchers.IO).launch {
                runCatching { Api.objeto("envelope.encerrar") }
                runCatching { Api.objeto("carteira.descartarRascunho") }
            }
        }
    }

    fun mensagemDeMemoria(mib: Int) = t("Este envelope exige %lld MiB por tentativa, e este celular não consegue reservar tanto agora. Feche outros apps e tente de novo. A senha não chegou a ser testada.", mib)

    val escolher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        erro = null
        escopo.launch {
            val dados = withContext(Dispatchers.IO) {
                runCatching {
                    contexto.contentResolver.openInputStream(uri)?.use { entrada ->
                        val buffer = ByteArray(TAMANHO_DO_ENVELOPE + 1)
                        var lidos = 0
                        while (lidos < buffer.size) {
                            val n = entrada.read(buffer, lidos, buffer.size - lidos)
                            if (n < 0) break
                            lidos += n
                        }
                        if (lidos == TAMANHO_DO_ENVELOPE) buffer.copyOf(lidos) else null
                    }
                }.getOrNull()
            }
            if (dados == null) {
                erro = t("Este arquivo não é um envelope Escalibur. Envelopes terminam em .esclbr e têm 16.504 bytes.")
                return@launch
            }
            // O nome que o dono ve no seletor; o caminho da uri e so um numero do provedor.
            nomeDoArquivo = withContext(Dispatchers.IO) {
                runCatching {
                    contexto.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                        if (c.moveToFirst()) c.getString(0) else null
                    }
                }.getOrNull()
            } ?: "envelope.esclbr"
            try {
                segundos = Api.objeto("envelope.inspecionar", JSONObject().put("dados", Base64.encodeToString(dados, Base64.NO_WRAP))).optDouble("segundos", 3.0)
                pesadoConfirmado = false
                passo = "senha"
            } catch (falha: FalhaDoNucleo) {
                erro = when (falha.codigo) {
                    "envelope.boundToDevice" -> t("Este envelope foi lacrado preso ao aparelho que o criou e só abre no app Escalibur daquele aparelho.")
                    "envelope.caro" -> mensagemDeMemoria(falha.dados.optInt("mib"))
                    else -> t("Este arquivo não é um envelope Escalibur. Envelopes terminam em .esclbr e têm 16.504 bytes.")
                }
            }
        }
    }

    fun abrir() {
        if (senha.text.isEmpty() || passo == "abrindo") return
        if (segundos > 10 && !pesadoConfirmado) {
            pesado = true
            return
        }
        erro = null
        passo = "abrindo"
        escopo.launch {
            try {
                aberto = Api.comSegredo("envelope.abrir", JSONObject(), senha.bytes())
                senha.clearText()
                passo = "aberto"
            } catch (falha: FalhaDoNucleo) {
                erro = when (falha.codigo) {
                    "envelope.slip39Share" -> t("Este envelope guarda uma parte SLIP-39. Uma parte sozinha não abre carteira, e esta versão ainda não junta partes.")
                    "envelope.invalidPhrase" -> t("Este envelope está danificado e não abre. Se você tem outra cópia do arquivo, use a outra.")
                    "envelope.unknownLanguage" -> t("O envelope abriu, mas a senha da carteira dentro dele está num idioma que esta versão não reconhece.")
                    "envelope.caro" -> mensagemDeMemoria(falha.dados.optInt("mib"))
                    "envelope.cannotOpen" -> { senha.clearText(); t("Não abriu. Confira a senha, com maiúsculas, acentos e espaços, e tente de novo.") }
                    else -> { senha.clearText(); t("Não foi possível abrir este envelope agora. Tente de novo.") }
                }
                passo = "senha"
            }
        }
    }

    fun mostrarPrevia() {
        trabalhando = true
        erro = null
        escopo.launch {
            try {
                previa = Api.objeto("envelope.previa")
                passo = "previa"
            } catch (_: FalhaDoNucleo) {
                erro = t("Não foi possível importar a carteira.")
            } finally {
                trabalhando = false
            }
        }
    }

    val conferir = previa
    if (passo == "previa" && conferir != null) {
        Box(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
            ConferenciaDaImportacao(conferir, comPassphrase = aberto?.optBoolean("comPassphrase") == true, doEnvelope = true,
                                    aoVoltar = { passo = "aberto" }, aoGuardar = aoTerminar) { tronOutraChave ->
                val salva = Autorizacao.tentando(t("Guardar a carteira do envelope neste celular")) { credencial ->
                    Api.comSegredo("envelope.importar", JSONObject().put("tronOutraChave", tronOutraChave).put("credencial", credencial.json()), *credencial.partes())
                }
                salva?.let { Avisos.mostrar(t("%@ foi guardada neste celular.", it.optString("nome"))) }
                salva != null
            }
        }
        return
    }
    if (passo == "palavras") {
        val dados = aberto
        BackHandler { aoCancelar() }
        Box(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                Spacer(Modifier.height(Altura.barra))
                GravarPalavras(palavras, nomeDaCarteira = dados?.optString("rotulo")?.ifEmpty { null } ?: t("Envelope"),
                               comPassphrase = dados?.optBoolean("comPassphrase") == true) { aoCancelar() }
            }
            BotaoDeCanto(Icones.fechar, t("Fechar"), Modifier.padding(start = Espaco.xs)) { aoCancelar() }
        }
        return
    }
    BackHandler(enabled = passo != "abrindo") {
        when (passo) {
            "senha" -> { senha.clearText(); passo = "escolher" }
            else -> aoCancelar()
        }
    }
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding().acimaDoTeclado()) {
        CabecalhoDeFolha("", if (passo == "abrindo") null else ({ aoCancelar() }))
        when (passo) {
            "escolher" -> {
                // O conteudo no meio da pagina, entre o fechar e o botao; num celular baixo, rola.
                BoxWithConstraints(Modifier.weight(1f)) {
                Column(Modifier.fillMaxWidth().heightIn(min = maxHeight).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem),
                       horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    // O lacre ao contrario, em pixels: o envelope abre e as palavras sobem dele.
                    CenaDoEnvelope(Modifier.padding(top = Espaco.sm, bottom = Espaco.lg), abrindo = true)
                    Text(t("Abrir um envelope criptografado"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center)
                    Text(t("Escolha o arquivo .esclbr e digite a senha do envelope. A senha da carteira é decifrada só aqui, neste celular, sem internet, e o arquivo original continua onde está."),
                         style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(top = Espaco.sm))
                    BotaoComoFunciona(Modifier.padding(top = Espaco.md))
                    erro?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
                }
                }
                Rodape { BotaoPrimario(t("Escolher arquivo")) { escolher.launch(arrayOf("*/*")) } }
            }
            "senha" -> {
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md),
                       verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Box(Modifier.fillMaxWidth().padding(bottom = Espaco.md), contentAlignment = Alignment.Center) { EmblemaCifrado() }
                    Text(nomeDoArquivo, style = estilo(Tipo.monoPequeno), color = Paleta.tintaApagada, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(t("Senha do envelope"), style = estilo(Tipo.titulo), color = Paleta.tinta)
                    Text(t("A senha escolhida quando o envelope foi lacrado. No app Escalibur, é a senha do cofre."), style = estilo(Tipo.corpo), color = Paleta.tintaSuave,
                         modifier = Modifier.padding(bottom = Espaco.md))
                    CampoSecreto(senha, t("Senha do envelope"), revelar) { revelar = it }
                    Text(t("Segure o dedo no campo para ver o que digitou."), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                    erro?.let { Text(it, style = estilo(Tipo.nota), color = Paleta.baixa, modifier = Modifier.padding(top = Espaco.xs)) }
                }
                Rodape { BotaoPrimario(t("Abrir envelope"), ligado = senha.text.isNotEmpty()) { abrir() } }
            }
            // Abrindo e aberto dividem a ilustracao: o arquivo com o cifrado trocando enquanto o app faz
            // a conta e, aberto, um visto no lugar de cada palavra (nunca as de exemplo).
            "abrindo" -> {
                Column(Modifier.weight(1f).padding(horizontal = Espaco.margem)) {
                    CartaoCifrado(ModoDoCartao.abrindo, Modifier.padding(top = Espaco.sm, bottom = Espaco.xl), nomeDoArquivo)
                    Text(t("Abrindo o envelope"), style = estilo(Tipo.titulo), color = Paleta.tinta)
                    Text(t("Leva %@, e cada tentativa custa o mesmo para quem tentar adivinhar.", cercaDe(segundos)), style = estilo(Tipo.corpo),
                         color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.sm))
                }
            }
            "aberto" -> {
                val dados = aberto ?: return@Column
                palavras = dados.optInt("palavras", 12)
                Column(Modifier.weight(1f).padding(horizontal = Espaco.margem)) {
                    CartaoCifrado(ModoDoCartao.aberto, Modifier.padding(top = Espaco.sm, bottom = Espaco.xl), nomeDoArquivo, palavras)
                    Text(dados.optString("rotulo").ifEmpty { t("Envelope aberto") }, style = estilo(Tipo.titulo), color = Paleta.tinta)
                    Text(t("%lld palavras, lista em %@", palavras, nomeDoIdioma(dados.optString("idioma"))) +
                             (if (dados.optBoolean("comPassphrase")) t(" · com passphrase") else ""),
                         style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xxs))
                    erro?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
                }
                Rodape {
                    BotaoPrimario(t("Importar esta carteira"), carregando = trabalhando) { mostrarPrevia() }
                    BotaoSecundario(t("Só ver as palavras"), Modifier.padding(top = Espaco.sm)) {
                        escopo.launch {
                            if (runCatching { Api.objeto("envelope.verPalavras") }.isSuccess) passo = "palavras"
                        }
                    }
                }
            }
        }
    }
    if (pesado) {
        Confirmacao(
            t("Este envelope pede uma conta pesada"),
            t("Abrir leva cerca de %lld segundos com a tela parada. Um envelope lacrado pela Escalibur leva de 1 a 3. Se você não sabe de onde veio este arquivo, não abra.",
              Math.round(segundos).toInt()),
            t("Abrir mesmo assim"),
            aoConfirmar = {
                pesado = false
                pesadoConfirmado = true
                abrir()
            },
            aoCancelar = { pesado = false }, destrutiva = false,
        )
    }
}
