import XCTest
@testable import NorseMixologyCore

final class UserTasteProfileTests: XCTestCase {
    func testDefaultsAreAllNeutral() {
        let profile = UserTasteProfile()
        XCTAssertEqual(profile.sweetness, 0.5)
        XCTAssertEqual(profile.bitterness, 0.5)
        XCTAssertEqual(profile.citrus, 0.5)
        XCTAssertEqual(profile.smokiness, 0.5)
        XCTAssertEqual(profile.herbal, 0.5)
        XCTAssertFalse(profile.hasCompletedOnboarding)
        XCTAssertEqual(profile, UserTasteProfile.neutral)
    }

    func testRoundTripsThroughCodable() throws {
        let profile = UserTasteProfile(
            sweetness: 0.85, bitterness: 0.15, citrus: 0.5,
            smokiness: 0.85, herbal: 0.15, hasCompletedOnboarding: true
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserTasteProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }
}
