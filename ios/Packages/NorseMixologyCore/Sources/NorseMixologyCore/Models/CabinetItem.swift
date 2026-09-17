import Foundation
import SwiftData

/// An ingredient the user has added to their cabinet — a snapshot of the
/// taxonomy `IngredientStyle` they picked at add time (name, brand,
/// flavour profile), not a live reference to it.
///
/// `FlavorProfile` is stored as individual columns rather than a single
/// transformable/blob field, for query flexibility (see Phase 2 notes).
@Model
public final class CabinetItem {
    public var id: UUID
    public var ingredientStyleId: UUID
    public var ingredientFamilyId: UUID
    public var categoryId: UUID
    public var displayName: String
    public var brand: String?
    public var style: String
    public var family: String
    public var category: String

    public var flavorSweetness: Double
    public var flavorBitterness: Double
    public var flavorSmokiness: Double
    public var flavorCitrus: Double
    public var flavorFloral: Double
    public var flavorSpice: Double
    public var flavorHerbal: Double
    public var flavorFruity: Double
    public var flavorOaky: Double
    public var flavorAbv: Double

    public var dateAdded: Date

    public var flavorProfile: FlavorProfile {
        get {
            FlavorProfile(
                sweetness: flavorSweetness, bitterness: flavorBitterness, smokiness: flavorSmokiness,
                citrus: flavorCitrus, floral: flavorFloral, spice: flavorSpice, herbal: flavorHerbal,
                fruity: flavorFruity, oaky: flavorOaky, abv: flavorAbv
            )
        }
        set {
            flavorSweetness = newValue.sweetness
            flavorBitterness = newValue.bitterness
            flavorSmokiness = newValue.smokiness
            flavorCitrus = newValue.citrus
            flavorFloral = newValue.floral
            flavorSpice = newValue.spice
            flavorHerbal = newValue.herbal
            flavorFruity = newValue.fruity
            flavorOaky = newValue.oaky
            flavorAbv = newValue.abv
        }
    }

    public init(
        id: UUID = UUID(),
        ingredientStyleId: UUID,
        ingredientFamilyId: UUID,
        categoryId: UUID,
        displayName: String,
        brand: String?,
        style: String,
        family: String,
        category: String,
        flavorProfile: FlavorProfile,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.ingredientStyleId = ingredientStyleId
        self.ingredientFamilyId = ingredientFamilyId
        self.categoryId = categoryId
        self.displayName = displayName
        self.brand = brand
        self.style = style
        self.family = family
        self.category = category
        self.flavorSweetness = flavorProfile.sweetness
        self.flavorBitterness = flavorProfile.bitterness
        self.flavorSmokiness = flavorProfile.smokiness
        self.flavorCitrus = flavorProfile.citrus
        self.flavorFloral = flavorProfile.floral
        self.flavorSpice = flavorProfile.spice
        self.flavorHerbal = flavorProfile.herbal
        self.flavorFruity = flavorProfile.fruity
        self.flavorOaky = flavorProfile.oaky
        self.flavorAbv = flavorProfile.abv
        self.dateAdded = dateAdded
    }
}
