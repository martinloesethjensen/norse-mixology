import Foundation

/// Limits for a recipe's "My take" (Recipe Take spec §2).
public enum TakeLimits {
    /// 0 means "no rating".
    public static let ratingRange = 0...5
    public static let maxNotesLength = 2_000
    public static let maxPhotos = 6
    public static let fullPhotoMaxPixels = 1_600
    public static let thumbnailMaxPixels = 320
    public static let jpegQuality = 0.8
}
