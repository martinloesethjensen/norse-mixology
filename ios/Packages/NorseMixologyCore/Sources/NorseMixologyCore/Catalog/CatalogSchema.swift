import GRDB

/// DDL for the on-device catalog database. `version` is stored in
/// `PRAGMA user_version`; bump it whenever these statements change — the
/// bootstrap rebuilds any database whose version differs.
enum CatalogSchema {
    static let version = 1

    /// The nine 0–1 flavour dimensions, then `abv` (not range-checked).
    static let profileColumns = ["sweetness", "bitterness", "smokiness", "citrus", "floral",
                                 "spice", "herbal", "fruity", "oaky", "abv"]

    /// Values in `profileColumns` order.
    static func profileValues(_ p: FlavorProfile) -> [Double] {
        [p.sweetness, p.bitterness, p.smokiness, p.citrus, p.floral, p.spice, p.herbal, p.fruity, p.oaky, p.abv]
    }

    private static var profileColumnDefinitions: String {
        profileColumns.map { column in
            column == "abv"
                ? "abv REAL NOT NULL"
                : "\(column) REAL NOT NULL CHECK (\(column) BETWEEN 0 AND 1)"
        }.joined(separator: ",\n  ")
    }

    static var statements: [String] {
        [
            "CREATE TABLE catalog_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT",
            "CREATE TABLE category (id TEXT PRIMARY KEY, name TEXT NOT NULL, sort_order INTEGER NOT NULL) STRICT",
            """
            CREATE TABLE family (
              id TEXT PRIMARY KEY,
              category_id TEXT NOT NULL REFERENCES category(id),
              name TEXT NOT NULL,
              sort_order INTEGER NOT NULL) STRICT
            """,
            """
            CREATE TABLE style (
              id TEXT PRIMARY KEY,
              family_id TEXT NOT NULL REFERENCES family(id),
              category_id TEXT NOT NULL REFERENCES category(id),
              name TEXT NOT NULL,
              sort_order INTEGER NOT NULL,
              abv_min REAL NOT NULL,
              abv_max REAL NOT NULL,
              \(profileColumnDefinitions)) STRICT
            """,
            """
            CREATE TABLE style_brand (
              style_id TEXT NOT NULL REFERENCES style(id),
              position INTEGER NOT NULL,
              brand TEXT NOT NULL,
              PRIMARY KEY (style_id, position)) STRICT
            """,
            """
            CREATE TABLE recipe (
              id TEXT PRIMARY KEY,
              sort_order INTEGER NOT NULL,
              name TEXT NOT NULL,
              description TEXT NOT NULL,
              glass_type TEXT NOT NULL,
              method TEXT NOT NULL,
              difficulty TEXT NOT NULL,
              image_url TEXT,
              \(profileColumnDefinitions)) STRICT
            """,
            """
            CREATE TABLE recipe_ingredient (
              recipe_id TEXT NOT NULL REFERENCES recipe(id),
              position INTEGER NOT NULL,
              style_id TEXT NOT NULL REFERENCES style(id),
              amount TEXT NOT NULL,
              preparation TEXT,
              is_optional INTEGER NOT NULL CHECK (is_optional IN (0, 1)),
              substitute_notes TEXT,
              PRIMARY KEY (recipe_id, position)) STRICT
            """,
            """
            CREATE TABLE recipe_step (
              recipe_id TEXT NOT NULL REFERENCES recipe(id),
              position INTEGER NOT NULL,
              text TEXT NOT NULL,
              PRIMARY KEY (recipe_id, position)) STRICT
            """,
            """
            CREATE TABLE recipe_tag (
              recipe_id TEXT NOT NULL REFERENCES recipe(id),
              position INTEGER NOT NULL,
              tag TEXT NOT NULL,
              PRIMARY KEY (recipe_id, position),
              UNIQUE (recipe_id, tag)) STRICT
            """,
            "CREATE INDEX recipe_tag_by_tag ON recipe_tag(tag)"
        ]
    }

    static func create(in db: Database) throws {
        for statement in statements {
            try db.execute(sql: statement)
        }
        try db.execute(sql: "PRAGMA user_version = \(version)")
    }
}
