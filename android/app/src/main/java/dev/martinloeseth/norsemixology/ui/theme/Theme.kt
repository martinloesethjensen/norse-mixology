package dev.martinloeseth.norsemixology.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable

/** Access to the Design System tokens: `NorseTheme.colors.surfaceRaised`, `NorseTheme.type.heading`. */
object NorseTheme {
    val colors: NorseColors
        @Composable @ReadOnlyComposable get() = LocalNorseColors.current
    val type: NorseType
        @Composable @ReadOnlyComposable get() = LocalNorseType.current
}

/**
 * Follows the system light/dark setting (never forced). Dynamic colour is deliberately off: the
 * app's identity is the Modern Neon Bar palette on both platforms.
 */
@Composable
fun NorseMixologyTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colors = if (darkTheme) DarkNorseColors else LightNorseColors
    val scheme = if (darkTheme) {
        darkColorScheme(
            primary = colors.accent, onPrimary = colors.onAccent,
            secondaryContainer = colors.accent, onSecondaryContainer = colors.onAccent,
            background = colors.background, onBackground = colors.textPrimary,
            surface = colors.surface, onSurface = colors.textPrimary,
            surfaceVariant = colors.surfaceRaised, onSurfaceVariant = colors.textSecondary,
            surfaceContainer = colors.surface, surfaceContainerHigh = colors.surfaceRaised,
            surfaceContainerHighest = colors.surfaceRaised,
            outline = colors.border, outlineVariant = colors.border,
        )
    } else {
        lightColorScheme(
            primary = colors.accent, onPrimary = colors.onAccent,
            secondaryContainer = colors.accent, onSecondaryContainer = colors.onAccent,
            background = colors.background, onBackground = colors.textPrimary,
            surface = colors.surface, onSurface = colors.textPrimary,
            surfaceVariant = colors.surfaceRaised, onSurfaceVariant = colors.textSecondary,
            surfaceContainer = colors.surface, surfaceContainerHigh = colors.surfaceRaised,
            surfaceContainerHighest = colors.surfaceRaised,
            outline = colors.border, outlineVariant = colors.border,
        )
    }

    CompositionLocalProvider(LocalNorseColors provides colors, LocalNorseType provides DefaultNorseType) {
        MaterialTheme(colorScheme = scheme, typography = DefaultNorseType.toMaterialTypography(), content = content)
    }
}
