package dev.martinloeseth.norsemixology.data.local

import androidx.room3.Embedded
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index
import androidx.room3.PrimaryKey
import java.util.Date
import java.util.UUID

/**
 * Normalised 0.0–1.0 flavour dimensions (plus informational `abv`), embedded — never its own
 * table — into every entity that holds one. Field names match the iOS model and Data Model.md.
 */
data class FlavorProfile(
    val sweetness: Double,
    val bitterness: Double,
    val smokiness: Double,
    val citrus: Double,
    val floral: Double,
    val spice: Double,
    val herbal: Double,
    val fruity: Double,
    val oaky: Double,
    val abv: Double,
)

// ---- Taxonomy (read-only reference data, re-seeded from the bundled JSON) -----------------
// `sortOrder` keeps the catalog's authored order for the Browse screens.

@Entity
data class IngredientCategory(
    @PrimaryKey val id: UUID,
    val name: String,
    val sortOrder: Int,
)

@Entity(
    foreignKeys = [ForeignKey(IngredientCategory::class, ["id"], ["categoryId"], onDelete = ForeignKey.CASCADE)],
    indices = [Index("categoryId")],
)
data class IngredientFamily(
    @PrimaryKey val id: UUID,
    val categoryId: UUID,
    val name: String,
    val sortOrder: Int,
)

@Entity(
    foreignKeys = [ForeignKey(IngredientFamily::class, ["id"], ["familyId"], onDelete = ForeignKey.CASCADE)],
    indices = [Index("familyId")],
)
data class IngredientStyle(
    @PrimaryKey val id: UUID,
    val name: String,
    val familyId: UUID,
    val categoryId: UUID,
    @Embedded(prefix = "flavor_") val flavorProfile: FlavorProfile,
    val abvMin: Double,
    val abvMax: Double,
    val exampleBrands: List<String>,
    val sortOrder: Int,
)

// ---- User data -----------------------------------------------------------------------------

/**
 * An ingredient the user owns — a *snapshot* of the taxonomy style they picked (names, brand,
 * flavour profile), deliberately not a foreign key, so re-seeding the catalog never touches it.
 * `ingredientStyleId` is unique: an ingredient can only be in the cabinet once.
 */
@Entity(indices = [Index(value = ["ingredientStyleId"], unique = true)])
data class CabinetItem(
    @PrimaryKey val id: UUID,
    val ingredientStyleId: UUID,
    val ingredientFamilyId: UUID,
    val categoryId: UUID,
    val displayName: String,
    val brand: String?,
    val style: String,
    val family: String,
    val category: String,
    @Embedded(prefix = "flavor_") val flavorProfile: FlavorProfile,
    val dateAdded: Date,
)

/** Stub until Phase 9 wires favourites; the table exists so the schema is stable from v1. */
@Entity
data class FavouriteRecipe(
    @PrimaryKey val id: UUID,
    val recipeId: UUID,
    val recipeName: String,
    val dateFavourited: Date,
)

// ---- Recipe catalog ------------------------------------------------------------------------

@Entity
data class Recipe(
    @PrimaryKey val id: UUID,
    val name: String,
    val description: String,
    val glassType: GlassType,
    val method: Method,
    val steps: List<String>,
    @Embedded(prefix = "flavor_") val flavorProfile: FlavorProfile,
    val tags: List<String>,
    val difficulty: Difficulty,
    val imageURL: String?,
    val sortOrder: Int,
)

/** Room can't embed a list of structs, so a recipe's ingredients are their own table. */
@Entity(
    foreignKeys = [ForeignKey(Recipe::class, ["id"], ["recipeId"], onDelete = ForeignKey.CASCADE)],
    indices = [Index("recipeId")],
)
data class RecipeIngredient(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val recipeId: UUID,
    val ingredientStyleId: UUID,
    val amount: String,
    val preparation: String?,
    val isOptional: Boolean,
    val substituteNotes: String?,
    val position: Int,
)
