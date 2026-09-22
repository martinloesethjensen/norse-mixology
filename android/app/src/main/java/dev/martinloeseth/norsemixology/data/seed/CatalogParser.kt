package dev.martinloeseth.norsemixology.data.seed

import dev.martinloeseth.norsemixology.data.local.Recipe
import dev.martinloeseth.norsemixology.data.local.RecipeIngredient
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.decodeFromJsonElement

/** Parses the bundled catalog JSON. Pure — no Android or Room — so it's trivially unit-testable. */
object CatalogParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun parseTaxonomy(text: String): TaxonomyRows =
        json.decodeFromString<List<CategoryDto>>(text).toRows()

    /**
     * Skips an individual malformed recipe (bad enum spelling, missing field, invalid UUID) rather
     * than failing the whole catalog, and reports how many were skipped. A file that isn't a JSON
     * array at all still throws. Same rule as the iOS app.
     */
    fun parseRecipes(text: String): ParsedRecipes {
        val elements = json.decodeFromString<JsonArray>(text)
        val recipes = mutableListOf<Recipe>()
        val ingredients = mutableListOf<RecipeIngredient>()
        var skipped = 0
        for (element in elements) {
            try {
                val dto = json.decodeFromJsonElement<RecipeDto>(element)
                val entity = dto.toEntity(sortOrder = recipes.size)
                val rows = dto.toIngredientEntities()
                recipes += entity
                ingredients += rows
            } catch (e: Exception) {
                skipped++
            }
        }
        return ParsedRecipes(RecipeRows(recipes, ingredients), skipped)
    }
}

data class ParsedRecipes(val rows: RecipeRows, val skippedCount: Int)
