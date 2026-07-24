import CoreText
import Foundation

enum FontRegistry {
    static func registerBundledFonts() {
        let fileManager = FileManager.default
        let candidateDirectories = [
            Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Resources/Fonts", isDirectory: true)
        ].compactMap { $0 }

        for directory in candidateDirectories where fileManager.fileExists(atPath: directory.path) {
            registerFonts(in: directory)
        }
    }

    private static func registerFonts(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
