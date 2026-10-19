import SwiftUI

struct HistoryView: View {
    @Bindable var model: AppModel
    var body: some View {
        Page(title: "Saved reports.") {
            Text("Text only. Photos are never saved to your history.").foregroundStyle(StylistTheme.muted)
            NoticeView(error: model.error)
            if model.history.isEmpty && !model.historyLoading { ContentUnavailableView("Your notes, collected.", systemImage: "bookmark", description: Text("Reports you choose to save will appear here.")) }
            ForEach(model.history) { item in
                NavigationLink {
                    SavedReportDetail(model: model, item: item)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Eyebrow(text: item.dateLabel); Spacer(); Text("\(item.report.rating) / 10").font(.headline).foregroundStyle(StylistTheme.accent) }
                        Text(item.report.summary).lineLimit(3).foregroundStyle(StylistTheme.ink)
                        Label("View assessment", systemImage: "arrow.right").font(.footnote)
                    }.stylistCard()
                }.buttonStyle(.plain)
            }
            if model.historyLoading { ProgressView("Loading your reports…") }
            if model.historyCursor != nil { StylistButton(title: "Load older reports", secondary: true) { Task { await model.loadHistory(older: true) } }.disabled(model.historyLoading) }
            StylistButton(title: "Refresh history", secondary: true) { Task { await model.loadHistory() } }.disabled(model.historyLoading)
        }
        .task { if model.tab == .saved { await model.loadHistory() } }
        .refreshable { await model.loadHistory() }
    }
}
struct SavedReportDetail: View {
    @Bindable var model: AppModel
    let item: SavedReport
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Page(title: "Your outfit notes.") {
            Eyebrow(text: item.dateLabel)
            ReportView(report: item.report)
            NoticeView(error: model.error)
            StylistButton(title: "Delete report", symbol: "trash", secondary: true, destructive: true) { confirmDelete = true }.disabled(model.busy)
        }
        .confirmationDialog("Delete saved report?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete report", role: .destructive) {
                Task {
                    await model.deleteReport(item.id)
                    if !model.history.contains(where: { $0.id == item.id }) { dismiss() }
                }
            }
            Button("Keep report", role: .cancel) { }
        } message: { Text("This removes the saved text assessment.") }
    }
}

struct AccountView: View {
    @Bindable var model: AppModel
    @State private var style = ""
    @State private var constraints = ""
    @State private var confirmDeletion = false
    @State private var confirmWithdrawal = false
    var body: some View {
        Page(title: "Your account.") {
            Eyebrow(text: "Personal Stylist")
            VStack(alignment: .leading, spacing: 8) {
                Text("Your allowance").font(.headline)
                Text(model.bootstrap?.allowance ?? "Refresh account access to check your allowance.")
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Style preferences").font(.headline)
                Text("Preferences are optional and can be used as explicit context for future assessments.").font(.callout).foregroundStyle(StylistTheme.muted)
                TextField("Preferred style (optional)", text: $style, axis: .vertical).accessibilityLabel("Preferred style")
                TextField("Constraints, one per line (optional)", text: $constraints, axis: .vertical).lineLimit(3...10).accessibilityLabel("Styling constraints, one per line")
                Text("Up to 160 characters per entry and 10 constraints.").font(.caption).foregroundStyle(StylistTheme.muted)
                StylistButton(title: "Save preferences") { Task { await model.savePreferences(style: style, constraints: constraints) } }.disabled(model.busy)
            }.textFieldStyle(.roundedBorder)
            DisclosureGroup("Privacy and consent") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Only reports you explicitly save are stored in history. Operational records contain no photos, prompts, or report content and are retained for 30 days. Hosting and AI-provider retention requires separate review.")
                    Text("Policy \(Contracts.policyVersion) · \(model.bootstrap?.hasConsent == true ? "Accepted" : "Not accepted")").font(.footnote)
                    StylistButton(title: "Withdraw AI-processing consent", secondary: true) { confirmWithdrawal = true }.disabled(model.busy || model.bootstrap?.hasConsent != true)
                }.padding(.top, 12)
            }
            NoticeView(error: model.error, notice: model.notice)
            if model.busy { ProgressView() }
            StylistButton(title: "Sign out", secondary: true) { Task { await model.signOut() } }.disabled(model.busy)
            StylistButton(title: "Delete account", secondary: true, destructive: true) { confirmDeletion = true }.disabled(model.busy)
        }
        .onAppear { style = model.bootstrap?.profile.desiredStyle ?? ""; constraints = model.bootstrap?.profile.constraints?.joined(separator: "\n") ?? "" }
        .confirmationDialog("Delete your account?", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await model.deleteAccount() } }
            Button("Keep account", role: .cancel) { }
        } message: { Text("This deletes your saved reports and profile. Apple will ask you to authorize again. Local email test accounts cannot complete Apple account deletion.") }
        .confirmationDialog("Withdraw consent?", isPresented: $confirmWithdrawal, titleVisibility: .visible) {
            Button("Withdraw consent", role: .destructive) { Task { await model.withdrawConsent() } }
            Button("Keep consent", role: .cancel) { }
        } message: { Text("Current photos and unsaved results will be cleared. Processing that already started cannot be undone.") }
    }
}
