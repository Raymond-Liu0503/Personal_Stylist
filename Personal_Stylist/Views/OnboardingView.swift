import SwiftUI
import AuthenticationServices

private struct NativeAppleSignInButton: UIViewRepresentable {
    let action: () -> Void
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.cornerRadius = 10
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) { button.isEnabled = context.environment.isEnabled }
}

struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var adult = false
    @State private var consent = false
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        Page(title: "A fresh eye on your outfit.") {
            Eyebrow(text: "Personal Stylist")
            Text("A considered second opinion, with practical changes you can try. For adults in our invited iPhone beta.").font(.title3)
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "sparkles").font(.title).foregroundStyle(StylistTheme.accent)
                Text("Your photo, one assessment").font(.headline)
                Text("Your photo and optional question are sent to our hosting and AI providers for this assessment. We do not save photos or unsaved reports in application storage. Provider processing and retention follow the beta privacy policy.")
                Text("History contains only text reports you choose to save. Cancellation cannot undo processing that already started.").foregroundStyle(StylistTheme.muted)
            }.stylistCard()
            Toggle("I am 18 or older", isOn: $adult).accessibilityIdentifier("adultConsent")
            Toggle("I consent to AI photo processing", isOn: $consent).accessibilityIdentifier("processingConsent")
            Text("Policy \(Contracts.policyVersion). You can withdraw consent in Account.").font(.footnote).foregroundStyle(StylistTheme.muted)
            if !model.config.configured { NoticeView(error: "Add your public Supabase configuration to LocalConfig.plist to open the beta.") }
            NoticeView(error: model.error)
            if model.signedIn {
                if model.bootstrap?.policyVersion != nil && model.bootstrap?.policyVersion != Contracts.policyVersion {
                    Text("This app needs an update to accept the current privacy policy.").foregroundStyle(.red)
                } else {
                    StylistButton(title: "Accept and continue") { Task { await model.acceptConsent() } }
                        .disabled(!adult || !consent || model.busy)
                }
                StylistButton(title: "Refresh account access", secondary: true) { Task { await model.refresh() } }.disabled(model.busy)
            } else {
                NativeAppleSignInButton { Task { await model.appleSignIn() } }.frame(height: 50)
                    .disabled(!adult || !consent || model.busy || !model.config.configured)
                    .opacity(!adult || !consent ? 0.45 : 1)
                if model.config.allowsLocalLogin {
                    DisclosureGroup("Local test login") {
                        VStack(spacing: 12) {
                            TextField("Email", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("testEmail")
                            SecureField("Password", text: $password).textContentType(.password).accessibilityIdentifier("testPassword")
                            StylistButton(title: "Sign in to local backend", secondary: true) {
                                let enteredPassword = password; password = ""
                                Task { await model.localSignIn(email: email, password: enteredPassword) }
                            }.disabled(!adult || !consent || model.busy || email.isEmpty || password.isEmpty || !model.config.configured)
                        }.textFieldStyle(.roundedBorder).padding(.top, 12)
                    }
                }
            }
            if model.busy { ProgressView("Connecting…") }
        }
    }
}
