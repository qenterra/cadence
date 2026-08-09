import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ArtworkThumbnailGenerator {
    static func data(
        from sourceData: Data,
        maximumPixelDimension: Int
    ) -> Data? {
        guard maximumPixelDimension > 0,
              let source = CGImageSourceCreateWithData(
                  sourceData as CFData,
                  nil
              ),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
                  ] as CFDictionary
              )
        else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }
}
