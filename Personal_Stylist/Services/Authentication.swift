import Foundation
import Security
import AuthenticationServices
import CryptoKit
import UIKit

struct AppleCredential {
    let token: String
    let code: String
    let nonce: String
}
@MainActor final class AppleAuthorization: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleCredential, Error>?
    private var nonce = ""
    private var controller: ASAuthorizationController?
    func authorize() async throws -> AppleCredential {
        guard continuation == nil else { throw StylistError.message("Apple sign-in is already open.") }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw StylistError.message("Secure sign-in could not start.") }
        nonce = bytes.map { String(format: "%02x", $0) }.joined()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller; controller.delegate = self; controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { continuation = nil; self.controller = nil; nonce = "" }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
              let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) else {
            continuation?.resume(throwing: StylistError.message("Apple did not return a complete authorization. Please retry.")); return
        }
        continuation?.resume(returning: AppleCredential(token: token, code: code, nonce: nonce))
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        continuation?.resume(throwing: cancelled ? CancellationError() : StylistError.message("Apple sign-in could not finish. Please retry."))
        continuation = nil; self.controller = nil; nonce = ""
    }
}
