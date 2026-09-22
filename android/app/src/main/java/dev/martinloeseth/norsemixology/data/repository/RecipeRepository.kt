package dev.martinloeseth.norsemixology.data.repository

import dev.martinloeseth.norsemixology.data.local.RecipeDao
import dev.martinloeseth.norsemixology.domain.RecipeCatalog

class RecipeRepository(private val dao: RecipeDao) {
    /** Reads the seeded recipe catalog from Room into its in-memory form, ready for matching. */
    suspend fun load(): RecipeCatalog = RecipeCatalog.from(dao.recipes(), dao.recipeIngredients())
}
