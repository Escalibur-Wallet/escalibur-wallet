package app.escalibur.wallet.ui.ajustes

import app.escalibur.wallet.ui.comp.DeslizeParaSeguir
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.text.input.TextFieldState
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

/** O que o modo faz quando a biometria muda (o HardenedFaceChange do iOS). */
private enum class Politica(val chave: String) {
    continuar("continuar"), esperar("esperar"), bloquear("bloquear");

    val titulo: String get() = when (this) {
        continuar -> t("Continuar normal")
        esperar -> t("Esperar 24 horas")
        bloquear -> t("Bloquear as carteiras")
    }

    /** A frase honesta de cada opcao, na lista das tres. */
    val resumo: String get() = when (this) {
        continuar -> t("Uma biometria nova abre as carteiras com o PIN, na hora. Quem sabe o seu PIN e o bloqueio de tela do celular tem acesso aos seus fundos.")
        esperar -> t("Uma biometria nova abre o app e mostra o saldo. O resto espera 24 horas.")
        bloquear -> t("Uma biometria nova fecha as carteiras daqui de vez. Só as palavras trazem de volta.")
    }

    /** O que acontece, numa frase curta, em "O que muda". */
    val consequencia: String get() = when (this) {
        continuar -> t("Com uma digital ou um rosto novo no celular, as carteiras continuam abrindo com o PIN.")
        esperar -> t("Com uma digital ou um rosto novo no celular, por 24 horas só dá para ver o saldo.")
        bloquear -> t("Se a biometria deste celular mudar, as carteiras daqui fecham de vez, e só as palavras de cada carteira trazem de volta.")
    }

    val icone: ImageVector get() = when (this) {
        continuar -> Icones.digital
        esperar -> Icones.ampulheta
        bloquear -> Icones.cadeadoCheio
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
    t("Entendo que, se a biometria deste celular mudar, as carteiras daqui fecham de vez, e só as palavras de cada carteira trazem de volta. Os nomes, endereços salvos e ajustes daqui se perdem junto.")

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
 * Ajustes, Seguranca, Super Security (o HardenedModeView do iOS): o PIN e a biometria juntos
 * para abrir o app, enviar, trocar e ver as palavras, e o que acontece quando a biometria muda.
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
    // Desligado: a politica escolhida para ligar (o padrao, continuar normal) e o aceite do bloqueio.
    var escolhida by remember { mutableStateOf(Politica.continuar) }
    var aceitouBloqueio by remember { mutableStateOf(false) }
    var escolhendo by remember { mutableStateOf(false) }

    suspend fun recarregar() {
        r = runCatching { RetratoDoReforco(Api.objeto("reforco.estado")) }.getOrNull()
        r?.let { if (it.ligado && it.politica != null) escolhida = it.politica }
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
                escolhida = Politica.continuar
                Avisos.mostrar(if (voltou) t("Super Security desligado. A biometria continua ligada.")
                               else t("Super Security desligado. A biometria ficou desligada; ligue de novo em Segurança."))
            } catch (falha: FalhaDoNucleo) {
                mensagem = mensagemDoReforco(falha, t("Não foi possível desligar agora. O Super Security continua ligado."))
            } finally {
                trabalhando = false
                App.recarregar()
                recarregar()
            }
        }
    }

    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
        CabecalhoDeFolha("", null, aoVoltar = { Navegacao.fechar() })
        val e = r
        Column(Modifier.weight(1f).verticalScroll(rolagem).padding(horizontal = Espaco.margem).padding(bottom = Espaco.lg)) {
            EmblemaDoReforco(e?.ligado == true)
            Text(t("Super Security"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center,
                 modifier = Modifier.fillMaxWidth().padding(top = Espaco.md))
            if (e?.ligado == true) {
                Row(Modifier.align(Alignment.CenterHorizontally).padding(top = Espaco.xs).height(28.dp).clip(CircleShape).background(Paleta.controle)
                        .padding(horizontal = Espaco.sm), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.size(7.dp).clip(CircleShape).background(Paleta.sucesso))
                    Text(t("Ligado"), style = estilo(Tipo.rotulo), color = Paleta.tinta)
                }
            }
            Text(t("O PIN e a biometria juntos para abrir o app, enviar, trocar e ver as palavras. Nenhum dos dois sozinho abre nada: é a própria cifra das carteiras que pede os dois."),
                 style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = Espaco.sm))
            if (e == null) return@Column
            if (e.ligado && e.espera > 0) Faixa(TipoDeFaixa.cautela, mensagemDaEspera(e.espera), Modifier.padding(top = Espaco.md))

            Text(t("O que muda"), style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg, bottom = Espaco.xs))
            Cartao {
                Ponto(Icones.chave, t("Quem viu só o seu PIN não abre o app nem envia nada sem a sua biometria."))
                Ponto(Icones.teclado, t("As palavras passam a ser digitadas no teclado do app: o teclado do celular não vê as letras."))
                Ponto(Icones.digital, t("Uma biometria que não confirma conta como tentativa, como um PIN errado."))
                Ponto(escolhida.icone, escolhida.consequencia)
            }
            // A linha da politica: ligado com o cabecalho ilegivel, o cofre nao diz qual vale, e ela some.
            if (!e.ligado || e.politica != null) {
                LinhaDaPolitica(escolhida, Modifier.padding(top = Espaco.md)) { escolhendo = true }
            }
            if (e.ligado) {
                Row(Modifier.padding(top = Espaco.lg), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                    Icone(Icones.vistoCheio, Paleta.sucesso, tamanho = 18.dp)
                    Text(t("Ligado neste celular"), style = estilo(Tipo.linha), color = Paleta.sucesso)
                }
            } else {
                Text(t("Para ligar"), style = estilo(Tipo.linha), color = Paleta.tinta, modifier = Modifier.padding(top = Espaco.lg, bottom = Espaco.xs))
                Cartao(preenchimento = 0.dp) {
                    Requisito(Icones.digital, e.biometriaLigada, t("Biometria neste app"),
                              when {
                                  e.biometriaLigada -> t("Ligado")
                                  e.biometriaPronta -> t("O Super Security nasce dela. Ligue em Segurança.")
                                  else -> t("Cadastre uma digital ou o rosto nas configurações do celular antes.")
                              })
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
        Rodape {
            val e2 = r
            if (e2?.ligado == true) {
                BotaoSecundario(t("Desligar o Super Security"), ligado = !trabalhando) { desligar() }
            } else {
                BotaoPrimario(t("Ligar o Super Security"), ligado = e2?.pronto == true) {
                    mensagem = null
                    val politica = escolhida
                    val aceito = aceitouBloqueio
                    Navegacao.cobrir { FluxoDeLigar(politica, aceito) }
                }
            }
        }
    }
    if (escolhendo) {
        val e = r
        FolhaDaPolitica(escolhida, aoFechar = { escolhendo = false }) { nova ->
            escolhendo = false
            if (nova == escolhida || e == null) return@FolhaDaPolitica
            if (e.ligado) {
                Navegacao.cobrir { FluxoDaPolitica(nova) }
            } else if (nova == Politica.bloquear) {
                Navegacao.cobrir {
                    AceiteDoBloqueio { aceito ->
                        Navegacao.fechar()
                        if (aceito) {
                            escolhida = Politica.bloquear
                            aceitouBloqueio = true
                        }
                    }
                }
            } else {
                escolhida = nova
                aceitouBloqueio = false
            }
        }
    }
}

