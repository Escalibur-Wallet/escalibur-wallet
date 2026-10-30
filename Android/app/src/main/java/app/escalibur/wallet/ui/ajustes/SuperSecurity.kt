package app.escalibur.wallet.ui.ajustes

import app.escalibur.wallet.ui.comp.DeslizeParaSeguir
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Dp
import app.escalibur.wallet.ui.comp.EmblemaCifrado
import app.escalibur.wallet.ui.comp.Girando
import app.escalibur.wallet.ui.comp.Interruptor
import app.escalibur.wallet.ui.comp.PixelsCifrando
import app.escalibur.wallet.ui.comp.TelaComBarra
import app.escalibur.wallet.ui.novacarteira.PapelRabiscado
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import app.escalibur.wallet.ui.comp.Segredo
import androidx.compose.foundation.text.input.clearText
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Ciclo
import app.escalibur.wallet.ui.Credencial
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.carteira.CopiaAgora
import app.escalibur.wallet.ui.comp.Aceite
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoPrimario
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.CabecalhoDeFolha
import app.escalibur.wallet.ui.comp.Faixa
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.Rodape
import app.escalibur.wallet.ui.comp.TipoDeFaixa
import app.escalibur.wallet.ui.importar.EntradaDaFrase
import app.escalibur.wallet.ui.importar.TelaDaFrase
import app.escalibur.wallet.ui.objetos
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.receber.opcional
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Raio
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import app.escalibur.wallet.ui.trocar.Folha
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

/** O que o modo faz quando a digital muda (o HardenedFaceChange do iOS, com os textos do Touch ID). */
private enum class Politica(val chave: String) {
    continuar("continuar"), esperar("esperar"), bloquear("bloquear");

    val titulo: String get() = when (this) {
        continuar -> t("Continuar normal")
        esperar -> t("Esperar 24 horas")
        bloquear -> t("Bloquear as carteiras")
    }

    /** A frase honesta de cada opcao, na lista das tres. */
    val resumo: String get() = when (this) {
        continuar -> t("Uma digital nova abre as carteiras com o PIN, na hora. Quem sabe o seu PIN e o bloqueio de tela do celular tem acesso aos seus fundos.")
        esperar -> t("Uma digital nova abre o app e mostra o saldo. O resto espera 24 horas.")
        bloquear -> t("Uma digital nova fecha as carteiras daqui de vez. Só as palavras trazem de volta.")
    }

    /** O que acontece, numa frase curta, em "O que muda". */
    val consequencia: String get() = when (this) {
        continuar -> t("Com uma digital nova no celular, as carteiras continuam abrindo com o PIN.")
        esperar -> t("Com uma digital nova no celular, por 24 horas só dá para ver o saldo.")
        bloquear -> t("Se a digital deste celular mudar, as carteiras daqui fecham de vez, e só as palavras de cada carteira trazem de volta.")
    }

    val icone: ImageVector get() = when (this) {
        continuar -> Icones.setaCirculo
        esperar -> Icones.cronometro
        bloquear -> Icones.cadeado
    }

    companion object {
        fun de(chave: String?) = entries.firstOrNull { it.chave == chave }
    }
}

private class RetratoDoReforco(j: JSONObject) {
    val ligado = j.optBoolean("ligado")
    val politica = Politica.de(j.opcional("politica"))
    val espera = j.optDouble("espera", 0.0)
    val biometriaLigada = j.optBoolean("biometriaLigada")
    val biometriaPronta = j.optBoolean("biometriaPronta")
    val faltaCopia: String? = j.opcional("faltaCopia")
    val faltaCopiaID: String? = j.opcional("faltaCopiaID")
    val carteiras = j.optJSONArray("carteiras").objetos()
    val pronto get() = biometriaLigada && faltaCopia == null && carteiras.isNotEmpty()
}

private val textoDoAceite get() =
    t("Entendo que, se a digital deste celular mudar, as carteiras daqui fecham de vez, e só as palavras de cada carteira trazem de volta. Os nomes, endereços salvos e ajustes daqui se perdem junto.")

private fun mensagemDaEspera(segundos: Double) =
    t("A biometria deste celular mudou. Enviar, trocar e ver as palavras voltam em %@. São 24 horas com o celular ligado; reiniciar ou uma biometria nova recomeça a contagem. Se não foi você, troque o bloqueio de tela do celular.", Formato.duracao(segundos))

/** O erro de ligar, desligar ou mudar a politica, dito ao dono. */
private fun mensagemDoReforco(falha: FalhaDoNucleo, padrao: String): String = when (falha.codigo) {
    "reforco.naoConfere" -> t("O que você digitou de %@ não confere com esta carteira. Confira no papel e comece de novo.", falha.dados.optString("nome"))
    "reforco.passphraseAntiga" -> t("A passphrase de %@ foi gravada por uma versão anterior do app, e restaurada pelas palavras a conta da Cardano dela muda. Mova o saldo dela para outra carteira e crie a carteira com passphrase de novo.", falha.dados.optString("nome"))
    "reforco.faltamPalavras" -> t("Digite as palavras de cada carteira antes de ligar.")
    "sessao.copiaPendente" -> t("Confira a cópia de todas as carteiras antes de ligar.")
    "cofre.pinErrado" -> Autorizacao.mensagemDePinErrado(falha)
    "cofre.espera" -> t("Tentativas demais. Tente de novo em %@.", Formato.duracao(falha.segundos))
    "cofre.biometriaNaoConfirmou" -> Autorizacao.mensagemDeBiometriaNaoConfirmou(falha.restantes)
    "cofre.cancelled" -> t("A biometria não confirmou. Nada mudou: o modo de antes continua valendo.")
    "cofre.biometryChanged" -> t("A biometria deste celular mudou durante a conferência. Nada mudou: o modo de antes continua valendo.")
    "cofre.hardenedSlotLost" -> t("A conferência do modo novo não abriu. Nada mudou: o modo de antes continua valendo.")
    "cofre.reforcadoBloqueado" -> when (falha.dados.optString("motivo")) {
        "biometryOff" -> t("Ligue a biometria neste app antes.")
        "changePending" -> t("Uma troca de PIN não terminou. Destrave o app com o PIN e tente de novo.")
        "legacySlot" -> t("Destrave o app com o PIN uma vez e tente de novo.")
        else -> t("A biometria não está disponível agora. Tente de novo no próprio celular.")
    }
    else -> Autorizacao.mensagemDeRecusa(falha) ?: padrao
}

