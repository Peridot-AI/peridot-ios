import SwiftUI

struct AccountView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if let user = store.user {
                    Section {
                        HStack(spacing: 14) {
                            Avatar(name: user.displayName, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: user.displayName).font(.headline).lineLimit(1)
                                if !user.email.isEmpty, user.email != user.displayName {
                                    Text(verbatim: user.email).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    LabeledContent {
                        Text(verbatim: planName(store.limits?.plan ?? store.user?.plan, unlimited: store.limits?.unlimited ?? false))
                    } label: {
                        Text("plan")
                    }
                    if let limits = store.limits, !limits.unlimited {
                        meter(
                            title: "messages_today",
                            value: String(format: String(localized: "used_of"), limits.dailyUsed, limits.dailyLimit),
                            fraction: limits.dailyLimit > 0 ? Double(limits.dailyUsed) / Double(limits.dailyLimit) : 0
                        )
                        meter(
                            title: "monthly_usage",
                            value: String(format: String(localized: "percent_used"), limits.monthlyPercent),
                            fraction: Double(limits.monthlyPercent) / 100
                        )
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button("sign_out", role: .destructive) { confirmSignOut = true }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button("privacy") { openURL(Config.webURL.appendingPathComponent("privacy")) }
                    Button("terms") { openURL(Config.webURL.appendingPathComponent("terms")) }
                }
                .foregroundStyle(Theme.muted)
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(Text(verbatim: "Peridot"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { store.refreshAccount() }
            .confirmationDialog("sign_out_title", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("sign_out", role: .destructive) {
                    store.signOut()
                    dismiss()
                }
                Button("cancel", role: .cancel) {}
            }
        }
    }

    private func meter(title: LocalizedStringKey, value: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                Text(verbatim: value)
            } label: {
                Text(title)
            }
            ProgressView(value: min(max(fraction, 0), 1)).tint(Theme.mint)
        }
        .padding(.vertical, 2)
    }
}
