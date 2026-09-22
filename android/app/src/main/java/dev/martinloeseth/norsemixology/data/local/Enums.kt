package dev.martinloeseth.norsemixology.data.local

/**
 * The catalog JSON spells these in lowerCamelCase (`wineGlass`, `throw`); [json] is that spelling.
 * Room stores the enum's own name via its built-in enum converter.
 */
enum class GlassType(val json: String) {
    Coupe("coupe"), Rocks("rocks"), Highball("highball"), Martini("martini"), Collins("collins"),
    Hurricane("hurricane"), Flute("flute"), Mug("mug"), WineGlass("wineGlass");

    companion object {
        fun fromJson(value: String): GlassType =
            entries.firstOrNull { it.json == value } ?: throw IllegalArgumentException("Unknown glassType '$value'")
    }
}

enum class Method(val json: String) {
    Shake("shake"), Stir("stir"), Build("build"), Blend("blend"), Throw("throw");

    companion object {
        fun fromJson(value: String): Method =
            entries.firstOrNull { it.json == value } ?: throw IllegalArgumentException("Unknown method '$value'")
    }
}

enum class Difficulty(val json: String) {
    Easy("easy"), Medium("medium"), Advanced("advanced");

    companion object {
        fun fromJson(value: String): Difficulty =
            entries.firstOrNull { it.json == value } ?: throw IllegalArgumentException("Unknown difficulty '$value'")
    }
}
