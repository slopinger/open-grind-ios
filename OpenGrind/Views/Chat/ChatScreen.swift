import OpenGrindKit
import SwiftUI

/// A conversation with one profile.
struct ChatScreen: View {
    let profileID: ProfileID

    @Environment(AccountSession.self) private var session

    var body: some View {
        let conversation = session.inbox.conversation(Conversation.id(between: session.profileID, and: profileID))
        ChatContent(chat: session.chat(with: profileID, name: conversation?.name), conversation: conversation)
    }
}

private struct ChatContent: View {
    @Bindable var chat: ChatModel
    let conversation: Conversation?

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isComposerFocused: Bool
    @State private var viewer: ViewerItem?
    /// On screen, not covered by a pushed profile.
    @State private var isVisible = false

    private var name: String {
        chat.name ?? chat.profile?.name ?? conversation?.name ?? String(localized: "Chat")
    }

    var body: some View {
        content
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { titleButton }
            }
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatComposer(chat: chat, isFocused: $isComposerFocused)
            }
            .task { await chat.loadIfNeeded() }
            .onAppear {
                isVisible = true
                chat.appeared()
            }
            .onDisappear {
                isVisible = false
                chat.disappeared()
            }
            .onChange(of: scenePhase) { _, phase in
                guard isVisible else { return }
                if phase == .active {
                    chat.appeared()
                    Task { await chat.reload() }
                } else {
                    chat.disappeared()
                }
            }
            .fullScreenCover(item: $viewer) { item in
                PhotoViewer(urls: [item.url], selection: 0)
                    .environment(\.cachesImages, !item.isViewOnce)
            }
            .failureAlert($chat.actionFailure)
    }

    private var content: some View {
        LoadStateView(chat.state, isEmpty: chat.items.isEmpty) {
            await chat.reload()
        } content: {
            if chat.items.isEmpty && !chat.isOtherTyping {
                ContentUnavailableView {
                    Label("Say Hi", systemImage: "hand.wave")
                } description: {
                    Text("Send \(name) a message to start the conversation.")
                }
            } else {
                transcript
            }
        }
    }

    private var titleButton: some View {
        NavigationLink(value: Route.profile(chat.otherProfileID, fromChat: true)) {
            HStack(spacing: 8) {
                Avatar(
                    photoHash: chat.profile?.photoHash ?? conversation?.participant?.photoHash, size: 30,
                    isOnline: chat.profile?.isOnline() ?? conversation?.participant?.isOnline() ?? false)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                    if chat.isOtherTyping {
                        Text("typing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let distance = Formatting.distance(
                        chat.profile?.distance ?? conversation?.participant?.distance)
                    {
                        Text(distance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel(name)
        .accessibilityHint("Shows the profile.")
    }

    private var transcript: some View {
        // Read once per update: each row needs its neighbours and the read receipt.
        let items = chat.items
        let lastReadOutgoingID = chat.lastReadOutgoingID
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if chat.didFailLoadingOlder {
                        Button("Load Earlier Messages") { Task { await chat.loadOlder() } }
                            .padding()
                    } else if chat.hasOlderMessages {
                        ProgressView()
                            .padding()
                            .task { await chat.loadOlder() }
                            .accessibilityLabel("Loading earlier messages")
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let previous = index > 0 ? items[index - 1] : nil
                        let next = index + 1 < items.count ? items[index + 1] : nil
                        if previous.map({
                            !Calendar.current.isDate($0.message.date, inSameDayAs: item.message.date)
                        })
                            ?? true
                        {
                            Text(Formatting.daySeparator(item.message.date))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 16)
                                .padding(.bottom, 6)
                                .accessibilityAddTraits(.isHeader)
                        }
                        MessageRow(
                            chat: chat, item: item,
                            startsGroup: previous.map { $0.message.senderID != item.message.senderID } ?? true,
                            endsGroup: next.map {
                                $0.message.senderID != item.message.senderID
                                    || $0.message.date.timeIntervalSince(item.message.date) > 600
                            } ?? true,
                            showsReadReceipt: item.id == lastReadOutgoingID,
                            openImage: { viewer = ViewerItem(url: $0, isViewOnce: $1) }
                        )
                        .id(item.id)
                    }
                    if chat.isOtherTyping {
                        TypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                            .id("typing")
                            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottomLeading)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .animation(.default, value: chat.isOtherTyping)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.items.last?.id) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            }
            .onChange(of: chat.isOtherTyping) { _, isTyping in
                if isTyping { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
            .onChange(of: isComposerFocused) { _, isFocused in
                if isFocused, let id = chat.items.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }
}

private struct ViewerItem: Identifiable {
    var url: URL
    var isViewOnce: Bool
    var id: URL { url }
}

/// Three dots that pulse while the other side is typing.
private struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 3
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .frame(width: 7, height: 7)
                        .opacity(reduceMotion ? 0.6 : 0.35 + 0.65 * max(0, sin(phase - Double(index) * 0.7)))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemFill), in: .capsule)
        }
        .accessibilityElement()
        .accessibilityLabel("Typing")
    }
}
