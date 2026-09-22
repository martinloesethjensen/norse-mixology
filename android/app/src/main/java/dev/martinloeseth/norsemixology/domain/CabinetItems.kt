package dev.martinloeseth.norsemixology.domain

import dev.martinloeseth.norsemixology.data.local.CabinetItem
import dev.martinloeseth.norsemixology.data.local.IngredientStyle
import java.util.Date
import java.util.UUID

object CabinetItems {
    /**
     * Snapshots a taxonomy style into a cabinet item. A non-blank [brand] is trimmed and prefixed to
     * the name ("Hendrick's Contemporary Gin"); otherwise the style name is used — same as iOS.
     */
    fun create(
        style: IngredientStyle,
        taxonomy: Taxonomy,
        brand: String?,
        id: UUID = UUID.randomUUID(),
        dateAdded: Date = Date(),
    ): CabinetItem {
        val cleanBrand = brand?.trim()?.takeIf { it.isNotEmpty() }
        return CabinetItem(
            id = id,
            ingredientStyleId = style.id,
            ingredientFamilyId = style.familyId,
            categoryId = style.categoryId,
            displayName = cleanBrand?.let { "$it ${style.name}" } ?: style.name,
            brand = cleanBrand,
            style = style.name,
            family = taxonomy.familyNamesById[style.familyId].orEmpty(),
            category = taxonomy.categoryNamesById[style.categoryId].orEmpty(),
            flavorProfile = style.flavorProfile,
            dateAdded = dateAdded,
        )
    }
}
