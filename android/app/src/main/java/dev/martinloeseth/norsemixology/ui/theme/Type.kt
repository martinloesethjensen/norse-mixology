package dev.martinloeseth.norsemixology.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * The Design System's four text roles (sizes in `sp`, so they scale with the user's font size):
 * display 26·800, heading 16·600, body 13·400, label 10·700 (callers add uppercase + tracking).
 */
data class NorseType(
    val display: TextStyle,
    val heading: TextStyle,
    val body: TextStyle,
    val label: TextStyle,
)

val DefaultNorseType = NorseType(
    display = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.ExtraBold, fontSize = 26.sp, lineHeight = 32.sp),
    heading = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, lineHeight = 22.sp),
    body = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Normal, fontSize = 13.sp, lineHeight = 18.sp),
    label = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Bold, fontSize = 10.sp, lineHeight = 14.sp, letterSpacing = 0.6.sp),
)

internal val LocalNorseType = staticCompositionLocalOf { DefaultNorseType }

/** Material components (app bars, buttons, sheets) pick their text up from the same four roles. */
internal fun NorseType.toMaterialTypography() = Typography(
    headlineMedium = display,
    titleLarge = display.copy(fontSize = 22.sp, lineHeight = 28.sp),
    titleMedium = heading,
    titleSmall = heading,
    bodyLarge = heading.copy(fontWeight = FontWeight.Normal),
    bodyMedium = body,
    bodySmall = body,
    labelLarge = heading,
    labelMedium = label,
    labelSmall = label,
)
