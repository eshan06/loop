import SwiftUI

@MainActor struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var error: String?
    @State private var isLoading = false
    @FocusState private var focused: Bool
    @State private var useMocks = APIConfig.useMocks

    private var trimmed: String { email.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Theme.Space.m) {
                Wordmark(size: 52, highlight: true)
                Text("Swap, give, and donate clothes\non your campus.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                TextField("Email", text: $email, prompt: Text(verbatim: "you@school.edu").foregroundColor(Color(uiColor: .placeholderText)))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($focused)
                    .onSubmit(submit)
                    .padding(.horizontal, Theme.Space.m)
                    .frame(height: 52)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                            .strokeBorder(error == nil ? Color.clear : Theme.destructive, lineWidth: 1)
                    }
                    .onChange(of: email) { error = nil }

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.destructive)
                        .transition(.opacity)
                }

                PrimaryButton(title: "Continue", isLoading: isLoading, isEnabled: !trimmed.isEmpty, action: submit)
                    .padding(.top, Theme.Space.xs)

                Text("Use your college .edu email. Loop only shows you people on your campus.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.Space.xs)

                #if DEBUG
                demoAccounts
                #endif
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.bottom, Theme.Space.l)
        }
        .background(Theme.background)
        .animation(.snappy, value: error)
        .sensoryFeedback(.warning, trigger: error) { _, new in new != nil }
    }

    #if DEBUG
    private var demoAccounts: some View {
        VStack(spacing: Theme.Space.xs) {
            Picker("Server", selection: $useMocks) {
                Text("Mock data").tag(true)
                Text("Live server").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("serverMode")
            .onChange(of: useMocks) { _, value in
                APIConfig.setUseMocks(value)
                error = nil
            }
            Text("Demo accounts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            HStack(spacing: Theme.Space.xs) {
                ForEach(DemoAccounts.all, id: \.email) { account in
                    Chip(title: account.label) {
                        email = account.email
                        submit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.m)
    }
    #endif

    private func submit() {
        let address = trimmed.lowercased()
        guard !address.isEmpty, !isLoading else { return }
        guard address.contains("@"), address.hasSuffix(".edu") else {
            error = "Use your college .edu email address."
            return
        }
        focused = false
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await session.signIn(email: address)
            } catch {
                self.error = error.userMessage
            }
        }
    }
}

#Preview {
    SignInView().environment(SessionStore())
}