/**
 * A politica escolhida para ligar (desligado; ligado, a que vale) e o aceite do bloqueio, divididos
 * entre a tela do Super Security e a de "Quando a digital mudar".
 */
private class EscolhaDoReforco {
    var politica by mutableStateOf(Politica.continuar)
    var aceitouBloqueio by mutableStateOf(false)
}

/**
 * Ajustes, Seguranca, Super Security (o HardenedModeView do iOS, com a digital no lugar do Face ID):
 * o PIN e a digital juntos para abrir o app, enviar, trocar e ver as palavras, e o que acontece
 * quando a digital muda.
 */
@Composable
fun TelaDoSuperSecurity() {
    val escopo = rememberCoroutineScope()
    var r by remember { mutableStateOf<RetratoDoReforco?>(null) }
    var mensagem by remember { mutableStateOf<String?>(null) }
    // A recusa aparece no fim da lista: a tela desce ate ela.
    val rolagem = rememberScrollState()
    LaunchedEffect(mensagem) { if (mensagem != null) rolagem.animateScrollTo(rolagem.maxValue) }
    var trabalhando by remember { mutableStateOf(false) }
    val escolha = remember { EscolhaDoReforco() }

    suspend fun recarregar() {
        r = runCatching { RetratoDoReforco(Api.objeto("reforco.estado")) }.getOrNull()
        r?.let { if (it.ligado && it.politica != null) escolha.politica = it.politica }
    }
    LaunchedEffect(Navegacao.pilha.size, Navegacao.sobre.size, Ciclo.vinda, App.estado.biometriaLigada) { recarregar() }

    fun desligar() {
        mensagem = null
        val atual = r ?: return
        if (atual.espera > 0) {
            mensagem = mensagemDaEspera(atual.espera)
            return
        }
        escopo.launch {
            val credencial = Autorizacao.credencial(t("Desligar o Super Security")) as? Credencial.Reforcado ?: return@launch
            trabalhando = true
            try {
                val voltou = Api.comSegredo("reforco.desligar", JSONObject(), credencial.pin).optBoolean("biometria")
                // Ligar de novo comeca do padrao.
                escolha.politica = Politica.continuar
                escolha.aceitouBloqueio = false
                Avisos.mostrar(if (voltou) t("Super Security desligado. A digital continua ligada.")
                               else t("Super Security desligado. A digital ficou desligada; ligue de novo em Segurança."))
            } catch (falha: FalhaDoNucleo) {
                mensagem = mensagemDoReforco(falha, t("Não foi possível desligar agora. O Super Security continua ligado."))
            } finally {
                trabalhando = false
                App.recarregar()
                recarregar()
            }
        }
    }

    // A digital ligada ou desligada daqui mesmo, como em Seguranca: ligar pede o PIN e confere a
    // digital; desligar pede o PIN e a digital.
    fun mudarDigital(ligar: Boolean) {
        mensagem = null
        if (ligar) {
            Navegacao.cobrir { LigarBiometria() }
            return
        }
        escopo.launch {
            try {
                Autorizacao.tentando(t("Desligar a digital"), Autorizacao.Presenca.pinEBiometria) { credencial ->
                    App.aplicar(Api.comSegredo("sessao.desligarBiometria", JSONObject().put("credencial", credencial.json()), *credencial.partes()))
                }
            } catch (falha: FalhaDoNucleo) {
                mensagem = Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível mudar agora.")
            }
            App.recarregar()
            recarregar()
        }
    }

    val e = r
    TelaComBarra({ Navegacao.fechar() }, rodape = {
        if (e?.ligado == true) {
            BotaoSecundario(t("Desligar o Super Security"), ligado = !trabalhando) { desligar() }
        } else {
            BotaoPrimario(t("Ligar o Super Security"), ligado = e?.pronto == true) {
                mensagem = null
                val politica = escolha.politica
                val aceito = escolha.aceitouBloqueio
                Navegacao.cobrir { FluxoDeLigar(politica, aceito) }
            }
        }
    }) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rolagem).padding(espaco).padding(horizontal = Espaco.margem).padding(vertical = Espaco.md)) {
            EmblemaDoReforco(e?.ligado == true, Modifier.fillMaxWidth().padding(top = Espaco.xs))
            // O titulo no centro, embaixo do emblema; so a etiqueta de ligado.
            Column(Modifier.fillMaxWidth().padding(top = Espaco.md), horizontalAlignment = Alignment.CenterHorizontally,
                   verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Text(t("Super Security"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center)
                if (e?.ligado == true) {
                    Row(Modifier.height(28.dp).clip(CircleShape).background(Paleta.controle).padding(horizontal = Espaco.sm),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Box(Modifier.size(7.dp).clip(CircleShape).background(Paleta.sucesso))
                        Text(t("Ligado"), style = estilo(Tipo.rotulo), color = Paleta.tinta)
                    }
                }
            }
            Text(t("O PIN e a digital juntos para abrir o app, enviar, trocar e ver as palavras. Nenhum dos dois sozinho abre nada: é a própria cifra das carteiras que pede os dois."),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = Espaco.sm))
            if (e == null) return@Column
            if (e.ligado && e.espera > 0) Faixa(TipoDeFaixa.cautela, mensagemDaEspera(e.espera), Modifier.padding(top = Espaco.md))

            Secao(t("O que muda"))
            Cartao {
                Ponto(Icones.pessoaComChave, t("Quem viu só o seu PIN não abre o app nem envia nada sem a sua digital."))
                Ponto(Icones.teclado, t("As palavras passam a ser digitadas no Safe Keyboard: o teclado do celular não vê as letras."))
                Ponto(Icones.maoLevantada, t("Uma digital que não confirma não conta como tentativa: só o PIN errado conta."))
                Ponto(Icones.digital, escolha.politica.consequencia)
            }
            // A linha da politica: o valor, e a tela das tres opcoes. Ligado com o cabecalho ilegivel,
            // o cofre nao diz qual vale, e a linha some.
            if (!e.ligado || e.politica != null) {
                LinhaDaPolitica(escolha.politica, Modifier.padding(top = Espaco.md)) { Navegacao.abrir { TelaDaPolitica(escolha) } }
            }
            if (e.ligado) {
                Row(Modifier.padding(top = Espaco.lg), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Icone(Icones.vistoCheio, Paleta.sucesso, tamanho = 18.dp)
                    Text(t("Ligado neste celular"), style = estilo(Tipo.linha), color = Paleta.sucesso)
                }
            } else {
                Secao(t("Para ligar"))
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo)) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = Espaco.md, vertical = Espaco.sm),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
                        IconeDoRequisito(Icones.digital, e.biometriaLigada)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(t("Digital neste app"), style = estilo(Tipo.linha), color = Paleta.tinta)
                            Text(when {
                                e.biometriaLigada -> t("Ligado")
                                e.biometriaPronta -> t("O Super Security nasce dela.")
                                else -> t("Cadastre uma digital nas configurações do celular antes.")
                            }, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                        }
                        Interruptor(e.biometriaLigada, { mudarDigital(it) }, habilitado = e.biometriaPronta || e.biometriaLigada)
                    }
                    Requisito(Icones.documento, e.faltaCopia == null && e.carteiras.isNotEmpty(),
                              e.faltaCopia?.let { t("Cópia de %@ conferida", it) } ?: t("Cópia de todas as carteiras conferida"),
                              if (e.faltaCopia == null) t("Pronto") else t("No Super Security, a cópia é o único caminho de volta."),
                              acao = e.faltaCopiaID?.let { id -> App.estado.carteiras.firstOrNull { it.id == id } }?.let { carteira ->
                                  t("Gravar agora") to { Navegacao.cobrir { CopiaAgora(carteira) } }
                              })
                }
            }
            Text(t("Se o seu celular oferecer, deixe ligadas nas configurações a proteção contra roubo e a verificação de identidade."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.md))
            mensagem?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
        }
    }
}