@Composable
private fun EmblemaDoReforco(ligado: Boolean) {
    Box(Modifier.fillMaxWidth().padding(top = Espaco.xs), contentAlignment = Alignment.Center) {
        Box(Modifier.size(96.dp).clip(CircleShape).background(if (ligado) Paleta.controle else Paleta.corpo), contentAlignment = Alignment.Center) {
            Icone(Icones.escudo, if (ligado) Paleta.sucesso else Paleta.tinta, tamanho = 42.dp)
        }
    }
}

@Composable
private fun Cartao(preenchimento: androidx.compose.ui.unit.Dp = Espaco.base, conteudo: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).padding(preenchimento),
        verticalArrangement = Arrangement.spacedBy(Espaco.md),
    ) { conteudo() }
}

@Composable
private fun Ponto(icone: ImageVector, texto: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
            Icone(icone, Paleta.tintaSuave, tamanho = 15.dp)
        }
        Text(texto, style = estilo(Tipo.nota), color = Paleta.tinta, modifier = Modifier.weight(1f).padding(top = 6.dp))
    }
}

@Composable
private fun Requisito(icone: ImageVector, pronto: Boolean, titulo: String, detalhe: String, acao: Pair<String, () -> Unit>? = null) {
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = Espaco.md, vertical = Espaco.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Box {
            Box(Modifier.size(36.dp).clip(CircleShape).background(Paleta.controle), contentAlignment = Alignment.Center) {
                Icone(icone, Paleta.tinta, tamanho = 16.dp)
            }
            if (pronto) {
                Box(Modifier.align(Alignment.BottomEnd).offset(x = 3.dp, y = 3.dp).size(16.dp).clip(CircleShape).background(Paleta.corpo),
                    contentAlignment = Alignment.Center) { Icone(Icones.vistoCheio, Paleta.sucesso, tamanho = 14.dp) }
            }
        }
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

@Composable
private fun LinhaDaPolitica(politica: Politica, modifier: Modifier = Modifier, acao: () -> Unit) {
    Row(
        modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.corpo).clickable(onClick = acao).padding(Espaco.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
    ) {
        IconeDaPolitica(politica)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(t("Quando a biometria mudar"), style = estilo(Tipo.nota), color = Paleta.tintaSuave)
            Text(politica.titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
        }
        Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 13.dp)
    }
}

