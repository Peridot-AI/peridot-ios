import SwiftUI

/// The chat list (signed in), with a new-chat button and the account at the bottom.
struct HistoryView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSignIn: () -> Void
    let onAccount: () -> Void

    @State private var renaming: Conversation?
    @State private var newTitle = ""
    @State private var deleting: Conversation?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        store.newChat()
                        dismiss()
                    } label: {
                        Label("new_chat", systemImage: "square.and.pencil").foregroundStyle(Theme.mint)
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    if !store.signedIn {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("history_signed_out").font(.subheadline).foregroundStyle(Theme.muted)
                            Button("sign_in", action: onSignIn)
                                .buttonStyle(.borderedProminent)
                                .foregroundStyle(Theme.onMint)
                        }
                        .padding(.vertical, 6)
                    } else if store.conversations.isEmpty {
                        Text("no_chats").foregroundStyle(Theme.muted)
                    } else {
                        ForEach(store.conversations) { conversation in
                            row(conversation)
                        }
                    }
                } header: {
                    Text("chats")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(Text(verbatim: "Peridot"))
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { store.loadConversations() }
            .safeAreaInset(edge: .bottom) { accountBar }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("close"))
                }
            }
        }
        .alert("rename_chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(text: $newTitle) { Text(verbatim: renaming?.title ?? "") }
            Button("save") {
                if let renaming { store.rename(renaming, to: newTitle) }
            }
            Button("cancel", role: .cancel) {}
        }
        .alert("delete_chat", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("delete", role: .destructive) {
                if let deleting { store.delete(deleting) }
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text(verbatim: String(format: String(localized: "delete_chat_text"), deleting?.title ?? ""))
        }
    }

    private func row(_ conversation: Conversation) -> some View {
        Button {
            store.open(conversation)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: conversation.title.isEmpty ? String(localized: "untitled") : conversation.title)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                let time = ago(conversation.updatedAt)
                if !time.isEmpty {
                    Text(verbatim: time).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .listRowBackground(conversation.id == store.conversationID ? Theme.surfaceHigh : Theme.surface)
        .swipeActions {
            Button("delete", role: .destructive) { deleting = conversation }
            Button("rename") { newTitle = conversation.title; renaming = conversation }
                .tint(Theme.muted)
        }
        .contextMenu {
            Button { newTitle = conversation.title; renaming = conversation } label: { Label("rename", systemImage: "pencil") }
            Button(role: .destructive) { deleting = conversation } label: { Label("delete", systemImage: "trash") }
        }
    }

    private var accountBar: some View {
        Button(action: store.signedIn ? onAccount : onSignIn) {
            HStack(spacing: 12) {
                if let user = store.user {
                    Avatar(name: user.displayName)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: user.displayName).foregroundStyle(Theme.text).lineLimit(1)
                        Text(verbatim: planName(store.limits?.plan ?? user.plan, unlimited: store.limits?.unlimited ?? false))
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("sign_in").foregroundStyle(Theme.mint)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.surface)
        }
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }
}
