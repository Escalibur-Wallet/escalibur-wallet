package app.escalibur.wallet.ui.ajustes

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.comp.BotaoTerciario
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.pin.EntradaDoPin
import app.escalibur.wallet.ui.pin.TelaDoPin
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.launch
import org.json.JSONObject

/** S3: Seguranca. */
@Composable
fun TelaDeSeguranca() {
    val escopo = rememberCoroutineScope()
    val estado = App.estado
    var erro by remember { mutableStateOf<String?>(null) }
    val disponivel = estado.biometriaPronta || estado.biometriaLigada

    // Desligar pede o PIN e a biometria: com ela desligada, o que pedia os dois passa a pedir so
    // o PIN, e quem viu o PIN desligaria aqui antes de ver as palavras.
    fun desligarBiometria() {
        erro = null
        escopo.launch {
            try {
                Autorizacao.tentando(t("Desligar a biometria"), Autorizacao.Presenca.pinEBiometria) { credencial ->
                    App.aplicar(Api.comSegredo("sessao.desligarBiometria", JSONObject().put("credencial", credencial.json()), *credencial.partes()))
                }
            } catch (falha: FalhaDoNucleo) {
                erro = Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível mudar agora.")
            }
            App.recarregar()
        }
    }

    Subtela(t("Segurança")) {
        // Na ordem do iOS: o PIN, o Super Security, o Safe Keyboard, a biometria (escondida no Super Security, que ja a
        // inclui) e o bloqueio; depois a carteira com passphrase e o apagar.
        GrupoDeAjustes(Modifier.padding(top = Espaco.md)) {
            LinhaDeAjuste(Icones.gradeDoPin, t("Mudar o PIN")) { Navegacao.cobrir { TrocarPin() } }
            LinhaDeAjuste(Icones.escudoCadeado, t("Super Security"), if (estado.reforcado) t("Ligado") else t("Desligado")) { Navegacao.abrir { TelaDoSuperSecurity() } }
            LinhaDeAjuste(Icones.teclado, "Safe Keyboard", if (estado.tecladoProprio) t("Ligado") else t("Desligado")) { Navegacao.abrir { TelaDoSafeKeyboard() } }
            if (!estado.reforcado) {
                LinhaComInterruptor(Icones.digital, t("Biometria"), estado.biometriaLigada, habilitado = disponivel) { ligar ->
                    if (ligar) Navegacao.cobrir { LigarBiometria() } else desligarBiometria()
                }
            }
            LinhaDeAjuste(Icones.cadeadoGirando, t("Bloquear o app"), rotuloDoBloqueio(estado.autoTravar)) { Navegacao.abrir { BloquearApp() } }
        }
        NotaDeAjuste(
            erro ?: if (disponivel) t("Com a biometria ligada, ver as palavras, lacrar um envelope e remover carteira pedem o PIN e a biometria. Depois de reiniciar o celular, a biometria só volta a valer depois do PIN digitado uma vez.")
            else t("Para usar a biometria aqui, cadastre uma digital ou o rosto nas configurações do celular."),
            cor = if (erro == null) Paleta.tintaApagada else Paleta.baixa,
        )
        estado.carteira?.takeIf { !it.observacao }?.let { carteira ->
            GrupoDeAjustes(Modifier.padding(top = Espaco.lg)) {
                LinhaDeAjuste(Icones.chave, t("Carteira com passphrase")) { Navegacao.abrir { FluxoDaCarteiraComPassphrase(carteira) } }
            }
            NotaDeAjuste(t("Outra carteira, aberta pela senha de %@ com uma passphrase que só você sabe.", carteira.nome))
        }
        GrupoDeAjustes(Modifier.padding(top = Espaco.lg)) {
            LinhaDeAjuste(Icones.lixeira, t("Apagar depois de PINs errados"), rotuloDoApagar(estado.apagarDepois)) { Navegacao.abrir { ApagarDepois() } }
        }
        Text(if (estado.reforcado) t("Super Security: abrir o app e todo envio, troca e ordem pedem o PIN e a biometria.")
             else t("Todo envio, troca e ordem pede a biometria ou o PIN."), style = estilo(Tipo.nota), color = Paleta.tintaSuave,
             modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg))
    }
}

