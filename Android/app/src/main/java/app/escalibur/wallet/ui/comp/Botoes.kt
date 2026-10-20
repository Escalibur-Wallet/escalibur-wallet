package app.escalibur.wallet.ui.comp

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
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
            CircularProgressIndicator(color = texto, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
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
            .navigationBarsPadding()
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

/** O botao redondo de voltar ou fechar no canto. */
@Composable
fun BotaoDeCanto(icone: ImageVector, descricao: String, modifier: Modifier = Modifier, ligado: Boolean = true, acao: () -> Unit) {
    Box(
        modifier
            .size(Altura.toque)
            .clip(RoundedCornerShape(22.dp))
            .clickable(enabled = ligado, role = Role.Button, onClickLabel = descricao, onClick = acao),
        contentAlignment = Alignment.Center,
    ) {
        Icone(icone, Paleta.tintaSuave, tamanho = 20.dp, descricao = descricao)
    }
}

/** O toque leve de selecao, como o `sensoryFeedback(.selection)` do iOS. */
@Composable
fun toqueDeSelecao(): () -> Unit {
    val haptico = LocalHapticFeedback.current
    return { haptico.performHapticFeedback(HapticFeedbackType.SegmentTick) }
}
