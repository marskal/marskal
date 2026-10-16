import AuthenticationServices
import MarskalKit
import SwiftUI

/// The first screen: the server's address, and the system's web sheet for
/// the server's own sign-in and consent pages (ADR 0029).
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var address = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server address", text: $address, prompt: Text(verbatim: "marskal.example"))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(signIn)
                } header: {
                    Text("Server")
                } footer: {
                    Text("The address you open Marskal at in a browser.")
                }

                Section {
                    Button(action: signIn) {
                        HStack {
                            Text("Sign In")
                            if model.signingIn {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || model.signingIn)
                }
            }
            .navigationTitle(Text(verbatim: "Marskal"))
        }
        .onAppear {
            if address.isEmpty { address = Self.defaultAddress }
        }
    }

    private func signIn() {
        Task {
            await model.signIn(address: address) { url in
                try await webAuthenticationSession.authenticate(
                    using: url,
                    callback: .customScheme(OAuthClient.callbackScheme),
                    preferredBrowserSession: .shared,
                    additionalHeaderFields: [:]
                )
            }
        }
    }

    // The dev server (web/, `devenv up`) in debug builds.
    #if DEBUG
    static let defaultAddress = "http://marskal.localhost:8275"
    #else
    static let defaultAddress = ""
    #endif
}
