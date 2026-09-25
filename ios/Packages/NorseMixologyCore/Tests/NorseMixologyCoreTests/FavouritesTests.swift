import XCTest
import SwiftData
@testable import NorseMixologyCore

final class FavouritesTests: XCTestCase {
    // MARK: - Fixtures

    /// Keeps the container alive alongside its context for the whole test.
    private struct Store {
        let container: ModelContainer
        let context: ModelContext
    }

    private func makeStore() throws -> Store {
        let schema = Schema([FavouriteRecipe.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return Store(container: container, context: ModelContext(container))
    }

    private func makeRecipe(_ name: String = "Negroni", ingredients: [RecipeIngredient] = []) -> Recipe {
        Recipe(
            id: UUID(),
            name: name,
            description: "",
            glassType: .rocks,
            method: .build,
            ingredients: ingredients,
            steps: [],
            flavorProfile: FlavorProfile(sweetness: 0, bitterness: 0, smokiness: 0, citrus: 0, floral: 0, spice: 0, herbal: 0, fruity: 0, oaky: 0, abv: 0),
            tags: [],
            difficulty: .easy,
            imageURL: nil
        )
    }

    // MARK: - FavouritesService

    func testSaveStoresRecipeIdCachedNameAndDate() throws {
        let store = try makeStore()
        let recipe = makeRecipe("Negroni")
        let date = Date(timeIntervalSince1970: 1_000)

        FavouritesService.save(recipe, context: store.context, date: date)

        let saved = try XCTUnwrap(FavouritesService.all(context: store.context).first)
        XCTAssertEqual(saved.recipeId, recipe.id)
        XCTAssertEqual(saved.recipeName, "Negroni")
        XCTAssertEqual(saved.dateFavourited, date)
    }

    func testSavingTheSameRecipeTwiceDoesNotDuplicate() throws {
        let store = try makeStore()
        let recipe = makeRecipe()

        FavouritesService.save(recipe, context: store.context)
        FavouritesService.save(recipe, context: store.context)

        XCTAssertEqual(FavouritesService.all(context: store.context).count, 1)
    }

    func testIsFavouritedReflectsSaveAndRemove() throws {
        let store = try makeStore()
        let recipe = makeRecipe()
        XCTAssertFalse(FavouritesService.isFavourited(recipeId: recipe.id, context: store.context))

        FavouritesService.save(recipe, context: store.context)
        XCTAssertTrue(FavouritesService.isFavourited(recipeId: recipe.id, context: store.context))

        FavouritesService.remove(recipeId: recipe.id, context: store.context)
        XCTAssertFalse(FavouritesService.isFavourited(recipeId: recipe.id, context: store.context))
    }

    func testRemoveOnlyDeletesTheMatchingRecipe() throws {
        let store = try makeStore()
        let keep = makeRecipe("Manhattan"), drop = makeRecipe("Negroni")
        FavouritesService.save(keep, context: store.context)
        FavouritesService.save(drop, context: store.context)

        FavouritesService.remove(recipeId: drop.id, context: store.context)

        XCTAssertEqual(FavouritesService.all(context: store.context).map(\.recipeName), ["Manhattan"])
    }

    func testAllIsSortedMostRecentlyFavouritedFirst() throws {
        let store = try makeStore()
        FavouritesService.save(makeRecipe("Oldest"), context: store.context, date: Date(timeIntervalSince1970: 100))
        FavouritesService.save(makeRecipe("Newest"), context: store.context, date: Date(timeIntervalSince1970: 300))
        FavouritesService.save(makeRecipe("Middle"), context: store.context, date: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(FavouritesService.all(context: store.context).map(\.recipeName), ["Newest", "Middle", "Oldest"])
    }

    func testToggleSavesThenRemovesAndReportsNewState() throws {
        let store = try makeStore()
        let recipe = makeRecipe()

        XCTAssertTrue(FavouritesService.toggle(recipe, context: store.context))
        XCTAssertTrue(FavouritesService.isFavourited(recipeId: recipe.id, context: store.context))

        XCTAssertFalse(FavouritesService.toggle(recipe, context: store.context))
        XCTAssertFalse(FavouritesService.isFavourited(recipeId: recipe.id, context: store.context))
    }

    func testFavouritesSurviveANewContextOnTheSameStore() throws {
        // The closest unit-level stand-in for "restart the app": a fresh context
        // reading what the first one saved.
        let store = try makeStore()
        let recipe = makeRecipe()
        FavouritesService.save(recipe, context: store.context)

        let freshContext = ModelContext(store.container)

        XCTAssertTrue(FavouritesService.isFavourited(recipeId: recipe.id, context: freshContext))
    }

    // MARK: - FavouritesViewModel

    func testViewModelStartsEmpty() throws {
        let store = try makeStore()
        let viewModel = FavouritesViewModel(modelContext: store.context)

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertTrue(viewModel.favourites.isEmpty)
    }

    func testTogglingTwiceLeavesRecipeNotFavourited() throws {
        let store = try makeStore()
        let viewModel = FavouritesViewModel(modelContext: store.context)
        let recipe = makeRecipe()

        viewModel.toggle(recipe)
        XCTAssertTrue(viewModel.isFavourited(recipe.id))
        XCTAssertFalse(viewModel.isEmpty)

        viewModel.toggle(recipe)
        XCTAssertFalse(viewModel.isFavourited(recipe.id))
        XCTAssertTrue(viewModel.isEmpty)
    }

    func testViewModelListsMostRecentFirst() throws {
        let store = try makeStore()
        let viewModel = FavouritesViewModel(modelContext: store.context)
        let first = makeRecipe("First"), second = makeRecipe("Second")

        viewModel.toggle(first, date: Date(timeIntervalSince1970: 100))
        viewModel.toggle(second, date: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(viewModel.favourites.map(\.recipeName), ["Second", "First"])
    }

    func testRemovingAFavouriteUpdatesTheViewModel() throws {
        let store = try makeStore()
        let viewModel = FavouritesViewModel(modelContext: store.context)
        let recipe = makeRecipe()
        viewModel.toggle(recipe)

        viewModel.remove(try XCTUnwrap(viewModel.favourites.first))

        XCTAssertFalse(viewModel.isFavourited(recipe.id))
        XCTAssertTrue(viewModel.isEmpty)
    }

    func testNewViewModelOnSameContextLoadsExistingFavourites() throws {
        let store = try makeStore()
        let recipe = makeRecipe("Negroni")
        FavouritesViewModel(modelContext: store.context).toggle(recipe)

        let reloaded = FavouritesViewModel(modelContext: store.context)

        XCTAssertTrue(reloaded.isFavourited(recipe.id))
        XCTAssertEqual(reloaded.favourites.map(\.recipeName), ["Negroni"])
    }

    // MARK: - Detail for a favourite that may not be makeable right now

    private func loadBundled() throws -> (TaxonomyIndex, [IngredientCategory], [Recipe]) {
        let taxonomyURL = try XCTUnwrap(Bundle.module.url(forResource: "taxonomy", withExtension: "json"))
        let recipesURL = try XCTUnwrap(Bundle.module.url(forResource: "recipes", withExtension: "json"))
        let categories = try IngredientTaxonomy.loadCategories(from: Data(contentsOf: taxonomyURL))
        let recipes = try IngredientTaxonomy.loadRecipes(from: Data(contentsOf: recipesURL))
        return (TaxonomyIndex(categories: categories), categories, recipes)
    }

    private func cabinetItem(_ name: String, index: TaxonomyIndex) throws -> CabinetItem {
        let style = try XCTUnwrap(index.stylesById.values.first { $0.name == name })
        return CabinetItem(
            ingredientStyleId: style.id, ingredientFamilyId: style.familyId, categoryId: style.categoryId,
            displayName: style.name, brand: nil, style: style.name,
            family: index.familyName(for: style), category: index.categoryName(for: style),
            flavorProfile: style.flavorProfile
        )
    }

    func testMatchResultForMakeableFavouriteIsReturned() throws {
        let (index, categories, recipes) = try loadBundled()
        let negroni = try XCTUnwrap(recipes.first { $0.name == "Negroni" })
        let cabinet = try ["London Dry Gin", "Bitter Aperitif", "Sweet/Rosso Vermouth"].map { try cabinetItem($0, index: index) }

        let result = RecipeService.matchResult(for: negroni, cabinet: cabinet, taxonomyCategories: categories)

        XCTAssertEqual(result?.matchType, .exact)
    }

    func testMatchResultIsNilWhenTheCabinetCannotMakeTheRecipe() throws {
        let (_, categories, recipes) = try loadBundled()
        let negroni = try XCTUnwrap(recipes.first { $0.name == "Negroni" })

        XCTAssertNil(RecipeService.matchResult(for: negroni, cabinet: [], taxonomyCategories: categories))
    }

    func testAvailabilityWithoutAMatchMarksMissingIngredientsUnavailable() throws {
        let (index, _, recipes) = try loadBundled()
        let negroni = try XCTUnwrap(recipes.first { $0.name == "Negroni" })
        let gin = try XCTUnwrap(index.stylesById.values.first { $0.name == "London Dry Gin" })

        // Only gin on hand — the recipe isn't makeable, but the detail still needs honest rows.
        let rows = RecipeAvailability.rows(for: negroni, substitutions: [], cabinetStyleIds: [gin.id])
        let statusByName = Dictionary(uniqueKeysWithValues: rows.map { (index.stylesById[$0.ingredient.ingredientStyleId]?.name ?? "?", $0.status) })

        XCTAssertEqual(statusByName["London Dry Gin"], .exact)
        XCTAssertEqual(statusByName["Bitter Aperitif"], .unavailable)
        XCTAssertEqual(statusByName["Sweet/Rosso Vermouth"], .unavailable)
    }

    // Spec row 16: a favourite whose recipe left the catalog keeps its cached
    // name and has no recipe; the others pair with their catalog recipe.
    func testEntriesPairFavouritesWithCatalogRecipesOrNil() throws {
        let store = try makeStore()
        let viewModel = FavouritesViewModel(modelContext: store.context)
        let kept = makeRecipe("Negroni")
        let removed = makeRecipe("Old House Special")
        viewModel.toggle(removed, date: Date(timeIntervalSince1970: 1_000))
        viewModel.toggle(kept, date: Date(timeIntervalSince1970: 2_000))

        let entries = viewModel.entries(in: [kept, makeRecipe("Unrelated")])

        XCTAssertEqual(entries.map(\.favourite.recipeName), ["Negroni", "Old House Special"])
        XCTAssertEqual(entries[0].recipe, kept)
        XCTAssertEqual(entries[0].id, kept.id)
        XCTAssertNil(entries[1].recipe)
        XCTAssertEqual(entries[1].favourite.recipeId, removed.id)
    }
}
