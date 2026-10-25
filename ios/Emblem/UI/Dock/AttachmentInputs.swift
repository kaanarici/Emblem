import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct AttachmentInputs: ViewModifier {
    @Environment(ConversationStore.self) private var store

    @Binding var photoItems: [PhotosPickerItem]
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var showFileImporter: Bool
    @State private var photoTasks: [UUID: Task<Void, Never>] = [:]
    @State private var imports = AttachmentImportLifetime()
    @State private var photoContext: AttachmentImportLifetime.Context?
    @State private var fileContext: AttachmentImportLifetime.Context?
    @State private var cameraContext: AttachmentImportLifetime.Context?

    private var remainingSlots: Int { max(0, 5 - store.attachments.count) }

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $photoItems,
                maxSelectionCount: max(1, remainingSlots),
                matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                let picked = items
                photoItems = []
                let id = UUID()
                guard let context = photoContext else { return }
                let previous = Array(photoTasks.values)
                photoTasks[id] = Task { @MainActor in
                    defer { photoTasks[id] = nil }
                    for task in previous { await task.value }
                    guard !Task.isCancelled, imports.accepts(context, in: store) else { return }
                    await ingestPhotos(picked, context: context)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                if let context = cameraContext {
                    CameraPicker { data in
                        ingestImageData(data, filename: "Camera.jpg", context: context)
                    }
                    .ignoresSafeArea()
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .image, .plainText, .text],
                allowsMultipleSelection: true
            ) { result in
                let context = fileContext
                fileContext = nil
                if case .success(let urls) = result, let context {
                    ingestFiles(urls, context: context)
                }
            }
            .onChange(of: showPhotoPicker) { _, presented in
                if presented { photoContext = imports.capture(in: store) }
            }
            .onChange(of: showFileImporter) { _, presented in
                if presented { fileContext = imports.capture(in: store) }
            }
            .onChange(of: showCamera) { _, presented in
                if presented { cameraContext = imports.capture(in: store) }
            }
            .onChange(of: store.currentPage?.id) { cancelPhotoImports() }
            .onChange(of: store.isGenerationActive) { _, active in
                if active { cancelPhotoImports() }
            }
            .onDisappear {
                if !showCamera { cancelPhotoImports() }
            }
    }

    private func ingestPhotos(_ items: [PhotosPickerItem], context: AttachmentImportLifetime.Context) async {
        for item in items.prefix(remainingSlots) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  !Task.isCancelled, imports.accepts(context, in: store),
                  let attachment = AttachmentFactory.image(from: data, filename: "Photo.jpg")
            else { continue }
            store.addAttachment(attachment)
        }
    }

    private func cancelPhotoImports() {
        imports.invalidate()
        photoContext = nil
        fileContext = nil
        cameraContext = nil
        for task in photoTasks.values { task.cancel() }
        photoTasks.removeAll()
    }

    private func ingestImageData(_ data: Data, filename: String, context: AttachmentImportLifetime.Context) {
        guard imports.accepts(context, in: store), let attachment = AttachmentFactory.image(from: data, filename: filename) else { return }
        store.addAttachment(attachment)
    }

    private func ingestFiles(_ urls: [URL], context: AttachmentImportLifetime.Context) {
        for url in urls.prefix(remainingSlots) {
            guard imports.accepts(context, in: store), let attachment = AttachmentFactory.fromFileURL(url) else { continue }
            store.addAttachment(attachment)
        }
    }
}

struct AttachmentImportLifetime {
    struct Context {
        fileprivate let lifetimeID: UUID
        fileprivate let pageID: UUID?
    }

    private var id = UUID()

    @MainActor func capture(in store: ConversationStore) -> Context {
        Context(lifetimeID: id, pageID: store.currentPage?.id)
    }

    @MainActor func accepts(_ context: Context, in store: ConversationStore) -> Bool {
        context.lifetimeID == id && context.pageID == store.currentPage?.id && !store.isGenerationActive
    }

    mutating func invalidate() { id = UUID() }
}
