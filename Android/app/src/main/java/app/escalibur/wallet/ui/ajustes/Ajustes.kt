package app.escalibur.wallet.ui.ajustes

import app.escalibur.wallet.ui.comp.LocalEspacoDaBarra
import app.escalibur.wallet.ui.Ciclo
import app.escalibur.wallet.ui.avisos.TelaDoRecebimento
import app.escalibur.wallet.ui.avisos.TelaDosAlertas
import app.escalibur.wallet.ui.avisos.resumoDoRecebimento
import app.escalibur.wallet.ui.avisos.resumoDosAlertas
import app.escalibur.wallet.ui.envelope.FluxoDeAbrirEnvelope
import app.escalibur.wallet.ui.envelope.FluxoDeLacrar
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.BuildConfig
import app.escalibur.wallet.nucleo.Api
import app.escalibur.wallet.nucleo.FalhaDoNucleo
import app.escalibur.wallet.ui.App
import app.escalibur.wallet.ui.Autorizacao
import app.escalibur.wallet.ui.Carteira
import app.escalibur.wallet.ui.Formato
import app.escalibur.wallet.ui.carteira.AdicionarCarteira
import app.escalibur.wallet.ui.carteira.CopiaAgora
import app.escalibur.wallet.ui.carteira.FluxoDeRevelar
import app.escalibur.wallet.ui.carteira.GlifoDaCarteira
import app.escalibur.wallet.ui.carteira.Redes
import app.escalibur.wallet.ui.comp.Avisos
import app.escalibur.wallet.ui.comp.BotaoDestrutivo
import app.escalibur.wallet.ui.comp.BotaoSecundario
import app.escalibur.wallet.ui.comp.Confirmacao
import app.escalibur.wallet.ui.comp.Icone
import app.escalibur.wallet.ui.comp.Icones
import app.escalibur.wallet.ui.comp.SeloDaRede
import app.escalibur.wallet.ui.comp.TituloDeAba
import app.escalibur.wallet.ui.comp.Transferencia
import app.escalibur.wallet.ui.enviar.PedidoDePassphrase
import app.escalibur.wallet.ui.legal.DocumentoLegal
import app.escalibur.wallet.ui.legal.FolhaLegal
import app.escalibur.wallet.ui.principal.Navegacao
import app.escalibur.wallet.ui.t
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo
import kotlinx.coroutines.launch
import org.json.JSONObject
import app.escalibur.wallet.ui.carteira.RemocaoDeCarteira
import app.escalibur.wallet.ui.carteira.PopupDeRemover
import app.escalibur.wallet.ui.carteira.LinhaQueApaga
import java.util.Date

/** S1: Ajustes. */
@Composable
fun TelaDeAjustes() {
    val estado = App.estado
    var alertas by remember { mutableStateOf<String?>(null) }
    var recebimento by remember { mutableStateOf<String?>(null) }
    // Ao voltar de uma subtela: o resumo de agora.
    LaunchedEffect(Navegacao.pilha.size, Navegacao.sobre.size, Ciclo.vinda) {
        alertas = resumoDosAlertas()
        recebimento = resumoDoRecebimento()
    }
    Column(Modifier.fillMaxSize().background(Paleta.vazio).statusBarsPadding().verticalScroll(rememberScrollState()).padding(bottom = Espaco.xl + LocalEspacoDaBarra.current)) {
        TituloDeAba(t("Ajustes"))
        GrupoDeAjustes(Modifier.padding(top = Espaco.lg)) {
            LinhaDeAjuste(Icones.carteiraContorno, t("Carteiras"), "${estado.carteiras.size}") { Navegacao.abrir { TelaDeCarteiras() } }
            LinhaDeAjuste(Icones.cadeado, t("Segurança")) { Navegacao.abrir { TelaDeSeguranca() } }
            LinhaDeAjuste(Icones.livro, t("Endereços salvos"), estado.contatos.takeIf { it > 0 }?.toString()) { Navegacao.abrir { TelaDeContatos() } }
            LinhaDeAjuste(Icones.envelopeAberto, t("Abrir um envelope")) { Navegacao.cobrir { FluxoDeAbrirEnvelope() } }
        }
        SecaoDeAjustes(t("Preferências")) {
            val ligadas = (Redes.todas.size - estado.redesDesligadas.size).coerceAtLeast(0)
            LinhaDeAjuste(Icones.rede, t("Redes"), t("%lld ligadas", ligadas)) { Navegacao.abrir { TelaDeRedes() } }
            LinhaDeAjuste(Icones.sino, t("Alertas de preço"), alertas) { Navegacao.abrir { TelaDosAlertas() } }
            LinhaDeAjuste(Icones.receberCirculo, t("Aviso de recebimento"), recebimento) { Navegacao.abrir { TelaDoRecebimento() } }
        }
        SecaoDeAjustes(t("Sobre")) {
            LinhaDeAjuste(Icones.pergunta, t("Suporte")) { Navegacao.abrir { TelaDeSuporte() } }
            LinhaDeAjuste(Icones.info, t("Taxas, código auditável e versão")) { Navegacao.abrir { TelaSobre() } }
        }
    }
}

