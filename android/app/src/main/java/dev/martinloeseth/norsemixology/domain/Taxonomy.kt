package dev.martinloeseth.norsemixology.domain

import dev.martinloeseth.norsemixology.data.local.IngredientCategory
import dev.martinloeseth.norsemixology.data.local.IngredientFamily
import dev.martinloeseth.norsemixology.data.local.IngredientStyle
import dev.martinloeseth.norsemixology.data.seed.TaxonomyRows
import java.util.UUID

data class FamilyNode(val family: IngredientFamily, val styles: List<IngredientStyle>)

data class CategoryNode(val category: IngredientCategory, val families: List<FamilyNode>)

/**
 * The ingredient hierarchy (Category → Family → Style) in memory, in authored order, with the
 * lookups the UI needs. Built once from Room after seeding — ~100 styles, so it's cheap to hold.
 */
class Taxonomy(val categories: List<CategoryNode>) {
    val stylesById: Map<UUID, IngredientStyle> =
        categories.flatMap { c -> c.families.flatMap { f -> f.styles } }.associateBy { it.id }
    val familyNamesById: Map<UUID, String> =
        categories.flatMap { c -> c.families }.associate { it.family.id to it.family.name }
    val categoryNamesById: Map<UUID, String> =
        categories.associate { it.category.id to it.category.name }

    fun category(id: UUID): CategoryNode? = categories.firstOrNull { it.category.id == id }
    fun family(id: UUID): FamilyNode? = categories.firstNotNullOfOrNull { c -> c.families.firstOrNull { it.family.id == id } }

    val isEmpty: Boolean get() = categories.isEmpty()

    companion object {
        val Empty = Taxonomy(emptyList())

        fun from(categories: List<IngredientCategory>, families: List<IngredientFamily>, styles: List<IngredientStyle>): Taxonomy {
            val stylesByFamily = styles.groupBy { it.familyId }
            val familiesByCategory = families.groupBy { it.categoryId }
            return Taxonomy(
                categories.sortedBy { it.sortOrder }.map { category ->
                    CategoryNode(
                        category,
                        familiesByCategory[category.id].orEmpty().sortedBy { it.sortOrder }.map { family ->
                            FamilyNode(family, stylesByFamily[family.id].orEmpty().sortedBy { it.sortOrder })
                        },
                    )
                },
            )
        }

        fun from(rows: TaxonomyRows): Taxonomy = from(rows.categories, rows.families, rows.styles)
    }
}
