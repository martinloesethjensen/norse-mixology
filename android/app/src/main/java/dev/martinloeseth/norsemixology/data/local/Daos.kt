package dev.martinloeseth.norsemixology.data.local

import androidx.room3.Dao
import androidx.room3.Delete
import androidx.room3.Insert
import androidx.room3.OnConflictStrategy
import androidx.room3.Query
import androidx.room3.Transaction
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/** Read access to the taxonomy, plus an atomic replace used when the bundled catalog changes. */
@Dao
abstract class TaxonomyDao {
    @Query("SELECT * FROM IngredientCategory ORDER BY sortOrder")
    abstract suspend fun categories(): List<IngredientCategory>

    @Query("SELECT * FROM IngredientFamily ORDER BY sortOrder")
    abstract suspend fun families(): List<IngredientFamily>

    @Query("SELECT * FROM IngredientStyle ORDER BY sortOrder")
    abstract suspend fun styles(): List<IngredientStyle>

    @Query("SELECT COUNT(*) FROM IngredientStyle")
    abstract suspend fun styleCount(): Int

    @Insert
    protected abstract suspend fun insertCategories(items: List<IngredientCategory>)

    @Insert
    protected abstract suspend fun insertFamilies(items: List<IngredientFamily>)

    @Insert
    protected abstract suspend fun insertStyles(items: List<IngredientStyle>)

    // Deleting categories cascades to families and styles.
    @Query("DELETE FROM IngredientCategory")
    protected abstract suspend fun deleteAll()

    @Transaction
    open suspend fun replaceAll(
        categories: List<IngredientCategory>,
        families: List<IngredientFamily>,
        styles: List<IngredientStyle>,
    ) {
        deleteAll()
        insertCategories(categories)
        insertFamilies(families)
        insertStyles(styles)
    }
}

@Dao
interface CabinetDao {
    /** Ignored (returns -1) if the style is already in the cabinet — enforced by a unique index. */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(item: CabinetItem): Long

    @Delete
    suspend fun delete(item: CabinetItem)

    @Query("SELECT * FROM CabinetItem ORDER BY category COLLATE NOCASE, displayName COLLATE NOCASE")
    fun observeAll(): Flow<List<CabinetItem>>

    @Query("SELECT COUNT(*) FROM CabinetItem WHERE ingredientStyleId = :styleId")
    suspend fun countForStyle(styleId: UUID): Int
}

@Dao
abstract class RecipeDao {
    @Query("SELECT COUNT(*) FROM Recipe")
    abstract suspend fun recipeCount(): Int

    @Query("SELECT COUNT(*) FROM RecipeIngredient")
    abstract suspend fun ingredientCount(): Int

    @Insert
    protected abstract suspend fun insertRecipes(items: List<Recipe>)

    @Insert
    protected abstract suspend fun insertIngredients(items: List<RecipeIngredient>)

    // Deleting recipes cascades to their ingredients.
    @Query("DELETE FROM Recipe")
    protected abstract suspend fun deleteAll()

    @Transaction
    open suspend fun replaceAll(recipes: List<Recipe>, ingredients: List<RecipeIngredient>) {
        deleteAll()
        insertRecipes(recipes)
        insertIngredients(ingredients)
    }
}
