import SwiftUI
import UniformTypeIdentifiers
import EmblemCore

struct ComposerCard: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.accent) private var accent
    @Binding var draft: String
    var focus: FocusState<Bool>.Binding
    var attachmentMorph: Namespace.ID
    let onPhotos: () -> Void
    let onCamera: () -> Void
    let onFiles: () -> Void
    let onSend: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.attachments.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !store.attachments.isEmpty {
                AttachmentStrip(size: 128, morphNamespace: attachmentMorph)
                    .padding(.horizontal, -6)
                    .padding(.top, -8)
                    .padding(.bottom, 12)
            }

            TextField("Ask Emblem", text: $draft, axis: .vertical)
                .accessibilityIdentifier("composer-draft")
                .focused(focus)
                .font(.system(size: 16))
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
                .padding(.bottom, 12)

            HStack(spacing: 0) {
                composerIcon(.image, label: "Photos", action: onPhotos)
                composerIcon(.camera, label: "Camera", action: onCamera)
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                composerIcon(.file, label: "Files", action: onFiles)
                Spacer(minLength: 0)
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSend ? accent.glyph : Theme.onAccent)
                        .frame(width: 36, height: 36)
                        .background {
                            if canSend {
                                AnodizedSurface(shape: Circle())
                            } else {
                                Circle().fill(Color(white: 0.7059))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .disabled(!canSend)
                .accessibilityLabel("Send message")
                .accessibilityIdentifier("arrow.up")
                .animation(.smooth(duration: 0.2), value: canSend)
            }
            .padding(.leading, -10)
            .padding(.trailing, -12)
            .offset(y: -1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 5)
        .frame(minHeight: 90, alignment: .bottom)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func composerIcon(_ symbol: ChromeGlyph.Symbol, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ChromeGlyph(symbol: symbol)
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
        .accessibilityIdentifier("composer-\(label.lowercased())")
    }
}

struct AttachmentStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ConversationStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat
    var contentInset: CGFloat = 0
    var morphNamespace: Namespace.ID? = nil
    var expanded: Binding<Bool>?
    @State private var selectedAttachment: Attachment?
    @Namespace private var attachmentMotion

    private var usesStack: Bool { size <= 60 }

    var body: some View {
        Group {
            if usesStack {
                Button { expanded?.wrappedValue = true } label: {
                    ZStack {
                        ForEach(Array(store.attachments.suffix(4).enumerated()), id: \.element.id) { index, attachment in
                            AttachmentPreviewTile(attachment: attachment, compact: true)
                                .frame(width: size, height: size)
                                .clipShape(.rect(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(.white, lineWidth: 1.5)
                                }
                                .modifier(AttachmentMorph(
                                    id: attachment.id, namespace: morphNamespace,
                                    isSource: store.dockState != .keyboard))
                                .rotationEffect(.degrees(index == min(store.attachments.count, 4) - 1 ? -1 : index.isMultiple(of: 2) ? -4 : 4))
                                .offset(x: CGFloat(index - min(store.attachments.count, 4) + 1) * 2)
                                .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                        }
                    }
                    .frame(width: size + 12, height: size + 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(store.attachments.count) attachments")
                .accessibilityIdentifier("attachment-stack")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(store.attachments) { attachment in
                                attachmentCard(attachment)
                                    .id(attachment.id)
                            }
                        }
                        .padding(.horizontal, contentInset)
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(store.attachmentsRevealNewest ? .trailing : .leading)
                    .onChange(of: store.attachments.last?.id) { _, id in
                        guard let id, store.attachmentsRevealNewest else { return }
                        withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo(id, anchor: .trailing) }
                    }
                }
                .frame(height: size)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: store.attachments)
        .fullScreenCover(item: $selectedAttachment) { attachment in
            AttachmentFullscreenPreview(attachment: attachment, transitionNamespace: attachmentMotion)
        }
    }

    private func attachmentCard(_ attachment: Attachment) -> some View {
        ZStack(alignment: .topTrailing) {
            AttachmentPreviewTile(attachment: attachment)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: 20))
                .modifier(AttachmentMorph(
                    id: attachment.id, namespace: morphNamespace,
                    isSource: store.dockState == .keyboard))
                .matchedTransitionSource(id: attachment.id, in: attachmentMotion)
                .contextMenu {
                    Button { selectedAttachment = attachment } label: {
                        Label("Preview", systemImage: "eye")
                    }
                } preview: {
                    AttachmentPeek(attachment: attachment)
                }
            Button {
                store.removeAttachment(attachment)
                if store.attachments.isEmpty { expanded?.wrappedValue = false }
            } label: {
                CloseGlyph(variant: .navigation)
                    .scaleEffect(0.5)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 20, height: 20)
                    .background {
                        Circle().fill(colorScheme == .dark
                            ? AnyShapeStyle(.regularMaterial)
                            : AnyShapeStyle(Color.white))
                    }
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(attachment.filename)")
            .accessibilityIdentifier("remove-attachment-\(attachment.id)")
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
    }
}