@Composable
private fun Secao(titulo: String) {
    Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg, bottom = Espaco.xs))
}

/**
 * O emblema do Super Security (o HardenedEmblem do iOS): o PIN e a digital, dois discos que se
 * encontram e travam com o cadeado no meio. Desligado, eles se aproximam e se afastam devagar;
 * ligado, ficam juntos.
 */
@Composable
private fun EmblemaDoReforco(junto: Boolean, modifier: Modifier = Modifier) {
    var juntos by remember { mutableStateOf(false) }
    val haptico = LocalHapticFeedback.current
    LaunchedEffect(junto) {
        juntos = false
        if (junto) return@LaunchedEffect
        while (isActive) {
            delay(900)
            juntos = true
            haptico.performHapticFeedback(HapticFeedbackType.SegmentTick)
            delay(2200)
            juntos = false
        }
    }
    val perto = junto || juntos
    val distancia by animateDpAsState(if (perto) 30.dp else 50.dp,
                                      if (perto) spring(dampingRatio = 0.72f, stiffness = 130f) else tween(600, easing = FastOutSlowInEasing), label = "discos")
    val cadeado by animateFloatAsState(if (perto) 1f else 0f,
                                       if (perto) spring(dampingRatio = 0.72f, stiffness = 130f) else tween(600, easing = FastOutSlowInEasing), label = "cadeado")
    Box(modifier.height(100.dp), contentAlignment = Alignment.Center) {
        DiscoDoReforco(Icones.gradeCheia, Modifier.offset(x = -distancia))
        DiscoDoReforco(Icones.digital, Modifier.offset(x = distancia))
        Selo(Icones.cadeadoCheio, 32.dp, Modifier.graphicsLayer {
            scaleX = 0.5f + 0.5f * cadeado
            scaleY = 0.5f + 0.5f * cadeado
            alpha = cadeado
        })
    }
}

/** Um disco do emblema: o PIN ou a digital, com o aro da cor do fundo. */
@Composable
private fun DiscoDoReforco(icone: ImageVector, modifier: Modifier = Modifier, tamanho: Dp = 76.dp) {
    Box(modifier.size(tamanho).clip(CircleShape).background(Paleta.vazio).padding(1.5.dp).clip(CircleShape).background(Paleta.controle),
        contentAlignment = Alignment.Center) {
        Icone(icone, Paleta.tinta, tamanho = tamanho * 0.42f)
    }
}

