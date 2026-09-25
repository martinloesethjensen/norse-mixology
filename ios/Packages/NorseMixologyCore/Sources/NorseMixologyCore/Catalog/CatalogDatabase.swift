import Foundation
import GRDB

/// Reads a catalog database back into the app's model types. Read-only, and
/// every failure is a thrown `CatalogError` — rows are decoded with throwing
/// `Decodable` records rather than force-typed subscripts, so a damaged file
/// can never crash the app at launch.
public enum CatalogDatabase {
    public static func load(from url: URL) throws -> LoadedCatalog {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CatalogError.missingDatabase
        }
        var configuration = Configuration()
        configuration.readonly = true
        do {
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            defer { try? queue.close() }
            return try queue.read { db in
                let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
                guard version == CatalogSchema.version else {
                    throw CatalogError.schemaMismatch(found: version)
                }
                return LoadedCatalog(meta: try readMeta(db), categories: try readCategories(db), recipes: try readRecipes(db))
            }
        } catch let error as CatalogError {
            throw error
        } catch {
            throw CatalogError.corruptDatabase(String(describing: error))
        }
    }

    // MARK: - Rows

    private struct MetaRow: SnakeCaseRecord { let key: String; let value: String }
    private struct CategoryRow: SnakeCaseRecord { let id: String; let name: String }
    private struct FamilyRow: SnakeCaseRecord { let id: String; let categoryId: String; let name: String }
    private struct StyleRow: SnakeCaseRecord {
        let id: String, familyId: String, categoryId: String, name: String, abvMin: Double, abvMax: Double
        let sweetness: Double, bitterness: Double, smokiness: Double, citrus: Double, floral: Double
        let spice: Double, herbal: Double, fruity: Double, oaky: Double, abv: Double
    }
    private struct BrandRow: SnakeCaseRecord { let styleId: String; let brand: String }
    private struct RecipeRow: SnakeCaseRecord {
        let id: String, name: String, description: String, glassType: String, method: String, difficulty: String, imageUrl: String?
        let sweetness: Double, bitterness: Double, smokiness: Double, citrus: Double, floral: Double
        let spice: Double, herbal: Double, fruity: Double, oaky: Double, abv: Double
    }
    private struct IngredientRow: SnakeCaseRecord {
        let recipeId: String, styleId: String, amount: String, preparation: String?, isOptional: Int, substituteNotes: String?
    }
    private struct StepRow: SnakeCaseRecord { let recipeId: String; let text: String }
    private struct TagRow: SnakeCaseRecord { let recipeId: String; let tag: String }

    // MARK: - Readers

    private static func readMeta(_ db: Database) throws -> CatalogMeta {
        let rows = try MetaRow.fetchAll(db, sql: "SELECT key, value FROM catalog_meta")
        let values = Dictionary(rows.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        guard
            let schemaVersion = values["schemaVersion"].flatMap(Int.init),
            let contentVersion = values["contentVersion"],
            let generatedAt = values["generatedAt"].flatMap(CatalogDate.parse),
            let source = values["source"].flatMap(CatalogSource.init(rawValue:))
        else {
            throw CatalogError.corruptDatabase("catalog_meta is incomplete")
        }
        return CatalogMeta(schemaVersion: schemaVersion, contentVersion: contentVersion, generatedAt: generatedAt, source: source, etag: values["etag"])
    }

    private static func readCategories(_ db: Database) throws -> [IngredientCategory] {
        let categoryRows = try CategoryRow.fetchAll(db, sql: "SELECT id, name FROM category ORDER BY sort_order")
        let familyRows = try FamilyRow.fetchAll(db, sql: "SELECT id, category_id, name FROM family ORDER BY sort_order")
        let styleColumns = (["id", "family_id", "category_id", "name", "abv_min", "abv_max"] + CatalogSchema.profileColumns).joined(separator: ", ")
        let styleRows = try StyleRow.fetchAll(db, sql: "SELECT \(styleColumns) FROM style ORDER BY sort_order")
        let brandRows = try BrandRow.fetchAll(db, sql: "SELECT style_id, brand FROM style_brand ORDER BY style_id, position")

        var brandsByStyle: [String: [String]] = [:]
        for row in brandRows { brandsByStyle[row.styleId, default: []].append(row.brand) }

        var stylesByFamily: [String: [IngredientStyle]] = [:]
        for row in styleRows {
            let style = IngredientStyle(
                id: try uuid(row.id), name: row.name, familyId: try uuid(row.familyId), categoryId: try uuid(row.categoryId),
                exampleBrands: brandsByStyle[row.id] ?? [],
                flavorProfile: FlavorProfile(sweetness: row.sweetness, bitterness: row.bitterness, smokiness: row.smokiness,
                                             citrus: row.citrus, floral: row.floral, spice: row.spice, herbal: row.herbal,
                                             fruity: row.fruity, oaky: row.oaky, abv: row.abv),
                abvMin: row.abvMin, abvMax: row.abvMax
            )
            stylesByFamily[row.familyId, default: []].append(style)
        }

        var familiesByCategory: [String: [IngredientFamily]] = [:]
        for row in familyRows {
            let family = IngredientFamily(id: try uuid(row.id), name: row.name, categoryId: try uuid(row.categoryId),
                                          styles: stylesByFamily[row.id] ?? [])
            familiesByCategory[row.categoryId, default: []].append(family)
        }

        return try categoryRows.map { row in
            IngredientCategory(id: try uuid(row.id), name: row.name, families: familiesByCategory[row.id] ?? [])
        }
    }

    private static func readRecipes(_ db: Database) throws -> [Recipe] {
        let recipeColumns = (["id", "name", "description", "glass_type", "method", "difficulty", "image_url"] + CatalogSchema.profileColumns).joined(separator: ", ")
        let recipeRows = try RecipeRow.fetchAll(db, sql: "SELECT \(recipeColumns) FROM recipe ORDER BY sort_order")
        let ingredientRows = try IngredientRow.fetchAll(db, sql: """
            SELECT recipe_id, style_id, amount, preparation, is_optional, substitute_notes
            FROM recipe_ingredient ORDER BY recipe_id, position
            """)
        let stepRows = try StepRow.fetchAll(db, sql: "SELECT recipe_id, text FROM recipe_step ORDER BY recipe_id, position")
        let tagRows = try TagRow.fetchAll(db, sql: "SELECT recipe_id, tag FROM recipe_tag ORDER BY recipe_id, position")

        var ingredients: [String: [RecipeIngredient]] = [:]
        for row in ingredientRows {
            ingredients[row.recipeId, default: []].append(RecipeIngredient(
                ingredientStyleId: try uuid(row.styleId), amount: row.amount, preparation: row.preparation,
                isOptional: row.isOptional != 0, substituteNotes: row.substituteNotes
            ))
        }
        var steps: [String: [String]] = [:]
        for row in stepRows { steps[row.recipeId, default: []].append(row.text) }
        var tags: [String: [String]] = [:]
        for row in tagRows { tags[row.recipeId, default: []].append(row.tag) }

        return try recipeRows.map { row in
            guard
                let glassType = GlassType(rawValue: row.glassType),
                let method = Method(rawValue: row.method),
                let difficulty = Difficulty(rawValue: row.difficulty)
            else {
                throw CatalogError.corruptDatabase("recipe \(row.id) has an unknown glass type, method or difficulty")
            }
            return Recipe(
                id: try uuid(row.id), name: row.name, description: row.description, glassType: glassType, method: method,
                ingredients: ingredients[row.id] ?? [], steps: steps[row.id] ?? [],
                flavorProfile: FlavorProfile(sweetness: row.sweetness, bitterness: row.bitterness, smokiness: row.smokiness,
                                             citrus: row.citrus, floral: row.floral, spice: row.spice, herbal: row.herbal,
                                             fruity: row.fruity, oaky: row.oaky, abv: row.abv),
                tags: tags[row.id] ?? [], difficulty: difficulty, imageURL: row.imageUrl
            )
        }
    }

    private static func uuid(_ string: String) throws -> UUID {
        guard let value = UUID(uuidString: string) else {
            throw CatalogError.corruptDatabase("invalid UUID \(string)")
        }
        return value
    }
}

/// Row records decode columns like `abv_min` / `image_url` into `abvMin` / `imageUrl`.
private protocol SnakeCaseRecord: Decodable, FetchableRecord {}

extension SnakeCaseRecord {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
