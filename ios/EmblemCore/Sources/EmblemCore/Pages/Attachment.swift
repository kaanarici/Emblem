import Foundation
#if canImport(UIKit)
import UIKit
public typealias AttachmentThumbnail = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias AttachmentThumbnail = NSImage
#endif

public struct Attachment: Identifiable, Equatable {
    public enum Kind: Equatable { case image, pdf, file }

    public let id = UUID()
    public var kind: Kind
    public var filename: String
    public var thumbnail: AttachmentThumbnail?
    public var payload: Data
    public var text: String?
    public var previewData: Data? = nil

    public static func == (lhs: Attachment, rhs: Attachment) -> Bool { lhs.id == rhs.id }

    public var wireKind: String {
        switch kind {
        case .image: "image"
        case .pdf: "pdf"
        case .file: "file"
        }
    }

    public var dataURL: String {
        kind == .image ? "data:image/jpeg;base64,\(payload.base64EncodedString())" : ""
    }

    public init(kind: Kind, filename: String, thumbnail: AttachmentThumbnail? = nil, payload: Data, text: String? = nil, previewData: Data? = nil) {
        self.kind = kind
        self.filename = filename
        self.thumbnail = thumbnail
        self.payload = payload
        self.text = text
        self.previewData = previewData
    }
}