/** Ligar a biometria: o PIN, e depois ela mesma, para a chave nascer presa a ela. */
@Composable
internal fun LigarBiometria() {
    val escopo = rememberCoroutineScope()
    val entrada = remember { EntradaDoPin(App.estado.pinDigitos) }
    var trabalhando by remember { mutableStateOf(false) }
    BackHandler { entrada.limpar(); Navegacao.fechar() }
    TelaDoPin(
        titulo = t("Confirme com o PIN"), subtitulo = t("Para ligar a biometria."), entrada = entrada, trabalhando = trabalhando,
        aoCompletar = {
            val pin = entrada.tirar()
            trabalhando = true
            escopo.launch {
                try {
                    App.aplicar(Api.comSegredo("sessao.ligarBiometria", JSONObject().put("motivo", t("Confirme a biometria para ligar")), pin))
                    Navegacao.fechar()
                } catch (falha: FalhaDoNucleo) {
                    entrada.falhar(when (falha.codigo) {
                        "cofre.pinErrado" -> Autorizacao.mensagemDePinErrado(falha)
                        "cofre.espera" -> t("Tentativas demais. Tente de novo em %@.", Formato.duracao(falha.segundos))
                        "cofre.cancelled" -> t("A biometria não confirmou. Ela continua desligada.")
                        "cofre.wiped" -> Autorizacao.mensagemDeRecusa(falha) ?: ""
                        else -> t("Não foi possível ligar a biometria agora.")
                    })
                    App.recarregar()
                } finally {
                    trabalhando = false
                }
            }
        },
    ) {
        BotaoTerciario(t("Cancelar")) { entrada.limpar(); Navegacao.fechar() }
    }
}

/** Mudar o PIN: o atual, o novo e a repeticao. Antes do ponto sem volta, o atual continua valendo. */
@Composable
private fun TrocarPin() {
    val escopo = rememberCoroutineScope()
    val entrada = remember { EntradaDoPin(App.estado.pinDigitos) }
    var passo by remember { mutableIntStateOf(0) }
    var atual by remember { mutableStateOf<ByteArray?>(null) }
    var novo by remember { mutableStateOf<ByteArray?>(null) }
    var trabalhando by remember { mutableStateOf(false) }

    fun cancelar() {
        atual?.fill(0)
        novo?.fill(0)
        entrada.limpar()
        Navegacao.fechar()
    }

    fun seguir() {
        val pin = entrada.tirar()
        when (passo) {
            0 -> {
                atual = pin
                passo = 1
                entrada.usarTamanhos(setOf(6))
            }
            1 -> {
                novo = pin
                passo = 2
            }
            else -> {
                val escolhido = novo ?: return
                val mesmo = java.security.MessageDigest.isEqual(escolhido, pin)
                pin.fill(0)
                if (!mesmo) {
                    escolhido.fill(0)
                    novo = null
                    passo = 1
                    entrada.falhar(t("Os dois não conferem. Escolha de novo."))
                    return
                }
                val pinAtual = atual ?: return
                trabalhando = true
                escopo.launch {
                    try {
                        val credencial = JSONObject().put("tipo", if (App.estado.reforcado) "reforcado" else "pin").put("motivo", t("Mudar o PIN"))
                        App.aplicar(Api.comSegredo("sessao.trocarPIN", JSONObject().put("credencial", credencial), pinAtual, escolhido))
                        atual = null
                        novo = null
                        Navegacao.fechar()
                    } catch (falha: FalhaDoNucleo) {
                        atual = null
                        novo = null
                        passo = 0
                        entrada.usarTamanhos(App.estado.pinDigitos)
                        entrada.falhar(when (falha.codigo) {
                            "cofre.pinErrado" -> t("O PIN atual não confere.")
                            "cofre.espera" -> t("Tentativas demais. Tente de novo em %@.", Formato.duracao(falha.segundos))
                            "cofre.malformedPIN" -> t("O PIN precisa ter 4 ou 6 números.")
                            else -> Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível trocar. O PIN atual continua valendo.")
                        })
                        App.recarregar()
                    } finally {
                        trabalhando = false
                    }
                }
            }
        }
    }

    BackHandler { cancelar() }
    TelaDoPin(
        titulo = listOf(t("Digite o PIN atual"), t("Escolha o novo PIN"), t("Repita o novo PIN"))[passo],
        subtitulo = if (passo == 1) {
            if (entrada.tamanho == 4) t("Quatro dígitos são mais fáceis de adivinhar que seis. Não use o PIN da tela do celular: quem rouba o celular geralmente já viu esse código.")
            else t("Não use o PIN da tela do celular: quem rouba o celular geralmente já viu esse código.")
        } else null,
        entrada = entrada, trabalhando = trabalhando, aoCompletar = { seguir() },
    ) {
        if (passo == 1) {
            BotaoTerciario(if (entrada.tamanho == 4) t("Usar PIN de 6 dígitos") else t("Usar PIN de 4 dígitos")) {
                entrada.escolher(if (entrada.tamanho == 4) 6 else 4)
            }
        }
        BotaoTerciario(t("Cancelar")) { cancelar() }
    }
}

