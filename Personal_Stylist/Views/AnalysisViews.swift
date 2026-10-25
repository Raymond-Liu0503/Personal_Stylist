import SwiftUI
import PhotosUI

struct PhotoImportButton: View {
    @Bindable var model: AppModel
    var title = "Choose photo"
    var compact = false
    var onPresentationChange: ((Bool) -> Void)?
    @State private var pickerPresented = false
    @State private var selection: PhotosPickerItem?
    @State private var importing = false
    var body: some View {
        Button { pickerPresented = true } label: {
            if compact {
                Image(systemName: "photo.on.rectangle").font(.title2).frame(width: 48, height: 48)
            } else {
                Label(importing ? "Opening…" : title, systemImage: "photo.on.rectangle")
                    .font(.callout.weight(.medium)).frame(minHeight: 44)
            }
        }
        .photosPicker(isPresented: $pickerPresented, selection: $selection, matching: .images, photoLibrary: .shared())
        .onChange(of: pickerPresented || importing) { _, covered in onPresentationChange?(covered) }
        .accessibilityLabel(importing ? "Opening photo" : title)
        .disabled(!model.onboarded || model.refreshing || model.busy || model.preparing || model.submitting || importing)
        .task(id: selection) {
            guard let selection else { return }
            importing = true
            defer { importing = false; self.selection = nil }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else { throw StylistError.message("The selected photo could not be opened.") }
                try Task.checkCancellation()
                await model.prepare(data)
            } catch is CancellationError { }
            catch { model.error = "Couldn't open this photo. Check that it's downloaded and try again." }
        }
    }
}

private struct PreparedPhotoPreview: View {
    let photo: PreparedPhoto
    let photos: PhotoService
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
        }
        .accessibilityLabel("Outfit photo preview")
        .task(id: photo.url) {
            image = nil
            if let data = try? await photos.read(photo), !Task.isCancelled { image = UIImage(data: data) }
        }
    }
}

struct ReviewView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var model: AppModel
    @State private var infoOpen = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let photo = model.photo {
                    PreparedPhotoPreview(photo: photo, photos: model.photos)
                        .frame(maxWidth: .infinity).frame(height: 360)
                        .background(StylistTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                let replacementLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout())
                replacementLayout {
                    Button("Retake", systemImage: "camera") { Task { await model.navigate(.camera, preserveBrief: true) } }
                        .frame(minHeight: 44).disabled(model.busy || model.preparing)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    PhotoImportButton(model: model, title: "Replace")
                }.font(.callout.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                if model.preparing { ProgressView("Preparing photo…") }
                DisclosureGroup("Styling options · \(model.intent.label)") {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Styling intent", selection: $model.intent) { ForEach(IntentPreset.allCases) { Text($0.label).tag($0) } }
                        if model.intent == .custom {
                            TextField("Your intent", text: $model.customIntent, axis: .vertical).lineLimit(2...4)
                            Text("\(model.customIntent.utf16.count)/160").font(.caption)
                        }
                        TextField("Anything to consider?", text: $model.prompt, axis: .vertical).lineLimit(2...5).accessibilityLabel("Optional outfit question")
                        if !model.prompt.isEmpty { Text("\(model.prompt.utf16.count)/1,000").font(.caption).foregroundStyle(StylistTheme.muted) }
                    }.textFieldStyle(.roundedBorder).padding(.top, 12)
                }.stylistCard()
                if !model.validIntent { NoticeView(error: "Use 1–160 characters for a custom intent and up to 1,000 for a question.") }
                NoticeView(error: model.error)
                if let block = model.analysisBlock {
                    Text(block).font(.callout).foregroundStyle(StylistTheme.muted)
                    if !model.refreshing { Button("Refresh access") { Task { await model.refresh() } } }
                }
            }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(StylistTheme.background).foregroundStyle(StylistTheme.ink)
        .navigationTitle("Your photo").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            StylistButton(title: "Analyze", symbol: "sparkles") { model.submit() }
                .accessibilityIdentifier("analyzeOutfit")
                .disabled(model.photo == nil || model.preparing || !model.validIntent || model.analysisBlock != nil || model.busy)
                .padding(.horizontal, 20).padding(.vertical, 12).background(StylistTheme.background)
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { infoOpen = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("Photo privacy and allowance")
        } }
        .sheet(isPresented: $infoOpen) {
            NavigationStack {
                Page(title: "Before you analyze") {
                    Text("Only this prepared photo is uploaded. Photos aren't saved to your reports.")
                    Text(model.bootstrap?.allowance ?? "Check Account for your allowance.")
                    Text("A request sent to the AI provider may count toward your allowance even if you cancel.")
                }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { infoOpen = false } } }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }
}

