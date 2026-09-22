package dev.martinloeseth.norsemixology.domain

import dev.martinloeseth.norsemixology.data.local.IngredientStyle

/** Free-text search across the taxonomy, used by the Add Ingredient screen. */
object IngredientSearch {
    /**
     * Case-insensitive substring match on style name, family name, or any example brand — the same
     * rule as iOS. Blank queries return nothing. Results keep the catalog's order.
     */
    fun search(query: String, taxonomy: Taxonomy): List<IngredientStyle> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList()

        return buildList {
            for (category in taxonomy.categories) {
                for (family in category.families) {
                    val familyMatches = family.family.name.lowercase().contains(q)
                    for (style in family.styles) {
                        if (familyMatches ||
                            style.name.lowercase().contains(q) ||
                            style.exampleBrands.any { it.lowercase().contains(q) }
                        ) {
                            add(style)
                        }
                    }
                }
            }
        }
    }
}
