import Foundation
import GRDB

/// The only code that writes a catalog database. Turns verified JSON bytes
/// into a complete SQLite file at `destination`, or throws and leaves nothing
/// behind — callers never see a half-built catalog.
public enum CatalogImporter {
    public static func build(
        at destination: URL,
        manifest: CatalogManifest,
        taxonomyData: Data,
        recipesData: Data,
        source: CatalogSource,
        etag: String?
    ) throws {
        do {
            try verify(taxonomyData, against: manifest.taxonomy, name: "taxonomy")
            try verify(recipesData, against: manifest.recipes, name: "recipes")
            let categories = try decodeCategories(taxonomyData)
            let recipes = try decodeRecipes(recipesData)
            try checkNesting(categories)
            let meta = CatalogMeta(
                schemaVersion: manifest.schemaVersion,
                contentVersion: manifest.contentVersion,
                generatedAt: manifest.generatedAt,
                source: source,
                etag: etag
            )
            CatalogPaths.removeDatabaseFiles(at: destination)
            try write(categories: categories, recipes: recipes, meta: meta, to: destination)
        } catch {
            CatalogPaths.removeDatabaseFiles(at: destination)
            throw error
        }
    }

    // MARK: - Checks before touching the disk

    private static func verify(_ data: Data, against entry: CatalogManifest.FileEntry, name: String) throws {
        guard data.count <= CatalogManifest.maxFileBytes else {
            throw CatalogError.fileTooLarge(name, data.count)
        }
        guard CatalogHash.sha256Hex(data) == entry.sha256 else {
            throw CatalogError.hashMismatch(name)
        }
    }

    private static func decodeCategories(_ data: Data) throws -> [IngredientCategory] {
        do {
            return try IngredientTaxonomy.loadCategories(from: data)
        } catch {
            throw CatalogError.malformedTaxonomy(String(describing: error))
        }
    }

    /// Stricter than the app's tolerant loader: a remote update with even one
    /// undecodable recipe is rejected whole, and the current catalog is kept.
    private static func decodeRecipes(_ data: Data) throws -> [Recipe] {
        let result: (recipes: [Recipe], skippedCount: Int)
        do {
            result = try IngredientTaxonomy.loadRecipesReportingSkipped(from: data)
        } catch {
            throw CatalogError.malformedRecipes(String(describing: error))
        }
        guard result.skippedCount == 0 else {
            throw CatalogError.malformedRecipes("\(result.skippedCount) recipe(s) could not be decoded")
        }
        return result.recipes
    }

    private static func checkNesting(_ categories: [IngredientCategory]) throws {
        for category in categories {
            for family in category.families {
                guard family.categoryId == category.id else {
                    throw CatalogError.invalidStructure("family \(family.name) is nested under the wrong category")
                }
                for style in family.styles where style.familyId != family.id || style.categoryId != category.id {
                    throw CatalogError.invalidStructure("style \(style.name) is nested under the wrong family or category")
                }
            }
        }
    }

    // MARK: - Writing

