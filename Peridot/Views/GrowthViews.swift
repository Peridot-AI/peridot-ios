import SwiftUI
import UIKit

/// The system share sheet for a link (messages, mail, copy…).
struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A URL that can drive `.sheet(item:)`.
struct SharedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// In the account sheet: your invite link and how many friends joined.
struct InviteSection: View {
    @Environment(ChatStore.self) private var store
    @State private var sharing: SharedURL?

    var body: some View {
        Section {
            if let r = store.referrals, let url = URL(string: inviteLink(r.code)) {
                Text(verbatim: String(format: String(localized: "invite_explain"), "\(r.friendPercentOff)%", euros(r.referrerCreditCents)))
                    .font(.subheadline)
                Text(verbatim: url.absoluteString).font(.subheadline).foregroundStyle(Theme.mint)
                Text(verbatim: String(format: String(localized: "invite_stats"), r.invited, r.paid, euros(r.earnedCents)))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Button("share_link") { sharing = SharedURL(url: url) }
            } else {
                ProgressView().tint(Theme.mint)
            }
        } header: {
            Text("invite_friends")
        }
        .onAppear { store.loadReferrals() }
        .sheet(item: $sharing) { ActivitySheet(url: $0.url).presentationDetents([.medium]) }
    }
}

/// Pick a plan and pay on the website's checkout in the browser, signed in for this account (the terms are
/// accepted there). Back in the app the account is reloaded, and an alert says when the plan is active.
struct UpgradeView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = "plus"
    @State private var busy = false

    private var paid: Bool { (store.user?.plan ?? store.limits?.plan ?? "free") != "free" }

    var body: some View {
        NavigationStack {
            List {
                if paid && !store.awaitingPlan {
                    Text("already_paid").foregroundStyle(Theme.muted).listRowBackground(Theme.surface)
                } else if store.awaitingPlan {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView().tint(Theme.mint)
                            Text("finish_payment")
                        }
                        Button("check_again") { store.refreshAccount() }
                    }
                    .listRowBackground(Theme.surface)
                } else if let config = store.plans {
                    Section {
                        ForEach(config.plans) { plan in
                            Button { selected = plan.id } label: { planRow(plan) }
                                .listRowBackground(selected == plan.id ? Theme.surfaceHigh : Theme.surface)
                        }
                    }
                    if let off = store.offer?.friendPercentOff {
                        Text(verbatim: String(format: String(localized: "friend_discount"), off))
                            .font(.subheadline)
                            .foregroundStyle(Theme.mint)
                            .listRowBackground(Theme.surface)
                    }
                    Section {
                        Button(action: pay) {
                            Text(buttonTitle(config))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(Theme.onMint)
                        }
                        .disabled(busy || !config.enabled)
                        .listRowBackground(Theme.mint.opacity(config.enabled ? 1 : 0.4))
                    } footer: {
                        Text("payment_in_browser")
                    }
                } else {
                    ProgressView().tint(Theme.mint).frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(Text("upgrade_plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
            }
            .onAppear { store.loadPlans() }
            // Back from the payment page in the browser: see whether the plan is active yet
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, store.awaitingPlan { store.refreshAccount() }
            }
            .onChange(of: store.awaitingPlan) { _, waiting in
                if !waiting, paid { dismiss() }
            }
        }
    }

    private func buttonTitle(_ config: CheckoutConfig) -> LocalizedStringKey {
        if !config.enabled { return "payments_off" }
        return store.offer?.trial?.plan == selected ? "start_free_trial" : "continue_to_payment"
    }

    private func planRow(_ plan: CheckoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: plan.name.replacingOccurrences(of: "Peridot ", with: "")).font(.headline)
                Spacer()
                Text(verbatim: String(format: String(localized: "per_month"), euros(plan.amountCents))).font(.headline)
                if selected == plan.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint) }
            }
            if let trial = store.offer?.trial, trial.plan == plan.id {
                Text(verbatim: String(format: String(localized: "free_trial_days"), trial.days))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.onMint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.mint, in: Capsule())
            }
            Text(blurb(plan.id)).font(.subheadline).foregroundStyle(Theme.muted)
            if let n = plan.dailyMessages {
                Text(verbatim: String(format: String(localized: "messages_per_day"), n)).font(.subheadline)
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.vertical, 4)
    }

    private func blurb(_ id: String) -> LocalizedStringKey {
        switch id {
        case "plus": return "plan_plus_blurb"
        case "extended": return "plan_extended_blurb"
        default: return "plan_extended10_blurb"
        }
    }

    private func pay() {
        busy = true
        Task {
            if let url = await store.checkout(plan: selected) { openURL(url) }
            busy = false
        }
    }
}
