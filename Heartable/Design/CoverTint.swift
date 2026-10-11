import CoreImage
import SwiftUI
import UIKit

/// The average color of an image, used to tint a screen after its artwork.
enum CoverTint {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func color(of image: UIImage) async -> Color? {
        guard let cgImage = image.cgImage else { return nil }
        return await Task.detached(priority: .utility) { average(cgImage) }.value
    }

    private static func average(_ cgImage: CGImage) -> Color? {
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return Color(
            red: Double(pixel[0]) / 255,
            green: Double(pixel[1]) / 255,
            blue: Double(pixel[2]) / 255
        )
    }
}
