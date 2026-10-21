package app.escalibur.wallet.ui.comp

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.escalibur.wallet.ui.tema.Altura
import app.escalibur.wallet.ui.tema.Espaco
import app.escalibur.wallet.ui.tema.Paleta
import app.escalibur.wallet.ui.tema.Tipo
import app.escalibur.wallet.ui.tema.estilo

/**
 * Os botoes do app, os mesmos do iOS (Design/Buttons.swift). Nenhum escurece por transparencia: o
 * estado desligado e opaco e declarado, e continua dizendo o que falta.
 */
@Composable
fun BotaoPrimario(
    titulo: String, modifier: Modifier = Modifier, ligado: Boolean = true, carregando: Boolean = false,
    claro: Boolean = false, acao: () -> Unit,
) {
    val interacao = remember { MutableInteractionSource() }
    val apertado by interacao.collectIsPressedAsState()
    val escala by animateFloatAsState(if (apertado && ligado) 0.985f else 1f, tween(100), label = "aperto")
    val fundo = when {
        !ligado -> Paleta.trilho
        claro -> if (apertado) Paleta.vivaApertada else Paleta.viva
        else -> if (apertado) Paleta.acentoApertado else Paleta.acento
    }
    val texto = when {
        !ligado -> Paleta.tintaApagada
        claro -> Paleta.sobreViva
        else -> Paleta.sobreAcento
    }
    Box(
        modifier
            .fillMaxWidth()
            .height(Altura.primaria)
            .scale(escala)
            .clip(CircleShape)
            .background(fundo)
            .clickable(interacao, indication = null, enabled = ligado && !carregando, role = Role.Button, onClick = acao),
        contentAlignment = Alignment.Center,
    ) {
        if (carregando) {
            Girando(texto, 22.dp)
        } else {
            Text(titulo, style = estilo(Tipo.acao), color = texto, textAlign = TextAlign.Center, maxLines = 1)
        }
    }
}

@Composable
fun BotaoSecundario(
    titulo: String, modifier: Modifier = Modifier, icone: ImageVector? = null, altura: Dp = Altura.secundaria,
    ligado: Boolean = true, acao: () -> Unit,
) {
    val interacao = remember { MutableInteractionSource() }
    val apertado by interacao.collectIsPressedAsState()
    Row(
        modifier
            .fillMaxWidth()
            .height(altura)
            .clip(CircleShape)
            .background(if (apertado) Paleta.trilho else Paleta.corpo)
            .border(BorderStroke(1.dp, Paleta.borda), CircleShape)
            .clickable(interacao, indication = null, enabled = ligado, role = Role.Button, onClick = acao),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icone != null) {
            Icone(icone, if (ligado) Paleta.tinta else Paleta.tintaApagada, tamanho = 17.dp)
            Spacer(Modifier.width(Espaco.xs))
        }
        Text(titulo, style = estilo(Tipo.acao), color = if (ligado) Paleta.tinta else Paleta.tintaApagada, maxLines = 1)
    }
}

@Composable
fun BotaoTerciario(titulo: String, modifier: Modifier = Modifier, cor: Color = Paleta.tintaSuave, acao: () -> Unit) {
    val interacao = remember { MutableInteractionSource() }
    val apertado by interacao.collectIsPressedAsState()
    Box(
        modifier
            .heightIn(min = Altura.toque)
            .clickable(interacao, indication = null, role = Role.Button, onClick = acao)
            .padding(horizontal = Espaco.xs),
        contentAlignment = Alignment.Center,
    ) {
        Text(titulo, style = estilo(Tipo.corpo), color = if (apertado) Paleta.tinta else cor, textAlign = TextAlign.Center)
    }
}