// MARK: Carteiras

/** A origem de uma carteira, embaixo do nome. */
private fun origemDaCarteira(carteira: Carteira): String = when (carteira.origem) {
    "created" -> t("%lld palavras", carteira.palavras ?: 12)
    "importedPhrase" -> t("Importada com a senha da carteira")
    "importedEnvelope" -> t("Importada de envelope")
    else -> t("Só observar")
}

@Composable
fun TelaDeCarteiras() {
    val estado = App.estado
    val escopo = rememberCoroutineScope()
    // A linha com o apagar a mostra, e a carteira no popup de apagar.
    var aberta by remember { mutableStateOf<String?>(null) }
    var apagando by remember { mutableStateOf<Carteira?>(null) }
    Subtela(t("Carteiras")) {
        GrupoDeAjustes(Modifier.padding(top = Espaco.md)) {
            for (carteira in estado.carteiras) {
                LinhaQueApaga(carteira.id, aberta, { aberta = it }, { apagando = carteira }) {
                Row(
                    Modifier.fillMaxWidth().height(Altura.linha).clickable { Navegacao.abrir { AjustesDaCarteira(carteira.id) } }.padding(horizontal = Espaco.md),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                ) {
                    GlifoDaCarteira(carteira, 32.dp, selecionada = true)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(carteira.nome, style = estilo(Tipo.linha), color = Paleta.tinta, maxLines = 1)
                        val emDia = carteira.temCopia || carteira.observacao
                        Text(
                            if (emDia) origemDaCarteira(carteira) else if (carteira.palavrasConfirmadas) t("Passphrase não conferida") else t("Palavras não confirmadas"),
                            style = estilo(Tipo.nota), color = if (emDia) Paleta.tintaSuave else Paleta.cautela,
                        )
                    }
                    Icone(Icones.avancar, Paleta.tintaApagada, tamanho = 13.dp)
                }
                }
            }
        }
        BotaoSecundario(t("Adicionar carteira"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.lg)) {
            Navegacao.cobrir { AdicionarCarteira(primeira = false) { Navegacao.fechar() } }
        }
    }
    apagando?.let { carteira ->
        PopupDeRemover(carteira) { confirmou ->
            apagando = null
            if (confirmou) escopo.launch { RemocaoDeCarteira.remover(carteira) }
        }
    }
}

/** "17/10": o dia, como a regiao escreve. */
private fun dia(data: Date): String {
    val padrao = android.text.format.DateFormat.getBestDateTimePattern(Formato.locale, "ddMM")
    return java.text.SimpleDateFormat(padrao, Formato.locale).format(data)
}

