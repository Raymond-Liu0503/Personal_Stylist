import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PreparedPhoto: Sendable { let url: URL; let width: Int; let height: Int }
actor PhotoService {
    private let directory: URL
    init(directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("stylist-private", isDirectory: true)) { self.directory = directory }
    func sweep() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func remove(_ photo: PreparedPhoto) throws {
        guard photo.url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        if FileManager.default.fileExists(atPath: photo.url.path) { try FileManager.default.removeItem(at: photo.url) }
    }
    func prepare(_ data: Data) throws -> PreparedPhoto {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw StylistError.message("This photo could not be opened. Try another image.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resource = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
        for quality in [0.85, 0.7, 0.5, 0.3] {
            try Task.checkCancellation()
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            // Encode pixels into a new container; never copy EXIF/GPS/IPTC metadata.
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination), output.length <= 2 * 1024 * 1024 else { continue }
            let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            do {
                try (output as Data).write(to: url, options: [.atomic, .completeFileProtection])
                try Task.checkCancellation()
                return PreparedPhoto(url: url, width: image.width, height: image.height)
            } catch {
                try? FileManager.default.removeItem(at: url); throw error
            }
        }
        throw StylistError.message("This photo is still too large. Try another photo.")
    }
}
