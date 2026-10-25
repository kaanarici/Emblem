import SwiftUI
import UIKit
import EmblemCore

struct WritingBlockView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let block: WritingBlock
    @Environment(\.renderedPage) private var page
    @Environment(ConversationStore.self) private var store
    @State private var editing: WritingBlock.Draft?
    @State private var copied: UUID?
    @State private var selectedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title = block.title, !title.isEmpty {
                Text(title).font(Theme.cardTitle()).padding(.horizontal, Theme.contentMargin)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(block.drafts) { draft in
                        draftCard(draft)
                            .containerRelativeFrame(.horizontal) { width, _ in
                                block.drafts.count == 1 ? width : width - 24
                            }
                            .id(draft.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Theme.contentMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $selectedID)
            .scrollClipDisabled()
        }
        .foregroundStyle(Theme.ink)
        .overlay(alignment: .top) { WritingCopyToast(trigger: $copied) }
        .fullScreenCover(item: $editing, onDismiss: { store.isEditingWriting = false }) { draft in
            WritingEditor(draft: draft, origin: page?.origin ?? .apple) { body in
                guard blockInteraction.allowsStoreMutation else { throw CancellationError() }
                guard let page else { throw URLError(.cannotWriteToFile) }
                try await store.saveWritingDraft(
                    page: page, blockID: block.id, draftID: draft.id,
                    previousBody: draft.body, body: body)
            }
            .onAppear { store.isEditingWriting = true }
        }
    }

    private func draftCard(_ draft: WritingBlock.Draft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: draft.sym ?? "text.alignleft")
                    .font(.system(size: 21))
                    .accessibilityHidden(true)
                Text(draft.label).font(.system(.subheadline, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    guard blockInteraction.allowsActivation else { return }
                    copied = UUID()
                    UIPasteboard.general.string = draft.body
                } label: {
                    Image(systemName: "square.on.square").frame(width: 44, height: 44).contentShape(
                        Rectangle())
                }
                .blockActivationControl()
                .accessibilityLabel("Copy \(draft.label) draft")
                ShareLink(item: draft.body) {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .blockActivationControl()
                .accessibilityLabel("Share \(draft.label) draft")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            Divider().opacity(0.35)
            Text(draft.body)
                .font(.body)
                .lineSpacing(4)
                .blockActivationTextSelection()
                .blockActivationLinks()
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("draft-body-\(draft.id)")
            Button {
                guard blockInteraction.allowsActivation else { return }
                editing = draft
            } label: {
                Text("Edit").font(.system(.subheadline, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .blockActivationControl()
            .accessibilityLabel("Edit \(draft.label) draft")
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.045), radius: 8, y: 4)
    }
}

private struct WritingCopyToast: View {
    @Binding var trigger: UUID?
    @State private var isPresented = false

    var body: some View {
        Group {
            if isPresented {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(.subheadline, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Theme.accentDark, in: Capsule())
                    .foregroundStyle(Theme.onAccent)
                    .accessibilityIdentifier("writing-copy-toast")
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.success, trigger: trigger) { _, new in new != nil }
        .task(id: trigger) {
            guard trigger != nil else {
                isPresented = false
                return
            }
            isPresented = true
            UIAccessibility.post(notification: .announcement, argument: "Copied")
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            isPresented = false
            trigger = nil
        }
        .onDisappear {
            isPresented = false
            trigger = nil
        }
    }
}

private struct WritingEditor: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let draft: WritingBlock.Draft
    let origin: GeneratedPage.Origin
    var onSave: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var text: String
    @State private var proposal: String?
    @State private var isRewriting = false
    @State private var isSaving = false
    @State private var hasAcceptedRewrite = false
    @State private var error: String?
    @State private var copied: UUID?
    @State private var showDiscard = false
    @State private var showDiscardChanges = false
    @State private var rewriteTask: Task<Void, Never>?

    init(
        draft: WritingBlock.Draft, origin: GeneratedPage.Origin,
        onSave: @escaping (String) async throws -> Void
    ) {
        self.draft = draft
        self.origin = origin
        self.onSave = onSave
        _text = State(initialValue: draft.body)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Theme.background.ignoresSafeArea().allowsHitTesting(false)
                TextEditor(
                    text: Binding(
                        get: { text },
                        set: { value in
                            guard proposal == nil, !isSaving else { return }
                            guard value.utf16.count <= 20000 else {
                                error = "Drafts can contain up to 20,000 characters."
                                return
                            }
                            text = value
                        })
                )
                .font(.body)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 15)
                .padding(.top, 10)
                .focused($focused)
                .opacity(proposal == nil ? 1 : 0)
                .accessibilityHidden(proposal != nil)
                .accessibilityIdentifier("writing-editor")
                .disabled(isSaving)
                if let proposal {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if isRewriting {
                                Text(text).strikethrough()
                                    .foregroundStyle(Theme.inkSecondary.opacity(0.6))
                            }
                            if !proposal.isEmpty {
                                Text(proposal)
                                    .foregroundStyle(.blue)
                                    .padding(8)
                                    .background(
                                        .blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6)
                                    )
                                    .accessibilityIdentifier("writing-proposal")
                            }
                            if isRewriting {
                                ProgressView("Rewriting…")
                                    .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                            }
                        }
                        .font(.body).lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                    }
                }
            }
            .foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        close()
                    } label: {
                        if isSaving { ProgressView() } else { Image(systemName: "xmark") }
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Close editor")
                    .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        guard blockInteraction.allowsActivation else { return }
                        UIPasteboard.general.string = text
                        copied = UUID()
                    } label: {
                        Image(systemName: "square.on.square")
                    }
                    .blockActivationControl()
                    .accessibilityLabel("Copy draft")
                    .disabled(proposal != nil || isSaving)
                    ShareLink(item: text) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .blockActivationControl()
                    .accessibilityLabel("Share draft")
                    .disabled(proposal != nil || isSaving)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
            .overlay(alignment: .top) { WritingCopyToast(trigger: $copied) }
            .alert(
                "Discard the proposed rewrite?", isPresented: $showDiscard
            ) {
                Button("Discard rewrite", role: .destructive) {
                    cancelRewrite()
                    close()
                }
                Button("Keep reviewing", role: .cancel) {}
            }
            .alert(
                "Discard your changes?", isPresented: $showDiscardChanges
            ) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .interactiveDismissDisabled()
            .onDisappear { rewriteTask?.cancel() }
        }
    }

    private var bottomControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error {
                Text(error).font(.footnote).foregroundStyle(Theme.negative)
                    .accessibilityIdentifier("writing-error")
                if text != draft.body, proposal == nil {
                    Button("Discard changes", role: .destructive) { showDiscardChanges = true }
                        .frame(minHeight: 44)
                }
            }
            if proposal != nil {
                HStack(spacing: 20) {
                    Button(role: .cancel, action: cancelRewrite) {
                        Text("Cancel").frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("writing-cancel")
                    if !isRewriting {
                        Button {
                            guard blockInteraction.allowsActivation else { return }
                            acceptRewrite()
                        } label: {
                            Label("Accept", systemImage: "checkmark").frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .blockActivationControl()
                        .accessibilityIdentifier("writing-accept")
                    }
                    Spacer()
                }
                .font(.system(.subheadline, weight: .medium))
                .frame(minHeight: 44)
            } else if origin == .apple {
                Text(WritingClient.Failure.appleOrigin.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.vertical, 8)
            } else if OnDeviceModel.selection() != .emblem {
                Text(WritingClient.Failure.appleMode.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.style) { suggestion in
                            Button {
                                guard blockInteraction.allowsStoreMutation else { return }
                                rewrite(style: suggestion.style)
                            } label: {
                                Label(suggestion.title, systemImage: suggestion.symbol)
                                    .font(.system(.subheadline, weight: .medium))
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .background(
                                        Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .blockStoreMutationControl()
                            .disabled(
                                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || isSaving)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Theme.background)
    }

    private var suggestions: [(style: String, title: String, symbol: String)] {
        hasAcceptedRewrite
            ? [
                ("shorter", "Shorter", "scissors"), ("casual", "More casual", "bubble"),
                ("direct", "More direct", "arrow.up.right"),
            ]
            : [
                ("bolder", "Bolder", "bold"), ("crisper", "Crisper", "scissors"),
                ("playful", "More playful", "sparkles"),
            ]
    }

    private func rewrite(style: String) {
        guard blockInteraction.allowsStoreMutation else { return }
        error = nil
        focused = true
        proposal = ""
        isRewriting = true
        let source = text
        rewriteTask = Task {
            do {
                let result = try await WritingClient.rewrite(body: source, style: style, origin: origin) {
                    proposal = $0
                }
                try Task.checkCancellation()
                proposal = result
                isRewriting = false
            } catch {
                guard !Task.isCancelled else { return }
                proposal = nil
                isRewriting = false
                self.error =
                    (error as? WritingClient.Failure)?.errorDescription
                    ?? "The rewrite couldn't finish. Your draft is unchanged. Try again."
            }
        }
    }

    private func cancelRewrite() {
        rewriteTask?.cancel()
        rewriteTask = nil
        proposal = nil
        isRewriting = false
        error = nil
    }

    private func acceptRewrite() {
        guard let proposal, !isRewriting else { return }
        text = proposal
        self.proposal = nil
        hasAcceptedRewrite = true
        error = nil
        focused = true
    }

    private func close() {
        if proposal != nil {
            showDiscard = true
            return
        }
        guard text != draft.body else {
            dismiss()
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.utf16.count <= 20000
        else {
            error = "Keep a little text in your draft, up to 20,000 characters."
            return
        }
        guard blockInteraction.allowsStoreMutation else { return }
        isSaving = true
        error = nil
        Task {
            do {
                try await onSave(text)
                dismiss()
            } catch {
                self.error =
                    (error as? WritingClient.Failure)?.errorDescription
                    ?? "Your changes couldn't be saved. They are still here. Try closing again to save."
                isSaving = false
            }
        }
    }
}
