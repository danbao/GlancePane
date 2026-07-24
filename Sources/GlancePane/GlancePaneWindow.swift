import AppKit

final class GlancePaneWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func configureForStatusScreen() {
        styleMask = [.borderless]
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        ignoresMouseEvents = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }
}
