import XCTest
import SwiftData
@testable import NorseMixologyCore

/// Whole-star ratings saved before half stars existed must survive the Int → Double change.
final class RatingMigrationTests: XCTestCase {
    /// `RecipeTake` as shipped in v1.0.0-mvp: whole-star `Int` rating.
    enum Before {
        @Model
        final class RecipeTake {
            var id: UUID
            var recipeId: UUID = UUID()
            var recipeName: String = ""
            var rating: Int = 0
            var notes: String = ""
            var updatedAt: Date = Date()

            init(id: UUID = UUID(), recipeId: UUID, recipeName: String, rating: Int, notes: String) {
                self.id = id
                self.recipeId = recipeId
                self.recipeName = recipeName
                self.rating = rating
                self.notes = notes
            }
        }
    }

    func testWholeStarRatingsSavedAsIntegersStillOpen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let recipeId = UUID()

        do {
            let oldSchema = Schema([Before.RecipeTake.self])
            let container = try ModelContainer(for: oldSchema, configurations: [ModelConfiguration(schema: oldSchema, url: url)])
            let context = ModelContext(container)
            context.insert(Before.RecipeTake(recipeId: recipeId, recipeName: "Negroni", rating: 4, notes: "Great"))
            try context.save()
        }

        let newSchema = Schema([RecipeTake.self])
        let container = try ModelContainer(for: newSchema, configurations: [ModelConfiguration(schema: newSchema, url: url)])
        let context = ModelContext(container)

        let takes = try context.fetch(FetchDescriptor<RecipeTake>())
        XCTAssertEqual(takes.count, 1)
        XCTAssertEqual(takes.first?.rating, 4)
        XCTAssertEqual(takes.first?.notes, "Great")
        XCTAssertEqual(RecipeTakeService.ratings(context: context), [recipeId: 4])
    }

    func testBackupWrittenWithWholeNumberRatingsStillDecodes() throws {
        let json = """
        {"id":"\(UUID())","recipeId":"\(UUID())","recipeName":"Negroni","rating":4,"notes":"","updatedAt":0}
        """
        let decoder = JSONDecoder()
        let record = try decoder.decode(TakeRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.rating, 4)
        XCTAssertTrue(TakeLimits.isValidRating(record.rating))
    }
}