/** O cadeado entre os discos. */
@Composable
private fun Selo(icone: ImageVector, tamanho: Dp, modifier: Modifier = Modifier) {
    Box(modifier.size(tamanho).clip(CircleShape).background(Paleta.vazio).padding(3.dp).clip(CircleShape).background(Paleta.bordaForte),
        contentAlignment = Alignment.Center) {
        Icone(icone, Paleta.tinta, tamanho = tamanho * 0.42f)
    }
}

@Composable
private fun Cartao(preenchimento: Dp = Espaco.base, conteudo: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(preenchimento),
        verticalArrangement = Arrangement.spacedBy(Espaco.md),
    ) { conteudo() }
}

@Composable
private fun Ponto(icone: ImageVector, texto: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(icone, Paleta.tinta, tamanho = 18.dp)
        }
        Text(texto, style = estilo(Tipo.corpo), color = Paleta.tinta, modifier = Modifier.weight(1f).padding(top = 5.dp))
    }
}

/** Os itens de "Antes de ligar": o icone mais apagado e o texto menor. */
@Composable
private fun Resumo(icone: ImageVector, texto: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(icone, Paleta.tintaSuave, tamanho = 15.dp)
        }
        Text(texto, style = estilo(Tipo.nota), color = Paleta.tinta, modifier = Modifier.weight(1f).padding(top = 6.dp))
    }
}

