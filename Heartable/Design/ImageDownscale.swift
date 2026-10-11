import ImageIO
import UIKit

/// Shared image helper: decode arbitrary picked image data, scale its longest
/// edge down to <=1024px, and re-encode as JPEG (quality 0.85). Returns nil if
/// the data isn't a decodable image. Used by avatar, mixtape-cover, and song-note photo uploads.
enum ImageDownscale {
    /// ImageIO decodes straight to the target size, so a 48 MP camera photo
    /// never becomes a ~200 MB full-resolution bitmap. Orientation is applied;
    /// smaller images keep their size.
    nonisolated static func jpeg(from data: Data, maxEdge: CGFloat = 1024, quality: CGFloat = 0.85) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxEdge,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: quality)
    }

    /// The same work off the main actor, for callers in views.
    nonisolated static func jpegInBackground(from data: Data, maxEdge: CGFloat = 1024,
                                             quality: CGFloat = 0.85) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            jpeg(from: data, maxEdge: maxEdge, quality: quality)
        }.value
    }
}
