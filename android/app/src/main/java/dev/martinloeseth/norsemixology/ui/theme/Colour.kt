package dev.martinloeseth.norsemixology.ui.theme

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * "Modern Neon Bar" tokens from the vault's Design System note — the same values, in the same
 * light/dark pairs, as the iOS `DesignTokens`. Screens read them via [NorseTheme.colors]; nothing
 * else in the app defines a colour.
 */
data class NorseColors(
    val background: Color,
    val surface: Color,
    val surfaceRaised: Color,
    val border: Color,
    val accent: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val matchExact: Color,
    val matchSubstituted: Color,
    val matchUnavailable: Color,
    /** Text/icons on the filled lime/gold badges and buttons — dark in both modes for contrast. */
    val onAccent: Color,
)

val DarkNorseColors = NorseColors(
    background = Color(0xFF0D0F14),
    surface = Color(0xFF161920),
    surfaceRaised = Color(0xFF1F232D),
    border = Color(0xFF262B36),
    accent = Color(0xFF8FE388),
    textPrimary = Color(0xFFEEF1F5),
    textSecondary = Color(0xFF9AA1AF),
    matchExact = Color(0xFF8FE388),
    matchSubstituted = Color(0xFFF0B93D),
    matchUnavailable = Color(0xFF4A5160),
    onAccent = Color(0xFF0D0F14),
)

val LightNorseColors = NorseColors(
    background = Color(0xFFF7F8FA),
    surface = Color(0xFFFFFFFF),
    surfaceRaised = Color(0xFFEFF1F4),
    border = Color(0xFFDDE1E7),
    accent = Color(0xFF8FE388),
    textPrimary = Color(0xFF14171C),
    textSecondary = Color(0xFF5B6472),
    matchExact = Color(0xFF8FE388),
    matchSubstituted = Color(0xFFF0B93D),
    matchUnavailable = Color(0xFFA6AEBA),
    onAccent = Color(0xFF0D0F14),
)

internal val LocalNorseColors = staticCompositionLocalOf { DarkNorseColors }
