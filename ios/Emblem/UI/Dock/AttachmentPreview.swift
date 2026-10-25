import PDFKit
import SwiftUI
import EmblemCore

struct AttachmentFullscreenPreview: View {
    let attachment: Attachment
    let transitionNamespace: Namespace.ID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isImage: Bool { attachment.kind == .image }

    var body: some View {
        if reduceMotion {
            preview
        } else {
            preview.navigationTransition(.zoom(sourceID: attachment.id, in: transitionNamespace))
        }
    }

    private var preview: some View {
        ZStack {
            (isImage ? Color.black : Theme.surface).ignoresSafeArea()
            content
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    CloseGlyph(variant: .navigation)
                        .foregroundStyle(isImage ? Color.white : Theme.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.clear.interactive(), in: .circle)
                .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                .accessibilityLabel("Dismiss preview")
                Text(attachment.filename)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isImage ? Color.white : Theme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(isImage ? Color.black : Theme.surface)
        }
    }

    @ViewBuilder private var content: some View {
        switch attachment.kind {
        case .image:
            if let image = UIImage(data: attachment.payload) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(attachment.filename)
            } else {
                unavailable
            }
        case .pdf:
            if let data = attachment.previewData, let document = PDFDocument(data: data), document.pageCount > 0 {
                AttachmentPDFPreview(document: document)
            } else {
                unavailable
            }
        case .file:
            if let text = attachment.text {
                ScrollView {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            } else {
                unavailable
            }
        }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("No preview available", systemImage: "doc")
        } description: {
            Text(attachment.filename)
        }
    }
}

private struct AttachmentPDFPreview: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "attachment-pdf-preview"
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