/** S2: uma carteira. */
@Composable
fun AjustesDaCarteira(id: String) {
    val escopo = rememberCoroutineScope()
    val contexto = LocalContext.current
    val carteira = App.estado.carteiras.firstOrNull { it.id == id }
    var nome by remember { mutableStateOf(carteira?.nome ?: "") }
    var removendo by remember { mutableStateOf(false) }
    if (carteira == null) {
        Subtela("") {}
        return
    }

    fun renomear() {
        val limpo = nome.filter { !it.isISOControl() && Character.getType(it) != Character.FORMAT.toInt() }.trim().take(40)
        if (limpo.isEmpty() || limpo == carteira.nome) return
        escopo.launch { runCatching { App.aplicar(Api.objeto("carteira.renomear", JSONObject().put("id", carteira.id).put("nome", limpo))) } }
    }

    fun revelar() { Navegacao.cobrir { FluxoDeRevelar(carteira, copia = !carteira.palavrasConfirmadas) { Navegacao.fechar() } } }

    // Ligar e na hora; desligar pede a passphrase e o PIN, e o cofre confere a passphrase.
    fun pedirPassphrase(ligar: Boolean) {
        escopo.launch {
            if (ligar) {
                runCatching { App.aplicar(Api.objeto("carteira.pedirPassphraseParaEnviar", JSONObject().put("id", carteira.id))) }
                return@launch
            }
            val digitada = PedidoDePassphrase.pedir(carteira.nome,
                t("Para deixar de pedir a passphrase nos envios de %@, digite a passphrase. Depois vem o PIN.", carteira.nome)) ?: return@launch
            try {
                Autorizacao.tentando(t("Deixar de pedir a passphrase em %@", carteira.nome), Autorizacao.Presenca.pin) { credencial ->
                    App.aplicar(Api.comSegredo("carteira.naoPedirPassphrase", JSONObject().put("id", carteira.id).put("credencial", credencial.json()),
                                               *credencial.partes(digitada.bytes.copyOf())))
                }
            } catch (falha: FalhaDoNucleo) {
                Avisos.mostrar(when (falha.codigo) {
                    "passphrase.errada" -> t("A passphrase não confere. Nada foi assinado. Escreva igual ao que você anotou: maiúscula, acento e espaço contam.")
                    else -> Autorizacao.mensagemDeRecusa(falha) ?: t("Não foi possível mudar agora.")
                })
            } finally {
                digitada.bytes.fill(0)
            }
        }
    }

    Subtela("") {
        Box(Modifier.padding(horizontal = Espaco.margem)) {
            BasicTextField(
                nome, { nome = it.take(40) }, singleLine = true, textStyle = estilo(Tipo.titulo).copy(color = Paleta.tinta),
                cursorBrush = SolidColor(Paleta.acento),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { renomear() }),
                modifier = Modifier.fillMaxWidth().onFocusChanged { if (!it.isFocused) renomear() },
            )
        }
        if (!carteira.observacao) {
            SecaoDeAjustes(t("Cópias")) {
                LinhaDeAjuste(
                    Icones.documento, t("Papel"),
                    if (carteira.palavrasConfirmadas) carteira.copiaConfirmadaEm?.let { t("confirmado em %@", dia(it)) } ?: t("importada") else t("não confirmado"),
                    corDoValor = if (carteira.palavrasConfirmadas) Paleta.tintaSuave else Paleta.cautela,
                ) { revelar() }
                if (carteira.temPassphrase) {
                    LinhaDeAjuste(
                        Icones.chave, t("Passphrase"),
                        carteira.passphraseConferidaEm?.let { t("conferida em %@", dia(it)) } ?: t("não conferida"),
                        corDoValor = if (carteira.passphraseConfirmada) Paleta.tintaSuave else Paleta.cautela,
                    ) { if (carteira.passphraseConfirmada) revelar() else Navegacao.cobrir { CopiaAgora(carteira) } }
                }
                if (carteira.palavras != null) {
                    LinhaDeAjuste(Icones.envelope, t("Envelope Escalibur"), carteira.envelopeLacradoEm?.let { t("lacrado em %@", dia(it)) } ?: t("nenhum")) {
                        Navegacao.cobrir { FluxoDeLacrar(carteira) }
                    }
                }
            }
            if (carteira.temPassphrase) {
                SecaoDeAjustes(t("Segurança")) {
                    LinhaComInterruptor(
                        Icones.escudo, t("Pedir a passphrase para enviar"), carteira.pedePassphrase,
                        detalhe = t("Envios, trocas e pontes desta carteira pedem a passphrase antes da biometria ou do PIN."),
                    ) { pedirPassphrase(it) }
                }
            }
            carteira.vistaEm?.let {
                NotaDeAjuste(t("Última vez que a senha da carteira foi exibida: %@.", Formato.relativo(it, naFrase = true)))
            }
            GrupoDeAjustes(Modifier.padding(top = Espaco.lg)) {
                LinhaDeAjuste(Icones.olho, t("Ver a senha da carteira")) { revelar() }
                if (carteira.palavras != null) {
                    LinhaDeAjuste(Icones.cadeado, t("Criptografar a senha da carteira")) { Navegacao.cobrir { FluxoDeLacrar(carteira) } }
                    LinhaDeAjuste(Icones.chave, t("Abrir ou criar com passphrase")) { Navegacao.abrir { FluxoDaCarteiraComPassphrase(carteira) } }
                }
            }
        }
        if (!carteira.temCopia && !carteira.observacao) {
            SecaoDeAjustes(t("Endereços")) {
                LinhaDeAjuste(
                    Icones.alerta,
                    if (carteira.palavrasConfirmadas) t("Confira a passphrase para ver os endereços") else t("Grave as palavras para ver os endereços"),
                    corDoTitulo = Paleta.cautela,
                ) { Navegacao.cobrir { CopiaAgora(carteira) } }
            }
        } else {
            SecaoDeAjustes(t("Endereços")) {
                for ((rede, endereco) in carteira.contas) {
                    val info = Redes.rede(rede) ?: continue
                    if (info.familia == "tron" && carteira.tronOutraChave) {
                        LinhaDeAjuste(Icones.falha, t("Tron: controlada por outra chave"), corDoTitulo = Paleta.baixa, seta = false)
                        continue
                    }
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = Altura.linha).clickable {
                            Transferencia.copiar(contexto, endereco)
                            Avisos.mostrar(t("Endereço copiado."))
                        }.padding(horizontal = Espaco.md),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espaco.sm),
                    ) {
                        SeloDaRede(info.id, info.coingecko, 24.dp, Paleta.corpo)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(info.nome, style = estilo(Tipo.nota), color = Paleta.tinta)
                            Text(Formato.endereco(endereco, 8, 6), style = estilo(Tipo.monoPequeno), color = Paleta.tintaSuave)
                        }
                        Icone(Icones.copiar, Paleta.tintaApagada, tamanho = 13.dp)
                    }
                }
            }
        }
        BotaoDestrutivo(t("Remover deste celular"), Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.xl)) { removendo = true }
    }

    if (removendo) {
        PopupDeRemover(carteira) { confirmou ->
            removendo = false
            if (confirmou) escopo.launch { if (RemocaoDeCarteira.remover(carteira)) Navegacao.fechar() }
        }
    }
}

