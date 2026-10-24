import SwiftUI
import UIKit

struct ChatView: View {
    @Environment(ChatStore.self) private var store
    @State private var input = ""
    @State private var showHistory = false
    @State private var showModels = false
    @State private var showAccount = false
    @State private var showSignIn = false
    @State private var showShare = false
    @State private var sharing: SharedURL?
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if store.loadingConversation {
                        ProgressView().tint(Theme.mint).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if store.messages.isEmpty {
                        EmptyState().frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { composerFocused = false }
                    } else {
                        MessageList(messages: store.messages, onRetry: store.retry)
                    }
                }
                Composer(text: $input, focused: $composerFocused, streaming: store.streaming, onSend: send, onStop: store.stop)
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if store.signedIn { store.loadConversations() }
                        showHistory = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel(Text("open_menu"))
                }
                ToolbarItem(placement: .principal) {
                    Button { showModels = true } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: store.currentModel?.name ?? "Peridot")
                                .font(.headline)
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityHint(Text("choose_model"))
                }
                if store.signedIn, store.conversationID != nil, !store.messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.loadShare()
                            showShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(Text("share_chat"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.newChat() } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(store.messages.isEmpty && store.conversationID == nil)
                    .accessibilityLabel(Text("new_chat"))
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(
                onSignIn: { showHistory = false; showSignIn = true },
                onAccount: { showHistory = false; showAccount = true }
            )
        }
        .sheet(isPresented: $showModels) {
            ModelPickerView().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAccount) {
            AccountView().presentationDetents([.medium, .large])
        }
        .confirmationDialog("share_chat", isPresented: $showShare, titleVisibility: .visible) {
            Button(store.share == nil ? "share_link" : "update_link") {
                Task { if let url = await store.shareChat() { sharing = SharedURL(url: url) } }
            }
            if store.share != nil {
                Button("stop_sharing", role: .destructive) { store.stopSharing() }
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("share_explain")
        }
        .sheet(item: $sharing) { ActivitySheet(url: $0.url).presentationDetents([.medium]) }
        .fullScreenCover(isPresented: $showSignIn) {
            SignInView()
        }
        .alert(
            store.notice ?? "",
            isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private func send() {
        if store.send(input) { input = "" }
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 20) {
            PeridotLogo(size: 44)
            Text("empty_title")
                .font(.system(size: 26, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.text)
        }
        .padding(32)
    }
}

private struct MessageList: View {
    let messages: [ChatMessage]
    let onRetry: () -> Void
    /// Follow the answer while it streams, until the user scrolls up to read; back at the bottom, follow again.
    @State private var follow = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(messages) { message in
                        if message.role == .user {
                            UserBubble(text: message.text)
                        } else {
                            ModelMessage(message: message, isLast: message.id == messages.last?.id, onRetry: onRetry)
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                        .onAppear { follow = true }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(DragGesture().onChanged { drag in
                if drag.translation.height > 0 { follow = false }
            })
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: messages.count) {
                if messages.last?.streaming == true { follow = true }
                if follow { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: messages.last?.text) {
                if follow { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: messages.last?.error) {
                if follow { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
    }
}

private struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(verbatim: text)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 20))
                .contextMenu {
                    Button { UIPasteboard.general.string = text } label: { Label("copy", systemImage: "doc.on.doc") }
                }
        }
    }
}

private struct ModelMessage: View {
    let message: ChatMessage
    let isLast: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.text.isEmpty && message.streaming {
                PeridotLogo(size: 22, thinking: true).padding(.vertical, 4)
            } else if !message.text.isEmpty {
                MarkdownView(text: message.text)
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
            }
            if let error = message.error {
                Text(verbatim: error).font(.callout).foregroundStyle(Theme.error)
                if isLast {
                    Button("retry", action: onRetry).foregroundStyle(Theme.mint)
                }
            } else if !message.streaming && !message.text.isEmpty {
                Button {
                    UIPasteboard.general.string = message.text
                } label: {
                    Label("copy", systemImage: "doc.on.doc").font(.footnote)
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Composer: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let streaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("message_hint", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .focused(focused)
                .foregroundStyle(Theme.text)
                .padding(.vertical, 9)
            Button(action: streaming ? onStop : onSend) {
                Group {
                    if streaming {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.onMint).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(canSend ? Theme.onMint : Theme.muted)
                    }
                }
                .frame(width: 38, height: 38)
                .background(streaming || canSend ? Theme.mint : Theme.surfaceHigh, in: Circle())
            }
            .disabled(!streaming && !canSend)
            .accessibilityLabel(Text(streaming ? LocalizedStringKey("stop") : LocalizedStringKey("send")))
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Theme.border))
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}
