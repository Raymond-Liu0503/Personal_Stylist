import SwiftUI
import PhotosUI

struct PhotoImportButton: View {
    @Bindable var model: AppModel
    var title = "Choose photo"
    @State private var selection: PhotosPickerItem?
    @State private var importing = false
    var body: some View {
        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            Label(importing ? "Opening photo…" : title, systemImage: "photo.on.rectangle")
                .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 16)
        }
        .buttonStyle(StylistButtonStyle(secondary: true, destructive: false))
        .disabled(model.busy || model.preparing || model.submitting || importing)
        .task(id: selection) {
            guard let selection else { return }
            importing = true
            defer { importing = false; self.selection = nil }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else { throw StylistError.message("The selected photo could not be opened.") }
                try Task.checkCancellation()
                await model.prepare(data)
            } catch is CancellationError { }
            catch { model.error = "The photo could not be imported. Check that it is downloaded and try again." }
        }
    }
}

struct HomeView: View {
    @Bindable var model: AppModel
    var body: some View {
        Page(title: "A fresh perspective.") {
            HStack {
                Eyebrow(text: "Personal Stylist")
                Spacer()
                if model.bootstrap?.analysisMode == "mock" { Text("MOCK").font(.caption2.bold()).padding(6).background(StylistTheme.line, in: Capsule()).accessibilityLabel("Mock mode: sample feedback") }
            }
            Text("Good style starts with what you have.").font(.title3).foregroundStyle(StylistTheme.muted)
            Button { Task { await model.navigate(.camera) } } label: {
                VStack(alignment: .leading, spacing: 40) {
                    Image(systemName: "camera").font(.system(size: 28)).padding(18).background(.white.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Let’s see the look.").font(.custom("Georgia", size: 32, relativeTo: .title))
                        HStack { Text("Take an outfit photo"); Spacer(); Image(systemName: "arrow.up.right") }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(28).foregroundStyle(.white).background(StylistTheme.accent, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain).accessibilityLabel("Take a photo").disabled(model.busy || model.preparing)
            PhotoImportButton(model: model)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                Button("Use test outfit") { Task { await model.prepareTestPhoto() } }.accessibilityIdentifier("testPhoto")
            }
            #endif
            if model.preparing { ProgressView("Preparing and reducing your photo…") }
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "A better second opinion")
                Text("Find even light. Leave room for the shoes.")
                Text("A clear, full-outfit photo gives us more to work with.").font(.callout).foregroundStyle(StylistTheme.muted)
            }
            Divider()
            Text(model.bootstrap?.allowance ?? "Checking your allowance…").font(.footnote).foregroundStyle(StylistTheme.muted)
            if let block = model.analysisBlock { Text(block).font(.callout).foregroundStyle(StylistTheme.muted) }
            NoticeView(error: model.error)
        }.refreshable { await model.refresh() }
    }
}

struct ReviewView: View {
    @Bindable var model: AppModel
    @State private var optionsOpen = false
    var body: some View {
        Page(title: "The look, in focus.") {
            if let photo = model.photo {
                AsyncImage(url: photo.url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .frame(maxWidth: .infinity).frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityLabel("Outfit photo preview")
            }
            if model.preparing { ProgressView("Preparing your photo…") }
            DisclosureGroup("Styling options · \(model.intent.label)", isExpanded: $optionsOpen) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Styling intent", selection: $model.intent) { ForEach(IntentPreset.allCases) { Text($0.label).tag($0) } }
                    if model.intent == .custom {
                        TextField("Describe your intent", text: $model.customIntent, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                        Text("\(model.customIntent.utf16.count)/160 characters").font(.caption)
                    }
                    TextField("Anything to consider? (optional)", text: $model.prompt, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder).accessibilityLabel("Optional outfit question")
                    Text("\(model.prompt.utf16.count)/1,000 characters").font(.caption).foregroundStyle(StylistTheme.muted)
                }.padding(.top, 12)
            }.stylistCard()
            if !model.validIntent { NoticeView(error: "Use a plain-text custom intent of 1–160 characters and a question no longer than 1,000 characters.") }
            Text("Only this prepared photo is uploaded. Photos are not saved to your reports.").font(.footnote).foregroundStyle(StylistTheme.muted)
            Text(model.bootstrap?.allowance ?? "").font(.footnote)
            NoticeView(error: model.error)
            if let block = model.analysisBlock {
                NoticeView(error: block)
                StylistButton(title: "Refresh access", secondary: true) { Task { await model.refresh() } }
            }
            StylistButton(title: "Analyse outfit", symbol: "sparkles") { model.submit() }
                .disabled(model.photo == nil || model.preparing || !model.validIntent || model.analysisBlock != nil || model.busy)
            StylistButton(title: "Retake photo", symbol: "camera", secondary: true) { Task { await model.navigate(.camera, preserveBrief: true) } }.disabled(model.busy || model.preparing)
            PhotoImportButton(model: model, title: "Choose another photo")
        }
    }
}