/** O bloqueio no vermelho forte: e a opcao sem volta. */
@Composable
private fun IconeDaPolitica(politica: Politica) {
    val bloqueio = politica == Politica.bloquear
    Box(Modifier.size(36.dp).clip(CircleShape).background(if (bloqueio) Paleta.baixa else Paleta.controle), contentAlignment = Alignment.Center) {
        Icone(politica.icone, if (bloqueio) Color.White else Paleta.tinta, tamanho = 15.dp)
    }
}

@Composable
private fun FolhaDaPolitica(atual: Politica, aoFechar: () -> Unit, aoEscolher: (Politica) -> Unit) {
    Folha(t("Quando a biometria mudar"), aoFechar) { fechar ->
        Column(Modifier.fillMaxWidth().padding(horizontal = Espaco.margem).padding(bottom = Espaco.md), verticalArrangement = Arrangement.spacedBy(Espaco.sm)) {
            for (politica in Politica.entries) {
                val escolhida = politica == atual
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(if (escolhida) Paleta.controle else Paleta.vazio)
                        .clickable { fechar { aoEscolher(politica) } }.padding(Espaco.md),
                    horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    IconeDaPolitica(politica)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(politica.titulo, style = estilo(Tipo.linha), color = Paleta.tinta)
                        Text(politica.resumo, style = estilo(Tipo.nota), color = Paleta.tintaSuave)
                    }
                    if (escolhida) Icone(Icones.visto, Paleta.tinta, tamanho = 16.dp)
                }
            }
            Text(t("Contra quem não sabe o bloqueio de tela do celular, as três valem igual: cadastrar uma biometria nova pede o bloqueio de tela."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada)
        }
    }
}

/** A nota de "Esperar 24 horas". */
@Composable
private fun NotaDaEspera() {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Raio.cartao)).background(Paleta.trilho).padding(Espaco.md),
        horizontalArrangement = Arrangement.spacedBy(Espaco.sm)) {
        Icone(Icones.ampulheta, Paleta.tintaSuave, tamanho = 15.dp)
        Text(t("Com uma biometria nova, por 24 horas só dá para ver o saldo: enviar, trocar e ver as palavras esperam. Reiniciar o celular recomeça a contagem."),
             style = estilo(Tipo.nota), color = Paleta.tinta, modifier = Modifier.weight(1f))
    }
}

