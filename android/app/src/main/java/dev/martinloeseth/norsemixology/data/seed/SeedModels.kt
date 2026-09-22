package dev.martinloeseth.norsemixology.data.seed

import dev.martinloeseth.norsemixology.data.local.Difficulty
import dev.martinloeseth.norsemixology.data.local.FlavorProfile
import dev.martinloeseth.norsemixology.data.local.GlassType
import dev.martinloeseth.norsemixology.data.local.IngredientCategory
import dev.martinloeseth.norsemixology.data.local.IngredientFamily
import dev.martinloeseth.norsemixology.data.local.IngredientStyle
import dev.martinloeseth.norsemixology.data.local.Method
import dev.martinloeseth.norsemixology.data.local.Recipe
import dev.martinloeseth.norsemixology.data.local.RecipeIngredient
import kotlinx.serialization.Serializable
import java.util.UUID

// Wire shapes of the shared /seed-data JSON (identical on iOS and Android). Kept separate from the
// Room entities because the JSON nests the hierarchy and spells enums differently.

@Serializable
data class FlavorProfileDto(
    val sweetness: Double, val bitterness: Double, val smokiness: Double, val citrus: Double,
    val floral: Double, val spice: Double, val herbal: Double, val fruity: Double, val oaky: Double,
    val abv: Double,
) {
    fun toEntity() = FlavorProfile(sweetness, bitterness, smokiness, citrus, floral, spice, herbal, fruity, oaky, abv)
}

@Serializable
data class StyleDto(
    val id: String, val name: String, val familyId: String, val categoryId: String,
    val exampleBrands: List<String>, val flavorProfile: FlavorProfileDto, val abvMin: Double, val abvMax: Double,
)

@Serializable
data class FamilyDto(val id: String, val name: String, val categoryId: String, val styles: List<StyleDto>)

@Serializable
data class CategoryDto(val id: String, val name: String, val families: List<FamilyDto>)

@Serializable
data class RecipeIngredientDto(
    val ingredientStyleId: String, val amount: String, val preparation: String? = null,
    val isOptional: Boolean, val substituteNotes: String? = null,
)

@Serializable
data class RecipeDto(
    val id: String, val name: String, val description: String, val glassType: String, val method: String,
    val ingredients: List<RecipeIngredientDto>, val steps: List<String>, val flavorProfile: FlavorProfileDto,
    val tags: List<String>, val difficulty: String, val imageURL: String? = null,
)

/** The taxonomy flattened to the three tables, in authored order. */
data class TaxonomyRows(
    val categories: List<IngredientCategory>,
    val families: List<IngredientFamily>,
    val styles: List<IngredientStyle>,
)

data class RecipeRows(val recipes: List<Recipe>, val ingredients: List<RecipeIngredient>)

fun List<CategoryDto>.toRows(): TaxonomyRows {
    val categories = mutableListOf<IngredientCategory>()
    val families = mutableListOf<IngredientFamily>()
    val styles = mutableListOf<IngredientStyle>()
    forEachIndexed { categoryIndex, category ->
        categories += IngredientCategory(UUID.fromString(category.id), category.name, categoryIndex)
        category.families.forEachIndexed { familyIndex, family ->
            families += IngredientFamily(UUID.fromString(family.id), UUID.fromString(family.categoryId), family.name, familyIndex)
            family.styles.forEachIndexed { styleIndex, style ->
                styles += IngredientStyle(
                    id = UUID.fromString(style.id),
                    name = style.name,
                    familyId = UUID.fromString(style.familyId),
                    categoryId = UUID.fromString(style.categoryId),
                    flavorProfile = style.flavorProfile.toEntity(),
                    abvMin = style.abvMin,
                    abvMax = style.abvMax,
                    exampleBrands = style.exampleBrands,
                    sortOrder = styleIndex,
                )
            }
        }
    }
    return TaxonomyRows(categories, families, styles)
}

/** Throws if an enum spelling or UUID is invalid — callers skip the entry (see `CatalogParser`). */
fun RecipeDto.toEntity(sortOrder: Int): Recipe = Recipe(
    id = UUID.fromString(id),
    name = name,
    description = description,
    glassType = GlassType.fromJson(glassType),
    method = Method.fromJson(method),
    steps = steps,
    flavorProfile = flavorProfile.toEntity(),
    tags = tags,
    difficulty = Difficulty.fromJson(difficulty),
    imageURL = imageURL,
    sortOrder = sortOrder,
)

fun RecipeDto.toIngredientEntities(): List<RecipeIngredient> = ingredients.mapIndexed { position, ingredient ->
    RecipeIngredient(
        recipeId = UUID.fromString(id),
        ingredientStyleId = UUID.fromString(ingredient.ingredientStyleId),
        amount = ingredient.amount,
        preparation = ingredient.preparation,
        isOptional = ingredient.isOptional,
        substituteNotes = ingredient.substituteNotes,
        position = position,
    )
}
