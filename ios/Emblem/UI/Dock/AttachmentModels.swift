import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import EmblemCore

enum AttachmentFactory {
    static let maxImageDimension: CGFloat = 1200
    static let jpegQuality: CGFloat = 0.8
    static let maxPdfTextChars = 4000
    private static let thumbnailMinimumDimension: CGFloat = 384
    private static let thumbnailMaximumDimension: CGFloat = 1024

    static func image(from data: Data, filename: String) -> Attachment? {
        guard let original = UIImage(data: data) else { return nil }
        let scaled = downscale(original, maxDimension: maxImageDimension)
        guard let jpeg = scaled.jpegData(compressionQuality: jpegQuality) else { return nil }
        return Attachment(
            kind: .image,
            filename: filename,
            thumbnail: thumbnail(scaled),
            payload: jpeg)
    }

    static func pdf(from data: Data, filename: String) -> Attachment {
        let document = PDFDocument(data: data)
        let page = document?.page(at: 0)
        let thumbnail = page.flatMap { page -> UIImage? in
            let bounds = page.bounds(for: .cropBox)
            let shorter = min(bounds.width, bounds.height)
            let longer = max(bounds.width, bounds.height)
            guard shorter > 0, longer > 0 else { return nil }
            let scale = min(thumbnailMinimumDimension / shorter, thumbnailMaximumDimension / longer)
            return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .cropBox)
        }
        let text = String((document?.string ?? "").prefix(maxPdfTextChars))
        return Attachment(
            kind: .pdf,
            filename: filename,
            thumbnail: thumbnail,
            payload: Data(),
            text: text.isEmpty ? nil : text,
            previewData: data)
    }

    static func file(from data: Data, filename: String) -> Attachment {
        let text = String(data: data, encoding: .utf8).map { String($0.prefix(maxPdfTextChars)) }
        return Attachment(
            kind: .file,
            filename: filename,
            thumbnail: nil,
            payload: Data(),
            text: text?.isEmpty == false ? text : nil)
    }

    static func fromFileURL(_ url: URL) -> Attachment? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            return pdf(from: data, filename: name)
        }
        if type?.conforms(to: .image) == true {
            return image(from: data, filename: name)
        }
        return file(from: data, filename: name)
    }

    private static func thumbnail(_ image: UIImage) -> UIImage {
        let shorter = min(image.size.width, image.size.height)
        let longer = max(image.size.width, image.size.height)
        guard shorter > 0, longer > 0 else { return image }
        let scale = min(1, thumbnailMinimumDimension / shorter, thumbnailMaximumDimension / longer)
        return downscale(image, maxDimension: longer * scale)
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
