package dev.martinloeseth.norsemixology.data.seed

import dev.martinloeseth.norsemixology.data.local.NorseMixologyDatabase

/** Remembers which catalog version is already in the database. */
interface SeedFlagStore {
    suspend fun seededVersion(): Int
    suspend fun setSeededVersion(version: Int)
}

sealed interface SeedResult {
    /** The catalog was already current — nothing was touched. */
    data object AlreadySeeded : SeedResult
    data class Seeded(val styles: Int, val recipes: Int, val skippedRecipes: Int) : SeedResult
}

/**
 * Loads the bundled taxonomy + recipes into Room. Bump [CATALOG_VERSION] whenever `/seed-data`
 * changes and the next launch replaces the catalog tables — leaving the user's cabinet and
 * favourites untouched. If the app dies mid-seed the version flag isn't written, so the next launch
 * simply redoes it (each table replace is atomic and idempotent).
 */
class CatalogSeeder(
    private val database: NorseMixologyDatabase,
    private val flags: SeedFlagStore,
    private val taxonomyJson: () -> String,
    private val recipesJson: () -> String,
) {
    suspend fun seedIfNeeded(): SeedResult {
        if (flags.seededVersion() >= CATALOG_VERSION) return SeedResult.AlreadySeeded

        val taxonomy = CatalogParser.parseTaxonomy(taxonomyJson())
        val recipes = CatalogParser.parseRecipes(recipesJson())

        database.taxonomyDao().replaceAll(taxonomy.categories, taxonomy.families, taxonomy.styles)
        database.recipeDao().replaceAll(recipes.rows.recipes, recipes.rows.ingredients)
        flags.setSeededVersion(CATALOG_VERSION)

        return SeedResult.Seeded(taxonomy.styles.size, recipes.rows.recipes.size, recipes.skippedCount)
    }

    companion object {
        const val CATALOG_VERSION = 1
    }
}
