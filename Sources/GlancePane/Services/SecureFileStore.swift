import Foundation

enum SecureFileStore {
    static let directoryPermissions = 0o700
    static let filePermissions = 0o600

    static func ensurePrivateDirectory(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
        try fileManager.setAttributes(
            [.posixPermissions: directoryPermissions],
            ofItemAtPath: url.path
        )
    }

    static func write(
        _ data: Data,
        to url: URL,
        secureParent: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        if secureParent {
            try ensurePrivateDirectory(at: url.deletingLastPathComponent(), fileManager: fileManager)
        }
        try data.write(to: url, options: [.atomic])
        try secureFile(at: url, fileManager: fileManager)
    }

    static func copy(
        from source: URL,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        try ensurePrivateDirectory(at: destination.deletingLastPathComponent(), fileManager: fileManager)
        try fileManager.copyItem(at: source, to: destination)
        try secureFile(at: destination, fileManager: fileManager)
    }

    static func secureFile(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: url.path
        )
    }
}
