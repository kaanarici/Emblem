import Foundation
import Observation
import SwiftUI
import UIKit
import EmblemCore

extension ConversationStore {
    var showsUploadingAttachment: Bool {
        guard let upload, dockShowsGenerationStop,
              visibleGeneration?.id == upload.runID || upload.runID == nil
        else { return false }
        return !upload.accepted || !upload.minimumElapsed
    }

    func beginUpload(_ outgoing: [Attachment], runID: GenerationRunID?) {
        guard let attachment = outgoing.first(where: { $0.kind == .image }) ?? outgoing.first else {
            upload = nil
            return
        }
        let images = outgoing.filter { $0.kind == .image }.count
        upload = Upload(attachment: attachment, status: images == outgoing.count
            ? (images == 1 ? "Uploading photo…" : "Uploading photos…")
            : (outgoing.count == 1 ? "Uploading file…" : "Uploading files…"), runID: runID)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, self.upload?.attachment.id == attachment.id else { return }
            self.upload?.minimumElapsed = true
        }
    }

    func addAttachment(_ attachment: Attachment) {
        guard attachments.count < 5 else { return }
        attachmentsRevealNewest = !attachments.isEmpty && Date().timeIntervalSince(lastAttachmentAdd) > 1
        lastAttachmentAdd = Date()
        withAnimation(.smooth(duration: 0.3)) { attachments.append(attachment) }
    }

    func removeAttachment(_ attachment: Attachment) {
        generationSession.clearRetryCandidate(attachmentID: attachment.id)
        attachments.removeAll { $0.id == attachment.id }
    }
}