/** "Bloquear as carteiras": o preco, dito antes, e o aceite. */
@Composable
private fun AceiteDoBloqueio(aoTerminar: (Boolean) -> Unit) {
    var aceito by remember { mutableStateOf(false) }
    BackHandler { aoTerminar(false) }
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
        CabecalhoDeFolha("", { aoTerminar(false) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Espaco.margem), verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Box(Modifier.size(96.dp).clip(CircleShape).background(Paleta.baixaFundo), contentAlignment = Alignment.Center) {
                    Icone(Icones.cadeadoCheio, Paleta.baixa, tamanho = 40.dp)
                }
            }
            Text(t("Bloquear as carteiras"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Text(Politica.bloquear.consequencia, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Faixa(TipoDeFaixa.cautela, t("Uma redefinição da biometria ou do bloqueio de tela também conta como mudança."))
            Aceite(aceito, textoDoAceite) { aceito = it }
        }
        Rodape { BotaoPrimario(t("Continuar"), ligado = aceito) { aoTerminar(true) } }
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
        val passphrase = remember { TextFieldState() }
        val repeticao = remember { TextFieldState() }
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

/** Ligar: o resumo do que muda, a politica, as palavras (no bloqueio), o deslizar e o PIN. */
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
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
        CabecalhoDeFolha("", if (trabalhando) null else ({ Navegacao.fechar() }))
        Column(Modifier.weight(1f).verticalScroll(rolagem).padding(horizontal = Espaco.margem).padding(bottom = Espaco.md),
               verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
            EmblemaDoReforco(false)
            Text(t("Antes de ligar"), style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Cartao {
                Ponto(Icones.escudo, t("Abrir o app, enviar, trocar e ver as palavras pedem o PIN e a biometria. Nenhum dos dois sozinho abre nada."))
                Ponto(Icones.teclado, t("As palavras passam a ser digitadas sempre no teclado do app."))
                Ponto(Icones.digital, t("Uma biometria que não confirma conta como tentativa, como um PIN errado."))
            }
            LinhaDaPolitica(politica) { escolhendo = true }
            if (politica == Politica.esperar) NotaDaEspera()
            if (politica == Politica.bloquear) Aceite(aceito, textoDoAceite) { aceito = it }
            Text(if (politica == Politica.bloquear) t("Depois, as palavras de cada carteira, e o PIN e a biometria duas vezes: uma para abrir, outra para conferir o modo novo antes de valer.")
                 else t("Depois, o PIN e a biometria duas vezes: uma para abrir, outra para conferir o modo novo antes de valer."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            mensagem?.let { Faixa(TipoDeFaixa.falha, it) }
        }
        Rodape {
            androidx.compose.runtime.key(rodada) {
                DeslizeParaSeguir(t("Ligar o Super Security"), ligado = (politica != Politica.bloquear || aceito) && !trabalhando) { ligar() }
            }
        }
    }
    if (escolhendo) {
        FolhaDaPolitica(politica, aoFechar = { escolhendo = false }) { nova ->
            escolhendo = false
            if (nova == politica) return@FolhaDaPolitica
            mensagem = null
            palavrasProntas = false
            if (nova == Politica.bloquear) {
                Navegacao.cobrir {
                    AceiteDoBloqueio { ok ->
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

/** Ligado, mudar a politica: o PIN e a biometria, e as palavras de cada carteira na ida para o bloqueio. */
@Composable
private fun FluxoDaPolitica(alvo: Politica) {
    val escopo = rememberCoroutineScope()
    var aceito by remember { mutableStateOf(false) }
    var digitando by remember { mutableStateOf(false) }
    var trabalhando by remember { mutableStateOf(false) }
    var mensagem by remember { mutableStateOf<String?>(null) }
    // A recusa aparece no fim da lista: a tela desce ate ela.
    val rolagem = rememberScrollState()
    LaunchedEffect(mensagem) { if (mensagem != null) rolagem.animateScrollTo(rolagem.maxValue) }
    var carteiras by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var espera by remember { mutableStateOf(0.0) }
    LaunchedEffect(Unit) {
        runCatching { RetratoDoReforco(Api.objeto("reforco.estado")) }.getOrNull()?.let {
            carteiras = it.carteiras
            espera = it.espera
        }
    }
    DisposableEffect(Unit) { onDispose { CoroutineScope(Dispatchers.IO).launch { runCatching { Api.objeto("reforco.esquecer") } } } }

    fun aplicar() {
        mensagem = null
        if (espera > 0) {
            mensagem = mensagemDaEspera(espera)
            return
        }
        escopo.launch {
            val credencial = Autorizacao.credencial(t("Mudar o que acontece quando a biometria mudar")) as? Credencial.Reforcado ?: return@launch
            trabalhando = true
            try {
                Api.comSegredo("reforco.politica", JSONObject().put("politica", alvo.chave), credencial.pin)
                Navegacao.fechar()
                Avisos.mostrar(t("Quando a biometria mudar: %@.", alvo.titulo))
            } catch (falha: FalhaDoNucleo) {
                mensagem = mensagemDoReforco(falha, t("Não foi possível mudar agora. Nada mudou: o modo de antes continua valendo."))
            } finally {
                trabalhando = false
                App.recarregar()
            }
        }
    }

    if (digitando) {
        ConferenciaDasPalavras(carteiras) { completas ->
            digitando = false
            if (completas) aplicar()
        }
        return
    }
    BackHandler(enabled = !trabalhando) { Navegacao.fechar() }
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().navigationBarsPadding()) {
        CabecalhoDeFolha("", if (trabalhando) null else ({ Navegacao.fechar() }))
        Column(Modifier.weight(1f).verticalScroll(rolagem).padding(horizontal = Espaco.margem), verticalArrangement = Arrangement.spacedBy(Espaco.md)) {
            Box(Modifier.fillMaxWidth().padding(top = Espaco.md), contentAlignment = Alignment.Center) { IconeDaPolitica(alvo) }
            Text(alvo.titulo, style = estilo(Tipo.titulo), color = Paleta.tinta, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Text(alvo.resumo, style = estilo(Tipo.corpo), color = Paleta.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            if (alvo == Politica.esperar) NotaDaEspera()
            if (alvo == Politica.bloquear) Aceite(aceito, textoDoAceite) { aceito = it }
            Text(if (alvo == Politica.bloquear) t("Depois, as palavras de cada carteira, e o PIN e a biometria duas vezes: uma para abrir, outra para conferir o modo novo antes de valer.")
                 else t("Depois, o PIN e a biometria duas vezes: uma para abrir, outra para conferir o modo novo antes de valer."),
                 style = estilo(Tipo.nota), color = Paleta.tintaApagada)
            mensagem?.let { Faixa(TipoDeFaixa.falha, it) }
        }
        Rodape {
            BotaoPrimario(t("Mudar"), ligado = alvo != Politica.bloquear || aceito, carregando = trabalhando) {
                if (alvo == Politica.bloquear) digitando = true else aplicar()
            }
        }
    }
}
