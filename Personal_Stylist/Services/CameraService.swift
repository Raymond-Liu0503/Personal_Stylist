import AVFoundation
import Foundation
import Observation
import UIKit

// All capture-session operations are serialized off the main thread.
final class CaptureEngine: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "stylist.camera")
    private var completion: (@Sendable (Result<Data, Error>) -> Void)?
    func start(position: AVCaptureDevice.Position) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo
                    self.session.inputs.forEach { self.session.removeInput($0) }
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { throw StylistError.message("This device has no available camera. Choose a photo instead.") }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else { throw StylistError.message("The camera could not start.") }
                    self.session.addInput(input)
                    if self.session.outputs.isEmpty {
                        guard self.session.canAddOutput(self.output) else { throw StylistError.message("Photo capture is unavailable.") }
                        self.session.addOutput(self.output)
                    }
                    self.session.commitConfiguration()
                    if let connection = self.output.connection(with: .video) {
                        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                        if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false }
                    }
                    self.session.startRunning()
                    continuation.resume()
                } catch {
                    self.session.commitConfiguration(); continuation.resume(throwing: error)
                }
            }
        }
    }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.completion == nil, self.session.isRunning else { continuation.resume(throwing: StylistError.message("The camera is not ready.")); return }
                self.completion = { result in continuation.resume(with: result) }
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        queue.async {
            defer { self.completion = nil }
            if let error { self.completion?(.failure(error)) }
            else if let data { self.completion?(.success(data)) }
            else { self.completion?(.failure(StylistError.message("The camera did not capture a photo."))) }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error { queue.async { self.completion?(.failure(error)); self.completion = nil } }
    }
}

@MainActor @Observable final class CameraModel {
    @ObservationIgnored let engine = CaptureEngine()
    var ready = false
    var denied = false
    var error: String?
    var front = true
    var countdown: Int?
    var busy = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var startupDeadline: Task<Void, Never>?
    func start() {
        stop(); let epoch = generation
        startTask = Task {
            var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .video) }
            guard epoch == generation, !Task.isCancelled else { return }
            denied = !granted
            guard granted else { return }
            startupDeadline = Task {
                do {
                    try await Task.sleep(for: .seconds(8))
                    if epoch == generation && !ready { error = "The camera is taking too long to start. Tap Restart camera to try again." }
                } catch { }
            }
            do {
                try await engine.start(position: front ? .front : .back)
                guard epoch == generation, !Task.isCancelled else { return }
                startupDeadline?.cancel(); startupDeadline = nil
                ready = true; error = nil
            } catch { if epoch == generation { self.error = error.localizedDescription } }
        }
    }
    func stop() {
        generation = UUID(); startTask?.cancel(); captureTask?.cancel(); startupDeadline?.cancel(); startupDeadline = nil
        startTask = nil; captureTask = nil; countdown = nil; busy = false; ready = false; engine.stop()
    }
    func flip() { guard !busy else { return }; front.toggle(); start() }
    func takePhoto(timer: Int, receive: @escaping @MainActor (Data) async -> Void) {
        guard ready, !busy else { return }
        busy = true; error = nil; let epoch = generation
        captureTask = Task {
            do {
                if timer > 0 {
                    for remaining in stride(from: timer, through: 1, by: -1) {
                        try Task.checkCancellation(); countdown = remaining
                        UIAccessibility.post(notification: .announcement, argument: "\(remaining)")
                        try await Task.sleep(for: .seconds(1))
                    }
                }
                countdown = nil
                let data = try await engine.capture()
                guard epoch == generation, !Task.isCancelled else { return }
                await receive(data)
            } catch is CancellationError { }
            catch { if epoch == generation { self.error = error.localizedDescription } }
            if epoch == generation { busy = false; countdown = nil; captureTask = nil }
        }
    }
}
