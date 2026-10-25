import SwiftUI
import AVFoundation

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        updateConnection()
    }
    func updateConnection() {
        if let connection = previewLayer.connection {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false }
        }
    }
}
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(); view.previewLayer.session = session; view.previewLayer.videoGravity = .resizeAspect; return view
    }
    func updateUIView(_ view: PreviewView, context: Context) { view.updateConnection() }
}

struct CameraView: View {
    @Bindable var model: AppModel
    @Bindable var camera: CameraModel
    @State private var importingPhoto = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    private var active: Bool { scenePhase == .active && model.sheet == nil && !importingPhoto }
    private var canCapture: Bool { model.onboarded && !model.refreshing && !model.busy && !model.preparing }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CameraControl(symbol: "bookmark", label: "Saved reports") { model.sheet = .saved }
                Spacer()
                if model.bootstrap?.analysisMode == "mock" {
                    Text("MOCK").font(.caption2.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.12), in: Capsule()).accessibilityLabel("Mock mode: sample feedback")
                }
                Spacer()
                CameraControl(symbol: "person.crop.circle", label: "Account") { model.sheet = .account }
            }.padding(.horizontal, 16)
            ZStack {
                CameraPreview(session: camera.engine.session)
                if camera.denied {
                    VStack(spacing: 16) {
                        Image(systemName: "camera").font(.largeTitle)
                        Text("Allow camera access").font(.title2.weight(.semibold))
                        Text("Or choose a photo below.").foregroundStyle(.white.opacity(0.7))
                        Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                            .buttonStyle(.borderedProminent).tint(StylistTheme.accent)
                    }.padding(24)
                } else if let error = camera.error {
                    VStack(spacing: 12) {
                        Text(error).multilineTextAlignment(.center)
                        Button("Restart camera") { camera.restart() }.buttonStyle(.bordered)
                    }.padding(24)
                } else if !camera.ready && !model.onboarded && AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                    Image(systemName: "camera").font(.largeTitle).accessibilityLabel("Camera")
                } else if !camera.ready {
                    ProgressView().tint(.white).accessibilityLabel("Starting camera")
                }
                if let count = camera.countdown {
                    Text("\(count)").font(.system(size: 96, weight: .semibold)).shadow(radius: 8).accessibilityLabel("Countdown \(count)")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            VStack(spacing: 12) {
                if model.preparing { ProgressView("Preparing photo…").tint(.white) }
                if model.refreshing { ProgressView("Checking access…").tint(.white) }
                else if let block = model.analysisBlock {
                    Text(block).font(.footnote).multilineTextAlignment(.center)
                    Button("Refresh access") { Task { await model.refresh() } }.font(.callout)
                }
                if let error = model.error { Text(error).font(.footnote).multilineTextAlignment(.center).accessibilityIdentifier("errorMessage") }
                HStack {
                    Menu {
                        Picker("Timer", selection: $model.timer) { Text("Off").tag(0); Text("3 seconds").tag(3); Text("10 seconds").tag(10) }
                    } label: {
                        Label(model.timer == 0 ? "Off" : "\(model.timer)s", systemImage: "timer")
                            .font(.callout.weight(.medium)).frame(minWidth: 48, minHeight: 44)
                    }.accessibilityLabel("Timer").disabled(camera.busy)
                    Spacer()
                    if camera.countdown != nil {
                        CameraControl(symbol: "stop.circle", label: "Cancel countdown") { camera.cancelCountdown() }
                    } else {
                        CameraControl(symbol: "arrow.triangle.2.circlepath.camera", label: "Switch camera") { camera.flip() }
                            .disabled(camera.busy || !camera.ready)
                    }
                }
                HStack {
                    PhotoImportButton(model: model, compact: true, onPresentationChange: { importingPhoto = $0 }).disabled(!canCapture || camera.busy)
                    Spacer()
                    Button { camera.takePhoto(timer: model.timer) { data in await model.prepare(data) } } label: {
                        Circle().fill(.white).padding(6).overlay(Circle().stroke(.white, lineWidth: 3)).frame(width: 76, height: 76)
                    }.accessibilityLabel("Capture outfit").accessibilityIdentifier("captureOutfit")
                        .disabled(!camera.ready || camera.busy || !canCapture)
                        .opacity(!camera.ready || camera.busy || !canCapture ? 0.4 : 1)
                    Spacer()
                    Color.clear.frame(width: 48, height: 48).accessibilityHidden(true)
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                    Button("Use test outfit") { Task { await model.prepareTestPhoto() } }.accessibilityIdentifier("testPhoto").disabled(!canCapture)
                }
                #endif
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
        }
        .foregroundStyle(.white).background(Color.black.ignoresSafeArea()).preferredColorScheme(.dark)
        .task { updateCamera() }
        .onDisappear { camera.stop() }
        .onChange(of: active) { _, _ in updateCamera() }
        .onChange(of: model.onboarded) { _, _ in updateCamera() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: camera.engine.session)) { _ in
            camera.stop(); camera.error = "Camera interrupted. Tap Restart when ready."
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: camera.engine.session)) { _ in
            camera.stop(); camera.error = "Camera unavailable. Try restarting it."
        }
    }
    private func updateCamera() {
        if active { camera.start(allowPermissionRequest: model.onboarded) } else { camera.stop() }
    }
}

private struct CameraControl: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.title2).frame(width: 48, height: 48) }
            .accessibilityLabel(label)
    }
}