/** O icone do requisito, com o selo de pronto no canto quando ele ja vale. */
@Composable
private fun IconeDoRequisito(icone: ImageVector, pronto: Boolean?) {
    Box {
        Box(Modifier.size(36.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(icone, Paleta.tinta, tamanho = 16.dp)
        }
        if (pronto == true) {
            Box(Modifier.align(Alignment.BottomEnd).offset(x = 3.dp, y = 3.dp).size(16.dp).clip(CircleShape).background(Paleta.corpo),
                contentAlignment = Alignment.Center) { Icone(Icones.vistoCheio, Paleta.sucesso, tamanho = 14.dp) }
        }
    }
}

@Composable
private fun Requisito(icone: ImageVector, pronto: Boolean, titulo: String, detalhe: String, acao: Pair<String, () -> Unit>? = null) {
    Row(Modifier.fillMaxWidth().padding(horizontal = Espaco.md, vertical = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        IconeDoRequisito(icone, pronto)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
            Text(detalhe, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
        }
        acao?.let { (rotulo, executar) ->
            Box(Modifier.height(32.dp).clip(CircleShape).background(Paleta.controle).clickable(onClick = executar).padding(horizontal = Espaco.sm),
                contentAlignment = Alignment.Center) { Text(rotulo, style = estilo(Tipo.rotulo), color = Paleta.tinta) }
        }
    }
}

/** "Quando a digital mudar", com o valor que vale, na tela do Super Security. */
@Composable
private fun LinhaDaPolitica(politica: Politica, modifier: Modifier = Modifier, acao: () -> Unit) {
    Row(
        modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).clickable(onClick = acao)
            .padding(horizontal = Espaco.md, vertical = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        IconeDoRequisito(politica.icone, null)
        Text(t("Quando a digital mudar"), style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.weight(1f))
        Text(politica.titulo, style = estilo(Tipo.nota), color = Paleta.tintaSuave, textAlign = TextAlign.End)
        Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 13.dp)
    }
}

/** A politica em "Antes de ligar": o nome em cima, o valor embaixo, o bloqueio no vermelho. */
@Composable
private fun BotaoDaPolitica(politica: Politica, acao: () -> Unit) {
    val bloqueio = politica == Politica.bloquear
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).clickable(onClick = acao).padding(Espaco.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        // O bloqueio no vermelho forte; a espera no verde, com o cronometro branco (pedido do dono, 24/10/2026).
        val espera = politica == Politica.esperar
        Box(Modifier.size(32.dp).clip(CircleShape).background(if (bloqueio) Paleta.baixa else if (espera) Paleta.sucesso else Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(politica.icone, if (bloqueio || espera) Color.White else Paleta.tinta, tamanho = 15.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(t("Quando a digital mudar"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            Text(politica.titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
        }
        Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 13.dp)
    }
}

/**
 * As tres politicas, uma embaixo da outra, cada uma com a frase dela (o HardenedFaceChangeOptions do
 * iOS). O bloqueio no vermelho forte: e a opcao sem volta. O visto diz qual vale.
 */
@Composable
private fun OpcoesDaPolitica(atual: Politica, trabalhando: Politica? = null, modifier: Modifier = Modifier, aoEscolher: (Politica) -> Unit) {
    val haptico = LocalHapticFeedback.current
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        for (politica in Politica.entries) {
            val escolhida = politica == atual
            val bloqueio = politica == Politica.bloquear
            val forma = RoundedCornerShape(Raio.cartao)
            Row(
                Modifier.fillMaxWidth().clip(forma).background(Paleta.corpo).border(1.dp, Paleta.borda, forma)
                    .clickable(enabled = trabalhando == null) {
                        haptico.performHapticFeedback(HapticFeedbackType.SegmentTick)
                        aoEscolher(politica)
                    }
                    .padding(Espaco.md),
                horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
            ) {
                val espera = politica == Politica.esperar
                Box(Modifier.size(36.dp).clip(CircleShape).background(if (bloqueio) Paleta.baixa else if (espera) Paleta.sucesso else Paleta.controle), contentAlignment = Alignment.Center) {
                    Icone(politica.icone, if (bloqueio || espera) Color.White else Paleta.tinta, tamanho = 16.dp)
                }
                Column(Modifier.weight(1f).padding(top = 1.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(politica.titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
                    Text(politica.resumo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                }
                Box(Modifier.size(width = 24.dp, height = 36.dp), contentAlignment = Alignment.Center) {
                    when {
                        trabalhando == politica -> Girando(Paleta.tintaSuave)
                        escolhida -> Icone(Icones.vistoCheio, Paleta.tinta, tamanho = 21.dp)
                        else -> Icone(Icones.circulo, Paleta.bordaForte, tamanho = 21.dp)
                    }
                }
            }
        }
    }
}

/** A explicacao curta da espera, ao escolher "Esperar 24 horas". */
@Composable
private fun NotaDaEspera(modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.trilho).padding(Espaco.md),
        horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Icone(Icones.cronometro, Paleta.tintaSuave, tamanho = 15.dp, modifier = Modifier.width(20.dp))
        Text(t("Com uma digital nova, por 24 horas só dá para ver o saldo: enviar, trocar e ver as palavras esperam. Reiniciar o celular recomeça a contagem."),
             style = estilo(Tipo.nota), color = Paleta.tinta, modifier = Modifier.weight(1f))
    }
}

/**
 * "Quando a digital mudar" (o HardenedFaceChangeView do iOS): as tres opcoes. Desligado, so a escolha
 * para ligar; ligado, mudar pede o PIN e a digital. "Bloquear as carteiras" abre a tela dele, com a
 * animacao e o aceite.
 */
@Composable
private fun TelaDaPolitica(escolha: EscolhaDoReforco) {
    val escopo = rememberCoroutineScope()
    var r by remember { mutableStateOf<RetratoDoReforco?>(null) }
    var trabalhando by remember { mutableStateOf<Politica?>(null) }
    var mensagem by remember { mutableStateOf<String?>(null) }
    suspend fun recarregar() { r = runCatching { RetratoDoReforco(Api.objeto("reforco.estado")) }.getOrNull() }
    LaunchedEffect(Ciclo.vinda) { recarregar() }
    val ligado = r?.ligado == true

    fun escolher(politica: Politica) {
        if (politica == escolha.politica || trabalhando != null) return
        mensagem = null
        if (politica == Politica.bloquear) {
            Navegacao.cobrir {
                TelaDoBloqueio(ligado) { feito ->
                    Navegacao.fechar()
                    if (!feito) return@TelaDoBloqueio
                    escolha.politica = Politica.bloquear
                    if (ligado) {
                        Avisos.mostrar(t("Quando a digital mudar: %@.", Politica.bloquear.titulo))
                        escopo.launch { recarregar() }
                    } else {
                        escolha.aceitouBloqueio = true
                    }
                }
            }
            return
        }
        if (!ligado) {
            escolha.politica = politica
            escolha.aceitouBloqueio = false
            return
        }
        // Na espera de "Esperar 24 horas", mudar a politica espera: recusa antes do teclado.
        val espera = r?.espera ?: 0.0
        if (espera > 0) {
            mensagem = mensagemDaEspera(espera)
            return
        }
        escopo.launch {
            val credencial = Autorizacao.credencial(t("Para trocar o que fazer se a digital mudar.")) as? Credencial.Reforcado ?: return@launch
            trabalhando = politica
            try {
                Api.comSegredo("reforco.politica", JSONObject().put("politica", politica.chave), credencial.pin)
                escolha.politica = politica
                Avisos.mostrar(t("Quando a digital mudar: %@.", politica.titulo))
            } catch (falha: FalhaDoNucleo) {
                mensagem = mensagemDoReforco(falha, t("Não foi possível mudar agora. Nada mudou: o modo de antes continua valendo."))
            } finally {
                trabalhando = null
                App.recarregar()
                recarregar()
            }
        }
    }

    Subtela("") {
        Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md)) {
            Text(t("Quando a digital mudar"), style = estilo(Tipo.titulo), color = Paleta.tinta)
            Text(t("Escolha o que acontece com as carteiras daqui quando uma digital nova entra neste celular. Apagar todas as digitais pode fechar as carteiras daqui em qualquer uma das três, e aí só as palavras de cada carteira trazem de volta."),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(top = Espaco.xs))
            val espera = r?.espera ?: 0.0
            if (ligado && espera > 0) Faixa(TipoDeFaixa.cautela, mensagemDaEspera(espera), Modifier.padding(top = Espaco.md))
            OpcoesDaPolitica(escolha.politica, trabalhando, Modifier.padding(top = Espaco.lg)) { escolher(it) }
            if (escolha.politica == Politica.esperar) NotaDaEspera(Modifier.padding(top = Espaco.sm))
            Text(t("Contra quem não sabe o bloqueio de tela do celular, as três protegem igual: cadastrar uma digital pede o bloqueio de tela."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada, modifier = Modifier.padding(top = Espaco.lg))
            mensagem?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
        }
    }
}

/**
 * "Bloquear as carteiras" (o HardenedLockFlow do iOS): a animacao em quatro quadros, o que vale, e o
 * aceite. Desligado, o aceite e a escolha para ligar (as palavras vem no fluxo de ligar); ligado,
 * depois do aceite, a frase de cada carteira, e o PIN e a digital.
 */
@Composable
private fun TelaDoBloqueio(ligado: Boolean, aoTerminar: (Boolean) -> Unit) {
    val escopo = rememberCoroutineScope()
    var aceito by remember { mutableStateOf(false) }
    var trabalhando by remember { mutableStateOf(false) }
    var mensagem by remember { mutableStateOf<String?>(null) }
    var digitando by remember { mutableStateOf(false) }
    // Muda quando a ativacao para com aviso: o deslizar volta ao comeco.
    var tentativa by remember { mutableIntStateOf(0) }
    var retrato by remember { mutableStateOf<RetratoDoReforco?>(null) }
    LaunchedEffect(Unit) { retrato = runCatching { RetratoDoReforco(Api.objeto("reforco.estado")) }.getOrNull() }

    fun aplicar() {
        escopo.launch {
            val credencial = Autorizacao.credencial(t("Para ativar o bloqueio se a digital mudar.")) as? Credencial.Reforcado
            if (credencial == null) {
                tentativa++
                return@launch
            }
            trabalhando = true
            try {
                Api.comSegredo("reforco.politica", JSONObject().put("politica", Politica.bloquear.chave), credencial.pin)
                aoTerminar(true)
            } catch (falha: FalhaDoNucleo) {
                mensagem = mensagemDoReforco(falha, t("Não foi possível mudar agora. Nada mudou: o modo de antes continua valendo."))
                tentativa++
            } finally {
                trabalhando = false
                App.recarregar()
            }
        }
    }

    fun comecar() {
        mensagem = null
        // Desligado: so a escolha. As palavras, o PIN e a digital vem no fluxo de ligar.
        if (!ligado) {
            aoTerminar(true)
            return
        }
        val espera = retrato?.espera ?: 0.0
        if (espera > 0) {
            mensagem = mensagemDaEspera(espera)
            tentativa++
            return
        }
        digitando = true
    }

    if (digitando) {
        ConferenciaDasPalavras(retrato?.carteiras.orEmpty()) { completas ->
            digitando = false
            if (completas) aplicar() else tentativa++
        }
        return
    }
    BackHandler(enabled = !trabalhando) { aoTerminar(false) }
    TelaComBarra(if (trabalhando) null else ({ aoTerminar(false) }), iconeDoVoltar = Icones.fechar, rodape = {
        androidx.compose.runtime.key(tentativa) {
            // O deslizar de pixels, que um toque sem querer nao dispara.
            DeslizeParaSeguir(t("Ativar o bloqueio"), ligado = aceito && !trabalhando) { comecar() }
        }
    }) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(espaco).padding(horizontal = Espaco.margem).padding(vertical = Espaco.md)) {
            HistoriaDoBloqueio(Modifier.fillMaxWidth().padding(top = Espaco.xs))
            Text(t("Trancar de vez se a digital mudar"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                 modifier = Modifier.fillMaxWidth().padding(top = Espaco.lg))
            Text(t("Qualquer mudança nas digitais, até uma digital sua, fecha as carteiras deste celular. Para voltar, você importa cada carteira pelas palavras, e os nomes, os endereços salvos e os ajustes daqui se perdem."),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = Espaco.xs))
            Text(t("Para ativar, você digita as palavras de cada carteira e confirma com o PIN e a digital."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = Espaco.md))
            Aceite(aceito, textoDoAceite, Modifier.padding(top = Espaco.lg)) { aceito = it }
            mensagem?.let { Faixa(TipoDeFaixa.falha, it, Modifier.padding(top = Espaco.md)) }
        }
    }
}

/**
 * A animacao de "Bloquear as carteiras" (o HardenedLockStory do iOS), em quatro quadros: o PIN e a
 * digital abrem as carteiras; outra digital entra; o selo de pixels fecha com o cadeado vermelho; o
 * papel das palavras traz de volta. As quatro legendas ocupam o mesmo lugar: o texto embaixo nao pula.
 */
@Composable
private fun HistoriaDoBloqueio(modifier: Modifier = Modifier) {
    val legendas = listOf(
        t("A sua digital e o PIN abrem as carteiras."),
        t("Alguém cadastra outra digital, ou apaga uma das suas."),
        t("As carteiras daqui fecham de vez. Ninguém abre, nem a Escalibur."),
        t("Só as palavras de cada carteira trazem de volta."),
    )
    var quadro by remember { mutableIntStateOf(0) }
    val haptico = LocalHapticFeedback.current
    LaunchedEffect(Unit) {
        while (isActive) {
            delay(2800)
            quadro = (quadro + 1) % 4
            if (quadro == 2) haptico.performHapticFeedback(HapticFeedbackType.Confirm)
        }
    }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
        PalcoDoBloqueio(quadro)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (indice in 0..3) {
                val largura by animateDpAsState(if (indice == quadro) 16.dp else 6.dp, spring(dampingRatio = 0.8f, stiffness = 110f), label = "ponto")
                Box(Modifier.size(width = largura, height = 6.dp).clip(CircleShape).background(if (indice == quadro) Paleta.tinta else Paleta.bordaForte))
            }
        }
        Box(Modifier.widthIn(max = 300.dp), contentAlignment = Alignment.TopCenter) {
            legendas.forEachIndexed { indice, legenda ->
                val opacidade by animateFloatAsState(if (indice == quadro) 1f else 0f, tween(300), label = "legenda")
                Text(legenda, style = estilo(Tipo.corpo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.alpha(opacidade))
            }
        }
    }
}

