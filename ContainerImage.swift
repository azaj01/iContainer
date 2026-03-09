import Foundation

struct ContainerImage: Identifiable, Equatable {
    let id: String
    let name: String
    let tag: String?
    let sizeBytes: Int64?
    let sizeText: String?
    let createdAt: String?

    var reference: String {
        Self.reference(name: name, tag: tag)
    }

    var displayName: String {
        let ref = reference
        if !ref.isEmpty {
            return ref
        }
        return name.isEmpty ? id : name
    }

    var displaySize: String {
        if let sizeBytes {
            return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
        if let sizeText, !sizeText.isEmpty {
            return sizeText
        }
        return "-"
    }

    var displayCreated: String {
        createdAt ?? "-"
    }

    static func reference(name: String, tag: String?) -> String {
        guard !name.isEmpty else { return "" }
        if let tag, !tag.isEmpty, tag != "<none>" {
            return "\(name):\(tag)"
        }
        return name
    }
}