struct ProcessingView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if model.submitting {
                ProgressView().controlSize(.large).tint(StylistTheme.accent)
                Text("Analyzing…").font(.title2.weight(.medium)).accessibilityAddTraits(.isHeader)
            } else {
                Image(systemName: "exclamationmark.circle").font(.largeTitle).foregroundStyle(StylistTheme.accent)
                Text("Couldn't finish").font(.title2.weight(.medium))
            }
            NoticeView(error: model.error)
            if !model.submitting && model.photo != nil {
                StylistButton(title: "Retry", symbol: "arrow.clockwise") { model.submit() }.disabled(model.analysisBlock != nil)
                Text("Retry starts a new analysis and uses allowance.").font(.footnote).foregroundStyle(StylistTheme.muted)
                if let block = model.analysisBlock {
                    Text(block).font(.footnote)
                    if !model.refreshing { Button("Refresh access") { Task { await model.refresh() } } }
                }
            }
            Spacer()
            if model.submitting { Text("Canceling may still use allowance.").font(.footnote).foregroundStyle(StylistTheme.muted) }
            StylistButton(title: model.submitting ? "Cancel" : "Back to camera", secondary: true) {
                Task { await model.navigate(.home, preserveBrief: true) }
            }.disabled(model.busy)
        }
        .multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StylistTheme.background).foregroundStyle(StylistTheme.ink)
    }
}

struct ResultsView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let report = model.result?.report {
                    ReportView(report: report, feedback: model.suggestionFeedback, busy: model.busy, onFeedback: { index, helpful in Task { await model.sendFeedback(helpful: helpful, suggestion: index) } })
                    DisclosureGroup("Report feedback") {
                        VStack(spacing: 12) {
                            StylistButton(title: model.reportFeedbackSent ? "Thanks for your feedback" : "Helpful", secondary: true) { Task { await model.sendFeedback(helpful: true) } }
                            StylistButton(title: "Report invented details", secondary: true) { Task { await model.sendFeedback(helpful: false) } }
                        }.padding(.top, 12).disabled(model.busy || model.reportFeedbackSent)
                    }
                    Text("Saves text only. Save within 24 hours; unsaved notes clear when you close.").font(.footnote).foregroundStyle(StylistTheme.muted)
                } else if let result = model.result {
                    Label("Try another photo", systemImage: "camera").font(.title2.weight(.medium))
                    ForEach(Array(result.instructions.enumerated()), id: \.offset) { _, instruction in Text(instruction) }
                    Text("No rating. This analysis counts toward your allowance.").font(.footnote).foregroundStyle(StylistTheme.muted)
                }
                NoticeView(error: model.error, notice: model.notice)
            }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(StylistTheme.background).foregroundStyle(StylistTheme.ink)
        .navigationTitle("Your look").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { model.sheet = .saved } label: { Image(systemName: "bookmark") }.accessibilityLabel("Saved reports")
        } }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if model.result?.report != nil {
                    StylistButton(title: model.savedID == nil ? "Save report" : "Saved", symbol: model.savedID == nil ? "bookmark" : "bookmark.fill") { Task { await model.saveReport() } }.disabled(model.busy || model.savedID != nil)
                }
                Button(model.result?.report == nil ? "Retake" : "New photo", systemImage: "camera") {
                    Task { await model.navigate(.camera, preserveBrief: model.result?.report == nil) }
                }.fontWeight(.semibold).frame(minHeight: 44).disabled(model.busy)
            }.padding(.horizontal, 20).padding(.vertical, 12).background(StylistTheme.background)
        }
        .onAppear {
            if let ready = model.resultReadyAt {
                PerformanceTrace.finish("result_presentation", since: ready, id: model.result?.report?.runId ?? "none")
                model.resultReadyAt = nil
            }
        }
    }
}
