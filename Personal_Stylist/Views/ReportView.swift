import SwiftUI

struct ReportView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let report: OutfitReport
    var feedback: [Int: Bool] = [:]
    var busy = false
    var onFeedback: ((Int, Bool) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            let scoreLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
            scoreLayout {
                Text(report.rating).font(.custom("Georgia", size: 56, relativeTo: .largeTitle)).foregroundStyle(StylistTheme.accent)
                    .accessibilityLabel(report.overallScore == nil ? "Rating unavailable" : "Rating \(report.rating) out of 10")
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: report.overallScore == nil ? "Unrated" : "Out of 10")
                    Text(report.verdictLabel).font(.headline)
                }
            }
            Text(report.summary).font(.title3)
            if report.status == "partial" { Label("Partial assessment · some details could not be assessed.", systemImage: "circle.lefthalf.filled").font(.callout).foregroundStyle(StylistTheme.accent) }
            if let first = report.suggestions.first {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(text: "Best next move")
                    Text(first.action).font(.title3.weight(.medium))
                    DisclosureGroup("Why this works") { suggestionDetails(first, index: 0).padding(.top, 12) }
                }.stylistCard()
            }
            if report.suggestions.count > 1 {
                Eyebrow(text: "More ways to wear it")
                ForEach(Array(report.suggestions.dropFirst().enumerated()), id: \.offset) { offset, suggestion in
                    DisclosureGroup("Option \(offset + 2) · \(suggestion.action)") { suggestionDetails(suggestion, index: offset + 1).padding(.top, 12) }
                }
            }
            if !report.strengths.isEmpty {
                DisclosureGroup("What works") {
                    ForEach(Array(report.strengths.enumerated()), id: \.offset) { _, text in
                        Label(text, systemImage: "checkmark").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                }
            }
            if !report.limitations.isEmpty {
                DisclosureGroup("Limitations (\(report.limitations.count))") {
                    ForEach(Array(report.limitations.enumerated()), id: \.offset) { _, value in Text(value).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6) }
                }
            }
            DisclosureGroup("Criteria") {
                ForEach(report.criteria) { criterion in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(criterion.id.capitalized) · \(criterion.applicable ? criterion.score.map { "\($0) / 5" } ?? "Not visible" : "Not applicable")").font(.headline)
                        Text(criterion.observation)
                        Text(criterion.explanation).foregroundStyle(StylistTheme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                }
            }
        }
    }
    @ViewBuilder private func suggestionDetails(_ suggestion: Suggestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.observation).foregroundStyle(StylistTheme.muted)
            Text(suggestion.reason)
            if let onFeedback, index < 3 {
                if let sent = feedback[index] { Label(sent ? "Marked helpful" : "Marked not for me", systemImage: "checkmark.circle").font(.footnote) }
                else {
                    HStack {
                        Button("Helpful", systemImage: "hand.thumbsup") { onFeedback(index, true) }
                        Spacer()
                        Button("Not for me", systemImage: "hand.thumbsdown") { onFeedback(index, false) }
                    }.buttonStyle(.bordered).disabled(busy)
                }
            }
        }
    }
}
