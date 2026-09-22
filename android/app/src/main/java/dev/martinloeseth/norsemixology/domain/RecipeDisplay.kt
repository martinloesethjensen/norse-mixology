package dev.martinloeseth.norsemixology.domain

import dev.martinloeseth.norsemixology.data.local.Difficulty
import dev.martinloeseth.norsemixology.data.local.GlassType
import dev.martinloeseth.norsemixology.data.local.Method

// Display names for the recipe catalog's enums — a Kotlin port of iOS's RecipePresentation.swift
// extensions. Kept separate from the Room enums (data/local/Enums.kt) since those exist for
// persistence, not presentation.

val GlassType.displayName: String
    get() = when (this) {
        GlassType.Coupe -> "Coupe"
        GlassType.Rocks -> "Rocks"
        GlassType.Highball -> "Highball"
        GlassType.Martini -> "Martini"
        GlassType.Collins -> "Collins"
        GlassType.Hurricane -> "Hurricane"
        GlassType.Flute -> "Flute"
        GlassType.Mug -> "Mug"
        GlassType.WineGlass -> "Wine glass"
    }

val Method.displayName: String
    get() = when (this) {
        Method.Shake -> "Shake"
        Method.Stir -> "Stir"
        Method.Build -> "Build"
        Method.Blend -> "Blend"
        Method.Throw -> "Throw"
    }

val Difficulty.displayName: String
    get() = when (this) {
        Difficulty.Easy -> "Easy"
        Difficulty.Medium -> "Medium"
        Difficulty.Advanced -> "Advanced"
    }
