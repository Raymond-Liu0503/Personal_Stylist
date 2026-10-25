import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
@testable import StylistCore
#else
@testable import PersonalStylist
#endif

final class PhotoTests: XCTestCase {
    func testResizeOrientationMetadataRemovalAndCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = PhotoService(directory: directory)
        let context = CGContext(data: nil, width: 2400, height: 3200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.5, green: 0.25, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2400, height: 3200))
        let input = NSMutableData()
        let encoder = CGImageDestinationCreateWithData(input, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, context.makeImage()!, [kCGImagePropertyOrientation: 6, kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 45, kCGImagePropertyGPSLatitudeRef: "N"], kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private-source-metadata"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let photo = try await service.prepare(input as Data)
        XCTAssertEqual(photo.width, 1600); XCTAssertEqual(photo.height, 1200)
        let bytes = try await service.read(photo)
        XCTAssertEqual(bytes, try Data(contentsOf: photo.url))
        XCTAssertLessThanOrEqual(bytes.count, 2 * 1024 * 1024)
        let source = CGImageSourceCreateWithData(bytes as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment])
        XCTAssertNil(bytes.range(of: Data("private-source-metadata".utf8)))
        try await service.sweep()
        XCTAssertFalse(FileManager.default.fileExists(atPath: photo.url.path))
    }
    func testInvalidInputAndCancellation() async throws {
        let service = PhotoService(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        do { _ = try await service.prepare(Data("bad".utf8)); XCTFail() } catch { }
        let task = Task { try await Task.sleep(for: .milliseconds(100)); return try await service.prepare(Data()) }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch is CancellationError { } catch { XCTFail("Wrong cancellation error") }
    }
    func testSweepRemovesInterruptedWorkAndDoesNotTouchOtherFolders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let own = root.appendingPathComponent("private")
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        let other = root.appendingPathComponent("keep.jpg")
        try Data([1]).write(to: other)
        try Data([2]).write(to: own.appendingPathComponent("interrupted.jpg"))
        let service = PhotoService(directory: own)
        try await service.remove(PreparedPhoto(url: other, width: 1, height: 1))
        try await service.sweep()
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: own.path))
        try FileManager.default.removeItem(at: root)
    }
}
