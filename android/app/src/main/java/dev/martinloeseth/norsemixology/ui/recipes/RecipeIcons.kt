package dev.martinloeseth.norsemixology.ui.recipes

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.LocalBar
import androidx.compose.material.icons.filled.LocalDrink
import androidx.compose.material.icons.filled.WineBar
import androidx.compose.ui.graphics.vector.ImageVector
import dev.martinloeseth.norsemixology.data.local.GlassType

/**
 * Material icon per glass shape — the same grouping as iOS's SF Symbol mapping
 * (coupe/martini/flute/wine glass -> stemmed glass; rocks -> short glass; highball/collins/
 * hurricane -> tall glass; mug -> mug), translated to the nearest Material icon.
 */
val GlassType.icon: ImageVector
    get() = when (this) {
        GlassType.Coupe, GlassType.Martini, GlassType.Flute, GlassType.WineGlass -> Icons.Filled.WineBar
        GlassType.Rocks -> Icons.Filled.LocalBar
        GlassType.Highball, GlassType.Collins, GlassType.Hurricane -> Icons.Filled.LocalDrink
        GlassType.Mug -> Icons.Filled.Coffee
    }