    private static func write(categories: [IngredientCategory], recipes: [Recipe], meta: CatalogMeta, to destination: URL) throws {
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: destination.path)
        } catch {
            throw CatalogError.fileSystem(String(describing: error))
        }
        do {
            try queue.write { db in
                try CatalogSchema.create(in: db)
                try insert(meta: meta, into: db)
                try insert(categories: categories, into: db)
                try insert(recipes: recipes, into: db)
            }
            let violations = try queue.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }
            guard violations.isEmpty else {
                throw CatalogError.constraintViolation("\(violations.count) foreign key violation(s)")
            }
            let integrity = try queue.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") }
            guard integrity == "ok" else {
                throw CatalogError.constraintViolation("integrity_check: \(integrity ?? "no result")")
            }
            try queue.close()
        } catch let error as CatalogError {
            try? queue.close()
            throw error
        } catch let error as DatabaseError {
            try? queue.close()
            throw CatalogError.constraintViolation(error.message ?? error.description)
        } catch {
            try? queue.close()
            throw CatalogError.fileSystem(String(describing: error))
        }
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static func insert(meta: CatalogMeta, into db: Database) throws {
        var rows: [(String, String)] = [
            ("schemaVersion", String(meta.schemaVersion)),
            ("contentVersion", meta.contentVersion),
            ("generatedAt", CatalogDate.format(meta.generatedAt)),
            ("source", meta.source.rawValue)
        ]
        if let etag = meta.etag {
            rows.append(("etag", etag))
        }
        for (key, value) in rows {
            try db.execute(sql: "INSERT INTO catalog_meta (key, value) VALUES (?, ?)", arguments: [key, value])
        }
    }

    private static func insert(categories: [IngredientCategory], into db: Database) throws {
        let styleColumns = ["id", "family_id", "category_id", "name", "sort_order", "abv_min", "abv_max"] + CatalogSchema.profileColumns
        let styleSQL = "INSERT INTO style (\(styleColumns.joined(separator: ", "))) VALUES (\(placeholders(styleColumns.count)))"
        var familyOrder = 0
        var styleOrder = 0
        for (categoryOrder, category) in categories.enumerated() {
            try db.execute(
                sql: "INSERT INTO category (id, name, sort_order) VALUES (?, ?, ?)",
                arguments: [category.id.uuidString, category.name, categoryOrder]
            )
            for family in category.families {
                try db.execute(
                    sql: "INSERT INTO family (id, category_id, name, sort_order) VALUES (?, ?, ?, ?)",
                    arguments: [family.id.uuidString, category.id.uuidString, family.name, familyOrder]
                )
                familyOrder += 1
                for style in family.styles {
                    var args: [(any DatabaseValueConvertible)?] = [
                        style.id.uuidString, family.id.uuidString, category.id.uuidString,
                        style.name, styleOrder, style.abvMin, style.abvMax
                    ]
                    args.append(contentsOf: CatalogSchema.profileValues(style.flavorProfile).map { $0 as (any DatabaseValueConvertible)? })
                    try db.execute(sql: styleSQL, arguments: StatementArguments(args))
                    styleOrder += 1
                    for (position, brand) in style.exampleBrands.enumerated() {
                        try db.execute(
                            sql: "INSERT INTO style_brand (style_id, position, brand) VALUES (?, ?, ?)",
                            arguments: [style.id.uuidString, position, brand]
                        )
                    }
                }
            }
        }
    }

    private static func insert(recipes: [Recipe], into db: Database) throws {
        let recipeColumns = ["id", "sort_order", "name", "description", "glass_type", "method", "difficulty", "image_url"] + CatalogSchema.profileColumns
        let recipeSQL = "INSERT INTO recipe (\(recipeColumns.joined(separator: ", "))) VALUES (\(placeholders(recipeColumns.count)))"
        for (order, recipe) in recipes.enumerated() {
            var args: [(any DatabaseValueConvertible)?] = [
                recipe.id.uuidString, order, recipe.name, recipe.description,
                recipe.glassType.rawValue, recipe.method.rawValue, recipe.difficulty.rawValue, recipe.imageURL
            ]
            args.append(contentsOf: CatalogSchema.profileValues(recipe.flavorProfile).map { $0 as (any DatabaseValueConvertible)? })
            try db.execute(sql: recipeSQL, arguments: StatementArguments(args))

            for (position, ingredient) in recipe.ingredients.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO recipe_ingredient (recipe_id, position, style_id, amount, preparation, is_optional, substitute_notes)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [recipe.id.uuidString, position, ingredient.ingredientStyleId.uuidString, ingredient.amount,
                                ingredient.preparation, ingredient.isOptional ? 1 : 0, ingredient.substituteNotes]
                )
            }
            for (position, step) in recipe.steps.enumerated() {
                try db.execute(
                    sql: "INSERT INTO recipe_step (recipe_id, position, text) VALUES (?, ?, ?)",
                    arguments: [recipe.id.uuidString, position, step]
                )
            }
            for (position, tag) in recipe.tags.enumerated() {
                try db.execute(
                    sql: "INSERT INTO recipe_tag (recipe_id, position, tag) VALUES (?, ?, ?)",
                    arguments: [recipe.id.uuidString, position, tag]
                )
            }
        }
    }
}