struct ProcessingView: View {
    @Bindable var model: AppModel
    var body: some View {
        Page(title: model.submitting ? "Looking at the whole look." : "The assessment did not finish") {
            if model.submitting { ProgressView("Assessing visible details and preparing suggestions…").padding(.vertical, 40) }
            Text("This usually takes a few moments. You can cancel at any time.")
            Text("A request already sent to the AI provider may still count toward your daily allowance.").font(.callout).foregroundStyle(StylistTheme.muted)
            NoticeView(error: model.error)
            if !model.submitting && model.photo != nil {
                StylistButton(title: "Start a new analysis (uses allowance)") { model.submit() }.disabled(model.analysisBlock != nil)
                if let block = model.analysisBlock { Text(block); StylistButton(title: "Refresh access", secondary: true) { Task { await model.refresh() } } }
            }
            StylistButton(title: "Cancel and clear photo", secondary: true) { Task { await model.navigate(.home, preserveBrief: true) } }.disabled(model.busy)
        }
    }
}

struct ResultsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Page(title: model.result?.report == nil ? "A clearer view." : "Your outfit notes.") {
            if let report = model.result?.report {
                ReportView(report: report, feedback: model.suggestionFeedback, busy: model.busy, onFeedback: { index, helpful in Task { await model.sendFeedback(helpful: helpful, suggestion: index) } })
                DisclosureGroup("Share feedback") {
                    VStack(spacing: 12) {
                        StylistButton(title: model.reportFeedbackSent ? "Thanks for your feedback" : "This was helpful", secondary: true) { Task { await model.sendFeedback(helpful: true) } }
                        StylistButton(title: "Report invented details", secondary: true) { Task { await model.sendFeedback(helpful: false) } }
                    }.padding(.top, 12).disabled(model.busy || model.reportFeedbackSent)
                }
                StylistButton(title: model.savedID == nil ? "Save report" : "Saved to history", symbol: model.savedID == nil ? "bookmark" : "bookmark.fill") { Task { await model.saveReport() } }.disabled(model.busy || model.savedID != nil)
                Text("Text only · unsaved reports clear when you leave. Saving is available for 24 hours while this assessment remains open.").font(.footnote).foregroundStyle(StylistTheme.muted)
            } else if let result = model.result {
                ForEach(Array(result.instructions.enumerated()), id: \.offset) { _, instruction in Text(instruction) }
                Text("No rating was produced. This assessment counts toward the daily allowance.").font(.callout).foregroundStyle(StylistTheme.muted)
                StylistButton(title: "Retake this outfit", symbol: "camera") { Task { await model.navigate(.camera, preserveBrief: true) } }.disabled(model.busy)
            }
            NoticeView(error: model.error, notice: model.notice)
            StylistButton(title: "Start a new outfit", secondary: true) { Task { await model.navigate(.camera) } }.disabled(model.busy)
            StylistButton(title: "Saved reports", secondary: true) {
                Task { await model.navigate(.home); model.tab = .saved }
            }.disabled(model.busy)
        }
    }
}
