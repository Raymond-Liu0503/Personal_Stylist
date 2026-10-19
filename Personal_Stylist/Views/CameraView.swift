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
    @State private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button { camera.stop(); Task { await model.navigate(.home, preserveBrief: true) } } label: { Image(systemName: "xmark").frame(width: 48, height: 48) }.accessibilityLabel("Cancel camera")
                Spacer(); Text("OUTFIT").font(.caption.bold()).tracking(3); Spacer()
                Menu {
                    Picker("Timer", selection: $model.timer) { Text("Off").tag(0); Text("3 seconds").tag(3); Text("10 seconds").tag(10) }
                } label: { Label(model.timer == 0 ? "Off" : "\(model.timer)s", systemImage: "timer").frame(minWidth: 48, minHeight: 48) }.disabled(camera.busy)
            }
            if camera.denied {
                Spacer()
                Image(systemName: "camera.fill").font(.largeTitle)
                Text("Make room for the look.").font(.custom("Georgia", size: 30, relativeTo: .title))
                Text("Allow camera access in Settings, or choose an outfit photo from your library.").multilineTextAlignment(.center)
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }.buttonStyle(.borderedProminent)
                Spacer()
            } else {
                GeometryReader { geometry in
                    ZStack {
                        CameraPreview(session: camera.engine.session)
                        if let count = camera.countdown { Text("\(count)").font(.system(size: 96, weight: .semibold)).shadow(radius: 8).accessibilityLabel("Countdown \(count)") }
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }
                if !camera.ready && camera.error == nil { ProgressView("Starting camera…").tint(.white) }
                Text(camera.error ?? model.error ?? (camera.countdown != nil ? "Hold your pose." : "Keep the whole outfit in frame.")).font(.callout).multilineTextAlignment(.center)
                if camera.error != nil { Button("Restart camera") { camera.start() }.buttonStyle(.bordered) }
                HStack(spacing: 40) {
                    Button { camera.flip() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel("Switch camera").disabled(camera.busy)
                    Button {
                        camera.takePhoto(timer: model.timer) { data in await model.prepare(data) }
                    } label: {
                        Circle().fill(.white).padding(6).overlay(Circle().stroke(.white, lineWidth: 3)).frame(width: 76, height: 76)
                    }.accessibilityLabel("Capture outfit").disabled(!camera.ready || camera.busy || model.preparing).opacity(camera.busy ? 0.4 : 1)
                    if camera.countdown != nil {
                        Button { camera.stop(); camera.start() } label: { Image(systemName: "stop.circle").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel("Cancel countdown")
                    } else { Color.clear.frame(width: 48, height: 48) }
                }
            }
            PhotoImportButton(model: model).disabled(camera.busy)
        }
        .padding(20).foregroundStyle(.white).background(Color(red: 0.035, green: 0.031, blue: 0.035)).preferredColorScheme(.dark)
        .task { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { camera.start() } else { camera.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: camera.engine.session)) { _ in camera.stop(); camera.error = "The camera was interrupted. Restart when you are ready." }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: camera.engine.session)) { _ in camera.stop(); camera.error = "The camera could not continue. Try restarting it." }
    }
}
