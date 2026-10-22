import Foundation

/// Limits for a recipe's "My take" (Recipe Take spec §2).
public enum TakeLimits {
    /// 0 means "no rating"; ratings move in half-star steps (0.5, 1, 1.5 … 5).
    public static let ratingRange: ClosedRange<Double> = 0...5
    public static let ratingStep = 0.5

    /// True for 0…5 in half-star steps.
    public static func isValidRating(_ rating: Double) -> Bool {
        ratingRange.contains(rating) && (rating / ratingStep).rounded() * ratingStep == rating
    }
    public static let maxNotesLength = 2_000
    public static let maxPhotos = 6
    public static let fullPhotoMaxPixels = 1_600
    public static let thumbnailMaxPixels = 320
    public static let jpegQuality = 0.8
}
