import SwiftUI

enum StylistTheme {
    static let background = Color(red: 0.969, green: 0.953, blue: 0.925)
    static let surface = Color(red: 1, green: 0.992, blue: 0.98)
    static let ink = Color(red: 0.129, green: 0.114, blue: 0.118)
    static let muted = Color(red: 0.443, green: 0.408, blue: 0.42)
    static let accent = Color(red: 0.455, green: 0.176, blue: 0.259)
    static let line = Color(red: 0.871, green: 0.843, blue: 0.816)
}
struct Page<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title).font(.custom("Georgia", size: 36, relativeTo: .largeTitle)).accessibilityAddTraits(.isHeader)
                content
            }.frame(maxWidth: 600, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }
        .background(StylistTheme.background)
        .foregroundStyle(StylistTheme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(StylistTheme.muted) }
}
struct StylistButton: View {
    let title: String
    var symbol: String? = nil
    var secondary = false
    var destructive = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol { Image(systemName: symbol) }
                Text(title).fontWeight(.semibold)
            }.frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 12)
        }
        .buttonStyle(StylistButtonStyle(secondary: secondary, destructive: destructive))
    }
}
struct StylistButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    let secondary: Bool
    let destructive: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(secondary ? (destructive ? Color.red : StylistTheme.accent) : .white)
            .background(secondary ? StylistTheme.surface : StylistTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(secondary ? StylistTheme.line : .clear))
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}
struct NoticeView: View {
    let error: String?
    var notice: String? = nil
    var body: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red).accessibilityIdentifier("errorMessage")
        }
        if let notice { Label(notice, systemImage: "checkmark.circle").font(.callout).foregroundStyle(StylistTheme.accent) }
    }
}
extension View {
    func stylistCard() -> some View { padding(20).frame(maxWidth: .infinity, alignment: .leading).background(StylistTheme.surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(StylistTheme.line)) }
}
