package dev.martinloeseth.norsemixology.data.local

import androidx.room3.BuiltInColumnTypeConverters
import androidx.room3.ColumnTypeConverters
import androidx.room3.Database
import androidx.room3.RoomDatabase

/**
 * Version 1. The catalog tables are re-seeded from the bundled JSON (see `CatalogSeeder`);
 * `CabinetItem` and `FavouriteRecipe` are user data and must survive every catalog change, so any
 * future schema change needs a real migration — never `fallbackToDestructiveMigration`.
 */
@Database(
    entities = [
        IngredientCategory::class,
        IngredientFamily::class,
        IngredientStyle::class,
        CabinetItem::class,
        FavouriteRecipe::class,
        Recipe::class,
        RecipeIngredient::class,
    ],
    version = 1,
    exportSchema = false,
)
@ColumnTypeConverters(
    value = [Converters::class],
    builtInColumnTypeConverters = BuiltInColumnTypeConverters(
        enums = BuiltInColumnTypeConverters.State.ENABLED,
        uuid = BuiltInColumnTypeConverters.State.ENABLED,
    ),
)
abstract class NorseMixologyDatabase : RoomDatabase() {
    abstract fun taxonomyDao(): TaxonomyDao
    abstract fun cabinetDao(): CabinetDao
    abstract fun recipeDao(): RecipeDao
    abstract fun favouriteDao(): FavouriteDao
}