struct UploadingAttachmentChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let attachment: Attachment
    @State private var sweep = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        AttachmentPreviewTile(attachment: attachment, compact: true)
            .frame(width: 48, height: 48)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width * 0.6)
                            .rotationEffect(.degrees(20))
                            .offset(x: sweep ? geometry.size.width * 1.3 : -geometry.size.width * 0.9)
                    }
                    .blendMode(.plusLighter)
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(.white, lineWidth: 1.5) }
            .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
            .accessibilityLabel("Uploading \(attachment.filename)")
            .accessibilityIdentifier("uploading-attachment")
    }
}

private struct AttachmentMorph: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: UUID
    let namespace: Namespace.ID?
    let isSource: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace, !reduceMotion {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            content
        }
    }
}

struct AttachmentMenuPanel: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    let onPhotos: () -> Void
    let onCamera: () -> Void
    let onFiles: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if store.attachments.isEmpty {
                Color.clear.frame(height: 16)
            } else {
                AttachmentStrip(size: 128, contentInset: 24)
                    .padding(.top, 24)
                    .padding(.bottom, 18)
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color(white: 229.0 / 255))
                    .frame(height: 1)
                    .padding(.horizontal, 28)
                Color.clear.frame(height: 10)
            }
            menuRow("Photos", symbol: .image, action: onPhotos)
            menuRow("Camera", symbol: .camera, action: onCamera)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            menuRow("Files", symbol: .file, action: onFiles)
        }
        .padding(.bottom, 13)
        .frame(width: Self.width(for: store.attachments.count))
    }

    static func height(for attachmentCount: Int) -> CGFloat {
        attachmentCount == 0 ? 149 : 314
    }

    @MainActor
    static func width(for attachmentCount: Int) -> CGFloat {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }.first ?? 440
        return attachmentCount > 2 ? screen - 32 : attachmentCount == 2 ? 312 : 250
    }

    private func menuRow(_ title: String, symbol: ChromeGlyph.Symbol, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ChromeGlyph(symbol: symbol)
                Text(title).font(.system(size: 16))
                Spacer()
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 28)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("attachment-menu-\(title.lowercased())")
    }
}

private struct AttachmentPreviewTile: View {
    let attachment: Attachment
    var compact = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Color.white
                if let thumbnail = attachment.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height,
                               alignment: attachment.kind == .image ? .center : .top)
                        .clipped()
                } else {
                    ChromeGlyph(symbol: .file, size: compact ? 18 : 30)
                        .foregroundStyle(Color(white: 107.0 / 255))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if attachment.kind != .image && !compact {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0.5),
                            .init(color: .white, location: 0.82),
                        ],
                        startPoint: .top, endPoint: .bottom)
                    Text(attachment.filename)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 31.0 / 255))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct AttachmentPeek: View {
    let attachment: Attachment

    var body: some View {
        AttachmentPreviewTile(attachment: attachment)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