// MARK: Redes

@Composable
fun TelaDeRedes() {
    val escopo = rememberCoroutineScope()
    val desligadas = App.estado.redesDesligadas
    Subtela(t("Redes")) {
        Text(t("Para ler saldos, cotações e enviar, o app fala direto com nós públicos de cada rede, de empresas diferentes. Não existe servidor da Escalibur no meio."),
             style = estilo(Tipo.corpo), color = Paleta.tintaSuave, modifier = Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md))
        GrupoDeAjustes(Modifier.padding(top = Espaco.md)) {
            for (rede in Redes.todas) {
                LinhaComInterruptor(null, rede.nome, rede.id !in desligadas, inicio = { SeloDaRede(rede.id, rede.coingecko, 24.dp, Paleta.corpo) }) { ligada ->
                    escopo.launch { runCatching { App.aplicar(Api.objeto("ajustes.rede", JSONObject().put("rede", rede.id).put("ligada", ligada))) } }
                }
            }
        }
    }
}

// MARK: Sobre

@Composable
fun TelaSobre() {
    val contexto = LocalContext.current
    var documento by remember { mutableStateOf<DocumentoLegal?>(null) }
    Subtela(t("Sobre")) {
        Column(Modifier.padding(horizontal = Espaco.margem).padding(top = Espaco.md), verticalArrangement = Arrangement.spacedBy(Espaco.lg)) {
            Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Text(t("Taxas"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
                Text(t("A Escalibur não cobra taxa sobre envios, recebimentos, trocas ou ordens. Você paga só a taxa da rede e, nas trocas, a do provedor, que já vem dentro do valor que você recebe."),
                     style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
            }
            Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Text(t("Código auditável"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
                Text(t("Todo o código que guarda chaves, assina e fala com as redes é publicado para quem quiser auditar, linha por linha. As bibliotecas de criptografia são compiladas a partir do código-fonte, e cada versão delas é conferida por uma impressão digital: se alguém trocar uma, a compilação para."),
                     style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
                Text(t("Versão %@ (%@)", BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toString()), style = estilo(Tipo.nota), color = Paleta.tintaApagada)
                // A auditoria abre no navegador do celular, em outro app: o app nao abre conexao nenhuma.
                BotaoSecundario(t("Auditar o código"), Modifier.padding(top = Espaco.xs), icone = Icones.documento) {
                    runCatching { contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://escalibur-wallet.github.io/auditoria/"))) }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(Espaco.xs)) {
                Text(t("Preços"), style = estilo(Tipo.cabecalho), color = Paleta.tinta)
                Text(t("Preços e dados de mercado: CoinGecko, com CoinPaprika e OKX de reserva. Os saldos e as transações vêm direto das redes."),
                     style = estilo(Tipo.corpo), color = Paleta.tintaSuave)
            }
        }
        GrupoDeAjustes(Modifier.padding(top = Espaco.lg)) {
            LinhaDeAjuste(Icones.documento, t("Termos de uso")) { documento = DocumentoLegal.termos }
            LinhaDeAjuste(Icones.escudo, t("Política de privacidade")) { documento = DocumentoLegal.privacidade }
        }
    }
    documento?.let { FolhaLegal(it) { documento = null } }
}
