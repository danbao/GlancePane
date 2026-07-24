import AppKit

@MainActor
final class DisplayManager {
    func displays() -> [DisplayDescriptor] {
        NSScreen.screens.map { screen in
            DisplayDescriptor(
                id: screen.smartScreenDisplayID,
                name: screen.localizedName,
                frame: screen.frame,
                scaleFactor: screen.backingScaleFactor,
                isMain: screen == NSScreen.main
            )
        }
    }

    func preferredScreen(named displayName: String) -> NSScreen? {
        let targetName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetName.isEmpty else {
            return NSScreen.screens.first { $0 != NSScreen.main } ?? NSScreen.main
        }

        if let exact = NSScreen.screens.first(where: { $0.localizedName == targetName }) {
            return exact
        }

        if let partial = NSScreen.screens.first(where: {
            $0.localizedName.localizedCaseInsensitiveContains(targetName)
        }) {
            return partial
        }

        return NSScreen.screens.first { $0 != NSScreen.main } ?? NSScreen.main
    }

    func descriptor(for screen: NSScreen) -> DisplayDescriptor {
        DisplayDescriptor(
            id: screen.smartScreenDisplayID,
            name: screen.localizedName,
            frame: screen.frame,
            scaleFactor: screen.backingScaleFactor,
            isMain: screen == NSScreen.main
        )
    }
}