private val prazos = listOf(0, 30, 60, 300, 600)

fun rotuloDoBloqueio(segundos: Int): String = when (prazos.lastOrNull { it <= segundos } ?: 0) {
    0 -> t("Ao sair do app")
    30 -> t("Depois de 30 segundos")
    60 -> t("Depois de 1 minuto")
    300 -> t("Depois de 5 minutos")
    else -> t("Depois de 10 minutos")
}

private fun motivoDoBloqueio(segundos: Int): String = when (segundos) {
    0 -> t("Bloquear o app ao sair dele")
    30 -> t("Bloquear o app depois de 30 segundos")
    60 -> t("Bloquear o app depois de 1 minuto")
    300 -> t("Bloquear o app depois de 5 minutos")
    else -> t("Bloquear o app depois de 10 minutos")
}

/** Encurtar so reduz a janela de quem pega o celular destravado; alongar amplia, e pede o PIN. */
@Composable
private fun BloquearApp() {
    val escopo = rememberCoroutineScope()
    var erro by remember { mutableStateOf<String?>(null) }
    val atual = App.estado.autoTravar
    Subtela(t("Bloquear o app")) {
        GrupoDeAjustes(Modifier.padding(top = Espaco.md)) {
            for (segundos in prazos) {
                LinhaDeEscolha(rotuloDoBloqueio(segundos), segundos == atual) {
                    if (segundos == atual) return@LinhaDeEscolha
                    erro = null
                    escopo.launch {
                        try {
                            if (segundos < atual) {
                                App.aplicar(Api.objeto("ajustes.autoTravar", JSONObject().put("segundos", segundos)))
                            } else {
                                Autorizacao.tentando(motivoDoBloqueio(segundos), Autorizacao.Presenca.pin) { credencial ->
                                    App.aplicar(Api.comSegredo("ajustes.autoTravar", JSONObject().put("segundos", segundos).put("credencial", credencial.json()), *credencial.partes()))
                                }
                            }
                        } catch (falha: FalhaDoNucleo) {
                            erro = Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível salvar. Tente de novo.")
                        }
                    }
                }
            }
        }
        NotaDeAjuste(erro ?: t("Encurtar vale na hora. Alongar pede o PIN."), cor = if (erro == null) Paleta.tintaApagada else Paleta.baixa)
    }
}

fun rotuloDoApagar(limite: Int?): String = limite?.let { t("Depois de %lld erros", it) } ?: t("Nunca")

/**
 * Quantos PINs errados apagam as carteiras deste celular, ou nunca. Qualquer mudanca pede o PIN:
 * ligar e uma forma de destruir as carteiras errando de proposito; desligar tira a barreira.
 */
@Composable
private fun ApagarDepois() {
    val escopo = rememberCoroutineScope()
    var erro by remember { mutableStateOf<String?>(null) }
    val estado = App.estado
    val opcoes: List<Int?> = listOf<Int?>(null) + estado.opcoesDeApagar
    Subtela(t("Apagar depois de erros")) {
        GrupoDeAjustes(Modifier.padding(top = Espaco.md)) {
            for (opcao in opcoes) {
                LinhaDeEscolha(rotuloDoApagar(opcao), opcao == estado.apagarDepois) {
                    if (opcao == estado.apagarDepois) return@LinhaDeEscolha
                    erro = null
                    val motivo = opcao?.let { t("Apagar depois de %lld PINs errados", it) } ?: t("Nunca apagar por PINs errados")
                    escopo.launch {
                        try {
                            Autorizacao.tentando(motivo, Autorizacao.Presenca.pin) { credencial ->
                                val corpo = JSONObject().put("credencial", credencial.json())
                                if (opcao != null) corpo.put("limite", opcao)
                                App.aplicar(Api.comSegredo("ajustes.apagarDepois", corpo, *credencial.partes()))
                            }
                        } catch (falha: FalhaDoNucleo) {
                            erro = if (falha.codigo.startsWith("ajustes.semCopia:")) t("Confirme a cópia de %@ antes de ligar.", falha.codigo.removePrefix("ajustes.semCopia:"))
                                   else Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível mudar agora. Tente de novo.")
                        }
                    }
                }
            }
        }
        NotaDeAjuste(
            erro ?: t("Contra quem pega o celular e tenta adivinhar o PIN. Depois do número escolhido de PINs errados seguidos, este celular apaga as carteiras; só a senha de cada carteira ou um envelope traz de volta. Mudar pede o PIN."),
            cor = if (erro == null) Paleta.tintaApagada else Paleta.baixa,
        )
    }
}
