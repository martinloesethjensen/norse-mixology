package dev.martinloeseth.norsemixology.data.repository

import dev.martinloeseth.norsemixology.data.local.FavouriteDao
import dev.martinloeseth.norsemixology.data.local.FavouriteRecipe
import dev.martinloeseth.norsemixology.data.local.Recipe
import kotlinx.coroutines.flow.Flow
import java.util.Date
import java.util.UUID

/** The user's saved recipes. Every mutation is a deliberate, user-visible action, saved immediately. */
class FavouritesRepository(private val dao: FavouriteDao) {
    /** No-op if the recipe is already saved, so there is never a duplicate record. */
    suspend fun save(recipe: Recipe, date: Date = Date()) {
        dao.insert(FavouriteRecipe(id = UUID.randomUUID(), recipeId = recipe.id, recipeName = recipe.name, dateFavourited = date))
    }

    suspend fun remove(recipeId: UUID) = dao.deleteByRecipeId(recipeId)

    suspend fun isFavourited(recipeId: UUID): Boolean = dao.countForRecipe(recipeId) > 0

    /** Most recently favourited first. */
    fun all(): Flow<List<FavouriteRecipe>> = dao.observeAll()

    /** Saves the recipe if it isn't a favourite, removes it if it is. Returns the new favourited state. */
    suspend fun toggle(recipe: Recipe, date: Date = Date()): Boolean =
        if (isFavourited(recipe.id)) {
            remove(recipe.id)
            false
        } else {
            save(recipe, date)
            true
        }
}
