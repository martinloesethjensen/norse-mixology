package dev.martinloeseth.norsemixology.domain

import dev.martinloeseth.norsemixology.data.local.Recipe
import dev.martinloeseth.norsemixology.data.local.RecipeIngredient

data class RecipeWithIngredients(val recipe: Recipe, val ingredients: List<RecipeIngredient>)

/** The bundled recipe catalog in memory, built once from Room after seeding. */
class RecipeCatalog(val recipes: List<RecipeWithIngredients>) {
    val isEmpty: Boolean get() = recipes.isEmpty()

    companion object {
        val Empty = RecipeCatalog(emptyList())

        fun from(recipes: List<Recipe>, ingredients: List<RecipeIngredient>): RecipeCatalog {
            val byRecipe = ingredients.groupBy { it.recipeId }
            return RecipeCatalog(recipes.map { RecipeWithIngredients(it, byRecipe[it.id].orEmpty()) })
        }
    }
}