@Composable
fun BotaoDestrutivo(titulo: String, modifier: Modifier = Modifier, acao: () -> Unit) {
    val interacao = remember { MutableInteractionSource() }
    val apertado by interacao.collectIsPressedAsState()
    Box(
        modifier
            .fillMaxWidth()
            .height(Altura.secundaria)
            .clip(CircleShape)
            .background(if (apertado) Paleta.baixaApertada else Paleta.baixaFundo)
            .clickable(interacao, indication = null, role = Role.Button, onClick = acao),
        contentAlignment = Alignment.Center,
    ) {
        Text(titulo, style = estilo(Tipo.acao), color = Paleta.baixa)
    }
}

/** Rodape fixo de acao: margens de 20, area segura mais 8, fundo solido. */
@Composable
fun Rodape(modifier: Modifier = Modifier, conteudo: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .background(Paleta.vazio)
            .then(if (LocalEspacoDaBarra.current > 0.dp) Modifier.padding(bottom = LocalEspacoDaBarra.current - Espaco.md) else Modifier.navigationBarsPadding())
            .padding(start = Espaco.margem, end = Espaco.margem, top = Espaco.sm, bottom = Espaco.xs),
        verticalArrangement = Arrangement.spacedBy(Espaco.sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        content = conteudo,
    )
}

/** Circulo de acao rapida (Enviar, Receber, Trocar). */
@Composable
fun AcaoRapida(titulo: String, icone: ImageVector, modifier: Modifier = Modifier, acao: () -> Unit) {
    val interacao = remember { MutableInteractionSource() }
    val apertado by interacao.collectIsPressedAsState()
    val escala by animateFloatAsState(if (apertado) 0.96f else 1f, tween(100), label = "aperto")
    Column(
        modifier.scale(escala).clickable(interacao, indication = null, role = Role.Button, onClick = acao),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Espaco.xs),
    ) {
        Box(Modifier.size(Altura.acaoRapida).clip(CircleShape).background(Paleta.trilho), contentAlignment = Alignment.Center) {
            Icone(icone, Paleta.tinta, tamanho = 22.dp)
        }
        Text(titulo, style = estilo(Tipo.rotulo), color = Paleta.tintaSuave, maxLines = 1)
    }
}

/** A acao de receber quando falta saldo: o rosa da acao, chapado, texto branco (o AccentButton do iOS). */
@Composable
fun BotaoDeDestaque(titulo: String, modifier: Modifier = Modifier, icone: ImageVector? = null, acao: () -> Unit) {
    val interacao = remember { MutableInteractionSource() }
    val apertado by interacao.collectIsPressedAsState()
    Row(
        modifier
            .fillMaxWidth()
            .height(Altura.primaria)
            .clip(CircleShape)
            .background(if (apertado) Paleta.acentoApertado else Paleta.acento)
            .clickable(interacao, indication = null, role = Role.Button, onClick = acao)
            .padding(horizontal = Espaco.lg),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icone != null) {
            Icone(icone, Color.White, tamanho = 17.dp)
            Spacer(Modifier.width(Espaco.xs))
        }
        Text(titulo, style = estilo(Tipo.acao), color = Color.White)
    }
}

/**
 * O botao redondo de voltar ou fechar no canto: um circulo de vidro, como os botoes da barra do
 * iOS 26. Apertado, o vidro cresce um pouco.
 */
@Composable
fun BotaoDeCanto(icone: ImageVector, descricao: String, modifier: Modifier = Modifier, ligado: Boolean = true, acao: () -> Unit) {
    val toque = remember { MutableInteractionSource() }
    val apertado by toque.collectIsPressedAsState()
    val escala by animateFloatAsState(if (apertado) 1.12f else 1f, spring(dampingRatio = 0.6f, stiffness = 600f), label = "escala")
    Box(
        modifier
            .size(Altura.toque)
            .graphicsLayer { scaleX = escala; scaleY = escala }
            .vidro(CircleShape, Vidros.barra)
            .clip(CircleShape)
            .clickable(toque, indication = null, enabled = ligado, role = Role.Button, onClickLabel = descricao, onClick = acao),
        contentAlignment = Alignment.Center,
    ) {
        Icone(icone, if (ligado) Paleta.tinta else Paleta.tintaApagada, tamanho = 20.dp, descricao = descricao)
    }
}