/** Um quadro da animacao: as pecas sao as mesmas nos quatro; o quadro decide onde cada uma esta. */
@Composable
private fun PalcoDoBloqueio(quadro: Int) {
    val mola = spring<Float>(dampingRatio = 0.8f, stiffness = 110f)
    val primeiro by animateFloatAsState(if (quadro == 0) 1f else 0f, mola, label = "primeiro")
    Box(Modifier.size(width = 240.dp, height = 124.dp).clipToBounds(), contentAlignment = Alignment.Center) {
        // O PIN e a digital do dono, com o cadeado aberto entre os dois; a digital sobe e some.
        DiscoDoReforco(Icones.gradeCheia, Modifier.offset(x = (-34).dp).alpha(primeiro), tamanho = 62.dp)
        DiscoDoReforco(Icones.digital, Modifier.offset(x = 34.dp, y = (-62).dp * (1f - primeiro)).alpha(primeiro), tamanho = 62.dp)
        Selo(Icones.cadeadoAbertoCheio, 30.dp, Modifier.graphicsLayer {
            scaleX = 0.5f + 0.5f * primeiro
            scaleY = 0.5f + 0.5f * primeiro
            alpha = primeiro
        })
        // Outra digital sendo cadastrada.
        AnimatedVisibility(quadro == 1, enter = scaleIn(initialScale = 0.8f) + fadeIn(), exit = scaleOut(targetScale = 0.8f) + fadeOut()) {
            DigitalNova()
        }
        // O selo de pixels fecha, com o cadeado vermelho.
        AnimatedVisibility(quadro == 2, enter = scaleIn(initialScale = 1.3f) + fadeIn(), exit = scaleOut(targetScale = 1.3f) + fadeOut()) {
            EmblemaCifrado(104.dp, Icones.cadeadoCheio, Paleta.baixa)
        }
        // A folha das palavras sendo anotada, a mesma de criar a carteira.
        AnimatedVisibility(quadro == 3, enter = slideInVertically { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut()) {
            PapelRabiscado(8, largura = 150.dp, altura = 98.dp)
        }
    }
}

/**
 * Outra digital sendo cadastrada, no estilo de pixels do app: o glifo da digital no meio e, em volta,
 * um anel de pixels que acende em amarelo, como o cadastro de uma digital; cheio, entra o "+" de digital
 * nova, e o anel recomeca.
 */
@Composable
private fun DigitalNova() {
    val periodo = 2600L
    var t by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) {
        val inicio = withFrameMillis { it }
        while (isActive) withFrameMillis { agora -> t = ((agora - inicio) % periodo) / periodo.toFloat() }
    }
    // Tres quartos do ciclo enchendo, o resto cheio, com o "+".
    val enchido = minOf(t / 0.72f, 1f)
    val cheio = enchido >= 1f
    val mais by animateFloatAsState(if (cheio) 1f else 0f, spring(dampingRatio = 0.6f, stiffness = 440f), label = "mais")
    Box(Modifier.size(100.dp)) {
        Canvas(Modifier.fillMaxSize()) {
            val quantos = 44
            val celula = 5.dp.toPx()
            val raio = size.minDimension / 2 - celula
            val centro = Offset(size.width / 2, size.height / 2)
            for (indice in 0 until quantos) {
                val parte = indice / quantos.toFloat()
                val angulo = parte * 2 * PI - PI / 2
                val aceso = parte < enchido
                val ponta = aceso && parte > enchido - 1.5f / quantos && !cheio
                val ponto = Offset(centro.x + raio * cos(angulo).toFloat(), centro.y + raio * sin(angulo).toFloat())
                val cor = when {
                    ponta -> Color.White
                    aceso -> Paleta.cautela
                    else -> PixelsCifrando.cinza(0.2 + 0.1 * PixelsCifrando.ruido(indice, 3, 0x7A))
                }
                drawRoundRect(cor, Offset(ponto.x - celula / 2, ponto.y - celula / 2), Size(celula, celula), CornerRadius(1.3.dp.toPx()))
            }
        }
        Box(Modifier.align(Alignment.Center).size(62.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(Icones.digital, if (cheio) Paleta.cautela else Paleta.tinta, tamanho = 32.dp)
        }
        Box(Modifier.align(Alignment.BottomEnd).offset(x = (-4).dp, y = (-4).dp).graphicsLayer {
            scaleX = 0.4f + 0.6f * mais
            scaleY = 0.4f + 0.6f * mais
            alpha = mais
        }.size(26.dp).clip(CircleShape).background(Paleta.vazio).padding(3.dp).clip(CircleShape).background(Paleta.cautela), contentAlignment = Alignment.Center) {
            Icone(Icones.mais, Paleta.vazio, tamanho = 12.dp)
        }
    }
}


/**
 * As palavras de cada carteira, uma depois da outra, para o cofre conferir antes de "Bloquear
 * as carteiras". Fechar no meio esquece as que ja vieram.
 */
@Composable
private fun ConferenciaDasPalavras(carteiras: List<JSONObject>, aoTerminar: (Boolean) -> Unit) {
    var indice by remember { mutableIntStateOf(0) }
    var terminou by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        onDispose { if (!terminou) CoroutineScope(Dispatchers.IO).launch { runCatching { Api.objeto("reforco.esquecer") } } }
    }
    val carteira = carteiras.getOrNull(indice) ?: return
    val id = carteira.getString("id")
    val temPassphrase = carteira.optBoolean("temPassphrase")
    // Uma tela nova a cada carteira: a entrada nasce do tamanho da frase dela.
    androidx.compose.runtime.key(id) {
        val entrada = remember { EntradaDaFrase(carteira.optInt("palavras", 12)) }
        val passphrase = remember { Segredo() }
        val repeticao = remember { Segredo() }
        DisposableEffect(Unit) {
            onDispose {
                entrada.zerar()
                passphrase.clearText()
                repeticao.clearText()
            }
        }
        Box(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
            TelaDaFrase(
                entrada, passphrase, repeticao, temPassphrase, {}, aoCancelar = { aoTerminar(false) }, conferindo = carteira.optString("nome"),
                aoConferirCopia = { frase, segredo ->
                    try {
                        val partes = if (segredo != null) arrayOf(frase, segredo) else arrayOf(frase)
                        Api.comSegredo("reforco.guardarFrase", JSONObject().put("id", id), *partes)
                        if (indice + 1 >= carteiras.size) {
                            terminou = true
                            aoTerminar(true)
                        } else indice++
                        null
                    } catch (_: FalhaDoNucleo) {
                        t("Não foi possível conferir as palavras agora.")
                    }
                },
                aoConferir = {},
            )
        }
    }
}

