import AuthenticationServices
import SwiftUI

/// Sign in with Google or with email and password. New email accounts are made on the website
/// (it also has the legal pages); Google sign-in works for any Google account, like on the website.
struct SignInView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var email = ""
    @State private var password = ""
    @FocusState private var field: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool { !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !store.authBusy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    PeridotLogo(size: 44).padding(.top, 24)
                    Text("sign_in_title")
                        .font(.system(size: 26, design: .serif))
                        .multilineTextAlignment(.center)
                        .padding(.top, 18)
                        .padding(.bottom, 28)

                    Button(action: signInWithGoogle) {
                        HStack(spacing: 10) {
                            Image("GoogleLogo")
                                .resizable()
                                .frame(width: 18, height: 18)
                                .accessibilityHidden(true)
                            Text("continue_with_google").fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(Theme.text)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(store.authBusy)

                    HStack(spacing: 12) {
                        Rectangle().fill(Theme.border).frame(height: 1)
                        Text("or").font(.footnote).foregroundStyle(Theme.muted)
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }
                    .padding(.vertical, 18)

                    VStack(spacing: 12) {
                        TextField("email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($field, equals: .email)
                            .onSubmit { field = .password }
                            .fieldStyle()
                        SecureField("password", text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($field, equals: .password)
                            .onSubmit(submit)
                            .fieldStyle()
                    }
                    .onChange(of: email) { store.authError = nil }
                    .onChange(of: password) { store.authError = nil }

                    if let error = store.authError {
                        Text(verbatim: error)
                            .font(.callout)
                            .foregroundStyle(Theme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }

                    Button(action: submit) {
                        Group {
                            if store.authBusy {
                                ProgressView().tint(Theme.onMint)
                            } else {
                                Text("sign_in").fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(Theme.onMint)
                        .background(Theme.mint.opacity(canSubmit || store.authBusy ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canSubmit)
                    .padding(.top, 20)

                    Button("create_account_on_web") { openURL(Config.webURL.appendingPathComponent("signup")) }
                        .font(.subheadline)
                        .foregroundStyle(Theme.mint)
                        .multilineTextAlignment(.center)
                        .padding(.top, 22)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("close"))
                }
            }
        }
        .onDisappear { store.authError = nil }
    }

    private func submit() {
        guard canSubmit else { return }
        Task {
            if await store.signIn(email: email, password: password) { dismiss() }
        }
    }

    private func signInWithGoogle() {
        store.authError = nil
        Task {
            if await store.signInWithGoogle(using: webAuthenticationSession) { dismiss() }
        }
    }
}

private extension View {
    func fieldStyle() -> some View {
        padding(.horizontal, 14)
            .frame(height: 48)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }
}