/** Varios botoes num vidro so, como o grupo da direita na barra do iOS 26 (o sino e o favorito). */
@Composable
fun GrupoDeVidro(modifier: Modifier = Modifier, conteudo: @Composable RowScope.() -> Unit) {
    Row(
        modifier.height(Altura.toque).vidro(CircleShape, Vidros.barra).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = conteudo,
    )
}

/** Um botao de dentro do `GrupoDeVidro`. */
@Composable
fun BotaoDoGrupo(icone: ImageVector, descricao: String, cor: Color = Paleta.tinta, acao: () -> Unit) {
    Box(
        Modifier.size(width = 42.dp, height = Altura.toque).clip(CircleShape)
            .clickable(role = Role.Button, onClickLabel = descricao, onClick = acao),
        contentAlignment = Alignment.Center,
    ) { Icone(icone, cor, tamanho = 21.dp, descricao = descricao) }
}

/** Um botao de texto do `GrupoDeVidro` (o "OK" da barra das folhas do iOS). */
@Composable
fun BotaoDeTextoDoGrupo(titulo: String, acao: () -> Unit) {
    Box(
        Modifier.height(Altura.toque).clip(CircleShape).clickable(role = Role.Button, onClick = acao).padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) { Text(titulo, style = estilo(Tipo.acao), color = Paleta.tinta, maxLines = 1) }
}

/** O toque leve de selecao, como o `sensoryFeedback(.selection)` do iOS. */
@Composable
fun toqueDeSelecao(): () -> Unit {
    val haptico = LocalHapticFeedback.current
    return { haptico.performHapticFeedback(HapticFeedbackType.SegmentTick) }
}

/**
 * O interruptor do iOS 26: a trilha larga (63 por 28) e o botao em capsula branca (37 por 24) que
 * desliza com mola. Apertado, o botao cresce, como o vidro do iOS. Desligado, a trilha e o cinza dos
 * controles; ligado, a cor dada (o verde do sistema, por padrao).
 */
@Composable
fun Interruptor(ligado: Boolean, aoMudar: (Boolean) -> Unit, modifier: Modifier = Modifier, cor: Color = Paleta.sucesso, habilitado: Boolean = true) {
    val haptico = LocalHapticFeedback.current
    val toque = remember { MutableInteractionSource() }
    val apertado by toque.collectIsPressedAsState()
    val posicao by animateFloatAsState(if (ligado) 1f else 0f, spring(dampingRatio = 0.78f, stiffness = 520f), label = "interruptor")
    val crescido by animateFloatAsState(if (apertado && habilitado) 1f else 0f, spring(dampingRatio = 0.7f, stiffness = 600f), label = "aperto")
    val trilha by androidx.compose.animation.animateColorAsState(
        when { !habilitado -> Paleta.controle; ligado -> cor; else -> Paleta.controle }, tween(180), label = "trilha")
    Box(
        modifier.size(width = 63.dp, height = 28.dp).clip(CircleShape).background(trilha)
            .clickable(toque, indication = null, enabled = habilitado, role = Role.Switch) {
                haptico.performHapticFeedback(HapticFeedbackType.SegmentTick)
                aoMudar(!ligado)
            },
    ) {
        Box(
            Modifier.padding(2.dp)
                .graphicsLayer {
                    translationX = (63.dp - 37.dp - 4.dp).toPx() * posicao
                    val e = 1f + 0.18f * crescido
                    scaleX = e
                    scaleY = e
                }
                .size(width = 37.dp, height = 24.dp).clip(CircleShape)
                .background(if (habilitado) Color.White.copy(alpha = 1f - 0.12f * crescido) else Paleta.tintaApagada),
        )
    }
}