/** Ligar (o HardenedEnableFlow do iOS): o resumo do que muda, a politica, as palavras (no bloqueio), o deslizar e o PIN. */
@Composable
private fun FluxoDeLigar(inicial: Politica, aceitoInicial: Boolean) {
    val escopo = rememberCoroutineScope()
    var politica by remember { mutableStateOf(inicial) }
    var aceito by remember { mutableStateOf(inicial == Politica.bloquear && aceitoInicial) }
    var mensagem by remember { mutableStateOf<String?>(null) }
    // A recusa aparece no fim da lista: a tela desce ate ela.
    val rolagem = rememberScrollState()
    LaunchedEffect(mensagem) { if (mensagem != null) rolagem.animateScrollTo(rolagem.maxValue) }
    var trabalhando by remember { mutableStateOf(false) }
    var escolhendo by remember { mutableStateOf(false) }
    var digitando by remember { mutableStateOf(false) }
    var palavrasProntas by remember { mutableStateOf(false) }
    var rodada by remember { mutableIntStateOf(0) }
    var carteiras by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    LaunchedEffect(Unit) { carteiras = runCatching { RetratoDoReforco(Api.objeto("reforco.estado")).carteiras }.getOrDefault(emptyList()) }
    DisposableEffect(Unit) { onDispose { CoroutineScope(Dispatchers.IO).launch { runCatching { Api.objeto("reforco.esquecer") } } } }

    fun ligar() {
        mensagem = null
        if (politica == Politica.bloquear && !palavrasProntas) {
            digitando = true
            return
        }
        escopo.launch {
            // O PIN sempre: o cofre pede a biometria duas vezes, uma para abrir e outra para conferir.
            val credencial = Autorizacao.credencial(t("Ligar o Super Security"), forcarPin = true) as? Credencial.Pin
            if (credencial == null) {
                rodada++
                return@launch
            }
            trabalhando = true
            try {
                Api.comSegredo("reforco.ligar", JSONObject().put("politica", politica.chave), credencial.pin)
                App.recarregar()
                Navegacao.fechar()
                Avisos.mostrar(t("Super Security ligado."))
            } catch (falha: FalhaDoNucleo) {
                palavrasProntas = false
                mensagem = mensagemDoReforco(falha, t("Não foi possível ligar agora. Nada mudou: o modo de antes continua valendo."))
                rodada++
                App.recarregar()
            } finally {
                trabalhando = false
            }
        }
    }

    if (digitando) {
        ConferenciaDasPalavras(carteiras) { completas ->
            digitando = false
            palavrasProntas = completas
            if (completas) ligar() else rodada++
        }
        return
    }
    BackHandler(enabled = !trabalhando) { Navegacao.fechar() }
    TelaComBarra(if (trabalhando) null else ({ Navegacao.fechar() }), iconeDoVoltar = Icones.fechar, rodape = {
        androidx.compose.runtime.key(rodada) {
            // O deslizar de pixels.
            DeslizeParaSeguir(t("Ligar o Super Security"), ligado = (politica != Politica.bloquear || aceito) && !trabalhando) { ligar() }
        }
    }) { espaco ->
        Column(Modifier.fillMaxSize().verticalScroll(rolagem).padding(espaco).padding(horizontal = Espaco.margem).padding(vertical = Espaco.md),
               verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
            // Os dois discos, o PIN e a digital, se juntando no cadeado.
            EmblemaDoReforco(false, Modifier.fillMaxWidth())
            Text(t("Antes de ligar"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Cartao {
                Resumo(Icones.escudoCadeado, t("Abrir o app, enviar, trocar e ver as palavras pedem o PIN e a digital. Nenhum dos dois sozinho abre nada."))
                Resumo(Icones.teclado, t("As palavras passam a ser digitadas sempre no Safe Keyboard."))
                Resumo(Icones.maoLevantada, t("Uma digital que não confirma não conta como tentativa: só o PIN errado conta."))
            }
            BotaoDaPolitica(politica) { escolhendo = true }
            if (politica == Politica.esperar) NotaDaEspera()
            if (politica == Politica.bloquear) Aceite(aceito, textoDoAceite) { aceito = it }
            Text(if (politica == Politica.bloquear) t("Depois, as palavras de cada carteira, e o PIN e a digital duas vezes: uma para abrir, outra para conferir o modo novo antes de valer.")
                 else t("Depois, o PIN e a digital duas vezes: uma para abrir, outra para conferir o modo novo antes de valer."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            mensagem?.let { Faixa(TipoDeFaixa.falha, it) }
        }
    }
    if (escolhendo) {
        Folha(t("Quando a digital mudar"), { escolhendo = false }) { fechar ->
            OpcoesDaPolitica(politica, modifier = Modifier.padding(horizontal = Espaco.margem).padding(bottom = Espaco.md)) { nova ->
                fechar {
                    escolhendo = false
                    if (nova == politica) return@fechar
                    mensagem = null
                    palavrasProntas = false
                    if (nova == Politica.bloquear) {
                        // A tela do bloqueio, com a animacao e o aceite, que vale como o aceite de ligar.
                        Navegacao.cobrir {
                            TelaDoBloqueio(ligado = false) { ok ->
                                Navegacao.fechar()
                                if (ok) {
                                    politica = Politica.bloquear
                                    aceito = true
                                }
                            }
                        }
                    } else {
                        politica = nova
                        aceito = false
                    }
                }
            }
        }
    }
}
